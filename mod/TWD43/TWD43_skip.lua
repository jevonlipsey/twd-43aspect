-- TWD43_skip.lua: hold B (controller east button) for 1 s to skip the current cutscene stretch.
-- Adapted from "TWDG-Skip" (Nexus Mods, The Walking Dead: The Telltale Definitive Series, mod 333), whose
-- twd_skip_integrated.lua (hold-state model, native progress bar, eligibility checks, skip by seeking the dialog's
-- playback controller) is kept here almost unchanged; credit to its author. Changes for twd-43aspect:
--   * controller: InputMapperKeyPressed(513) = kEventCodeButtonB (engine binding; S4 NavigateWD.lua polls pad codes
--     with it), plus the original keyboard keys (Q, S1 also Space);
--   * hold 1 s instead of 3 s; caption "HOLD B TO SKIP";
--   * extra guard (all seasons): never skip a chore that keys a QTE / action / struggle / timer property;
--   * Michonne (season 5) on the S3 path with that guard (no QTE registry getter there);
--   * no log file writes.
local TWDHoldState = (function()
  local HoldState = {}
  local HOLD_SECONDS = 1
  local DRAIN_SECONDS = 0.7
  local FADE_IN_SECONDS = 0.18
  local FADE_OUT_SECONDS = 0.22
  local CONFIRM_SECONDS = 0.2
  
  local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
  end
  
  local function clamp01(n)
    return math.min(1, math.max(0, n))
  end
  
  local function clear(self)
    self.phase = "idle"
    self.progress = 0
    self.opacity = 0
    self.context = nil
    self.startedAt = nil
    self.startProgress = 0
    self.drainAt = nil
    self.drainProgress = 0
    self.successAt = nil
  end
  
  local function snapshot(self, skip)
    local slide = 1 - self.opacity
    return {
      phase = self.phase,
      progress = self.progress,
      opacity = self.opacity,
      slide = slide * slide,
      visible = self.phase ~= "idle",
      skip = skip == true,
      context = self.context
    }
  end
  
  function HoldState.new(options)
    options = options or {}
    local maxGap = options.maxGap or 0.25
    assert(finite(maxGap) and 0 < maxGap, "maxGap must be a positive finite number")
    local self = {
      maxGap = maxGap,
      armed = false,
      q = false,
      space = false,
      lastTime = nil
    }
    clear(self)
    return setmetatable(self, {__index = HoldState})
  end
  
  function HoldState:invalidate()
    clear(self)
    self.armed = false
    self.q, self.space = false, false
    self.lastTime = nil
    return snapshot(self, false)
  end
  
  function HoldState:step(now, q, space, eligible, context)
    if not finite(now) or type(q) ~= "boolean" or type(space) ~= "boolean" or type(eligible) ~= "boolean" then
      return self:invalidate()
    end
    local dt = self.lastTime and now - self.lastTime or 0
    if dt < 0 or not finite(dt) then
      return self:invalidate()
    end
    local wasQ, wasSpace = self.q, self.space
    local wasDown, isDown = wasQ or wasSpace, q or space
    local released = wasQ and not q or wasSpace and not space
    local pressed = q and not wasQ or space and not wasSpace
    self.q, self.space, self.lastTime = q, space, now
    if dt > self.maxGap and (self.phase ~= "idle" or wasDown) then
      clear(self)
      self.armed = not isDown
      return snapshot(self, false)
    end
    if not eligible or context == nil then
      clear(self)
      self.armed = not isDown
      return snapshot(self, false)
    end
    if self.context ~= nil and self.context ~= context then
      clear(self)
      self.armed = not isDown
      return snapshot(self, false)
    end
    local skip = false
    if self.phase == "holding" then
      local elapsed = now - self.startedAt
      local fraction = clamp01(elapsed / HOLD_SECONDS)
      self.progress = self.startProgress + (1 - self.startProgress) * fraction
      self.opacity = clamp01(self.opacity + dt / FADE_IN_SECONDS)
      if released then
        self.progress = math.min(self.progress, 0.999999)
        if isDown then
          self.startedAt = now
          self.startProgress = self.progress
        else
          self.phase = "draining"
          self.drainAt = now
          self.drainProgress = self.progress
        end
      elseif isDown and elapsed >= HOLD_SECONDS then
        self.progress = 1
        self.phase = "success"
        self.successAt = now
        self.armed = false
        skip = true
      end
    elseif self.phase == "draining" then
      self.progress = math.max(0, self.drainProgress - (now - self.drainAt) / DRAIN_SECONDS)
      self.opacity = clamp01(self.opacity + dt / FADE_IN_SECONDS)
      if 0 >= self.progress then
        self.phase = "fading"
      end
    elseif self.phase == "fading" then
      self.opacity = clamp01(self.opacity - dt / FADE_OUT_SECONDS)
      if 0 >= self.opacity then
        clear(self)
      end
    elseif self.phase == "success" and now - self.successAt >= CONFIRM_SECONDS then
      self.opacity = clamp01(self.opacity - dt / FADE_OUT_SECONDS)
      if 0 >= self.opacity then
        clear(self)
      end
    end
    if not isDown then
      self.armed = true
    end
    if pressed and isDown and not wasDown and self.armed and self.phase ~= "holding" then
      if self.phase == "success" then
        self.progress = 0
      end
      self.phase = "holding"
      self.context = context
      self.startedAt = now
      self.startProgress = self.progress
      self.drainAt, self.successAt = nil, nil
    end
    return snapshot(self, skip)
  end
  
  return HoldState
end)()
local TWDNativeBar = (function()
  local NativeBar = {}
  local PROBE = 4
  local themes = {
    [1] = {
      fill = {
        0.67,
        0.09,
        0.13
      },
      head = {
        0.9,
        0.32,
        0.28
      },
      border = {
        0.42,
        0.27,
        0.27
      },
      text = {
        0.84,
        0.8,
        0.76
      },
      track = {
        0.045,
        0.035,
        0.038
      },
      glow = 0.08
    },
    [2] = {
      fill = {
        0.26,
        0.59,
        0.71
      },
      head = {
        0.78,
        0.94,
        0.98
      },
      border = {
        0.37,
        0.53,
        0.59
      },
      text = {
        0.82,
        0.91,
        0.95
      },
      track = {
        0.035,
        0.055,
        0.065
      },
      glow = 0.19
    },
    [3] = {
      fill = {
        0.72,
        0.15,
        0.07
      },
      head = {
        1,
        0.55,
        0.22
      },
      border = {
        0.5,
        0.29,
        0.19
      },
      text = {
        0.93,
        0.84,
        0.74
      },
      track = {
        0.055,
        0.032,
        0.025
      },
      glow = 0.14
    },
    [4] = {
      fill = {
        0.38,
        0.15,
        0.31
      },
      head = {
        0.75,
        0.36,
        0.44
      },
      border = {
        0.43,
        0.3,
        0.44
      },
      text = {
        0.88,
        0.8,
        0.88
      },
      track = {
        0.042,
        0.03,
        0.05
      },
      glow = 0.13
    }
  }
  local parts = {
    "Label",
    "Shadow",
    "Border",
    "Track",
    "GlowOuter",
    "GlowInner",
    "Fill",
    "Highlight",
    "Head",
    "LeftTick",
    "RightTick",
    "Detail1",
    "Detail2"
  }
  
  local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
  end
  
  local function clamp(n, low, high)
    return math.max(low, math.min(high, n))
  end

  themes[5] = themes[3]   -- Michonne: A New Frontier's palette

  function NativeBar.new(season, trace)
    assert(themes[season], "unsupported bar theme")
    return setmetatable({
      season = season,
      agents = {},
      names = {},
      cache = {},
      scene = nil,
      guard = nil,
      metrics = nil,
      calibration = nil,
      caption = nil,
      trace = trace
    }, {__index = NativeBar})
  end
  
  function NativeBar:available()
    for _, name in ipairs({
      "AgentCreate",
      "AgentExists",
      "AgentFind",
      "AgentDestroy",
      "AgentSetProperty",
      "AgentGetProperty",
      "AgentSetWorldPosFromLogicalScreenPos",
      "TextSet",
      "TextSetColor",
      "TextSetScale",
      "TextSetHorizAlign",
      "TextGetExtents",
      "TextSetMinWidth",
      "TextSetBackgroundColor",
      "TextEnableBackground",
      "RenderGetAspectRatio",
      "GetFrameNumber",
      "Vector",
      "Color"
    }) do
      if type(_G[name]) ~= "function" then
        return false
      end
    end
    return true
  end
  
  function NativeBar:destroy()
    self.guard = nil
    for index, agent in pairs(self.agents) do
      pcall(function()
        local name = self.names[index]
        if AgentExists(name) and AgentFind(name) == agent then
          pcall(AgentSetProperty, agent, "Runtime: Visible", false)
          AgentDestroy(agent)
        end
      end)
    end
    self.agents, self.names, self.cache = {}, {}, {}
    self.scene, self.metrics, self.calibration, self.caption = nil, nil, nil, nil
  end
  
  function NativeBar:_check()
    if self.failure or self.cancelled then
      return false
    end
    if self.guard == nil or not self.guard() then
      self.cancelled = true
      return false
    end
    return true
  end
  
  function NativeBar:_fail(reason)
    self.failure = reason
    return false
  end
  
  function NativeBar:_call(fn, ...)
    if not self:_check() then
      return nil
    end
    local a, b = fn(...)
    if not self:_check() then
      return nil
    end
    return a, b
  end
  
  function NativeBar:_property(index, name, value)
    if not self:_check() then
      return
    end
    local cache = self.cache[index]
    if cache[name] ~= value then
      if name == "Text Min Width" then
        self:_call(TextSetMinWidth, self.agents[index], value)
      elseif name == "Text Background" then
        self:_call(TextEnableBackground, self.agents[index], value)
      else
        self:_call(AgentSetProperty, self.agents[index], name, value)
      end
      cache[name] = value
    end
  end
  
  function NativeBar:_create(scene)
    self.scene = scene
    for index, part in ipairs(parts) do
      self.names[index] = "TWDHoldSkipS" .. self.season .. part
      if self:_call(AgentExists, self.names[index]) then
        return self:_fail("bar agent name already exists")
      end
    end
    for index in ipairs(parts) do
      if not self:_check() then
        return false
      end
      local name = self.names[index]
      local agent = AgentCreate(name, "ui_text.prop", Vector(0, 0, 0), Vector(0, 0, 0), scene, false, false)
      if agent == nil then
        return self:_fail("native bar creation failed")
      end
      self.names[index] = name
      self.agents[index], self.cache[index] = agent, {}
      if not self:_check() then
        return false
      end
      self:_call(TextSetHorizAlign, agent, 2)
      self:_call(TextSetScale, agent, index == 1 and 0.6 or 1)
      self:_call(TextSet, agent, index == 1 and "" or ".")
      self:_property(index, "Game Selectable", false)
      self:_property(index, "Exclude From Save Games", true)
      self:_property(index, "Text Shadow Height", 0)
      self:_property(index, "Text Render Layer", index == 1 and 99 or 80 + index)
      self:_property(index, "Text Render After Post-Effects", true)
      self:_call(TextSetBackgroundColor, agent, Color(0, 0, 0, 0))
      self:_property(index, "Text Background", index ~= 1)
      self:_property(index, "Text Min Width", 0)
      self:_property(index, "Text Min Height", 0)
      self:_call(TextSetColor, agent, Color(1, 1, 1, 1))
      self:_property(index, "Runtime: Visible", false)
    end
    return self:_check()
  end
  
  function NativeBar:_reference()
    local ref = self:_call(AgentGetProperty, self.agents[7], "Text Reference Screen Size")
    if not (ref ~= nil and finite(ref.x) and finite(ref.y)) or ref.x <= 0 or ref.y <= 0 then
      self:_fail("invalid text reference screen size")
      return nil
    end
    return ref.x, ref.y
  end
  
  function NativeBar:_measure(index, refX, refY)
    local low, high = self:_call(TextGetExtents, self.agents[index])
    if not (low ~= nil and high ~= nil and finite(low.x) and finite(low.y) and finite(high.x)) or not finite(high.y) then
      self:_fail("invalid native text extents")
      return nil
    end
    return {
      w = (high.x - low.x) / refX,
      h = (high.y - low.y) / refY,
      x = (high.x + low.x) / (2 * refX),
      y = -(high.y + low.y) / (2 * refY)
    }
  end
  
  function NativeBar:_calibrate(refX, refY, aspect)
    local frame = self:_call(GetFrameNumber)
    if not finite(frame) then
      return self:_fail("native frame counter unavailable")
    end
    local c = self.calibration
    if c == nil or c.refX ~= refX or c.refY ~= refY or c.aspect ~= aspect then
      c = {
        refX = refX,
        refY = refY,
        aspect = aspect,
        frame = frame,
        stage = 0
      }
      self.calibration = c
      for index in ipairs(parts) do
        self:_property(index, "Runtime: Visible", false)
      end
      self:_property(7, "Text Min Width", 0)
      self:_call(TextSetScale, self.agents[7], 1)
      self:_call(AgentSetWorldPosFromLogicalScreenPos, self.agents[7], Vector(-2, -2, 0))
      self:_property(7, "Runtime: Visible", true)
      local hint = "HOLD B TO SKIP"
      self:_call(TextSet, self.agents[1], hint)
      self:_call(TextSetScale, self.agents[1], 0.6)
      self.caption = hint
      return false, "warming"
    end
    if frame <= c.frame then
      return false, "warming"
    end
    if c.stage == 0 then
      c.base = self:_measure(7, refX, refY)
      if c.base == nil then
        return false
      end
      c.stage, c.frame = 1, frame
      self:_property(7, "Text Min Width", PROBE)
      return false, "warming"
    end
    if c.stage == 1 then
      c.a = self:_measure(7, refX, refY)
      if c.a == nil then
        return false
      end
      c.stage, c.frame = 2, frame
      self:_property(7, "Text Min Width", 2 * PROBE)
      return false, "warming"
    end
    local a, b = c.a, self:_measure(7, refX, refY)
    if b == nil then
      return false
    end
    local sw = (b.w - a.w) / PROBE
    if not (finite(sw) and not (sw < 1.0E-10) and finite(a.h)) or 0 >= a.h then
      return self:_fail("native rectangle calibration unavailable; reference=" .. refX .. "x" .. refY .. "; measures=" .. a.w .. "," .. a.h .. " / " .. b.w .. "," .. b.h)
    end
    self.metrics = {
      refX = refX,
      refY = refY,
      aspect = aspect,
      sw = sw,
      baseHeight = a.h,
      minWidth = c.base.w,
      iw = a.w - PROBE * sw,
      cx = 2 * a.x - b.x,
      cy = a.y,
      dx = (b.x - a.x) / PROBE
    }
    local width = clamp(0.3911111 / aspect, 0.12, 0.65)
    self.metrics.width = width
    self:_call(TextSetScale, self.agents[1], 0.6)
    if self.trace then
      self.trace("native metrics: reference=" .. refX .. "x" .. refY .. " aspect=" .. aspect .. " rect=" .. a.w .. "," .. a.h .. " / " .. b.w .. "," .. b.h .. " widthSlope=" .. sw .. " glyphMinimum=" .. c.base.w)
    end
    self.calibration = nil
    return self:_check()
  end
  
  function NativeBar:_rect(index, cx, cy, width, height, rgb, alpha)
    if not self:_check() then
      return
    end
    if width <= 0 or height <= 0 or alpha <= 0 then
      self:_property(index, "Runtime: Visible", false)
      return
    end
    local m = self.metrics
    local scale = height / m.baseHeight
    if width < scale * m.minWidth then
      self:_property(index, "Runtime: Visible", false)
      return
    end
    local pw = (width / scale - m.iw) / m.sw
    if not (finite(pw) and finite(scale)) or pw < 0 or scale <= 0 or 100000000 < pw or 10 < scale then
      self:_fail("native rectangle dimensions out of range")
      return
    end
    self:_call(TextSetScale, self.agents[index], scale)
    self:_property(index, "Text Min Width", pw)
    self:_call(TextSetBackgroundColor, self.agents[index], Color(rgb[1], rgb[2], rgb[3], clamp(alpha, 0, 1)))
    self:_call(TextSetColor, self.agents[index], Color(rgb[1], rgb[2], rgb[3], clamp(alpha, 0, 1)))
    self:_call(AgentSetWorldPosFromLogicalScreenPos, self.agents[index], Vector(cx - scale * (m.cx + pw * m.dx), cy - scale * m.cy, 0))
    self:_property(index, "Runtime: Visible", true)
  end
  
  function NativeBar:_draw(view)
    for index, agent in ipairs(self.agents) do
      if not self:_call(AgentExists, self.names[index]) or self:_call(AgentFind, self.names[index]) ~= agent then
        return self:_fail("owned native bar agent disappeared")
      end
    end
    local aspect = self:_call(RenderGetAspectRatio)
    if not finite(aspect) or aspect < 0.5 or 5 < aspect then
      return self:_fail("unsupported screen aspect ratio")
    end
    local refX, refY = self:_reference()
    if refX == nil then
      return false
    end
    if self.metrics == nil or self.metrics.refX ~= refX or self.metrics.refY ~= refY or self.metrics.aspect ~= aspect then
      local ready, status = self:_calibrate(refX, refY, aspect)
      if not ready then
        return false, status
      end
    end
    local t, m = themes[self.season], self.metrics
    local p, opacity = clamp(view.progress, 0, 1), clamp(view.opacity, 0, 1)
    opacity = opacity * opacity * (3 - 2 * opacity)
    local y, w, h = 0.795 + view.slide * 0.012, m.width, 0.008
    local xunit = 1.7777778 / aspect
    local left, edge = 0.5 - w / 2, 0.5 - w / 2 + w * p
    local pulse = view.phase == "success" and 1 or 0
    local hint = view.phase == "success" and "SKIPPING..." or "HOLD B TO SKIP"
    if hint ~= self.caption then
      self:_call(TextSet, self.agents[1], hint)
      self.caption = hint
    end
    self:_property(1, "Runtime: Visible", 0 < opacity)
    self:_call(TextSetColor, self.agents[1], Color(t.text[1], t.text[2], t.text[3], opacity))
    self:_call(AgentSetWorldPosFromLogicalScreenPos, self.agents[1], Vector(0.5, y - 0.025, 0))
    self:_rect(2, 0.5, y + 0.001, w + 0.008 * xunit, h + 0.009, {
      0,
      0,
      0
    }, opacity * 0.65)
    self:_rect(3, 0.5, y, w + 0.002 * xunit, h + 0.002, t.border, opacity)
    self:_rect(4, 0.5, y, w, h, t.track, opacity)
    self:_rect(5, edge, y, 0.014 * xunit, h + 0.012, t.head, 0 < p and opacity * (t.glow + 0.06 * pulse) or 0)
    self:_rect(6, edge, y, 0.007 * xunit, h + 0.006, t.head, 0 < p and opacity * (t.glow + 0.08 * pulse) or 0)
    self:_rect(7, left + w * p / 2, y, w * p, h, t.fill, opacity)
    self:_rect(8, left + w * p / 2, y - h / 2 + 7.0E-4, w * p, 0.0014, t.head, opacity * 0.6)
    self:_rect(9, edge - 0.0012 * xunit, y, math.min(w * p, 0.0024 * xunit), h, t.head, opacity)
    self:_rect(10, left - 0.004 * xunit, y, 0.0022 * xunit, h + 0.004, t.head, opacity * 0.6)
    self:_rect(11, left + w + 0.004 * xunit, y, 0.0022 * xunit, h + 0.004, t.head, opacity * 0.6)
    if self.season == 1 then
      self:_rect(12, left + w * 0.31, y, 0.001 * xunit, h * 0.65, t.track, 0.32 < p and opacity * 0.5 or 0)
      self:_rect(13, left + w * 0.72, y, 6.0E-4 * xunit, h * 0.4, t.track, 0.73 < p and opacity * 0.5 or 0)
    elseif self.season == 3 then
      self:_rect(12, left - 0.007 * xunit, y + 0.002, 0.002 * xunit, 0.0015, t.head, opacity * 0.8)
      self:_rect(13, left + w + 0.007 * xunit, y - 0.002, 0.002 * xunit, 0.0015, t.head, opacity * 0.8)
    else
      self:_rect(12, 0.5, y + h / 2 + 0.001, w, 6.0E-4, t.border, opacity * 0.6)
      self:_rect(13, 0.5, y - h / 2 - 0.001, w, 6.0E-4, t.border, opacity * 0.6)
    end
    return self:_check()
  end
  
  function NativeBar:render(scene, view, guard)
    if not view.visible or scene == nil then
      self:destroy()
      return true
    end
    if self.scene ~= nil and self.scene ~= scene then
      self:destroy()
    end
    self.guard = guard
    self.failure, self.cancelled = nil, false
    local ok, drawn, status = pcall(function()
      if self.scene == nil and not self:_create(scene) then
        return false
      end
      return self:_draw(view)
    end)
    if not ok or self.failure or self.cancelled then
      local reason = not ok and tostring(drawn) or self.failure
      local cancelled = self.cancelled
      self:destroy()
      if cancelled then
        return false, "cancelled"
      end
      return false, "error: " .. tostring(reason)
    end
    return drawn, status
  end
  
  return NativeBar
end)()
local season = TWDSkipIntegratedSeason
local dryRun = TWDSkipIntegratedDryRun == true
local buildId = TWDSkipIntegratedBuild or "source-test"
local model
local enabled = true
local updating = false
local generation = 0
local target
local registrations = {}
local renderer, lastDiagnostic
local colors = {
  [1] = {
    0.72,
    0.24,
    0.23
  },
  [2] = {
    0.56,
    0.8,
    0.91
  },
  [3] = {
    0.92,
    0.37,
    0.18
  },
  [4] = {
    0.72,
    0.43,
    0.61
  }
}
colors[5] = colors[3]

