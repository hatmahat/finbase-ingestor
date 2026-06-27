# finbase — Project Context & Handoff

> **How to use this doc:** Paste or upload it at the start of a new chat with this framing:
> *"I'm continuing a personal project called **finbase**. The doc below is the full context and the decisions already locked in. Help me continue building it — and hold me to the scope discipline noted at the bottom."*

---

## TL;DR

A personal finance ledger app. The one feature that justifies the whole thing: **upload a bank e-statement → Claude extracts + categorizes every transaction → it lands in my database as `pending` → I approve or remove per transaction.** Everything else (dashboard, wallets, subscriptions) is a view over a single `transactions` table.

Built as a **personal tool + portfolio/learning artifact — not a business.** Guiding mantra: **cabin before cathedral.**

---

## Why this exists (the pain)

- I tracked finances for ~4 years in **Simple** (formerly Budgetify / Personal Capital). The app is abandonware and I'm locked out on my MacBook.
- The real pain was **manual monthly entry** of spending from bank e-statements. That's the thing being automated.
- I have orphaned CSV exports from Simple (1,073 transactions). They've been cleaned and migrated already (see Artifacts).

---

## Scope

### In scope (the disciplined version)
- **MAIN FEATURE:** e-statement (PDF) → Claude API structured extraction → auto-insert → **human approval per transaction** (approve / remove).
- **Categorization** matching my existing taxonomy (50 categories, listed below).
- **Analytics dashboard** — charts: spending by category, monthly totals, savings rate, total spent / income / invested.
- **Wallets** tracking.
- **Subscription** tracking.

### Explicitly OUT of scope (decided, with reasons)
- **Portfolio tracker** — already well-built in Google Sheets (live FX via exchangerate-api, per-holding age-weighted CAGR, realized/unrealized/cost-basis split, 4 years of monthly net-worth snapshots). It's alive, low-pain, mostly self-pricing, and I enjoy maintaining it. Rebuilding = re-solving a solved problem. **Pain asymmetry**: automate the high-frequency painful thing (spending entry), not the low-frequency enjoyable thing (portfolio).
- **Family / multi-user** — the moment it's multi-person it becomes a product (auth, sharing, real upkeep). Not now.
- **MCP server** — see "Roadmap / phase two." NOT part of the current build. My ingestion uses tool-use/function-calling, which is *not* MCP.

---

## Tech stack (decided)

**Frontend (on Vercel)**
- Next.js + TypeScript
- Tailwind CSS + shadcn/ui
- Recharts (charts)

**Database + platform: Supabase**
- Postgres (the ledger)
- Auto-generated REST API → frontend reads/writes tables directly via `supabase-js` (most CRUD needs no backend code)
- Supabase Auth + Row Level Security (free; the piece that would make "family later" safe)

**Backend: Python — only for heavy/secret parts**
- FastAPI (endpoints for ingestion, price refresh, approve actions — when needed)
- pdfplumber + pikepdf (statement parsing/decryption); pytesseract for scanned statements
- Anthropic SDK (Claude extraction/categorization)
- **Do NOT host the Python backend on Vercel** — PDF/OCR libs are native binaries that fight serverless. Host on **Cloud Run** (scale-to-zero, plays to my GCP/k8s strengths) or Railway/Render. For the MVP it may not need hosting at all — run as a **local CLI** or a **GitHub Action cron**.

**AI**
- Anthropic API via **structured output (tool use)** — one forced tool call (`record_transactions`) returns a typed array of transactions.
- Models: `claude-sonnet-4-6` for accuracy on financial data; `claude-haiku-4-5-20251001` to cut cost (one-line swap).

**Optional / later (portfolio or family expansion)**
- Price data: Finnhub, Alpha Vantage, or CoinGecko (free tiers).
- Scheduling: GitHub Actions cron, or Supabase pg_cron / Edge Functions.

---

## Cost reality

