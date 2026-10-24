-- Run from the repository root with Lua 5.1/LuaJIT or LuaJIT's host/minilua.
-- Exercise the production joystick listener without a server or a UI.
local tests, sent, predicted, stops, scheduled = 0, 0, 0, 0, 0
local listener, playerEvents
local pka, allowed, locked, dead, serverWalking, passable = true, true, false, false, false, true
local player = {}
North, East, South, West = 0, 1, 2, 3
NorthEast, SouthEast, SouthWest, NorthWest = 4, 5, 6, 7
GameAllowPreWalk, GameForceFirstAutoWalkStep = 122, 123
LocalPlayer = {}
Controller = {new = function()
    return {registerEvents = function(self, target, events)
        if target == LocalPlayer then playerEvents = events end
    end}
end}
local activePlayer = player
g_game = {
    isPokeAllianceProtocol = function() return pka end,
    getLocalPlayer = function() return activePlayer end,
    isDead = function() return false end,
    isFollowing = function() return false end,
    getFeature = function(feature) return feature == GameAllowPreWalk end,
    walk = function() sent = sent + 1; return true end,
    stop = function() stops = stops + 1 end,
    isOfficialTibia = function() return false end,
    enableFeature = function() end
}
player.isDead = function() return dead end
player.isWalkLocked = function() return locked end
player.isAutoWalking = function() return false end
player.isServerWalking = function() return serverWalking end
player.canWalk = function() return allowed and not locked and not dead end
player.getPosition = function() return {x = 100, y = 100, z = 7} end
player.getStepDuration = function() return 200 end
player.preWalk = function() predicted = predicted + 1; allowed = false end
player.lockWalk = function() locked = true end
g_clock = {millis = function() return 1000 end}
Position = {translatedToDirection = function() return {x = 101, y = 100, z = 7} end}
g_map = {getTile = function(pos)
    if pos.z ~= 7 then return nil end
    return {isWalkable = function() return passable end,
            hasElevation = function() return false end,
            hasFloorChange = function() return false end}
end}
local rootPanel = {}
modules = {
    game_joystick = {addOnJoystickMoveListener = function(callback) listener = callback end},
    game_interface = {getRootPanel = function() return rootPanel end}
}
function removeEvent() end
function scheduleEvent() scheduled = scheduled + 1 end
function addEvent() scheduled = scheduled + 1 end
local function check(condition, message)
    assert(condition, message)
    tests = tests + 1
end

assert(loadfile('modules/game_walk/walk.lua'))()
WalkController:onGameStart()
check(type(listener) == 'function', 'joystick listener was not registered')
check(listener(East) == true and sent == 1 and predicted == 1,
      'first allowed step must predict and send once')
for i = 1, 100 do listener(East) end
check(sent == 1, 'held joystick sent steps while awaiting confirmation')
allowed = true
playerEvents.onWalkFinish(player)
check(sent == 1 and scheduled == 0, 'release left a queued step')
listener(North)
check(sent == 2 and predicted == 2, 'confirmed movement did not permit the next step')

allowed, locked = true, true
listener(East)
check(sent == 2, 'walk lock did not suppress joystick movement')
locked, dead = false, true
listener(East)
check(sent == 2, 'dead player was allowed to walk')
dead, passable = false, false
listener(East)
check(sent == 2 and predicted == 2, 'blocked tile was sent or prewalked')
passable, serverWalking = true, true
listener(East)
check(sent == 2 and stops == 1 and locked, 'server walk did not use keyboard stop/lock path')
serverWalking, locked = false, false
activePlayer = nil
check(listener(East) == false and sent == 2, 'offline listener attempted movement')

-- Other profiles retain their existing joystick behavior.
pka, activePlayer, allowed = false, player, false
check(listener(East) == true and sent == 3, 'non-PKA behavior changed')
io.write('joystick regression passed: ' .. tests .. ' checks\n')
