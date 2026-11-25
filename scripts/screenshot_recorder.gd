extends Node
## Drop this into any Godot project as an autoload (e.g. ScreenshotRecorder).
## Inert in normal play. Activated by CLI args.
##
## Project-side setup:
##   1. Copy this file into your project (e.g. res://scripts/screenshot_recorder.gd)
##   2. Project Settings → Autoload, add it with name "ScreenshotRecorder"
##
## CLI args (any order, any combination):
##   --shot <path>              capture at default delay (see --shot-delay)
##   --shot <path>@<seconds>    capture at this absolute time since load
##   --shot-delay <seconds>     default for bare --shot (defaults to 2.0)
##   --press <key>@<seconds>    tap a key (down, brief, up). Key = Godot Key-enum
##                              name (Tab, Escape, Space, A, 1, …)
##   --click <btn>@<seconds>    click a mouse button: left | right | middle
##   --hold <target>@<down>:<up>  HOLD a key or mouse button DOWN from <down> to
##                              <up> seconds (stays pressed across that window, so
##                              a --shot in between sees it held). <target> is a
##                              Key-enum name (Space, Shift, F, …) OR a mouse
##                              token: mouse_left | mouse_right | mouse_middle.
##   --mouse <x>,<y>@<seconds>  move the cursor to viewport pixel (x,y) at <time>
##                              so held-button aim / hover lands where you want.
##
## Multiple actions queue a timeline, sorted by time and executed in order. The
## process exits after the last action + a small grace period.
##
## Examples:
##   --shot menu.png
##   --mouse 900,300@0.5 --hold mouse_left@1.0:2.0 --shot beam.png@1.5
##   --hold Shift@1.0:3.0 --shot sprint.png@2.0
##   --press Tab@1.0 --shot post.png@1.5

var _actions: Array = []
var _mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	_mouse_pos = Vector2(get_viewport().get_visible_rect().size) * 0.5
	_parse_args()
	if _actions.is_empty():
		return
	_actions.sort_custom(_action_cmp)
	_run_timeline()

# ── Arg parsing ────────────────────────────────────────────────────────────────

func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	var default_shot_delay: float = 2.0
	var deferred_shots: Array = []

	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--shot-delay" and i + 1 < args.size():
			default_shot_delay = float(args[i + 1])
			i += 2
			continue
		if arg == "--shot" and i + 1 < args.size():
			var parsed: Dictionary = _parse_at(args[i + 1])
			if parsed["has_time"]:
				_actions.append({"time": parsed["time"], "kind": "shot", "value": parsed["value"]})
			else:
				deferred_shots.append(parsed["value"])
			i += 2
			continue
		if arg == "--press" and i + 1 < args.size():
			var parsed_p: Dictionary = _parse_at(args[i + 1])
			if not parsed_p["has_time"]:
				push_error("[recorder] --press requires Key@seconds: " + args[i + 1])
			else:
				_actions.append({"time": parsed_p["time"], "kind": "press", "value": parsed_p["value"]})
			i += 2
			continue
		if arg == "--click" and i + 1 < args.size():
			var parsed_c: Dictionary = _parse_at(args[i + 1])
			if not parsed_c["has_time"]:
				push_error("[recorder] --click requires btn@seconds: " + args[i + 1])
			else:
				_actions.append({"time": parsed_c["time"], "kind": "click", "value": parsed_c["value"]})
			i += 2
			continue
		if arg == "--hold" and i + 1 < args.size():
			_parse_hold(args[i + 1])
			i += 2
			continue
		if arg == "--mouse" and i + 1 < args.size():
			_parse_mouse(args[i + 1])
			i += 2
			continue
		i += 1

	# Apply default delay to bare --shot args
	for p in deferred_shots:
		_actions.append({"time": default_shot_delay, "kind": "shot", "value": p})

func _parse_at(s: String) -> Dictionary:
	var idx: int = s.rfind("@")
	if idx < 0:
		return {"has_time": false, "value": s, "time": 0.0}
	var lhs: String = s.substr(0, idx)
	var rhs: String = s.substr(idx + 1)
	if not rhs.is_valid_float():
		return {"has_time": false, "value": s, "time": 0.0}
	return {"has_time": true, "value": lhs, "time": float(rhs)}

