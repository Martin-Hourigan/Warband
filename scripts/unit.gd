extends Node2D
## One fighter, seen from straight above: the party's (sword and shield,
## two-handed, bow, sorcerer) or an enemy's (hollow, hollow archer, knight,
## the giant). Everyone has a basic attack and a dodge; shields block too.
## The possessed one (your soul is in it) is yours to drive, with the
## enhanced moveset (faster, a chain of attacks). The rest of the party keep
## their places in the formation, round the circle you move (or round the one
## you're in), and attack anything that comes in range; released, they go
## after enemies themselves, spread out; given a focus, they all go for it.
## Drawn from computed shapes at the base resolution, so every pixel sits on
## the grid.

const Data = preload("res://scripts/data.gd")

var main
var team := "party"
var kind := "sword"
var def := {}
var atk := {}  # the attack it's on (a boss has several)
var hp := 1.0
var dead := false
var possessed := false
var facing := 0.0  # radians, 0 = right
var state := "idle"  # idle, windup, active, recover, dodge, stagger
var state_t := 0.0
var blocking := false
var combo := 0
var attacks := 0  # wind-ups started (the party reacts to each one once)
var moving := false
var walk_t := 0.0
var flash_t := 0.0
var home := Vector2.ZERO
var target = null  # what it's going for
var _buffer_t := 0.0  # a press of attack, remembered for a moment
var _aim := Vector2.ZERO
var _dodge_dir := Vector2.ZERO
var _dodge_cool := 0.0
var _dodge_buf := false  # a dodge asked for: it goes as soon as it can (never cutting an attack short)
var _dodge_buf_t := 0.0  # ...and is forgotten if it still can't after this long, standing
var _dodge_buf_dir := Vector2.ZERO
var _cool := 0.0  # AI: wait before attacking again
var _block_t := 0.0  # AI: holding the shield up
var _threat := Vector2.ZERO
var _poise := 0.0
var _poise_t := 0.0
var _reacted := {}


func setup(main_ref, team_v: String, kind_v: String, at: Vector2) -> void:
	main = main_ref
	team = team_v
	kind = kind_v
	def = (Data.UNITS if team == "party" else Data.ENEMIES)[kind]
	atk = def.attack if def.has("attack") else def.attacks[0]
	hp = float(def.hp)
	position = at
	home = at
	facing = -PI * 0.5


func radius() -> float:
	return float(def.radius)


func ranged() -> bool:
	return atk.kind != "melee"


func _to(s: String) -> void:
	state = s
	state_t = 0.0


# ── Each frame ─────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	modulate = Color(4, 4, 4) if flash_t > 0.0 else Color.WHITE
	if dead or main.menu:
		return
	# an enemy far from you, at home with nothing to do: asleep till you come near
	if team == "enemy" and state == "idle" and position.distance_squared_to(home) < 16.0 			and position.distance_squared_to(main.formation_center()) > main.AWAKE * main.AWAKE:
		return
	flash_t -= delta
	_dodge_cool -= delta
	_cool -= delta
	_buffer_t -= delta
	_block_t -= delta
	_poise_t -= delta
	if _poise_t <= 0.0:
		_poise = 0.0
	state_t += delta
	var it: Dictionary = main.leader_intent() if possessed else _think()
	if it.attack and (possessed or state == "idle"):  # the AI doesn't line up its next attack mid-attack
		_buffer_t = 0.3
	if it.dodge:
		ask_dodge(it.move)
	if state == "idle":
		_dodge_buf_t -= delta
		if _dodge_buf_t <= 0.0:
			_dodge_buf = false
	var speed := float(def.speed) * (float(Data.LEADER.speed) if possessed else 1.0)
	var mv := Vector2.ZERO
	var turn := 14.0 if possessed else 7.0
	if def.has("attacks"):
		turn = 2.5
	match state:
		"idle":
			blocking = it.block and def.get("shield", false)
			if _dodge_buf and _dodge_cool <= 0.0:
				_start_dodge(it.move)
			elif _buffer_t > 0.0 and not blocking:
				if it.has("which"):
					atk = it.which
				_start_attack(it.aim)
			else:
				mv = it.move * speed * (float(Data.BLOCK.move) if blocking else 1.0)
		"windup":
			turn *= 0.3
			_aim = it.aim
			if state_t >= float(atk.windup):
				_to("active")
				_strike()
		"active":
			turn = 0.0
			if state_t >= float(atk.active):
				_to("recover")
		"recover":
			turn = 0.0
			if possessed and not _dodge_buf and _buffer_t > 0.0 and combo < Data.LEADER.combo.size() - 1 and state_t >= float(atk.recover) * 0.3:
				combo += 1
				_start_attack(it.aim, true)
			elif state_t >= float(atk.recover):
				combo = 0
				_to("idle")
				if def.has("cool"):
					_cool = randf_range(def.cool[0], def.cool[1])
				else:
					_cool = 0.3
		"dodge":
			turn = 0.0
			mv = _dodge_dir * float(Data.DODGE.distance) / float(Data.DODGE.time)
			if state_t >= float(Data.DODGE.time):
				_to("idle")
				_dodge_cool = float(Data.DODGE.cool)
		"stagger":
			turn = 0.0
			if state_t >= Data.STAGGER:
				_to("idle")
	if state != "idle":
		blocking = false
	var want: Vector2 = it.aim - position
	if want.length() > 1.0 and turn > 0.0:
		facing = rotate_toward(facing, want.angle(), turn * delta)
	position += mv * delta
	main.map.collide(self)
	moving = mv.length() > 1.0
	if moving:
		walk_t += delta
	if position.distance_squared_to(main.cam.position) < 400.0 * 400.0:  # only redrawn near the screen
		queue_redraw()


