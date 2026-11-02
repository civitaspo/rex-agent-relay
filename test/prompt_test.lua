package.path = "./rex-agent-relay/?.lua;" .. package.path
local prompt = require("prompt")
local decode = prompt.decoder({ open_editor = prompt.control("ctrl+g"), open_pager = prompt.control("ctrl+o") })
local events = {}
local function feed(text)
  for i = 1, #text do
    for _, event in ipairs(decode(text:sub(i, i))) do
      events[#events + 1] = event
    end
  end
end
feed("a\27[A\27[200~hello\nworld\27[201~\7")
assert(
  #events == 3
    and events[1].text == "a"
    and events[2].type == "paste"
    and events[2].text == "hello\nworld"
    and events[3].type == "open_editor"
)
feed("\27")
assert(#decode(nil) == 1)
local state = { mode = "input", text = "" }
state = prompt.transition(state, { type = "char", text = "日本" })
state = prompt.transition(state, { type = "backspace" })
assert(state.text == "日")
local result
state, result = prompt.transition(state, { type = "paste", text = "a\nb" })
assert(state.text == "日" and result.action == "open_editor" and result.text == "日a\nb")
state = prompt.transition(state, { type = "paste", text = "ab" })
state, result = prompt.transition(state, { type = "submit" })
assert(result.action == "submit" and result.text == "日ab")
state = { mode = "review", text = "note\ntext" }
state, result = prompt.transition(state, { type = "escape" })
assert(state.mode == "discard_armed" and not result)
state, result = prompt.transition(state, { type = "escape" })
assert(result.action == "cancel")
local test_io = io
local real_exec, real_read, real_write, real_flush = rex.exec, io.read, io.write, io.flush
local bytes = { "x", "\7", "\r" }
local temp_path = os.getenv("TMPDIR") or "/tmp"
temp_path = temp_path .. "/rex-prompt-test"
rex.exec = function(args)
  if args[1] == "mktemp" then return { ok = true, stdout = temp_path .. "\n" } end
  if args[1] == "sh" and args[3]:find("fake%-editor") then
    local f = assert(io.open(temp_path, "wb"))
    f:write("discarded")
    f:close()
    return { ok = false, code = 1, stderr = "" }
  end
  return { ok = true, stdout = "settings\n" }
end
test_io.read = function() return table.remove(bytes, 1) end
test_io.write, test_io.flush = function() end, function() end
local submitted = prompt.run({ editor = "fake-editor", keys = { open_editor = 7 }, render = function() end })
rex.exec, test_io.read, test_io.write, test_io.flush = real_exec, real_read, real_write, real_flush
assert(submitted.action == "submit" and submitted.text == "x")

print("prompt tests passed")
