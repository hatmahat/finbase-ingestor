import json
import anthropic
from app.core.config import settings
from app.schemas.extracted_transaction import ExtractedTransaction

TOOL_NAME = "record_transactions"

TOOL_SCHEMA = {
    "name": TOOL_NAME,
    "description": "Record all transactions extracted from a bank e-statement.",
    "input_schema": {
        "type": "object",
        "properties": {
            "transactions": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "txn_date":        {"type": "string", "description": "ISO date YYYY-MM-DD"},
                        "amount":          {"type": "number", "description": "Always positive"},
                        "type":            {"type": "string", "enum": ["expense", "income", "transfer", "refund"]},
                        "category":        {"type": "string", "description": "One of the 50 allowed categories"},
                        "wallet":          {"type": "string", "description": "Source wallet / account name"},
                        "to_wallet":       {"type": "string", "description": "Destination wallet (transfers only)"},
                        "note":            {"type": "string"},
                        "raw_description": {"type": "string", "description": "Original bank narration verbatim"},
                        "balance_after":   {"type": "number", "description": "Running balance after this transaction"},
                        "confidence":      {"type": "number", "minimum": 0, "maximum": 1},
                    },
                    "required": ["txn_date", "amount", "type", "wallet", "confidence"],
                },
            }
        },
        "required": ["transactions"],
    },
}

SYSTEM_PROMPT = """You are a financial data extraction assistant.
Extract every transaction from the bank e-statement text provided.
Categorize each transaction using exactly one of these categories:
Bank Fees, Cash, Cellphone, Charity, Cinema, Coffee, Cosmetics, Credit Card,
Doctor, Drinks, Education, Electricity, Electronics, Fashion, Flight, Food,
Games, Gas, Groceries, Gym, Health Insurance, Home Maintenance, Home Supplies,
Hotel, Income, Income Tax, Internet, Investment, Laundry, Life Insurance,
Maintenance, Medication, Miscellaneous, Others, Parking, Public Transport,
Salary, Shopping, Subscriptions, Taxi, Telephone, Tolls, Transfer,
Travel Attractions, Treat, Unknown, Vacation, Vehicle Tax, Water, Zakat.
Set confidence 0–1 based on how certain you are of the category.
Amount is ALWAYS positive — direction is captured by type:
- type=expense: money leaving the account (charges, purchases, fees)
- type=income: real money earned (salary, interest, investment returns, cashback rewards)
- type=refund: money returned for a previous purchase (credits, reversals, cancelled orders)
- type=transfer: money moving between accounts (must have a destination)
On credit card statements, negative amounts are type=refund if they reverse a purchase, or type=income if they are genuine earnings."""


def extract(statement_text: str, wallet_name: str) -> list[ExtractedTransaction]:
    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=16384,
        system=SYSTEM_PROMPT,
        tools=[TOOL_SCHEMA],
        tool_choice={"type": "tool", "name": TOOL_NAME},
        messages=[
            {
                "role": "user",
                "content": f"Wallet / account: {wallet_name}\n\n{statement_text}",
            }
        ],
    )

    if message.stop_reason == "max_tokens":
        raise RuntimeError("Claude response truncated (max_tokens hit) — increase max_tokens or chunk the statement")

    tool_block = next(b for b in message.content if b.type == "tool_use")
    raw = tool_block.input["transactions"]

    return [ExtractedTransaction.model_validate(t) for t in raw]
