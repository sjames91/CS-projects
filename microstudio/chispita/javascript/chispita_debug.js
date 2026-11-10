var Debug = {
  panel: 1,
  panel_open: 1,
  grid: 1,
  grid_size: 32,
  hit_boxes: 1,
  hurt_boxes: 1,
  velocity: 0,
  contacts: 0,
  labels: 0,
  map_cells: 0,
  camera: 0,
  mouse: 1,
  info: 1,
  drag: 1,
  slow_motion: 0,
  slow_factor: 4,
  paused: 0,
}

var chispita_debug_rows = []
var chispita_step_requested = 0
var chispita_slow_counter = 0
var chispita_dragging = 0
var chispita_drag_dx = 0
var chispita_drag_dy = 0
var chispita_throw_x = 0
var chispita_throw_y = 0
var chispita_watches = {}
var chispita_watch_order = []

function chispita_debug_reset() {
  chispita_dragging = 0
  chispita_step_requested = 0
  chispita_slow_counter = 0
  chispita_throw_x = 0
  chispita_throw_y = 0
  chispita_watches = {}
  chispita_watch_order = []
}

var chispita_debug_text_color = "rgb(255,255,255)"
var chispita_debug_size = 5

// Watch values
function Chispita_watch(label, value) {
  if (chispita_watch_order.indexOf(label) < 0) chispita_watch_order.push(label)
  chispita_watches[label] = value
}

function Chispita_toggleDebug(name) {
  if (!name) {
    chispita_debug_mode = !chispita_debug_mode
  } else {
    Debug[name] = !Debug[name]
  }
}

function Chispita_mouseOnDebug() {
  if (!chispita_debug_mode) return 0
  if (chispita_dragging) return 1
  return chispita_debug_row_at(mouse.x, mouse.y) != "none"
}

// Debug panel
function chispita_debug_add_row(label, field) {
  var row = {}
  row.label = label
  row.field = field
  chispita_debug_rows.push(row)
}

function chispita_debug_make_rows() {
  if (chispita_debug_rows.length > 0) return
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
}

function chispita_debug_panel_layout() {
  var l = {}
  l.width = 56
  l.row_h = 7
  l.left = screen.width / 2 - 2 - l.width
  l.top = screen.height / 2 - 2
  return l
}

// Header
function chispita_debug_row_at(x, y) {
  if (!Debug.panel) return "none"
  var l = chispita_debug_panel_layout()
  if (x < l.left || x > l.left + l.width) return "none"
  var from_top = l.top - y
  if (from_top < 0) return "none"
  var row = Math.floor(from_top / l.row_h)
  if (row == 0) return "header"
  if (!Debug.panel_open) return "none"
  if (row - 1 < chispita_debug_rows.length) return row - 1
  return "none"
}


// Update debug
function chispita_debug_update() {
  chispita_debug_make_rows()

  var row = chispita_debug_row_at(mouse.x, mouse.y)
  if (mouse.press && row != "none") {
    if (row == "header") {
      Debug.panel_open = !Debug.panel_open
    } else {
      var field = chispita_debug_rows[row].field
      if (field == "step") {
        Debug.paused = 1
        chispita_step_requested = 1
      } else {
        Debug[field] = !Debug[field]
      }
    }
  }

  chispita_debug_update_drag(row == "none")
}

function chispita_debug_update_drag(mouse_is_free) {
  var world = Chispita_screenToWorld(mouse.x, mouse.y)

  if (mouse.press && mouse_is_free && Debug.drag) {
    chispita_dragging = chispita_debug_sprite_at(world.x, world.y)
    if (chispita_dragging) {
      chispita_drag_dx = chispita_dragging.x - world.x
      chispita_drag_dy = chispita_dragging.y - world.y
    }
  }

  if (!chispita_dragging) return
  var s = chispita_dragging

  if (mouse.pressed) {
    var new_x = world.x + chispita_drag_dx
    var new_y = world.y + chispita_drag_dy
    chispita_throw_x = (new_x - s.x) * 60
    chispita_throw_y = (new_y - s.y) * 60
    s.x = new_x
    s.y = new_y
    s.old_x = new_x
    s.old_y = new_y
    s.vx = 0
    s.vy = 0
  } else {

    if (!s.fixed) {
      s.vx = chispita_throw_x
      s.vy = chispita_throw_y
    }
    chispita_dragging = 0
  }
}

