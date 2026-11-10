local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt
local function sind(a) return math.sin(a * math.pi / 180) end
local function cosd(a) return math.cos(a * math.pi / 180) end

chispita_ignored = {}
chispita_hurt_ignored = {}
chispita_any_ignored = false
chispita_any_hurt_ignored = false

-- Set sprite shapes
function chispita_set_shape(shape, kind, x, y, width, height, radius, angle)
  if kind ~= "rect" and kind ~= "circle" and kind ~= "capsule" then
    chispita_warn("unknown hit box shape '" .. tostring(kind) .. "'. Use 'rect', 'circle' or 'capsule'.")
    kind = "rect"
  end
  if not angle then angle = 0 end
  shape.kind = kind
  shape.x = x
  shape.y = y
  shape.angle = angle
  shape.cos = 1
  shape.sin = 0
  if angle ~= 0 then
    shape.cos = cosd(angle)
    shape.sin = sind(angle)
  end

  if kind == "circle" then
    shape.r = radius
    shape.hw = radius
    shape.hh = radius
    shape.ex = radius
    shape.ey = radius
  elseif kind == "rect" or kind == "capsule" then
    local c = abs(shape.cos)
    local n = abs(shape.sin)
    shape.hw = width / 2
    shape.hh = height / 2
    shape.ex = shape.hw * c + shape.hh * n
    shape.ey = shape.hw * n + shape.hh * c
  end

  if kind == "capsule" then
    shape.r = shape.hw
    shape.half = max(0, shape.hh - shape.hw)
  end
  return shape
end

function chispita_rotation(s)
  if not s.rotate_hit_box or not s.rotation then return 0 end
  return s.rotation % 360
end

function chispita_hit_angle(s)
  if s.hit_box_shape == "circle" then return 0 end
  return chispita_rotation(s)
end

function chispita_box_shape(s, shape, kind, offset_x, offset_y, width, height, radius)
  return chispita_place_shape(s, shape, kind, offset_x, offset_y, width, height, radius, chispita_hit_angle(s))
end

function chispita_part_shape(s, part)
  return chispita_place_shape(s, part.shape, part.kind, part.offset_x, part.offset_y, part.width, part.height, part.radius, chispita_rotation(s))
end

-- Shape 0 is the sprite's own hit box, shapes 1 and up are its parts.
function chispita_sprite_shape(s, index)
  if index == 0 then return chispita_hit_shape(s) end
  return chispita_part_shape(s, s.hit_parts[index])
end

function chispita_shape_count(s)
  if s.hit_parts then return #s.hit_parts + 1 end
  return 1
end

function chispita_place_shape(s, shape, kind, offset_x, offset_y, width, height, radius, angle)
  chispita_set_shape(shape, kind, s.x, s.y, width, height, radius, angle)
  shape.x = shape.x + offset_x * shape.cos - offset_y * shape.sin
  shape.y = shape.y + offset_x * shape.sin + offset_y * shape.cos
  return shape
end

function chispita_hit_shape(s)
  return chispita_box_shape(s, s.hit_shape, s.hit_box_shape, s.hit_offset_x, s.hit_offset_y, s.hit_width, s.hit_height, s.hit_radius)
end

function chispita_hurt_shape(s)
  return chispita_box_shape(s, s.hurt_shape, s.hurt_box_shape, s.hurt_offset_x, s.hurt_offset_y, s.hurt_width, s.hurt_height, s.hurt_radius)
end

--Choose direction of push
function chispita_use_x_axis(hit)
  hit.nx = hit.x_side
  hit.ny = 0
  hit.overlap = hit.ox
end

function chispita_use_y_axis(hit)
  hit.nx = 0
  hit.ny = hit.y_side
  hit.overlap = hit.oy
end

