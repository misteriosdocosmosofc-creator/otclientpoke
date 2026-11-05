-- PKA owns its UI and actions. Legacy config scripts never execute in this profile.
PkaBot = {}
local window, hud, event, actionEvent, config, character, selectedKey
local tab = 'Pokemon'
local recording, running, dirty = false, false, false
local status = 'Pausado'
local signature = ''
local rows = {}
local metrics = {refreshes = 0, rebuilds = 0, actions = 0}
local connected = false
local stored = {}
local storageError = false
local render, refresh, stop

function PkaBot.isActive()
  return g_game.isPokeAllianceProtocol and g_game.isPokeAllianceProtocol()
end

local function pokemonState()
  local pokemon = modules.game_pokemon
  return pokemon and pokemon.getState() or {selected = {}, moves = {}}
end

local function save()
  if not dirty or not config or not character or storageError then return end
  stored[character] = config
  -- OTML nodes stringify numeric keys and lose ipairs order on reload.
  -- Keep the typed arrays/booleans in a JSON value under an isolated key.
  g_settings.set('pka-bot-v1-json', json.encode(stored))
  g_settings.save()
  dirty = false
end

local function profile()
  config.profiles = config.profiles or {}
  config.profiles[selectedKey] = config.profiles[selectedKey] or {order = {}, moves = {}, interval = 500, cleanse = 0, revive = 0}
  local p = config.profiles[selectedKey]
  p.order, p.moves = p.order or {}, p.moves or {}
  return p
end

local function remaining(move)
  return math.max(0, (tonumber(move.remaining) or 0) - math.floor((g_clock.millis() - (move.received or g_clock.millis())) / 1000))
end

local function setStatus(text)
  status = text
  if window then window.footer.status:setText(text) end
  if hud then hud.state:setText((selectedKey or 'Arcanine') .. '\n' .. text) end
end

stop = function(reason)
  if actionEvent then removeEvent(actionEvent) actionEvent = nil end
  running = false
  setStatus(reason or 'Pausado')
end

local function cancelViewTimer()
  if event then removeEvent(event) event = nil end
end

local function fit()
  if not window then return end
  local area = window:getParent():getPaddingRect()
  window:breakAnchors()
  window:setSize({width = math.min(520, area.width - 12), height = math.min(370, area.height - 12)})
  window:setPosition({x = area.x + math.floor((area.width - window:getWidth()) / 2),
                      y = area.y + math.floor((area.height - window:getHeight()) / 2)})
  for _, button in ipairs(window.tabs:getChildren()) do button:setWidth(math.floor((window.tabs:getWidth() - 12) / 4)) end
  hud:bindRectToParent()
end

local function add(style, text)
  local widget = g_ui.createWidget(style, window.body.content)
  if text then widget:setText(text) end
  return widget
end

local function label(text) return add('PkaBotLabel', text) end
local function button(text, callback)
  local b = add('PkaBotButton', text)
  b.onClick = callback
  return b
end
local function check(text, value, callback)
  local b = add('PkaBotCheck', text)
  b:setChecked(value == true or value == 'true')
  b.onCheckChange = function(_, checked) callback(checked) dirty = true end
  return b
end
local function number(text, value, minimum, maximum, callback)
  label(text)
  local input = add('PkaBotInput', tostring(value or 0))
  input.onTextChange = function(_, value)
    local n = tonumber(value)
    if n and n == math.floor(n) and n >= minimum and n <= maximum then
      callback(n) dirty = true
    else setStatus('Valor esperado: ' .. minimum .. ' a ' .. maximum) end
  end
  return input
end

