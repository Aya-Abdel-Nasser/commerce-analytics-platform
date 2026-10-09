"""Generate reproducible, order-linked e-commerce application events as JSONL batches.

Input:  data/generated/oltp/<profile>/initial/{orders,order_items}.csv
Output: data/landing/events/<profile>/initial/part-*.jsonl and manifest.json

No Python dependencies outside the standard library. Does not modify databases.
"""

from __future__ import annotations

import argparse
import csv
import json
import random
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    "dev": {"orders": 50_000, "items": 125_000, "customers": 10_000, "products": 1_000},
    "prodlike": {"orders": 200_000, "items": 500_000, "customers": 50_000, "products": 3_000},
}
HISTORY_START = datetime(2025, 10, 8, tzinfo=timezone.utc)
SUCCESS = {"PAID", "SHIPPED", "DELIVERED"}
STATUSES = SUCCESS | {"CREATED", "CANCELLED"}


def utc_iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def validate_headers(reader: csv.DictReader, required: set[str], file: Path) -> None:
    present = set(reader.fieldnames or [])
    if missing := required - present:
        raise ValueError(f"Missing columns in {file}: {sorted(missing)}")


class EventSink:
    def __init__(self, folder: Path, max_rows: int, seed: int):
        self.folder = folder
        self.max_rows = max_rows
        self.seed = seed
        self.handle = None
        self.part = 0
        self.in_part = 0
        self.total = 0
        self.types: Counter[str] = Counter()
        self.late_count = 0
        self.files: list[dict] = []

    def emit(self, event_name: str, timestamp: datetime, session_id: str,
             customer_code: str | None, anonymous_id: str | None,
             product_sku: str | None, order_number: str | None, channel: str) -> None:
        if self.handle is None or self.in_part == self.max_rows:
            self.close_part()
            self.part += 1
            path = self.folder / f"part-{self.part:05d}.jsonl"
            self.handle = path.open("w", encoding="utf-8", newline="\n")
            self.in_part = 0
        event_number = self.total + 1
        # Roughly 1 in 137 messages arrives ~48 hours late.
        is_late = (event_number % 137 == 0)
        received_at = timestamp + (timedelta(hours=48) if is_late else timedelta(seconds=2 + event_number % 21))
        document = {
            "_source_system": "COMMERCE_WEB_APP" if channel == "WEB" else "COMMERCE_MOBILE_APP",
            "_batch": "initial",
            "payload": {
                "event_id": f"EVT{event_number:012d}",
                "event_name": event_name,
                "event_time_utc": utc_iso(timestamp),
                "received_at_utc": utc_iso(received_at),
                "session_id": session_id,
                "customer_code": customer_code,
                "anonymous_id": anonymous_id,
                "product_sku": product_sku,
                "order_number": order_number,
                "channel": channel,
            },
        }
        self.handle.write(json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n")
        self.total += 1
        self.in_part += 1
        self.types[event_name] += 1
        self.late_count += int(is_late)

    def close_part(self) -> None:
        if self.handle is not None:
            self.handle.close()
            self.files.append({"file": f"part-{self.part:05d}.jsonl", "rows": self.in_part})
            self.handle = None


def produce_order_events(orders_path: Path, items_path: Path, cfg: dict, sink: EventSink) -> int:
    order_count = item_count = 0
    with orders_path.open(newline="", encoding="utf-8-sig") as orders_file, \
         items_path.open(newline="", encoding="utf-8-sig") as items_file:
        orders = csv.DictReader(orders_file)
        items = csv.DictReader(items_file)
        validate_headers(orders, {"order_id", "order_number", "customer_id", "order_status", "sales_channel", "order_date"}, orders_path)
        validate_headers(items, {"order_id", "product_id"}, items_path)
        item = next(items, None)
        for order in orders:
            order_count += 1
            oid = int(order["order_id"])
            if oid != order_count:
                raise ValueError(f"Unexpected order_id {oid}; initial source should have sequential IDs")
            if order["order_number"] != f"ORD{oid:09d}":
                raise ValueError(f"Unexpected order_number for order_id={oid}")
            cust_id = int(order["customer_id"])
            if not (1 <= cust_id <= cfg["customers"]):
                raise ValueError(f"Invalid customer_id for order_id={oid}")
            status = order["order_status"]
            if status not in STATUSES:
                raise ValueError(f"Unexpected order_status={status!r} at order_id={oid}")
            channel = order["sales_channel"]
            if channel not in ("WEB", "MOBILE"):
                raise ValueError(f"Unexpected sales_channel={channel!r} at order_id={oid}")
            at = datetime.fromisoformat(order["order_date"].replace("Z", "+00:00"))
            if at.tzinfo is None:
                raise ValueError(f"Timezone missing on order_id={oid}")
            at = at.astimezone(timezone.utc)
            if item is None or int(item["order_id"]) != oid:
                raise ValueError(f"Missing or unordered order items for order_id={oid}")
            product_id = int(item["product_id"])
            if not (1 <= product_id <= cfg["products"]):
                raise ValueError(f"Invalid product_id={product_id} on order_id={oid}")
            sku = f"SKU{product_id:07d}"
            while item is not None and int(item["order_id"]) == oid:
                pid = int(item["product_id"])
                if not (1 <= pid <= cfg["products"]):
                    raise ValueError(f"Invalid product_id={pid} on order_id={oid}")
                item_count += 1
                item = next(items, None)
            # Times reflect a funnel that starts before order creation.
            session = f"SES-ORD-{oid:09d}"
            customer = f"CUST{cust_id:07d}"
            common = (session, customer, None, sku, None, channel)
            sink.emit("session_started", at - timedelta(minutes=30), session, customer, None, None, None, channel)
            sink.emit("product_viewed", at - timedelta(minutes=25), *common)
            sink.emit("added_to_cart", at - timedelta(minutes=15), *common)
            sink.emit("checkout_started", at - timedelta(minutes=5), *common)
            sink.emit("order_submitted", at, session, customer, None, sku, order["order_number"], channel)
            if status == "CANCELLED":
                sink.emit("checkout_cancelled", at + timedelta(minutes=7), session, customer, None, sku, order["order_number"], channel)
            elif status in SUCCESS:
                sink.emit("payment_submitted", at + timedelta(minutes=2), session, customer, None, sku, order["order_number"], channel)
                sink.emit("purchase_completed", at + timedelta(minutes=5), session, customer, None, sku, order["order_number"], channel)
        if item is not None:
            raise ValueError("Unexpected remaining order_items after last order")
    if order_count != cfg["orders"] or item_count != cfg["items"]:
        raise ValueError(f"Input row counts unexpected: orders={order_count}, order_items={item_count}")
    return order_count


def produce_browsing_events(cfg: dict, sink: EventSink, seed: int) -> int:
    rng = random.Random(seed + 99_001)
    sessions = cfg["customers"] * 3
    for i in range(1, sessions + 1):
        channel = rng.choice(("WEB", "MOBILE"))
        at = HISTORY_START + timedelta(minutes=rng.randrange(365 * 24 * 60), seconds=rng.randrange(60))
        customer_id = rng.randint(1, cfg["customers"])
        guest = (i % 4 == 0)
        customer = None if guest else f"CUST{customer_id:07d}"
        anonymous = f"ANON{i:09d}" if guest else None
        sku = f"SKU{rng.randint(1, cfg['products']):07d}"
        session = f"SES-BRW-{i:09d}"
        sink.emit("session_started", at, session, customer, anonymous, None, None, channel)
        sink.emit("product_viewed", at + timedelta(minutes=2), session, customer, anonymous, sku, None, channel)
        if i % 5 == 0:
            sink.emit("added_to_cart", at + timedelta(minutes=4), session, customer, anonymous, sku, None, channel)
    return sessions


def run(profile: str, seed: int, max_part_rows: int) -> None:
    if max_part_rows <= 0:
        raise ValueError("--part-rows must be greater than zero")
    cfg = PROFILES[profile]
    source = ROOT / "data" / "generated" / "oltp" / profile / "initial"
    orders_path = source / "orders.csv"
    items_path = source / "order_items.csv"
    if not orders_path.is_file() or not items_path.is_file():
        raise FileNotFoundError(f"OLTP source CSVs not found in {source}")

    parent = ROOT / "data" / "landing" / "events" / profile
    finished = parent / "initial"
    staging = parent / "initial.inprogress"
    if finished.exists() or staging.exists():
        raise FileExistsError(f"Output already exists ({finished} or {staging}); refusing overwrite")
    parent.mkdir(parents=True, exist_ok=True)
    staging.mkdir()
    sink = EventSink(staging, max_part_rows, seed)
    try:
        order_sessions = produce_order_events(orders_path, items_path, cfg, sink)
        browse_sessions = produce_browsing_events(cfg, sink, seed)
        sink.close_part()
        expected = (cfg["orders"] * 5 + cfg["orders"] // 10 +
                    cfg["orders"] * 7 // 10 * 2 +
                    browse_sessions * 2 + browse_sessions // 5)
        if sink.total != expected:
            raise AssertionError(f"Expected {expected:,} events, generated {sink.total:,}")
        manifest = {
            "schema_version": 1,
            "profile": profile,
            "mode": "initial",
            "seed": seed,
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "order_sessions": order_sessions,
            "browse_only_sessions": browse_sessions,
            "event_records": sink.total,
            "late_arriving_event_records": sink.late_count,
            "event_types": dict(sorted(sink.types.items())),
            "parts": sink.files,
        }
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        staging.rename(finished)
    except BaseException:
        sink.close_part()
        raise
    print(f"Input: {source}")
    print(f"Output: {finished}")
    print(f"Order sessions: {order_sessions:,}")
    print(f"Browse-only sessions: {browse_sessions:,}")
    print(f"JSONL parts: {len(sink.files):,}")
    print(f"Late-arriving messages (simulated): {sink.late_count:,}")
    print(f"APPLICATION EVENT GENERATION: COMPLETE ({sink.total:,} events)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES.keys(), default="prodlike")
    parser.add_argument("--seed", type=int, default=20261008)
    parser.add_argument("--part-rows", type=int, default=200_000)
    args = parser.parse_args()
    run(args.profile, args.seed, args.part_rows)
