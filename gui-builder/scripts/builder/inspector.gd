extends VBoxContainer
## Properties of the selected widget. Every field writes straight into the
## widget's Dictionary and then reports the edit, so undo sees each change.
##
## The properties each type shows come from GuiWidgetTypes ("props"), so a
## new widget type gets its inspector without code here.
##
## With nothing selected it shows the layout's grid and the package theme.
##
## Rough frame: common fields, the type's properties, and the raw GuiScript
## for each event. Motion settings and receive rules get proper editors later.

## A field changed [param widget_id]'s Dictionary.
signal edited(widget_id: String)
## The selected widget's id changed; the page needs rebuilding.
signal id_changed(new_id: String)
## The layout's grid or the package theme changed; the page needs rebuilding.
signal layout_edited

const FIELD_WIDTH := 220.0
const MAX_CELLS := 64

## Theme entries offered with nothing selected: [path, label].
const THEME_FIELDS := [
	["background", "Page background"],
	["surface", "Surface"],
	["primary", "Primary"],
	["text", "Text"],
	["panel.background", "Panel background"],
	["panel.titleBackground", "Panel title bar"],
	["panel.border", "Panel border"],
]

var _widget: Dictionary
var _pkg: Dictionary
var _layout: Dictionary
var _page: Dictionary
var _strict := true


## [param strict]: the widget's container keeps blocks to their types' sizes.
func show_widget(pkg: Dictionary, layout: Dictionary, page: Dictionary, widget: Dictionary,
		strict := true) -> void:
	_pkg = pkg
	_layout = layout
	_page = page
	_widget = widget
	_strict = strict
	for child in get_children():
		child.queue_free()
	if widget.is_empty():
		_show_layout()
		return

	var type: String = widget["type"]
	_heading("%s  (%s)" % [widget["id"], GuiWidgetTypes.info(type).get("name", type)])
	_text_field("ID", widget["id"], _set_id)
	_int_field("Column", widget, "col", 0, MAX_CELLS - 1)
	_int_field("Row", widget, "row", 0, MAX_CELLS - 1)
	var sizes := GuiWidgetTypes.sizes(type)
	if strict and not sizes.is_empty():
		_size_choice(sizes)
	else:
		_int_field("Width (cells)", widget, "cw", 1, MAX_CELLS)
		_int_field("Height (cells)", widget, "ch", 1, MAX_CELLS)
	_text_field("Style class", str(widget.get("class", "")), func(t: String) -> void:
		if t.strip_edges().is_empty():
			widget.erase("class")
		else:
			widget["class"] = t.strip_edges()
		_changed())

	for prop: Dictionary in GuiWidgetTypes.info(type).get("props", []):
		_prop_field(prop)

	if widget.has("children"):
		_heading("Inner grid")
		_note("Cells inside this %s. Leave as is to line up with the cells around it." % type)
		var grid: Dictionary = widget.get("grid", {})
		for key_label in [["cols", "Columns", "cw"], ["rows", "Rows", "ch"]]:
			var s := _spin(1, MAX_CELLS, 1)
			s.value = grid.get(key_label[0], widget[key_label[2]])
			s.value_changed.connect(func(v: float) -> void:
				var g: Dictionary = widget.get_or_add("grid", {})
				g[key_label[0]] = int(v)
				_changed())
			_row(key_label[1], s)

	if widget.has("params"):
		_heading("Group params")
		_note("Scripts inside this group read these as $name. Duplicate adds 1 to each number.")
		var params: Dictionary = widget["params"]
		for key: String in params:
			_number_field("$" + key, params, key)
		_text_field("Add param", "", func(t: String) -> void:
			if GuiPackage.is_valid_id(t) and not params.has(t):
				params[t] = 1
				_changed()
				_reshow.call_deferred())

	var parts := GuiWidgetTypes.parts(type)
	if parts.is_empty():
		_value_sections(widget, "")
	else:
		# Each part (a dual encoder's outer and inner knob) has its own
		# value, scripts and receive rules.
		for part: String in parts:
			_value_sections(widget.get_or_add(part, {}), part)


