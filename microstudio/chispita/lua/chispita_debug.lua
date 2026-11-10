local min, max, floor = math.min, math.max, math.floor

Debug = {
  panel = true,
  panel_open = true,
  grid = true,
  grid_size = 32,
  hit_boxes = true,
  hurt_boxes = true,
  velocity = false,
  contacts = false,
  labels = false,
  map_cells = false,
  camera = false,
  mouse = true,
  info = true,
  drag = true,
  slow_motion = false,
  slow_factor = 4,
  paused = false,
}

chispita_debug_rows = {}
chispita_step_requested = false
chispita_slow_counter = 0
chispita_dragging = false
chispita_drag_dx = 0
chispita_drag_dy = 0
chispita_throw_x = 0
chispita_throw_y = 0
chispita_watches = {}
chispita_watch_order = {}

function chispita_debug_reset()
  chispita_dragging = false
  chispita_step_requested = false
  chispita_slow_counter = 0
  chispita_throw_x = 0
  chispita_throw_y = 0
  chispita_watches = {}
  chispita_watch_order = {}
end

chispita_debug_text_color = "rgb(255,255,255)"
chispita_debug_size = 5

-- Watch values
function Chispita_watch(label, value)
  if chispita_watches[label] == nil then
    local listed = false
    for _, l in ipairs(chispita_watch_order) do
      if l == label then listed = true end
    end
    if not listed then table.insert(chispita_watch_order, label) end
  end
  chispita_watches[label] = value
end

function Chispita_toggleDebug(name)
  if not name then
    chispita_debug_mode = not chispita_debug_mode
  else
    Debug[name] = not Debug[name]
  end
end

function Chispita_mouseOnDebug()
  if not chispita_debug_mode then return false end
  if chispita_dragging then return true end
  return chispita_debug_row_at(mouse.x, mouse.y) ~= "none"
end

-- Debug panel
function chispita_debug_add_row(label, field)
  local row = {}
  row.label = label
  row.field = field
  table.insert(chispita_debug_rows, row)
end

function chispita_debug_make_rows()
  if #chispita_debug_rows > 0 then return end
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
end

function chispita_debug_panel_layout()
  local l = {}
  l.width = 56
  l.row_h = 7
  l.left = screen.width / 2 - 2 - l.width
  l.top = screen.height / 2 - 2
  return l
end

-- Header. Gives back "none", "header", or the number of the row (1 = first).
function chispita_debug_row_at(x, y)
  if not Debug.panel then return "none" end
  local l = chispita_debug_panel_layout()
  if x < l.left or x > l.left + l.width then return "none" end
  local from_top = l.top - y
  if from_top < 0 then return "none" end
  local row = floor(from_top / l.row_h)
  if row == 0 then return "header" end
  if not Debug.panel_open then return "none" end
  if row <= #chispita_debug_rows then return row end
  return "none"
end


-- Update debug
function chispita_debug_update()
  chispita_debug_make_rows()

  local row = chispita_debug_row_at(mouse.x, mouse.y)
  if mouse.press == 1 and row ~= "none" then
    if row == "header" then
      Debug.panel_open = not Debug.panel_open
    else
      local field = chispita_debug_rows[row].field
      if field == "step" then
        Debug.paused = true
        chispita_step_requested = true
      else
        Debug[field] = not Debug[field]
      end
    end
  end

  chispita_debug_update_drag(row == "none")
end

