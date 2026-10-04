class_name GuiPackage
extends RefCounted
## The package model shared by the Builder and the Player.
##
## A package is kept as plain Dictionaries and Arrays, shaped exactly like
## package.json (docs/Package-format.md), so saving and loading are just
## JSON.stringify and JSON.parse with nothing to map in between.
##
## A package holds one or more layouts (tablet, phone, foldable folded and
## unfolded …). Each layout has its own screen size and pages; devices are
## shared. A widget id names the same control in every layout, so the Player
## can switch layouts (a foldable opening, a phone turning) and keep values.
##
## Functions that take a "layout" also accept anything with "screen" and
## "pages" keys.
##
## Widgets are blocks on a grid: "col", "row" for the top-left cell and
## "cw", "ch" for the size in cells. Pixels are worked out by GuiGrid.
##
## Rough frame: packages are saved as a single .json file for now. The zip
## container (.guipkg with assets/) comes with image and font support.

const FORMAT := "guipkg"
## 2: widgets placed in grid cells. 1 (pixels) is converted on load.
const FORMAT_VERSION := 2

const MIN_SCREEN := 320
const MAX_SCREEN := 7680


static func create(width: int, height: int, orientation := "landscape",
		layout_name := "Layout") -> Dictionary:
	return {
		"format": FORMAT,
		"formatVersion": FORMAT_VERSION,
		"meta": {
			"name": "Untitled",
			"author": "",
			"created": Time.get_datetime_string_from_system(true) + "Z",
		},
		"theme": {},
		"styles": {},
		"devices": {},
		"layouts": [new_layout("layout1", layout_name, width, height, orientation)],
	}


static func new_layout(id: String, layout_name: String, width: int, height: int,
		orientation: String) -> Dictionary:
	return {
		"id": id,
		"name": layout_name,
		"screen": {
			"width": clampi(width, MIN_SCREEN, MAX_SCREEN),
			"height": clampi(height, MIN_SCREEN, MAX_SCREEN),
			"orientation": orientation,
			"fit": "keep",
			"background": "#1E1E1E",
		},
		"grid": GuiGrid.default_grid(width, height),
		"pages": [new_page("main", "Main")],
	}


## A new layout made from [param source], rescaled to the new screen, with the
## same widget ids so it controls the same things. Appended to [param pkg].
static func copy_layout(pkg: Dictionary, source: Dictionary, layout_name: String,
		width: int, height: int, orientation: String) -> Dictionary:
	var layout: Dictionary = source.duplicate(true)
	var used := {}
	for l: Dictionary in pkg["layouts"]:
		used[l["id"]] = true
	layout["id"] = _next_free(used, "layout")
	layout["name"] = layout_name
	rescale(layout, width, height)
	layout["screen"]["orientation"] = orientation
	pkg["layouts"].append(layout)
	return layout


## The layout whose shape is closest to a screen of [param screen] pixels.
## Shapes are compared as ratios, so 2:1 is as far from 1:1 as 1:1 is from 1:2.
static func pick_layout(pkg: Dictionary, screen: Vector2) -> Dictionary:
	var want := log(screen.x / maxf(1.0, screen.y))
	var best: Dictionary = pkg["layouts"][0]
	var best_gap := INF
	for layout: Dictionary in pkg["layouts"]:
		var s := screen_size(layout)
		var gap := absf(log(float(s.x) / s.y) - want)
		if gap < best_gap - 0.001:
			best = layout
			best_gap = gap
	return best


## Adds an empty page to every layout, so `page "<id>"` works whichever
## layout is showing.
static func add_page(pkg: Dictionary) -> String:
	var id := unique_id(pkg, "page")
	for layout: Dictionary in pkg["layouts"]:
		layout["pages"].append(new_page(id, id.capitalize()))
	return id


static func new_page(id: String, page_name: String) -> Dictionary:
	return {"id": id, "name": page_name, "widgets": []}


