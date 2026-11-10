var chispita_ignored = {}
var chispita_hurt_ignored = {}
var chispita_any_ignored = 0
var chispita_any_hurt_ignored = 0

// Set sprite shapes
function chispita_set_shape(shape, kind, x, y, width, height, radius, angle) {
  if (kind != "rect" && kind != "circle" && kind != "capsule") {
    chispita_warn("unknown hit box shape '" + kind + "'. Use 'rect', 'circle' or 'capsule'.")
    kind = "rect"
  }
  shape.kind = kind
  shape.x = x
  shape.y = y
  shape.angle = angle
  shape.cos = 1
  shape.sin = 0
  if (angle) {
    shape.cos = chispita_cosd(angle)
    shape.sin = chispita_sind(angle)
  }

  if (kind == "circle") {
    shape.r = radius
    shape.hw = radius
    shape.hh = radius
    shape.ex = radius
    shape.ey = radius
  } else if (kind == "rect" || kind == "capsule") {
    var c = Math.abs(shape.cos)
    var n = Math.abs(shape.sin)
    shape.hw = width / 2
    shape.hh = height / 2
    shape.ex = shape.hw * c + shape.hh * n
    shape.ey = shape.hw * n + shape.hh * c
  }

  if (kind == "capsule") {
    shape.r = shape.hw
    shape.half = Math.max(0, shape.hh - shape.hw)
  }
  return shape
}

function chispita_rotation(s) {
  if (!s.rotate_hit_box || !s.rotation) return 0
  return s.rotation % 360
}

function chispita_hit_angle(s) {
  if (s.hit_box_shape == "circle") return 0
  return chispita_rotation(s)
}

function chispita_box_shape(s, shape, kind, offset_x, offset_y, width, height, radius) {
  return chispita_place_shape(s, shape, kind, offset_x, offset_y, width, height, radius, chispita_hit_angle(s))
}

function chispita_part_shape(s, part) {
  return chispita_place_shape(s, part.shape, part.kind, part.offset_x, part.offset_y, part.width, part.height, part.radius, chispita_rotation(s))
}

function chispita_sprite_shape(s, index) {
  if (index == 0) return chispita_hit_shape(s)
  return chispita_part_shape(s, s.hit_parts[index - 1])
}

function chispita_shape_count(s) {
  if (s.hit_parts) return s.hit_parts.length + 1
  return 1
}

function chispita_place_shape(s, shape, kind, offset_x, offset_y, width, height, radius, angle) {
  chispita_set_shape(shape, kind, s.x, s.y, width, height, radius, angle)
  shape.x += offset_x * shape.cos - offset_y * shape.sin
  shape.y += offset_x * shape.sin + offset_y * shape.cos
  return shape
}

function chispita_hit_shape(s) {
  return chispita_box_shape(s, s.hit_shape, s.hit_box_shape, s.hit_offset_x, s.hit_offset_y, s.hit_width, s.hit_height, s.hit_radius)
}

function chispita_hurt_shape(s) {
  return chispita_box_shape(s, s.hurt_shape, s.hurt_box_shape, s.hurt_offset_x, s.hurt_offset_y, s.hurt_width, s.hurt_height, s.hurt_radius)
}

//Choose direction of push
function chispita_use_x_axis(hit) {
  hit.nx = hit.x_side
  hit.ny = 0
  hit.overlap = hit.ox
}

function chispita_use_y_axis(hit) {
  hit.nx = 0
  hit.ny = hit.y_side
  hit.overlap = hit.oy
}

// Sprite test collisions
function chispita_test_rect_rect(a, b) {
  if (a.angle || b.angle) return chispita_test_box_box(a, b)
  var ox = a.hw + b.hw - Math.abs(a.x - b.x)
  if (ox <= 0) return 0
  var oy = a.hh + b.hh - Math.abs(a.y - b.y)
  if (oy <= 0) return 0

  var hit = {}
  hit.ox = ox
  hit.oy = oy
  if (a.x < b.x) hit.x_side = 1; else hit.x_side = -1
  if (a.y < b.y) hit.y_side = 1; else hit.y_side = -1
  if (ox < oy) {
    chispita_use_x_axis(hit)
  } else {
    chispita_use_y_axis(hit)
  }
  return hit
}

