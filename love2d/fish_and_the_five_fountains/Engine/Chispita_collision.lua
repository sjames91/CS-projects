local Chispita_collision = {}
local Chispita_sprite = require("Engine/Chispita_sprite")
local sprites = Chispita_sprite.sprites

Chispita_collision.friction = 10
Chispita_collision.solid = true
Chispita_collision.trigger = false
Chispita_collision.overlap = false

Chispita_collision.checkCollision_rect_rect = function(s1, s2)
    if s1.x < s2.x + s2.width and
       s1.x + s1.width > s2.x and
       s1.y < s2.y + s2.height and
       s1.y + s1.height > s2.y then
        local dx = math.min(s1.x + s1.width, s2.x + s2.width) - math.max(s1.x, s2.x)
        local dy = math.min(s1.y + s1.height, s2.y + s2.height) - math.max(s1.y, s2.y)
        if dx < dy then
            return dir, dx, 0
        else
            return dir, 0, dy
        end
    else
        return false
    end
end

Chispita_collision.checkCollision_circle_circle = function()
end

Chispita_collision.checkCollision_rect_circle = function()
end

Chispita_collision.checkCollision_pillbox_pillbox = function()
end

Chispita_collision.checkCollision_rect_pillbox = function()
end

Chispita_collision.checkCollision_circle_pillbox = function()
end


function Chispita_collision.checkCollisions()
    for i = 1, #sprites do
        for j = i + 1, #sprites do
            local s1 = sprites[i]
            local s2 = sprites[j]
            if s1.physics and s2.physics then
                if s1.hit_box_shape == "rect" and s2.hit_box_shape == "rect" then
                        local dir, dx, dy = Chispita_collision.checkCollision_rect_rect(s1, s2)
                    if dx ~= nil and dx ~= false then

                        if s1.trigger and s1.callback then
                            s1.callback(s1,s2)
                        end
                        if s2.trigger and s2.callback then
                            s2.callback(s2,s1)   
                        end

                        if not s1.fixed and s1.solid then
                            if s1.x < s2.x then           
                                s1.x = s1.x - dx
                                vx = dx*s1.bounciness
                            else
                                s1.x = s1.x + dx
                                vx = dx*s1.bounciness
                            end

                            if s1.y < s2.y then
                                s1.y = s1.y - dy
                                vy = dy*s1.bounciness
                            else
                                s1.y = s1.y + dy
                                vy = dy*s1.bounciness
                            end

                        end
                        
                        if not s2.fixed and s2.solid then

                            if s2.x < s1.x then           
                                s2.x = s2.x - dx * s2.bounciness
                            else
                                s2.x = s2.x + dx * s2.bounciness
                            end

                            if s2.y < s1.y then
                                s2.y = s2.y - dy * s2.bounciness
                            else
                                s2.y = s2.y + dy * s2.bounciness
                            end
                        end
                    else 
                        return nil
                    end

                elseif s1.hit_box_shape == "circle" and s2.hit_box_shape == "circle" then
                        Chispita_collision.checkCollision_circle_circle(s1, s2)
                elseif (s1.hit_box_shape == "rect" and s2.hit_box_shape == "circle") or (s1.hit_box_shape == "circle" and s2.hit_box_shape == "rect") then
                        Chispita_collision.checkCollision_rect_circle(s1, s2)
                elseif s1.hit_box_shape == "pillbox" and s2.hit_box_shape == "pillbox" then
                        Chispita_collision.checkCollision_pillbox_pillbox(s1, s2)
                elseif (s1.hit_box_shape == "rect" and s2.hit_box_shape == "pillbox") or (s1.hit_box_shape == "pillbox" and s2.hit_box_shape == "rect") then
                        Chispita_collision.checkCollision_rect_pillbox(s1, s2)
                elseif (s1.hit_box_shape == "circle" and s2.hit_box_shape == "pillbox") or (s1.hit_box_shape == "pillbox" and s2.hit_box_shape == "circle") then
                        Chispita_collision.checkCollision_circle_pillbox(s1, s2)
                end
            end
         end 
    end 
end
return Chispita_collision


