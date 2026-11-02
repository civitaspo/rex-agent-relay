package.path = "./rex-agent-relay/?.lua;" .. package.path
local view = require("view")
local lines, hidden =
  view.render({ source = "A", target = "B", count = 2, conversation = "abc", input = "note", help = "help" }, 80, 20)
assert(hidden == 0)
assert(
  table.concat(lines, "\n")
    == "From: A\nTo: B  2\n\nabc\n\n---[note]"
      .. string.rep("-", 71)
      .. "\nnote> note\n"
      .. string.rep("-", 80)
      .. "\nhelp"
)
local review = view.render({ state = "review", input = "first\nsecond" }, 15, 30)
assert(table.concat(review, "\n"):find("---[note]------\nfirst\nsecond\n---------------", 1, true))
local narrow = view.render({ state = "input", input = "x" }, 4, 30)
assert(table.concat(narrow, "\n"):find("---[\n", 1, true))
local short, omitted =
  view.render({ source = "A", target = "B", conversation = "こんにちは", input = "", help = "help" }, 4, 3)
assert(omitted > 0)
assert(#short == 3)
local wrapped = view.render({ source = "A", target = string.rep("x", 8), conversation = "ok" }, 6, 30)
assert(wrapped[3] == "To: xx" and wrapped[4] == "xxxxxx" and wrapped[5] == "  0")
