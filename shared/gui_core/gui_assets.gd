class_name GuiAssets
extends RefCounted
## Images a package refers to (style.image), loaded from files at run time.
##
## A path is relative to the package's folder ([member base_dir], set by the
## Builder and the Player when a package is opened or saved) or absolute.
##
## Rough frame: images stay next to the package. Putting them inside the
## .guipkg zip (assets/) comes with the zip format; the paths then become
## paths inside the zip and this class reads from there.

const IMAGE_FILTERS := "*.png, *.jpg, *.jpeg, *.webp, *.svg, *.bmp ; Images"

static var base_dir := ""
static var _cache := {}       ## resolved path -> Texture2D, or null when it failed


static func resolve(path: String) -> String:
	if path.is_empty() or path.is_absolute_path() or base_dir.is_empty():
		return path
	return base_dir.path_join(path)


## The image at [param path], or null when it is empty or cannot be read.
static func texture(path: String) -> Texture2D:
	var full := resolve(path)
	if full.is_empty():
		return null
	if not _cache.has(full):
		var img := Image.load_from_file(full)
		_cache[full] = ImageTexture.create_from_image(img) if img and not img.is_empty() else null
	return _cache[full]


## [param path] as the package should store it: relative to the package's
## folder when it is inside it, else absolute.
static func to_package_path(path: String) -> String:
	if not base_dir.is_empty() and path.begins_with(base_dir.path_join("")):
		return path.substr(base_dir.path_join("").length())
	return path


## Points every image in [param pkg] at the same files after the package
## moves to [param new_dir] (Save As into another folder): relative paths are
## worked out again from there, or made absolute when the file is outside it.
static func move_package(pkg: Dictionary, new_dir: String) -> void:
	var old_dir := base_dir
	for layout: Dictionary in pkg.get("layouts", []):
		for page: Dictionary in layout.get("pages", []):
			GuiPackage.walk(page.get("widgets", []), func(w: Dictionary) -> void:
				var style: Dictionary = w.get("style", {})
				var path := str(style.get("image", ""))
				if path.is_empty() or path.is_absolute_path() or old_dir.is_empty():
					return
				base_dir = new_dir
				style["image"] = to_package_path(old_dir.path_join(path))
				base_dir = old_dir)
	base_dir = new_dir


## Forget loaded images, e.g. after the files changed on disk.
static func clear() -> void:
	_cache.clear()
