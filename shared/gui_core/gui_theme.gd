class_name GuiTheme
extends RefCounted
## The look shared by every widget of a package: colors, sizes, panel title
## bars. One package = one client's design, so changing the theme restyles the
## whole UI without touching a widget.
##
## Where a widget gets a style value, first match wins:
##   1. its own "style" (that one widget)
##   2. the named style in the package's "styles" that its "class" names
##   3. the theme
## See docs/Package-format.md 5.6.

const DEFAULT := {
	"background": "#1E1E1E",     ## Page background
	"surface": "#2E3036",        ## Button face when off, knob body, fader track
	"primary": "#3A7BD5",        ## Accent: button on, fader fill, knob arc
	"secondary": "#F5A623",      ## Second accent: a dual encoder's inner knob
	"text": "#FFFFFF",
	"textDim": "#A0A4AC",
	"border": "#4A4D55",
	"ok": "#4CD964",             ## LED colour
	"danger": "#E53935",         ## Record icon, warnings
	"fontSize": 18,
	"radius": 6,
	"gap": 8,                    ## Space between cells, unless a grid sets its own
	"padding": 16,               ## Space around the page grid
	"panel": {
		"background": "#1B2430",
		"border": "#3A7BD5",
		"borderWidth": 1,
		"radius": 4,
		"padding": 8,
		"titleHeight": 36,
		"titleBackground": "#1F5F8B",
		"titleColor": "#FFFFFF",
		"titleFontSize": 18,
	},
}


## The package's theme over the defaults, with its named styles under
## "styles".
static func of(pkg: Dictionary) -> Dictionary:
	var theme: Dictionary = DEFAULT.duplicate(true)
	_merge(theme, pkg.get("theme", {}))
	theme["styles"] = pkg.get("styles", {})
	return theme


static func _merge(into: Dictionary, over: Dictionary) -> void:
	for key: String in over:
		if into.get(key) is Dictionary and over[key] is Dictionary:
			_merge(into[key], over[key])
		else:
			into[key] = over[key]


## A theme value by dotted path, e.g. "panel.titleHeight".
static func value(theme: Dictionary, path: String) -> Variant:
	var at: Variant = theme
	for part in path.split("."):
		if not at is Dictionary or not at.has(part):
			return null
		at = at[part]
	return at


## Style [param key] for [param widget] (own style, then its class), or the
## theme value at [param theme_path] when neither sets it.
static func style(theme: Dictionary, widget: Dictionary, key: String, theme_path: String) -> Variant:
	var own: Dictionary = widget.get("style", {})
	if own.has(key):
		return own[key]
	var named: Dictionary = theme.get("styles", {}).get(widget.get("class", ""), {})
	if named.has(key):
		return named[key]
	return value(theme, theme_path)


static func to_color(v: Variant, fallback := Color.MAGENTA) -> Color:
	return Color.from_string(str(v), fallback)
