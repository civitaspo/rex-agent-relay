local dir = debug.getinfo(1, "S").source:match("^@?(.*)/[^/]*$") or "."
package.path = dir .. "/?.lua;" .. package.path
local transcript = require("transcript")
local kinds = { codex = true, claude = true }
local state = (os.getenv("XDG_STATE_HOME") or (assert(os.getenv("HOME")) .. "/.local/state")) .. "/rex-agent-relay"
local source, mode = rex.args.source, rex.args.mode or "send"

local function mkdir(path)
  local result, err = rex.exec({"mkdir", "-p", path})
  if not result or not result.ok then error(err or result.stderr, 0) end
end
local function missing(err, code)
  return code == 2 or (type(err) == "string" and err:lower():find("no such file or directory", 1, true) ~= nil)
end
local function read_json(path, optional)
  local f, err, code = io.open(path, "rb")
  if not f then if optional and missing(err, code) then return {} end; error(err, 0) end
  local text = f:read("*a"); f:close()
  local value, decode_err = rex.json.decode(text)
  if type(value) ~= "table" then error("invalid state " .. path .. ": " .. tostring(decode_err), 0) end
  return value
end
local function temporary(template)
  local result, err = rex.exec({"mktemp", template})
  if not result or not result.ok then error(err or result.stderr, 0) end
  return assert(result.stdout:match("^[^\n]+"))
end
local function save_json(path, value)
  mkdir(state)
  local encoded, encode_err = rex.json.encode(value)
  if not encoded then error(encode_err, 0) end
  local name = temporary(path .. ".XXXXXXXX")
  local out = assert(io.open(name, "wb")); assert(out:write(encoded)); assert(out:close())
  local ok, rename_err = os.rename(name, path)
  if not ok then os.remove(name); error(rename_err, 0) end
end
local function agent(id)
  if type(id) ~= "string" or not id:match("^block:[%w%-]+$") then error("invalid source or target block ID", 0) end
  local f, err, code = io.open(state .. "/agents/" .. id:sub(7) .. ".json", "rb")
  if not f then if missing(err, code) then return nil end; error(err, 0) end
  f:close()
  local value = read_json(state .. "/agents/" .. id:sub(7) .. ".json")
  if value.block_id ~= id or not kinds[value.agent] or type(value.hook) ~= "table" then error("invalid agent registration: " .. id, 0) end
  return value
end
local function call(method, args)
  local result, err = rex.call(method, args)
  if not result then error(tostring(err), 0) end
  return result
end
local function panes()
  local found = {}
  local sessions = call("session.list", {}).sessions or {}
  for _, session in ipairs(sessions) do
    call("session.attach", {session_id=session.session_id})
    for _, block in ipairs(call("session.list_blocks", {session_id=session.session_id}).blocks or {}) do
      if block.block_id and block.placement == "placed" then
        found[block.block_id] = { session_id=session.session_id, session_label=session.label, label=block.label }
      end
    end
  end
  return found
end
local function foreground(id, pane, kind)
  if not pane then return false end
  local result = rex.call("com.superlogical.terminal.process", {session_id=pane.session_id, block_id=id, args={}})
  local process = result and result.foreground
  if not process then return false end
  local name = process.script or process.argv0 or process.name or ""
  name = name:match("([^/]+)$") or name
  return name == kind or name == kind .. ".js"
end
local function pair_save(a, b)
  local pairs = read_json(state .. "/pairs.json", true)
  local olda, oldb = pairs[a], pairs[b]
  if olda then pairs[olda] = nil end
  if oldb then pairs[oldb] = nil end
  pairs[a], pairs[b] = b, a
  save_json(state .. "/pairs.json", pairs)
