-- twd-43aspect: 4:3 fixes that run inside each season's Lua (one copy per season set, built by tools/build_fix43.py).
-- The build prepends the season's generated table (mod/TWD43/anchors_<season>.lua):
--   TWD43_ANCHORS = { {agent, authored local x, half-height of its UI camera at the agent, sign}, ... }
--   TWD43_WRAP    = { {agent, authored "Text Width" (0 = none), room inside 4:3}, ... }
-- plus TWD43_SEASON, TWD43_MARKER (" [43]" in test builds, nil in release), TWD43_MARKED (agents to mark) and, in
-- test builds, TWD43_LONG (set of choice agents that also get TWD43_LONG_TAIL, to force a wrap).
--
-- 1. Re-anchor: every UI scene is authored for 16:9 (the engine renders a camera at 0.75 x its authored FOV, so the
--    pins sit exactly on the 16:9 edge). Edge elements are moved inward by halfH * (16/9 - aspect): same distance
--    from the real edge as authored, same size. Only an agent still at its authored x is moved (idempotent).
-- 2. Wrap: dialogue choices get a "Text Width" that fits inside the 4:3 frame, so a long option breaks onto a
--    second line at its authored glyph size instead of running past the edge. "Text Width" is the engine's wrap
--    width (squeezing is a separate flag, "Text Shrink To Fit", false on every choice prop); never widened.
-- 3. Vert+ channel for the exe (tools/patch43.py --level p10): during gameplay RenderSetAspectRatio(1.7) tells the
--    camera cave to give every 3D camera the full 16:9 width (cameras below 15 degrees included); while a menu scene
--    is up it is set back to the window aspect, so menu scenes keep the p6menu look.

local kOn = 1.7
local kMenuScenes = {"ui_menuPause.scene", "ui_menuEndOfEpisode.scene", "Menu_Pause.scene", "Menu_Pause", "ui_menuPause", "ui_menu_pause.scene"}
local kWide = 1.7777778

local function WindowAspect()
  local r = RenderGetScreenResolution()
  if r and r.x and r.y and r.y > 0 then
    return r.x / r.y
  end
end

local function Exists(name)
  local ok, e = pcall(AgentExists, name)
  return ok and e
end

local function ReAnchor(a)
  local k = kWide - a
  for _, row in ipairs(TWD43_ANCHORS) do
    local name, ax, hh, sign = row[1], row[2], row[3], row[4]
    if Exists(name) then
      local pos = AgentGetPos(name)
      if pos and math.abs(pos.x - ax) < 0.01 then
        pos.x = ax - sign * hh * k
        AgentSetPos(name, pos)
      end
    end
  end
end

local mWrapped = {}

local function Wrap()
  for _, row in ipairs(TWD43_WRAP) do
    local name, room = row[1], row[3]
    if Exists(name) then
      local agent = AgentFind(name)
      if mWrapped[name] ~= agent then
        -- only ever narrow: the authored (or inherited) width wins when it already fits; 0 = no wrap at all
        local ok, w = pcall(AgentGetProperty, name, "Text Width")
        if not ok or type(w) ~= "number" or w <= 0 or w > room then
          pcall(AgentSetProperty, name, "Text Width", room)
        end
        mWrapped[name] = agent
      end
    end
  end
end

-- 4. Nudge (TWD43_NUDGE, per season, from device measurements): at 4:3 the controller choice cluster renders with its
--    face-button icons at 0.75 of the text's scale, so the authored text offsets land on the buttons (Y text over the
--    Y icon, X/B text a row low, A text under the timer bar). Rows: {agent, authored x, authored y, dx, dy, mode, grow}.
--    mode "offset": (ax, ay) and (dx, dy) apply to the agent's "Text Offset" instead of its position (S2 buttons).
--    mode "add": the offset is added on top of whatever position the agent has now (its chores re-pose it), once per
--    new base. Otherwise the agent is only moved from its authored position (or the spot this file put it), and
--    grow = +1 / -1 moves it half a line up / down per extra wrapped line (text is centred on its row), so a long
--    Y choice grows upward away from its icon and a long A choice downward. linesOf (8th field) makes an agent follow
--    another agent's line count instead (the timer bar steps down with a wrapped A choice).
local kHalfLine = 0.225
local mNudged = {}

