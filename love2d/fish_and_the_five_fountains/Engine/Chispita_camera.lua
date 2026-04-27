local Chispita_camera = {}

function Camera_update(dt)
    if Camera.target then
        Camera.x = Camera.target.x - love.graphics.getWidth() / 2 + 0.5
        Camera.y = Camera.target.y - love.graphics.getHeight() / 2 + 0.5 
    end
end

return Chispita_camera