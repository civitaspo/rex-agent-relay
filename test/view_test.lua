package.path = "./rex-agent-relay/?.lua;" .. package.path
local view = require("view")
local lines, hidden, cursor =
  view.render({ source = "A", target = "B", count = 2, conversation = "abc", input = "note", help = "help" }, 80, 20)
assert(hidden == 0)
assert(
  table.concat(lines, "\n")
    == "From: A\nTo: B  2\n\nabc\n\n───[note]"
      .. string.rep("─", 71)
      .. "\nnote\n"
      .. string.rep("─", 80)
      .. "\nhelp"
)
assert(cursor.row == 7 and cursor.col == 5)
local review = view.render({ state = "review", input = "first\nsecond" }, 15, 30)
assert(
  table
    .concat(review, "\n")
    :find("───[note]──────\nfirst\nsecond\n───────────────", 1, true)
)
local narrow = view.render({ state = "input", input = "x" }, 4, 30)
assert(table.concat(narrow, "\n"):find("───[\n", 1, true))
local short, omitted =
  view.render({ source = "A", target = "B", conversation = "こんにちは", input = "", help = "help" }, 4, 3)
assert(omitted > 0)
assert(#short == 3)
local wrapped = view.render({ source = "A", target = string.rep("x", 8), conversation = "ok" }, 6, 30)
assert(wrapped[3] == "To: xx" and wrapped[4] == "xxxxxx" and wrapped[5] == "  0")
local _, _, wrapped_cursor = view.render({ input = "日本abc" }, 4, 30)
assert(wrapped_cursor.col == 4)
local _, _, clipped_cursor = view.render({ input = "hello", help = "help" }, 15, 5)
assert(clipped_cursor.row == 3 and clipped_cursor.col == 6)
local _, _, review_cursor = view.render({ state = "review", input = "hello" }, 15, 30)
assert(review_cursor == nil)

local long, hidden_long = view.render(
  { source = "A", target = "B", count = 2, conversation = string.rep("line\n", 50), input = "note", help = "help" },
  80,
  10
)
assert(long[1] == "From: A" and long[2] == "To: B  2" and long[3]:find("hidden", 1, true))
assert(hidden_long > 0 and #long == 10)

local _, _, punctuation = view.render({ input = "’“…”→日本" }, 80, 20)
assert(punctuation.col == 10)
local tabs = view.render({ conversation = "a\tb" }, 4, 30)
assert(table.concat(tabs, "\n"):find("a   \n    \nb", 1, true))
local empty = view.render({ conversation = "" }, 80, 20)
assert(table.concat(empty, "\n"):find("No new conversation since last relay", 1, true))
local colored = view.render({ conversation = "user: hello\n\nclaude: hi" }, 80, 20)
assert(table.concat(colored, "\n"):find("\27[36muser:\27[0m hello", 1, true))
assert(long[3]:find("ctrl+o pager", 1, true))
assert(view.display("日本\194\15531m") == "日本?31m")
