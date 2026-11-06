-- twd-43aspect: keep the interaction label ("Examine / ATM") inside a 4:3 frame.
--
-- ui_tooltip.scene places the verb and noun text at x 12.776 (camera cam_ui_tooltip at z -20,
-- 45 degree vertical FOV, so the view is 8.2843 units half-high at the text; +x is screen left).
-- That is 1.95 units inside the left edge of a 16:9 frame (half-width 14.728), but 1.73 units
-- PAST the left edge of a 4:3 frame (half-width 11.046): only "ne" of "Examine" shows.
-- This moves both lines inward by halfH * (16/9 - aspect), so they keep the authored 1.95-unit
-- margin from the real left edge, at their authored size. Nothing changes on a 16:9 screen.
--
-- This file replaces Tooltip.lua; the game's own Tooltip.lua runs first, unchanged
-- (shipped as TWD43_Tooltip_stock.lua, copied byte for byte from the user's game).

require("TWD43_Tooltip_stock.lua")

local kAgents = {"ui_tooltip_verb", "ui_tooltip_noun"}
local kAuthoredX = 12.776
local kHalfHeight = 8.2843
TWD43_MARKER = " [43]"   -- test builds only: appended to the verb so a screenshot proves this file ran

local function WindowAspect()
  local r = RenderGetScreenResolution()
  if r and r.x and r.y and r.y > 0 then
    return r.x / r.y
  end
end

local function ReAnchor()
  local a = WindowAspect()
  if not a or a >= 1.7777 then
    return
  end
  if a < 1.3333333 then
    a = 1.3333333
  end
  local dx = kHalfHeight * (1.7777778 - a)
  for _, name in ipairs(kAgents) do
    if AgentExists(name) then
      local pos = AgentGetPos(name)
      if math.abs(pos.x - kAuthoredX) < 0.01 then
        pos.x = pos.x - dx
        AgentSetPos(name, pos)
      end
    end
  end
end

-- Re-applied every frame as well, in case a chore (ui_tooltip_on.chore) or a scene reload puts the
-- label back at its authored x. Only an agent still at the authored x is moved.
local function Keeper()
  while true do
    TWD43_TooltipBeat = GetTotalTime()
    pcall(ReAnchor)
    Yield()
  end
end

local function EnsureKeeper()
  if not TWD43_TooltipBeat or GetTotalTime() - TWD43_TooltipBeat > 1 then
    TWD43_TooltipBeat = GetTotalTime()
    ThreadStart(Keeper)
  end
end

local StockRefresh = Tooltip_Refresh

function Tooltip_Refresh(...)
  local r = StockRefresh(...)
  pcall(ReAnchor)
  pcall(EnsureKeeper)
  if TWD43_MARKER and AgentExists("ui_tooltip_verb") then
    local v = AgentGetProperty("ui_tooltip_verb", "Text String")
    if v and v ~= "" and v ~= " " then
      AgentSetProperty("ui_tooltip_verb", "Text String", v .. TWD43_MARKER)
    end
  end
  return r
end

pcall(EnsureKeeper)
