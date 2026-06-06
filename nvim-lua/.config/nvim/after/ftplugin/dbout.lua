vim.opt_local.foldlevelstart = 99
vim.opt_local.foldlevel = 99

-- Default visible chars per column before truncation kicks in. Edit for a permanent
-- default, or change it live with :DBoutTruncate / the limit keymap below — the
-- runtime value lives in vim.g.dbout_truncate_at and applies to all dbout buffers.
local DEFAULT_TRUNCATE_AT = 25
local function trunc_at()
  local v = vim.g.dbout_truncate_at
  if type(v) == "number" and v >= 1 then return math.floor(v) end
  return DEFAULT_TRUNCATE_AT
end

-- Reveal mode for wide cells:
--   "status" → show the full value in the lualine statusline (doesn't cover data)
--   "float"  → show the full value in a popup near the cursor
-- Flip to "float" to restore the popup behaviour.
local REVEAL_MODE = "status"

-- Normal-mode keybind (buffer-local) to expand/collapse the column under the cursor.
-- Expanding widens it to fit the longest *data* value (header excluded). Also
-- available as :DBoutToggleColumn.
local TOGGLE_KEY = "gz"

-- Normal-mode keybind (buffer-local) to change the truncation limit on the fly.
-- Prompts for an absolute (35) or relative (+5 / -5) value. Also :DBoutTruncate.
local LIMIT_KEY = "gl"

local ns = vim.api.nvim_create_namespace("dbout_truncate")

local float_state    = { win = nil, buf = nil }
local cell_map       = {}   -- [bufnr][row_0] = {col_idx -> full_value}  (data rows only)
local cols_map       = {}   -- [bufnr][row_0] = cols[]                    (ALL truncated rows)
local conceal_map         = {}   -- [bufnr][row_0] = {col_idx -> {cs, ce}}  concealed byte ranges
local expanded_cols  = {}   -- [bufnr] = { [col.from] = true }  columns the user expanded
local last_hover     = {}   -- [winid] = {row_0, col_idx}  debounce
local prev_cursor    = {}   -- [bufnr] = {row_0, col_0}    direction detection
local in_jump        = {}   -- [bufnr] = bool               re-entry guard

local function close_float()
  if float_state.win and vim.api.nvim_win_is_valid(float_state.win) then
    pcall(vim.api.nvim_win_close, float_state.win, true)
  end
  float_state.win = nil
  float_state.buf = nil
end

-- Parse column {from, to} (0-indexed, inclusive) from a "---- ---- ---" separator line.
local function parse_cols(sep)
  local cols, in_dash, start = {}, false, 0
  for i = 1, #sep do
    local ch = sep:sub(i, i)
    if ch == "-" then
      if not in_dash then start, in_dash = i - 1, true end
    else
      if in_dash then
        cols[#cols + 1] = { from = start, to = i - 2 }
        in_dash = false
      end
    end
  end
  if in_dash then cols[#cols + 1] = { from = start, to = #sep - 1 } end
  return cols
end

-- Conceal the overflow of wide columns in one row according to `plan`.
--   plan[col_idx] = { limit = N, side = "left"|"right", ellipsis = bool }
-- `side` is the side that gets concealed: "right" keeps the leading chars
-- (left-aligned text / headers), "left" keeps the trailing chars (right-aligned
-- numerics, so the value stays visible). Records concealed ranges in conceal_map
-- and returns {col_idx -> trimmed_value} for cells whose content exceeds the limit.
local function truncate_row(bufnr, row_0, line, cols, plan)
  local values = {}
  local ranges = {}
  for col_idx, col in ipairs(cols) do
    local p = plan[col_idx]
    if p and col.to - col.from + 1 > p.limit and col.from < #line then
      local last = math.min(col.to, #line - 1)   -- 0-indexed last char actually present
      local cs, ce, ell_col

      if p.side == "left" then
        -- conceal the leading padding, keep the rightmost `limit` chars
        cs = col.from
        ce = math.min(col.to - p.limit, last)
        ell_col = ce + 1                          -- "…value"
      else
        -- conceal the trailing overflow, keep the leading `limit` chars
        cs = col.from + p.limit
        ce = last
        ell_col = cs                              -- "value…"
      end

      if cs <= ce then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row_0, cs, {
          end_col = ce + 1,
          conceal = "",
        })
        if p.ellipsis then
          vim.api.nvim_buf_set_extmark(bufnr, ns, row_0, ell_col, {
            virt_text     = { { "…", "Comment" } },
            virt_text_pos = "inline",
          })
        end
        ranges[col_idx] = { cs, ce }
      end

      local cell    = line:sub(col.from + 1, last + 1)
      local trimmed = vim.trim(cell)
      if #trimmed > p.limit then
        values[col_idx] = trimmed
      end
    end
  end
  conceal_map[bufnr][row_0] = ranges
  return values
end

local ROWS_AFFECTED = "^%(%d+ rows? affected%)"

local function apply_truncation(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  cell_map[bufnr]    = {}
  cols_map[bufnr]    = {}
  conceal_map[bufnr] = {}
  local exp          = expanded_cols[bufnr] or {}

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local i = 1

  while i <= #lines do
    if lines[i]:match("^%-%-%-") then
      local sep_row_0 = i - 1
      local cols      = parse_cols(lines[i])

      -- Find the data-row range for this block (start..stop are 1-indexed line numbers).
      local dstart = i + 1
      local dstop  = dstart - 1
      do
        local j = dstart
        while j <= #lines do
          local dline = lines[j]
          if dline == "" or dline:match(ROWS_AFFECTED) or dline:match("^%-%-%-") then
            break
          end
          dstop = j
          j = j + 1
        end
      end

      -- Per-column analysis of the DATA rows (header excluded): longest value and
      -- alignment (right-aligned ⇒ values hug the right edge, e.g. numerics).
      local maxlen, right_votes, nonempty = {}, {}, {}
      for col_idx = 1, #cols do maxlen[col_idx] = 0; right_votes[col_idx] = 0; nonempty[col_idx] = 0 end
      for j = dstart, dstop do
        local dline = lines[j]
        for col_idx, col in ipairs(cols) do
          local last = math.min(col.to, #dline - 1)
          if last >= col.from then
            local cell    = dline:sub(col.from + 1, last + 1)
            local trimmed = vim.trim(cell)
            if #trimmed > maxlen[col_idx] then maxlen[col_idx] = #trimmed end
            if #trimmed > 0 then
              nonempty[col_idx] = nonempty[col_idx] + 1
              if cell:sub(1, 1) == " " then right_votes[col_idx] = right_votes[col_idx] + 1 end
            end
          end
        end
      end

      -- Build the per-column truncation plan for header/separator vs data rows.
      -- By default each column is fitted to its longest DATA value (capped at the
      -- truncation limit), so short columns and NULL columns no longer carry a wide
      -- band of trailing padding. Expanding (gz) lifts the cap and also makes room
      -- for the full header.
      local header_line = (i >= 2) and lines[i - 1] or ""
      local head_plan, data_plan = {}, {}
      for col_idx, col in ipairs(cols) do
        -- trimmed length of this column's header text
        local hlen, hlast = 0, math.min(col.to, #header_line - 1)
        if hlast >= col.from then
          local hcell = header_line:sub(col.from + 1, hlast + 1)
          hlen = #(vim.trim(hcell))
        end

        local vlen  = maxlen[col_idx]
        local limit
        if exp[col.from] then
          limit = math.max(vlen, hlen, 1)                       -- reveal: full value + header
        else
          limit = math.min(trunc_at(), math.max(vlen, 1))       -- compact: fit value, capped
        end

        local right    = nonempty[col_idx] > 0 and (right_votes[col_idx] * 2 > nonempty[col_idx])
        local overflow = vlen > limit   -- real data content would be hidden ⇒ show "…"
        head_plan[col_idx] = { limit = limit, side = "right", ellipsis = overflow }
        data_plan[col_idx] = { limit = limit, side = right and "left" or "right", ellipsis = overflow }
      end

      -- Header row (one line above separator)
      if sep_row_0 >= 1 and lines[sep_row_0] ~= "" then
        truncate_row(bufnr, sep_row_0 - 1, lines[sep_row_0], cols, head_plan)
        cols_map[bufnr][sep_row_0 - 1] = cols
      end

      -- Separator row itself
      truncate_row(bufnr, sep_row_0, lines[i], cols, head_plan)
      cols_map[bufnr][sep_row_0] = cols

      -- Data rows
      for j = dstart, dstop do
        local row_0  = j - 1
        local values = truncate_row(bufnr, row_0, lines[j], cols, data_plan)
        cols_map[bufnr][row_0] = cols
        if next(values) then
          cell_map[bufnr][row_0] = values
        end
      end

      i = (dstop >= dstart) and (dstop + 1) or (i + 1)
    else
      i = i + 1
    end
  end
end

-- Return the concealed byte range {cs, ce} if col_0 falls inside one, else nil.
local function concealed_range_at(bufnr, row_0, col_0)
  local ranges = conceal_map[bufnr] and conceal_map[bufnr][row_0]
  if not ranges then return nil end
  for _, r in pairs(ranges) do
    if col_0 >= r[1] and col_0 <= r[2] then
      return r[1], r[2]
    end
  end
  return nil
end

local function show_float(bufnr)
  local winid  = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row_0  = cursor[1] - 1
  local col_0  = cursor[2]

  local values = cell_map[bufnr] and cell_map[bufnr][row_0]
  local cols   = cols_map[bufnr] and cols_map[bufnr][row_0]
  if not values or not cols then
    close_float()
    last_hover[winid] = nil
    return
  end

  local value, col_idx_found
  for col_idx, col in ipairs(cols) do
    if col_0 >= col.from and col_0 <= col.to then
      value         = values[col_idx]
      col_idx_found = col_idx
      break
    end
  end

  if not value then
    close_float()
    last_hover[winid] = nil
    return
  end

  -- Debounce: skip redraw if still on the same cell
  local prev = last_hover[winid]
  if prev and prev.row_0 == row_0 and prev.col_idx == col_idx_found then return end
  last_hover[winid] = { row_0 = row_0, col_idx = col_idx_found }

  -- Word-wrap value into float lines
  local win_width  = vim.api.nvim_win_get_width(winid)
  local max_content = math.max(math.min(#value, win_width - 6), 20)
  local wrapped    = {}
  local s          = value
  while #s > 0 do
    if #s <= max_content then
      wrapped[#wrapped + 1] = " " .. s .. " "
      break
    end
    local bp = max_content
    while bp > 1 and s:sub(bp, bp) ~= " " do bp = bp - 1 end
    if bp <= 1 then bp = max_content end
    wrapped[#wrapped + 1] = " " .. s:sub(1, bp) .. " "
    s = vim.trim(s:sub(bp + 1))
  end
  if #wrapped == 0 then wrapped = { " " .. value .. " " } end

  local fwidth = math.min(#wrapped[1], win_width - 4)

  -- Absolute screen position of the *actual cursor*. screencol()/screenrow()
  -- reflect the real rendered cursor location, so they correctly account for
  -- concealed text, inline virtual text and horizontal scroll — unlike
  -- screenpos(win, line, col), which mis-measures concealed lines.
  local scol = vim.fn.screencol()   -- 1-based absolute screen column
  local srow = vim.fn.screenrow()   -- 1-based absolute screen row

  local fheight      = #wrapped
  local total_w      = fwidth + 2     -- include rounded border
  local total_h      = fheight + 2
  local editor_cols  = vim.o.columns
  local editor_lines = vim.o.lines

  -- Horizontal: align left edge with the cursor; clamp so the float stays on screen.
  local fcol = scol - 1                         -- 0-indexed editor column
  if fcol + total_w > editor_cols then
    fcol = math.max(0, editor_cols - total_w)
  end

  -- Vertical: prefer one line below the cursor; flip above if it would overflow.
  local frow = srow                             -- one line below cursor
  if frow + total_h > editor_lines then
    frow = math.max(0, (srow - 1) - total_h)    -- place above the cursor line
  end

  local config = {
    relative = "editor",
    row      = frow,
    col      = fcol,
    width    = fwidth,
    height   = fheight,
  }

  if float_state.win and vim.api.nvim_win_is_valid(float_state.win) then
    vim.api.nvim_buf_set_lines(float_state.buf, 0, -1, false, wrapped)
    vim.api.nvim_win_set_config(float_state.win, config)
  else
    float_state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_state.buf, 0, -1, false, wrapped)
    config.style     = "minimal"
    config.border    = "rounded"
    config.focusable = false
    float_state.win  = vim.api.nvim_open_win(float_state.buf, false, config)
  end
end

-- ── Per-buffer wiring ──────────────────────────────────────────────────────

-- Publish the full (trimmed) value of the cell under the cursor to vim.g.dbout_cell
-- so the lualine statusline component can display it. Clears when not on a cell.
local function set_status(bufnr)
  local winid  = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row_0  = cursor[1] - 1
  local col_0  = cursor[2]

  local cols = cols_map[bufnr] and cols_map[bufnr][row_0]
  local line = vim.api.nvim_buf_get_lines(bufnr, row_0, row_0 + 1, false)[1] or ""

  local value = ""
  if cols and not line:match("^%-%-%-") then
    for _, col in ipairs(cols) do
      if col_0 >= col.from and col_0 <= col.to then
        local ce   = math.min(col.to, #line - 1)
        local cell = line:sub(col.from + 1, ce + 1)
        value = vim.trim(cell)
        break
      end
    end
  end

  if vim.g.dbout_cell ~= value then
    vim.g.dbout_cell = value
    pcall(function() require("lualine").refresh() end)
  end
end

local function clear_status()
  if vim.g.dbout_cell ~= nil and vim.g.dbout_cell ~= "" then
    vim.g.dbout_cell = ""
    pcall(function() require("lualine").refresh() end)
  end
end

-- Dispatch to the configured reveal mechanism.
local function reveal(bufnr)
  if REVEAL_MODE == "float" then
    show_float(bufnr)
  else
    set_status(bufnr)
  end
end

-- Toggle expand/collapse of the column under the cursor. Columns are compact by
-- default (fitted to the longest data value, capped at the limit); expanding lifts
-- the cap and widens to show the full value AND the full header.
local function toggle_column(bufnr)
  local winid  = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row_0  = cursor[1] - 1
  local col_0  = cursor[2]

  local cols = cols_map[bufnr] and cols_map[bufnr][row_0]
  if not cols then return end

  local target
  for _, col in ipairs(cols) do
    if col_0 >= col.from and col_0 <= col.to then
      target = col
      break
    end
  end
  if not target then return end

  expanded_cols[bufnr] = expanded_cols[bufnr] or {}
  if expanded_cols[bufnr][target.from] then
    expanded_cols[bufnr][target.from] = nil
  else
    expanded_cols[bufnr][target.from] = true
  end

  apply_truncation(bufnr)
  -- Park the cursor at the column start so it isn't stranded inside a region
  -- that just became concealed.
  pcall(vim.api.nvim_win_set_cursor, winid, { row_0 + 1, target.from })
  prev_cursor[bufnr] = { row_0 = row_0, col_0 = target.from }
  reveal(bufnr)
end

-- If the cursor is sitting inside a concealed range, slide it to the last visible
-- char before that range (used after a live truncation-limit change).
local function nudge_cursor_out(bufnr)
  local winid  = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row_0  = cursor[1] - 1
  local cs     = concealed_range_at(bufnr, row_0, cursor[2])
  if cs then
    local new_col = math.max(0, cs - 1)
    pcall(vim.api.nvim_win_set_cursor, winid, { row_0 + 1, new_col })
    prev_cursor[bufnr] = { row_0 = row_0, col_0 = new_col }
  end
  reveal(bufnr)
end

-- Change the truncation limit live. `spec` may be a number, a numeric string, or a
-- relative "+N" / "-N" string. Persists in vim.g.dbout_truncate_at for all dbout buffers.
local function set_truncate(bufnr, spec)
  local n
  if type(spec) == "number" then
    n = spec
  elseif type(spec) == "string" then
    spec = vim.trim(spec)
    local sign = spec:sub(1, 1)
    if sign == "+" or sign == "-" then
      local d = tonumber(spec:sub(2))
      if d then n = trunc_at() + (sign == "+" and d or -d) end
    else
      n = tonumber(spec)
    end
  end
  if not n then
    vim.notify("DBoutTruncate: invalid value '" .. tostring(spec) .. "'", vim.log.levels.WARN)
    return
  end
  n = math.max(1, math.floor(n))
  vim.g.dbout_truncate_at = n
  apply_truncation(bufnr)
  nudge_cursor_out(bufnr)
  vim.notify("dbout truncate limit = " .. n)
end

local function prompt_truncate(bufnr)
  vim.ui.input(
    { prompt = "Truncate at (n, +n, -n): ", default = tostring(trunc_at()) },
    function(input)
      if input and vim.trim(input) ~= "" then set_truncate(bufnr, input) end
    end
  )
end

local bufnr = vim.api.nvim_get_current_buf()
vim.opt_local.conceallevel  = 2
-- "n" keeps the cursor line concealed in normal mode → lines don't expand/jump
-- when the cursor moves between rows.  We manually skip the cursor past concealed
-- regions in the CursorMoved handler below.
vim.opt_local.concealcursor = "n"

if not vim.b.dbout_truncate_init then
  vim.b.dbout_truncate_init = true

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = function()
      -- Guard: this callback fires once more after our own set_cursor call.
      -- On that re-entry just update the float and return.
      if in_jump[bufnr] then
        in_jump[bufnr] = false
        reveal(bufnr)
        return
      end

      local winid  = vim.api.nvim_get_current_win()
      local cursor = vim.api.nvim_win_get_cursor(winid)
      local row_0  = cursor[1] - 1
      local col_0  = cursor[2]

      -- Check whether the cursor landed inside a concealed range.
      local cs, ce = concealed_range_at(bufnr, row_0, col_0)
      if cs then
        local prev    = prev_cursor[bufnr]
        local new_col

        if prev and prev.row_0 == row_0 and prev.col_0 < cs then
          -- Moving right into concealment → jump to first char after it
          new_col = ce + 1
        elseif prev and prev.row_0 == row_0 and prev.col_0 > ce then
          -- Moving left into concealment → jump to last char before it
          new_col = cs - 1
        else
          -- Arrived from a different row (vertical movement) → skip right
          new_col = ce + 1
        end

        -- Clamp to valid range; if past end-of-line, fall back to left boundary
        local line    = vim.api.nvim_buf_get_lines(bufnr, row_0, row_0 + 1, false)[1] or ""
        local max_col = math.max(0, #line - 1)
        if new_col > max_col then
          new_col = math.max(0, cs - 1)  -- can't go right; go to last visible char before conceal
        end
        new_col = math.max(0, math.min(new_col, max_col))

        prev_cursor[bufnr] = { row_0 = row_0, col_0 = new_col }
        in_jump[bufnr]     = true
        vim.api.nvim_win_set_cursor(winid, { row_0 + 1, new_col })
        -- show_float will be called by the re-entry above after the jump fires
        return
      end

      prev_cursor[bufnr] = { row_0 = row_0, col_0 = col_0 }
      reveal(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer = bufnr,
    callback = function()
      close_float()
      clear_status()
      last_hover[vim.api.nvim_get_current_win()] = nil
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    buffer = bufnr,
    callback = function()
      vim.schedule(function() apply_truncation(bufnr) end)
    end,
  })

  -- Catch async result delivery from dadbod-ui
  if not _G._dbout_query_post_registered then
    _G._dbout_query_post_registered = true
    vim.api.nvim_create_autocmd("User", {
      pattern = "DBQueryPost",
      callback = function()
        local cbuf = vim.api.nvim_get_current_buf()
        if vim.bo[cbuf].filetype == "dbout" then
          vim.schedule(function() apply_truncation(cbuf) end)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer   = bufnr,
    once     = true,
    callback = function()
      cell_map[bufnr]      = nil
      cols_map[bufnr]      = nil
      conceal_map[bufnr]        = nil
      expanded_cols[bufnr] = nil
      prev_cursor[bufnr]   = nil
      in_jump[bufnr]       = nil
    end,
  })

  vim.keymap.set("n", TOGGLE_KEY, function() toggle_column(bufnr) end, {
    buffer = bufnr,
    silent = true,
    desc   = "dbout: expand/collapse current column",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "DBoutToggleColumn", function()
    toggle_column(bufnr)
  end, { desc = "Expand/collapse the dbout column under the cursor" })

  vim.keymap.set("n", LIMIT_KEY, function() prompt_truncate(bufnr) end, {
    buffer = bufnr,
    silent = true,
    desc   = "dbout: set truncation limit",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "DBoutTruncate", function(opts)
    if opts.args == "" then
      prompt_truncate(bufnr)
    else
      set_truncate(bufnr, opts.args)
    end
  end, {
    nargs    = "?",
    complete = function() return { "10", "15", "20", "25", "30", "35", "40", "50", "+5", "-5" } end,
    desc     = "Set dbout truncation limit (absolute N, or relative +N / -N)",
  })
end

vim.schedule(function() apply_truncation(bufnr) end)
