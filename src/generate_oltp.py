"""Reproducible, streaming synthetic Commerce OLTP CSV generator."""
import argparse
import csv
import json
import random
from contextlib import ExitStack
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIRST_DAILY_DATE = date(2026, 10, 9)
HISTORY_START = datetime(2025, 10, 8, tzinfo=timezone.utc)
PROFILES = {
    "dev": {"customers": 10_000, "products": 1_000, "orders": 50_000,
            "items": 125_000, "payments": 53_000, "daily_orders": 250,
            "daily_extra_payments": 15},
    "prodlike": {"customers": 50_000, "products": 3_000, "orders": 200_000,
                 "items": 500_000, "payments": 215_000, "daily_orders": 1_000,
                 "daily_extra_payments": 75},
}
COLUMNS = {
    "customers": ["customer_id", "customer_code", "full_name", "email", "city", "created_at", "updated_at"],
    "products": ["product_id", "sku", "product_name", "category", "list_price_egp", "created_at", "updated_at"],
    "orders": ["order_id", "order_number", "customer_id", "order_status", "sales_channel", "order_date", "updated_at"],
    "order_items": ["order_item_id", "order_id", "product_id", "quantity", "unit_price_egp", "discount_amount_egp"],
    "payments": ["payment_id", "transaction_id", "order_id", "payment_method", "payment_status", "amount_egp", "payment_date"],
}
STATUSES = ["CREATED", "CREATED", "PAID", "SHIPPED", "SHIPPED",
            "DELIVERED", "DELIVERED", "DELIVERED", "DELIVERED", "CANCELLED"]


