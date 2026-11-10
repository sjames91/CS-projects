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

import math

Debug = chispita_obj()
Debug.panel = 1
Debug.panel_open = 1
Debug.grid = 1
Debug.grid_size = 32
Debug.hit_boxes = 1
Debug.hurt_boxes = 1
Debug.velocity = 0
Debug.contacts = 0
Debug.labels = 0
Debug.map_cells = 0
Debug.camera = 0
Debug.mouse = 1
Debug.info = 1
Debug.drag = 1
Debug.slow_motion = 0
Debug.slow_factor = 4
Debug.paused = 0
chispita_debug_rows = []
chispita_step_requested = 0
chispita_slow_counter = 0
chispita_dragging = 0
chispita_drag_dx = 0
chispita_drag_dy = 0
chispita_throw_x = 0
chispita_throw_y = 0
chispita_watches = chispita_obj()
chispita_watch_order = []

def chispita_debug_reset():
  global chispita_dragging, chispita_slow_counter, chispita_step_requested, chispita_throw_x, chispita_throw_y, chispita_watch_order, chispita_watches
  chispita_dragging = 0
  chispita_step_requested = 0
  chispita_slow_counter = 0
  chispita_throw_x = 0
  chispita_throw_y = 0
  chispita_watches = chispita_obj()
  chispita_watch_order = []

chispita_debug_text_color = "rgb(255,255,255)"
chispita_debug_size = 5

# Watch values
def Chispita_watch(label=None, value=None):
  if label not in chispita_watch_order: chispita_watch_order.append(label)
  chispita_watches[label] = value

def Chispita_toggleDebug(name=None):
  global chispita_debug_mode
  if not name:
    chispita_debug_mode = not chispita_debug_mode
  else:
    Debug[name] = not Debug[name]

def Chispita_mouseOnDebug():
  if not chispita_debug_mode: return 0
  if chispita_dragging: return 1
  return chispita_debug_row_at(mouse.x, mouse.y) != "none"

# Debug panel
def chispita_debug_add_row(label=None, field=None):
  row = chispita_obj()
  row.label = label
  row.field = field
  chispita_debug_rows.append(row)

def chispita_debug_make_rows():
  if len(chispita_debug_rows) > 0: return
  chispita_debug_add_row("Grid", "grid")
  chispita_debug_add_row("Hit boxes", "hit_boxes")
  chispita_debug_add_row("Hurt boxes", "hurt_boxes")
  chispita_debug_add_row("Velocity", "velocity")
  chispita_debug_add_row("Contacts", "contacts")
  chispita_debug_add_row("Labels", "labels")
  chispita_debug_add_row("Map cells", "map_cells")
  chispita_debug_add_row("Camera", "camera")
  chispita_debug_add_row("Mouse", "mouse")
  chispita_debug_add_row("Info", "info")
  chispita_debug_add_row("Drag", "drag")
  chispita_debug_add_row("Slow motion", "slow_motion")
  chispita_debug_add_row("Paused", "paused")
  chispita_debug_add_row("Step frame", "step")

def chispita_debug_panel_layout():
  l = chispita_obj()
  l.width = 56
  l.row_h = 7
  l.left = screen.width / 2 - 2 - l.width
  l.top = screen.height / 2 - 2
  return l

# Header
def chispita_debug_row_at(x=None, y=None):
  if not Debug.panel: return "none"
  l = chispita_debug_panel_layout()
  if x < l.left or x > l.left + l.width: return "none"
  from_top = l.top - y
  if from_top < 0: return "none"
  row = math.floor(from_top / l.row_h)
  if row == 0: return "header"
  if not Debug.panel_open: return "none"
  if row - 1 < len(chispita_debug_rows): return row - 1
  return "none"


# Update debug
def chispita_debug_update():
  global chispita_step_requested
  chispita_debug_make_rows()

  row = chispita_debug_row_at(mouse.x, mouse.y)
  if mouse.press and row != "none":
    if row == "header":
      Debug.panel_open = not Debug.panel_open
    else:
      field = chispita_debug_rows[row].field
      if field == "step":
        Debug.paused = 1
        chispita_step_requested = 1
      else:
        Debug[field] = not Debug[field]

  chispita_debug_update_drag(row == "none")

