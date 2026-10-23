-- Run explicitly from the developer console after installing the matching build.
-- Copy the prepared pka-bootstrap.cam to the writable records directory first.
assert(not g_game.isOnline() and not g_game.isLogging(), 'Close the live session before replay')
g_game.setClientVersion(860)
g_game.setProtocolVersion(854)
g_game.setPokeAllianceProtocol(true)
g_game.enableFeature(GameOpcodeU16)
g_game.playRecord('pka-bootstrap.cam')
if EnterGame then EnterGame.hide() end
if CharacterList and CharacterList.isVisible() then CharacterList.hide() end