function chispita_debug_update_drag(mouse_is_free)
  local world = Chispita_screenToWorld(mouse.x, mouse.y)

  if mouse.press == 1 and mouse_is_free and Debug.drag then
    chispita_dragging = chispita_debug_sprite_at(world.x, world.y)
    if chispita_dragging then
      chispita_drag_dx = chispita_dragging.x - world.x
      chispita_drag_dy = chispita_dragging.y - world.y
    end
  end

  if not chispita_dragging then return end
  local s = chispita_dragging

  if mouse.pressed == 1 then
    local new_x = world.x + chispita_drag_dx
    local new_y = world.y + chispita_drag_dy
    chispita_throw_x = (new_x - s.x) * 60
    chispita_throw_y = (new_y - s.y) * 60
    s.x = new_x
    s.y = new_y
    s.old_x = new_x
    s.old_y = new_y
    s.vx = 0
    s.vy = 0
  else

    if not s.fixed then
      s.vx = chispita_throw_x
      s.vy = chispita_throw_y
    end
    chispita_dragging = false
  end
end

function chispita_debug_should_step()
  if Debug.paused then
    if chispita_step_requested then
      chispita_step_requested = false
      return true
    end
    return false
  end
  if Debug.slow_motion then
    chispita_slow_counter = chispita_slow_counter + 1
    return chispita_slow_counter % Debug.slow_factor == 0
  end
  return true
end

function chispita_debug_sprite_at(x, y)
  for i = #chispita_drawables, 1, -1 do
    local o = chispita_drawables[i]
    if o.hit_box_shape and o.active and o.visible and not o.ui then
      if Chispita_pointIn(o, x, y) then return o end
    end
  end
  return false
end

-- Drawing Debug
function chispita_debug_text(text, x, y, color)
  screen:setDrawAnchor(-1, 0)
  screen:drawText(text, x + 0.5, y - 0.5, chispita_debug_size, "rgb(0,0,0)")
  screen:drawText(text, x, y, chispita_debug_size, color)
  screen:setDrawAnchor(0, 0)
end

function chispita_fmt(n)
  return floor(n * 100 + 0.5) / 100
end

function chispita_debug_outline(shape, color)
  local x = chispita_world_x(shape.x)
  local y = chispita_world_y(shape.y)
  local w = shape.hw * 2 * Camera.zoom
  local h = shape.hh * 2 * Camera.zoom
  if shape.kind == "circle" then
    screen:drawRound(x, y, w, h, color)
  elseif shape.kind == "capsule" then
    if shape.angle ~= 0 then screen:setDrawRotation(shape.angle) end
    screen:drawRoundRect(x, y, w, h, w / 2, color)
    if shape.angle ~= 0 then screen:setDrawRotation(0) end
  elseif shape.angle ~= 0 then
    local ux = shape.hw * shape.cos
    local uy = shape.hw * shape.sin
    local vx = -shape.hh * shape.sin
    local vy = shape.hh * shape.cos
    screen:drawPolygon(
      chispita_world_x(shape.x - ux - vx), chispita_world_y(shape.y - uy - vy),
      chispita_world_x(shape.x + ux - vx), chispita_world_y(shape.y + uy - vy),
      chispita_world_x(shape.x + ux + vx), chispita_world_y(shape.y + uy + vy),
      chispita_world_x(shape.x - ux + vx), chispita_world_y(shape.y - uy + vy),
      color)
  else
    screen:drawRect(x, y, w, h, color)
  end
end

function chispita_debug_box_color(s)
  if not s.solid then return "rgb(255,230,0)" end
  if s.fixed or s.kinematic then return "rgb(80,160,255)" end
  return "rgb(0,255,0)"
end

-- Draws tools
function chispita_debug_draw_grid()
  local size = Debug.grid_size
  local half_w = screen.width / 2 / Camera.zoom
  local half_h = screen.height / 2 / Camera.zoom
  local left = chispita_view_x() - half_w
  local right = chispita_view_x() + half_w
  local bottom = chispita_view_y() - half_h
  local top = chispita_view_y() + half_h
  local color = "rgb(60,60,70)"

  screen:setLineWidth(1)
  local x = floor(left / size) * size
  while x <= right do
    screen:drawLine(chispita_world_x(x), -screen.height / 2, chispita_world_x(x), screen.height / 2, color)
    x = x + size
  end
  local y = floor(bottom / size) * size
  while y <= top do
    screen:drawLine(-screen.width / 2, chispita_world_y(y), screen.width / 2, chispita_world_y(y), color)
    y = y + size
  end

  screen:drawLine(chispita_world_x(0), -screen.height / 2, chispita_world_x(0), screen.height / 2, "rgb(0,140,0)")
  screen:drawLine(-screen.width / 2, chispita_world_y(0), screen.width / 2, chispita_world_y(0), "rgb(160,0,0)")