function chispita_debug_should_step() {
  if (Debug.paused) {
    if (chispita_step_requested) {
      chispita_step_requested = 0
      return 1
    }
    return 0
  }
  if (Debug.slow_motion) {
    chispita_slow_counter += 1
    return chispita_slow_counter % Debug.slow_factor == 0
  }
  return 1
}

function chispita_debug_sprite_at(x, y) {
  for (var i = chispita_drawables.length - 1; i >= 0; i += -1) {
    var o = chispita_drawables[i]
    if (o.hit_box_shape && o.active && o.visible && !o.ui) {
      if (Chispita_pointIn(o, x, y)) return o
    }
  }
  return 0
}

// Drawing Debug
function chispita_debug_text(text, x, y, color) {
  screen.setDrawAnchor(-1, 0)
  screen.drawText(text, x + 0.5, y - 0.5, chispita_debug_size, "rgb(0,0,0)")
  screen.drawText(text, x, y, chispita_debug_size, color)
  screen.setDrawAnchor(0, 0)
}

function chispita_fmt(n) {
  return Math.floor(n * 100 + 0.5) / 100
}

function chispita_debug_outline(shape, color) {
  var x = chispita_world_x(shape.x)
  var y = chispita_world_y(shape.y)
  var w = shape.hw * 2 * Camera.zoom
  var h = shape.hh * 2 * Camera.zoom
  if (shape.kind == "circle") {
    screen.drawRound(x, y, w, h, color)
  } else if (shape.kind == "capsule") {
    if (shape.angle) screen.setDrawRotation(shape.angle)
    screen.drawRoundRect(x, y, w, h, w / 2, color)
    if (shape.angle) screen.setDrawRotation(0)
  } else if (shape.angle) {
    var ux = shape.hw * shape.cos
    var uy = shape.hw * shape.sin
    var vx = -shape.hh * shape.sin
    var vy = shape.hh * shape.cos
    screen.drawPolygon([
    chispita_world_x(shape.x - ux - vx), chispita_world_y(shape.y - uy - vy),
    chispita_world_x(shape.x + ux - vx), chispita_world_y(shape.y + uy - vy),
    chispita_world_x(shape.x + ux + vx), chispita_world_y(shape.y + uy + vy),
    chispita_world_x(shape.x - ux + vx), chispita_world_y(shape.y - uy + vy)
    ], color)
  } else {
    screen.drawRect(x, y, w, h, color)
  }
}

function chispita_debug_box_color(s) {
  if (!s.solid) return "rgb(255,230,0)"
  if (s.fixed || s.kinematic) return "rgb(80,160,255)"
  return "rgb(0,255,0)"
}

// Draws tools
function chispita_debug_draw_grid() {
  var size = Debug.grid_size
  var half_w = screen.width / 2 / Camera.zoom
  var half_h = screen.height / 2 / Camera.zoom
  var left = chispita_view_x() - half_w
  var right = chispita_view_x() + half_w
  var bottom = chispita_view_y() - half_h
  var top = chispita_view_y() + half_h
  var color = "rgb(60,60,70)"

  screen.setLineWidth(1)
  var x = Math.floor(left / size) * size
  while (x <= right) {
    screen.drawLine(chispita_world_x(x), -screen.height / 2, chispita_world_x(x), screen.height / 2, color)
    x += size
  }
  var y = Math.floor(bottom / size) * size
  while (y <= top) {
    screen.drawLine(-screen.width / 2, chispita_world_y(y), screen.width / 2, chispita_world_y(y), color)
    y += size
  }

  screen.drawLine(chispita_world_x(0), -screen.height / 2, chispita_world_x(0), screen.height / 2, "rgb(0,140,0)")
  screen.drawLine(-screen.width / 2, chispita_world_y(0), screen.width / 2, chispita_world_y(0), "rgb(160,0,0)")
}

