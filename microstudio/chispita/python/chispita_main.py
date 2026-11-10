import math

chispita_version = "0.21"

# microStudio may run the engine files in any order, so each file that
# needs chispita_obj when it loads makes sure it exists.
if "chispita_obj" not in globals():
  class chispita_obj:
    """An object like microScript's: o.x and o["x"] are the same field, a
    field that was never set is None, and "for key in o" goes through the
    field names."""
    def __init__(self):
      object.__setattr__(self, "_fields", {})
    def __getattr__(self, name):
      if name.startswith("__"): raise AttributeError(name)
      return self._fields.get(name)
    def __setattr__(self, name, value): self._fields[name] = value
    def __getitem__(self, key): return self._fields.get(key)
    def __setitem__(self, key, value): self._fields[key] = value
    def __delitem__(self, key): self._fields.pop(key, None)
    def __contains__(self, key): return key in self._fields
    def __iter__(self): return iter(list(self._fields))
    def __len__(self): return len(self._fields)
    def __bool__(self): return True

# Helpers for things microScript has built in.
def chispita_sind(a): return math.sin(a * math.pi / 180)
def chispita_cosd(a): return math.cos(a * math.pi / 180)

def chispita_str(value):
  """Text for a value, as microScript writes it: 3 not 3.0, and 1/0 for
  True/False."""
  if value is True: return "1"
  if value is False or value is None: return "0"
  if isinstance(value, float) and value == int(value): return str(int(value))
  return str(value)

def chispita_remove_from(items, o):
  """Takes o out of a list, wherever it is (microScript's removeElement)."""
  for i in range(len(items) - 1, -1, -1):
    if items[i] is o: del items[i]

def chispita_index_of(items, o):
  for i in range(len(items)):
    if items[i] is o: return i
  return -1

def chispita_lookup(table, name):
  """sprites[name] or maps[name], or None when there isn't one."""
  if not isinstance(name, str): return None
  try:
    value = table[name]
  except Exception:
    return None
  if value is None or value == 0: return None
  try:
    from javascript import UNDEFINED
    if value is UNDEFINED: return None
  except Exception:
    pass
  return value

chispita_warned = chispita_obj()

def chispita_warn(message=None):
  if chispita_warned[message]: return
  chispita_warned[message] = 1
  print("Chispita: " + chispita_str(message))

def Chispita_init():
  global chispita_any_hurt_ignored, chispita_any_ignored, chispita_drawables, chispita_dt, chispita_hurt_ignored, chispita_ignored, chispita_maps, chispita_particle_layer, chispita_particles, chispita_paused, chispita_remove_queue, chispita_sprites, chispita_time, chispita_timers
  chispita_config()

  # Sprites, text, maps and particles
  chispita_sprites = []
  chispita_maps = []
  chispita_drawables = []
  chispita_particles = []
  chispita_particle_layer = 0 # made again by the next burst
  chispita_remove_queue = []

  # Collision group rules
  chispita_ignored = chispita_obj()
  chispita_hurt_ignored = chispita_obj()
  chispita_any_ignored = 0
  chispita_any_hurt_ignored = 0

  # Timers
  chispita_timers = []
  chispita_dt = 1 / 60
  chispita_time = 0

  # Camera
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

  if "chispita_debug_reset" in globals(): chispita_debug_reset()

def chispita_needed_substeps(dt=None):
  fastest = 0
  thinnest = 0
  for s in chispita_sprites:
    if not (s.active and s.physics and s.solid): continue
    half = 0
    if s.hit_box_shape == "circle":
      half = s.hit_radius
    else:
      half = min(s.hit_width, s.hit_height) / 2
    if half > 0 and (thinnest == 0 or half < thinnest): thinnest = half
    if not s.fixed:
      move = max(abs(s.vx), abs(s.vy)) * dt
      if move > fastest: fastest = move
  for m in chispita_maps:
    if not (m.map and m.physics and m.active): continue
    l = chispita_map_layout(m)
    half = min(l.cw, l.ch) / 2
    if half > 0 and (thinnest == 0 or half < thinnest): thinnest = half
  if thinnest <= 0: return 1
  return math.ceil(fastest / thinnest)

def Chispita_update(dt=None):
  global chispita_dt, chispita_step_passes, chispita_time
  if not dt: dt = 1 / 60
  if chispita_debug_mode:
    chispita_debug_update()
    if not chispita_debug_should_step():
      chispita_dt = 0
      return
  if chispita_paused:
    chispita_dt = 0
    chispita_update_timers(dt, 1)
    chispita_purge_removed()
    return
  dt *= chispita_time_scale
  chispita_dt = dt
  chispita_time += dt
  chispita_begin_frame()
  chispita_check_sprite_fields()

  steps = max(chispita_substeps, chispita_needed_substeps(dt))
  steps = max(1, min(steps, max(chispita_substeps, chispita_max_substeps)))
  chispita_step_passes = max(1, math.ceil(chispita_collision_passes / steps))
  step = dt / steps
  for i in range(1, steps + 1):
    chispita_move_sprites(step)
    chispita_check_collisions()
    chispita_check_map_collisions()

  chispita_apply_friction(dt)
  chispita_fire_contact_events()
  chispita_check_hurt_boxes()
  chispita_update_timers(dt)
  chispita_update_particles(dt)
  chispita_update_animations(dt)
  chispita_update_lifetimes(dt)
  chispita_camera_update(dt)
  chispita_purge_removed()

def Chispita_draw():
  chispita_draw_all()

chispita_paused = 0

def Chispita_pause():
  global chispita_paused
  chispita_paused = 1

def Chispita_resume():
  global chispita_paused
  chispita_paused = 0

def Chispita_isPaused():
  return chispita_paused

