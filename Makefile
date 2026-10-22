ifneq (,$(wildcard .env))
    include .env
    export
endif

.PHONY: install ingest ingest-dir import-csv migrate revert new-migration backup restore

install:
	pip3 install -r requirements.txt

# Usage: make ingest f=data/statements/bca-jan-2026.pdf w="BCA (Leisure)"
ingest:
	python3 -m app.main ingest "$(f)" --wallet "$(w)"

# Usage: make ingest-dir d=data/statements w="BCA (Leisure)"
ingest-dir:
	python3 -m app.main ingest-dir $(d) --wallet "$(w)"

# Usage: make import-csv f=data/imports/file.csv
import-csv:
	python3 -m app.main import-csv "$(f)"


migrate:
	supabase db push

revert:
	psql "$(SUPABASE_DB_URL)" -f supabase/revert/$(shell ls supabase/revert | tail -1)

# Usage: make new-migration name=add_wallet_notes
new-migration:
	@[ "$(name)" ] || (echo "Usage: make new-migration name=<migration_name>"; exit 1)
	@supabase migration new $(name)
	@FILE=$$(ls supabase/migrations/*_$(name).sql | tail -1); \
	[ -n "$$FILE" ] || (echo "Could not find the new migration file"; exit 1); \
	touch "supabase/revert/$$(basename $$FILE)"; \
	echo "Created supabase/revert/$$(basename $$FILE)"

# Backup database to backups/ directory
backup:
	@set -o pipefail; \
	echo "📦 Backing up Supabase database..."; \
	DIR=data/backups/$$(date +%Y-%m); \
	mkdir -p $$DIR; \
	echo "  → Full database dump (compressed)..." && \
	pg_dump "$(SUPABASE_DB_URL)" | gzip > $$DIR/full-$$(date +%Y%m%d-%H%M%S).sql.gz && \
	echo "  → Exporting transactions table..." && \
	psql "$(SUPABASE_DB_URL)" -v ON_ERROR_STOP=1 -c "COPY transactions TO STDOUT CSV HEADER" > $$DIR/transactions-$$(date +%Y%m%d).csv && \
	echo "  → Exporting wallets table..." && \
	psql "$(SUPABASE_DB_URL)" -v ON_ERROR_STOP=1 -c "COPY wallets TO STDOUT CSV HEADER" > $$DIR/wallets-$$(date +%Y%m%d).csv && \
	echo "  → Saving metadata..." && \
	{ echo "Backup Date: $$(date)"; \
	  echo "Git Commit: $$(git rev-parse HEAD 2>/dev/null || echo 'N/A')"; \
	  psql "$(SUPABASE_DB_URL)" -v ON_ERROR_STOP=1 -t -c "SELECT 'Total Transactions: ' || COUNT(*) FROM transactions"; \
	} > $$DIR/metadata-$$(date +%Y%m%d).txt && \
	echo "✅ Backup complete: $$DIR/"

# Restore database from backup
# Usage: make restore backup=data/backups/2026-09/full-20260924-165300.sql.gz
restore:
	@[ "$(backup)" ] || (echo "Usage: make restore backup=data/backups/YYYY-MM/full-YYYYMMDD-HHMMSS.sql.gz"; exit 1)
	@[ -f "$(backup)" ] || (echo "❌ File not found: $(backup)"; exit 1)
	@echo "⚠️  WARNING: This will OVERWRITE your current database!"
	@echo "⚠️  Restoring from: $(backup)"
	@echo "⚠️  Press Ctrl+C within 5 seconds to cancel..."
	@sleep 5
	@set -o pipefail; \
	echo "  → Restoring database..." && \
	gunzip -c "$(backup)" | psql "$(SUPABASE_DB_URL)" -v ON_ERROR_STOP=1 && \
	echo "✅ Database restored from $(backup)"
