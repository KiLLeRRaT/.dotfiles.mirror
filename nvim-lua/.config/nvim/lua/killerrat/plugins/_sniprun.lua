local p = "sniprun"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
require('sniprun').setup({
	selected_interpreters={"JS_TS_deno"},
	repl_enable={"JS_TS_deno"}
})


vim.api.nvim_set_keymap('v', '<leader>SR', '<Plug>SnipRun', {silent = true})
vim.api.nvim_set_keymap('n', '<leader>Sr', '<Plug>SnipRunOperator', {silent = true})
vim.api.nvim_set_keymap('n', '<leader>SR', '<Plug>SnipRun', {silent = true})
