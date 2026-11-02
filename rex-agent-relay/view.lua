local M = {}

local function width(text)
  -- shortcut: UTF-8 length approximates display width; use wcwidth if alignment matters for other scripts.
  local columns = 0
  local i = 1
  while i <= #text do
    local byte = text:byte(i)
    local size = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
    columns = columns + (size >= 3 and 2 or 1)
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
    text = tostring(text or ""):gsub("[%z\1-\8\11-\31\127]", "?")
    for _, line in ipairs(wrap(text, math.max(1, cols))) do
      lines[#lines + 1] = line
    end
  end
  add("From: " .. (model.source or "new source"))
  add("To: " .. (model.target or "new target") .. "  " .. tostring(model.count or 0))
  add("")
  add(model.conversation or "No conversation")
  add("")
  local note_width = math.max(1, cols)
  local lead = math.min(3, note_width)
  local title = ("[note]"):sub(1, note_width - lead)
  lines[#lines + 1] = string.rep("─", lead) .. title .. string.rep("─", note_width - lead - #title)
  if model.state == "discard_armed" then add("Press Esc again to discard the note.") end
  add(((model.state == nil or model.state == "input") and "note> " or "") .. (model.input or ""))
  lines[#lines + 1] = string.rep("─", note_width)
  add(model.help or "Enter send · Esc cancel")
  local hidden = math.max(0, #lines - rows)
  local visible = {}
  if hidden > 0 and rows > 2 then
    hidden = hidden + 1
    visible[1] = lines[1]
    visible[2] = "(" .. hidden .. " lines hidden)"
    for i = #lines - rows + 3, #lines do
      visible[#visible + 1] = lines[i]
    end
  else
    for i = hidden + 1, #lines do
      visible[#visible + 1] = lines[i]
    end
  end
  return visible, hidden
end

return M
