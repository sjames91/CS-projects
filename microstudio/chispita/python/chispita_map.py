import math

chispita_maps = []

# Add maps
def Chispita_addMap(name=None, x=None, y=None, physics=None, cell_size=None):
  global chispita_next_id
  # Left out, a position is 0, as in microScript.
  if not x: x = 0
  if not y: y = 0
  m = chispita_obj()
  m.id = chispita_next_id
  chispita_next_id += 1
  m.name = name
  m.map = chispita_lookup(maps, name)
  if not m.map: chispita_warn("no map named " + chispita_str(name) + ". Check the name in the map editor.")
  if physics and physics != physics_on and physics != physics_off:
    chispita_warn("Chispita_addMap: physics should be physics_on or physics_off, not " + chispita_str(physics) + ". Using physics_on.")
  m.x = x
  m.y = y
  m.cell_size = cell_size
  m.physics = physics != physics_off
  m.active = 1
  m.visible = 1
  m.parallax = 1
  m.tile = 0
  m.tile_across = 1
  m.tile_down = 1
  m.ui = 0
  m.bounciness = 0.3
  m.grip = 0
  m.callback = 0 # a sprite touched a tile: callback(sprite, tile)
  m.hollow = chispita_obj()
  m.one_way = chispita_obj()
  m.kinds = chispita_obj() # remembers each cell value's kind so it's only worked out once
  m.layout = 0
  m.cloned = 0
  if m.physics: m.layer = 0
  else: m.layer = -1

  m.tile_body = chispita_obj()
  m.tile_body.shape = chispita_obj()
  m.tile_body.fixed = 1
  m.tile_body.solid = 1
  m.tile_body.kinematic = 0
  m.tile_body.x = 0 # tiles never move; these just keep the push maths happy
  m.tile_body.y = 0
  m.tile_body.vx = 0
  m.tile_body.vy = 0

  def draw():
    chispita_draw_map(m)
  m.draw = draw

  chispita_maps.append(m)
  chispita_add_drawable(m)
  return m

#World Size
def chispita_map_layout(m=None):
  if not m.map: return 0
  l = m.layout
  if l and l.x == m.x and l.y == m.y and l.cell_size == m.cell_size and l.map == m.map:
    return l

  l = chispita_obj()
  l.x = m.x
  l.y = m.y
  l.cell_size = m.cell_size
  l.map = m.map
  l.cw = m.cell_size
  if not l.cw: l.cw = m.map.block_width
  l.ch = l.cw * m.map.block_height / m.map.block_width
  l.width = m.map.width * l.cw
  l.height = m.map.height * l.ch
  l.left = m.x - l.width / 2
  l.bottom = m.y - l.height / 2
  m.layout = l
  return l

#Tile flags
def chispita_tile_name(cell=None):
  if not cell: return ""
  return cell.split(":")[0]

def chispita_set_tile_rule(m=None, tile_name=None, hollow=None, one_way=None):
  if not m.hollow:
    chispita_warn("tile rules need a map from Chispita_addMap.")
    return
  m.hollow[tile_name] = hollow
  m.one_way[tile_name] = one_way
  m.kinds = chispita_obj() # forget remembered kinds, the rules changed

def Chispita_setHollow(m=None, tile_name=None):
  chispita_set_tile_rule(m, tile_name, 1, 0)

def Chispita_setSolid(m=None, tile_name=None):
  chispita_set_tile_rule(m, tile_name, 0, 0)

def Chispita_setOneWay(m=None, tile_name=None):
  chispita_set_tile_rule(m, tile_name, 0, 1)

def chispita_tile_kind(m=None, cell=None):
  if not cell: return "empty"
  kind = m.kinds[cell]
  if kind: return kind

  name = chispita_tile_name(cell)
  if m.hollow[name]:
    kind = "empty"
  elif m.one_way[name]:
    kind = "one_way"
  else:
    kind = "solid"
  m.kinds[cell] = kind
  return kind

def chispita_tiles_across(m=None):
  return m.tile and m.tile_across

def chispita_tiles_down(m=None):
  return m.tile and m.tile_down

def chispita_wrap_x(m=None, cx=None):
  if not chispita_tiles_across(m): return cx
  w = m.map.width
  return (cx % w + w) % w

def chispita_wrap_y(m=None, cy=None):
  if not chispita_tiles_down(m): return cy
  h = m.map.height
  return (cy % h + h) % h

def chispita_map_get(m=None, cx=None, cy=None):
  return m.map.get(chispita_wrap_x(m, cx), chispita_wrap_y(m, cy))

