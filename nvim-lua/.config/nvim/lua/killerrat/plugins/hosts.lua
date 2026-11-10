-- Every plugin honours this table via `defaults.cond` in _lazy-nvim.lua; :KillerratPlugins shows
-- the outcome. The startup prompt and scripts/nvim-plugins may add entries via hosts_edit.lua.

local servers = {
	["neorg"] = false,
	["luarocks.nvim"] = false,
	["nvim-silicon"] = false,
	["nvim-dap-ui"] = false,
	["nvim-dap-virtual-text"] = false,
	["telescope-dap.nvim"] = false,
	["nvim-dap"] = false,
	["nvim-nio"] = false,
	["nvim-dbee"] = false,
	["vim-dadbod-ui"] = false,
	["avante.nvim"] = false,
	-- ["copilot"] = false
	["copilot.lua"] = false,
	["nvim-treesitter"] = false,
	["nvim-treesitter-textobjects"] = false
}

local iphone = {
	["nvim-silicon"] = false,
	["nvim-dap-ui"] = false,
	["nvim-dap-virtual-text"] = false,
	["telescope-dap.nvim"] = false,
	["nvim-dap"] = false,
	["nvim-nio"] = false,
	["nvim-dbee"] = false,
	["neorg"] = false,
	["vim-dadbod-ui"] = false,
}

local sierradeltaPlugins = vim.deepcopy(servers)
sierradeltaPlugins["neorg"] = true
sierradeltaPlugins["luarocks.nvim"] = true
sierradeltaPlugins["nvim-nio"] = true

local plugins = {}
plugins = {
		-- if not set, defaults to enabled = true
	["arch-agouws"] = { },
	["pappa"] = servers,
	["sierraecho"] = servers,
	["sierrafoxtrot"] = servers,
	["sierradelta"] = sierradeltaPlugins,
	["proxmox-i7-2600k"] = servers,
	["proxmox-backup-server"] = servers,
	["proxmox-backup-server4"] = servers,
	["kiosk-1"] = servers,
	["SALDOCPROD1"] = servers,
	["SALDOCDEV1"] = vim.tbl_extend("force", servers, { }),
	["SALAZAGENTS01"] = vim.tbl_extend("force", servers, { }),
	["localhost"] = iphone,
	["arch-i5-6400"] = {
		["copilot.lua"] = false,
		["nvim-dbee"] = false,
		["vim-dadbod-ui"] = false,
		["avante.nvim"] = false,
	},
	["hppavilion"] = {
		["copilot.lua"] = false,
		["nvim-dbee"] = false,
		["vim-dadbod-ui"] = false,
		["avante.nvim"] = false,
	},
	["agouws3"] = {
		["neorg"] = false,
		["luarocks.nvim"] = false,
	}
}
return plugins
