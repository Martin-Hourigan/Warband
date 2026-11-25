extends Control
## The screen is the play area in the middle with a panel down each side
## (shaped for a phone held sideways).
## Left panel: the party, one small figure each with its health (the one your
## soul is in is ringed), and under them the thumbstick - it moves the circle,
## or the one your soul is in.
## Right panel: the formations, the release and dodge, as buttons, and under them the
## dial that turns the formation - its notch is the way the formation faces;
## drag it round.
## Over the play area: the pointer, "YOU DIED". The main menu.
## Tap a figure on the left to put your soul in it (tap it again: back out).
## The mouse works everything here too (touch is emulated from it); on a
## phone, taps on the play area go to main.tap.

const Data = preload("res://scripts/data.gd")

const W := 608  # the whole screen
const H := 270
const SIDE := 64  # each panel's width; the play area is the 480 between
const STICK_AT := Vector2(32, 226)
const DIAL_AT := Vector2(W - 32, 226)
const PAD := 22.0  # the stick's and the dial's radius
const GRAB := 30.0  # a touch this close to one takes it
const BUTTON := Vector2(24, 24)
const PANEL := Color(0.09, 0.085, 0.08)
const EDGE := Color(0.22, 0.2, 0.18)

var main
var stick := Vector2.ZERO  # -1..1 each way
var _stick_id := -1  # the touch on the stick (-1: none)
var _dial_id := -1
var _dial_last := 0.0  # the touch's angle round the dial last frame
var turned := 0.0  # radians the dial has turned since main last took it
var _block_id := -1  # the touch holding the block button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The buttons on the right panel: name -> rect. Formations two by two, then
## the release under them.
func buttons() -> Dictionary:
	var out := {}
	var x0 := W - SIDE + 6.0
	for i in Data.FORMATIONS.size():
		out[Data.FORMATIONS[i]] = Rect2(Vector2(x0 + (i % 2) * 28.0, 10.0 + (i / 2) * 28.0), BUTTON)
	out["release"] = Rect2(Vector2(x0, 70.0), Vector2(52, 20))
	out["dodge"] = Rect2(Vector2(x0, 98.0), Vector2(52, 52))
	out["block"] = Rect2(Vector2(x0, 156.0), Vector2(52, 30))
	return out


## The party down the left: one row each, tapped to put your soul in it.
func roster() -> Array:
	var out := []
	var y := 12.0
	for u in main.party_units():
		out.append([u, Rect2(0, y - 8.0, SIDE, 16)])
		y += 17.0
	return out


func menu_buttons() -> Dictionary:
	return {
		"start": Rect2(W * 0.5 - 50.0, 130.0, 100, 24),
		"update": Rect2(W * 0.5 - 70.0, 200.0, 140, 18),
	}


func block_held() -> bool:
	return _block_id >= 0


func in_panels(p: Vector2) -> bool:
	return p.x < SIDE or p.x >= W - SIDE


## True while a finger (or the mouse) is on the stick or the dial, so a
## press there isn't also an attack or a pick.
func touching() -> bool:
	return _stick_id >= 0 or _dial_id >= 0


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if touch(e.index, e.position, e.pressed):
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if drag(e.index, e.position):
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and (touching() or in_panels(e.position) or main.menu):
		get_viewport().set_input_as_handled()  # the touch made from it does the work


## A finger down or up. Returns true if it was on the panels.
func touch(id: int, p: Vector2, pressed: bool) -> bool:
	if main.menu:
		if pressed:
			var mb := menu_buttons()
			if mb.start.has_point(p):
				main.start()
			elif mb.update.has_point(p):
				main.update_tap()
		return true
	if pressed:
		if _stick_id < 0 and p.distance_to(STICK_AT) <= GRAB:
			_stick_id = id
			_set_stick(p)
			return true
		if _dial_id < 0 and p.distance_to(DIAL_AT) <= GRAB:
			_dial_id = id
			_dial_last = (p - DIAL_AT).angle()
			return true
		var bs := buttons()
		for b in bs:
			if bs[b].has_point(p):
				if b == "block":
					_block_id = id
				else:
					_press(b)
				return true
		for r in roster():
			if r[1].has_point(p):
				main.soul_into(r[0])
				return true
		if not in_panels(p) and main.touch:
			main.tap(main.get_canvas_transform().affine_inverse() * p)
			return true
		return in_panels(p)
	if id == _block_id:
		_block_id = -1
		return true
	if id == _stick_id:
		_stick_id = -1
		stick = Vector2.ZERO
		return true
	if id == _dial_id:
		_dial_id = -1
		return true
	return in_panels(p)


