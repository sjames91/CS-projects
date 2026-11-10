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

chispita_ignored = chispita_obj()
chispita_hurt_ignored = chispita_obj()
chispita_any_ignored = 0
chispita_any_hurt_ignored = 0

# Set sprite shapes
def chispita_set_shape(shape=None, kind=None, x=None, y=None, width=None, height=None, radius=None, angle=None):
  if kind != "rect" and kind != "circle" and kind != "capsule":
    chispita_warn("unknown hit box shape '" + chispita_str(kind) + "'. Use 'rect', 'circle' or 'capsule'.")
    kind = "rect"
  shape.kind = kind
  shape.x = x
  shape.y = y
  shape.angle = angle
  shape.cos = 1
  shape.sin = 0
  if angle:
    shape.cos = chispita_cosd(angle)
    shape.sin = chispita_sind(angle)

  if kind == "circle":
    shape.r = radius
    shape.hw = radius
    shape.hh = radius
    shape.ex = radius
    shape.ey = radius
  elif kind == "rect" or kind == "capsule":
    c = abs(shape.cos)
    n = abs(shape.sin)
    shape.hw = width / 2
    shape.hh = height / 2
    shape.ex = shape.hw * c + shape.hh * n
    shape.ey = shape.hw * n + shape.hh * c

  if kind == "capsule":
    shape.r = shape.hw
    shape.half = max(0, shape.hh - shape.hw)
  return shape

def chispita_rotation(s=None):
  if not s.rotate_hit_box or not s.rotation: return 0
  return s.rotation % 360

def chispita_hit_angle(s=None):
  if s.hit_box_shape == "circle": return 0
  return chispita_rotation(s)

def chispita_box_shape(s=None, shape=None, kind=None, offset_x=None, offset_y=None, width=None, height=None, radius=None):
  return chispita_place_shape(s, shape, kind, offset_x, offset_y, width, height, radius, chispita_hit_angle(s))

def chispita_part_shape(s=None, part=None):
  return chispita_place_shape(s, part.shape, part.kind, part.offset_x, part.offset_y, part.width, part.height, part.radius, chispita_rotation(s))

def chispita_sprite_shape(s=None, index=None):
  if index == 0: return chispita_hit_shape(s)
  return chispita_part_shape(s, s.hit_parts[index - 1])

def chispita_shape_count(s=None):
  if s.hit_parts: return len(s.hit_parts) + 1
  return 1

def chispita_place_shape(s=None, shape=None, kind=None, offset_x=None, offset_y=None, width=None, height=None, radius=None, angle=None):
  chispita_set_shape(shape, kind, s.x, s.y, width, height, radius, angle)
  shape.x += offset_x * shape.cos - offset_y * shape.sin
  shape.y += offset_x * shape.sin + offset_y * shape.cos
  return shape

def chispita_hit_shape(s=None):
  return chispita_box_shape(s, s.hit_shape, s.hit_box_shape, s.hit_offset_x, s.hit_offset_y, s.hit_width, s.hit_height, s.hit_radius)

def chispita_hurt_shape(s=None):
  return chispita_box_shape(s, s.hurt_shape, s.hurt_box_shape, s.hurt_offset_x, s.hurt_offset_y, s.hurt_width, s.hurt_height, s.hurt_radius)

#Choose direction of push
def chispita_use_x_axis(hit=None):
  hit.nx = hit.x_side
  hit.ny = 0
  hit.overlap = hit.ox

def chispita_use_y_axis(hit=None):
  hit.nx = 0
  hit.ny = hit.y_side
  hit.overlap = hit.oy

