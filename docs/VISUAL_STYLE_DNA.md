# Visual Style DNA — a transferable rendering style

How the graphics of this project **look** and **are constructed**, written so another
project can reproduce the same style in any setting. Nothing here prescribes subject
matter, era, architecture, lore or a fixed palette.

Every rule is tagged:

- **Observed**: verified in this repository's assets, generator code or Godot settings
  (file references given).
- **Inferred**: a visual characteristic read from the artwork and rendered screenshots,
  not set explicitly anywhere.
- **Recommended**: a practical rule for recreating the look elsewhere.

Measurements come from the shipped PNGs in `assets/provisional/` (analysed with
numpy: HSV saturation/value of opaque pixels, outline run lengths at alpha edges) and
from captured gameplay frames at 1600×900.

> **Implementation vs. style.** The originals happen to be drawn procedurally by Python
> scripts (`tools/art/*.py`). That is a production choice, not part of the look; a
> painter or an image model can produce the same result. Where a technique only exists
> to make code-drawn art behave like drawn art (supersampling, seeded noise), it is
> listed under *Implementation notes*, not under the style.

---

## 1. Projection and camera

**Observed**
- Pure top-down orthographic 2D: `Camera2D`, no perspective, no isometric skew.
  Everything (floors, furniture, characters) is drawn as seen from directly above.
- Grid: 1 cell = 32 world px (`Defs.CELL`); art is authored at **64 px per cell**
  (`HouseView.ART_SCALE = 0.5`), i.e. twice the world density.
- Camera zoom 1.55 at a 1600×900 canvas (`Run.CAMERA_ZOOM`): one cell ≈ 50 screen px,
  one art texel ≈ 0.78 screen px, so art is always very slightly *down*-sampled, never
  magnified.
- Characters are round "tokens" (miniature on a base, seen from above) drawn facing
  **+X**; the game rotates the whole token to the direction of travel
  (`TokenSprite.face`). Furniture is authored at rotation 0 and rotated in 90° steps.
- Depth cues are all 2D: a soft drop shadow offset down-right under every token and
  object, layer order (floors → weathering → rugs → decals → furniture → actors →
  overlay; `HouseView._layer`), and occlusion of light by walls.

**Inferred**
- The implied light comes from the **upper-left**; shadows always fall down-right.
  It's a fixed "studio" direction, not tied to the in-game light sources.
- Objects show a sliver of their top silhouette only (a chair seat, a table top, a
  head and shoulders), never their sides — a "board-game miniature" reading.

**Recommended**
- Keep strict orthographic top-down. No visible side faces, no vanishing points.
- Author every asset at 2× its on-screen world size and display it at 0.75–1.0 texel
  per screen pixel.
- Draw movable characters facing one canonical direction (right) and rotate in-engine.
- Use one global light direction for baked shading (upper-left) and one consistent
  drop-shadow offset (down-right) across all assets.

## 2. Illustration technique

**Observed**
- **Ink-and-wash**: a near-black warm ink outline (RGB 19,16,15; `core.INK`) around
  flat or gently graded colour fills, with hatched shading inside.
- Outline construction: the silhouette is dilated by the outline width with a
  low-frequency noise displacement, so lines **wobble slightly** like a hand-held pen
  (`Canvas.ink`, `wobble=True`).
- Outline widths (at authoring resolution): furniture ≈ 4 px per 64-px cell (≈ 2 world
  px), items 1–2 px on a 64-px sprite, icons ≈ 2 px on 48 px (`ITEM_ST.ow = 2.0`,
  `ICON_ST.ow = 2.1`), detail strokes 1.0–1.35 px. Measured median outline run: tokens
  2.1 px, items 1.1 px, furniture 4.2 px.
- Shapes are built from smooth Catmull-Rom curves and ellipses with small random wobble
  (`catmull`, `wobble_pts`); straight edges are rarely perfectly straight.
- A fine **paper/pigment grain** (≈ 6 % multiplicative noise at two scales) covers
  finished assets (`Canvas.grain(0.06)`).
- Icons add a thin **light halo** (≈ 1 px, warm off-white) outside the ink line, so
  they separate from dark backgrounds (`items_icons.halo`).

**Inferred**
- Reads as a hand-inked illustration that has been coloured with ink washes, not as
  pixel art and not as a painterly oil look. Edges are crisp but anti-aliased.
