extends Control
## The editing surface: the current page at its base resolution, scaled to fit,
## with drop, select, move and resize.
##
## Widgets on the page do not take the mouse here; this control hit-tests them
## itself so a click can mean "select" or "move" rather than "press".
##
## Selection and groups work like most design tools: a click picks the
## outermost widget under the mouse, a double click goes one level into a
## group, and Shift+click adds or removes siblings.

## A finished edit (drop, move, resize, delete). The main screen records it
## for undo.
signal edited
## The selection changed. [param widget_id] is the primary (last picked) one.
signal selection_changed(widget_id: String)

const MARGIN := 40.0
const HANDLE := 14.0          ## Resize handle size in screen pixels.
const SELECT_COLOR := Color(1.0, 0.75, 0.2)
const GROUP_COLOR := Color(0.4, 0.7, 1.0, 0.6)

var pkg: Dictionary
var layout: Dictionary                 ## The layout being edited, inside pkg.
var page_index := 0
var selected_id := ""                  ## Primary selection; the inspector shows it.
var selected_ids: Array[String] = []   ## All selected widgets, siblings only.

var _page_view := GuiPageView.new()
var _overlay := Control.new()
var _zoom := 1.0

enum Drag { NONE, MOVE, RESIZE }
var _drag := Drag.NONE
var _drag_from := Vector2.ZERO     ## Page coordinates where the drag started.
var _drag_orig := {}               ## widget id -> Rect2 in its own list's coordinates
var _drag_changed := false


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	add_child(_page_view)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(_layout)


func show_page(package: Dictionary, layout_data: Dictionary, index: int) -> void:
	pkg = package
	layout = layout_data
	page_index = clampi(index, 0, layout["pages"].size() - 1)
	_page_view.build(layout, page(), false)
	var still := selected_ids.filter(func(id: String) -> bool: return not _find(id).is_empty())
	select_many(still, selected_id if selected_id in still else "")
	_layout()


func page() -> Dictionary:
	return layout["pages"][page_index]


func select(widget_id: String) -> void:
	select_many([widget_id] if not widget_id.is_empty() else [], widget_id)


func select_many(ids: Array, primary := "") -> void:
	selected_ids.assign(ids)
	selected_id = primary if primary in ids else (ids.back() if not ids.is_empty() else "")
	_overlay.queue_redraw()
	selection_changed.emit(selected_id)


## Call after changing a widget's Dictionary from outside (the inspector).
func refresh_widget(widget_id: String) -> void:
	var view := _page_view.get_view(widget_id)
	if view:
		view.refresh()
	_overlay.queue_redraw()


func _find(widget_id: String) -> Dictionary:
	if pkg.is_empty() or widget_id.is_empty():
		return {}
	return GuiPackage.locate(page(), widget_id).get("widget", {})


## --- layout ------------------------------------------------------------------

func _layout() -> void:
	if pkg.is_empty():
		return
	var base := Vector2(GuiPackage.screen_size(layout))
	var room := size - Vector2(MARGIN, MARGIN) * 2.0
	# TODO(canvas): mouse-wheel zoom and panning
	_zoom = maxf(0.05, minf(room.x / base.x, room.y / base.y))
	_page_view.scale = Vector2(_zoom, _zoom)
	_page_view.position = ((size - base * _zoom) / 2.0).floor()
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	queue_redraw()
	_overlay.queue_redraw()


func _to_page(screen: Vector2) -> Vector2:
	return (screen - _page_view.position) / _zoom


func _to_screen(page_rect: Rect2) -> Rect2:
	return Rect2(_page_view.position + page_rect.position * _zoom, page_rect.size * _zoom)


func _snap(v: float) -> int:
	var editor: Dictionary = pkg.get("editor", {})
	var grid := int(editor.get("grid", 10))
	if editor.get("snap", true) and grid > 1:
		return roundi(v / grid) * grid
	return roundi(v)


## --- drawing -----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.09, 0.1))
	if pkg.is_empty():
		return
	# Shadow of the device screen, so its edge reads clearly.
	var screen := _to_screen(Rect2(Vector2.ZERO, Vector2(GuiPackage.screen_size(layout))))
	draw_rect(screen.grow(3), Color(0.3, 0.3, 0.33))


func _draw_overlay() -> void:
	if pkg.is_empty():
		return
	# Groups are invisible on the device, so outline them here.
	GuiPackage.walk(page()["widgets"], func(w: Dictionary) -> void:
		if w["type"] == "group":
			_overlay.draw_rect(_to_screen(GuiPackage.page_rect(page(), w["id"])), GROUP_COLOR, false, 1.0))
	for id in selected_ids:
		var r := _to_screen(GuiPackage.page_rect(page(), id))
		_overlay.draw_rect(r, SELECT_COLOR, false, 2.0)
	if selected_ids.size() == 1:
		_overlay.draw_rect(_handle_rect(_to_screen(GuiPackage.page_rect(page(), selected_id))), SELECT_COLOR)


func _handle_rect(screen_rect: Rect2) -> Rect2:
	return Rect2(screen_rect.end - Vector2(HANDLE, HANDLE) / 2.0, Vector2(HANDLE, HANDLE))


