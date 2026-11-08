# Shmup (working title)

A side-scrolling ship game built on the [Chispita](../chispita) engine in microStudio. It's a work in progress. Right now you can fly a ship over a map, land it, get out and walk around as the pilot, and get back in.

**[▶ Play it in the browser](https://microstudio.io/Sjamescalaway/day1thegameplayloopdrawing/JE4B894V/)**

The files are plain-text copies of the microStudio source files. The sprites and maps they refer to (`ship_1`, `overworld/overworld`, and so on) are in the microStudio project and aren't included here.

## Controls

| Key | In the ship | On foot |
| --- | --- | --- |
| Left / Right | Thrust sideways | Walk |
| Up | Climb | Jump |
| Down | Dive | |
| Q | Get out (when landed) | Get in (when near the ship) |

## How it's put together

- [`main`](main.txt) wires the game into the engine's `init` / `update` / `draw`.
- [`level`](level.txt) builds each level: the solid map, plus a background map that tiles and scrolls with parallax.
- [`player_character`](player_character.txt) has the ship and the pilot.

### Ship flight model

Each ship is described by a few stats, and the handling comes from its shape:

- **Mass** comes from the total area of the ship's hit box parts. A bigger ship is heavier.
- **Drag** depends on the ship's width and height, measured from its parts. A tall, narrow ship falls faster and climbs more easily. A wide one falls more slowly but pushes more air when it moves sideways.
- **`top_speed`** sets the top speed. **`handling`** sets how fast the ship gets up to speed and stops, and it's scaled by mass. With the engines off, the ship falls at a rate set by its handling and shape.
- Speed-up and slow-down are written as exponential decay toward a target speed. This keeps top speed the same at any handling value and frame rate.

To add a new ship, give it hit box parts and stats, then call `player_ship_measure`.

### Getting in and out

The ship and the pilot are two sprites, and only one is active at a time:

- **Getting out:** raycasts check both sides of the ship for walls, so the pilot never appears inside one. If both sides are blocked, you stay in.
- **Getting in:** the pilot has to be near the ship and press Q.
- **Camera:** when you switch, the camera's smoothing drops low and then tweens back to normal. It glides to the new target instead of jumping.