def chispita_debug_update_drag(mouse_is_free=None):
  global chispita_drag_dx, chispita_drag_dy, chispita_dragging, chispita_throw_x, chispita_throw_y
  world = Chispita_screenToWorld(mouse.x, mouse.y)

  if mouse.press and mouse_is_free and Debug.drag:
    chispita_dragging = chispita_debug_sprite_at(world.x, world.y)
    if chispita_dragging:
      chispita_drag_dx = chispita_dragging.x - world.x
      chispita_drag_dy = chispita_dragging.y - world.y

  if not chispita_dragging: return
  s = chispita_dragging

  if mouse.pressed:
    new_x = world.x + chispita_drag_dx
    new_y = world.y + chispita_drag_dy
    chispita_throw_x = (new_x - s.x) * 60
    chispita_throw_y = (new_y - s.y) * 60
    s.x = new_x
    s.y = new_y
    s.old_x = new_x
    s.old_y = new_y
    s.vx = 0
    s.vy = 0
  else:

    if not s.fixed:
      s.vx = chispita_throw_x
      s.vy = chispita_throw_y
    chispita_dragging = 0

def chispita_debug_should_step():
  global chispita_slow_counter, chispita_step_requested
  if Debug.paused:
    if chispita_step_requested:
      chispita_step_requested = 0
      return 1
    return 0
  if Debug.slow_motion:
    chispita_slow_counter += 1
    return chispita_slow_counter % Debug.slow_factor == 0
  return 1

def chispita_debug_sprite_at(x=None, y=None):
  for i in range(len(chispita_drawables) - 1, -1, -1):
    o = chispita_drawables[i]
    if o.hit_box_shape and o.active and o.visible and not o.ui:
      if Chispita_pointIn(o, x, y): return o
  return 0

# Drawing Debug
def chispita_debug_text(text=None, x=None, y=None, color=None):
  screen.setDrawAnchor(-1, 0)
  screen.drawText(text, x + 0.5, y - 0.5, chispita_debug_size, "rgb(0,0,0)")
  screen.drawText(text, x, y, chispita_debug_size, color)
  screen.setDrawAnchor(0, 0)

def chispita_fmt(n=None):
  return math.floor(n * 100 + 0.5) / 100

def chispita_debug_outline(shape=None, color=None):
  x = chispita_world_x(shape.x)
  y = chispita_world_y(shape.y)
  w = shape.hw * 2 * Camera.zoom
  h = shape.hh * 2 * Camera.zoom
  if shape.kind == "circle":
    screen.drawRound(x, y, w, h, color)
  elif shape.kind == "capsule":
    if shape.angle: screen.setDrawRotation(shape.angle)
    screen.drawRoundRect(x, y, w, h, w / 2, color)
    if shape.angle: screen.setDrawRotation(0)
  elif shape.angle:
    ux = shape.hw * shape.cos
    uy = shape.hw * shape.sin
    vx = -shape.hh * shape.sin
    vy = shape.hh * shape.cos
    screen.drawPolygon(
      chispita_world_x(shape.x - ux - vx), chispita_world_y(shape.y - uy - vy),
      chispita_world_x(shape.x + ux - vx), chispita_world_y(shape.y + uy - vy),
      chispita_world_x(shape.x + ux + vx), chispita_world_y(shape.y + uy + vy),
      chispita_world_x(shape.x - ux + vx), chispita_world_y(shape.y - uy + vy),
      color)
  else:
    screen.drawRect(x, y, w, h, color)

def chispita_debug_box_color(s=None):
  if not s.solid: return "rgb(255,230,0)"
  if s.fixed or s.kinematic: return "rgb(80,160,255)"
  return "rgb(0,255,0)"

