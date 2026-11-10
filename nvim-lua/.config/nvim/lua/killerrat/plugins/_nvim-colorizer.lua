local p = "nvim-colorizer.lua"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
require 'colorizer'.setup()
