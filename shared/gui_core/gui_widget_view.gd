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
	if data.has("children") or GuiWidgetTypes.is_back(data.get("type", "")):
		mouse_filter = Control.MOUSE_FILTER_IGNORE  # children / widgets in front take the touches
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
		"label": _draw_label()
		"led": _draw_led()
		"image": _draw_image()
		"background": _draw_background()
		"panel": _draw_panel()
		"group":
			if data.get("style", {}).has("background"):
				draw_rect(Rect2(Vector2.ZERO, size), _color("background", "surface"))


## Label text aligned by style.align (center by default). Left and right
## keep a small inset from the block's edge.
func _draw_label() -> void:
	const INSET := 8.0
	var align := HORIZONTAL_ALIGNMENT_CENTER
	match str(_style("align", "")):
		"left": align = HORIZONTAL_ALIGNMENT_LEFT
		"right": align = HORIZONTAL_ALIGNMENT_RIGHT
	_draw_text(Rect2(INSET, 0, maxf(1.0, size.x - INSET * 2.0), size.y),
			str(_style("text", "")), _color("textColor", "text"), 0, align)


func _draw_button() -> void:
	var accent := _color("color", "primary")
	var on := _norm() > 0.5
	var box := StyleBoxFlat.new()
	box.bg_color = accent if on else _color("background", "surface")
	box.border_color = accent
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(_style("radius", "radius")))
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var text := str(_style("text", ""))
	var icon := str(_style("icon", "none"))
	if icon in ["up", "down", "left", "right", "stop", "pause", "record", "rewind", "ffwd", "prev", "next"]:
		# Record is red unless the widget sets its own icon colour.
		var icon_color := _color("iconColor", "danger" if icon == "record" else "text")
		# With text, the icon takes the upper part and the text the lower.
		var icon_rect := Rect2(Vector2.ZERO, size)
		if not text.is_empty():
			icon_rect.size.y = size.y * 0.6
			_draw_text(Rect2(0, size.y * 0.55, size.x, size.y * 0.45), text,
					_color("textColor", "text"))
		match icon:
			"stop": _draw_stop(icon_rect, icon_color)
			"pause": _draw_pause(icon_rect, icon_color)
			"record": draw_circle(icon_rect.get_center(),
					minf(icon_rect.size.x, icon_rect.size.y) * 0.24, icon_color)
			"rewind": _draw_double_arrow(icon_rect, "left", icon_color)
			"ffwd": _draw_double_arrow(icon_rect, "right", icon_color)
			"prev": _draw_track_arrow(icon_rect, "left", icon_color)
			"next": _draw_track_arrow(icon_rect, "right", icon_color)
			_: _draw_arrow(icon_rect, icon, icon_color)
	else:
		_draw_text(Rect2(Vector2.ZERO, size), text, _color("textColor", "text"))


## A solid square, the same visual weight as an arrow, centred in [param rect].
func _draw_stop(rect: Rect2, color: Color) -> void:
	var half := minf(rect.size.x, rect.size.y) * 0.21
	draw_rect(Rect2(rect.get_center() - Vector2(half, half), Vector2(half, half) * 2.0), color)


## The stop square split into two bars by a vertical gap.
func _draw_pause(rect: Rect2, color: Color) -> void:
	var half := minf(rect.size.x, rect.size.y) * 0.21
	var bar := Vector2(half * 0.7, half * 2.0)
	var top_left := rect.get_center() - Vector2(half, half)
	draw_rect(Rect2(top_left, bar), color)
	draw_rect(Rect2(top_left + Vector2(half * 2.0 - bar.x, 0), bar), color)


## Two normal arrows overlapping: fast forward ("right") or rewind ("left").
func _draw_double_arrow(rect: Rect2, direction: String, color: Color) -> void:
	_draw_arrow(rect, direction, color, -0.45)
	_draw_arrow(rect, direction, color, 0.45)


## A normal arrow with a bar at its tip: next track ("right") or previous
## track ("left").
func _draw_track_arrow(rect: Rect2, direction: String, color: Color) -> void:
	var r := minf(rect.size.x, rect.size.y) * 0.28
	var dir := 1.0 if direction == "right" else -1.0
	_draw_arrow(rect, direction, color, -0.2)
	# The arrow's tip ends at 0.8 r from the centre; the bar starts there.
	var c := rect.get_center()
	var near_x := c.x + dir * r * 0.8
	var far_x := c.x + dir * r * 1.15
	draw_rect(Rect2(minf(near_x, far_x), c.y - r, absf(far_x - near_x), r * 2.0), color)


## A solid triangle pointing [param direction], centred in [param rect].
## [param shift] moves it along its own direction, in multiples of its size.
func _draw_arrow(rect: Rect2, direction: String, color: Color, shift := 0.0) -> void:
	var r := minf(rect.size.x, rect.size.y) * 0.28
	var tip: Vector2 = {"up": Vector2.UP, "down": Vector2.DOWN,
		"left": Vector2.LEFT, "right": Vector2.RIGHT}[direction]
	var c := rect.get_center() + tip * r * shift
	var side := Vector2(-tip.y, tip.x)
	draw_colored_polygon(PackedVector2Array([
		c + tip * r,
		c - tip * r * 0.7 + side * r,
		c - tip * r * 0.7 - side * r,
	]), color)


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
	var tex := GuiAssets.texture(str(data.get("style", {}).get("image", "")))
	if tex == null:
		_draw_placeholder("IMAGE")
		return
	_draw_fitted(tex, str(data.get("style", {}).get("fit", "contain")), Color.WHITE)