## A new widget of [param type] with its top-left cell at ([param col],
## [param row]), its default size and an id that is unique in [param pkg].
## It is not added to any page.
static func new_widget(pkg: Dictionary, type: String, col: int, row: int) -> Dictionary:
	var w := {"id": unique_id(pkg, type), "type": type, "col": col, "row": row}
	w.merge(GuiWidgetTypes.defaults(type))
	return w


## [param base] followed by the first number that makes it unused, e.g. fader1.
static func unique_id(pkg: Dictionary, base: String) -> String:
	return _next_free(_used_ids(pkg), base)


## Widget, page and device names share one namespace, so a script or a
## receive rule can never be ambiguous about what a name means.
static func id_in_use(pkg: Dictionary, id: String) -> bool:
	return _used_ids(pkg).has(id)


static func _used_ids(pkg: Dictionary) -> Dictionary:
	var used := {}
	for layout: Dictionary in pkg.get("layouts", []):
		for page: Dictionary in layout.get("pages", []):
			used[page.get("id", "")] = true
			walk(page.get("widgets", []), func(w: Dictionary) -> void: used[w.get("id", "")] = true)
	for device_name: String in pkg.get("devices", {}):
		used[device_name] = true
	return used


static func is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 32:
		return false
	var re := RegEx.create_from_string("^[A-Za-z][A-Za-z0-9_]*$")
	return re.search(id) != null


static func screen_size(layout: Dictionary) -> Vector2i:
	var s: Dictionary = layout.get("screen", {})
	return Vector2i(int(s.get("width", 1280)), int(s.get("height", 800)))


## Gives the layout a new base resolution. Blocks keep their cells, so the
## layout keeps its arrangement and the cells grow or shrink with the screen.
## Font sizes follow the smaller of the two ratios.
static func rescale(layout: Dictionary, width: int, height: int) -> void:
	var old := screen_size(layout)
	var sf := minf(float(width) / old.x, float(height) / old.y)
	for page: Dictionary in layout.get("pages", []):
		walk(page.get("widgets", []), func(w: Dictionary) -> void:
			var style: Dictionary = w.get("style", {})
			if style.has("fontSize"):
				style["fontSize"] = maxi(6, roundi(style["fontSize"] * sf)))
	layout["screen"]["width"] = width
	layout["screen"]["height"] = height


## --- hierarchy -----------------------------------------------------------------
##
## A container widget (panel, group) holds other widgets in "children",
## placed on its own inner grid. A group's "params" (e.g. {"ch": 1}) are readable as $ch in the scripts
## of everything inside it, so every copy of a channel strip can share the same
## scripts. See docs/Package-format.md 5.7.

## Calls [param fn] with every widget in [param widgets], groups before their
## children.
static func walk(widgets: Array, fn: Callable) -> void:
	for w: Dictionary in widgets:
		fn.call(w)
		if w.has("children"):
			walk(w["children"], fn)


## Where widget [param id] is on [param page]: {"widget", "list" (the Array
## holding it), "parent" (its container or {})}. Empty when not found.
static func locate(page: Dictionary, id: String) -> Dictionary:
	return _locate_in(page.get("widgets", []), id, {})


static func _locate_in(list: Array, id: String, parent: Dictionary) -> Dictionary:
	for w: Dictionary in list:
		if w.get("id") == id:
			return {"widget": w, "list": list, "parent": parent}
		if w.has("children"):
			var found := _locate_in(w["children"], id, w)
			if not found.is_empty():
				return found
	return {}


