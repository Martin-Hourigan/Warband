extends Node2D
## An arrow or a sorcerer's bolt. The arrow arcs up into the sky and comes
## down where it was aimed (its shadow runs along the ground below it); it
## hits whoever is there when it lands. The bolt flies straight and low into
## the first one in its way, or a wall.

const Data = preload("res://scripts/data.gd")

var main
var src
var kind := "arrow"
var dmg := 10.0
var from := Vector2.ZERO
var to := Vector2.ZERO
var dir := Vector2.RIGHT
var speed := 150.0
var range_left := 130.0
var t := 0.0
var flight := 1.0
var peak := 0.0
var height := 0.0
var landed := false
var _stick := 1.2


func setup_arrow(main_ref, src_ref, a: Vector2, b: Vector2, damage: float) -> void:
	main = main_ref
	src = src_ref
	kind = "arrow"
	from = a
	to = b
	dmg = damage
	flight = maxf(0.15, a.distance_to(b) / float(Data.ARROW.speed))
	peak = a.distance_to(b) * float(Data.ARROW.arc)
	position = a
	z_index = 5


func setup_bolt(main_ref, src_ref, a: Vector2, d: Vector2, damage: float, spd: float, rng: float) -> void:
	main = main_ref
	src = src_ref
	kind = "bolt"
	position = a
	dir = d
	dmg = damage
	speed = spd
	range_left = rng
	z_index = 5


func _physics_process(delta: float) -> void:
	t += delta
	if kind == "arrow":
		if landed:
			_stick -= delta
			if _stick <= 0.0:
				queue_free()
			return
		var k := minf(t / flight, 1.0)
		position = from.lerp(to, k)
		height = 4.0 * peak * k * (1.0 - k)
		if k >= 1.0:
			landed = true
			height = 0.0
			for o in main.opponents(src):
				if o.position.distance_to(to) <= float(Data.ARROW.hit) + o.radius():
					o.take_hit(dmg, src)
					queue_free()
					return
	else:
		var step := dir * speed * delta
		position += step
		range_left -= step.length()
		if range_left <= 0.0 or main.map.wall_at(position):
			queue_free()
			return
		for o in main.opponents(src):
			if o.position.distance_to(position) <= o.radius() + 2.0:
				o.take_hit(dmg, src)
				queue_free()
				return
	queue_redraw()


func _draw() -> void:
	if kind == "bolt":
		var glow := Color(0.6, 0.85, 1.0)
		draw_circle(Vector2.ZERO, 2.0, glow)
		draw_rect(Rect2((-dir * 4.0).round(), Vector2.ONE), glow.darkened(0.3))
		draw_rect(Rect2((-dir * 6.0).round(), Vector2.ONE), glow.darkened(0.5))
		return
	var g := (to - from).normalized()
	if landed:
		draw_line(Vector2.ZERO, (-g * 4.0).round(), Color(0.55, 0.4, 0.25))
		return
	# the shadow on the ground, then the arrow up in the air, tilted by its climb or fall
	draw_line((-g * 2.0).round(), (g * 2.0).round(), Color(0, 0, 0, 0.45))
	var k := minf(t / flight, 1.0)
	var climb := 4.0 * peak * (1.0 - 2.0 * k) / flight  # height per second
	var v := g * from.distance_to(to) / flight - Vector2(0, climb)
	var n := v.normalized()
	var up := Vector2(0, -height).round()
	draw_line(up - (n * 3.0).round(), up + (n * 3.0).round(), Color(0.75, 0.6, 0.4))
	draw_rect(Rect2(up + (n * 3.0).round(), Vector2.ONE), Color(0.9, 0.9, 0.95))
