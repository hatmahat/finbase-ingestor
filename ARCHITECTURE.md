# Architecture

**finbase** is a personal finance ledger built around one core workflow: **upload a bank e-statement PDF → Claude extracts and categorizes transactions → human approves each one in the frontend.**

This document describes how the system is structured to support that workflow.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Frontend                            │
│              (Next.js + Supabase Client)                    │
│                                                             │
│  • Review Queue (approve/reject pending transactions)       │
│  • Analytics Dashboard (savings rate, spending)             │
│  • Wallet & Subscription Management                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Direct CRUD via supabase-js
                       │ (Auth + Row Level Security)
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                      Supabase Postgres                      │
│                                                             │
│  • transactions (fingerprint UNIQUE for dedup)              │
│  • wallets, categories, securities, holdings                │
│  • Triggers: set_updated_at, check_transfer_shape           │
└─────────────────────────────────────────────────────────────┘
                       ▲
                       │ Repository layer (supabase-py)
                       │
┌──────────────────────┴──────────────────────────────────────┐
│                   Python Ingestion CLI                      │
│                      (local only)                           │
│                                                             │
│  PDF → pdfplumber/pytesseract → Claude API → fingerprint    │
│                      → Supabase insert                      │
└─────────────────────────────────────────────────────────────┘
```

**Key design decision:** Frontend talks directly to Supabase for all normal CRUD. Python backend exists **only** for ingestion: it holds the Anthropic API key, parses PDFs, and calls Claude for extraction. This eliminates the need for a traditional API server.

---

## Data Flow: PDF Ingestion

```
1. User runs: make ingest f=statement.pdf w="BCA Leisure"

2. app/main.py → services/ingest_service.py orchestrates:

┌──────────────────────────────────────────────────────────┐
│ PDF Parsing (pkg/parser/pdf_reader.py)                   │
│ • pikepdf: decrypt if password-protected                 │
│ • pdfplumber: extract text                               │
│ • pytesseract: OCR fallback for scanned statements       │
└──────────────────┬───────────────────────────────────────┘
                   │ raw text
                   ▼
┌──────────────────────────────────────────────────────────┐
│ Claude Extraction (pkg/parser/claude_extractor.py)       │
│ • Anthropic SDK with forced tool-use                     │
│ • Tool: record_transactions                              │
│ • Returns: ExtractedTransaction[] (typed JSON)           │
│ • Model: claude-sonnet-4-6 (swap to haiku for cost)      │
└──────────────────┬───────────────────────────────────────┘
                   │ structured transactions
                   ▼
┌──────────────────────────────────────────────────────────┐
│ Fingerprinting (pkg/parser/fingerprint.py)               │
│ • sha256(account | date | amount | norm_description)     │
│ • Dedup key: re-uploading same statement = no-op         │
└──────────────────┬───────────────────────────────────────┘
                   │ transactions + fingerprints
                   ▼
┌──────────────────────────────────────────────────────────┐
│ Repository Layer (app/repositories/)                     │
│ • get_or_create wallet, category, currency               │
│ • upsert transactions (ON CONFLICT fingerprint)          │
│ • Insert as status='pending', model_confidence 0-1       │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
            Supabase Postgres
```

**Critical invariants:**
- Every transaction inserts as `status='pending'` — never auto-approve
- Fingerprint collision → silent no-op (idempotent re-uploads)
- Claude extraction uses **forced tool-use**, not agent flow (predictable, single-call structured output)

---

## Data Flow: CSV Import (One-Time Migration)

```
make import-csv → services/csv_import_service.py

