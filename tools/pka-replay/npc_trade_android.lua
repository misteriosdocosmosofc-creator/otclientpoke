-- Explicit offline NPC shop replay. Stage npc-trade.cam and the private
-- npc-trade-expectations.json; the runner restores the real settings afterward.
EnterGame.firstShow = function() end
local opened, balances = {}, {}
local closed = 0
connect(g_game, {
  onOpenNpcTrade = function(items) opened[#opened + 1] = items end,
  onPlayerGoods = function(money, goods) balances[#balances + 1] = {money = money, goods = goods} end,
  onCloseNpcTrade = function() closed = closed + 1 end
})

local function hex(text)
  return (text:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end

connect(g_app, {onRun = function()
  scheduleEvent(function()
    g_settings.set('protocol-diagnostics', 'off')
    g_game.setClientVersion(860)
    g_game.setProtocolVersion(854)
    g_game.chooseRsa('login.pokealliance.com')
    g_game.enableFeature(GameOpcodeU16)
    local expected = json.decode(g_resources.readFileContents('/npc-trade-expectations.json'))
    g_game.playRecord('npc-trade.cam')
    EnterGame.hide()
    if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
    scheduleEvent(function()
      local passed, problem = pcall(function()
        assert(g_app.getMaxFps() == 60 and not g_sounds.isAudioEnabled())
        if not expected.expectOnline then
          assert(not g_game.isOnline() and #opened == 0 and #balances == 0)
          g_logger.info('[npc-trade-probe] old parser reproduced disconnect before opening shop')
          return
        end
        assert(g_game.isOnline() and #opened == 3 and #balances == 3 and closed == 1)
        for _, index in ipairs({1, 3}) do
          local items, balance = opened[index], balances[index]
          assert(#items == #expected.offers and balance.money == expected.money)
          assert(#balance.goods == #expected.goods)
          for i, row in ipairs(expected.offers) do
            local actual = items[i]
            assert(actual[1]:getId() == row.id and actual[1]:getCountOrSubType() == row.subtype)
            assert(hex(actual[2]) == row.nameHex and actual[3] == row.weight)
            assert(actual[4] == row.buy and actual[5] == row.sell)
          end
          for i, row in ipairs(expected.goods) do
            assert(balance.goods[i][1]:getId() == row[1] and balance.goods[i][2] == row[2])
          end
        end
        -- Synthetic wide-value controls also traverse the real C++ -> Lua path.
        assert(opened[2][1][4] == 4294967297 and opened[2][1][5] == 0)
        assert(opened[2][1][1]:getCountOrSubType() == 4660)
        assert(balances[2].goods[1][2] == 305419896)
        local window = assert(g_ui.getRootWidget():recursiveGetChildById('npcWindow'))
        assert(window:isVisible())
        local buy, sell = window:getChildById('buyTab'), window:getChildById('sellTab')
        assert(type(buy.onClick) == 'function' and type(sell.onClick) == 'function')
        sell.onClick(sell)
        assert(sell:isChecked() and window:recursiveGetChildById('itemsPanel'):getChildCount() > 0)
        buy.onClick(buy)
        assert(buy:isChecked() and window:recursiveGetChildById('itemsPanel'):getChildCount() > 0)
        if g_platform.isMobile() and window:getChildById('closeTopButton') then
          local area = window:getParent():getPaddingRect()
          local function contained(widget)
            local rect = widget:getRect()
            return rect.x >= area.x and rect.y >= area.y and
              rect.x + rect.width <= area.x + area.width and rect.y + rect.height <= area.y + area.height
          end
          assert(contained(window), 'NPC window exceeds the mobile viewport')
          local top, footer = window:getChildById('closeTopButton'), window:getChildById('closeFooterButton')
          assert(top:isVisible() and contained(top) and contained(footer), 'Close control is outside the screen')
          local function checkClose(button)
            local original, calls = g_game.closeNpcTrade, 0
            g_game.closeNpcTrade = function() calls = calls + 1 end
            local ok, problem = pcall(function() button.onClick(button) end)
            g_game.closeNpcTrade = original
            assert(ok, tostring(problem))
            assert(calls == 1 and not window:isVisible() and g_game.isOnline())
            modules.game_npctrade.controllerNpcTrader:legacy_show()
          end
          checkClose(top)
          checkClose(footer)
          g_logger.info('[npc-trade-probe] mobile window and both close controls fit; X/footer close and reopen passed')
        end
        g_logger.info('[npc-trade-probe] 335 real offers, 9 goods, prices/amounts, close/reopen and Buy/Sell tabs passed')
      end)
      if not passed then g_logger.error('[npc-trade-probe] ' .. tostring(problem)) end
      scheduleEvent(function()
        g_logger.info('[npc-trade-probe] complete passed=' .. tostring(passed))
      end, 500)
    end, 11000)
  end, 1000)
end})
