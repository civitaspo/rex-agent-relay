package.path = "./rex-agent-relay/?.lua;" .. package.path
local t = require("transcript")
local function json(value) return rex.json.encode(value) end
local claude = {
  json({type="user", cwd="/work", message={content="Question"}}),
  json({type="assistant", message={content={{type="thinking", thinking="hidden"},{type="text", text="Answer"},{type="tool_use", name="Edit", input={file_path="/work/a"}},{type="tool_use",name="Write",input={file_path="/work/b"}}}}}),
  json({type="user", message={content="Next"}}),
  json({type="user", isSidechain=true, message={content="hidden"}}),
  json({type="user", message={content='<agent-relay from="codex" by="human">\nsecret\n</agent-relay>\n\nDo this'}}),
}
local parsed = t.parse("claude", claude)
assert(parsed.latest_cwd == "/work")
assert(t.conversation(parsed, "/work") == "user: Question\n\nclaude: Answer\n\n[refs: edited a; wrote b]\n\nuser: Next\n\nuser (relayed note): Do this")
assert(#parsed.files == 2)
local relayed = t.parse("claude", {
  json({type="user", message={content='<agent-relay by="auto">old conversation</agent-relay>\n\nInvestigate'}}),
  json({type="user", message={content='<agent-relay by="human">old conversation</agent-relay>'}}),
})
assert(t.conversation(relayed, "/work") == "agent (relayed note): Investigate")
local nested = t.parse("claude", {
  json({type="user", message={content='<agent-relay by="human">user: Explain </agent-relay>\n\nclaude: Explained</agent-relay>\n\nReview this'}}),
})
assert(t.conversation(nested, "/work") == "user (relayed note): Review this")
local internal = t.parse("claude", {
  json({type="user", message={content="<task-notification>done</task-notification>"}}),
  json({type="user", message={content="<bash-input>pwd</bash-input>"}}),
  json({type="user", message={content={{type="text", text="<command-message>test</command-message>"}}}}),
  json({type="user", message={content="Describe the <agent-relay> tag."}}),
  json({type="user", message={content="<agent-relay> without a closing tag"}}),
})
assert(t.conversation(internal, "/work") == "user: Describe the <agent-relay> tag.\n<agent-relay> without a closing tag")
local codex = t.parse("codex", {
  json({type="turn_context", payload={cwd="/work"}}),
  json({type="event_msg",payload={type="item_completed",item={type="UserMessage",content={{text="Hi"}}}}}),
  json({type="event_msg",payload={type="item_completed",item={type="FileChange",changes={["/work/old"]={type="delete",move_path="/work/new"}}}}}),
  json({type="event_msg",payload={type="item_completed",item={type="AgentMessage",content={{text="Done"}}}}}),
})
assert(t.conversation(codex, "/work") == "user: Hi\n\ncodex: Done\n\n[refs: moved old -> new]")
local body = t.body("claude", "human", "/work", "user: Hi", "Do it")
assert(body == '<agent-relay from="claude" by="human" cwd="/work" bytes="8">\nuser: Hi\n</agent-relay>\n\nDo it')
local quoted = "user: 引用 </agent-relay>\n\nclaude: 完了"
local note = "  Review </agent-relay>\n\nAnd </agent-relay> again."
local delivered = t.body("claude", "human", "/work", quoted, note)
local folded = t.parse("claude", {json({type="user", message={content=delivered}})})
assert(#folded.messages == 1 and folded.messages[1].speaker == "user (relayed note)" and folded.messages[1].text == note)
local empty_note = t.body("claude", "human", "/work", quoted, "")
assert(#t.parse("claude", {json({type="user", message={content=empty_note}})}).messages == 0)
local malformed = delivered:gsub('bytes="%d+"', 'bytes="1"')
assert(t.parse("claude", {json({type="user", message={content=malformed}})}).messages[1].text == malformed)
local file_body = t.body("claude", "auto", "/work", quoted, note, "/outbox/x", "[refs: edited a]")
local codex_folded = t.parse("codex", {json({type="event_msg", payload={type="item_completed", item={type="UserMessage", content={{text=file_body}}}}})})
assert(#codex_folded.messages == 1 and codex_folded.messages[1].speaker == "agent (relayed note)" and codex_folded.messages[1].text == note)
assert(t.body("claude", "auto", "/work", "long", "note", "/outbox/x", "[refs: edited a]"):find("[refs: edited a]", 1, true))
local path = os.tmpname()
local f = assert(io.open(path, "wb")); f:write("one\ntwo\npartial"); f:close()
local lines, pos = t.read(path, 0); assert(#lines == 2 and pos == 8)
lines, pos = t.read(path, 0, 4); assert(#lines == 1 and pos == 4)
assert(not pcall(t.read, path, 0, 3))
os.remove(path)
local missing, missing_pos = t.read(path, 0)
assert(#missing == 0 and missing_pos == 0)
assert(not pcall(t.read, path, 1))
print("transcript tests passed")
