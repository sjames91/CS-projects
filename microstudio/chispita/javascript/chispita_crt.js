// CRT effect for Chispita (optional file)
//
// Makes pixel art look the way it did on a good CRT, without scanlines:
// each art pixel becomes a soft spot of light that blends into its
// neighbors instead of a hard square, bright pixels spread a little
// wider than dark ones, and bright things glow. It also fixes pixels
// coming out different sizes when the window isn't an exact multiple of
// the art. Plus a few color controls and film grain.
//
// The old-TV extras (scanlines, RGB mask, curve, vignette, color
// fringes, flicker, rolling bar) are all off unless you turn them on.
//
// Use: call Chispita_applyCrt() at the end of your draw function.
// Everything drawn before the call gets the effect.
//
//   draw = function()
//     Chispita_draw()
//     Chispita_applyCrt()
//   end
//
// Presets: Chispita_crtPreset(name) sets all the settings at once.
//   "crisp"   barely softened, a little glow
//   "soft"    the default: pixels blend, gentle glow
//   "arcade"  punchier: strong glow, more contrast and color
//   "dreamy"  very soft, big warm glow, light grain
//   "tv"      soft, plus every old-TV extra turned on
// Every preset except "tv" switches the old-TV extras off.
// Call it after Chispita_init (which resets settings to chispita_config),
// then change any single setting after it if you like.
//
// Settings (in chispita_config, change them any time):
//   chispita_crt                 0 = off, 1 = on
//   chispita_crt_pixel_size      units per art pixel. 1 = sprites drawn at
//                                their image size. 2 = art drawn twice as big.
//   chispita_crt_soften          0 to 1, how much pixels blend into each other
//   chispita_crt_beam            0 to 1, how much wider bright pixels spread
//                                than dark ones
//   chispita_crt_glow            0 to 1, glow around bright things
//   chispita_crt_glow_size       0.3 to 3, how far the glow spreads
//   chispita_crt_glow_threshold  0 to 1, how bright a color must be to glow
//   chispita_crt_brightness      1 = unchanged
//   chispita_crt_contrast        1 = unchanged
//   chispita_crt_saturation      1 = unchanged, 0 = black and white
//   chispita_crt_warmth          -1 (cooler, bluer) to 1 (warmer), 0 = unchanged
//   chispita_crt_grain           0 to 1, moving film grain
//
// Old-TV extras, all 0 to 1, all 0 (off) by default:
//   chispita_crt_scanlines       dark gaps between rows of art pixels
//   chispita_crt_mask            the red, green and blue stripes of a TV
//   chispita_crt_curve           the screen bulges; corners curve into black.
//                                Mouse and touch positions don't follow it.
//   chispita_crt_vignette        darker corners
//   chispita_crt_aberration      red and blue fringes either side of things
//   chispita_crt_flicker         brightness flickers a little each frame
//   chispita_crt_roll            a faint bright band rolls slowly down
//
// While it's on, microStudio draws the game at the art's own resolution
// (about 200 pixels tall with pixel size 1), and the shader scales it up.
// So everything is drawn on the art grid: text, circles and rotated
// sprites are pixel art too. Mouse and touch positions work as normal.
//
// How it works: this is a WebGL shader. It draws on a second canvas laid
// over the microStudio screen, which clicks and touches pass through. If
// the game stops calling Chispita_applyCrt (or sets chispita_crt to 0),
// it goes back to normal drawing within a frame or two. Without WebGL the
// game draws as normal and a warning is printed once. It needs the
// default microStudio graphics (not Pixi, M2D, M3D or Babylon).

function chispita_crt_extras_off() {
  chispita_crt_scanlines = 0
  chispita_crt_mask = 0
  chispita_crt_curve = 0
  chispita_crt_vignette = 0
  chispita_crt_aberration = 0
  chispita_crt_flicker = 0
  chispita_crt_roll = 0
}

