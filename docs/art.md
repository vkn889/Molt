# Creature artwork

The user selected pixel art instead of the roadmap’s proposed low-poly direction. Molt uses one original 4-by-4 transparent sprite atlas, cropped into cached frames by the native renderer. There is no runtime image generation or art download. Oxanium is bundled locally under the SIL Open Font License, included alongside the font.

Asset: `Sources/Molt/Resources/Art/molt-atlas.png`.

Creation mode: built-in image generation. Production prompt:

> Create one transparent PNG sheet with exactly four columns and four rows of equal square cells. Each cell contains the same original small sage-green soft-bodied creature, tiny feet, large dark expressive eyes, flexible leaf-like ear fins, short curled tail, cream belly and a chunky readable silhouette. Use crisp pixel art, hard edges and a restrained palette. No text or grid lines. Consistent scale, centered poses and transparent margins. Row one: neutral front, blink, looking left, sitting. Row two: walking left, walking right, stretching, yawning. Row three: sleeping, waking, eating a berry, drinking from a cup. Row four: playing, thinking, celebrating, sweating. Keep anatomy consistent and full bodies unclipped.

The runtime renderer uses discrete poses, gentle breathing and short transitions. It pauses when the associated window is hidden or occluded, respects Reduce Motion, and reduces motion when thermal pressure is elevated. Current cosmetics use supported overlay anchors. This is a sprite renderer, not a real-time 3D engine.