func _press(b: String) -> void:
	if b == "dodge":
		main.dodge()
	elif b == "release":
		main.released = not main.released
	else:
		main.set_formation(b)


func drag(id: int, p: Vector2) -> bool:
	if id == _stick_id:
		_set_stick(p)
		return true
	if id == _dial_id:
		var a := (p - DIAL_AT).angle()
		if p.distance_to(DIAL_AT) > 3.0:  # right at the middle the angle jumps about
			turned += angle_difference(_dial_last, a)
			_dial_last = a
		return true
	return false


func _set_stick(p: Vector2) -> void:
	stick = (p - STICK_AT).limit_length(PAD) / PAD


## The dial's turning since last asked (main adds it to the formation's).
func take_turn() -> float:
	var t := turned
	turned = 0.0
	return t


# ── Drawing ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if main.menu:
		_draw_menu()
		return
	for x in [0, W - SIDE]:
		draw_rect(Rect2(x, 0, SIDE, H), PANEL)
	draw_rect(Rect2(SIDE - 1, 0, 1, H), EDGE)
	draw_rect(Rect2(W - SIDE, 0, 1, H), EDGE)
	_draw_party()
	_draw_buttons()
	_draw_pads()
	if main.died:
		draw_rect(Rect2(Vector2(SIDE, H * 0.5 - 14.0), Vector2(W - SIDE * 2, 22)), Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(SIDE, H * 0.5 + 3.0), "YOU DIED", HORIZONTAL_ALIGNMENT_CENTER, W - SIDE * 2, 16, Color(0.7, 0.1, 0.08))
	if main.touch:
		return
	# the pointer (the controller's sits out in the world, from the circle)
	var m := get_viewport().get_mouse_position().round()
	if main.using_pad:
		if main.leader != null:
			return
		m = (main.get_viewport().get_canvas_transform() * main.pointer()).round()
	for d in [Vector2(-3, 0), Vector2(-2, 0), Vector2(2, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, -2), Vector2(0, 2), Vector2(0, 3)]:
		draw_rect(Rect2(m + d, Vector2.ONE), Color(0.95, 0.95, 0.9))


## The party down the left: figure, health bar.
func _draw_party() -> void:
	var y := 12.0
	for u in main.party_units():
		var c := Vector2(12, y)
		var cloth: Color = u.def.cloth
		if u.dead:
			cloth = cloth.darkened(0.6)
		draw_circle(c, 4.0, cloth)
		draw_circle(c + Vector2(0, -1), 2.0, u.def.head if not u.dead else cloth)
		if u.possessed:
			draw_arc(c, 6.0, 0.0, TAU, 16, Data.SOUL, -1.0)
		var frac: float = maxf(0.0, u.hp / float(u.def.hp))
		draw_rect(Rect2(Vector2(21, y - 1.0), Vector2(36, 3)), Color(0.15, 0.05, 0.05))
		draw_rect(Rect2(Vector2(21, y - 1.0), Vector2(roundf(36.0 * frac), 3)), Color(0.75, 0.15, 0.12))
		y += 17.0


