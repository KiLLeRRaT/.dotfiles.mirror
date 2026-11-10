local p = "mini.comment"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
-- require('mini.comment').setup {
-- 	options = {
-- 		custom_commentstring = function()
-- 			return require('ts_context_commentstring').calculate_commentstring() or vim.bo.commentstring
-- 		end,
-- 	},
-- }
