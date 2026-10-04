class_name GuiWidgetView
extends Control
## Draws one widget from its package Dictionary and, in the Player, lets the
## user move it.
##
## The Builder and the Player use this same class so the editor shows exactly
## what the device will show. In the Builder [member interactive] is false and
## the canvas handles the mouse instead.
##
## Its position and size are set by GuiPageView from the grid. Colours and
## sizes come from the package theme unless the widget's style overrides them
## (GuiTheme.style).
##
## Rough frame: shapes are drawn with plain lines and rectangles. Skins
## (style.image, fonts) come later.

## The user changed a value. [param event] is the package event name:
## "change", "press", "release" or "touch". For a widget with parts (a dual
## encoder) [param widget_id] names the part: "eq1.inner".
signal widget_event(widget_id: String, event: String, value: float)

## Share of a dual encoder's radius that belongs to the inner knob. A touch
## inside it turns the inner knob, on the ring around it the outer one.
const INNER_RATIO := 0.58

var data: Dictionary
var pkg_theme: Dictionary
var interactive := false

## part -> value in that part's own range (value.min..value.max). A widget
## with one value uses the part "".
var _values := {}
var _part := ""             ## The part being touched.
var _dragging := false
var _drag_start_pos := Vector2.ZERO
var _drag_start_norm := 0.0


func setup(widget: Dictionary, package_theme: Dictionary, is_interactive: bool) -> void:
	data = widget
	pkg_theme = package_theme
	interactive = is_interactive
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if data.has("children"):
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # its children take the touches
	for part in _parts():
		_values[part] = float(_range(part).get("default", 0))


## Sets a value without firing any event. Received values go through here
## so they never echo back to the device (docs/Package-format.md 7.1).
func set_value_silently(v: float, part := "") -> void:
	if _dragging and part == _part:
		return  # TODO(receive): keep the last value and apply it on release
	if not _values.has(part):
		return
	_values[part] = _snap(v, part)
	queue_redraw()


func get_value(part := "") -> float:
	return _values.get(part, 0.0)


## The widget's parts: [""] for a widget with one value, otherwise the
## names from GuiWidgetTypes ("outer", "inner").
func _parts() -> Array:
	var parts: Array = GuiWidgetTypes.info(data.get("type", "")).get("parts", [])
	return parts if not parts.is_empty() else [""]


## --- value helpers -----------------------------------------------------------

## Where a part keeps its value, motion, scripts and receive rules: the
## widget itself, or its sub-Dictionary for a named part.
func _part_data(part: String) -> Dictionary:
	return data if part.is_empty() else data.get(part, {})


func _range(part := "") -> Dictionary:
	return _part_data(part).get("value", {"min": 0, "max": 1, "step": 0, "default": 0})


## The widget's motion with the part's own motion over it.
func _motion(part := "") -> Dictionary:
	var m: Dictionary = data.get("motion", {}).duplicate()
	if not part.is_empty():
		m.merge(_part_data(part).get("motion", {}), true)
	return m


func _norm(part := "") -> float:
	var r := _range(part)
	var lo := float(r.get("min", 0))
	var hi := float(r.get("max", 1))
	var v: float = _values.get(part, lo)
	return 0.0 if is_equal_approx(lo, hi) else clampf((v - lo) / (hi - lo), 0.0, 1.0)


func _set_norm(n: float, part := "") -> void:
	var r := _range(part)
	_set_value(lerpf(float(r.get("min", 0)), float(r.get("max", 1)), clampf(n, 0.0, 1.0)), part)


func _set_value(v: float, part := "") -> void:
	v = _snap(v, part)
	if is_equal_approx(v, _values.get(part, NAN)):
		return
	_values[part] = v
	queue_redraw()
	# TODO(motion): throttle with motion.sendInterval
	widget_event.emit(_event_id(part), "change", v)


func _snap(v: float, part := "") -> float:
	var step := float(_range(part).get("step", 0))
	return snappedf(v, step) if step > 0.0 else v


func _event_id(part: String) -> String:
	var id: String = data.get("id", "")
	return id if part.is_empty() else "%s.%s" % [id, part]


## Style [param key], or the theme value at [param theme_path].
func _style(key: String, theme_path: String) -> Variant:
	return GuiTheme.style(pkg_theme, data, key, theme_path)


func _color(key: String, theme_path: String) -> Color:
	return GuiTheme.to_color(_style(key, theme_path))


func _theme_color(path: String) -> Color:
	return GuiTheme.to_color(GuiTheme.value(pkg_theme, path))


## A fader runs along its longer side.
func _vertical() -> bool:
	return size.y >= size.x


