"""Host state-machine checks. Requires lupa; native OTUI is tested on Android."""
from pathlib import Path
from lupa import LuaRuntime

repo = Path(__file__).resolve().parents[2]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
clock, queue, writes, sent = 1000, {}, 0, 0
function scheduleEvent(fn, delay)
  local e={fn=fn, at=clock+delay}; queue[#queue+1]=e; return e
end
function removeEvent(e) if e then e.cancelled=true end end
function advance(ms)
  clock=clock+ms
  local current=queue; queue={}
  for _,e in ipairs(current) do
    if not e.cancelled then
      if e.at<=clock then e.fn() else queue[#queue+1]=e end
    end
  end
end
g_clock={millis=function() return clock end, realMillis=function() return clock end}
function connect() end
function disconnect() end
LocalPlayer={}
local settings={}
g_settings={getNode=function(k) return settings[k] end,
  setNode=function(k,v) settings[k]=v end, save=function() writes=writes+1 end,
  getString=function(k) return settings[k] or '' end, set=function(k,v) settings[k]=v end}
local encoded={};local serial=0
json={encode=function(v) serial=serial+1;local k=tostring(serial);encoded[k]=v;return k end,
 decode=function(k) return assert(encoded[k]) end}
local W={}; W.__index=W
function widget(parent)
  local w=setmetatable({parent=parent,children={},visible=false,width=520,height=370,text=''},W)
  if parent then table.insert(parent.children,w) end
  return w
end
function W:getChildren() return self.children end
function W:destroyChildren() self.children={} end
function W:destroy() self.dead=true end
function W:getParent() return self.parent end
function W:getPaddingRect() return {x=0,y=0,width=640,height=360} end
function W:setSize(s) self.width=s.width; self.height=s.height end
function W:setWidth(v) self.width=v end
function W:setHeight(v) self.height=v end
function W:getWidth() return self.width end
function W:getHeight() return self.height end
function W:setText(t) self.text=t end
function W:getText() return self.text end
function W:setChecked(v) self.checked=v end
function W:setEnabled(v) self.enabled=v end
function W:setTooltip(v) self.tooltip=v end
function W:show() self.visible=true end
function W:hide() self.visible=false end
function W:isVisible() return self.visible end
function W:raise() end
function W:breakAnchors() end
function W:bindRectToParent() end
function W:setPosition() end
root=widget()
g_ui={importStyle=function() end, createWidget=function(style,parent)
  local w=widget(parent)
  if style=='PkaBotWindow' then
    w.profile=widget(w);w.tabs=widget(w);w.body=widget(w);w.body.content=widget(w.body)
    w.footer=widget(w);w.footer.status=widget(w.footer);w.footer.compact=widget(w.footer);w.footer.combo=widget(w.footer);w.footer.pause=widget(w.footer)
  elseif style=='PkaBotMove' then w.enabled=widget(w);w.name=widget(w);w.stun=widget(w);w.up=widget(w);w.cooldown=widget(w)
  elseif style=='PkaBotHud' then w.state=widget(w);w.pause=widget(w);w.configure=widget(w) end
  return w
end}
player={getPosition=function() return {x=100,y=100,z=7} end}
online,pka=true,true
g_game={isOnline=function() return online end,isPokeAllianceProtocol=function() return pka end,
 getCharacterName=function() return 'test' end,getWorldName=function() return 'offline' end,
 getLocalPlayer=function() return player end}
state={selected={mode=1,name='Arcanine',identity='one'},moves={
 {name='Burn Up',key='m7',remaining=0,received=clock},
 {name='Fireball',key='m3',remaining=0,received=clock}}}
modules={game_interface={getRootPanel=function() return root end},game_pokemon={
 getState=function() return state end,castMove=function() sent=sent+1;return true end}}
''')
for filename in ['mods/game_bot/pka.lua','mods/game_bot/bot.lua','mods/game_bot/executor.lua',
                 'mods/game_bot/functions/callbacks.lua','tools/pka-replay/pka_bot_android.lua']:
    lua.execute('assert(load(...))', (repo/filename).read_text(encoding='utf-8'))
lua.execute((repo/'mods/game_bot/pka.lua').read_text(encoding='utf-8'))
lua.execute(r'''
PkaBot.online();PkaBot.toggle()
local d=PkaBot.getDiagnostics()
assert(d.window:isVisible() and d.timer and #d.profile.order==2)
assert(not PkaBot.executeCombo() and sent==0)
d.profile.moves.m7.enabled=true;d.profile.moves.m3.enabled=true;d.profile.interval=100
state.moves[1].remaining=2
assert(not PkaBot.executeCombo() and sent==0)
state.moves[1].remaining=0
assert(PkaBot.executeCombo() and sent==1)
d.hud.pause.onClick();advance(200)
assert(sent==1 and not PkaBot.getDiagnostics().actionTimer)
assert(PkaBot.executeCombo() and sent==2)
state.selected.identity='two';advance(200)
assert(sent==2 and not PkaBot.getDiagnostics().running)
assert(PkaBot.executeCombo());advance(100);advance(100)
assert(sent==4 and not PkaBot.getDiagnostics().running)
local rebuilds=PkaBot.getDiagnostics().rebuilds
local oldWrites=writes
for i=1,50 do advance(500) end
assert(PkaBot.getDiagnostics().rebuilds<=rebuilds+1 and writes==oldWrites)
assert(PkaBot.mark('andar'));assert(not PkaBot.mark('andar'))
for i=2,512 do assert(PkaBot.mark('andar',{x=100+i,y=100,z=7})) end
assert(not PkaBot.mark('combate'))
assert(#PkaBot.getDiagnostics().config.route==512)
assert(PkaBot.executeCombo());local before=sent
PkaBot.hide();advance(1000)
assert(sent==before and not PkaBot.getDiagnostics().timer and not PkaBot.getDiagnostics().actionTimer)
local refreshes=PkaBot.getDiagnostics().refreshes
for i=1,50 do advance(500) end
assert(PkaBot.getDiagnostics().refreshes==refreshes)
PkaBot.toggle();PkaBot.offline()
assert(not PkaBot.getDiagnostics().running and not PkaBot.getDiagnostics().timer)
pka=false;assert(not PkaBot.executeCombo())
PkaBot.terminate()
''')

# Exercise callback removal with real module code (not a mirror of it).
lua.execute('G={botContext={_callbacks={onTalk={}},now=100}}; g_game.enableTileThingLuaCallback=function() end')
lua.execute((repo/'mods/game_bot/functions/callbacks.lua').read_text(encoding='utf-8'))
lua.execute('local h=G.botContext.callback("onTalk",function() end); assert(#G.botContext._callbacks.onTalk==1); h.remove();h.remove();assert(#G.botContext._callbacks.onTalk==0)')
print('PASS: Lua syntax, profile, cooldown, pause/switch/close/logout, single-pass combo, bounded route, idle timers/writes, callback removal')