end
local function pick(candidates)
  local result, err = rex.exec({"sh", "-c", os.getenv("REX_AGENT_RELAY_FUZZY_FINDER") or "fzf"}, {stdin=table.concat(candidates, "\n") .. "\n"})
  if not result then error("cannot start fuzzy finder: " .. tostring(err), 0) end
  if not result.ok then return nil end
  return result.stdout:match("^[^\n]+")
end
local function short(id) return "…" .. id:sub(-6) end
local function label(reg, id)
  return reg.agent .. " " .. transcript.display_path(reg.hook.cwd or "?", nil) .. " (" .. short(id) .. ")"
end
local function collect(limit)
  local src = agent(source)
  if not src then error("source agent is not registered; configure the SessionStart hook and restart the agent", 0) end
  if type(src.hook.transcript_path) ~= "string" then error("source hook has no transcript_path", 0) end
  local all = panes()
  if not all[source] then error("source pane is not available", 0) end
  local pairs = read_json(state .. "/pairs.json", true)
  local target_id = pairs[source]
  local target = target_id and agent(target_id)
  local pending = target_id and all[target_id] and not target
  if not target or not foreground(target_id, all[target_id], target.agent) then target, target_id = nil, nil end
  local cursors = read_json(state .. "/cursors.json", true)
  local offset = cursors[src.hook.transcript_path] or 0
  if type(offset) ~= "number" or offset < 0 then error("invalid relay point", 0) end
  local lines, ending = transcript.read(src.hook.transcript_path, offset, limit)
  local parsed = transcript.parse(src.agent, lines)
  local cwd = parsed.latest_cwd
  if not cwd and offset > 0 then
    local earlier = transcript.read(src.hook.transcript_path, 0, offset)
    cwd = transcript.parse(src.agent, earlier).latest_cwd
  end
  cwd = cwd or src.hook.cwd
  if not cwd then error("source working directory is unavailable", 0) end
  return {src=src, target=target, target_id=target_id, pending=pending, panes=all, cursors=cursors, parsed=parsed, cwd=cwd, ending=ending}
