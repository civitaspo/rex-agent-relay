local cjson = require("cjson")
rex = {json = {encode = cjson.encode, decode = cjson.decode}}
dofile("test/transcript_test.lua")
