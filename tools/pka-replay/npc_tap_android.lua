-- Offline input/event regression. All greeting/trade messages are intercepted.
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
    if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    scheduleEvent(function()
      local mod, interface = modules.game_npctrade, modules.game_interface
      local saved = {talk = g_game.talk, channel = g_game.talkChannel, lookup = g_map.getCreatureById,
        modifiers = g_keyboard.getModifiers, shortcut = modules.game_shortcuts.getShortcut, look = g_game.look}
      local function finish(ok, problem)
        mod.cancelNpcTradeRequest()
        g_game.talk, g_game.talkChannel, g_game.look = saved.talk, saved.channel, saved.look
        g_map.getCreatureById, g_keyboard.getModifiers = saved.lookup, saved.modifiers
        modules.game_shortcuts.getShortcut = saved.shortcut
        if not ok then g_logger.error('[npc-tap-probe] ' .. tostring(problem)) end
        g_logger.info('[npc-tap-probe] complete passed=' .. tostring(ok))
      end
      local p = g_game.getLocalPlayer():getPosition()
      local npc = {id = 0x70000001, name = 'Tap Test Merchant', position = {x = p.x + 1, y = p.y, z = p.z}, removed = false}
      function npc:getId() return self.id end
      function npc:getName() return self.name end
      function npc:getPosition() return self.position end
      function npc:isRemoved() return self.removed end
      function npc:isNpc() return true end
      local greetings, trades, looks = 0, 0, 0
      local shortcut = ''
      g_game.talk = function(text) assert(text == 'hi'); greetings = greetings + 1 end
      g_game.talkChannel = function(mode, channel, text)
        assert(mode == MessageModes.NpcTo and channel == 0 and text == 'trade')
        trades = trades + 1
      end
      g_game.look = function(thing) assert(thing == npc); looks = looks + 1 end
      g_keyboard.getModifiers = function() return KeyboardNoModifier end
      modules.game_shortcuts.getShortcut = function() return shortcut end
      g_map.getCreatureById = function(id) if id == npc.id then return npc end return saved.lookup(id) end
      local function tap()
        return interface.processMouseAction({x = 0, y = 0}, MouseLeftButton, npc.position, npc, nil, npc, npc)
      end
      local function reply(name, mode)
        signalcall(g_game.onTalk, name, 0, mode, 'Welcome', 0, npc.position)
      end
      local ok, problem = pcall(function()
        assert(g_game.isOnline() and tap() and greetings == 1 and trades == 0)
        assert(tap() and greetings == 1, 'Repeated tap sent another greeting')
        reply('Another NPC', MessageModes.NpcFrom)
        reply(npc.name, MessageModes.Say)
        assert(trades == 0)
        reply(npc.name, MessageModes.NpcFromStartBlock)
      end)
      if not ok then finish(ok, problem) return end
      scheduleEvent(function()
        local ok, problem = pcall(function()
          assert(trades == 1 and greetings == 1)
          reply(npc.name, MessageModes.NpcFrom)
          assert(tap() and greetings == 1, 'Trade handshake repeated')
          mod.cancelNpcTradeRequest()
          assert(tap() and greetings == 2)
          reply(npc.name, MessageModes.NpcFrom)
          mod.cancelNpcTradeRequest()
        end)
        if not ok then finish(ok, problem) return end
        scheduleEvent(function()
          local ok, problem = pcall(function()
            assert(trades == 1, 'Canceled deferred trade was still sent')
            npc.position.x = p.x + 4
            assert(not mod.requestNpcTrade(npc))
            npc.position.x, npc.position.z = p.x + 1, p.z + 1
            assert(not mod.requestNpcTrade(npc))
            npc.position.z, npc.removed = p.z, true
            assert(not mod.requestNpcTrade(npc))
            npc.removed = false
            local isPka = g_game.isPokeAllianceProtocol
            g_game.isPokeAllianceProtocol = function() return false end
            local rejected = not mod.requestNpcTrade(npc)
            g_game.isPokeAllianceProtocol = isPka
            assert(rejected, 'Non-PKA profile triggered shop request')
            shortcut = 'look'
            assert(tap() and looks == 1 and greetings == 2, 'Explicit Look action was intercepted')
            shortcut = ''
            assert(tap() and greetings == 3)
            reply(npc.name, MessageModes.NpcFrom)
            -- A shop in the greeting response must cancel the follow-up.
            signalcall(g_game.onOpenNpcTrade, {})
          end)
          if not ok then finish(ok, problem) return end
          scheduleEvent(function()
            local ok, problem = pcall(function()
              assert(trades == 1 and g_game.isOnline())
              assert(g_app.getMaxFps() == 60 and not g_sounds.isAudioEnabled())
              g_logger.info('[npc-tap-probe] input, one greeting/trade, selected NPC reply, debounce, cancellation, range/profile and Look guards passed')
            end)
            finish(ok, problem)
          end, 50)
        end, 50)
      end, 50)
    end, 9000)
  end, 1000)
end})
