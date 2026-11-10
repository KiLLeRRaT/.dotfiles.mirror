local p = "fzf-lua"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
-- imap <c-x><c-f> <plug>(fzf-complete-path)
-- vim.keymap.set("i", "<C-x><C-f>", "<plug>(fzf-complete-path)")


-- vim.keymap.set({ "n", "v", "i" }, "<C-x><C-f>",
-- 	function() require("fzf-lua").complete_path() end,
-- 	{ silent = true, desc = "Fuzzy complete path" })
--
--
require('fzf-lua').setup({'fzf-native'})

vim.keymap.set({ "i" }, "<C-x><C-f>",
	function() require("fzf-lua").complete_file() end,
	{ silent = true, desc = "Fuzzy complete file" })
