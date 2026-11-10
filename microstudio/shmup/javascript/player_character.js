var ship = true
var player_pilot = 0
var player_ship = 0

function player_init() {
  ship = true
  player_pilot = Chispita_addSprite("player_character")
    Chispita_disable(player_pilot)
    player_pilot.speed = 15
    player_pilot.bounciness = 0
  player_ship = Chispita_addSprite("ship_1")
    player_ship.hit_width = 15
    player_ship.hit_height = 13
    player_ship.hit_offset_y = -1
    var base = Chispita_addPart(player_ship, "rect", 30, 5)
    base.offset_y = -5
    player_ship.fall = 0
    player_ship.top_speed = 120
    player_ship.handling = 200
    player_ship.bounciness = 0.5
    player_ship_measure(player_ship)
    Chispita_setTarget(player_ship)
}

function player_update() {
  if (ship == true) {
    player_controls()
  } else if (ship == false) {
    pilot_controls()
  }
}

function player_draw() {
}

function pilot_controls() {
  if (keyboard.RIGHT) {
    player_pilot.vx += player_pilot.speed
  }

  if (keyboard.LEFT) {
    player_pilot.vx -= player_pilot.speed
  }

  // grounded is 1 or 0, so this compares loosely, like microScript
  if (player_pilot.grounded == true && keyboard.UP) {
    player_pilot.vy += 150
  }

  if (Chispita_distanceBetween(player_pilot, player_ship) < 30 && keyboard.press.Q) {
    enter_ship()
  }
}

function player_controls() {

  player_ship.air_friction = 1 / chispita_air_friction
  var frames = Chispita_deltaTime() * 60
  var stop_frames = Math.max(1, player_ship.handling * player_ship.mass)
  var k = Math.pow(0.1, 1 / stop_frames)
  var push = player_ship.top_speed * player_ship.side_shape * (1 - k) / k * frames
  var vertical_frames = Math.max(1, stop_frames / 2)
  var kv = Math.pow(0.1, 1 / vertical_frames)
  var lift = player_ship.top_speed * player_ship.climb_shape * (1 - kv) / kv * frames
  var fall_frames = Math.max(1, player_ship.handling / 1.5 * player_ship.fall_shape)
  var kf = Math.pow(0.1, 1 / fall_frames)
  var sink = player_ship.handling * 2 * player_ship.fall_shape * (1 - kf) / kf * frames

  if (player_ship.grounded == true) {
    if (keyboard.press.Q) {
      exit_ship()
    }
  }
  if (keyboard.LEFT) {
    player_ship.vx -= push
  }
  if (keyboard.RIGHT) {
    player_ship.vx += push
  }

  var vertical_keep = Math.pow(kv, frames)
  if (keyboard.UP) {
    player_ship.vy += lift
  } else {
    player_ship.vy -= sink
    vertical_keep = Math.pow(kf, frames)
  }

  if (keyboard.DOWN) {
    player_ship.vy -= lift * 1.5 + 3 * frames
    vertical_keep = Math.pow(Math.pow(0.1, 1 / (fall_frames * 2)), frames)
  }

  player_ship.vx *= Math.pow(k, frames)
  player_ship.vy *= vertical_keep
}

function enter_ship() {
  ship = true
  Chispita_disable(player_pilot)
  player_ship.fixed = false
  player_camera_switch(player_ship)
}

function exit_ship() {
  var reach = 25 + player_pilot.hit_width / 2
  var side = 0
  if (!Chispita_raycast(player_ship.x, player_ship.y, player_ship.x + reach, player_ship.y, player_ship)) {
    side = 1
  } else if (!Chispita_raycast(player_ship.x, player_ship.y, player_ship.x - reach, player_ship.y, player_ship)) {
    side = -1
  }
  if (side == 0) return
  ship = false
  player_ship.fixed = true
  player_pilot.y = player_ship.y
  player_pilot.x = player_ship.x + 25 * side
  Chispita_enable(player_pilot)
  player_camera_switch(player_pilot)
}

function player_shape_area(kind, width, height, radius) {
  if (kind == "circle") return Math.PI * radius * radius
  if (kind == "capsule") return width * (height - width) + Math.PI * width * width / 4
  return width * height
}

function player_ship_measure(ship) {
  var half_width = ship.hit_width / 2
  var half_height = ship.hit_height / 2
  if (ship.hit_box_shape == "circle") {
    half_width = ship.hit_radius
    half_height = ship.hit_radius
  }
  var left = ship.hit_offset_x - half_width
  var right = ship.hit_offset_x + half_width
  var bottom = ship.hit_offset_y - half_height
  var top = ship.hit_offset_y + half_height
  var area = player_shape_area(ship.hit_box_shape, ship.hit_width, ship.hit_height, ship.hit_radius)
  if (ship.hit_parts) {
    for (var part of ship.hit_parts) {
      half_width = part.width / 2
      half_height = part.height / 2
      if (part.kind == "circle") {
        half_width = part.radius
        half_height = part.radius
      }
      left = Math.min(left, part.offset_x - half_width)
      right = Math.max(right, part.offset_x + half_width)
      bottom = Math.min(bottom, part.offset_y - half_height)
      top = Math.max(top, part.offset_y + half_height)
      area += player_shape_area(part.kind, part.width, part.height, part.radius)
    }
  }
  ship.ship_width = right - left
  ship.ship_height = top - bottom
  ship.mass = area / 345
  var upright = Math.sqrt(ship.ship_height / ship.ship_width * 30 / 13)
  ship.fall_shape = Math.sqrt(ship.mass * 30 / ship.ship_width * upright)
  ship.climb_shape = Math.sqrt(30 / ship.ship_width * upright / ship.mass)
  ship.side_shape = Math.sqrt(13 / ship.ship_height / upright)
}

function player_camera_switch(target) {
  Chispita_setTarget(target)
  Camera.smooth = 0.01
  Chispita_tween(Camera, "smooth", 1, 1)
}
