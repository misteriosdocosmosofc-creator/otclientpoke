-- Offline engine integration: no messages are sent to a real server.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    g_settings.set('protocol-diagnostics', 'off')
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.chooseRsa('login.pokealliance.com')
    g_game.enableFeature(GameOpcodeU16)
    g_game.playRecord('npc-trade.cam')
    EnterGame.hide()
    scheduleEvent(function()
      local bot = modules.game_bot.PkaBot
      local pokemon = modules.game_pokemon
      local oldGet, oldCast = pokemon.getState, pokemon.castMove
      local sends = 0
      local fixture = {selected = {mode = 1, name = 'Arcanine', identity = 'offline-test'}, moves = {
        {name = 'Burn Up', key = 'm7', remaining = 0, received = g_clock.millis()},
        {name = 'Fireball', key = 'm3', remaining = 0, received = g_clock.millis()}}}
      pokemon.getState = function() return fixture end
      pokemon.castMove = function(i) assert(i == 1 or i == 2) sends = sends + 1 return true end
      local function finish(ok, problem)
        bot.offline()
        pokemon.getState, pokemon.castMove = oldGet, oldCast
        if not ok then g_logger.error('[pka-bot-probe] ' .. tostring(problem)) end
        g_logger.info('[pka-bot-probe] complete passed=' .. tostring(ok))
      end
      local ok, problem = pcall(function()
        assert(g_game.isOnline())
        modules.game_bot.refresh()
        bot.toggle()
        local d = bot.getDiagnostics()
        assert(d.window:isVisible() and not modules.game_bot.botWindow:isVisible())
        assert(not d.running and not d.recording)
        assert(#d.profile.order == 2)
        local area = d.window:getParent():getPaddingRect()
        assert(d.window:getWidth() <= area.width and d.window:getHeight() <= area.height)
        for _, b in ipairs(d.window.tabs:getChildren()) do b.onClick() end
        d.window.tabs:getChildren()[1].onClick()
        assert(not bot.executeCombo(), 'unselected skills must not run')
        d.profile.moves.m7.enabled = true
        d.profile.moves.m3.enabled = true
        d.profile.interval = 100
        assert(bot.executeCombo() and sends == 1)
        d.hud.pause.onClick()
        assert(not bot.getDiagnostics().actionTimer)
        assert(bot.mark('cobertura'))
        assert(bot.mark('combate'))
        bot.hide()
        assert(not bot.getDiagnostics().timer)
        bot.offline()
        bot.online()
        assert(#bot.getDiagnostics().profile.order == 2, 'saved skill order did not survive reload')
        assert(#bot.getDiagnostics().config.route >= 2, 'saved route did not survive reload')
      end)
      if not ok then finish(ok, problem) return end
      scheduleEvent(function()
        local ok, problem = pcall(function()
          assert(sends == 1, 'pause allowed a delayed action')
          bot.toggle()
          fixture.moves[1].remaining = 5
          fixture.moves[1].received = g_clock.millis()
          assert(not bot.executeCombo(), 'cooldown was ignored')
          fixture.moves[1].remaining = 0
          assert(bot.executeCombo())
          fixture.selected.identity = 'switched'
        end)
        if not ok then finish(ok, problem) return end
        scheduleEvent(function()
          local ok, problem = pcall(function()
            assert(sends == 2, 'Pokemon switch allowed a delayed action')
            assert(not bot.getDiagnostics().running)
            local d = bot.getDiagnostics()
            d.window.footer.compact.onClick()
            assert(d.hud:isVisible() and not d.window:isVisible())
            d.hud.configure.onClick()
            assert(d.window:isVisible())
            local before = bot.getDiagnostics().rebuilds
            bot.hide()
            assert(bot.getDiagnostics().rebuilds == before and not bot.getDiagnostics().timer)
          end)
          -- Keep the UI visible for the runner screenshot; stop action state.
          if not ok then finish(ok, problem) return end
          local hiddenRefreshes = bot.getDiagnostics().refreshes
          scheduleEvent(function()
            local ok, problem = pcall(function()
              assert(bot.getDiagnostics().refreshes == hiddenRefreshes, 'closed view still polling')
              bot.toggle()
            end)
            if not ok then finish(ok, problem) return end
            local visible = bot.getDiagnostics()
            scheduleEvent(function()
              local ok, problem = pcall(function()
                local d = bot.getDiagnostics()
                assert(d.rebuilds == visible.rebuilds, 'unchanged view rebuilt')
                local polls = d.refreshes - visible.refreshes
                assert(polls >= 1 and polls <= 4, 'unexpected polling cadence')
                g_logger.info('[pka-bot-probe] hidden polls=0; visible polls=' .. polls ..
                  ' over 1800ms; unchanged rebuilds=0; fps sample=' .. g_app.getFps())
              end)
              if not ok then finish(ok, problem) return end
              g_logger.info('[pka-bot-probe] complete passed=true')
            end, 1800)
          end, 1800)
        end, 250)
      end, 250)
    end, 1500)
  end, 100)
end})