function chispita_test_box_box(a, b) {
  var dx = b.x - a.x
  var dy = b.y - a.y
  var best = -1
  var best_nx = 0
  var best_ny = 0
  for (var i = 0; i <= 3; i += 1) {
    var owner = a
    if (i >= 2) owner = b
    var ax = owner.cos
    var ay = owner.sin
    if (i % 2 == 1) {
      ax = -owner.sin
      ay = owner.cos
    }
    var ra = a.hw * Math.abs(a.cos * ax + a.sin * ay) + a.hh * Math.abs(a.cos * ay - a.sin * ax)
    var rb = b.hw * Math.abs(b.cos * ax + b.sin * ay) + b.hh * Math.abs(b.cos * ay - b.sin * ax)
    var d = dx * ax + dy * ay
    var overlap = ra + rb - Math.abs(d)
    if (overlap <= 0) return 0
    if (best < 0 || overlap < best) {
      best = overlap
      if (d < 0) {
        best_nx = -ax
        best_ny = -ay
      } else {
        best_nx = ax
        best_ny = ay
      }
    }
  }

  var hit = {}
  hit.nx = best_nx
  hit.ny = best_ny
  hit.overlap = best
  return hit
}

function chispita_test_rect_circle(r, c) {
  var wx = c.x - r.x
  var wy = c.y - r.y
  var lx = wx * r.cos + wy * r.sin
  var ly = wy * r.cos - wx * r.sin

  var px = Math.max(-r.hw, Math.min(lx, r.hw))
  var py = Math.max(-r.hh, Math.min(ly, r.hh))
  var dx = lx - px
  var dy = ly - py
  var distance_sq = dx * dx + dy * dy
  if (distance_sq >= c.r * c.r) return 0

  var distance = Math.sqrt(distance_sq)
  var nx = 0
  var ny = 0
  var overlap = 0
  if (distance > 0.001) {
    nx = dx / distance
    ny = dy / distance
    overlap = c.r - distance + 0.02
  } else {
    var to_left = lx + r.hw
    var to_right = r.hw - lx
    var to_bottom = ly + r.hh
    var to_top = r.hh - ly
    var nearest = Math.min(Math.min(to_left, to_right), Math.min(to_bottom, to_top))
    if (nearest == to_left) {
      nx = -1
    } else if (nearest == to_right) {
      nx = 1
    } else if (nearest == to_bottom) {
      ny = -1
    } else {
      ny = 1
    }
    overlap = nearest + c.r + 0.02
  }

  var hit = {}
  hit.nx = nx * r.cos - ny * r.sin
  hit.ny = nx * r.sin + ny * r.cos
  hit.overlap = overlap
  return hit
}

function chispita_test_circle_circle(a, b) {
  var dx = b.x - a.x
  var dy = b.y - a.y
  var radii = a.r + b.r
  var distance_sq = dx * dx + dy * dy
  if (distance_sq >= radii * radii) return 0

  var distance = Math.sqrt(distance_sq)
  var hit = {}
  if (distance > 0.001) {
    hit.nx = dx / distance
    hit.ny = dy / distance
  } else {
    hit.nx = 0
    hit.ny = 1
  }
  hit.overlap = radii - distance
  return hit
}

var chispita_capsule_circle_a = {}
var chispita_capsule_circle_b = {}
var chispita_capsule_point_a = {}
var chispita_capsule_point_b = {}

function chispita_closest_on_segment(x1, y1, x2, y2, px, py, out) {
  var dx = x2 - x1
  var dy = y2 - y1
  var length_sq = dx * dx + dy * dy
  var t = 0
  if (length_sq > 0) t = Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / length_sq))
  out.x = x1 + dx * t
  out.y = y1 + dy * t
}

function chispita_capsule_point(c, px, py, out) {
  var ux = -c.sin * c.half
  var uy = c.cos * c.half
  chispita_closest_on_segment(c.x - ux, c.y - uy, c.x + ux, c.y + uy, px, py, out)
}

