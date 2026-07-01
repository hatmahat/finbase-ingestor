import csv
from pathlib import Path
from app.core.database import get_client
from app.schemas.csv_row import CsvRow
from pkg.parser import fingerprint as fp
from app.repositories import transaction as txn_repo, wallet as wallet_repo, category as cat_repo, imports as imports_repo
from app.models.transaction import Transaction

# Categories renamed/split since the CSV was exported — map old name → current DB name.
CATEGORY_MAP: dict[str, str] = {
    "Subscriptions": "Other Subscription",
}


def run(csv_path: str) -> tuple[int, int]:
    client = get_client()
    wallet_map = wallet_repo.get_name_to_id(client)
    category_map = cat_repo.get_name_to_id(client)
    txn_type_map = _get_txn_type_map(client)
    currency_id = _get_currency_id(client, "IDR")

    import_id = imports_repo.get_or_create(client, Path(csv_path).name, "csv")

    transactions: list[Transaction] = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            if not (raw.get("originWallet") or "").strip():
                continue
            row = CsvRow.model_validate(raw)

            wallet_id = wallet_map.get(row.origin_wallet)
            if wallet_id is None:
                print(f"  [skip] unknown wallet: {row.origin_wallet!r}")
                continue

            fingerprint = fp.make(
                row.origin_wallet,
                row.date,
                row.amount,
                row.note or "",
            )
            to_wallet_id = wallet_map.get(row.destination_wallet) if row.destination_wallet else None

            cat_name = CATEGORY_MAP.get(row.category, row.category) if row.category else None
            category_id = category_map.get(cat_name) if cat_name else None

            transactions.append(
                Transaction(
                    txn_date=row.date,
                    currency_id=currency_id,
                    amount=row.amount,
                    transaction_type_id=txn_type_map[row.type.lower()],
                    category_id=category_id,
                    wallet_id=wallet_id,
                    to_wallet_id=to_wallet_id,
                    note=row.note,
                    fingerprint=fingerprint,
                    import_id=import_id,
                    status="approved",
                )
            )

    return txn_repo.insert_many(client, transactions)


def _get_currency_id(client, code: str) -> int:
    result = client.table("currencies").select("id").eq("name", code).single().execute()
    return result.data["id"]


def _get_txn_type_map(client) -> dict[str, int]:
    result = client.table("transaction_types").select("id, name").execute()
    return {row["name"]: row["id"] for row in result.data}
