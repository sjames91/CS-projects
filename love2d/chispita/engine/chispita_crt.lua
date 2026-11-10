-- CRT effect for Chispita (optional file)
--
-- Makes pixel art look the way it did on a good CRT, without scanlines:
-- each art pixel becomes a soft spot of light that blends into its
-- neighbors instead of a hard square, bright pixels spread a little
-- wider than dark ones, and bright things glow. It also fixes pixels
-- coming out different sizes when the window isn't an exact multiple of
-- the art. Plus a few color controls and film grain.
--
-- The old-TV extras (scanlines, RGB mask, curve, vignette, color
-- fringes, flicker, rolling bar) are all off unless you turn them on.
--
-- Use: call Chispita_applyCrt() at the end of love.draw. Everything drawn
-- from Chispita_draw() up to that call gets the effect.
--
--   function love.draw()
--     Chispita_draw()
--     Chispita_applyCrt()
--   end
--
-- Presets: Chispita_crtPreset(name) sets all the settings at once.
--   "crisp"   barely softened, a little glow
--   "soft"    the default: pixels blend, gentle glow
--   "arcade"  punchier: strong glow, more contrast and color
--   "dreamy"  very soft, big warm glow, light grain
--   "tv"      soft, plus every old-TV extra turned on
-- Every preset except "tv" switches the old-TV extras off.
-- Call it after Chispita_init (which resets settings to chispita_config),
-- then change any single setting after it if you like.
--
-- Settings (in chispita_config, change them any time):
--   chispita_crt                 false = off, true = on
--   chispita_crt_pixel_size      units per art pixel. 1 = sprites drawn at
--                                their image size. 2 = art drawn twice as big.
--   chispita_crt_soften          0 to 1, how much pixels blend into each other
--   chispita_crt_beam            0 to 1, how much wider bright pixels spread
--                                than dark ones
--   chispita_crt_glow            0 to 1, glow around bright things
--   chispita_crt_glow_size       0.3 to 3, how far the glow spreads
--   chispita_crt_glow_threshold  0 to 1, how bright a color must be to glow
--   chispita_crt_brightness      1 = unchanged
--   chispita_crt_contrast        1 = unchanged
--   chispita_crt_saturation      1 = unchanged, 0 = black and white
--   chispita_crt_warmth          -1 (cooler, bluer) to 1 (warmer), 0 = unchanged
--   chispita_crt_grain           0 to 1, moving film grain
--
-- Old-TV extras, all 0 to 1, all 0 (off) by default:
--   chispita_crt_scanlines       dark gaps between rows of art pixels
--   chispita_crt_mask            the red, green and blue stripes of a TV
--   chispita_crt_curve           the screen bulges; corners curve into black.
--                                Mouse positions don't follow it.
--   chispita_crt_vignette        darker corners
--   chispita_crt_aberration      red and blue fringes either side of things
--   chispita_crt_flicker         brightness flickers a little each frame
--   chispita_crt_roll            a faint bright band rolls slowly down
--
-- While it's on, the game is drawn at the art's own resolution (about 200
-- pixels on the short side with pixel size 1) and the shader scales it up.
-- So everything is drawn on the art grid: text, circles and rotated
-- sprites are pixel art too. Mouse positions work as normal.
--
-- How it works: Chispita_draw starts drawing onto a small canvas when the
-- game used Chispita_applyCrt last frame. Chispita_applyCrt then draws that
-- canvas to the window through the shaders below. If the game stops
-- calling it, drawing goes back to normal on the next frame.

local lg = love.graphics

chispita_crt_capturing = false   -- drawing onto the small canvas this frame
chispita_crt_wanted = false      -- Chispita_applyCrt was called last frame
chispita_crt_state = false       -- canvases and shaders, made on first use

function chispita_crt_extras_off()
  chispita_crt_scanlines = 0
  chispita_crt_mask = 0
  chispita_crt_curve = 0
  chispita_crt_vignette = 0
  chispita_crt_aberration = 0
  chispita_crt_flicker = 0
  chispita_crt_roll = 0
