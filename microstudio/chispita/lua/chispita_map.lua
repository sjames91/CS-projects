local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

chispita_maps = {}

-- Add maps
function Chispita_addMap(name, x, y, physics, cell_size)
  local m = {}
  m.id = chispita_next_id
  chispita_next_id = chispita_next_id + 1
  m.name = name
  m.map = maps[name]
  if not m.map then chispita_warn("no map named " .. tostring(name) .. ". Check the name in the map editor.") end
  if physics and physics ~= physics_on and physics ~= physics_off then
    chispita_warn("Chispita_addMap: physics should be physics_on or physics_off, not " .. tostring(physics) .. ". Using physics_on.")
  end
  m.x = x or 0
  m.y = y or 0
  m.cell_size = cell_size
  m.physics = physics ~= physics_off
  m.active = true
  m.visible = true
  m.parallax = 1
  m.tile = false
  m.tile_across = true
  m.tile_down = true
  m.ui = false
  m.bounciness = 0.3
  m.grip = 0
  m.callback = false     -- a sprite touched a tile: callback(sprite, tile)
  m.hollow = {}
  m.one_way = {}
  m.kinds = {}           -- remembers each cell value's kind so it's only worked out once
  m.layout = false
  m.cloned = false
  if m.physics then m.layer = 0 else m.layer = -1 end

  m.tile_body = {}
  m.tile_body.shape = {}
  m.tile_body.fixed = true
  m.tile_body.solid = true
  m.tile_body.kinematic = false
  m.tile_body.x = 0      -- tiles never move; these just keep the push maths happy
  m.tile_body.y = 0
  m.tile_body.vx = 0
  m.tile_body.vy = 0

  m.draw = function()
    chispita_draw_map(m)
  end

  table.insert(chispita_maps, m)
  chispita_add_drawable(m)
  return m
end

--World Size
function chispita_map_layout(m)
  if not m.map then return false end
  local l = m.layout
  if l and l.x == m.x and l.y == m.y and l.cell_size == m.cell_size and l.map == m.map then
    return l
  end

  l = {}
  l.x = m.x
  l.y = m.y
  l.cell_size = m.cell_size
  l.map = m.map
  l.cw = m.cell_size
  if not l.cw then l.cw = m.map.block_width end
  l.ch = l.cw * m.map.block_height / m.map.block_width
  l.width = m.map.width * l.cw
  l.height = m.map.height * l.ch
  l.left = m.x - l.width / 2
  l.bottom = m.y - l.height / 2
  m.layout = l
  return l
end

--Tile flags. A cell is "name" or "name:column,row" (a tile from a tile sheet).
function chispita_tile_name(cell)
  if not cell then return "" end
  return cell:match("^[^:]*")
end

function chispita_set_tile_rule(m, tile_name, hollow, one_way)
  if not m.hollow then
    chispita_warn("tile rules need a map from Chispita_addMap.")
    return
  end
  m.hollow[tile_name] = hollow
  m.one_way[tile_name] = one_way
  m.kinds = {}   -- forget remembered kinds, the rules changed
end

function Chispita_setHollow(m, tile_name)
  chispita_set_tile_rule(m, tile_name, true, false)
end

function Chispita_setSolid(m, tile_name)
  chispita_set_tile_rule(m, tile_name, false, false)
end

function Chispita_setOneWay(m, tile_name)
  chispita_set_tile_rule(m, tile_name, false, true)
end

function chispita_tile_kind(m, cell)
  if not cell then return "empty" end
  local kind = m.kinds[cell]
  if kind then return kind end

  local name = chispita_tile_name(cell)
  if m.hollow[name] then
    kind = "empty"
  elseif m.one_way[name] then
    kind = "one_way"
  else
    kind = "solid"
  end
  m.kinds[cell] = kind
  return kind
end

function chispita_tiles_across(m)
  return m.tile and m.tile_across
end

function chispita_tiles_down(m)
  return m.tile and m.tile_down
end

function chispita_wrap_x(m, cx)
  if not chispita_tiles_across(m) then return cx end
  local w = m.map.width
  return (cx % w + w) % w
end

function chispita_wrap_y(m, cy)
  if not chispita_tiles_down(m) then return cy end
  local h = m.map.height
  return (cy % h + h) % h
end

-- microStudio maps give back 0 for an empty cell. In Lua 0 counts as
-- true, so it's turned into nil here.
function chispita_cell(map, cx, cy)
  local cell = map:get(cx, cy)
  if cell == 0 then return nil end
  return cell
end

function chispita_map_get(m, cx, cy)
  return chispita_cell(m.map, chispita_wrap_x(m, cx), chispita_wrap_y(m, cy))
end

