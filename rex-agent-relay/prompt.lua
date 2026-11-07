local M = {}
local view = require("view")
local controls = {
  [127] = "backspace",
  [8] = "backspace",
  [21] = "kill_line",
  [23] = "kill_word",
  [13] = "submit",
  [10] = "submit",
  [3] = "interrupt",
  [4] = "interrupt",
}

function M.control(key) return assert(key:match("^ctrl%+([a-z])$")):byte() - 96 end

function M.decoder(keys)
  local buffer, paste = "", nil
  return function(byte)
    if byte then buffer = buffer .. byte end
    local events = {}
    while #buffer > 0 do
      if paste then
        local stop = buffer:find("\27[201~", 1, true)
        if not stop then break end
        events[#events + 1] = { type = "paste", text = buffer:sub(1, stop - 1) }
        buffer, paste = buffer:sub(stop + 6), nil
      elseif buffer:byte(1) == 27 then
        if #buffer == 1 then
          if not byte then
            events[#events + 1] = { type = "escape" }
            buffer = ""
          end
          break
        elseif buffer:sub(2, 2) == "[" then
          local finish = buffer:find("[@-~]", 3)
          if not finish then
            if not byte then buffer = "" end
            break
          end
          local sequence = buffer:sub(1, finish)
          buffer = buffer:sub(finish + 1)
          if sequence == "\27[200~" then paste = true end
        else
          buffer = buffer:sub(3)
        end
      else
        local b = buffer:byte(1)
        local kind = controls[b]
        for name, code in pairs(keys or {}) do
          if b == code then kind = name end
        end
        if kind then
          events[#events + 1] = { type = kind }
          buffer = buffer:sub(2)
        elseif b >= 32 and b ~= 127 then
          local size = b < 128 and 1 or b < 224 and 2 or b < 240 and 3 or 4
          if #buffer < size then break end
          events[#events + 1] = { type = "char", text = buffer:sub(1, size) }
          buffer = buffer:sub(size + 1)
        else
          buffer = buffer:sub(2)
        end
      end
    end
    return events
  end
end

function M.transition(state, event)
  local kind = event.type
  if kind == "interrupt" then return state, { action = "cancel" } end
  if kind == "escape" then
    if state.mode == "input" or state.mode == "discard_armed" then return state, { action = "cancel" } end
    state.mode = "discard_armed"
  elseif kind == "submit" then
    return state, { action = "submit", text = state.text }
  elseif kind == "open_editor" or kind == "open_pager" then
    return state, { action = kind }
  elseif state.mode == "input" then
    if kind == "paste" and event.text:find("[\r\n]") then
      return state, { action = "open_editor", text = state.text .. event.text }
    elseif kind == "char" or kind == "paste" then
      state.text = state.text .. event.text
    elseif kind == "backspace" then
      local updated, count = state.text:gsub("[\194-\244][\128-\191]*$", "", 1)
      state.text = count > 0 and updated or state.text:sub(1, -2)
    elseif kind == "kill_line" then
      state.text = ""
    elseif kind == "kill_word" then
      state.text = state.text:gsub("%s*%S+%s*$", "")
    end
  elseif state.mode == "discard_armed" then
    state.mode = "review"
  end
  return state
end

local function command(args)
  local result, err = rex.exec(args)
  if not result or not result.ok then error(tostring(err or (result and result.stderr) or "command failed"), 0) end
  return result.stdout or ""
end

function M.wait_close()
  local old = command({ "sh", "-c", "/bin/stty -g </dev/tty" }):match("%S+")
  assert(old, "cannot read terminal settings")
  local ok, err = pcall(function()
    command({ "sh", "-c", "/bin/stty -echo -icanon min 1 time 0 </dev/tty" })
    while true do
      local byte = io.read(1)
      if not byte or byte == "\27" or byte == "\r" or byte == "\n" then break end
    end
  end)
  local restored, restore_err = pcall(command, { "sh", "-c", '/bin/stty "$1" </dev/tty', "sh", old })
  if not ok then error(err, 0) end
  if not restored then error(restore_err, 0) end
end

local function gum_available()
  local result = rex.exec({ "sh", "-c", "command -v gum >/dev/null 2>&1" })
  if not result then error("cannot check for gum", 0) end
  if result.ok then return true end
  if result.code == 1 then return false end
  error("gum availability check failed with status " .. tostring(result.code), 0)
end

local function gum_input(opts)
  if opts.conversation ~= "" then
    local result, err = rex.exec({ "sh", "-c", "gum pager >/dev/tty 2>/dev/tty", "sh" }, {
      stdin = view.display(opts.header)
        .. "\n\nClose the pager to write a note. Ctrl+C cancels the relay.\n\n"
        .. view.display(opts.conversation),
    })
    if not result then error(tostring(err or "gum pager failed to launch"), 0) end
    if result.code == 130 then return { action = "cancel" } end
    if not result.ok then
      error(
        tostring(
          err or result.stderr ~= "" and result.stderr or ("gum pager failed with status " .. tostring(result.code))
        ),
        0
      )
    end
  end
  local result, err = rex.exec({
    "sh",
    "-c",
    'gum write --char-limit=0 --header "$1" </dev/tty 2>/dev/tty',
    "sh",
    view.display(opts.header) .. "\nEnter sends. Esc cancels.",
  })
  if not result then error(tostring(err or "gum write failed"), 0) end
  if result.code == 1 or result.code == 130 then return { action = "cancel" } end
  if not result.ok then
    error(
      tostring(
        err or result.stderr ~= "" and result.stderr or ("gum write failed with status " .. tostring(result.code))
      ),
      0
    )
  end
  return { action = "submit", text = (result.stdout or ""):gsub("\n$", "") }
end

function M.run(opts)
  local old = command({ "sh", "-c", "/bin/stty -g </dev/tty" }):match("%S+")
  assert(old, "cannot read terminal settings")
  local function raw() command({ "sh", "-c", "/bin/stty -echo -icanon -isig -iexten -ixon min 0 time 1 </dev/tty" }) end
  local function restore() command({ "sh", "-c", '/bin/stty "$1" </dev/tty', "sh", old }) end
  local state = { mode = "input", text = "" }
  local decode = M.decoder(opts.keys)
  local ok, result = xpcall(function()
    if gum_available() then return gum_input(opts) end
    raw()
    io.write("\27[?2004h")
    io.flush()
    local dirty, idle = true, 0
    while true do
      if dirty then
        opts.render(state)
        dirty = false
      end
      local byte = io.read(1)
      if byte then
        idle = 0
      else
        idle = idle + 1
        if idle >= 10 then
          idle = 0
          if opts.size_changed and opts.size_changed() then dirty = true end
        end
      end
      for _, event in ipairs(decode(byte)) do
        dirty = true
        local action
        state, action = M.transition(state, event)
        if action and (action.action == "submit" or action.action == "cancel") then return action end
        if action then
          local editor = action.action == "open_editor"
          local path =
            command({ "mktemp", (os.getenv("TMPDIR") or "/tmp") .. "/rex-agent-relay.XXXXXXXX" }):match("[^\n]+")
          local file = assert(io.open(path, "wb"))
          assert(file:write(editor and (action.text or state.text) or opts.conversation))
          assert(file:close())
          io.write("\27[?2004l\27[?25h")
          io.flush()
          restore()
          local child, child_err =
            rex.exec({ "sh", "-c", (editor and opts.editor or opts.pager) .. ' "$1" </dev/tty >/dev/tty', "sh", path })
          if editor and child and child.ok then
            local f = assert(io.open(path, "rb"))
            state.text = assert(f:read("*a")):gsub("\n$", "")
            f:close()
            state.mode = "review"
          end
          os.remove(path)
          if not child or (not child.ok and (not editor or child.code == 127)) then
            error(tostring(child_err or (child and child.stderr) or "command failed"), 0)
          end
          raw()
          io.write("\27[?2004h")
          io.flush()
        end
      end
    end
  end, debug.traceback)
  io.write("\27[?2004l\27[?25h")
  io.flush()
  local restored, err = pcall(restore)
  if not ok then error(result, 0) end
  if not restored then error(err, 0) end
  return result
end
return M