end

function chispita_debug_draw_map_cells()
  local half_w = screen.width / 2 / Camera.zoom
  local half_h = screen.height / 2 / Camera.zoom
  for _, m in ipairs(chispita_maps) do
    if m.map and m.physics and m.active then
      local l = chispita_map_layout(m)
      local x0 = floor((chispita_view_x() - half_w - l.left) / l.cw)
      local x1 = floor((chispita_view_x() + half_w - l.left) / l.cw)
      local y0 = floor((chispita_view_y() - half_h - l.bottom) / l.ch)
      local y1 = floor((chispita_view_y() + half_h - l.bottom) / l.ch)
      if not chispita_tiles_across(m) then
        x0 = max(0, x0)
        x1 = min(m.map.width - 1, x1)
      end
      if not chispita_tiles_down(m) then
        y0 = max(0, y0)
        y1 = min(m.map.height - 1, y1)
      end

      for cy = y0, y1 do
        for cx = x0, x1 do
          local kind = chispita_tile_kind(m, chispita_map_get(m, cx, cy))
          if kind ~= "empty" then
            local x = chispita_world_x(l.left + (cx + 0.5) * l.cw)
            local y = chispita_world_y(l.bottom + (cy + 0.5) * l.ch)
            local w = l.cw * Camera.zoom
            local h = l.ch * Camera.zoom
            if kind == "solid" then
              screen:drawRect(x, y, w, h, "rgb(255,140,0)")
            else
              screen:drawLine(x - w / 2, y + h / 2, x + w / 2, y + h / 2, "rgb(0,220,255)")
            end
          end
        end
      end
    end
  end
end

function chispita_debug_draw_camera()
  local b = Camera.bounds
  if b then
    local x = chispita_world_x((b.left + b.right) / 2)
    local y = chispita_world_y((b.bottom + b.top) / 2)
    screen:drawRect(x, y, (b.right - b.left) * Camera.zoom, (b.top - b.bottom) * Camera.zoom, "rgb(255,0,255)")
  end

  screen:drawLine(-3, 0, 3, 0, "rgb(255,0,255)")
  screen:drawLine(0, -3, 0, 3, "rgb(255,0,255)")
  if Camera.target then
    local tx = chispita_world_x(Camera.target.x)
    local ty = chispita_world_y(Camera.target.y)
    screen:drawLine(0, 0, tx, ty, "rgb(255,0,255)")
  end
end

function chispita_debug_draw_sprite(s)
  local shape = chispita_hit_shape(s)
  local x = chispita_world_x(shape.x)
  local y = chispita_world_y(shape.y)

  if Debug.hit_boxes and s.physics then
    chispita_debug_outline(shape, chispita_debug_box_color(s))
    if s.hit_parts then
      for _, part in ipairs(s.hit_parts) do
        chispita_debug_outline(chispita_part_shape(s, part), chispita_debug_box_color(s))
      end
    end
  end
  if Debug.hurt_boxes and s.hurt_box then
    chispita_debug_outline(chispita_hurt_shape(s), "rgb(255,0,0)")
    if s.hurt_parts then
      for _, part in ipairs(s.hurt_parts) do
        chispita_debug_outline(chispita_part_shape(s, part), "rgb(255,0,0)")
      end
    end
  end

  if Debug.velocity and (s.vx ~= 0 or s.vy ~= 0) then
    local end_x = chispita_world_x(shape.x + s.vx * 0.1)
    local end_y = chispita_world_y(shape.y + s.vy * 0.1)
    screen:drawLine(x, y, end_x, end_y, "rgb(255,80,200)")
    screen:fillRound(end_x, end_y, 2, 2, "rgb(255,80,200)")
  end

  if Debug.contacts then
    local bottom = y - shape.hh * Camera.zoom
    if s.grounded then
      screen:fillRect(x, bottom - 1, shape.hw * 2 * Camera.zoom, 1, "rgb(255,255,255)")
    end
    if s.trigger then
      for id, other in pairs(s.contacts) do
        screen:drawLine(x, y, chispita_world_x(other.x), chispita_world_y(other.y), "rgb(255,255,255)")
      end
    end
  end

  if Debug.labels then
    local label = "#" .. s.id

    if s.sprite_name then label = label .. " " .. s.sprite_name end
    chispita_debug_text(label, x - shape.hw * Camera.zoom, y + shape.hh * Camera.zoom + 4, chispita_debug_text_color)
  end