function chispita_tile_is_solid(m, cx, cy)
  return chispita_tile_kind(m, chispita_map_get(m, cx, cy)) == "solid"
end

function chispita_make_tile(m, l, cx, cy, cell)
  local tile = {}
  tile.map = m
  tile.cell = cell
  tile.name = chispita_tile_name(cell)
  tile.cx = chispita_wrap_x(m, cx)
  tile.cy = chispita_wrap_y(m, cy)
  tile.x = l.left + (cx + 0.5) * l.cw
  tile.y = l.bottom + (cy + 0.5) * l.ch
  return tile
end

function chispita_tile_image_part(m, cell)
  local column, row = cell:match(":(%d+),(%d+)$")
  if not column then return false end
  local part = {}
  part.w = m.map.block_width
  part.h = m.map.block_height
  part.x = tonumber(column) * part.w
  part.y = tonumber(row) * part.h
  return part
end

function chispita_skip_internal_edge(m, body, hit)
  if not chispita_tile_is_solid(m, body.cx - hit.nx, body.cy - hit.ny) then return hit end
  if hit.nx ~= 0 then
    chispita_use_y_axis(hit)
  else
    chispita_use_x_axis(hit)
  end
  if chispita_tile_is_solid(m, body.cx - hit.nx, body.cy - hit.ny) then return false end
  return hit
end

function chispita_record_tile_touch(s, m, l, cx, cy, cell)
  local key = m.id .. ":" .. cx .. "," .. cy
  if s.tile_contacts[key] then return end
  s.tile_contacts[key] = chispita_make_tile(m, l, cx, cy, cell)
  s.tile_touched = true
end

function chispita_collide_sprite_map(s, m, l)
  local wants_touch = (s.trigger and s.on_tile) or m.callback
  if not (chispita_movable(s) or wants_touch) then return end
  for index = 0, chispita_shape_count(s) - 1 do
    chispita_collide_shape_map(s, m, l, index, wants_touch)
  end
end

function chispita_collide_shape_map(s, m, l, index, wants_touch)
  local shape = chispita_sprite_shape(s, index)
  local x0 = floor((shape.x - shape.ex - l.left) / l.cw)
  local x1 = floor((shape.x + shape.ex - l.left) / l.cw)
  local y0 = floor((shape.y - shape.ey - l.bottom) / l.ch)
  local y1 = floor((shape.y + shape.ey - l.bottom) / l.ch)
  if not chispita_tiles_across(m) then
    x0 = max(0, x0)
    x1 = min(m.map.width - 1, x1)
  end
  if not chispita_tiles_down(m) then
    y0 = max(0, y0)
    y1 = min(m.map.height - 1, y1)
  end
  local body = m.tile_body
  body.bounciness = m.bounciness
  body.grip = m.grip

  for cy = y0, y1 do
    for cx = x0, x1 do
      local cell = chispita_map_get(m, cx, cy)
      local kind = chispita_tile_kind(m, cell)
      if kind ~= "empty" then
        body.cx = cx
        body.cy = cy
        chispita_set_shape(body.shape, "rect", l.left + (cx + 0.5) * l.cw, l.bottom + (cy + 0.5) * l.ch, l.cw, l.ch, 0)

        local hit = chispita_test(chispita_sprite_shape(s, index), body.shape)
        if hit and hit.ox and kind == "solid" then
          hit = chispita_skip_internal_edge(m, body, hit)
        end
        if hit then
          if wants_touch then chispita_record_tile_touch(s, m, l, cx, cy, cell) end
          if kind == "one_way" then
            chispita_try_one_way(s, body, body.shape.y + body.shape.hh)
          else
            chispita_resolve(s, body, hit)
          end
        end
      end
    end
  end
end

function chispita_ray_map(m, x1, y1, dx, dy, limit)
  local l = chispita_map_layout(m)
  if not l then return false end
  local gx = (x1 - l.left) / l.cw
  local gy = (y1 - l.bottom) / l.ch
  local gdx = dx / l.cw
  local gdy = dy / l.ch
  local cx = floor(gx)
  local cy = floor(gy)
  local huge = 1000000000

  local step_x = 0
  local next_x = huge
  local delta_x = huge
  if gdx > 0 then
    step_x = 1
    next_x = (cx + 1 - gx) / gdx
    delta_x = 1 / gdx
  elseif gdx < 0 then
    step_x = -1
    next_x = (gx - cx) / -gdx
    delta_x = 1 / -gdx
  end

  local step_y = 0
  local next_y = huge
  local delta_y = huge
  if gdy > 0 then
    step_y = 1
    next_y = (cy + 1 - gy) / gdy
    delta_y = 1 / gdy
  elseif gdy < 0 then
    step_y = -1
    next_y = (gy - cy) / -gdy
    delta_y = 1 / -gdy
  end

  local across = chispita_tiles_across(m)
  local down = chispita_tiles_down(m)
  local t = 0
  while t <= min(1, limit) do
    local inside_x = across or (cx >= 0 and cx < m.map.width)
    local inside_y = down or (cy >= 0 and cy < m.map.height)
    if inside_x and inside_y then
      local cell = chispita_map_get(m, cx, cy)
      if chispita_tile_kind(m, cell) == "solid" then
        local found = {}
        found.t = t
        found.tile = chispita_make_tile(m, l, cx, cy, cell)
        return found
      end
    end
    if next_x < next_y then
      cx = cx + step_x
      t = next_x
      next_x = next_x + delta_x
    else
      cy = cy + step_y
      t = next_y
      next_y = next_y + delta_y
    end
  end
  return false
