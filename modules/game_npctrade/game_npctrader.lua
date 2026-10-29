controllerNpcTrader = Controller:new()
controllerNpcTrader.widthConsole = controllerNpcTrader.DEFAULT_CONSOLE_WIDTH
controllerNpcTrader.creatureName = ""
controllerNpcTrader.outfit = nil
controllerNpcTrader.buttons = {}
controllerNpcTrader.isTradeOpen = false
controllerNpcTrader.legacyMode = false
controllerNpcTrader.npcTalkConnected = false

local tapTrade = nil

local function cancelTapTrade()
    if tapTrade then
        if tapTrade.timeout then removeEvent(tapTrade.timeout) end
        if tapTrade.followup then removeEvent(tapTrade.followup) end
        tapTrade = nil
    end
end

function cancelNpcTradeRequest()
    cancelTapTrade()
end

local function inNpcRange(npc)
    local player = g_game.getLocalPlayer()
    if not player or not npc or npc:isRemoved() then return false end
    local p, n = player:getPosition(), npc:getPosition()
    return p and n and p.z == n.z and math.max(math.abs(p.x - n.x), math.abs(p.y - n.y)) <= 3
end

local function sendNpcTradeMessage(text)
    local console = modules.game_console
    if console and console.addTab and console.sendMessage then
        local tab = console.addTab('NPCs', true)
        tab.npcChat = true
        tab.channelId = nil
        console.sendMessage(text, tab)
    else
        -- Preserve private NPC routing even if the chat module is unavailable.
        g_game.talkChannel(MessageModes.NpcTo, 0, text)
    end
end

function requestNpcTrade(npc)
    if not g_platform.isMobile() or not g_game.isPokeAllianceProtocol() or not g_game.isOnline() or
       not npc or not npc:isNpc() or not inNpcRange(npc) then return false end
    if tapTrade and tapTrade.id == npc:getId() then return true end
    cancelTapTrade()
    local request = {id = npc:getId(), name = npc:getName(), sentTrade = false}
    tapTrade = request
    request.timeout = scheduleEvent(function()
        if tapTrade == request then cancelTapTrade() end
    end, 5000)
    g_game.getLocalPlayer():stopAutoWalk()
    sendNpcTradeMessage('hi')
    return true
end

local function onTapNpcTalk(name, level, mode)
    local request = tapTrade
    if not request or request.sentTrade or request.followup or name ~= request.name or
       (mode ~= MessageModes.NpcFrom and mode ~= MessageModes.NpcFromStartBlock) then return end
    -- Defer to the end of the receive packet: if the greeting already carries
    -- a shop catalog, onOpenNpcTrade cancels this request before sending trade.
    request.followup = addEvent(function()
        if tapTrade ~= request then return end
        request.followup = nil
        local npc = g_map.getCreatureById(request.id)
        if not g_game.isPokeAllianceProtocol() or not g_game.isOnline() or not inNpcRange(npc) then
            cancelTapTrade()
            return
        end
        request.sentTrade = true
        sendNpcTradeMessage('trade')
    end)
end

function controllerNpcTrader:isLegacyMode()
    return self.legacyMode
end

function controllerNpcTrader:onInit()

end

function controllerNpcTrader:onGameStart()
    self.legacyMode = not g_game.getFeature(GameNpcWindowRedesign)
    if self:isLegacyMode() then
        self:legacy_init()
    end

    self:registerEvents(g_game, {
        onTalk = onTapNpcTalk,
        onNpcChatWindow = function(data)
            onNpcChatWindow(data)
        end,
        onOpenNpcTrade = function(...)
            cancelTapTrade()
            self:startEquippedImbuementsTracking()
            if self:isLegacyMode() then
                onOpenNpcTrade(...)
            else
                self:onOpenNpcTrade(...)
            end
        end,
        onPlayerGoods = function(money, items)
            if self:isLegacyMode() then
                onPlayerGoods(money, items)
            else
                self:onPlayerGoods(money, items)
            end
        end,
        onUpdateImbuementTracker = function(items)
            self:onUpdateEquippedImbuements(items)
        end,
        onNpcChatWindowClose = function()
            self:stopEquippedImbuementsTracking()
            if self:isLegacyMode() then
                self:legacy_hide()
            else
                self:onCloseNpcTrade()
            end
        end,
        onCloseNpcTrade = function()
            self:stopEquippedImbuementsTracking()
            if self:isLegacyMode() then
                self:legacy_hide()
            else
                self:onCloseNpcTrade()
            end
        end
    })
