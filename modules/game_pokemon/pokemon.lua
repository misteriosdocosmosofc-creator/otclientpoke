local windows = {}
local state
local tickEvent
local placementEvent
local enabled = false
local lastFlyCommand
local refreshTimers

local function resetState()
  state = {roster = {}, selected = {}, moves = {}, conditions = {}, flying = false}
end
resetState()

local function now() return g_clock.millis() end
local function isPka() return g_game.isPokeAllianceProtocol() end
local function warn(text)
  if modules.game_textmessage then modules.game_textmessage.displayStatusMessage(text) end
end

local function remember(window)
  local parent = window:getParent()
  g_settings.setNode('pka-window-' .. window:getId(), {
    x = window:getX() - parent:getX(), y = window:getY() - parent:getY(),
    minimized = window.minimized
  })
end

local function setMinimized(window, minimized, save)
  window.minimized = minimized == true
  window.contents:setVisible(not window.minimized)
  window.minimize:setText(window.minimized and '+' or '-')
  window:setHeight(window.minimized and 33 or window.expandedHeight)
  window:bindRectToParent()
  if save then remember(window) g_settings.save() end
end

local function resizeWindow(window, width, bodyHeight)
  window:setWidth(width)
  window.expandedHeight = bodyHeight + 35
  setMinimized(window, window.minimized, false)
end

local function makeWindow(id, title, width, height, x, y)
  local parent = modules.game_interface.getRootPanel()
  local window = g_ui.createWidget('PkaFloatWindow', parent)
  window:setId(id)
  window.title:setText(title .. '  ::')
  window.title:setTooltip('Arraste a barra de titulo para mover')
  window.minimize.onClick = function()
    setMinimized(window, not window.minimized, true)
    if refreshTimers then refreshTimers() end
  end
  window.onDragLeave = function() window.pendingPosition = nil remember(window) g_settings.save() end
  local saved = g_settings.getNode('pka-window-' .. id) or {}
  window.defaultX = tonumber(saved.x) == nil
  window.pendingPosition = {x = tonumber(saved.x) or x, y = tonumber(saved.y) or y}
  window:setPosition({x = parent:getX() + window.pendingPosition.x,
                      y = parent:getY() + window.pendingPosition.y})
  window.minimized = saved.minimized == true or saved.minimized == 'true'
  resizeWindow(window, width, height)
  windows[id] = window
  return window
end

local function setText(widget, text)
  if widget:getText() ~= text then widget:setText(text) end
end

local function stampCooldowns(entries)
  local time = now()
  for _, entry in ipairs(entries) do entry.received = time end
  return entries
end

local function remaining(entry)
  return math.max(0, (entry.remaining or 0) - math.floor((now() - entry.received) / 1000))
end

local function updateRosterTimers()
  local window = windows.pkaRoster
  if not window or window.minimized then return false end
  local active = false
  for i, pokemon in ipairs(state.roster) do
    local row = window.contents:getChildById('pokemon' .. i)
    if row then
      local ready, count = 0, 0
      for _, move in ipairs(pokemon.cooldowns) do
        if move.key ~= 'passive' then
          count = count + 1
          if remaining(move) == 0 then ready = ready + 1 else active = true end
        end
      end
      setText(row.cooldown, count > 0 and ('Skills ' .. ready .. '/' .. count) or '')
    end
  end
  return active
end

local function updateMoveTimers()
  local window = windows.pkaMoves
  if not window or window.minimized then return false end
  local active = false
  for i, move in ipairs(state.moves) do
    local widget = window.contents:getChildById('move' .. i)
    if widget then
      local left = remaining(move)
      setText(widget.seconds, left > 0 and tostring(left) or '')
      widget.progress:setVisible(left > 0)
      if left > 0 then
        active = true
        widget.progress:setPercent(math.max(0, math.min(100, 100 - left * 100 / math.max(1, move.total))))
      end
    end
  end
  return active
end

