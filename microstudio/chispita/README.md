# Chispita

A small 2D game engine written in [microScript](https://microstudio.dev/documentation/microScript/) for [microStudio](https://microstudio.dev), a browser-based game maker. Current version: **0.14**.

microScript is a small Lua-like language. microStudio projects live in the browser, so the files here are plain-text copies of each source file (`.txt`). Each one is pasted into a microStudio source file of the same name.

## What it does

- **Sprites:** rects, circles, images, text, particles and animated sprite sheets.
- **Physics:** gravity, friction, bounce, grip, and fixed, kinematic and one-way bodies. There are platformer and top-down modes.
- **Collisions:**
  - Rect, circle and capsule shapes, and compound hit boxes built from several parts.
  - Collision groups, and triggers (`on_enter` / `on_exit`).
  - Separate hurt boxes for attacks.
  - Raycasts and area queries.
- **Tile maps** from the microStudio map editor: solid, one-way and hollow tiles, parallax, and maps that tile endlessly in either direction.
- **Camera:** follow with smoothing, deadzone, look-ahead, bounds, zoom, shake and draw layers.
- **Timers and tweens:** `Chispita_after`, `Chispita_every`, `Chispita_tween`.
- **Debug mode:** hit box, contact, map cell and camera overlays, an inspector, dragging and frame stepping.
- **Warnings:** microScript turns misspelled names into 0 instead of raising an error, so the engine prints a warning in the console for likely mistakes, like a sprite or map name that doesn't exist.

## A minimal game

```lua
init = function()
  Chispita_init()
  chispita_mode = "platformer"

  ground = Chispita_addRect(0, -80, 300, 20)
  ground.fixed = 1

  player = Chispita_addRect(0, 0, 14, 14)
  Chispita_setTarget(player)
end

update = function()
  if keyboard.LEFT then player.vx -= 20 end
  if keyboard.RIGHT then player.vx += 20 end
  if keyboard.press.UP and player.grounded then player.vy = 220 end
  Chispita_update()
end

draw = function()
  Chispita_draw()
end
```

## Other languages

microStudio projects can also be written in JavaScript, Lua or Python. Each has its own copy of the engine, with the same functions, settings and behavior:

- [`javascript/`](javascript)
- [`lua/`](lua)
- [`python/`](python)

There's also a [LÖVE version](../../love2d/chispita) for making games outside microStudio.

## Files

| File | Contents |
| --- | --- |
| [`chispita_config`](engine/chispita_config.txt) | Default settings (gravity, friction, mode, limits) |
| [`chispita_main`](engine/chispita_main.txt) | `Chispita_init`, `Chispita_update`, `Chispita_draw` |
| [`chispita_sprite`](engine/chispita_sprite.txt) | Sprites, text, particles, sheets, animation |
| [`chispita_collision`](engine/chispita_collision.txt) | Shapes, collision resolution, groups, triggers, hurt boxes, raycasts |
| [`chispita_map`](engine/chispita_map.txt) | Tile maps, map collisions, tiling |
| [`chispita_camera`](engine/chispita_camera.txt) | Camera, screen positions, draw layers |
| [`chispita_timers`](engine/chispita_timers.txt) | Timers, tweens, game time |
| [`chispita_debug`](engine/chispita_debug.txt) | Debug overlays (optional) |
| [`chispita_helpers`](engine/chispita_helpers.txt) | Math helpers (optional) |

All functions and settings are documented in [CHISPITA_DOCS.txt](CHISPITA_DOCS.txt).

## Conventions

- Functions a game calls are `Chispita_camelCase`. Engine internals are `chispita_lowercase`.
- Settings are lowercase `chispita_*` variables, and `Chispita_init` resets them to the values in `chispita_config`.
- Coordinates follow microStudio: (0, 0) is the center of the screen, and y points up.

The [shmup](../shmup) folder has a game being built on the engine.