## Dodge (the way given, or the way it's going): now if it's free, or the
## moment the attack it's in is over.
func ask_dodge(dir: Vector2) -> void:
	_dodge_buf = true
	_dodge_buf_t = 0.3
	_dodge_buf_dir = dir


func _start_dodge(move: Vector2) -> void:
	var d := _dodge_buf_dir
	if possessed and move.length() > 0.1:  # yours goes the way you're pushing now
		d = move
	if d.length() < 0.1:
		d = move if move.length() > 0.1 else Vector2.from_angle(facing)
	_dodge_buf = false
	_dodge_dir = d.normalized()
	_to("dodge")


func _start_attack(aim: Vector2, chained := false) -> void:
	_buffer_t = 0.0
	if not chained:
		combo = 0
	_aim = aim
	attacks += 1
	_to("windup")


## Inside the attack's shape right now? arc: in reach and in front; ring: in
## reach all round; line: in a strip straight ahead.
func in_shape(o) -> bool:
	var to: Vector2 = o.position - position
	var r: float = o.radius()
	match atk.get("shape", "arc"):
		"ring":
			return to.length() <= float(atk.reach) + r
		"line":
			var f := Vector2.from_angle(facing)
			var along := to.dot(f)
			return along >= 0.0 and along <= float(atk.reach) + r and absf(to.dot(f.orthogonal())) <= float(atk.width) * 0.5 + r
	if to.length() > float(atk.reach) + r:
		return false
	return to.length() <= r or absf(rad_to_deg(angle_difference(facing, to.angle()))) <= float(atk.arc) * 0.5


## The attack lands: melee hits everything in its shape; a bow looses an
## arrow at the aim; a sorcerer sends a bolt the way it faces.
func _strike() -> void:
	var dmg := float(atk.damage) * (float(Data.LEADER.combo[combo]) if possessed else 1.0)
	match atk.kind:
		"melee":
			for o in main.opponents(self):
				if in_shape(o):
					o.take_hit(dmg, self)
		"arrow":
			var to: Vector2 = _aim - position
			if to.length() > float(atk.range):
				to = to.normalized() * float(atk.range)
			main.shoot_arrow(self, position, position + to, dmg)
		"bolt":
			main.shoot_bolt(self, position + Vector2.from_angle(facing) * radius(), Vector2.from_angle(facing), dmg)


## Hit by src. Returns true if it hurt (not dodged or blocked).
func take_hit(dmg: float, src) -> bool:
	if dead:
		return false
	if state == "dodge" and state_t < float(Data.DODGE.iframes):
		return false
	if blocking and src != null:
		var to: Vector2 = src.position - position
		if absf(rad_to_deg(angle_difference(facing, to.angle()))) <= float(Data.BLOCK.arc) * 0.5:
			position -= to.normalized() * 2.0
			main.spark(position + Vector2.from_angle(facing) * (radius() + 1.0))
			return false
	hp -= dmg
	flash_t = 0.1
	_poise += dmg
	_poise_t = 2.0
	if hp <= 0.0:
		_die()
		return true
	if _poise >= float(def.poise) and state != "dodge":
		_poise = 0.0
		_to("stagger")
	return true