# Draws tools
def chispita_debug_draw_grid():
  size = Debug.grid_size
  half_w = screen.width / 2 / Camera.zoom
  half_h = screen.height / 2 / Camera.zoom
  left = chispita_view_x() - half_w
  right = chispita_view_x() + half_w
  bottom = chispita_view_y() - half_h
  top = chispita_view_y() + half_h
  color = "rgb(60,60,70)"

  screen.setLineWidth(1)
  x = math.floor(left / size) * size
  while x <= right:
    screen.drawLine(chispita_world_x(x), -screen.height / 2, chispita_world_x(x), screen.height / 2, color)
    x += size
  y = math.floor(bottom / size) * size
  while y <= top:
    screen.drawLine(-screen.width / 2, chispita_world_y(y), screen.width / 2, chispita_world_y(y), color)
    y += size

  screen.drawLine(chispita_world_x(0), -screen.height / 2, chispita_world_x(0), screen.height / 2, "rgb(0,140,0)")
  screen.drawLine(-screen.width / 2, chispita_world_y(0), screen.width / 2, chispita_world_y(0), "rgb(160,0,0)")

def chispita_debug_draw_map_cells():
  half_w = screen.width / 2 / Camera.zoom
  half_h = screen.height / 2 / Camera.zoom
  for m in chispita_maps:
    if not (m.map and m.physics and m.active): continue
    l = chispita_map_layout(m)
    x0 = math.floor((chispita_view_x() - half_w - l.left) / l.cw)
    x1 = math.floor((chispita_view_x() + half_w - l.left) / l.cw)
    y0 = math.floor((chispita_view_y() - half_h - l.bottom) / l.ch)
    y1 = math.floor((chispita_view_y() + half_h - l.bottom) / l.ch)
    if not chispita_tiles_across(m):
      x0 = max(0, x0)
      x1 = min(m.map.width - 1, x1)
    if not chispita_tiles_down(m):
      y0 = max(0, y0)
      y1 = min(m.map.height - 1, y1)

    for cy in range(y0, y1 + 1):
      for cx in range(x0, x1 + 1):
        kind = chispita_tile_kind(m, chispita_map_get(m, cx, cy))
        if kind == "empty": continue
        x = chispita_world_x(l.left + (cx + 0.5) * l.cw)
        y = chispita_world_y(l.bottom + (cy + 0.5) * l.ch)
        w = l.cw * Camera.zoom
        h = l.ch * Camera.zoom
        if kind == "solid":
          screen.drawRect(x, y, w, h, "rgb(255,140,0)")
        else:
          screen.drawLine(x - w / 2, y + h / 2, x + w / 2, y + h / 2, "rgb(0,220,255)")

def chispita_debug_draw_camera():
  b = Camera.bounds
  if b:
    x = chispita_world_x((b.left + b.right) / 2)
    y = chispita_world_y((b.bottom + b.top) / 2)
    screen.drawRect(x, y, (b.right - b.left) * Camera.zoom, (b.top - b.bottom) * Camera.zoom, "rgb(255,0,255)")

  screen.drawLine(-3, 0, 3, 0, "rgb(255,0,255)")
  screen.drawLine(0, -3, 0, 3, "rgb(255,0,255)")
  if Camera.target:
    tx = chispita_world_x(Camera.target.x)
    ty = chispita_world_y(Camera.target.y)
    screen.drawLine(0, 0, tx, ty, "rgb(255,0,255)")

