-- Only add F5 binding in DBUI-managed buffers
if vim.b.dbui_db_key_name then
  vim.keymap.set("n", "<F5>", "<Plug>(DBUI_ExecuteQuery)", { buffer = true, desc = "Execute DBUI query" })
  vim.keymap.set("v", "<F5>", "<Plug>(DBUI_ExecuteQuery)", { buffer = true, desc = "Execute selected DBUI query" })
end
