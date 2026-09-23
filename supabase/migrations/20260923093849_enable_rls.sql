-- Enable RLS on every table
alter table category_groups     enable row level security;
alter table categories          enable row level security;
alter table wallet_types        enable row level security;
alter table currencies          enable row level security;
alter table wallet_institutions enable row level security;
alter table wallets             enable row level security;
alter table transaction_types   enable row level security;
alter table transactions        enable row level security;
alter table securities          enable row level security;
alter table holdings            enable row level security;
alter table imports             enable row level security;

-- One policy per table: authenticated users get full access, anon gets nothing
create policy "Authenticated full access" on category_groups
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on categories
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on wallet_types
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on currencies
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on wallet_institutions
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on wallets
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on transaction_types
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on transactions
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on securities
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on holdings
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create policy "Authenticated full access" on imports
    for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- View: make it run with the querying user's permissions, not the owner's,
-- so it respects the RLS on wallets/transactions underneath it
alter view wallet_balances set (security_invoker = true);