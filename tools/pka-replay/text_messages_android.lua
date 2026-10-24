-- Reproduce the real failure, then verify both extra modes and empty strings.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    assert(not g_game.isOnline() and not g_game.isLogging())
    local expected = json.decode(g_resources.readFileContents('/text-manifest.json'))
    local originalText = expected.originalTextHex:gsub('..', function(byte)
      return string.char(tonumber(byte, 16))
    end)
    local originalSeen, emptyAttention, emptyLoot, lootSeen, attentionSeen = false, false, false, false, false
    local function onTextMessage(mode, text)
      if mode == MessageModes.Attention then
        if text == originalText then originalSeen = true end
        if text == '' then emptyAttention = true end
        if text == 'PKA attention regression' then attentionSeen = true end
      elseif mode == MessageModes.Loot then
        if text == '' then emptyLoot = true end
        if text == 'PKA loot regression' then lootSeen = true end
      end
    end
    connect(g_game, {onTextMessage = onTextMessage})
    g_settings.set('protocol-diagnostics', 'off')
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.setPokeAllianceProtocol(true)
    g_game.enableFeature(GameOpcodeU16)
    g_game.playRecord('text-repro.cam')
    EnterGame.hide()
    if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    local elapsed = 0
    local function check()
      elapsed = elapsed + 2000
      local player = g_game.getLocalPlayer()
      local sentinel = player and player:getInventoryItem(4)
      local finished = sentinel and sentinel:getId() == expected.inventoryId and
        sentinel:getCountOrSubType() == expected.inventorySubtype
      if not finished and elapsed < expected.completionMs + 120000 then
        scheduleEvent(check, 2000)
        return
      end
      local passed = finished and g_game.isOnline() and player:isKnown() and
        originalSeen and emptyAttention and emptyLoot and lootSeen and attentionSeen
      disconnect(g_game, {onTextMessage = onTextMessage})
      g_logger.info('[coverage-replay] text original=' .. tostring(originalSeen) ..
        ' emptyAttention=' .. tostring(emptyAttention) .. ' emptyLoot=' .. tostring(emptyLoot) ..
        ' loot=' .. tostring(lootSeen) .. ' attention=' .. tostring(attentionSeen) ..
        ' sentinel=' .. tostring(not not finished) .. ' online=' .. tostring(g_game.isOnline()))
      g_logger.info('[coverage-replay] complete passed=' .. tostring(not not passed))
    end
    scheduleEvent(check, 2000)
  end, 1000)
end})
