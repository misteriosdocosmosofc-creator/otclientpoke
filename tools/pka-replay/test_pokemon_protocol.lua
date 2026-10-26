-- Measured PKA wire layouts and exact outgoing commands; no connection or UI.
if not PokemonProtocol then assert(loadfile('modules/game_pokemon/protocol.lua'))() end
local function u8(n) return string.char(n) end
local function u16(n) return u8(n % 256) .. u8(math.floor(n / 256) % 256) end
local function u32(n) return u16(n % 65536) .. u16(math.floor(n / 65536)) end
local function str(s) return u16(#s) .. s end
local function reader(raw)
  local r = {pos = 1}
  function r:getU8()
    assert(self.pos <= #raw, 'EOF')
    local value = raw:byte(self.pos) self.pos = self.pos + 1 return value
  end
  function r:getU16() return self:getU8() + self:getU8() * 256 end
  function r:getU32() return self:getU16() + self:getU16() * 65536 end
  function r:getString()
    local count = self:getU16()
    assert(self.pos + count - 1 <= #raw, 'String EOF')
    local value = raw:sub(self.pos, self.pos + count - 1)
    self.pos = self.pos + count return value
  end
  return r
end
local cases = {
  {PokemonProtocol.readRoster, u8(0)..u16(1)..str('Skarmory')..u8(2)..u16(9861)..u8(73)..u32(120000)..str('test-pokemon')..u8(1)..str('m1')..u16(12)..u16(15),
   function(x) assert(x.entries[1].health == 73 and x.entries[1].identity == 'test-pokemon' and x.entries[1].cooldowns[1].remaining == 12) end},
  {PokemonProtocol.readRosterUpdate, u8(6)..u8(8)..u8(31)..u8(1)..str('m9')..u16(65535)..u16(55),
   function(x) assert(x.slot == 6 and x.health == 31 and x.cooldowns[1].total == 55) end},
  {PokemonProtocol.readSelected, u8(1)..u16(9861)..str('Skarmory')..str('test-pokemon'),
   function(x) assert(x.itemId == 9861 and x.name == 'Skarmory' and x.identity == 'test-pokemon') end},
  {PokemonProtocol.readSelected, u8(0), function(x) assert(x.mode == 0 and x.identity == nil) end},
  {PokemonProtocol.readMoves, u8(1)..str('Skarmory')..u8(1)..str('Steel Wing')..u32(10001)..u32(40)..str('m3')..u16(20),
   function(x) assert(x.entries[1].value == 10001 and x.entries[1].key == 'm3' and x.entries[1].remaining == 20) end},
  {PokemonProtocol.readMoves, u8(0), function(x) assert(#x.entries == 0) end},
  {PokemonProtocol.readMoveCooldown, str('m3')..u16(0), function(x) assert(x.key == 'm3' and x.remaining == 0) end},
  {PokemonProtocol.readCondition, u8(2)..u32(0xffffffff)..u32(1)..u32(32)..u32(2000)..u32(5000),
   function(x) assert(x.creatureId == 0xffffffff and x.duration == 2000 and PokemonProtocol.hasCondition(x, 0) and PokemonProtocol.hasCondition(x, 37) and not PokemonProtocol.hasCondition(x, 36)) end}
}
local function auxiliary(opcode)
  return function(msg) assert(PokemonProtocol.readAuxiliary(msg, opcode)) end
end
cases[#cases + 1] = {auxiliary(0x55), u32(0xffffffff)..u16(42)..u32(0xffffffff)..u32(0xffffffff)..u16(65535)..u8(255)..u8(1)..u8(0), function() end}
for field = 1, 10 do
  local body
  if field == 1 or field == 9 then body = str('property')
  elseif field == 6 then body = u16(65535)
  elseif field == 10 then body = u8(2)..str('m1')..u16(0)..u16(65535)..str('m9')..u16(33)..u16(44)
  else body = u8(255) end
  cases[#cases + 1] = {auxiliary(0x56), u32(1234)..u8(field)..body, function() end}
end
cases[#cases + 1] = {auxiliary(0x56), u32(1234)..u8(10)..u8(0), function() end}
cases[#cases + 1] = {auxiliary(0x114), u8(2)..u16(1)..u16(2)..u16(3)..u8(255)..str('one')..u16(4)..u8(0)..u16(5)..u16(6)..u16(7)..u8(0)..str('')..u16(8)..u8(255), function() end}
cases[#cases + 1] = {auxiliary(0x114), u8(0), function() end}
cases[#cases + 1] = {auxiliary(0x115), u32(0xffffffff)..u16(0)..u16(65535)..u8(0)..u8(1)..u8(2)..u8(255), function() end}
assert(not PokemonProtocol.readAuxiliary(reader(''), 0x777))
for _, field in ipairs({0, 11, 255}) do
  assert(not pcall(auxiliary(0x56), reader(u32(1234)..u8(field))))
end
local truncated = 0
for _, case in ipairs(cases) do
  local msg = reader(case[2] .. u16(0xa3))
  case[3](case[1](msg))
  assert(msg:getU16() == 0xa3 and msg.pos == #case[2] + 3, 'Wrong next opcode boundary')
  for i = 0, #case[2] - 1 do
    assert(not pcall(case[1], reader(case[2]:sub(1, i))), 'Accepted a truncated payload')
    truncated = truncated + 1
  end
end
local function encode(callback)
  local m = {raw = ''}
  function m:addU8(x) self.raw = self.raw .. u8(x) end
  function m:addU16(x) self.raw = self.raw .. u16(x) end
  callback(m) return m.raw
end
assert(encode(function(m) PokemonProtocol.writePokemonItem(m, 3156, true) end) == string.char(0x5a,0,2,0x54,0x0c,0xa7))
assert(encode(function(m) PokemonProtocol.writePokemonItem(m, 1234, false) end) == string.char(0x5a,0,1,0xd2,4))
assert(encode(function(m) PokemonProtocol.writeFly(m, false) end) == string.char(0x0f,6,0))
assert(encode(function(m) PokemonProtocol.writeFly(m, true) end) == string.char(0x0f,6,1))
assert(encode(function(m) PokemonProtocol.writeSelect(m, 6) end) == string.char(0x0a,6,3,6))
local summary = string.format('Pokemon protocol OK: %d payloads, %d truncated prefixes rejected, 5 exact command encodings.', #cases, truncated)
if g_logger then g_logger.info(summary) else io.write(summary .. '\n') end