def chispita_debug_draw_sprite(s=None):
  shape = chispita_hit_shape(s)
  x = chispita_world_x(shape.x)
  y = chispita_world_y(shape.y)

  if Debug.hit_boxes and s.physics:
    chispita_debug_outline(shape, chispita_debug_box_color(s))
    if s.hit_parts:
      for part in s.hit_parts:
        chispita_debug_outline(chispita_part_shape(s, part), chispita_debug_box_color(s))
  if Debug.hurt_boxes and s.hurt_box:
    chispita_debug_outline(chispita_hurt_shape(s), "rgb(255,0,0)")
    if s.hurt_parts:
      for part in s.hurt_parts:
        chispita_debug_outline(chispita_part_shape(s, part), "rgb(255,0,0)")

  if Debug.velocity and (s.vx != 0 or s.vy != 0):
    end_x = chispita_world_x(shape.x + s.vx * 0.1)
    end_y = chispita_world_y(shape.y + s.vy * 0.1)
    screen.drawLine(x, y, end_x, end_y, "rgb(255,80,200)")
    screen.fillRound(end_x, end_y, 2, 2, "rgb(255,80,200)")

  if Debug.contacts:
    bottom = y - shape.hh * Camera.zoom
    if s.grounded:
      screen.fillRect(x, bottom - 1, shape.hw * 2 * Camera.zoom, 1, "rgb(255,255,255)")
    if s.trigger:
      for id in s.contacts:
        other = s.contacts[id]
        screen.drawLine(x, y, chispita_world_x(other.x), chispita_world_y(other.y), "rgb(255,255,255)")

  if Debug.labels:
    label = "#" + chispita_str(s.id)

    if s.sprite_name: label += " " + chispita_str(s.sprite_name)
    chispita_debug_text(label, x - shape.hw * Camera.zoom, y + shape.hh * Camera.zoom + 4, chispita_debug_text_color)

def chispita_debug_draw_mouse():
  mx = mouse.x
  my = mouse.y
  world = Chispita_screenToWorld(mx, my)
  color = "rgb(255,255,0)"

  # Crosshair
  screen.setAlpha(0.4)
  screen.drawLine(-screen.width / 2, my, screen.width / 2, my, color)
  screen.drawLine(mx, -screen.height / 2, mx, screen.height / 2, color)
  screen.setAlpha(1)

  lines = []
  lines.append(chispita_str(chispita_fmt(world.x)) + ", " + chispita_str(chispita_fmt(world.y)))
  for m in chispita_maps:
    if not (m.map and m.physics): continue
    cell = Chispita_cellAt(m, world.x, world.y)
    if cell:
      l = chispita_map_layout(m)
      cx = chispita_wrap_x(m, math.floor((world.x - l.left) / l.cw))
      cy = chispita_wrap_y(m, math.floor((world.y - l.bottom) / l.ch))
      lines.append(chispita_str(m.name) + " [" + chispita_str(cx) + "," + chispita_str(cy) + "] " + chispita_str(cell) + " (" + chispita_str(chispita_tile_kind(m, cell)) + ")")

  text_x = mx + 4
  if text_x > screen.width / 2 - 70: text_x = mx - 70
  text_y = my + 6
  if text_y > screen.height / 2 - 6 * len(lines): text_y = my - 6
  for i in range(len(lines)):
    chispita_debug_text(lines[i], text_x, text_y - i * 6, color)

  s = chispita_debug_sprite_at(world.x, world.y)
  if s:
    chispita_debug_outline(chispita_hit_shape(s), "rgb(255,255,0)")
    chispita_debug_draw_inspector(s)

def chispita_debug_draw_inspector(s=None):
  lines = []
  title = "#" + chispita_str(s.id) + " " + chispita_str(s.hit_box_shape)

  if s.sprite_name: title += " " + chispita_str(s.sprite_name)
  lines.append(title)
  lines.append("x, y: " + chispita_str(chispita_fmt(s.x)) + ", " + chispita_str(chispita_fmt(s.y)))
  lines.append("vx, vy: " + chispita_str(chispita_fmt(s.vx)) + ", " + chispita_str(chispita_fmt(s.vy)))
  lines.append("grounded: " + chispita_str(s.grounded) + "  group: " + chispita_str(s.group) + "  layer: " + chispita_str(s.layer))
  lines.append("mass: " + chispita_str(s.mass) + "  grip: " + chispita_str(s.grip) + "  bounce: " + chispita_str(s.bounciness))

  flags = ""
  if s.fixed: flags += "fixed "
  if s.kinematic: flags += "kinematic "
  if not s.solid: flags += "not-solid "
  if s.trigger: flags += "trigger "
  if s.one_way: flags += "one-way "
  if s.riding: flags += "riding#" + chispita_str(s.riding.id) + " "
  if flags != "": lines.append(flags)

  if s.animation: lines.append("animation: " + chispita_str(s.animation) + " frame " + chispita_str(s.frame))

  left = -screen.width / 2 + 4
  bottom = -screen.height / 2 + 4
  for i in range(len(lines)):
    chispita_debug_text(lines[i], left, bottom + (len(lines) - 1 - i) * 6, "rgb(255,255,0)")

