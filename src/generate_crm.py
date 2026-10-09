"""Generate reproducible CRM source CSVs linked to the Commerce OLTP source.

Run from a project containing data/generated/oltp/<profile>/initial/{customers,orders}.csv.
Only generates data; it never connects to or modifies MySQL/PostgreSQL.
"""

import argparse
import csv
import hashlib
import json
import random
from collections import Counter, defaultdict
from contextlib import ExitStack
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    "dev": {"customers": 10_000, "accounts": 7_000, "transactions": 35_000,
            "campaigns": 32, "memberships": 60_000, "tickets": 8_000},
    "prodlike": {"customers": 50_000, "accounts": 35_000, "transactions": 175_000,
                 "campaigns": 120, "memberships": 360_000, "tickets": 45_000},
}
COLUMNS = {
    "crm_customers": ["crm_customer_id", "external_customer_code", "signup_at", "customer_segment",
                      "marketing_opt_in", "preferred_channel", "updated_at"],
    "loyalty_accounts": ["loyalty_account_id", "crm_customer_id", "loyalty_tier", "points_balance",
                         "enrolled_at", "updated_at"],
    "loyalty_transactions": ["loyalty_transaction_id", "loyalty_account_id", "transaction_type",
                             "points_delta", "reference_order_number", "occurred_at"],
    "campaigns": ["campaign_id", "campaign_code", "campaign_name", "channel", "campaign_status",
                  "starts_at", "ends_at", "updated_at"],
    "campaign_memberships": ["campaign_id", "crm_customer_id", "engagement_status", "targeted_at",
                             "engaged_at", "updated_at"],
    "support_tickets": ["ticket_id", "ticket_number", "crm_customer_id", "issue_category",
                        "ticket_status", "created_at", "resolved_at", "updated_at"],
}
AS_OF = datetime(2026, 10, 8, 12, 0, 0)


def dt(value):
    """Emit UTC as an unzoned MySQL DATETIME(6) string."""
    return value.strftime("%Y-%m-%d %H:%M:%S.%f")


