var chispita_maps = []

// Add maps
function Chispita_addMap(name, x, y, physics, cell_size) {
  // Left out, a position is 0, as in microScript.
  if (!x) x = 0
  if (!y) y = 0
  var m = {}
  m.id = chispita_next_id
  chispita_next_id += 1
  m.name = name
  m.map = maps[name]
  if (!m.map) chispita_warn("no map named " + name + ". Check the name in the map editor.")
  if (physics && physics != physics_on && physics != physics_off) {
    chispita_warn("Chispita_addMap: physics should be physics_on or physics_off, not " + physics + ". Using physics_on.")
  }
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
  m.callback = 0 // a sprite touched a tile: callback(sprite, tile)
  m.hollow = {}
  m.one_way = {}
  m.kinds = {} // remembers each cell value's kind so it's only worked out once
  m.layout = 0
  m.cloned = 0
  if (m.physics) m.layer = 0; else m.layer = -1

  m.tile_body = {}
  m.tile_body.shape = {}
  m.tile_body.fixed = 1
  m.tile_body.solid = 1
  m.tile_body.kinematic = 0
  m.tile_body.x = 0      // tiles never move; these just keep the push maths happy
  m.tile_body.y = 0
  m.tile_body.vx = 0
  m.tile_body.vy = 0

  m.draw = function() {
    chispita_draw_map(this)
  }

  chispita_maps.push(m)
  chispita_add_drawable(m)
  return m
}

//World Size
function chispita_map_layout(m) {
  if (!m.map) return 0
  var l = m.layout
  if (l && l.x == m.x && l.y == m.y && l.cell_size == m.cell_size && l.map == m.map) {
    return l
  }

  l = {}
  l.x = m.x
  l.y = m.y
  l.cell_size = m.cell_size
  l.map = m.map
  l.cw = m.cell_size
  if (!l.cw) l.cw = m.map.block_width
  l.ch = l.cw * m.map.block_height / m.map.block_width
  l.width = m.map.width * l.cw
  l.height = m.map.height * l.ch
  l.left = m.x - l.width / 2
  l.bottom = m.y - l.height / 2
  m.layout = l
  return l
}

//Tile flags
function chispita_tile_name(cell) {
  if (!cell) return ""
  return cell.split(":")[0]
}

function chispita_set_tile_rule(m, tile_name, hollow, one_way) {
  if (!m.hollow) {
    chispita_warn("tile rules need a map from Chispita_addMap.")
    return
  }
  m.hollow[tile_name] = hollow
  m.one_way[tile_name] = one_way
  m.kinds = {} // forget remembered kinds, the rules changed
}

function Chispita_setHollow(m, tile_name) {
  chispita_set_tile_rule(m, tile_name, 1, 0)
}

function Chispita_setSolid(m, tile_name) {
  chispita_set_tile_rule(m, tile_name, 0, 0)
}

function Chispita_setOneWay(m, tile_name) {
  chispita_set_tile_rule(m, tile_name, 0, 1)
}

function chispita_tile_kind(m, cell) {
  if (!cell) return "empty"
  var kind = m.kinds[cell]
  if (kind) return kind

  var name = chispita_tile_name(cell)
  if (m.hollow[name]) {
    kind = "empty"
  } else if (m.one_way[name]) {
    kind = "one_way"
  } else {
    kind = "solid"
  }
  m.kinds[cell] = kind
  return kind
}

function chispita_tiles_across(m) {
  return m.tile && m.tile_across
}

function chispita_tiles_down(m) {
  return m.tile && m.tile_down
}

function chispita_wrap_x(m, cx) {
  if (!chispita_tiles_across(m)) return cx
  var w = m.map.width
  return (cx % w + w) % w
}

function chispita_wrap_y(m, cy) {
  if (!chispita_tiles_down(m)) return cy
  var h = m.map.height
  return (cy % h + h) % h
}

function chispita_map_get(m, cx, cy) {
  return m.map.get(chispita_wrap_x(m, cx), chispita_wrap_y(m, cy))
}

function chispita_tile_is_solid(m, cx, cy) {
  return chispita_tile_kind(m, chispita_map_get(m, cx, cy)) == "solid"
}

function chispita_make_tile(m, l, cx, cy, cell) {
  var tile = {}
  tile.map = m
  tile.cell = cell
  tile.name = chispita_tile_name(cell)
  tile.cx = chispita_wrap_x(m, cx)
  tile.cy = chispita_wrap_y(m, cy)
  tile.x = l.left + (cx + 0.5) * l.cw
  tile.y = l.bottom + (cy + 0.5) * l.ch
  return tile
}