function chispita_closest_on_rect(r, px, py, out) {
  var wx = px - r.x
  var wy = py - r.y
  var lx = Math.max(-r.hw, Math.min(wx * r.cos + wy * r.sin, r.hw))
  var ly = Math.max(-r.hh, Math.min(wy * r.cos - wx * r.sin, r.hh))
  out.x = r.x + lx * r.cos - ly * r.sin
  out.y = r.y + lx * r.sin + ly * r.cos
}

function chispita_circle_at(circle, x, y, r) {
  circle.kind = "circle"
  circle.x = x
  circle.y = y
  circle.r = r
  return circle
}

function chispita_capsule_vs_circle(cap, circle) {
  var p = chispita_capsule_point_a
  chispita_capsule_point(cap, circle.x, circle.y, p)
  return chispita_test_circle_circle(chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, cap.r), circle)
}

function chispita_capsule_vs_capsule(a, b) {
  var p = chispita_capsule_point_a
  var q = chispita_capsule_point_b
  chispita_capsule_point(a, b.x, b.y, p)
  for (var i = 1; i <= 3; i += 1) {
    chispita_capsule_point(b, p.x, p.y, q)
    chispita_capsule_point(a, q.x, q.y, p)
  }
  chispita_capsule_point(b, p.x, p.y, q)
  return chispita_test_circle_circle(chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, a.r), chispita_circle_at(chispita_capsule_circle_b, q.x, q.y, b.r))
}

function chispita_rect_vs_capsule(rect, cap) {
  var p = chispita_capsule_point_a
  var q = chispita_capsule_point_b
  chispita_capsule_point(cap, rect.x, rect.y, p)
  for (var i = 1; i <= 3; i += 1) {
    chispita_closest_on_rect(rect, p.x, p.y, q)
    chispita_capsule_point(cap, q.x, q.y, p)
  }
  return chispita_test_rect_circle(rect, chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, cap.r))
}

function chispita_flip_hit(hit) {
  if (hit) {
    hit.nx = -hit.nx
    hit.ny = -hit.ny
  }
  return hit
}

function chispita_test_capsule(a, b) {
  if (a.kind == "capsule" && b.kind == "capsule") return chispita_capsule_vs_capsule(a, b)
  if (a.kind == "capsule") {
    if (b.kind == "circle") return chispita_capsule_vs_circle(a, b)
    return chispita_flip_hit(chispita_rect_vs_capsule(b, a))
  }
  if (a.kind == "circle") return chispita_flip_hit(chispita_capsule_vs_circle(b, a))
  return chispita_rect_vs_capsule(a, b)
}

function chispita_test(a, b) {
  if (a.kind == "capsule" || b.kind == "capsule") return chispita_test_capsule(a, b)
  if (a.kind == "circle" && b.kind == "circle") {
    return chispita_test_circle_circle(a, b)
  } else if (b.kind == "circle") {
    return chispita_test_rect_circle(a, b)
  } else if (a.kind == "circle") {
    return chispita_flip_hit(chispita_test_rect_circle(b, a))
  }
  return chispita_test_rect_rect(a, b)
}

// Collision responses
function chispita_movable(s) {
  return s.solid && !s.fixed && !s.kinematic
}

function chispita_inverse_mass(s) {
  if (!chispita_movable(s)) return 0
  if (s.mass <= 0) {
    chispita_warn("sprite #" + s.id + " has mass " + s.mass + ". Mass must be above 0, so 1 is used.")
    return 1
  }
  return 1 / s.mass
}

function chispita_ground(s, surface) {
  s.grounded = 1
  var surface_vy = 0
  if (surface.kinematic) {
    s.riding = surface
    surface_vy = surface.vy
  }
  if (Math.abs(s.vy - surface_vy) < chispita_rest_speed) {
    s.vy = 0
  }
}

