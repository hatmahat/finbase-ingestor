alter table securities drop constraint securities_wallet_ticker_unique;
alter table securities add constraint securities_ticker_key unique (ticker);
