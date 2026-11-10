-- Surgical editor for hosts.lua (the per-host plugin enable/disable table).
--
-- hosts.lua is hand-edited and committed, so edits must touch only the bytes that
-- express the one requested change: we locate nodes with Neovim's bundled Lua
-- tree-sitter parser (no nvim-treesitter dependency) and splice text by byte range,
-- never re-serialising the table. Profiles shared between hosts (`servers`, `iphone`,
-- ...) are never mutated; a host bound to a profile gets wrapped in
-- `vim.tbl_extend("force", profile, { ... })` instead. Before writing, the new text is
-- loaded and deep-compared against the original (only the intended key may differ),
-- then written to a temp file and renamed over the original so a crash can't truncate it.

local M = {}

local uv = vim.uv or vim.loop
local loadchunk = loadstring or load

--- Plugins that must never be disabled: the loader itself and its hard dependencies.
M.core = { "lazy.nvim", "plenary.nvim", "nvim-web-devicons" }

local HOSTS_REL = "lua/killerrat/plugins/hosts.lua"
local HOSTS_MOD = "killerrat.plugins.hosts"

local QUERY = [[
(assignment_statement
	(variable_list (identifier) @name (#eq? @name "plugins"))
	(expression_list (table_constructor) @tbl)) @assign
]]

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

--- Absolute path of hosts.lua (runtime lookup, falling back to a sibling of this file).
--- `vim.g.killerrat_hosts_path` (a string) overrides the lookup; _lazy-nvim.lua honours the
--- same variable, so the startup prompt can be exercised against a fixture copy.
---@return string|nil
function M.path()
	local override = vim.g.killerrat_hosts_path
	if type(override) == "string" and override ~= "" then
		return vim.fs.normalize(override)
	end
	local found = vim.api.nvim_get_runtime_file(HOSTS_REL, false)[1]
	if found then
		return vim.fs.normalize(found)
	end
	local src = debug.getinfo(1, "S").source
	if src:sub(1, 1) == "@" then
		local sibling = vim.fs.joinpath(vim.fs.dirname(src:sub(2)), "hosts.lua")
		if uv.fs_stat(sibling) then
			return vim.fs.normalize(sibling)
		end
	end
	return nil
end

local function resolve_path(opts)
	local p = opts and opts.path or M.path()
	if not p then
		error("hosts.lua not found on the runtime path")
	end
	return p
end

local function read_file(path)
	local fh, err = io.open(path, "rb")
	if not fh then
		error(("cannot read %s: %s"):format(path, err))
	end
	local text = fh:read("*a")
	fh:close()
	return text
end

--- Evaluate Lua source as a chunk returning the hosts table.
local function eval_text(text, chunkname)
	local chunk, lerr = loadchunk(text, chunkname)
	if not chunk then
		error("hosts.lua does not compile: " .. tostring(lerr))
	end
	local ok, result = pcall(chunk)
	if not ok then
		error("hosts.lua failed to run: " .. tostring(result))
	end
	if type(result) ~= "table" then
		error("hosts.lua did not return a table (got " .. type(result) .. ")")
	end
	return result
end

local function eval_file(path)
	return eval_text(read_file(path), "@" .. path)
end

local function node_text(node, text)
	return vim.treesitter.get_node_text(node, text)
end

-- 0-based byte offsets: [sb, eb) covers the node.
local function node_bytes(node)
	local _, _, sb = node:start()
	local _, _, eb = node:end_()
	return sb, eb
end

--- Lua literal for a table key: always the `["x"]` form.
local function key_literal(s)
	return ('["%s"]'):format(s)
end

--- Plain key name of a `field` node, or nil for positional / computed keys.
local function field_key(field, text)
	local name = field:field("name")[1]
	if not name then
		return nil
	end
	local t = name:type()
	if t == "identifier" then
		return node_text(name, text)
	elseif t == "string" then
		local content = name:field("content")[1]
		return content and node_text(content, text) or ""
	end
	return nil
end

local function table_fields(tbl)
	local out = {}
	for child in tbl:iter_children() do
		if child:type() == "field" then
			out[#out + 1] = child
		end
	end
	return out
end

--- Last field in `tbl` keyed `key` (Lua "last assignment wins" semantics), or nil.
local function find_field(tbl, key, text)
	local hit
	for _, f in ipairs(table_fields(tbl)) do
		if field_key(f, text) == key then
			hit = f
		end
	end
	return hit
end

local function closing_brace(tbl)
	local n = tbl:child_count()
	for i = n - 1, 0, -1 do
		local c = tbl:child(i)
		if c:type() == "}" then
			return c
		end
	end
	error("table_constructor without a closing brace")
end

--- Leading whitespace of the line containing 0-based byte offset `pos`.
local function line_indent(text, pos)
	local line_start = pos + 1
	while line_start > 1 and text:sub(line_start - 1, line_start - 1) ~= "\n" do
		line_start = line_start - 1
	end
	return text:sub(line_start):match("^[ \t]*")
end

--- True when only whitespace precedes `pos` on its line.
local function starts_line(text, pos)
	local i = pos
	while i > 0 do
		local ch = text:sub(i, i)
		if ch == "\n" then
			return true
		elseif ch ~= " " and ch ~= "\t" and ch ~= "\r" then
			return false
		end
		i = i - 1
	end
	return true
end

local function newline_of(text)
	return text:find("\r\n", 1, true) and "\r\n" or "\n"
end

--- Locate the `plugins = { ... }` assignment (not `local plugins = {}`); prefer the last
--- one that has fields, else the last one. Returns the table_constructor node.
local function find_plugins_table(text)
	local parser = vim.treesitter.get_string_parser(text, "lua")
	local root = parser:parse()[1]:root()
	if root:has_error() then
		error("hosts.lua has a syntax error (tree-sitter reports ERROR nodes)")
	end
	local query = vim.treesitter.query.parse("lua", QUERY)
	local candidates = {}
	for id, node in query:iter_captures(root, text) do
		if query.captures[id] == "assign" then
			local vars = node:named_child(0)
			local exprs = node:named_child(1)
			if vars and exprs and vars:named_child_count() == 1 and exprs:named_child_count() == 1 then
				local var, expr = vars:named_child(0), exprs:named_child(0)
				if var:type() == "identifier" and node_text(var, text) == "plugins"
					and expr:type() == "table_constructor" then
					candidates[#candidates + 1] = expr
				end
			end
		end
	end
	if #candidates == 0 then
		error("could not find `plugins = { ... }` in hosts.lua")
	end
	for i = #candidates, 1, -1 do
		if #table_fields(candidates[i]) > 0 then
			return candidates[i], parser
		end
	end
	return candidates[#candidates], parser
end

--- Indent unit used by the file (indent of the first host-level field), default tab.
local function indent_unit(text, plugins_tbl)
	local first = table_fields(plugins_tbl)[1]
	if first then
		local sb = node_bytes(first)
		local ind = line_indent(text, sb)
		if ind ~= "" then
			return ind
		end
	end
	return "\t"
end

--- Insert `field_core` (a field without its trailing comma, may span lines) as the last
--- entry of table_constructor `tbl`. Returns the new full text.
local function insert_field(text, tbl, field_core, unit)
	local nl = newline_of(text)
	local tsb = node_bytes(tbl)
	local base = line_indent(text, tsb)
	local fields = table_fields(tbl)
	local brace_sb = node_bytes(closing_brace(tbl))

	if #fields == 0 then
		-- `{ }` (or `{}` / `{\n}`): rewrite the whole table as a multi-line one.
		local _, teb = node_bytes(tbl)
		local body = "{" .. nl .. base .. unit .. field_core .. "," .. nl .. base .. "}"
		return text:sub(1, tsb) .. body .. text:sub(teb + 1)
	end

	local last = fields[#fields]
	local _, leb = node_bytes(last)
	local gap = text:sub(leb + 1, brace_sb)
	local comma_rel = gap:match("^%s*,()")
	local has_comma = comma_rel ~= nil
	local nl_rel = gap:find("\n", 1, true)

	if nl_rel then
		-- Multi-line table: add the field on its own line right after the last field's line.
		local eol = leb + nl_rel - 1 -- 0-based offset of the "\n"
		if text:sub(eol, eol) == "\r" then
			eol = eol - 1
		end
		local lsb = node_bytes(last)
		local indent = starts_line(text, lsb) and line_indent(text, lsb) or (base .. unit)
		local comma = has_comma and "" or ","
		return text:sub(1, leb) .. comma .. text:sub(leb + 1, eol)
			.. nl .. indent .. field_core .. "," .. text:sub(eol + 1)
	end

	-- Single-line table: `{ a = 1 }` -> `{ a = 1, b = 2 }`.
	if has_comma then
		local after_comma = leb + comma_rel - 1
		return text:sub(1, after_comma) .. " " .. field_core .. "," .. text:sub(after_comma + 1)
	end
	return text:sub(1, leb) .. ", " .. field_core .. text:sub(leb + 1)
end

--- Set `plugin = enabled` inside table_constructor `tbl`. Returns new text, description.
local function set_in_table(text, tbl, plugin, enabled, unit)
	local existing = find_field(tbl, plugin, text)
	local lit = tostring(enabled)
	if existing then
		local value = existing:field("value")[1]
		if not value then
			error("field " .. key_literal(plugin) .. " has no value node")
		end
		local sb, eb = node_bytes(value)
		return text:sub(1, sb) .. lit .. text:sub(eb + 1), "updated existing key"
	end
	local core = key_literal(plugin) .. " = " .. lit
	return insert_field(text, tbl, core, unit), "added key"
end

--- Recognise `vim.tbl_extend("force", ..., { ... })` and return its last table arg.
local function tbl_extend_target(value, text)
	if value:type() ~= "function_call" then
		return nil
	end
	local name = value:field("name")[1]
	if not name or node_text(name, text) ~= "vim.tbl_extend" then
		return nil, "unsupported function call: " .. node_text(name or value, text)
	end
	local args = value:field("arguments")[1]
	local list = {}
	if args then
		for child in args:iter_children() do
			if child:named() and child:type() ~= "comment" then
				list[#list + 1] = child
			end
		end
	end
	local first, last = list[1], list[#list]
	if not first or first:type() ~= "string" then
		return nil, 'vim.tbl_extend whose first argument is not the string "force"'
	end
	local content = first:field("content")[1]
	if not content or node_text(content, text) ~= "force" then
		return nil, 'vim.tbl_extend whose first argument is not "force"'
	end
	if #list < 2 or last:type() ~= "table_constructor" then
		return nil, "vim.tbl_extend whose last argument is not a table constructor"
	end
	return last
end

--- Compute the edited text. Returns new_text, description.
local function apply_edit(text, host, plugin, enabled)
	local plugins_tbl = find_plugins_table(text)
	local unit = indent_unit(text, plugins_tbl)
	local host_field = find_field(plugins_tbl, host, text)
	local hk, pk = key_literal(host), key_literal(plugin)

	if not host_field then
		-- (a) new host block appended to the plugins table.
		local fsb = node_bytes(table_fields(plugins_tbl)[1] or plugins_tbl)
		local indent1 = table_fields(plugins_tbl)[1] and line_indent(text, fsb) or unit
		local nl = newline_of(text)
		local core = hk .. " = {" .. nl .. indent1 .. unit .. pk .. " = " .. tostring(enabled)
			.. "," .. nl .. indent1 .. "}"
		return insert_field(text, plugins_tbl, core, unit), "added host " .. hk
	end

	local value = host_field:field("value")[1]
	if not value then
		error("host field " .. hk .. " has no value")
	end
	local vt = value:type()

	if vt == "table_constructor" then
		-- (b) plain table literal.
		local new_text, what = set_in_table(text, value, plugin, enabled, unit)
		return new_text, what .. " in " .. hk
	end

	if vt == "function_call" then
		-- (d) existing vim.tbl_extend("force", profile, { ... }) override.
		local target, why = tbl_extend_target(value, text)
		if not target then
			error(("refusing to edit %s: %s"):format(hk, why))
		end
		local new_text, what = set_in_table(text, target, plugin, enabled, unit)
		return new_text, what .. " in " .. hk .. " (tbl_extend override table)"
	end

	-- (c) host bound to a shared profile expression: wrap it, never mutate the profile.
	local expr = node_text(value, text)
	if expr:find("\n", 1, true) then
		error(("refusing to wrap multi-line expression for %s"):format(hk))
	end
	local sb, eb = node_bytes(value)
	local wrapped = ('vim.tbl_extend("force", %s, { %s = %s })'):format(expr, pk, tostring(enabled))
	return text:sub(1, sb) .. wrapped .. text:sub(eb + 1),
		("wrapped profile `%s` for %s in vim.tbl_extend"):format(expr, hk)
end

--- Verify new_text evaluates to the original table with exactly one change.
local function validate(orig_text, new_text, host, plugin, enabled)
	local before = eval_text(orig_text, "=hosts.lua(original)")
	local after = eval_text(new_text, "=hosts.lua(edited)")
	if type(after[host]) ~= "table" then
		error(("after edit, plugins[%s] is not a table"):format(key_literal(host)))
	end
	if after[host][plugin] ~= enabled then
		error(("after edit, plugins[%s][%s] is %s, expected %s"):format(
			key_literal(host), key_literal(plugin), tostring(after[host][plugin]), tostring(enabled)))
	end
	-- vim.deepcopy preserves aliasing (pappa/sierraecho share `servers`), so give the host
	-- its own copy before mutating, or the "expected" profile would change for every alias.
	local expected = vim.deepcopy(before)
	expected[host] = vim.deepcopy(before[host] or {})
	expected[host][plugin] = enabled
	if not vim.deep_equal(after, expected) then
		error("edit changed more than the requested key; refusing to write")
	end
end

--- Write `text` to `path` atomically, preserving the file mode.
local function atomic_write(path, text)
	local st = uv.fs_stat(path)
	local mode = st and st.mode and bit.band(st.mode, 511) or 420 -- 0777 mask, default 0644
	local tmp = ("%s.tmp.%d"):format(path, uv.os_getpid())
	local fd, oerr = uv.fs_open(tmp, "w", mode)
	if not fd then
		error(("cannot create %s: %s"):format(tmp, tostring(oerr)))
	end
	local ok, werr = pcall(function()
		local written = assert(uv.fs_write(fd, text, -1))
		if written ~= #text then
			error(("short write: %d of %d bytes"):format(written, #text))
		end
		assert(uv.fs_fsync(fd))
	end)
	uv.fs_close(fd)
	if not ok then
		uv.fs_unlink(tmp)
		error(werr)
	end
	local rok, rerr = uv.fs_rename(tmp, path)
	if not rok then
		uv.fs_unlink(tmp)
		error(("rename %s -> %s failed: %s"):format(tmp, path, tostring(rerr)))
	end
end

local NAME_PAT = "^[%w%._%-]+$"

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

--- Forget the cached hosts module so the next require() re-reads the file.
function M.reload()
	package.loaded[HOSTS_MOD] = nil
end

--- Effective value of plugins[host][plugin]: true/false, or nil (= not mentioned).
---@param opts? { path?: string }
function M.get(host, plugin, opts)
	local ok, t = pcall(function()
		return eval_file(resolve_path(opts))
	end)
	if not ok or type(t[host]) ~= "table" then
		return nil
	end
	return t[host][plugin]
end

--- Effective table for a host (a copy), or {} when the host is unknown.
---@param opts? { path?: string }
function M.list(host, opts)
	local ok, t = pcall(function()
		return eval_file(resolve_path(opts))
	end)
	if not ok or type(t[host]) ~= "table" then
		return {}
	end
	return vim.deepcopy(t[host])
end

--- Set plugins[host][plugin] = enabled in hosts.lua. Never throws.
---@param host string
---@param plugin string
---@param enabled boolean
---@param opts? { path?: string }
---@return boolean ok
---@return string message summary on success, error on failure
function M.set(host, plugin, enabled, opts)
	local ok, result = pcall(function()
		if type(host) ~= "string" or not host:match(NAME_PAT) then
			error("host must be a plain name (letters, digits, '.', '_', '-')")
		end
		if type(plugin) ~= "string" or not plugin:match(NAME_PAT) then
			error("plugin must be a plain name (letters, digits, '.', '_', '-')")
		end
		if type(enabled) ~= "boolean" then
			error("enabled must be a boolean")
		end
		if enabled == false and vim.tbl_contains(M.core, plugin) then
			error(("refusing to disable core plugin %q"):format(plugin))
		end

		local path = resolve_path(opts)
		local text = read_file(path)
		local new_text, what = apply_edit(text, host, plugin, enabled)
		validate(text, new_text, host, plugin, enabled)

		local summary = ("%s: %s%s = %s (%s)"):format(
			vim.fs.basename(path), key_literal(host), key_literal(plugin), tostring(enabled), what)
		if new_text == text then
			return summary .. " [no change needed]"
		end
		atomic_write(path, new_text)
		M.reload()
		return summary
	end)
	if ok then
		return true, result
	end
	-- error() prefixes the throw site ("…/hosts_edit.lua:123: "); callers want clean text.
	-- Only a location prefix at the very start of the message is removed.
	return false, (tostring(result):gsub("^[^\n]-:%d+: ", "", 1))
end

return M
