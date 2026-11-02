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
state = prompt.transition(state, { type = "paste", text = "a\nb" })
assert(state.text == "日a b")
local result
state, result = prompt.transition(state, { type = "submit" })
assert(result.action == "submit" and result.text == "日a b")
state = { mode = "review", text = "note\ntext" }
state, result = prompt.transition(state, { type = "escape" })
assert(state.mode == "discard_armed" and not result)
state, result = prompt.transition(state, { type = "escape" })
assert(result.action == "cancel")
print("prompt tests passed")