end

function Chispita_crtPreset(name)
  chispita_crt_extras_off()
  if name == "crisp" then
    chispita_crt_soften = 0.25
    chispita_crt_beam = 0.3
    chispita_crt_glow = 0.15
    chispita_crt_glow_size = 0.8
    chispita_crt_glow_threshold = 0.7
    chispita_crt_brightness = 1
    chispita_crt_contrast = 1
    chispita_crt_saturation = 1
    chispita_crt_warmth = 0
    chispita_crt_grain = 0
  elseif name == "soft" then
    chispita_crt_soften = 0.5
    chispita_crt_beam = 0.5
    chispita_crt_glow = 0.3
    chispita_crt_glow_size = 1
    chispita_crt_glow_threshold = 0.6
    chispita_crt_brightness = 1
    chispita_crt_contrast = 1
    chispita_crt_saturation = 1
    chispita_crt_warmth = 0
    chispita_crt_grain = 0
  elseif name == "arcade" then
    chispita_crt_soften = 0.45
    chispita_crt_beam = 0.8
    chispita_crt_glow = 0.45
    chispita_crt_glow_size = 1.2
    chispita_crt_glow_threshold = 0.5
    chispita_crt_brightness = 1.05
    chispita_crt_contrast = 1.1
    chispita_crt_saturation = 1.2
    chispita_crt_warmth = 0
    chispita_crt_grain = 0
  elseif name == "dreamy" then
    chispita_crt_soften = 0.8
    chispita_crt_beam = 0.6
    chispita_crt_glow = 0.7
    chispita_crt_glow_size = 2
    chispita_crt_glow_threshold = 0.35
    chispita_crt_brightness = 1
    chispita_crt_contrast = 0.95
    chispita_crt_saturation = 0.9
    chispita_crt_warmth = 0.4
    chispita_crt_grain = 0.15
  elseif name == "tv" then
    chispita_crt_soften = 0.5
    chispita_crt_beam = 0.7
    chispita_crt_glow = 0.4
    chispita_crt_glow_size = 1
    chispita_crt_glow_threshold = 0.6
    chispita_crt_brightness = 1.1
    chispita_crt_contrast = 1
    chispita_crt_saturation = 1
    chispita_crt_warmth = 0
    chispita_crt_grain = 0
    chispita_crt_scanlines = 0.6
    chispita_crt_mask = 0.4
    chispita_crt_curve = 0.3
    chispita_crt_vignette = 0.35
    chispita_crt_aberration = 0.3
    chispita_crt_flicker = 0.2
    chispita_crt_roll = 0.3
  else
    chispita_warn("Chispita_crtPreset doesn't know " .. tostring(name) .. ". Use crisp, soft, arcade, dreamy or tv.")
    return
  end
  chispita_crt = true
end


-- Shaders ------------------------------------------------------------------
-- Colors are mixed in linear light, the way light really adds up, and
-- turned back for the screen at the end.

local head = [[
vec3 lin(vec3 c) { return c * c; }
vec3 unlin(vec3 c) { return sqrt(max(c, 0.0)); }
]]

-- Shrinks the frame and keeps only the colors bright enough to glow.
local bright_code = head .. [[
uniform float threshold;
uniform vec2 texel;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
  vec3 c = lin(Texel(tex, uv).rgb) * 0.2
         + lin(Texel(tex, uv + texel * vec2(-0.3, -0.3)).rgb) * 0.2
         + lin(Texel(tex, uv + texel * vec2( 0.3, -0.3)).rgb) * 0.2
         + lin(Texel(tex, uv + texel * vec2(-0.3,  0.3)).rgb) * 0.2
         + lin(Texel(tex, uv + texel * vec2( 0.3,  0.3)).rgb) * 0.2;
  float l = max(c.r, max(c.g, c.b));
  float t = threshold * threshold;
  float k = clamp((l - t) / max(1.0 - t, 0.001), 0.0, 1.0);
  return vec4(unlin(c * k), 1.0);
}
]]