## --- mouse and keys ------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if pkg.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			if event.double_click:
				_enter_group(event.position)
			else:
				_begin_drag(event.position, event.shift_pressed)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		_continue_drag(event.position)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and not selected_ids.is_empty():
			_delete_selected()
			accept_event()


## What a plain click at [param page_pos] picks: inside the group that holds
## the current selection when the click lands in it, otherwise the outermost
## widget.
func _pick(page_pos: Vector2) -> Dictionary:
	if not selected_id.is_empty():
		var at := GuiPackage.locate(page(), selected_id)
		var parent: Dictionary = at.get("parent", {})
		if not parent.is_empty() and GuiPackage.page_rect(page(), parent["id"]).has_point(page_pos):
			var hit := _page_view.widget_at(page_pos, parent["children"], at["origin"])
			if not hit.is_empty():
				return hit
	return _page_view.widget_at(page_pos)


func _begin_drag(screen_pos: Vector2, add: bool) -> void:
	if selected_ids.size() == 1:
		var r := _to_screen(GuiPackage.page_rect(page(), selected_id))
		if _handle_rect(r).grow(4).has_point(screen_pos):
			_start(Drag.RESIZE, screen_pos)
			return
	var hit := _pick(_to_page(screen_pos))
	var id: String = hit.get("id", "")
	if add and not id.is_empty():
		_toggle_in_selection(id)
	elif id.is_empty():
		select("")
	elif not id in selected_ids:
		select(id)
	else:
		select_many(selected_ids, id)
	if not id.is_empty() and id in selected_ids:
		_start(Drag.MOVE, screen_pos)


## Shift+click: only widgets in the same list can be selected together, so
## they can be moved, grouped or deleted as one.
func _toggle_in_selection(id: String) -> void:
	if id in selected_ids:
		var rest := selected_ids.duplicate()
		rest.erase(id)
		select_many(rest)
		return
	if not selected_ids.is_empty():
		var list_a: Array = GuiPackage.locate(page(), selected_ids[0])["list"]
		var list_b: Array = GuiPackage.locate(page(), id)["list"]
		if not is_same(list_a, list_b):
			select(id)
			return
	select_many(selected_ids + [id], id)


## Double click: select the widget under the mouse one level inside the
## selected group.
func _enter_group(screen_pos: Vector2) -> void:
	var w := _find(selected_id)
	if w.get("type") != "group":
		return
	var origin := GuiPackage.page_rect(page(), selected_id).position
	var hit := _page_view.widget_at(_to_page(screen_pos), w["children"], origin)
	if not hit.is_empty():
		select(hit["id"])


func _start(kind: Drag, screen_pos: Vector2) -> void:
	_drag = kind
	_drag_from = _to_page(screen_pos)
	_drag_orig.clear()
	for id in selected_ids:
		var w := _find(id)
		_drag_orig[id] = Rect2(w["x"], w["y"], w["w"], w["h"])
	_drag_changed = false


func _continue_drag(screen_pos: Vector2) -> void:
	var delta := _to_page(screen_pos) - _drag_from
	for id: String in _drag_orig:
		var w := _find(id)
		var orig: Rect2 = _drag_orig[id]
		if _drag == Drag.MOVE:
			w["x"] = _snap(orig.position.x + delta.x)
			w["y"] = _snap(orig.position.y + delta.y)
		else:
			w["w"] = maxi(GuiPackage.MIN_WIDGET_SIZE, _snap(orig.end.x + delta.x) - int(w["x"]))
			w["h"] = maxi(GuiPackage.MIN_WIDGET_SIZE, _snap(orig.end.y + delta.y) - int(w["y"]))
		refresh_widget(id)
	_drag_changed = true
	selection_changed.emit(selected_id)


func _end_drag() -> void:
	if _drag != Drag.NONE and _drag_changed:
		edited.emit()
	_drag = Drag.NONE


func _delete_selected() -> void:
	for id in selected_ids:
		var at := GuiPackage.locate(page(), id)
		if not at.is_empty():
			(at["list"] as Array).erase(at["widget"])
	select("")
	show_page(pkg, layout, page_index)
	edited.emit()


## --- drop from the palette -------------------------------------------------------

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return not pkg.is_empty() and data is Dictionary and data.get("kind") == "new_widget"


## A widget dropped onto a group goes inside it.
func _drop_data(at: Vector2, data: Variant) -> void:
	var p := _to_page(at)
	var w := GuiPackage.new_widget(pkg, data["type"], 0, 0)
	var list: Array = page()["widgets"]
	var origin := Vector2.ZERO
	var target := _page_view.widget_at(p)
	while target.get("type") == "group":
		origin += Vector2(target["x"], target["y"])
		list = target["children"]
		# ch1_encoder1 rather than encoder7, so a duplicate of ch1 renames it
		# to ch2_encoder1.
		w["id"] = GuiPackage.unique_id(pkg, "%s_%s" % [target["id"], data["type"]])
		target = _page_view.widget_at(p, list, origin)
	# Centre the new widget on the drop point.
	w["x"] = _snap(p.x - origin.x - w["w"] / 2.0)
	w["y"] = _snap(p.y - origin.y - w["h"] / 2.0)
	list.append(w)
	show_page(pkg, layout, page_index)
	select(w["id"])
	edited.emit()
