local p = "undotree"; if (not require('killerrat.plugins._lazy-nvim').LazyHasPlugin(p)) then return end
vim.g.undotree_WindowLayout = 2
vim.g.undotree_DiffpanelHeight = 10
vim.keymap.set("n", "<leader>U", vim.cmd.UndotreeToggle)
