extends VBoxContainer
## Properties of the selected widget. Every field writes straight into the
## widget's Dictionary and then reports the edit, so undo sees each change.
##
## Rough frame: common fields, a few per-type options, and the raw GuiScript
## for each event. Motion settings and receive rules get proper editors later.

## A field changed [param widget_id]'s Dictionary.
signal edited(widget_id: String)
## The selected widget's id changed; the page needs rebuilding.
signal id_changed(new_id: String)

const FIELD_WIDTH := 220.0

var _widget: Dictionary
var _pkg: Dictionary
var _page: Dictionary


func show_widget(pkg: Dictionary, widget: Dictionary, page: Dictionary = {}) -> void:
	_pkg = pkg
	_widget = widget
	if not page.is_empty():
		_page = page
	for child in get_children():
		child.queue_free()
	if widget.is_empty():
		_heading("No selection")
		_note("Drag a widget from the left onto the screen.")
		return

	_heading("%s  (%s)" % [widget["id"], widget["type"]])
	_text_field("ID", widget["id"], _set_id)
	_int_field("X", widget, "x")
	_int_field("Y", widget, "y")
	_int_field("Width", widget, "w", GuiPackage.MIN_WIDGET_SIZE)
	_int_field("Height", widget, "h", GuiPackage.MIN_WIDGET_SIZE)

	var style: Dictionary = widget.get("style", {})
	if style.has("text"):
		_text_field("Text", style["text"], func(t: String) -> void:
			style["text"] = t
			_changed())
	if style.has("color"):
		_text_field("Color", style["color"], func(t: String) -> void:
			style["color"] = t
			_changed())

	match widget["type"]:
		"button":
			_choice("Mode", widget, "mode", ["momentary", "toggle"])
		"fader":
			_choice("Orientation", widget, "orientation", ["vertical", "horizontal"])
			_choice("Touch mode", widget["motion"], "touchMode", ["relative", "jump"])
		"encoder":
			_choice("Drag", widget["motion"], "drag", ["vertical", "horizontal", "circular"])

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
				show_widget.call_deferred(_pkg, _widget))

	if widget.has("value"):
		_heading("Value")
		_number_field("Min", widget["value"], "min")
		_number_field("Max", widget["value"], "max")
		_number_field("Step", widget["value"], "step")
		_number_field("Default", widget["value"], "default")

	if widget.has("on"):
		_heading("Send (GuiScript)")
		var inherited := GuiPackage.params_for(_page, widget["id"])
		if not inherited.is_empty():
			_note("Also available: " + ", ".join(inherited.keys().map(func(k: String) -> String: return "$" + k)))
		for event_name in _events(widget["type"]):
			_script_field(event_name, widget["on"])

	if widget.has("receive"):
		_heading("Receive")
		_note("Receive rules: next step.")  # TODO(receive)


func _events(type: String) -> Array[String]:
	match type:
		"button": return ["press", "release", "change"]
		"fader", "encoder": return ["change", "touch", "release"]
		"image": return ["press"]
	return []


func _changed() -> void:
	edited.emit(_widget["id"])


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


func _int_field(label: String, dict: Dictionary, key: String, min_value := -100000) -> void:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = 100000
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


func _choice(label: String, dict: Dictionary, key: String, options: Array) -> void:
	var o := OptionButton.new()
	for opt: String in options:
		o.add_item(opt)
	o.selected = maxi(0, options.find(dict.get(key, options[0])))
	o.item_selected.connect(func(i: int) -> void:
		dict[key] = options[i]
		_changed())
	_row(label, o)


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
		show_widget.call_deferred(_pkg, _widget)
		return
	_widget["id"] = new_id
	id_changed.emit(new_id)