# Sprite test collisions
def chispita_test_rect_rect(a=None, b=None):
  if a.angle or b.angle: return chispita_test_box_box(a, b)
  ox = a.hw + b.hw - abs(a.x - b.x)
  if ox <= 0: return 0
  oy = a.hh + b.hh - abs(a.y - b.y)
  if oy <= 0: return 0

  hit = chispita_obj()
  hit.ox = ox
  hit.oy = oy
  if a.x < b.x: hit.x_side = 1
  else: hit.x_side = -1
  if a.y < b.y: hit.y_side = 1
  else: hit.y_side = -1
  if ox < oy:
    chispita_use_x_axis(hit)
  else:
    chispita_use_y_axis(hit)
  return hit

def chispita_test_box_box(a=None, b=None):
  dx = b.x - a.x
  dy = b.y - a.y
  best = -1
  best_nx = 0
  best_ny = 0
  for i in range(3 + 1):
    owner = a
    if i >= 2: owner = b
    ax = owner.cos
    ay = owner.sin
    if i % 2 == 1:
      ax = -owner.sin
      ay = owner.cos
    ra = a.hw * abs(a.cos * ax + a.sin * ay) + a.hh * abs(a.cos * ay - a.sin * ax)
    rb = b.hw * abs(b.cos * ax + b.sin * ay) + b.hh * abs(b.cos * ay - b.sin * ax)
    d = dx * ax + dy * ay
    overlap = ra + rb - abs(d)
    if overlap <= 0: return 0
    if best < 0 or overlap < best:
      best = overlap
      if d < 0:
        best_nx = -ax
        best_ny = -ay
      else:
        best_nx = ax
        best_ny = ay

  hit = chispita_obj()
  hit.nx = best_nx
  hit.ny = best_ny
  hit.overlap = best
  return hit

def chispita_test_rect_circle(r=None, c=None):
  wx = c.x - r.x
  wy = c.y - r.y
  lx = wx * r.cos + wy * r.sin
  ly = wy * r.cos - wx * r.sin

  px = max(-r.hw, min(lx, r.hw))
  py = max(-r.hh, min(ly, r.hh))
  dx = lx - px
  dy = ly - py
  distance_sq = dx * dx + dy * dy
  if distance_sq >= c.r * c.r: return 0

  distance = math.sqrt(distance_sq)
  nx = 0
  ny = 0
  overlap = 0
  if distance > 0.001:
    nx = dx / distance
    ny = dy / distance
    overlap = c.r - distance + 0.02
  else:
    to_left = lx + r.hw
    to_right = r.hw - lx
    to_bottom = ly + r.hh
    to_top = r.hh - ly
    nearest = min(min(to_left, to_right), min(to_bottom, to_top))
    if nearest == to_left:
      nx = -1
    elif nearest == to_right:
      nx = 1
    elif nearest == to_bottom:
      ny = -1
    else:
      ny = 1
    overlap = nearest + c.r + 0.02

  hit = chispita_obj()
  hit.nx = nx * r.cos - ny * r.sin
  hit.ny = nx * r.sin + ny * r.cos
  hit.overlap = overlap
  return hit

def chispita_test_circle_circle(a=None, b=None):
  dx = b.x - a.x
  dy = b.y - a.y
  radii = a.r + b.r
  distance_sq = dx * dx + dy * dy
  if distance_sq >= radii * radii: return 0

  distance = math.sqrt(distance_sq)
  hit = chispita_obj()
  if distance > 0.001:
    hit.nx = dx / distance
    hit.ny = dy / distance
  else:
    hit.nx = 0
    hit.ny = 1
  hit.overlap = radii - distance
  return hit

chispita_capsule_circle_a = chispita_obj()
chispita_capsule_circle_b = chispita_obj()
chispita_capsule_point_a = chispita_obj()
chispita_capsule_point_b = chispita_obj()

def chispita_closest_on_segment(x1=None, y1=None, x2=None, y2=None, px=None, py=None, out=None):
  dx = x2 - x1
  dy = y2 - y1
  length_sq = dx * dx + dy * dy
  t = 0
  if length_sq > 0: t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / length_sq))
  out.x = x1 + dx * t
  out.y = y1 + dy * t

