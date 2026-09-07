# Generating the arena's textures

Everything on screen is an untextured primitive with a flat `albedo_color`. This file is how
that stops being true for the WORLD - the ground, the lava, the rocks and the trees. The
wizards are a separate decision and are deliberately not here yet: they are capsules, and what
a capsule should become depends on what the world around it looks like first.

**The target look is Warcraft III's**, and the reason is not nostalgia. That game is simple
geometry wearing hand-painted textures, which is exactly the shape this project is already in:
cylinders, spheres and capsules, lit by one warm directional light over a purple ambient.
Nothing here asks for a new mesh.

## The two rules every prompt below is built around

**1. It has to TILE, because the ground shrinks.** The platform starts at 11m of radius and
closes to 4.5m during a round. A painted island would be squashed as it closes; a seamless
tile stays the same size on the grass no matter what the ring does. Every texture here is
seamless, and none of them is a picture of a place.

**2. It has to carry no light direction.** There is a real `DirectionalLight3D` in the scene
casting real shadows, at a warm white (255, 245, 229) over a purple-lavender ambient
(92, 87, 141). A texture with a sun baked into it fights that: every rock lit from the top
left while its shadow falls to the bottom right. Baked *contact* darkness down in the crevices
is fine and is what makes hand-painted art read - a baked *sun* is not.

## What the generator has to be told about this game

Measured, not guessed. If any of it changes, change it here too.

| | |
|---|---|
| Camera | fixed three-quarter, **55° below the horizon**, 45° vertical FOV, ~34.5m out, never rotates |
| Design resolution | 1280 x 720, landscape |
| Wizard | 2m tall, about a twelfth of the screen's height |
| Platform | disc, **11m radius at the start, closing to 4.5m**, 2m thick |
| Ground colour now | RGB **(55, 104, 43)** - a mid, saturated green |
| Lava field | flat disc, **60m across**, covering everything the camera can see past the ring |
| Lava colour now | base **(120, 35, 10)**, emissive **(255, 101, 24)** at low energy |
| Rock | 7-sided cylinder, 1.8m tall, 0.8m at the base tapering to 0.45m, **(90, 81, 113)** |
| Tree trunk | 8-sided cylinder, 2.6m tall, 0.34m tapering to 0.24m, **(90, 62, 47)** |
| Tree canopy | sphere, 1.05m radius, **(22, 61, 42)** |

**There is no black anywhere on screen and there must not be.** A void reads as "off the map";
lava reads as "somewhere you can be, briefly", and being knocked into it is survivable and
meant to feel that way. The darkest thing in any of these textures is a deep warm brown or a
deep cool grey, never a black.

**The platform's SIDE does not need art.** It is a 2m cliff seen from 55° above and the rim
and shore rings cover almost all of it. One texture on the whole cylinder is fine.

## Order to generate them in

1. **Ground** and **lava**. Between them they are every pixel of the screen; the other three
   are small objects standing on top.
2. **Rock**, then **bark**, then **canopy**. Four obstacles at a couple of metres each.

---

## 1. Ground

```text
Create a seamless, tileable texture of stylised grassy ground for a video game.

STYLE: hand-painted fantasy game art, in the tradition of early-2000s stylised RTS
textures. Painterly brushwork, chunky readable clumps, saturated colour. Not
photorealistic, not a photograph, no fine grain or noise.

COLOUR: a mid saturated green centred on RGB (55, 104, 43). Vary it with warmer
yellow-greens and cooler blue-greens around that centre. Keep some patches of bare
warm earth showing through, in a brown around RGB (92, 68, 46). Nothing in the image
may be black or near-black; the darkest tone is that brown.

SCALE: the square represents about 4 metres of real ground. Paint clumps and tufts at
roughly the size of a boot, not individual blades of grass.

LIGHTING: FLAT and directionless. Do NOT paint a sun, a light direction, cast shadows,
highlights on one side, or any gradient across the image. Soft darkening down inside
the gaps between clumps is wanted; a light coming from anywhere is not.

SEAMLESS: the texture must tile perfectly. The left edge continues into the right edge
and the top edge into the bottom edge, with no visible seam, no border, no frame, no
vignette, and no darkening at the edges of the image.

OUTPUT: a single square image, 1024 x 1024, filling the entire frame flat-on, as if
scanned. Do not present it on a card, at an angle, on a surface, with a drop shadow,
with a label, or as a swatch next to anything. No text, no watermark, no logo.
```

## 2. Lava

