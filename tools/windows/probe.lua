-- Offline desktop integration. Install only in a dedicated --user-dir as
-- pka_windowsrc.lua, together with records/npc-trade.cam. Never use a live account.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    local ok, problem = pcall(function()
      assert(not g_platform.isMobile(), 'Expected native desktop')
      g_settings.set('protocol-diagnostics', 'off')
      g_game.setClientVersion(860)
      assert(g_game.getClientVersion() == 860, 'Updated DAT/SPR did not load')
      g_game.setProtocolVersion(854)
      g_game.chooseRsa('login.pokealliance.com')
      g_game.enableFeature(GameOpcodeU16)
      g_game.playRecord('npc-trade.cam')
      EnterGame.hide()
      if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    end)
    if not ok then g_logger.error('[windows-probe] bootstrap: ' .. tostring(problem)) return end
    scheduleEvent(function()
      local ok, problem = pcall(function()
        assert(g_game.isOnline(), 'Replay did not enter the world')
        local player = assert(g_game.getLocalPlayer())
        assert(g_map.getTile(player:getPosition()), 'Player tile missing')
        local pokemon = modules.game_pokemon
        local windows = pokemon.getWindows()
        local area = modules.game_interface.getRootPanel():getRect()
        for _, id in ipairs({'pkaRoster', 'pkaMoves', 'pkaConditions', 'pkaFly'}) do
          local w = assert(windows[id], 'Missing desktop window ' .. id)
          assert(w:isVisible(), 'Hidden desktop window ' .. id)
          assert(w:getX() >= area.x and w:getY() >= area.y, 'Window starts outside viewport')
          assert(w:getX() + w:getWidth() <= area.x + area.width, 'Window exceeds viewport width')
          assert(w:getY() + w:getHeight() <= area.y + area.height, 'Window exceeds viewport height')
          w.minimize.onClick()
          assert(w:getHeight() == 33)
          w.minimize.onClick()
        end
        assert(windows.pkaFly.contents:getChildCount() == 3, 'Desktop order button missing')
        -- All outbound action functions are intercepted for this fixture.
        local oldTalk, oldPrivate = g_game.talk, g_game.talkPrivate
        local sentMove, greetings = 0, 0
        g_game.talk = function(text) assert(text == 'm7') sentMove = sentMove + 1 end
        g_game.talkPrivate = function(mode, receiver, text)
          assert(mode == MessageModes.NpcTo and receiver == 'NPCs' and text == 'hi')
          greetings = greetings + 1
        end
        local actionOk, actionProblem = pcall(function()
          local state = pokemon.getState()
          state.moves = {{key = 'm7', name = 'Fixture Burn Up', remaining = 0, received = g_clock.millis()}}
          assert(pokemon.castMove(1) and sentMove == 1)
          state.moves[1].remaining = 10
          assert(not pokemon.castMove(1) and sentMove == 1)
          local pos = player:getPosition()
          local npc = {}
          function npc:getPosition() return {x = pos.x + 1, y = pos.y, z = pos.z} end
          function npc:isRemoved() return false end
          function npc:isNpc() return true end
          function npc:getId() return 0x70000001 end
          function npc:getName() return 'Offline desktop merchant' end
          assert(modules.game_npctrade.requestNpcTrade(npc) and greetings == 1)
          assert(modules.game_npctrade.requestNpcTrade(npc) and greetings == 1)
          modules.game_npctrade.cancelNpcTradeRequest()
        end)
        g_game.talk, g_game.talkPrivate = oldTalk, oldPrivate
        assert(actionOk, actionProblem)
        modules.game_bot.refresh()
        local bot = modules.game_bot.PkaBot
        bot.toggle()
        assert(bot.getDiagnostics().window:isVisible())
        assert(not bot.getDiagnostics().running, 'Bot started automatically')
        bot.hide()
        g_logger.info('[windows-probe] map, desktop windows, minimize, skills, cooldown, private NPC, bot idle PASS')
      end)
      if not ok then g_logger.error('[windows-probe] ' .. tostring(problem)) end
      g_logger.warning('[windows-probe] complete passed=' .. tostring(ok))
      g_app.doScreenshot('windows-probe.png')
    end, 2500)
  end, 1000)
end})