def chispita_capsule_point(c=None, px=None, py=None, out=None):
  ux = -c.sin * c.half
  uy = c.cos * c.half
  chispita_closest_on_segment(c.x - ux, c.y - uy, c.x + ux, c.y + uy, px, py, out)

def chispita_closest_on_rect(r=None, px=None, py=None, out=None):
  wx = px - r.x
  wy = py - r.y
  lx = max(-r.hw, min(wx * r.cos + wy * r.sin, r.hw))
  ly = max(-r.hh, min(wy * r.cos - wx * r.sin, r.hh))
  out.x = r.x + lx * r.cos - ly * r.sin
  out.y = r.y + lx * r.sin + ly * r.cos

def chispita_circle_at(circle=None, x=None, y=None, r=None):
  circle.kind = "circle"
  circle.x = x
  circle.y = y
  circle.r = r
  return circle

def chispita_capsule_vs_circle(cap=None, circle=None):
  p = chispita_capsule_point_a
  chispita_capsule_point(cap, circle.x, circle.y, p)
  return chispita_test_circle_circle(chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, cap.r), circle)

def chispita_capsule_vs_capsule(a=None, b=None):
  p = chispita_capsule_point_a
  q = chispita_capsule_point_b
  chispita_capsule_point(a, b.x, b.y, p)
  for i in range(1, 3 + 1):
    chispita_capsule_point(b, p.x, p.y, q)
    chispita_capsule_point(a, q.x, q.y, p)
  chispita_capsule_point(b, p.x, p.y, q)
  return chispita_test_circle_circle(chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, a.r), chispita_circle_at(chispita_capsule_circle_b, q.x, q.y, b.r))

def chispita_rect_vs_capsule(rect=None, cap=None):
  p = chispita_capsule_point_a
  q = chispita_capsule_point_b
  chispita_capsule_point(cap, rect.x, rect.y, p)
  for i in range(1, 3 + 1):
    chispita_closest_on_rect(rect, p.x, p.y, q)
    chispita_capsule_point(cap, q.x, q.y, p)
  return chispita_test_rect_circle(rect, chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, cap.r))

def chispita_flip_hit(hit=None):
  if hit:
    hit.nx = -hit.nx
    hit.ny = -hit.ny
  return hit

def chispita_test_capsule(a=None, b=None):
  if a.kind == "capsule" and b.kind == "capsule": return chispita_capsule_vs_capsule(a, b)
  if a.kind == "capsule":
    if b.kind == "circle": return chispita_capsule_vs_circle(a, b)
    return chispita_flip_hit(chispita_rect_vs_capsule(b, a))
  if a.kind == "circle": return chispita_flip_hit(chispita_capsule_vs_circle(b, a))
  return chispita_rect_vs_capsule(a, b)

def chispita_test(a=None, b=None):
  if a.kind == "capsule" or b.kind == "capsule": return chispita_test_capsule(a, b)
  if a.kind == "circle" and b.kind == "circle":
    return chispita_test_circle_circle(a, b)
  elif b.kind == "circle":
    return chispita_test_rect_circle(a, b)
  elif a.kind == "circle":
    return chispita_flip_hit(chispita_test_rect_circle(b, a))
  return chispita_test_rect_rect(a, b)

# Collision responses
def chispita_movable(s=None):
  return s.solid and not s.fixed and not s.kinematic

def chispita_inverse_mass(s=None):
  if not chispita_movable(s): return 0
  if s.mass <= 0:
    chispita_warn("sprite #" + chispita_str(s.id) + " has mass " + chispita_str(s.mass) + ". Mass must be above 0, so 1 is used.")
    return 1
  return 1 / s.mass

def chispita_ground(s=None, surface=None):
  s.grounded = 1
  surface_vy = 0
  if surface.kinematic:
    s.riding = surface
    surface_vy = surface.vy
  if abs(s.vy - surface_vy) < chispita_rest_speed:
    s.vy = 0

