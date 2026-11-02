-- Revert add_forex_asset_class: Postgres can't drop an enum value, so rebuild the type.
-- Fails on purpose if any security is still 'forex' (cast to the old enum errors) — delete/reclassify those first.
-- holding_positions depends on securities.asset_class, so drop it and recreate it afterwards.
drop view if exists holding_positions;

alter type asset_class_type rename to asset_class_type_old;
create type asset_class_type as enum ('stock', 'etf', 'crypto');

alter table securities alter column asset_class drop default;
alter table securities
    alter column asset_class type asset_class_type using asset_class::text::asset_class_type;
alter table securities alter column asset_class set default 'stock';

drop type asset_class_type_old;

create view holding_positions with (security_invoker = true) as
select h.id, s.ticker, s.name, s.asset_class,
       w.name as wallet, wt.name as wallet_type, cur.name as currency,
       h.shares, h.avg_cost
from holdings h
join securities s    on s.id = h.security_id
join wallets w       on w.id = s.wallet_id
join wallet_types wt on wt.id = w.wallet_type_id
join currencies cur  on cur.id = w.currency_id
where h.shares > 0 and w.is_active;

grant select on holding_positions to mcp_reader;
