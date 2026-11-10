-- lazy.nvim itself stays a hard require: if it cannot bootstrap, nothing below can work.
require("killerrat.plugins._lazy-nvim")

-- Every per-plugin config module is loaded via pcall; see loader.lua and :KillerratPlugins.
require("killerrat.plugins.loader").load()
