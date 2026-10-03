class_name GuiPageView
extends Control
## One page of a package at its base resolution: the background plus one
## GuiWidgetView per widget, in drawing order.
##
## It is always laid out at the package's base size. The Builder scales it to
## fit the canvas; the Player lets Godot's stretch settings scale the window.

signal widget_event(widget_id: String, event: String, value: float)

var page: Dictionary
var _views := {}            ## widget id -> GuiWidgetView


func build(layout: Dictionary, page_data: Dictionary, interactive: bool) -> void:
	page = page_data
	for child in get_children():
		child.queue_free()
	_views.clear()
	size = Vector2(GuiPackage.screen_size(layout))
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS if interactive else Control.MOUSE_FILTER_IGNORE
	_add_views(self, page.get("widgets", []), interactive)
	queue_redraw()


## Group children become child Controls of the group's view, so their
## positions are relative to the group exactly as in the package.
func _add_views(parent: Control, widgets: Array, interactive: bool) -> void:
	for w: Dictionary in widgets:
		var view := GuiWidgetView.new()
		view.name = w.get("id", "widget")
		view.setup(w, interactive)
		view.widget_event.connect(widget_event.emit)
		parent.add_child(view)
		_views[w.get("id", "")] = view
		if w.has("children"):
			_add_views(view, w["children"], interactive)


func get_view(widget_id: String) -> GuiWidgetView:
	return _views.get(widget_id)


## The topmost widget under [param point] (page coordinates) in
## [param widgets] (the page's top level by default), or {}.
## [param origin] is the page position of that list's coordinates.
func widget_at(point: Vector2, widgets: Variant = null, origin := Vector2.ZERO) -> Dictionary:
	if widgets == null:
		widgets = page.get("widgets", [])
	for i in range(widgets.size() - 1, -1, -1):
		var w: Dictionary = widgets[i]
		if Rect2(origin + Vector2(w["x"], w["y"]), Vector2(w["w"], w["h"])).has_point(point):
			return w
	return {}


func _draw() -> void:
	var bg := Color.from_string(str(page.get("background", "#202020")), Color(0.125, 0.125, 0.125))
	draw_rect(Rect2(Vector2.ZERO, size), bg)
