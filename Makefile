ifneq (,$(wildcard .env))
    include .env
    export
endif

.PHONY: install ingest ingest-dir import-csv migrate revert new-migration

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
	@DATE=$$(date +%Y%m%d); \
	touch "supabase/revert/$${DATE}_$(name).sql"; \
	echo "Created supabase/revert/$${DATE}_$(name).sql"
