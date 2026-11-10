level = 0
sky = 0

def level_init(level_number):
  global level, sky, chispita_mode
  if level_number == 1:
    level = Chispita_addMap("overworld/overworld")
    sky = Chispita_addMap("overworld/overworld_background", 0, 0, physics_off)
    sky.tile = 1
    sky.parallax = 0.5
    chispita_mode = "platformer"
    level.bounciness = 1
    Camera.zoom = .7

def level_update():
  pass

def level_draw():
  pass
