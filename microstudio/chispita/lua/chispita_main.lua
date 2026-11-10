chispita_version = "0.1"

-- microStudio's own things (screen, mouse, sprites, maps, random, system)
-- are JavaScript objects. Their functions are called with ":", like
-- screen:fillRect(...), and their on/off values are 1 and 0. In Lua 0
-- counts as true, so the engine checks them with == 1.

local abs, min, max, ceil = math.abs, math.min, math.max, math.ceil

chispita_warned = {}

function chispita_warn(message)
  if chispita_warned[message] then return end
  chispita_warned[message] = true
  print("Chispita: " .. message)
end

function Chispita_init()
  chispita_config()

  -- Sprites, text, maps and particles
  chispita_sprites = {}
  chispita_maps = {}
  chispita_drawables = {}
  chispita_particles = {}
  chispita_particle_layer = false  -- made again by the next burst
  chispita_remove_queue = {}

  -- Collision group rules
  chispita_ignored = {}
  chispita_hurt_ignored = {}
  chispita_any_ignored = false
  chispita_any_hurt_ignored = false

  -- Timers
  chispita_timers = {}
  chispita_dt = 1 / 60
  chispita_time = 0

  -- Camera
  Camera.x = 0
  Camera.y = 0
  Camera.target = false
  Camera.smooth = 1
  Camera.zoom = 1
  Camera.bounds = false
  Camera.deadzone_x = 0
  Camera.deadzone_y = 0
  Camera.look_ahead_x = 0
  Camera.look_ahead_y = 0
  Camera.shake_amount = 0
  Camera.shake_time = 0
  Camera.shake_total = 0
  Camera.shake_fade = true
  chispita_paused = false
  Camera.shake_x = 0
  Camera.shake_y = 0

  if chispita_debug_reset then chispita_debug_reset() end
end

function chispita_needed_substeps(dt)
  local fastest = 0
  local thinnest = 0
  for _, s in ipairs(chispita_sprites) do
    if s.active and s.physics and s.solid then
      local half = 0
      if s.hit_box_shape == "circle" then
        half = s.hit_radius
      else
        half = min(s.hit_width, s.hit_height) / 2
      end
      if half > 0 and (thinnest == 0 or half < thinnest) then thinnest = half end
      if not s.fixed then
        local move = max(abs(s.vx), abs(s.vy)) * dt
        if move > fastest then fastest = move end
      end
    end
  end
  for _, m in ipairs(chispita_maps) do
    if m.map and m.physics and m.active then
      local l = chispita_map_layout(m)
      local half = min(l.cw, l.ch) / 2
      if half > 0 and (thinnest == 0 or half < thinnest) then thinnest = half end
    end
  end
  if thinnest <= 0 then return 1 end
  return ceil(fastest / thinnest)
end

function Chispita_update(dt)
  if not dt then dt = 1 / 60 end
  if chispita_debug_mode then
    chispita_debug_update()
    if not chispita_debug_should_step() then
      chispita_dt = 0
      return
    end
  end
  if chispita_paused then
    chispita_dt = 0
    chispita_update_timers(dt, true)
    chispita_purge_removed()
    return
  end
  dt = dt * chispita_time_scale
  chispita_dt = dt
  chispita_time = chispita_time + dt
  chispita_begin_frame()

  local steps = max(chispita_substeps, chispita_needed_substeps(dt))
  steps = max(1, min(steps, max(chispita_substeps, chispita_max_substeps)))
  chispita_step_passes = max(1, ceil(chispita_collision_passes / steps))
  local step = dt / steps
  for i = 1, steps do
    chispita_move_sprites(step)
    chispita_check_collisions()
    chispita_check_map_collisions()
  end

  chispita_apply_friction(dt)
  chispita_fire_contact_events()
  chispita_check_hurt_boxes()
  chispita_update_timers(dt)
  chispita_update_particles(dt)
  chispita_update_animations(dt)
  chispita_update_lifetimes(dt)
  chispita_camera_update(dt)
  chispita_purge_removed()
end

function Chispita_draw()
  chispita_draw_all()
end

chispita_paused = false

function Chispita_pause()
  chispita_paused = true
end

function Chispita_resume()
  chispita_paused = false
end

function Chispita_isPaused()
  return chispita_paused
end