# --hold <target>@<down>:<up> → a down action at <down> and an up action at <up>.
func _parse_hold(spec: String) -> void:
	var at: int = spec.rfind("@")
	if at < 0:
		push_error("[recorder] --hold requires target@down:up: " + spec)
		return
	var target: String = spec.substr(0, at)
	var times: PackedStringArray = spec.substr(at + 1).split(":")
	if times.size() != 2 or not times[0].is_valid_float() or not times[1].is_valid_float():
		push_error("[recorder] --hold requires target@down:up: " + spec)
		return
	var t_down: float = float(times[0])
	var t_up: float = float(times[1])
	var is_mouse: bool = target.begins_with("mouse_")
	_actions.append({"time": t_down, "kind": ("mouse_down" if is_mouse else "key_down"), "value": target})
	_actions.append({"time": t_up, "kind": ("mouse_up" if is_mouse else "key_up"), "value": target})

# --mouse <x>,<y>@<seconds> → move the cursor at <seconds>.
func _parse_mouse(spec: String) -> void:
	var at: int = spec.rfind("@")
	var coords: String = spec if at < 0 else spec.substr(0, at)
	var t: float = 0.0
	if at >= 0 and spec.substr(at + 1).is_valid_float():
		t = float(spec.substr(at + 1))
	var xy: PackedStringArray = coords.split(",")
	if xy.size() != 2 or not xy[0].is_valid_float() or not xy[1].is_valid_float():
		push_error("[recorder] --mouse requires x,y@seconds: " + spec)
		return
	_actions.append({"time": t, "kind": "mouse_move", "value": Vector2(float(xy[0]), float(xy[1]))})

func _action_cmp(a: Dictionary, b: Dictionary) -> bool:
	return float(a["time"]) < float(b["time"])

# ── Timeline ───────────────────────────────────────────────────────────────────

func _run_timeline() -> void:
	print("[recorder] timeline (%d action(s)):" % _actions.size())
	for a in _actions:
		print("  t=%.2fs  %-10s  %s" % [a["time"], a["kind"], a["value"]])

	var last_t: float = 0.0
	for action in _actions:
		var wait: float = float(action["time"]) - last_t
		if wait > 0.001:
			await get_tree().create_timer(wait).timeout
		last_t = float(action["time"])
		match action["kind"]:
			"shot":
				_capture(String(action["value"]))
			"press":
				await _press_key(String(action["value"]))
			"click":
				await _click_mouse(String(action["value"]))
			"key_down":
				_key_event(String(action["value"]), true)
			"key_up":
				_key_event(String(action["value"]), false)
			"mouse_down":
				_mouse_button(String(action["value"]), true)
			"mouse_up":
				_mouse_button(String(action["value"]), false)
			"mouse_move":
				_mouse_move(action["value"])

	await get_tree().create_timer(0.25).timeout
	print("[recorder] done.")
	get_tree().quit(0)

# ── Actions ────────────────────────────────────────────────────────────────────

func _capture(path: String) -> void:
	print("[recorder] shot -> ", path)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("[recorder] viewport returned null image")
		return
	var err: int = img.save_png(path)
	if err != OK:
		push_error("[recorder] save_png failed (%d): %s" % [err, path])

func _key_event(key_name: String, pressed: bool) -> void:
	var keycode: int = OS.find_keycode_from_string(key_name)
	if keycode == 0:
		keycode = OS.find_keycode_from_string(key_name.capitalize())
	if keycode == 0:
		push_error("[recorder] unknown key: " + key_name)
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _press_key(key_name: String) -> void:
	print("[recorder] press ", key_name)
	_key_event(key_name, true)
	await get_tree().create_timer(0.06).timeout
	_key_event(key_name, false)

func _mouse_token_to_btn(token: String) -> int:
	match token:
		"mouse_left", "left":
			return MOUSE_BUTTON_LEFT
		"mouse_right", "right":
			return MOUSE_BUTTON_RIGHT
		"mouse_middle", "middle":
			return MOUSE_BUTTON_MIDDLE
	return -1

func _mouse_button(token: String, pressed: bool) -> void:
	var btn: int = _mouse_token_to_btn(token)
	if btn < 0:
		push_error("[recorder] unknown mouse button: " + token)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	if pressed:
		ev.button_mask = 1 << (btn - 1)
	ev.pressed = pressed
	ev.position = _mouse_pos
	ev.global_position = _mouse_pos
	Input.parse_input_event(ev)

func _click_mouse(token: String) -> void:
	print("[recorder] click ", token)
	_mouse_button(token, true)
	await get_tree().create_timer(0.06).timeout
	_mouse_button(token, false)

func _mouse_move(pos: Vector2) -> void:
	print("[recorder] mouse -> ", pos)
	_mouse_pos = pos
	Input.warp_mouse(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
