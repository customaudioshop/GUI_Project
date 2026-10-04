extends Tree
## The page's widgets as a tree: groups open to show what they hold.
## Picking a row selects that widget on the canvas, at any depth.
##
## Rows are in the package's order, so a new widget appears at the bottom.
## Rows can be dragged: between two rows to reorder, onto a panel or group to
## put the widget inside it.

signal picked(widget_id: String)
## A row was dropped: put [param widget_id] at [param index] in the list of
## [param parent_id] ("" is the page).
signal move_requested(widget_id: String, parent_id: String, index: int)

var _page: Dictionary

var _items := {}          ## widget id -> TreeItem
var _syncing := false     ## True while the selection is set from the canvas.


func _init() -> void:
	hide_root = true
	select_mode = Tree.SELECT_ROW
	item_selected.connect(func() -> void:
		if not _syncing:
			picked.emit(get_selected().get_metadata(0)))


func show_page(page: Dictionary) -> void:
	_page = page
	clear()
	_items.clear()
	var root := create_item()
	_add(root, page.get("widgets", []))


func _add(parent: TreeItem, widgets: Array) -> void:
	for w: Dictionary in widgets:
		var item := create_item(parent)
		item.set_text(0, "%s   (%s)" % [w["id"], w["type"]])
		item.set_metadata(0, w["id"])
		_items[w["id"]] = item
		if w.has("children"):
			_add(item, w["children"])


func show_selection(widget_id: String) -> void:
	_syncing = true
	deselect_all()
	var item: TreeItem = _items.get(widget_id)
	if item:
		item.select(0)
		scroll_to_item(item)
	_syncing = false


## --- drag to reorder --------------------------------------------------------------

func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var preview := Label.new()
	preview.text = item.get_text(0)
	set_drag_preview(preview)
	return {"kind": "hierarchy", "id": item.get_metadata(0)}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("kind") == "hierarchy"):
		return false
	drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	# Read where on the row it landed before drop mode is switched off.
	var section := get_drop_section_at_position(at)
	drop_mode_flags = Tree.DROP_MODE_DISABLED
	var item := get_item_at_position(at)
	if item == null:
		# Below the last row: the end of the page's list.
		move_requested.emit(data["id"], "", _page["widgets"].size())
		return
	var target_id: String = item.get_metadata(0)
	if target_id == data["id"]:
		return
	var at_target := GuiPackage.locate(_page, target_id)
	var target: Dictionary = at_target["widget"]
	var is_container := target.has("children")
	# Onto a container: inside it, at the end. Just below an open one (above
	# its first child): inside it, first.
	if is_container and section == 0:
		move_requested.emit(data["id"], target_id, target["children"].size())
		return
	if is_container and section == 1 and not item.collapsed:
		move_requested.emit(data["id"], target_id, 0)
		return
	var parent_id: String = at_target["parent"].get("id", "")
	var index: int = (at_target["list"] as Array).find(target)
	move_requested.emit(data["id"], parent_id, index if section <= 0 else index + 1)
