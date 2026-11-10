local p = "mason.nvim"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
-- require("mason").setup()

require('mason').setup {
	registries = {
		'github:mason-org/mason-registry',
		'github:crashdummyy/mason-registry',
	},
}