def hash_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args):
    cfg = PROFILES[args.profile]
    src = ROOT / "data" / "generated" / "oltp" / args.profile / "initial"
    customers_file = src / "customers.csv"
    orders_file = src / "orders.csv"
    manifest_file = src / "manifest.json"
    for path in (customers_file, orders_file, manifest_file):
        if not path.is_file():
            raise SystemExit(f"Missing OLTP input: {path}\nGenerate the OLTP initial batch first.")
    src_manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    if src_manifest.get("profile") != args.profile or src_manifest.get("mode") != "initial":
        raise SystemExit("OLTP manifest profile/mode mismatch")
    if int(src_manifest.get("counts", {}).get("customers", -1)) != cfg["customers"]:
        raise SystemExit("Unexpected customer count in OLTP manifest")

    rng = random.Random(args.seed)
    customers = []
    customer_id_set = set()
    code_set = set()
    with customers_file.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            customer_id = int(row["customer_id"])
            code = row["customer_code"]
            if customer_id in customer_id_set or code in code_set or not code:
                raise SystemExit("Duplicate/empty business key in OLTP customers.csv")
            customer_id_set.add(customer_id)
            code_set.add(code)
            customers.append((customer_id, code))
    if len(customers) != cfg["customers"]:
        raise SystemExit(f"Customers file count mismatch: {len(customers)} != {cfg['customers']}")

    # Linking order references to the *same* OLTP customer, not a random order.
    order_counts = Counter()
    orders_by_customer = defaultdict(list)
    with orders_file.open(newline="", encoding="utf-8") as handle:
        for order in csv.DictReader(handle):
            customer_id = int(order["customer_id"])
            if customer_id not in customer_id_set:
                raise SystemExit(f"Orphan order in OLTP CSV: {order['order_number']}")
            order_counts[customer_id] += 1
            if order["order_status"] in ("PAID", "SHIPPED", "DELIVERED"):
                # Keep only genuine order numbers and their timestamps.
                order_at = datetime.fromisoformat(order["order_date"]).replace(tzinfo=None)
                orders_by_customer[customer_id].append((order["order_number"], order_at))

    rng.shuffle(customers)  # CRM's surrogate identifiers are independent of OLTP IDs.
    target_dir = ROOT / "data" / "generated" / "crm" / args.profile / "initial"
    target_dir.mkdir(parents=True, exist_ok=True)
    counts = {key: 0 for key in COLUMNS}
    with ExitStack() as stack:
        writers = {}
        for table, columns in COLUMNS.items():
            handle = stack.enter_context((target_dir / f"{table}.csv").open("w", newline="", encoding="utf-8"))
            writer = csv.DictWriter(handle, fieldnames=columns)
            writer.writeheader()
            writers[table] = writer

        def emit(table, record):
            writers[table].writerow(record)
            counts[table] += 1

        customer_records = []  # 50K records: small, reused for memberships/tickets.
        eligible_by_channel = defaultdict(list)
        for position, (oltp_id, business_code) in enumerate(customers, start=1):
            crm_id = 100_000 + position
            n_orders = order_counts.get(oltp_id, 0)
            segment = ("VIP" if n_orders >= 9 else
                       "ACTIVE" if n_orders >= 4 else
                       "AT_RISK" if n_orders >= 1 else "NEW")
            marketing_opt_in = rng.random() < 0.78
            channel = rng.choice(("EMAIL", "SMS", "PUSH")) if marketing_opt_in else "NONE"
            signup_at = datetime(2025, 1, 2) + timedelta(days=rng.randint(0, 180))
            emit("crm_customers", {
                "crm_customer_id": crm_id, "external_customer_code": business_code,
                "signup_at": dt(signup_at), "customer_segment": segment,
                "marketing_opt_in": int(marketing_opt_in), "preferred_channel": channel,
                "updated_at": dt(AS_OF),
            })
            customer_records.append((crm_id, oltp_id, channel))
            if marketing_opt_in:
                eligible_by_channel[channel].append(crm_id)

        chosen_accounts = rng.sample(customer_records, cfg["accounts"])
        n_per_account, remainder = divmod(cfg["transactions"], cfg["accounts"])
        tx_id = 0
        for n, (crm_id, oltp_id, _channel) in enumerate(chosen_accounts, start=1):
            account_id = 200_000 + n
            enrolled = datetime(2025, 9, 1) + timedelta(days=rng.randint(0, 90))
            balance = 0
            lifetime_earned = 0
            eligible_orders = orders_by_customer[oltp_id]
            # One account may reference multiple real orders; do not repeat references.
            available_orders = sorted(eligible_orders, key=lambda x: x[1])
            referenced_order_numbers = set()
            for j in range(n_per_account + (1 if n <= remainder else 0)):
                tx_id += 1
                at = datetime(2026, 1, 5) + timedelta(days=j * 51, hours=rng.randrange(24))
                kind = "EARN"
                points = rng.randint(25, 290)
                if j > 0 and j % 3 == 2 and balance >= 50:
                    kind = "REDEEM"
                    points = -rng.randint(10, min(140, balance))
                elif j > 0 and j % 4 == 3:
                    kind = "ADJUST"
                    points = -min(20, balance) if balance >= 20 else 20
                balance += points
                if kind == "EARN":
                    lifetime_earned += points
                order_ref = ""
                if kind == "EARN":
                    for order_number, ordered_at in available_orders:
                        if order_number not in referenced_order_numbers and ordered_at < at:
                            order_ref = order_number
                            referenced_order_numbers.add(order_number)
                            break
                emit("loyalty_transactions", {
                    "loyalty_transaction_id": tx_id, "loyalty_account_id": account_id,
                    "transaction_type": kind, "points_delta": points,
                    "reference_order_number": order_ref, "occurred_at": dt(at),
                })
            tier = ("PLATINUM" if lifetime_earned >= 900 else
                    "GOLD" if lifetime_earned >= 650 else
                    "SILVER" if lifetime_earned >= 350 else "BRONZE")
            emit("loyalty_accounts", {
                "loyalty_account_id": account_id, "crm_customer_id": crm_id,
                "loyalty_tier": tier, "points_balance": balance,
                "enrolled_at": dt(enrolled), "updated_at": dt(AS_OF),
            })

        campaigns = []
        for i in range(1, cfg["campaigns"] + 1):
            campaign_id = 40_000 + i
            channel = ("EMAIL", "SMS", "PUSH")[(i - 1) % 3]
            if i % 10 == 0:
                status = "DRAFT"
                start = datetime(2026, 10, 15) + timedelta(days=i % 5)
            elif i % 7 == 0:
                status = "ACTIVE"
                start = datetime(2026, 10, 1)
            else:
                status = "COMPLETED"
                start = datetime(2025, 11, 1) + timedelta(days=i * 2)
            end = start + timedelta(days=14)
            emit("campaigns", {
                "campaign_id": campaign_id, "campaign_code": f"CMP{i:05d}",
                "campaign_name": f"Commerce Campaign {i:03d}",
                "channel": channel, "campaign_status": status,
                "starts_at": dt(start), "ends_at": dt(end),
                "updated_at": dt(AS_OF),
            })
            if status != "DRAFT":
                campaigns.append((campaign_id, channel, start))

        base_memberships, membership_remainder = divmod(cfg["memberships"], len(campaigns))
        for index, (campaign_id, channel, start) in enumerate(campaigns):
            total_for_campaign = base_memberships + (1 if index < membership_remainder else 0)
            eligible = eligible_by_channel[channel]
            if len(eligible) < total_for_campaign:
                raise SystemExit(f"Not enough opted-in {channel} customers for campaign {campaign_id}")
            for crm_id in rng.sample(eligible, total_for_campaign):
                engagement = rng.choices(("TARGETED", "SENT", "OPENED", "CONVERTED"),
                                         weights=(12, 30, 42, 16), k=1)[0]
                targeted_at = start + timedelta(hours=1)
                engaged_at = ("" if engagement == "TARGETED" else
                              dt(start + timedelta(days=1 if engagement == "SENT" else
                                                            2 if engagement == "OPENED" else 3)))
                emit("campaign_memberships", {
                    "campaign_id": campaign_id, "crm_customer_id": crm_id,
                    "engagement_status": engagement, "targeted_at": dt(targeted_at),
                    "engaged_at": engaged_at,
                    "updated_at": engaged_at or dt(targeted_at),
                })

        categories = ("DELIVERY", "PAYMENT", "RETURN", "PRODUCT", "OTHER")
        ticket_states = ("OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED")
        for ticket_id in range(1, cfg["tickets"] + 1):
            crm_id, _oltp_id, _channel = rng.choice(customer_records)
            status = rng.choices(ticket_states, weights=(8, 12, 43, 37), k=1)[0]
            created = datetime(2025, 10, 8) + timedelta(
                minutes=rng.randrange(360 * 24 * 60)
            )
            resolved = (created + timedelta(hours=rng.randint(2, 72))
                        if status in ("RESOLVED", "CLOSED") else None)
            updated = resolved if resolved else created + timedelta(minutes=rng.randint(1, 180))
            emit("support_tickets", {
                "ticket_id": ticket_id, "ticket_number": f"TKT{ticket_id:09d}",
                "crm_customer_id": crm_id, "issue_category": rng.choice(categories),
                "ticket_status": status, "created_at": dt(created),
                "resolved_at": dt(resolved) if resolved else "", "updated_at": dt(updated),
            })

    expected = {
        "crm_customers": cfg["customers"], "loyalty_accounts": cfg["accounts"],
        "loyalty_transactions": cfg["transactions"], "campaigns": cfg["campaigns"],
        "campaign_memberships": cfg["memberships"], "support_tickets": cfg["tickets"],
    }
    if counts != expected:
        raise SystemExit(f"DATA COUNT MISMATCH: {counts} != {expected}")
    manifest = {
        "schema_version": 1, "source": "mysql_crm", "profile": args.profile,
        "mode": "initial", "seed": args.seed, "counts": counts,
        "oltp_input": {
            "profile": src_manifest["profile"], "mode": src_manifest["mode"],
            "customer_csv_sha256": hash_file(customers_file),
            "orders_csv_sha256": hash_file(orders_file),
        },
        "null_convention": "Empty CSV fields represent SQL NULL for nullable columns",
        "datetime_convention": "UTC represented as MySQL DATETIME(6) without timezone",
    }
    (target_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Output: {target_dir}")
    for name in COLUMNS:
        print(f"{name}.csv: {counts[name]:,} rows")
    print(f"TOTAL: {sum(counts.values()):,} rows | CRM GENERATION: COMPLETE")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, default="prodlike")
    parser.add_argument("--seed", type=int, default=20261008)
    run(parser.parse_args())