function chispita_resolve(s1, s2, hit) {
  var nx = hit.nx
  var ny = hit.ny
  var w1 = chispita_inverse_mass(s1)
  var w2 = chispita_inverse_mass(s2)
  var total = w1 + w2
  if (total <= 0) return

  var push = Math.max(hit.overlap - chispita_collision_slop, 0) * chispita_collision_push / total
  s1.x -= nx * push * w1
  s1.y -= ny * push * w1
  s2.x += nx * push * w2
  s2.y += ny * push * w2

  var rvx = s2.vx - s1.vx
  var rvy = s2.vy - s1.vy
  var speed_into_normal = rvx * nx + rvy * ny
  if (speed_into_normal < 0) {
    var bounce = s1.bounciness * s2.bounciness
    if (-speed_into_normal < chispita_rest_speed) bounce = 0
    var impulse = -(1 + bounce) * speed_into_normal / total
    s1.vx -= impulse * nx * w1
    s1.vy -= impulse * ny * w1
    s2.vx += impulse * nx * w2
    s2.vy += impulse * ny * w2

    var grip = (s1.grip + s2.grip) / 2
    var riding = (s2.kinematic && ny < -0.9) || (s1.kinematic && ny > 0.9)
    if (grip > 0 && !riding) {
      var tx = -ny
      var ty = nx
      var slide = rvx * tx + rvy * ty
      var limit = grip * impulse
      var friction_impulse = Math.max(-limit, Math.min(-slide / total, limit))
      s1.vx -= friction_impulse * tx * w1
      s1.vy -= friction_impulse * ty * w1
      s2.vx += friction_impulse * tx * w2
      s2.vy += friction_impulse * ty * w2
    }
  }

  if (w1 > 0 && ny < -0.9) chispita_ground(s1, s2)
  if (w2 > 0 && ny > 0.9) chispita_ground(s2, s1)
}

function chispita_try_one_way(mover, platform, platform_top) {
  if (mover.drop_through || !chispita_movable(mover)) return
  var half = chispita_hit_shape(mover).ey
  var old_bottom = mover.old_y + mover.hit_offset_y - half
  if (mover.vy > platform.vy || old_bottom < platform_top - 0.5) return

  var bottom = mover.y + mover.hit_offset_y - half
  mover.y += platform_top - bottom
  mover.vy = platform.vy - (mover.vy - platform.vy) * mover.bounciness * platform.bounciness
  chispita_ground(mover, platform)
}

function Chispita_ignore(group_a, group_b) {
  if (!group_a || !group_b) {
    chispita_warn("Chispita_ignore needs two group names, like Chispita_ignore('player', 'ghost').")
    return
  }
  chispita_ignored[group_a + "|" + group_b] = 1
  chispita_ignored[group_b + "|" + group_a] = 1
  chispita_any_ignored = 1
}

function Chispita_ignoreHurt(group_a, group_b) {
  if (!group_a || !group_b) {
    chispita_warn("Chispita_ignoreHurt needs two group names, like Chispita_ignoreHurt('player', 'player').")
    return
  }
  chispita_hurt_ignored[group_a + "|" + group_b] = 1
  chispita_hurt_ignored[group_b + "|" + group_a] = 1
  chispita_any_hurt_ignored = 1
}

function chispita_can_collide(s1, s2) {
  if (!chispita_any_ignored) return 1
  return !chispita_ignored[s1.group + "|" + s2.group]
}

function chispita_can_hurt(attacker, victim) {
  if (!chispita_any_hurt_ignored) return 1
  return !chispita_hurt_ignored[attacker.group + "|" + victim.group]
}

function chispita_update_bounds(s) {
  var shape = chispita_hit_shape(s)
  s.left = shape.x - shape.ex
  s.right = shape.x + shape.ex
  s.bottom = shape.y - shape.ey
  s.top = shape.y + shape.ey
  if (s.hit_parts) {
    for (var part of s.hit_parts) {
      var p = chispita_part_shape(s, part)
      s.left = Math.min(s.left, p.x - p.ex)
      s.right = Math.max(s.right, p.x + p.ex)
      s.bottom = Math.min(s.bottom, p.y - p.ey)
      s.top = Math.max(s.top, p.y + p.ey)
    }
  }
}

