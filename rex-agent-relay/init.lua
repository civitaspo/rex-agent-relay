local M = {}
local dir = debug.getinfo(1, "S").source:match("^@?(.*)/[^/]*$") or "."
local function key(name, field)
  if type(name) ~= "string" or not name:match("^ctrl%+[a-z]$") then
    error("invalid " .. field .. ": expected ctrl+<letter>", 0)
  end
  local byte = string.byte(name:sub(-1):upper()) - 64
  if byte == 3 or byte == 4 or byte == 8 or byte == 9 or byte == 10 or byte == 13 or byte == 21 or byte == 23 then
    error("reserved " .. field, 0)
  end
  return name, byte
end
local function open(ctx, mode, config)
  local command = {
    "/bin/sh",
    "-c",
    'saved=$(/bin/stty -g </dev/tty) || exit 1; trap \'/bin/stty "$saved" </dev/tty\' EXIT HUP INT TERM; "${REX_BIN_DIR:?REX_BIN_DIR is not set}/rex" do "$@"',
    "rex-agent-relay",
    dir .. "/relay.lua",
    "source=" .. ctx.block_id,
    "mode=" .. mode,
    "finder=" .. config.finder,
    "editor_key=" .. config.editor_key,
    "pager_key=" .. config.pager_key,
  }
  if config.editor then command[#command + 1] = "editor=" .. config.editor end
  if config.pager then command[#command + 1] = "pager=" .. config.pager end
  local _, err = rex.session.new_layer({
    bounds = { 0.05, 0.05, 0.90, 0.90 },
    focus = true,
    layout = rex.layout.block({
      flavor = "com.superlogical.terminal.shell",
      options = {
        command = command,
      },
    }),
  })
  if err then error(err, 0) end
end
function M.setup(opts)
  opts = opts or {}
  local config = {}
  for field, fallback in pairs({
    finder = "fzf",
    editor_key = "ctrl+g",
    pager_key = "ctrl+o",
  }) do
    local value = opts[field]
    if value == nil then value = fallback end
    if type(value) ~= "string" or value == "" then error("invalid " .. field, 0) end
    config[field] = value
  end
  for _, field in ipairs({ "editor", "pager" }) do
    local value = opts[field]
    if value ~= nil and (type(value) ~= "string" or value == "") then error("invalid " .. field, 0) end
    config[field] = value
  end
  local _, ek = key(config.editor_key, "editor_key")
  local _, pk = key(config.pager_key, "pager_key")
  if ek == pk then error("editor_key and pager_key must differ", 0) end
  rex.action({
    name = "agent_relay",
    title = "Agent Relay: Send",
    category = "Agent Relay",
    run = function(ctx) open(ctx, "send", config) end,
  })
  rex.action({
    name = "agent_relay_pair",
    title = "Agent Relay: Change Pair",
    category = "Agent Relay",
    run = function(ctx) open(ctx, "pair", config) end,
  })
  if opts.key ~= false then rex.bind(opts.key or "cmd+shift+r", "agent_relay") end
end
return M