end

function controllerNpcTrader:connectNpcTalkEvent()
    if self:isLegacyMode() or self.npcTalkConnected then
        return
    end

    connect(g_game, {
        onTalk = onNpcTalk
    })
    self.npcTalkConnected = true
end

function controllerNpcTrader:disconnectNpcTalkEvent()
    if not self.npcTalkConnected then
        return
    end

    disconnect(g_game, {
        onTalk = onNpcTalk
    })
    self.npcTalkConnected = false
end

function controllerNpcTrader:onTerminate()
    cancelTapTrade()
    if self:isLegacyMode() then
        self:legacy_terminate()
    else
        self:onCloseNpcTrade()
    end
end

function controllerNpcTrader:onGameEnd()
    cancelTapTrade()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:onCloseNpcTrade()
    end
end

function controllerNpcTrader:onCloseNpcTrade()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:disconnectNpcTalkEvent()
        if controllerNpcTrader.ui and controllerNpcTrader.ui:isVisible() then
            controllerNpcTrader:unloadHtml()
        end
        controllerNpcTrader.isTradeOpen = false
        if controllerNpcTrader.sellAllWithDelayEvent then
            removeEvent(controllerNpcTrader.sellAllWithDelayEvent)
            controllerNpcTrader.sellAllWithDelayEvent = nil
        end
        -- Clean up state
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.playerItems = {}
        controllerNpcTrader.playerMoney = nil
        controllerNpcTrader.selectedItem = nil
        controllerNpcTrader.tradeItems = {}
        controllerNpcTrader.currentList = {}
        controllerNpcTrader.allTradeItems = {}
    end
end

function sellAll(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        sellAllLegacy(...)
    else
        controllerNpcTrader:sellAll(...)
    end
end

function isTrading(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return isTradingLegacy(...)
    end

    return controllerNpcTrader.isTradeOpen == true
end

function getSellItems(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getSellItemsLegacy(...)
    end

    return controllerNpcTrader.sellItems or {}
end

function getBuyItems(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getBuyItemsLegacy(...)
    end

    return controllerNpcTrader.buyItems or {}
end

function getSellQuantity(item) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getSellQuantityLegacy(item)
    end

    if type(item) == 'number' then
        item = Item.create(item)
    end

    return controllerNpcTrader:getSellQuantity(item)
end

function canTradeItem(item) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return canTradeItemLegacy(item)
    end

    if type(item) == 'number' then
        item = Item.create(item)
    end

    local tradeEntry = item
    if item and not item.ptr then
        for _, entry in ipairs(controllerNpcTrader.sellItems or {}) do
            if entry.ptr:getId() == item:getId() and entry.ptr:getSubType() == item:getSubType() then
                tradeEntry = entry
                break
            end
        end

        if tradeEntry == item then
            for _, entry in ipairs(controllerNpcTrader.buyItems or {}) do
                if entry.ptr:getId() == item:getId() and entry.ptr:getSubType() == item:getSubType() then
                    tradeEntry = entry
                    break
                end
            end
        end
    end

    if not tradeEntry or not tradeEntry.ptr then
        return false
    end

    return controllerNpcTrader:canTradeItem(tradeEntry)
end

function closeNpcTrade(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return closeNpcTradeLegacy(...)
    end

    return g_game.closeNpcTrade()
end
