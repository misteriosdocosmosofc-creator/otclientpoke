-- Offline regression for PKA's signed DAT displacement and mobile action icons.
-- Stage the explicit private displacements.json and dismount-bootstrap.cam.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    local ok, problem = pcall(function()
      g_settings.set('protocol-diagnostics', 'off')
      g_game.setClientVersion(860)
      g_game.setProtocolVersion(854)
      g_game.chooseRsa('login.pokealliance.com')
      g_game.enableFeature(GameOpcodeU16)
      assert(not g_game.getFeature(GameNegativeOffset), 'PKA must not change the global negative-offset feature')
      local expected = json.decode(g_resources.readFileContents('/displacements.json'))
      assert(g_things.getDatSignature() == expected.datSignature)
      local mismatches = 0
      for _, row in ipairs(expected.entries) do
        local actual = g_things.getThingType(row.id, row.category):getDisplacement()
        if actual.x ~= row.x or actual.y ~= row.y then
          mismatches = mismatches + 1
          if mismatches <= 5 then
            g_logger.info(string.format('[displacement-probe] mismatch category=%d id=%d expected=%d,%d actual=%d,%d',
              row.category, row.id, row.x, row.y, actual.x, actual.y))
          end
        end
      end
      assert(mismatches == 0, 'Signed DAT displacement mismatches: ' .. mismatches)
      local trainer = g_things.getThingType(3860, ThingCategoryCreature):getDisplacement()
      assert(trainer.x == -16 and trainer.y == -16, 'Observed dismount outfit must use -16, not 65520')
      g_logger.info(string.format('[displacement-probe] DAT passed entries=%d negative=%d', #expected.entries, expected.negativeEntries))
      g_game.playRecord('dismount-bootstrap.cam')
      EnterGame.hide()
      if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
      scheduleEvent(function()
        local passed, errorText = pcall(function()
          assert(g_game.isOnline())
          local player = assert(g_game.getLocalPlayer())
          local before = player:getOutfit()
          -- Reproduce only the observed appearance transition in an offline
          -- recording. No order, mount, movement or item command is sent.
          player:setOutfit({type = 3860, head = 72, body = 51, legs = 68, feet = 84, addons = 0})
          assert(player:getOutfit().type == 3860 and player:getHealthPercent() > 0)
          assert(not player:isRemoved() and player:canBeSeen() and not player:isInvisible())
          local present = false
          for _, thing in ipairs(g_map.getTile(player:getPosition()):getThings()) do
            if thing == player then present = true break end
          end
          assert(present and modules.game_interface.getMapPanel():getFollowingCreature() == player)
          local buttons = modules.game_shortcuts.getPanel().shortcutIcons
          for id, icon in pairs({attack = 'pka-order', use = 'pka-pokeball', follow = 'pka-fly'}) do
            local button = buttons:getChildById(id)
            assert(button.pokemonAction and button.caption:isVisible())
            assert(button.image:getImageSource():find(icon, 1, true), 'Wrong action icon')
            assert(g_resources.fileExists('/images/game/mobile/' .. icon .. '.png'), 'Missing action icon')
          end
          assert(buttons.look.image:getImageSource():find('/look', 1, true), 'Look icon changed')
          assert(g_app.getMaxFps() == 60 and not g_sounds.isAudioEnabled())
          g_logger.info(string.format('[displacement-probe] offline outfit transition %d -> 3860; player/tile/camera and action icons passed', before.type))
        end)
        if not passed then g_logger.error('[displacement-probe] ' .. tostring(errorText)) end
        -- Let both the outfit texture and the icon layout settle for the screenshot.
        scheduleEvent(function()
          g_logger.info('[displacement-probe] complete passed=' .. tostring(passed))
        end, 750)
      end, 8500)
    end)
    if not ok then
      g_logger.error('[displacement-probe] ' .. tostring(problem))
      g_logger.info('[displacement-probe] complete passed=false')
    end
  end, 1000)
end})
