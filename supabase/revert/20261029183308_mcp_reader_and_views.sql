-- Revert mcp_reader_and_views
do $$
declare t text;
begin
  foreach t in array array['transactions', 'transaction_types', 'currencies', 'wallets', 'wallet_types',
                           'wallet_institutions', 'categories', 'category_groups'] loop
    execute format('drop policy mcp_reader_select on %I', t);
  end loop;
end $$;

drop view monthly_summary, monthly_category_spend, transactions_enriched;

revoke select on wallet_balances from mcp_reader;
revoke select on transactions, transaction_types, currencies, wallets, wallet_types, wallet_institutions,
                 categories, category_groups from mcp_reader;
revoke usage on schema public from mcp_reader;
revoke mcp_reader from authenticator;
drop role mcp_reader;
-- the `refund` row stays: transactions may reference it