local function renderConditions()
  local window = windows.pkaConditions
  if not window or window.minimized then return false end
  local list = {}
  local time = now()
  for creatureId, conditions in pairs(state.conditions) do
    local creature = g_map.getCreatureById(creatureId)
    local ownPokemon = creature and creature:getType() == 3
    for bitIndex, condition in pairs(conditions) do
      if condition.expires and condition.expires <= time then
        conditions[bitIndex] = nil
      elseif ownPokemon then
        list[#list + 1] = condition
      end
    end
  end
  table.sort(list, function(a, b) return a.bit < b.bit end)
  local signature = ''
  for _, condition in ipairs(list) do signature = signature .. ':' .. condition.bit end
  if window.signature ~= signature then
    window.contents:destroyChildren()
    for i, condition in ipairs(list) do
      local icon = g_ui.createWidget('PkaConditionIcon', window.contents)
      icon:setId('condition' .. i)
      icon:setMarginLeft(((i - 1) % 7) * 35)
      icon:setMarginTop(math.floor((i - 1) / 7) * 37)
      icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      icon:addAnchor(AnchorTop, 'parent', AnchorTop)
      local file = '/images/conditions/' .. condition.icon .. '.png'
      if not g_resources.fileExists(file) then file = '/images/conditions/condition_neutral.png' end
      if g_resources.fileExists(file) then icon.icon:setImageSource(file) end
      icon:setTooltip(condition.name)
    end
    window.signature = signature
    resizeWindow(window, 252, math.max(37, math.ceil(#list / 7) * 37))
    if #list == 0 then
      local label = g_ui.createWidget('Label', window.contents)
      label:setText('Sem efeitos no Pokemon')
      label:setSize({width = 240, height = 30})
      label:setPhantom(true)
    end
  end
  local timed = false
  for i, condition in ipairs(list) do
    local widget = window.contents:getChildById('condition' .. i)
    if widget then
      setText(widget.seconds, condition.expires and tostring(math.ceil((condition.expires - time) / 1000)) or '')
      timed = timed or condition.expires ~= nil
    end
  end
  return timed
end

refreshTimers = function()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if not enabled then return end
  local rosterActive = updateRosterTimers()
  local movesActive = updateMoveTimers()
  local conditionsActive = renderConditions()
  if rosterActive or movesActive or conditionsActive then
    tickEvent = scheduleEvent(refreshTimers, 250)
  end
end

local function renderRoster()
  local window = windows.pkaRoster
  if not window then return end
  window.contents:destroyChildren()
  for i, pokemon in ipairs(state.roster) do
    if i > 6 then break end
    local row = g_ui.createWidget('PkaRosterRow', window.contents)
    row:setId('pokemon' .. i)
    row:addAnchor(AnchorTop, 'parent', AnchorTop)
    row:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    row:addAnchor(AnchorRight, 'parent', AnchorRight)
    row:setMarginTop((i - 1) * 40)
    row.name:setText(i .. '. ' .. pokemon.name)
    row.health:setPercent(math.min(100, pokemon.health))
    row.health:setText(pokemon.health .. '%')
    row.health:setBackgroundColor(pokemon.health > 25 and '#29b33e' or '#d44c54')
    row:setTooltip(pokemon.name .. ' - ' .. pokemon.health .. '%')
    if pokemon.identity == state.selected.identity then row:setBorderWidth(1) row:setBorderColor('#7beaff') end
    local portrait = PokemonPortraits[pokemon.name:lower()]
    local file = portrait and ('/images/pokemons/' .. portrait .. '.png')
    if file and g_resources.fileExists(file) then row.portrait:setImageSource(file) end
    -- Selection is a deliberate touch, never an automatic summon/revive loop.
    row.onClick = function() selectPokemon(i) end
  end
  resizeWindow(window, 170, math.max(38, math.min(6, #state.roster) * 40))
  refreshTimers()
end

local function renderMoves()
  local window = windows.pkaMoves
  if not window then return end
  window.contents:destroyChildren()
  local width = modules.game_interface.getRootPanel():getWidth()
  local columns = math.min(10, math.max(3, math.floor((width - 190) / 46)))
  for i, move in ipairs(state.moves) do
    local widget = g_ui.createWidget('PkaMoveButton', window.contents)
    widget:setId('move' .. i)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:addAnchor(AnchorTop, 'parent', AnchorTop)
    widget:setMarginLeft(((i - 1) % columns) * 46)
    widget:setMarginTop(math.floor((i - 1) / columns) * 47)
    local itemId = move.value ~= 0 and move.value or 0x2357
    local thing = g_things.getThingType(itemId, ThingCategoryItem)
    if thing then widget.icon:setItemId(itemId) end
    widget.key:setText(move.key:upper())
    widget:setTooltip(move.name .. ' (' .. move.key .. ')')
    widget.onClick = function() castMove(i) end
  end
  if #state.moves == 0 then
    local label = g_ui.createWidget('Label', window.contents)
    label:setText('Selecione / chame um Pokemon')
    label:setSize({width = 235, height = 28})
    label:setPhantom(true)
  end
  window.title:setText((state.selected.name or 'Habilidades') .. '  ::')
  resizeWindow(window, math.max(242, math.min(columns, #state.moves) * 46 + 6),
               math.max(30, math.ceil(#state.moves / columns) * 47))
  refreshTimers()
end

local function createWindows()
  if next(windows) then return end
  g_ui.importStyle('pokemon')
  local root = modules.game_interface.getRootPanel()
  local controls = root:getChildById('mobilePanelControls')
  -- Startup anchors can still be settling when onGameStart fires. Reserve
  -- enough header space even before mobilePanelControls has its final rect.
  local top = math.max(85, controls and (controls:getY() - root:getY() + controls:getHeight() + 8) or 0)
  local map = modules.game_interface.getMapPanel()
  local left = map and (map:getX() - root:getX() + 5) or 5
  makeWindow('pkaRoster', 'Pokebar', 170, 240, left, top)
  makeWindow('pkaMoves', 'Habilidades', 460, 47, left + 180, math.max(top + 80, root:getHeight() - 130))
  makeWindow('pkaConditions', 'Efeitos do Pokemon', 252, 37, left + 180, top)
  local fly = makeWindow('pkaFly', 'Voo', 164, 38, math.max(left + 180, root:getWidth() - 355), math.max(top + 80, root:getHeight() - 225))
  local up = g_ui.createWidget('Button', fly.contents)
  up:setText('Subir') up:setSize({width = 76, height = 35})
  up:addAnchor(AnchorTop, 'parent', AnchorTop)
  up:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  up.onClick = function() flyHeight(false) end
  local down = g_ui.createWidget('Button', fly.contents)
  down:setText('Descer') down:setSize({width = 76, height = 35})
  down:addAnchor(AnchorTop, 'parent', AnchorTop)
  down:addAnchor(AnchorRight, 'parent', AnchorRight)
  down.onClick = function() flyHeight(true) end
  renderRoster()
  renderMoves()
  renderConditions()
  -- The game root moves below the top menu after startup's deferred layout.
  -- Apply saved/default offsets once that parent rectangle has settled.
  placementEvent = scheduleEvent(function()
    placementEvent = nil
    local settledMap = modules.game_interface.getMapPanel()
    local settledLeft = settledMap and (settledMap:getX() - root:getX() + 5) or left
    -- The map can extend under the mobile overlays and side panels. Reserve
    -- their actual rectangles rather than assuming the map's left edge is free.
    local keypad = g_ui.getRootWidget():recursiveGetChildById('keypad')
    local side = modules.game_interface.getLeftPanel()
    for _, obstacle in pairs({keypad = keypad, side = side}) do
      if obstacle:isVisible() then
        settledLeft = math.max(settledLeft, obstacle:getX() + obstacle:getWidth() - root:getX() + 8)
      end
    end
    for _, window in pairs(windows) do
      local position = window.pendingPosition
      if position then
        if window.defaultX then
          if window:getId() == 'pkaRoster' then position.x = settledLeft
          elseif window:getId() == 'pkaFly' then position.x = math.max(settledLeft + 180, root:getWidth() - 355)
          else position.x = settledLeft + 180 end
        end
        window:setPosition({x = root:getX() + position.x, y = root:getY() + position.y})
        window:bindRectToParent()
        window.pendingPosition = nil
        window.defaultX = nil
      end
    end
  end, 100)
end

local function send(write)
  if not isPka() or not g_game.isOnline() then return false end
  local protocol = g_game.getProtocolGame()
  if not protocol then return false end
  local msg = OutputMessage.create()
  write(msg)
  protocol:send(msg)
  return true
end

function isRevive(itemId)
  return itemId == 0xc05 or itemId == 0xc54 or itemId == 0x9b44
end

function usePokemonItem(itemId, revive)
  if revive and not isRevive(itemId) then return false end
  return send(function(msg) PokemonProtocol.writePokemonItem(msg, itemId, revive) end)
end

function selectPokemon(slot)
  if not state.roster[slot] or slot < 1 or slot > 6 then return false end
  return send(function(msg) PokemonProtocol.writeSelect(msg, slot) end)
end

function castMove(index)
  local move = state.moves[index]
  if not isPka() or not g_game.isOnline() or not move then return false end
  if remaining(move) > 0 then return false end
  -- Original PokemoveIcon click (14064f3c0 -> 140725320) says its
  -- server-provided key in ordinary Say mode, e.g. m1.
  g_game.talk(move.key)
  return true
end

function startOrder()
  if not isPka() or not g_game.isOnline() then return end
  -- Original ACTION_BAR_ORDER and ORDER_SELF both use item 0x0d7d.
  modules.game_interface.startUseWith(Item.create(0x0d7d))
  warn('Comando: toque no destino ou no seu personagem. Toque fora do mapa para cancelar.')
end

function flyHeight(down)
  if not state.flying then warn('O controle de altura funciona durante o fly.') return false end
  -- Match the original PageUp/PageDown callback's 200 ms input gate.
  local time = now()
  if lastFlyCommand and time - lastFlyCommand < 200 then return false end
  local sent = send(function(msg) PokemonProtocol.writeFly(msg, down) end)
  if sent then lastFlyCommand = time end
  return sent
end

function toggleWindow(id)
  local window = windows[id]
  if window then setMinimized(window, not window.minimized, true) refreshTimers() end
end

function parseOpcode(protocol, opcode, msg)
  if not isPka() then return false end
  if opcode == 0x5d then
    local data = PokemonProtocol.readRoster(msg)
    if data.mode == 0 then state.roster = {} end
    for i, pokemon in ipairs(data.entries) do
      pokemon.cooldowns = stampCooldowns(pokemon.cooldowns)
      state.roster[i] = pokemon
    end
    renderRoster()
  elseif opcode == 0x602 then
    local data = PokemonProtocol.readRosterUpdate(msg)
    local pokemon = state.roster[data.slot]
    if pokemon then
      pokemon.health = data.health
      pokemon.cooldowns = stampCooldowns(data.cooldowns)
    end
    renderRoster()
  elseif opcode == 0x11a then
    state.selected = PokemonProtocol.readSelected(msg)
    if state.selected.mode ~= 1 then state.moves = {} end
    renderRoster()
    renderMoves()
  elseif opcode == 0x5c then
    local data = PokemonProtocol.readMoves(msg)
    state.moves = stampCooldowns(data.entries)
    renderMoves()
  elseif opcode == 0x603 then
    local data = PokemonProtocol.readMoveCooldown(msg)
    for _, move in ipairs(state.moves) do
      if move.key == data.key then move.remaining = data.remaining move.received = now() end
    end
    refreshTimers()
  elseif opcode == 0x60a then
    local data = PokemonProtocol.readCondition(msg)
    local creature = g_map.getCreatureById(data.creatureId)
    -- Match the PC's own-summon gate. Do not retain every other player's
    -- conditions for the lifetime of a busy map session.
    if not creature or creature:getType() ~= 3 then return true end
    local conditions = state.conditions[data.creatureId] or {}
    state.conditions[data.creatureId] = conditions
    for bitIndex, definition in pairs(PokemonConditions) do
      if PokemonProtocol.hasCondition(data, bitIndex) then
        if data.mode == 3 then conditions[bitIndex] = nil
        elseif data.mode == 1 or data.mode == 2 then
          conditions[bitIndex] = {bit = bitIndex, icon = definition.icon, name = definition.name,
            expires = data.duration > 0 and (now() + data.duration) or nil, total = data.total}
        end
      end
    end
    refreshTimers()
  elseif opcode == 0x60e then
    state.flying = msg:getU8() == 1
  else return PokemonProtocol.readAuxiliary(msg, opcode) end
  return true
end

function onGameStart()
  enabled = g_platform.isMobile() and isPka()
  if enabled then
    createWindows()
    for _, window in pairs(windows) do window:show() window:bindRectToParent() end
    refreshTimers()
  end
end

function onGameEnd()
  enabled = false
  lastFlyCommand = nil
  if placementEvent then removeEvent(placementEvent) placementEvent = nil end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  for _, window in pairs(windows) do remember(window) window:hide() end
  resetState()
end

function init()
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  onGameEnd()
  for _, window in pairs(windows) do window:destroy() end
  windows = {}
end

-- Used by the existing action bar and offline integration checks.
function getState() return state end
function getWindows() return windows end
