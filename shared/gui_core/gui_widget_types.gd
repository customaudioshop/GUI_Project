class_name GuiWidgetTypes
extends RefCounted
## Every widget type the Builder offers and the Player draws, in one table.
##
## A type's entry says everything the rest of the app needs to know about it:
## where it sits in the palette, which block sizes it comes in, which events
## it fires, which properties the inspector shows and what a new one holds.
## Adding a widget type starts here; the palette and the inspector follow.
##
## Sizes are in grid cells (docs/Package-format.md 5.2). A type with "sizes"
## only comes in those sizes on a page or in a panel; inside a group (a
## component) every widget may take any size. A type without "sizes" may take
## any size anywhere.
##
## "presets" lists the sizes the palette offers ready-made, e.g. a 1x1 and a
## 2x1 button. Without it the palette offers the default "size".
##
## "parts" names the values of a widget that has more than one, e.g. a dual
## encoder's "outer" and "inner". Each part keeps its own "value", "motion",
## "on" and "receive" under its name; its events go out as "<id>.<part>".
##
## "container" marks types that hold other widgets in "children":
##   "strict"  children keep to their types' sizes (panel)
##   "free"    children take any size (group, i.e. a component's inside)

const CATEGORIES: Array = [
	["basic", "Basic"],
	["display", "Display"],
	["structure", "Structure"],
]

const _VALUE_01 := {"min": 0, "max": 1, "step": 0, "default": 0}

const TYPES := {
	"button": {
		"name": "Button", "category": "basic",
		"size": [2, 1], "sizes": [[1, 1], [2, 1], [3, 1], [1, 2], [2, 2]],
		"presets": [[1, 1], [2, 1]],
		"events": ["press", "release", "change"],
		"props": [
			{"key": "style.text", "label": "Text", "kind": "text"},
			{"key": "mode", "label": "Mode", "kind": "choice", "options": ["momentary", "toggle"]},
			{"key": "style.color", "label": "Color", "kind": "color", "theme": "primary"},
		],
		"defaults": {"mode": "momentary", "style": {"text": "Button"},
			"value": {"min": 0, "max": 1, "step": 1, "default": 0},
			"on": {}, "receive": []},
	},
	"fader": {
		"name": "Fader", "category": "basic",
		"size": [1, 3], "sizes": [[1, 2], [1, 3], [1, 4], [1, 5], [2, 1], [3, 1], [4, 1]],
		"events": ["change", "touch", "release"],
		"props": [
			{"key": "motion.touchMode", "label": "Touch mode", "kind": "choice", "options": ["relative", "jump"]},
			{"key": "style.color", "label": "Color", "kind": "color", "theme": "primary"},
		],
		"defaults": {"value": _VALUE_01,
			"motion": {"touchMode": "relative", "sensitivity": 1.0,
				"resetOnDoubleTap": true, "sendInterval": 20},
			"on": {}, "receive": []},
	},
	"encoder": {
		"name": "Encoder 1-layer", "category": "basic",
		"size": [1, 1], "sizes": [[1, 1], [2, 2], [3, 3]],
		"events": ["change", "touch", "release"],
		"props": [
			{"key": "motion.drag", "label": "Drag", "kind": "choice", "options": ["vertical", "horizontal", "circular"]},
			{"key": "motion.endless", "label": "Endless", "kind": "bool"},
			{"key": "style.color", "label": "Color", "kind": "color", "theme": "primary"},
		],
		"defaults": {"value": _VALUE_01,
			"motion": {"endless": false, "angleRange": 270, "drag": "vertical",
				"sensitivity": 1.0, "acceleration": true,
				"resetOnDoubleTap": true, "sendInterval": 20},
			"on": {}, "receive": []},
	},
	"dual_encoder": {
		"name": "Encoder 2-layer", "category": "basic",
		"size": [2, 2], "sizes": [[1, 1], [2, 2], [3, 3]],
		"parts": ["outer", "inner"],
		"events": ["change", "touch", "release"],
		"props": [
			{"key": "outer.label", "label": "Outer name", "kind": "text"},
			{"key": "inner.label", "label": "Inner name", "kind": "text"},
			{"key": "motion.drag", "label": "Drag", "kind": "choice", "options": ["vertical", "horizontal", "circular"]},
			{"key": "outer.motion.endless", "label": "Outer endless", "kind": "bool"},
			{"key": "inner.motion.endless", "label": "Inner endless", "kind": "bool"},
			{"key": "style.color", "label": "Outer color", "kind": "color", "theme": "primary"},
			{"key": "style.innerColor", "label": "Inner color", "kind": "color", "theme": "secondary"},
		],
		"defaults": {
			"motion": {"drag": "vertical", "sensitivity": 1.0, "acceleration": true,
				"resetOnDoubleTap": true, "sendInterval": 20},
			"outer": {"label": "Freq", "value": _VALUE_01,
				"motion": {"endless": false, "angleRange": 270}, "on": {}, "receive": []},
			"inner": {"label": "Gain", "value": _VALUE_01,
				"motion": {"endless": false, "angleRange": 270}, "on": {}, "receive": []},
		},
	},
	"label": {
		"name": "Label", "category": "display",
		"size": [2, 1],
		"events": [],
		"props": [
			{"key": "style.text", "label": "Text", "kind": "text"},
			{"key": "style.fontSize", "label": "Font size", "kind": "int", "theme": "fontSize"},
			{"key": "style.textColor", "label": "Text color", "kind": "color", "theme": "text"},
		],
		"defaults": {"style": {"text": "Label"}, "receive": []},
	},
	"led": {
		"name": "LED", "category": "display",
		"size": [1, 1],
		"events": [],
		"props": [
			{"key": "style.color", "label": "Color", "kind": "color", "theme": "ok"},
		],
		"defaults": {"value": _VALUE_01, "receive": []},
	},
	"image": {
		"name": "Image", "category": "display",
		"size": [2, 2],
		"events": ["press"],
		"props": [
			{"key": "style.image", "label": "Image", "kind": "text"},
		],
		"defaults": {"style": {"image": ""}, "on": {}},
	},
	"panel": {
		"name": "Panel", "category": "structure",
		"size": [4, 3], "container": "strict",
		"events": [],
		"props": [
			{"key": "title", "label": "Title", "kind": "text"},
			{"key": "style.background", "label": "Background", "kind": "color", "theme": "panel.background"},
		],
		"defaults": {"title": "Panel", "children": []},
	},
	"group": {
		"name": "Group", "category": "structure", "palette": false,
		"size": [2, 2], "container": "free",
		"events": [],
		"props": [],
		"defaults": {"params": {}, "children": []},
	},
}


