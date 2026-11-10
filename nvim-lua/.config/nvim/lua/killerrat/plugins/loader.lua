-- killerrat.plugins.loader
--
-- Loads every per-plugin config module in M.modules via pcall, so ONE broken module (plugin not
-- installed on this host, missing binary, upstream API change) no longer aborts every module after
-- it. Before this, a single throw silently took remaps, lualine, telescope etc. down with it.
--
-- Whether a plugin is active on this host is decided, in order, by:
--   1. hosts.lua             per-hostname table; a nil/absent entry means enabled
--   2. lazy `defaults.cond`  _lazy-nvim.lua passes pluginCondForHost for every spec, so a plugin
--                            disabled in hosts.lua never appears in require("lazy.core.config").plugins
--   3. LazyHasPlugin guard   line 1 of each _*.lua returns early when its plugin is absent
-- Each outcome is recorded in M.results; :KillerratPlugins shows them (:KillerratPlugins! opens the
-- full error text in a scratch buffer). Failures are also reported through vim.notify.
--
-- Errors raised INSIDE lazy.nvim (a spec's config/opts/init handler) never reach the pcall above:
-- lazy catches them itself. M.hook_lazy() (called by _lazy-nvim.lua before lazy's setup) records
-- those too, as synthetic rows whose module is "lazy:<handler>".
--
-- At VimEnter, M.prompt_failures() asks once per failed plugin whether to disable it for this host
-- (writes hosts.lua through hosts_edit.lua, so the next start skips it). Opt out with
-- `vim.g.killerrat_plugin_prompt = false`; `= true` forces the prompt even without a UI (tests).

local M = {}

-- Ordered list of config modules. _lazy-nvim is deliberately NOT here: it is hard-required by
-- plugins/init.lua because nothing below can work if lazy itself fails.
M.modules = {
	"killerrat.plugins._colors",
	"killerrat.plugins._tokyonight-nvim",

	"killerrat.plugins._whitespace-nvim",
	"killerrat.plugins._telescope-nvim",
	"killerrat.plugins._vim-devicons",
	"killerrat.plugins._nerdtree",
	"killerrat.plugins._grapple-nvim",
	"killerrat.plugins._better-escape-nvim",
	"killerrat.plugins._hop",
	"killerrat.plugins._flash-nvim",
	"killerrat.plugins._nvim-surround",
	"killerrat.plugins._vim-fugitive",
	-- "killerrat.plugins._vim-commentary",
	-- "killerrat.plugins._mini-comment",
	"killerrat.plugins._nvim-ts-context-commentstring",
	"killerrat.plugins._substitute-nvim",

	-- "killerrat.plugins._copilot",
	"killerrat.plugins._copilot-lua",
	-- "killerrat.plugins._copilotc-nvim",
	"killerrat.plugins._avante",

	"killerrat.plugins._switch-vim",
	"killerrat.plugins._lualine-nvim",
	-- "killerrat.plugins._bufferline-nvim",
	"killerrat.plugins._vimwiki",
	"killerrat.plugins._mason-nvim",
	"killerrat.plugins._mason-lspconfig-nvim",
	"killerrat.plugins._roslyn-nvim",
	"killerrat.plugins._nvim-lspconfig",
	"killerrat.plugins._nvim-cmp",
	"killerrat.plugins._nvim-treesitter",
	"killerrat.plugins._gitsigns-nvim",
	"killerrat.plugins._goto-preview",
	"killerrat.plugins._nvim-treesitter-context",
	-- "killerrat.plugins._tokyonight-nvim",
	"killerrat.plugins._diffview-nvim",
	"killerrat.plugins._neorg",
	"killerrat.plugins._luasnip",
	"killerrat.plugins._undotree",
	"killerrat.plugins._nvim-colorizer",
	"killerrat.plugins._neovim-session-manager",
	"killerrat.plugins._sniprun",
	"killerrat.plugins._nvim-dap",
	"killerrat.plugins._oil-nvim",
	"killerrat.plugins._zen-mode-nvim",
	"killerrat.plugins._gx-nvim",
	"killerrat.plugins._nvim-silicon",
	"killerrat.plugins._vim-dadbod-ui",
	"killerrat.plugins._fzf-lua",
	"killerrat.plugins._conform-nvim",
}

---@class KillerratLoadResult
---@field module string   full module name, e.g. "killerrat.plugins._fzf-lua", or "lazy:config"
---@field plugin string|nil  lazy plugin name from the module's guard line, nil if it has none
---@field status "ok"|"failed"|"skipped"
---@field err string|nil   full error text when status == "failed"
---@field lazy boolean|nil true for a failure captured inside lazy.nvim (see M.hook_lazy)

---@type KillerratLoadResult[]
M.results = {}

--- Number of times the disable prompt (vim.fn.confirm) was actually shown this session.
M.prompt_count = 0

local PREFIX = "killerrat.plugins."

local function first_line(s)
	return (tostring(s):match("^[^\n]*"))
end

-- First line of an error with the Lua throw-site prefix ("…/file.lua:12: ") removed; the full
-- text in M.results is left untouched.
local function display_line(s)
	return (first_line(s):gsub("^[^\n]-:%d+: ", "", 1))
end

local function short_module(mod)
	return (mod:sub(1, #PREFIX) == PREFIX) and mod:sub(#PREFIX + 1) or mod
end

-- Read `local p = "<name>"` from line 1 of the module file (resolved via the runtimepath, so a
-- shadowing copy earlier on 'rtp' is honoured exactly like `require` honours it).
local function plugin_of(mod)
	local rel = "lua/" .. mod:gsub("%.", "/") .. ".lua"
	local path = vim.api.nvim_get_runtime_file(rel, false)[1]
	if not path then return nil end
	local f = io.open(path, "r")
	if not f then return nil end
	local line = f:read("*l") or ""
	f:close()
	return line:match('^local p = "([^"]+)"')
end

function M.host()
	return vim.loop.os_gethostname()
end

-- Run `fn` once VimEnter has happened (now, if it already has), always via vim.schedule.
local function on_vim_enter(fn)
	if vim.v.vim_did_enter == 1 then
		vim.schedule(fn)
		return
	end
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function() vim.schedule(fn) end,
	})
end

function M.load()
	-- Keep rows captured inside lazy.nvim: lazy's setup() ran before us, so they already exist.
	M.results = vim.tbl_filter(function(r) return r.lazy == true end, M.results)
	for _, mod in ipairs(M.modules) do
		local plugin = plugin_of(mod)
		local entry = { module = mod, plugin = plugin, status = "ok", err = nil }
		if plugin ~= nil and require("lazy.core.config").plugins[plugin] == nil then
			-- Disabled in hosts.lua (or absent from the spec): the module's guard line would
			-- return at once, so don't require it at all. A plugin disabled after a failure is
			-- therefore reported as skipped on the next start, whatever the module would do.
			entry.status = "skipped"
		else
			local ok, err = pcall(require, mod)
			if not ok then
				entry.status = "failed"
				entry.err = tostring(err)
				vim.notify(
					("killerrat: %s failed to load: %s"):format(mod, display_line(err)),
					vim.log.levels.ERROR
				)
			end
		end
		M.results[#M.results + 1] = entry
	end
	if not M._prompt_armed then
		M._prompt_armed = true
		on_vim_enter(M.prompt_failures)
	end
	return M.results
end

function M.failures()
	return vim.tbl_filter(function(r) return r.status == "failed" end, M.results)
end

------------------------------------------------------------------------------
-- Capturing failures that happen inside lazy.nvim
------------------------------------------------------------------------------
-- Investigated against lazy.nvim 306a055 (2025-12-17), ~/.local/share/nvim/lazy/lazy.nvim:
--  * Every user handler runs inside Util.try (lua/lazy/core/util.lua:118-137): an xpcall whose
--    error handler builds `opts.msg .. "\n\n" .. err .. pretty_trace()` and, unless opts.on_error
--    is set, does `vim.schedule(function() M.error(msg) end)` (util.lua:124-131). It returns nil
--    and records NOTHING on the plugin object, so option 1 (read `plugin._.…` after setup) is out.
--  * Option 2 cannot target Loader.config: it calls Util.try itself (core/loader.lua:395), so a
--    wrapper around it never sees the error. `init` is not a Loader function at all; it runs
--    inline in Loader.startup (loader.lua:114-116) and Loader.reload (loader.lua:252-254).
--    What IS reachable is Util.try: each of those sites calls it through the module table
--    (`local Util = require("lazy.core.util")`, loader.lua:5; handler/init.lua:34; event.lua:160),
--    so replacing the field `try` before require("lazy").setup() takes effect everywhere.
--  * Plugin identity: Loader.loading has the plugin being loaded (pushed loader.lua:339, popped
--    :366) around the deps (:353) and config/opts (:361 -> :395) calls. `init` runs outside that
--    bracket, so for it the name comes from lazy's own message, loader.lua:116 / :254:
--        "Failed to run `init` for **" .. plugin.name .. "**"
-- We hand lazy an on_error of our own so the error is seen AT the throw point (lazy's stack trace
-- is preserved), record it, and then do exactly what lazy's default handler does.

--- Record a failure that lazy.nvim caught. Returns the new result row.
---@param handler string  e.g. "config", "init"
---@param plugin string|nil
---@param err string
function M.record_lazy_failure(handler, plugin, err)
	local entry = {
		module = "lazy:" .. handler, plugin = plugin, status = "failed", err = tostring(err),
		lazy = true,
	}
	M.results[#M.results + 1] = entry
	-- A lazily loaded plugin (cmd=/ft=/event=) failing after startup: prompt now, not never.
	if M._startup_prompted then
		vim.schedule(function() M.prompt_failure(entry) end)
	end
	return entry
end

--- Install the Util.try wrapper. Must run after lazy.nvim is on the rtp and BEFORE
--- require("lazy").setup(); _lazy-nvim.lua does that. Idempotent.
function M.hook_lazy()
	if M._lazy_hooked then return end
	M._lazy_hooked = true
	local Util = require("lazy.core.util")
	local orig_try = Util.try
	if type(orig_try) ~= "function" then
		vim.notify_once("killerrat: lazy.core.util.try is not a function; lazy error hook skipped",
			vim.log.levels.WARN)
		return
	end
	Util.try = function(fn, opts)
		opts = type(opts) == "string" and { msg = opts } or opts or {}
		local msg, user_on_error = opts.msg, opts.on_error
		local wrapped = vim.tbl_extend("force", opts, {
			on_error = function(full)
				-- Recording must never get in the way of lazy's own handling below.
				local ok, e = pcall(function()
					local Loader = require("lazy.core.loader")
					local current = Loader.loading[#Loader.loading]
					local plugin = current and current.name
						or (msg and msg:match("^Failed to run `init` for %*%*(.-)%*%*$"))
					-- Only load-related errors are ours: skip an anonymous try (event re-fire).
					if plugin or msg then
						local handler = msg and (msg:match("^Failed to run `(%w+)`")
							or msg:match("^Failed to (%w+ %w+)")) or "try"
						-- `full` is `msg .. "\n\n" .. err .. trace`: keep just the error + trace.
						local err = full
						if msg and full:sub(1, #msg + 2) == msg .. "\n\n" then
							err = full:sub(#msg + 3)
						end
						M.record_lazy_failure(handler, plugin, err)
					end
				end)
				if not ok then
					vim.schedule(function()
						vim.notify("killerrat: failed to record a lazy.nvim error: " .. tostring(e),
							vim.log.levels.ERROR)
					end)
				end
				if user_on_error then
					user_on_error(full)
				else
					vim.schedule(function() Util.error(full) end) -- lazy's default, util.lua:129-131
				end
			end,
		})
		return orig_try(fn, wrapped)
	end
end

------------------------------------------------------------------------------
-- Startup prompt
------------------------------------------------------------------------------

local prompted = {} -- plugin name -> true, so one plugin is never asked about twice per session
local skip_all = false

local function should_prompt()
	local g = vim.g.killerrat_plugin_prompt
	if g == false then return false end
	if g == true then return true end
	return #vim.api.nvim_list_uis() > 0
end

local function label_of(r)
	if r.lazy then
		return ("lazy.nvim `%s` handler"):format(r.module:gsub("^lazy:", ""))
	end
	return ("`%s.lua`"):format(short_module(r.module))
end

local open_error_buffer -- defined with the :KillerratPlugins command below

--- Ask whether to disable the plugin of one failed row for this host. No-op without a plugin,
--- when already asked, after "Skip all", or when prompting is off.
---@param r KillerratLoadResult
function M.prompt_failure(r)
	if skip_all or r.status ~= "failed" or not r.plugin or prompted[r.plugin] then return end
	if not should_prompt() then return end
	prompted[r.plugin] = true
	local host = M.host()
	local msg = ("%s failed to load (plugin `%s`) on host `%s`:\n%s\n\nDisable `%s` for this host?")
		:format(label_of(r), r.plugin, host, display_line(r.err), r.plugin)
	while true do
		M.prompt_count = M.prompt_count + 1
		local choice = vim.fn.confirm(msg, "&Disable\n&Skip\nS&how error\nSkip &all", 2)
		if choice == 1 then
			local ok, text = require("killerrat.plugins.hosts_edit").set(host, r.plugin, false)
			vim.notify(("killerrat: %s"):format(text), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
			return
		elseif choice == 3 then
			open_error_buffer({ r }, true)
			-- fall through: ask the same question again
		elseif choice == 4 then
			skip_all = true
			return
		else
			return -- Skip (2), <Esc> (0) or anything else
		end
	end
end

--- Runs once (vim.schedule'd) at VimEnter: prompt for every failure recorded so far.
function M.prompt_failures()
	M._startup_prompted = true
	if not should_prompt() then return end
	local unmapped = 0
	for _, r in ipairs(M.results) do
		if r.status == "failed" then
			if r.plugin then
				M.prompt_failure(r)
			else
				unmapped = unmapped + 1
			end
		end
	end
	if unmapped > 0 then
		vim.notify(
			("killerrat: %d failed module(s) have no plugin mapping; see :KillerratPlugins!")
				:format(unmapped),
			vim.log.levels.INFO
		)
	end
end

local STATUS_ORDER = { failed = 1, skipped = 2, ok = 3 }

-- Rows sorted failed -> skipped -> ok, original load order within each group.
local function sorted_results()
	local rows = {}
	for i, r in ipairs(M.results) do
		rows[#rows + 1] = { idx = i, r = r }
	end
	table.sort(rows, function(a, b)
		local oa, ob = STATUS_ORDER[a.r.status] or 9, STATUS_ORDER[b.r.status] or 9
		if oa ~= ob then return oa < ob end
		return a.idx < b.idx
	end)
	local out = {}
	for _, row in ipairs(rows) do out[#out + 1] = row.r end
	return out
end

local function render_lines()
	local rows = sorted_results()
	local counts = { ok = 0, skipped = 0, failed = 0 }
	local cells = {}
	for _, r in ipairs(rows) do
		counts[r.status] = (counts[r.status] or 0) + 1
		cells[#cells + 1] = {
			short_module(r.module), r.plugin or "-", r.status, r.err and display_line(r.err) or "",
		}
	end
	local header = { "MODULE", "PLUGIN", "STATUS", "ERROR (first line)" }
	local width = {}
	for c = 1, 3 do
		width[c] = #header[c]
		for _, row in ipairs(cells) do
			width[c] = math.max(width[c], vim.fn.strdisplaywidth(row[c]))
		end
	end
	local function fmt(row)
		local parts = {}
		for c = 1, 3 do
			parts[c] = row[c] .. string.rep(" ", width[c] - vim.fn.strdisplaywidth(row[c]))
		end
		parts[4] = row[4]
		return table.concat(parts, "  ")
	end
	local lines = {
		("killerrat plugins on host %s: %d ok, %d skipped, %d failed (modules under %s)"):format(
			M.host(), counts.ok, counts.skipped, counts.failed, PREFIX:sub(1, -2)),
		fmt(header),
	}
	for _, row in ipairs(cells) do lines[#lines + 1] = fmt(row) end
	return lines, rows
end

--- Open a scratch split with the full error text of every failed row in `rows`.
---@param rows KillerratLoadResult[]
---@param only_errors boolean  true: no status table header, just the error sections
open_error_buffer = function(rows, only_errors)
	local lines = only_errors and {} or (render_lines())
	for _, r in ipairs(rows) do
		if r.status == "failed" then
			if #lines > 0 then lines[#lines + 1] = "" end
			lines[#lines + 1] = ("--- %s (%s) ---"):format(r.module, r.plugin or "-")
			vim.list_extend(lines, vim.split(r.err or "", "\n", { plain = true }))
		end
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "killerratplugins"
	vim.cmd.split()
	vim.api.nvim_set_current_buf(buf)
	vim.cmd.redraw()
end

vim.api.nvim_create_user_command("KillerratPlugins", function(opts)
	if not opts.bang then
		print(table.concat((render_lines()), "\n"))
		return
	end
	local _, rows = render_lines()
	open_error_buffer(rows, false)
end, {
	bang = true,
	desc = "Show load status of every killerrat plugin config module (! opens full errors)",
})

return M
