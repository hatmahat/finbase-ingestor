-- Revert add_holding_positions_view
drop policy mcp_reader_select on securities;
drop policy mcp_reader_select on holdings;

revoke select on holdings, securities from mcp_reader;

-- dropping the view also drops its grant
drop view holding_positions;
