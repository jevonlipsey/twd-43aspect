-- twd-43aspect: lay the UI out for the real window aspect instead of a forced 16:9.
--
-- The UI already has 4:3 layouts: AspectRatio.lua scrubs each UI agent's "Aspect Ratio - Chore"
-- from its 4:3 pose (time 0) to its 16:9 pose (time 1) from RenderGetAspectRatio(). Stock PC
-- scripts just never ask for 4:3: this file's original calls RenderForce_16_by_9_AspectRatio(true),
-- and the season EpisodeSystem/menus call RenderSetAspectRatio(16/9). Here both resolve to the
-- window's own aspect, clamped to the range the layouts cover. On a 16:9 screen nothing changes.
--
-- This file replaces ProjectSettingsShared.lua (run at every boot / engine reset), installs the
-- hook, then runs the game's original script unchanged (shipped as ProjectSettingsShared_stock.lua).

-- uimod5 debug log channel: appended to prefs.prop key "TWD43 Log" (pull prefs.prop and run strings on it).
TWD43_LogN = rawget(_G, "TWD43_LogN") or 0
function TWD43_Log(msg)
  if TWD43_LogN >= 40 then
    return
  end
  TWD43_LogN = TWD43_LogN + 1
  pcall(function()
    local prefs = GetPreferences()
    local old = PropertyExists(prefs, "TWD43 Log") and PropertyGet(prefs, "TWD43 Log") or ""
    PropertySet(prefs, "TWD43 Log", string.sub(old .. "|" .. tostring(msg), -3000))
    SavePrefs()
  end)
end
TWD43_StateId = rawget(_G, "TWD43_StateId") or string.sub(tostring({}), -8)
pcall(function()
  local r = RenderGetScreenResolution()
  TWD43_Log("boot " .. TWD43_StateId .. " t=" .. tostring(GetTotalTime and GetTotalTime()) .. " res=" .. tostring(r and r.x) .. "x" .. tostring(r and r.y) .. " inst=" .. tostring(rawget(_G, "TWD43_Installed")) .. " mt=" .. tostring(getmetatable(_G)))
end)

local function TWD43_WindowAspect()
  local r = RenderGetScreenResolution()
  if r and r.x and r.y and r.y > 0 then
    local a = r.x / r.y
    if a < 1.3333334 then
      a = 1.3333334
    elseif a > 1.7777778 then
      a = 1.7777778
    end
    return a
  end
end

-- RenderSetAspectRatio is kept out of _G's own keys and served through a metatable, so that
-- every later redefinition (Menu/AspectRatio.lua wraps it to re-pose its "Aspect Ratio - Chore"
-- agents) is itself wrapped: a script asking for 16:9 then re-poses the UI for the real window
-- aspect too, not just the renderer. (uimod1 hooked only the engine function, so AspectRatio.lua's
-- wrapper still posed its agents for the 16:9 it was asked for.)
if not rawget(_G, "TWD43_Installed") then
  TWD43_Installed = true
  local function fix(f)
    return function(aspectRatio, ...)
      TWD43_Log("RSAR " .. tostring(aspectRatio) .. "->" .. tostring(TWD43_WindowAspect()))
      return f(TWD43_WindowAspect() or aspectRatio, ...)
    end
  end
  local current = fix(RenderSetAspectRatio)
  rawset(_G, "RenderSetAspectRatio", nil)
  local mt = getmetatable(_G) or {}
  local oldIndex, oldNewIndex = mt.__index, mt.__newindex
  mt.__index = function(t, k)
    if k == "RenderSetAspectRatio" then
      return current
    end
    if type(oldIndex) == "function" then
      return oldIndex(t, k)
    elseif type(oldIndex) == "table" then
      return oldIndex[k]
    end
  end
  mt.__newindex = function(t, k, v)
    if k == "RenderSetAspectRatio" then
      current = type(v) == "function" and fix(v) or v
    elseif k == "Tooltip_Refresh" and type(v) == "function" and TWD43_WrapTooltipRefresh then
      rawset(t, k, TWD43_WrapTooltipRefresh(v))
      TWD43_Log("wrap Tooltip_Refresh " .. TWD43_StateId)
    elseif oldNewIndex then
      oldNewIndex(t, k, v)
    else
      rawset(t, k, v)
    end
  end
  setmetatable(_G, mt)
  function RenderForce_16_by_9_AspectRatio()
    local a = TWD43_WindowAspect()
    if a then
      RenderSetAspectRatio(a)
    end
  end
end

