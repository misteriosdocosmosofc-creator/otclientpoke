local shortcutsWindow
local shortcuts
local shortcutIcons

function init()
  if not g_platform.isMobile() then return end

  shortcutsWindow = g_ui.displayUI('shortcuts')
  shortcuts = shortcutsWindow.shortcuts
  shortcutIcons = shortcuts.shortcutIcons

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })
  
  setupShortcuts()
end

function terminate()
  if not g_platform.isMobile() then return end

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })

  shortcutsWindow:destroy()
  shortcutsWindow = nil
end

function onGameStart()
  local pka = g_game.isPokeAllianceProtocol() and modules.game_pokemon
  local replacements = {
    attack = {'Comando', 'pka-order', function() modules.game_pokemon.startOrder() end},
    use = {'Pokes', 'pka-pokeball', function() modules.game_pokemon.toggleWindow('pkaRoster') end},
    follow = {'Voo', 'pka-fly', function() modules.game_pokemon.toggleWindow('pkaFly') end}
  }
  local icons = {attack = 'attack', use = 'use', follow = 'follow'}
  for id, replacement in pairs(replacements) do
    local widget = shortcutIcons:getChildById(id)
    widget.pokemonAction = pka and replacement[3] or nil
    widget.image:setImageSource('/images/game/mobile/' .. (pka and replacement[2] or icons[id]))
    widget.image:setText('')
    widget.caption:setText(replacement[1])
    widget.caption:setVisible(pka ~= false and pka ~= nil)
    if pka then
      widget.image:removeAnchor(AnchorVerticalCenter)
      widget.image:addAnchor(AnchorTop, 'parent', AnchorTop)
      widget.image:setMarginTop(3)
      widget.image:setSize({width = 40, height = 40})
    else
      widget.image:removeAnchor(AnchorTop)
      widget.image:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      widget.image:setMarginTop(0)
      widget.image:setSize({width = 48, height = 48})
    end
    widget.image:setOpacity(1)
    widget:setTooltip(pka and replacement[1] or id)
  end
  resetShortcuts()
  shortcuts:show()
end

function onGameEnd()
  shortcuts:hide()
end

function hide()
  shortcutsWindow:hide()
end

function show()
  shortcutsWindow:show()
end

function setupShortcuts()
  if not g_platform.isMobile() then return end
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
    widget.onClick = function()
      if widget.pokemonAction then
        resetShortcuts()
        widget.pokemonAction()
        return
      end
      if widget.image:isChecked() then
        widget.image:setChecked(false)
        return
      end
      resetShortcuts()
      widget.image:setChecked(true)
      widget.lastClicked = g_clock.millis()
    end
  end
end

function resetShortcuts()
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    widget.image:setChecked(false)
    if widget.pokemonAction then widget.image:setOpacity(1) end
    widget.lastClicked = 0
  end
end

function getShortcut()
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    if widget.image:isChecked() then
      return widget:getId()
    end
  end
  return ""
end

function getPanel()
  return shortcuts
end