def chispita_resolve(s1=None, s2=None, hit=None):
  nx = hit.nx
  ny = hit.ny
  w1 = chispita_inverse_mass(s1)
  w2 = chispita_inverse_mass(s2)
  total = w1 + w2
  if total <= 0: return

  push = max(hit.overlap - chispita_collision_slop, 0) * chispita_collision_push / total
  s1.x -= nx * push * w1
  s1.y -= ny * push * w1
  s2.x += nx * push * w2
  s2.y += ny * push * w2

  rvx = s2.vx - s1.vx
  rvy = s2.vy - s1.vy
  speed_into_normal = rvx * nx + rvy * ny
  if speed_into_normal < 0:
    bounce = s1.bounciness * s2.bounciness
    if -speed_into_normal < chispita_rest_speed: bounce = 0
    impulse = -(1 + bounce) * speed_into_normal / total
    s1.vx -= impulse * nx * w1
    s1.vy -= impulse * ny * w1
    s2.vx += impulse * nx * w2
    s2.vy += impulse * ny * w2

    grip = (s1.grip + s2.grip) / 2
    riding = (s2.kinematic and ny < -0.9) or (s1.kinematic and ny > 0.9)
    if grip > 0 and not riding:
      tx = -ny
      ty = nx
      slide = rvx * tx + rvy * ty
      limit = grip * impulse
      friction_impulse = max(-limit, min(-slide / total, limit))
      s1.vx -= friction_impulse * tx * w1
      s1.vy -= friction_impulse * ty * w1
      s2.vx += friction_impulse * tx * w2
      s2.vy += friction_impulse * ty * w2

  if w1 > 0 and ny < -0.9: chispita_ground(s1, s2)
  if w2 > 0 and ny > 0.9: chispita_ground(s2, s1)

def chispita_try_one_way(mover=None, platform=None, platform_top=None):
  if mover.drop_through or not chispita_movable(mover): return
  half = chispita_hit_shape(mover).ey
  old_bottom = mover.old_y + mover.hit_offset_y - half
  if mover.vy > platform.vy or old_bottom < platform_top - 0.5: return

  bottom = mover.y + mover.hit_offset_y - half
  mover.y += platform_top - bottom
  mover.vy = platform.vy - (mover.vy - platform.vy) * mover.bounciness * platform.bounciness
  chispita_ground(mover, platform)

def Chispita_ignore(group_a=None, group_b=None):
  global chispita_any_ignored
  if not group_a or not group_b:
    chispita_warn("Chispita_ignore needs two group names, like Chispita_ignore('player', 'ghost').")
    return
  chispita_ignored[chispita_str(group_a) + "|" + chispita_str(group_b)] = 1
  chispita_ignored[chispita_str(group_b) + "|" + chispita_str(group_a)] = 1
  chispita_any_ignored = 1

def Chispita_ignoreHurt(group_a=None, group_b=None):
  global chispita_any_hurt_ignored
  if not group_a or not group_b:
    chispita_warn("Chispita_ignoreHurt needs two group names, like Chispita_ignoreHurt('player', 'player').")
    return
  chispita_hurt_ignored[chispita_str(group_a) + "|" + chispita_str(group_b)] = 1
  chispita_hurt_ignored[chispita_str(group_b) + "|" + chispita_str(group_a)] = 1
  chispita_any_hurt_ignored = 1

def chispita_can_collide(s1=None, s2=None):
  if not chispita_any_ignored: return 1
  return not chispita_ignored[chispita_str(s1.group) + "|" + chispita_str(s2.group)]

def chispita_can_hurt(attacker=None, victim=None):
  if not chispita_any_hurt_ignored: return 1
  return not chispita_hurt_ignored[chispita_str(attacker.group) + "|" + chispita_str(victim.group)]

