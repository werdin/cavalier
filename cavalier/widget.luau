--!nonstrict
-- Media Cava — bar widget entry.
--
-- Layout (horizontal bar):  [ audio visualizer ] [ ⏮  ⏯  ⏭ ]
--
-- Data sources:
--   * onAudioSpectrum(valuesCsv, stateCsv) — Noctalia's built-in PipeWire
--       spectrum. valuesCsv is comma-separated bar magnitudes; stateCsv[1]==1
--       means audio is active. Defining this global is the opt-in — the host
--       wires the spectrum when the plugin is (re)enabled/loaded.
--   * playerctl (MPRIS) — polled in update() to pick the active player (the one
--       that is Playing, else the one we last controlled) for the play/pause
--       glyph and for the transport buttons.
--
-- Interaction:
--   * transport buttons consume their own clicks (onPrev/onPlayPause/onNext);
--   * clicking anywhere else on the capsule (the visualizer) triggers the
--     widget-level onClick(), which toggles the built-in Control Center on its
--     media view.

-- ── Settings (seeded from plugin.toml defaults) ──────────────────────────────
local AUDIO_REACTIVE = noctalia.getConfig("audio_spectrum") ~= false
local SENSITIVITY = tonumber(noctalia.getConfig("sensitivity")) or 2.0
-- Temporal damping: fraction of the previous bar height kept each frame.
-- 0 = raw/snappy, higher = smoother and calmer. Clamped to stay stable.
local SMOOTHING = tonumber(noctalia.getConfig("smoothing")) or 0.6
if SMOOTHING < 0 then SMOOTHING = 0 end
if SMOOTHING > 0.95 then SMOOTHING = 0.95 end
local SHOW_VIS = noctalia.getConfig("show_visualizer") ~= false
local BAR_COUNT = math.max(4, math.floor(tonumber(noctalia.getConfig("bar_count")) or 14))
local ACCENT = noctalia.getConfig("accent_color") or "primary"
local CC_CONTEXT = noctalia.getConfig("cc_context") or "media"

local MAX_BAR_H = 16 -- px; kept short so the capsule never clips
local MIN_BAR_H = 2

-- ── State ────────────────────────────────────────────────────────────────────
local isVertical = false
local hasPlayer = false
local activePlayer = "" -- MPRIS player name the buttons act on
local status = "" -- "Playing" | "Paused" | ""
local tipText = "" -- hover tooltip ("Title — Artist")
local audioActive = false
local vals = {} -- spectrum magnitudes (0..1), length BAR_COUNT
local frame = 0

for i = 1, BAR_COUNT do
  vals[i] = 0
end

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function parseCsvNumbers(csv)
  local out = {}
  if not csv then return out end
  for part in tostring(csv):gmatch("([^,]+)") do
    table.insert(out, tonumber(part) or 0)
  end
  return out
end

-- ── Rendering ────────────────────────────────────────────────────────────────
local function visualizer()
  local bars = {}
  for i = 1, BAR_COUNT do
    local v = audioActive and clamp01(vals[i] or 0) or 0
    local h = math.floor(v * MAX_BAR_H + 0.5)
    if h < MIN_BAR_H then h = MIN_BAR_H end
    bars[i] = ui.box({
      key = "bar" .. i,
      width = 3,
      height = h,
      radius = 2,
      fill = ACCENT,
    })
  end
  return ui.row({ key = "viz", gap = 2, align = "center", height = MAX_BAR_H }, bars)
end

local function render()
  local kids = {}

  if SHOW_VIS then
    table.insert(kids, visualizer())
  end

  local playGlyph = (status == "Playing") and "player-pause" or "player-play"
  table.insert(kids, ui.button({
    key = "prev",
    glyph = "player-skip-back",
    glyphSize = 13,
    variant = "ghost",
    enabled = true,
    tooltip = noctalia.tr("tooltip.previous"),
    onClick = "onPrev",
  }))
  -- Play/pause: only a real ui.button consumes its click in the bar (container
  -- click-targets fall through to the widget-level onClick / panel). A filled
  -- "primary" variant gives the accent background; a compact size makes the
  -- theme's button radius reach half the size, so it reads as a circle.
  table.insert(kids, ui.button({
    key = "playpause",
    glyph = playGlyph,
    glyphSize = 15,
    variant = "primary",
    enabled = true,
    tooltip = noctalia.tr("tooltip.playpause"),
    onClick = "onPlayPause",
  }))
  table.insert(kids, ui.button({
    key = "next",
    glyph = "player-skip-forward",
    glyphSize = 13,
    variant = "ghost",
    enabled = true,
    tooltip = noctalia.tr("tooltip.next"),
    onClick = "onNext",
  }))

  local container = isVertical and ui.column or ui.row
  barWidget.render(container({ gap = 4, align = "center" }, kids))

  if hasPlayer and tipText ~= "" then
    barWidget.setTooltip(tipText)
  end
