local temp_index = 0
local json, exec
if rex and rex.json then
  json, exec = rex.json, rex.exec
else
  json = require("test.json")
  exec = function(argv)
    if argv[1] == "mkdir" then
      local ok = os.execute("mkdir -p '" .. argv[3] .. "'")
      return { ok = ok == 0, stderr = "mkdir failed" }
    end
    if argv[1] == "mktemp" then
      temp_index = temp_index + 1
      local path = argv[2]:gsub("XXXXXXXX$", tostring(temp_index) .. "tmp")
      local file = assert(io.open(path, "wb"))
      file:close()
      return { ok = true, stdout = path .. "\n" }
    end
    error("unexpected command: " .. argv[1])
  end
end
rex = {
  args = nil,
  json = json,
  exec = exec,
}

local root = assert(os.getenv("XDG_STATE_HOME"))
local M = dofile("hooks/session-start.lua")
local payload = { transcript_path = "/tmp/transcript.jsonl", cwd = "/tmp/project", session_id = "session-123" }
M.run("claude", "123", "block:test-123", payload, root)
local path = root .. "/rex-agent-relay/agents/test-123.json"
local file = assert(io.open(path, "rb"))
local record = json.decode(file:read("*a"))
file:close()
assert(record.agent == "claude" and record.block_id == "block:test-123" and record.pid == 123)
assert(
  record.transcript_path == payload.transcript_path
    and record.cwd == payload.cwd
    and record.session_id == payload.session_id
)
M.run(
  "codex",
  456,
  "block:test-123",
  { transcript_path = "/tmp/next.jsonl", cwd = "/tmp/next", session_id = "session-456" },
  root
)
file = assert(io.open(path, "rb"))
record = json.decode(file:read("*a"))
file:close()
assert(record.agent == "codex" and record.pid == 456 and record.session_id == "session-456")

for _, args in ipairs({
  { "opencode", 1, "block:test-123", payload },
  { "claude", 0, "block:test-123", payload },
  { "claude", 1.5, "block:test-123", payload },
  { "claude", 1, "not-a-block", payload },
  { "claude", 1, "block:test-123", { cwd = "/tmp", session_id = "s" } },
}) do
  assert(not pcall(M.run, args[1], args[2], args[3], args[4], root))
end
file = assert(io.open(path, "rb"))
record = json.decode(file:read("*a"))
file:close()
assert(record.agent == "codex" and record.pid == 456)
local getenv, read = os.getenv, io.read
os.getenv = function(name)
  if name == "REX_BLOCK" then return "block:cli-789" end
  if name == "XDG_STATE_HOME" then return root end
  return getenv(name)
end
rex.args = {}
io.read = function() return "{}" end
assert(not pcall(dofile, "hooks/session-start.lua"))
rex.args = { agent = "claude", pid = "789" }
io.read = function() return "{" end
assert(not pcall(dofile, "hooks/session-start.lua"))
io.read = function() return json.encode(payload) end
dofile("hooks/session-start.lua")
os.getenv, io.read, rex.args = getenv, read, {}
file = assert(io.open(root .. "/rex-agent-relay/agents/cli-789.json", "rb"))
record = json.decode(file:read("*a"))
file:close()
assert(record.agent == "claude" and record.pid == 789 and record.session_id == payload.session_id)
print("hook tests passed")
