class_name GuiPageView
extends Control
## One page of a package at its base resolution: the background plus one
## GuiWidgetView per widget, in drawing order.
##
## It is always laid out at the package's base size. The Builder scales it to
## fit the canvas; the Player lets Godot's stretch settings scale the window.
##
## Widget rectangles come from the grid (GuiGrid.layout_page). After changing
## cells, grids or the theme, call relayout().

signal widget_event(widget_id: String, event: String, value: float)

var page: Dictionary
var layout: Dictionary
var pkg_theme: Dictionary
var _views := {}            ## widget id -> GuiWidgetView
var _rects := {}            ## GuiGrid.layout_page result


func build(pkg: Dictionary, layout_data: Dictionary, page_data: Dictionary, interactive: bool) -> void:
	page = page_data
	layout = layout_data
	pkg_theme = GuiTheme.of(pkg)
	for child in get_children():
		child.queue_free()
	_views.clear()
	size = Vector2(GuiPackage.screen_size(layout))
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS if interactive else Control.MOUSE_FILTER_IGNORE
	_add_views(self, page.get("widgets", []), interactive)
	relayout()


## Container children become child Controls of the container's view, so they
## move with it. Backgrounds are added first so they are drawn behind their
## siblings wherever they are in the list.
func _add_views(parent: Control, widgets: Array, interactive: bool) -> void:
	var backs := widgets.filter(func(w: Dictionary) -> bool: return GuiWidgetTypes.is_back(w["type"]))
	var rest := widgets.filter(func(w: Dictionary) -> bool: return not GuiWidgetTypes.is_back(w["type"]))
	for w: Dictionary in backs + rest:
		var view := GuiWidgetView.new()
		view.name = w.get("id", "widget")
		view.setup(w, pkg_theme, interactive)
		view.widget_event.connect(widget_event.emit)
		parent.add_child(view)
		_views[w.get("id", "")] = view
		if w.has("children"):
			_add_views(view, w["children"], interactive)


## Works out every rectangle again from the cells and moves the views.
func relayout() -> void:
	_rects = GuiGrid.layout_page(pkg_theme, layout, page)
	for id: String in _views:
		var view: GuiWidgetView = _views[id]
		var entry: Dictionary = _rects.get(id, {})
		if entry.is_empty():
			continue
		view.position = entry["local"].position
		view.size = entry["local"].size
		view.queue_redraw()
	queue_redraw()


## Every rectangle and grid on the page; see GuiGrid.layout_page.
func rects() -> Dictionary:
	return _rects


func get_view(widget_id: String) -> GuiWidgetView:
	return _views.get(widget_id)


## The topmost widget under [param point] (page coordinates) in
## [param widgets] (the page's top level by default), or {}.
func widget_at(point: Vector2, widgets: Variant = null) -> Dictionary:
	if widgets == null:
		widgets = page.get("widgets", [])
	for i in range(widgets.size() - 1, -1, -1):
		var w: Dictionary = widgets[i]
		if GuiWidgetTypes.is_back(w["type"]):
			continue  # backgrounds are picked in the hierarchy, not by clicking
		if _rects.get(w["id"], {}).get("rect", Rect2()).has_point(point):
			return w
	return {}


func _draw() -> void:
	var bg: Variant = page.get("background", pkg_theme.get("background", "#202020"))
	draw_rect(Rect2(Vector2.ZERO, size), GuiTheme.to_color(bg, Color(0.125, 0.125, 0.125)))
