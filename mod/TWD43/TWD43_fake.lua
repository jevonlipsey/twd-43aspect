-- twd-43aspect TEST ONLY (tools/build_fix43.py --fake): synthetic controller choice prompts for S3/S4/M, so one run
-- can judge the choice layout where the tour reaches no real dialogue choice in time (S4 import screen, M101 QTEs).
-- Uses the same scene agents and chores as the stock code (GameDialog.lua / DialogChoices.lua: SetChoices sets
-- "Text String" + unhides ui_dialog_controller1-4, then SceneHide(false) + ui_dialog_controllerShow +
-- ui_dialog_timerShow), so the geometry is the real one. 1 = A (below), 2 = B, 3 = X, 4 = Y (above).
-- Times count from when this file loaded. Chains TWD43_TourBeat.

local kFakeAt = {S3 = {50, 80}, S4 = {95, 125, 155}, M = {35, 65, 95}}
local kTexts = {
  {"A short", "B short", "X short", "Y short"},
  {"A: this option is long enough to need a second line", "B: this option is long enough to need a second line",
   "X: this option is long enough to need a second line", "Y: this option is long enough to need a second line"}
}
local fakeT0 = GetTotalTime()
local fakeDone = 0
local fakeBusy = false
local fakeTourBeat = TWD43_TourBeat

local function FakeWait(s)
  local t = GetTotalTime() + s
  while GetTotalTime() < t do
    WaitForNextFrame()
  end
end

local function FakeChoice(texts)
  fakeBusy = true
  if AgentExists("ui_dialog_controller1") then
    for i = 1, 4 do
      local n = "ui_dialog_controller" .. i
      if AgentExists(n) then
        AgentSetProperty(n, "Text String", texts[i])
        AgentHide(n, false, true)
      end
    end
    pcall(AgentHide, "ui_dialog_mouseParent", true, true)
    pcall(AgentHide, "ui_dialog_touchParent", true, true)
    pcall(AgentHide, "ui_dialog_controllerParent", false, true)
    pcall(SceneHide, "ui_dialog", false)
    pcall(ChorePlayAndWait, "ui_dialog_controllerShow")
    pcall(ChorePlay, "ui_dialog_timerShow")
    FakeWait(9)
    pcall(SceneHide, "ui_dialog", true)
  end
  fakeBusy = false
end

function TWD43_TourBeat()
  if fakeTourBeat then
    pcall(fakeTourBeat)
  end
  local at = kFakeAt[TWD43_SEASON]
  if not at or fakeBusy or fakeDone >= #at then
    return
  end
  if GetTotalTime() - fakeT0 >= at[fakeDone + 1] then
    fakeDone = fakeDone + 1
    ThreadStart(FakeChoice, kTexts[(fakeDone - 1) % 2 + 1])
  end
end
