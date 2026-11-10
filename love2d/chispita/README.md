# Chispita for LÖVE

A port of [Chispita](../../microstudio/chispita) to [LÖVE](https://love2d.org) 11, in Lua. Version **0.21**.

It has the same functions, settings and behavior as the microStudio version, file for file. A game written for one should move to the other with small changes. It uses no physics library: the collisions are Chispita's own, the same code as on microStudio.

Run the demo from this folder with `love .`. Arrow keys move, UP jumps, D turns on debug mode and C changes the CRT preset.

## Using it in a game

Copy the `engine` folder into the game, then:

```lua
require("engine/chispita")

function love.load()
  Chispita_init()
  chispita_mode = "platformer"

  ground = Chispita_addRect(0, -80, 300, 20)
  ground.fixed = true

  player = Chispita_addRect(0, 0, 14, 14)
  Chispita_setTarget(player)
end

function love.update(dt)
  if keyboard.LEFT then player.vx = player.vx - 20 end
  if keyboard.RIGHT then player.vx = player.vx + 20 end
  if keyboard.press.UP and player.grounded then player.vy = 220 end
  Chispita_update(dt)
end

function love.draw()
  Chispita_draw()
end
```

Every function and setting is described in the microStudio version's [CHISPITA_DOCS.txt](../../microstudio/chispita/CHISPITA_DOCS.txt). The CRT effect is described at the top of [`chispita_crt.lua`](engine/chispita_crt.lua).

## Files

Each engine file matches the microStudio file with the same name, function for function, so the two can be read side by side.

| File | Contents |
| --- | --- |
| [`chispita`](engine/chispita.lua) | Loads the other files |
| [`chispita_screen`](engine/chispita_screen.lua) | **LÖVE only.** microStudio's `screen`, `sprites`, `maps`, `mouse` and `keyboard`, so the rest of the engine (and game code) can stay the same |
| [`chispita_config`](engine/chispita_config.lua) | Default settings |
| [`chispita_main`](engine/chispita_main.lua) | `Chispita_init`, `Chispita_update`, `Chispita_draw` |
| [`chispita_sprite`](engine/chispita_sprite.lua) | Sprites, text, particles, sheets, animation |
| [`chispita_collision`](engine/chispita_collision.lua) | Shapes, collision resolution, groups, triggers, hurt boxes, raycasts |
| [`chispita_map`](engine/chispita_map.lua) | Tile maps, map collisions, tiling |
| [`chispita_camera`](engine/chispita_camera.lua) | Camera, screen positions, draw layers |
| [`chispita_timers`](engine/chispita_timers.lua) | Timers, tweens, game time |
| [`chispita_debug`](engine/chispita_debug.lua) | Debug overlays and panel (optional) |
| [`chispita_helpers`](engine/chispita_helpers.lua) | Math helpers (optional) |
| [`chispita_crt`](engine/chispita_crt.lua) | CRT effect (optional) |

## What's different from microStudio

The engine works the same way. These are the differences that come from Lua and LÖVE:

- **On and off are `true` and `false`.** microScript uses 1 and 0, but in Lua 0 counts as true, so `ground.fixed = 1` would work and `ground.fixed = 0` would not. Use `true`/`false` everywhere (`fixed`, `trigger`, `chispita_debug_mode`, `Debug.grid`...).
- **"Nothing" is `nil` or `false`.** Where microStudio gives back 0 for nothing (`Chispita_raycast` with no hit, `Camera.target` with no target), this version gives back `false` or `nil`.
- **Pass `dt`.** Call `Chispita_update(dt)` with LÖVE's `dt`. microStudio always runs at 60 frames a second; LÖVE doesn't.
- **Lists count from 1.** Lists the engine gives you (`Chispita_findGroup`, `Chispita_spawnFromMap`...) are Lua lists. Animation frame numbers still count from 0 (the top-left frame of a sheet), the same as microStudio.
- **Pictures** live in a `sprites` folder: `Chispita_addSprite("ship", ...)` loads `sprites/ship.png`.
- **Maps** are Lua files in a `maps` folder, drawn with letters, since LÖVE has no map editor. The format is explained in [`chispita_screen.lua`](engine/chispita_screen.lua), and [`maps/demo.lua`](maps/demo.lua) is an example.
- **Fonts:** text uses LÖVE's default font. `t.font = "name"` loads `fonts/name.ttf`.
- **Coordinates are microStudio's:** (0, 0) is the center of the window, y points up, and the shorter side of the window is 200 units. `screen.drawText`, `screen.fillRect` and the rest work in those units too.
- **The CRT effect** is simpler here: LÖVE draws the frame onto a small canvas and runs it through the shader, with no browser tricks.
