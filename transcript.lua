local M = {}

local function display_path(path, cwd)
  if cwd and path:sub(1, #cwd + 1) == cwd .. "/" then return path:sub(#cwd + 2) end
  local home = os.getenv("HOME")
  if home and (path == home or path:sub(1, #home + 1) == home .. "/") then
    return "~" .. path:sub(#home + 1)
  end
  return path
end
M.display_path = display_path

function M.read(path, offset, limit)
  local f, err = io.open(path, "rb")
  if not f then
    if offset == 0 and (limit == nil or limit == 0) and err:lower():find("no such file or directory", 1, true) then return {}, 0 end
    error(err, 0)
  end
  local size = f:seek("end")
  if offset > size or (limit and (limit < offset or limit > size)) then
    f:close(); error("invalid relay point or until", 0)
  end
  f:seek("set", offset)
  local lines, ending = {}, offset
  while true do
    local line = f:read("*l")
    if not line then break end
    local pos = f:seek()
    f:seek("set", pos - 1)
    local last = f:read(1)
    if last ~= "\n" or (limit and pos > limit) then break end
    lines[#lines + 1], ending = line, pos
  end
  f:close()
  if limit and ending ~= limit then error("until is not a complete line boundary", 0) end
  return lines, ending
end

function M.parse(kind, lines)
  local result = { messages = {}, files = {} }
  local pending, pending_seen, all_seen = {}, {}, {}
  local function flush()
    if #pending > 0 then
      result.messages[#result.messages + 1] = { refs = pending }
      pending, pending_seen = {}, {}
    end
  end
  local function message(speaker, text)
    if not text or text == "" then return end
    local tag, note
    if text:match("^<agent%-relay[%s>]") then tag, note = text:match("^<agent%-relay([^>]*)>.*</agent%-relay>%s*(.*)$") end
    if speaker == "user" and tag then
      text = note
      if text == "" then return end
      speaker = tag:match('by="human"') and "user (relayed note)" or "agent (relayed note)"
    end
    if speaker == "user" or speaker:find("relayed note", 1, true) then flush() end
    local last = result.messages[#result.messages]
    if last and last.speaker == speaker then last.text = last.text .. "\n" .. text
    else result.messages[#result.messages + 1] = { speaker = speaker, text = text } end
  end
  local function file(path, op, to)
    if type(path) ~= "string" then return end
    local item = { path = path, op = op, to = to }
    if not pending_seen[path] then pending[#pending + 1] = item; pending_seen[path] = true end
    if not all_seen[path] then result.files[#result.files + 1] = item; all_seen[path] = true end
  end
  for _, line in ipairs(lines) do
    local ok, row = pcall(rex.json.decode, line)
    if not ok or type(row) ~= "table" then error("invalid transcript JSON", 0) end
    if kind == "claude" and not row.isSidechain and not row.isMeta then
      if row.cwd then result.latest_cwd = row.cwd end
      local content = row.message and row.message.content
      if row.type == "user" or row.type == "assistant" then
        local speaker = row.type == "user" and "user" or "claude"
        local function claude_message(text)
          if speaker == "user" and text and (text:match("^<command%-name>") or text:match("^<command%-message>") or text:match("^<local%-command%-") or text:match("^<system%-reminder>") or text:match("^<task%-notification>") or text:match("^<bash%-")) then return end
          message(speaker, text)
        end
        if type(content) == "string" then
          claude_message(content)
        elseif type(content) == "table" then
          for _, part in ipairs(content) do
            if part.type == "text" then claude_message(part.text)
            elseif part.type == "image" and speaker == "user" then message(speaker, "[image]")
            elseif part.type == "tool_use" and speaker == "claude" then
              local input = part.input or {}
              if part.name == "Write" then file(input.file_path, "wrote")
              elseif part.name == "Edit" or part.name == "MultiEdit" then file(input.file_path, "edited")
              elseif part.name == "NotebookEdit" then file(input.notebook_path, "edited") end
            end
          end
        end
      end
    elseif kind == "codex" then
      local payload = row.payload or {}
      if (row.type == "turn_context" or row.type == "session_meta") and payload.cwd then result.latest_cwd = payload.cwd end
      local item = row.type == "event_msg" and payload.type == "item_completed" and payload.item
      if item and (item.type == "UserMessage" or item.type == "AgentMessage") then
        local texts = {}
        for _, part in ipairs(item.content or {}) do
          if part.text then texts[#texts + 1] = part.text elseif part.type == "image" then texts[#texts + 1] = "[image]" end
        end
        message(item.type == "UserMessage" and "user" or "codex", table.concat(texts, "\n"))
      elseif item and item.type == "FileChange" then
        local paths = {}; for path in pairs(item.changes or {}) do paths[#paths + 1] = path end; table.sort(paths)
        for _, path in ipairs(paths) do
          local change = item.changes[path]
          local op = ({ update = "edited", add = "added", delete = "deleted" })[change.type]
          if change.move_path then file(path, "moved", change.move_path) elseif op then file(path, op) end
        end
      end
    end
  end
  flush()
  return result
end

function M.refs(files, cwd)
  local groups, order = {}, {}
  for _, item in ipairs(files) do
    if not groups[item.op] then groups[item.op] = {}; order[#order + 1] = item.op end
    local path = display_path(item.path, cwd)
    if item.to then path = path .. " -> " .. display_path(item.to, cwd) end
    groups[item.op][#groups[item.op] + 1] = path
  end
  local parts = {}
  for _, op in ipairs(order) do parts[#parts + 1] = op .. " " .. table.concat(groups[op], ", ") end
  return #parts > 0 and "[refs: " .. table.concat(parts, "; ") .. "]" or ""
end

function M.conversation(parsed, cwd)
  local parts = {}
  for _, item in ipairs(parsed.messages) do
    parts[#parts + 1] = item.refs and M.refs(item.refs, cwd) or item.speaker .. ": " .. item.text
  end
  return table.concat(parts, "\n\n")
end

local function attr(value)
  return tostring(value):gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
function M.body(kind, by, cwd, conversation, note, file, refs)
  local tag = '<agent-relay from="' .. attr(kind) .. '" by="' .. attr(by) .. '" cwd="' .. attr(display_path(cwd, nil)) .. '"'
  if file then tag = tag .. ' file="' .. attr(display_path(file, nil)) .. '"' end
  local content = conversation
  if file then
    content = "The conversation is too long to paste. Read the file above before following the note."
    if refs ~= "" then content = content .. "\n\n" .. refs end
  end
  local body = tag .. ">\n" .. content .. "\n</agent-relay>"
  if note ~= "" then body = body .. "\n\n" .. note end
  return body
end
return M
