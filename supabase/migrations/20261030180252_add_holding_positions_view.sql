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
grant select on holdings, securities to mcp_reader;
create policy mcp_reader_select on holdings   for select to mcp_reader using (true);
create policy mcp_reader_select on securities for select to mcp_reader using (true);