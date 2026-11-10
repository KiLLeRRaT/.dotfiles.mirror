local p = "nvim-treesitter-context"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
require'treesitter-context'.setup {}