def chispita_update_bounds(s=None):
  shape = chispita_hit_shape(s)
  s.left = shape.x - shape.ex
  s.right = shape.x + shape.ex
  s.bottom = shape.y - shape.ey
  s.top = shape.y + shape.ey
  if s.hit_parts:
    for part in s.hit_parts:
      p = chispita_part_shape(s, part)
      s.left = min(s.left, p.x - p.ex)
      s.right = max(s.right, p.x + p.ex)
      s.bottom = min(s.bottom, p.y - p.ey)
      s.top = max(s.top, p.y + p.ey)

def chispita_sort_by_left(list=None):
  for i in range(1, len(list)):
    s = list[i]
    j = i - 1
    while j >= 0:
      if list[j].left <= s.left: break
      list[j + 1] = list[j]
      j -= 1
    list[j + 1] = s

def chispita_record_contact(s1=None, s2=None):
  if s1.trigger: s1.contacts[s2.id] = s2
  if s2.trigger: s2.contacts[s1.id] = s1

def chispita_collide_pair(s1=None, s2=None):
  a = chispita_hit_shape(s1)
  b = chispita_hit_shape(s2)
  hit = chispita_test(a, b)
  if s1.hit_parts or s2.hit_parts:
    for i in range(chispita_shape_count(s1)):
      for j in range(chispita_shape_count(s2)):
        if i == 0 and j == 0: continue
        sa = chispita_sprite_shape(s1, i)
        sb = chispita_sprite_shape(s2, j)
        h = chispita_test(sa, sb)
        if h and (not hit or h.overlap > hit.overlap):
          hit = h
          a = sa
          b = sb
  if not hit: return

  chispita_record_contact(s1, s2)
  if not (s1.solid and s2.solid): return
  if s1.one_way and s2.one_way: return
  if s2.one_way:
    chispita_try_one_way(s1, s2, b.y + b.ey)
  elif s1.one_way:
    chispita_try_one_way(s2, s1, a.y + a.ey)
  else:
    chispita_resolve(s1, s2, hit)
    if s1.on_hit: s1.hit_list[s2.id] = s2
    if s2.on_hit: s2.hit_list[s1.id] = s1

chispita_step_passes = 0

def chispita_check_collisions():
  passes = chispita_step_passes
  if passes < 1: passes = chispita_collision_passes
  for pass_number in range(1, passes + 1):
    chispita_collision_pass()

def chispita_collision_pass():
  for s in chispita_sprites:
    if s.active and s.physics: chispita_update_bounds(s)
  chispita_sort_by_left(chispita_sprites)

  n = len(chispita_sprites)
  for i in range(n):
    s1 = chispita_sprites[i]
    if not (s1.active and s1.physics): continue
    s1_matters = chispita_movable(s1) or s1.trigger
    for j in range(i + 1, n):
      s2 = chispita_sprites[j]
      if not (s2.active and s2.physics): continue
      if s2.left > s1.right: break
      if s2.bottom > s1.top or s2.top < s1.bottom: continue
      if not (s1_matters or chispita_movable(s2) or s2.trigger): continue
      if chispita_can_collide(s1, s2):
        chispita_collide_pair(s1, s2)

def chispita_fire_contact_events():
  for s in chispita_sprites:
    if s.trigger:
      for id in s.contacts:
        other = s.contacts[id]
        if s.on_enter and not s.old_contacts[id]:
          f = s.on_enter
          f(s, other)
        if s.callback:
          f = s.callback
          f(s, other)
      for id in s.old_contacts:
        if s.on_exit and not s.contacts[id]:
          f = s.on_exit
          f(s, s.old_contacts[id])

    if s.on_hit:
      for id in s.hit_list:
        if not s.old_hit_list[id]:
          f = s.on_hit
          f(s, s.hit_list[id])

    if s.tile_touched:
      for key in s.tile_contacts:
        tile = s.tile_contacts[key]
        if s.trigger and s.on_tile:
          f = s.on_tile
          f(s, tile)
        if tile.map.callback:
          f = tile.map.callback
          f(s, tile)

