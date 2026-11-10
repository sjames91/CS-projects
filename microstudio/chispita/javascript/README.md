# Chispita for microStudio, in JavaScript

The JavaScript version of [Chispita](..), version **0.21**, for microStudio projects set to JavaScript. Same functions, settings and behavior as the microScript engine, file for file.

## Adding it to a project

Make a source file for each `.js` file here, with the same name, and paste it in. The files can be in any order. `chispita_debug`, `chispita_helpers` and `chispita_crt` are optional.

```js
function init() {
  Chispita_init()
  chispita_mode = "platformer"

  ground = Chispita_addRect(0, -80, 300, 20)
  ground.fixed = 1

  player = Chispita_addRect(0, 0, 14, 14)
  Chispita_setTarget(player)
}

function update() {
  if (keyboard.LEFT) player.vx -= 20
  if (keyboard.RIGHT) player.vx += 20
  if (keyboard.press.UP && player.grounded) player.vy = 220
  Chispita_update()
}

function draw() {
  Chispita_draw()
}
```

Every function and setting is described in [CHISPITA_DOCS.txt](../CHISPITA_DOCS.txt).

## Differences from microScript

Very few, since JavaScript works a lot like microScript: lists count from 0, 0 counts as false, and on/off is 1 and 0 as before.

- **Declare your own top-level variables with `var`, or with none at all.** microStudio runs each source file separately, so a `let` or `const` at the top of one file can't be seen from another.
- **Callbacks are JavaScript functions:** `coin.on_enter = function(self, other) { ... }`.
- **The CRT effect** runs directly, with no `system.javascript`, and reads its settings straight from the global variables.