-- Sprite test collisions. Each test gives back a hit (the direction to
-- push, nx/ny, and how deep the overlap is) or false.
function chispita_test_rect_rect(a, b)
  if a.angle ~= 0 or b.angle ~= 0 then return chispita_test_box_box(a, b) end
  local ox = a.hw + b.hw - abs(a.x - b.x)
  if ox <= 0 then return false end
  local oy = a.hh + b.hh - abs(a.y - b.y)
  if oy <= 0 then return false end

  local hit = {}
  hit.ox = ox
  hit.oy = oy
  if a.x < b.x then hit.x_side = 1 else hit.x_side = -1 end
  if a.y < b.y then hit.y_side = 1 else hit.y_side = -1 end
  if ox < oy then
    chispita_use_x_axis(hit)
  else
    chispita_use_y_axis(hit)
  end
  return hit
end

function chispita_test_box_box(a, b)
  local dx = b.x - a.x
  local dy = b.y - a.y
  local best = -1
  local best_nx = 0
  local best_ny = 0
  for i = 0, 3 do
    local owner = a
    if i >= 2 then owner = b end
    local ax = owner.cos
    local ay = owner.sin
    if i % 2 == 1 then
      ax = -owner.sin
      ay = owner.cos
    end
    local ra = a.hw * abs(a.cos * ax + a.sin * ay) + a.hh * abs(a.cos * ay - a.sin * ax)
    local rb = b.hw * abs(b.cos * ax + b.sin * ay) + b.hh * abs(b.cos * ay - b.sin * ax)
    local d = dx * ax + dy * ay
    local overlap = ra + rb - abs(d)
    if overlap <= 0 then return false end
    if best < 0 or overlap < best then
      best = overlap
      if d < 0 then
        best_nx = -ax
        best_ny = -ay
      else
        best_nx = ax
        best_ny = ay
      end
    end
  end

  local hit = {}
  hit.nx = best_nx
  hit.ny = best_ny
  hit.overlap = best
  return hit
end

function chispita_test_rect_circle(r, c)
  local wx = c.x - r.x
  local wy = c.y - r.y
  local lx = wx * r.cos + wy * r.sin
  local ly = wy * r.cos - wx * r.sin

  local px = max(-r.hw, min(lx, r.hw))
  local py = max(-r.hh, min(ly, r.hh))
  local dx = lx - px
  local dy = ly - py
  local distance_sq = dx * dx + dy * dy
  if distance_sq >= c.r * c.r then return false end

  local distance = sqrt(distance_sq)
  local nx = 0
  local ny = 0
  local overlap = 0
  if distance > 0.001 then
    nx = dx / distance
    ny = dy / distance
    overlap = c.r - distance + 0.02
  else
    local to_left = lx + r.hw
    local to_right = r.hw - lx
    local to_bottom = ly + r.hh
    local to_top = r.hh - ly
    local nearest = min(min(to_left, to_right), min(to_bottom, to_top))
    if nearest == to_left then
      nx = -1
    elseif nearest == to_right then
      nx = 1
    elseif nearest == to_bottom then
      ny = -1
    else
      ny = 1
    end
    overlap = nearest + c.r + 0.02
  end

  local hit = {}
  hit.nx = nx * r.cos - ny * r.sin
  hit.ny = nx * r.sin + ny * r.cos
  hit.overlap = overlap
  return hit
end

function chispita_test_circle_circle(a, b)
  local dx = b.x - a.x
  local dy = b.y - a.y
  local radii = a.r + b.r
  local distance_sq = dx * dx + dy * dy
  if distance_sq >= radii * radii then return false end

  local distance = sqrt(distance_sq)
  local hit = {}
  if distance > 0.001 then
    hit.nx = dx / distance
    hit.ny = dy / distance
  else
    hit.nx = 0
    hit.ny = 1
  end
  hit.overlap = radii - distance
  return hit
end

chispita_capsule_circle_a = {}
chispita_capsule_circle_b = {}
chispita_capsule_point_a = {}
chispita_capsule_point_b = {}

function chispita_closest_on_segment(x1, y1, x2, y2, px, py, out)
  local dx = x2 - x1
  local dy = y2 - y1
  local length_sq = dx * dx + dy * dy
  local t = 0
  if length_sq > 0 then t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / length_sq)) end
  out.x = x1 + dx * t
  out.y = y1 + dy * t
end

