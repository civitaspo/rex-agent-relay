local lunajson = require("lunajson")

local function compact(value)
  if type(value) ~= "table" then return value end
  local length = value[0]
  if length then
    local result = {}
    for i = 1, length do
      local item = compact(value[i])
      if item ~= nil then result[#result + 1] = item end
    end
    return result
  end
  for key, item in pairs(value) do value[key] = compact(item) end
  return value
end

local function normalize(value, seen)
  if type(value) ~= "table" then return value end
  if seen[value] then error("cycle in table") end
  seen[value] = true
  local count, max, array = 0, 0, true
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      array = false
    elseif key > max then
      max = key
    end
  end
  array = array and count > 0 and count == max
  local result = {}
  for key, item in pairs(value) do
    if not array then
      if type(key) ~= "string" and type(key) ~= "number" then error("invalid object key") end
      key = tostring(key)
    end
    result[key] = normalize(item, seen)
  end
  seen[value] = nil
  return result
end

local function result(ok, value)
  if ok then return value end
  return nil, value
end

return {
  encode = function(value)
    return result(pcall(function() return lunajson.encode(normalize(value, {})) end))
  end,
  decode = function(text)
    return result(pcall(function() return compact(lunajson.decode(text, 1, nil, true)) end))
  end,
}