end

function chispita_debug_draw_mouse()
  local mx = mouse.x
  local my = mouse.y
  local world = Chispita_screenToWorld(mx, my)
  local color = "rgb(255,255,0)"

  -- Crosshair
  screen:setAlpha(0.4)
  screen:drawLine(-screen.width / 2, my, screen.width / 2, my, color)
  screen:drawLine(mx, -screen.height / 2, mx, screen.height / 2, color)
  screen:setAlpha(1)

  local lines = {}
  table.insert(lines, chispita_fmt(world.x) .. ", " .. chispita_fmt(world.y))
  for _, m in ipairs(chispita_maps) do
    if m.map and m.physics then
      local cell = Chispita_cellAt(m, world.x, world.y)
      if cell then
        local l = chispita_map_layout(m)
        local cx = chispita_wrap_x(m, floor((world.x - l.left) / l.cw))
        local cy = chispita_wrap_y(m, floor((world.y - l.bottom) / l.ch))
        table.insert(lines, m.name .. " [" .. cx .. "," .. cy .. "] " .. cell .. " (" .. chispita_tile_kind(m, cell) .. ")")
      end
    end
  end

  local text_x = mx + 4
  if text_x > screen.width / 2 - 70 then text_x = mx - 70 end
  local text_y = my + 6
  if text_y > screen.height / 2 - 6 * #lines then text_y = my - 6 end
  for i, line in ipairs(lines) do
    chispita_debug_text(line, text_x, text_y - (i - 1) * 6, color)
  end

  local s = chispita_debug_sprite_at(world.x, world.y)
  if s then
    chispita_debug_outline(chispita_hit_shape(s), "rgb(255,255,0)")
    chispita_debug_draw_inspector(s)
  end
end