## --- input (Player only) -------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var type: String = data.get("type", "")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_part = _part_at(event.position)
		if event.double_click and _motion(_part).get("resetOnDoubleTap", false):
			_dragging = false
			_set_value(float(_range(_part).get("default", 0)), _part)
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


## Which part a touch at [param pos] moves.
func _part_at(pos: Vector2) -> String:
	if data.get("type") != "dual_encoder":
		return ""
	var inner := _knob_radius() * INNER_RATIO
	return "inner" if pos.distance_to(size / 2.0) <= inner else "outer"


func _press(type: String, pos: Vector2) -> void:
	var id := _event_id(_part)
	match type:
		"button":
			widget_event.emit(id, "press", get_value())
			if data.get("mode", "momentary") == "toggle":
				_set_norm(0.0 if _norm() > 0.5 else 1.0)
			else:
				_set_norm(1.0)
		"image":
			widget_event.emit(id, "press", 0.0)
		"fader", "encoder", "dual_encoder":
			_dragging = true
			_drag_start_pos = pos
			_drag_start_norm = _norm(_part)
			widget_event.emit(id, "touch", get_value(_part))
			if type == "fader" and _motion().get("touchMode", "relative") == "jump":
				_set_norm(_fader_norm_at(pos))


func _release(type: String) -> void:
	var id := _event_id(_part)
	match type:
		"button":
			if data.get("mode", "momentary") == "momentary":
				_set_norm(0.0)
			widget_event.emit(id, "release", get_value())
		"fader", "encoder", "dual_encoder":
			if _dragging:
				_dragging = false
				widget_event.emit(id, "release", get_value(_part))


func _drag(type: String, pos: Vector2) -> void:
	var sens := float(_motion(_part).get("sensitivity", 1.0))
	if type == "fader":
		if _motion().get("touchMode", "relative") == "jump":
			_set_norm(_fader_norm_at(pos))
			return
		var vertical := _vertical()
		var length := maxf(1.0, size.y if vertical else size.x)
		var moved := (_drag_start_pos.y - pos.y) if vertical else (pos.x - _drag_start_pos.x)
		_set_norm(_drag_start_norm + moved / length * sens)
	else:
		# TODO(motion): drag "horizontal"/"circular", endless wrap, $delta, acceleration
		var moved := _drag_start_pos.y - pos.y
		_set_norm(_drag_start_norm + moved / 200.0 * sens, _part)


func _fader_norm_at(pos: Vector2) -> float:
	if _vertical():
		return 1.0 - pos.y / maxf(1.0, size.y)
	return pos.x / maxf(1.0, size.x)


## --- drawing -------------------------------------------------------------------

func _draw() -> void:
	match data.get("type", ""):
		"button": _draw_button()
		"fader": _draw_fader()
		"encoder": _draw_encoder()
		"dual_encoder": _draw_dual_encoder()
		"label": _draw_text(Rect2(Vector2.ZERO, size), str(_style("text", "")),
				_color("textColor", "text"))
		"led": _draw_led()
		"image": _draw_image()
		"panel": _draw_panel()
		"group":
			if data.get("style", {}).has("background"):
				draw_rect(Rect2(Vector2.ZERO, size), _color("background", "surface"))


func _draw_button() -> void:
	var accent := _color("color", "primary")
	var on := _norm() > 0.5
	var box := StyleBoxFlat.new()
	box.bg_color = accent if on else _color("background", "surface")
	box.border_color = accent
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(_style("radius", "radius")))
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	_draw_text(Rect2(Vector2.ZERO, size), str(_style("text", "")), _color("textColor", "text"))


func _draw_fader() -> void:
	var accent := _color("color", "primary")
	var track := _color("background", "surface")
	var n := _norm()
	draw_rect(Rect2(Vector2.ZERO, size), track.darkened(0.3))
	if _vertical():
		var cx := size.x / 2.0
		draw_line(Vector2(cx, 8), Vector2(cx, size.y - 8), track.lightened(0.2), 4.0)
		var cap_h := clampf(size.y * 0.08, 12.0, 40.0)
		var y := (size.y - cap_h) * (1.0 - n)
		draw_line(Vector2(cx, y + cap_h / 2.0), Vector2(cx, size.y - 8), accent, 4.0)
		draw_rect(Rect2(2, y, size.x - 4, cap_h), Color(0.85, 0.85, 0.88))
	else:
		var cy := size.y / 2.0
		draw_line(Vector2(8, cy), Vector2(size.x - 8, cy), track.lightened(0.2), 4.0)
		var cap_w := clampf(size.x * 0.08, 12.0, 40.0)
		var x := (size.x - cap_w) * n
		draw_line(Vector2(8, cy), Vector2(x + cap_w / 2.0, cy), accent, 4.0)
		draw_rect(Rect2(x, 2, cap_w, size.y - 4), Color(0.85, 0.85, 0.88))


