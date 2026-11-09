-- Mac stub test for TWD43_fix.lua section 6 (Reach). Loads the REAL decompiled reticle controller of the season,
-- then the built TWD43_fix.src.lua, drives its keeper and checks the reticle clamp in DRAWN space
-- (drawn = 0.5 + 0.75 * (u - 0.5) while the p10 channel is on).
--   lua tools/stubreach.lua <season S1|S2|S3|S4|M> <TWD43_fix.src.lua>
local season, path = arg[1], arg[2]
local ctl = ({S1 = "decomp/lua/ProjectSeason1/reticleController.lua"})[season]
  or ("decomp/lua/ProjectSeason" .. (season == "M" and "M" or season:sub(2)) .. "/ReticleController.lua")
local W, H, t, episode, scenes, fails = 1280, 960, 0, true, {}, 0
local logicProps = {["Reticle - Horiztonal Min Percentage Allowed"] = 0, ["Reticle - Horiztonal Max Percentage Allowed"] = 1,
  ["Reticle - Vertical Min Percentage Allowed"] = 0, ["Reticle - Vertical Max Percentage Allowed"] = 1}
local touched = 0
-- engine stubs
function Vector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function InRange(v, a, b) return v >= a and v <= b end
function GetPreferences() return {} end
function IsToolBuild() return false end
function Platform_IsIOS() return false end
function Platform_HasTouch() return false end
function Platform_HasController() return true end
function ReticleUI_Touch() touched = touched + 1 end
function RenderGetScreenResolution() return {x = W, y = H} end
local ag = {}   -- glue test agents: name -> {w = world pos, o = Text Offset}
function AgentExists(n) return ag[n] ~= nil end
function AgentGetWorldPos(n) local a = ag[n]; return {x = a.w.x, y = a.w.y, z = 0} end
function AgentGetProperty(n, k) if k == "Text Offset" and ag[n] then local o = ag[n].o; return {x = o.x, y = o.y, z = 0} end end
function AgentSetProperty(n, k, v) if k == "Text Offset" and ag[n] then ag[n].o = {x = v.x, y = v.y} end end
function AgentFind(n) if n == "logic_reticle" then return {mProps = logicProps} end end
function SceneIsActive(s) return scenes[s] == true end
function SubProject_IsEpisode() return episode end
function RenderSetAspectRatio() end
function GetTotalTime() return t end
local co
function ThreadStart(f) co = coroutine.create(f) end
Yield = coroutine.yield
function EngineAddOnAgentSetupCallback() end
require = function() end   -- S1 requires TVRemoteManager.lua at load
dofile(ctl)
local function step(n) for _ = 1, n do t = t + 0.016; assert(coroutine.resume(co)) end end
local function drawn(u) return 0.5 + 0.75 * (u - 0.5) end
local function check(label, x, y, wx, wy)   -- wx/wy: expected DRAWN position
  ReticleController_SetScreenPos(x, y)
  local p = ReticleController_GetScreenPos()
  local ok = (not wx or math.abs(drawn(p.x) - wx) < 1e-6) and (not wy or math.abs(drawn(p.y) - wy) < 1e-6)
  if not ok then fails = fails + 1 end
  print(string.format("  %-34s u=(%.4f, %.4f) drawn=(%.4f, %.4f) %s", label, p.x, p.y, drawn(p.x), drawn(p.y), ok and "ok" or "FAIL"))
end
local function checkU(label, x, y, ux, uy)  -- expected u (stock behaviour)
  ReticleController_SetScreenPos(x, y)
  local p = ReticleController_GetScreenPos()
  local ok = math.abs(p.x - ux) < 1e-6 and math.abs(p.y - uy) < 1e-6
  if not ok then fails = fails + 1 end
  print(string.format("  %-34s u=(%.4f, %.4f) want u=(%.4f, %.4f) %s", label, p.x, p.y, ux, uy, ok and "ok" or "FAIL"))