function Chispita_crtPreset(name) {
  chispita_crt_extras_off()
  if (name == "crisp") {
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
  } else if (name == "soft") {
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
  } else if (name == "arcade") {
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
  } else if (name == "dreamy") {
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
  } else if (name == "tv") {
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
  } else {
    chispita_warn("Chispita_crtPreset doesn't know " + name + ". Use crisp, soft, arcade, dreamy or tv.")
    return
  }
  chispita_crt = 1
}



window.chispitaCrtHide = function() {
  var st = window.chispitaCrtState;
  if (!st) return;
  if (st.overlay && st.shown) {
    st.overlay.style.display = "none";
    st.shown = false;
  }
  if (st.lowres) {
    // Back to drawing at full screen resolution.
    st.lowres = false;
    if (st.screen) st.screen.resize();
  }
};

window.chispitaCrt = function(g) {
  var p = window.player;
  if (!p || !p.runtime || !p.runtime.screen) return 0;
  var screen = p.runtime.screen;
  var src = screen.canvas;
  if (!src || !src.parentNode || typeof screen.resize != "function") return 0;

  var num = function(v, d) { return (typeof v == "number" && isFinite(v)) ? v : d; };
  var clamp = function(v, a, b) { return Math.max(a, Math.min(b, v)); };
  var set = {
    pixel: clamp(num(g.chispita_crt_pixel_size, 1), 0.25, 8),
    soften: clamp(num(g.chispita_crt_soften, 0.5), 0, 1),
    beam: clamp(num(g.chispita_crt_beam, 0.5), 0, 1),
    glow: clamp(num(g.chispita_crt_glow, 0.3), 0, 1),
    size: clamp(num(g.chispita_crt_glow_size, 1), 0.3, 3),
    threshold: clamp(num(g.chispita_crt_glow_threshold, 0.6), 0, 1),
    brightness: clamp(num(g.chispita_crt_brightness, 1), 0, 3),
    contrast: clamp(num(g.chispita_crt_contrast, 1), 0, 3),
    saturation: clamp(num(g.chispita_crt_saturation, 1), 0, 3),
    warmth: clamp(num(g.chispita_crt_warmth, 0), -1, 1),
    grain: clamp(num(g.chispita_crt_grain, 0), 0, 1),
    scanlines: clamp(num(g.chispita_crt_scanlines, 0), 0, 1),
    mask: clamp(num(g.chispita_crt_mask, 0), 0, 1),
    curve: clamp(num(g.chispita_crt_curve, 0), 0, 1),
    vignette: clamp(num(g.chispita_crt_vignette, 0), 0, 1),
    aberration: clamp(num(g.chispita_crt_aberration, 0), 0, 1),
    flicker: clamp(num(g.chispita_crt_flicker, 0), 0, 1),
    roll: clamp(num(g.chispita_crt_roll, 0), 0, 1)
  };

  var st = window.chispitaCrtState;
  if (!st) st = window.chispitaCrtState = {};
  if (!st.gl && !st.noGl) {
    try { st.gl = chispitaCrtMakeGl(st); } catch (e) { console.error(e); st.gl = null; }
    if (!st.gl) st.noGl = true;
  }
  // Without WebGL the game just draws as normal.
  if (!st.gl) return 2;
  if (st.gl.isContextLost()) {
    window.chispitaCrtHide();
    if (st.overlay && st.overlay.parentNode) st.overlay.parentNode.removeChild(st.overlay);
    st.gl = null; st.overlay = null;
    return 1;
  }

  // From now on microStudio draws the game on the art grid: one canvas
  // pixel per art pixel. The shader turns those into soft spots of light.
  if (st.screen != screen) {
    st.screen = screen;
    var original = screen.resize;
    screen.resize = function() {
      original.apply(this, arguments);
      if (st.lowres) chispitaCrtShrink(this, st.pixel);
    };
  }
  if (!st.lowres || st.pixel != set.pixel) {
    st.lowres = true;
    st.pixel = set.pixel;
    screen.resize();
    // This frame was drawn before the change, so it is gone: start next frame.
    return 1;
  }

  var o = st.overlay;
  if (o.parentNode != src.parentNode || o.previousSibling != src) {
    src.parentNode.insertBefore(o, src.nextSibling);
  }
  var r = src.getBoundingClientRect();
  var place = r.left + "," + r.top + "," + r.width + "," + r.height;
  if (place != st.place) {
    st.place = place;
    o.style.left = r.left + "px";
    o.style.top = r.top + "px";
    o.style.width = r.width + "px";
    o.style.height = r.height + "px";
  }
  var dpr = window.devicePixelRatio || 1;
  var W = Math.max(2, Math.round(r.width * dpr)), H = Math.max(2, Math.round(r.height * dpr));
  if (o.width != W || o.height != H) { o.width = W; o.height = H; }

  chispitaCrtDraw(st, src, set);
  if (!st.shown) { o.style.display = "block"; st.shown = true; }

  // If the game stops calling Chispita_applyCrt, go back to normal drawing
  // so an old frame is never left covering the game.
  st.last = performance.now();
  if (!st.watching) {
    st.watching = true;
    var watch = function() {
      if (st.lowres && performance.now() - st.last > 100) window.chispitaCrtHide();
      requestAnimationFrame(watch);
    };
    requestAnimationFrame(watch);
  }
  return 1;
};

