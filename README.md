# Warband (working title)

Top down. A party of 8 (sword and shield x2, two-handed x2, bow x2, sorcerer x2).
Most of the time you move a circle; the party keeps its places in it and attacks
whatever comes in range. Your soul can go into any of them.
Enemies: small groups in rooms, a large boss (the giant), and both together.

Run: `play.bat`. Phone: install the APK from the GitHub releases; after that the
main menu's update button fetches new versions. Tests: `godot --headless --path . --script res://tests/spot.gd`.

| Key | |
|---|---|
| WASD | move the circle (or the one your soul is in) |
| Q / E | turn the formation |
| left panel | the party's health; under it the thumbstick: moves the circle (or the one your soul is in) - for phones; the mouse drags it too |
| right panel | formation buttons, the release button, the dodge button; under them the dial - drag its notch round to turn the formation |
| 1-4 | formation: base (four melee on the front corners of an octagon, ranged in a square in the middle), line, wedge, column |
| F | release them (they spread out over the enemies) / back into the circle |
| LMB on an enemy (as the circle), or G | focus: all of them go for it; on nothing: no focus |
| Tab | your soul into the one nearest the pointer |
| X | out of it, back to the circle |
| Space (or the dodge button) | dodge: in a body, that one; as the circle, the whole party (the way you push, or back). Pressed mid-attack, it goes when the attack's over |
| In a body: LMB / RMB | attack (press again in time: a chain of three) / block (shields) |
| R | rest at the bonfire: everyone up and healed, enemies back |

Controller: left stick move; right stick aim (in a body) or move the pointer
(as the circle); A dodge; X attack (in a body) / focus what the pointer's on
(as the circle); Y soul into the one nearest the pointer; B back out; LB block;
RB release; triggers turn the formation; d-pad formations; Start rest.

Dev: `--at x,y` (the circle at that tile), `--soul <n>`, `--release`, `--formation <name>`.

Phone: the left panel's figures are tapped to put your soul in one (again: back
out); taps on the play area focus an enemy (as the circle) or attack toward the
tap (in a body); tap the bonfire near it to rest; hold BLOCK; back = menu.

Build: `build_apk.bat` (add `install` with a phone plugged in). Release:
`python tools/release.py 0.2 "what changed"` (version bump, APK, commit, push,
GitHub release). Icon: `python tools/make_icon.py`.