function chispita_sort_by_left(list) {
  for (var i = 1; i <= list.length - 1; i += 1) {
    var s = list[i]
    var j = i - 1
    while (j >= 0) {
      if (list[j].left <= s.left) break
      list[j + 1] = list[j]
      j -= 1
    }
    list[j + 1] = s
  }
}

function chispita_record_contact(s1, s2) {
  if (s1.trigger) s1.contacts[s2.id] = s2
  if (s2.trigger) s2.contacts[s1.id] = s1
}

function chispita_collide_pair(s1, s2) {
  var a = chispita_hit_shape(s1)
  var b = chispita_hit_shape(s2)
  var hit = chispita_test(a, b)
  if (s1.hit_parts || s2.hit_parts) {
    for (var i = 0; i <= chispita_shape_count(s1) - 1; i += 1) {
      for (var j = 0; j <= chispita_shape_count(s2) - 1; j += 1) {
        if (i == 0 && j == 0) continue
        var sa = chispita_sprite_shape(s1, i)
        var sb = chispita_sprite_shape(s2, j)
        var h = chispita_test(sa, sb)
        if (h && (!hit || h.overlap > hit.overlap)) {
          hit = h
          a = sa
          b = sb
        }
      }
    }
  }
  if (!hit) return

  chispita_record_contact(s1, s2)
  if (!(s1.solid && s2.solid)) return
  if (s1.one_way && s2.one_way) return
  if (s2.one_way) {
    chispita_try_one_way(s1, s2, b.y + b.ey)
  } else if (s1.one_way) {
    chispita_try_one_way(s2, s1, a.y + a.ey)
  } else {
    chispita_resolve(s1, s2, hit)
    if (s1.on_hit) s1.hit_list[s2.id] = s2
    if (s2.on_hit) s2.hit_list[s1.id] = s1
  }
}

var chispita_step_passes = 0

function chispita_check_collisions() {
  var passes = chispita_step_passes
  if (passes < 1) passes = chispita_collision_passes
  for (var pass = 1; pass <= passes; pass += 1) {
    chispita_collision_pass()
  }
}

function chispita_collision_pass() {
  for (var s of chispita_sprites) {
    if (s.active && s.physics) chispita_update_bounds(s)
  }
  chispita_sort_by_left(chispita_sprites)

  var n = chispita_sprites.length
  for (var i = 0; i <= n - 1; i += 1) {
    var s1 = chispita_sprites[i]
    if (!(s1.active && s1.physics)) continue
    var s1_matters = chispita_movable(s1) || s1.trigger
    for (var j = i + 1; j <= n - 1; j += 1) {
      var s2 = chispita_sprites[j]
      if (!(s2.active && s2.physics)) continue
      if (s2.left > s1.right) break
      if (s2.bottom > s1.top || s2.top < s1.bottom) continue
      if (!(s1_matters || chispita_movable(s2) || s2.trigger)) continue
      if (chispita_can_collide(s1, s2)) {
        chispita_collide_pair(s1, s2)
      }
    }
  }
}

function chispita_fire_contact_events() {
  for (var s of chispita_sprites) {
    if (s.trigger) {
      for (var id in s.contacts) {
        var other = s.contacts[id]
        if (s.on_enter && !s.old_contacts[id]) {
          var f = s.on_enter
          f(s, other)
        }
        if (s.callback) {
          var f = s.callback
          f(s, other)
        }
      }
      for (var id in s.old_contacts) {
        if (s.on_exit && !s.contacts[id]) {
          var f = s.on_exit
          f(s, s.old_contacts[id])
        }
      }
    }

    if (s.on_hit) {
      for (var id in s.hit_list) {
        if (!s.old_hit_list[id]) {
          var f = s.on_hit
          f(s, s.hit_list[id])
        }
      }
    }

    if (s.tile_touched) {
      for (var key in s.tile_contacts) {
        var tile = s.tile_contacts[key]
        if (s.trigger && s.on_tile) {
          var f = s.on_tile
          f(s, tile)
        }
        if (tile.map.callback) {
          var f = tile.map.callback
          f(s, tile)
        }
      }
    }
  }
}