Effectively **$0 except a few cents of Claude API per statement** (well under $1/month), as long as it stays personal and Python runs as a script/cron rather than always-on.
- Supabase free tier: data is KB vs the 500MB cap. Projects pause after 7 days idle but **data is preserved** and wake takes ~30s — a non-issue for monthly use (just click Resume).
- Vercel Hobby: free, licensed non-commercial (would owe ~$20/mo Pro if it ever became a paid product).

---

## Key architecture & decisions

1. **Frontend talks to Supabase directly** for normal CRUD. The Python backend exists ONLY for things that can't live in the browser: the Anthropic call (holds the API key), PDF parsing, price fetching. → far less backend code than a typical app.

2. **Structured output is the core concept** (not an "agent framework"). Define a `record_transactions` tool schema, force `tool_choice`, model returns guaranteed-valid JSON. The whole pipeline is a linear script with one LLM call in the middle: read PDF → Claude (extract+categorize) → fingerprint → insert.

3. **Dedup via fingerprint UNIQUE constraint.** `fingerprint = sha256(account | date | amount | normalized_description)`. Re-uploading the same statement is a silent no-op instead of doubling balances.

4. **Human-in-the-loop.** Insert every row as `status='pending'` with a `confidence` score. Review/approve low-confidence rows. Never auto-insert financial data blindly. The review queue is a first-class screen (inbox of low-confidence rows, ideally keyboard-driven).

5. **Simple migration workflow.** One-time CSV import (809 transactions from 2025) to seed historical data. After that, only ingest bank PDF statements for ongoing tracking. No complex cutoff rules needed.

---

## The Postgres schema

```sql
create table if not exists transactions (
    id              bigint generated always as identity primary key,
    txn_date        timestamptz not null,
    amount          numeric(18,2) not null,             -- IDR, always positive; direction in `type`
    type            text not null check (type in ('Expense','Income','Transfer')),
    category        text,
    wallet          text not null,                      -- the account this row belongs to
    to_wallet       text,                               -- destination (transfers only; often null)
    note            text,
    raw_description text,                               -- original bank narration
    balance_after   numeric(18,2),                      -- running balance from the statement line, if present
    fingerprint     text not null unique,               -- dedup key
    confidence      numeric(3,2),                        -- 0..1 model confidence
    status          text not null default 'pending'
                        check (status in ('pending','approved','rejected')),
    source_file     text,
    created_at      timestamptz not null default now()
);
create index if not exists idx_txn_date on transactions (txn_date);
create index if not exists idx_status   on transactions (status);
```

Note: bank e-statements carry a **running balance per line** (`balance_after`) — unlike the Simple export, which had none. This is why statements are a better source of record than the old CSVs (balances anchor themselves going forward).

---

## My data (from the CSV export)

- **809 transactions** covering Jan 1, 2025 → Dec 31, 2025 (full year 2025).
- Exported from Simple app before being locked out.
- **This is a one-time migration** to seed historical data. After migration, only use PDF e-statements going forward.
- CSV structure: `date, amount, type, category, originWallet, destinationWallet, note, location`
- Multiple wallets tracked: BCA (Leisure), BRI (Credit Card), BRI (Savings), Mandiri (Opr. Cash), Sinarmas (Reserved Cash), investment wallets, etc.

### Category taxonomy (50 — keep ingestion consistent with these)
Bank Fees, Cash, Cellphone, Charity, Cinema, Coffee, Cosmetics, Credit Card, Doctor, Drinks, Education, Electricity, Electronics, Fashion, Flight, Food, Games, Gas, Groceries, Gym, Health Insurance, Home Maintenance, Home Supplies, Hotel, Income, Income Tax, Internet, Investment, Laundry, Life Insurance, Maintenance, Medication, Miscellaneous, Others, Parking, Public Transport, Salary, Shopping, Subscriptions, Taxi, Telephone, Tolls, Transfer, Travel Attractions, Treat, Unknown, Vacation, Vehicle Tax, Water, Zakat