-- Gaussian blur in one direction.
local blur_code = head .. [[
uniform vec2 dir;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
  vec3 c = lin(Texel(tex, uv).rgb) * 0.2270;
  c += lin(Texel(tex, uv + dir * 1.3846).rgb) * 0.3162;
  c += lin(Texel(tex, uv - dir * 1.3846).rgb) * 0.3162;
  c += lin(Texel(tex, uv + dir * 3.2308).rgb) * 0.0703;
  c += lin(Texel(tex, uv - dir * 3.2308).rgb) * 0.0703;
  return vec4(unlin(c), 1.0);
}
]]

local final_code = head .. [[
uniform Image glowTex;
uniform vec2 size;
uniform vec2 spot;
uniform float beam;
uniform float glow;
uniform float brightness;
uniform float contrast;
uniform float saturation;
uniform float warmth;
uniform float grain;
uniform float seed;
uniform float time;
uniform float aspect;
uniform float scanlines;
uniform float mask;
uniform float curve;
uniform float vignette;
uniform float aberration;
uniform float flicker;
uniform float roll;

// Every art pixel is a soft spot of light. Nearby spots overlap and
// blend; bright ones spread wider than dark ones.
vec3 spots(Image tex, vec2 q) {
  vec2 pos = q * size - 0.5;
  vec2 base = floor(pos);
  vec2 f = pos - base;
  vec3 sum = vec3(0.0);
  float total = 0.0;
  for (int j = -1; j <= 2; j++) {
    for (int i = -1; i <= 2; i++) {
      vec2 cell = vec2(float(i), float(j));
      vec3 g = Texel(tex, (base + cell + 0.5) / size).rgb;
      float l = dot(g, vec3(0.299, 0.587, 0.114));
      vec2 d = (cell - f) / (spot * (1.0 + beam * (l - 0.5) * 0.8));
      float w = exp(-0.5 * dot(d, d));
      sum += lin(g) * w;
      total += w;
    }
  }
  return sum / max(total, 1e-30);
}

float random(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
  vec2 q = uv;

  // Extra: curve. The screen bulges; the corners curve away into black.
  if (curve > 0.0) {
    vec2 p = uv * 2.0 - 1.0;
    p.x *= aspect;
    float k = curve * 0.12;
    p *= 1.0 + k * dot(p, p);
    p.x /= (1.0 + k * aspect * aspect) * aspect;
    p.y /= 1.0 + k;
    q = p * 0.5 + 0.5;
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) {
      return vec4(0.0, 0.0, 0.0, 1.0);
    }
  }

  // Extra: aberration. Red and blue land a little to either side of
  // green, like a TV whose colors are slightly out of line.
  vec3 c;
  if (aberration > 0.0) {
    vec2 shift = vec2(aberration * 0.7 / size.x, 0.0);
    c = vec3(spots(tex, q + shift).r, spots(tex, q).g, spots(tex, q - shift).b);
  } else {
    c = spots(tex, q);
  }

  // Glow: light spilling around bright things.
  vec3 b = lin(Texel(glowTex, q).rgb) * glow * 2.5;
  c = c + b * (1.0 - c);

  // Extra: scanlines. Dark gaps between rows of art pixels. Bright
  // rows fill more of the gap, like a real beam.
  if (scanlines > 0.0) {
    float y = q.y * size.y - 0.5;
    float row = 0.5 + 0.5 * cos(6.2831853 * y);
    float l = max(c.r, max(c.g, c.b));
    float line = pow(row, mix(1.6, 0.4, sqrt(l)));
    c *= mix(1.0, line, scanlines) * (1.0 + scanlines * 0.35);
  }

  // Extra: mask. The red, green and blue stripes of a TV screen.
  if (mask > 0.0) {
    float m = mod(screen_coords.x, 3.0);
    vec3 stripe = m < 1.0 ? vec3(1.0, 0.0, 0.0) : (m < 2.0 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
    c *= mix(vec3(1.0), stripe * 0.75 + 0.25, mask * 0.5) * (1.0 + mask * 0.35);
  }

  // Extra: flicker and a slow rolling bar (LÖVE counts y downward, so the
  // bar moves down the screen).
  if (flicker > 0.0) c *= 1.0 - flicker * 0.08 * random(vec2(seed, 1.0));
  if (roll > 0.0) {
    float d = abs(fract(q.y - time * 0.07) - 0.5);
    c *= 1.0 + roll * 0.12 * smoothstep(0.12, 0.0, d);
  }

  // Extra: vignette. Darker corners.
  if (vignette > 0.0) {
    vec2 e = q * (1.0 - q);
    c *= mix(1.0, pow(clamp(e.x * e.y * 16.0, 0.0, 1.0), 0.3), vignette);
  }
  if (curve > 0.0) {
    vec2 d = min(q, 1.0 - q) * vec2(aspect, 1.0);
    c *= clamp(min(d.x, d.y) / (0.004 + 0.006 * curve), 0.0, 1.0);
  }

  // Color controls.
  c *= brightness;
  c *= vec3(1.0 + warmth * 0.08, 1.0 + warmth * 0.01, 1.0 - warmth * 0.10);
  c = unlin(c);
  c = (c - 0.5) * contrast + 0.5;
  float y = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(vec3(y), c, saturation);
  if (grain > 0.0) c += (random(screen_coords + seed) - 0.5) * grain * 0.08;
  return vec4(clamp(c, 0.0, 1.0), 1.0);
}
]]


