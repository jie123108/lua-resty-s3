local resty_sha256 = require "resty.sha256"
local str = require "resty.string"

local sha256_bytes = function(input)
  local sha256 = resty_sha256:new()
  sha256:update(input)
  return sha256:final()
end

local sha256_hex = function(input)
  local r = sha256_bytes(input)
  return str.to_hex(r)
end

return {
  sha256_bin = sha256_bytes,
  sha256_hex = sha256_hex,
  sha256 = sha256_hex,
}