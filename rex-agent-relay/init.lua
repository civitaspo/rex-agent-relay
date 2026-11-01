local M = {}
local dir = debug.getinfo(1, "S").source:match("^@?(.*)/[^/]*$") or "."
local function open(ctx, mode)
  local _, err = rex.session.new_layer{
    bounds = {0.15, 0.30, 0.70, 0.40}, focus = true,
    layout = rex.layout.block{flavor = "com.superlogical.terminal.shell", options = {command = {"/bin/sh", "-c", 'exec "${REX_BIN_DIR:?REX_BIN_DIR is not set}/rex" do "$@"', "rex-agent-relay", dir .. "/relay.lua", "source=" .. ctx.block_id, "mode=" .. mode}}},
  }
  if err then error(err, 0) end
end
function M.setup(opts)
  opts = opts or {}
  rex.action{name="agent_relay", title="Agent Relay: Send", category="Agent Relay", run=function(ctx) open(ctx, "send") end}
  rex.action{name="agent_relay_pair", title="Agent Relay: Change Pair", category="Agent Relay", run=function(ctx) open(ctx, "pair") end}
  if opts.key ~= false then rex.bind(opts.key or "cmd+shift+r", "agent_relay") end
end
return M
