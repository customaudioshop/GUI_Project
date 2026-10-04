extends Control
## The Builder screen: toolbar, widget palette, canvas and inspector, plus the
## package file and its undo history.
##
## A package can hold several layouts (tablet, phone, foldable …). The canvas
## edits one of them; the toolbar switches between them.
##
## Undo keeps a snapshot of the whole package after every edit. Packages are
## small (a few hundred widgets at most), so this is simpler than recording
## each kind of change and cannot miss one.

const HISTORY_LIMIT := 200
const FILE_FILTER := "*.guipkg.json ; GUI package"

var pkg: Dictionary
var file_path := ""

var _history: Array[String] = []
var _history_at := -1

@onready var _sub_bar: Control = $"Top Menu/SubBar"
@onready var _work_area: Control = $Work_Area

var _canvas := preload("res://scripts/builder/canvas.gd").new()
var _inspector := preload("res://scripts/builder/inspector.gd").new()
var _resolution := preload("res://scripts/builder/resolution_dialog.gd").new()
var _hierarchy := preload("res://scripts/builder/hierarchy.gd").new()
enum Ask { NEW, CHANGE, ADD_LAYOUT }
var _asking := Ask.NEW
var _layout_index := 0
var _layout_select := OptionButton.new()
var _page_select := OptionButton.new()
var _status := Label.new()
var _open_dialog := FileDialog.new()
var _save_dialog := FileDialog.new()


func _ready() -> void:
	_build_toolbar()
	_build_work_area()
	_build_dialogs()
	# FHD is the default target; the dialog below offers the others.
	_set_package(GuiPackage.create(1920, 1080, "landscape", "PC FHD"), "")
	# The first thing to decide for a new layout is the target screen.
	_ask_new.call_deferred()


## --- layout of the screen -------------------------------------------------------

func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 24
	bar.add_theme_constant_override("separation", 8)
	_sub_bar.add_child(bar)

	for item in [["New", _ask_new], ["Open", _show_open],
			["Save", _save], ["Save As", _show_save], [],
			["Undo", _undo], ["Redo", _redo], [],
			["Group", _group, "Select several widgets (drag a box over them or Shift+click), then Group (Ctrl+G)"],
			["Ungroup", _ungroup, "Break the selected group back into its widgets (Ctrl+Shift+G)"],
			["Duplicate", _duplicate, "Copy the selection into the nearest free cells; a group's names and numbers go up by one (Ctrl+D)"], [],
			["Resolution", _ask_resolution], [],
			["Play", _play, "Try this layout as the Player runs it, without saving (F5)"], []]:
		if item.is_empty():
			bar.add_child(VSeparator.new())
			continue
		var b := Button.new()
		b.text = item[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(item[1])
		if item.size() > 2:
			b.tooltip_text = item[2]
		bar.add_child(b)

	var ll := Label.new()
	ll.text = "Layout"
	bar.add_child(ll)
	_layout_select.focus_mode = Control.FOCUS_NONE
	_layout_select.item_selected.connect(func(i: int) -> void:
		_layout_index = i
		_canvas.select_many([])
		_refresh_all(_canvas.page_index))
	bar.add_child(_layout_select)
	var add_layout := Button.new()
	add_layout.text = "+ Layout"
	add_layout.tooltip_text = "Copy this layout for another screen (phone, foldable …)"
	add_layout.focus_mode = Control.FOCUS_NONE
	add_layout.pressed.connect(_ask_add_layout)
	bar.add_child(add_layout)
	bar.add_child(VSeparator.new())

	var l := Label.new()
	l.text = "Page"
	bar.add_child(l)
	_page_select.focus_mode = Control.FOCUS_NONE
	_page_select.item_selected.connect(func(i: int) -> void:
		_canvas.show_page(pkg, _layout(), i)
		_hierarchy.show_page(_canvas.page()))
	bar.add_child(_page_select)
	var add_page := Button.new()
	add_page.text = "+ Page"
	add_page.focus_mode = Control.FOCUS_NONE
	add_page.pressed.connect(_add_page)
	bar.add_child(add_page)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_status.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	bar.add_child(_status)
	var right_pad := Control.new()
	right_pad.custom_minimum_size.x = 16
	bar.add_child(right_pad)


func _build_work_area() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	_work_area.add_child(row)

	var palette := VBoxContainer.new()
	palette.custom_minimum_size.x = 320
	palette.add_theme_constant_override("separation", 6)
	# The palette lists GuiWidgetTypes by category.
	for category: Array in GuiWidgetTypes.CATEGORIES:
		var types := GuiWidgetTypes.in_category(category[0])
		if types.is_empty():
			continue
		var heading := Label.new()
		heading.text = "  " + category[1]
		palette.add_child(heading)
		var flow := HFlowContainer.new()
		for type in types:
			for preset: Array in GuiWidgetTypes.presets(type):
				flow.add_child(_palette_item(type, Vector2i(preset[0], preset[1])))
		palette.add_child(flow)
	var tree_heading := Label.new()
	tree_heading.text = "  Hierarchy"
	palette.add_child(tree_heading)
	_hierarchy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hierarchy.picked.connect(func(id: String) -> void: _canvas.select(id))
	_hierarchy.move_requested.connect(_move_widget)
	palette.add_child(_hierarchy)
	row.add_child(_padded(palette))

	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.edited.connect(_record)
	_canvas.selection_changed.connect(_on_selection)
	row.add_child(_canvas)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 440
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 6)
	_inspector.edited.connect(func(id: String) -> void:
		_canvas.refresh_widget(id)
		_record())
	_inspector.id_changed.connect(func(id: String) -> void:
		_canvas.show_page(pkg, _layout(), _canvas.page_index)
		_canvas.select(id)
		_record())
	_inspector.layout_edited.connect(func() -> void:
		_canvas.show_page(pkg, _layout(), _canvas.page_index)
		_record())
	scroll.add_child(_inspector)
	row.add_child(_padded(scroll))


