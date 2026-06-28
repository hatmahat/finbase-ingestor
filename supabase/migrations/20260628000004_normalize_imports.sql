create table imports (
    id          bigint generated always as identity primary key,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    file_name   text not null unique,
    file_type   text not null check (file_type in ('pdf', 'csv')),
    imported_at timestamptz not null default now(),
    row_count   int not null default 0
);

create trigger trg_set_updated_at before update on imports
    for each row execute function set_updated_at();

-- backfill imports from existing transactions
insert into imports (file_name, file_type)
select distinct
    file_name,
    case when file_name ilike '%.pdf' then 'pdf' else 'csv' end
from transactions
where file_name is not null;

-- add FK column to transactions
alter table transactions add column import_id bigint references imports(id) on delete restrict;

-- backfill import_id
update transactions t
set import_id = i.id
from imports i
where t.file_name = i.file_name;

-- remove the now-redundant text column
alter table transactions drop column file_name;
