-- Received-only fixture: fluid subtype U16 followed by an inventory sentinel.
EnterGame.firstShow = function() end
connect(g_app, {onRun=function()
  scheduleEvent(function()
    assert(not g_game.isOnline() and not g_game.isLogging())
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.setPokeAllianceProtocol(true)
    g_game.enableFeature(GameOpcodeU16)
    g_game.playRecord('fluid-width-repro.cam')
    EnterGame.hide()
    if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    scheduleEvent(function()
      local player = g_game.getLocalPlayer()
      local fluid = player and player:getInventoryItem(4)
      local sentinel = player and player:getInventoryItem(5)
      local passed = g_game.isOnline() and fluid and fluid:getId() == 869 and fluid:getCountOrSubType() == 0x1234 and sentinel and sentinel:getId() == 100
      g_logger.info('[coverage-replay] fluid=' .. tostring(fluid and fluid:getId()) .. ' subtype=' .. tostring(fluid and fluid:getCountOrSubType()) .. ' sentinel=' .. tostring(sentinel and sentinel:getId()))
      g_logger.info('[coverage-replay] complete passed=' .. tostring(not not passed))
    end, 10000)
  end, 1000)
end})