function chispita_check_hurt_boxes() {
  var attackers = 0
  for (var a of chispita_sprites) {
    if (a.hurt_box && a.active) {
      attackers += 1
    } else if (a.was_hurting) {
      a.hurting = {}
      a.was_hurting = 0
    }
  }
  if (attackers == 0) return

  for (var s of chispita_sprites) {
    if (s.active && s.physics) chispita_update_bounds(s)
  }

  for (var a of chispita_sprites) {
    if (!(a.hurt_box && a.active)) continue
    a.was_hurting = 1
    var hurt = chispita_hurt_shape(a)
    var left = hurt.x - hurt.ex
    var right = hurt.x + hurt.ex
    var bottom = hurt.y - hurt.ey
    var top = hurt.y + hurt.ey
    if (a.hurt_parts) {
      for (var part of a.hurt_parts) {
        var p = chispita_part_shape(a, part)
        left = Math.min(left, p.x - p.ex)
        right = Math.max(right, p.x + p.ex)
        bottom = Math.min(bottom, p.y - p.ey)
        top = Math.max(top, p.y + p.ey)
      }
    }
    for (var b of chispita_sprites) {
      if (b == a || !(b.active && b.physics)) continue
      if (b.left > right || b.right < left || b.bottom > top || b.top < bottom) continue
      if (!chispita_can_hurt(a, b)) continue
      if (a.hurting[b.id]) continue
      if (chispita_hurt_touches(a, hurt, b)) {
        a.hurting[b.id] = b
        if (a.on_hurt) {
          var f = a.on_hurt
          f(a, b)
        }
      }
    }
  }
}

// Collision response questions
function chispita_shape_touches(shape, s) {
  if (chispita_test(shape, chispita_hit_shape(s))) return 1
  if (s.hit_parts) {
    for (var part of s.hit_parts) {
      if (chispita_test(shape, chispita_part_shape(s, part))) return 1
    }
  }
  return 0
}

function chispita_hurt_touches(a, hurt, b) {
  if (chispita_shape_touches(hurt, b)) return 1
  if (a.hurt_parts) {
    for (var part of a.hurt_parts) {
      if (chispita_shape_touches(part.shape, b)) return 1
    }
  }
  return 0
}

function Chispita_overlaps(a, b) {
  for (var i = 0; i <= chispita_shape_count(a) - 1; i += 1) {
    if (chispita_shape_touches(chispita_sprite_shape(a, i), b)) return 1
  }
  return 0
}

function Chispita_pointIn(s, x, y) {
  for (var i = 0; i <= chispita_shape_count(s) - 1; i += 1) {
    if (chispita_point_in_shape(chispita_sprite_shape(s, i), x, y)) return 1
  }
  return 0
}

function chispita_point_in_shape(shape, x, y) {
  var dx = x - shape.x
  var dy = y - shape.y
  if (shape.kind == "circle") {
    return dx * dx + dy * dy < shape.r * shape.r
  }
  if (shape.kind == "capsule") {
    var p = chispita_capsule_point_a
    chispita_capsule_point(shape, x, y, p)
    return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) < shape.r * shape.r
  }
  var lx = dx * shape.cos + dy * shape.sin
  var ly = dy * shape.cos - dx * shape.sin
  return Math.abs(lx) < shape.hw && Math.abs(ly) < shape.hh
}

function Chispita_findGroup(group) {
  var list = []
  for (var s of chispita_sprites) {
    if (s.active && s.group == group) list.push(s)
  }
  return list
}

var chispita_query_shape = {}

function Chispita_spritesIn(x, y, width, height) {
  var list = []
  if (width <= 0 || height <= 0) {
    chispita_warn("Chispita_spritesIn needs a width and height above 0.")
    return list
  }
  var area = chispita_set_shape(chispita_query_shape, "rect", x, y, width, height, 0, 0)
  for (var s of chispita_sprites) {
    if (s.active && chispita_shape_touches(area, s)) list.push(s)
  }
  return list
}

