require("Engine/Chispita")
local circle
local rect
Mode = "platformer"
Debug_mode = true
Friction = 0


function love.load()
    rect1 = Chispita.addCircle(800, -5, 128, true)
        rect1.bounciness = 1
        rect1.friction = -10

    rect2 = Chispita.addCircle(800,800,400,true)
        rect2.fall = false
        rect2.fixed = true
        rect2.friction = 1
        rect2.bounciness = 0 
    Chispita.setTarget(rect1)

end

function love.update(dt)
    print(rect1.grounded)
    Chispita.update(dt)

  if love.keyboard.isDown("w") and rect1.grounded then rect1.vy = -5 end
  if love.keyboard.isDown("s") then rect1.vy = 5 end
  if love.keyboard.isDown("a") then rect1.vx = -5 end
  if love.keyboard.isDown("d") then rect1.vx = 5 end
  
  if love.keyboard.isDown("up") then rect2.vy = -2 end
  if love.keyboard.isDown("down") then rect2.vy = 5 end
  if love.keyboard.isDown("left") then rect2.vx = -5 end
  if love.keyboard.isDown("right") then rect2.vx = 5 end
end

function love.keypressed(key) 
    if key == "q" then
        Debug_mode = not Debug_mode
        love.graphics.setColor(1,1,1,1)
    end
end

function love.draw()
    Chispita.draw()
end