- Detail is concentrated at silhouette and a few interior strokes (seams, folds,
  grain lines), not spread evenly; interiors stay readable at small sizes.

**Recommended**
- Every object: one closed, slightly irregular dark outline (2–4 % of the object's
  width), then flat base colour, then interior detail strokes at ~50 % of the outline
  width. Never leave a coloured edge without ink, except light-emitting effects.
- Keep line colour near-black and *slightly* warm or cool, never pure #000.
- Add a subtle, even grain (5–7 %) after shading so every asset shares one "paper".

## 3. Shading

**Observed** (`Canvas.part`, defaults per style)
- **Form shadow** = an inner band along the lower-right edge of each shape, made by
  offsetting the shape by `depth` (2–4 px) and blurring (σ ≈ 0.6·depth). It is
  multiplied toward a **cool, desaturated shadow colour** (RGB 38,40,56) at 30–45 %.
- **Hatching** sits only inside the shadow band: parallel lines at 45°, spacing ≈ 3 px,
  width ≈ 0.8 px, opacity 35–55 %; the deepest part gets a second, cross direction
  (−45°). Lines are dashed (dash ≈ 12–14 px) so they read hand-made.
- **Rim light** on the opposite (upper-left) edge: a screen-blend toward warm
  off-white (RGB 255,240,210) at 22–30 %.
- Optional **inner occlusion** (`soft`): a blurred darkening just inside the outline,
  for rounded or soft materials.
- **Cast/drop shadow** behind each sprite: offset (+3, +4) px, blur σ 2.5, 50–55 %
  near-black (furniture); (+1.5, +2) σ 1.4 at 50 % (items). Characters get a runtime
  shadow: the same sprite tinted black at 50 %, offset (3, 4), scaled 1.04.
- Volume fills: many base colours are 45° linear gradients from a lighter to a darker
  tone of the same hue (`gradient(..., 45)`).

**Inferred**
- Dimensionality is "shallow relief": objects look like thick cut-outs with bevelled
  edges, not fully modelled 3D forms. Shadow shapes hug silhouettes.
- Shadows are cooler than lights, a constant temperature split.

**Recommended**
- Light from upper-left; shade a band 4–6 % of the object size along the lower-right
  edge; hatch only inside it (45°, about 3 px spacing at 2× resolution); cross-hatch
  the darkest 1/3 of the band.
- Shadow colour: the scene's ambient hue, desaturated, about 15–20 % value. Highlight:
  warm near-white, screen-blended, thin.
- Every sprite gets a soft drop shadow down-right; keep its offset identical across
  all assets of the same layer.

## 4. Materials (setting-independent)

**Observed** (`core.wood_tex`, `noise_tex`, `fabric_tex`; floors in `floors.py`)
- **Wood / fibrous surfaces**: sine banding along one axis distorted by low-frequency
  noise (grain rings), plus fine streaks; dark grain lines pulled 75 % toward a
  darker tone, highlights 18 % toward a lighter tone. Planks are separate cells with
  their own tone, seam lines in ink, and bevelled lower-right edges.
- **Stone / mineral surfaces**: fractal noise (4 octaves) at ±15 % value around a base
  colour; blocks/tiles as a label map with ink seams and per-tile bevel (dark
  lower-right rim 45 %, light upper-left rim 25 %).
- **Fabric / soft surfaces**: base colour × (1 ± 12 % broad noise + 5 % fine sinusoidal
  weave); inner occlusion instead of hard hatching; folds as thin ink curves.
- **Metal / glass**: smooth gradient fill, a sharp small gloss ellipse or streak
  (`gloss`) and a thin bright highlight line; little or no grain.
- **Vegetation**: clustered rounded blobs (leaf masses) with darker lower-right
  overlap shadows and a few light flecks on top.
- **Weathering** (an overlay, not baked into the material): tiled grime, damp and
  crack masks, blended at low alpha; pale "dust/tide" layers via a light colour.
  Rooms can be desaturated 0.5–0.88 and slightly tinted for an aged look.
- Floors are calmed at render time: texture detail is pulled 35 % toward each
  material's average colour (`HouseView.FLOOR_CALM`).

**Recommended**
- Distinguish materials by **texture pattern and edge treatment**, not by stronger
  colour: wood = directional banding, stone = isotropic mottling + bevelled blocks,
  fabric = soft weave + inner occlusion, metal = gradient + one sharp specular.
