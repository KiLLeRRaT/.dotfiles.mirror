local p = "zen-mode.nvim"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
require('zen-mode').setup {
	plugins = {
		gitsigns = { enabled = true },
		tmux = { enabled = true },
		alacritty = {
			enabled = true,
			font = "+25"
		}
	}
}
