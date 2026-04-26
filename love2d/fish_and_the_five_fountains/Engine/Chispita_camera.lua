local Chispita_camera = {}

function Camera_update(dt)
    if Camera.target then
        Camera.x = Camera.target.x - love.graphics.getWidth() / 2
        Camera.y = Camera.target.y - love.graphics.getHeight() / 2
    end
end

return Chispita_camera