class_name GuiFonts
extends RefCounted
## The fonts the app draws with. Builder and Player ship one font, Noto Sans
## KR (SIL Open Font License, fonts/OFL.txt), so text looks the same and
## takes the same width on PC, Mac, iOS and Android whatever the device has
## installed.
##
## It is a variable font: one file holds every weight, and each weight below
## is a FontVariation of it. The file's own default is Thin (100), so it is
## never used directly.

const WEIGHTS: Array[String] = ["light", "normal", "bold"]

const _FONTS := {
	"light": preload("res://gui_core/fonts/noto_sans_kr_light.tres"),    # wght 300
	"normal": preload("res://gui_core/fonts/noto_sans_kr_normal.tres"),  # wght 400
	"bold": preload("res://gui_core/fonts/noto_sans_kr_bold.tres"),      # wght 700
}


## The font for [param weight] ("light", "normal" or "bold"); anything else
## gives normal.
static func of(weight: String) -> Font:
	return _FONTS.get(weight, _FONTS["normal"])
