local cjson = require("cjson")
rex = {json = {encode = cjson.encode, decode = cjson.decode}}
rex.exec = function(argv)
  local result = os.execute("mkdir -p " .. argv[3])
  return {ok = result == 0, stderr = "mkdir failed"}
end
dofile("test/relay_test.lua")