func _die() -> void:
	dead = true
	hp = 0.0
	blocking = false
	state = "dead"
	z_index = -1
	queue_redraw()
	main.on_death(self)


# ── Thinking: the rest of the party, and enemies ───────────────────────────────

func _think() -> Dictionary:
	var it := {"move": Vector2.ZERO, "aim": position + Vector2.from_angle(facing) * 10.0, "attack": false, "dodge": false, "block": false}
	if team == "party":
		_think_party(it)
	else:
		_think_enemy(it)
	return it


func _think_party(it: Dictionary) -> void:
	_react(it)
	if _block_t > 0.0:
		it.block = true
		it.aim = _threat
		return
	var spot: Vector2 = main.slot_pos(self)
	var held: bool = not main.released and (main.focus == null or main.focus.dead)
	target = null
	if main.focus != null and not main.focus.dead:
		target = main.focus
	elif main.released:
		var best := Data.RELEASED_SIGHT
		for o in main.opponents(self):
			var score: float = position.distance_to(o.position) + Data.SPREAD * main.claims.get(o, 0)
			if position.distance_to(o.position) < Data.RELEASED_SIGHT and score < best:
				best = score
				target = o
	else:  # in formation: only what comes within reach of its place
		var best := INF
		for o in main.opponents(self):
			var d: float
			if ranged():
				d = spot.distance_to(o.position) - float(atk.range)
			else:
				d = spot.distance_to(o.position) - o.radius() - float(atk.reach) - Data.STEP_OUT
			if d <= 0.0 and d < best:
				best = d
				target = o
	if target != null:
		main.claims[target] = main.claims.get(target, 0) + 1
		if not held:
			_fight(it, target, false)
			return
		# in formation its place comes first: it fights only from near it
		if _fight_held(it, target, spot):
			return
	if position.distance_to(spot) > 2.0:
		it.move = main.map.dir_to(position, spot)
		if position.distance_to(spot) < 10.0:
			it.move *= position.distance_to(spot) / 10.0
		it.aim = position + it.move * 10.0
	else:
		it.aim = position + Vector2.from_angle(main.formation_angle()) * 10.0


## Held in formation: melee steps out toward o, never more than STEP_OUT from
## its place; ranged shoot only from their place (within HOLD_NEAR), with a
## clear line for a bolt. Returns false if it can't fight from here: then it
## goes back to its place.
func _fight_held(it: Dictionary, o, spot: Vector2) -> bool:
	var d: float = position.distance_to(o.position)
	if atk.kind == "melee":
		if position.distance_to(spot) > Data.STEP_OUT:
			return false
		it.aim = o.position
		if d <= float(atk.reach) + o.radius() - 3.0:
			if _cool <= 0.0:
				it.attack = true
			return true
		var step: Vector2 = main.map.dir_to(position, o.position)
		if (position + step * 4.0).distance_to(spot) > Data.STEP_OUT:
			return false
		it.move = step
		return true
	if position.distance_to(spot) > Data.HOLD_NEAR:
		return false
	if d > float(atk.range) or (atk.kind == "bolt" and not main.map.line_clear(position, o.position)):
		return false
	it.aim = o.position
	if _cool <= 0.0:
		it.attack = true
	return true


## Go for o: melee closes in and swings; ranged keeps its distance and shoots
## (held in formation, ranged don't go closer).
func _fight(it: Dictionary, o, held: bool) -> void:
	var to: Vector2 = o.position - position
	var d := to.length()
	it.aim = o.position
	if atk.kind == "melee":
		if d > float(atk.reach) + o.radius() - 3.0:
			it.move = main.map.dir_to(position, o.position)
		elif _cool <= 0.0:
			it.attack = true
		return
	var clear: bool = main.map.line_clear(position, o.position)
	if d > float(atk.range) * 0.9 or (atk.kind == "bolt" and not clear):
		if not held:
			it.move = main.map.dir_to(position, o.position)
	elif d < float(atk.range) * 0.3 and not held:
		it.move = -to.normalized()
	elif _cool <= 0.0:
		it.attack = true