static func has(type: String) -> bool:
	return TYPES.has(type)


static func info(type: String) -> Dictionary:
	return TYPES.get(type, {})


## Types shown in the palette under [param category], in table order.
static func in_category(category: String) -> Array[String]:
	var out: Array[String] = []
	for type: String in TYPES:
		var t: Dictionary = TYPES[type]
		if t["category"] == category and t.get("palette", true):
			out.append(type)
	return out


## The palette's ready-made sizes for [param type].
static func presets(type: String) -> Array:
	return info(type).get("presets", [info(type).get("size", [1, 1])])


## Value part names, or [] for a widget with one value.
static func parts(type: String) -> Array:
	return info(type).get("parts", [])


static func events(type: String) -> Array:
	return info(type).get("events", [])


## "strict", "free" or "" for widgets that hold nothing.
static func container(type: String) -> String:
	return info(type).get("container", "")


## A new widget's fields apart from id, type and position.
static func defaults(type: String) -> Dictionary:
	var size: Array = info(type).get("size", [1, 1])
	var d: Dictionary = info(type).get("defaults", {}).duplicate(true)
	d["cw"] = size[0]
	d["ch"] = size[1]
	return d


## The sizes [param type] may take in a strict container, or [] for any.
static func sizes(type: String) -> Array:
	return info(type).get("sizes", [])


## The allowed size closest to [param want] (in cells). With no size list,
## [param want] itself, at least 1x1.
static func nearest_size(type: String, want: Vector2i) -> Vector2i:
	want = want.max(Vector2i.ONE)
	var best := want
	var best_gap := 1 << 30
	for s: Array in sizes(type):
		var gap := absi(s[0] - want.x) + absi(s[1] - want.y)
		if gap < best_gap:
			best = Vector2i(s[0], s[1])
			best_gap = gap
	return best