- Keep large surfaces (floors, walls) low in contrast (value std ≈ 0.13) so props
  and characters read on top of them.
- Keep weathering as separate low-opacity overlays so it can be dialled per area.

## 5. Colour

**Observed** (mean over opaque pixels)

| Asset group | Saturation | Value | Value std | Notes |
|---|---|---|---|---|
| Characters (tokens, on their base) | 0.20 (max 0.37) | 0.24 | 0.19 | darkest group |
| Props / items | 0.33 (accents up to 0.86) | 0.43 | 0.18 | small, saturated accents allowed |
| Furniture | 0.34 (max 0.57) | 0.33 | 0.18 | |
| Floors | 0.34 (max 0.67) | 0.31 | 0.13 | lowest contrast |
| UI icons | 0.30 (max 0.56) | 0.44 | 0.25 | highest contrast (readability) |

- Hue concentration per asset (mean resultant length of hues) is 0.6–0.9: each asset
  sticks to **one hue family** plus neutrals and one accent.
- Final grade in-game: the whole world is multiplied by a cool, dark ambient
  (`CanvasModulate` ≈ RGB 0.23, 0.24, 0.32), then lit additively by **warm** lights
  (e.g. 1.0, 0.78, 0.5). Measured rendered frames: median luminance 0.03–0.05, 95th
  percentile ≈ 0.2, 99th ≈ 0.42, mean saturation 0.32–0.39.
- Mood states change only the ambient multiply (e.g. darker for danger, tinted for
  special events), recomposed from layers rather than replaced (`_effective_darkness`).

**Inferred**
- Albedos are mid-dark and muted, so the *lighting* creates contrast rather than the
  paint. Saturation rises where light falls, because the multiply keeps hue while the
  additive warm light lifts it.
- Contrast relationships: cool ambient vs warm light; muted bodies vs a few saturated
  accents (signals, hazards, important items).

**Recommended**
- Paint albedos at value 0.25–0.45 and saturation 0.2–0.35; reserve saturation > 0.6
  for small accents that must be noticed.
- One dominant hue family per asset; neutrals lean toward the scene's ambient hue.
- Grade the scene with a single multiply colour (ambient) that is darker and colour-
  temperature-opposite to the main light sources. Keep the rendered median very dark
  (luma ≈ 0.05) if a moody look is wanted, or raise the ambient for a brighter game.
  The *relationship* is the style, not the absolute colours.

## 6. Scale and detail

**Observed**
- Texel density: 64 px per world cell (2× world). Sizes: characters 128×128 drawn at
  30–58 world px diameter; items 64×64 at 26–30 world px; UI icons 48×48; furniture
  64 px × cell footprint (64×64 up to 384×256); seamless floor tiles 512×512 (= 8×8
  cells); wall-cap tile 128×128; lights 256–2048 px gradients.
- Characters are ~1 cell across (smaller than most furniture); a full figure (head,
  shoulders, arms) fits inside a base disc with a ~6 % rim. Silhouette fills ~70 % of
  the token canvas; props fill 20–40 % of theirs (generous transparent margin).
- Interior detail per asset is low: one silhouette, 3–8 interior strokes, one material
  pattern, one highlight.

**Recommended**
- Fix one texel density for all world art and never mix densities in one scene.
- Characters ≈ 1 grid cell; small props ≈ 0.8 cell; leave ≥ 15 % transparent margin
  around props for the drop shadow and rotation.
- Judge detail at final display size: if an interior stroke is under ~1 screen px,
  remove it.

## 7. Lighting

**Observed**
- Godot 2D lighting on the Compatibility renderer: `CanvasModulate` for ambient,
  `PointLight2D` (additive) for every source, `LightOccluder2D` on wall cells.
- Light textures are pre-baked radial gradients with a **near-Gaussian falloff**
  (σ ≈ 0.35 of the radius, zero by 0.9 R): `lights/soft.png` 512², `candle.png` 256²,
  a 2048×512 cone for directional beams (apex at the texture centre).
- Shadows: `SHADOW_FILTER_PCF5`, smooth 1.5–2.0, shadow colour black at 0.75–0.85
  alpha. Room fills 0.55–0.75 energy at texture scale 0.8–3.2; small sources 0.85–1.1
  energy at 0.55–0.9 scale; a weak non-shadowing fill (0.18) keeps dark rooms legible.
