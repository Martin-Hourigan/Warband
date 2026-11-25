extends Node2D
## The level as a tile grid (placeholder layout): the bonfire room, a room
## of hollows, a room of hollows with archers, the giant's arena (with two
## hollows of its own). Walls block movement;
## the party finds its way round them. Floor and walls are drawn from
## computed pixels.
## # wall, . floor, B bonfire, P the party, h hollow, a hollow archer,
## k knight, G giant.

const T := 16
const ROWS := [
	"####################################################",
	"#.........#########.............####################",
	"#.........#########.............####################",
	"#....B....#########...h.....h...####################",
	"#....P..........................####################",
	"#...............................####################",
	"#.........#########......h......######.............#",
	"###################.............######.............#",
	"########################..############.............#",
	"########################..############..h..........#",
	"########################..############.............#",
	"#############....................#####.............#",
	"#############....................#####.............#",
	"#############.....h.......h......#####.............#",
	"#############................................G.....#",
	"#############.........h............................#",
	"#############....................#####.............#",
	"#############...a............a...#####.............#",
	"#############....................#####.............#",
	"######################################.............#",
	"######################################..h..........#",
	"######################################.............#",
	"######################################.............#",
	"######################################.............#",
	"####################################################",
]

var w := 0
var h := 0
var solid := PackedByteArray()
var bonfire := Vector2.ZERO
var party_at := Vector2.ZERO
var spawns: Array = []  # {kind, at}
var _flow := {}  # target tile -> distances, for this frame


func build() -> void:
	h = ROWS.size()
	for r in ROWS:
		w = maxi(w, r.length())
	solid.resize(w * h)
	for y in h:
		var row: String = ROWS[y]
		for x in w:
			var c := row[x] if x < row.length() else "#"
			solid[y * w + x] = 1 if c == "#" else 0
			var at := Vector2(x + 0.5, y + 0.5) * T
			match c:
				"B":
					bonfire = at
				"P":
					party_at = at
				"h":
					spawns.append({"kind": "hollow", "at": at})
				"k":
					spawns.append({"kind": "knight", "at": at})
				"a":
					spawns.append({"kind": "hollow_bow", "at": at})
				"G":
					spawns.append({"kind": "giant", "at": at})
	queue_redraw()


func size_px() -> Vector2:
	return Vector2(w, h) * T


