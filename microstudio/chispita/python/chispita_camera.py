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

# Create camera object
Camera = chispita_obj()
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
Camera.shake_x = 0
Camera.shake_y = 0

def chispita_camera_aim(position=None, target=None, zone=None):
  if zone <= 0: return target
  if target > position + zone: return target - zone
  if target < position - zone: return target + zone
  return position

# Update camera
def chispita_camera_update(dt=None):
  if Camera.target:
    tx = Camera.target.x + Camera.target.vx * Camera.look_ahead_x
    ty = Camera.target.y + Camera.target.vy * Camera.look_ahead_y
    tx = chispita_camera_aim(Camera.x, tx, Camera.deadzone_x)
    ty = chispita_camera_aim(Camera.y, ty, Camera.deadzone_y)
    ease = Camera.smooth
    if ease < 1 and dt != 1 / 60: ease = 1 - math.pow(1 - ease, dt * 60)
    Camera.x += (tx - Camera.x) * ease
    Camera.y += (ty - Camera.y) * ease

  # Clamp camera bounds
  if Camera.bounds:
    chispita_camera_clamp()

  # Camera shake
  Camera.shake_x = 0
  Camera.shake_y = 0
  if Camera.shake_time > 0:
    Camera.shake_time -= dt
    amount = Camera.shake_amount
    if Camera.shake_fade and Camera.shake_total > 0:
      amount *= max(0, Camera.shake_time / Camera.shake_total)
    angle = random.next() * 360
    Camera.shake_x = chispita_cosd(angle) * amount
    Camera.shake_y = chispita_sind(angle) * amount

# Camera clamping math
def chispita_camera_clamp():
  b = Camera.bounds
  half_w = screen.width / 2 / Camera.zoom
  half_h = screen.height / 2 / Camera.zoom

  if b.right - b.left < half_w * 2:
    Camera.x = (b.left + b.right) / 2
  else:
    Camera.x = max(b.left + half_w, min(Camera.x, b.right - half_w))

  if b.top - b.bottom < half_h * 2:
    Camera.y = (b.bottom + b.top) / 2
  else:
    Camera.y = max(b.bottom + half_h, min(Camera.y, b.top - half_h))

def Chispita_setTarget(sprite=None):
  Camera.target = sprite

def Chispita_cameraShake(amount=None, seconds=None):
  Camera.shake_amount = amount
  Camera.shake_time = seconds
  Camera.shake_total = seconds

def Chispita_setCameraBounds(left=None, bottom=None, right=None, top=None):
  if left >= right or bottom >= top:
    chispita_warn("Chispita_setCameraBounds needs left < right and bottom < top.")
    return
  b = chispita_obj()
  b.left = left
  b.bottom = bottom
  b.right = right
  b.top = top
  Camera.bounds = b

def Chispita_limitCameraToMap(m=None):
  if not m.map:
    chispita_warn("Chispita_limitCameraToMap needs a map from Chispita_addMap.")
    return
  l = chispita_map_layout(m)
  if not l: return
  huge = 1000000000
  left = l.left
  right = l.left + l.width
  bottom = l.bottom
  top = l.bottom + l.height
  if chispita_tiles_across(m):
    left = -huge
    right = huge
  if chispita_tiles_down(m):
    bottom = -huge
    top = huge
  Chispita_setCameraBounds(left, bottom, right, top)

# Camera view
def chispita_view_x():
  return Camera.x + Camera.shake_x

def chispita_view_y():
  return Camera.y + Camera.shake_y

def Chispita_screenToWorld(x=None, y=None):
  p = chispita_obj()
  p.x = x / Camera.zoom + chispita_view_x()
  p.y = y / Camera.zoom + chispita_view_y()
  return p

def Chispita_worldToScreen(x=None, y=None):
  p = chispita_obj()
  p.x = (x - chispita_view_x()) * Camera.zoom
  p.y = (y - chispita_view_y()) * Camera.zoom
  return p

chispita_drawables = []
chispita_fps = 60
chispita_last_draw_time = 0

def chispita_add_drawable(o=None):
  chispita_drawables.append(o)
  i = len(chispita_drawables) - 1
  while i > 0:
    before = chispita_drawables[i - 1]
    if before.layer <= o.layer: break
    chispita_drawables[i] = before
    i -= 1
  chispita_drawables[i] = o

def Chispita_setLayer(o=None, layer=None):
  index = chispita_index_of(chispita_drawables, o)
  if index < 0:
    chispita_warn("Chispita_setLayer: that object isn't being drawn (it may have been removed).")
    return
  del chispita_drawables[index]
  o.layer = layer
  chispita_add_drawable(o)

def chispita_screen_x(o=None, x=None):
  if o.ui: return x
  return (x - chispita_view_x() * o.parallax) * Camera.zoom

def chispita_screen_y(o=None, y=None):
  if o.ui: return y
  return (y - chispita_view_y() * o.parallax) * Camera.zoom

def chispita_screen_size(o=None, size=None):
  if o.ui: return size
  return size * Camera.zoom

def chispita_world_x(x=None):
  return (x - chispita_view_x()) * Camera.zoom

def chispita_world_y(y=None):
  return (y - chispita_view_y()) * Camera.zoom

def chispita_measure_fps():
  global chispita_fps, chispita_last_draw_time
  now = system.time()
  dt = now - chispita_last_draw_time
  chispita_last_draw_time = now
  if dt > 0 and dt < 1000:
    chispita_fps = chispita_fps * 0.95 + (1000 / dt) * 0.05

def chispita_depth_key(o=None):
  if o.hit_box_shape == "circle": return o.y - o.radius
  return o.y - o.height / 2

def chispita_sort_depth():
  list = chispita_drawables
  for i in range(1, len(list)):
    o = list[i]
    if not o.depth_sort: continue
    key = chispita_depth_key(o)
    j = i - 1
    while j >= 0:
      before = list[j]
      if not before.depth_sort or before.layer != o.layer: break
      if chispita_depth_key(before) >= key: break
      list[j + 1] = before
      j -= 1
    list[j + 1] = o

def chispita_draw_all():
  chispita_measure_fps()
  chispita_sort_depth()
  if chispita_background: screen.clear(chispita_background)
  if chispita_debug_mode and Debug.grid: chispita_debug_draw_grid()

  for o in chispita_drawables:
    if o.visible: o.draw()

  if chispita_debug_mode: chispita_draw_debug()

