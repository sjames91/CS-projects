Chispita = {}
Gravity = 5
Mode = "topdown"
Friction = .85
Air_friction = .95
Camera = {}
Camera.x = 0
Camera.y = 0
Camera.target = nil
Debug_mode = false

local Chispita_sprite = require("Engine/Chispita_sprite")
local Chispita_collision = require("Engine/Chispita_collision")
local Chispita_camera = require("Engine/Chispita_camera")
local sprites = Chispita_sprite.sprites

Chispita.addRect = Chispita_sprite.addRect
Chispita.addCircle = Chispita_sprite.addCircle

Chispita.setTarget = function(sprite)
    Camera.target = sprite
end 




function Debug_info()
    love.graphics.setColor(1,1,0,1)
    local mx, my = love.mouse.getPosition()
    local wx = mx + Camera.x
    local wy = my + Camera.y

    love.graphics.print("Camera: " .. string.format("%.2f", Camera.x) .. ", " .. string.format("%.2f", Camera.y), 10, 10)
    love.graphics.print("Mouse Screen: " .. string.format("%.2f", mx) .. ", " .. string.format("%.2f", my), 10, 30)
    love.graphics.print("Mouse World: " .. string.format("%.2f", wx) .. ", " .. string.format("%.2f", wy), 10, 50)
    love.graphics.print("Mode: " .. Mode, 10, 70)
    love.graphics.print("Gravity: " .. Gravity, 10, 90)
    love.graphics.print("Sprites: " .. #sprites, 10, 110)
end

function Chispita.draw()
    draw_sprites()
    if Debug_mode then 
        Debug_info()
    end
end


function Chispita.update(dt)
    Gravity_pre(dt)
    Chispita_collision.checkCollisions()
    Gravity_post(dt)
    Camera_update(dt)
end