function chispita_ray_slab(start, move, half, t) {
  if (Math.abs(move) < 0.000001) {
    if (start < -half || start > half) t.miss = 1
    return
  }
  var t1 = (-half - start) / move
  var t2 = (half - start) / move
  if (t1 > t2) {
    var swap = t1
    t1 = t2
    t2 = swap
  }
  t.near = Math.max(t.near, t1)
  t.far = Math.min(t.far, t2)
  if (t.near > t.far) t.miss = 1
}

function chispita_ray_circle(cx, cy, r, x1, y1, dx, dy) {
  var fx = x1 - cx
  var fy = y1 - cy
  var a = dx * dx + dy * dy
  var b = 2 * (fx * dx + fy * dy)
  var c = fx * fx + fy * fy - r * r
  if (c <= 0) return 0
  var disc = b * b - 4 * a * c
  if (disc < 0) return -1
  var t = (-b - Math.sqrt(disc)) / (2 * a)
  if (t < 0 || t > 1) return -1
  return t
}

var chispita_ray_span = {}

function chispita_ray_box(shape, half_w, half_h, x1, y1, dx, dy) {
  var fx = x1 - shape.x
  var fy = y1 - shape.y
  var lx = fx * shape.cos + fy * shape.sin
  var ly = fy * shape.cos - fx * shape.sin
  var ldx = dx * shape.cos + dy * shape.sin
  var ldy = dy * shape.cos - dx * shape.sin
  var t = chispita_ray_span
  t.near = 0
  t.far = 1
  t.miss = 0
  chispita_ray_slab(lx, ldx, half_w, t)
  if (!t.miss) chispita_ray_slab(ly, ldy, half_h, t)
  if (t.miss) return -1
  return t.near
}

function chispita_ray_nearest(a, b) {
  if (a < 0) return b
  if (b < 0) return a
  return Math.min(a, b)
}

function chispita_ray_shape(shape, x1, y1, dx, dy) {
  if (shape.kind == "circle") {
    return chispita_ray_circle(shape.x, shape.y, shape.r, x1, y1, dx, dy)
  }
  if (shape.kind == "capsule") {
    var ux = -shape.sin * shape.half
    var uy = shape.cos * shape.half
    var t = chispita_ray_box(shape, shape.r, shape.half, x1, y1, dx, dy)
    t = chispita_ray_nearest(t, chispita_ray_circle(shape.x - ux, shape.y - uy, shape.r, x1, y1, dx, dy))
    return chispita_ray_nearest(t, chispita_ray_circle(shape.x + ux, shape.y + uy, shape.r, x1, y1, dx, dy))
  }
  return chispita_ray_box(shape, shape.hw, shape.hh, x1, y1, dx, dy)
}

function chispita_ray_sprite(s, x1, y1, dx, dy) {
  var t = chispita_ray_shape(chispita_hit_shape(s), x1, y1, dx, dy)
  if (s.hit_parts) {
    for (var part of s.hit_parts) {
      t = chispita_ray_nearest(t, chispita_ray_shape(chispita_part_shape(s, part), x1, y1, dx, dy))
    }
  }
  return t
}

function Chispita_raycast(x1, y1, x2, y2, ignore) {
  var dx = x2 - x1
  var dy = y2 - y1
  var length = Math.sqrt(dx * dx + dy * dy)
  if (length == 0) return 0

  var best = 2
  var best_sprite = 0
  for (var s of chispita_sprites) {
    if (s == ignore || !(s.active && s.physics && s.solid)) continue
    var t = chispita_ray_sprite(s, x1, y1, dx, dy)
    if (t >= 0 && t < best) {
      best = t
      best_sprite = s
    }
  }

  var best_tile = 0
  for (var m of chispita_maps) {
    if (!(m.map && m.physics && m.active)) continue
    var found = chispita_ray_map(m, x1, y1, dx, dy, best)
    if (found && found.t < best) {
      best = found.t
      best_tile = found.tile
      best_sprite = 0
    }
  }

  if (best > 1) return 0
  var hit = {}
  hit.x = x1 + dx * best
  hit.y = y1 + dy * best
  hit.distance = length * best
  hit.sprite = best_sprite
  hit.tile = best_tile
  return hit
}

















