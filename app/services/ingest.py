from pathlib import Path
from app.core.database import get_client
from pkg.parser import pdf_reader, claude_extractor, fingerprint as fp
from app.repositories import transaction as txn_repo, wallet as wallet_repo, category as cat_repo, imports as imports_repo
from app.models.transaction import Transaction


def run(pdf_path: str, wallet_name: str, password: str | None = None) -> tuple[int, int]:
    client = get_client()
    wallet_map = wallet_repo.get_name_to_id(client)
    category_map = cat_repo.get_name_to_id(client)

    currency_id = _get_currency_id(client, "IDR")
    wallet_id = wallet_map[wallet_name]
    import_id = imports_repo.get_or_create(client, Path(pdf_path).name, "pdf")

    text = pdf_reader.extract_text(pdf_path, password=password)
    extracted = claude_extractor.extract(text, wallet_name)

    txn_type_map = _get_txn_type_map(client)

    transactions: list[Transaction] = []
    for e in extracted:
        to_wallet_id = wallet_map.get(e.to_wallet) if e.to_wallet else None

        unresolved_transfer = e.type == "transfer" and to_wallet_id is None
        if unresolved_transfer:
            print(f"  [unresolved] transfer downgraded to expense: {e.txn_date} {e.amount} {e.raw_description!r}")

        txn_type = "expense" if unresolved_transfer else e.type
        fingerprint = fp.make(wallet_name, e.txn_date, e.amount, e.raw_description or "")
        category_id = category_map.get(e.category) if (e.category and not unresolved_transfer) else None

        transactions.append(
            Transaction(
                txn_date=e.txn_date,
                currency_id=currency_id,
                amount=e.amount,
                transaction_type_id=txn_type_map[txn_type],
                category_id=category_id,
                wallet_id=wallet_id,
                to_wallet_id=None if unresolved_transfer else to_wallet_id,
                note=e.note,
                raw_description=e.raw_description,
                balance_after=e.balance_after,
                fingerprint=fingerprint,
                model_confidence=e.confidence,
                import_id=import_id,
            )
        )

    return txn_repo.insert_many(client, transactions)


def _get_currency_id(client, code: str) -> int:
    result = client.table("currencies").select("id").eq("name", code).single().execute()
    return result.data["id"]


def _get_txn_type_map(client) -> dict[str, int]:
    result = client.table("transaction_types").select("id, name").execute()
    return {row["name"]: row["id"] for row in result.data}
