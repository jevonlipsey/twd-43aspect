-- Mac stub test for the hold-B skip sets (tools/build_skip43.py).
--   lua tools/stubskip.lua <S1|S2|S3|S4|M> out/skip43a_<s>/hook.src.lua mod/TWD43/TWD43_skip.lua
-- Runs the real hook source and the real TWD43_skip.lua against a stubbed engine, frame by frame, and checks:
-- 1 s hold skips once; a tap or a short hold does not; no repeat without release; never with a choice up, during a
-- QTE / action / struggle chore or mode, while paused, or outside a cutscene; a B press that began outside the cutscene
-- does not arm it; the 4:3 fix still loads (S2-M) / the stock dialog manager loads (S1); reload keeps ONE instance;
-- the bar agents are destroyed again.
local season, hookPath, skipPath = arg[1], arg[2], arg[3]
local N = ({S1 = 1, S2 = 2, S3 = 3, S4 = 4, M = 5})[season]
assert(N and hookPath and skipPath, "usage: stubskip.lua <season> <hook.src.lua> <TWD43_skip.lua>")
local fails = 0
local function check(cond, msg)
  if cond then print("ok   " .. msg) else print("FAIL " .. msg); fails = fails + 1 end
end

-- engine state
local S = {}
local function reset()
  S.t, S.frame, S.padB, S.choices, S.mode, S.paused, S.cutscene = 100, 0, false, nil, "cut", false, true
  S.ctrlTime, S.seeks, S.skips, S.keys, S.qteAgents, S.qteMode, S.actionMode = 0, {}, {}, {}, {}, false, false
  S.ctrl = {name = "ctrl" .. math.random(1e6)}