1. Read data/imports/transactions-from-*.csv (809 rows from Simple app)
2. Parse into CsvRow schema (Pydantic)
3. Map Simple's categories → finbase 50-category taxonomy
4. get_or_create wallets, categories
5. Generate fingerprint per row
6. Bulk upsert as status='approved' (historical data, pre-approved)
```

This flow runs **once** to seed historical data. After that, only PDF ingestion is used.

---

## Database Schema Design

### Normalization Strategy

**Lookup tables** instead of raw strings:
- `wallet_types` (bank, cash, credit_card, e_wallet, investment, restricted)
- `wallet_institutions` (BCA, Mandiri, BRI, Nanovest, GoTrade)
- `currencies` (IDR, SGD, JPY, USD)
- `transaction_types` (expense, income, transfer)
- `category_groups` (grouped categories for dashboard)

**Core tables:**
- `transactions` — the ledger. Every row is one financial event.
- `wallets` — accounts (references wallet_types, institutions, currencies)
- `categories` — 50-category taxonomy (references category_groups)
- `securities` — ticker, name, asset_class (stock, etf, crypto)
- `holdings` — current share count per security

### Key Constraints

```sql
-- Dedup via fingerprint
ALTER TABLE transactions ADD CONSTRAINT transactions_fingerprint_key
  UNIQUE (fingerprint);

-- Transfer validation (trigger)
-- Enforces: transfers must have to_wallet_id; expense/income must not
CREATE TRIGGER check_transfer_shape_trigger
  BEFORE INSERT OR UPDATE ON transactions ...
```

### Auto-Maintained Fields

```sql
-- updated_at auto-stamp on every table
CREATE TRIGGER set_updated_at_trigger
  BEFORE UPDATE ON <table>
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

---

## Python Backend Structure

```
app/
├── main.py                    # CLI: ingest, ingest-dir, import-csv
├── core/
│   ├── config.py              # Settings (env vars via pydantic-settings)
│   └── database.py            # Supabase client singleton
├── models/                    # Dataclasses mirroring DB tables
│   ├── transaction.py
│   ├── wallet.py
│   └── category.py
├── schemas/                   # Pydantic v2 validation
│   ├── extracted_transaction.py
│   └── csv_row.py
├── repositories/              # Supabase CRUD + dedup logic
│   ├── transactions.py
│   ├── wallets.py
│   └── categories.py
└── services/                  # Orchestration
    ├── ingest_service.py      # PDF → Claude → DB pipeline
    └── csv_import_service.py  # One-time CSV migration

pkg/
└── parser/
    ├── pdf_reader.py          # PDF decryption + text extraction + OCR
    ├── claude_extractor.py    # Anthropic API structured extraction
    └── fingerprint.py         # sha256 dedup key generator
```

**Separation of concerns:**
- `pkg/parser/` — external integrations (PDF, Claude, crypto)
- `app/repositories/` — database boundary (only layer that touches Supabase)
- `app/services/` — orchestration (compose parsers + repositories)
- `app/models/` — domain objects (match DB schema)
- `app/schemas/` — I/O validation (Pydantic)

---

## Claude Extraction Design

### Forced Tool-Use (Not Agent Flow)

```python
# pkg/parser/claude_extractor.py

response = anthropic.messages.create(
    model="claude-sonnet-4-6",
    messages=[{"role": "user", "content": pdf_text}],
    tools=[{
        "name": "record_transactions",
        "description": "Extract all transactions from the statement",
        "input_schema": {
            "type": "object",
            "properties": {
                "transactions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "date": {"type": "string"},
                            "amount": {"type": "number"},
                            "description": {"type": "string"},
                            "category": {"enum": [...50 categories...]},
                            "type": {"enum": ["expense", "income", "transfer"]},
                            ...
                        }
                    }
                }
            }
        }
    }],
    tool_choice={"type": "tool", "name": "record_transactions"}
)
```

**Why this approach:**
- **Guaranteed structure** — response is always valid JSON matching schema
- **Single round-trip** — no agent loop, no back-and-forth
- **Predictable cost** — one call per statement (vs. multi-turn agent)
- **Confidence scoring** — Claude assigns 0–1 confidence per transaction

### Category Taxonomy (50 — Fixed)

Claude must map to this exact set:

```
Bank Fees, Cash, Cellphone, Charity, Cinema, Coffee, Cosmetics, Credit Card,
Doctor, Drinks, Education, Electricity, Electronics, Fashion, Flight, Food,
Games, Gas, Groceries, Gym, Health Insurance, Home Maintenance, Home Supplies,
Hotel, Income, Income Tax, Internet, Investment, Laundry, Life Insurance,
Maintenance, Medication, Miscellaneous, Others, Parking, Public Transport,
Salary, Shopping, Subscriptions, Taxi, Telephone, Tolls, Transfer,
Travel Attractions, Treat, Unknown, Vacation, Vehicle Tax, Water, Zakat
```