function chispita_debug_draw_inspector(s)
  local lines = {}
  local title = "#" .. s.id .. " " .. s.hit_box_shape

  if s.sprite_name then title = title .. " " .. s.sprite_name end
  table.insert(lines, title)
  table.insert(lines, "x, y: " .. chispita_fmt(s.x) .. ", " .. chispita_fmt(s.y))
  table.insert(lines, "vx, vy: " .. chispita_fmt(s.vx) .. ", " .. chispita_fmt(s.vy))
  table.insert(lines, "grounded: " .. tostring(s.grounded) .. "  group: " .. s.group .. "  layer: " .. s.layer)
  table.insert(lines, "mass: " .. s.mass .. "  grip: " .. s.grip .. "  bounce: " .. s.bounciness)

  local flags = ""
  if s.fixed then flags = flags .. "fixed " end
  if s.kinematic then flags = flags .. "kinematic " end
  if not s.solid then flags = flags .. "not-solid " end
  if s.trigger then flags = flags .. "trigger " end
  if s.one_way then flags = flags .. "one-way " end
  if s.riding then flags = flags .. "riding#" .. s.riding.id .. " " end
  if flags ~= "" then table.insert(lines, flags) end

  if s.animation then table.insert(lines, "animation: " .. s.animation .. " frame " .. s.frame) end

  local left = -screen.width / 2 + 4
  local bottom = -screen.height / 2 + 4
  for i, line in ipairs(lines) do
    chispita_debug_text(line, left, bottom + (#lines - i) * 6, "rgb(255,255,0)")
  end
end

function chispita_debug_draw_info()
  local active = 0
  for _, s in ipairs(chispita_sprites) do
    if s.active then active = active + 1 end
  end

  local state = "running"
  if Debug.paused then
    state = "PAUSED"
  elseif Debug.slow_motion then
    state = "SLOW x" .. Debug.slow_factor
  end

  local lines = {}
  table.insert(lines, "FPS: " .. floor(chispita_fps + 0.5) .. "  " .. state)
  table.insert(lines, "Mode: " .. chispita_mode .. "  Gravity: " .. chispita_gravity .. "  Substeps: " .. chispita_substeps)
  table.insert(lines, "Sprites: " .. active .. " active / " .. #chispita_sprites .. "  Maps: " .. #chispita_maps)
  table.insert(lines, "Particles: " .. chispita_live_particles() .. "  Timers: " .. chispita_live_timers())
  table.insert(lines, "Camera: " .. chispita_fmt(Camera.x) .. ", " .. chispita_fmt(Camera.y) .. "  zoom " .. Camera.zoom)
  for _, label in ipairs(chispita_watch_order) do
    table.insert(lines, label .. ": " .. tostring(chispita_watches[label]))
  end

  local left = -screen.width / 2 + 4
  local top = screen.height / 2 - 5
  for i, line in ipairs(lines) do
    chispita_debug_text(line, left, top - (i - 1) * 6, chispita_debug_text_color)
  end
end

function chispita_debug_draw_panel()
  chispita_debug_make_rows()
  local l = chispita_debug_panel_layout()
  local rows_shown = 0
  if Debug.panel_open then rows_shown = #chispita_debug_rows end
  local height = (rows_shown + 1) * l.row_h

  -- Background
  screen:setAlpha(0.75)
  screen:fillRect(l.left + l.width / 2, l.top - height / 2, l.width, height, "rgb(0,0,0)")
  screen:setAlpha(1)

  local hover = chispita_debug_row_at(mouse.x, mouse.y)
  if hover ~= "none" then
    local index = 0
    if hover ~= "header" then index = hover end
    screen:setAlpha(0.2)
    screen:fillRect(l.left + l.width / 2, l.top - (index + 0.5) * l.row_h, l.width, l.row_h, "rgb(255,255,255)")
    screen:setAlpha(1)
  end

  local fold = "[-]"
  if not Debug.panel_open then fold = "[+]" end
  chispita_debug_text("DEBUG " .. fold, l.left + 3, l.top - l.row_h / 2, "rgb(255,230,0)")
  if not Debug.panel_open then return end

  for i, row in ipairs(chispita_debug_rows) do
    local y = l.top - (i + 0.5) * l.row_h
    chispita_debug_text(row.label, l.left + 3, y, chispita_debug_text_color)

    local box_x = l.left + l.width - 5
    if row.field == "step" then
      chispita_debug_text(">", box_x - 1, y, chispita_debug_text_color)
    else
      screen:drawRect(box_x, y, 4, 4, chispita_debug_text_color)
      if Debug[row.field] then screen:fillRect(box_x, y, 2, 2, "rgb(0,255,0)") end
    end
  end
end

function chispita_draw_debug()
  if Debug.map_cells then chispita_debug_draw_map_cells() end
  if Debug.camera then chispita_debug_draw_camera() end
  for _, s in ipairs(chispita_sprites) do
    if s.active then chispita_debug_draw_sprite(s) end
  end
  if Debug.mouse then chispita_debug_draw_mouse() end
  if Debug.info then chispita_debug_draw_info() end
  if Debug.panel then chispita_debug_draw_panel() end
end
