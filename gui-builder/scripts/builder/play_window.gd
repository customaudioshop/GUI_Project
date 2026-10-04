extends Window
## Play mode: the layout being edited, running as the Player runs it, without
## saving first.
##
## It draws with the same GuiPageView as the Player, interactive, on a copy
## of the package, so nothing done here changes the edit or its undo history.
## Values carry over between pages, as in the Player. Every widget event is
## listed at the bottom so the user can see what would be sent.
##
## Rough frame: events are only listed. GuiScript and device connections
## come with the Player's.

const LOG_LIMIT := 200

var _pkg: Dictionary
var _layout: Dictionary
var _values := {}           ## widget id (or "id.part") -> last value
var _page_select := OptionButton.new()
var _stage := Control.new() ## Holds the page, scaled to fit.
var _page_view: GuiPageView
var _log := ItemList.new()


func _init() -> void:
	title = "Play"
	close_requested.connect(queue_free)
	min_size = Vector2i(640, 480)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "  Page"
	bar.add_child(l)
	_page_select.focus_mode = Control.FOCUS_NONE
	_page_select.item_selected.connect(func(i: int) -> void: _show_page(i))
	bar.add_child(_page_select)
	var hint := Label.new()
	hint.text = "   Touch the controls to try them. Nothing here changes the layout.   Esc closes."
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	column.add_child(bar)

	_stage.clip_contents = true
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.resized.connect(_fit)
	column.add_child(_stage)

	var log_heading := Label.new()
	log_heading.text = "  Events"
	column.add_child(log_heading)
	_log.custom_minimum_size.y = 140
	_log.focus_mode = Control.FOCUS_NONE
	column.add_child(_log)


## Starts playing [param layout_index] of a copy of [param pkg] on page
## [param page_index].
func play(pkg: Dictionary, layout_index: int, page_index: int) -> void:
	# It opens inside the Builder's window, so it is sized from that.
	size = Vector2i(get_tree().root.get_visible_rect().size * 0.85).max(min_size)
	_pkg = GuiPackage.deep_copy(pkg)
	_layout = _pkg["layouts"][layout_index]
	var s := GuiPackage.screen_size(_layout)
	title = "Play - %s (%d x %d)" % [_layout["name"], s.x, s.y]
	_page_select.clear()
	for page: Dictionary in _layout["pages"]:
		_page_select.add_item(page["name"])
	_page_select.selected = page_index
	_show_page(page_index)


func _show_page(index: int) -> void:
	if _page_view:
		_page_view.queue_free()
	_page_view = GuiPageView.new()
	_page_view.widget_event.connect(_on_widget_event)
	_stage.add_child(_page_view)
	_page_view.build(_pkg, _layout, _layout["pages"][index], true)
	for key: String in _values:
		var id_part := key.split(".")
		var view := _page_view.get_view(id_part[0])
		if view:
			view.set_value_silently(_values[key], id_part[1] if id_part.size() > 1 else "")
	_fit()


## The page at its base size, scaled to fit the stage and centred, as the
## Player's "keep" fit does.
func _fit() -> void:
	if _page_view == null:
		return
	var base := Vector2(GuiPackage.screen_size(_layout))
	var zoom := maxf(0.05, minf(_stage.size.x / base.x, _stage.size.y / base.y))
	_page_view.scale = Vector2(zoom, zoom)
	_page_view.position = ((_stage.size - base * zoom) / 2.0).floor()


func _on_widget_event(widget_id: String, event: String, value: float) -> void:
	_values[widget_id] = value
	# TODO(guiscript): run the widget's script for this event, as the Player will
	_log.add_item("%s   %s   %s" % [widget_id, event, snappedf(value, 0.001)])
	if _log.item_count > LOG_LIMIT:
		_log.remove_item(0)
	_log.ensure_current_is_visible()
	_log.select(_log.item_count - 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_F5]:
		close_requested.emit()
		get_viewport().set_input_as_handled()