window.chispitaCrtShrink = function(screen, pixel) {
  var c = screen.canvas;
  var w = c.width, h = c.height;
  if (w < 2 || h < 2) return;
  // microStudio fits 200 units across the shorter side of the screen.
  var side = Math.max(16, Math.round(200 / pixel));
  var nw, nh;
  if (w < h) { nw = side; nh = Math.round(h * side / w); }
  else { nh = side; nw = Math.round(w * side / h); }
  if (nw == w && nh == h) return;
  c.width = nw;
  c.height = nh;
  screen.initContext();
  if (screen.interface && screen.updateInterface) screen.updateInterface();
};

window.chispitaCrtMakeGl = function(st) {
  var o = document.createElement("canvas");
  o.style.position = "fixed";
  o.style.pointerEvents = "none";
  o.style.display = "none";
  o.style.margin = "0";
  var gl = o.getContext("webgl", { alpha: false, antialias: false, depth: false, premultipliedAlpha: false });
  if (!gl) return null;
  var hp = gl.getShaderPrecisionFormat(gl.FRAGMENT_SHADER, gl.HIGH_FLOAT);
  var precision = (hp && hp.precision > 0) ? "highp" : "mediump";
  st.overlay = o;

  var vs = `
    attribute vec2 pos;
    varying vec2 uv;
    void main() { uv = pos * 0.5 + 0.5; gl_Position = vec4(pos, 0.0, 1.0); }`;

  // Colors are mixed in linear light, the way light really adds up, and
  // turned back for the screen at the end.
  var head = `
    precision ` + precision + ` float;
    varying vec2 uv;
    uniform sampler2D tex;
    vec3 lin(vec3 c) { return c * c; }
    vec3 unlin(vec3 c) { return sqrt(max(c, 0.0)); }`;

  // Shrinks the frame and keeps only the colors bright enough to glow.
  var brightFs = head + `
    uniform float threshold;
    uniform vec2 texel;
    void main() {
      vec3 c = lin(texture2D(tex, uv).rgb) * 0.2
             + lin(texture2D(tex, uv + texel * vec2(-0.3, -0.3)).rgb) * 0.2
             + lin(texture2D(tex, uv + texel * vec2( 0.3, -0.3)).rgb) * 0.2
             + lin(texture2D(tex, uv + texel * vec2(-0.3,  0.3)).rgb) * 0.2
             + lin(texture2D(tex, uv + texel * vec2( 0.3,  0.3)).rgb) * 0.2;
      float l = max(c.r, max(c.g, c.b));
      float t = threshold * threshold;
      float k = clamp((l - t) / max(1.0 - t, 0.001), 0.0, 1.0);
      gl_FragColor = vec4(unlin(c * k), 1.0);
    }`;

  // Gaussian blur in one direction.
  var blurFs = head + `
    uniform vec2 dir;
    void main() {
      vec3 c = lin(texture2D(tex, uv).rgb) * 0.2270;
      c += lin(texture2D(tex, uv + dir * 1.3846).rgb) * 0.3162;
      c += lin(texture2D(tex, uv - dir * 1.3846).rgb) * 0.3162;
      c += lin(texture2D(tex, uv + dir * 3.2308).rgb) * 0.0703;
      c += lin(texture2D(tex, uv - dir * 3.2308).rgb) * 0.0703;
      gl_FragColor = vec4(unlin(c), 1.0);
    }`;

  var finalFs = head + `
    uniform sampler2D glowTex;
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
    vec3 spots(vec2 q) {
      vec2 pos = q * size - 0.5;
      vec2 base = floor(pos);
      vec2 f = pos - base;
      vec3 sum = vec3(0.0);
      float total = 0.0;
      for (int j = -1; j <= 2; j++) {
        for (int i = -1; i <= 2; i++) {
          vec2 cell = vec2(float(i), float(j));
          vec3 g = texture2D(tex, (base + cell + 0.5) / size).rgb;
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

    void main() {
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
          gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
          return;
        }
      }

      // Extra: aberration. Red and blue land a little to either side of
      // green, like a TV whose colors are slightly out of line.
      vec3 c;
      if (aberration > 0.0) {
        vec2 shift = vec2(aberration * 0.7 / size.x, 0.0);
        c = vec3(spots(q + shift).r, spots(q).g, spots(q - shift).b);
      } else {
        c = spots(q);
      }

      // Glow: light spilling around bright things.
      vec3 b = lin(texture2D(glowTex, q).rgb) * glow * 2.5;
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
        float m = mod(gl_FragCoord.x, 3.0);
        vec3 stripe = m < 1.0 ? vec3(1.0, 0.0, 0.0) : (m < 2.0 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
        c *= mix(vec3(1.0), stripe * 0.75 + 0.25, mask * 0.5) * (1.0 + mask * 0.35);
      }

      // Extra: flicker and a slow rolling bar (WebGL counts y upward, so
    // adding time moves the bar down the screen).
      if (flicker > 0.0) c *= 1.0 - flicker * 0.08 * random(vec2(seed, 1.0));
      if (roll > 0.0) {
        float d = abs(fract(q.y + time * 0.07) - 0.5);
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
      if (grain > 0.0) c += (random(gl_FragCoord.xy + seed) - 0.5) * grain * 0.08;
      gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
    }`;

  var shader = function(type, code) {
    var s = gl.createShader(type);
    gl.shaderSource(s, code);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  };
  var vsh = shader(gl.VERTEX_SHADER, vs);
  var program = function(fs, uniforms) {
    var pr = gl.createProgram();
    gl.attachShader(pr, vsh);
    gl.attachShader(pr, shader(gl.FRAGMENT_SHADER, fs));
    gl.bindAttribLocation(pr, 0, "pos");
    gl.linkProgram(pr);
    if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(pr));
    var u = { program: pr };
    uniforms.forEach(function(n) { u[n] = gl.getUniformLocation(pr, n); });
    return u;
  };
  st.bright = program(brightFs, ["tex", "threshold", "texel"]);
  st.blur = program(blurFs, ["tex", "dir"]);
  st.final = program(finalFs, ["tex", "glowTex", "size", "spot", "beam", "glow",
    "brightness", "contrast", "saturation", "warmth", "grain", "seed", "time", "aspect",
    "scanlines", "mask", "curve", "vignette", "aberration", "flicker", "roll"]);

  var buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

  var texture = function(filter) {
    var t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  };
  st.frame = texture(gl.NEAREST);
  st.glowA = { tex: texture(gl.LINEAR), fb: gl.createFramebuffer() };
  st.glowB = { tex: texture(gl.LINEAR), fb: gl.createFramebuffer() };
  st.glowW = 0; st.glowH = 0;
  st.seed = 0;
  return gl;
};