-- Drawing ------------------------------------------------------------------

local function clamp(v, low, high)
  if type(v) ~= "number" then return low end
  return math.max(low, math.min(high, v))
end

-- Shaders throw away uniforms they don't use, and sending to one that's
-- gone is an error in LÖVE, so check first.
local function send(shader, name, ...)
  if shader:hasUniform(name) then shader:send(name, ...) end
end

local function make_state()
  local st = {}
  st.bright = lg.newShader(bright_code)
  st.blur = lg.newShader(blur_code)
  st.final = lg.newShader(final_code)
  st.seed = 0
  return st
end

local function canvas(st, name, w, h, filter)
  local c = st[name]
  if not c or c:getWidth() ~= w or c:getHeight() ~= h then
    c = lg.newCanvas(w, h)
    c:setFilter(filter, filter)
    st[name] = c
  end
  return c
end

-- LÖVE stops with an error if a frame ends while drawing onto a canvas.
-- This wraps love.draw so that if the game stops calling Chispita_applyCrt,
-- the frame still ends on the window.
function chispita_crt_hook_draw()
  if chispita_crt_hooked == love.draw then return end
  local game_draw = love.draw
  love.draw = function()
    if game_draw then game_draw() end
    if chispita_crt_capturing then
      lg.setCanvas()
      chispita_crt_capturing = false
      screen.update()
    end
  end
  chispita_crt_hooked = love.draw
end

-- Called by Chispita_draw: when the game used Chispita_applyCrt last frame,
-- this frame is drawn onto a small canvas, one pixel per art pixel.
function chispita_crt_begin()
  if chispita_crt_capturing then
    -- Chispita_applyCrt wasn't called last frame: stop capturing.
    lg.setCanvas()
    chispita_crt_capturing = false
  end
  if not (chispita_crt and chispita_crt_wanted) then return end
  chispita_crt_wanted = false
  chispita_crt_hook_draw()
  if not chispita_crt_state then chispita_crt_state = make_state() end
  local st = chispita_crt_state

  local w, h = lg.getDimensions()
  local pixel = clamp(chispita_crt_pixel_size, 0.25, 8)
  -- The shorter side of the window is 200 units.
  local side = math.max(16, math.floor(200 / pixel + 0.5))
  local fw, fh
  if w < h then
    fw = side
    fh = math.floor(h * side / w + 0.5)
  else
    fh = side
    fw = math.floor(w * side / h + 0.5)
  end
  local frame = canvas(st, "frame", fw, fh, "nearest")
  lg.setCanvas(frame)
  chispita_crt_capturing = true
  screen.update()