local function Lines(name)
  local ok, n = pcall(TextGetNumLines, AgentFind(name))
  if ok and type(n) == "number" and n >= 1 then
    return n
  end
  return 1
end

local function Nudge()
  local rows = rawget(_G, "TWD43_NUDGE")
  if not rows then
    return
  end
  for _, row in ipairs(rows) do
    local name, ax, ay, dx, dy, mode, grow, linesOf = row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]
    local half = row[9] or kHalfLine   -- half a text line in this row's units (S2 font differs from S1)
    if Exists(name) then
      local pos = AgentGetPos(name)
      local last = mNudged[name]
      if mode == "offset" then
        -- S2: the choice text sits at "Text Offset" (ax, ay) from its icon; move only the text, never the icon
        local ok, o = pcall(AgentGetProperty, name, "Text Offset")
        if ok and o then
          local atHome = math.abs(o.x - ax) < 0.01 and math.abs(o.y - ay) < 0.01
          local atOurs = last and math.abs(o.x - last.x) < 1e-4 and math.abs(o.y - last.y) < 1e-4
          if atHome or atOurs then
            local extra = grow and grow * (Lines(linesOf or name) - 1) * half or 0
            local tx, ty = ax + dx, ay + dy + extra
            if math.abs(o.x - tx) > 1e-4 or math.abs(o.y - ty) > 1e-4 then
              pcall(AgentSetProperty, name, "Text Offset", Vector(tx, ty, o.z or 0))
            end
            mNudged[name] = {x = tx, y = ty}
          end
        end
      elseif pos and mode == "add" then
        if not (last and math.abs(pos.x - last.x) < 1e-4 and math.abs(pos.y - last.y) < 1e-4) then
          pos.x, pos.y = pos.x + dx, pos.y + dy
          AgentSetPos(name, pos)
          mNudged[name] = {x = pos.x, y = pos.y}
        end
      elseif pos then
        local atHome = math.abs(pos.x - ax) < 0.01 and math.abs(pos.y - ay) < 0.01
        local atOurs = last and math.abs(pos.x - last.x) < 1e-4 and math.abs(pos.y - last.y) < 1e-4
        if atHome or atOurs then
          -- linesOf: follow another agent's line count (the timer bar moves down with a wrapped A choice)
          local extra = grow and grow * (Lines(linesOf or name) - 1) * half or 0
          local tx, ty = ax + dx, ay + dy + extra
          if math.abs(pos.x - tx) > 1e-4 or math.abs(pos.y - ty) > 1e-4 then
            pos.x, pos.y = tx, ty
            AgentSetPos(name, pos)
          end
          mNudged[name] = {x = tx, y = ty}
        end
      end
    end
  end
end

-- 5. Glue (TWD43_GLUE, S2-M): during gameplay the exe's vert+ scale (p10 channel) also reaches the UI cameras, so UI
--    MESHES (face-button icons, timer bars) are drawn at 0.75 about the screen centre while TEXT is drawn unscaled
--    (device-measured 2026-11-09: icon = 480 + 0.75 * (text - 480) px in S1, S2 and S3). A choice's text therefore
--    drifts away from its own icon by 0.25 x its distance from the centre (choices sit low: text ~60 px under the
--    icons). Each row {agent, authored Text Offset x, y} puts the agent's text back at its authored offset from the
--    icon as drawn: Text Offset = authored + (s - 1) * world position (UI cameras sit at x = y = 0). Text size and
--    spacing are untouched. Follows the parent at runtime (subtitle / timer re-posing); only ever moves an offset
--    that is still authored or the value this file set.
local mGlued = {}

