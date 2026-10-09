"""Generate deterministic carrier CSV deliveries from Commerce OLTP orders.

Usage: python src/generate_partner_files.py --profile prodlike

The partner CSV files contain only the externally shared order_number, NOT the
PostgreSQL internal order_id. All naive CSV timestamps are in UTC and use
MM/dd/yyyy HH:mm:ss to match the configured Informatica Flat File connection.
"""
from __future__ import annotations

import argparse
import csv
import json
import random
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CARRIERS = ("EGX", "FST", "NIL", "DLV")  # Synthetic courier codes
FIELDNAMES = (
    "shipment_id", "order_number", "carrier_code", "tracking_number",
    "shipment_status", "shipped_at", "delivered_at",
    "shipping_fee_egp", "source_updated_at",
)
ALLOWED_ORDER_STATUSES = {"CREATED", "PAID", "SHIPPED", "DELIVERED", "CANCELLED"}


def parse_oltp_date(value: str) -> datetime:
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError(f"OLTP timestamp lacks timezone: {value}")
    return result.astimezone(timezone.utc)


def timestamp(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%m/%d/%Y %H:%M:%S")


def generate(profile: str, seed: int) -> None:
    source = ROOT / "data" / "generated" / "oltp" / profile / "initial" / "orders.csv"
    target = ROOT / "data" / "landing" / "partners" / profile / "initial"
    if not source.is_file():
        raise SystemExit(f"Missing OLTP orders file: {source}")
    target.mkdir(parents=True, exist_ok=True)
    output_files = {code: target / f"{code.lower()}_shipments_initial.csv" for code in CARRIERS}
    manifest = target / "manifest.json"
    existing = [str(path) for path in (*output_files.values(), manifest) if path.exists()]
    if existing:
        raise SystemExit("Outputs already exist; refusing to overwrite. Files: " + ", ".join(existing))

    rng = random.Random(seed)
    counts = {c: 0 for c in CARRIERS}
    statuses = {"DELIVERED": 0, "IN_TRANSIT": 0, "DELAYED": 0}
    total_orders = 0
    seen_orders = set()
    temps = []
    try:
        with ExitStack() as stack:
            writers = {}
            for code, output in output_files.items():
                temp_path = output.with_name(output.name + ".part")
                if temp_path.exists():
                    raise SystemExit(f"Temporary file exists; inspect before rerunning: {temp_path}")
                temps.append(temp_path)
                handle = stack.enter_context(temp_path.open("w", newline="", encoding="utf-8"))
                writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
                writer.writeheader()
                writers[code] = writer

            with source.open("r", newline="", encoding="utf-8-sig") as file:
                reader = csv.DictReader(file)
                required = {"order_id", "order_number", "order_status", "order_date"}
                if not required.issubset(set(reader.fieldnames or [])):
                    raise ValueError(f"Missing order columns: {required - set(reader.fieldnames or [])}")

                for row in reader:
                    total_orders += 1
                    order_id = int(row["order_id"])
                    number = row["order_number"].strip()
                    status = row["order_status"].strip()
                    if not number or status not in ALLOWED_ORDER_STATUSES:
                        raise ValueError(f"Invalid OLTP order row {total_orders}: {number=} {status=}")
                    if number in seen_orders:
                        raise ValueError(f"Duplicate order_number: {number}")
                    seen_orders.add(number)
                    if status not in {"SHIPPED", "DELIVERED"}:
                        continue

                    carrier = CARRIERS[rng.randrange(len(CARRIERS))]
                    ordered_at = parse_oltp_date(row["order_date"])
                    shipped_at = ordered_at + timedelta(hours=8 + order_id % 24)
                    if status == "DELIVERED":
                        delivered_at = shipped_at + timedelta(days=1 + order_id % 5,
                                                               hours=order_id % 12)
                        shipment_status = "DELIVERED"
                        last_update = delivered_at
                    else:
                        delivered_at = None
                        shipment_status = "DELAYED" if order_id % 17 == 0 else "IN_TRANSIT"
                        last_update = shipped_at + timedelta(days=3) if shipment_status == "DELAYED" else shipped_at

                    writers[carrier].writerow({
                        "shipment_id": f"SHP{order_id:09d}",
                        "order_number": number,
                        "carrier_code": carrier,
                        "tracking_number": f"{carrier}{order_id:010d}",
                        "shipment_status": shipment_status,
                        "shipped_at": timestamp(shipped_at),
                        "delivered_at": timestamp(delivered_at) if delivered_at else "",
                        "shipping_fee_egp": f"{(3500 + (order_id * 17) % 6500) / 100:.2f}",
                        "source_updated_at": timestamp(last_update),
                    })
                    counts[carrier] += 1
                    statuses[shipment_status] += 1

        for carrier, output in output_files.items():
            output.with_name(output.name + ".part").replace(output)
        temps.clear()
        details = {"schema_version": 1, "profile": profile, "seed": seed,
                   "source": str(source.relative_to(ROOT)), "timestamp_timezone": "UTC",
                   "timestamp_format": "MM/dd/yyyy HH:mm:ss", "orders_read": total_orders,
                   "shipments_written": sum(counts.values()), "counts_by_carrier": counts,
                   "counts_by_status": statuses}
        manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
        print(f"Input: {source}")
        print(f"Output: {target}")
        print(f"Orders inspected: {total_orders:,}")
        for carrier, count in counts.items():
            print(f"{output_files[carrier].name}: {count:,} rows")
        print(f"PARTNER FILE GENERATION: COMPLETE ({sum(counts.values()):,} rows)")
    finally:
        for temp in temps:
            temp.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("dev", "prodlike"), default="prodlike")
    parser.add_argument("--seed", type=int, default=20261008)
    args = parser.parse_args()
    generate(args.profile, args.seed)
