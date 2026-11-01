local base = assert(os.getenv("XDG_STATE_HOME")) .. "/rex-agent-relay"
assert(rex.exec({"mkdir", "-p", base .. "/agents"}).ok)
local function write(path, data)
  local f = assert(io.open(path, "wb")); assert(f:write(data)); assert(f:close())
end
local source, target = "block:source", "block:target"
local log = base .. "/conversation.jsonl"
local first = '{"type":"user","cwd":"/work","message":{"content":"seen"}}\n'
local later = '{"type":"user","cwd":"/work","message":{"content":"later"}}\n'
write(log, first .. later)
local function register(id, kind)
  write(base .. "/agents/" .. id:sub(7) .. ".json", rex.json.encode({agent=kind, block_id=id, pid=101, cwd="/work", transcript_path=log, session_id="test"}))
end
register(source, "claude")
write(base .. "/pairs.json", rex.json.encode({[source]=target, [target]=source}))
local sent = {}
rex.args = {mode="deliver", source=source, ["until"]=#first}
rex.call = function(method, args)
  if method == "session.list" then return {sessions={{session_id="s1",label="one"},{session_id="s2",label="two"}}} end
  if method == "session.attach" then return {} end
  if method == "session.list_blocks" then return {blocks={{block_id=args.session_id == "s1" and source or target, placement="placed"}}} end
  if method == "com.superlogical.terminal.process" then
    if args.block_id == source then return {foreground={name="claude", pid=101, cwd="/work"}} end
    return {foreground={name="codex", pid=202, cwd="/target"}}
  end
  if method == "com.superlogical.terminal.write" then sent[#sent+1]=args.args.data; return {bytes_written=#args.args.data} end
  error("unexpected method " .. method)
end
rex.sleep = function() end
local original_exit, original_read = os.exit, io.read
os.exit = function(code) error({exit=code}) end
io.read = function() return "Review\n" end
local ok, result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.read = original_exit, original_read
assert(not ok and type(result) == "table" and result.exit == 0)
assert(#sent == 2 and sent[1]:find("user: seen", 1, true) and not sent[1]:find("user: later", 1, true))
assert(sent[1]:find('by="auto"', 1, true) and sent[1]:find("\n\nReview", 1, true) and sent[2] == "\r")
local f = assert(io.open(base .. "/cursors.json")); local cursors = rex.json.decode(f:read("*a")); f:close()
assert(cursors[log] == #first)
sent = {}
rex.args = {mode="deliver", source=source, ["until"]=#first - 1}
os.exit = function(code) error({exit=code}) end
io.read = function() return "" end
local failed, failure = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.read = original_exit, original_read
assert(not failed and type(failure) == "table" and failure.exit == 1 and #sent == 0)
write(base .. "/pairs.json", "{}")
local launched
rex.session = {new_split=function(args)
  launched = args.layout.command or args.layout.options.command
  return {block_ids={"block:new"}}
end}
rex.layout = {block=function(args) return args end}
rex.args = {mode="deliver", source=source, kind="codex"}
os.exit = function(code) error({exit=code}) end
io.read = function() return "Review" end
local started, start_result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.read = original_exit, original_read
assert(not started and type(start_result) == "table" and start_result.exit == 0)
assert(launched[1] == "codex" and launched[2] == "--no-daemon")
local pairfile = assert(io.open(base .. "/pairs.json")); local saved_pairs = rex.json.decode(pairfile:read("*a")); pairfile:close()
local cursorfile = assert(io.open(base .. "/cursors.json")); cursors = rex.json.decode(cursorfile:read("*a")); cursorfile:close()
assert(saved_pairs[source] == "block:new" and cursors[log] == #first + #later)
local original_call = rex.call
rex.call = function(method, args)
  if method == "session.list_blocks" and args.session_id == "s1" then
    return {blocks={{block_id=source, placement="placed"}, {block_id="block:new", placement="placed"}}}
  end
  if method == "com.superlogical.terminal.process" and args.block_id == "block:new" then return {foreground={name="sh",pid=303}} end
  return original_call(method, args)
end
rex.args = {mode="deliver", source=source}
local new_split = rex.session.new_split
rex.session.new_split = function() error("must not start another agent") end
os.exit = function(code) error({exit=code}) end
io.read = function() return "Another note" end
local pending_ok, pending_result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.read, rex.call, rex.session.new_split = original_exit, original_read, original_call, new_split
assert(not pending_ok and pending_result.exit == 1)
os.exit = function(code) error({exit=code}) end
io.read = function() return "Another note" end
local retry_ok, retry_result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.read = original_exit, original_read
assert(not retry_ok and retry_result.exit == 0)
rex.args = {mode="send", source="block:missing"}
os.exit = function(code) error({exit=code}) end
io.read = function() error({waiting=true}) end
local ui_ok, ui_result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.read = original_exit, original_read
assert(not ui_ok and type(ui_result) == "table" and ui_result.waiting)
local original_open = io.open
io.open = function(path, mode)
  if path == base .. "/pairs.json" then return nil, "permission denied", 13 end
  return original_open(path, mode)
end
rex.args = {mode="peek", source=source}
os.exit = function(code) error({exit=code}) end
local readable, read_result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, io.open = original_exit, original_open
assert(not readable and type(read_result) == "table" and read_result.exit == 1)
local function rejected_source(process)
  rex.call = function(method, args)
    if method == "com.superlogical.terminal.process" and args.block_id == source then return {foreground=process} end
    return original_call(method, args)
  end
  rex.args = {mode="peek", source=source}
  os.exit = function(code) error({exit=code}) end
  local valid, result = pcall(dofile, "rex-agent-relay/relay.lua")
  os.exit, rex.call = original_exit, original_call
  assert(not valid and type(result) == "table" and result.exit == 1)
end
rejected_source({name="claude",pid=999})
rejected_source({name="codex",pid=101})
local original_exec = rex.exec
rex.exec = function(argv, opts)
  if argv[1] == "sh" then
    assert(opts.stdin:find("codex /target", 1, true) and opts.stdin:find(target, 1, true))
    return {ok=true, stdout="codex /target (…target) two\t" .. target .. "\n"}
  end
  return original_exec(argv, opts)
end
rex.args = {mode="pair", source=source}
os.exit = function(code) error({exit=code}) end
local paired, pair_result = pcall(dofile, "rex-agent-relay/relay.lua")
os.exit, rex.exec = original_exit, original_exec
assert(not paired and type(pair_result) == "table" and pair_result.exit == 0)
print("relay tests passed")
