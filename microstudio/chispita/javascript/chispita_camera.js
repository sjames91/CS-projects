// Create camera object
var Camera = {
  x: 0,
  y: 0,
  target: 0,
  smooth: 1,
  zoom: 1,
  bounds: 0,
  deadzone_x: 0,
  deadzone_y: 0,
  look_ahead_x: 0,
  look_ahead_y: 0,
  shake_amount: 0,
  shake_time: 0,
  shake_total: 0,
  shake_fade: 1,
  shake_x: 0,
  shake_y: 0,
}

function chispita_camera_aim(position, target, zone) {
  if (zone <= 0) return target
  if (target > position + zone) return target - zone
  if (target < position - zone) return target + zone
  return position
}

// Update camera
function chispita_camera_update(dt) {
  if (Camera.target) {
    var tx = Camera.target.x + Camera.target.vx * Camera.look_ahead_x
    var ty = Camera.target.y + Camera.target.vy * Camera.look_ahead_y
    tx = chispita_camera_aim(Camera.x, tx, Camera.deadzone_x)
    ty = chispita_camera_aim(Camera.y, ty, Camera.deadzone_y)
    var ease = Camera.smooth
    if (ease < 1 && dt != 1 / 60) ease = 1 - Math.pow(1 - ease, dt * 60)
    Camera.x += (tx - Camera.x) * ease
    Camera.y += (ty - Camera.y) * ease
  }

// Clamp camera bounds
  if (Camera.bounds) {
    chispita_camera_clamp()
  }

// Camera shake
  Camera.shake_x = 0
  Camera.shake_y = 0
  if (Camera.shake_time > 0) {
    Camera.shake_time -= dt
    var amount = Camera.shake_amount
    if (Camera.shake_fade && Camera.shake_total > 0) {
      amount *= Math.max(0, Camera.shake_time / Camera.shake_total)
    }
    var angle = random.next() * 360
    Camera.shake_x = chispita_cosd(angle) * amount
    Camera.shake_y = chispita_sind(angle) * amount
  }
}

// Camera clamping math
function chispita_camera_clamp() {
  var b = Camera.bounds
  var half_w = screen.width / 2 / Camera.zoom
  var half_h = screen.height / 2 / Camera.zoom

  if (b.right - b.left < half_w * 2) {
    Camera.x = (b.left + b.right) / 2
  } else {
    Camera.x = Math.max(b.left + half_w, Math.min(Camera.x, b.right - half_w))
  }

  if (b.top - b.bottom < half_h * 2) {
    Camera.y = (b.bottom + b.top) / 2
  } else {
    Camera.y = Math.max(b.bottom + half_h, Math.min(Camera.y, b.top - half_h))
  }
}

function Chispita_setTarget(sprite) {
  Camera.target = sprite
}

function Chispita_cameraShake(amount, seconds) {
  Camera.shake_amount = amount
  Camera.shake_time = seconds
  Camera.shake_total = seconds
}

function Chispita_setCameraBounds(left, bottom, right, top) {
  if (left >= right || bottom >= top) {
    chispita_warn("Chispita_setCameraBounds needs left < right and bottom < top.")
    return
  }
  var b = {}
  b.left = left
  b.bottom = bottom
  b.right = right
  b.top = top
  Camera.bounds = b
}

function Chispita_limitCameraToMap(m) {
  if (!m.map) {
    chispita_warn("Chispita_limitCameraToMap needs a map from Chispita_addMap.")
    return
  }
  var l = chispita_map_layout(m)
  if (!l) return
  var huge = 1000000000
  var left = l.left
  var right = l.left + l.width
  var bottom = l.bottom
  var top = l.bottom + l.height
  if (chispita_tiles_across(m)) {
    left = -huge
    right = huge
  }
  if (chispita_tiles_down(m)) {
    bottom = -huge
    top = huge
  }
  Chispita_setCameraBounds(left, bottom, right, top)
}

// Camera view
function chispita_view_x() {
  return Camera.x + Camera.shake_x
}

function chispita_view_y() {
  return Camera.y + Camera.shake_y
}

function Chispita_screenToWorld(x, y) {
  var p = {}
  p.x = x / Camera.zoom + chispita_view_x()
  p.y = y / Camera.zoom + chispita_view_y()
  return p
}

function Chispita_worldToScreen(x, y) {
  var p = {}
  p.x = (x - chispita_view_x()) * Camera.zoom
  p.y = (y - chispita_view_y()) * Camera.zoom
  return p
}

var chispita_drawables = []
var chispita_fps = 60
var chispita_last_draw_time = 0

function chispita_add_drawable(o) {
  chispita_drawables.push(o)
  var i = chispita_drawables.length - 1
  while (i > 0) {
    var before = chispita_drawables[i - 1]
    if (before.layer <= o.layer) break
    chispita_drawables[i] = before
    i -= 1
  }
  chispita_drawables[i] = o
}

function Chispita_setLayer(o, layer) {
  var index = chispita_drawables.indexOf(o)
  if (index < 0) {
    chispita_warn("Chispita_setLayer: that object isn't being drawn (it may have been removed).")
    return
  }
  chispita_drawables.splice(index, 1)
  o.layer = layer
  chispita_add_drawable(o)
}

function chispita_screen_x(o, x) {
  if (o.ui) return x
  return (x - chispita_view_x() * o.parallax) * Camera.zoom
}

function chispita_screen_y(o, y) {
  if (o.ui) return y
  return (y - chispita_view_y() * o.parallax) * Camera.zoom
}

function chispita_screen_size(o, size) {
  if (o.ui) return size
  return size * Camera.zoom
}

function chispita_world_x(x) {
  return (x - chispita_view_x()) * Camera.zoom
}

function chispita_world_y(y) {
  return (y - chispita_view_y()) * Camera.zoom
}

function chispita_measure_fps() {
  var now = system.time()
  var dt = now - chispita_last_draw_time
  chispita_last_draw_time = now
  if (dt > 0 && dt < 1000) {
    chispita_fps = chispita_fps * 0.95 + (1000 / dt) * 0.05
  }
}

function chispita_depth_key(o) {
  if (o.hit_box_shape == "circle") return o.y - o.radius
  return o.y - o.height / 2
}

function chispita_sort_depth() {
  var list = chispita_drawables
  for (var i = 1; i <= list.length - 1; i++) {
    var o = list[i]
    if (!o.depth_sort) continue
    var key = chispita_depth_key(o)
    var j = i - 1
    while (j >= 0) {
      var before = list[j]
      if (!before.depth_sort || before.layer != o.layer) break
      if (chispita_depth_key(before) >= key) break
      list[j + 1] = before
      j -= 1
    }
    list[j + 1] = o
  }
}

function chispita_draw_all() {
  chispita_measure_fps()
  chispita_sort_depth()
  if (chispita_background) screen.clear(chispita_background)
  if (chispita_debug_mode && Debug.grid) chispita_debug_draw_grid()

  for (var o of chispita_drawables) {
    if (o.visible) o.draw()
  }

  if (chispita_debug_mode) chispita_draw_debug()
}
