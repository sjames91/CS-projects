-- microStudio runs Lua 5.3, so powers are written a ^ b (there's no
-- math.pow). microStudio's keyboard gives 1 or 0 (and nothing for a key never
-- pressed). In Lua 0 counts as true, so keys are checked with == 1.

player_init = function()
  ship = true
  player_pilot = Chispita_addSprite("player_character")
    Chispita_disable(player_pilot)
    player_pilot.speed = 15
    player_pilot.bounciness = 0
  player_ship = Chispita_addSprite("ship_1")
    player_ship.hit_width = 15
    player_ship.hit_height = 13
    player_ship.hit_offset_y = -1
    local base = Chispita_addPart(player_ship, "rect", 30, 5)
    base.offset_y = -5
    player_ship.fall = false
    player_ship.top_speed = 120
    player_ship.handling = 200
    player_ship.bounciness = 0.5
    player_ship_measure(player_ship)
    Chispita_setTarget(player_ship)
end

player_update = function()
  if ship == true then
    player_controls()
  elseif ship == false then
    pilot_controls()
  end
end

player_draw = function()
end

pilot_controls = function()
  if keyboard.RIGHT == 1 then
    player_pilot.vx = player_pilot.vx + player_pilot.speed
  end

  if keyboard.LEFT == 1 then
    player_pilot.vx = player_pilot.vx - player_pilot.speed
  end

  if player_pilot.grounded == true and keyboard.UP == 1 then
    player_pilot.vy = player_pilot.vy + 150
  end

  if Chispita_distanceBetween(player_pilot, player_ship) < 30 and keyboard.press.Q == 1 then
    enter_ship()
  end
end

player_controls = function()

  player_ship.air_friction = 1 / chispita_air_friction
  local frames = Chispita_deltaTime() * 60
  local stop_frames = math.max(1, player_ship.handling * player_ship.mass)
  local k = 0.1 ^ (1 / stop_frames)
  local push = player_ship.top_speed * player_ship.side_shape * (1 - k) / k * frames
  local vertical_frames = math.max(1, stop_frames / 2)
  local kv = 0.1 ^ (1 / vertical_frames)
  local lift = player_ship.top_speed * player_ship.climb_shape * (1 - kv) / kv * frames
  local fall_frames = math.max(1, player_ship.handling / 1.5 * player_ship.fall_shape)
  local kf = 0.1 ^ (1 / fall_frames)
  local sink = player_ship.handling * 2 * player_ship.fall_shape * (1 - kf) / kf * frames

  if player_ship.grounded == true then
    if keyboard.press.Q == 1 then
      exit_ship()
    end
  end
  if keyboard.LEFT == 1 then
    player_ship.vx = player_ship.vx - push
  end
  if keyboard.RIGHT == 1 then
    player_ship.vx = player_ship.vx + push
  end

  local vertical_keep = kv ^ frames
  if keyboard.UP == 1 then
    player_ship.vy = player_ship.vy + lift
  else
    player_ship.vy = player_ship.vy - sink
    vertical_keep = kf ^ frames
  end

  if keyboard.DOWN == 1 then
    player_ship.vy = player_ship.vy - (lift * 1.5 + 3 * frames)
    vertical_keep = (0.1 ^ (1 / (fall_frames * 2))) ^ frames
  end

  player_ship.vx = player_ship.vx * k ^ frames
  player_ship.vy = player_ship.vy * vertical_keep
end

enter_ship = function()
  ship = true
  Chispita_disable(player_pilot)
  player_ship.fixed = false
  player_camera_switch(player_ship)
end

exit_ship = function()
  local reach = 25 + player_pilot.hit_width / 2
  local side = 0
  if not Chispita_raycast(player_ship.x, player_ship.y, player_ship.x + reach, player_ship.y, player_ship) then
    side = 1
  elseif not Chispita_raycast(player_ship.x, player_ship.y, player_ship.x - reach, player_ship.y, player_ship) then
    side = -1
  end
  if side == 0 then return end
  ship = false
  player_ship.fixed = true
  player_pilot.y = player_ship.y
  player_pilot.x = player_ship.x + 25 * side
  Chispita_enable(player_pilot)
  player_camera_switch(player_pilot)
end

player_shape_area = function(kind, width, height, radius)
  if kind == "circle" then return math.pi * radius * radius end
  if kind == "capsule" then return width * (height - width) + math.pi * width * width / 4 end
  return width * height
end

player_ship_measure = function(ship)
  local half_width = ship.hit_width / 2
  local half_height = ship.hit_height / 2
  if ship.hit_box_shape == "circle" then
    half_width = ship.hit_radius
    half_height = ship.hit_radius
  end
  local left = ship.hit_offset_x - half_width
  local right = ship.hit_offset_x + half_width
  local bottom = ship.hit_offset_y - half_height
  local top = ship.hit_offset_y + half_height
  local area = player_shape_area(ship.hit_box_shape, ship.hit_width, ship.hit_height, ship.hit_radius)
  if ship.hit_parts then
    for _, part in ipairs(ship.hit_parts) do
      half_width = part.width / 2
      half_height = part.height / 2
      if part.kind == "circle" then
        half_width = part.radius
        half_height = part.radius
      end
      left = math.min(left, part.offset_x - half_width)
      right = math.max(right, part.offset_x + half_width)
      bottom = math.min(bottom, part.offset_y - half_height)
      top = math.max(top, part.offset_y + half_height)
      area = area + player_shape_area(part.kind, part.width, part.height, part.radius)
    end
  end
  ship.ship_width = right - left
  ship.ship_height = top - bottom
  ship.mass = area / 345
  local upright = math.sqrt(ship.ship_height / ship.ship_width * 30 / 13)
  ship.fall_shape = math.sqrt(ship.mass * 30 / ship.ship_width * upright)
  ship.climb_shape = math.sqrt(30 / ship.ship_width * upright / ship.mass)
  ship.side_shape = math.sqrt(13 / ship.ship_height / upright)
end

player_camera_switch = function(target)
  Chispita_setTarget(target)
  Camera.smooth = 0.01
  Chispita_tween(Camera, "smooth", 1, 1)
end
