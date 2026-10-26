-- Offline native UI regression. Stage with pokemon-actions.cam and the protocol
-- unit test; the runner must restore config AND /settings/clientoptions.json.
EnterGame.firstShow = function() end
local function report(ok, problem)
  if not ok then g_logger.error('[pokemon-actions] ' .. tostring(problem)) end
  g_logger.info('[pokemon-actions] complete passed=' .. tostring(ok))
end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    local ok, problem = pcall(function()
      g_settings.set('protocol-diagnostics', 'off')
      g_game.setClientVersion(860)
      g_game.setProtocolVersion(854)
      g_game.chooseRsa('login.pokealliance.com')
      g_game.enableFeature(GameOpcodeU16)
      PokemonProtocol = modules.game_pokemon.PokemonProtocol
      assert(loadstring(g_resources.readFileContents('/test_pokemon_protocol.lua')))()
      g_game.playRecord('pokemon-actions.cam')
      EnterGame.hide()
      if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
      scheduleEvent(function()
        local finalUi
        local passed, errorText = xpcall(function()
          assert(g_game.isOnline(), 'Offline replay disconnected')
          local mod, bar = modules.game_pokemon, modules.game_actionbar
          assert(mod.getState().roster[6].health == 46, 'Auxiliary updates lost following roster sentinel')
          local windows = mod.getWindows()
          local controls = modules.game_interface.getRootPanel():getChildById('mobilePanelControls')
          for _, id in ipairs({'pkaRoster', 'pkaConditions'}) do
            assert(windows[id]:getY() >= controls:getY() + controls:getHeight(),
              string.format('Default %s y=%d covers mobile controls bottom=%d', id, windows[id]:getY(), controls:getY() + controls:getHeight()))
          end
          local saved = {}
          for id, window in pairs(windows) do
            window:setPosition({x = window:getX() + 7, y = window:getY() + 9})
            window.minimize.onClick()
            saved[id] = g_settings.getNode('pka-window-' .. id)
          end
          mod.terminate()
          mod.init()
          for id, window in pairs(mod.getWindows()) do
            local parent = window:getParent()
            assert(window.minimized and window:getHeight() == 33)
            assert(window:getX() - parent:getX() == tonumber(saved[id].x))
            assert(window:getY() - parent:getY() == tonumber(saved[id].y))
            window.minimize.onClick()
          end
          g_logger.info('[pokemon-actions] auxiliary boundary and window recreation checks passed')

          local actionbar = assert(bar.actionBars[1])
          actionbar.locked = false
          local button = assert(actionbar.tabBar:getChildren()[1])
          local output = {}
          local originalProtocol = g_game.getProtocolGame
          g_game.getProtocolGame = function()
            return {send = function(self, msg) output[#output + 1] = msg:getBuffer() end}
          end
          local function dialog(itemId, actionType, multi)
            bar.ApiJson.createOrUpdateAction(1, 1, actionType, itemId, 0)
            bar.updateButton(button)
            if multi then
              button.cache.multiActions = {{useObject = itemId, useType = actionType, upgradeTier = 0}, {}, {}}
            end
            bar.assignItem(button, itemId, 0, false, multi and 1 or nil)
            return assert(bar.ActionBarController.ui, 'Assign item dialog absent')
          end
          local ui = dialog(3156, 'AutoRevive')
          local revive, pokemon = ui:querySelector('#AutoRevive'), ui:querySelector('#UseOnPokemon')
          assert(revive:isVisible() and revive:isEnabled() and revive:isChecked(), 'Revive option/preselection missing')
          assert(pokemon:isVisible() and pokemon:isEnabled(), 'Pokemon use option missing')
          pokemon:setChecked(true)
          assert(not revive:isChecked(), 'Item actions are not exclusive')
          revive:setChecked(true)
          assert(not pokemon:isChecked())
          local cancel = ui:querySelector('#buttonClose')
          assert(cancel:isVisible() and cancel:getY() + cancel:getHeight() <= ui:getY() + ui:getHeight(), 'Dialog footer clipped')
          ui:querySelector('#buttonOk').onClick()
          bar.ApiJson.saveData()
          assert(bar.ApiJson.loadData('/settings/clientoptions.json') and bar.ApiJson.refreshState())
          bar.updateButton(button)
          assert(button.cache.actionType == bar.UseTypes.AutoRevive, 'Saved action type changed')
          button.cache.lastClick = 0
          bar.onExecuteAction(button, false)
          assert(#output == 1 and output[1] == string.char(90,0,2,84,12,167), 'Real action bar revive bytes incorrect')
          button.cache.lastClick = 0
          button.cache.nextDownKey = 0
          bar.onExecuteAction(button, true)
          assert(#output == 1, 'Holding a hotkey repeated revive')

          ui = dialog(3156, 'UseOnPokemon', true)
          assert(ui:querySelector('#UseOnPokemon'):isChecked(), 'Multi-slot string preselection lost')
          ui:querySelector('#buttonOk').onClick()
          bar.ApiJson.saveData()
          assert(bar.ApiJson.loadData('/settings/clientoptions.json') and bar.ApiJson.refreshState())
          local slot = bar.ApiJson.getMapping(1, 1).actionsetting.multiActions
          assert(slot[1].useType == 'UseOnPokemon' and slot[1].useObject == 3156, 'Saved multi-slot action changed')
          assert(button.cache.multiActions[1].useType == 'UseOnPokemon')
          button.cache.actionType = bar.UseTypes.UseOnPokemon
          button.cache.lastClick = 0
          bar.onExecuteAction(button, false)
          assert(#output == 2 and output[2] == string.char(90,0,1,84,12), 'Pokemon item bytes incorrect')
          mod.parseOpcode(originalProtocol(), 0x60e, {getU8 = function() return 1 end})
          local clock, time = g_clock.millis, g_clock.millis()
          g_clock.millis = function() return time end
          assert(mod.flyHeight(false) and output[#output] == string.char(15,6,0))
          assert(not mod.flyHeight(true), 'Fly input ignored the original 200 ms gate')
          time = time + 200
          assert(mod.flyHeight(true) and output[#output] == string.char(15,6,1))
          g_clock.millis = clock
          g_game.getProtocolGame = originalProtocol

          -- A non-revive multi-use item must expose only the generic Pokemon
          -- option. Its gameplay name is deliberately not guessed here.
          local other
          for id = 100, 20000 do
            if not mod.isRevive(id) then
              local item = Item.create(id)
              if item and item:isMultiUse() then other = id break end
            end
          end
          assert(other, 'No non-revive multi-use fixture available')
          ui = dialog(other, 'UseOnPokemon')
          assert(ui:querySelector('#UseOnPokemon'):isEnabled() and ui:querySelector('#UseOnPokemon'):isChecked())
          assert(not ui:querySelector('#AutoRevive'):isEnabled())
          bar.ActionBarController:unloadHtml()
          local parse = mod.parseOpcode
          mod.parseOpcode = nil
          assert(not originalProtocol():onOpcode(0x777, InputMessage.create()), 'Unloaded Pokemon module broke opcode dispatch')
          mod.parseOpcode = parse
          g_game.chooseRsa('login.tibia.com')
          assert(not g_game.isPokeAllianceProtocol())
          assert(not mod.parseOpcode(originalProtocol(), 0x55, InputMessage.create()), 'Pokemon handler intercepted another profile')
          ui = dialog(3156, 'Use')
          assert(not ui:querySelector('#UseOnPokemon'):isVisible() and not ui:querySelector('#AutoRevive'):isVisible())
          assert(bar.getItemActionSpell(3156, 'AutoRevive') == Spells.getRuneSpellByItem(3156), 'Non-PKA rune lookup changed')
          bar.ActionBarController:unloadHtml()
          g_game.chooseRsa('login.pokealliance.com')
          finalUi = dialog(3156, 'AutoRevive')
          g_logger.info('[pokemon-actions] dialog, exclusive selection, JSON and real action execution checks passed')
          assert(g_app.getMaxFps() == 60 and not g_sounds.isAudioEnabled())
          -- Keep the last dialog open for the runner's screenshot.
        end, debug.traceback)
        if not passed then report(false, errorText) return end
        scheduleEvent(function()
          local layoutOk, layoutError = pcall(function()
            local cancel = finalUi:querySelector('#buttonClose')
            local revive = finalUi:querySelector('#AutoRevive')
            assert(revive:isEnabled() and revive:isChecked())
            assert(cancel:getY() + cancel:getHeight() <= finalUi:getY() + finalUi:getHeight(), 'Settled dialog footer is outside the window')
            assert(revive:getY() + revive:getHeight() <= cancel:getY(), 'Settled dialog options overlap footer')
          end)
          report(layoutOk, layoutError)
        end, 500)
      end, 8500)
    end)
    if not ok then report(false, problem) end
  end, 1000)
end})