## A full-area picture behind the other blocks: a fill colour, then the image.
func _draw_background() -> void:
	var opacity := clampf(float(data.get("style", {}).get("opacity", 100)) / 100.0, 0.0, 1.0)
	var style: Dictionary = data.get("style", {})
	if style.has("background"):
		var fill := _color("background", "background")
		fill.a *= opacity
		draw_rect(Rect2(Vector2.ZERO, size), fill)
	var tex := GuiAssets.texture(str(data.get("style", {}).get("image", "")))
	if tex == null:
		if not interactive and not style.has("background"):
			_draw_placeholder("BACKGROUND")  # only in the Builder
		return
	_draw_fitted(tex, str(style.get("fit", "cover")), Color(1, 1, 1, opacity))


## [param tex] in the widget's rectangle:
##   "cover"    keeps proportions and fills it, cutting off what sticks out
##   "contain"  keeps proportions and shows all of it (the default)
##   "stretch"  fills it exactly
func _draw_fitted(tex: Texture2D, fit: String, modulate: Color) -> void:
	var area := Rect2(Vector2.ZERO, size)
	var tex_size := tex.get_size()
	match fit:
		"stretch":
			draw_texture_rect(tex, area, false, modulate)
		"cover":
			# Draw the middle part of the image that has the area's shape.
			var scale := maxf(size.x / tex_size.x, size.y / tex_size.y)
			var src_size := size / scale
			draw_texture_rect_region(tex, area, Rect2((tex_size - src_size) / 2.0, src_size), modulate)
		_:
			var scale := minf(size.x / tex_size.x, size.y / tex_size.y)
			var dst := tex_size * scale
			draw_texture_rect(tex, Rect2((size - dst) / 2.0, dst), false, modulate)


func _draw_placeholder(label: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.22, 0.25, 0.6))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.45, 0.5), false, 2.0)
	_draw_text(Rect2(Vector2.ZERO, size), label, Color(0.6, 0.6, 0.65))


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
			int(GuiTheme.value(pkg_theme, "panel.titleFontSize")), HORIZONTAL_ALIGNMENT_LEFT,
			str(GuiTheme.value(pkg_theme, "panel.titleFontWeight")))


## A blurred text shadow. Canvas drawing has no blur, so the shadow is
## stacked from outlines that grow by [param blur] px in a few steps, each
## faint: where they all overlap (the glyph itself) the colour reaches its
## full strength, and it fades out towards the widest outline.
func _draw_soft_shadow(font: Font, at: Vector2, text: String, align: HorizontalAlignment,
		width: float, font_size: int, outline: int, blur: int, color: Color) -> void:
	# Two layers per pixel of blur keeps the steps from showing.
	var steps := clampi(blur * 2, 2, 24)
	# Alpha per layer such that steps + 1 overlapping layers add up to color.a.
	var layer := color
	layer.a = 1.0 - pow(1.0 - color.a, 1.0 / (steps + 1))
	var just := TextServer.JUSTIFICATION_NONE
	for i in range(steps, 0, -1):
		var grow := outline + blur * float(i) / steps
		draw_string_outline(font, at, text, align, width, font_size, roundi(grow * 2.0), layer, just)
	draw_string(font, at, text, align, width, font_size, layer, just)


## [param text] centred vertically in [param rect]. Font size 0 and an empty
## weight mean the widget's own (style.fontSize / style.fontWeight, else the
## theme's).
func _draw_text(rect: Rect2, text: String, color: Color, font_size := 0,
		align := HORIZONTAL_ALIGNMENT_CENTER, weight := "") -> void:
	if text.is_empty():
		return
	if weight.is_empty():
		weight = str(_style("fontWeight", "fontWeight"))
	var font := GuiFonts.of(weight)
	if font_size <= 0:
		font_size = int(_style("fontSize", "fontSize"))
	var y := rect.position.y + (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var pos := Vector2(rect.position.x, y)
	var just := TextServer.JUSTIFICATION_NONE
	var outline := int(_style("textOutline", "textOutline"))
	var shadow := int(_style("textShadow", "textShadow"))
	# Back to front: shadow (with the outline's thickness), outline, text.
	if shadow > 0:
		var shadow_color := _color("textShadowColor", "textShadowColor")
		var at := pos + Vector2(shadow, shadow)
		var blur := int(_style("textShadowBlur", "textShadowBlur"))
		if blur > 0:
			_draw_soft_shadow(font, at, text, align, rect.size.x, font_size, outline, blur,
					shadow_color)
		else:
			if outline > 0:
				draw_string_outline(font, at, text, align, rect.size.x, font_size, outline * 2,
						shadow_color, just)
			draw_string(font, at, text, align, rect.size.x, font_size, shadow_color, just)
	if outline > 0:
		# Godot's outline size is the full stroke, half of it outside the glyph.
		draw_string_outline(font, pos, text, align, rect.size.x, font_size, outline * 2,
				_color("textOutlineColor", "textOutlineColor"), just)
	draw_string(font, pos, text, align, rect.size.x, font_size, color, just)
