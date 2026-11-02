-- Read-only access for finbase-mcp: the refund type, three views and the mcp_reader role.
-- The design and the reasoning are in finbase-mcp/docs/BUILD_PLAN.md, appendix "schema contract".

-- The dashboard also has refunds. No earlier migration seeds the type, but the live database has it.
insert into transaction_types (name, is_income) values ('refund', false)
on conflict (name) do nothing;

create view transactions_enriched with (security_invoker = true) as
select t.id,
       (t.txn_date at time zone 'Asia/Jakarta')::date as txn_day,
       tt.name as type, t.amount, cur.name as currency,
       c.name as category, w.name as wallet, tw.name as to_wallet,
       t.status, t.note, t.raw_description
from transactions t
join transaction_types tt on tt.id = t.transaction_type_id
join currencies cur       on cur.id = t.currency_id
join wallets w            on w.id = t.wallet_id
left join wallets tw      on tw.id = t.to_wallet_id
left join categories c    on c.id = t.category_id;

-- expenses minus refunds, like the dashboard: a refund counts in the month and category it arrives in
create view monthly_category_spend with (security_invoker = true) as
select date_trunc('month', t.txn_date at time zone 'Asia/Jakarta')::date as month,
       coalesce(c.name, 'Uncategorized')  as category,
       coalesce(cg.name, 'Uncategorized') as category_group,
       cur.name as currency,
       sum(case when tt.name = 'refund' then -t.amount else t.amount end) as total,
       count(*) filter (where tt.name = 'expense') as txns
from transactions t
join transaction_types tt    on tt.id = t.transaction_type_id and tt.name in ('expense', 'refund')
join currencies cur          on cur.id = t.currency_id
left join categories c       on c.id = t.category_id
left join category_groups cg on cg.id = c.category_group_id
where t.status = 'approved'
group by 1, 2, 3, 4;

-- Transfers are neither income nor spending. `invested` is the transfers into an investment wallet
-- (buys, gross: sells are not subtracted). Currencies are never summed together.
create view monthly_summary with (security_invoker = true) as
select month, currency, income, expense, refunds,
       income - expense as net,
       case when income > 0 then round((income - expense) / income, 4) end as savings_rate,
       invested, txns
from (
  select date_trunc('month', t.txn_date at time zone 'Asia/Jakarta')::date as month,
         cur.name as currency,
         coalesce(sum(t.amount) filter (where tt.name = 'income'), 0) as income,
         coalesce(sum(t.amount) filter (where tt.name = 'expense'), 0)
           - coalesce(sum(t.amount) filter (where tt.name = 'refund'), 0) as expense,
         coalesce(sum(t.amount) filter (where tt.name = 'refund'), 0) as refunds,
         coalesce(sum(t.amount) filter (where tt.name = 'transfer' and twt.name = 'investment'), 0) as invested,
         count(*) filter (where tt.name in ('income', 'expense', 'refund')) as txns
  from transactions t
  join transaction_types tt  on tt.id = t.transaction_type_id
  join currencies cur        on cur.id = t.currency_id
  left join wallets tw       on tw.id = t.to_wallet_id
  left join wallet_types twt on twt.id = tw.wallet_type_id
  where t.status = 'approved'
  group by 1, 2
) m;

create role mcp_reader nologin noinherit;
grant mcp_reader to authenticator;
grant usage on schema public to mcp_reader;

grant select on transactions_enriched, monthly_category_spend, monthly_summary, wallet_balances to mcp_reader;
-- every table the views read, because security_invoker runs them as mcp_reader
grant select on transactions, transaction_types, currencies, wallets, wallet_types, wallet_institutions,
                categories, category_groups to mcp_reader;

do $$
declare t text;
begin
  foreach t in array array['transactions', 'transaction_types', 'currencies', 'wallets', 'wallet_types',
                           'wallet_institutions', 'categories', 'category_groups'] loop
    execute format('create policy mcp_reader_select on %I for select to mcp_reader using (true)', t);
  end loop;
end $$;