## Wraps sibling widgets [param ids] in a new group covering their cells.
## Returns the group, or {} when they are not all in the same list.
##
## Everything inside gets the group's name in front of its id (button1 ->
## group1_button1), so duplicating the group renumbers the whole set
## (group2, group2_button1) instead of scattering new numbers.
static func group_widgets(pkg: Dictionary, page: Dictionary, ids: Array) -> Dictionary:
	if ids.is_empty():
		return {}
	var first := locate(page, ids[0])
	if first.is_empty():
		return {}
	var list: Array = first["list"]
	var members: Array[Dictionary] = []
	for w: Dictionary in list:
		if w["id"] in ids:
			members.append(w)
	if members.size() != ids.size():
		return {}
	var box := GuiGrid.cells_of(members[0])
	for w in members:
		box = box.merge(GuiGrid.cells_of(w))
	# The group spans exactly its members' cells and has no grid of its own,
	# so its inner cells line up with the outer ones and nothing moves.
	var group := new_widget(pkg, "group", box.position.x, box.position.y)
	group["cw"] = box.size.x
	group["ch"] = box.size.y
	var at := list.find(members[0])
	for w in members:
		list.erase(w)
		w["col"] -= box.position.x
		w["row"] -= box.position.y
		group["children"].append(w)
	list.insert(mini(at, list.size()), group)
	_prefix_ids(pkg, group["id"], group["children"])
	return group


## Puts [param prefix] and "_" in front of every id in [param widgets] (and
## inside them) that lacks it.
static func _prefix_ids(pkg: Dictionary, prefix: String, widgets: Array) -> void:
	var used := _used_ids(pkg)
	walk(widgets, func(w: Dictionary) -> void:
		var id: String = w["id"]
		if id.begins_with(prefix + "_"):
			return
		var new_id: String = prefix + "_" + id
		if used.has(new_id) or new_id.length() > 32:
			new_id = _next_free(used, prefix + "_" + w["type"])
		used[new_id] = true
		w["id"] = new_id)


## Moves widget [param id] to position [param index] of container
## [param parent_id]'s list ("" is the page). Returns the widget's id
## afterwards, or "" with [param error] filled in when it cannot go there.
##
## Within the same list only the order changes. Into another container the
## block keeps its cells when they are free there, otherwise it takes the
## nearest free cells (sized to the container's rules); moving into a panel
## or group puts the container's name in front of its id, as a drop does.
static func move_widget(pkg: Dictionary, layout: Dictionary, page: Dictionary, id: String,
		parent_id: String, index: int, error: Array[String] = []) -> String:
	var at := locate(page, id)
	if at.is_empty():
		error.append("'%s' is not on this page." % id)
		return ""
	var w: Dictionary = at["widget"]
	var inside := {}
	walk([w], func(x: Dictionary) -> void: inside[x["id"]] = true)
	if inside.has(parent_id):
		error.append("A widget cannot go inside itself.")
		return ""
	var target: Array = page["widgets"]
	if not parent_id.is_empty():
		var parent: Dictionary = locate(page, parent_id).get("widget", {})
		if not parent.has("children"):
			error.append("'%s' cannot hold other widgets." % parent_id)
			return ""
		target = parent["children"]
	var source: Array = at["list"]

	if is_same(source, target):
		var from := source.find(w)
		source.remove_at(from)
		if from < index:
			index -= 1
		source.insert(clampi(index, 0, source.size()), w)
		return id

	var box: Dictionary = GuiGrid.layout_page(GuiTheme.of(pkg), layout, page)[parent_id]
	var cells := GuiGrid.cells_of(w)
	if box["strict"]:
		cells.size = GuiWidgetTypes.nearest_size(w["type"], cells.size)
	if not GuiGrid.fits(box, target, cells):
		var spot := GuiGrid.free_spot(box, target, cells.size, cells.position)
		if spot.x < 0:
			error.append("There is no room for a %dx%d block in '%s'." % [cells.size.x, cells.size.y,
					parent_id if not parent_id.is_empty() else page.get("name", "the page")])
			return ""
		cells.position = spot
	source.erase(w)
	GuiGrid.set_cells(w, cells)
	target.insert(clampi(index, 0, target.size()), w)
	if not parent_id.is_empty():
		_prefix_ids(pkg, parent_id, [w])
	return w["id"]