func wall(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return true
	return solid[y * w + x] == 1


func wall_at(p: Vector2) -> bool:
	return wall(int(floorf(p.x / T)), int(floorf(p.y / T)))


## Push a unit out of any wall it overlaps.
func collide(u) -> void:
	u.position = push_out(u.position, u.radius())


func push_out(p: Vector2, r: float) -> Vector2:
	for y in range(int(floorf((p.y - r) / T)), int(floorf((p.y + r) / T)) + 1):
		for x in range(int(floorf((p.x - r) / T)), int(floorf((p.x + r) / T)) + 1):
			if not wall(x, y):
				continue
			var near := Vector2(clampf(p.x, x * T, (x + 1) * T), clampf(p.y, y * T, (y + 1) * T))
			var d := p - near
			if d.length() < r:
				if d.length() < 0.01:
					d = Vector2(0, -1)
				p = near + d.normalized() * r
	return p


## As far from a toward b as is open (a straight line, no wall in between).
func reach_toward(a: Vector2, b: Vector2) -> Vector2:
	if line_clear(a, b):
		return b
	var lo := 0.0
	var hi := 1.0
	for i in 6:
		var m := (lo + hi) * 0.5
		if line_clear(a, a.lerp(b, m)):
			lo = m
		else:
			hi = m
	return a.lerp(b, lo)


func line_clear(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 4.0) + 1
	for i in n + 1:
		if wall_at(a.lerp(b, float(i) / n)):
			return false
	return true


## Clear for a body r wide, not just a point: its middle and both edges.
func line_clear_wide(a: Vector2, b: Vector2, r: float) -> bool:
	var side := (b - a).normalized().orthogonal() * r
	return line_clear(a, b) and line_clear(a + side, b + side) and line_clear(a - side, b - side)


func new_frame() -> void:
	_flow.clear()


## Which way to walk from a to reach b: straight if nothing's in the way,
## otherwise along the shortest path over the tiles.
func dir_to(a: Vector2, b: Vector2) -> Vector2:
	if a.distance_to(b) < 1.0:
		return Vector2.ZERO
	if line_clear_wide(a, b, 5.0) or (int(a.x / T) == int(b.x / T) and int(a.y / T) == int(b.y / T)):
		return (b - a).normalized()
	var tx := int(b.x / T)
	var ty := int(b.y / T)
	var key := ty * w + tx
	if not _flow.has(key):
		_flow[key] = _bfs(tx, ty)
	var dist: PackedInt32Array = _flow[key]
	var ax := int(a.x / T)
	var ay := int(a.y / T)
	var best := Vector2i(ax, ay)
	var bd := dist[ay * w + ax] if not wall(ax, ay) else 1 << 20
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var nx: int = ax + d.x
		var ny: int = ay + d.y
		if wall(nx, ny) or (d.x != 0 and d.y != 0 and (wall(ax + d.x, ay) or wall(ax, ay + d.y))):
			continue
		if dist[ny * w + nx] < bd:
			bd = dist[ny * w + nx]
			best = Vector2i(nx, ny)
	var goal := (Vector2(best) + Vector2(0.5, 0.5)) * T
	return (goal - a).normalized() if goal.distance_to(a) > 0.5 else (b - a).normalized()


func _bfs(tx: int, ty: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(1 << 20)
	if wall(tx, ty):
		return dist
	dist[ty * w + tx] = 0
	var q: Array[Vector2i] = [Vector2i(tx, ty)]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if wall(n.x, n.y) or dist[n.y * w + n.x] <= dist[c.y * w + c.x] + 1:
				continue
			dist[n.y * w + n.x] = dist[c.y * w + c.x] + 1
			q.append(n)
	return dist


# ── Drawing ────────────────────────────────────────────────────────────────────
# The whole floor is painted into one image when the map is built and drawn
# as a single texture after that (cheap on phones).

var _tex: ImageTexture


func _bake() -> void:
	var img := Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var floor_c := Color(0.2, 0.19, 0.18)
	img.fill(Color(0.07, 0.07, 0.08))
	for y in h:
		for x in w:
			var ox := x * T
			var oy := y * T
			if wall(x, y):
				# the wall's top edge catches light where it meets floor
				if not wall(x, y + 1):
					img.fill_rect(Rect2i(ox, oy + T - 3, T, 3), Color(0.16, 0.15, 0.15))
					img.fill_rect(Rect2i(ox, oy + T - 3, T, 1), Color(0.26, 0.25, 0.24))
				continue
			# flagstones, offset each row, with worn pixels
			img.fill_rect(Rect2i(ox, oy, T, T), floor_c.lightened(rng.randf() * 0.06))
			var seam := floor_c.darkened(0.18)
			img.fill_rect(Rect2i(ox + (8 if y % 2 == 1 else 0), oy, 1, T), seam)
			img.fill_rect(Rect2i(ox, oy, T, 1), seam)
			for k in 5:
				var c := floor_c.lightened(0.15) if rng.randf() < 0.5 else floor_c.darkened(0.2)
				img.set_pixel(ox + rng.randi_range(1, T - 2), oy + rng.randi_range(1, T - 2), c)
			if wall(x, y - 1):  # the shadow under a wall
				for yy in 2:
					for xx in T:
						img.set_pixel(ox + xx, oy + yy, img.get_pixel(ox + xx, oy + yy).lerp(Color.BLACK, 0.35))
	_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	if _tex == null:
		_bake()
	draw_texture(_tex, Vector2.ZERO)
