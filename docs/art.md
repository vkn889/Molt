# Creature artwork

Molt is drawn in code, not from an image. `CreatureView` paints a 14 by 11 pixel grid (plus two rows of headroom for hops) with SwiftUI `Canvas`: a wide body with softened corners, two dot eyes, stubby arms, four legs and a leaf sprout. The palette setting changes the body color (green by default, or blue, amber or violet).

Poses are small edits to the same grid:

- **Idle:** occasional blink; the sprout sways.
- **Walk:** the body bobs one pixel and alternate pairs of legs lift.
- **Sleep:** eyes close to lines, the body settles, and a "z" drifts up.
- **Eat:** a mouth opens and closes.
- **Happy:** arms wave and Molt hops.

On Home, Molt walks along the bottom of the panel. How far and how fast it goes depends on its care level and how often you have played with it in the last few hours. It sleeps during its sleep hours or when its energy is low. Animation stops with Reduce Motion.
