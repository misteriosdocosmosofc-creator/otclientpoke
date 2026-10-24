-- Explicit offline metadata audit. No world login or persistent changes.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    assert(not g_game.isOnline() and not g_game.isLogging())
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.setPokeAllianceProtocol(true)
    assert(g_things.isDatLoaded() and g_sprites.isLoaded())
    local expected = json.decode(g_resources.readFileContents('/coverage-expectations.json'))
    local category, ident, definitions, references, mismatches = 0, 100, 0, 0, 0
    local function batch()
      for _ = 1, 200 do
        local maximum = expected.highestIds[category + 1]
        if ident > maximum then
          g_logger.info('[asset-probe] category=' .. category .. ' highest=' .. maximum .. ' finished')
          category, ident = category + 1, 1
          if category == 4 then
            g_logger.info('[asset-probe] definitions=' .. definitions .. ' references=' .. references .. ' mismatches=' .. mismatches)
            if assetProbeAfterAudit and mismatches == 0 then
              assetProbeAfterAudit()
            else
              g_logger.info('[asset-probe] complete passed=' .. tostring(mismatches == 0))
            end
            return
          end
        end
        local thing = g_things.getThingType(ident, category)
        local sprites = thing:getSprites()
        local size = thing:getSize()
        local count = size.width * size.height * thing:getLayers() * thing:getNumPatternX() * thing:getNumPatternY() * thing:getNumPatternZ() * thing:getAnimationPhases()
        assert(#sprites == count and count > 0, 'Invalid native composition for ' .. category .. ':' .. ident)
        for _, sprite in ipairs(sprites) do
          assert(sprite >= 0 and sprite <= g_sprites.getSpritesCount(), 'Sprite reference outside SPR')
        end
        if category == 0 then
          local flags = (thing:isStackable() and 1 or 0) + (thing:isFluidContainer() and 2 or 0) + (thing:isSplash() and 4 or 0) + (thing:isChargeable() and 8 or 0)
          local wanted = expected.itemFlags[tostring(ident)] or 0
          if flags ~= wanted then
            mismatches = mismatches + 1
            if mismatches <= 40 then
              g_logger.info('[asset-probe] flag-mismatch item=' .. ident .. ' expected=' .. wanted .. ' actual=' .. flags)
            end
          end
        end
        definitions, references, ident = definitions + 1, references + #sprites, ident + 1
      end
      scheduleEvent(batch, 1)
    end
    batch()
  end, 1000)
end})