```text
Create a seamless, tileable texture of stylised molten lava for a video game.

STYLE: hand-painted fantasy game art, in the tradition of early-2000s stylised RTS
textures. Painterly, chunky, readable. Not photorealistic, no fine grain.

WHAT IT IS: a lake of slow, thick lava seen from above. A dark cooled crust broken into
irregular plates, with molten orange running in the cracks between them.

COLOUR: the crust is a deep warm brown-red around RGB (120, 35, 10). The cracks glow in
orange around RGB (255, 101, 24), reaching a pale yellow-white only in the very
thinnest, brightest lines. Nothing in the image may be black or near-black - the crust
is the darkest tone and it is a brown, not a shadow.

IMPORTANT - THIS IS A BACKGROUND. It covers the entire screen around the play area and
must never compete with what is standing on the ground in front of it. Keep it MOSTLY
dark crust with a modest amount of glow. Roughly one part molten to four parts crust.
Do not fill the image with bright lava.

SCALE: the square represents about 8 metres. Crust plates about the size of a small
table, cracks a hand's width.

LIGHTING: FLAT and directionless. The only light in the picture is the lava's own glow
coming out of the cracks. No sun, no cast shadows, no gradient across the image.

SEAMLESS: the texture must tile perfectly, left edge into right and top into bottom,
with no visible seam, no border, no frame, no vignette, no darkening at the edges.

OUTPUT: a single square image, 1024 x 1024, filling the entire frame flat-on. Do not
present it on a card, at an angle, with a drop shadow, or as a swatch. No text, no
watermark.
```

## 3. Rock

```text
Create a seamless, tileable texture of stylised rock for a video game.

STYLE: hand-painted fantasy game art, in the tradition of early-2000s stylised RTS
textures. Broad painterly facets, chunky readable chips and cracks, no fine grain and
no photographic detail.

COLOUR: a cool purple-grey stone centred on RGB (90, 81, 113). Vary it with lighter
lilac-greys and a few warmer sandy patches. Nothing may be black or near-black; the
deepest crack tone is a dark slate grey.

SCALE: the square represents about 2 metres of rock face - this wraps a boulder roughly
as tall as a person. Facets about the size of two hands.

LIGHTING: FLAT and directionless. Do NOT paint a sun, a light direction, a highlight on
one side, cast shadows, or any gradient across the image. Darkening inside the cracks
is wanted; a light coming from anywhere is not.

SEAMLESS: it must tile perfectly left-to-right and top-to-bottom, with no visible seam,
no border, no frame, no vignette and no darkening at the edges.

OUTPUT: a single square image, 1024 x 1024, filling the entire frame flat-on. No card,
no angle, no drop shadow, no swatch, no text, no watermark.
```

## 4. Tree bark

```text
Create a seamless, tileable texture of stylised tree bark for a video game.

STYLE: hand-painted fantasy game art, in the tradition of early-2000s stylised RTS
textures. Bold vertical ridges, chunky and readable, painterly. No fine grain, no
photographic detail.

COLOUR: a warm mid brown centred on RGB (90, 62, 47), with lighter tan ridges and
cooler grey-brown in the grooves. Nothing may be black or near-black.

DIRECTION: the ridges run VERTICALLY, top to bottom of the image, because this wraps
around a standing tree trunk.

SCALE: the square represents about 1 metre of trunk. Ridges roughly a finger wide.

LIGHTING: FLAT and directionless. No sun, no light direction, no highlight on one side,
no cast shadows, no gradient across the image. Darkening down inside the grooves is
wanted.

SEAMLESS: it must tile perfectly left-to-right and top-to-bottom, with no visible seam,
no border, no frame, no vignette, no darkening at the edges.

OUTPUT: a single square image, 1024 x 1024, filling the entire frame flat-on. No card,
no angle, no drop shadow, no swatch, no text, no watermark.
```

## 5. Tree canopy

```text
Create a seamless, tileable texture of stylised tree foliage for a video game.

STYLE: hand-painted fantasy game art, in the tradition of early-2000s stylised RTS
textures. Leaves painted in CLUMPS and masses rather than individually, chunky
silhouettes, broad brushwork. No fine grain, no photographic detail.

COLOUR: a deep green centred on RGB (22, 61, 42), varied with brighter yellow-greens on
the outer clumps and cooler blue-greens deeper in. Nothing may be black or near-black;
the deepest shade between clumps is a dark blue-green.

SCALE: the square represents about 2 metres of canopy. Leaf clumps roughly a hand's
width.

LIGHTING: FLAT and directionless. No sun, no light direction, no cast shadows, no
gradient across the image. Soft darkening in the gaps between clumps is wanted, since
that is what gives the mass its depth.

FULLY OPAQUE: this wraps a solid ball, not a cut-out. Fill the entire square with
foliage. No transparent areas, no sky showing through, no gaps to the background.

SEAMLESS: it must tile perfectly left-to-right and top-to-bottom, with no visible seam,
no border, no frame, no vignette, no darkening at the edges.

OUTPUT: a single square image, 1024 x 1024, filling the entire frame flat-on. No card,
no angle, no drop shadow, no swatch, no text, no watermark.
```

---

## Checking one when it comes back

In this order, because the cheap checks fail most often:

1. **Is it a texture or a picture OF a texture?** Generators love returning a swatch on a
   surface, at an angle, with a shadow under it. If there is a corner, a card edge or a
   shadow anywhere, it is unusable - ask again rather than cropping.
2. **Does it tile?** Put four copies in a 2x2 grid and look at the two seams in the middle. A
   generator will say it is seamless and return something that is not. This is the check that
   matters most for the ground, because the ground is seen at every size.
3. **Is there a sun in it?** Look for a consistent bright side and a consistent dark side. If
   there is, it will fight the real light in the scene and every rock will be lit twice.
4. **Is anything black?** Sample the darkest pixel. Black reads as a hole in the world.
5. **Does it read at size?** The wizard is a twelfth of the screen tall. Scale the texture
   down to about 100px and see whether the shapes still say "grass" or turn into mush. Fine
   detail is worse than useless on a phone: it aliases and sparkles.

## Wiring one in

Drop the file in `assets/materials/` and set it as `albedo_texture` on the material that
already carries that flat colour. **Keep the flat `albedo_color` as white** once a texture is
on it, or the tint multiplies into the art and darkens it.

**One property is not optional, and it is the same trap the camera had.** The platform's UVs
run 0..1 across the cap whatever its radius, so a texture on it SCALES as the ring closes -
the grass would zoom in exactly as the ring shrank, which is the "everything changes size but
the wizard" problem all over again. Switch the ground material to **`uv1_triplanar = true`**
and set `uv1_scale` in world units. Triplanar maps from world position, so the grass stays
put on the ground while the disc closes over it.

The rocks and trees do not shrink, so they need no such thing - only a `uv1_scale` that makes
the texture the right size on the mesh.

## Checking one WITHOUT looking at it

    python tools/check_texture.py <image.png> --expect 55,104,43         --preview tile.png --seam-strip seam.png

Four of the five checks above are numbers, so they are done with numbers. It reports the
size, how much worse the wrap seam is than an ordinary neighbouring column, the brightness
spread across a 3x3 grid (a baked sun shows up here and nowhere else), the darkest tone, and
how far the mean colour is from the one the game uses now.

Two images come out of it and both are worth looking at:

- `--preview` tiles it 2x2, which is the classic seam check.
- `--seam-strip` butts the last hundred columns against the first hundred **at full
  resolution**, so the join is the vertical line down the middle. The 2x2 preview is
  downscaled and a one-pixel seam vanishes into it - which is exactly the seam that then
  shows up as a faint grid on the ground.

**The seam ratio's thresholds are advisory and they run hot on painted textures.** The first
pair this repo received measured 2.0 to 2.8 - "marginal" by the tool - and both are invisible
in the full-resolution strip, because an ordinary step between neighbouring columns in a
busy hand-painted texture is only 7 to 13 out of 765. Read the ratio, then look at the strip.

## Bringing one in

    python tools/fit_texture.py <in.png> assets/materials/<name>.png --size 1024

Generators return whatever size they like - 1254 square, the first time. `fit_texture.py`
area-averages it down to a power of two. **Area-average, not nearest**: sampling one pixel
out of each block is what makes hand-painted art sparkle at distance, and sparkle reads to a
player as "low resolution", which is the opposite of the point.

Then, and this bites every single time:

1. Run `Godot.exe --headless --path . --import`.
2. **Open the `.import` file and set `mipmaps/generate=true`.** It arrives `false`. On a
   ground plane seen at a 55 degree slant across the whole screen, no mipmaps means the grass
   crawls and shimmers whenever anything moves.
3. Set `compress/mode=2` (VRAM compressed) while you are in there. These are phone builds.
4. Re-import.

## What the first pair needed after it was in the scene

Both textures passed every check and still needed tuning, because a texture is only half of
how it looks - the other half is `uv1_scale`, and no measurement of the file can tell you
that.

- **The lava tiled every 8 metres and the repeat was obvious** across a 120-metre field. It
  is 22 metres now (`uv1_scale` 0.045) and reads as a surface rather than as wallpaper.
- **The lava was brighter than the ring.** Its material is `shading_mode = 0`, unshaded, so
  the painted brightness goes straight to the screen with no light to dim it - while the
  grass beside it is lit and therefore darker than its own file. `albedo_color` multiplies
  down to (0.62, 0.56, 0.56) to put the ring back in charge of the screen.
- **The spell buttons stopped being readable.** They are translucent discs, which was fine
  over a flat orange background and stopped being fine the moment the background had a
  pattern in it. They have a dark plate under them now - `AbilityButton.backdrop`. Worth
  knowing before the next texture lands: **anything drawn over the world gets harder to read
  every time the world gets more detailed.**

## Where the file lands

ChatGPT downloads arrive in `Downloads` named as a GUID, and often with an **uppercase
`.PNG`** that a `*.png` glob misses. Codex writes its own into
`~/.codex/generated_images/<session>/exec-<guid>.png` instead. Rename on the way in.
