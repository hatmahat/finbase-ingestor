-- restore file_name on transactions
alter table transactions add column file_name text;

update transactions t
set file_name = i.file_name
from imports i
where t.import_id = i.id;

-- drop FK
alter table transactions drop column import_id;

-- drop imports
drop trigger trg_set_updated_at on imports;
drop table imports;
