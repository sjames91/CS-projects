local min, max, pow = math.min, math.max, math.pow
local function sind(a) return math.sin(a * math.pi / 180) end
local function cosd(a) return math.cos(a * math.pi / 180) end

-- Create camera object
Camera = {
  x = 0,
  y = 0,
  target = false,
  smooth = 1,
  zoom = 1,
  bounds = false,
  deadzone_x = 0,
  deadzone_y = 0,
  look_ahead_x = 0,
  look_ahead_y = 0,
  shake_amount = 0,
  shake_time = 0,
  shake_total = 0,
  shake_fade = true,
  shake_x = 0,
  shake_y = 0,
}

function chispita_camera_aim(position, target, zone)
  if zone <= 0 then return target end
  if target > position + zone then return target - zone end
  if target < position - zone then return target + zone end
  return position
end

-- Update camera
function chispita_camera_update(dt)
  if Camera.target then
    local tx = Camera.target.x + Camera.target.vx * Camera.look_ahead_x
    local ty = Camera.target.y + Camera.target.vy * Camera.look_ahead_y
    tx = chispita_camera_aim(Camera.x, tx, Camera.deadzone_x)
    ty = chispita_camera_aim(Camera.y, ty, Camera.deadzone_y)
    local ease = Camera.smooth
    if ease < 1 and dt ~= 1 / 60 then ease = 1 - pow(1 - ease, dt * 60) end
    Camera.x = Camera.x + (tx - Camera.x) * ease
    Camera.y = Camera.y + (ty - Camera.y) * ease
  end

-- Clamp camera bounds
  if Camera.bounds then
    chispita_camera_clamp()
  end

-- Camera shake
  Camera.shake_x = 0
  Camera.shake_y = 0
  if Camera.shake_time > 0 then
    Camera.shake_time = Camera.shake_time - dt
    local amount = Camera.shake_amount
    if Camera.shake_fade and Camera.shake_total > 0 then
      amount = amount * max(0, Camera.shake_time / Camera.shake_total)
    end
    local angle = random:next() * 360
    Camera.shake_x = cosd(angle) * amount
    Camera.shake_y = sind(angle) * amount
  end
end

-- Camera clamping math
function chispita_camera_clamp()
  local b = Camera.bounds
  local half_w = screen.width / 2 / Camera.zoom
  local half_h = screen.height / 2 / Camera.zoom

  if b.right - b.left < half_w * 2 then
    Camera.x = (b.left + b.right) / 2
  else
    Camera.x = max(b.left + half_w, min(Camera.x, b.right - half_w))
  end

  if b.top - b.bottom < half_h * 2 then
    Camera.y = (b.bottom + b.top) / 2
  else
    Camera.y = max(b.bottom + half_h, min(Camera.y, b.top - half_h))
  end
end

function Chispita_setTarget(sprite)
  Camera.target = sprite
end

function Chispita_cameraShake(amount, seconds)
  Camera.shake_amount = amount
  Camera.shake_time = seconds
  Camera.shake_total = seconds
end

function Chispita_setCameraBounds(left, bottom, right, top)
  if left >= right or bottom >= top then
    chispita_warn("Chispita_setCameraBounds needs left < right and bottom < top.")
    return
  end
  local b = {}
  b.left = left
  b.bottom = bottom
  b.right = right
  b.top = top
  Camera.bounds = b
end

function Chispita_limitCameraToMap(m)
  if not m.map then
    chispita_warn("Chispita_limitCameraToMap needs a map from Chispita_addMap.")
    return
  end
  local l = chispita_map_layout(m)
  if not l then return end
  local huge = 1000000000
  local left = l.left
  local right = l.left + l.width
  local bottom = l.bottom
  local top = l.bottom + l.height
  if chispita_tiles_across(m) then
    left = -huge
    right = huge
  end
  if chispita_tiles_down(m) then
    bottom = -huge
    top = huge
  end
  Chispita_setCameraBounds(left, bottom, right, top)
end

-- Camera view
function chispita_view_x()
  return Camera.x + Camera.shake_x
end

function chispita_view_y()
  return Camera.y + Camera.shake_y
end

function Chispita_screenToWorld(x, y)
  local p = {}
  p.x = x / Camera.zoom + chispita_view_x()
  p.y = y / Camera.zoom + chispita_view_y()
  return p
end

function Chispita_worldToScreen(x, y)
  local p = {}
  p.x = (x - chispita_view_x()) * Camera.zoom
  p.y = (y - chispita_view_y()) * Camera.zoom
  return p
end

chispita_drawables = {}
chispita_fps = 60
chispita_last_draw_time = 0

-- Adds o after everything on its layer or lower, before higher layers.
function chispita_add_drawable(o)
  table.insert(chispita_drawables, o)
  local i = #chispita_drawables
  while i > 1 do
    local before = chispita_drawables[i - 1]
    if before.layer <= o.layer then break end
    chispita_drawables[i] = before
    i = i - 1
  end
  chispita_drawables[i] = o
end

function Chispita_setLayer(o, layer)
  local index = false
  for i, d in ipairs(chispita_drawables) do
    if d == o then index = i break end
  end
  if not index then
    chispita_warn("Chispita_setLayer: that object isn't being drawn (it may have been removed).")
    return
  end
  table.remove(chispita_drawables, index)
  o.layer = layer
  chispita_add_drawable(o)
end

function chispita_screen_x(o, x)
  if o.ui then return x end
  return (x - chispita_view_x() * o.parallax) * Camera.zoom
end

function chispita_screen_y(o, y)
  if o.ui then return y end
  return (y - chispita_view_y() * o.parallax) * Camera.zoom
end

function chispita_screen_size(o, size)
  if o.ui then return size end
  return size * Camera.zoom
end

function chispita_world_x(x)
  return (x - chispita_view_x()) * Camera.zoom
end

function chispita_world_y(y)
  return (y - chispita_view_y()) * Camera.zoom
end

function chispita_measure_fps()
  local now = system:time()
  local dt = now - chispita_last_draw_time
  chispita_last_draw_time = now
  if dt > 0 and dt < 1000 then
    chispita_fps = chispita_fps * 0.95 + (1000 / dt) * 0.05
  end
end

function chispita_depth_key(o)
  if o.hit_box_shape == "circle" then return o.y - o.radius end
  return o.y - o.height / 2
end

-- Within a layer, depth-sorted things lower on the screen draw in front.
function chispita_sort_depth()
  local list = chispita_drawables
  for i = 2, #list do
    local o = list[i]
    if o.depth_sort then
      local key = chispita_depth_key(o)
      local j = i - 1
      while j >= 1 do
        local before = list[j]
        if not before.depth_sort or before.layer ~= o.layer then break end
        if chispita_depth_key(before) >= key then break end
        list[j + 1] = before
        j = j - 1
      end
      list[j + 1] = o
    end
  end
end

function chispita_draw_all()
  chispita_measure_fps()
  chispita_sort_depth()
  if chispita_background then screen:clear(chispita_background) end
  if chispita_debug_mode and Debug.grid then chispita_debug_draw_grid() end

  for _, o in ipairs(chispita_drawables) do
    if o.visible then o.draw() end
  end

  if chispita_debug_mode then chispita_draw_debug() end
end
