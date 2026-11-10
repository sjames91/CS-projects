-- microStudio-style screen, sprites, mouse and keyboard for LÖVE.
--
-- The microStudio version of Chispita draws with microStudio's "screen"
-- object. This file gives LÖVE the same calls, so the other engine files
-- can stay almost line for line the same as their microStudio twins.
-- Game code can use them too, which makes moving a game across easier.
--
-- Coordinates work like microStudio:
--   (0, 0) is the center of the window, y points UP, and the shorter side
--   of the window is 200 units. Everything is drawn centered on its x, y.
-- Colors are microStudio strings: "rgb(255,200,80)", "rgba(0,0,0,0.5)"
-- or "#ffc850".

local lg = love.graphics

-- Small math helpers microScript has built in.
function chispita_sind(a) return math.sin(a * math.pi / 180) end
function chispita_cosd(a) return math.cos(a * math.pi / 180) end

random = {}
function random.next() return love.math.random() end


-- Colors -----------------------------------------------------------------

local color_cache = {}

function chispita_color(text)
  local c = color_cache[text]
  if c then return c end
  local r, g, b, a
  local inside = text:match("^rgba?%((.*)%)$")
  if inside then
    local parts = {}
    for n in inside:gmatch("[^,]+") do parts[#parts + 1] = tonumber(n) end
    r, g, b, a = (parts[1] or 0) / 255, (parts[2] or 0) / 255, (parts[3] or 0) / 255, parts[4] or 1
  elseif text:match("^#%x%x%x%x%x%x$") then
    r = tonumber(text:sub(2, 3), 16) / 255
    g = tonumber(text:sub(4, 5), 16) / 255
    b = tonumber(text:sub(6, 7), 16) / 255
    a = 1
  else
    r, g, b, a = 1, 1, 1, 1
    chispita_warn("can't read the color " .. tostring(text) .. ". Use \"rgb(255,200,80)\" or \"#ffc850\".")
  end
  c = { r, g, b, a }
  color_cache[text] = c
  return c
end


-- Images: sprites["name"] loads sprites/name.png the first time ------------

sprites = setmetatable({}, {
  __index = function(list, name)
    if type(name) ~= "string" then return nil end
    local path = "sprites/" .. name .. ".png"
    if not love.filesystem.getInfo(path) then return nil end
    local image = lg.newImage(path)
    image:setFilter("nearest", "nearest")
    local picture = { image = image, width = image:getWidth(), height = image:getHeight(), name = name }
    rawset(list, name, picture)
    return picture
  end
})


-- The screen ---------------------------------------------------------------

screen = {
  width = 200,          -- in units, set each frame from the window size
  height = 200,
  ratio = 1,            -- pixels per unit
  pixel_width = 1,      -- size of what's being drawn on, in pixels: the
  pixel_height = 1,     -- window, or the CRT effect's small canvas
  alpha = 1,
  line_width = 1,
  rotation = 0,         -- setDrawRotation, degrees, counterclockwise
  scale_x = 1,          -- setDrawScale
  scale_y = 1,
  anchor_x = 0,         -- setDrawAnchor: -1 = left/bottom, 0 = center, 1 = right/top
  anchor_y = 0,
  font = "default",
  fonts = {},
  quads = {},
}

-- Works out the size of the screen in units. Chispita calls this every frame.
function screen.update()
  local w, h = lg.getDimensions()
  local target = lg.getCanvas()
  if target then w, h = target:getDimensions() end
  screen.pixel_width = w
  screen.pixel_height = h
  screen.ratio = math.min(w, h) / 200
  screen.width = w / screen.ratio
  screen.height = h / screen.ratio
end

-- Sets up a drawing operation centered at x, y (units) with the current
-- rotation and scale. Ends with screen.finish().
local function begin(x, y)
  lg.push()
  lg.translate(screen.pixel_width / 2, screen.pixel_height / 2)
  lg.scale(screen.ratio, screen.ratio)
  lg.translate(x, -y)
  if screen.rotation ~= 0 then lg.rotate(-screen.rotation * math.pi / 180) end
  if screen.scale_x ~= 1 or screen.scale_y ~= 1 then lg.scale(screen.scale_x, screen.scale_y) end
end

local function finish()
  lg.pop()
end

local function use_color(color)
  local c = chispita_color(color or "rgb(255,255,255)")
  lg.setColor(c[1], c[2], c[3], c[4] * screen.alpha)
end

-- Top-left corner of a w by h box drawn at the origin, after the anchor.
local function corner(w, h)
  return -w / 2 - screen.anchor_x * w / 2, -h / 2 + screen.anchor_y * h / 2
end

function screen.clear(color)
  local c = chispita_color(color or "rgb(0,0,0)")
  lg.clear(c[1], c[2], c[3], 1)
end

function screen.setAlpha(alpha) screen.alpha = alpha end
function screen.setLineWidth(width) screen.line_width = width end
function screen.setDrawRotation(angle) screen.rotation = angle end
function screen.setDrawScale(x, y) screen.scale_x = x; screen.scale_y = y or x end
function screen.setDrawAnchor(x, y) screen.anchor_x = x; screen.anchor_y = y end
function screen.setFont(font) screen.font = font or "default" end

function screen.fillRect(x, y, w, h, color)
  begin(x, y)
  use_color(color)
  local cx, cy = corner(w, h)
  lg.rectangle("fill", cx, cy, w, h)
  finish()
end

function screen.drawRect(x, y, w, h, color)
  begin(x, y)
  use_color(color)
  lg.setLineWidth(screen.line_width)
  local cx, cy = corner(w, h)
  lg.rectangle("line", cx, cy, w, h)
  finish()
end

function screen.fillRoundRect(x, y, w, h, round, color)
  begin(x, y)
  use_color(color)
  local cx, cy = corner(w, h)
  lg.rectangle("fill", cx, cy, w, h, round, round, 24)
  finish()
end

function screen.drawRoundRect(x, y, w, h, round, color)
  begin(x, y)
  use_color(color)
  lg.setLineWidth(screen.line_width)
  local cx, cy = corner(w, h)
  lg.rectangle("line", cx, cy, w, h, round, round, 24)
  finish()
end

function screen.fillRound(x, y, w, h, color)
  begin(x, y)
  use_color(color)
  local cx, cy = corner(w, h)
  lg.ellipse("fill", cx + w / 2, cy + h / 2, w / 2, h / 2, 32)
  finish()
end

function screen.drawRound(x, y, w, h, color)
  begin(x, y)
  use_color(color)
  lg.setLineWidth(screen.line_width)
  local cx, cy = corner(w, h)
  lg.ellipse("line", cx + w / 2, cy + h / 2, w / 2, h / 2, 32)
  finish()
end

function screen.drawLine(x1, y1, x2, y2, color)
  begin(0, 0)
  use_color(color)
  lg.setLineWidth(screen.line_width)
  lg.line(x1, -y1, x2, -y2)
  finish()
end

-- screen.drawPolygon({x1, y1, x2, y2, ...}, color), points in units.
function screen.drawPolygon(points, color)
  begin(0, 0)
  use_color(color)
  lg.setLineWidth(screen.line_width)
  local flipped = {}
  for i = 1, #points, 2 do
    flipped[i] = points[i]
    flipped[i + 1] = -points[i + 1]
  end
  lg.polygon("line", flipped)
  finish()
end

-- name is a picture in the sprites folder (without ".png").
function screen.drawSprite(name, x, y, w, h)
  local picture = sprites[name]
  if not picture then return end
  if not w then w = picture.width end
  if not h then h = w * picture.height / picture.width end
  begin(x, y)
  lg.setColor(1, 1, 1, screen.alpha)
  local cx, cy = corner(w, h)
  lg.draw(picture.image, cx, cy, 0, w / picture.width, h / picture.height)
  finish()
end

-- Draws the part of a picture starting at sx, sy (pixels from its top-left
-- corner), sw by sh pixels in size.
function screen.drawSpritePart(name, sx, sy, sw, sh, x, y, w, h)
  local picture = sprites[name]
  if not picture then return end
  local key = name .. ":" .. sx .. "," .. sy .. "," .. sw .. "," .. sh
  local quad = screen.quads[key]
  if not quad then
    quad = lg.newQuad(sx, sy, sw, sh, picture.width, picture.height)
    screen.quads[key] = quad
  end
  begin(x, y)
  lg.setColor(1, 1, 1, screen.alpha)
  local cx, cy = corner(w, h)
  lg.draw(picture.image, quad, cx, cy, 0, w / sw, h / sh)
  finish()
end

-- Text "size" units tall. The font is made at the window's real pixel
-- size so it stays sharp.
local function font_for(size)
  local pixels = math.max(1, math.floor(size * screen.ratio + 0.5))
  local key = screen.font .. ":" .. pixels
  local f = screen.fonts[key]
  if not f then
    if screen.font ~= "default" and love.filesystem.getInfo("fonts/" .. screen.font .. ".ttf") then
      f = lg.newFont("fonts/" .. screen.font .. ".ttf", pixels)
    else
      f = lg.newFont(pixels)
    end
    screen.fonts[key] = f
  end
  return f, pixels
end

function screen.textWidth(text, size)
  local f, pixels = font_for(size)
  return f:getWidth(tostring(text)) * size / pixels
end

function screen.drawText(text, x, y, size, color)
  text = tostring(text)
  local f, pixels = font_for(size)
  local scale = size / pixels
  local w = f:getWidth(text) * scale
  local h = f:getHeight() * scale
  begin(x, y)
  use_color(color)
  lg.setFont(f)
  local cx, cy = corner(w, h)
  lg.print(text, cx, cy, 0, scale, scale)
  finish()
end


-- Mouse: mouse.x, mouse.y in units, mouse.pressed while held,
-- mouse.press on the frame it goes down, mouse.release on the frame it
-- comes back up. Updated at the start of every love.update.

mouse = { x = 0, y = 0, pressed = false, press = false, release = false, left = false, right = false, middle = false }

local function update_mouse()
  local mx, my = love.mouse.getPosition()
  local w, h = lg.getDimensions()
  local ratio = math.min(w, h) / 200
  mouse.x = (mx - w / 2) / ratio
  mouse.y = (h / 2 - my) / ratio
  local was = mouse.pressed
  mouse.left = love.mouse.isDown(1)
  mouse.right = love.mouse.isDown(2)
  mouse.middle = love.mouse.isDown(3)
  mouse.pressed = mouse.left or mouse.right or mouse.middle
  mouse.press = mouse.pressed and not was
  mouse.release = was and not mouse.pressed
end


-- Keyboard: keyboard.LEFT is true while the left arrow is held, and
-- keyboard.press.LEFT / keyboard.release.LEFT on the frame it goes down
-- or up, like microStudio. Names are LÖVE key names in capitals:
-- LEFT, RIGHT, UP, DOWN, SPACE, A, Z, RETURN, LSHIFT...

local keys_down = {}
local keys_before = {}
local keys_watched = {}

local function key_down(name)
  name = string.lower(name)
  local ok, down = pcall(love.keyboard.isDown, name)
  return ok and down
end

local function watch(name)
  if not keys_watched[name] then
    keys_watched[name] = true
    keys_down[name] = key_down(name)
    keys_before[name] = keys_down[name]
  end
end

keyboard = setmetatable({
  press = setmetatable({}, { __index = function(_, name)
    watch(name)
    return keys_down[name] and not keys_before[name]
  end }),
  release = setmetatable({}, { __index = function(_, name)
    watch(name)
    return keys_before[name] and not keys_down[name]
  end }),
}, { __index = function(_, name)
  watch(name)
  return keys_down[name]
end })

local function update_keyboard()
  for name in pairs(keys_watched) do
    keys_before[name] = keys_down[name]
    keys_down[name] = key_down(name)
  end
end

function chispita_update_input()
  update_mouse()
  update_keyboard()
end

-- Chispita_init calls this so the mouse and keyboard are read at the start
-- of every frame, before the game's own love.update.
function chispita_hook_input()
  if chispita_input_hooked == love.update then return end
  local game_update = love.update
  love.update = function(dt)
    chispita_update_input()
    if game_update then game_update(dt) end
  end
  chispita_input_hooked = love.update
  chispita_update_input()
end


-- Maps: maps["name"] loads maps/name.lua the first time ---------------------
--
-- microStudio has a map editor; here a map is a Lua file you can read and
-- edit by hand. maps/level1.lua:
--
--   return {
--     block_width = 16,          -- size of one tile's picture, in pixels
--     block_height = 16,
--     legend = {                 -- what each letter in the rows means
--       ["#"] = "brick",         -- the picture sprites/brick.png
--       ["="] = "tiles:2,0",     -- column 2, row 0 of sprites/tiles.png
--     },
--     rows = {                   -- top row first, "." or " " = empty
--       "..........",
--       "...===....",
--       "##########",
--     },
--   }
--
-- The map object works like microStudio's: map.width and map.height in
-- cells, map.get(cx, cy) and map.set(cx, cy, value) where cy = 0 is the
-- BOTTOM row, map.clone() and map.update().

function chispita_make_map(data)
  local map = {
    block_width = data.block_width or 16,
    block_height = data.block_height or data.block_width or 16,
    height = #data.rows,
    width = 0,
    cells = {},
  }
  for _, row in ipairs(data.rows) do map.width = math.max(map.width, #row) end
  -- cells[cy * width + cx + 1], with cy counted from the bottom
  for r, row in ipairs(data.rows) do
    local cy = map.height - r
    for cx = 0, #row - 1 do
      local letter = row:sub(cx + 1, cx + 1)
      if letter ~= "." and letter ~= " " then
        local value = data.legend and data.legend[letter]
        if not value then
          chispita_warn("a map has the letter '" .. letter .. "' but its legend doesn't say what it is.")
        else
          map.cells[cy * map.width + cx + 1] = value
        end
      end
    end
  end

  function map.get(cx, cy)
    if cx < 0 or cy < 0 or cx >= map.width or cy >= map.height then return nil end
    return map.cells[cy * map.width + cx + 1]
  end

  function map.set(cx, cy, value)
    if cx < 0 or cy < 0 or cx >= map.width or cy >= map.height then return end
    map.cells[cy * map.width + cx + 1] = value
  end

  function map.clone()
    local copy = chispita_make_map({ block_width = map.block_width, block_height = map.block_height, rows = {} })
    copy.width = map.width
    copy.height = map.height
    for k, v in pairs(map.cells) do copy.cells[k] = v end
    return copy
  end

  function map.update() end

  return map
end

maps = setmetatable({}, {
  __index = function(list, name)
    if type(name) ~= "string" then return nil end
    local path = "maps/" .. name .. ".lua"
    if not love.filesystem.getInfo(path) then return nil end
    local map = chispita_make_map(love.filesystem.load(path)())
    rawset(list, name, map)
    return map
  end
})

-- Draws a whole map w by h units, centered at x, y. Only the cells on the
-- screen are drawn.
function screen.drawMap(map, x, y, w, h)
  if type(map) == "string" then map = maps[map] end
  if not map then return end
  local cw = w / map.width
  local ch = h / map.height
  local left = x - w / 2
  local bottom = y - h / 2
  local x0 = math.max(0, math.floor((-screen.width / 2 - left) / cw))
  local x1 = math.min(map.width - 1, math.floor((screen.width / 2 - left) / cw))
  local y0 = math.max(0, math.floor((-screen.height / 2 - bottom) / ch))
  local y1 = math.min(map.height - 1, math.floor((screen.height / 2 - bottom) / ch))
  for cy = y0, y1 do
    for cx = x0, x1 do
      local cell = map.get(cx, cy)
      if cell then
        local name, column, row = cell:match("^([^:]*):(%d+),(%d+)$")
        local tx = left + (cx + 0.5) * cw
        local ty = bottom + (cy + 0.5) * ch
        if name then
          screen.drawSpritePart(name, tonumber(column) * map.block_width, tonumber(row) * map.block_height,
            map.block_width, map.block_height, tx, ty, cw, ch)
        else
          screen.drawSprite(cell, tx, ty, cw, ch)
        end
      end
    end
  end
end
