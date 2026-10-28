import json
import anthropic
from app.core.config import settings
from app.schemas.extracted_transaction import ExtractedTransaction

TOOL_NAME = "record_transactions"

def build_tool_schema(categories: list[str], txn_types: list[str]) -> dict:
    """Tool schema whose enums come from the DB, so new categories/types need no code change."""
    return {
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
                            "type":            {"type": "string", "enum": txn_types},
                            "category":        {"type": "string", "enum": categories},
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
Categorize each transaction using the category enum in the record_transactions tool.
Pick the most specific category that fits.
Set confidence 0–1 based on how certain you are of the category.
Amount is ALWAYS positive — direction is captured by type:
- type=expense: money leaving the account (charges, purchases, fees)
- type=income: money coming in (salary, interest, investment returns, cashback, refunds and reversals of earlier purchases)
- type=transfer: money moving between accounts (must have a destination)
On credit card statements, negative amounts are credits to the card: record them as type=income."""


def extract(statement_text: str, wallet_name: str, categories: list[str], txn_types: list[str]) -> list[ExtractedTransaction]:
    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    # Streaming — a full statement can take minutes to generate, which trips the
    # SDK's HTTP read timeout on a non-streaming request.
    with client.messages.stream(
        model="claude-sonnet-4-6",
        max_tokens=64000,
        system=SYSTEM_PROMPT,
        tools=[build_tool_schema(categories, txn_types)],
        tool_choice={"type": "tool", "name": TOOL_NAME},
        messages=[
            {
                "role": "user",
                "content": f"Wallet / account: {wallet_name}\n\n{statement_text}",
            }
        ],
    ) as stream:
        message = stream.get_final_message()

    if message.stop_reason == "max_tokens":
        raise RuntimeError("Claude response truncated (max_tokens hit) — increase max_tokens or chunk the statement")

    tool_block = next(b for b in message.content if b.type == "tool_use")
    raw = tool_block.input["transactions"]

    return [ExtractedTransaction.model_validate(t) for t in raw]
