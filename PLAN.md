# Warband - plan

Martin (2026-11-25): top-down Patapon-style army controlling, like Pikmin, but
the narrative structure and map design more Dark Souls. A small group, 4 to
10. Units to start: sword and shield, two-handed weapon, bow and arrow,
sorcerer. Simple attacks; you control them individually - you jump your soul
into one and direct the group, with a more enhanced moveset. Every unit: a
basic attack and a dodge, and a block if it has a shield. Pixel art like Pack
Hero in scope, generated from computed shapes. Completely top down for now.
Arrows arc in the sky.

Martin, later the same day: Patapon = just the armies, not the rhythm; getting
near large bosses or armies and fighting. Enemies: small groups in rooms,
larger bosses, sometimes both. Most of the time you move a CIRCLE; the
characters auto attack enemies nearby within range. A RELEASE option lets
them fan out; you can choose an enemy for all to FOCUS, or spread out. Moving,
they follow your controlled character or stay within the circle you control,
which you can ROTATE and change FORMATIONS. "Do your best... make assumptions
and I'll assess later".

## First pass (built)
- 480x270 base resolution, scaled up whole; everything drawn from computed
  shapes at that resolution (no sprite rotation, every pixel on the grid).
- Party of 8, enemies: hollows and a knight. Placeholder map: bonfire room,
  passage, courtyard, passage, knight's hall.
- Arrows fly up and land where aimed (the shadow runs along the ground); they
  hit whoever is there when they land. Sorcerer bolts fly straight.

## Second pass (built): the circle
- You are the circle by default (WASD). Formations ring/line/wedge/column
  (1-4), Q/E turn it. Melee in front/outside, ranged behind/inside.
- In formation: melee step out up to 20 px from their place to hit an enemy;
  ranged shoot anything within range from where they stand.
- F release: they go after enemies within 170 px, spreading over them (a
  taken enemy counts as 50 px further). F again: back to places.
- Focus: LMB on an enemy as the circle (or G any time): all on it till it dies.
- Tab: soul into a unit (formation forms round it, same rotation); X: back out.
  If that body dies you're back to the circle.
- Map: bonfire, room of 3 hollows, room of hollows + 2 hollow archers, the
  giant's arena with 2 hollows.
- The giant: sweep (wide arc in front), stomp (all round), slam (a long strip
  ahead); picks from those that suit the distance; never staggers. Its wind-up
  darkens the ground it's about to hit (MY CALL - a readability aid).
- Martin said "maybe this happens when you take control of an enemy" about
  release: not done (read as possibly a typo); possessing enemies not built.

## Phone controls (built)
- Martin: a manual rotation control on the right, a thumbstick on the left;
  keep WASD for computer; formation options on the sides later (he'll decide).
- Stick bottom left, dial bottom right (drag the notch round, 1:1 with the
  formation). Always shown for now; the mouse works them (touch emulation).
- Side panels (Martin: "a UI section to the left and right of the play
  screen"): the screen is 608x270 - the 480x270 play area between two 64 px
  panels (phone-sideways shaped). Left: the party's health, the stick.
  Right: formation buttons (2x2), release button, the dial. Layout MY CALL.

## Controller + dodge (built)
- Martin: controller support; a dodge button; dodge doesn't cancel attacks,
  it goes when the attack is over.
- Dodge asked for mid-attack waits (and stops the chain); standing, it's
  remembered 0.3 s (e.g. while the last dodge cools down).
- MY CALLS: as the circle, dodge = the whole party dodges (the way you push,
  or backwards from the formation's facing). Button mapping: see README. With
  a controller the pointer sits out from the circle where the right stick
  last pushed it; X picks the enemy within 40 px of it.

## Phone build (v0.1)
- Copied from Pack-hero: Android preset (com.martinhourigan.warband, landscape
  sensor, immersive), build_apk.bat, tools/release.py, update button on a new
  MAIN MENU (scripts/update.gd checks GitHub releases), phone back = menu/quit,
  GL Compatibility renderer, icon.
- Phone controls added: left panel figures = soul in/out, play-area taps
  (focus / attack toward / rest at the bonfire), BLOCK hold button.
- Optimisation: the map is painted into one texture once; the party/enemy
  lists and formation places worked out once a frame; enemies far off at
  home sleep; units off screen aren't redrawn.

## Keeping to the circle (after v0.1)
- Martin: units must try their best to stay in the circle when not
  released; ranged got stuck in a hallway till released.
- Bug: held ranged with an enemy in range but no shot (wall, or at the edge
  of range) did nothing - didn't shoot, didn't go back. Now in formation the
  place comes first: ranged shoot only within HOLD_NEAR (8 px) of their place
  and with a shot, else walk back; melee step out at most STEP_OUT (20 px)
  and return. Targets are picked from their place, not from where they stand.
- Paths: a straight walk only if a body-wide line is clear (no catching on
  corners); otherwise the tile path.

## Base formation (Martin)
- "the base formation have the 4 melee characters at the front in an arc like
  1 side of a octagon, and then the ranged ones in the middle like a square".
  Built as "base" (replaces ring): melee on the octagon's four front corners
  (22.5/67.5 degrees either side of the front, at 0.75 of the circle), ranged
  2x2, 12 px apart, in the middle. Extra melee go on round the octagon.

## Focus = priority target (Martin)
- "it just makes them the priority target within range. It doesn't make them
  all rush that target." In formation: a unit that can reach the focus from
  its place (ranged range, melee reach + step out) takes it over anything
  else. Released: the focus beats any other enemy within their sight (170).

## MY CALLS (all placeholders, numbers in scripts/data.gd)
- Party: 2 of each unit = 8.
- Enhanced moveset of the possessed one: 15% faster, and a chain of three
  attacks (the third x1.6). Everyone else: single attacks.
- Keys: see README.
- Party AI: shields come up against a wind-up aimed at them, others dodge half the time.
- Bonfire: rest = all revived and healed, enemies reset. All dead = YOU DIED,
  back at the bonfire.
- No stamina yet.

## Open
- Patapon: answered - armies, no rhythm.
- What should the enhanced moveset really be (per unit)?
- Isometric later? Unit size on screen (10 px across now).
- Dark Souls structure: shortcuts, souls/levelling, recruiting more units.