function chispita_tile_image_part(m, cell) {
  var parts = cell.split(":")
  if (parts.length < 2) return 0
  var coords = parts[1].split(",")
  var part = {}
  part.w = m.map.block_width
  part.h = m.map.block_height
  part.x = coords[0] * part.w
  part.y = coords[1] * part.h
  return part
}

function chispita_skip_internal_edge(m, body, hit) {
  if (!chispita_tile_is_solid(m, body.cx - hit.nx, body.cy - hit.ny)) return hit
  if (hit.nx != 0) {
    chispita_use_y_axis(hit)
  } else {
    chispita_use_x_axis(hit)
  }
  if (chispita_tile_is_solid(m, body.cx - hit.nx, body.cy - hit.ny)) return 0
  return hit
}

function chispita_record_tile_touch(s, m, l, cx, cy, cell) {
  var key = m.id + ":" + cx + "," + cy
  if (s.tile_contacts[key]) return
  s.tile_contacts[key] = chispita_make_tile(m, l, cx, cy, cell)
  s.tile_touched = 1
}

function chispita_collide_sprite_map(s, m, l) {
  var wants_touch = (s.trigger && s.on_tile) || m.callback
  if (!(chispita_movable(s) || wants_touch)) return
  for (var index = 0; index <= chispita_shape_count(s) - 1; index += 1) {
    chispita_collide_shape_map(s, m, l, index, wants_touch)
  }
}

function chispita_collide_shape_map(s, m, l, index, wants_touch) {
  var shape = chispita_sprite_shape(s, index)
  var x0 = Math.floor((shape.x - shape.ex - l.left) / l.cw)
  var x1 = Math.floor((shape.x + shape.ex - l.left) / l.cw)
  var y0 = Math.floor((shape.y - shape.ey - l.bottom) / l.ch)
  var y1 = Math.floor((shape.y + shape.ey - l.bottom) / l.ch)
  if (!chispita_tiles_across(m)) {
    x0 = Math.max(0, x0)
    x1 = Math.min(m.map.width - 1, x1)
  }
  if (!chispita_tiles_down(m)) {
    y0 = Math.max(0, y0)
    y1 = Math.min(m.map.height - 1, y1)
  }
  var body = m.tile_body
  body.bounciness = m.bounciness
  body.grip = m.grip

  for (var cy = y0; cy <= y1; cy += 1) {
    for (var cx = x0; cx <= x1; cx += 1) {
      var cell = chispita_map_get(m, cx, cy)
      var kind = chispita_tile_kind(m, cell)
      if (kind == "empty") continue

      body.cx = cx
      body.cy = cy
      chispita_set_shape(body.shape, "rect", l.left + (cx + 0.5) * l.cw, l.bottom + (cy + 0.5) * l.ch, l.cw, l.ch, 0)

      var hit = chispita_test(chispita_sprite_shape(s, index), body.shape)
      if (hit && hit.ox && kind == "solid") {
        hit = chispita_skip_internal_edge(m, body, hit)
      }
      if (!hit) continue

      if (wants_touch) chispita_record_tile_touch(s, m, l, cx, cy, cell)
      if (kind == "one_way") {
        chispita_try_one_way(s, body, body.shape.y + body.shape.hh)
      } else {
        chispita_resolve(s, body, hit)
      }
    }
  }
}

function chispita_ray_map(m, x1, y1, dx, dy, limit) {
  var l = chispita_map_layout(m)
  if (!l) return 0
  var gx = (x1 - l.left) / l.cw
  var gy = (y1 - l.bottom) / l.ch
  var gdx = dx / l.cw
  var gdy = dy / l.ch
  var cx = Math.floor(gx)
  var cy = Math.floor(gy)
  var huge = 1000000000

  var step_x = 0
  var next_x = huge
  var delta_x = huge
  if (gdx > 0) {
    step_x = 1
    next_x = (cx + 1 - gx) / gdx
    delta_x = 1 / gdx
  } else if (gdx < 0) {
    step_x = -1
    next_x = (gx - cx) / -gdx
    delta_x = 1 / -gdx
  }

  var step_y = 0
  var next_y = huge
  var delta_y = huge
  if (gdy > 0) {
    step_y = 1
    next_y = (cy + 1 - gy) / gdy
    delta_y = 1 / gdy
  } else if (gdy < 0) {
    step_y = -1
    next_y = (gy - cy) / -gdy
    delta_y = 1 / -gdy
  }

  var across = chispita_tiles_across(m)
  var down = chispita_tiles_down(m)
  var t = 0
  while (t <= Math.min(1, limit)) {
    var inside_x = across || (cx >= 0 && cx < m.map.width)
    var inside_y = down || (cy >= 0 && cy < m.map.height)
    if (inside_x && inside_y) {
      var cell = chispita_map_get(m, cx, cy)
      if (chispita_tile_kind(m, cell) == "solid") {
        var found = {}
        found.t = t
        found.tile = chispita_make_tile(m, l, cx, cy, cell)
        return found
      }
    }
    if (next_x < next_y) {
      cx += step_x
      t = next_x
      next_x += delta_x
    } else {
      cy += step_y
      t = next_y
      next_y += delta_y
    }
  }
  return 0
}

