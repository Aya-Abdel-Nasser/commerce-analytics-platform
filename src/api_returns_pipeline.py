"""Commerce Analytics Platform — local mock Returns REST API and HTTP extractor.

DEV DEMO:
  python src/api_returns_pipeline.py --profile prodlike --mode demo

This intentionally simulates an external REST service. It uses a real local
HTTP server, bearer authentication, JSON pagination, retrying client, and writes
raw JSONL for later Bronze ingestion. It does NOT call a real external API.
No third-party packages are required.
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import secrets
import threading
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
AS_OF = datetime(2026, 10, 8, tzinfo=timezone.utc)
REASONS = ("DAMAGED_ITEM", "WRONG_ITEM", "QUALITY_ISSUE", "NOT_AS_DESCRIBED", "CHANGED_MIND")
STATES = ("REQUESTED", "APPROVED", "REJECTED", "REFUNDED")
API_PATH = "/api/v1/returns"


def read_orders(profile: str, seed: int) -> list[dict]:
    """Select historical delivered orders for synthetic third-party returns."""
    folder = ROOT / "data" / "generated" / "oltp" / profile / "initial"
    orders_file, items_file = folder / "orders.csv", folder / "order_items.csv"
    if not orders_file.is_file() or not items_file.is_file():
        raise FileNotFoundError(f"Expected OLTP orders.csv and order_items.csv in {folder}")

    rng = random.Random(seed)
    selected = {}
    read_count = 0
    with orders_file.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        required = {"order_id", "order_number", "order_status", "order_date"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f"Missing orders.csv columns: {sorted(required - set(reader.fieldnames or []))}")
        for order in reader:
            read_count += 1
            if order["order_status"] != "DELIVERED":
                continue
            ordered_at = datetime.fromisoformat(order["order_date"].replace("Z", "+00:00"))
            if ordered_at.tzinfo is None:
                raise ValueError("order_date must include a timezone")
            if ordered_at.astimezone(timezone.utc) > AS_OF - timedelta(days=30):
                continue
            if rng.random() >= 0.30:
                continue
            oid = int(order["order_id"])
            selected[oid] = (order["order_number"], ordered_at.astimezone(timezone.utc))

    # Find item totals only for orders included in the external returns service.
    totals = {oid: Decimal("0.00") for oid in selected}
    with items_file.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        required = {"order_id", "quantity", "unit_price_egp", "discount_amount_egp"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f"Missing order_items.csv columns: {sorted(required - set(reader.fieldnames or []))}")
        for item in reader:
            oid = int(item["order_id"])
            if oid in totals:
                totals[oid] += (Decimal(item["unit_price_egp"]) *
                                int(item["quantity"]) - Decimal(item["discount_amount_egp"]))

    returns = []
    for oid, (number, ordered_at) in sorted(selected.items()):
        total = totals[oid]
        if total <= 0:
            raise ValueError(f"Invalid order total for {number}")
        requested = ordered_at + timedelta(days=5 + oid % 12)
        status = STATES[oid % len(STATES)]
        updated = requested if status == "REQUESTED" else requested + timedelta(days=1 + oid % 4)
        fraction = Decimal("0.50") + Decimal(oid % 6) * Decimal("0.10")
        refund = (total * fraction).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        if requested > AS_OF or updated > AS_OF:
            raise ValueError(f"Return date exceeds snapshot date for {number}")
        returns.append({
            "return_id": f"RET{oid:09d}",
            "order_number": number,
            "requested_at": requested.isoformat(timespec="seconds"),
            "reason_code": REASONS[oid % len(REASONS)],
            "return_status": status,
            "requested_refund_egp": str(refund),
            "updated_at": updated.isoformat(timespec="seconds"),
        })
    print(f"OLTP orders inspected: {read_count:,}")
    print(f"Eligible API return records: {len(returns):,}")
    return returns


class ReturnsAPIHandler(BaseHTTPRequestHandler):
    """Handler is configured with .records and .token on a subclass."""
    records: list[dict] = []
    token: str = ""

    def log_message(self, format, *args):  # noqa: A002
        return  # Avoid per-page noise and do not print tokens.

    def send_json(self, status, payload):
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != API_PATH:
            self.send_json(404, {"error": "not_found"})
            return
        if self.headers.get("Authorization") != f"Bearer {self.token}":
            self.send_json(401, {"error": "unauthorized"})
            return
        query = parse_qs(parsed.query)
        try:
            page = int(query.get("page", ["1"])[0])
            size = int(query.get("page_size", ["500"])[0])
        except ValueError:
            self.send_json(400, {"error": "invalid_pagination"})
            return
        if page < 1 or not 1 <= size <= 1000:
            self.send_json(400, {"error": "invalid_pagination"})
            return
        start = (page - 1) * size
        total = len(self.records)
        total_pages = (total + size - 1) // size
        self.send_json(200, {
            "data": self.records[start:start + size],
            "meta": {"page": page, "page_size": size, "total": total,
                     "total_pages": total_pages,
                     "next_page": page + 1 if page < total_pages else None},
        })


def http_page(base_url: str, token: str, page: int, size: int) -> dict:
    url = f"{base_url}{API_PATH}?page={page}&page_size={size}"
    for attempt in range(4):
        try:
            request = Request(url, headers={"Authorization": f"Bearer {token}",
                                            "Accept": "application/json"})
            with urlopen(request, timeout=15) as response:
                if response.headers.get_content_type() != "application/json":
                    raise ValueError("API did not return JSON")
                return json.load(response)
        except HTTPError as exc:
            if exc.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise
        except (URLError, TimeoutError) as exc:
            if attempt == 3:
                raise RuntimeError(f"API request failed: {exc}") from exc
        time.sleep(0.3 * (2 ** attempt))
    raise RuntimeError("HTTP retries exhausted")


def extract(profile: str, base_url: str, token: str, page_size: int) -> int:
    target = ROOT / "data" / "landing" / "api" / profile / "initial"
    target.mkdir(parents=True, exist_ok=True)
    output = target / "returns_initial.jsonl"
    manifest = target / "manifest.json"
    tmp = target / "returns_initial.jsonl.part"
    if output.exists() or manifest.exists() or tmp.exists():
        raise FileExistsError(f"API landing output already exists in {target}; refusing overwrite")

    seen = set()
    count = 0
    expected_total = None
    page = 1
    ingestion_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    try:
        with tmp.open("w", encoding="utf-8", newline="\n") as stream:
            while True:
                response = http_page(base_url, token, page, page_size)
                data = response.get("data")
                meta = response.get("meta")
                if not isinstance(data, list) or not isinstance(meta, dict):
                    raise ValueError("Unexpected API response structure")
                if meta.get("page") != page or meta.get("page_size") != page_size:
                    raise ValueError(f"Unexpected API pagination metadata at page {page}")
                if expected_total is None:
                    expected_total = meta.get("total")
                    if not isinstance(expected_total, int) or expected_total < 0:
                        raise ValueError("Invalid API total")
                elif meta.get("total") != expected_total:
                    raise ValueError("API total changed during extraction")
                for record in data:
                    if not isinstance(record, dict) or not record.get("return_id") or not record.get("order_number"):
                        raise ValueError("Invalid return record")
                    if record["return_id"] in seen:
                        raise ValueError(f"Duplicate return_id: {record['return_id']}")
                    seen.add(record["return_id"])
                    raw = {"_source_system": "MOCK_RETURNS_API", "_ingested_at_utc": ingestion_at,
                           "_source_endpoint": API_PATH, "payload": record}
                    stream.write(json.dumps(raw, ensure_ascii=False, separators=(",", ":")) + "\n")
                    count += 1
                print(f"API page {page}: {len(data):,} records | received {count:,}")
                following = meta.get("next_page")
                if following is None:
                    break
                if following != page + 1:
                    raise ValueError("Invalid next_page link")
                if not data:
                    raise ValueError("Unexpected empty intermediate API page")
                page = following
        if count != expected_total:
            raise ValueError(f"Pagination incomplete: extracted {count}, expected {expected_total}")
        tmp.replace(output)
        summary = {"schema_version": 1, "profile": profile, "source_system": "MOCK_RETURNS_API",
                   "endpoint": API_PATH, "page_size": page_size, "pages": page,
                   "rows_extracted": count, "ingested_at_utc": ingestion_at,
                   "data_file": output.name, "demo_note": "Local simulated REST API, not a live external provider"}
        manifest.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"Output: {output}")
        print(f"RETURNS API EXTRACTION: COMPLETE ({count:,} records, {page} pages)")
        return count
    finally:
        tmp.unlink(missing_ok=True)


def demo(profile: str, seed: int, page_size: int) -> None:
    records = read_orders(profile, seed)
    token = secrets.token_urlsafe(24)  # Temporary in-memory bearer token; never stored.
    handler = type("DemoReturnsHandler", (ReturnsAPIHandler,), {"records": records, "token": token})
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        port = server.server_address[1]
        print(f"Mock REST API ready on localhost (port {port}; HTTP + Bearer auth)")
        extract(profile, f"http://127.0.0.1:{port}", token, page_size)
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("dev", "prodlike"), default="prodlike")
    parser.add_argument("--mode", choices=("demo", "extract"), default="demo")
    parser.add_argument("--seed", type=int, default=20261008)
    parser.add_argument("--page-size", type=int, default=500)
    parser.add_argument("--base-url", help="API base URL (only with --mode extract)")
    args = parser.parse_args()
    if not 1 <= args.page_size <= 1000:
        parser.error("--page-size must be between 1 and 1000")
    try:
        if args.mode == "demo":
            if args.base_url:
                parser.error("--base-url is only valid with --mode extract")
            demo(args.profile, args.seed, args.page_size)
        else:
            import os
            if not args.base_url or not os.environ.get("RETURNS_API_TOKEN"):
                parser.error("--mode extract requires --base-url and RETURNS_API_TOKEN environment variable")
            extract(args.profile, args.base_url.rstrip("/"), os.environ["RETURNS_API_TOKEN"], args.page_size)
    except (FileNotFoundError, FileExistsError, ValueError, OSError) as exc:
        parser.exit(1, f"ERROR: {exc}\n")
