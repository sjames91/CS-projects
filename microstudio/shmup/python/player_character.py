import math

ship = True
player_pilot = 0
player_ship = 0

# microStudio only adds a key to keyboard once it has been pressed, and
# Python can't read a field that isn't there, so keys are read with these.
def key(name):
  return getattr(keyboard, name, 0)

def key_press(name):
  return getattr(keyboard.press, name, 0)

def player_init():
  global ship, player_pilot, player_ship
  ship = True
  player_pilot = Chispita_addSprite("player_character")
  Chispita_disable(player_pilot)
  player_pilot.speed = 15
  player_pilot.bounciness = 0
  player_ship = Chispita_addSprite("ship_1")
  player_ship.hit_width = 15
  player_ship.hit_height = 13
  player_ship.hit_offset_y = -1
  base = Chispita_addPart(player_ship, "rect", 30, 5)
  base.offset_y = -5
  player_ship.fall = 0
  player_ship.top_speed = 120
  player_ship.handling = 200
  player_ship.bounciness = 0.5
  player_ship_measure(player_ship)
  Chispita_setTarget(player_ship)

def player_update():
  if ship == True:
    player_controls()
  elif ship == False:
    pilot_controls()

def player_draw():
  pass

def pilot_controls():
  if key("RIGHT"):
    player_pilot.vx += player_pilot.speed

  if key("LEFT"):
    player_pilot.vx -= player_pilot.speed

  # grounded is 1 or 0, and 1 == True in Python, like microScript
  if player_pilot.grounded == True and key("UP"):
    player_pilot.vy += 150

  if Chispita_distanceBetween(player_pilot, player_ship) < 30 and key_press("Q"):
    enter_ship()

def player_controls():

  player_ship.air_friction = 1 / chispita_air_friction
  frames = Chispita_deltaTime() * 60
  stop_frames = max(1, player_ship.handling * player_ship.mass)
  k = math.pow(0.1, 1 / stop_frames)
  push = player_ship.top_speed * player_ship.side_shape * (1 - k) / k * frames
  vertical_frames = max(1, stop_frames / 2)
  kv = math.pow(0.1, 1 / vertical_frames)
  lift = player_ship.top_speed * player_ship.climb_shape * (1 - kv) / kv * frames
  fall_frames = max(1, player_ship.handling / 1.5 * player_ship.fall_shape)
  kf = math.pow(0.1, 1 / fall_frames)
  sink = player_ship.handling * 2 * player_ship.fall_shape * (1 - kf) / kf * frames

  if player_ship.grounded == True:
    if key_press("Q"):
      exit_ship()
  if key("LEFT"):
    player_ship.vx -= push
  if key("RIGHT"):
    player_ship.vx += push

  vertical_keep = math.pow(kv, frames)
  if key("UP"):
    player_ship.vy += lift
  else:
    player_ship.vy -= sink
    vertical_keep = math.pow(kf, frames)

  if key("DOWN"):
    player_ship.vy -= lift * 1.5 + 3 * frames
    vertical_keep = math.pow(math.pow(0.1, 1 / (fall_frames * 2)), frames)

  player_ship.vx *= math.pow(k, frames)
  player_ship.vy *= vertical_keep

def enter_ship():
  global ship
  ship = True
  Chispita_disable(player_pilot)
  player_ship.fixed = False
  player_camera_switch(player_ship)

def exit_ship():
  global ship
  reach = 25 + player_pilot.hit_width / 2
  side = 0
  if not Chispita_raycast(player_ship.x, player_ship.y, player_ship.x + reach, player_ship.y, player_ship):
    side = 1
  elif not Chispita_raycast(player_ship.x, player_ship.y, player_ship.x - reach, player_ship.y, player_ship):
    side = -1
  if side == 0: return
  ship = False
  player_ship.fixed = True
  player_pilot.y = player_ship.y
  player_pilot.x = player_ship.x + 25 * side
  Chispita_enable(player_pilot)
  player_camera_switch(player_pilot)

def player_shape_area(kind, width, height, radius):
  if kind == "circle": return math.pi * radius * radius
  if kind == "capsule": return width * (height - width) + math.pi * width * width / 4
  return width * height

def player_ship_measure(ship):
  half_width = ship.hit_width / 2
  half_height = ship.hit_height / 2
  if ship.hit_box_shape == "circle":
    half_width = ship.hit_radius
    half_height = ship.hit_radius
  left = ship.hit_offset_x - half_width
  right = ship.hit_offset_x + half_width
  bottom = ship.hit_offset_y - half_height
  top = ship.hit_offset_y + half_height
  area = player_shape_area(ship.hit_box_shape, ship.hit_width, ship.hit_height, ship.hit_radius)
  if ship.hit_parts:
    for part in ship.hit_parts:
      half_width = part.width / 2
      half_height = part.height / 2
      if part.kind == "circle":
        half_width = part.radius
        half_height = part.radius
      left = min(left, part.offset_x - half_width)
      right = max(right, part.offset_x + half_width)
      bottom = min(bottom, part.offset_y - half_height)
      top = max(top, part.offset_y + half_height)
      area += player_shape_area(part.kind, part.width, part.height, part.radius)
  ship.ship_width = right - left
  ship.ship_height = top - bottom
  ship.mass = area / 345
  upright = math.sqrt(ship.ship_height / ship.ship_width * 30 / 13)
  ship.fall_shape = math.sqrt(ship.mass * 30 / ship.ship_width * upright)
  ship.climb_shape = math.sqrt(30 / ship.ship_width * upright / ship.mass)
  ship.side_shape = math.sqrt(13 / ship.ship_height / upright)

def player_camera_switch(target):
  Chispita_setTarget(target)
  Camera.smooth = 0.01
  Chispita_tween(Camera, "smooth", 1, 1)