-- Re-anchor UI agents that the game places at a fixed distance from the 16:9 frame's edge, so
-- they keep that margin from the real (narrower) frame's edge, at their authored size.
-- Each entry: authored local x, side (+1 = agent sits on the +x side of its camera), and the
-- half-height of the camera's view at the agent's depth (ui_tooltip.scene: camera at z -20,
-- 45 degree vertical FOV -> 20 * tan(22.5 deg) = 8.2843; checked against the stock 16:9 shot:
-- "Examine" at x 85 of 1280, y 762 of the 720-high band, as measured).
-- An agent is only moved while it is still at its authored x, so running twice changes nothing.
local TWD43_EdgeAgents = {
  ui_tooltip_verb = {x = 12.776, side = 1, halfH = 8.2843},
  ui_tooltip_noun = {x = 12.776, side = 1, halfH = 8.2843},
}

TWD43_DEBUG = true   -- uimod4 test build: appends a marker with the re-anchor state to the tooltip noun
TWD43_Dbg = {cb = 0, cbx = "-", rf = 0, tf = 0}

-- Move each edge agent that is still at its authored x; returns a short report.
local function TWD43_FixEdgeAgents(counter)
  local a = TWD43_WindowAspect()
  if not a or a >= 1.7777 then
    return "wide"
  end
  local out = {}
  for name, e in pairs(TWD43_EdgeAgents) do
    if AgentExists(name) then
      local p = AgentGetPos(name)
      local before = p.x
      if math.abs(p.x - e.x) < 0.01 then
        p.x = p.x - e.side * e.halfH * (1.7777778 - a)
        AgentSetPos(name, p)
        TWD43_Dbg[counter] = TWD43_Dbg[counter] + 1
      end
      out[#out + 1] = string.format("%s%.2f>%.2f", string.sub(name, 12, 12), before, AgentGetPos(name).x)
    end
  end
  return table.concat(out, " ")
end

local function TWD43_ReAnchor(agent)
  local e = TWD43_EdgeAgents[AgentGetName(agent)]
  if not e then
    return
  end
  TWD43_Dbg.cb = TWD43_Dbg.cb + 1
  local a = TWD43_WindowAspect()
  if not a or a >= 1.7777 then
    return
  end
  local pos = AgentGetPos(agent)
  TWD43_Dbg.cbx = string.format("%.2f", pos.x)
  TWD43_Log("cb " .. AgentGetName(agent) .. " x=" .. TWD43_Dbg.cbx)
  if pos and math.abs(pos.x - e.x) < 0.01 then
    pos.x = pos.x - e.side * e.halfH * (1.7777778 - a)
    AgentSetPos(agent, pos)
  end
end

-- Per-frame keeper: re-applies the move if anything (a chore, a scene reload) puts the label back.
local function TWD43_Keeper()
  TWD43_Log("keeper start " .. TWD43_StateId)
  local seen = false
  while true do
    TWD43_Beat = GetTotalTime()
    local ok, rep = pcall(TWD43_FixEdgeAgents, "tf")
    if not seen and (not ok or rep ~= "") then
      seen = true
      TWD43_Log("keeper " .. tostring(ok) .. " " .. tostring(rep))
    end
    Yield()
  end
end

local function TWD43_EnsureKeeper()
  if not TWD43_Beat or GetTotalTime() - TWD43_Beat > 1 then
    TWD43_Beat = GetTotalTime()
    ThreadStart(TWD43_Keeper)
  end
end

function TWD43_WrapTooltipRefresh(f)
  return function(...)
    local r = f(...)
    pcall(TWD43_EnsureKeeper)
    local ok, rep = pcall(TWD43_FixEdgeAgents, "rf")
    TWD43_Log("rf " .. tostring(ok) .. " " .. tostring(rep))
    if TWD43_DEBUG and AgentExists("ui_tooltip_noun") then
      local n = AgentGetProperty("ui_tooltip_noun", "Text String")
      if n and n ~= "" and n ~= " " then
        local d = TWD43_Dbg
        AgentSetProperty("ui_tooltip_noun", "Text String", n .. "  [43R5 " .. tostring(rep) .. " cb" .. d.cb .. "@" .. d.cbx .. " rf" .. d.rf .. " tf" .. d.tf .. "]")
      end
    end
    return r
  end
end

pcall(TWD43_EnsureKeeper)
if not rawget(_G, "TWD43_ReAnchorInstalled") then
  TWD43_ReAnchorInstalled = true
  EngineAddOnAgentSetupCallback(function(agent)
    pcall(TWD43_ReAnchor, agent)
  end)
end

TWD43_Log("hooks ok " .. TWD43_StateId)
dofile("ProjectSettingsShared_stock.lua")
TWD43_Log("stock done " .. TWD43_StateId)
