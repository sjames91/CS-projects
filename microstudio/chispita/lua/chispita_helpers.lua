local min, max, floor, sqrt, cos, sin, PI = math.min, math.max, math.floor, math.sqrt, math.cos, math.sin, math.pi
-- microStudio runs Lua 5.3, where math.atan takes y and x (there is no math.atan2).
local function atan2(y, x) return math.atan(y, x) end
local function sind(a) return math.sin(a * math.pi / 180) end
local function cosd(a) return math.cos(a * math.pi / 180) end

function Chispita_vector(x, y)
  local v = {}
  v.x = x
  v.y = y
  return v
end

-- Distances and angles
function Chispita_distance(x1, y1, x2, y2)
  local dx = x2 - x1
  local dy = y2 - y1
  return sqrt(dx * dx + dy * dy)
end

function Chispita_distanceBetween(a, b)
  return Chispita_distance(a.x, a.y, b.x, b.y)
end

function Chispita_angle(x1, y1, x2, y2)
  return Chispita_vectorToAngle(x2 - x1, y2 - y1)
end

function Chispita_angleBetween(a, b)
  return Chispita_angle(a.x, a.y, b.x, b.y)
end

function Chispita_angleDifference(from_angle, to_angle)
  local difference = (to_angle - from_angle) % 360
  if difference < 0 then difference = difference + 360 end
  if difference > 180 then difference = difference - 360 end
  return difference
end

-- Vectors
function Chispita_angleToVector(angle, length)
  if not length then length = 1 end
  local radians = angle * PI / 180
  return Chispita_vector(cos(radians) * length, sin(radians) * length)
end

function Chispita_vectorToAngle(x, y)
  return atan2(y, x) * 180 / PI
end

function Chispita_vectorLength(x, y)
  return sqrt(x * x + y * y)
end

function Chispita_normalize(x, y)
  local length = Chispita_vectorLength(x, y)
  if length == 0 then return Chispita_vector(0, 0) end
  return Chispita_vector(x / length, y / length)
end

-- Movement
function Chispita_moveAtAngle(s, angle, speed)
  s.vx = cosd(angle) * speed
  s.vy = sind(angle) * speed
end

function Chispita_moveToward(s, x, y, speed)
  local direction = Chispita_normalize(x - s.x, y - s.y)
  s.vx = direction.x * speed
  s.vy = direction.y * speed
end

function Chispita_approach(value, target, step)
  if value < target then return min(value + step, target) end
  return max(value - step, target)
end

function Chispita_pointAt(s, x, y)
  s.rotation = Chispita_angle(s.x, s.y, x, y)
end

function Chispita_clamp(value, low, high)
  return max(low, min(value, high))
end

function Chispita_lerp(a, b, t)
  return a + (b - a) * t
end

function Chispita_sign(n)
  if n > 0 then return 1 end
  if n < 0 then return -1 end
  return 0
end

function Chispita_wrap(value, low, high)
  local size = high - low
  local wrapped = (value - low) % size
  if wrapped < 0 then wrapped = wrapped + size end
  return low + wrapped
end

-- Random
function Chispita_randomRange(low, high)
  return low + random:next() * (high - low)
end

function Chispita_randomInt(low, high)
  return floor(low + random:next() * (high - low + 1))
end

function Chispita_chance(percent)
  return random:next() * 100 < percent
end