function chispita_check_map_collisions() {
  for (var m of chispita_maps) {
    if (!(m.map && m.physics && m.active)) continue
    if (m.parallax != 1) {
      chispita_warn("map " + m.name + " is solid but has parallax " + m.parallax + ". Its tiles are drawn moved but collide where the map really is. Use physics_off for parallax backgrounds.")
    }
    var l = chispita_map_layout(m)
    for (var s of chispita_sprites) {
      if (s.active && s.physics) {
        chispita_collide_sprite_map(s, m, l)
      }
    }
  }
}

function Chispita_cellAt(m, x, y) {
  if (!m.map) {
    chispita_warn("Chispita_cellAt needs a map from Chispita_addMap.")
    return 0
  }
  var l = chispita_map_layout(m)
  if (!l) return 0
  return chispita_map_get(m, Math.floor((x - l.left) / l.cw), Math.floor((y - l.bottom) / l.ch))
}

function Chispita_spawnFromMap(m, tile_name) {
  var list = []
  if (!m.map) {
    chispita_warn("Chispita_spawnFromMap needs a map from Chispita_addMap.")
    return list
  }
  var l = chispita_map_layout(m)
  if (!l) return list

  if (!m.cloned) {
    m.map = m.map.clone()
    m.cloned = 1
    l = chispita_map_layout(m)
  }

  for (var cy = 0; cy <= m.map.height - 1; cy += 1) {
    for (var cx = 0; cx <= m.map.width - 1; cx += 1) {
      var cell = m.map.get(cx, cy)
      if (!cell) continue
      if (cell != tile_name && chispita_tile_name(cell) != tile_name) continue

      m.map.set(cx, cy, 0)
      var x = l.left + (cx + 0.5) * l.cw
      var y = l.bottom + (cy + 0.5) * l.ch
      var s = Chispita_addRect(x, y, l.cw, l.ch)
      s.image = chispita_tile_name(cell)
      s.image_part = chispita_tile_image_part(m, cell)
      list.push(s)
    }
  }
  m.map.update()
  return list
}

function chispita_draw_map(m) {
  var l = chispita_map_layout(m)
  if (!l) return
  var x = chispita_screen_x(m, m.x)
  var y = chispita_screen_y(m, m.y)
  var w = chispita_screen_size(m, l.width)
  var h = chispita_screen_size(m, l.height)
  var across = chispita_tiles_across(m)
  var down = chispita_tiles_down(m)
  if (!across && (x + w / 2 < -screen.width / 2 || x - w / 2 > screen.width / 2)) return
  if (!down && (y + h / 2 < -screen.height / 2 || y - h / 2 > screen.height / 2)) return
  if (!m.tile) {
    screen.drawMap(m.map, x, y, w, h)
    return
  }
  var copies = 1
  if (across) copies *= Math.ceil(screen.width / w) + 1
  if (down) copies *= Math.ceil(screen.height / h) + 1
  if (copies > chispita_max_map_copies) {
    chispita_warn("map " + m.name + " is too small to tile at this zoom (" + copies + " copies). Drawing it once. Use a bigger map or raise chispita_max_map_copies.")
    screen.drawMap(m.map, x, y, w, h)
    return
  }
  var draw_w = w
  var draw_h = h
  if (across) {
    x -= Math.floor((x + screen.width / 2 + w / 2) / w) * w
    draw_w += 1
  }
  if (down) {
    y -= Math.floor((y + screen.height / 2 + h / 2) / h) * h
    draw_h += 1
  }
  var first_y = y
  while (x - w / 2 < screen.width / 2) {
    y = first_y
    while (y - h / 2 < screen.height / 2) {
      screen.drawMap(m.map, x, y, draw_w, draw_h)
      if (!down) break
      y += h
    }
    if (!across) break
    x += w
  }
}








