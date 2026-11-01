local root = assert(os.getenv("PWD"))
local actions, layer = {}, nil
rex = {
  action = function(action) actions[action.name] = action end,
  layout = {block = function(spec) return spec end},
  session = {new_layer = function(spec) layer = spec; return {} end},
}
local module = dofile(root .. "/rex-agent-relay/init.lua")
module.setup{key=false}
actions.agent_relay.run{block_id="block:source"}
local command = layer.layout.options.command
assert(command[1] == "/bin/sh" and command[3]:find('"${REX_BIN_DIR:', 1, true))
assert(command[5] == root .. "/rex-agent-relay/relay.lua")
assert(command[6] == "source=block:source" and command[7] == "mode=send")
print("action tests passed")
