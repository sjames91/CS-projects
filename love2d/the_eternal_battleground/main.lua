function love.load()
    --player_variables
    x = 64
    y = 64

    --init_stage
    grid_1load = {}
    grid_2load = {}
    grid_1play = {}
    grid_2play = {}
    for i = 1,3 do
        table.insert(grid_1load, i*64)
    end
    for i = 21, 24 do
        table.insert(grid_2load, i *64)
    end
    for i = 1, 24 do
        table.insert(grid_1play, i*64)
    end

    for i = 1, 16 do
        table.insert(grid_2play, i*64)
    end

    --global_offset
    offset_x = love.graphics.getWidth()/2 - (12*64+64)
    offset_y = love.graphics.getHeight()/2 - (8*64+64)

    --init_player

end

function love.update(dt)

    --player_movement
    if love.keyboard.isDown("d") then
        x = x + 100 * dt
    end
    if love.keyboard.isDown("a") then
        x = x - 100 * dt
    end
    if love.keyboard.isDown("w") then
        y = y - 100 * dt
    end
    if love.keyboard.isDown("s") then
        y = y + 100 * dt
    end
end

function love.draw()
    --draw_stage
    love.graphics.rectangle("fill", x, y, 64, 64)
    for i, grid_y in ipairs(grid_2play) do
        for i, grid_x in ipairs(grid_1load) do
            love.graphics.rectangle("fill", offset_x + grid_x, offset_y + grid_y, 64, 64)
        end
        for i, grid_x in ipairs(grid_2load) do
            love.graphics.rectangle("fill", offset_x + grid_x, offset_y + grid_y, 64, 64)
        end
        for i, grid_x in ipairs(grid_1play) do
            love.graphics.rectangle("line", offset_x + grid_x, offset_y + grid_y, 64, 64)
        end
    end

    --draw_players
end