## Replaces container [param id] by its children, keeping them where they
## are. When the container has a grid of its own, cells are scaled to the
## outer grid, so blocks may land a little off and are shown as conflicts.
static func ungroup(page: Dictionary, id: String) -> Array:
	var at := locate(page, id)
	if at.is_empty() or not at["widget"].has("children"):
		return []
	var group: Dictionary = at["widget"]
	var list: Array = at["list"]
	var index := list.find(group)
	list.remove_at(index)
	var g: Dictionary = group.get("grid", {})
	var scale := Vector2(float(group["cw"]) / int(g.get("cols", group["cw"])),
			float(group["ch"]) / int(g.get("rows", group["ch"])))
	var children: Array = group["children"]
	for i in children.size():
		var w: Dictionary = children[i]
		var c := GuiGrid.cells_of(w)
		var pos := (Vector2(c.position) * scale).floor()
		var end := (Vector2(c.end) * scale).ceil()
		GuiGrid.set_cells(w, Rect2i(Vector2i(pos) + Vector2i(group["col"], group["row"]),
				Vector2i(end - pos).max(Vector2i.ONE)))
		list.insert(index + i, w)
	return children.map(func(w: Dictionary) -> String: return w["id"])


## Copies widget [param id] (with everything inside it) into the free spot
## nearest the original's right-hand side, in [param layout].
##
## Ids are renumbered from the original's trailing number: ch1 with ch1_fader
## and ch1_mute becomes ch2 with ch2_fader and ch2_mute. Every number in
## "params" goes up by the same amount, so a strip whose scripts use $ch talks
## to the next channel without any script being touched.
static func duplicate_widget(pkg: Dictionary, layout: Dictionary, page: Dictionary,
		id: String) -> Dictionary:
	var at := locate(page, id)
	if at.is_empty():
		return {}
	var original: Dictionary = at["widget"]
	var copy: Dictionary = original.duplicate(true)
	var used := _used_ids(pkg)

	var m := RegEx.create_from_string("^(.*?)(\\d+)$").search(id)
	var stem := m.get_string(1) if m else id
	var old_n := int(m.get_string(2)) if m else 0
	var new_n := old_n + 1
	while used.has(stem + str(new_n)):
		new_n += 1
	var step := new_n - old_n

	var old_tag := stem + str(old_n) if m else id
	var new_tag := stem + str(new_n)
	walk([copy], func(w: Dictionary) -> void:
		var new_id := (w["id"] as String).replace(old_tag, new_tag)
		if new_id == w["id"] or used.has(new_id):
			new_id = _next_free(used, w["type"])
		used[new_id] = true
		w["id"] = new_id)
	var params: Dictionary = copy.get("params", {})
	for key: String in params:
		if params[key] is float or params[key] is int:
			params[key] += step

	var list: Array = at["list"]
	var box: Dictionary = GuiGrid.layout_page(GuiTheme.of(pkg), layout, page)[
			at["parent"].get("id", "")]
	var c := GuiGrid.cells_of(original)
	var spot := GuiGrid.free_spot(box, list, c.size, c.position + Vector2i(c.size.x, 0))
	# No room: put it to the right anyway; the Builder shows the conflict.
	copy["col"] = spot.x if spot.x >= 0 else c.end.x
	copy["row"] = spot.y if spot.x >= 0 else c.position.y
	list.insert(list.find(original) + 1, copy)
	return copy


static func _next_free(used: Dictionary, base: String) -> String:
	var n := 1
	while used.has(base + str(n)):
		n += 1
	return base + str(n)


## Merged params of every group around widget [param id], inner groups
## winning. These become read-only script variables for that widget.
static func params_for(page: Dictionary, id: String) -> Dictionary:
	var chain: Array[Dictionary] = []
	var current := id
	while true:
		var at := locate(page, current)
		if at.is_empty() or at["parent"].is_empty():
			break
		chain.push_front(at["parent"])
		current = at["parent"]["id"]
	var params := {}
	for g in chain:
		params.merge(g.get("params", {}), true)
	return params