## Value, Send and Receive for the widget, or for one of its parts.
func _value_sections(holder: Dictionary, part: String) -> void:
	var prefix := ""
	if not part.is_empty():
		prefix = "%s (%s): " % [part.capitalize(), holder.get("label", part)]
	if holder.has("value"):
		_heading(prefix + "Value")
		_number_field("Min", holder["value"], "min")
		_number_field("Max", holder["value"], "max")
		_number_field("Step", holder["value"], "step")
		_number_field("Default", holder["value"], "default")

	if holder.has("on"):
		_heading(prefix + "Send (GuiScript)")
		var inherited := GuiPackage.params_for(_page, _widget["id"])
		if not inherited.is_empty():
			_note("Also available: " + ", ".join(inherited.keys().map(func(k: String) -> String: return "$" + k)))
		for event_name: String in GuiWidgetTypes.events(_widget["type"]):
			_script_field(event_name, holder["on"])

	if holder.has("receive"):
		_heading(prefix + "Receive")
		_note("Receive rules: next step.")  # TODO(receive)


## Nothing selected: the layout's grid and the package theme.
func _show_layout() -> void:
	_heading("Layout grid")
	_note("Every widget is a block of grid cells. Drag widgets from the left onto the screen.")
	var grid: Dictionary = _layout["grid"]
	var theme := GuiTheme.of(_pkg)
	for f in [["cols", "Columns", 1, MAX_CELLS, 4], ["rows", "Rows", 1, MAX_CELLS, 4],
			["gap", "Gap (px)", 0, 200, theme["gap"]], ["padding", "Padding (px)", 0, 400, theme["padding"]]]:
		var s := _spin(f[2], f[3], 1)
		s.value = grid.get(f[0], f[4])
		s.value_changed.connect(func(v: float) -> void:
			grid[f[0]] = int(v)
			layout_edited.emit())
		_row(f[1], s)

	_heading("Theme")
	_note("The look of the whole package. A widget's own style or style class wins over it.")
	var own: Dictionary = _pkg.get_or_add("theme", {})
	for f in THEME_FIELDS:
		var c := ColorPickerButton.new()
		c.color = GuiTheme.to_color(GuiTheme.value(theme, f[0]))
		c.popup_closed.connect(func() -> void:
			_set_path(own, f[0], "#" + c.color.to_html(c.color.a < 1.0))
			layout_edited.emit())
		_row(f[1], c)


## A field for one entry of a type's "props" (GuiWidgetTypes). Keys may be
## dotted ("style.text"); a missing value shows the theme's.
##
## The field writes to the widget it was built for, not whatever is shown
## when it fires: a colour picker can close after the selection changed.
func _prop_field(prop: Dictionary) -> void:
	var widget := _widget
	var path: String = prop["key"]
	var current: Variant = _get_path(widget, path)
	var theme_path: String = prop.get("theme", "")
	if current == null and not theme_path.is_empty():
		current = GuiTheme.value(GuiTheme.of(_pkg), theme_path)
	var apply := func(v: Variant) -> void:
		_set_path(widget, path, v)
		_changed_for(widget)
	match prop["kind"]:
		"text":
			_text_field(prop["label"], str(current if current != null else ""), apply)
		"int":
			var s := _spin(1, 400, 1)
			s.value = float(current if current != null else 0)
			s.value_changed.connect(func(v: float) -> void: apply.call(int(v)))
			_row(prop["label"], s)
		"bool":
			var b := CheckBox.new()
			b.button_pressed = bool(current)
			b.toggled.connect(func(on: bool) -> void: apply.call(on))
			_row(prop["label"], b)
		"choice":
			var options: Array = prop["options"]
			var o := OptionButton.new()
			for opt: String in options:
				o.add_item(opt)
			o.selected = maxi(0, options.find(current))
			o.item_selected.connect(func(i: int) -> void: apply.call(options[i]))
			_row(prop["label"], o)
		"color":
			var c := ColorPickerButton.new()
			c.color = GuiTheme.to_color(current, Color.WHITE)
			c.popup_closed.connect(func() -> void:
				apply.call("#" + c.color.to_html(c.color.a < 1.0)))
			_row(prop["label"], c)