def chispita_check_hurt_boxes():
  attackers = 0
  for a in chispita_sprites:
    if a.hurt_box and a.active:
      attackers += 1
    elif a.was_hurting:
      a.hurting = chispita_obj()
      a.was_hurting = 0
  if attackers == 0: return

  for s in chispita_sprites:
    if s.active and s.physics: chispita_update_bounds(s)

  for a in chispita_sprites:
    if not (a.hurt_box and a.active): continue
    a.was_hurting = 1
    hurt = chispita_hurt_shape(a)
    left = hurt.x - hurt.ex
    right = hurt.x + hurt.ex
    bottom = hurt.y - hurt.ey
    top = hurt.y + hurt.ey
    if a.hurt_parts:
      for part in a.hurt_parts:
        p = chispita_part_shape(a, part)
        left = min(left, p.x - p.ex)
        right = max(right, p.x + p.ex)
        bottom = min(bottom, p.y - p.ey)
        top = max(top, p.y + p.ey)
    for b in chispita_sprites:
      if b == a or not (b.active and b.physics): continue
      if b.left > right or b.right < left or b.bottom > top or b.top < bottom: continue
      if not chispita_can_hurt(a, b): continue
      if a.hurting[b.id]: continue
      if chispita_hurt_touches(a, hurt, b):
        a.hurting[b.id] = b
        if a.on_hurt:
          f = a.on_hurt
          f(a, b)

# Collision response questions
def chispita_shape_touches(shape=None, s=None):
  if chispita_test(shape, chispita_hit_shape(s)): return 1
  if s.hit_parts:
    for part in s.hit_parts:
      if chispita_test(shape, chispita_part_shape(s, part)): return 1
  return 0

def chispita_hurt_touches(a=None, hurt=None, b=None):
  if chispita_shape_touches(hurt, b): return 1
  if a.hurt_parts:
    for part in a.hurt_parts:
      if chispita_shape_touches(part.shape, b): return 1
  return 0

def Chispita_overlaps(a=None, b=None):
  for i in range(chispita_shape_count(a)):
    if chispita_shape_touches(chispita_sprite_shape(a, i), b): return 1
  return 0

def Chispita_pointIn(s=None, x=None, y=None):
  for i in range(chispita_shape_count(s)):
    if chispita_point_in_shape(chispita_sprite_shape(s, i), x, y): return 1
  return 0

def chispita_point_in_shape(shape=None, x=None, y=None):
  dx = x - shape.x
  dy = y - shape.y
  if shape.kind == "circle":
    return dx * dx + dy * dy < shape.r * shape.r
  if shape.kind == "capsule":
    p = chispita_capsule_point_a
    chispita_capsule_point(shape, x, y, p)
    return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) < shape.r * shape.r
  lx = dx * shape.cos + dy * shape.sin
  ly = dy * shape.cos - dx * shape.sin
  return abs(lx) < shape.hw and abs(ly) < shape.hh

def Chispita_findGroup(group=None):
  list = []
  for s in chispita_sprites:
    if s.active and s.group == group: list.append(s)
  return list

chispita_query_shape = chispita_obj()

def Chispita_spritesIn(x=None, y=None, width=None, height=None):
  list = []
  if width <= 0 or height <= 0:
    chispita_warn("Chispita_spritesIn needs a width and height above 0.")
    return list
  area = chispita_set_shape(chispita_query_shape, "rect", x, y, width, height, 0, 0)
  for s in chispita_sprites:
    if s.active and chispita_shape_touches(area, s): list.append(s)
  return list

