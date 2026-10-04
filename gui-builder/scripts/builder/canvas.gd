extends Control
## The editing surface: the current page at its base resolution, scaled to fit,
## with drop, select, move and resize.
##
## Widgets are blocks on a grid (GuiGrid). Moving and resizing go cell by
## cell; a block may not cover another block or leave its grid. While a drag
## would break that, the block is outlined in red and snaps back on release.
## A drop shows a ghost of the cells the new block will take.
##
## Widgets on the page do not take the mouse here; this control hit-tests them
## itself so a click can mean "select" or "move" rather than "press".
##
## Selection and containers work like most design tools: a click picks the
## outermost widget under the mouse, a double click goes one level into a
## panel or group, Shift+click adds or removes siblings, and dragging from an
## empty spot draws a box that selects every block it touches.

## A finished edit (drop, move, resize, delete). The main screen records it
## for undo.
signal edited
## The selection changed. [param widget_id] is the primary (last picked) one.
signal selection_changed(widget_id: String)

const MARGIN := 40.0
const HANDLE := 14.0          ## Resize handle size in screen pixels.
const SELECT_COLOR := Color(1.0, 0.75, 0.2)
const GROUP_COLOR := Color(0.4, 0.7, 1.0, 0.6)
const GRID_COLOR := Color(1, 1, 1, 0.06)
const ACTIVE_GRID_COLOR := Color(0.4, 0.7, 1.0, 0.25)
const BAD_COLOR := Color(1.0, 0.3, 0.3)
const GHOST_COLOR := Color(0.4, 0.85, 0.5, 0.35)
const MARQUEE_COLOR := Color(1.0, 0.75, 0.2, 0.15)

var pkg: Dictionary
var layout: Dictionary                 ## The layout being edited, inside pkg.
var page_index := 0
var selected_id := ""                  ## Primary selection; the inspector shows it.
var selected_ids: Array[String] = []   ## All selected widgets, siblings only.

var _page_view := GuiPageView.new()
var _overlay := Control.new()
var _zoom := 1.0

enum Drag { NONE, MOVE, RESIZE, MARQUEE }
var _drag := Drag.NONE
var _drag_from := Vector2.ZERO     ## Page coordinates where the drag started.
var _drag_orig := {}               ## widget id -> Rect2i cells before the drag
var _drag_changed := false
var _drag_ok := true               ## False while the dragged blocks do not fit.
var _drop_ghost := {}              ## {"parent", "cells"} while dragging from the palette
var _marquee := Rect2()            ## Selection box in page coordinates.
var _marquee_parent := ""          ## The container whose blocks the box selects.
var _marquee_base: Array[String] = []  ## Already selected when the box started (Shift).


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
	_page_view.build(pkg, layout, page(), false)
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
func refresh_widget(_widget_id: String) -> void:
	_page_view.relayout()
	_overlay.queue_redraw()


## True when the widget's container keeps blocks to their types' sizes.
func is_strict(widget_id: String) -> bool:
	return _box(_parent_id(widget_id)).get("strict", true)


func _find(widget_id: String) -> Dictionary:
	if pkg.is_empty() or widget_id.is_empty():
		return {}
	return GuiPackage.locate(page(), widget_id).get("widget", {})


func _rect(widget_id: String) -> Rect2:
	return _page_view.rects().get(widget_id, {}).get("rect", Rect2())


func _parent_id(widget_id: String) -> String:
	return _page_view.rects().get(widget_id, {}).get("parent", "")


## The grid with id [param container_id] ("" is the page).
func _box(container_id: String) -> Dictionary:
	return _page_view.rects().get(container_id, {})


## The blocks on the grid of [param container_id].
func _list(container_id: String) -> Array:
	return page()["widgets"] if container_id.is_empty() else _find(container_id)["children"]


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
	_draw_grid("", GRID_COLOR)
	# The grid being worked in: where a drop lands, or the selection's container.
	var active := ""
	if not _drop_ghost.is_empty():
		active = _drop_ghost["parent"]
	elif not selected_id.is_empty():
		active = _parent_id(selected_id)
	if not active.is_empty():
		_draw_grid(active, ACTIVE_GRID_COLOR)

	# Groups are invisible on the device, so outline them here.
	GuiPackage.walk(page()["widgets"], func(w: Dictionary) -> void:
		if w["type"] == "group":
			_overlay.draw_rect(_to_screen(_rect(w["id"])), GROUP_COLOR, false, 1.0))
	_draw_conflicts()

	var color := SELECT_COLOR if _drag_ok else BAD_COLOR
	for id in selected_ids:
		_overlay.draw_rect(_to_screen(_rect(id)), color, false, 2.0)
	if selected_ids.size() == 1:
		_overlay.draw_rect(_handle_rect(_to_screen(_rect(selected_id))), color)

	if not _drop_ghost.is_empty():
		var r := GuiGrid.cell_rect(_box(_drop_ghost["parent"]), _drop_ghost["cells"])
		_overlay.draw_rect(_to_screen(r), GHOST_COLOR)
	if _drag == Drag.MARQUEE:
		_overlay.draw_rect(_to_screen(_marquee), MARQUEE_COLOR)
		_overlay.draw_rect(_to_screen(_marquee), SELECT_COLOR, false, 1.0)