- Living sources flicker by summed sines (`sin(t·9)` + `sin(t·23)`, i.e. ≈ 1.4 Hz and 3.7 Hz,
  ±5–30 % depending on the source), not random noise.
- Some content is lit or unlit on purpose: UI, text and warning markers use an
  **unshaded** material; secret layers use a **light-only** material, visible only
  inside a specific light (`light_mask` / `range_item_cull_mask`).
- Assets contain **no baked light pools**: only their own form shading.

**Recommended**
- Paint assets as if under even, neutral light (form shading only); let the engine add
  every pool of light. That keeps assets reusable in any lighting state.
- Use soft radial Gaussian light textures, shadowed, with a near-black ambient
  multiply; animate intensity with smooth periodic functions.
- Keep gameplay-critical markers unshaded so darkness never hides them.

## 8. Animation

**Observed**
- **No frame-by-frame sprite animation** anywhere (`AnimatedSprite2D`/`SpriteFrames`
  unused). Motion is rigid-body: tokens slide and rotate (facing eases at 14/s), doors
  swing via tweens (0.25 s, quadratic), objects shake/rotate/scale briefly.
- Effects are procedural or shader-based:
  - flames as 3 layered polygon tongues swaying on sine sums,
  - expanding rings for impacts and signals (≈ 0.9 s),
  - a screen-space **distortion shader** for unnatural beings,
  - alpha fades and squash/stretch (scale 1.4×0.75) for fast movement,
  - camera shake for impacts.
- State changes are swaps of whole illustrations (a different token or texture), with
  a flash (bright modulate) and a short scale pop.

**Inferred**
- Motion reads like moving physical game pieces on a board: whole-object transforms,
  not character animation. Effects are the only "living" drawings.

**Recommended**
- Animate by transform (position, rotation, scale), alpha and colour modulate, not by
  frame sequences. Use short eased tweens (0.2–0.4 s).
- Draw effects in the same palette logic: warm additive for energy and fire, cool
  multiply for dread, a distortion shader for "wrongness". Keep effects soft-edged and
  semi-transparent so they sit over the inked art without competing with its lines.

## 9. UI rendering

**Observed**
- Panels are **9-slice textures** (`StyleBoxTexture`, 24 px margins) whose centres
  **tile** rather than stretch (`AXIS_STRETCH_MODE_TILE_FIT`), so paper grain stays
  crisp at any size (`Art.stylebox`).
- Paper-like panel fill with ink-dark text; dark inset panels with light text for HUD.
  Buttons are illustrated plates (normal / hover / pressed textures).
- Typography: a pair of old-style serif faces (a small-caps display face for
  headings, a regular and an italic text face; `assets/fonts/`). Text drawn over the
  world always has a dark outline 3–12 px (scaled with UI scale).
- HUD widgets (gauges, discs, bars) are drawn with `_draw()`: a dark fill, a
  thin metallic-coloured ring, an inner highlight; states change ring colour, not shape.
- Icons: ink line art with a light halo, flat colour, minimal shading (shade 0.3 vs 0.45
  on world props).
- Two independent scales: menu UI scale and gameplay HUD scale.

**Recommended** (setting-independent)
- Build every panel from one textured 9-slice with a tiled centre; one border texture
  per panel family.
- Pair a characterful display face (headings, small caps or a stylised weight) with a
  highly legible text face of the same family; keep body text ≥ 15 px at 1080p.
- Outline all world-space text; use the scene's darkest neutral as outline colour.
- Icons follow the world line style but with less shading and a light halo so they
  read on both light and dark panels.

## 10. Asset production

**Observed**
- Format: PNG, 8-bit RGBA; opaque (RGB) only for full-bleed backgrounds and floor
  tiles. Fully transparent pixels have RGB cleared to 0 (no colour bleeding).
- Seamless tiles are generated with wrap-around padding so all four edges match.
- Folder-per-kind with lowercase snake_case names: `tokens/`, `items/`, `icons/`
  (`ev_*`, `eq_*`, `ui_*` prefixes), `furniture/`, `floors/`, `decor/`, `ui/`, `lights/`,
  `menu/`. A manifest lists every expected file and size (`docs/ASSET_MANIFEST.md`),
  checked by `python3 tools/art/generate_art.py --check`.