---

## Data files

1. **transactions-from-1-1-2025-to-31-12-2026 (1).csv** — 809 transactions from Simple app export (Jan 1 - Dec 31, 2025). One-time import to seed historical data.

---

## Build sequence / roadmap

**Phase 1 — kill the pain (do this first)**
1. Spin up Supabase free; run `schema.sql` to create the database schema.
2. Build CSV importer to seed the 809 historical transactions (one-time migration).
3. Build PDF ingestion script: PDF (with optional password) → Claude structured extraction → Supabase insert with dedup. Test with real bank statement.
4. Review pending rows monthly. **View results in the Supabase table editor if needed — no frontend required to be useful.**

**Phase 2 — only after the core earns its keep**
5. Frontend/dashboard (Next.js + shadcn on Vercel). Three screens: dashboard (lead with **savings rate**, not a transaction wall), transactions table (scannable; category pills, color-coded amounts, inline edit), review queue (the approval inbox).
6. **MCP server** as a deliberate learning exercise — wrap the ledger in MCP tools (`query_spending`, `list_pending`, `categorize_transaction`, `get_savings_rate`), connect Claude Desktop, and operate the ledger in natural language. This is *additive* and separate from the ingestion (which is plain tool-use, not MCP). Don't graft it on before the core works.

---

## Design references (for the eventual frontend)

- **Open-source (read the code — best for a dev):** Maybe Finance (`maybe-finance/maybe`), Actual Budget (`actualbudget/actual`), Lunch Money.
- **Commercial (visual study):** Copilot Money (spending/categorization UX, category pills, calm palette where color *means* in/out), Monarch Money (dashboard composition: net worth up top, cash flow, spending-by-category, recent activity).
- **Browse patterns:** Mobbin (fintech flows), Dribbble/Behance (visual direction only — don't copy unbuildable concept shots), Figma Community finance dashboard kits.
- Most UI is nearly free from shadcn/ui: `Card`, `Table`, `Badge` (category pills), `Dialog` (edit), `Tabs`.

---

## Repo / naming

- Repo name: **`finbase`** (modern, echoes Firebase/Supabase). Single repo with `/backend` and `/frontend` folders rather than separate repos.
- Rejected: `finos` (collides with FINOS, the Fintech Open Source Foundation). `-backend` suffix is redundant since `finbase` already implies the data layer.

---

## Guiding principles (hold me to these)

- **Cabin before cathedral.** Ship the lean core; add features only after the base proves it earns its keep. The MAIN feature justifies the whole project on its own.
- **Build from felt pain, not imagined pain.** Automate the high-frequency painful thing; leave the low-frequency enjoyable thing (portfolio in Sheets) alone.
- **Not a business.** Consumer PFM is a monetization graveyard (Mint died). B2B financial-data infra is crowded/funded (Brick, Ayoconnect, Brankas, Finantier) and the per-bank-parser "moat" is eroding because vision LLMs generalize across formats. This is a personal tool + portfolio artifact. Frame accordingly.
- **Savings rate is the metric that matters** — but I'm already a disciplined saver, so tracking is a monitoring / early-warning tool, not a wealth lever. Don't oversell what tracking does.
- **Don't reverse-justify.** Don't build (or expand) "to learn MCP" or for any tacked-on reason — the build doesn't require it. Build because it kills the monthly pain.
- **Own the data in a durable format** that can't be orphaned the way Simple was.
- **The tracker was never the achievement; what it's for is.** Keep the machine simple enough that it stays out of the way of life.

---

## Open items / next decisions

- Set up Supabase database and run schema.
- Build CSV import script to migrate the 809 historical transactions.
- Build PDF ingestion script with Claude API integration.
- Test with real bank statement (BCA/BRI/Mandiri) and tune extraction prompt.
- Decide CLI/cron vs. hosted backend for ingestion (CLI is the simplest MVP path).