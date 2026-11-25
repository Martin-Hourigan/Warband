extends Node2D
## Game root, top down: a 480x270 play area between two side panels (608x270
## in all), scaled up whole.
## Most of the time you move a circle: the party keeps its places inside it,
## in a formation you choose and turn, and attacks whatever comes in range.
## Release them and they spread out and go after enemies themselves; or pick
## one enemy for them all to focus. Your soul can go into any of them: you
## drive that one (with the enhanced moveset) and the formation forms round
## it; leave it and you're back to the circle, where it was.
## The bonfire: rest there and the dead get up, everyone heals, and the
## enemies come back (as when you all die).
## It opens on the main menu (start, and the update button). On a phone the
## play area is tapped: as the circle, a tap on an enemy focuses it (on the
## bonfire, near it, rests); in a body, a tap attacks toward it.

const Data = preload("res://scripts/data.gd")
const MapScript = preload("res://scripts/map.gd")
const UnitScript = preload("res://scripts/unit.gd")
const MissileScript = preload("res://scripts/missile.gd")
const HudScript = preload("res://scripts/hud.gd")
const Update = preload("res://scripts/update.gd")

const JUMP_TIME := 0.25  # the soul flying to or from a body
const PAD_REACH := 90.0  # a controller's pointer: this far out from the circle at full tilt
const PAD_AIM := 30.0
const PAD_PICK := 40.0  # with a controller, an enemy this close to the pointer is picked
const TAP_PICK := 20.0  # a finger's tap: an enemy this close to it is picked
const TAP_AIM_TIME := 0.5  # in a body, a tap's direction is kept this long
const REST_NEAR := 36.0  # the circle (or body) this close to the bonfire can rest
const AWAKE := 320.0  # enemies further than this from you, at home and idle, don't think

var map
var units: Array = []
var leader = null  # the one your soul is in; none: you're the circle
var circle := Vector2.ZERO
var circle_rot := -PI * 0.5  # which way the formation faces
var formation := "ring"
var released := false
var focus = null  # the enemy they all go for
var claims := {}  # enemy -> how many of the party are going for it (this frame)
var died := false
var cam: Camera2D
var hud
var fx: Node2D
var scripted := false  # tests: input comes from `test`
var test := {"move": Vector2.ZERO, "aim": Vector2.ZERO, "attack": false, "dodge": false, "block": false, "turn": 0.0}
var _sparks: Array = []  # [pos, time left]
var _jump := {}  # from, to (a unit, or null for the circle), t
var using_pad := false  # last touched: a controller (else mouse/keys/touch)
var _pad_off := Vector2(0, -40)  # the controller's pointer, from the circle
var _ui_dodge := false  # the panel's dodge button, pressed
var _ui_attack := false  # a tap on the play area, in a body
var _tap_aim := Vector2.ZERO
var _tap_t := 0.0
var menu := true  # the main menu is up
var touch := false  # a phone: taps, no pointer
var _party: Array = []  # this frame's lists (see _lists)
var _alive := {"party": [], "enemy": []}
var _slots := {}  # unit -> its place, this frame

# updates: checking GitHub for a newer release, downloading it
var update_state := ""  # "", checking, latest, new, downloading, ready, failed, download_failed
var update_tag := ""
var update_url := ""
var update_page := ""
var update_asked := false  # tapped to check, so say if nothing turned up
var update_note := 0.0  # s left showing "no new version"
var http: HTTPRequest
var download: HTTPRequest


func _ready() -> void:
	_setup_input()
	touch = OS.has_feature("mobile") or OS.get_cmdline_args().has("--touch")
	# an update downloaded last time has been installed (or given up on)
	if FileAccess.file_exists(Update.APK):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Update.APK))
	if OS.has_feature("mobile"):
		_check_update()
	map = MapScript.new()
	add_child(map)
	map.build()
	fx = Node2D.new()
	fx.z_index = 4
	fx.draw.connect(_draw_fx)
	add_child(fx)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	# the side panels cover the screen's edges: the play area can still reach the map's
	cam.limit_left = -HudScript.SIDE
	cam.limit_top = 0
	cam.limit_right = int(map.size_px().x) + HudScript.SIDE
	cam.limit_bottom = int(map.size_px().y)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.main = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	if not touch:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	rest()
	_dev_args.call_deferred()


