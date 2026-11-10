import math

def Chispita_vector(x=None, y=None):
  v = chispita_obj()
  v.x = x
  v.y = y
  return v

# Distances and angles
def Chispita_distance(x1=None, y1=None, x2=None, y2=None):
  dx = x2 - x1
  dy = y2 - y1
  return math.sqrt(dx * dx + dy * dy)

def Chispita_distanceBetween(a=None, b=None):
  return Chispita_distance(a.x, a.y, b.x, b.y)

def Chispita_angle(x1=None, y1=None, x2=None, y2=None):
  return Chispita_vectorToAngle(x2 - x1, y2 - y1)

def Chispita_angleBetween(a=None, b=None):
  return Chispita_angle(a.x, a.y, b.x, b.y)

def Chispita_angleDifference(from_angle=None, to_angle=None):
  difference = (to_angle - from_angle) % 360
  if difference < 0: difference += 360
  if difference > 180: difference -= 360
  return difference

# Vectors
def Chispita_angleToVector(angle=None, length=None):
  if not length: length = 1
  radians = angle * math.pi / 180
  return Chispita_vector(math.cos(radians) * length, math.sin(radians) * length)

def Chispita_vectorToAngle(x=None, y=None):
  return math.atan2(y, x) * 180 / math.pi

def Chispita_vectorLength(x=None, y=None):
  return math.sqrt(x * x + y * y)

def Chispita_normalize(x=None, y=None):
  length = Chispita_vectorLength(x, y)
  if length == 0: return Chispita_vector(0, 0)
  return Chispita_vector(x / length, y / length)

# Movement
def Chispita_moveAtAngle(s=None, angle=None, speed=None):
  s.vx = chispita_cosd(angle) * speed
  s.vy = chispita_sind(angle) * speed

def Chispita_moveToward(s=None, x=None, y=None, speed=None):
  direction = Chispita_normalize(x - s.x, y - s.y)
  s.vx = direction.x * speed
  s.vy = direction.y * speed

def Chispita_approach(value=None, target=None, step=None):
  if value < target: return min(value + step, target)
  return max(value - step, target)

def Chispita_pointAt(s=None, x=None, y=None):
  s.rotation = Chispita_angle(s.x, s.y, x, y)

def Chispita_clamp(value=None, low=None, high=None):
  return max(low, min(value, high))

def Chispita_lerp(a=None, b=None, t=None):
  return a + (b - a) * t

def Chispita_sign(n=None):
  if n > 0: return 1
  if n < 0: return -1
  return 0

def Chispita_wrap(value=None, low=None, high=None):
  size = high - low
  wrapped = (value - low) % size
  if wrapped < 0: wrapped += size
  return low + wrapped

# Random
def Chispita_randomRange(low=None, high=None):
  return low + random.next() * (high - low)

def Chispita_randomInt(low=None, high=None):
  return math.floor(low + random.next() * (high - low + 1))

def Chispita_chance(percent=None):
  return random.next() * 100 < percent

