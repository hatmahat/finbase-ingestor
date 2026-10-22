-- Trade log: one row per buy or sell of a security
create table trades (
    id              bigint generated always as identity primary key,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    trade_date      timestamptz not null,
    security_id     bigint not null references securities(id) on delete restrict,
    transaction_id  bigint unique references transactions(id) on delete restrict,  -- the cash transfer saved with this trade (1:1)
    side            text not null check (side in ('buy', 'sell')),
    shares          numeric(18,8) not null check (shares > 0),
    price           numeric(24,10) not null check (price > 0),  -- per unit, in the security wallet's currency; wide scale for low-priced crypto
    total_amount    numeric(18,2) not null check (total_amount > 0),  -- sell/buy amount before fees
    net_amount      numeric(18,2) not null check (net_amount > 0),    -- sell: proceeds received, buy: total paid (fee = the difference)
    realized_pnl    numeric(18,2),              -- sells only: net_amount - shares * avg cost at the time
    check (side = 'sell' or realized_pnl is null),
    check ((side = 'buy'  and net_amount >= total_amount)
        or (side = 'sell' and net_amount <= total_amount))
);
-- covers per-security lookups and date-ordered avg cost / realized P&L
create index on trades (security_id, trade_date);

create trigger trg_set_updated_at before update on trades
    for each row execute function set_updated_at();

alter table trades enable row level security;

create policy "Authenticated full access" on trades
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
