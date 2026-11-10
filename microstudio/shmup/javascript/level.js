var level = 0
var sky = 0

function level_init(level_number) {
  if (level_number == 1) {
    level = Chispita_addMap("overworld/overworld")
    sky = Chispita_addMap("overworld/overworld_background", 0, 0, physics_off)
    sky.tile = 1
    sky.parallax = 0.5
    chispita_mode = "platformer"
    level.bounciness = 1
    Camera.zoom = .7
  }
}

function level_update() {
}

function level_draw() {
}