func _knob_radius() -> float:
	return minf(size.x, size.y) / 2.0 - 4.0


func _draw_encoder() -> void:
	var body := _color("background", "surface")
	var radius := _knob_radius()
	draw_circle(size / 2.0, radius, body)
	_draw_knob_arc(radius - 3.0, "", _color("color", "primary"), body, 4.0, true)


## Two knobs on one shaft: a ring for the outer value around a smaller knob
## for the inner one, each with its own colour, e.g. outer = frequency,
## inner = gain.
func _draw_dual_encoder() -> void:
	var body := _color("background", "surface")
	var radius := _knob_radius()
	var inner := radius * INNER_RATIO
	draw_circle(size / 2.0, radius, body.darkened(0.25))
	_draw_knob_arc(radius - 3.0, "outer", _color("color", "primary"), body, 4.0, false)
	draw_circle(size / 2.0, inner, body)
	draw_arc(size / 2.0, inner, 0, TAU, 48, body.darkened(0.5), 2.0)
	_draw_knob_arc(inner - 4.0, "inner", _color("innerColor", "secondary"), body, 3.0, true)


## The value arc of [param part] at [param radius], and a pointer from the
## centre when [param pointer] is set (or a tick on the ring when not).
func _draw_knob_arc(radius: float, part: String, accent: Color, body: Color, width: float,
		pointer: bool) -> void:
	var center := size / 2.0
	var sweep := deg_to_rad(float(_motion(part).get("angleRange", 270)))
	# 0 is straight up; the sweep is centred on it.
	var start := -PI / 2.0 - sweep / 2.0
	var angle := start + sweep * _norm(part)
	draw_arc(center, radius, start, start + sweep, 48, body.lightened(0.2), width)
	draw_arc(center, radius, start, angle, 48, accent, width)
	var dir := Vector2.from_angle(angle)
	if pointer:
		draw_line(center, center + dir * (radius - 5.0), Color.WHITE, 3.0)
	else:
		draw_line(center + dir * (radius - 8.0), center + dir * (radius + 2.0), Color.WHITE, 3.0)


func _draw_led() -> void:
	var on := _color("color", "ok")
	var off := on.darkened(0.8)
	draw_circle(size / 2.0, minf(size.x, size.y) / 2.0 - 2.0, off.lerp(on, _norm()))


func _draw_image() -> void:
	# TODO(assets): load style.image from the package
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.22, 0.25))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.45, 0.5), false, 2.0)
	_draw_text(Rect2(Vector2.ZERO, size), "IMAGE", Color(0.6, 0.6, 0.65))


## A box with an optional title bar across the top. Its children sit on the
## grid below the bar (GuiGrid._inner_box).
func _draw_panel() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = _color("background", "panel.background")
	box.border_color = _color("borderColor", "panel.border")
	box.set_border_width_all(int(_style("borderWidth", "panel.borderWidth")))
	var radius := int(_style("radius", "panel.radius"))
	box.set_corner_radius_all(radius)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var title := str(data.get("title", ""))
	if title.is_empty():
		return
	var bar := Rect2(0, 0, size.x, minf(size.y, float(GuiTheme.value(pkg_theme, "panel.titleHeight"))))
	var band := StyleBoxFlat.new()
	band.bg_color = _theme_color("panel.titleBackground")
	band.corner_radius_top_left = radius
	band.corner_radius_top_right = radius
	draw_style_box(band, bar)
	var pad := float(GuiTheme.value(pkg_theme, "panel.padding"))
	_draw_text(bar.grow_individual(-pad, 0, -pad, 0), title, _theme_color("panel.titleColor"),
			int(GuiTheme.value(pkg_theme, "panel.titleFontSize")), HORIZONTAL_ALIGNMENT_LEFT)


## [param text] centred vertically in [param rect]. Font size 0 means the
## widget's own (style.fontSize, else the theme's).
func _draw_text(rect: Rect2, text: String, color: Color, font_size := 0,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	if text.is_empty():
		return
	var font := get_theme_default_font()
	if font_size <= 0:
		font_size = int(_style("fontSize", "fontSize"))
	var y := rect.position.y + (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(rect.position.x, y), text, align, rect.size.x, font_size, color,
			TextServer.JUSTIFICATION_NONE)
