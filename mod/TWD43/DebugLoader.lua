-- twd-43aspect TEST ONLY (tools/build_tour43.py; never shipped): warp tour, Definitive Menu side.
-- Stock ships no DebugLoader.lua; the Definitive menu requires it when present (Menu/Menu_main.lua:16-19, then
-- Callback_OnLoadDebugMenu:Add at :175), and so do BootTitle and the season menus / pause menus. So this file must
-- (1) give every caller a harmless Callback_OnLoadDebugMenu, (2) do nothing outside the "Menu" subproject.
-- In the Definitive menu, once per tour: set prefs "TWD43 Tour" = 1 and start WalkingDead101 after kDelay seconds.
-- The season sets' TWD43_tour.lua then chain 101 -> 201 -> 301 -> 401 -> M101 and clear the flag at the end.

if not rawget(_G, "Callback_OnLoadDebugMenu") then
  Callback_OnLoadDebugMenu = {
    Add = function() end,
    Remove = function() end,
    Call = function() end
  }
end

local kFlag = "TWD43 Tour"
local kFirst = "WalkingDead101"
local kDelay = 8

local function TourFlag()
  local prefs = GetPreferences()
  if PropertyExists(prefs, kFlag) then
    return PropertyGet(prefs, kFlag)
  end
  return 0
end

local function StartTour()
  local prefs = GetPreferences()
  if PropertyExists(prefs, kFlag) then
    PropertySet(prefs, kFlag, 1)
  else
    PropertyCreate(prefs, kFlag, "int", 1)
  end
  SavePrefs()
  Sleep(kDelay)
  SubProject_StartEpisode(kFirst)
end

local function MaybeStart()
  if TWD43_TourMenuThread or SubProject_GetCurrent() ~= "Menu" then
    return
  end
  -- 0 = never toured (the user's prefs), 1 = tour running, 2 = tour finished: start only from 0
  if TourFlag() ~= 0 then
    return
  end
  TWD43_TourMenuThread = ThreadStart(StartTour)
end

pcall(MaybeStart)