## For screenshots (any of them skips the menu): --play, --at <x>,<y> (the
## circle there, in tiles), --soul <n> (your soul in the nth of the party),
## --release, --formation <name>. --touch: as on a phone.
func _dev_args() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		var v: String = args[i + 1] if i + 1 < args.size() else ""
		if args[i] in ["--play", "--at", "--soul", "--release", "--formation"]:
			menu = false
		match args[i]:
			"--at":
				var p := v.split(",")
				var to: Vector2 = (Vector2(float(p[0]), float(p[1])) + Vector2(0.5, 0.5)) * map.T
				for u in party_units():
					u.position += to - circle
				circle = to
			"--soul":
				possess(party_units()[int(v)].position)
				_jump = {}
			"--release":
				released = true
			"--formation":
				formation = v


## Keys and mouse, and a controller:
## left stick move, right stick aim (in a body) or the pointer (as the circle),
## A dodge, X attack (in a body) or focus what the pointer's on (as the circle),
## Y soul into the one nearest the pointer, B back out, LB block, RB release,
## triggers turn the formation, d-pad formations, Start rest.
func _setup_input() -> void:
	var keys := {
		"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"turn_left": [KEY_Q], "turn_right": [KEY_E],
		"f1": [KEY_1], "f2": [KEY_2], "f3": [KEY_3], "f4": [KEY_4],
		"dodge": [KEY_SPACE], "soul": [KEY_TAB], "leave": [KEY_X],
		"release": [KEY_F], "focus": [KEY_G], "rest": [KEY_R],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["block", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
	var axes := {
		"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0], "up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
		"aim_left": [JOY_AXIS_RIGHT_X, -1.0], "aim_right": [JOY_AXIS_RIGHT_X, 1.0], "aim_up": [JOY_AXIS_RIGHT_Y, -1.0], "aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
		"turn_left": [JOY_AXIS_TRIGGER_LEFT, 1.0], "turn_right": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	}
	for a in axes:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_set_deadzone(a, 0.2)
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[a][0]
		jm.axis_value = axes[a][1]
		InputMap.action_add_event(a, jm)
	var pad := {
		"dodge": JOY_BUTTON_A, "attack": JOY_BUTTON_X, "soul": JOY_BUTTON_Y, "leave": JOY_BUTTON_B,
		"block": JOY_BUTTON_LEFT_SHOULDER, "release": JOY_BUTTON_RIGHT_SHOULDER,
		"f1": JOY_BUTTON_DPAD_UP, "f2": JOY_BUTTON_DPAD_RIGHT, "f3": JOY_BUTTON_DPAD_DOWN, "f4": JOY_BUTTON_DPAD_LEFT,
		"rest": JOY_BUTTON_START,
	}
	for a in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[a]
		InputMap.action_add_event(a, jb)


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.3):
		using_pad = true
	elif e is InputEventMouseMotion and e.relative.length() > 0.5:
		using_pad = false


## Where you're pointing in the world: the mouse, or the controller's pointer
## (the right stick pushes it out from the circle; it stays where it was left).
func pointer() -> Vector2:
	if not using_pad:
		return get_global_mouse_position()
	return formation_center() + _pad_off


func aim_stick() -> Vector2:
	return Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")


## At the bonfire (and after you all die): the party back on their feet in
## the circle, healed; every enemy back where it started.
func rest() -> void:
	for u in units:
		u.queue_free()
	units.clear()
	for c in get_children():
		if c is MissileScript:
			c.queue_free()
	circle = map.party_at
	leader = null
	released = false
	focus = null
	died = false
	_jump = {}
	for i in Data.PARTY.size():
		var u = _spawn("party", Data.PARTY[i], circle)
		u.position = slot_pos(u)
	for s in map.spawns:
		_spawn("enemy", s.kind, s.at)


func _spawn(team: String, kind: String, at: Vector2):
	var u = UnitScript.new()
	u.setup(self, team, kind, at)
	add_child(u)
	units.append(u)
	_lists()
	return u


## The party and who's still standing on each side, worked out once a frame
## (and when someone's added or dies) instead of every time they're asked for.
func _lists() -> void:
	_party = units.filter(func(u): return is_instance_valid(u) and u.team == "party")
	_alive = {"party": [], "enemy": []}
	for u in units:
		if is_instance_valid(u) and not u.dead:
			_alive[u.team].append(u)
	_slots.clear()


func party_units() -> Array:
	return _party


func opponents(u) -> Array:
	return _alive["enemy" if u.team == "party" else "party"]


# ── Formations ─────────────────────────────────────────────────────────────────

func formation_center() -> Vector2:
	return leader.position if leader != null else circle


func formation_angle() -> float:
	return circle_rot


## Where u stands in the formation: melee to the front and outside, ranged
## behind and inside. Offsets are (ahead, right) of the way it faces.
func slot_pos(u) -> Vector2:
	if _slots.has(u):
		return _slots[u]
	var p := _slot_pos(u)
	_slots[u] = p
	return p


func _slot_pos(u) -> Vector2:
	var melee: Array = []
	var back: Array = []
	for o in party_units():
		if o.dead or o == leader:
			continue
		(back if o.ranged() else melee).append(o)
	var group: Array = back if u.ranged() else melee
	var i := group.find(u)
	var n := group.size()
	var R: float = Data.CIRCLE.radius
	var off := Vector2.ZERO
	match formation:
		"ring":
			var ang := TAU * (float(i) + 0.5) / maxf(1.0, float(n))
			off = Vector2.from_angle(ang) * (R * 0.75 if not u.ranged() else R * 0.38)
		"line":  # one row across the front, one behind
			off = Vector2(8.0 if not u.ranged() else -12.0, (float(i) - (n - 1) * 0.5) * 12.0)
		"wedge":  # a point forward, opening back
			var side := 1.0 if i % 2 == 1 else -1.0
			var rank := float((i + 1) / 2)
			if u.ranged():
				off = Vector2(-8.0 - rank * 8.0, side * (4.0 + rank * 6.0))
			else:
				off = Vector2(16.0 - rank * 10.0, side * rank * 10.0)
		"column":  # two abreast, melee at the head
			var row := i / 2
			var base := 0 if not u.ranged() else (melee.size() + 1) / 2
			off = Vector2(18.0 - float(base + row) * 11.0, (float(i % 2) - 0.5) * 11.0)
	var c := formation_center()
	return map.reach_toward(c, c + off.rotated(circle_rot))


# ── Your controls ──────────────────────────────────────────────────────────────

## What the possessed one is told to do this frame (mouse aims).
func leader_intent() -> Dictionary:
	if scripted:
		var t := test.duplicate()
		test.attack = false
		test.dodge = false
		return t
	if died:
		return {"move": Vector2.ZERO, "aim": leader.position, "attack": false, "dodge": false, "block": false}
	var on_pads: bool = hud.touching()
	var mv := move_input()
	var aim := get_global_mouse_position()
	if touch:  # toward the last tap for a moment, then the way it's going
		var d: Vector2 = mv if mv.length() > 0.1 else Vector2.from_angle(leader.facing)
		aim = _tap_aim if _tap_t > 0.0 else leader.position + d.normalized() * PAD_AIM
	elif using_pad:  # the right stick aims; let go, it faces the way it's going
		var rs := aim_stick()
		var d: Vector2 = rs if rs.length() > 0.2 else (mv if mv.length() > 0.1 else Vector2.from_angle(leader.facing))
		aim = leader.position + d.normalized() * PAD_AIM
	var dodge := Input.is_action_just_pressed("dodge") or _ui_dodge
	var attack := (Input.is_action_just_pressed("attack") and not on_pads and not touch) or _ui_attack
	_ui_dodge = false
	_ui_attack = false
	return {
		"move": mv,
		"aim": aim,
		"attack": attack,
		"dodge": dodge,
		"block": (Input.is_action_pressed("block") and not on_pads) or hud.block_held(),
	}


## A finger on the play area (phones): in a body, attack toward it; as the
## circle, focus the enemy there - or rest, on the bonfire, if you're near it.
func tap(at: Vector2) -> void:
	if died:
		rest()
		return
	if leader != null:
		_tap_aim = at
		_tap_t = TAP_AIM_TIME
		_ui_attack = true
		return
	if _try_rest(at):
		return
	pick_focus(at, TAP_PICK)


## Rest, if the point is on the bonfire and you're near it.
func _try_rest(at: Vector2) -> bool:
	if at.distance_to(map.bonfire) < 12.0 and formation_center().distance_to(map.bonfire) < REST_NEAR:
		rest()
		return true
	return false


## WASD and the on-screen stick together.
func move_input() -> Vector2:
	return (Input.get_vector("left", "right", "up", "down") + hud.stick).limit_length(1.0)


## Your soul into the one of the party nearest the point.
func possess(near: Vector2) -> bool:
	var best = null
	var bd := INF
	for u in party_units():
		if u.dead or u == leader:
			continue
		var d: float = u.position.distance_to(near)
		if d < bd:
			bd = d
			best = u
	if best == null:
		return false
	_jump = {"from": formation_center(), "to": best, "t": 0.0}
	_slots.clear()
	if leader != null:
		leader.possessed = false
	leader = best
	leader.possessed = true
	return true


## Out of the body and back to the circle, where it stands.
func leave() -> void:
	if leader == null:
		return
	circle = leader.position
	_slots.clear()
	_jump = {"from": leader.position, "to": null, "t": 0.0}
	leader.possessed = false
	leader = null


## Dodge: in a body, that one does; as the circle, the whole party does -
## the way you're pushing, or back if you aren't. Each goes as soon as it's
## free (an attack under way finishes first).
func dodge() -> void:
	if leader != null:
		_ui_dodge = true
		return
	var mv: Vector2 = test.move if scripted else move_input()
	var d: Vector2 = mv if mv.length() > 0.1 else -Vector2.from_angle(circle_rot)
	for u in party_units():
		if not u.dead:
			u.ask_dodge(d)


## The enemy nearest the point, for them all to go for; none near: no focus.
func pick_focus(near: Vector2, within := 16.0) -> void:
	focus = null
	var bd := within
	for u in units:
		if u.team == "enemy" and not u.dead:
			var d: float = u.position.distance_to(near) - u.radius()
			if d < bd:
				bd = d
				focus = u


func set_formation(name_v: String) -> void:
	formation = name_v
	_slots.clear()


## Your soul into this one of the party; already in it: back out.
func soul_into(u) -> void:
	if u == leader:
		leave()
	elif not u.dead:
		possess(u.position)
		if leader != u:  # another stood nearer that point: this one exactly
			leader.possessed = false
			leader = u
			u.possessed = true
			_slots.clear()


func start() -> void:
	menu = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:  # a phone's back: in play, to the menu; on it, quit
		if menu:
			get_tree().quit()
		else:
			menu = true


func _unhandled_input(e: InputEvent) -> void:
	if scripted:
		return
	if menu:
		if e.is_action_pressed("ui_accept") or e.is_action_pressed("dodge") or e.is_action_pressed("rest"):
			start()
		return
	if died:
		if e.is_action_pressed("rest") or (e is InputEventMouseButton and e.pressed):
			rest()
		return
	var m := pointer()
	if leader == null and e.is_action_pressed("attack") and _try_rest(m):
		return
	for k in 4:
		if e.is_action_pressed("f%d" % (k + 1)):
			set_formation(Data.FORMATIONS[k])
	if e.is_action_pressed("soul"):
		possess(m)
	elif e.is_action_pressed("leave"):
		leave()
	elif e.is_action_pressed("release"):
		released = not released
	elif e.is_action_pressed("focus") or (leader == null and e.is_action_pressed("attack")):
		pick_focus(m, PAD_PICK if using_pad else 16.0)
	elif e.is_action_pressed("dodge") and leader == null:
		dodge()
	elif e.is_action_pressed("rest") and formation_center().distance_to(map.bonfire) < REST_NEAR:
		rest()


# ── Each frame ─────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	update_note -= delta
	hud.queue_redraw()
	if menu:
		return
	_tap_t -= delta
	_lists()
	map.new_frame()
	claims.clear()
	if focus != null and focus.dead:
		focus = null
	var turn: float = test.turn if scripted else Input.get_axis("turn_left", "turn_right")
	var dial: float = hud.take_turn()
	if leader == null and aim_stick().length() > 0.2:
		_pad_off = aim_stick() * PAD_REACH
	if not died:
		circle_rot = wrapf(circle_rot + turn * float(Data.CIRCLE.turn) * delta + dial, -PI, PI)
	if leader == null:
		var mv: Vector2 = (test.move + hud.stick) if scripted else move_input()
		if died:
			mv = Vector2.ZERO
		circle = map.push_out(circle + mv * float(Data.CIRCLE.speed) * delta, 6.0)
	else:
		circle = leader.position
	# bodies don't overlap: each pair pushed apart
	for i in units.size():
		var a = units[i]
		if a.dead:
			continue
		for j in range(i + 1, units.size()):
			var b = units[j]
			if b.dead:
				continue
			var d: Vector2 = b.position - a.position
			var min_d: float = a.radius() + b.radius()
			if d.length() < min_d and d.length() > 0.01:
				var push: Vector2 = d.normalized() * (min_d - d.length())
				var wa: float = b.radius() / min_d  # the bigger one moves less
				a.position -= push * wa
				b.position += push * (1.0 - wa)
	if not _jump.is_empty():
		_jump.t += delta
		if _jump.t >= JUMP_TIME:
			_jump = {}
	for s in _sparks:
		s[1] -= delta
	_sparks = _sparks.filter(func(s): return s[1] > 0.0)
	_slots.clear()  # the circle's moved: places from here
	cam.position = formation_center().round()
	fx.queue_redraw()


func on_death(u) -> void:
	_lists()
	if u.team != "party":
		return
	if u == leader:
		leave()
	if party_units().all(func(o): return o.dead):
		died = true


func shoot_arrow(src, a: Vector2, b: Vector2, dmg: float) -> void:
	var m = MissileScript.new()
	m.setup_arrow(self, src, a, b, dmg)
	add_child(m)


func shoot_bolt(src, a: Vector2, d: Vector2, dmg: float) -> void:
	var m = MissileScript.new()
	m.setup_bolt(self, src, a, d, dmg, float(src.atk.speed), float(src.atk.range))
	add_child(m)


func spark(at: Vector2) -> void:
	_sparks.append([at, 0.15])


# ── The circle, the bonfire, the focus, sparks, your soul flying ───────────────

func _draw_fx() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var b: Vector2 = map.bonfire.round()
	# a sword in a ring of ash, and the fire
	fx.draw_circle(b, 5.0, Color(0.16, 0.14, 0.13))
	fx.draw_line(b + Vector2(0, -7), b + Vector2(0, 2), Color(0.6, 0.6, 0.65))
	fx.draw_line(b + Vector2(-2, -5), b + Vector2(2, -5), Color(0.6, 0.6, 0.65))
	for k in 6:
		var a := float(k) * 1.7 + t * 3.0
		var p := b + Vector2(sin(a) * 2.5, -fmod(t * 9.0 + k * 1.3, 7.0)).round()
		fx.draw_rect(Rect2(p, Vector2.ONE), Color(1.0, 0.55 + 0.3 * sin(a), 0.15))
	# the circle: whole when they keep their places, broken when released;
	# the notch is the way the formation faces
	var c := formation_center().round()
	var R: float = Data.CIRCLE.radius
	var col := Data.SOUL if leader == null else Color(Data.SOUL, 0.45)
	if released:
		for k in 16:
			var a0 := TAU * k / 16.0
			fx.draw_arc(c, R, a0, a0 + TAU / 32.0, 3, col, -1.0)
	else:
		fx.draw_arc(c, R, 0.0, TAU, 40, col, -1.0)
	var f := Vector2.from_angle(circle_rot)
	fx.draw_line((c + f * (R - 3.0)).round(), (c + f * (R + 3.0)).round(), col)
	if leader == null:
		fx.draw_circle(c, 1.5, col)
	if focus != null:  # a mark over the one they go for
		var p: Vector2 = (focus.position + Vector2(0, -focus.radius() - 6.0)).round()
		for d in [Vector2(-2, -2), Vector2(-1, -1), Vector2(0, 0), Vector2(1, -1), Vector2(2, -2)]:
			fx.draw_rect(Rect2(p + d, Vector2.ONE), Color(0.95, 0.25, 0.2))
	for s in _sparks:
		var p: Vector2 = s[0].round()
		for d in [Vector2(-2, -1), Vector2(2, -2), Vector2(1, 2), Vector2(-1, 1)]:
			fx.draw_rect(Rect2(p + d, Vector2.ONE), Color(1.0, 0.9, 0.5))
	if not _jump.is_empty():
		var k: float = _jump.t / JUMP_TIME
		var to: Vector2 = _jump.to.position if _jump.to != null else circle
		var p: Vector2 = _jump.from.lerp(to, k) + Vector2(0, -sin(k * PI) * 12.0)
		fx.draw_circle(p.round(), 2.0, Data.SOUL)


# ── Updates (phones) ───────────────────────────────────────────────────────────

func _check_update() -> void:
	if http == null:
		http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_release)
	update_state = "checking"
	if http.request(Update.API, ["User-Agent: Warband", "Accept: application/vnd.github+json"]) != OK:
		update_state = "failed"