- Pivot: centred sprites; characters face +X; furniture authored unrotated, rotated in
  90° steps in-engine; floors placed as UV-repeated polygons (texture repeat on).
- Godot: `default_texture_filter = 1` (linear), no pixel snapping
  (`snap_2d_transforms_to_pixel = false`), stretch mode `canvas_items` / `expand`,
  Compatibility renderer, clear colour near-black (0.03, 0.03, 0.04).
- Creator overrides: hand-made files of the same name and size can replace any
  generated asset without code changes.

**Recommended**
- Deliver straight (not premultiplied) RGBA PNGs at exact manifest sizes; downsample
  from a 2–4× working canvas with a high-quality filter (Lanczos) and clear transparent
  RGB.
- Linear filtering, no mipmaps for world sprites unless zooming far out; no pixel
  snapping (the style is smooth, not pixel art).

### Implementation notes (production choices, not style)

- The originals are drawn at 2× or 4× (`Canvas(..., ss=2|4)`), then Lanczos-downsampled
  with premultiplied alpha: that's how code-drawn lines become smooth. A painter
  achieves the same by working large.
- Noise is seeded from asset names so regeneration is deterministic.
- Masks, edge bands and hatching are numpy array operations; any paint program's
  layers (multiply, screen, clipping masks) reproduce them.

---

## Reusable style specification (setting-independent)

1. **View**: strict top-down orthographic; objects show their top silhouette only;
   characters are round tokens facing right; no perspective.
2. **Line**: one closed, slightly wobbly near-black outline per object (2–4 % of its
   width), thinner interior detail strokes, smooth curves, no perfectly ruler-straight
   edges.
3. **Fill**: flat or gently graded (45°) mid-dark muted colour; one hue family per
   object plus neutrals; one small saturated accent at most.
4. **Shading**: fixed upper-left light; a soft shadow band along lower-right edges,
   cool-tinted, with 45° hatching inside it and cross-hatching in the deepest part; a
   thin warm rim highlight upper-left; soft drop shadow offset down-right.
5. **Texture**: material pattern (banding / mottling / weave / gloss) at low contrast,
   then a uniform 5–7 % grain over everything.
6. **Lighting**: assets carry no light pools; the scene is a dark cool ambient multiply
   lit by warm, soft, shadow-casting Gaussian light pools; key markers unshaded.
7. **Motion**: whole-object transforms and short eased tweens; procedural soft-edged
   effects; no frame animation.
8. **UI**: tiled-texture 9-slice panels, ink-on-paper and light-on-dark variants,
   old-style or characterful serif pairing, outlined world text, halo'd line icons.

## Image-generation prompt (reusable)

> top-down orthographic game asset, viewed from directly above, isolated on
> transparent background, hand-inked illustration with slightly wobbly near-black
> outlines, flat muted ink-wash colours, single light from the upper left, soft cool
> shadow band along the lower-right edges with fine 45-degree cross-hatching inside the
> shadow, thin warm rim highlight on the upper-left edge, subtle paper grain, soft drop
> shadow offset down-right, low-contrast material texture, mid-dark values, one
> dominant hue family with one small saturated accent, crisp anti-aliased edges,
> board-game miniature readability, clean silhouette, no perspective, no side faces

## Negative prompt

> isometric, perspective, three-quarter view, side view, front view, vanishing point,
> pixel art, low-res pixels, dithering, voxel, 3D render, photorealistic, photo, PBR,
> glossy CGI, cel-shaded anime, thick cartoon outlines, comic halftone, vector flat
> design with no texture, gradient mesh, neon glow, lens flare, bloom, baked light
> pools, harsh rim lights on all sides, pure black outlines, oversaturated colours,
> rainbow palette, high-contrast noise texture, painterly impasto brush strokes,
> watercolour bleed, text, watermark, frame, background scenery, cast shadow toward
> the upper left

## Godot asset / rendering checklist

- [ ] Renderer: Compatibility (or Forward+ with 2D lights; the style uses only 2D).
- [ ] `rendering/textures/canvas_textures/default_texture_filter = Linear`;
      `2d/snap/snap_2d_transforms_to_pixel = false`.
- [ ] Window stretch `canvas_items`, aspect `expand`; design canvas 1600×900 (or
      similar 16:9); near-black clear colour.
- [ ] One world grid; art authored at 2× world density; camera zoom so that one texel
      ≈ 0.75–1.0 screen px.