## The block sizes the type comes in, e.g. "1 x 3".
func _size_choice(sizes: Array) -> void:
	var widget := _widget
	var o := OptionButton.new()
	var current := [widget["cw"], widget["ch"]]
	for s: Array in sizes:
		o.add_item("%d x %d" % s)
	o.selected = maxi(0, sizes.find(current))
	if sizes.find(current) < 0:
		o.add_item("%d x %d (custom)" % current)
		o.selected = sizes.size()
	o.item_selected.connect(func(i: int) -> void:
		if i < sizes.size():
			widget["cw"] = sizes[i][0]
			widget["ch"] = sizes[i][1]
			_changed_for(widget))
	_row("Size (cells)", o)


static func _get_path(d: Dictionary, path: String) -> Variant:
	var at: Variant = d
	for part in path.split("."):
		if not at is Dictionary or not at.has(part):
			return null
		at = at[part]
	return at


static func _set_path(d: Dictionary, path: String, v: Variant) -> void:
	var parts := path.split(".")
	var at := d
	for i in parts.size() - 1:
		at = at.get_or_add(parts[i], {})
	at[parts[-1]] = v


func _changed() -> void:
	_changed_for(_widget)


## Reports an edit of [param widget]. A field that fires after its inspector
## was cleared (nothing selected now) still reports the widget it edited.
func _changed_for(widget: Dictionary) -> void:
	if widget.has("id"):
		edited.emit(widget["id"])


## --- field builders -----------------------------------------------------------

func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	add_child(l)


func _row(label: String, field: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 120
	field.custom_minimum_size.x = FIELD_WIDTH
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(field)
	add_child(row)


## A LineEdit that applies on Enter or when it loses focus.
func _text_field(label: String, value: String, apply: Callable) -> void:
	var e := LineEdit.new()
	e.text = value
	var commit := func(_t := "") -> void:
		if e.text != value:
			apply.call(e.text)
	e.text_submitted.connect(commit)
	e.focus_exited.connect(commit)
	_row(label, e)


func _reshow() -> void:
	show_widget(_pkg, _layout, _page, _widget, _strict)


func _spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	return s


func _int_field(label: String, dict: Dictionary, key: String, min_value := -100000,
		max_value := 100000) -> void:
	var s := _spin(min_value, max_value, 1)
	s.value = dict[key]
	s.value_changed.connect(func(v: float) -> void:
		dict[key] = int(v)
		_changed())
	_row(label, s)


func _number_field(label: String, dict: Dictionary, key: String) -> void:
	var s := SpinBox.new()
	s.min_value = -100000
	s.max_value = 100000
	s.step = 0.001
	s.value = dict.get(key, 0)
	s.value_changed.connect(func(v: float) -> void:
		dict[key] = v
		_changed())
	_row(label, s)


func _script_field(event_name: String, on: Dictionary) -> void:
	var l := Label.new()
	l.text = "on " + event_name
	add_child(l)
	var t := TextEdit.new()
	t.text = on.get(event_name, "")
	t.custom_minimum_size = Vector2(FIELD_WIDTH, 90)
	# TODO(guiscript): check with ScriptChecker and show errors inline
	t.focus_exited.connect(func() -> void:
		var src := t.text.strip_edges()
		if src == on.get(event_name, ""):
			return
		if src.is_empty():
			on.erase(event_name)
		else:
			on[event_name] = src
		_changed())
	add_child(t)


func _set_id(new_id: String) -> void:
	if new_id == _widget["id"]:
		return
	var problem := ""
	if not GuiPackage.is_valid_id(new_id):
		problem = "An ID starts with a letter and uses only letters, digits and _ (max 32)."
	elif GuiPackage.id_in_use(_pkg, new_id):
		problem = "'%s' is already used by another widget, page or device." % new_id
	if not problem.is_empty():
		OS.alert(problem, "Invalid ID")
		_reshow.call_deferred()
		return
	_widget["id"] = new_id
	id_changed.emit(new_id)
