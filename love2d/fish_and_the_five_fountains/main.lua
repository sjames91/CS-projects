require("Engine/Chispita")
local circle
local rect


function love.load()
    rect1 = Chispita.addRect(800, -5, 128, 128, true)
        rect1.fall = true
        rect1.bounciness = .8

    rect2 = Chispita.addRect(800,500,256,64,true)
        rect2.fall = false
        rect2.fixed = true
        rect2.friction = 8
end

function love.update(dt)
    print(rect1.grounded)
    Chispita.update(dt)

  if love.keyboard.isDown("w") then rect1.vy = -5 end
  if love.keyboard.isDown("s") then rect1.vy = 5 end
  if love.keyboard.isDown("a") then rect1.vx = -5 end
  if love.keyboard.isDown("d") then rect1.vx = 5 end
  
  if love.keyboard.isDown("up") then rect2.vy = -5 end
  if love.keyboard.isDown("down") then rect2.vy = 5 end
  if love.keyboard.isDown("left") then rect2.vx = -5 end
  if love.keyboard.isDown("right") then rect2.vx = 5 end
end

function love.draw()
    Chispita.draw()
end