def chispita_debug_draw_info():
  active = 0
  for s in chispita_sprites:
    if s.active: active += 1

  state = "running"
  if Debug.paused:
    state = "PAUSED"
  elif Debug.slow_motion:
    state = "SLOW x" + chispita_str(Debug.slow_factor)

  lines = []
  lines.append("FPS: " + chispita_str(math.floor(chispita_fps + 0.5)) + "  " + chispita_str(state))
  lines.append("Mode: " + chispita_str(chispita_mode) + "  Gravity: " + chispita_str(chispita_gravity) + "  Substeps: " + chispita_str(chispita_substeps))
  lines.append("Sprites: " + chispita_str(active) + " active / " + chispita_str(len(chispita_sprites)) + "  Maps: " + chispita_str(len(chispita_maps)))
  lines.append("Particles: " + chispita_str(chispita_live_particles()) + "  Timers: " + chispita_str(chispita_live_timers()))
  lines.append("Camera: " + chispita_str(chispita_fmt(Camera.x)) + ", " + chispita_str(chispita_fmt(Camera.y)) + "  zoom " + chispita_str(Camera.zoom))
  for label in chispita_watch_order:
    lines.append(chispita_str(label) + ": " + chispita_str(chispita_watches[label]))

  left = -screen.width / 2 + 4
  top = screen.height / 2 - 5
  for i in range(len(lines)):
    chispita_debug_text(lines[i], left, top - i * 6, chispita_debug_text_color)

def chispita_debug_draw_panel():
  chispita_debug_make_rows()
  l = chispita_debug_panel_layout()
  rows_shown = 0
  if Debug.panel_open: rows_shown = len(chispita_debug_rows)
  height = (rows_shown + 1) * l.row_h

  # Background
  screen.setAlpha(0.75)
  screen.fillRect(l.left + l.width / 2, l.top - height / 2, l.width, height, "rgb(0,0,0)")
  screen.setAlpha(1)

  hover = chispita_debug_row_at(mouse.x, mouse.y)
  if hover != "none":
    index = 0
    if hover != "header": index = hover + 1
    screen.setAlpha(0.2)
    screen.fillRect(l.left + l.width / 2, l.top - (index + 0.5) * l.row_h, l.width, l.row_h, "rgb(255,255,255)")
    screen.setAlpha(1)

  fold = "[-]"
  if not Debug.panel_open: fold = "[+]"
  chispita_debug_text("DEBUG " + chispita_str(fold), l.left + 3, l.top - l.row_h / 2, "rgb(255,230,0)")
  if not Debug.panel_open: return

  for i in range(len(chispita_debug_rows)):
    row = chispita_debug_rows[i]
    y = l.top - (i + 1.5) * l.row_h
    chispita_debug_text(row.label, l.left + 3, y, chispita_debug_text_color)

    box_x = l.left + l.width - 5
    if row.field == "step":
      chispita_debug_text(">", box_x - 1, y, chispita_debug_text_color)
    else:
      screen.drawRect(box_x, y, 4, 4, chispita_debug_text_color)
      if Debug[row.field]: screen.fillRect(box_x, y, 2, 2, "rgb(0,255,0)")

def chispita_draw_debug():
  if Debug.map_cells: chispita_debug_draw_map_cells()
  if Debug.camera: chispita_debug_draw_camera()
  for s in chispita_sprites:
    if s.active: chispita_debug_draw_sprite(s)
  if Debug.mouse: chispita_debug_draw_mouse()
  if Debug.info: chispita_debug_draw_info()
  if Debug.panel: chispita_debug_draw_panel()

