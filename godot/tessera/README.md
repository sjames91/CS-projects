# Tessera

A layered, cell-based pixel art editor in Godot 4 (GDScript + shaders). The
grid is the medium: every mark is a cell, every layer is a way of rendering
cells, and layers with different tilings stack on top of each other.

Open the folder in Godot 4.3+ and run. The project uses the Forward+ renderer
because compute shaders (RenderingDevice) need Vulkan / Metal / D3D12.

## Status

**Part 1 (full pixel editor): built and tested.**

- Canvas: size + cell size, grid lines, 9-point anchored resize (every layer and
  direction stroke moves with the anchor; GPU resample)
- Tools: pencil, eraser, eyedropper, line, rectangle, ellipse (outline/filled,
  brush size), flood fill (contiguous/global, OKLab tolerance), rectangle /
  lasso / magic-wand selection (add/subtract), move (Alt = copy), cut/copy/
  paste/delete, flip, rotate by the tiling's own symmetry step, mirror
  drawing (H/V/both), wrap-around drawing, 3×3 tile preview
- Mouse: left draws, right erases with any tool, wheel zooms at the cursor,
  middle-drag (or Space-drag) pans
- Layers: add, delete, duplicate, reorder, rename (double-click), show/hide,
  solo, lock, opacity, blend mode (normal, multiply, screen, overlay, add),
  static layers
- Color: one shared palette (≤255), add/remove/reorder (cells keep their color
  through a GPU remap), PNG import (A: exact unique colors in image order;
  B: k-means in OKLab to N colors, sorted into ramps), preview before accept,
  replace or append; export as PNG swatch strip, .hex, .gpl
- Palette Lock (final output only): OKLab nearest-color snap on export, with
  optional ordered dithering and strength; preview panel can show it
- Render toggle (Tab): full result vs. the selected layer's raw flat cells
- Preview panel: always the whole fully rendered image, never UI; palette
  lock view; click/drag to navigate the main view; hide with P, resizable
- Undo/redo: one completed action = one step (stroke, fill, full slider drag…)
- Save/load `.tessera` (JSON; cells zstd + base64). Every file stores a
  `format_version`; older files run through one small migration function per
  version (`ProjectIO.MIGRATIONS`); newer files load with a warning
- Export PNG: current frame, numbered frames, or sprite sheet, at any scale

**Tilings** (all through one interface, `src/tiling/tiling.gd`): square,
hexagon, triangle, diamond, Voronoi (jitter + seed). Changing a layer's tiling
resamples its cells (with a confirm dialog).

**Layer settings built so far:** tiling; cell styles (flat, dot, cross-stitch X,
LED dot, Lite-Brite peg, brush dab, mosaic tile, CRT phosphor); features:
rounding (plain, or color-aware with outer-only / inner+outer corners), gap +
grout color, hard or dithered color boundaries, jitter (position, size, rotation,
seed) driven by random or by a Direction Layer's flow, CRT scanlines, phosphor masks (aperture grille, slot, shadow),
beam spot, horizontal bleed.

**Part 2 (animation) — partly built:** frames per layer, static layers,
add/duplicate/delete/reorder frames, per-frame duration + FPS, play/pause,
loop/ping-pong/once, step, onion skin on the main canvas. Animated features
(flicker, noise, flow motion) are not built yet.

**Not built yet:** Patterns (reaction-diffusion, noise, Worley, halftone,
Bayer, hatching, weave/knit, wood/marble) and what they drive; SVG stamps
and the Shape Editor; Offset; the rest of the spec after "Jitter" in Part 3.

**Direction layers:** draw arrows/curves (left), erase strokes (right). A
flow field is computed on the GPU from the strokes (only when a stroke is
finished) and any layer can follow it via Jitter → Driven by → Flow.

## Architecture

```
src/core     App (autoload state + undo helpers), ProjectData, LayerData,
             ProjectIO (save/load/migrations), OkLab, UndoStack
src/tiling   Tiling interface + square/hex/triangle/diamond/voronoi, registry
src/gpu      Gpu autoload: compute kernels (palette snap, unique colors,
             k-means, cross-tiling resample, palette remap, flow field)
src/render   ShaderBuilder (layer, overlay, compositor shaders), RenderHub
             (cell textures + layer cache images), CompositeView
src/tools    ToolController (all tools), SelectionOps
src/ui       Main window and panels
tests        test_core.gd, interaction.tscn, screenshot.tscn
```

- **Cells** are palette indexes (0 = empty) in each layer's own grid, one byte
  per cell, uploaded as an R8 texture.
- **Rendering**: each tiling ships a GLSL snippet (`TL_cell`, `TL_center`,
  `TL_sdf`, `TL_inradius`) that is pasted into the layer shader, the grid /
  selection overlay shader and compute kernels, so the GPU and GDScript agree
  on which cell a point is in (checked by the tests).
- **Caching**: only the selected layer renders live. Every other layer is
  drawn from a cached `ImageTexture`, rebuilt only when its cells, settings,
  the palette or the canvas change (with a "rendering" indicator).
- **Compositing**: one compositor pass blends up to 16 layer textures with
  straight-alpha maths and all blend modes; more layers chain passes. (The
  Godot 2D backbuffer drops alpha, so screen-texture blending is not used.)
- **Heavy work** runs in compute shaders: palette snapping, palette
  extraction, k-means, resampling between tilings, palette remaps.

## Shortcuts

Tools: B pencil · E eraser · I eyedropper · L line · U rectangle · O ellipse ·
G fill · M rect select · Q lasso · W wand · V move. `[` `]` brush size.
Tab render toggle · Ctrl+G grid · T tile preview · Shift+T wrap · Y mirror ·
H / Shift+H flip · R / Shift+R rotate · Ctrl+Z / Ctrl+Shift+Z undo/redo ·
Ctrl+C/X/V · Delete · Ctrl+A / Ctrl+D · P preview · Shift+P palette-lock
preview · Enter play · , . step frames · F1 all shortcuts.

## Tests

Needs a Vulkan device (a software one such as lavapipe works):

```
godot --path . -s tests/test_core.gd           # tilings, GPU kernels, IO
godot --path . res://tests/interaction.tscn    # real mouse events on the canvas
godot --path . res://tests/screenshot.tscn     # renders every tiling/style (SHOT_DIR=…)
```