- [ ] Layers (z-order): floor tiles → weathering overlays → rugs/flat decor → decals →
      furniture/props → characters → effects/overlays → unshaded markers/text.
- [ ] `CanvasModulate` ambient: dark, colour-temperature opposite to the main lights.
      Compose mood changes into one colour (one active tween at a time).
- [ ] Every light: `PointLight2D` + soft radial Gaussian texture, `shadow_enabled`,
      `SHADOW_FILTER_PCF5`, smooth 1.5–2, shadow colour black ~0.8 alpha; walls get
      `LightOccluder2D`; disable lights that are fully off.
- [ ] Flicker via summed sines; no random per-frame noise.
- [ ] Characters: `Sprite2D` of a +X-facing token, child shadow sprite (black, 50 %,
      offset +3/+4, scale 1.04), rotate the node for facing.
- [ ] Props: centred pivot, drop shadow baked into the PNG, ≥ 15 % transparent margin.
- [ ] Floors: seamless 512² tiles on UV-repeated polygons (`texture_repeat` enabled),
      optional calm shader (pull detail ~35 % toward the material average).
- [ ] UI: `StyleBoxTexture` 9-slice, 24 px margins, tiled centre; outlined labels
      (`outline_size` scaled with UI scale); unshaded `CanvasItemMaterial` for overlays.
- [ ] Effects: tweens and `_draw()` / shader effects, not sprite sheets; a reusable
      distortion shader for "unnatural" elements.
- [ ] Asset QA: PNG RGBA at manifest sizes, transparent RGB cleared, lowercase
      snake_case names, one folder per kind; a size/manifest check script.

## Example asset prompts in unrelated settings

These reuse the style prompt above; only the subject changes. No historical,
supernatural or Gothic content.

**Modern — a café espresso machine**
> top-down orthographic game asset of a compact café espresso machine on a counter
> segment, seen from directly above: rounded steel body, two portafilter handles,
> drip tray, a small dial with one bright red accent; hand-inked slightly wobbly dark
> outline, flat muted ink-wash colours (cool greys, desaturated teal enamel), upper-left
> light, cool shadow band with fine 45-degree hatching on the lower-right edges, a single
> sharp gloss streak on the steel, subtle paper grain, soft drop shadow down-right,
> transparent background, 128×128 px

**Fantasy — a druid's mushroom-cap stool and herb basket**
> top-down orthographic game asset of a giant mushroom-cap stool beside a woven herb
> basket, viewed from directly above: speckled cap with soft mottled texture, basket
> with a fine weave pattern and a few leaf sprigs, one small saturated violet blossom
> as accent; hand-inked slightly wobbly near-black outlines, muted earthy ink-wash
> colours, upper-left light, cool shadow band with 45-degree hatching along the
> lower-right edges, warm thin rim highlight upper-left, subtle grain, soft drop shadow
> down-right, transparent background, 128×128 px

**Science fiction — a maintenance drone (character token)**
> top-down orthographic character token of a small hovering maintenance drone, seen
> from directly above, facing right: circular chassis on a dark round base disc, two
> stubby manipulator arms, a sensor dome with one small saturated cyan accent light;
> hand-inked slightly wobbly dark outline, flat muted metal and composite colours with
> a 45-degree gradient for volume, upper-left light, cool shadow band with fine
> cross-hatching on the lower-right, single sharp specular glint on the dome, subtle
> grain, soft drop shadow down-right, transparent background, 128×128 px

## Sources in this repository

- Drawing primitives: `tools/art/core.py` (`Canvas.part`, `ink`, `hatch`, `grain`,
  `drop_shadow`, `wood_tex`, `noise_tex`, `fabric_tex`, `gradient`).
- Style parameters: `tools/art/objects.py` (`Style`), `tools/art/items_icons.py`
  (`ITEM_ST`, `ICON_ST`, `halo`), `tools/art/floors.py`, `tools/art/tokens.py`.
- Rendering: `project.godot` (`[rendering]`, `[display]`), `scripts/world/house_view.gd`
  (layers, darkness, lights, floor calm shader, weathering),
  `scripts/world/lighting.gd`, `scripts/game/token_sprite.gd`,
  `scripts/world/world_fx.gd` (rings, distortion), `scripts/autoload/art.gd` (fonts,
  9-slice panels).
- Asset list and sizes: `docs/ASSET_MANIFEST.md`.