end

function Chispita_applyCrt()
  chispita_crt_wanted = chispita_crt and true or false
  if not chispita_crt_capturing then return end
  chispita_crt_capturing = false
  lg.setCanvas()
  screen.update()

  local st = chispita_crt_state
  local frame = st.frame
  local fw, fh = frame:getWidth(), frame:getHeight()
  local W, H = lg.getDimensions()
  local set = {
    pixel = clamp(chispita_crt_pixel_size, 0.25, 8),
    soften = clamp(chispita_crt_soften, 0, 1),
    beam = clamp(chispita_crt_beam, 0, 1),
    glow = clamp(chispita_crt_glow, 0, 1),
    size = clamp(chispita_crt_glow_size, 0.3, 3),
    threshold = clamp(chispita_crt_glow_threshold, 0, 1),
  }

  lg.push("all")
  lg.origin()
  lg.setColor(1, 1, 1, 1)
  lg.setBlendMode("replace")

  -- The glow is worked out on a smaller copy: the bigger the glow, the
  -- smaller the copy, so the blur stays smooth.
  local gw = math.max(8, math.floor(fw * set.pixel / (3 * set.size) + 0.5))
  local gh = math.max(8, math.floor(fh * set.pixel / (3 * set.size) + 0.5))
  local glow_a = canvas(st, "glow_a", gw, gh, "linear")
  local glow_b = canvas(st, "glow_b", gw, gh, "linear")
  if set.glow > 0 then
    -- Smooth sampling here, so small bright things are not skipped.
    frame:setFilter("linear", "linear")
    lg.setCanvas(glow_a)
    lg.setShader(st.bright)
    send(st.bright, "threshold", set.threshold)
    send(st.bright, "texel", { 1 / gw, 1 / gh })
    lg.draw(frame, 0, 0, 0, gw / fw, gh / fh)
    frame:setFilter("nearest", "nearest")

    -- Blur across, then down, twice.
    lg.setShader(st.blur)
    for _, pass in ipairs({ { 1, 0, glow_a, glow_b }, { 0, 1, glow_b, glow_a }, { 1, 0, glow_a, glow_b }, { 0, 1, glow_b, glow_a } }) do
      lg.setCanvas(pass[4])
      send(st.blur, "dir", { pass[1] / gw, pass[2] / gh })
      lg.draw(pass[3])
    end
  end

  lg.setCanvas()
  local f = st.final
  lg.setShader(f)
  send(f, "glowTex", glow_a)
  send(f, "size", { fw, fh })
  -- Spot size in art pixels: tight at soften 0, very soft at 1.
  local s = 0.12 + set.soften * 0.5
  send(f, "spot", { s, s * 0.75 })
  send(f, "beam", set.beam)
  send(f, "glow", set.glow)
  send(f, "brightness", clamp(chispita_crt_brightness, 0, 3))
  send(f, "contrast", clamp(chispita_crt_contrast, 0, 3))
  send(f, "saturation", clamp(chispita_crt_saturation, 0, 3))
  send(f, "warmth", clamp(chispita_crt_warmth, -1, 1))
  send(f, "grain", clamp(chispita_crt_grain, 0, 1))
  st.seed = (st.seed + 17.31) % 1000
  send(f, "seed", st.seed)
  send(f, "time", love.timer.getTime() % 1000)
  send(f, "aspect", W / H)
  send(f, "scanlines", clamp(chispita_crt_scanlines, 0, 1))
  send(f, "mask", clamp(chispita_crt_mask, 0, 1))
  send(f, "curve", clamp(chispita_crt_curve, 0, 1))
  send(f, "vignette", clamp(chispita_crt_vignette, 0, 1))
  send(f, "aberration", clamp(chispita_crt_aberration, 0, 1))
  send(f, "flicker", clamp(chispita_crt_flicker, 0, 1))
  send(f, "roll", clamp(chispita_crt_roll, 0, 1))
  lg.draw(frame, 0, 0, 0, W / fw, H / fh)
  lg.pop()
end