local function Glue()
  local rows = rawget(_G, "TWD43_GLUE")
  if not rows then
    return
  end
  local s = TWD43_GLUE_SCALE or 0.75
  for _, row in ipairs(rows) do
    local name, ax, ay = row[1], row[2], row[3]
    if Exists(name) then
      local okw, w = pcall(AgentGetWorldPos, name)
      local ok, o = pcall(AgentGetProperty, name, "Text Offset")
      if okw and w and ok and o then
        local last = mGlued[name]
        local atHome = math.abs(o.x - ax) < 0.01 and math.abs(o.y - ay) < 0.01
        local atOurs = last and math.abs(o.x - last.x) < 1e-4 and math.abs(o.y - last.y) < 1e-4
        if atHome or atOurs then
          local tx, ty = ax + (s - 1) * w.x, ay + (s - 1) * w.y
          if math.abs(o.x - tx) > 1e-4 or math.abs(o.y - ty) > 1e-4 then
            pcall(AgentSetProperty, name, "Text Offset", Vector(tx, ty, o.z or 0))
          end
          mGlued[name] = {x = tx, y = ty}
        end
      end
    end
  end
end

local function Mark()
  if not TWD43_MARKER then
    return
  end
  for _, name in ipairs(TWD43_MARKED) do
    if Exists(name) then
      local ok, v = pcall(AgentGetProperty, name, "Text String")
      if ok and type(v) == "string" and v ~= "" and v ~= " " and not string.find(v, "[43", 1, true) then
        -- test builds: choice lines that should wrap get a long tail so the first real choice proves the wrap
        local tail = TWD43_LONG and TWD43_LONG[name] and TWD43_LONG_TAIL or ""
        pcall(AgentSetProperty, name, "Text String", v .. TWD43_MARKER .. tail)
      end
    end
  end
end

local function InMenu()
  if rawget(_G, "SubProject_IsEpisode") then
    local ok, ep = pcall(SubProject_IsEpisode)
    if ok and not ep then
      return true
    end
  end
  for _, s in ipairs(kMenuScenes) do
    local ok, active = pcall(SceneIsActive, s)
    if ok and active then
      return true
    end
  end
  if rawget(_G, "Game_IsPaused") then
    local ok, p = pcall(Game_IsPaused)
    if ok and p then
      return true
    end
  end
  return false
end

local mLastChannel, mChannelAge = nil, 0

local function Channel(a)
  local want = InMenu() and a or kOn
  mChannelAge = mChannelAge + 1
  -- re-asserted every ~30 frames: stock code (S2 pause close, Menu_endEpisode, EpisodeSystem) writes 16/9 over it
  if want ~= mLastChannel or mChannelAge > 30 then
    mLastChannel, mChannelAge = want, 0
    pcall(RenderSetAspectRatio, want)
  end
end

local function Beat()
  if rawget(_G, "TWD43_TourBeat") then   -- test builds only (mod/TWD43/TWD43_tour.lua)
    pcall(TWD43_TourBeat)
  end
  local a = WindowAspect()
  if not a or a >= 1.7777 then
    return
  end
  if a < 1.3333333 then
    a = 1.3333333
  end
  pcall(ReAnchor, a)
  pcall(Wrap)
  pcall(Nudge)
  pcall(Glue)
  pcall(Mark)
  pcall(Channel, a)
end

local function Keeper()
  while true do
    TWD43_FixBeat = GetTotalTime()
    pcall(Beat)
    Yield()
  end
end

local function EnsureKeeper()
  if not TWD43_FixBeat or GetTotalTime() - TWD43_FixBeat > 1 then
    TWD43_FixBeat = GetTotalTime()
    ThreadStart(Keeper)
  end
end

-- agent setup fires on every scene load, so a keeper thread that died with a scene is restarted
EngineAddOnAgentSetupCallback(function(agent)
  pcall(EnsureKeeper)
end)
pcall(EnsureKeeper)
