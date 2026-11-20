# Tessera

A layered, cell-based pixel art editor in Godot 4 (GDScript + shaders). The
grid is the medium: every mark is a cell, every layer is a way of rendering
cells, and layers with different tilings stack on top of each other.

Open the folder in Godot 4.3+ and run. The project uses the Forward+ renderer
because compute shaders (RenderingDevice) need Vulkan / Metal / D3D12.

## Status

Everything in the spec is built, in its build order. Tests run under a
real Vulkan device (see Tests). Known gaps are listed at the end.

- **Part 1, full editor:** all tools through the Tiling interface, layers,
  shared palette with OKLab matching, PNG palette import (exact / k-means),
  Palette Lock, render toggle, preview panel, undo/redo, versioned
  save/load with migrations (project format v3).
- **Part 2, animation:** per-layer frames, static layers, timeline,
  playback (loop / ping-pong / once), onion skin, per-frame caches;
  animated features (interlace flicker, static noise, flow drift) get
  their own frames when playing or exporting.
- **Layer Settings (all six sections):**
  - 1 Tiling: square, hexagon, triangle, diamond, Voronoi, and custom
    Shape Editor tilings.
  - 2 Cell style: flat, dot, cross-stitch, LED, Lite-Brite, brush dab,
    mosaic, CRT phosphor, SVG stamp.
  - 3 Features: rounding (color-aware outer / inner+outer), gap/grout,
    dithered boundaries, jitter (random / pattern / flow), scanlines,
    phosphor masks, beam spot, horizontal bleed.
  - 4 Patterns: up to 4 stacked slots. Sources: reaction-diffusion, value /
    Perlin / fractal noise, Worley, halftone, Bayer, hatching, weave, knit,
    wood, marble, lightness. Each slot drives style, size, rotation,
    rounding, gap, jitter, palette shift and visibility, with color filter,
    seed + Randomize, map view and fine texture.
  - 5 Offset: half X/Y/both, brick rows/columns (only on non-staggered
    tilings), amount; a Tiling decorator, so clicks land on shifted cells.
  - 6 Flow: follow a direction layer with a strength; stamp / cell rotation,
    pattern bending, anisotropic reaction-diffusion, jitter push, animated
    drift.
- **Display stack:** curvature, vignette, bloom, chromatic aberration,
  interlace flicker, static noise; TV / arcade / PVM / handheld presets.
  Order: layers → Display → Palette Lock → export.
- **Part 4, direction layers:** arrow, curve, Bezier and edit tools; swirl
  and radial strokes; per-stroke radius and strength; smoothing and default
  direction; field as arrows or streamlines (main canvas only); per frame;
  SVG paths to strokes.
- **Shape Editor:** tiling shapes that always tile (paired edges by
  construction, curved edges, linked corners, built-in chevron / puzzle /
  fish scale / lizard), stamp shapes with holes, SVG import (as stamp or
  fitted to a base tile) and export.
- **Presets and library:** 21 built-in layer presets plus display,
  direction and full-stack presets; user presets and shapes stored as
  versioned files in `user://library`, with zip export/import; projects
  embed the shapes they use.
- **Export** (`Exporter.FORMATS` registry): PNG at any scale (rendered or
  raw cells, all layers or one), zipped PNG sequence, animated GIF and APNG
  (built-in encoders), SVG vector cells, direction field image.
- **Flatten / Apply** (Layer menu): the only action that bakes effects
  (pattern palette shift and visibility) into cells.

### Known gaps

- Curved outlines are flattened at a fixed resolution (6 segments per
  curve), not matched to zoom or export scale.
- Plain rounding is not applied to custom-shape tilings (gap and
  color-aware rounding work). Color-aware rounding ignores pattern drives.
- Still on the CPU in GDScript: flood fill, global fill and wand, move
  lift, selection transforms, the per-cell SVG text, GIF LZW and APNG CRC.
  Fine at 64×64; not measured at 256×256.
- The 256×256 / 10-layer performance target and the export presets
  (`export_presets.cfg`) have not been checked on real hardware or with
  export templates.

## Architecture

```
src/core     App (autoload state + undo helpers), ProjectData, LayerData,
             ProjectIO (save/load/migrations), OkLab, UndoStack
src/tiling   Tiling interface + square/hex/triangle/diamond/voronoi,
             OffsetTiling decorator, registry
src/shapes   Shape model, ShapeTiling, SVG import/export, stamp SDF
src/patterns Pattern GLSL library, per-cell map + reaction-diffusion kernels
src/direction DirStroke (types, Bezier, presets)
src/library  Presets and user library storage
src/export   Exporter registry, GIF / APNG encoders
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
godot --path . res://tests/test_core.tscn      # tilings × offsets, GPU kernels, IO, migrations
godot --path . res://tests/interaction.tscn    # real mouse events on the canvas
godot --path . res://tests/screenshot.tscn     # renders every tiling/style (SHOT_DIR=…)
SCENARIO=patterns godot --path . res://tests/visual.tscn   # see tests/visual.gd
```