function chispita_capsule_point(c, px, py, out)
  local ux = -c.sin * c.half
  local uy = c.cos * c.half
  chispita_closest_on_segment(c.x - ux, c.y - uy, c.x + ux, c.y + uy, px, py, out)
end

function chispita_closest_on_rect(r, px, py, out)
  local wx = px - r.x
  local wy = py - r.y
  local lx = max(-r.hw, min(wx * r.cos + wy * r.sin, r.hw))
  local ly = max(-r.hh, min(wy * r.cos - wx * r.sin, r.hh))
  out.x = r.x + lx * r.cos - ly * r.sin
  out.y = r.y + lx * r.sin + ly * r.cos
end

function chispita_circle_at(circle, x, y, r)
  circle.kind = "circle"
  circle.x = x
  circle.y = y
  circle.r = r
  return circle
end

function chispita_capsule_vs_circle(cap, circle)
  local p = chispita_capsule_point_a
  chispita_capsule_point(cap, circle.x, circle.y, p)
  return chispita_test_circle_circle(chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, cap.r), circle)
end

function chispita_capsule_vs_capsule(a, b)
  local p = chispita_capsule_point_a
  local q = chispita_capsule_point_b
  chispita_capsule_point(a, b.x, b.y, p)
  for i = 1, 3 do
    chispita_capsule_point(b, p.x, p.y, q)
    chispita_capsule_point(a, q.x, q.y, p)
  end
  chispita_capsule_point(b, p.x, p.y, q)
  return chispita_test_circle_circle(chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, a.r), chispita_circle_at(chispita_capsule_circle_b, q.x, q.y, b.r))
end

function chispita_rect_vs_capsule(rect, cap)
  local p = chispita_capsule_point_a
  local q = chispita_capsule_point_b
  chispita_capsule_point(cap, rect.x, rect.y, p)
  for i = 1, 3 do
    chispita_closest_on_rect(rect, p.x, p.y, q)
    chispita_capsule_point(cap, q.x, q.y, p)
  end
  return chispita_test_rect_circle(rect, chispita_circle_at(chispita_capsule_circle_a, p.x, p.y, cap.r))
end

function chispita_flip_hit(hit)
  if hit then
    hit.nx = -hit.nx
    hit.ny = -hit.ny
  end
  return hit
end

function chispita_test_capsule(a, b)
  if a.kind == "capsule" and b.kind == "capsule" then return chispita_capsule_vs_capsule(a, b) end
  if a.kind == "capsule" then
    if b.kind == "circle" then return chispita_capsule_vs_circle(a, b) end
    return chispita_flip_hit(chispita_rect_vs_capsule(b, a))
  end
  if a.kind == "circle" then return chispita_flip_hit(chispita_capsule_vs_circle(b, a)) end
  return chispita_rect_vs_capsule(a, b)
end

function chispita_test(a, b)
  if a.kind == "capsule" or b.kind == "capsule" then return chispita_test_capsule(a, b) end
  if a.kind == "circle" and b.kind == "circle" then
    return chispita_test_circle_circle(a, b)
  elseif b.kind == "circle" then
    return chispita_test_rect_circle(a, b)
  elseif a.kind == "circle" then
    return chispita_flip_hit(chispita_test_rect_circle(b, a))
  end
  return chispita_test_rect_rect(a, b)
end

-- Collision responses
function chispita_movable(s)
  return s.solid and not s.fixed and not s.kinematic
end

function chispita_inverse_mass(s)
  if not chispita_movable(s) then return 0 end
  if s.mass <= 0 then
    chispita_warn("sprite #" .. s.id .. " has mass " .. s.mass .. ". Mass must be above 0, so 1 is used.")
    return 1
  end
  return 1 / s.mass
end

function chispita_ground(s, surface)
  s.grounded = true
  local surface_vy = 0
  if surface.kinematic then
    s.riding = surface
    surface_vy = surface.vy
  end
  if abs(s.vy - surface_vy) < chispita_rest_speed then
    s.vy = 0
  end
end

