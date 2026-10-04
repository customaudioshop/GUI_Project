extends Control
## Opens a package and runs its first page full screen.
##
## The package's layout whose shape is closest to the screen is shown, and the
## choice is made again whenever the window changes shape: a foldable opening
## or closing, a phone turning. Widget values and the current page carry over,
## because a widget id names the same control in every layout.
##
## The window is scaled with Godot's own stretch settings: the content size is
## the layout's base resolution and the aspect rule is its "fit" value, so
## every widget keeps the position it had in the Builder.
##
## Rough frame: widget events are only logged. GuiScript, device connections
## and receive rules come next.
##
## A package can be given on the command line:  godot --path gui-player -- my.guipkg.json

const LAST_PATH_FILE := "user://last_package.txt"

var pkg: Dictionary
var layout: Dictionary
var page_id := ""
var _values := {}          ## widget id (or "id.part") -> last value, kept across layout switches
var _page_view: GuiPageView
var _open_dialog := FileDialog.new()


func _ready() -> void:
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.use_native_dialog = true
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = PackedStringArray(["*.guipkg.json ; GUI package"])
	_open_dialog.file_selected.connect(_open)
	add_child(_open_dialog)
	get_window().size_changed.connect(_on_window_resized)

	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else _last_path()
	if path.is_empty() or not _open(path):
		_show_start_screen()


func _last_path() -> String:
	return FileAccess.get_file_as_string(LAST_PATH_FILE).strip_edges()


## Shown until a package is opened.
func _show_start_screen() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var l := Label.new()
	l.text = "GUI Player"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 32)
	box.add_child(l)
	var b := Button.new()
	b.text = "Open package"
	b.pressed.connect(func() -> void: _open_dialog.popup_centered_ratio(0.6))
	box.add_child(b)
	add_child(box)


func _open(path: String) -> bool:
	var error: Array[String] = []
	var loaded := GuiPackage.load_file(path, error)
	if loaded.is_empty():
		push_warning(error[0] if not error.is_empty() else "cannot open " + path)
		return false
	# TODO(guiscript): re-check every script and skip the ones with errors
	var f := FileAccess.open(LAST_PATH_FILE, FileAccess.WRITE)
	if f:
		f.store_string(path)
	for child in get_children():
		if child != _open_dialog:
			child.queue_free()
	pkg = loaded
	GuiAssets.base_dir = path.get_base_dir()
	_values.clear()
	_set_orientation_policy()
	_use_layout(GuiPackage.pick_layout(pkg, Vector2(get_window().size)))
	show_page(layout["pages"][0]["id"])
	return true


## With layouts for both orientations the device may turn freely and the
## layout follows; with only one, the screen is locked to it.
func _set_orientation_policy() -> void:
	var kinds := {}
	for l: Dictionary in pkg["layouts"]:
		kinds[l["screen"].get("orientation", "landscape")] = true
	var orientation := DisplayServer.SCREEN_SENSOR
	if kinds.size() == 1:
		orientation = (DisplayServer.SCREEN_PORTRAIT if kinds.has("portrait")
				else DisplayServer.SCREEN_LANDSCAPE)
	DisplayServer.screen_set_orientation(orientation)


func _on_window_resized() -> void:
	if pkg.is_empty():
		return
	var best := GuiPackage.pick_layout(pkg, Vector2(get_window().size))
	if not is_same(best, layout):
		_use_layout(best)
		show_page(page_id)


func _use_layout(new_layout: Dictionary) -> void:
	layout = new_layout
	var screen: Dictionary = layout["screen"]
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = GuiPackage.screen_size(layout)
	window.content_scale_aspect = (Window.CONTENT_SCALE_ASPECT_EXPAND
			if screen.get("fit", "keep") == "expand" else Window.CONTENT_SCALE_ASPECT_KEEP)
	# The letterbox bars are the window's clear colour.
	RenderingServer.set_default_clear_color(
			Color.from_string(str(screen.get("background", "#1E1E1E")), Color(0.12, 0.12, 0.12)))
	# TODO(fit): with "expand", move widgets by their anchor into the extra space
	# TODO(safe area): keep widgets clear of notches, rounded corners and the
	# foldable hinge (DisplayServer.get_display_safe_area / cutouts)


## Switches to page [param id] in the current layout. GuiScript's `page` command will
## call this.
func show_page(id: String) -> void:
	var pages: Array = layout["pages"]
	var page: Dictionary = pages[0]
	for p: Dictionary in pages:
		if p["id"] == id:
			page = p
	if page["id"] != id:
		push_warning("no page '%s' in layout '%s'" % [id, layout["name"]])
	page_id = page["id"]
	if _page_view:
		_page_view.queue_free()
	_page_view = GuiPageView.new()
	_page_view.widget_event.connect(_on_widget_event)
	add_child(_page_view)
	_page_view.build(pkg, layout, page, true)
	for key: String in _values:
		# "eq1.inner" is part "inner" of widget eq1.
		var id_part := key.split(".")
		var view := _page_view.get_view(id_part[0])
		if view:
			view.set_value_silently(_values[key], id_part[1] if id_part.size() > 1 else "")


func _on_widget_event(widget_id: String, event: String, value: float) -> void:
	_values[widget_id] = value
	# TODO(guiscript): run widget.on[event] with $value
	print("%s.%s  value=%s" % [widget_id, event, snappedf(value, 0.001)])
