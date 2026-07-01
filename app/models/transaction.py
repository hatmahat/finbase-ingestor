from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal


@dataclass
class Transaction:
    txn_date: datetime
    currency_id: int
    amount: Decimal
    transaction_type_id: int
    wallet_id: int
    fingerprint: str
    category_id: int | None = None
    to_wallet_id: int | None = None
    note: str | None = None
    raw_description: str | None = None
    balance_after: Decimal | None = None
    model_confidence: float | None = None
    import_id: int | None = None
    status: str = "pending"