end
local gH = season == "S1" and 0.07 or 0.04
local gV = season == "S1" and 0.15 or 0.08
local stockGV = gV
dofile(path)
step(3)
print(season .. " 1280x960 gameplay (channel on)")
local gv43 = gH * 4 / 3
check("hard left/top", -5, -5, gH, gv43)
check("hard right/bottom", 5, 5, 1 - gH, 1 - gv43)
checkU("inside stays put", 0.3, 0.6, 0.3, 0.6)
-- what the user saw: stock clamp kept drawn x within 0.5 +- 0.75 * (0.5 - gH)
print(string.format("  (stock reach was drawn x %.4f..%.4f, y %.4f..%.4f)", drawn(gH), drawn(1 - gH), drawn(stockGV), drawn(1 - stockGV)))
if season == "S1" then
  local n = touched; ReticleController_SetScreenPos(0.5, 0.5); print("  ReticleUI_Touch still called:", touched > n)
  if touched <= n then fails = fails + 1 end
  n = touched; ReticleController_SetScreenPos(0.5, 0.5, true); print("  bNoTouch respected:", touched == n)
  if touched ~= n then fails = fails + 1 end
  logicProps["Reticle - Horiztonal Min Percentage Allowed"], logicProps["Reticle - Horiztonal Max Percentage Allowed"] = 0.3, 0.3
  logicProps["Reticle - Vertical Min Percentage Allowed"], logicProps["Reticle - Vertical Max Percentage Allowed"] = 0.4, 0.4
  checkU("locked (min == max) -> stock", -5, 5, 0.3, 0.4)
  logicProps["Reticle - Horiztonal Min Percentage Allowed"], logicProps["Reticle - Horiztonal Max Percentage Allowed"] = 0.25, 1
  logicProps["Reticle - Vertical Min Percentage Allowed"], logicProps["Reticle - Vertical Max Percentage Allowed"] = 0.2, 1
  check("scene limit h>=0.25 (drawn) v>=0.2 (u)", -5, -5, 0.25, drawn(0.2))
  logicProps["Reticle - Horiztonal Min Percentage Allowed"], logicProps["Reticle - Vertical Min Percentage Allowed"] = 0, 0
  logicProps["Reticle - Horiztonal Max Percentage Allowed"], logicProps["Reticle - Vertical Max Percentage Allowed"] = 1, 1
end
scenes["ui_menuPause.scene"] = true; step(2)
print("pause (channel off) -> stock clamp")
checkU("hard left/top", -5, -5, gH, gV)
scenes["ui_menuPause.scene"] = nil; step(2)
print("resume")
check("hard left/top", -5, -5, gH, gv43)
-- the controller file re-runs (new scene): the stock global comes back and is wrapped again on the next beat
dofile(ctl); ReticleController_SetScreenPos(-5, -5)
print("controller re-loaded (before beat): stock", math.abs(ReticleController_GetScreenPos().x - gH) < 1e-9 and "ok" or "FAIL")
step(1)
check("after one beat: rewrapped", -5, -5, gH, gv43)
W, H = 1920, 1080; step(2)
print("1920x1080 -> stock")
checkU("hard left/top", -5, -5, gH, gV)
W, H = 1280, 960; step(2)
episode = false; step(2)
print("menu subproject -> stock")
checkU("hard left/top", -5, -5, gH, gV)
-- Glue rows (S2-M choices, M hover label): Text Offset = authored + (0.75 - 1) * world pos, follows, never fights
if TWD43_GLUE then
  W, H = 1280, 960; episode = true; step(2)
  for _, r in ipairs(TWD43_GLUE) do ag[r[1]] = {w = {x = 8, y = -3}, o = {x = r[2], y = r[3]}} end
  step(1)
  local function glued(r, wx, wy) local o = ag[r[1]].o; return math.abs(o.x - (r[2] - 0.25 * wx)) < 1e-6 and math.abs(o.y - (r[3] - 0.25 * wy)) < 1e-6 end
  local okg = true
  for _, r in ipairs(TWD43_GLUE) do okg = okg and glued(r, 8, -3) end
  for _, r in ipairs(TWD43_GLUE) do ag[r[1]].w = {x = -9, y = 4} end
  step(1)
  for _, r in ipairs(TWD43_GLUE) do okg = okg and glued(r, -9, 4) end
  local r1 = TWD43_GLUE[1]; ag[r1[1]].o = {x = 5, y = 5}; step(1)   -- someone else's value: left alone
  okg = okg and ag[r1[1]].o.x == 5
  print("glue rows " .. #TWD43_GLUE .. ": " .. (okg and "ok" or "FAIL"))
  if not okg then fails = fails + 1 end
end
print(fails == 0 and (season .. " REACH OK") or (season .. " REACH FAILED " .. fails))
os.exit(fails == 0 and 0 or 1)
