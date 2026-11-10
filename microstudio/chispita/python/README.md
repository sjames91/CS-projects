# Chispita for microStudio, in Python

The Python version of [Chispita](..), version **0.1**, for microStudio projects set to Python. Same functions, settings and behavior as the microScript engine, file for file.

## Adding it to a project

Make a source file for each `.py` file here, with the same name, and paste it in. The files can be in any order. `chispita_debug`, `chispita_helpers` and `chispita_crt` are optional.

```python
def init():
  global ground, player, chispita_mode
  Chispita_init()
  chispita_mode = "platformer"

  ground = Chispita_addRect(0, -80, 300, 20)
  ground.fixed = 1

  player = Chispita_addRect(0, 0, 14, 14)
  Chispita_setTarget(player)

def update():
  if keyboard.LEFT: player.vx -= 20
  if keyboard.RIGHT: player.vx += 20
  if keyboard.press.UP and player.grounded: player.vy = 220
  Chispita_update()

def draw():
  Chispita_draw()
```

Every function and setting is described in [CHISPITA_DOCS.txt](../CHISPITA_DOCS.txt).

## Differences from microScript

Python works a lot like microScript: lists count from 0, 0 counts as false, and on/off is 1 and 0 as before. The differences:

- **Changing a setting inside a function needs `global`.** In Python, `chispita_mode = "platformer"` inside `init` makes a new local variable unless the function says `global chispita_mode` first, as in the example. The same goes for your own variables. Changing a field (`player.vx = 3`, `Camera.zoom = 2`) doesn't need it.
- **Sprites and other Chispita objects** are `chispita_obj`s: `s.x` and `s["x"]` are the same field, and a field that was never set is `None`. Make your own with `chispita_obj()`.
- **Every argument can be left out**, as in microScript; a left-out argument is `None`.
- **Callbacks are Python functions:** `def got_coin(self, other): ...` then `coin.on_enter = got_coin`.
- **The CRT effect** runs its JavaScript through `system.javascript`, and since JavaScript can't see Python's variables, `Chispita_applyCrt` passes the settings to it each frame.

microStudio runs Python with Brython. The engine was tested with regular Python against a stand-in for microStudio, so if something behaves differently in microStudio, it's likely a Brython difference.
