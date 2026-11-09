-- twd-43aspect TEST ONLY (tools/build_fix43.py --diag): measure a season's controller choice layout in one run.
-- Every kPhase seconds the layout cycles:
--   phase 0 = as authored
--   phase 1 = every choice TEXT moved up by kStep (S1: agent position; S2: "Text Offset", the icon stays)
--   phase 2 = phase 1 + the button cluster parent lifted by kStep
-- The X choice reads "P<phase> xxxxxxxx" so each screenshot names its layout. Chains TWD43_TourBeat.

local kPhase = 3
local kStep = 0.5
local kSeason = {
  S1 = {
    pos = {
      ui_dialog_Item1Gamepad = {0, -0.575},
      ui_dialog_Item2Gamepad = {0.5, -0.025},
      ui_dialog_Item3Gamepad = {-0.5, -0.025},
      ui_dialog_Item4Gamepad = {0, 0.65}
    },
    parent = {"dialogParentGamepad", 0, 0},
    label = "ui_dialog_Item3Gamepad"
  },
  S2 = {
    offset = {
      ui_dialog_button1 = {0, -0.6},
      ui_dialog_button2 = {0.6, 0},
      ui_dialog_button3 = {-0.6, 0},
      ui_dialog_button4 = {0, 0.6}
    },
    parent = {"ui_dialog_buttonParent", 0, 0.331},
    label = "ui_dialog_button3"
  }
}
local tourBeat = TWD43_TourBeat

local function Has(name)
  local ok, e = pcall(AgentExists, name)
  return ok and e
end

local function SetPos(name, x, y)
  if Has(name) then
    local pos = AgentGetPos(name)
    if pos then
      pos.x, pos.y = x, y
      AgentSetPos(name, pos)
    end
  end
end

local function Diag()
  local cfg = kSeason[TWD43_SEASON]
  if not cfg then
    return
  end
  local phase = math.floor(GetTotalTime() / kPhase) % 3
  local up = phase >= 1 and kStep or 0
  for name, a in pairs(cfg.pos or {}) do
    SetPos(name, a[1], a[2] + up)
  end
  for name, o in pairs(cfg.offset or {}) do
    if Has(name) then
      pcall(AgentSetProperty, name, "Text Offset", Vector(o[1], o[2] + up, 0))
    end
  end
  local p = cfg.parent
  SetPos(p[1], p[2], p[3] + (phase == 2 and kStep or 0))
  if Has(cfg.label) then
    local cur = AgentGetProperty(cfg.label, "Text String")
    local want = "P" .. phase .. " xxxxxxxx"
    if cur ~= want then
      AgentSetProperty(cfg.label, "Text String", want)
    end
  end
end

function TWD43_TourBeat()
  if tourBeat then
    pcall(tourBeat)
  end
  pcall(Diag)
end