## Formation buttons, each with its shape in dots; the release under them.
func _draw_buttons() -> void:
	var bs := buttons()
	for b in bs:
		var r: Rect2 = bs[b]
		var on: bool = main.released if b == "release" else main.formation == b
		if b == "dodge":
			on = false
		elif b == "block":
			on = _block_id >= 0
		draw_rect(r, Color(0.16, 0.15, 0.14) if not on else Color(0.24, 0.3, 0.32))
		draw_rect(r, Data.SOUL if on else EDGE, false, 1.0)
		var c := r.get_center().round()
		var dot := Color(0.85, 0.85, 0.8)
		match b:
			"base":  # an arc of four across the front, a square of four in the middle
				for k in 4:
					var a := -PI * 0.5 + (float(k) - 1.5) * TAU / 8.0
					draw_rect(Rect2((c + Vector2(0, 2) + Vector2.from_angle(a) * 9.0).round(), Vector2.ONE), dot)
				for v in [Vector2(-2, 0), Vector2(2, 0), Vector2(-2, 4), Vector2(2, 4)]:
					draw_rect(Rect2(c + v, Vector2.ONE), dot)
			"line":
				for k in 5:
					draw_rect(Rect2(c + Vector2(-8 + k * 4, -3), Vector2.ONE), dot)
				for k in 3:
					draw_rect(Rect2(c + Vector2(-4 + k * 4, 4), Vector2.ONE), dot)
			"wedge":
				for k in 4:
					draw_rect(Rect2(c + Vector2(-k * 3, -6 + k * 4), Vector2.ONE), dot)
					draw_rect(Rect2(c + Vector2(k * 3, -6 + k * 4), Vector2.ONE), dot)
			"column":
				for k in 4:
					draw_rect(Rect2(c + Vector2(-2, -7 + k * 4), Vector2.ONE), dot)
					draw_rect(Rect2(c + Vector2(2, -7 + k * 4), Vector2.ONE), dot)
			"dodge":  # a figure rolling away, with the line it leaves behind
				draw_circle(c + Vector2(6, -4), 5.0, dot)
				draw_circle(c + Vector2(6, -4), 2.0, Color(0.16, 0.15, 0.14))
				for k in 4:
					draw_rect(Rect2(c + Vector2(-12 + k * 3, 4 - k * 2), Vector2(2, 1)), Color(dot, 0.4 + 0.15 * k))
			"block":  # a shield, edge on
				var sc := dot if main.leader != null and main.leader.def.get("shield", false) else Color(dot, 0.3)
				draw_rect(Rect2(c + Vector2(-8, -1), Vector2(16, 3)), sc)
				draw_rect(Rect2(c + Vector2(-1, 2), Vector2(2, 3)), sc)
			"release":  # the party spread out, a broken ring round them
				for k in 8:
					var a := TAU * k / 8.0
					draw_rect(Rect2((c + Vector2.from_angle(a) * Vector2(18, 6)).round(), Vector2.ONE), dot)
				for v in [Vector2(-6, -1), Vector2(-1, 2), Vector2(5, -2), Vector2(9, 1), Vector2(-10, 2)]:
					draw_rect(Rect2(c + v, Vector2.ONE), Data.SOUL if on else dot)


func _draw_pads() -> void:
	var dim := Color(0.9, 0.9, 0.85, 0.3)
	var lit := Color(0.9, 0.9, 0.85, 0.7)
	# the stick: a ring, and the knob where the thumb has it
	draw_circle(STICK_AT, PAD, Color(0, 0, 0, 0.35))
	draw_arc(STICK_AT, PAD, 0.0, TAU, 32, lit if _stick_id >= 0 else dim, -1.0)
	draw_circle((STICK_AT + stick * PAD).round(), 8.0, lit if _stick_id >= 0 else dim)
	# the dial: a ring with ticks round it, and the notch the way the formation faces
	draw_circle(DIAL_AT, PAD, Color(0, 0, 0, 0.35))
	var col := lit if _dial_id >= 0 else dim
	draw_arc(DIAL_AT, PAD, 0.0, TAU, 32, col, -1.0)
	for k in 8:
		var v := Vector2.from_angle(TAU * k / 8.0)
		draw_rect(Rect2((DIAL_AT + v * (PAD - 3.0)).round(), Vector2.ONE), col)
	var f := Vector2.from_angle(main.circle_rot)
	var soul := Color(Data.SOUL, 0.85 if _dial_id >= 0 else 0.55)
	draw_line((DIAL_AT + f * 6.0).round(), (DIAL_AT + f * (PAD + 2.0)).round(), soul, 2.0)
	draw_circle((DIAL_AT + f * PAD).round(), 3.0, soul)


## The main menu: the name, START, the update button, the version.
func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.045, 0.045))
	var font := ThemeDB.fallback_font
	var soul := Data.SOUL
	draw_string(font, Vector2(0, 92), "WARBAND", HORIZONTAL_ALIGNMENT_CENTER, W, 32, Color(0.85, 0.82, 0.75))
	# a small ring of the party under the name
	for i in Data.PARTY.size():
		var u: Dictionary = Data.UNITS[Data.PARTY[i]]
		var c := (Vector2(W * 0.5, 108) + Vector2((i - 3.5) * 12.0, 0)).round()
		draw_circle(c, 4.0, u.cloth)
		draw_circle(c + Vector2(0, -1), 2.0, u.head)
	var mb := menu_buttons()
	for k in mb:
		var r: Rect2 = mb[k]
		draw_rect(r, Color(0.14, 0.13, 0.12))
		draw_rect(r, soul if k == "start" else EDGE, false, 1.0)
		var label: String = "START" if k == "start" else main.update_label()
		var size := 16 if k == "start" else 10
		draw_string(font, Vector2(r.position.x, r.get_center().y + size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, Color(0.9, 0.9, 0.85))
	draw_string(font, Vector2(6, H - 6), "V" + main.Update.current(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.48, 0.45))
