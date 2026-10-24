-- Metadata + explicit received-only catalog replay in the installed engine.
-- run_android_probe.py restores both startup hook and settings after this test.
function assetProbeAfterAudit()
  -- Per-object tracing dominates the timing of a 52k-item stress fixture.
  -- Count real Lua events instead; the wrapper restores the original settings.
  g_settings.set('protocol-diagnostics', 'off')
  g_game.enableFeature(GameOpcodeU16)
  g_game.playRecord('catalog-coverage.cam')
  EnterGame.hide()
  if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
  local expected = json.decode(g_resources.readFileContents('/catalog-manifest.json'))
  local player = g_game.getLocalPlayer()
  local seenItems, seenOutfits, itemCount, outfitCount = {}, {}, 0, 0
  local signals = {
    onInventoryChange = function(_, slot, item)
      if slot == 4 and item then
        local id = item:getId()
        if id >= 100 and id <= expected.expectedInventory4 and not seenItems[id] then
          seenItems[id], itemCount = true, itemCount + 1
        end
      end
    end,
    onOutfitChange = function(_, outfit)
      local id = outfit.type
      if id and id > 0 and id <= expected.expectedOutfit and not seenOutfits[id] then
        seenOutfits[id], outfitCount = true, outfitCount + 1
      end
    end
  }
  connect(player, signals)
  local attempts = 0
  local function checkpoint()
    local player = g_game.getLocalPlayer()
    local last = player and player:getInventoryItem(4)
    local sentinel = player and player:getInventoryItem(5)
    local outfit = player and player:getOutfit()
    local passed = g_game.isOnline() and player:isKnown() and last and last:getId() == expected.expectedInventory4 and sentinel and sentinel:getId() == expected.expectedInventory5 and outfit and outfit.type == expected.expectedOutfit and itemCount == expected.items and outfitCount == expected.outfits
    attempts = attempts + 1
    if not passed and g_game.isOnline() and attempts < 120 then
      if attempts % 5 == 1 then
        g_logger.info('[coverage-replay] draining items=' .. itemCount .. ' outfits=' .. outfitCount)
      end
      scheduleEvent(checkpoint, 2000)
      return
    end
    disconnect(player, signals)
    g_logger.info('[coverage-replay] distinct-items=' .. itemCount .. ' distinct-outfits=' .. outfitCount)
    g_logger.info('[coverage-replay] last-item=' .. tostring(last and last:getId()) .. ' sentinel=' .. tostring(sentinel and sentinel:getId()) .. ' outfit=' .. tostring(outfit and outfit.type))
    g_logger.info('[coverage-replay] catalog passed=' .. tostring(not not passed))
    if not passed then
      g_logger.info('[coverage-replay] complete passed=false')
      return
    end
    g_game.cancelLogin()
    scheduleEvent(function()
      g_game.playRecord('movement-repro.cam')
      scheduleEvent(function()
        local movingPlayer = g_game.getLocalPlayer()
        local pos = movingPlayer and movingPlayer:getPosition()
        local movementPassed = g_game.isOnline() and pos and pos.x == 3324 and pos.y == 2058 and pos.z == 7
        g_logger.info('[coverage-replay] movement passed=' .. tostring(not not movementPassed))
        g_logger.info('[coverage-replay] complete passed=' .. tostring(not not movementPassed))
      end, 45000)
    end, 300)
  end
  scheduleEvent(checkpoint, expected.completionMs)
end
dofile('/audit_android.lua')
