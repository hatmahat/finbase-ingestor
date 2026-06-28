create or replace view wallet_balances as
select
    w.id,
    w.name,
    wi.name          as institution,
    wt.name          as wallet_type,
    wt.is_liability,
    c.name           as currency,
    w.is_active,
    w.sort_order,
    w.opening_balance,
    w.opening_balance + coalesce(
        sum(
            case
                when tt.name in ('expense', 'transfer') and t.wallet_id    = w.id then -t.amount
                when tt.name in ('income', 'refund')    and t.wallet_id    = w.id then  t.amount
                when tt.name = 'transfer'               and t.to_wallet_id = w.id then  t.amount
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
group by w.id, w.name, wi.name, wt.name, wt.is_liability, c.name, w.is_active, w.sort_order, w.opening_balance
order by w.sort_order;