function chispita_resolve(s1, s2, hit)
  local nx = hit.nx
  local ny = hit.ny
  local w1 = chispita_inverse_mass(s1)
  local w2 = chispita_inverse_mass(s2)
  local total = w1 + w2
  if total <= 0 then return end

  local push = max(hit.overlap - chispita_collision_slop, 0) * chispita_collision_push / total
  s1.x = s1.x - nx * push * w1
  s1.y = s1.y - ny * push * w1
  s2.x = s2.x + nx * push * w2
  s2.y = s2.y + ny * push * w2

  local rvx = s2.vx - s1.vx
  local rvy = s2.vy - s1.vy
  local speed_into_normal = rvx * nx + rvy * ny
  if speed_into_normal < 0 then
    local bounce = s1.bounciness * s2.bounciness
    if -speed_into_normal < chispita_rest_speed then bounce = 0 end
    local impulse = -(1 + bounce) * speed_into_normal / total
    s1.vx = s1.vx - impulse * nx * w1
    s1.vy = s1.vy - impulse * ny * w1
    s2.vx = s2.vx + impulse * nx * w2
    s2.vy = s2.vy + impulse * ny * w2

    local grip = (s1.grip + s2.grip) / 2
    local riding = (s2.kinematic and ny < -0.9) or (s1.kinematic and ny > 0.9)
    if grip > 0 and not riding then
      local tx = -ny
      local ty = nx
      local slide = rvx * tx + rvy * ty
      local limit = grip * impulse
      local friction_impulse = max(-limit, min(-slide / total, limit))
      s1.vx = s1.vx - friction_impulse * tx * w1
      s1.vy = s1.vy - friction_impulse * ty * w1
      s2.vx = s2.vx + friction_impulse * tx * w2
      s2.vy = s2.vy + friction_impulse * ty * w2
    end
  end

  if w1 > 0 and ny < -0.9 then chispita_ground(s1, s2) end
  if w2 > 0 and ny > 0.9 then chispita_ground(s2, s1) end
end

function chispita_try_one_way(mover, platform, platform_top)
  if mover.drop_through or not chispita_movable(mover) then return end
  local half = chispita_hit_shape(mover).ey
  local old_bottom = mover.old_y + mover.hit_offset_y - half
  if mover.vy > platform.vy or old_bottom < platform_top - 0.5 then return end

  local bottom = mover.y + mover.hit_offset_y - half
  mover.y = mover.y + platform_top - bottom
  mover.vy = platform.vy - (mover.vy - platform.vy) * mover.bounciness * platform.bounciness
  chispita_ground(mover, platform)
end

function Chispita_ignore(group_a, group_b)
  if not group_a or not group_b then
    chispita_warn("Chispita_ignore needs two group names, like Chispita_ignore('player', 'ghost').")
    return
  end
  chispita_ignored[group_a .. "|" .. group_b] = true
  chispita_ignored[group_b .. "|" .. group_a] = true
  chispita_any_ignored = true
end

function Chispita_ignoreHurt(group_a, group_b)
  if not group_a or not group_b then
    chispita_warn("Chispita_ignoreHurt needs two group names, like Chispita_ignoreHurt('player', 'player').")
    return
  end
  chispita_hurt_ignored[group_a .. "|" .. group_b] = true
  chispita_hurt_ignored[group_b .. "|" .. group_a] = true
  chispita_any_hurt_ignored = true
end

function chispita_can_collide(s1, s2)
  if not chispita_any_ignored then return true end
  return not chispita_ignored[s1.group .. "|" .. s2.group]
end

function chispita_can_hurt(attacker, victim)
  if not chispita_any_hurt_ignored then return true end
  return not chispita_hurt_ignored[attacker.group .. "|" .. victim.group]
end

function chispita_update_bounds(s)
  local shape = chispita_hit_shape(s)
  s.left = shape.x - shape.ex
  s.right = shape.x + shape.ex
  s.bottom = shape.y - shape.ey
  s.top = shape.y + shape.ey
  if s.hit_parts then
    for _, part in ipairs(s.hit_parts) do
      local p = chispita_part_shape(s, part)
      s.left = min(s.left, p.x - p.ex)
      s.right = max(s.right, p.x + p.ex)
      s.bottom = min(s.bottom, p.y - p.ey)
      s.top = max(s.top, p.y + p.ey)
    end
  end