end

function chispita_check_map_collisions()
  for _, m in ipairs(chispita_maps) do
    if m.map and m.physics and m.active then
      if m.parallax ~= 1 then
        chispita_warn("map " .. m.name .. " is solid but has parallax " .. m.parallax .. ". Its tiles are drawn moved but collide where the map really is. Use physics_off for parallax backgrounds.")
      end
      local l = chispita_map_layout(m)
      for _, s in ipairs(chispita_sprites) do
        if s.active and s.physics then
          chispita_collide_sprite_map(s, m, l)
        end
      end
    end
  end
end

-- The cell value at a world position (nil when empty).
function Chispita_cellAt(m, x, y)
  if not m.map then
    chispita_warn("Chispita_cellAt needs a map from Chispita_addMap.")
    return nil
  end
  local l = chispita_map_layout(m)
  if not l then return nil end
  return chispita_map_get(m, floor((x - l.left) / l.cw), floor((y - l.bottom) / l.ch))
end

function Chispita_spawnFromMap(m, tile_name)
  local list = {}
  if not m.map then
    chispita_warn("Chispita_spawnFromMap needs a map from Chispita_addMap.")
    return list
  end
  local l = chispita_map_layout(m)
  if not l then return list end

  if not m.cloned then
    m.map = m.map:clone()
    m.cloned = true
    l = chispita_map_layout(m)
  end

  for cy = 0, m.map.height - 1 do
    for cx = 0, m.map.width - 1 do
      local cell = chispita_cell(m.map, cx, cy)
      if cell and (cell == tile_name or chispita_tile_name(cell) == tile_name) then
        m.map:set(cx, cy, 0)
        local x = l.left + (cx + 0.5) * l.cw
        local y = l.bottom + (cy + 0.5) * l.ch
        local s = Chispita_addRect(x, y, l.cw, l.ch)
        s.image = chispita_tile_name(cell)
        s.image_part = chispita_tile_image_part(m, cell)
        table.insert(list, s)
      end
    end
  end
  m.map:update()
  return list
end

function chispita_draw_map(m)
  local l = chispita_map_layout(m)
  if not l then return end
  local x = chispita_screen_x(m, m.x)
  local y = chispita_screen_y(m, m.y)
  local w = chispita_screen_size(m, l.width)
  local h = chispita_screen_size(m, l.height)
  local across = chispita_tiles_across(m)
  local down = chispita_tiles_down(m)
  if not across and (x + w / 2 < -screen.width / 2 or x - w / 2 > screen.width / 2) then return end
  if not down and (y + h / 2 < -screen.height / 2 or y - h / 2 > screen.height / 2) then return end
  if not m.tile then
    screen:drawMap(m.map, x, y, w, h)
    return
  end
  local copies = 1
  if across then copies = copies * (ceil(screen.width / w) + 1) end
  if down then copies = copies * (ceil(screen.height / h) + 1) end
  if copies > chispita_max_map_copies then
    chispita_warn("map " .. m.name .. " is too small to tile at this zoom (" .. copies .. " copies). Drawing it once. Use a bigger map or raise chispita_max_map_copies.")
    screen:drawMap(m.map, x, y, w, h)
    return
  end
  local draw_w = w
  local draw_h = h
  if across then
    x = x - floor((x + screen.width / 2 + w / 2) / w) * w
    draw_w = draw_w + 1
  end
  if down then
    y = y - floor((y + screen.height / 2 + h / 2) / h) * h
    draw_h = draw_h + 1
  end
  local first_y = y
  while x - w / 2 < screen.width / 2 do
    y = first_y
    while y - h / 2 < screen.height / 2 do
      screen:drawMap(m.map, x, y, draw_w, draw_h)
      if not down then break end
      y = y + h
    end
    if not across then break end
    x = x + w
  end
end