end

-- ── MPRIS player selection (polled) ──────────────────────────────────────────
-- Follow whatever is actually playing, but stay *sticky* once we have a player:
-- with several MPRIS sources around (say mpd + Spotify) pausing the active one
-- leaves them all Paused, and a plain "first paused wins" rule would silently
-- hand the buttons to whichever name playerctl happens to list first. Then the
-- next Play would resume the wrong player.
local function refreshMeta()
  noctalia.runAsync(
    "playerctl -a metadata --format '{{playerName}}\t{{status}}\t{{title}}\t{{artist}}' 2>/dev/null",
    function(res)
      local out = res and res.stdout or ""
      local playing, paused, firstAny, current

      for line in out:gmatch("[^\n]+") do
        local name, st, ti, ar = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if name and name ~= "" then
          local entry = { name = name, st = st, ti = ti, ar = ar }
          if not firstAny then firstAny = entry end
          if st == "Playing" and not playing then playing = entry end
          if st == "Paused" and not paused then paused = entry end
          if name == activePlayer then current = entry end
        end
      end

      -- A Stopped player (e.g. an idle mpd) is not worth sticking to — treat it
      -- as "no current player" so a paused Spotify can take over instead.
      if current and current.st ~= "Playing" and current.st ~= "Paused" then
        current = nil
      end

      local pick
      if current and current.st == "Playing" then
        pick = current -- the player we already track is the one making sound
      elseif playing then
        pick = playing -- something else started playing — follow it
      elseif current then
        pick = current -- nothing is playing: keep the player we last controlled
      else
        pick = paused or firstAny -- cold start, or our player disappeared
      end
      local chTitle, chArtist = "", ""
      if pick then
        activePlayer = pick.name
        status = pick.st or ""
        chTitle, chArtist = pick.ti or "", pick.ar or ""
      else
        activePlayer = ""
        status = ""
      end
      hasPlayer = activePlayer ~= "" and (status == "Playing" or status == "Paused")

      local ti = noctalia.string.trim(chTitle or "")
      local ar = noctalia.string.trim(chArtist or "")
      if ti == "" then
        tipText = ""
      elseif ar == "" then
        tipText = ti
      else
        tipText = ti .. " — " .. ar
      end

      render()
    end
  )
end

-- Run a playerctl transport command against the chosen player.
local function transport(cmd)
  if activePlayer ~= "" then
    noctalia.runAsync("playerctl -p '" .. activePlayer .. "' " .. cmd)
  else
    noctalia.runAsync("playerctl " .. cmd)
  end
end

-- ── Entry-point callbacks ────────────────────────────────────────────────────
function update()
  noctalia.setUpdateInterval(700)
  isVertical = barWidget.isVertical()
  refreshMeta()
end

function onAudioSpectrum(valuesCsv, stateCsv)
  if not AUDIO_REACTIVE then return end

  local st = parseCsvNumbers(stateCsv)
  audioActive = st[1] == 1

  local raw = parseCsvNumbers(valuesCsv)
  local n = #raw
  if n == 0 then
    audioActive = false
  else
    for i = 1, BAR_COUNT do
      local lo = math.floor((i - 1) * n / BAR_COUNT) + 1
      local hi = math.floor(i * n / BAR_COUNT)
      if hi < lo then hi = lo end
      local sum, count = 0, 0
      for j = lo, hi do
        sum = sum + (raw[j] or 0)
        count = count + 1
      end
      local avg = count > 0 and (sum / count) or 0
      -- Perceptual curve: gain then sqrt so quiet passages still show life
      -- without loud ones slamming to the ceiling.
      local target = clamp01(math.sqrt(clamp01(avg * SENSITIVITY)))
      -- Exponential smoothing so the bars ease toward the target instead of
      -- jumping every frame — the main "make it calmer" knob.
      vals[i] = SMOOTHING * (vals[i] or 0) + (1 - SMOOTHING) * target
    end
  end

  -- Throttle to ~30 fps: the spectrum can arrive faster than we need to redraw.
  frame = frame + 1
  if frame % 2 == 0 then
    render()
  end
end

function onPrev()
  transport("previous")
end

function onNext()
  transport("next")
end

function onPlayPause()
  transport("play-pause")
end

-- Widget-level click: fires on the capsule (the visualizer / empty space) but
-- NOT on the transport buttons, which consume their own clicks. So clicking the
-- cava opens the built-in Control Center media view, while the buttons keep
-- doing transport.
function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center " .. CC_CONTEXT)
end
