Chispita = {}
Gravity = 5
local Chispita_sprite = require("Engine/Chispita_sprite")
local sprites = Chispita_sprite.sprites

Chispita.addRect = Chispita_sprite.addRect
Chispita.addCircle = Chispita_sprite.addCircle


function Chispita.draw()
    draw_sprites()
end


function Chispita.update(dt)
    gravity(dt)
end





