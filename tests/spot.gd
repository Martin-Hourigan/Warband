extends SceneTree
## Spot checks: godot --headless --path . --script res://tests/spot.gd

const Data = preload("res://scripts/data.gd")
const MissileScript = preload("res://scripts/missile.gd")

var main
var fails := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(ok: bool, what: String, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + what + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func seconds(t: float) -> void:
	await frames(int(t * 60.0))


func _clear_enemies() -> void:
	for u in main.units.duplicate():
		if u.team == "enemy":
			main.units.erase(u)
			u.queue_free()
	await frames(2)


## The party at the bonfire, no enemies, the circle still.
func _reset() -> void:
	main.rest()
	await frames(2)
	await _clear_enemies()
	main.test = {"move": Vector2.ZERO, "aim": main.circle + Vector2(20, 0), "attack": false, "dodge": false, "block": false, "turn": 0.0}
	main.circle_rot = -PI * 0.5
	await seconds(1.0)


## Only the one your soul's in moves; it faces right.
func _solo(n: int):
	main.possess(main.party_units()[n].position)
	var L = main.leader
	for u in main.party_units():
		u.set_physics_process(u == L)
	L.position = main.map.party_at
	L.facing = 0.0
	main.test.aim = L.position + Vector2(20, 0)
	await frames(2)
	return L


func _enemy(kind: String, at: Vector2, active := false):
	var e = main._spawn("enemy", kind, at)
	e.set_physics_process(active)
	return e


func _run() -> void:
	await frames(3)
	check(main.menu, "it opens on the main menu")
	main.start()
	main.scripted = true
	check(main.party_units().size() == Data.PARTY.size() and main.leader == null, "the party: %d, and you're the circle" % Data.PARTY.size())
	await _circle()
	await _pads()
	await _auto_attack()
	await _stay_in_circle()
	await _release_and_focus()
	await _possessed()
	await _block_and_dodge()
	await _ranged()
	await _dodges()
	await _controller()
	await _giant()
	await _death()
	print("SPOT %s (%d failed)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)


func _in_places(tol := 6.0) -> int:
	var n := 0
	for u in main.party_units():
		if u.position.distance_to(main.slot_pos(u)) < tol:
			n += 1
	return n


func _circle() -> void:
	await _reset()
	check(_in_places() == Data.PARTY.size(), "they stand in their places in the circle", str(_in_places()))
	var start: Vector2 = main.circle
	main.test.move = Vector2(1, 0)
	await seconds(1.5)
	main.test.move = Vector2.ZERO
	await seconds(1.0)
	check(main.circle.x > start.x + 30.0 and _in_places(8.0) >= Data.PARTY.size() - 1, "WASD moves the circle; they keep up", "%d in place" % _in_places(8.0))
	for f in Data.FORMATIONS:
		main.set_formation(f)
		await seconds(2.5)
		check(_in_places(8.0) >= Data.PARTY.size() - 1, "  formation: %s" % f, "%d in place" % _in_places(8.0))
	main.set_formation("line")
	await seconds(1.0)
	var melee = main.party_units()[0]
	var ahead: float = (melee.position - main.circle).dot(Vector2.from_angle(main.circle_rot))
	main.test.turn = 1.0
	await seconds(PI / Data.CIRCLE.turn)
	main.test.turn = 0.0
	await seconds(1.5)
	var ahead2: float = (melee.position - main.circle).dot(Vector2.from_angle(-PI * 0.5))
	check(ahead > 0.0 and ahead2 < 0.0, "Q/E turns it: the front row swings round", "%.1f %.1f" % [ahead, ahead2])
	main.set_formation("base")


## The on-screen stick and dial (touch).
func _pads() -> void:
	await _reset()
	var hud = main.hud
	var start: Vector2 = main.circle
	check(hud.touch(0, hud.STICK_AT, true), "a thumb on the stick")
	hud.drag(0, hud.STICK_AT + Vector2(hud.PAD, 0))
	await seconds(1.0)
	hud.touch(0, hud.STICK_AT, false)
	check(main.circle.x > start.x + 30.0 and hud.stick == Vector2.ZERO, "  pushed right: the circle goes right; let go: it stops", str(main.circle - start))
	var rot: float = main.circle_rot
	check(hud.touch(1, hud.DIAL_AT + Vector2.from_angle(rot) * hud.PAD, true), "a finger on the dial")
	for k in 10:
		hud.drag(1, hud.DIAL_AT + Vector2.from_angle(rot + PI * 0.5 * (k + 1) / 10.0) * hud.PAD)
		await frames(1)
	hud.touch(1, Vector2.ZERO, false)
	await frames(1)
	check(absf(angle_difference(rot + PI * 0.5, main.circle_rot)) < 0.05, "  dragged a quarter turn round: the formation turns a quarter", "%.2f -> %.2f" % [rot, main.circle_rot])
	check(not hud.touch(2, Vector2(240, 135), true), "a touch in the play area isn't on the panels")
	var bs: Dictionary = hud.buttons()
	hud.touch(3, bs["wedge"].get_center(), true)
	hud.touch(3, bs["wedge"].get_center(), false)
	check(main.formation == "wedge", "the right panel's formation buttons: wedge")
	hud.touch(3, bs["release"].get_center(), true)
	hud.touch(3, bs["release"].get_center(), false)
	check(main.released, "  the release button: released")
	hud.touch(3, bs["release"].get_center(), true)
	hud.touch(3, bs["release"].get_center(), false)
	check(not main.released, "  again: back in the circle")
	main.set_formation("base")
	var row: Array = hud.roster()[2]
	hud.touch(5, row[1].get_center(), true)
	hud.touch(5, row[1].get_center(), false)
	check(main.leader == row[0], "a figure on the left panel tapped: your soul in it")
	hud.touch(5, row[1].get_center(), true)
	hud.touch(5, row[1].get_center(), false)
	check(main.leader == null, "  tapped again: back out")
	hud.touch(6, bs["block"].get_center(), true)
	check(hud.block_held(), "the block button, held")
	hud.touch(6, bs["block"].get_center(), false)
	check(not hud.block_held(), "  let go")
	main.touch = true
	var e = await _enemy("knight", main.circle + Vector2(40, 0))
	await frames(2)
	hud.touch(7, main.get_canvas_transform() * e.position, true)
	hud.touch(7, main.get_canvas_transform() * e.position, false)
	check(main.focus == e, "on a phone, an enemy tapped: focused")
	main.touch = false
	main.focus = null
	await _clear_enemies()
	main.menu = true
	hud.touch(8, hud.menu_buttons().start.get_center(), true)
	hud.touch(8, hud.menu_buttons().start.get_center(), false)
	check(not main.menu, "the main menu's START")
	main.circle_rot = -PI * 0.5


## Not released, they keep to the circle: a sorcerer left behind in the passage,
## with an enemy in range but a wall in the way, comes back; a melee unit
## doesn't chase past its step out.
func _stay_in_circle() -> void:
	await _reset()
	var c: Vector2 = main.map.party_at
	var e = await _enemy("knight", main.circle + Vector2(0, -40))
	var sorc = main.party_units()[6]
	sorc.position = (Vector2(13.5, 4.5)) * main.map.T  # along the passage out of the bonfire room
	await seconds(4.0)
	check(sorc.position.distance_to(main.slot_pos(sorc)) < 10.0, "a sorcerer left in the passage comes back to its place", str(sorc.position.distance_to(main.slot_pos(sorc))))
	await _clear_enemies()
	e = await _enemy("knight", main.circle + Vector2(0, -60))
	var far := 0.0
	for i in 120:
		await physics_frame
		for u in main.party_units():
			if not u.ranged():
				far = maxf(far, u.position.distance_to(main.slot_pos(u)))
	check(far <= Data.STEP_OUT + 3.0, "melee step out to it, no further than %d from their places" % Data.STEP_OUT, "%.1f" % far)
	main.circle += Vector2(30, 0)
	await seconds(1.5)
	var off := 0
	for u in main.party_units():
		if u.position.distance_to(main.slot_pos(u)) > 8.0 + (Data.STEP_OUT if not u.ranged() else 0.0):
			off += 1
			print("   behind: ", u.kind, " ", u.position.distance_to(main.slot_pos(u)), " ", u.state)
	check(off == 0, "  the circle moves off: they go with it", "%d left behind" % off)
	await _clear_enemies()


func _auto_attack() -> void:
	await _reset()
	var far = await _enemy("hollow", main.circle + Vector2(0, 600), true)
	await seconds(0.5)
	check(far.position == far.home, "an enemy far off, at home: asleep (not thinking)")
	main.units.erase(far)
	far.queue_free()
	var e = await _enemy("knight", main.circle + Vector2(0, -60))
	var h: float = e.hp
	await seconds(2.0)
	check(e.hp < h, "an enemy in range: they attack it on their own", str(h - e.hp))
	await _clear_enemies()
	e = await _enemy("knight", main.circle + Vector2(0, -200))
	h = e.hp
	await seconds(2.0)
	check(e.hp == h, "  one far off: they keep their places")
	await _clear_enemies()


func _release_and_focus() -> void:
	await _reset()
	var a = await _enemy("knight", main.circle + Vector2(-60, -100))
	var b = await _enemy("knight", main.circle + Vector2(60, -100))
	main.released = true
	await seconds(3.0)
	var on_a := 0
	var on_b := 0
	for u in main.party_units():
		on_a += 1 if u.target == a else 0
		on_b += 1 if u.target == b else 0
	check(on_a >= 2 and on_b >= 2, "F: released, they spread out over the enemies", "%d / %d" % [on_a, on_b])
	main.pick_focus(b.position)
	await seconds(0.2)
	var on := 0
	for u in main.party_units():
		on += 1 if u.target == b else 0
	check(main.focus == b and on == Data.PARTY.size(), "a focus: all of them on it", str(on))
	main.released = false
	main.focus = null
	await _clear_enemies()


func _possessed() -> void:
	await _reset()
	main.possess(main.party_units()[2].position)
	check(main.leader == main.party_units()[2], "Tab: your soul into the one nearest the pointer")
	main.test.move = Vector2(1, 0)
	await seconds(1.0)
	main.test.move = Vector2.ZERO
	await seconds(1.5)
	check(_in_places(8.0) >= Data.PARTY.size() - 2, "  the formation forms round it", "%d in place" % _in_places(8.0))
	var at: Vector2 = main.leader.position
	main.leave()
	check(main.leader == null and main.circle == at, "X: back out to the circle, where it was")
	var L = await _solo(0)
	var e = await _enemy("knight", L.position + Vector2(16, 0))
	var h: float = e.hp
	main.test.attack = true
	await seconds(0.5)
	check(absf(h - e.hp - Data.UNITS.sword.attack.damage) < 0.01, "LMB: the sword hits what's in front", str(h - e.hp))
	h = e.hp
	for k in 3:
		main.test.attack = true
		await seconds(0.3)
	await seconds(0.4)
	check(L.combo == 0 and h - e.hp > Data.UNITS.sword.attack.damage * 2.5, "  pressed in time: a chain, the last hit harder", str(h - e.hp))
	h = e.hp
	main.test.aim = L.position + Vector2(-20, 0)
	await seconds(0.3)
	main.test.attack = true
	await seconds(0.5)
	check(e.hp == h, "  facing away: no hit")
	await _clear_enemies()


func _block_and_dodge() -> void:
	await _reset()
	var L = await _solo(0)
	main.test.block = true
	await frames(2)
	check(L.blocking, "RMB with a shield: blocking")
	var e = await _enemy("hollow", L.position + Vector2(12, 0), true)
	e.facing = PI
	await seconds(1.2)
	check(L.hp == L.def.hp, "  a hollow's hit from the front: nothing", str(L.hp))
	main.test.block = false
	await _clear_enemies()
	L.hp = L.def.hp
	e = await _enemy("hollow", L.position + Vector2(12, 0), true)
	e.facing = PI
	await seconds(0.2)
	check(e.state == "windup", "a hollow winds up", e.state)
	main.test.dodge = true
	main.test.move = Vector2(0, 1)
	await seconds(0.12)
	check(L.state == "dodge", "  Space: a dodge")
	main.test.move = Vector2.ZERO
	await seconds(0.5)
	check(L.hp == L.def.hp, "  ...out of it", str(L.hp))
	await _clear_enemies()


func _ranged() -> void:
	await _reset()
	var L = await _solo(4)
	check(L.kind == "bow", "your soul in the bow", L.kind)
	var e = await _enemy("knight", L.position + Vector2(60, 0))
	var h: float = e.hp
	main.test.aim = e.position
	main.test.attack = true
	await seconds(0.6)
	var arrows: Array = main.get_children().filter(func(c): return c is MissileScript)
	var high: bool = arrows.size() > 0 and arrows[0].height > 5.0
	check(high, "  LMB: an arrow, up in the air", str(arrows[0].height if arrows.size() else -1.0))
	await seconds(1.0)
	check(absf(h - e.hp - Data.UNITS.bow.attack.damage) < 0.01, "  ...comes down on it", str(h - e.hp))
	h = e.hp
	main.test.aim = e.position
	main.test.attack = true
	await seconds(0.5)
	e.position += Vector2(0, 30)  # it moves away while the arrow's up
	await seconds(1.5)
	check(e.hp == h, "  moved out from under it: missed")
	await _clear_enemies()
	L = await _solo(6)
	check(L.kind == "sorcerer", "your soul in the sorcerer", L.kind)
	e = await _enemy("knight", L.position + Vector2(60, 0))
	h = e.hp
	main.test.aim = e.position
	main.test.attack = true
	await seconds(1.2)
	check(absf(h - e.hp - Data.UNITS.sorcerer.attack.damage) < 0.01, "  LMB: a bolt", str(h - e.hp))
	await _clear_enemies()


func _dodges() -> void:
	await _reset()
	var L = await _solo(0)
	var e = await _enemy("knight", L.position + Vector2(16, 0))
	var h: float = e.hp
	main.test.attack = true
	await seconds(0.1)
	main.test.dodge = true
	await seconds(0.05)
	check(L.state == "windup", "dodge pressed mid-attack: the attack carries on", L.state)
	var a: Dictionary = L.atk
	await seconds(float(a.windup) + float(a.active) + float(a.recover))
	check(e.hp < h and L.state == "dodge", "  it lands, and then the dodge goes", "%s %s" % [h - e.hp, L.state])
	await _clear_enemies()
	await _reset()
	main.dodge()
	await frames(3)
	var n := 0
	for u in main.party_units():
		n += 1 if u.state == "dodge" else 0
	check(n == Data.PARTY.size(), "as the circle, dodge: the whole party dodges", str(n))
	await seconds(1.0)
	var bs: Dictionary = main.hud.buttons()
	main.hud.touch(4, bs["dodge"].get_center(), true)
	main.hud.touch(4, bs["dodge"].get_center(), false)
	await frames(3)
	n = 0
	for u in main.party_units():
		n += 1 if u.state == "dodge" else 0
	check(n == Data.PARTY.size(), "  ...and the dodge button on the right panel", str(n))


func _pad(button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _stick(axis: int, v: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	Input.parse_input_event(ev)


## A controller, through the real input (not the test's).
func _controller() -> void:
	await _reset()
	main.scripted = false
	var start: Vector2 = main.circle
	_stick(JOY_AXIS_LEFT_X, 1.0)
	await seconds(1.0)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	await frames(2)
	check(main.using_pad and main.circle.x > start.x + 25.0, "controller: the left stick moves the circle", str(main.circle - start))
	var rot: float = main.circle_rot
	_stick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await seconds(0.5)
	_stick(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames(2)
	check(main.circle_rot > rot + 0.5, "  a trigger turns the formation", "%.2f -> %.2f" % [rot, main.circle_rot])
	_pad(JOY_BUTTON_DPAD_DOWN, true)
	_pad(JOY_BUTTON_DPAD_DOWN, false)
	_pad(JOY_BUTTON_RIGHT_SHOULDER, true)
	_pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	await frames(3)
	check(main.formation == Data.FORMATIONS[2] and main.released, "  d-pad: a formation; RB: release", "%s %s" % [main.formation, main.released])
	_pad(JOY_BUTTON_RIGHT_SHOULDER, true)
	_pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	_pad(JOY_BUTTON_A, true)
	_pad(JOY_BUTTON_A, false)
	await frames(3)
	var n := 0
	for u in main.party_units():
		n += 1 if u.state == "dodge" else 0
	check(n == Data.PARTY.size(), "  A: the party dodges", str(n))
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	await frames(3)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	_pad(JOY_BUTTON_Y, true)
	_pad(JOY_BUTTON_Y, false)
	await frames(3)
	var right_most = null
	for u in main.party_units():
		if right_most == null or u.position.x > right_most.position.x:
			right_most = u
	check(main.leader == right_most, "  right stick points, Y: your soul into the one nearest it")
	_pad(JOY_BUTTON_B, true)
	_pad(JOY_BUTTON_B, false)
	await frames(3)
	check(main.leader == null, "  B: back out")
	main.scripted = true
	main.set_formation("base")


## The giant's attacks, each forced in turn, against bodies placed round it.
func _giant() -> void:
	await _reset()
	for u in main.party_units():
		u.set_physics_process(false)
	var g = await _enemy("giant", main.map.party_at)
	g.facing = 0.0
	var P: Array = main.party_units()
	var spots := {
		"front": Vector2(30, 0), "behind": Vector2(-34, 0), "far ahead": Vector2(70, 0), "far side": Vector2(20, 60),
	}
	var names := spots.keys()
	for i in range(names.size(), P.size()):
		P[i].position = g.position + Vector2(0, -200)  # the rest out of the way
	var expect := {
		"sweep": ["front"], "stomp": ["front", "behind"], "slam": ["front", "far ahead"],
	}
	for a in Data.ENEMIES.giant.attacks:
		for i in names.size():
			P[i].hp = 9999.0
			P[i].dead = false
			P[i].position = g.position + spots[names[i]]
		g.atk = a
		g.facing = 0.0
		g._start_attack(g.position + Vector2(20, 0))
		g.set_physics_process(true)
		await seconds(float(a.windup) + float(a.active) + 0.05)
		g.set_physics_process(false)
		g._to("idle")
		var hit := []
		for i in names.size():
			if P[i].hp < 9999.0:
				hit.append(names[i])
		check(hit == expect[a.name], "the giant's %s hits: %s" % [a.name, ", ".join(expect[a.name])], str(hit))
	await _clear_enemies()


func _death() -> void:
	main.rest()
	await frames(2)
	for u in main.party_units():
		u.take_hit(999.0, null)
	await frames(2)
	check(main.died, "the whole party dead: you died")
	main.rest()
	await frames(2)
	check(not main.died and main.party_units().all(func(u): return not u.dead), "  back at the bonfire, all of them")
