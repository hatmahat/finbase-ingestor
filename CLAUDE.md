# finbase — Project Context

A personal finance ledger. The one feature that justifies everything: **upload a bank e-statement → Claude extracts and categorizes every transaction → rows land in the database as `pending` → I approve or reject each one in the frontend.**

Everything else (analytics dashboard, wallets, subscriptions) is a view over a single `transactions` table.

Built as a **personal tool + portfolio/learning artifact — not a business.** Guiding mantra: **cabin before cathedral.**

---

## Why this exists

- Tracked finances for ~4 years in **Simple** (formerly Budgetify / Personal Capital). App is abandonware.
- The real pain: **manual monthly entry** of spending from bank e-statements. That's the thing being automated.
- Have orphaned CSV exports from Simple (809 transactions, Jan–Dec 2025). One-time migration to seed history.

---

## Scope

### In scope
- **MAIN FEATURE:** e-statement (PDF) → Claude API structured extraction → insert as `pending` → **human approval per transaction** (approve / reject) via the frontend.
- **Analytics dashboard** — savings rate, spending by category, monthly totals, wallet balances.
- **Wallet tracking.**
- **Subscription tracking.**

### Out of scope (decided)
- **Portfolio tracker** — already working in Google Sheets. Don't rebuild solved problems.
- **Multi-user / family** — turns it into a product. Not now.
- **MCP server** — Phase 2, additive learning exercise only. The ingestion uses plain tool-use, not MCP.

---

## Tech stack

**Frontend (Vercel)**
- Next.js + TypeScript
- Tailwind CSS + shadcn/ui
- Recharts

**Database: Supabase**
- Postgres
- Frontend reads/writes via `supabase-js` directly — no backend needed for CRUD
- Supabase Auth + Row Level Security

**Backend: Python — ingestion only (CLI-first)**
- CLI via typer (`make ingest`, `make import-csv`)
- pdfplumber + pikepdf (PDF parsing/decryption); pytesseract for scanned statements
- Anthropic SDK (Claude extraction + categorization)
- **Do NOT host on Vercel** — PDF/OCR libs are native binaries. Use Cloud Run (scale-to-zero) or Railway/Render when hosted.

**AI**
- Anthropic API, structured output via forced tool-use (`record_transactions`) → returns typed JSON array
- `claude-sonnet-4-6` for accuracy; swap to `claude-haiku-4-5-20251001` to cut cost

---

## Cost

Effectively **$0/month except a few cents of Claude API per statement.**
- Supabase free tier: data is KB vs 500MB cap. Pauses after 7 days idle but data is preserved — fine for monthly use.
- Vercel Hobby: free for personal/non-commercial use.

---

## Key architecture decisions

1. **Frontend → Supabase directly** for all normal CRUD. Python backend exists ONLY for: Anthropic API call (holds key), PDF parsing. Far less backend code than a typical app.

2. **Structured output, not an agent.** One forced `record_transactions` tool call returns guaranteed-valid JSON. Linear pipeline: read PDF → Claude (extract + categorize) → fingerprint → insert.

3. **Dedup via `fingerprint UNIQUE` constraint.** `fingerprint = sha256(account | date | amount | normalized_description)`. Re-uploading the same statement is a silent no-op.

4. **Human-in-the-loop.** Every row inserts as `status='pending'` with a `model_confidence` score (0–1). The review queue in the frontend is a first-class screen — approve or reject per transaction. Never auto-approve financial data.

5. **One-time CSV migration.** 809 transactions from Simple app seeded history. After that, only PDF e-statements going forward.

---

## Project structure

```
finbase-backend/
├── app/                          # Application logic
│   ├── main.py                   # CLI entry: ingest, ingest-dir, import-csv
│   ├── core/                     # config.py (Settings), database.py (Supabase client)
│   ├── models/                   # Dataclasses mirroring DB tables
│   ├── schemas/                  # Pydantic v2: ExtractedTransaction, CsvRow
│   ├── repositories/             # Supabase queries + dedup upsert
│   └── services/                 # Orchestration: ingest.py, csv_import.py
├── pkg/                          # External integrations
│   └── parser/
│       ├── pdf_reader.py         # pikepdf + pdfplumber; pytesseract fallback
│       ├── claude_extractor.py   # Anthropic SDK, forced tool-use record_transactions
│       └── fingerprint.py        # sha256 dedup key
├── supabase/                     # Supabase CLI migrations
│   ├── migrations/               # Deploy scripts (timestamped)
│   └── revert/                   # Manual revert scripts
├── data/                         # gitignored
│   ├── statements/               # drop PDFs here
│   └── imports/                  # CSV for one-time migration
└── Makefile                      # make ingest / import-csv / migrate / revert
```