func _draw_grid(container_id: String, color: Color) -> void:
	var box := _box(container_id)
	if box.is_empty():
		return
	for row in box["rows"]:
		for col in box["cols"]:
			var r := GuiGrid.cell_rect(box, Rect2i(col, row, 1, 1))
			_overlay.draw_rect(_to_screen(r), color, false, 1.0)


## Blocks that overlap or stick out (hand-edited or migrated packages).
func _draw_conflicts() -> void:
	var check := func(container_id: String) -> void:
		for id in GuiGrid.conflicts(_box(container_id), _list(container_id)):
			_overlay.draw_rect(_to_screen(_rect(id)).grow(-2), BAD_COLOR, false, 2.0)
	check.call("")
	GuiPackage.walk(page()["widgets"], func(w: Dictionary) -> void:
		if w.has("children"):
			check.call(w["id"]))


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
				_enter_container(event.position)
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
		elif event.keycode == KEY_A and event.is_command_or_control_pressed():
			# Everything in the selection's container, or on the page.
			var parent := _parent_id(selected_id) if not selected_id.is_empty() else ""
			select_many(_list(parent).map(func(w: Dictionary) -> String: return w["id"]))
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and not _drop_ghost.is_empty():
		_drop_ghost = {}
		_overlay.queue_redraw()


## What a plain click at [param page_pos] picks: inside the container that
## holds the current selection when the click lands in it, otherwise the
## outermost widget.
func _pick(page_pos: Vector2) -> Dictionary:
	if not selected_id.is_empty():
		var parent := _parent_id(selected_id)
		if not parent.is_empty() and _rect(parent).has_point(page_pos):
			var hit := _page_view.widget_at(page_pos, _list(parent))
			if not hit.is_empty():
				return hit
	return _page_view.widget_at(page_pos)


func _begin_drag(screen_pos: Vector2, add: bool) -> void:
	if selected_ids.size() == 1:
		var r := _to_screen(_rect(selected_id))
		if _handle_rect(r).grow(4).has_point(screen_pos):
			_start(Drag.RESIZE, screen_pos)
			return
	var hit := _pick(_to_page(screen_pos))
	var id: String = hit.get("id", "")
	if id.is_empty():
		_start_marquee(screen_pos, add)
		return
	if add:
		_toggle_in_selection(id)
	elif not id in selected_ids:
		select(id)
	else:
		select_many(selected_ids, id)
	if not id.is_empty() and id in selected_ids:
		_start(Drag.MOVE, screen_pos)


## Shift+click: only widgets in the same container can be selected together,
## so they can be moved, grouped or deleted as one.
func _toggle_in_selection(id: String) -> void:
	if id in selected_ids:
		var rest := selected_ids.duplicate()
		rest.erase(id)
		select_many(rest)
		return
	if not selected_ids.is_empty() and _parent_id(selected_ids[0]) != _parent_id(id):
		select(id)
		return
	select_many(selected_ids + [id], id)


## Double click: select the widget under the mouse one level inside the
## selected panel or group.
func _enter_container(screen_pos: Vector2) -> void:
	var w := _find(selected_id)
	if not w.has("children"):
		return
	var hit := _page_view.widget_at(_to_page(screen_pos), w["children"])
	if not hit.is_empty():
		select(hit["id"])


## A box from an empty spot. It selects blocks of the container it starts
## in; with Shift it adds to the selection.
func _start_marquee(screen_pos: Vector2, add: bool) -> void:
	var p := _to_page(screen_pos)
	_marquee_parent = _container_at(p)
	_marquee_base.clear()
	if add and not selected_ids.is_empty() and _parent_id(selected_ids[0]) == _marquee_parent:
		_marquee_base.assign(selected_ids)
	select_many(_marquee_base)
	_marquee = Rect2(p, Vector2.ZERO)
	_drag = Drag.MARQUEE


func _continue_marquee(screen_pos: Vector2) -> void:
	_marquee.size = _to_page(screen_pos) - _marquee.position
	var box := _marquee.abs()
	var ids: Array[String] = _marquee_base.duplicate()
	for w: Dictionary in _list(_marquee_parent):
		if box.intersects(_rect(w["id"])) and not w["id"] in ids:
			ids.append(w["id"])
	select_many(ids)


