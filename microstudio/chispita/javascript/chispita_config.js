// Settings. Chispita_init sets them back to these values.
// Same settings as the microScript version: 1 = on, 0 = off.

function chispita_config() {
  // World
  chispita_mode = "topdown"          // "topdown" or "platformer"
  chispita_gravity = 500             // platformer only, units per second squared
  chispita_friction = 0.85           // speed kept each frame (on the ground in platformer)
  chispita_air_friction = 0.95       // speed kept each frame in the air (platformer)
  chispita_rest_speed = 30           // slower than this, a landing stops instead of bouncing

  // Time
  chispita_substeps = 1              // least physics steps per frame, more are added for fast sprites
  chispita_max_substeps = 8
  chispita_time_scale = 1            // 1 = normal, 0.5 = slow motion, 0 = frozen

  // Collisions
  chispita_collision_passes = 3      // more = steadier stacks, but more work
  chispita_collision_slop = 0.1      // overlap allowed to stay (stops shivering)
  chispita_collision_push = 0.8      // how much of the rest gets pushed out each pass

  // Particles
  chispita_particle_gravity = 0      // units per second squared, pulls particles down

  // Drawing
  chispita_background = "rgb(0,0,0)"
  chispita_max_map_copies = 400      // most copies of one tiled map drawn per frame

  // CRT effect (used only by the optional chispita_crt file)
  chispita_crt = 1                   // 0 = Chispita_applyCrt does nothing
  chispita_crt_pixel_size = 1        // units per art pixel
  chispita_crt_soften = 0.5          // how much pixels blend into each other, 0 to 1
  chispita_crt_beam = 0.5            // how much wider bright pixels spread, 0 to 1
  chispita_crt_glow = 0.3            // glow around bright things, 0 to 1
  chispita_crt_glow_size = 1         // how far the glow spreads, 0.3 to 3
  chispita_crt_glow_threshold = 0.6  // how bright a color must be to glow, 0 to 1
  chispita_crt_brightness = 1        // 1 = unchanged
  chispita_crt_contrast = 1          // 1 = unchanged
  chispita_crt_saturation = 1        // 1 = unchanged, 0 = black and white
  chispita_crt_warmth = 0            // -1 cooler to 1 warmer
  chispita_crt_grain = 0             // film grain, 0 to 1
  chispita_crt_scanlines = 0         // old-TV extras, all 0 to 1, 0 = off:
  chispita_crt_mask = 0              //   scanlines, RGB stripes, screen bulge,
  chispita_crt_curve = 0             //   dark corners, color fringes,
  chispita_crt_vignette = 0          //   flicker, rolling bar
  chispita_crt_aberration = 0
  chispita_crt_flicker = 0
  chispita_crt_roll = 0

  // Debug
  chispita_debug_mode = 0
}

chispita_config()