function chispita_debug_draw_map_cells() {
  var half_w = screen.width / 2 / Camera.zoom
  var half_h = screen.height / 2 / Camera.zoom
  for (var m of chispita_maps) {
    if (!(m.map && m.physics && m.active)) continue
    var l = chispita_map_layout(m)
    var x0 = Math.floor((chispita_view_x() - half_w - l.left) / l.cw)
    var x1 = Math.floor((chispita_view_x() + half_w - l.left) / l.cw)
    var y0 = Math.floor((chispita_view_y() - half_h - l.bottom) / l.ch)
    var y1 = Math.floor((chispita_view_y() + half_h - l.bottom) / l.ch)
    if (!chispita_tiles_across(m)) {
      x0 = Math.max(0, x0)
      x1 = Math.min(m.map.width - 1, x1)
    }
    if (!chispita_tiles_down(m)) {
      y0 = Math.max(0, y0)
      y1 = Math.min(m.map.height - 1, y1)
    }

    for (var cy = y0; cy <= y1; cy += 1) {
      for (var cx = x0; cx <= x1; cx += 1) {
        var kind = chispita_tile_kind(m, chispita_map_get(m, cx, cy))
        if (kind == "empty") continue
        var x = chispita_world_x(l.left + (cx + 0.5) * l.cw)
        var y = chispita_world_y(l.bottom + (cy + 0.5) * l.ch)
        var w = l.cw * Camera.zoom
        var h = l.ch * Camera.zoom
        if (kind == "solid") {
          screen.drawRect(x, y, w, h, "rgb(255,140,0)")
        } else {
          screen.drawLine(x - w / 2, y + h / 2, x + w / 2, y + h / 2, "rgb(0,220,255)")
        }
      }
    }
  }
}

function chispita_debug_draw_camera() {
  var b = Camera.bounds
  if (b) {
    var x = chispita_world_x((b.left + b.right) / 2)
    var y = chispita_world_y((b.bottom + b.top) / 2)
    screen.drawRect(x, y, (b.right - b.left) * Camera.zoom, (b.top - b.bottom) * Camera.zoom, "rgb(255,0,255)")
  }

  screen.drawLine(-3, 0, 3, 0, "rgb(255,0,255)")
  screen.drawLine(0, -3, 0, 3, "rgb(255,0,255)")
  if (Camera.target) {
    var tx = chispita_world_x(Camera.target.x)
    var ty = chispita_world_y(Camera.target.y)
    screen.drawLine(0, 0, tx, ty, "rgb(255,0,255)")
  }
}

