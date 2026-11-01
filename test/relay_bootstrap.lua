rex = {json = require("test.json")}
rex.exec = function(argv)
  if argv[1] == "mktemp" then
    local path = argv[2]:gsub("XXXXXXXX$", tostring(os.time()) .. tostring(math.random(1000000000)))
    local f = assert(io.open(path, "wb")); f:close()
    return {ok=true, stdout=path .. "\n"}
  end
  local result = os.execute("mkdir -p " .. argv[3])
  return {ok = result == 0, stderr = "mkdir failed"}
end
dofile("test/relay_test.lua")