def money(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def product_price_cents(product_id):
    return 12_000 + (product_id * 1_739) % 500_000


def timestamp(value):
    return value.isoformat(timespec="seconds")


def run(args):
    cfg = PROFILES[args.profile]
    day_index = None
    batch_day = None
    if args.mode == "daily":
        if not args.date:
            raise SystemExit("--date YYYY-MM-DD is required for --mode daily")
        try:
            batch_day = date.fromisoformat(args.date)
        except ValueError as exc:
            raise SystemExit(f"Invalid --date: {exc}") from exc
        if batch_day < FIRST_DAILY_DATE:
            raise SystemExit("Daily batches start on 2026-10-09 (after the initial history)")
        day_index = (batch_day - FIRST_DAILY_DATE).days
    elif args.date:
        raise SystemExit("--date is only valid with --mode daily")

    folder = (ROOT / "data" / "generated" / "oltp" / args.profile /
              ("initial" if args.mode == "initial" else f"daily/{batch_day.isoformat()}"))
    folder.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed + (day_index or 0) * 10_007)
    counts = {name: 0 for name in COLUMNS}
    names = COLUMNS if args.mode == "initial" else {key: COLUMNS[key] for key in ("orders", "order_items", "payments")}

    with ExitStack() as stack:
        writers = {}
        for name in names:
            handle = stack.enter_context((folder / f"{name}.csv").open("w", newline="", encoding="utf-8"))
            writer = csv.DictWriter(handle, fieldnames=COLUMNS[name])
            writer.writeheader()
            writers[name] = writer

        def emit(name, row):
            writers[name].writerow(row)
            counts[name] += 1

        if args.mode == "initial":
            first_names = ["Ahmed", "Mona", "Omar", "Sara", "Youssef", "Nour", "Salma", "Karim"]
            last_names = ["Hassan", "Ali", "Ibrahim", "Mahmoud", "Fathy", "Nasser"]
            cities = ["Cairo", "Giza", "Alexandria", "Mansoura", "Tanta", "Aswan"]
            customer_created = timestamp(datetime(2025, 1, 1, tzinfo=timezone.utc))
            product_created = timestamp(datetime(2025, 2, 1, tzinfo=timezone.utc))
            for customer_id in range(1, cfg["customers"] + 1):
                emit("customers", {
                    "customer_id": customer_id,
                    "customer_code": f"CUST{customer_id:07d}",
                    "full_name": f"{rng.choice(first_names)} {rng.choice(last_names)}",
                    "email": f"customer{customer_id:07d}@example.test",
                    "city": rng.choice(cities),
                    "created_at": customer_created, "updated_at": customer_created,
                })
            categories = ["Electronics", "Fashion", "Home", "Beauty", "Sports"]
            for product_id in range(1, cfg["products"] + 1):
                emit("products", {
                    "product_id": product_id, "sku": f"SKU{product_id:07d}",
                    "product_name": f"Product {product_id:05d}",
                    "category": categories[(product_id - 1) % len(categories)],
                    "list_price_egp": money(product_price_cents(product_id)),
                    "created_at": product_created, "updated_at": product_created,
                })
            order_count = cfg["orders"]
            order_start = item_start = payment_start = 0
            extra_count = cfg["payments"] - cfg["orders"]
        else:
            order_count = cfg["daily_orders"]
            order_start = cfg["orders"] + day_index * cfg["daily_orders"]
            item_start = cfg["items"] + day_index * (3 * cfg["daily_orders"])
            payment_start = cfg["payments"] + day_index * (2 * cfg["daily_orders"])
            extra_count = cfg["daily_extra_payments"]

        # Exactly seven in every ten orders have successful payments.
        eligible_count = (order_count // 10) * 7
        success_index = 0
        initial_item_index = initial_payment_index = 0
        for position in range(1, order_count + 1):
            order_id = order_start + position
            status = STATUSES[(position - 1) % 10]
            if args.mode == "initial":
                order_at = HISTORY_START + timedelta(minutes=(position * 2_789) % (365 * 24 * 60))
            else:
                order_at = datetime(batch_day.year, batch_day.month, batch_day.day,
                                    tzinfo=timezone.utc) + timedelta(minutes=(position * 997) % 1440)
            order_iso = timestamp(order_at)
            emit("orders", {
                "order_id": order_id,
                "order_number": f"ORD{order_id:09d}",
                "customer_id": rng.randint(1, cfg["customers"]),
                "order_status": status,
                "sales_channel": rng.choice(["WEB", "MOBILE"]),
                "order_date": order_iso,
                "updated_at": timestamp(order_at + timedelta(hours=1)),
            })
            total_cents = 0
            for item_no in range(1, 3 + (position % 2)):
                product_id = rng.randint(1, cfg["products"])
                price_cents = product_price_cents(product_id)
                quantity = rng.randint(1, 3)
                discount_cents = 500 if (order_id + item_no) % 13 == 0 else 0
                total_cents += price_cents * quantity - discount_cents
                if args.mode == "initial":
                    initial_item_index += 1
                    item_id = initial_item_index
                else:
                    # Reserve 3 IDs per daily order for collision-free replays.
                    item_id = item_start + (position - 1) * 3 + item_no
                emit("order_items", {
                    "order_item_id": item_id, "order_id": order_id,
                    "product_id": product_id, "quantity": quantity,
                    "unit_price_egp": money(price_cents),
                    "discount_amount_egp": money(discount_cents),
                })
            payment_status = ("PENDING" if status == "CREATED" else
                              "FAILED" if status == "CANCELLED" else "SUCCESS")
            retry = False
            if payment_status == "SUCCESS":
                retry = (success_index * 73) % eligible_count < extra_count
                success_index += 1

            payment_states = (["FAILED", "SUCCESS"] if retry else [payment_status])
            for attempt_no, state in enumerate(payment_states, 1):
                if args.mode == "initial":
                    initial_payment_index += 1
                    payment_id = initial_payment_index
                else:
                    payment_id = payment_start + (position - 1) * 2 + attempt_no
                payment_time = "" if state == "PENDING" else timestamp(order_at + timedelta(minutes=attempt_no * 5))
                emit("payments", {
                    "payment_id": payment_id,
                    "transaction_id": f"TXN{payment_id:010d}",
                    "order_id": order_id,
                    "payment_method": rng.choice(["CARD", "WALLET"]),
                    "payment_status": state,
                    "amount_egp": money(total_cents),
                    "payment_date": payment_time,
                })

    if args.mode == "initial":
        for field, target in (("customers", "customers"), ("products", "products"),
                              ("orders", "orders"), ("order_items", "items"),
                              ("payments", "payments")):
            assert counts[field] == cfg[target], (field, counts[field], cfg[target])

    manifest = {"schema_version": 1, "profile": args.profile, "mode": args.mode,
                "date": args.date, "seed": args.seed, "counts": counts}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Output: {folder}")
    for name in names:
        print(f"{name}.csv: {counts[name]:,} rows")
    print(f"TOTAL: {sum(counts.values()):,} rows | GENERATION: COMPLETE")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, default="prodlike")
    parser.add_argument("--mode", choices=("initial", "daily"), default="initial")
    parser.add_argument("--date", help="Daily batch date as YYYY-MM-DD")
    parser.add_argument("--seed", type=int, default=20261008)
    run(parser.parse_args())
