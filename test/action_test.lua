local root = assert(os.getenv("PWD"))
local actions, layer = {}, nil
rex = {
  action = function(action) actions[action.name] = action end,
  layout = { block = function(spec) return spec end },
  session = {
    new_layer = function(spec)
      layer = spec
      return {}
    end,
  },
}
local module = dofile(root .. "/rex-agent-relay/init.lua")
module.setup({ key = false })
actions.agent_relay.run({ block_id = "block:source" })
local command = layer.layout.options.command
assert(command[1] == "/bin/sh" and command[3]:find('"${REX_BIN_DIR:', 1, true))
assert(command[5] == root .. "/rex-agent-relay/relay.lua")
assert(command[6] == "source=block:source" and command[7] == "mode=send")
assert(command[8] == "finder=fzf")
assert(command[11] == "editor_key=ctrl+g" and command[12] == "pager_key=ctrl+o")
module.setup({
  key = false,
  finder = "fzf --reverse",
  editor = "code --wait",
  pager = "less -R",
  editor_key = "ctrl+a",
  pager_key = "ctrl+b",
})
actions.agent_relay.run({ block_id = "block:source" })
command = layer.layout.options.command
assert(command[8] == "finder=fzf --reverse" and command[9] == "editor=code --wait")
assert(command[10] == "pager=less -R" and command[11] == "editor_key=ctrl+a" and command[12] == "pager_key=ctrl+b")
for _, name in ipairs({
  "ctrl+c",
  "ctrl+d",
  "ctrl+u",
  "ctrl+w",
  "ctrl+m",
  "ctrl+j",
  "ctrl+i",
  "ctrl+h",
  "ctrl+1",
  "Ctrl+g",
}) do
  assert(not pcall(module.setup, { key = false, editor_key = name }))
  assert(not pcall(module.setup, { key = false, pager_key = name }))
end
assert(not pcall(module.setup, { key = false, editor_key = "ctrl+g", pager_key = "ctrl+g" }))
assert(not pcall(module.setup, { key = false, finder = false }))
print("action tests passed")