end
local function choose_pair()
  if not agent(source) then error("source agent is not registered", 0) end
  local all, candidates = panes(), {}
  for id, pane in pairs(all) do
    if id ~= source then
      local reg = agent(id)
      if reg and foreground(id, pane, reg.agent) then candidates[#candidates + 1] = label(reg,id) .. " " .. pane.session_label .. "\t" .. id end
    end
  end
  table.sort(candidates)
  if #candidates == 0 then error("no available agent panes", 0) end
  local selected = pick(candidates)
  if selected then pair_save(source, assert(selected:match("\t(block:[%w%-]+)$"))) end
end
local function deliver(plan, note, kind, by)
  if #plan.parsed.messages == 0 and #plan.parsed.files == 0 and note == "" then return 2 end
  local conversation = transcript.conversation(plan.parsed, plan.cwd)
  local body = transcript.body(plan.src.agent, by, plan.cwd, conversation, note)
  local max = tonumber(os.getenv("REX_AGENT_RELAY_INLINE_MAX") or "20000")
  if not max or max < 0 then error("invalid REX_AGENT_RELAY_INLINE_MAX", 0) end
  if #body > max then
    local outbox = os.getenv("REX_AGENT_RELAY_OUTBOX_DIR") or state .. "/outbox"
    mkdir(outbox)
    local path = temporary(outbox .. "/" .. os.date("%Y%m%d-%H%M%S") .. "-" .. source:sub(-6) .. "-XXXXXXXX")
    local f, err = io.open(path, "wb"); if not f then error(err, 0) end
    assert(f:write(body)); assert(f:close())
    body = transcript.body(plan.src.agent, by, plan.cwd, conversation, note, path, transcript.refs(plan.parsed.files, plan.cwd))
  end
  if plan.target then
    local pane = plan.panes[plan.target_id]
    if not foreground(plan.target_id, pane, plan.target.agent) then error("target is no longer running its agent; nothing was sent", 0) end
    if body:find("\27[201~", 1, true) then error("relay contains a bracketed paste terminator", 0) end
    local function write(data)
      local result = call("com.superlogical.terminal.write", {session_id=pane.session_id, block_id=plan.target_id, args={data=data}})
      if result.bytes_written ~= #data then error("terminal write was incomplete", 0) end
    end
    write("\27[200~" .. body .. "\27[201~")
    rex.sleep(0.3)
    if not foreground(plan.target_id, pane, plan.target.agent) then error("target exited before submission", 0) end
    write("\r")
  else
    if not kinds[kind] then error("unknown agent kind: " .. tostring(kind), 0) end
    local command = kind == "codex" and {kind, "--no-daemon", body} or {kind, body}
    local split, err = rex.session.new_split{session_id=plan.panes[source].session_id, anchor_id=source, direction="horizontal", side="after", ratio=0.5, focus=false,
      layout=rex.layout.block{flavor="com.superlogical.terminal.shell", options={cwd=plan.cwd, command=command}}}
    if not split then error(tostring(err), 0) end
    local new_id = assert(split.block_ids[1])
    pair_save(source, new_id)
  end
  plan.cursors[plan.src.hook.transcript_path] = plan.ending
  save_json(state .. "/cursors.json", plan.cursors)
  return 0
end
local function run()
  if not source then error("source is required", 0) end
  if mode == "pair" then choose_pair(); return 0 end
  if mode ~= "send" and mode ~= "peek" and mode ~= "deliver" then error("unknown mode: " .. mode, 0) end
  local until_pos
  if rex.args["until"] then
    until_pos = tonumber(rex.args["until"])
    if not until_pos or until_pos < 0 or until_pos % 1 ~= 0 then error("until must be a non-negative byte position", 0) end
  end
  local plan = collect(until_pos)
  local count = 0; for _, item in ipairs(plan.parsed.messages) do if item.speaker then count = count + 1 end end
  local target_label = plan.target and label(plan.target, plan.target_id) or "none"
  if mode == "peek" then
    print("source: " .. label(plan.src, source)); print("target: " .. target_label); print("until: " .. plan.ending)
    print(count .. " messages, " .. #plan.parsed.files .. " files since last relay")
    local text = transcript.conversation(plan.parsed, plan.cwd)
    if text ~= "" then print("\n" .. text) end
    return #plan.parsed.messages == 0 and #plan.parsed.files == 0 and 2 or 0
  end
  if plan.pending then error("paired pane has not registered; wait for the agent or close the pane before retrying", 0) end
  local note, kind, by = "", rex.args.kind, rex.args.by or "auto"
  if by ~= "human" and by ~= "auto" then error("by must be human or auto", 0) end
  if mode == "send" then
    by = "human"
    print("agent-relay  " .. label(plan.src, source) .. "  ->  " .. target_label)
    print(count .. " messages, " .. #plan.parsed.files .. " files since last relay")
    if not plan.target then
      local other = plan.src.agent == "claude" and "codex" or "claude"
      local selection = pick({other .. "\t" .. other, plan.src.agent .. "\t" .. plan.src.agent})
      if not selection then return 1 end
      kind = selection:match("\t([^\t]+)$")
      print("no pair: start a new " .. kind .. " beside this pane")
    end
    io.write("note> "); io.flush(); note = io.read("*l")
    if note == nil then return 1 end
  else
    note = io.read("*a") or ""
    note = note:gsub("\n$", "")
  end
  kind = kind or (plan.src.agent == "claude" and "codex" or "claude")
  return deliver(plan, note, kind, by)
end
local ok, result = pcall(run)
if not ok then
  io.stderr:write("agent-relay: " .. tostring(result) .. "\n")
  if mode == "send" or mode == "pair" then io.write("Press Enter to close. "); io.flush(); io.read("*l") end
  os.exit(1)
end
if result == 2 and mode == "send" then print("nothing to relay") end
os.exit(result)
