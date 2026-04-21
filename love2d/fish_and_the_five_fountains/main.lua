
require("Chispita")
X = 500
Y = 500
local circle


function love.load()
    Chispita.addRect(X, Y, 128, 128, true)
    circle = Chispita.addCircle(800,800,128, false)
end

function love.update(dt)
    if love.keyboard.isDown("space") then
        circle.fill = "line"
    else
        circle.fill = "fill"
    end
end

function love.draw()
    Chispita.draw()
end