local function syncMoves()
  local s = pokemonState()
  local key = s.selected.name or 'Arcanine'
  if key ~= selectedKey then
    stop('Pokemon alterado')
    save()
    selectedKey = key
    signature = ''
  end
  local p = profile()
  local parts = {key}
  for _, move in ipairs(s.moves) do
    parts[#parts + 1] = move.key .. ':' .. move.name
    if not p.moves[move.key] then
      p.moves[move.key] = {name = move.name, enabled = false, stun = false}
      table.insert(p.order, move.key)
      dirty = true
    elseif p.moves[move.key].name ~= move.name then
      p.moves[move.key].name = move.name dirty = true
    end
  end
  return table.concat(parts, '|')
end

local function findMove(key)
  for index, move in ipairs(pokemonState().moves) do
    if move.key == key then return index, move end
  end
end

function PkaBot.executeCombo()
  if running or not PkaBot.isActive() or not g_game.isOnline() then return false end
  syncMoves()
  local s, p, sequence = pokemonState(), profile(), {}
  if s.selected.mode ~= 1 then setStatus('Invoque seu Pokemon') return false end
  for _, key in ipairs(p.order) do
    local m = p.moves[key]
    if m and (m.enabled == true or m.enabled == 'true') then
      local index, move = findMove(key)
      if not index or remaining(move) > 0 then setStatus('Skill indisponivel: ' .. m.name) return false end
      sequence[#sequence + 1] = key
    end
  end
  if #sequence == 0 then setStatus('Selecione as skills do combo') return false end
  local identity, name = s.selected.identity, s.selected.name
  local interval = math.max(100, math.min(5000, tonumber(p.interval) or 500))
  local i = 1
  running = true
  local function step()
    actionEvent = nil
    local current = pokemonState().selected
    if not running or not PkaBot.isActive() or not g_game.isOnline() or current.mode ~= 1 or
       current.identity ~= identity or current.name ~= name then stop('Combo interrompido') return end
    local key = sequence[i]
    if not key then stop('Sequencia enviada; confira os efeitos') return end
    local index, move = findMove(key)
    if not index or remaining(move) > 0 then stop('Combo pausado: skill indisponivel') return end
    if not modules.game_pokemon.castMove(index) then stop('Skill nao enviada') return end
    metrics.actions = metrics.actions + 1
    setStatus('Combo: ' .. move.name)
    i = i + 1
    actionEvent = scheduleEvent(step, interval)
  end
  step()
  return true
end

local function position()
  local player = g_game.getLocalPlayer()
  return player and player:getPosition()
end

function PkaBot.mark(kind, pos)
  if not config or not PkaBot.isActive() or not g_game.isOnline() then return false end
  pos = pos or position()
  if not pos then return false end
  local route = config.route
  local last = route[#route]
  if kind == 'andar' and last and last.x == pos.x and last.y == pos.y and last.z == pos.z then return false end
  if #route >= 512 then recording = false setStatus('Rota cheia: 512 pontos') return false end
  route[#route + 1] = {x = pos.x, y = pos.y, z = pos.z, kind = kind}
  dirty = true
  setStatus('Rota: ' .. #route .. ' pontos')
  return true
end

local function onPositionChange(player, pos)
  if recording and player == g_game.getLocalPlayer() then PkaBot.mark('andar', pos) end
end

render = function()
  if not window or not config then return end
  metrics.rebuilds = metrics.rebuilds + 1
  rows = {}
  window.body.content:destroyChildren()
  window.profile:setText('Perfil: ' .. selectedKey)
  local p = profile()
  if tab == 'Pokemon' then
    label('Skills do Pokemon invocado')
    if #p.order == 0 then label('Invoque o Arcanine para carregar as skills.') end
    for i, key in ipairs(p.order) do
      local m = p.moves[key]
      if m then
        local row = add('PkaBotMove')
        row.name:setText(i .. '. ' .. m.name .. ' (' .. key .. ')')
        row.enabled:setTooltip('Incluir ' .. m.name .. ' no combo')
        row.enabled:setChecked(m.enabled == true or m.enabled == 'true')
        row.enabled.onCheckChange = function(_, v) m.enabled = v dirty = true end
        row.stun:setChecked(m.stun == true or m.stun == 'true')
        row.stun.onCheckChange = function(_, v) m.stun = v dirty = true end
        rows[key] = row.cooldown
        row.up:setEnabled(i > 1)
        row.up.onClick = function()
            if i == 1 then return end
            if running then setStatus('Pause antes de editar a sequencia') return end
            p.order[i], p.order[i - 1] = p.order[i - 1], p.order[i]
            dirty = true render()
        end
      end
    end
    number('Intervalo entre skills (ms)', p.interval, 100, 5000, function(n) p.interval = n end)
    number('Pocao de limpeza: ID (0 = indefinido)', p.cleanse, 0, 65535, function(n) p.cleanse = n end)
    number('Revive: ID (0 = indefinido)', p.revive, 0, 65535, function(n) p.revive = n end)
    label('Limpeza e revive automaticos: pendentes de validacao.')
  elseif tab == 'Rota' then
    number('Inimigos desejados no lure', config.lure, 1, 8, function(n) config.lure = n end)
    button(recording and 'Parar gravacao' or 'Gravar caminho', function()
      recording = not recording
      if recording then PkaBot.mark('andar') else save() end
      render()
    end)
    button('Marcar combate aqui', function() PkaBot.mark('combate') render() end)
    button('Marcar ordenar aqui', function() PkaBot.mark('ordenar') render() end)
    button('Marcar cobertura aqui', function() PkaBot.mark('cobertura') render() end)
    label(#config.route .. ' pontos salvos. Percurso automatico pendente.')
    -- Bounded rendering; a recorded route can contain up to 512 points.
    for i = math.max(1, #config.route - 19), #config.route do
      local point = config.route[i]
      label(i .. '. ' .. point.kind .. '  ' .. point.x .. ', ' .. point.y .. ', ' .. point.z)
    end
    button('Remover ultimo ponto', function() table.remove(config.route) dirty = true render() end)
  elseif tab == 'Retirada' then
    label('Retirada pelo caminho ja percorrido.')
    label('Coberturas marcadas:')
    local count = 0
    for i, point in ipairs(config.route) do
      if point.kind == 'cobertura' then
        count = count + 1
        if count <= 20 then label('Ponto ' .. i .. ': ' .. point.x .. ', ' .. point.y .. ', ' .. point.z) end
      end
    end
    if count == 0 then label('Marque coberturas na aba Rota.') end
    button('Pausar combo e gravacao', function() recording = false stop() save() end)
    label('Fuga e revive automaticos: aguardando sinais de protecao.')
  else
    check('Tentar uma Pokebola no shiny derrotado', config.capture, function(v) config.capture = v end)
    number('Pokebola: ID (0 = indefinido)', config.ball, 0, 65535, function(n) config.ball = n end)
    label('Identificacao de shiny e corpo: ainda nao validada.')
    label('Captura automatica indisponivel nesta etapa.')
  end
end

refresh = function()
  event = nil
  if not window or (not window:isVisible() and not hud:isVisible()) or not config then return end
  metrics.refreshes = metrics.refreshes + 1
  local nextSignature = syncMoves()
  if nextSignature ~= signature then signature = nextSignature render() end
  if window:isVisible() and tab == 'Pokemon' then
    for key, widget in pairs(rows) do
      local _, move = findMove(key)
      local value = move and remaining(move)
      local text = not move and 'Fora da lista atual' or (value > 0 and ('Cooldown: ' .. value .. 's') or 'Disponivel')
      if widget:getText() ~= text then widget:setText(text) end
    end
  end
  event = scheduleEvent(refresh, 500)
end

local function ensureWindow()
  if window then return end
  g_ui.importStyle('pka.otui')
  local parent = modules.game_interface.getRootPanel()
  window = g_ui.createWidget('PkaBotWindow', parent)
  hud = g_ui.createWidget('PkaBotHud', parent)
  window:hide() hud:hide()
  for _, name in ipairs({'Pokemon', 'Rota', 'Retirada', 'Shiny'}) do
    local b = g_ui.createWidget('Button', window.tabs)
    b:setText(name) b:setHeight(32)
    b.onClick = function() save() tab = name render() end
  end
  window.footer.compact.onClick = function() save() window:hide() hud:show() hud:raise() fit() end
  window.footer.combo.onClick = PkaBot.executeCombo
  window.footer.pause.onClick = function() recording = false stop() save() end
  hud.configure.onClick = function() hud:hide() window:show() window:raise() fit() render() end
  hud.pause.onClick = function() recording = false stop() save() end
  connect(parent, {onGeometryChange = fit})
end

function PkaBot.online()
  if not PkaBot.isActive() then return end
  local key = g_game.getCharacterName() .. '_' .. g_game.getWorldName()
  if character ~= key then
    save()
    character = key
    local raw = g_settings.getString('pka-bot-v1-json')
    stored, storageError = {}, false
    if raw and raw ~= '' then
      local ok, decoded = pcall(json.decode, raw)
      if ok and type(decoded) == 'table' then stored = decoded
      else storageError = true end
    end
    config = stored[key] or {profiles = {}, route = {}, lure = 8, ball = 0, capture = false}
    if type(config) ~= 'table' or (config.route and type(config.route) ~= 'table') or
       (config.profiles and type(config.profiles) ~= 'table') then
      storageError = true
      config = {profiles = {}, route = {}, lure = 8, ball = 0, capture = false}
    end
    if storageError then setStatus('Erro no perfil salvo; original preservado') end
    config.route = config.route or {}
    selectedKey = pokemonState().selected.name or 'Arcanine'
    signature = ''
  end
  if not connected then connect(LocalPlayer, {onPositionChange = onPositionChange}) connected = true end
end

function PkaBot.hide()
  recording = false
  stop()
  save()
  if window then window:hide() hud:hide() end
  cancelViewTimer()
  if botButton then botButton:setOn(false) end
end

function PkaBot.toggle()
  if not g_game.isOnline() then return end
  PkaBot.online()
  ensureWindow()
  if window:isVisible() or hud:isVisible() then PkaBot.hide() return end
  signature = syncMoves()
  render() fit() window:show() window:raise()
  if botButton then botButton:setOn(true) end
  cancelViewTimer() refresh()
end

function PkaBot.offline()
  recording = false stop() PkaBot.hide()
  if connected then disconnect(LocalPlayer, {onPositionChange = onPositionChange}) connected = false end
  character, config, selectedKey = nil, nil, nil
end

function PkaBot.terminate()
  PkaBot.offline()
  if window then
    disconnect(window:getParent(), {onGeometryChange = fit})
    window:destroy() hud:destroy() window, hud = nil, nil
  end
end

function PkaBot.getDiagnostics()
  return {running = running, recording = recording, timer = event ~= nil, actionTimer = actionEvent ~= nil,
    refreshes = metrics.refreshes, rebuilds = metrics.rebuilds, actions = metrics.actions,
    window = window, hud = hud, profile = config and profile(), config = config, status = status}
end