end
reset()
local function Callback(scoped)
  local cb = {fns = {}}
  if scoped then cb.mScenes = {} end
  function cb:Add(a, b) local fn = scoped and b or a; self.fns[#self.fns + 1] = fn end
  function cb:Remove(a, b)
    local fn = scoped and b or a
    for i = #self.fns, 1, -1 do if self.fns[i] == fn then table.remove(self.fns, i) end end
  end
  return cb
end
local post
if N == 1 then
  Callback_PostUpdate = Callback(false); post = Callback_PostUpdate
  Callback_ScenePreOpen, Callback_SceneOpenFinished, Callback_AppExit = Callback(false), Callback(false), Callback(false)
else
  Callback_OnPostUpdate = Callback(true); post = Callback_OnPostUpdate
  Callback_OnGameSceneOpen, Callback_OnSceneOpenFinished = Callback(true), Callback(true)
  if N == 4 then Callback_OnGameSceneEnd = Callback(true) end
end

-- vectors / agents / text (enough for the native bar's calibration)
function Vector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function Color(r, g, b, a) return {r, g, b, a} end
local agents, live = {}, 0
function AgentCreate(name, prop, pos, rot, scene) local a = {name = name, props = {}, scale = 1, minW = 0, pos = Vector(0.5, 0.5)}; agents[name] = a; live = live + 1; return a end
function AgentExists(name) return agents[name] ~= nil end
function AgentFind(name) return agents[name] end
function AgentDestroy(a) agents[a.name] = nil; live = live - 1 end
function AgentSetProperty(a, k, v) a.props[k] = v end
function AgentGetProperty(a, k) if k == "Text Reference Screen Size" then return Vector(1280, 960) end return a.props[k] end
function AgentSetWorldPosFromLogicalScreenPos(a, v) a.pos = v end
function TextSet(a, s) a.text = s end
function TextSetColor() end
function TextSetScale(a, s) a.scale = s end
function TextSetHorizAlign() end
function TextSetMinWidth(a, w) a.minW = w end
function TextSetBackgroundColor() end
function TextEnableBackground() end
function TextGetExtents(a)
  local w, h = (0.01 + 0.05 * a.minW) * a.scale, 0.03 * a.scale
  return Vector((a.pos.x - w / 2) * 1280, -(a.pos.y + h / 2) * 960), Vector((a.pos.x + w / 2) * 1280, -(a.pos.y - h / 2) * 960)
end
function RenderGetAspectRatio() return 1.7 end   -- the p10 channel value during gameplay
function GetFrameNumber() return S.frame end
function GetTotalTime() return S.t end
function GetFrameTime() return 1 / 30 end
function RenderDelay() end

-- dialog / mode state
eModeCutscene, eModeQTE, eModeAction, eModeStruggle, eModeDrag = {n = "cut"}, {n = "qte"}, {n = "action"}, {n = "struggle"}, {n = "drag"}
function Game_GetMode() return S.mode == "cut" and eModeCutscene or {n = S.mode} end
function Game_IsPaused() return S.paused end
function Game_GetScene() return "scene" end
function Game_ModeIsOnStack(m) return (m == eModeQTE and S.qteMode) or (m == eModeAction and S.actionMode) or false end
function Dialog_GetCurrentID() return 7 end
function Dialog_IsPaused() return S.paused end
function Dialog_IsInteractiveCutscene() return false end
if N == 3 or N == 4 then
  function MultiQTE_IsEnabled() return false end
  function QTE_GetQuickTimeAgents() return S.qteAgents end
end
function DlgIsRunning() return true end
function DlgGetChoices() return S.choices end
function DlgGetCurPlaybackController() return S.ctrl end
function ControllerIsPlaying() return true end
function ControllerIsPaused() return false end
function ControllerGetLength() return 10 end
function ControllerGetTime() return S.ctrlTime end
function ControllerSetTime(c, t) S.seeks[#S.seeks + 1] = t; S.ctrlTime = t end
function ControllerGetChore(c) return {chore = c} end
function ChoreGetMasterCut(ch) return ch end
function ChoreGetAgentNames() return {"Lee", "Clementine", "qte_agent"} end
function ChoreGetPropertyKeysAsStrings(ch, name, key) return S.keys[name .. "|" .. key] end
function AgentGetName(a) return a.name end
-- S1
function Cutscene_IsActive() return S.cutscene end
function Game_AllDialogsPaused() return S.paused end
function Dialog_GetActiveCutscenes() return S.cutscene and {7} or {} end
function SceneGetBottomScene() return "scene" end
function Dialog_SkipCutscene(id) S.skips[#S.skips + 1] = id; return true end
-- input: keyboard never down; pad B through the engine poll
function Input_IsPressed() return false end
function Input_IsVKeyPressed() return false end
function InputMapperKeyPressed(code) return code == 513 and S.padB end

-- resources
local fixLoads, stockLoads, fixExists = 0, 0, true
function ResourceExists(n) return n == "TWD43_fix.lua" and fixExists end
function require(n)
  if n == "TWD43_skip.lua" then return dofile(skipPath) end
  if n == "TWD43_fix.lua" then fixLoads = fixLoads + 1; return end
  if n == "TWD43_skip_dlgmgr_stock.lua" then stockLoads = stockLoads + 1; return end
  error("unexpected require " .. n)
end
local function loadHook() dofile(hookPath) end

local function frame(dt)
  S.t, S.frame = S.t + dt, S.frame + 1
  S.ctrlTime = math.min(S.ctrlTime + dt, 10)
  if S.ctrlTime >= 10 then   -- chore finished: the dialog moves on to its next node (new controller)
    S.ctrl, S.ctrlTime = {name = "ctrl" .. math.random(1e6)}, 0
  end
  for _, fn in ipairs(post.fns) do fn() end
end
local function run(seconds, b)
  S.padB = b
  for _ = 1, math.floor(seconds * 30 + 0.5) do frame(1 / 30) end
end
local function skipped() return N == 1 and #S.skips or #S.seeks end

-- load
loadHook()
check(#post.fns == 1, "one post-update callback registered")
if N == 1 then check(stockLoads == 1, "S1 stock module_dialog_manager required first") else check(fixLoads == 1, "4:3 TWD43_fix.lua still required by the merged hook") end
check(TWDSkipIntegratedSeason == nil, "season global cleared")

-- 1 s hold skips once
reset(); run(0.5, false); run(0.9, true)
check(skipped() == 0, "0.9 s hold: no skip yet")
check(live > 0, "bar agents shown while holding")
run(0.2, true)
check(skipped() == 1, "1.1 s hold: one skip")
if N ~= 1 then check(math.abs(S.seeks[1] - (10 - 1 / 30)) < 1e-6, "seek to the controller end minus a frame") end
run(3, true)
check(skipped() == 1, "keep holding: no second skip without release")
run(1, false)
check(live == 0, "bar agents destroyed after release")
run(1.1, true)
check(skipped() == 2, "release + new 1.1 s hold: second skip")
run(0.5, false)

-- tap / short holds
reset(); run(0.3, false)
for _ = 1, 5 do run(0.4, true); run(0.3, false) end
check(skipped() == 0, "taps of 0.4 s never skip")

-- choice up
reset(); S.choices = {"a", "b"}; run(0.2, false); run(2, true)
check(skipped() == 0, "choice on screen: no skip")
-- B pressed during the choice, held into the cutscene: not armed
S.choices = nil; run(2, true)
check(skipped() == 0, "B held over from a choice does not skip")
run(0.2, false); run(1.1, true)
check(skipped() == 1, "fresh press after the choice skips")
run(0.3, false)

-- interactive chore keys
for _, key in ipairs({"QTE - Showing Next Prompt", "QTE - Marker ID", "Action Enabled", "Struggle - Complete", "Timer Enabled"}) do
  reset(); S.keys["qte_agent|" .. key] = {"0.5"}; run(0.2, false); run(2, true)
  check(skipped() == 0, "chore keys '" .. key .. "': no skip")
  run(0.2, false)
end
-- a chore-API error counts as interactive
reset(); local saved = ChoreGetAgentNames; ChoreGetAgentNames = function() error("boom") end
run(0.2, false); run(2, true); check(skipped() == 0, "chore API error: no skip"); run(0.2, false)
ChoreGetAgentNames = saved

-- paused / not a cutscene
reset(); S.paused = true; run(0.2, false); run(2, true); check(skipped() == 0, "paused: no skip"); run(0.2, false)
reset(); S.mode = "navigate"; S.cutscene = false; run(0.2, false); run(2, true); check(skipped() == 0, "not a cutscene: no skip"); run(0.2, false)
if N == 2 then reset(); S.actionMode = true; run(0.2, false); run(2, true); check(skipped() == 0, "S2 action mode on the stack: no skip"); run(0.2, false) end
if N == 4 then reset(); S.qteAgents = {{name = "q"}}; run(0.2, false); run(2, true); check(skipped() == 0, "S4 QTE agents registered: no skip"); run(0.2, false) end
if N == 3 or N == 5 then reset(); S.qteMode = true; S.qteAgents = {{name = "q", mProps = {}}}; run(0.2, false); run(2, true); check(skipped() == 0, "QTE mode on the stack: no skip"); run(0.2, false) end
-- near the end of the chore there is nothing to skip
reset(); S.ctrlTime = 9.99; run(1.5, true); check(skipped() == 0, "chore already at its end: no seek"); run(0.2, false)

-- reload: one instance only
loadHook()
check(#post.fns == 1, "reload retires the old instance (one callback)")
reset(); run(0.2, false); run(1.2, true)
check(skipped() == 1, "after reload: one skip per hold")
run(0.5, false)

-- without the 4:3 set (S2-M): skip alone still loads
if N ~= 1 then
  fixExists = false; fixLoads = 0; loadHook()
  check(fixLoads == 0 and #post.fns == 1, "without the 4:3 set: no TWD43_fix require, skip still registered")
end

-- engine without InputMapperKeyPressed: keyboard path only, no error
InputMapperKeyPressed = nil; reset(); run(0.2, false); S.padB = true; run(1.5, true)
check(skipped() == 0 and #post.fns == 1, "no pad poll: inert, still registered")

print(fails == 0 and ("ALL OK " .. season) or (fails .. " FAILED " .. season))
os.exit(fails == 0 and 0 or 1)
