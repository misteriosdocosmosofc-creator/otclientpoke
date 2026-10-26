-- Measured original DX readers: 140770ec0/1407715a0/140771780/
-- 140771b90/14077d000. Keep parsing separate from widgets and actions.
PokemonProtocol = {}

local function readCooldowns(msg)
  local entries = {}
  local count = msg:getU8()
  for i = 1, count do
    entries[i] = {key = msg:getString(), remaining = msg:getU16(), total = msg:getU16()}
  end
  return entries
end

function PokemonProtocol.readRoster(msg)
  local result = {mode = msg:getU8(), entries = {}}
  local count = msg:getU16()
  for i = 1, count do
    local entry = {
      name = msg:getString(), variant = msg:getU8(), itemId = msg:getU16(),
      health = msg:getU8(), value = msg:getU32(), identity = msg:getString()
    }
    entry.cooldowns = readCooldowns(msg)
    result.entries[i] = entry
  end
  return result
end

function PokemonProtocol.readRosterUpdate(msg)
  local result = {slot = msg:getU8(), state = msg:getU8(), health = msg:getU8()}
  result.cooldowns = readCooldowns(msg)
  return result
end

function PokemonProtocol.readSelected(msg)
  local result = {mode = msg:getU8()}
  if result.mode == 1 then
    result.itemId = msg:getU16()
    result.name = msg:getString()
    result.identity = msg:getString()
  end
  return result
end

function PokemonProtocol.readMoves(msg)
  local result = {mode = msg:getU8(), entries = {}}
  if result.mode == 1 then
    result.pokemon = msg:getString()
    local count = msg:getU8()
    for i = 1, count do
      result.entries[i] = {
        name = msg:getString(), value = msg:getU32(), total = msg:getU32(),
        key = msg:getString(), remaining = msg:getU16()
      }
    end
  end
  return result
end

function PokemonProtocol.readMoveCooldown(msg)
  return {key = msg:getString(), remaining = msg:getU16()}
end

function PokemonProtocol.readCondition(msg)
  -- Read U64 as two halves: Lua numbers cannot represent every U64 exactly.
  return {
    mode = msg:getU8(), creatureId = msg:getU32(),
    low = msg:getU32(), high = msg:getU32(),
    duration = msg:getU32(), total = msg:getU32()
  }
end

function PokemonProtocol.hasCondition(condition, bitIndex)
  local value = bitIndex < 32 and condition.low or condition.high
  return math.floor(value / 2 ^ (bitIndex % 32)) % 2 == 1
end

-- DX 140779120/140778f40, 1407791a0, 140794a70 and 140794ef0.
-- These updates can precede Pokemon UI records in the same message. Consume
-- their measured fields without assigning unverified gameplay meanings.
function PokemonProtocol.readAuxiliary(msg, opcode)
  if opcode == 0x55 then
    msg:getU32() msg:getU16()
    msg:getU32() msg:getU32() -- opaque U64, preserve its exact wire width
    msg:getU16() msg:getU8() msg:getU8() msg:getU8()
  elseif opcode == 0x56 then
    msg:getU32()
    local field = msg:getU8()
    if field == 1 or field == 9 then msg:getString()
    elseif field >= 2 and field <= 8 then
      if field == 6 then msg:getU16() else msg:getU8() end
    elseif field == 10 then
      local count = msg:getU8()
      for i = 1, count do msg:getString() msg:getU16() msg:getU16() end
    else error('Unknown PKA creature property ' .. field) end
  elseif opcode == 0x114 then
    local count = msg:getU8()
    for i = 1, count do
      msg:getU16() msg:getU16() msg:getU16() msg:getU8()
      msg:getString() msg:getU16() msg:getU8()
    end
  elseif opcode == 0x115 then
    msg:getU32() msg:getU16() msg:getU16()
    msg:getU8() msg:getU8() msg:getU8() msg:getU8()
  else return false end
  return true
end

function PokemonProtocol.writePokemonItem(msg, itemId, revive)
  -- Original action types onpokemon=1 and autorevive=7, DX 1405c4fe0.
  msg:addU16(0x5a)
  msg:addU8(revive and 2 or 1)
  msg:addU16(itemId)
  if revive then msg:addU8(0xa7) end
end

function PokemonProtocol.writeFly(msg, down)
  -- Original PageUp/PageDown callbacks, DX 140478ec0.
  msg:addU16(0x60f)
  msg:addU8(down and 1 or 0)
end

function PokemonProtocol.writeSelect(msg, slot)
  -- Original Pokebar click, DX 1405e93f0.
  msg:addU16(0x60a)
  msg:addU8(3)
  msg:addU8(slot)
end