## --- files -------------------------------------------------------------------

## The package in [param path], or an empty Dictionary with [param error]
## filled in when it cannot be used.
static func load_file(path: String, error: Array[String] = []) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		error.append("Cannot read %s" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or data.get("format") != FORMAT:
		error.append("%s is not a GUI package" % path.get_file())
		return {}
	if int(data.get("formatVersion", 0)) > FORMAT_VERSION:
		error.append("%s was made by a newer GUI Builder. Please update." % path.get_file())
		return {}
	if int(data.get("formatVersion", 0)) < 2:
		_from_pixels(data)
	normalize(data)
	return data


static func save_file(pkg: Dictionary, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(_whole_numbers(pkg), "  ", false))
	return OK


## JSON hands numbers back as floats; write 5000 rather than 5000.0.
static func _whole_numbers(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	if v is Dictionary:
		var out := {}
		for key: Variant in v:
			out[key] = _whole_numbers(v[key])
		return out
	if v is Array:
		return v.map(_whole_numbers)
	return v


## JSON numbers come back as floats; cells and grids are integers.
static func normalize(pkg: Dictionary) -> void:
	_lift_single_screen(pkg)
	for layout: Dictionary in pkg.get("layouts", []):
		var s: Dictionary = layout.get("screen", {})
		for key in ["width", "height"]:
			s[key] = int(s.get(key, 0))
		if not layout.has("grid"):
			layout["grid"] = GuiGrid.default_grid(s["width"], s["height"])
		_ints(layout["grid"])
		for page: Dictionary in layout.get("pages", []):
			walk(page.get("widgets", []), func(w: Dictionary) -> void:
				GuiGrid.set_cells(w, GuiGrid.cells_of(w))
				if w.has("grid"):
					_ints(w["grid"]))
	for key in ["theme", "styles"]:
		if not pkg.get(key) is Dictionary:
			pkg[key] = {}


## Early drafts had one screen and its pages at the top level.
static func _lift_single_screen(pkg: Dictionary) -> void:
	if not pkg.has("layouts") and pkg.has("pages"):
		pkg["layouts"] = [{"id": "layout1", "name": "Layout",
			"screen": pkg["screen"], "pages": pkg["pages"]}]
		pkg.erase("screen")
		pkg.erase("pages")


static func _ints(d: Dictionary) -> void:
	for key: String in d:
		if d[key] is float:
			d[key] = int(d[key])


## Format 1 placed widgets in pixels. Each layout gets a grid whose cells are
## about TARGET_PITCH wide with no gap or padding, and every widget takes the
## cells nearest its old rectangle. Overlaps that rounding creates are left
## for the Builder to show.
static func _from_pixels(pkg: Dictionary) -> void:
	_lift_single_screen(pkg)
	for layout: Dictionary in pkg.get("layouts", []):
		var s := screen_size(layout)
		var grid := GuiGrid.default_grid(s.x, s.y)
		grid["gap"] = 0
		grid["padding"] = 0
		layout["grid"] = grid
		var cell := Vector2(float(s.x) / grid["cols"], float(s.y) / grid["rows"])
		for page: Dictionary in layout.get("pages", []):
			walk(page.get("widgets", []), func(w: Dictionary) -> void:
				if w.has("col") or not w.has("x"):
					return
				var pos := (Vector2(float(w["x"]), float(w["y"])) / cell).round()
				var size := (Vector2(float(w["w"]), float(w["h"])) / cell).round().max(Vector2.ONE)
				GuiGrid.set_cells(w, Rect2i(Vector2i(pos), Vector2i(size)))
				for key in ["x", "y", "w", "h", "orientation"]:
					w.erase(key))
	pkg.erase("editor")
	pkg["formatVersion"] = FORMAT_VERSION


static func deep_copy(pkg: Dictionary) -> Dictionary:
	return pkg.duplicate(true)