end

function chispita_sort_by_left(list)
  for i = 2, #list do
    local s = list[i]
    local j = i - 1
    while j >= 1 do
      if list[j].left <= s.left then break end
      list[j + 1] = list[j]
      j = j - 1
    end
    list[j + 1] = s
  end
end

function chispita_record_contact(s1, s2)
  if s1.trigger then s1.contacts[s2.id] = s2 end
  if s2.trigger then s2.contacts[s1.id] = s1 end
end

function chispita_collide_pair(s1, s2)
  local a = chispita_hit_shape(s1)
  local b = chispita_hit_shape(s2)
  local hit = chispita_test(a, b)
  if s1.hit_parts or s2.hit_parts then
    for i = 0, chispita_shape_count(s1) - 1 do
      for j = 0, chispita_shape_count(s2) - 1 do
        if not (i == 0 and j == 0) then
          local sa = chispita_sprite_shape(s1, i)
          local sb = chispita_sprite_shape(s2, j)
          local h = chispita_test(sa, sb)
          if h and (not hit or h.overlap > hit.overlap) then
            hit = h
            a = sa
            b = sb
          end
        end
      end
    end
  end
  if not hit then return end

  chispita_record_contact(s1, s2)
  if not (s1.solid and s2.solid) then return end
  if s1.one_way and s2.one_way then return end
  if s2.one_way then
    chispita_try_one_way(s1, s2, b.y + b.ey)
  elseif s1.one_way then
    chispita_try_one_way(s2, s1, a.y + a.ey)
  else
    chispita_resolve(s1, s2, hit)
    if s1.on_hit then s1.hit_list[s2.id] = s2 end
    if s2.on_hit then s2.hit_list[s1.id] = s1 end
  end
end

chispita_step_passes = 0

function chispita_check_collisions()
  local passes = chispita_step_passes
  if passes < 1 then passes = chispita_collision_passes end
  for pass = 1, passes do
    chispita_collision_pass()
  end
end

function chispita_collision_pass()
  for _, s in ipairs(chispita_sprites) do
    if s.active and s.physics then chispita_update_bounds(s) end
  end
  chispita_sort_by_left(chispita_sprites)

  local n = #chispita_sprites
  for i = 1, n do
    local s1 = chispita_sprites[i]
    if s1.active and s1.physics then
      local s1_matters = chispita_movable(s1) or s1.trigger
      for j = i + 1, n do
        local s2 = chispita_sprites[j]
        if s2.active and s2.physics then
          if s2.left > s1.right then break end
          if not (s2.bottom > s1.top or s2.top < s1.bottom)
              and (s1_matters or chispita_movable(s2) or s2.trigger)
              and chispita_can_collide(s1, s2) then
            chispita_collide_pair(s1, s2)
          end
        end
      end
    end
  end
end

function chispita_fire_contact_events()
  for _, s in ipairs(chispita_sprites) do
    if s.trigger then
      for id, other in pairs(s.contacts) do
        if s.on_enter and not s.old_contacts[id] then
          local f = s.on_enter
          f(s, other)
        end
        if s.callback then
          local f = s.callback
          f(s, other)
        end
      end
      for id, other in pairs(s.old_contacts) do
        if s.on_exit and not s.contacts[id] then
          local f = s.on_exit
          f(s, other)
        end
      end
    end

    if s.on_hit then
      for id, other in pairs(s.hit_list) do
        if not s.old_hit_list[id] then
          local f = s.on_hit
          f(s, other)
        end
      end
    end

    if s.tile_touched then
      for key, tile in pairs(s.tile_contacts) do
        if s.trigger and s.on_tile then
          local f = s.on_tile
          f(s, tile)
        end
        if tile.map.callback then
          local f = tile.map.callback
          f(s, tile)
        end
      end
    end
  end
end