def chispita_tile_is_solid(m=None, cx=None, cy=None):
  return chispita_tile_kind(m, chispita_map_get(m, cx, cy)) == "solid"

def chispita_make_tile(m=None, l=None, cx=None, cy=None, cell=None):
  tile = chispita_obj()
  tile.map = m
  tile.cell = cell
  tile.name = chispita_tile_name(cell)
  tile.cx = chispita_wrap_x(m, cx)
  tile.cy = chispita_wrap_y(m, cy)
  tile.x = l.left + (cx + 0.5) * l.cw
  tile.y = l.bottom + (cy + 0.5) * l.ch
  return tile

def chispita_tile_image_part(m=None, cell=None):
  parts = cell.split(":")
  if len(parts) < 2: return 0
  coords = parts[1].split(",")
  part = chispita_obj()
  part.w = m.map.block_width
  part.h = m.map.block_height
  part.x = int(coords[0]) * part.w
  part.y = int(coords[1]) * part.h
  return part

def chispita_skip_internal_edge(m=None, body=None, hit=None):
  if not chispita_tile_is_solid(m, body.cx - hit.nx, body.cy - hit.ny): return hit
  if hit.nx != 0:
    chispita_use_y_axis(hit)
  else:
    chispita_use_x_axis(hit)
  if chispita_tile_is_solid(m, body.cx - hit.nx, body.cy - hit.ny): return 0
  return hit

def chispita_record_tile_touch(s=None, m=None, l=None, cx=None, cy=None, cell=None):
  key = chispita_str(m.id) + ":" + chispita_str(cx) + "," + chispita_str(cy)
  if s.tile_contacts[key]: return
  s.tile_contacts[key] = chispita_make_tile(m, l, cx, cy, cell)
  s.tile_touched = 1

def chispita_collide_sprite_map(s=None, m=None, l=None):
  wants_touch = (s.trigger and s.on_tile) or m.callback
  if not (chispita_movable(s) or wants_touch): return
  for index in range(chispita_shape_count(s)):
    chispita_collide_shape_map(s, m, l, index, wants_touch)

def chispita_collide_shape_map(s=None, m=None, l=None, index=None, wants_touch=None):
  shape = chispita_sprite_shape(s, index)
  x0 = math.floor((shape.x - shape.ex - l.left) / l.cw)
  x1 = math.floor((shape.x + shape.ex - l.left) / l.cw)
  y0 = math.floor((shape.y - shape.ey - l.bottom) / l.ch)
  y1 = math.floor((shape.y + shape.ey - l.bottom) / l.ch)
  if not chispita_tiles_across(m):
    x0 = max(0, x0)
    x1 = min(m.map.width - 1, x1)
  if not chispita_tiles_down(m):
    y0 = max(0, y0)
    y1 = min(m.map.height - 1, y1)
  body = m.tile_body
  body.bounciness = m.bounciness
  body.grip = m.grip

  for cy in range(y0, y1 + 1):
    for cx in range(x0, x1 + 1):
      cell = chispita_map_get(m, cx, cy)
      kind = chispita_tile_kind(m, cell)
      if kind == "empty": continue

      body.cx = cx
      body.cy = cy
      chispita_set_shape(body.shape, "rect", l.left + (cx + 0.5) * l.cw, l.bottom + (cy + 0.5) * l.ch, l.cw, l.ch, 0)

      hit = chispita_test(chispita_sprite_shape(s, index), body.shape)
      if hit and hit.ox and kind == "solid":
        hit = chispita_skip_internal_edge(m, body, hit)
      if not hit: continue

      if wants_touch: chispita_record_tile_touch(s, m, l, cx, cy, cell)
      if kind == "one_way":
        chispita_try_one_way(s, body, body.shape.y + body.shape.hh)
      else:
        chispita_resolve(s, body, hit)

