require("Engine/Chispita")
local circle
local rect


function love.load()
    rect = Chispita.addRect(500, -100, 128, 128, true)

    circle = Chispita.addCircle(800,200,128,false)

end 

function love.update(dt)
    Chispita.update(dt)
    if love.keyboard.isDown("d") then
        circle.vx = circle.vx+10
    end
end

function love.draw()
    Chispita.draw()
end
