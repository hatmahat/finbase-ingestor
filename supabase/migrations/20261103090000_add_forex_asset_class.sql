-- Add 'forex' to asset_class_type so currency pairs can be held as securities.
-- Note: the new value can't be used in this same transaction (e.g. no inserts here).
alter type asset_class_type add value if not exists 'forex';
