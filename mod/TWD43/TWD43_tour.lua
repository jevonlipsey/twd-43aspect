-- twd-43aspect TEST ONLY (appended by tools/build_fix43.py to test builds; --release leaves it out): warp tour,
-- episode side. Runs only while prefs "TWD43 Tour" == 1 (set by the Menu test set's DebugLoader.lua) and only in
-- the tour episodes. In each: a demo "<Name> will remember that." notification at kNoteAt seconds (and again later),
-- a demo hover label (S2/S3), then after kDwell seconds SubProject_StartEpisode(next). M101 is the last stop: it sets
-- the flag to 2 (done) and stays there. Times count from when this file loaded (early in the episode load).
-- TWD43_fix.lua calls TWD43_TourBeat() once per frame from its keeper.

local kFlag = "TWD43 Tour"
local kNext = {
  WalkingDead101 = "WalkingDead201",
  WalkingDead201 = "WalkingDead301",
  WalkingDead301 = "WalkingDead401",
  WalkingDead401 = "WalkingDeadM101",
  WalkingDeadM101 = false
}
local kDwell = {WalkingDead101 = 180}
local kDwellDefault = 130
local kNoteAt = {40, 85}
local kNoteText = "Clementine will remember that."
local kLabel = {
  S2 = {{"ui_reticle_textVerb", "Examine"}, {"ui_reticle_textNoun", "Hover label test"}},
  S3 = {{"ui_reticle_textVerb", "Examine"}, {"ui_reticle_textNoun", "Hover label test"}}
}
local kNoteAgent = {
  S2 = "ui_notification_textQuestion",
  S3 = "ui_notification_text",
  S4 = "ui_notification_text",
  M = "ui_notification_choiceText"
}

local mT0 = GetTotalTime()
local mNotesDone = 0
local mGone = false

local function TourFlag()
  local prefs = GetPreferences()
  if PropertyExists(prefs, kFlag) then
    return PropertyGet(prefs, kFlag)
  end
  return 0
end

local function WaitSeconds(s)
  local t = GetTotalTime() + s
  while GetTotalTime() < t do
    WaitForNextFrame()
  end
end

-- S1: WDChoiceNotification.lua shows ui_choice_notification.scene with its on/off chores (the node-name callback
-- only fires for a real dialog node), so replay that sequence with our own text.
local function NoteS1()
  local scene = SceneFind("ui_choice_notification.scene")
  if not scene or not AgentExists("ui_choice_notification_text") then
    return
  end
  AgentSetProperty("ui_choice_notification_text", "Text String", kNoteText)
  SceneHide(scene, false)
  ChorePlayAndWait("ui_choice_notification_on.chore")
  WaitSeconds(10)
  ChorePlayAndWait("ui_choice_notification_off.chore")
  SceneHide(scene, true)
end

-- S2/S3/S4/M: Notification_ShowChoice(node, delay, duration) adds ui_notification, waits `delay`, then sets the text
-- agent's node name. Node "" leaves the agent on its "Text String", which is set during the delay.
local function NoteSeason()
  local agent = kNoteAgent[TWD43_SEASON]
  if not agent or not rawget(_G, "Notification_ShowChoice") then
    return
  end
  -- every season gates ShowChoice on this pref (the menu's notification toggle): open it for the one call
  local prefs, k = GetPreferences(), "Enable Reticle Hint Dots"
  local was = PropertyGet(prefs, k)
  if not was then
    pcall(PropertySet, prefs, k, true)
  end
  Notification_ShowChoice("", 2, 10)
  if was == false then
    pcall(PropertySet, prefs, k, false)
  end
  for i = 1, 90 do
    if AgentExists(agent) then
      AgentSetProperty(agent, "Text String", kNoteText)
      break
    end
    WaitForNextFrame()
  end
end

local function DemoLabel()
  local rows = kLabel[TWD43_SEASON]
  if not rows then
    return
  end
  local t = GetTotalTime() + 8
  while GetTotalTime() < t do
    for _, row in ipairs(rows) do
      if AgentExists(row[1]) then
        local v = AgentGetProperty(row[1], "Text String")
        if type(v) ~= "string" or v == "" or v == " " then
          AgentSetProperty(row[1], "Text String", row[2])
        end
        AgentHide(row[1], false)
      end
    end
    WaitForNextFrame()
  end
end

local function Demo()
  if TWD43_SEASON == "S1" then
    pcall(NoteS1)
  else
    pcall(NoteSeason)
  end
  pcall(DemoLabel)
end

local function Leave(nextProject)
  if nextProject then
    SubProject_StartEpisode(nextProject)
  else
    local prefs = GetPreferences()
    PropertySet(prefs, kFlag, 2)
    SavePrefs()
  end
end

function TWD43_TourBeat()
  if mGone or TourFlag() ~= 1 then
    return
  end
  local cur = SubProject_GetCurrent()
  local nextProject = kNext[cur]
  if nextProject == nil then
    return
  end
  local t = GetTotalTime() - mT0
  if mNotesDone < #kNoteAt and t >= kNoteAt[mNotesDone + 1] then
    mNotesDone = mNotesDone + 1
    ThreadStart(Demo)
  end
  if t >= (kDwell[cur] or kDwellDefault) then
    mGone = true
    ThreadStart(Leave, nextProject)
  end
end
