function Chispita_vector(x, y) {
  var v = {}
  v.x = x
  v.y = y
  return v
}

// Distances and angles
function Chispita_distance(x1, y1, x2, y2) {
  var dx = x2 - x1
  var dy = y2 - y1
  return Math.sqrt(dx * dx + dy * dy)
}

function Chispita_distanceBetween(a, b) {
  return Chispita_distance(a.x, a.y, b.x, b.y)
}

function Chispita_angle(x1, y1, x2, y2) {
  return Chispita_vectorToAngle(x2 - x1, y2 - y1)
}

function Chispita_angleBetween(a, b) {
  return Chispita_angle(a.x, a.y, b.x, b.y)
}

function Chispita_angleDifference(from_angle, to_angle) {
  var difference = (to_angle - from_angle) % 360
  if (difference < 0) difference += 360
  if (difference > 180) difference -= 360
  return difference
}

// Vectors
function Chispita_angleToVector(angle, length) {
  if (!length) length = 1
  var radians = angle * Math.PI / 180
  return Chispita_vector(Math.cos(radians) * length, Math.sin(radians) * length)
}

function Chispita_vectorToAngle(x, y) {
  return Math.atan2(y, x) * 180 / Math.PI
}

function Chispita_vectorLength(x, y) {
  return Math.sqrt(x * x + y * y)
}

function Chispita_normalize(x, y) {
  var length = Chispita_vectorLength(x, y)
  if (length == 0) return Chispita_vector(0, 0)
  return Chispita_vector(x / length, y / length)
}

// Movement
function Chispita_moveAtAngle(s, angle, speed) {
  s.vx = chispita_cosd(angle) * speed
  s.vy = chispita_sind(angle) * speed
}

function Chispita_moveToward(s, x, y, speed) {
  var direction = Chispita_normalize(x - s.x, y - s.y)
  s.vx = direction.x * speed
  s.vy = direction.y * speed
}

function Chispita_approach(value, target, step) {
  if (value < target) return Math.min(value + step, target)
  return Math.max(value - step, target)
}

function Chispita_pointAt(s, x, y) {
  s.rotation = Chispita_angle(s.x, s.y, x, y)
}

function Chispita_clamp(value, low, high) {
  return Math.max(low, Math.min(value, high))
}

function Chispita_lerp(a, b, t) {
  return a + (b - a) * t
}

function Chispita_sign(n) {
  if (n > 0) return 1
  if (n < 0) return -1
  return 0
}

function Chispita_wrap(value, low, high) {
  var size = high - low
  var wrapped = (value - low) % size
  if (wrapped < 0) wrapped += size
  return low + wrapped
}

// Random
function Chispita_randomRange(low, high) {
  return low + random.next() * (high - low)
}

function Chispita_randomInt(low, high) {
  return Math.floor(low + random.next() * (high - low + 1))
}

function Chispita_chance(percent) {
  return random.next() * 100 < percent
}