function chispita_check_hurt_boxes()
  local attackers = 0
  for _, a in ipairs(chispita_sprites) do
    if a.hurt_box and a.active then
      attackers = attackers + 1
    elseif a.was_hurting then
      a.hurting = {}
      a.was_hurting = false
    end
  end
  if attackers == 0 then return end

  for _, s in ipairs(chispita_sprites) do
    if s.active and s.physics then chispita_update_bounds(s) end
  end

  for _, a in ipairs(chispita_sprites) do
    if a.hurt_box and a.active then
      a.was_hurting = true
      local hurt = chispita_hurt_shape(a)
      local left = hurt.x - hurt.ex
      local right = hurt.x + hurt.ex
      local bottom = hurt.y - hurt.ey
      local top = hurt.y + hurt.ey
      if a.hurt_parts then
        for _, part in ipairs(a.hurt_parts) do
          local p = chispita_part_shape(a, part)
          left = min(left, p.x - p.ex)
          right = max(right, p.x + p.ex)
          bottom = min(bottom, p.y - p.ey)
          top = max(top, p.y + p.ey)
        end
      end
      for _, b in ipairs(chispita_sprites) do
        if b ~= a and b.active and b.physics
            and not (b.left > right or b.right < left or b.bottom > top or b.top < bottom)
            and chispita_can_hurt(a, b)
            and not a.hurting[b.id]
            and chispita_hurt_touches(a, hurt, b) then
          a.hurting[b.id] = b
          if a.on_hurt then
            local f = a.on_hurt
            f(a, b)
          end
        end
      end
    end
  end
end

-- Collision response questions
function chispita_shape_touches(shape, s)
  if chispita_test(shape, chispita_hit_shape(s)) then return true end
  if s.hit_parts then
    for _, part in ipairs(s.hit_parts) do
      if chispita_test(shape, chispita_part_shape(s, part)) then return true end
    end
  end
  return false
end

function chispita_hurt_touches(a, hurt, b)
  if chispita_shape_touches(hurt, b) then return true end
  if a.hurt_parts then
    for _, part in ipairs(a.hurt_parts) do
      if chispita_shape_touches(part.shape, b) then return true end
    end
  end
  return false
end

function Chispita_overlaps(a, b)
  for i = 0, chispita_shape_count(a) - 1 do
    if chispita_shape_touches(chispita_sprite_shape(a, i), b) then return true end
  end
  return false
end

function Chispita_pointIn(s, x, y)
  for i = 0, chispita_shape_count(s) - 1 do
    if chispita_point_in_shape(chispita_sprite_shape(s, i), x, y) then return true end
  end
  return false
end

function chispita_point_in_shape(shape, x, y)
  local dx = x - shape.x
  local dy = y - shape.y
  if shape.kind == "circle" then
    return dx * dx + dy * dy < shape.r * shape.r
  end
  if shape.kind == "capsule" then
    local p = chispita_capsule_point_a
    chispita_capsule_point(shape, x, y, p)
    return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) < shape.r * shape.r
  end
  local lx = dx * shape.cos + dy * shape.sin
  local ly = dy * shape.cos - dx * shape.sin
  return abs(lx) < shape.hw and abs(ly) < shape.hh
end

function Chispita_findGroup(group)
  local list = {}
  for _, s in ipairs(chispita_sprites) do
    if s.active and s.group == group then table.insert(list, s) end
  end
  return list
end

chispita_query_shape = {}

function Chispita_spritesIn(x, y, width, height)
  local list = {}
  if width <= 0 or height <= 0 then
    chispita_warn("Chispita_spritesIn needs a width and height above 0.")
    return list
  end
  local area = chispita_set_shape(chispita_query_shape, "rect", x, y, width, height, 0, 0)
  for _, s in ipairs(chispita_sprites) do
    if s.active and chispita_shape_touches(area, s) then table.insert(list, s) end
  end
  return list
end

function chispita_ray_slab(start, move, half, t)
  if abs(move) < 0.000001 then
    if start < -half or start > half then t.miss = true end
    return
  end
  local t1 = (-half - start) / move
  local t2 = (half - start) / move
  if t1 > t2 then
    local swap = t1
    t1 = t2
    t2 = swap
  end
  t.near = max(t.near, t1)
  t.far = min(t.far, t2)
  if t.near > t.far then t.miss = true end
