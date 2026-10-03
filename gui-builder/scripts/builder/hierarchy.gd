extends Tree
## The page's widgets as a tree: groups open to show what they hold.
## Picking a row selects that widget on the canvas, at any depth.

signal picked(widget_id: String)

var _items := {}          ## widget id -> TreeItem
var _syncing := false     ## True while the selection is set from the canvas.


func _init() -> void:
	hide_root = true
	select_mode = Tree.SELECT_ROW
	item_selected.connect(func() -> void:
		if not _syncing:
			picked.emit(get_selected().get_metadata(0)))


func show_page(page: Dictionary) -> void:
	clear()
	_items.clear()
	var root := create_item()
	_add(root, page.get("widgets", []))


## Widgets drawn last are on top, so they are listed first, as in most
## design tools.
func _add(parent: TreeItem, widgets: Array) -> void:
	for i in range(widgets.size() - 1, -1, -1):
		var w: Dictionary = widgets[i]
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
