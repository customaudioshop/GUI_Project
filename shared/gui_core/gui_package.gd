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
## Rough frame: packages are saved as a single .json file for now. The zip
## container (.guipkg with assets/) comes with image and font support.

const FORMAT := "guipkg"
const FORMAT_VERSION := 1

const WIDGET_TYPES: Array[String] = [
	"button", "fader", "encoder", "label", "led", "image", "panel", "group",
]

const MIN_WIDGET_SIZE := 16
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
		"devices": {},
		"layouts": [new_layout("layout1", layout_name, width, height, orientation)],
		"editor": {"grid": 10, "snap": true},
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
	return {"id": id, "name": page_name, "background": "#202020", "widgets": []}


## A new widget of [param type] at ([param x], [param y]) with an id that is
## unique in [param pkg]. It is not added to any page.
static func new_widget(pkg: Dictionary, type: String, x: int, y: int) -> Dictionary:
	var w := {"id": unique_id(pkg, type), "type": type, "x": x, "y": y}
	w.merge(_defaults(type))
	return w


static func _defaults(type: String) -> Dictionary:
	match type:
		"button":
			return {"w": 120, "h": 60, "mode": "momentary",
				"style": {"text": "Button", "color": "#3A7BD5"},
				"value": {"min": 0, "max": 1, "step": 1, "default": 0},
				"on": {}, "receive": []}
		"fader":
			return {"w": 60, "h": 300, "orientation": "vertical",
				"style": {"color": "#3A7BD5"},
				"value": {"min": 0, "max": 1, "step": 0, "default": 0},
				"motion": {"touchMode": "relative", "sensitivity": 1.0,
					"resetOnDoubleTap": true, "sendInterval": 20},
				"on": {}, "receive": []}
		"encoder":
			return {"w": 120, "h": 120,
				"style": {"color": "#3A7BD5"},
				"value": {"min": 0, "max": 1, "step": 0, "default": 0},
				"motion": {"endless": false, "angleRange": 270, "drag": "vertical",
					"sensitivity": 1.0, "acceleration": true,
					"resetOnDoubleTap": true, "sendInterval": 20},
				"on": {}, "receive": []}
		"label":
			return {"w": 160, "h": 40, "style": {"text": "Label", "fontSize": 20},
				"receive": []}
		"led":
			return {"w": 40, "h": 40, "style": {"color": "#4CD964"},
				"value": {"min": 0, "max": 1, "step": 0, "default": 0},
				"receive": []}
		"image":
			return {"w": 160, "h": 120, "style": {"image": ""}, "on": {}}
		"panel":
			return {"w": 300, "h": 200, "style": {"background": "#2B2B2B"}}
		"group":
			return {"w": 100, "h": 100, "params": {}, "children": []}
	return {"w": 100, "h": 100}


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


## Moves every widget so the layout keeps its proportions in a new base
## resolution. Font sizes follow the smaller of the two ratios.
static func rescale(layout: Dictionary, width: int, height: int) -> void:
	var old := screen_size(layout)
	var sx := float(width) / old.x
	var sy := float(height) / old.y
	var sf := minf(sx, sy)
	# Group children are relative to their group, so the same ratios apply.
	for page: Dictionary in layout.get("pages", []):
		walk(page.get("widgets", []), func(w: Dictionary) -> void:
			w["x"] = roundi(w["x"] * sx)
			w["y"] = roundi(w["y"] * sy)
			w["w"] = maxi(MIN_WIDGET_SIZE, roundi(w["w"] * sx))
			w["h"] = maxi(MIN_WIDGET_SIZE, roundi(w["h"] * sy))
			var style: Dictionary = w.get("style", {})
			if style.has("fontSize"):
				style["fontSize"] = maxi(6, roundi(style["fontSize"] * sf)))
	layout["screen"]["width"] = width
	layout["screen"]["height"] = height


