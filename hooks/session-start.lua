local M = {}

local function nonempty(value) return type(value) == "string" and value ~= "" end

function M.run(agent, pid, block_id, payload, state_home)
  if agent ~= "claude" and agent ~= "codex" then error("agent must be claude or codex", 0) end
  local process_id = tonumber(pid)
  if not process_id or process_id < 1 or process_id % 1 ~= 0 then error("pid must be a positive integer", 0) end
  if not nonempty(block_id) or not block_id:match("^block:[%w%-]+$") then
    error("REX_BLOCK must be a valid block ID", 0)
  end
  if type(payload) ~= "table" then error("SessionStart payload must be a JSON object", 0) end
  for _, key in ipairs({ "transcript_path", "cwd", "session_id" }) do
    if not nonempty(payload[key]) then error("SessionStart payload is missing " .. key, 0) end
  end

  state_home = state_home or os.getenv("XDG_STATE_HOME") or (assert(os.getenv("HOME")) .. "/.local/state")
  local dir = state_home .. "/rex-agent-relay/agents"
  local made, mkdir_err = rex.exec({ "mkdir", "-p", dir })
  if not made or not made.ok then error(mkdir_err or made.stderr, 0) end
  local temporary, temp_err = rex.exec({ "mktemp", dir .. "/." .. block_id:sub(7) .. ".XXXXXXXX" })
  if not temporary or not temporary.ok then error(temp_err or temporary.stderr, 0) end
  local path = assert(temporary.stdout:match("^([^\n]+)"))
  local file, open_err = io.open(path, "wb")
  if not file then
    os.remove(path)
    error(open_err, 0)
  end
  local record = {
    agent = agent,
    block_id = block_id,
    pid = process_id,
    transcript_path = payload.transcript_path,
    cwd = payload.cwd,
    session_id = payload.session_id,
  }
  local encoded, encode_err = rex.json.encode(record)
  if not encoded then
    file:close()
    os.remove(path)
    error(encode_err, 0)
  end
  local wrote, write_err = file:write(encoded)
  local closed, close_err = file:close()
  if not wrote or not closed then
    os.remove(path)
    error(write_err or close_err, 0)
  end
  local renamed, rename_err = os.rename(path, dir .. "/" .. block_id:sub(7) .. ".json")
  if not renamed then
    os.remove(path)
    error(rename_err, 0)
  end
end

local cli = rex.args ~= nil
if cli then
  if not rex.args.agent then error("agent is required", 0) end
  local payload, decode_err = rex.json.decode(io.read("*a"))
  if type(payload) ~= "table" then error("invalid SessionStart JSON: " .. tostring(decode_err), 0) end
  M.run(rex.args.agent, rex.args.pid, os.getenv("REX_BLOCK"), payload)
end

if not cli then return M end