function chispita_debug_draw_sprite(s) {
  var shape = chispita_hit_shape(s)
  var x = chispita_world_x(shape.x)
  var y = chispita_world_y(shape.y)

  if (Debug.hit_boxes && s.physics) {
    chispita_debug_outline(shape, chispita_debug_box_color(s))
    if (s.hit_parts) {
      for (var part of s.hit_parts) {
        chispita_debug_outline(chispita_part_shape(s, part), chispita_debug_box_color(s))
      }
    }
  }
  if (Debug.hurt_boxes && s.hurt_box) {
    chispita_debug_outline(chispita_hurt_shape(s), "rgb(255,0,0)")
    if (s.hurt_parts) {
      for (var part of s.hurt_parts) {
        chispita_debug_outline(chispita_part_shape(s, part), "rgb(255,0,0)")
      }
    }
  }

  if (Debug.velocity && (s.vx != 0 || s.vy != 0)) {
    var end_x = chispita_world_x(shape.x + s.vx * 0.1)
    var end_y = chispita_world_y(shape.y + s.vy * 0.1)
    screen.drawLine(x, y, end_x, end_y, "rgb(255,80,200)")
    screen.fillRound(end_x, end_y, 2, 2, "rgb(255,80,200)")
  }

  if (Debug.contacts) {
    var bottom = y - shape.hh * Camera.zoom
    if (s.grounded) {
      screen.fillRect(x, bottom - 1, shape.hw * 2 * Camera.zoom, 1, "rgb(255,255,255)")
    }
    if (s.trigger) {
      for (var id in s.contacts) {
        var other = s.contacts[id]
        screen.drawLine(x, y, chispita_world_x(other.x), chispita_world_y(other.y), "rgb(255,255,255)")
      }
    }
  }

  if (Debug.labels) {
    var label = "#" + s.id

    if (s.sprite_name) label += " " + s.sprite_name
    chispita_debug_text(label, x - shape.hw * Camera.zoom, y + shape.hh * Camera.zoom + 4, chispita_debug_text_color)
  }
}

function chispita_debug_draw_mouse() {
  var mx = mouse.x
  var my = mouse.y
  var world = Chispita_screenToWorld(mx, my)
  var color = "rgb(255,255,0)"

  // Crosshair
  screen.setAlpha(0.4)
  screen.drawLine(-screen.width / 2, my, screen.width / 2, my, color)
  screen.drawLine(mx, -screen.height / 2, mx, screen.height / 2, color)
  screen.setAlpha(1)

  var lines = []
  lines.push(chispita_fmt(world.x) + ", " + chispita_fmt(world.y))
  for (var m of chispita_maps) {
    if (!(m.map && m.physics)) continue
    var cell = Chispita_cellAt(m, world.x, world.y)
    if (cell) {
      var l = chispita_map_layout(m)
      var cx = chispita_wrap_x(m, Math.floor((world.x - l.left) / l.cw))
      var cy = chispita_wrap_y(m, Math.floor((world.y - l.bottom) / l.ch))
      lines.push(m.name + " [" + cx + "," + cy + "] " + cell + " (" + chispita_tile_kind(m, cell) + ")")
    }
  }

  var text_x = mx + 4
  if (text_x > screen.width / 2 - 70) text_x = mx - 70
  var text_y = my + 6
  if (text_y > screen.height / 2 - 6 * lines.length) text_y = my - 6
  for (var i = 0; i <= lines.length - 1; i += 1) {
    chispita_debug_text(lines[i], text_x, text_y - i * 6, color)
  }

  var s = chispita_debug_sprite_at(world.x, world.y)
  if (s) {
    chispita_debug_outline(chispita_hit_shape(s), "rgb(255,255,0)")
    chispita_debug_draw_inspector(s)
  }
}

function chispita_debug_draw_inspector(s) {
  var lines = []
  var title = "#" + s.id + " " + s.hit_box_shape

  if (s.sprite_name) title += " " + s.sprite_name
  lines.push(title)
  lines.push("x, y: " + chispita_fmt(s.x) + ", " + chispita_fmt(s.y))
  lines.push("vx, vy: " + chispita_fmt(s.vx) + ", " + chispita_fmt(s.vy))
  lines.push("grounded: " + s.grounded + "  group: " + s.group + "  layer: " + s.layer)
  lines.push("mass: " + s.mass + "  grip: " + s.grip + "  bounce: " + s.bounciness)

  var flags = ""
  if (s.fixed) flags += "fixed "
  if (s.kinematic) flags += "kinematic "
  if (!s.solid) flags += "not-solid "
  if (s.trigger) flags += "trigger "
  if (s.one_way) flags += "one-way "
  if (s.riding) flags += "riding#" + s.riding.id + " "
  if (flags != "") lines.push(flags)

  if (s.animation) lines.push("animation: " + s.animation + " frame " + s.frame)

  var left = -screen.width / 2 + 4
  var bottom = -screen.height / 2 + 4
  for (var i = 0; i <= lines.length - 1; i += 1) {
    chispita_debug_text(lines[i], left, bottom + (lines.length - 1 - i) * 6, "rgb(255,255,0)")
  }
}

