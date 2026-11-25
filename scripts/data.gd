extends RefCounted
## Numbers. ALL placeholders. Distances in pixels at the base resolution
## (480x270; a person is about 10 px across), times in seconds.
## attack kind: melee (hits what's in reach and arc as it lands), arrow (arcs
## through the air, lands where it was aimed), bolt (flies straight).

const UNITS := {
	"sword": {"name": "Sword and shield", "hp": 60.0, "speed": 52.0, "radius": 5.0, "poise": 14.0, "shield": true,
		"cloth": Color(0.28, 0.42, 0.68), "head": Color(0.7, 0.72, 0.76),
		"attack": {"kind": "melee", "reach": 15.0, "arc": 110.0, "windup": 0.22, "active": 0.1, "recover": 0.3, "damage": 12.0,
			"rest": 0.5, "back": 1.8, "end": -1.1}},
	"great": {"name": "Two-handed", "hp": 70.0, "speed": 46.0, "radius": 5.0, "poise": 20.0,
		"cloth": Color(0.72, 0.42, 0.2), "head": Color(0.62, 0.62, 0.66),
		"attack": {"kind": "melee", "reach": 21.0, "arc": 170.0, "windup": 0.5, "active": 0.12, "recover": 0.5, "damage": 26.0,
			"rest": 0.5, "back": 2.4, "end": -1.7}},
	"bow": {"name": "Bow", "hp": 40.0, "speed": 54.0, "radius": 5.0, "poise": 8.0,
		"cloth": Color(0.3, 0.55, 0.28), "head": Color(0.22, 0.36, 0.2),
		"attack": {"kind": "arrow", "range": 150.0, "windup": 0.45, "active": 0.05, "recover": 0.35, "damage": 10.0}},
	"sorcerer": {"name": "Sorcerer", "hp": 35.0, "speed": 50.0, "radius": 5.0, "poise": 8.0,
		"cloth": Color(0.45, 0.3, 0.62), "head": Color(0.3, 0.2, 0.42),
		"attack": {"kind": "bolt", "range": 130.0, "windup": 0.5, "active": 0.05, "recover": 0.4, "damage": 16.0, "speed": 170.0}},
}

const ENEMIES := {
	"hollow": {"name": "Hollow", "hp": 36.0, "speed": 40.0, "radius": 5.0, "poise": 6.0, "aggro": 90.0, "cool": [0.6, 1.3],
		"cloth": Color(0.42, 0.34, 0.24), "head": Color(0.55, 0.56, 0.44),
		"attack": {"kind": "melee", "reach": 13.0, "arc": 90.0, "windup": 0.45, "active": 0.1, "recover": 0.5, "damage": 10.0,
			"rest": 0.6, "back": 1.9, "end": -1.0, "blade": 5.0}},
	"hollow_bow": {"name": "Hollow archer", "hp": 26.0, "speed": 40.0, "radius": 5.0, "poise": 6.0, "aggro": 130.0, "cool": [0.8, 1.6],
		"cloth": Color(0.36, 0.3, 0.22), "head": Color(0.5, 0.5, 0.4),
		"attack": {"kind": "arrow", "range": 140.0, "windup": 0.7, "active": 0.05, "recover": 0.5, "damage": 8.0}},
	# A large boss. Several attacks; use: the gap to its target (px) it picks each from.
	# shape: arc (reach, arc), ring (all round, reach), line (reach long, width wide).
	"giant": {"name": "Giant", "hp": 600.0, "speed": 22.0, "radius": 16.0, "poise": 99999.0, "aggro": 150.0, "cool": [0.9, 1.7],
		"cloth": Color(0.4, 0.34, 0.3), "head": Color(0.52, 0.46, 0.4),
		"attacks": [
			{"name": "sweep", "kind": "melee", "shape": "arc", "reach": 46.0, "arc": 160.0, "windup": 1.0, "active": 0.15, "recover": 0.8,
				"damage": 30.0, "rest": 0.6, "back": 2.5, "end": -1.9, "blade": 30.0, "use": [0.0, 26.0]},
			{"name": "stomp", "kind": "melee", "shape": "ring", "reach": 36.0, "arc": 360.0, "windup": 0.9, "active": 0.12, "recover": 0.9,
				"damage": 24.0, "rest": 0.6, "back": 0.6, "end": 0.6, "blade": 30.0, "use": [0.0, 12.0]},
			{"name": "slam", "kind": "melee", "shape": "line", "reach": 84.0, "width": 16.0, "windup": 1.2, "active": 0.15, "recover": 1.0,
				"damage": 40.0, "rest": 0.6, "back": 3.1, "end": 0.0, "blade": 30.0, "use": [14.0, 62.0]},
		]},
	"knight": {"name": "Knight", "hp": 180.0, "speed": 30.0, "radius": 8.0, "poise": 45.0, "aggro": 110.0, "cool": [0.8, 1.6],
		"cloth": Color(0.3, 0.3, 0.34), "head": Color(0.42, 0.42, 0.46),
		"attack": {"kind": "melee", "reach": 24.0, "arc": 140.0, "windup": 0.8, "active": 0.14, "recover": 0.7, "damage": 28.0,
			"rest": 0.5, "back": 2.3, "end": -1.6, "blade": 15.0}},
}

# The party you start with (4 to 10).
const PARTY := ["sword", "sword", "great", "great", "bow", "bow", "sorcerer", "sorcerer"]

const DODGE := {"distance": 34.0, "time": 0.28, "iframes": 0.22, "cool": 0.45}
const BLOCK := {"arc": 140.0, "move": 0.5}
const STAGGER := 0.4
const ARROW := {"speed": 150.0, "arc": 0.3, "hit": 6.0}  # arc: how high it flies, per pixel of distance

# The possessed one (your soul in it): the enhanced moveset.
const LEADER := {"speed": 1.15, "combo": [1.0, 1.0, 1.6]}  # each hit of the chain: times the damage

# The circle you move the party with, and its formations.
const CIRCLE := {"radius": 36.0, "speed": 42.0, "turn": 2.6}
const FORMATIONS := ["ring", "line", "wedge", "column"]

# The rest of the party.
const STEP_OUT := 20.0  # in formation, melee step this far out of place to hit something
const HOLD_NEAR := 8.0  # in formation, ranged shoot only this close to their place
const RELEASED_SIGHT := 170.0  # released, they go after enemies this close
const SPREAD := 50.0  # released: a target already taken counts as this much further away
const AI_DODGE := 0.5  # chance they dodge a wind-up aimed at them (shields block instead)
const LEASH := 220.0  # enemies give up this far from home

const SOUL := Color(0.75, 0.95, 1.0)