Passed to Claude as an `enum` constraint in the tool schema → forces valid categorization.

---

## Deduplication Strategy

### Fingerprint Generation

```python
# pkg/parser/fingerprint.py

def generate_fingerprint(
    account: str,
    date: str,
    amount: float,
    description: str
) -> str:
    normalized_desc = description.strip().lower()
    payload = f"{account}|{date}|{amount}|{normalized_desc}"
    return hashlib.sha256(payload.encode()).hexdigest()
```

### Database Enforcement

```sql
ALTER TABLE transactions ADD CONSTRAINT transactions_fingerprint_key
  UNIQUE (fingerprint);

-- Upsert pattern in repository
INSERT INTO transactions (..., fingerprint)
VALUES (..., $fingerprint)
ON CONFLICT (fingerprint) DO NOTHING;
```

**Result:** Re-uploading the same PDF multiple times is idempotent — duplicate transactions are silently skipped.

---

## Frontend Architecture (Separate Repo)

```
finbase-frontend/ (Next.js)
├── app/
│   ├── dashboard/             # Analytics: savings rate, spending charts
│   ├── review/                # Pending transactions approval queue
│   ├── wallets/               # Wallet CRUD
│   └── subscriptions/         # Subscription tracking
├── components/
│   └── ui/                    # shadcn/ui primitives
├── lib/
│   └── supabase.ts            # Supabase client (supabase-js)
└── hooks/
    └── use-transactions.ts    # SWR/TanStack Query for live data
```

**Key pattern:** Frontend reads/writes Supabase **directly** via `supabase-js`. No custom API server needed. Row Level Security (RLS) enforces auth.

---

## Deployment Architecture

### Frontend
- **Host:** Vercel
- **Auth:** Supabase Auth (handled via supabase-js)
- **Security:** Environment variables for Supabase URL + anon key

### Database
- **Host:** Supabase (free tier)
- **Migrations:** Applied via `supabase db push` (Supabase CLI)
- **Security:** Row Level Security policies; API keys rotatable

### Python Ingestion
- **Local:** `make ingest` runs on laptop (personal tool)
- **Future hosting (if needed):** Cloud Run / Railway / Render
  - **NOT Vercel** — PDF/OCR libs (pdfplumber, pytesseract) are native binaries incompatible with serverless
  - Scale-to-zero container works fine (ingestion is rare, ~1x/month)

**Critical:** Anthropic API key lives **only** in Python backend `.env` — never exposed to frontend.

---

## Security Model

### Secrets Management
- `.env` (gitignored) contains:
  - `SUPABASE_URL`, `SUPABASE_KEY` (service role key for backend)
  - `ANTHROPIC_API_KEY`
- Frontend uses **anon key** (safe to expose) + RLS policies

### Row Level Security (RLS)
```sql
-- Example: Users can only see their own transactions
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own transactions"
ON transactions FOR SELECT
USING (auth.uid() = user_id);
```

### Dedup Fingerprint as Security Layer
- Prevents accidental duplicate charges from being inserted
- Acts as data integrity check (same transaction = same fingerprint)

---

## Cost Model

**Monthly burn: ~$0 except a few cents of Claude API per statement**

| Service | Plan | Cost | Usage |
|---------|------|------|-------|
| Supabase | Free tier | $0 | Data: KB vs 500MB cap; pauses after 7d idle but preserves data |
| Vercel | Hobby | $0 | Personal/non-commercial use |
| Claude API | Pay-as-you-go | ~$0.05/statement | 1 PDF/month × sonnet-4-6 (~5K tokens) |

**Cost controls:**
- Swap `claude-sonnet-4-6` → `claude-haiku-4-5-20251001` to cut API cost by ~10x
- Supabase auto-pauses when idle → wake on first query (acceptable for monthly use)

---

## Tradeoffs & Constraints

### Why No Real-Time Backend?
**Decision:** Frontend → Supabase direct (no Express/FastAPI/etc.)

