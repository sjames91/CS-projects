# Chispita for microStudio, in Lua

The Lua version of [Chispita](..), version **0.1**, for microStudio projects set to Lua. Same functions, settings and behavior as the microScript engine, file for file. It's the [LÖVE port](../../../love2d/chispita) with its drawing swapped for microStudio's.

## Adding it to a project

Make a source file for each `.lua` file here, with the same name, and paste it in. The files can be in any order. `chispita_debug`, `chispita_helpers` and `chispita_crt` are optional.

```lua
init = function()
  Chispita_init()
  chispita_mode = "platformer"

  ground = Chispita_addRect(0, -80, 300, 20)
  ground.fixed = true

  player = Chispita_addRect(0, 0, 14, 14)
  Chispita_setTarget(player)
end

update = function()
  if keyboard.LEFT == 1 then player.vx = player.vx - 20 end
  if keyboard.RIGHT == 1 then player.vx = player.vx + 20 end
  if keyboard.press.UP == 1 and player.grounded then player.vy = 220 end
  Chispita_update()
end

draw = function()
  Chispita_draw()
end
```

Every function and setting is described in [CHISPITA_DOCS.txt](../CHISPITA_DOCS.txt).

## Differences from microScript

These all come from Lua itself:

- **On and off are `true` and `false`.** In Lua 0 counts as true, so `ground.fixed = 0` wouldn't switch it off. Use `true`/`false` for every Chispita setting.
- **microStudio's own values are still 1 and 0.** `keyboard.LEFT`, `mouse.pressed` and the like come from microStudio, so check them with `== 1`, as in the example.
- **microStudio's functions take `:`**: `screen:drawText(...)`, `random:next()`, `system:time()`. Chispita's own functions take a plain call: `Chispita_addRect(...)`.
- **"Nothing" is `nil` or `false`.** Where microScript gives back 0 for nothing (`Chispita_raycast` with no hit, an empty map cell from `Chispita_cellAt`), this version gives back `false` or `nil`.
- **Lists count from 1.** Lists the engine gives you (`Chispita_findGroup`, `Chispita_spawnFromMap`...) are Lua lists. Animation frame numbers still count from 0, as in microScript.
- **The CRT effect** runs its JavaScript through `system:javascript`, and since JavaScript can't see Lua's variables, `Chispita_applyCrt` passes the settings to it each frame.
