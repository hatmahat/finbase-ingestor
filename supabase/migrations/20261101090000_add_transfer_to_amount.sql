-- Cross-currency transfers: `amount` is what leaves the source wallet (in its currency),
-- `to_amount` is what arrives in the destination wallet (in its currency).
-- Null means the same amount arrives, which is right for same-currency transfers.
alter table transactions add column to_amount numeric(18,2) check (to_amount > 0);

-- credit the destination wallet with to_amount when set
create or replace view wallet_balances as
select
    w.id,
    w.name,
    wi.name          as institution,
    wt.name          as wallet_type,
    wt.is_liability,
    c.name           as currency,
    w.is_active,
    w.opening_balance,
    w.opening_balance + coalesce(
        sum(
            case
                when tt.name in ('expense', 'transfer') and t.wallet_id    = w.id then -t.amount
                when tt.name in ('income', 'refund')    and t.wallet_id    = w.id then  t.amount
                when tt.name = 'transfer'               and t.to_wallet_id = w.id then  coalesce(t.to_amount, t.amount)
                else 0
            end
        ) filter (where t.status = 'approved'),
        0
    ) as current_balance
from wallets w
join wallet_types        wt on wt.id = w.wallet_type_id
join wallet_institutions wi on wi.id = w.wallet_institution_id
join currencies          c  on c.id  = w.currency_id
left join transactions   t  on t.wallet_id = w.id or t.to_wallet_id = w.id
left join transaction_types tt on tt.id = t.transaction_type_id
group by w.id, w.name, wi.name, wt.name, wt.is_liability, c.name, w.is_active, w.opening_balance;

-- Fix transfers already saved across currencies (they credited the source amount in the wrong currency):
-- find them with
--   select t.id, t.txn_date, t.amount, sw.name, sc.name as from_ccy, dw.name, dc.name as to_ccy
--   from transactions t
--   join wallets sw on sw.id = t.wallet_id    join currencies sc on sc.id = sw.currency_id
--   join wallets dw on dw.id = t.to_wallet_id join currencies dc on dc.id = dw.currency_id
--   where sc.id <> dc.id;
-- then set the real received amount: update transactions set to_amount = <amount received> where id = <id>;