func _think_enemy(it: Dictionary) -> void:
	target = null
	var best := float(def.aggro)
	for o in main.opponents(self):
		var d: float = o.position.distance_to(position)
		if d < best:
			best = d
			target = o
	if target != null and position.distance_to(home) > Data.LEASH:
		target = null
	if target == null:
		if position.distance_to(home) > 4.0:
			it.move = main.map.dir_to(position, home)
			it.aim = position + it.move * 10.0
		return
	if not def.has("attacks"):
		_fight(it, target, false)
		return
	# a boss: of the attacks that suit how far off it is, any one
	var gap: float = position.distance_to(target.position) - radius() - target.radius()
	it.aim = target.position
	var can: Array = def.attacks.filter(func(a): return gap >= a.use[0] and gap <= a.use[1])
	if can.is_empty():
		it.move = main.map.dir_to(position, target.position)
	elif _cool <= 0.0 and state == "idle":
		it.attack = true
		it.which = can.pick_random()


## A wind-up aimed at it: a shield comes up, anything else may dodge away.
func _react(it: Dictionary) -> void:
	for o in main.opponents(self):
		if o.state != "windup" or o.atk.kind != "melee":
			continue
		var key := "%d:%d" % [o.get_instance_id(), o.attacks]
		if _reacted.has(key):
			continue
		if not o.in_shape(self) and position.distance_to(o.position) > float(o.atk.reach) + radius() + 6.0:
			continue
		_reacted[key] = true
		if def.get("shield", false) and o.atk.get("shape", "arc") != "ring":
			_block_t = float(o.atk.windup) + 0.3
			_threat = o.position
		elif randf() < Data.AI_DODGE:
			it.dodge = true
			it.move = (position - o.position).normalized()


# ── Drawing ────────────────────────────────────────────────────────────────────

func _disc(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c.round(), r, col)


func _line(a: Vector2, b: Vector2, col: Color, w := -1.0) -> void:
	draw_line(a.round(), b.round(), col, w)


## The weapon's angle from facing: resting, drawn back in the wind-up, swept
## across as it lands, back to rest.
func _swing() -> float:
	if not atk.has("rest"):
		return 0.0
	match state:
		"windup":
			return lerpf(atk.rest, atk.back, clampf(state_t / float(atk.windup), 0.0, 1.0))
		"active":
			return lerpf(atk.back, atk.end, clampf(state_t / float(atk.active), 0.0, 1.0))
		"recover":
			return lerpf(atk.end, atk.rest, clampf(state_t / float(atk.recover), 0.0, 1.0))
	return atk.rest