func _padded(content: Control) -> Control:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.add_child(content)
	return m


## A palette button that starts a drag carrying the widget type and size.
func _palette_item(type: String, size: Vector2i) -> Button:
	var info := GuiWidgetTypes.info(type)
	var b := Button.new()
	b.text = "%s  %dx%d" % [info.get("name", type), size.x, size.y]
	b.custom_minimum_size = Vector2(140, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Drag onto the screen"
	b.set_drag_forwarding(func(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = "+ " + info.get("name", type)
		b.set_drag_preview(preview)
		return {"kind": "new_widget", "type": type, "size": size},
		Callable(), Callable())
	return b


func _build_dialogs() -> void:
	_resolution.chosen.connect(_on_resolution_chosen)
	add_child(_resolution)

	for d: FileDialog in [_open_dialog, _save_dialog]:
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.use_native_dialog = true
		d.filters = PackedStringArray([FILE_FILTER])
		add_child(d)
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.file_selected.connect(_open)
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.file_selected.connect(_save_to)


## --- package and history ---------------------------------------------------------

func _set_package(new_pkg: Dictionary, path: String) -> void:
	pkg = new_pkg
	file_path = path
	_history.clear()
	_history_at = -1
	_layout_index = 0
	_record()
	_canvas.select_many([])
	_refresh_all(0)


func _layout() -> Dictionary:
	return pkg["layouts"][_layout_index]


func _refresh_all(page_index: int) -> void:
	_layout_index = clampi(_layout_index, 0, pkg["layouts"].size() - 1)
	_layout_select.clear()
	for layout: Dictionary in pkg["layouts"]:
		var s := GuiPackage.screen_size(layout)
		_layout_select.add_item("%s  (%d x %d)" % [layout["name"], s.x, s.y])
	_layout_select.selected = _layout_index
	var pages: Array = _layout()["pages"]
	_page_select.clear()
	for page: Dictionary in pages:
		_page_select.add_item(page["name"])
	page_index = clampi(page_index, 0, pages.size() - 1)
	_page_select.selected = page_index
	_canvas.show_page(pkg, _layout(), page_index)
	_hierarchy.show_page(_canvas.page())
	_on_selection(_canvas.selected_id)
	_update_status()


## Remembers the package as it is now, after an edit.
func _record() -> void:
	_history.resize(_history_at + 1)
	_history.append(JSON.stringify(pkg))
	if _history.size() > HISTORY_LIMIT:
		_history.pop_front()
	_history_at = _history.size() - 1
	_update_status()
	if not _canvas.layout.is_empty():
		_hierarchy.show_page(_canvas.page())
		_hierarchy.show_selection(_canvas.selected_id)


func _undo() -> void:
	if _history_at > 0:
		_restore(_history_at - 1)


func _redo() -> void:
	if _history_at < _history.size() - 1:
		_restore(_history_at + 1)


func _restore(index: int) -> void:
	_history_at = index
	pkg = JSON.parse_string(_history[index])
	GuiPackage.normalize(pkg)
	_refresh_all(_canvas.page_index)


func _update_status() -> void:
	var s := GuiPackage.screen_size(_layout())
	var file_name := file_path.get_file() if not file_path.is_empty() else "(unsaved)"
	_status.text = "%s   |   %d x %d %s" % [file_name, s.x, s.y, _layout()["screen"]["orientation"]]


func _on_selection(widget_id: String) -> void:
	if _canvas.layout.is_empty():
		return  # nothing shown yet
	var at := GuiPackage.locate(_canvas.page(), widget_id)
	_inspector.show_widget(pkg, _layout(), _canvas.page(), at.get("widget", {}),
			_canvas.is_strict(widget_id))
	_hierarchy.show_selection(widget_id)


## --- groups ----------------------------------------------------------------------

func _group() -> void:
	var group := GuiPackage.group_widgets(pkg, _canvas.page(), _canvas.selected_ids)
	if group.is_empty():
		return
	_after_structure_change(group["id"])


func _ungroup() -> void:
	var ids := GuiPackage.ungroup(_canvas.page(), _canvas.selected_id)
	if ids.is_empty():
		return
	_canvas.show_page(pkg, _layout(), _canvas.page_index)
	_canvas.select_many(ids)
	_record()


## Copies the selected widget or group next to itself, renumbering ids and
## params (ch1 -> ch2). See GuiPackage.duplicate_widget.
func _duplicate() -> void:
	if _canvas.selected_id.is_empty():
		return
	var copy := GuiPackage.duplicate_widget(pkg, _layout(), _canvas.page(), _canvas.selected_id)
	if not copy.is_empty():
		_after_structure_change(copy["id"])


## A row dragged in the hierarchy: reorder, or move into or out of a
## container (see GuiPackage.move_widget).
func _move_widget(widget_id: String, parent_id: String, index: int) -> void:
	var error: Array[String] = []
	var new_id := GuiPackage.move_widget(pkg, _layout(), _canvas.page(), widget_id, parent_id,
			index, error)
	if new_id.is_empty():
		OS.alert(error[0], "Move")
		return
	_after_structure_change(new_id)


func _after_structure_change(select_id: String) -> void:
	_canvas.show_page(pkg, _layout(), _canvas.page_index)
	_canvas.select(select_id)
	_record()


## --- play ------------------------------------------------------------------------

func _play() -> void:
	var window := preload("res://scripts/builder/play_window.gd").new()
	add_child(window)
	window.play(pkg, _layout_index, _canvas.page_index)
	window.popup_centered()


func _add_page() -> void:
	GuiPackage.add_page(pkg)
	_record()
	_refresh_all(_layout()["pages"].size() - 1)


## --- resolution --------------------------------------------------------------------

func _ask_new() -> void:
	# TODO(file): ask to save unsaved changes first
	_ask(Ask.NEW, "New package: target screen")


func _ask_resolution() -> void:
	_ask(Ask.CHANGE, "Change this layout's screen (widgets are rescaled)")


## A new layout starts as a rescaled copy of the current one, with the same
## widget ids, so it controls the same things.
func _ask_add_layout() -> void:
	_ask(Ask.ADD_LAYOUT, "Add layout: copy '%s' for another screen" % _layout()["name"])


func _ask(kind: Ask, dialog_title: String) -> void:
	_asking = kind
	var s := GuiPackage.screen_size(_layout())
	_resolution.ask(dialog_title, s.x, s.y, _layout()["screen"]["orientation"])


func _on_resolution_chosen(width: int, height: int, orientation: String, preset: String) -> void:
	match _asking:
		Ask.NEW:
			_set_package(GuiPackage.create(width, height, orientation, preset), "")
			return
		Ask.CHANGE:
			GuiPackage.rescale(_layout(), width, height)
			_layout()["screen"]["orientation"] = orientation
		Ask.ADD_LAYOUT:
			GuiPackage.copy_layout(pkg, _layout(), preset, width, height, orientation)
			_layout_index = pkg["layouts"].size() - 1
			_canvas.select_many([])
	_record()
	_refresh_all(_canvas.page_index)


## --- files ---------------------------------------------------------------------------

func _show_open() -> void:
	_open_dialog.popup_centered_ratio(0.6)


func _show_save() -> void:
	_save_dialog.popup_centered_ratio(0.6)


func _open(path: String) -> void:
	var error: Array[String] = []
	var loaded := GuiPackage.load_file(path, error)
	if loaded.is_empty():
		OS.alert(error[0] if not error.is_empty() else "Cannot open %s" % path, "Open")
		return
	_set_package(loaded, path)


func _save() -> void:
	if file_path.is_empty():
		_show_save()
	else:
		_save_to(file_path)


func _save_to(path: String) -> void:
	if not path.ends_with(".guipkg.json"):
		path = path.trim_suffix(".json") + ".guipkg.json"
	var err := GuiPackage.save_file(pkg, path)
	if err != OK:
		OS.alert("Cannot save %s (%s)" % [path, error_string(err)], "Save")
		return
	file_path = path
	_update_status()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F5:
		_play()
		get_viewport().set_input_as_handled()
		return
	if not event.is_command_or_control_pressed():
		return
	match event.keycode:
		KEY_Z:
			if event.shift_pressed:
				_redo()
			else:
				_undo()
		KEY_Y:
			_redo()
		KEY_G:
			if event.shift_pressed:
				_ungroup()
			else:
				_group()
		KEY_D:
			_duplicate()
		KEY_S:
			_save()
		KEY_O:
			_show_open()
		KEY_N:
			_ask_new()
		_:
			return
	get_viewport().set_input_as_handled()