def chispita_ray_slab(start=None, move=None, half=None, t=None):
  if abs(move) < 0.000001:
    if start < -half or start > half: t.miss = 1
    return
  t1 = (-half - start) / move
  t2 = (half - start) / move
  if t1 > t2:
    swap = t1
    t1 = t2
    t2 = swap
  t.near = max(t.near, t1)
  t.far = min(t.far, t2)
  if t.near > t.far: t.miss = 1

def chispita_ray_circle(cx=None, cy=None, r=None, x1=None, y1=None, dx=None, dy=None):
  fx = x1 - cx
  fy = y1 - cy
  a = dx * dx + dy * dy
  b = 2 * (fx * dx + fy * dy)
  c = fx * fx + fy * fy - r * r
  if c <= 0: return 0
  disc = b * b - 4 * a * c
  if disc < 0: return -1
  t = (-b - math.sqrt(disc)) / (2 * a)
  if t < 0 or t > 1: return -1
  return t

chispita_ray_span = chispita_obj()

def chispita_ray_box(shape=None, half_w=None, half_h=None, x1=None, y1=None, dx=None, dy=None):
  fx = x1 - shape.x
  fy = y1 - shape.y
  lx = fx * shape.cos + fy * shape.sin
  ly = fy * shape.cos - fx * shape.sin
  ldx = dx * shape.cos + dy * shape.sin
  ldy = dy * shape.cos - dx * shape.sin
  t = chispita_ray_span
  t.near = 0
  t.far = 1
  t.miss = 0
  chispita_ray_slab(lx, ldx, half_w, t)
  if not t.miss: chispita_ray_slab(ly, ldy, half_h, t)
  if t.miss: return -1
  return t.near

def chispita_ray_nearest(a=None, b=None):
  if a < 0: return b
  if b < 0: return a
  return min(a, b)

def chispita_ray_shape(shape=None, x1=None, y1=None, dx=None, dy=None):
  if shape.kind == "circle":
    return chispita_ray_circle(shape.x, shape.y, shape.r, x1, y1, dx, dy)
  if shape.kind == "capsule":
    ux = -shape.sin * shape.half
    uy = shape.cos * shape.half
    t = chispita_ray_box(shape, shape.r, shape.half, x1, y1, dx, dy)
    t = chispita_ray_nearest(t, chispita_ray_circle(shape.x - ux, shape.y - uy, shape.r, x1, y1, dx, dy))
    return chispita_ray_nearest(t, chispita_ray_circle(shape.x + ux, shape.y + uy, shape.r, x1, y1, dx, dy))
  return chispita_ray_box(shape, shape.hw, shape.hh, x1, y1, dx, dy)

def chispita_ray_sprite(s=None, x1=None, y1=None, dx=None, dy=None):
  t = chispita_ray_shape(chispita_hit_shape(s), x1, y1, dx, dy)
  if s.hit_parts:
    for part in s.hit_parts:
      t = chispita_ray_nearest(t, chispita_ray_shape(chispita_part_shape(s, part), x1, y1, dx, dy))
  return t

def Chispita_raycast(x1=None, y1=None, x2=None, y2=None, ignore=None):
  dx = x2 - x1
  dy = y2 - y1
  length = math.sqrt(dx * dx + dy * dy)
  if length == 0: return 0

  best = 2
  best_sprite = 0
  for s in chispita_sprites:
    if s == ignore or not (s.active and s.physics and s.solid): continue
    t = chispita_ray_sprite(s, x1, y1, dx, dy)
    if t >= 0 and t < best:
      best = t
      best_sprite = s

  best_tile = 0
  for m in chispita_maps:
    if not (m.map and m.physics and m.active): continue
    found = chispita_ray_map(m, x1, y1, dx, dy, best)
    if found and found.t < best:
      best = found.t
      best_tile = found.tile
      best_sprite = 0

  if best > 1: return 0
  hit = chispita_obj()
  hit.x = x1 + dx * best
  hit.y = y1 + dy * best
  hit.distance = length * best
  hit.sprite = best_sprite
  hit.tile = best_tile
  return hit
