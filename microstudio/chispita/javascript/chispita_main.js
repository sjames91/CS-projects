var chispita_version = "0.1"

// Math helpers microScript has built in.
function chispita_sind(a) { return Math.sin(a * Math.PI / 180) }
function chispita_cosd(a) { return Math.cos(a * Math.PI / 180) }

// Takes o out of a list, wherever it is (microScript's removeElement).
function chispita_remove_from(list, o) {
  for (var i = list.length - 1; i >= 0; i--) {
    if (list[i] === o) list.splice(i, 1)
  }
}

var chispita_warned = {}

function chispita_warn(message) {
  if (chispita_warned[message]) return
  chispita_warned[message] = 1
  print("Chispita: " + message)
}

function Chispita_init() {
  chispita_config()

  // Sprites, text, maps and particles
  chispita_sprites = []
  chispita_maps = []
  chispita_drawables = []
  chispita_particles = []
  chispita_particle_layer = 0      // made again by the next burst
  chispita_remove_queue = []

  // Collision group rules
  chispita_ignored = {}
  chispita_hurt_ignored = {}
  chispita_any_ignored = 0
  chispita_any_hurt_ignored = 0

  // Timers
  chispita_timers = []
  chispita_dt = 1 / 60
  chispita_time = 0

  // Camera
  Camera.x = 0
  Camera.y = 0
  Camera.target = 0
  Camera.smooth = 1
  Camera.zoom = 1
  Camera.bounds = 0
  Camera.deadzone_x = 0
  Camera.deadzone_y = 0
  Camera.look_ahead_x = 0
  Camera.look_ahead_y = 0
  Camera.shake_amount = 0
  Camera.shake_time = 0
  Camera.shake_total = 0
  Camera.shake_fade = 1
  chispita_paused = 0
  Camera.shake_x = 0
  Camera.shake_y = 0

  if (typeof chispita_debug_reset == "function") chispita_debug_reset()
}

function chispita_needed_substeps(dt) {
  var fastest = 0
  var thinnest = 0
  for (var s of chispita_sprites) {
    if (!(s.active && s.physics && s.solid)) continue
    var half = 0
    if (s.hit_box_shape == "circle") {
      half = s.hit_radius
    } else {
      half = Math.min(s.hit_width, s.hit_height) / 2
    }
    if (half > 0 && (thinnest == 0 || half < thinnest)) thinnest = half
    if (!s.fixed) {
      var move = Math.max(Math.abs(s.vx), Math.abs(s.vy)) * dt
      if (move > fastest) fastest = move
    }
  }
  for (var m of chispita_maps) {
    if (!(m.map && m.physics && m.active)) continue
    var l = chispita_map_layout(m)
    var half = Math.min(l.cw, l.ch) / 2
    if (half > 0 && (thinnest == 0 || half < thinnest)) thinnest = half
  }
  if (thinnest <= 0) return 1
  return Math.ceil(fastest / thinnest)
}

function Chispita_update(dt) {
  if (!dt) dt = 1 / 60
  if (chispita_debug_mode) {
    chispita_debug_update()
    if (!chispita_debug_should_step()) {
      chispita_dt = 0
      return
    }
  }
  if (chispita_paused) {
    chispita_dt = 0
    chispita_update_timers(dt, 1)
    chispita_purge_removed()
    return
  }
  dt *= chispita_time_scale
  chispita_dt = dt
  chispita_time += dt
  chispita_begin_frame()

  var steps = Math.max(chispita_substeps, chispita_needed_substeps(dt))
  steps = Math.max(1, Math.min(steps, Math.max(chispita_substeps, chispita_max_substeps)))
  chispita_step_passes = Math.max(1, Math.ceil(chispita_collision_passes / steps))
  var step = dt / steps
  for (var i = 1; i <= steps; i++) {
    chispita_move_sprites(step)
    chispita_check_collisions()
    chispita_check_map_collisions()
  }

  chispita_apply_friction(dt)
  chispita_fire_contact_events()
  chispita_check_hurt_boxes()
  chispita_update_timers(dt)
  chispita_update_particles(dt)
  chispita_update_animations(dt)
  chispita_update_lifetimes(dt)
  chispita_camera_update(dt)
  chispita_purge_removed()
}

function Chispita_draw() {
  chispita_draw_all()
}

var chispita_paused = 0

function Chispita_pause() {
  chispita_paused = 1
}

function Chispita_resume() {
  chispita_paused = 0
}

function Chispita_isPaused() {
  return chispita_paused
}