function chispita_debug_draw_info() {
  var active = 0
  for (var s of chispita_sprites) {
    if (s.active) active += 1
  }

  var state = "running"
  if (Debug.paused) {
    state = "PAUSED"
  } else if (Debug.slow_motion) {
    state = "SLOW x" + Debug.slow_factor
  }

  var lines = []
  lines.push("FPS: " + Math.round(chispita_fps) + "  " + state)
  lines.push("Mode: " + chispita_mode + "  Gravity: " + chispita_gravity + "  Substeps: " + chispita_substeps)
  lines.push("Sprites: " + active + " active / " + chispita_sprites.length + "  Maps: " + chispita_maps.length)
  lines.push("Particles: " + chispita_live_particles() + "  Timers: " + chispita_live_timers())
  lines.push("Camera: " + chispita_fmt(Camera.x) + ", " + chispita_fmt(Camera.y) + "  zoom " + Camera.zoom)
  for (var label of chispita_watch_order) {
    lines.push(label + ": " + chispita_watches[label])
  }

  var left = -screen.width / 2 + 4
  var top = screen.height / 2 - 5
  for (var i = 0; i <= lines.length - 1; i += 1) {
    chispita_debug_text(lines[i], left, top - i * 6, chispita_debug_text_color)
  }
}

function chispita_debug_draw_panel() {
  chispita_debug_make_rows()
  var l = chispita_debug_panel_layout()
  var rows_shown = 0
  if (Debug.panel_open) rows_shown = chispita_debug_rows.length
  var height = (rows_shown + 1) * l.row_h

  // Background
  screen.setAlpha(0.75)
  screen.fillRect(l.left + l.width / 2, l.top - height / 2, l.width, height, "rgb(0,0,0)")
  screen.setAlpha(1)

  var hover = chispita_debug_row_at(mouse.x, mouse.y)
  if (hover != "none") {
    var index = 0
    if (hover != "header") index = hover + 1
    screen.setAlpha(0.2)
    screen.fillRect(l.left + l.width / 2, l.top - (index + 0.5) * l.row_h, l.width, l.row_h, "rgb(255,255,255)")
    screen.setAlpha(1)
  }

  var fold = "[-]"
  if (!Debug.panel_open) fold = "[+]"
  chispita_debug_text("DEBUG " + fold, l.left + 3, l.top - l.row_h / 2, "rgb(255,230,0)")
  if (!Debug.panel_open) return

  for (var i = 0; i <= chispita_debug_rows.length - 1; i += 1) {
    var row = chispita_debug_rows[i]
    var y = l.top - (i + 1.5) * l.row_h
    chispita_debug_text(row.label, l.left + 3, y, chispita_debug_text_color)

    var box_x = l.left + l.width - 5
    if (row.field == "step") {
      chispita_debug_text(">", box_x - 1, y, chispita_debug_text_color)
    } else {
      screen.drawRect(box_x, y, 4, 4, chispita_debug_text_color)
      if (Debug[row.field]) screen.fillRect(box_x, y, 2, 2, "rgb(0,255,0)")
    }
  }
}

function chispita_draw_debug() {
  if (Debug.map_cells) chispita_debug_draw_map_cells()
  if (Debug.camera) chispita_debug_draw_camera()
  for (var s of chispita_sprites) {
    if (s.active) chispita_debug_draw_sprite(s)
  }
  if (Debug.mouse) chispita_debug_draw_mouse()
  if (Debug.info) chispita_debug_draw_info()
  if (Debug.panel) chispita_debug_draw_panel()
}

