local abs, min, max, floor = math.abs, math.min, math.max, math.floor
-- microStudio runs Lua 5.3, which has no math.pow: a ^ b is the same.
local function pow(a, b) return a ^ b end
local function sind(a) return math.sin(a * math.pi / 180) end
local function cosd(a) return math.cos(a * math.pi / 180) end

chispita_sprites = {}
chispita_next_id = 1
physics_on = "on"
physics_off = "off"

-- Takes o out of a list, wherever it is.
function chispita_remove_from(list, o)
  for i = #list, 1, -1 do
    if list[i] == o then table.remove(list, i) end
  end
end

  -- Create a new sprite.
function chispita_new_sprite(x, y, shape, physics)
  -- Left out, a position is 0, as in microScript.
  x = x or 0
  y = y or 0

  -- Basic sprite variables
  local s = {}
  s.id = chispita_next_id
  chispita_next_id = chispita_next_id + 1
  s.sprite_name = false
  s.x = x
  s.y = y
  s.old_x = x
  s.old_y = y
  s.vx = 0
  s.vy = 0

  -- Sprite physics variables
  s.active = true
  s.physics = true
  s.fall = true
  s.fixed = false
  s.kinematic = false
  s.solid = true
  s.bounciness = 0.3
  s.friction = 1
  s.air_friction = 1
  s.grounded = false
  s.riding = false
  s.group = "default"
  s.one_way = false
  s.drop_through = false
  s.mass = 1
  s.grip = 0
  s.rotate_hit_box = true
  s.drag = 1
  s.lifetime = 0

  -- Sprite hit box variables
  s.hit_box_shape = shape
  s.hit_offset_x = 0
  s.hit_offset_y = 0
  s.hit_parts = false
  -- Edges of the hit box, worked out each collision pass. Sprites with
  -- physics off keep these, so they still sort with the rest.
  s.left = x
  s.right = x
  s.bottom = y
  s.top = y

  -- Sprite hurt box variables
  s.hurt_box = false
  s.hurt_box_shape = shape
  s.hurt_offset_x = 0
  s.hurt_offset_y = 0
  s.hurt_parts = false

  --Hit and hurt boxes only make collision object once not every frame.
  s.hit_shape = {}
  s.hurt_shape = {}

  --Sprite triggers
  s.trigger = false
  s.was_trigger = false
  s.callback = false  --every frame while touching: callback(self, other)
  s.on_enter = false  -- first frame touching
  s.on_exit = false   -- first frame after touching
  s.on_tile = false   -- touching a map tile: on_tile(self, tile)
  s.on_hurt = false   --hurt box reached another sprite: on_hurt(self, other)
  s.contacts = {}
  s.old_contacts = {}
  s.tile_contacts = {}
  s.tile_touched = false
  s.hurting = {}
  s.on_hit = false
  s.hit_list = {}
  s.old_hit_list = {}

  --Sprite draw variables
  s.visible = true
  s.layer = 1
  s.depth_sort = false
  s.parallax = 1
  s.ui = false
  s.fill = "fill"
  s.color = "rgb(255,255,255)"
  s.alpha = 1
  s.image = false               -- name of a sprite from the sprite editor
  s.image_part = false          -- part of the image to draw (x, y, w, h in pixels), for tile sheets
  s.animations = {}             -- name -> separate image, when not using a sheet
  s.animation = false           -- name of the animation playing, or false
  s.sheet = false               -- sprite sheet from Chispita_addSheet
  s.frame = 0                   -- position in the current animation (0 = first)
  s.frame_time = 0
  s.animation_speed = 1         -- 2 plays twice as fast, 0.5 half speed
  s.animation_done = false      -- true once a play-once animation has finished
  s.on_animation_end = false    -- function(self, name), at the end of each run
  s.flip_x = false
  s.flip_y = false
  s.rotation = 0                -- degrees, only changes the drawing

  if physics and physics ~= physics_on and physics ~= physics_off then
    chispita_warn("physics should be physics_on or physics_off, not " .. tostring(physics) .. ". Using physics_on.")
  end

  -- Physics off
  if physics == physics_off then
    s.physics = false
    s.fall = false
    s.fixed = true
    s.solid = false
    s.bounciness = 0
  end

  --Draw sprites
  s.draw = function()
    chispita_draw_sprite(s)
  end

  if not chispita_sprite_fields then
    chispita_sprite_fields = {}
    for key in pairs(s) do
      chispita_sprite_fields[key] = true
    end
    for _, key in ipairs({ "width", "height", "radius", "hit_width", "hit_height", "hit_radius", "hurt_width", "hurt_height", "hurt_radius", "removed", "left", "right", "top", "bottom", "was_hurting" }) do
      chispita_sprite_fields[key] = true
    end
  end

  table.insert(chispita_sprites, s)
  chispita_add_drawable(s)
  return s
