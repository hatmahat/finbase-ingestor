alter table securities drop constraint securities_ticker_key;
alter table securities add constraint securities_wallet_ticker_unique unique (wallet_id, ticker);