-- no file writes: keep the last 40 messages in memory (TWD43_SkipLog) for debugging
local function trace(message)
  pcall(function()
    local log = rawget(_G, "TWD43_SkipLog")
    if type(log) ~= "table" then
      log = {}
      _G.TWD43_SkipLog = log
    end
    log[#log + 1] = tostring(message)
    if #log > 40 then
      table.remove(log, 1)
    end
  end)
end

if type(season) ~= "number" or colors[season] == nil then
  trace("not loaded: invalid or missing TWDSkipIntegratedSeason")
  return
end
if type(TWDHoldState) ~= "table" or type(TWDHoldState.new) ~= "function" then
  trace("not loaded: hold-state module unavailable")
  return
end
model = TWDHoldState.new()
if type(TWDNativeBar) ~= "table" or type(TWDNativeBar.new) ~= "function" then
  trace("not loaded: native renderer unavailable")
  return
end
renderer = TWDNativeBar.new(season, trace)

local function finite(number)
  return type(number) == "number" and number == number and number ~= math.huge and number ~= -math.huge
end

local function cleanup()
  renderer:destroy()
end

local function invalidate(reason)
  target = nil
  model:invalidate()
  cleanup()
  if reason then
    trace(reason)
  end
end

local function stop(reason)
  enabled = false
  invalidate(reason)
  for _, registration in ipairs(registrations) do
    if type(registration.callback.Remove) == "function" then
      if registration.sceneScoped then
        pcall(registration.callback.Remove, registration.callback, nil, registration.fn)
      else
        pcall(registration.callback.Remove, registration.callback, registration.fn)
      end
    end
  end
  registrations = {}
end

local function sceneChanged()
  if not enabled then
    return
  end
  generation = generation + 1
  invalidate()
end

local function subscribe(callback, fn)
  if callback == nil or type(callback.Add) ~= "function" then
    return false
  end
  local sceneScoped = type(callback.mScenes) == "table"
  if sceneScoped then
    callback:Add(nil, fn)
  else
    callback:Add(fn)
  end
  registrations[#registrations + 1] = {
    callback = callback,
    fn = fn,
    sceneScoped = sceneScoped
  }
  return true
end

local lifecycleBound = {}

local function bindLifecycle()
  local names
  if season == 1 then
    names = {
      "Callback_ScenePreOpen",
      "Callback_SceneOpenFinished",
      "Callback_AppExit"
    }
  else
    names = {
      "Callback_OnGameSceneOpen",
      "Callback_OnSceneOpenFinished"
    }
    if season == 4 then
      names[#names + 1] = "Callback_OnGameSceneEnd"
    end
  end
  for _, name in ipairs(names) do
    local callback = _G[name]
    if callback ~= lifecycleBound[name] and subscribe(callback, sceneChanged) then
      lifecycleBound[name] = callback
    end
  end
end

local function apisAvailable()
  local names = {
    "GetTotalTime",
    "AgentCreate",
    "AgentExists",
    "AgentFind",
    "AgentDestroy",
    "AgentSetProperty",
    "AgentSetWorldPosFromLogicalScreenPos",
    "TextSet",
    "TextSetColor",
    "TextSetScale",
    "TextSetHorizAlign",
    "Vector",
    "Color"
  }
  for _, name in ipairs(names) do
    if type(_G[name]) ~= "function" then
      return false
    end
  end
  return colors[season] ~= nil and renderer:available()
end

local function hasChoices(id)
  local choices = DlgGetChoices(id)
  return choices ~= nil and (type(choices) ~= "table" or next(choices) ~= nil)
end

local function blocked(reason)
  return nil, nil, reason
end

local function seekPosition(controller)
  if type(ControllerGetLength) ~= "function" or type(ControllerGetTime) ~= "function" or type(GetFrameTime) ~= "function" then
    return nil
  end
  local length, current, dt = ControllerGetLength(controller), ControllerGetTime(controller), GetFrameTime()
  if not (finite(length) and not (length <= 0) and finite(current) and not (current < 0) and finite(dt)) or dt <= 0 or 0.25 < dt then
    return nil
  end
  local margin = season == 1 and dt or math.min(dt, 0.1)
  local destination = math.max(0, length - margin)
  if current >= destination then
    return nil
  end
  return destination
end

local function playback(id)
  if type(DlgIsRunning) ~= "function" or type(DlgGetCurPlaybackController) ~= "function" or type(ControllerIsPlaying) ~= "function" or type(ControllerIsPaused) ~= "function" or DlgIsRunning(id) ~= true then
    return nil
  end
  local controller = DlgGetCurPlaybackController(id)
  if controller == nil or ControllerIsPlaying(controller) ~= true or ControllerIsPaused(controller) ~= false then
    return nil
  end
  if season == 1 then
    if type(Dialog_SkipCutscene) ~= "function" then
      return nil
    end
  elseif type(ControllerSetTime) ~= "function" or type(RenderDelay) ~= "function" then
    return nil
  end
  if seekPosition(controller) == nil then
    return nil
  end
  return controller
end

local function season3QteCheck(agents, controller)
  if type(Game_ModeIsOnStack) ~= "function" or eModeQTE == nil or Game_ModeIsOnStack(eModeQTE) ~= false then
    return false, "qte-mode-or-api"
  end
  if type(ControllerGetChore) ~= "function" or type(ChoreGetMasterCut) ~= "function" or type(AgentGetName) ~= "function" or type(ChoreGetPropertyKeysAsStrings) ~= "function" then
    return false, "qte-marker-api-unavailable"
  end
  local chore = ControllerGetChore(controller)
  if chore == nil then
    return false, "qte-chore-unavailable"
  end
  local cut = ChoreGetMasterCut(chore)
  if cut == nil then
    return false, "qte-master-cut-unavailable"
  end
  local count, maxIndex = 0, 0
  for index, agent in pairs(agents) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or agent == nil then
      return false, "qte-registry-unexpected"
    end
    count, maxIndex = count + 1, math.max(maxIndex, index)
    local props = agent.mProps
    if props == nil then
      return false, "qte-state-unavailable"
    end
    if props["QTE - Showing Next Prompt"] ~= false or props["QTE - Player Movement Enabled"] ~= false or agent.actionPromptShown or agent.actionController ~= nil then
      return false, "qte-active-or-state-unknown"
    end
    local name = AgentGetName(agent)
    if type(name) ~= "string" or name == "" then
      return false, "qte-name-unavailable"
    end
    local promptKeys = ChoreGetPropertyKeysAsStrings(cut, name, "QTE - Showing Next Prompt")
    local markerKeys = ChoreGetPropertyKeysAsStrings(cut, name, "QTE - Marker ID")
    if promptKeys ~= nil or markerKeys ~= nil then
      return false, "qte-markers-present"
    end
  end
  if count == 0 or count ~= maxIndex then
    return false, "qte-registry-unexpected"
  end
  return true, "eligible"
end

-- twd-43aspect guard: a chore that keys any of these properties drives a QTE, an action/struggle prompt or a timer;
-- skipping it could jump past input the player has to give, so it is never skippable. Unknown = not skippable.
local kInteractiveKeys = {
  "QTE - Showing Next Prompt",
  "QTE - Marker ID",
  "QTE - Player Movement Enabled",
  "Action Enabled",
  "Action Reset",
  "Trigger Event Dialog",
  "Struggle - Complete",
  "Timer Enabled"
}
local interactiveCache = setmetatable({}, {__mode = "k"})

local function choreInteractive(controller)
  local cached = interactiveCache[controller]
  if cached ~= nil then
    return cached
  end
  local result = true
  if type(ControllerGetChore) == "function" and type(ChoreGetAgentNames) == "function" and type(ChoreGetPropertyKeysAsStrings) == "function" then
    local ok, found = pcall(function()
      local chore = ControllerGetChore(controller)
      if chore == nil then
        return true
      end
      local names = ChoreGetAgentNames(chore)
      if type(names) ~= "table" then
        return true
      end
      for _, name in pairs(names) do
        if type(name) == "string" then
          for _, key in ipairs(kInteractiveKeys) do
            if ChoreGetPropertyKeysAsStrings(chore, name, key) then
              return true
            end
          end
        end
      end
      return false
    end)
    result = not ok or found ~= false
  end
  interactiveCache[controller] = result
  return result
end

local function modeOnStack(mode)
  return mode ~= nil and (type(Game_ModeIsOnStack) ~= "function" or Game_ModeIsOnStack(mode) ~= false)
end

local function eligible()
  if type(DlgGetChoices) ~= "function" then
    return blocked("choices-api-unavailable")
  end
  if season == 1 then
    if type(Cutscene_IsActive) ~= "function" or Cutscene_IsActive() ~= true or type(Game_AllDialogsPaused) ~= "function" or Game_AllDialogsPaused() ~= false or type(Dialog_GetActiveCutscenes) ~= "function" or type(SceneGetBottomScene) ~= "function" then
      return blocked("cutscene-or-api")
    end
    local dialogs = Dialog_GetActiveCutscenes()
    if type(dialogs) ~= "table" or #dialogs ~= 1 then
      return blocked("active-dialog-count")
    end
    local id, scene = dialogs[1], SceneGetBottomScene()
    if id == nil or scene == nil or hasChoices(id) then
      return blocked("scene-or-choice")
    end
    local controller = playback(id)
    if controller == nil then
      return blocked("dialog-controller-unavailable")
    end
    if choreInteractive(controller) then
      return blocked("interactive-chore")
    end
    return scene, id, "eligible", controller
  end
  if type(Game_GetMode) ~= "function" or eModeCutscene == nil or Game_GetMode() ~= eModeCutscene or type(Game_IsPaused) ~= "function" or Game_IsPaused() ~= false or type(Game_GetScene) ~= "function" then
    return blocked("mode-pause-or-api")
  end
  if 3 <= season and (type(Dialog_IsPaused) ~= "function" or Dialog_IsPaused() ~= false) then
    return blocked("dialog-paused-or-api")
  end
  if season == 4 and (type(Dialog_IsInteractiveCutscene) ~= "function" or Dialog_IsInteractiveCutscene() ~= false) then
    return blocked("interactive-cutscene-or-api")
  end
  if season == 2 and (modeOnStack(eModeAction) or modeOnStack(eModeStruggle) or modeOnStack(eModeDrag)) then
    return blocked("action-struggle-drag-mode")
  end
  if season == 5 and (eModeQTE == nil or modeOnStack(eModeQTE)) then
    return blocked("qte-mode-or-api")
  end
  local qteAgents
  if season == 3 or season == 4 then
    if type(MultiQTE_IsEnabled) ~= "function" or MultiQTE_IsEnabled() ~= false or type(QTE_GetQuickTimeAgents) ~= "function" then
      return blocked("multi-qte-active-or-api")
    end
    qteAgents = QTE_GetQuickTimeAgents()
    if type(qteAgents) ~= "table" then
      return blocked("qte-registry-unavailable")
    end
    if season == 4 and next(qteAgents) ~= nil then
      return blocked("qte-agents-present")
    end
  end
  if type(Dialog_GetCurrentID) ~= "function" or type(DlgIsRunning) ~= "function" or type(DlgGetCurPlaybackController) ~= "function" or type(ControllerIsPlaying) ~= "function" or type(ControllerIsPaused) ~= "function" then
    return blocked("dialog-controller-api")
  end
  local scene, id = Game_GetScene(), Dialog_GetCurrentID()
  if not (scene ~= nil and id ~= nil and DlgIsRunning(id)) or hasChoices(id) then
    return blocked("scene-dialog-or-choice")
  end
  local controller = playback(id)
  if controller == nil then
    return blocked("controller-not-playing-or-api")
  end
  if season == 3 and next(qteAgents) ~= nil then
    local safe, reason = season3QteCheck(qteAgents, controller)
    if not safe then
      return blocked(reason)
    end
  end
  if choreInteractive(controller) then
    return blocked("interactive-chore")
  end
  return scene, id, "eligible", controller
end

local function render(scene, view)
  local expectedGeneration = generation
  return renderer:render(scene, view, function()
    return enabled and generation == expectedGeneration
  end)
end

local function sameCandidate(candidate)
  if not enabled or candidate.generation ~= generation then
    return false
  end
  local scene, id, _, controller = eligible()
  return scene ~= nil and scene == candidate.scene and id == candidate.id and controller == candidate.controller
end

local function readInput()
  local input
  if season == 1 then
    input = Input_IsPressed
  else
    input = Input_IsVKeyPressed
  end
  if type(input) ~= "function" then
    return nil, nil, "required input API is unavailable"
  end
  local q, space = input(81), false
  if season == 1 then
    space = input(32)
  end
  if type(q) ~= "boolean" or type(space) ~= "boolean" then
    return nil, nil, "invalid input state"
  end
  -- controller B (east, kEventCodeButtonB = 513): engine poll of the held state, same call S4 NavigateWD.lua makes
  -- for pad codes; S1 falls back to Input.lua's own begin/end tracking. Counted as the "Q" key of the hold model.
  local pad = false
  if type(InputMapperKeyPressed) == "function" then
    pad = InputMapperKeyPressed(513) and true or false
  elseif season == 1 and type(Input_IsButtonPressed) == "function" then
    local ok, down = pcall(Input_IsButtonPressed, 513)
    pad = ok and down == true
  end
  return q or pad, space
end

local function inputUnchanged(q, space)
  local currentQ, currentSpace, reason = readInput()
  return reason == nil and currentQ == q and currentSpace == space
end

local function skipScene(candidate, q, space)
  if not sameCandidate(candidate) or not inputUnchanged(q, space) then
    return false, "target-changed"
  end
  local destination = seekPosition(candidate.controller)
  if destination == nil then
    return false, "invalid-controller-time"
  end
  if season == 1 then
    local result = Dialog_SkipCutscene(candidate.id)
    return result == true, "dialog-skip-" .. tostring(result)
  end
  RenderDelay(1)
  if not sameCandidate(candidate) or not inputUnchanged(q, space) then
    return false, "target-changed-after-delay"
  end
  destination = seekPosition(candidate.controller)
  if destination == nil then
    return false, "invalid-controller-time-after-delay"
  end
  ControllerSetTime(candidate.controller, destination)
  return true, "controller-seek"
end

local function update()
  if not enabled then
    return
  end
  bindLifecycle()
  if not apisAvailable() then
    stop("integrated hold-skip disabled: required engine UI API is unavailable")
    return
  end
  local q, space, inputError = readInput()
  if inputError then
    stop("integrated hold-skip disabled: " .. inputError)
    return
  end
  local now = GetTotalTime()
  if not finite(now) then
    invalidate("invalid-clock")
    return
  end
  if not q and not space and model.phase == "idle" then
    model:step(now, q, space, false, nil)
    target = nil
    for key in pairs(interactiveCache) do
      interactiveCache[key] = nil
    end
    cleanup()
    lastDiagnostic = nil
    return
  end
  local scene, id, reason, controller = eligible()
  local candidate
  if scene ~= nil then
    if target == nil or target.scene ~= scene or target.id ~= id or target.controller ~= controller or target.generation ~= generation then
      target = {
        scene = scene,
        id = id,
        controller = controller,
        generation = generation
      }
    end
    candidate = target
  else
    target = nil
  end
  local view = model:step(now, q, space, candidate ~= nil, candidate)
  if q or space then
    local diagnostic = scene ~= nil and "eligible/" .. view.phase or "blocked/" .. reason
    if diagnostic ~= lastDiagnostic then
      trace("UI check: " .. diagnostic)
      lastDiagnostic = diagnostic
    end
  else
    lastDiagnostic = nil
  end
  local drawn, renderStatus = render(scene, view)
  if not drawn then
    if type(renderStatus) == "string" and renderStatus:sub(1, 7) == "error: " then
      stop("integrated hold-skip disabled: renderer " .. renderStatus)
      return
    end
    if renderStatus ~= "warming" or view.skip then
      invalidate("render unavailable; skip cancelled")
    end
    return
  end
  if view.skip and candidate ~= nil then
    if dryRun then
      trace("display-only confirmation; skip DISABLED")
      return
    end
    local ok, result = skipScene(candidate, q, space)
    trace("skip result: " .. tostring(ok) .. " (" .. tostring(result) .. ")")
    if not ok then
      invalidate("skip cancelled; waiting for release")
      return
    end
  end
end

local function safeUpdate()
  if not enabled or updating then
    return
  end
  updating = true
  local ok, err = pcall(update)
  updating = false
  if not ok then
    stop("integrated hold-skip disabled: " .. tostring(err))
  end
end

local callback
if season == 1 then
  callback = Callback_PostUpdate
else
  callback = Callback_OnPostUpdate
end
local instances = _G.TWDHoldSkipIntegratedInstances
if instances == nil then
  instances = {}
  _G.TWDHoldSkipIntegratedInstances = instances
end
if type(instances) ~= "table" then
  trace("not loaded: instance registry is not a table")
  return
end
for _, previous in pairs(instances) do
  if type(previous) ~= "table" or type(previous.stop) ~= "function" then
    trace("not loaded: unexpected existing instance")
    return
  end
end
for key, previous in pairs(instances) do
  previous.stop("retired after script reload")
  instances[key] = nil
end
if callback and type(callback.Add) == "function" then
  local ok, err = pcall(function()
    subscribe(callback, safeUpdate)
    bindLifecycle()
  end)
  if not ok then
    stop("callback registration failed: " .. tostring(err))
    return
  end
  instances[season] = {stop = stop}
  local mapping = season == 1 and "Q/Space" or "Q only"
  trace("integrated hold-skip loaded for season " .. tostring(season) .. "; " .. mapping .. (dryRun and "; display-only, skip DISABLED" or "; skip enabled") .. "; build=" .. tostring(buildId))
else
  trace("integrated hold-skip could not register update callback")
end
