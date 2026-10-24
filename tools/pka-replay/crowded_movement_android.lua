-- Check both the crowded initial tile and final local-player membership.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    assert(not g_game.isOnline() and not g_game.isLogging())
    local expected = json.decode(g_resources.readFileContents('/crowded-manifest.json'))
    local probeSeen = false
    local function onMapDescription()
      local xyz = expected.probeTile
      local tile = g_map.getTile({x=xyz[1], y=xyz[2], z=xyz[3]})
      if tile and #tile:getThings() == expected.probeCount then
        probeSeen = true
      end
    end
    connect(g_game, {onMapDescription = onMapDescription})
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.setPokeAllianceProtocol(true)
    g_game.enableFeature(GameOpcodeU16)
    g_game.playRecord('crowded-movement.cam')
    EnterGame.hide()
    if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    scheduleEvent(function()
      disconnect(g_game, {onMapDescription = onMapDescription})
      local player = g_game.getLocalPlayer()
      local position = player and player:getPosition()
      local tile = player and player:getTile()
      local present = false
      if tile then
        for _, thing in ipairs(tile:getThings()) do
          if thing == player then present = true end
        end
      end
      local xyz = expected.expectedPosition
      local passed = player and player:isKnown() and g_game.isOnline() and
        probeSeen and present and position.x == xyz[1] and position.y == xyz[2] and
        position.z == xyz[3] and player:canWalk()
      g_logger.info('[coverage-replay] crowded probe=' .. tostring(probeSeen) ..
        ' inTile=' .. tostring(present) .. ' online=' .. tostring(g_game.isOnline()))
      g_logger.info('[coverage-replay] complete passed=' .. tostring(not not passed))
    end, expected.completionMs)
  end, 1000)
end})
