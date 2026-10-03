class_name GuiWidgetView
extends Control
## Draws one widget from its package Dictionary and, in the Player, lets the
## user move it.
##
## The Builder and the Player use this same class so the editor shows exactly
## what the device will show. In the Builder [member interactive] is false and
## the canvas handles the mouse instead.
##
## Rough frame: shapes are drawn with plain lines and rectangles. Skins
## (style.image, fonts) come later.

## The user changed the value. [param event] is the package event name:
## "change", "press", "release" or "touch".
signal widget_event(widget_id: String, event: String, value: float)

var data: Dictionary
var interactive := false

var _value := 0.0           ## In the widget's own range (value.min..value.max).
var _dragging := false
var _drag_start_pos := Vector2.ZERO
var _drag_start_norm := 0.0


func setup(widget: Dictionary, is_interactive: bool) -> void:
	data = widget
	interactive = is_interactive
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if data.get("type") == "group":
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # its children take the touches
	_value = float(_range().get("default", 0))
	refresh()


## Re-reads position, size and look from [member data].
func refresh() -> void:
	position = Vector2(data.get("x", 0), data.get("y", 0))
	size = Vector2(data.get("w", 100), data.get("h", 100))
	queue_redraw()


## Sets the value without firing any event. Received values go through here
## so they never echo back to the device (docs/Package-format.md 7.1).
func set_value_silently(v: float) -> void:
	if _dragging:
		return  # TODO(receive): keep the last value and apply it on release
	_value = _snap(v)
	queue_redraw()


func get_value() -> float:
	return _value


## --- value helpers -----------------------------------------------------------

func _range() -> Dictionary:
	return data.get("value", {"min": 0, "max": 1, "step": 0, "default": 0})


func _norm() -> float:
	var r := _range()
	var lo := float(r.get("min", 0))
	var hi := float(r.get("max", 1))
	return 0.0 if is_equal_approx(lo, hi) else clampf((_value - lo) / (hi - lo), 0.0, 1.0)


func _set_norm(n: float) -> void:
	var r := _range()
	_set_value(lerpf(float(r.get("min", 0)), float(r.get("max", 1)), clampf(n, 0.0, 1.0)))


func _set_value(v: float) -> void:
	v = _snap(v)
	if is_equal_approx(v, _value):
		return
	_value = v
	queue_redraw()
	# TODO(motion): throttle with motion.sendInterval
	widget_event.emit(data.get("id", ""), "change", _value)


func _snap(v: float) -> float:
	var step := float(_range().get("step", 0))
	return snappedf(v, step) if step > 0.0 else v


func _color(key: String, fallback: String) -> Color:
	return Color.from_string(str(data.get("style", {}).get(key, fallback)), Color(fallback))


## --- input (Player only) -------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var type: String = data.get("type", "")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and _motion().get("resetOnDoubleTap", false):
			_dragging = false
			_set_value(float(_range().get("default", 0)))
			accept_event()
			return
		if event.pressed:
			_press(type, event.position)
		else:
			_release(type)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag(type, event.position)
		accept_event()


func _motion() -> Dictionary:
	return data.get("motion", {})


func _press(type: String, pos: Vector2) -> void:
	var id: String = data.get("id", "")
	match type:
		"button":
			widget_event.emit(id, "press", _value)
			if data.get("mode", "momentary") == "toggle":
				_set_norm(0.0 if _norm() > 0.5 else 1.0)
			else:
				_set_norm(1.0)
		"image":
			widget_event.emit(id, "press", 0.0)
		"fader", "encoder":
			_dragging = true
			_drag_start_pos = pos
			_drag_start_norm = _norm()
			widget_event.emit(id, "touch", _value)
			if type == "fader" and _motion().get("touchMode", "relative") == "jump":
				_set_norm(_fader_norm_at(pos))


func _release(type: String) -> void:
	var id: String = data.get("id", "")
	match type:
		"button":
			if data.get("mode", "momentary") == "momentary":
				_set_norm(0.0)
			widget_event.emit(id, "release", _value)
		"fader", "encoder":
			if _dragging:
				_dragging = false
				widget_event.emit(id, "release", _value)


