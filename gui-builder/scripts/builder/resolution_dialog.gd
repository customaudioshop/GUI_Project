extends ConfirmationDialog
## Asks for the base resolution: for a new package, or to change the current
## one (which rescales every widget).

## [param preset_name] is the preset's short name, or "WxH" for custom sizes.
signal chosen(width: int, height: int, orientation: String, preset_name: String)

## [label, short name, width, height]. Sizes are logical (dp / pt), so a
## widget is about the same physical size on every device. Each preset is in
## the device's natural orientation and sets the orientation when picked.
## Mac sizes are the default "looks like" resolutions in points; foldable
## sizes are approximate (Galaxy Z Fold / Flip class).
const PRESETS := [
	["Custom", "", 0, 0],
	["PC FHD (1920 x 1080)", "PC FHD", 1920, 1080],
	["PC QHD (2560 x 1440)", "PC QHD", 2560, 1440],
	["PC 4K UHD (3840 x 2160)", "PC 4K", 3840, 2160],
	["PC WUXGA 16:10 (1920 x 1200)", "PC WUXGA", 1920, 1200],
	["MacBook Air 13 (1470 x 956)", "MacBook Air 13", 1470, 956],
	["MacBook Air 15 (1710 x 1112)", "MacBook Air 15", 1710, 1112],
	["MacBook Pro 14 (1512 x 982)", "MacBook Pro 14", 1512, 982],
	["MacBook Pro 16 (1728 x 1117)", "MacBook Pro 16", 1728, 1117],
	["iMac 24 (2240 x 1260)", "iMac 24", 2240, 1260],
	["Tablet 16:10 (1280 x 800)", "Tablet", 1280, 800],
	["Tablet 16:10 (1920 x 1200)", "Tablet", 1920, 1200],
	["iPad 4:3 (1024 x 768)", "iPad", 1024, 768],
	["iPad 4:3 (2048 x 1536)", "iPad", 2048, 1536],
	["Phone (360 x 800)", "Phone", 360, 800],
	["Phone large (412 x 915)", "Phone", 412, 915],
	["iPhone (393 x 852)", "iPhone", 393, 852],
	["iPhone Max (430 x 932)", "iPhone Max", 430, 932],
	["Foldable folded / cover (344 x 882)", "Fold folded", 344, 882],
	["Foldable unfolded / inner (690 x 829)", "Fold unfolded", 690, 829],
	["Flip unfolded (411 x 1006)", "Flip", 411, 1006],
]

var _preset := OptionButton.new()
var _width := SpinBox.new()
var _height := SpinBox.new()
var _orientation := OptionButton.new()


func _init() -> void:
	min_size = Vector2i(560, 0)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	for p: Array in PRESETS:
		_preset.add_item(p[0])
	_preset.set_item_disabled(0, true)  # chosen automatically when typing a size
	_preset.item_selected.connect(_on_preset)
	for s in [_width, _height]:
		s.min_value = GuiPackage.MIN_SCREEN
		s.max_value = GuiPackage.MAX_SCREEN
		s.value_changed.connect(func(_v: float) -> void: _preset.selected = 0)
	_orientation.add_item("landscape")
	_orientation.add_item("portrait")
	_orientation.item_selected.connect(func(_i: int) -> void: _swap_if_needed())

	for pair in [["Preset", _preset], ["Width", _width], ["Height", _height],
			["Orientation", _orientation]]:
		var l := Label.new()
		l.text = pair[0]
		grid.add_child(l)
		pair[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(pair[1])

	confirmed.connect(func() -> void:
		var w := int(_width.value)
		var h := int(_height.value)
		var preset: String = PRESETS[_preset.selected][1]
		chosen.emit(w, h, _orientation.get_item_text(_orientation.selected),
				preset if not preset.is_empty() else "%dx%d" % [w, h]))


func ask(dialog_title: String, width: int, height: int, orientation: String) -> void:
	title = dialog_title
	_width.set_value_no_signal(width)
	_height.set_value_no_signal(height)
	_orientation.selected = 1 if orientation == "portrait" else 0
	_preset.selected = 0
	for i in PRESETS.size():
		var p: Array = PRESETS[i]
		if (p[2] == width and p[3] == height) or (p[2] == height and p[3] == width):
			_preset.selected = i
			break
	popup_centered()


func _on_preset(i: int) -> void:
	if i == 0:
		return
	_width.set_value_no_signal(PRESETS[i][2])
	_height.set_value_no_signal(PRESETS[i][3])
	_orientation.selected = 1 if PRESETS[i][3] > PRESETS[i][2] else 0


## Keeps width and height matching the chosen orientation.
func _swap_if_needed() -> void:
	var portrait := _orientation.selected == 1
	if portrait != (_height.value > _width.value):
		var w := _width.value
		_width.set_value_no_signal(_height.value)
		_height.set_value_no_signal(w)
