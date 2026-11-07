local M = {}

function M.display(text) return (tostring(text or ""):gsub("[%z\1-\8\11-\31\127]", "?")) end

local function width(text)
  -- shortcut: common Unicode widths; use grapheme-aware terminal widths for complex emoji sequences.
  local columns, i = 0, 1
  while i <= #text do
    local b = text:byte(i)
    local size = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
    local cp = b % (size == 1 and 128 or size == 2 and 32 or size == 3 and 16 or 8)
    for j = 2, size do
      cp = cp * 64 + (text:byte(i + j - 1) or 128) - 128
    end
    local combining = (cp >= 0x300 and cp <= 0x36f) or (cp >= 0xfe00 and cp <= 0xfe0f) or cp == 0x200d
    local wide = cp >= 0x1100
      and (
        cp <= 0x115f
        or cp == 0x2329
        or cp == 0x232a
        or (cp >= 0x2e80 and cp <= 0xa4cf and cp ~= 0x303f)
        or (cp >= 0xac00 and cp <= 0xd7a3)
        or (cp >= 0xf900 and cp <= 0xfaff)
        or (cp >= 0xfe10 and cp <= 0xfe19)
        or (cp >= 0xfe30 and cp <= 0xfe6f)
        or (cp >= 0xff00 and cp <= 0xff60)
        or (cp >= 0xffe0 and cp <= 0xffe6)
        or (cp >= 0x1f300 and cp <= 0x1faff)
        or (cp >= 0x20000 and cp <= 0x3fffd)
      )
    columns = columns + (combining and 0 or wide and 2 or 1)
    i = i + size
  end
  return columns
end

local function wrap(text, cols)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local row, used = "", 0
    for i = 1, #line do
      local b = line:byte(i)
      if b < 128 or b >= 192 then
        local ch = line:sub(i, i + (b < 128 and 0 or b < 224 and 1 or b < 240 and 2 or 3))
        if ch == "\t" then
          local spaces = 8 - used % 8
          for _ = 1, spaces do
            if used == cols then
              out[#out + 1] = row
              row, used = "", 0
            end
            row, used = row .. " ", used + 1
          end
          ch = ""
        end
        local w = width(ch)
        if used + w > cols and row ~= "" then
          out[#out + 1] = row
          row, used = "", 0
        end
        row, used = row .. ch, used + w
      end
    end
    out[#out + 1] = row
  end
  return out
end

function M.render(model, cols, rows)
  local lines = {}
  local function add(text)
    text = M.display(text)
    for _, line in ipairs(wrap(text, math.max(1, cols))) do
      lines[#lines + 1] = line
    end
  end
  add("From: " .. (model.source or "new source"))
  add("To: " .. (model.target or "new target") .. "  " .. tostring(model.count or 0))
  local header_rows = #lines
  add("")
  local conversation_start = #lines + 1
  add(model.conversation and model.conversation ~= "" and model.conversation or "No new conversation since last relay")
  for i = conversation_start, #lines do
    for _, speaker in ipairs({ "user", "claude", "codex", "user (relayed note)", "agent (relayed note)" }) do
      local prefix = speaker .. ":"
      if lines[i]:sub(1, #prefix) == prefix then
        lines[i] = "\27[36m" .. prefix .. "\27[0m" .. lines[i]:sub(#prefix + 1)
        break
      end
    end
  end
  add("")
  local note_width = math.max(1, cols)
  local lead = math.min(3, note_width)
  local title = ("[note]"):sub(1, note_width - lead)
  lines[#lines + 1] = string.rep("─", lead) .. title .. string.rep("─", note_width - lead - #title)
  if model.state == "discard_armed" then add("Press Esc again to discard the note.") end
  add(model.input or "")
  local input_row = #lines
  local input_col = width(lines[input_row]) + 1
  lines[#lines + 1] = string.rep("─", note_width)
  add(model.help or "Enter send · Esc cancel")
  local hidden = math.max(0, #lines - rows)
  local visible, cursor = {}, nil
  local first = hidden + 1
  local kept = 0
  if hidden > 0 and rows > header_rows + 1 then
    kept = header_rows
    first = #lines - (rows - kept - 1) + 1
    hidden = first - kept - 1
    for i = 1, kept do
      visible[#visible + 1] = lines[i]
    end
    visible[#visible + 1] = ("(" .. hidden .. " hidden; " .. (model.pager_key or "ctrl+o") .. " pager)"):sub(1, cols)
  end
  for i = first, #lines do
    visible[#visible + 1] = lines[i]
    if i == input_row and (model.state == nil or model.state == "input") then
      cursor = { row = #visible, col = input_col }
    end
  end
  return visible, hidden, cursor
end

return M