window.chispitaCrtDraw = function(st, src, set) {
  var gl = st.gl, o = st.overlay;
  var sw = src.width, sh = src.height;

  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, st.frame);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, src);

  // The glow is worked out on a smaller copy: the bigger the glow, the
  // smaller the copy, so the blur stays smooth.
  var gw = Math.max(8, Math.round(sw * set.pixel / (3 * set.size)));
  var gh = Math.max(8, Math.round(sh * set.pixel / (3 * set.size)));
  if (gw != st.glowW || gh != st.glowH) {
    st.glowW = gw; st.glowH = gh;
    [st.glowA, st.glowB].forEach(function(t) {
      gl.bindTexture(gl.TEXTURE_2D, t.tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gw, gh, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      gl.bindFramebuffer(gl.FRAMEBUFFER, t.fb);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t.tex, 0);
    });
  }

  if (set.glow > 0) {
    gl.viewport(0, 0, gw, gh);
    gl.useProgram(st.bright.program);
    gl.bindFramebuffer(gl.FRAMEBUFFER, st.glowA.fb);
    gl.bindTexture(gl.TEXTURE_2D, st.frame);
    // Smooth sampling here, so small bright things are not skipped.
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.uniform1i(st.bright.tex, 0);
    gl.uniform1f(st.bright.threshold, set.threshold);
    gl.uniform2f(st.bright.texel, 1 / gw, 1 / gh);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    // Blur across, then down, twice.
    gl.useProgram(st.blur.program);
    gl.uniform1i(st.blur.tex, 0);
    [[1, 0, st.glowA, st.glowB], [0, 1, st.glowB, st.glowA],
     [1, 0, st.glowA, st.glowB], [0, 1, st.glowB, st.glowA]].forEach(function(s) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, s[3].fb);
      gl.bindTexture(gl.TEXTURE_2D, s[2].tex);
      gl.uniform2f(st.blur.dir, s[0] / gw, s[1] / gh);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    });
  }

  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.viewport(0, 0, o.width, o.height);
  gl.useProgram(st.final.program);
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D, st.glowA.tex);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, st.frame);
  var f = st.final;
  gl.uniform1i(f.tex, 0);
  gl.uniform1i(f.glowTex, 1);
  gl.uniform2f(f.size, sw, sh);
  // Spot size in art pixels: tight at soften 0, very soft at 1.
  var s = 0.12 + set.soften * 0.5;
  gl.uniform2f(f.spot, s, s * 0.75);
  gl.uniform1f(f.beam, set.beam);
  gl.uniform1f(f.glow, set.glow);
  gl.uniform1f(f.brightness, set.brightness);
  gl.uniform1f(f.contrast, set.contrast);
  gl.uniform1f(f.saturation, set.saturation);
  gl.uniform1f(f.warmth, set.warmth);
  gl.uniform1f(f.grain, set.grain);
  st.seed = (st.seed + 17.31) % 1000;
  gl.uniform1f(f.seed, st.seed);
  gl.uniform1f(f.time, (performance.now() / 1000) % 1000);
  gl.uniform1f(f.aspect, o.width / o.height);
  gl.uniform1f(f.scanlines, set.scanlines);
  gl.uniform1f(f.mask, set.mask);
  gl.uniform1f(f.curve, set.curve);
  gl.uniform1f(f.vignette, set.vignette);
  gl.uniform1f(f.aberration, set.aberration);
  gl.uniform1f(f.flicker, set.flicker);
  gl.uniform1f(f.roll, set.roll);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
};

// The settings are global variables, which in microStudio JavaScript live
// on window, so the effect reads them from there.
function Chispita_applyCrt() {
  if (!chispita_crt) {
    chispitaCrtHide()
    return
  }
  var result = chispitaCrt(window)
  if (result == 2) {
    chispita_warn("the CRT effect needs WebGL, which this browser doesn't have. The game draws as normal.")
  } else if (!result) {
    chispita_warn("the CRT effect can't run here. It needs the default microStudio graphics, in a browser.")
  }
}
