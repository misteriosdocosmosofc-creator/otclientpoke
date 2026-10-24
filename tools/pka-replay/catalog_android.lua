-- Metadata + explicit received-only catalog replay in the installed engine.
-- run_android_probe.py restores both startup hook and settings after this test.
function assetProbeAfterAudit()
  g_game.enableFeature(GameOpcodeU16)
  g_game.playRecord('catalog-coverage.cam')
  EnterGame.hide()
  if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
  local expected = json.decode(g_resources.readFileContents('/catalog-manifest.json'))
  scheduleEvent(function()
    local player = g_game.getLocalPlayer()
    local last = player and player:getInventoryItem(4)
    local sentinel = player and player:getInventoryItem(5)
    local outfit = player and player:getOutfit()
    local passed = g_game.isOnline() and player:isKnown() and last and last:getId() == expected.expectedInventory4 and sentinel and sentinel:getId() == expected.expectedInventory5 and outfit and outfit.type == expected.expectedOutfit
    g_logger.info('[coverage-replay] last-item=' .. tostring(last and last:getId()) .. ' sentinel=' .. tostring(sentinel and sentinel:getId()) .. ' outfit=' .. tostring(outfit and outfit.type))
    g_logger.info('[coverage-replay] complete passed=' .. tostring(not not passed))
  end, expected.completionMs)
end
dofile('/audit_android.lua')
