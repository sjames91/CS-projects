
local Chispita_sprite = {}
Chispita_sprite.__index = Chispita_sprite
Chispita_sprite.sprites = {}
local sprites = Chispita_sprite.sprites

Chispita_sprite.vx = 0
Chispita_sprite.vy = 0
Chispita_sprite.physics = true
Chispita_sprite.display = true
Chispita_sprite.active = true
Chispita_sprite.fall = true
Chispita_sprite.fixed = false
Chispita_sprite.solid = true
Chispita_sprite.bounciness = .3
Chispita_sprite.hit_box = false
Chispita_sprite.hurt_box = false
Chispita_sprite.friction = 1


function gravity(dt)
    for i, sprite in ipairs(sprites) do
        if sprite.physics == true then 
            sprite.grounded = false
        end
            sprite.y = sprite.y + sprite.vy
            sprite.x = sprite.x + sprite.vx
        if sprite.fall == true and Mode == "platformer" then
                sprite.vy = sprite.vy + Gravity *dt
        end
        if sprite.grounded == true and Mode == "platformer" then
            sprite.vx = sprite.vx * (Friction * sprite.friction)
            sprite.vy = sprite.vy * (Friction * sprite.friction)
        end
            if Mode == "topdown" then
                sprite.vx = sprite.vx * (Friction * sprite.friction)
                sprite.vy = sprite.vy * (Friction * sprite.friction)
        end
    end
end

function draw_sprites()
    for i, sprite in ipairs(sprites) do
        sprite.draw(sprite)
    end
end


function Chispita_sprite.addRect(x, y, width, height, physics)
    local rect = setmetatable({}, Chispita_sprite)
    rect.physics = physics or true
    rect.x = x
    rect.y = y 

    rect.width = width
    rect.height = height
    rect.hit_height = height
    rect.hit_width = width
    rect.hit_box_shape = "rect"
    rect.hurt_box_shape = "rect"
    rect.hurt_box_width = width
    rect.hurt_box_height = height
    rect.fill = "fill"

    if rect.physics == false then
        rect.fall = false
        rect.fixed = true
        rect.solid = false
        rect.bounciness = 0
    end

    table.insert(sprites, rect)

    rect.draw = function(self)
        love.graphics.rectangle(self.fill,self.x,self.y,self.width,self.height)
    end
    return rect
end

function Chispita_sprite.addCircle(x, y, radius, physics)
    local circle = setmetatable({}, Chispita_sprite)
    circle.x = x
    circle.y = y 
    circle.radius = radius
    circle.physics = physics or true
    circle.hit_box_radius = radius
    circle.hit_box_shape = "circle"
    circle.hurt_box_shape = "circle"
    circle.hurt_box_radius = radius
    circle.fill = "fill"

    if circle.physics == false then
        circle.fall = false
        circle.fixed = true
        circle.solid = false
        circle.bounciness = 0
    end

    table.insert(sprites, circle)

    circle.draw = function(self)
        love.graphics.circle(self.fill,self.x,self.y,self.radius)
    end
    return circle
end

return Chispita_sprite


-- [[function Chispita.addCircle(points) 

--     local poly = {}
--     poly.number_of_vertices = 0
--     poly_verts = {}
--     poly.radius = radius
--     poly.physics = physics or true
--     poly.display = true
--     poly.active = true
--     poly.fill = "fill"
--     poly.hit_box = false
--     poly.hit_box_radius = radius
--     poly.hurt_box = false
--     poly.hurt_box_shape = "poly"
--     poly.hurt_box_radius = radius

--     if poly.physics == true then
--         poly.fall = true
--         poly.fixed = false
--         poly.solid = true
--         poly.bounciness = 0

--     else
--         poly.fall = false
--         poly.fixed = true
--         poly.solid = false
--         poly.bounciness = 0
--     end

--     table.insert(sprites, poly)

--     poly.draw = function(self)
--         love.graphics.polygon(self.fill,self.x,self.y,self.radius)
--     end
--     return poly
-- end 

--draw function