func _on_release(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var rel := {}
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		rel = Update.read_release(body.get_string_from_utf8())
	if rel.is_empty():
		update_state = "failed"
		return
	update_tag = rel.tag
	update_url = rel.url
	update_page = rel.page
	update_state = "new" if Update.newer(update_tag, Update.current()) else "latest"
	if update_state == "latest" and update_asked:
		update_note = 2.0
	update_asked = false


## Download the new APK in the game, then hand it to Android's installer.
func _download_update() -> void:
	if download == null:
		download = HTTPRequest.new()
		download.use_threads = true
		download.download_file = Update.APK
		add_child(download)
		download.request_completed.connect(_on_downloaded)
	update_state = "downloading"
	if download.request(update_url, ["User-Agent: Warband"]) != OK:
		update_state = "download_failed"


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(Update.APK):
		update_state = "download_failed"
		return
	update_state = "ready"
	Update.install()


func update_label() -> String:
	match update_state:
		"checking":
			return "CHECKING..."
		"latest":
			return "NO NEW VERSION" if update_note > 0.0 else "CHECK FOR UPDATES"
		"new":
			return "UPDATE TO " + update_tag
		"downloading":
			var size := download.get_body_size()
			if size > 0:
				return "DOWNLOADING %d" % (100 * download.get_downloaded_bytes() / size)
			return "DOWNLOADING..."
		"ready":
			return "INSTALL " + update_tag
		"download_failed":
			return "FAILED. RETRY"
	return "CHECK FOR UPDATES"


func update_tap() -> void:
	match update_state:
		"new", "download_failed":
			if OS.get_name() == "Android":
				_download_update()
			else:
				OS.shell_open(update_page)
		"ready":
			Update.install()
		"checking", "downloading":
			pass
		_:
			update_asked = true
			_check_update()