end

-- Ray tests give back how far along the ray the hit is (0 to 1), or -1.
function chispita_ray_circle(cx, cy, r, x1, y1, dx, dy)
  local fx = x1 - cx
  local fy = y1 - cy
  local a = dx * dx + dy * dy
  local b = 2 * (fx * dx + fy * dy)
  local c = fx * fx + fy * fy - r * r
  if c <= 0 then return 0 end
  local disc = b * b - 4 * a * c
  if disc < 0 then return -1 end
  local t = (-b - sqrt(disc)) / (2 * a)
  if t < 0 or t > 1 then return -1 end
  return t
end

chispita_ray_span = {}

function chispita_ray_box(shape, half_w, half_h, x1, y1, dx, dy)
  local fx = x1 - shape.x
  local fy = y1 - shape.y
  local lx = fx * shape.cos + fy * shape.sin
  local ly = fy * shape.cos - fx * shape.sin
  local ldx = dx * shape.cos + dy * shape.sin
  local ldy = dy * shape.cos - dx * shape.sin
  local t = chispita_ray_span
  t.near = 0
  t.far = 1
  t.miss = false
  chispita_ray_slab(lx, ldx, half_w, t)
  if not t.miss then chispita_ray_slab(ly, ldy, half_h, t) end
  if t.miss then return -1 end
  return t.near
end

function chispita_ray_nearest(a, b)
  if a < 0 then return b end
  if b < 0 then return a end
  return min(a, b)
end

function chispita_ray_shape(shape, x1, y1, dx, dy)
  if shape.kind == "circle" then
    return chispita_ray_circle(shape.x, shape.y, shape.r, x1, y1, dx, dy)
  end
  if shape.kind == "capsule" then
    local ux = -shape.sin * shape.half
    local uy = shape.cos * shape.half
    local t = chispita_ray_box(shape, shape.r, shape.half, x1, y1, dx, dy)
    t = chispita_ray_nearest(t, chispita_ray_circle(shape.x - ux, shape.y - uy, shape.r, x1, y1, dx, dy))
    return chispita_ray_nearest(t, chispita_ray_circle(shape.x + ux, shape.y + uy, shape.r, x1, y1, dx, dy))
  end
  return chispita_ray_box(shape, shape.hw, shape.hh, x1, y1, dx, dy)
end

function chispita_ray_sprite(s, x1, y1, dx, dy)
  local t = chispita_ray_shape(chispita_hit_shape(s), x1, y1, dx, dy)
  if s.hit_parts then
    for _, part in ipairs(s.hit_parts) do
      t = chispita_ray_nearest(t, chispita_ray_shape(chispita_part_shape(s, part), x1, y1, dx, dy))
    end
  end
  return t
end

-- Gives back the first thing the line from x1, y1 to x2, y2 hits, or false.
function Chispita_raycast(x1, y1, x2, y2, ignore)
  local dx = x2 - x1
  local dy = y2 - y1
  local length = sqrt(dx * dx + dy * dy)
  if length == 0 then return false end

  local best = 2
  local best_sprite = false
  for _, s in ipairs(chispita_sprites) do
    if s ~= ignore and s.active and s.physics and s.solid then
      local t = chispita_ray_sprite(s, x1, y1, dx, dy)
      if t >= 0 and t < best then
        best = t
        best_sprite = s
      end
    end
  end

  local best_tile = false
  for _, m in ipairs(chispita_maps) do
    if m.map and m.physics and m.active then
      local found = chispita_ray_map(m, x1, y1, dx, dy, best)
      if found and found.t < best then
        best = found.t
        best_tile = found.tile
        best_sprite = false
      end
    end
  end

  if best > 1 then return false end
  local hit = {}
  hit.x = x1 + dx * best
  hit.y = y1 + dy * best
  hit.distance = length * best
  hit.sprite = best_sprite
  hit.tile = best_tile
  return hit
end