func _start(kind: Drag, screen_pos: Vector2) -> void:
	_drag = kind
	_drag_from = _to_page(screen_pos)
	_drag_orig.clear()
	for id in selected_ids:
		_drag_orig[id] = GuiGrid.cells_of(_find(id))
	_drag_changed = false
	_drag_ok = true


func _continue_drag(screen_pos: Vector2) -> void:
	if _drag == Drag.MARQUEE:
		_continue_marquee(screen_pos)
		return
	var parent := _parent_id(selected_id)
	var box := _box(parent)
	var steps := ((_to_page(screen_pos) - _drag_from) / GuiGrid.pitch(box)).round()
	var delta := Vector2i(steps)
	var ok := true
	for id: String in _drag_orig:
		var w := _find(id)
		var orig: Rect2i = _drag_orig[id]
		var cells := orig
		if _drag == Drag.MOVE:
			cells.position += delta
		else:
			var want := (orig.size + delta).max(Vector2i.ONE)
			cells.size = GuiWidgetTypes.nearest_size(w["type"], want) if box["strict"] else want
		if cells != GuiGrid.cells_of(w):
			GuiGrid.set_cells(w, cells)
			_drag_changed = true
		ok = ok and GuiGrid.fits(box, _list(parent), cells, _drag_orig.keys())
	_drag_ok = ok
	_page_view.relayout()
	_overlay.queue_redraw()
	selection_changed.emit(selected_id)


func _end_drag() -> void:
	if _drag == Drag.MARQUEE:
		_drag = Drag.NONE
		_overlay.queue_redraw()
		return
	if _drag != Drag.NONE and not _drag_ok:
		# It would cover another block or leave the grid: put everything back.
		for id: String in _drag_orig:
			GuiGrid.set_cells(_find(id), _drag_orig[id])
		_drag_changed = false
		_page_view.relayout()
		selection_changed.emit(selected_id)
	if _drag != Drag.NONE and _drag_changed:
		edited.emit()
	_drag = Drag.NONE
	_drag_ok = true
	_overlay.queue_redraw()


func _delete_selected() -> void:
	for id in selected_ids:
		var at := GuiPackage.locate(page(), id)
		if not at.is_empty():
			(at["list"] as Array).erase(at["widget"])
	select("")
	show_page(pkg, layout, page_index)
	edited.emit()


## --- drop from the palette -------------------------------------------------------

## The innermost panel or group under [param p], or "" for the page.
func _container_at(p: Vector2) -> String:
	var found := ""
	var list: Array = page()["widgets"]
	while true:
		var hit := _page_view.widget_at(p, list)
		if hit.is_empty() or not hit.has("children"):
			return found
		found = hit["id"]
		list = hit["children"]
	return found


## Where a new block of [param block] cells dropped at [param p] goes:
## centred on the drop point, or the nearest free cells. {} when there is no
## room.
func _drop_target(p: Vector2, block: Vector2i) -> Dictionary:
	var parent := _container_at(p)
	var box := _box(parent)
	var near := GuiGrid.cell_at(box, p - (Vector2(block - Vector2i.ONE) * GuiGrid.pitch(box)) / 2.0)
	var spot := GuiGrid.free_spot(box, _list(parent), block, near)
	if spot.x < 0:
		return {}
	return {"parent": parent, "cells": Rect2i(spot, block)}


## The palette item's size, or the type's default.
func _drop_size(data: Dictionary) -> Vector2i:
	if data.has("size"):
		return data["size"]
	var d := GuiWidgetTypes.defaults(data["type"])
	return Vector2i(d["cw"], d["ch"])


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if pkg.is_empty() or not (data is Dictionary and data.get("kind") == "new_widget"):
		return false
	_drop_ghost = _drop_target(_to_page(at), _drop_size(data))
	_overlay.queue_redraw()
	return not _drop_ghost.is_empty()


## A widget dropped onto a panel or group goes inside it.
func _drop_data(at: Vector2, data: Variant) -> void:
	var target := _drop_target(_to_page(at), _drop_size(data))
	_drop_ghost = {}
	if target.is_empty():
		return
	var parent: String = target["parent"]
	var w := GuiPackage.new_widget(pkg, data["type"], 0, 0)
	if not parent.is_empty():
		# ch1_encoder1 rather than encoder7, so a duplicate of ch1 renames it
		# to ch2_encoder1.
		w["id"] = GuiPackage.unique_id(pkg, "%s_%s" % [parent, data["type"]])
	GuiGrid.set_cells(w, target["cells"])
	_list(parent).append(w)
	show_page(pkg, layout, page_index)
	select(w["id"])
	edited.emit()