def chispita_ray_map(m=None, x1=None, y1=None, dx=None, dy=None, limit=None):
  l = chispita_map_layout(m)
  if not l: return 0
  gx = (x1 - l.left) / l.cw
  gy = (y1 - l.bottom) / l.ch
  gdx = dx / l.cw
  gdy = dy / l.ch
  cx = math.floor(gx)
  cy = math.floor(gy)
  huge = 1000000000

  step_x = 0
  next_x = huge
  delta_x = huge
  if gdx > 0:
    step_x = 1
    next_x = (cx + 1 - gx) / gdx
    delta_x = 1 / gdx
  elif gdx < 0:
    step_x = -1
    next_x = (gx - cx) / -gdx
    delta_x = 1 / -gdx

  step_y = 0
  next_y = huge
  delta_y = huge
  if gdy > 0:
    step_y = 1
    next_y = (cy + 1 - gy) / gdy
    delta_y = 1 / gdy
  elif gdy < 0:
    step_y = -1
    next_y = (gy - cy) / -gdy
    delta_y = 1 / -gdy

  across = chispita_tiles_across(m)
  down = chispita_tiles_down(m)
  t = 0
  while t <= min(1, limit):
    inside_x = across or (cx >= 0 and cx < m.map.width)
    inside_y = down or (cy >= 0 and cy < m.map.height)
    if inside_x and inside_y:
      cell = chispita_map_get(m, cx, cy)
      if chispita_tile_kind(m, cell) == "solid":
        found = chispita_obj()
        found.t = t
        found.tile = chispita_make_tile(m, l, cx, cy, cell)
        return found
    if next_x < next_y:
      cx += step_x
      t = next_x
      next_x += delta_x
    else:
      cy += step_y
      t = next_y
      next_y += delta_y
  return 0

def chispita_check_map_collisions():
  for m in chispita_maps:
    if not (m.map and m.physics and m.active): continue
    if m.parallax != 1:
      chispita_warn("map " + chispita_str(m.name) + " is solid but has parallax " + chispita_str(m.parallax) + ". Its tiles are drawn moved but collide where the map really is. Use physics_off for parallax backgrounds.")
    l = chispita_map_layout(m)
    for s in chispita_sprites:
      if s.active and s.physics:
        chispita_collide_sprite_map(s, m, l)

def Chispita_cellAt(m=None, x=None, y=None):
  if not m.map:
    chispita_warn("Chispita_cellAt needs a map from Chispita_addMap.")
    return 0
  l = chispita_map_layout(m)
  if not l: return 0
  return chispita_map_get(m, math.floor((x - l.left) / l.cw), math.floor((y - l.bottom) / l.ch))

def Chispita_spawnFromMap(m=None, tile_name=None):
  list = []
  if not m.map:
    chispita_warn("Chispita_spawnFromMap needs a map from Chispita_addMap.")
    return list
  l = chispita_map_layout(m)
  if not l: return list

  if not m.cloned:
    m.map = m.map.clone()
    m.cloned = 1
    l = chispita_map_layout(m)

  for cy in range(m.map.height):
    for cx in range(m.map.width):
      cell = m.map.get(cx, cy)
      if not cell: continue
      if cell != tile_name and chispita_tile_name(cell) != tile_name: continue

      m.map.set(cx, cy, 0)
      x = l.left + (cx + 0.5) * l.cw
      y = l.bottom + (cy + 0.5) * l.ch
      s = Chispita_addRect(x, y, l.cw, l.ch)
      s.image = chispita_tile_name(cell)
      s.image_part = chispita_tile_image_part(m, cell)
      list.append(s)
  m.map.update()
  return list

def chispita_draw_map(m=None):
  l = chispita_map_layout(m)
  if not l: return
  x = chispita_screen_x(m, m.x)
  y = chispita_screen_y(m, m.y)
  w = chispita_screen_size(m, l.width)
  h = chispita_screen_size(m, l.height)
  across = chispita_tiles_across(m)
  down = chispita_tiles_down(m)
  if not across and (x + w / 2 < -screen.width / 2 or x - w / 2 > screen.width / 2): return
  if not down and (y + h / 2 < -screen.height / 2 or y - h / 2 > screen.height / 2): return
  if not m.tile:
    screen.drawMap(m.map, x, y, w, h)
    return
  copies = 1
  if across: copies *= math.ceil(screen.width / w) + 1
  if down: copies *= math.ceil(screen.height / h) + 1
  if copies > chispita_max_map_copies:
    chispita_warn("map " + chispita_str(m.name) + " is too small to tile at this zoom (" + chispita_str(copies) + " copies). Drawing it once. Use a bigger map or raise chispita_max_map_copies.")
    screen.drawMap(m.map, x, y, w, h)
    return
  draw_w = w
  draw_h = h
  if across:
    x -= math.floor((x + screen.width / 2 + w / 2) / w) * w
    draw_w += 1
  if down:
    y -= math.floor((y + screen.height / 2 + h / 2) / h) * h
    draw_h += 1
  first_y = y
  while x - w / 2 < screen.width / 2:
    y = first_y
    while y - h / 2 < screen.height / 2:
      screen.drawMap(m.map, x, y, draw_w, draw_h)
      if not down: break
      y += h
    if not across: break
    x += w