func _draw() -> void:
	var R := radius()
	var f := Vector2.from_angle(facing)
	var s := f.rotated(PI * 0.5)  # its right
	var cloth: Color = def.cloth
	var head: Color = def.head
	if dead:
		_disc(-f * 2.0, R, cloth.darkened(0.55))
		_disc(-f * 2.0 + f * R * 0.6, R * 0.45, head.darkened(0.5))
		return
	var k := clampf(state_t / float(atk.windup), 0.0, 1.0) if state == "windup" else 0.0
	if kind == "giant" and state == "windup":  # the ground it's about to hit, darkening
		_area(Color(0.5, 0.05, 0.03, 0.12 + 0.2 * k))
	if possessed:
		draw_arc(Vector2.ZERO, R + 3.0, 0.0, TAU, 20, Data.SOUL, -1.0)
	var steel := Color(0.85, 0.86, 0.9)
	var wood := Color(0.48, 0.32, 0.18)
	if moving or state == "dodge":
		var step := sin(walk_t * 16.0) * 2.0 * R / 5.0
		var foot := maxf(1.0, R / 5.0)
		_disc(s * R * 0.4 + f * step, foot, cloth.darkened(0.5))
		_disc(-s * R * 0.4 - f * step, foot, cloth.darkened(0.5))
	var w := Vector2.from_angle(facing + _swing())
	var body := R
	if kind == "giant" and atk.name == "stomp" and state == "windup":
		body = R + 2.0 * k  # rising up on one foot
	_disc(Vector2.ZERO, body, cloth)
	_disc(Vector2(-1, -1) * R * 0.3, body * 0.55, cloth.lightened(0.15))
	match kind:
		"sword", "hollow":
			var hand := s * (R - 1.0) + f
			var blade := float(atk.get("blade", 8.0))
			var bc := steel if kind == "sword" else Color(0.55, 0.45, 0.35)
			_line(hand, hand + w * blade, bc)
			_line(hand + w + w.orthogonal() * 1.5, hand + w - w.orthogonal() * 1.5, Color(0.75, 0.6, 0.25))
			if def.get("shield", false):
				var c := -s * R + f
				if blocking:
					c = f * (R + 1.0)
					_line(c - s * 4.0, c + s * 4.0, wood, 2.0)
					_disc(c + f * 0.5, 0.5, steel)
				else:
					_line(c - f * 3.0, c + f * 3.0, wood, 2.0)
		"great", "knight":
			var hand := f * (R - 1.0) + s * 1.0
			var blade := float(atk.get("blade", 13.0))
			var bc := steel if kind == "great" else Color(0.25, 0.25, 0.28)
			_line(hand, hand + w * blade, bc, 2.0)
			_line(hand + w * 1.5 + w.orthogonal() * 2.0, hand + w * 1.5 - w.orthogonal() * 2.0, Color(0.7, 0.55, 0.25))
		"giant":  # a great club in the right hand, a fist on the left
			var hand := s * (R - 2.0) + f * 2.0
			_line(hand, hand + w * 30.0, Color(0.36, 0.26, 0.16), 4.0)
			_disc(hand + w * 28.0, 4.0, Color(0.3, 0.22, 0.14))
			_disc(hand, 3.0, head)
			_disc(-s * (R - 2.0) + f * 4.0, 3.0, head)
		"bow", "hollow_bow":
			var c := f * (R - 2.0)
			draw_arc(c.round(), 5.0, facing - 1.1, facing + 1.1, 7, wood, -1.0)
			var e1 := c + Vector2.from_angle(facing - 1.1) * 5.0
			var e2 := c + Vector2.from_angle(facing + 1.1) * 5.0
			var mid := (e1 + e2) * 0.5 - f * 4.0 * k
			_line(e1, mid, Color(0.9, 0.9, 0.8))
			_line(mid, e2, Color(0.9, 0.9, 0.8))
			if state == "windup":
				_line(mid, mid + f * 8.0, Color(0.75, 0.6, 0.4))
		"sorcerer":
			var hand := s * (R - 1.0)
			_line(hand - f * 3.0, hand + f * 7.0, wood)
			_disc(hand + f * 7.0, 1.0 + 2.0 * k, Color(0.6, 0.85, 1.0))
	_disc(f * R * 0.2, R * 0.55, head)
	draw_rect(Rect2((f * R * 0.2 + Vector2(-1, -1) * R * 0.2).round(), Vector2.ONE), head.lightened(0.35))
	match kind:
		"bow", "sorcerer", "hollow_bow":  # the hood's point at the back
			_disc(f * R * 0.2 - f * R * 0.55, 1.0, head)
		"knight":  # a red plume
			_line(f * 2.0, -f * (R - 1.0), Color(0.7, 0.12, 0.1), 2.0)
	if state == "active" and atk.kind == "melee":
		_area(Color(1, 1, 1, 0.75), true)
	if possessed:
		var t := Time.get_ticks_msec() / 1000.0
		var top := Vector2(0, -R - 4.0)
		_disc(top, 1.5, Data.SOUL)
		draw_rect(Rect2((top + Vector2(0, -2.0 - floorf(fmod(t * 6.0, 2.0)))).round(), Vector2.ONE), Data.SOUL)


## The attack's shape on the ground: filled (a boss's wind-up) or its edge (as it lands).
func _area(col: Color, edge := false) -> void:
	var reach := float(atk.reach)
	match atk.get("shape", "arc"):
		"ring":
			if edge:
				draw_arc(Vector2.ZERO, reach, 0.0, TAU, 24, col, -1.0)
			else:
				draw_circle(Vector2.ZERO, reach, col)
		"line":
			var f := Vector2.from_angle(facing)
			var hw := f.orthogonal() * float(atk.width) * 0.5
			var pts := PackedVector2Array([hw, f * reach + hw, f * reach - hw, -hw])
			if edge:
				pts.append(hw)
				draw_polyline(pts, col, -1.0)
			else:
				draw_colored_polygon(pts, col)
		_:
			var half := deg_to_rad(float(atk.arc)) * 0.5
			if edge:
				draw_arc(Vector2.ZERO, reach, facing - half, facing + half, 14, col, -1.0)
			else:
				var pts := PackedVector2Array([Vector2.ZERO])
				for i in 13:
					pts.append(Vector2.from_angle(facing - half + 2.0 * half * i / 12.0) * reach)
				draw_colored_polygon(pts, col)