end

chispita_sprite_fields = false
chispita_field_verdicts = {}
chispita_field_check_index = 1

-- True when two names are one or two letters apart (a likely typo).
function chispita_close_name(a, b)
  if #a < 4 or #b < 4 then return false end
  local limit = 2
  if #b < 5 then limit = 1 end
  if abs(#a - #b) > limit then return false end
  -- previous[j + 1] is the distance from the start of a to the first j letters of b
  local previous = {}
  for j = 0, #b do
    previous[j + 1] = j
  end
  for i = 1, #a do
    local current = { i }
    local letter = a:sub(i, i)
    for j = 1, #b do
      local cost = 1
      if letter == b:sub(j, j) then cost = 0 end
      current[j + 1] = min(min(current[j] + 1, previous[j + 1] + 1), previous[j] + cost)
    end
    previous = current
  end
  return previous[#b + 1] <= limit
end

function chispita_check_fields(s)
  for key in pairs(s) do
    if type(key) == "string" and not chispita_sprite_fields[key] then
      local verdict = chispita_field_verdicts[key]
      if not verdict then
        verdict = "ok"
        for known in pairs(chispita_sprite_fields) do
          if chispita_close_name(key, known) then
            verdict = known
            break
          end
        end
        chispita_field_verdicts[key] = verdict
      end
      if verdict ~= "ok" then
        chispita_warn("sprite #" .. s.id .. " has '" .. key .. "', which isn't a sprite setting. Did you mean '" .. verdict .. "'? (If it's your own variable, ignore this.)")
        chispita_field_verdicts[key] = "ok"
      end
    end
  end
end

function chispita_check_sprite_fields()
  local n = #chispita_sprites
  if n == 0 or not chispita_sprite_fields then return end
  for k = 1, min(4, n) do
    if chispita_field_check_index > n then chispita_field_check_index = 1 end
    chispita_check_fields(chispita_sprites[chispita_field_check_index])
    chispita_field_check_index = chispita_field_check_index + 1
  end
end

function Chispita_addRect(x, y, width, height, physics)
  if width <= 0 or height <= 0 then
    chispita_warn("Chispita_addRect needs a width and height above 0 (got " .. width .. " by " .. height .. ").")
  end
  local rect = chispita_new_sprite(x, y, "rect", physics)
  rect.width = width
  rect.height = height
  rect.hit_width = width
  rect.hit_height = height
  rect.hurt_width = width
  rect.hurt_height = height
  return rect
end

function Chispita_addCircle(x, y, radius, physics)
  if radius <= 0 then
    chispita_warn("Chispita_addCircle needs a radius above 0 (got " .. radius .. ").")
  end
  local circle = chispita_new_sprite(x, y, "circle", physics)
  circle.radius = radius
  circle.hit_radius = radius
  circle.hurt_radius = radius
  return circle
end

function Chispita_addCapsule(x, y, width, height, physics)
  if width <= 0 or height <= 0 then
    chispita_warn("Chispita_addCapsule needs a width and height above 0 (got " .. width .. " by " .. height .. ").")
  end
  if height < width then
    chispita_warn("Chispita_addCapsule: height should be at least the width. A capsule stands upright; use rotation to lay it down.")
    height = width
  end
  local capsule = chispita_new_sprite(x, y, "capsule", physics)
  capsule.width = width
  capsule.height = height
  capsule.hit_width = width
  capsule.hit_height = height
  capsule.hurt_width = width
  capsule.hurt_height = height
  return capsule
end

function chispita_make_part(s, kind, width, height, caller)
  if not s then
    chispita_warn(caller .. " was given nothing (nil) to add a part to.")
    return false
  end
  local sprite_width = s.width
  local sprite_height = s.height
  if s.hit_box_shape == "circle" then
    sprite_width = s.radius * 2
    sprite_height = s.radius * 2
  end
  local part = {}
  part.kind = kind
  part.offset_x = 0
  part.offset_y = 0
  part.width = 0
  part.height = 0
  part.radius = 0
  if kind == "rect" or kind == "capsule" then
    part.width = width
    part.height = height
    if not part.width then part.width = sprite_width end
    if not part.height then part.height = sprite_height end
    if part.width <= 0 or part.height <= 0 then
      chispita_warn(caller .. ": a " .. kind .. " part needs a width and height above 0.")
    end
    if kind == "capsule" and part.height < part.width then part.height = part.width end
  elseif kind == "circle" then
    part.radius = width
    if not part.radius then part.radius = min(sprite_width, sprite_height) / 2 end
    if part.radius <= 0 then
      chispita_warn(caller .. ": a circle part needs a radius above 0.")
    end
  else
    chispita_warn(caller .. ": kind should be 'rect', 'circle' or 'capsule', not " .. tostring(kind) .. ".")
    return false
  end
  part.shape = {}
  return part
end

function Chispita_addPart(s, kind, width, height)
  local part = chispita_make_part(s, kind, width, height, "Chispita_addPart")
  if not part then return false end
  if not s.hit_parts then s.hit_parts = {} end
  table.insert(s.hit_parts, part)
  return part
end

function Chispita_addHurtPart(s, kind, width, height)
  local part = chispita_make_part(s, kind, width, height, "Chispita_addHurtPart")
  if not part then return false end
  if not s.hurt_parts then s.hurt_parts = {} end
  table.insert(s.hurt_parts, part)
  return part
end

function Chispita_clearParts(s)
  if s then s.hit_parts = false end
end

function Chispita_clearHurtParts(s)
  if s then s.hurt_parts = false end
end

function Chispita_setSize(s, width, height)
  s.width = width
  s.height = height
  s.hit_width = width
  s.hit_height = height
  s.hurt_width = width
  s.hurt_height = height
end

function Chispita_setRadius(s, radius)
  s.radius = radius
  s.hit_radius = radius
  s.hurt_radius = radius
end

function Chispita_disable(o)
  if not o then
    chispita_warn("Chispita_disable was given nothing (nil).")
    return
  end
  o.active = false
  o.visible = false
end

function Chispita_enable(o)
  if not o then
    chispita_warn("Chispita_enable was given nothing (nil).")
    return
  end
  if o.removed then
    chispita_warn("Chispita_enable can't bring back something that was removed with Chispita_remove.")
    return
  end
  o.active = true
  o.visible = true
end

chispita_remove_queue = {}

function Chispita_remove(o)
  if not o then
    chispita_warn("Chispita_remove was given nothing (nil).")
    return
  end
  if o.removed then return end
  o.removed = true
  o.active = false
  o.visible = false
  table.insert(chispita_remove_queue, o)
end

function chispita_purge_removed()
  if #chispita_remove_queue == 0 then return end
  for _, o in ipairs(chispita_remove_queue) do
    chispita_remove_from(chispita_sprites, o)
    chispita_remove_from(chispita_drawables, o)
    chispita_remove_from(chispita_maps, o)
    if Camera.target == o then Camera.target = false end
    if chispita_dragging == o then chispita_dragging = false end
  end
  for _, s in ipairs(chispita_sprites) do
    if s.riding and s.riding.removed then s.riding = false end
  end
  chispita_remove_queue = {}
end

function Chispita_addSprite(image, x, y, width, height, physics)
  if type(image) == "table" and image.frame_width then
    if not width then width = image.frame_width end
    if not height then height = width * image.frame_height / image.frame_width end
    local character = Chispita_addRect(x, y, width, height, physics)
    Chispita_useSheet(character, image)
    return character
  end

  local picture = sprites[image]
  if not picture then
    chispita_warn("no sprite named " .. tostring(image) .. ". Check the name in the sprite editor.")
    if not width then width = 16 end
    if not height then height = width end
    return Chispita_addRect(x, y, width, height, physics)
  end
  if not width then width = picture.width end
  if not height then height = width * picture.height / picture.width end
  local rect = Chispita_addRect(x, y, width, height, physics)
  rect.image = image
  return rect
end


-- Add text
function Chispita_addText(text, x, y, size, color)
  -- Left out, a position is 0, as in microScript.
  x = x or 0
  y = y or 0
  local t = {}
  t.text = text
  t.x = x
  t.y = y
  t.size = size
  if not t.size then t.size = 10 end
  t.color = color
  if not t.color then t.color = "rgb(255,255,255)" end
  t.font = "BitCell"
  t.active = true
  t.visible = true
  t.layer = 3
  t.parallax = 1
  t.ui = false

  t.draw = function()
    screen:setFont(t.font)
    screen:drawText(t.text, chispita_screen_x(t, t.x), chispita_screen_y(t, t.y), chispita_screen_size(t, t.size), t.color)
  end

  chispita_add_drawable(t)
  return t
end


-- Particles
chispita_particles = {}
chispita_particle_layer = false

function Chispita_burst(x, y, count, color, speed, life, size)
  if not count then count = 10 end
  if not color then color = "rgb(255,255,255)" end
  if not speed then speed = 60 end
  if not life then life = 0.5 end
  if not size then size = 2 end

  if not chispita_particle_layer then
    chispita_particle_layer = {
      layer = 2,
      visible = true,
      draw = function()
        chispita_draw_particles()
      end
    }
    chispita_add_drawable(chispita_particle_layer)
  end

  local index = 1
  for i = 1, count do
    while index <= #chispita_particles do
      if not chispita_particles[index].active then break end
      index = index + 1
    end
    if index > #chispita_particles then
      table.insert(chispita_particles, {})
    end
    local p = chispita_particles[index]
    local angle = random:next() * 360
    local this_speed = speed * (0.5 + random:next() * 0.5)
    p.active = true
    p.x = x
    p.y = y
    p.vx = cosd(angle) * this_speed
    p.vy = sind(angle) * this_speed
    p.life = life
    p.max_life = life
    p.size = size
    p.color = color
  end
end

function chispita_update_particles(dt)
  for _, p in ipairs(chispita_particles) do
    if p.active then
      p.life = p.life - dt
      if p.life <= 0 then
        p.active = false
      else
        p.vy = p.vy - chispita_particle_gravity * dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
      end
    end
  end
end

function chispita_draw_particles()
  for _, p in ipairs(chispita_particles) do
    if p.active then
      screen:setAlpha(p.life / p.max_life)
      screen:fillRound(chispita_world_x(p.x), chispita_world_y(p.y), p.size * Camera.zoom, p.size * Camera.zoom, p.color)
    end
  end
  screen:setAlpha(1)
end

function chispita_live_particles()
  local count = 0
  for _, p in ipairs(chispita_particles) do
    if p.active then count = count + 1 end
  end
  return count
end

function Chispita_addSheet(image, frame_width, frame_height)
  local sheet = {}
  sheet.is_sheet = true
  sheet.image = image
  sheet.frame_width = frame_width
  sheet.frame_height = frame_height
  if not sheet.frame_height then sheet.frame_height = frame_width end
  sheet.animations = {}

  local picture = sprites[image]
  if picture then
    sheet.columns = max(1, floor(picture.width / sheet.frame_width))
    sheet.rows = max(1, floor(picture.height / sheet.frame_height))
  else
    chispita_warn("Chispita_addSheet: no sprite named " .. tostring(image) .. ". Check the name in the sprite editor.")
    sheet.columns = 1
    sheet.rows = 1
  end
  return sheet
end

function chispita_make_animation(frames, fps, once)
  local animation = {}
  animation.frames = frames
  animation.fps = fps
  if not animation.fps then animation.fps = 8 end
  animation.once = once
  return animation
end

-- Frame numbers count from 0 (the top-left frame), across then down,
-- like the microStudio version. Rows and columns count from 0 too.
function Chispita_addAnimation(sheet, name, row, first, count, fps, once)
  if not sheet.frame_width then
    chispita_warn("Chispita_addAnimation needs a sheet from Chispita_addSheet.")
    return
  end
  if row >= sheet.rows or first + count > sheet.columns then
    chispita_warn("animation " .. name .. " goes past the edge of its sheet (" .. sheet.columns .. " columns, " .. sheet.rows .. " rows).")
  end
  local frames = {}
  for i = 0, count - 1 do
    table.insert(frames, row * sheet.columns + first + i)
  end
  sheet.animations[name] = chispita_make_animation(frames, fps, once)
end

function Chispita_addAnimationFrames(sheet, name, frames, fps, once)
  sheet.animations[name] = chispita_make_animation(frames, fps, once)
end

function Chispita_useSheet(s, sheet)
  if not sheet.frame_width then
    chispita_warn("Chispita_useSheet needs a sheet from Chispita_addSheet.")
    return
  end
  s.sheet = sheet
  s.image = sheet.image
  s.image_part = {}
  s.image_part.w = sheet.frame_width
  s.image_part.h = sheet.frame_height
  s.animation = false
  chispita_show_sheet_frame(s, 0)
end

function chispita_show_sheet_frame(s, frame_number)
  local sheet = s.sheet
  s.image_part.x = (frame_number % sheet.columns) * sheet.frame_width
  s.image_part.y = floor(frame_number / sheet.columns) * sheet.frame_height
end

function Chispita_play(s, name, restart)
  if s.sheet then
    local animation = s.sheet.animations[name]
    if not animation then
      chispita_warn("sprite #" .. s.id .. " has no animation named " .. tostring(name) .. ". Add it with Chispita_addAnimation first.")
      return
    end
    if s.animation == name and not restart then return end
    s.animation = name
    s.frame = 0
    s.frame_time = 0
    s.animation_done = false
    chispita_show_sheet_frame(s, animation.frames[1])
    return
  end

  local image = s.animations[name]
  if image then
    s.image = image
    s.animation = name
  else
    chispita_warn("sprite #" .. s.id .. " has no animation named " .. tostring(name) .. ". Give it a sheet, or set its animations." .. tostring(name) .. " to an image.")
  end
end

function chispita_update_animations(dt)
  for _, s in ipairs(chispita_sprites) do
    if s.active and s.sheet and s.animation and not s.animation_done then
      local animation = s.sheet.animations[s.animation]
      s.frame_time = s.frame_time + dt * animation.fps * s.animation_speed

      while s.frame_time >= 1 do
        s.frame_time = s.frame_time - 1
        s.frame = s.frame + 1
        if s.frame >= #animation.frames then
          if animation.once then
            s.frame = #animation.frames - 1
            s.animation_done = true
          else
            s.frame = 0
          end
          if s.on_animation_end then
            local f = s.on_animation_end
            f(s, s.animation)
          end
          break
        end
      end

      local current = s.sheet.animations[s.animation]
      chispita_show_sheet_frame(s, current.frames[s.frame + 1])
    end
  end
end


-- Sprite movement
function chispita_begin_frame()
  for _, s in ipairs(chispita_sprites) do
    s.grounded = false
    if s.trigger then
      s.old_contacts = s.contacts
      s.contacts = {}
      s.was_trigger = true
    elseif s.was_trigger then
      s.contacts = {}
      s.old_contacts = {}
      s.was_trigger = false
    end

    if s.tile_touched then
      s.tile_contacts = {}
      s.tile_touched = false
    end

    if s.on_hit then
      s.old_hit_list = s.hit_list
      s.hit_list = {}
    end
  end
end

function chispita_move_sprites(dt)
  for _, s in ipairs(chispita_sprites) do
    if s.active and s.physics and s.kinematic and not s.fixed then
      s.old_x = s.x
      s.old_y = s.y
      s.x = s.x + s.vx * dt
      s.y = s.y + s.vy * dt
    end
  end

  for _, s in ipairs(chispita_sprites) do
    if s.active and s.physics and not s.fixed and not s.kinematic then
      s.old_x = s.x
      s.old_y = s.y
      if s.fall and chispita_mode == "platformer" then
        s.vy = s.vy - chispita_gravity * dt
      end
      if s.riding and s.riding.active then
        s.x = s.x + s.riding.x - s.riding.old_x
        s.y = s.y + s.riding.y - s.riding.old_y
      end
      s.riding = false
      s.x = s.x + s.vx * dt
      s.y = s.y + s.vy * dt
    end
  end
end

-- Sprite friction
function chispita_friction_factor(amount, frames)
  if frames == 1 then return amount end
  return pow(amount, frames)
end

function chispita_apply_friction(dt)
  local frames = dt * 60
  if frames <= 0 then return end
  local ground = chispita_friction_factor(chispita_friction, frames)
  local air = chispita_friction_factor(chispita_air_friction, frames)

  for _, s in ipairs(chispita_sprites) do
    if s.active and s.physics and not s.fixed and not s.kinematic and s.drag > 0 then
      if chispita_mode == "platformer" then
        if s.grounded then
          s.vx = s.vx * chispita_drag_keep(ground * chispita_friction_factor(s.friction, frames), s.drag)
        else
          s.vx = s.vx * chispita_drag_keep(air * chispita_friction_factor(s.air_friction, frames), s.drag)
        end
      elseif chispita_mode == "topdown" then
        local keep = chispita_drag_keep(ground * chispita_friction_factor(s.friction, frames), s.drag)
        s.vx = s.vx * keep
        s.vy = s.vy * keep
      end
    end
  end
end

function chispita_drag_keep(keep, drag)
  if drag == 1 then return keep end
  return 1 - (1 - keep) * drag
end

function chispita_update_lifetimes(dt)
  for _, s in ipairs(chispita_sprites) do
    if s.lifetime > 0 and s.active then
      s.lifetime = s.lifetime - dt
      if s.lifetime <= 0 then Chispita_remove(s) end
    end
  end
end

-- Sprite drawing
function chispita_draw_sprite(s)
  if s.alpha <= 0 then return end
  local x = chispita_screen_x(s, s.x)
  local y = chispita_screen_y(s, s.y)
  local w = 0
  local h = 0
  if s.hit_box_shape == "circle" then
    w = chispita_screen_size(s, s.radius * 2)
    h = w
  else
    w = chispita_screen_size(s, s.width)
    h = chispita_screen_size(s, s.height)
  end

  local margin = max(w, h) / 2
  if s.rotation ~= 0 then margin = max(w, h) end
  if x + margin < -screen.width / 2 or x - margin > screen.width / 2 then return end
  if y + margin < -screen.height / 2 or y - margin > screen.height / 2 then return end

  if s.alpha ~= 1 then screen:setAlpha(s.alpha) end
  if s.rotation ~= 0 then screen:setDrawRotation(s.rotation) end

  if s.image then
    local flipped = s.flip_x or s.flip_y
    if flipped then
      local scale_x = 1
      local scale_y = 1
      if s.flip_x then scale_x = -1 end
      if s.flip_y then scale_y = -1 end
      screen:setDrawScale(scale_x, scale_y)
    end
    if s.image_part then
      local p = s.image_part
      screen:drawSpritePart(s.image, p.x, p.y, p.w, p.h, x, y, w, h)
    else
      screen:drawSprite(s.image, x, y, w, h)
    end
    if flipped then screen:setDrawScale(1, 1) end
  elseif s.hit_box_shape == "circle" then
    if s.fill == "fill" then
      screen:fillRound(x, y, w, h, s.color)
    else
      screen:drawRound(x, y, w, h, s.color)
    end
  elseif s.hit_box_shape == "capsule" then
    if s.fill == "fill" then
      screen:fillRoundRect(x, y, w, h, w / 2, s.color)
    else
      screen:drawRoundRect(x, y, w, h, w / 2, s.color)
    end
  else
    if s.fill == "fill" then
      screen:fillRect(x, y, w, h, s.color)
    else
      screen:drawRect(x, y, w, h, s.color)
    end
  end

  if s.rotation ~= 0 then screen:setDrawRotation(0) end
  if s.alpha ~= 1 then screen:setAlpha(1) end
end