func _drag(type: String, pos: Vector2) -> void:
	var sens := float(_motion().get("sensitivity", 1.0))
	if type == "fader":
		if _motion().get("touchMode", "relative") == "jump":
			_set_norm(_fader_norm_at(pos))
			return
		var vertical: bool = data.get("orientation", "vertical") == "vertical"
		var length := maxf(1.0, size.y if vertical else size.x)
		var moved := (_drag_start_pos.y - pos.y) if vertical else (pos.x - _drag_start_pos.x)
		_set_norm(_drag_start_norm + moved / length * sens)
	else:
		# TODO(motion): drag "horizontal"/"circular", endless wrap, $delta, acceleration
		var moved := _drag_start_pos.y - pos.y
		_set_norm(_drag_start_norm + moved / 200.0 * sens)


func _fader_norm_at(pos: Vector2) -> float:
	if data.get("orientation", "vertical") == "vertical":
		return 1.0 - pos.y / maxf(1.0, size.y)
	return pos.x / maxf(1.0, size.x)


## --- drawing -------------------------------------------------------------------

func _draw() -> void:
	match data.get("type", ""):
		"button": _draw_button()
		"fader": _draw_fader()
		"encoder": _draw_encoder()
		"label": _draw_text(str(data.get("style", {}).get("text", "")), Color(0.9, 0.9, 0.9))
		"led": _draw_led()
		"image": _draw_image()
		"panel": draw_rect(Rect2(Vector2.ZERO, size), _color("background", "#2B2B2B"))
		"group":
			if data.get("style", {}).has("background"):
				draw_rect(Rect2(Vector2.ZERO, size), _color("background", "#2B2B2B"))


func _draw_button() -> void:
	var accent := _color("color", "#3A7BD5")
	var on := _norm() > 0.5
	var box := StyleBoxFlat.new()
	box.bg_color = accent if on else Color(0.18, 0.19, 0.21)
	box.border_color = accent
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	_draw_text(str(data.get("style", {}).get("text", "")), Color.WHITE)


func _draw_fader() -> void:
	var accent := _color("color", "#3A7BD5")
	var vertical: bool = data.get("orientation", "vertical") == "vertical"
	var n := _norm()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.15, 0.16))
	if vertical:
		var cx := size.x / 2.0
		draw_line(Vector2(cx, 8), Vector2(cx, size.y - 8), Color(0.35, 0.35, 0.38), 4.0)
		var cap_h := clampf(size.y * 0.08, 12.0, 40.0)
		var y := (size.y - cap_h) * (1.0 - n)
		draw_line(Vector2(cx, y + cap_h / 2.0), Vector2(cx, size.y - 8), accent, 4.0)
		draw_rect(Rect2(2, y, size.x - 4, cap_h), Color(0.85, 0.85, 0.88))
	else:
		var cy := size.y / 2.0
		draw_line(Vector2(8, cy), Vector2(size.x - 8, cy), Color(0.35, 0.35, 0.38), 4.0)
		var cap_w := clampf(size.x * 0.08, 12.0, 40.0)
		var x := (size.x - cap_w) * n
		draw_line(Vector2(8, cy), Vector2(x + cap_w / 2.0, cy), accent, 4.0)
		draw_rect(Rect2(x, 2, cap_w, size.y - 4), Color(0.85, 0.85, 0.88))


func _draw_encoder() -> void:
	var accent := _color("color", "#3A7BD5")
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 4.0
	var sweep := deg_to_rad(float(_motion().get("angleRange", 270)))
	# 0 is straight up; the sweep is centred on it.
	var start := -PI / 2.0 - sweep / 2.0
	draw_circle(center, radius, Color(0.18, 0.19, 0.21))
	draw_arc(center, radius - 3.0, start, start + sweep, 48, Color(0.35, 0.35, 0.38), 4.0)
	var angle := start + sweep * _norm()
	draw_arc(center, radius - 3.0, start, angle, 48, accent, 4.0)
	draw_line(center, center + Vector2.from_angle(angle) * (radius - 8.0), Color.WHITE, 3.0)


func _draw_led() -> void:
	var on := _color("color", "#4CD964")
	var off := on.darkened(0.8)
	draw_circle(size / 2.0, minf(size.x, size.y) / 2.0 - 2.0, off.lerp(on, _norm()))


func _draw_image() -> void:
	# TODO(assets): load style.image from the package
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.22, 0.25))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.45, 0.5), false, 2.0)
	_draw_text("IMAGE", Color(0.6, 0.6, 0.65))


func _draw_text(text: String, color: Color) -> void:
	if text.is_empty():
		return
	var font := get_theme_default_font()
	var font_size := int(data.get("style", {}).get("fontSize", 18))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2((size.x - text_size.x) / 2.0,
			(size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