**Rationale:**
- Ingestion is rare (~1x/month) → doesn't justify always-on server
- Supabase handles auth, RLS, CRUD → backend would just be a pass-through
- Python backend exists **only** for: Anthropic API (needs secret key), PDF parsing (native libs)

**Tradeoff:** Can't run custom business logic on writes. Acceptable because domain is simple (ledger + approval workflow).

### Why Structured Extraction (Not Agent)?
**Decision:** Forced `record_transactions` tool-use, not multi-turn agent

**Rationale:**
- **Predictable cost** — 1 call/statement vs. unknown agent rounds
- **Guaranteed valid output** — schema enforcement via tool input_schema
- **No hallucination risk** — single extraction pass, human approval gate after

**Tradeoff:** Can't iteratively refine extraction. But ingestion errors are caught in review queue (pending → approve/reject).

### Why 50-Category Taxonomy (Not Free-Text)?
**Decision:** Fixed enum of 50 categories, passed to Claude as constraint

**Rationale:**
- **Consistent aggregation** — dashboard charts require stable category keys
- **Migration from Simple app** — CSV import maps Simple's categories → finbase taxonomy
- **Claude reliability** — enum forces valid categorization (vs. free-text typos)

**Tradeoff:** Can't dynamically add categories without migration. Acceptable for personal tool with stable spending patterns.

---

## Monitoring & Observability

### Logs
- **Ingestion:** Python CLI outputs to stdout (structured logging via `loguru` possible)
- **Frontend:** Vercel logs + Supabase logs (query performance, auth events)

### Metrics
- **Confidence scores:** Track `model_confidence` distribution in `transactions` table
- **Review queue depth:** `SELECT COUNT(*) FROM transactions WHERE status='pending'`
- **Dedup hit rate:** Count `ON CONFLICT` no-ops vs. inserts

### Alerting
- **Supabase:** Email alerts if free tier quota nears limit
- **Anthropic API:** Monitor spend via Anthropic Console (should stay under $1/month)

---

## Future Considerations (Phase 2)

### MCP Server (Learning Exercise)
**Scope:** Read-only ledger query server for Claude Desktop

```
Tools:
- query_spending(start_date, end_date, category)
- list_pending_transactions()
- get_savings_rate(month)
```

**Rationale:** Additive learning project; doesn't replace ingestion flow.

### Multi-Currency Support
**Current:** `currencies` table exists but conversion not implemented

**Future:** Store exchange rates, calculate balances in base currency (IDR).

### Subscription Detection
**Current:** Manual tagging via category

**Future:** Detect recurring charges (same amount, ~monthly cadence) → auto-suggest subscription.

---

## Development Workflow

### Local Setup
```bash
# 1. Install dependencies
pip3 install -r requirements.txt

# 2. Set up environment
cp .env.example .env
# Fill in SUPABASE_URL, SUPABASE_KEY, ANTHROPIC_API_KEY

# 3. Apply migrations
supabase db push

# 4. Seed historical data
make import-csv

# 5. Test ingestion
make ingest f=data/statements/test.pdf w="BCA Leisure"
```

### Migration Workflow
```bash
# Create migration
supabase migration new <name>

# Apply
make migrate

# Revert (manual script in supabase/revert/)
make revert
```

### Testing Strategy
- **Unit tests:** `pytest` for fingerprint, schema validation
- **Integration tests:** End-to-end ingestion with fixture PDFs
- **Manual QA:** Review queue in frontend (approve/reject real transactions)

---

## Philosophy

This architecture optimizes for:
1. **Minimal surface area** — no backend server unless absolutely needed
2. **Data durability** — Postgres dump is portable; won't orphan like Simple app
3. **Cost efficiency** — $0/month except pennies of Claude API
4. **Human-in-the-loop** — never auto-approve financial data
5. **Cabin before cathedral** — ship lean core, add features only after it earns its keep

**Not optimized for:**
- Multi-user / multi-tenant (personal tool only)
- Real-time collaboration (monthly batch workflow)
- Scalability beyond 1 user (Supabase free tier caps acceptable)

The system is deliberately overfit to the problem: **kill the pain of manual monthly entry from bank e-statements.** Everything else is a view over a single `transactions` table.
