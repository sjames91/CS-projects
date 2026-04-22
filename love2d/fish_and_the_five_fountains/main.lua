
require("Chispita")

local circle
local rect


function love.load()
    rect = Chispita.addRect(500, -200, 128, 128, true)
    circle = Chispita.addCircle(800,200,128,false)
end 

function love.update(dt)
    Chispita.update(dt)
end

function love.draw()
    Chispita.draw()
end
