local p = "nvim-ts-context-commentstring"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
require('ts_context_commentstring').setup {
	enable_autocmd = false,
	languages = {
		-- typescript = '// %s',
		c_sharp = '// %s',
		sql = '-- %s',
	}
}

local get_option = vim.filetype.get_option
vim.filetype.get_option = function(filetype, option)
	return option == "commentstring"
		and require("ts_context_commentstring.internal").calculate_commentstring()
		or get_option(filetype, option)
end