## --- hierarchy -----------------------------------------------------------------
##
## A "group" widget holds other widgets in "children", positioned relative to
## the group. Its "params" (e.g. {"ch": 1}) are readable as $ch in the scripts
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
## holding it), "parent" (its group or {}), "origin" (page position of the
## list's coordinate origin)}. Empty when not found.
static func locate(page: Dictionary, id: String) -> Dictionary:
	return _locate_in(page.get("widgets", []), id, {}, Vector2.ZERO)


static func _locate_in(list: Array, id: String, parent: Dictionary, origin: Vector2) -> Dictionary:
	for w: Dictionary in list:
		if w.get("id") == id:
			return {"widget": w, "list": list, "parent": parent, "origin": origin}
		if w.has("children"):
			var found := _locate_in(w["children"], id, w, origin + Vector2(w["x"], w["y"]))
			if not found.is_empty():
				return found
	return {}


## The widget's rectangle in page coordinates.
static func page_rect(page: Dictionary, id: String) -> Rect2:
	var at := locate(page, id)
	if at.is_empty():
		return Rect2()
	var w: Dictionary = at["widget"]
	return Rect2(at["origin"] + Vector2(w["x"], w["y"]), Vector2(w["w"], w["h"]))


## Wraps sibling widgets [param ids] in a new group sized to fit them.
## Returns the group, or {} when they are not all in the same list.
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
	var box := Rect2(members[0]["x"], members[0]["y"], members[0]["w"], members[0]["h"])
	for w in members:
		box = box.merge(Rect2(w["x"], w["y"], w["w"], w["h"]))
	var group := new_widget(pkg, "group", int(box.position.x), int(box.position.y))
	group["w"] = int(box.size.x)
	group["h"] = int(box.size.y)
	var at := list.find(members[0])
	for w in members:
		list.erase(w)
		w["x"] -= group["x"]
		w["y"] -= group["y"]
		group["children"].append(w)
	list.insert(mini(at, list.size()), group)
	return group


## Replaces group [param id] by its children, keeping them where they are.
static func ungroup(page: Dictionary, id: String) -> Array:
	var at := locate(page, id)
	if at.is_empty() or not at["widget"].has("children"):
		return []
	var group: Dictionary = at["widget"]
	var list: Array = at["list"]
	var index := list.find(group)
	list.remove_at(index)
	var children: Array = group["children"]
	for i in children.size():
		var w: Dictionary = children[i]
		w["x"] += group["x"]
		w["y"] += group["y"]
		list.insert(index + i, w)
	return children.map(func(w: Dictionary) -> String: return w["id"])


## Copies widget [param id] (with everything inside it) next to the original.
##
## Ids are renumbered from the original's trailing number: ch1 with ch1_fader
## and ch1_mute becomes ch2 with ch2_fader and ch2_mute. Every number in
## "params" goes up by the same amount, so a strip whose scripts use $ch talks
## to the next channel without any script being touched.
static func duplicate_widget(pkg: Dictionary, page: Dictionary, id: String) -> Dictionary:
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

	copy["x"] = original["x"] + original["w"]
	var list: Array = at["list"]
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
	normalize(data)
	return data


static func save_file(pkg: Dictionary, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(pkg, "  ", false))
	return OK


## JSON numbers come back as floats; geometry is integer pixels.
static func normalize(pkg: Dictionary) -> void:
	# Early drafts had one screen and its pages at the top level.
	if not pkg.has("layouts") and pkg.has("pages"):
		pkg["layouts"] = [{"id": "layout1", "name": "Layout",
			"screen": pkg["screen"], "pages": pkg["pages"]}]
		pkg.erase("screen")
		pkg.erase("pages")
	for layout: Dictionary in pkg.get("layouts", []):
		var s: Dictionary = layout.get("screen", {})
		for key in ["width", "height"]:
			s[key] = int(s.get(key, 0))
		for page: Dictionary in layout.get("pages", []):
			walk(page.get("widgets", []), func(w: Dictionary) -> void:
				for key in ["x", "y", "w", "h"]:
					w[key] = int(w.get(key, 0)))


static func deep_copy(pkg: Dictionary) -> Dictionary:
	return pkg.duplicate(true)