---

## Postgres schema

Schema file: `supabase/migrations/20260628000000_initial_schema.sql` (Supabase CLI). Normalized design — lookup tables instead of raw strings.

**Core tables**
- `transactions` — the ledger; every row is one transaction. `status` ∈ `{pending, approved, rejected}`. `fingerprint` is `UNIQUE`. `model_confidence` 0–1.
- `wallets` — accounts (BCA Leisure, BRI Credit Card, Mandiri Opr. Cash, etc.). References `wallet_types`, `wallet_institutions`, `currencies`.
- `categories` / `category_groups` — 50-category taxonomy; each category belongs to one group.

**Lookup tables**
- `wallet_types` — `bank`, `cash`, `credit_card`, `e_wallet`, `investment`, `restricted`; `is_liability` flag
- `wallet_institutions` — BCA, Mandiri, BRI, Nanovest, GoTrade, etc.
- `currencies` — ISO 4217 (IDR, SGD, JPY, USD)
- `transaction_types` — `expense`, `income`, `transfer`; `is_income` flag

**Investment tables**
- `securities` — ticker, name, asset_class (`stock`, `etf`, `crypto`); linked to a wallet (platform)
- `holdings` — current share count per security

**Triggers**
- `set_updated_at` — auto-stamps `updated_at` on every table
- `check_transfer_shape` — enforces: transfers must have `to_wallet_id` set and source ≠ destination; expense/income must not have `to_wallet_id`

---

## Category taxonomy (50 — keep ingestion consistent)

Bank Fees, Cash, Cellphone, Charity, Cinema, Coffee, Cosmetics, Credit Card, Doctor, Drinks, Education, Electricity, Electronics, Fashion, Flight, Food, Games, Gas, Groceries, Gym, Health Insurance, Home Maintenance, Home Supplies, Hotel, Income, Income Tax, Internet, Investment, Laundry, Life Insurance, Maintenance, Medication, Miscellaneous, Others, Parking, Public Transport, Salary, Shopping, Subscriptions, Taxi, Telephone, Tolls, Transfer, Travel Attractions, Treat, Unknown, Vacation, Vehicle Tax, Water, Zakat

---

## Data files

- `data/imports/transactions-from-1-1-2025-to-31-12-2026.csv` — 809 transactions from Simple app (Jan–Dec 2025). One-time import to seed historical data. CSV columns: `date, amount, type, category, originWallet, destinationWallet, note, location`.

---

## Build roadmap

**Phase 1 — kill the pain**
1. Spin up Supabase; `supabase db push` to apply all migrations
2. `make import-csv` — seed 809 historical transactions from `data/imports/`
3. `make ingest f=<pdf> w="<wallet>"` — PDF → Claude extraction → Supabase insert with dedup
4. Frontend review queue: approve / reject pending rows per transaction

**Phase 2 — after Phase 1 earns its keep**
5. Analytics dashboard: savings rate (lead metric), spending by category, monthly totals, wallet balances
6. MCP server wrapping the ledger (`query_spending`, `list_pending`, `get_savings_rate`) — additive learning exercise, separate from ingestion

---

## Frontend design references

- **Open-source:** Maybe Finance (`maybe-finance/maybe`), Actual Budget (`actualbudget/actual`), Lunch Money
- **Commercial (visual study):** Copilot Money (category pills, calm palette, color = direction), Monarch Money (savings rate up top, cash flow, spending-by-category)
- **Patterns:** Mobbin (fintech flows), Figma Community finance dashboard kits
- shadcn/ui primitives cover most of the UI: `Card`, `Table`, `Badge` (category pills), `Dialog` (inline edit), `Tabs`

---

## Guiding principles

- **Cabin before cathedral.** Ship the lean core; add features only after it earns its keep.
- **Build from felt pain, not imagined pain.** Automate the high-frequency painful thing; leave the low-frequency enjoyable thing (portfolio in Sheets) alone.
- **Not a business.** Personal tool + portfolio artifact only. Consumer PFM is a monetization graveyard.
- **Savings rate is the metric that matters** — tracking is a monitoring / early-warning tool, not a wealth lever.
- **Don't reverse-justify.** Don't build "to learn MCP" — build because it kills the monthly pain.
- **Own the data in a durable format** that can't be orphaned the way Simple was.

---

## Open items

- Set up Supabase; fill in `.env` from `.env.example`; run `supabase db push`
- Seed history: `make import-csv`
- Test ingestion: `make ingest f=data/statements/<file>.pdf w="<wallet>"`
- Tune Claude extraction prompt against a real BCA/BRI/Mandiri statement
- Build frontend review queue (Next.js in `finbase-frontend` repo)
