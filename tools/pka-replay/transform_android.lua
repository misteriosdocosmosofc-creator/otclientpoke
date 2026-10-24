-- Exact received session followed by empty, single and multi-record batches.
EnterGame.firstShow = function() end
connect(g_app, {onRun=function()
  scheduleEvent(function()
    assert(not g_game.isOnline() and not g_game.isLogging())
    local expected = json.decode(g_resources.readFileContents('/transform-manifest.json'))
    g_settings.set('protocol-diagnostics', 'off')
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.setPokeAllianceProtocol(true)
    g_game.enableFeature(GameOpcodeU16)
    g_game.playRecord('transform-repro.cam')
    EnterGame.hide()
    if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    local elapsed = 0
    local function check()
      elapsed = elapsed + 2000
      local player = g_game.getLocalPlayer()
      local sentinel = player and player:getInventoryItem(4)
      local finished = sentinel and sentinel:getId() == expected.inventoryId and sentinel:getCountOrSubType() == expected.inventorySubtype
      if not finished and elapsed < expected.completionMs + 90000 then
        scheduleEvent(check, 2000)
        return
      end
      local creature = g_map.getCreatureById(expected.creatureId)
      local pos = creature and creature:getPosition()
      local passed = finished and g_game.isOnline() and creature and pos and
        pos.x == expected.position[1] and pos.y == expected.position[2] and pos.z == expected.position[3] and
        creature:getDirection() == expected.direction and player:getDirection() == expected.playerDirection
      g_logger.info('[coverage-replay] transform online=' .. tostring(g_game.isOnline()) ..
        ' sentinel=' .. tostring(not not finished) .. ' target=' .. tostring(creature and creature:getId()) ..
        ' direction=' .. tostring(creature and creature:getDirection()) .. ' playerDirection=' .. tostring(player and player:getDirection()))
      g_logger.info('[coverage-replay] complete passed=' .. tostring(not not passed))
    end
    scheduleEvent(check, 2000)
  end, 1000)
end})
