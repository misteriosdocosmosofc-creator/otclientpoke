-- Run only in an isolated user directory as pka_windowsrc.lua.
-- All login/network entry points below are intercepted; credentials are synthetic.
EnterGame.firstShow = function() end
connect(g_app, {onRun = function()
  scheduleEvent(function()
    local httpCalled, worldCalled = false, false
    LoginHttp.create = function()
      return {httpLogin = function(self, host, path, port, account, password)
        assert(host == 'login.pokealliance.com' and path == '/login' and port == 443)
        assert(account == 'offline-account' and password == 'offline-password')
        httpCalled = true
      end}
    end
    EnterGame.activateWorldProxies = function() end
    g_game.loginWorld = function(account, password, world, host, port, character)
      assert(account == 'offline-account' and password == 'offline-ticket')
      assert(character == 'Offline Character' and host == '127.0.0.1')
      assert(g_game.isPokeAllianceProtocol() and g_game.getProtocolVersion() == 854)
      assert(g_game.getFeature(GameOpcodeU16) and g_game.getOs() == 20)
      worldCalled = true
    end
    local ok, problem = pcall(function()
      assert(not g_platform.isMobile() and not g_game.isOnline())
      g_settings.remove('client-protocol')
      assert(g_game.getClientProtocolVersion(860, 'login.example.org') == 860)
      assert(g_game.getClientProtocolVersion(860, 'fakepokealliance.com') == 860)
      assert(g_game.getClientProtocolVersion(860, 'pokealliance.com.evil.example') == 860)
      assert(g_game.getClientProtocolVersion(860, 'https://LOGIN.POKEALLIANCE.COM/login') == 854)
      assert(g_game.getClientProtocolVersion(1511, 'pokealliance.com') == 1511)
      G.host, G.port = 'https://login.pokealliance.com/login', 443
      G.account, G.password = 'offline-account', 'offline-password'
      EnterGame.tryHttpLogin(860, false)
      assert(httpCalled and g_game.isPokeAllianceProtocol(), 'HTTP login did not select PKA profile')
      assert(ProtocolGame.getLoginExtendedData() ~= '' and ProtocolGame.getLoginChallengeReplacement() == 'pt')
      local preauth = ProtocolGame.getLoginPreAuthData()
      local fields = preauth:split('\n')
      assert(#fields == 4, 'Missing local pre-auth fields')
      for _, field in ipairs(fields) do assert(#field > 0, 'Empty pre-auth field') end
      G.sessionKey, G.sessionKeyReceivedAt = 'offline-ticket', g_clock.millis()
      CharacterList.create({{name = 'Offline Character', worldName = 'Offline',
        worldIp = '127.0.0.1', worldPort = 9788}}, {status = '', premDays = 0, subStatus = SubscriptionStatus.Free})
      CharacterList.doLogin()
      assert(worldCalled, 'Character login did not use HTTPS ticket')
    end)
    if not ok then g_logger.error('[login-profile-probe] ' .. tostring(problem)) end
    g_logger.warning('[login-profile-probe] fresh profile, pre-auth, OS, U16 and ticket passed=' .. tostring(ok))
    scheduleEvent(function() g_app.exit() end, 1000)
  end, 1000)
end})
