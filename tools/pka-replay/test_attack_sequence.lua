-- Profile switching must not leak PKA's 854 attack layout into another host.
-- Run with a Lua interpreter from the repository root.
G = {}
CIPSOFT_RSA, OTSERV_RSA, POKEALLIANCE_RSA = 'cip', 'ot', 'pka'
GameAttackSeq = 32
OsTypes = {Windows = 1, Linux = 2}
local clientVersion, protocolVersion, pka, sequence = 860, 854, false, true
g_game = {
  getClientVersion = function() return clientVersion end,
  getProtocolVersion = function() return protocolVersion end,
  isPokeAllianceProtocol = function() return pka and clientVersion == 860 and protocolVersion == 854 end,
  setPokeAllianceProtocol = function(value) pka = value end,
  disableFeature = function(feature) assert(feature == GameAttackSeq); sequence = false end,
  enableFeature = function(feature) assert(feature == GameAttackSeq); sequence = true end,
  setCustomOs = function() end
}
g_app = {getOs = function() return 'android' end}
g_gameConfig = {setLastSupportedVersion = function() end}
g_logger = {info = function() end}
g_crypt = {rsaSetPublicKey = function() end}
function string.ends(value, suffix) return value:sub(-#suffix) == suffix end
assert(loadfile('modules/gamelib/game.lua'))()
G.currentRsa = OTSERV_RSA
g_game.chooseRsa('https://login.pokealliance.com/login')
assert(pka and not sequence, 'PKA 860/854 must omit attack sequences')
g_game.chooseRsa('login.example.org')
assert(not pka and sequence, 'ordinary 860 must regain attack sequences')
g_game.chooseRsa('pokealliance.com')
assert(pka and not sequence)
-- The profile decision also applies when an explicit custom RSA is configured.
G.currentRsa = 'custom'
sequence = true
g_game.chooseRsa('login.pokealliance.com')
assert(not sequence)
g_game.chooseRsa('login.example.org')
assert(sequence)
g_game.chooseRsa('login.pokealliance.com')
assert(not sequence)
-- Protocol can change before host selection while assets remain at 860.
protocolVersion = 860
g_game.chooseRsa('login.example.org')
assert(sequence, 'leaving PKA must restore 860 even after a protocol change')
-- An unrelated protocol/version must retain the feature chosen for it.
clientVersion, protocolVersion, sequence = 854, 854, false
g_game.chooseRsa('login.example.org')
assert(not sequence)
clientVersion, protocolVersion, sequence = 860, 860, true
g_game.chooseRsa('login.pokealliance.com')
assert(sequence, 'the PKA override is limited to the 860/854 profile')
io.write('Attack sequence profile switching OK\n')
