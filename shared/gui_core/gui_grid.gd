class_name GuiGrid
extends RefCounted
## Where everything on a page goes, in pixels, worked out from grid cells.
##
## Widgets are blocks placed on a grid (col, row) and sized in cells (cw, ch),
## like LEGO bricks. The page has the layout's grid; a panel or a group has
## its own grid inside, so blocks nest. Pixel rectangles are never stored:
## they follow from the screen size, the grids and the theme, so changing the
## base resolution or the gap re-flows everything consistently.
## See docs/Package-format.md 5.2.
##
## A "box" below is a grid that holds blocks: the page itself or a container
## widget. It is a Dictionary with
##   "content"  Rect2 in page coordinates that the cells fill
##   "cols", "rows", "gap"
##   "strict"   true when blocks keep to their types' sizes

## Target cell pitch for a new layout's grid, in logical pixels: about a
## finger-and-a-half, so a 1x1 button is comfortable to press.
const TARGET_PITCH := 120.0
const MIN_COLS := 4
const MIN_ROWS := 4


static func default_grid(width: int, height: int) -> Dictionary:
	return {
		"cols": maxi(MIN_COLS, roundi(width / TARGET_PITCH)),
		"rows": maxi(MIN_ROWS, roundi(height / TARGET_PITCH)),
	}


## Every rectangle on [param page]:
##   "" -> the page's box
##   widget id -> {"rect": Rect2 in page coordinates, "local": Rect2 relative
##     to the parent's rect, "parent": parent id ("" for the page)}, plus the
##     box fields when the widget is a container.
static func layout_page(theme: Dictionary, layout: Dictionary, page: Dictionary) -> Dictionary:
	var screen := Vector2(GuiPackage.screen_size(layout))
	var g: Dictionary = layout.get("grid", {})
	var pad := float(g.get("padding", theme["padding"]))
	var page_box := {
		"rect": Rect2(Vector2.ZERO, screen),
		"content": Rect2(Vector2(pad, pad), (screen - Vector2(pad, pad) * 2.0).max(Vector2.ONE)),
		"cols": maxi(1, int(g.get("cols", MIN_COLS))),
		"rows": maxi(1, int(g.get("rows", MIN_ROWS))),
		"gap": float(g.get("gap", theme["gap"])),
		"strict": true,
		"parent": "",
	}
	var out := {"": page_box}
	_place(theme, page.get("widgets", []), page_box, "", out)
	return out


static func _place(theme: Dictionary, list: Array, box: Dictionary, parent_id: String, out: Dictionary) -> void:
	for w: Dictionary in list:
		var r := cell_rect(box, cells_of(w))
		var entry := {"rect": r, "local": Rect2(r.position - box["rect"].position, r.size),
			"parent": parent_id}
		if w.has("children"):
			entry.merge(_inner_box(theme, w, r, box))
			_place(theme, w["children"], entry, w["id"], out)
		out[w["id"]] = entry


## The grid inside container [param w]. Without its own "grid" it has as
## many cells as it spans and the same gap as around it, so its cells line up
## with the outer ones: a group of blocks looks exactly like the blocks did.
static func _inner_box(theme: Dictionary, w: Dictionary, r: Rect2, outer: Dictionary) -> Dictionary:
	var g: Dictionary = w.get("grid", {})
	var content := r
	if w["type"] == "panel":
		var p: Dictionary = theme["panel"]
		var top := float(p["titleHeight"]) if not str(w.get("title", "")).is_empty() else 0.0
		var pad := float(p["padding"])
		content = Rect2(r.position + Vector2(pad, top + pad),
				(r.size - Vector2(pad * 2.0, top + pad * 2.0)).max(Vector2.ONE))
	return {
		"content": content,
		"cols": maxi(1, int(g.get("cols", w["cw"]))),
		"rows": maxi(1, int(g.get("rows", w["ch"]))),
		"gap": float(g.get("gap", outer["gap"])),
		"strict": GuiWidgetTypes.container(w["type"]) == "strict",
	}


static func cells_of(w: Dictionary) -> Rect2i:
	return Rect2i(int(w.get("col", 0)), int(w.get("row", 0)),
			maxi(1, int(w.get("cw", 1))), maxi(1, int(w.get("ch", 1))))


static func set_cells(w: Dictionary, cells: Rect2i) -> void:
	w["col"] = cells.position.x
	w["row"] = cells.position.y
	w["cw"] = cells.size.x
	w["ch"] = cells.size.y


## One cell's size in pixels.
static func cell_size(box: Dictionary) -> Vector2:
	var c: Rect2 = box["content"]
	var gap: float = box["gap"]
	return Vector2(
		maxf(1.0, (c.size.x - gap * (box["cols"] - 1)) / box["cols"]),
		maxf(1.0, (c.size.y - gap * (box["rows"] - 1)) / box["rows"]))


## Distance from one cell to the next, gap included.
static func pitch(box: Dictionary) -> Vector2:
	return cell_size(box) + Vector2(box["gap"], box["gap"])


static func cell_rect(box: Dictionary, cells: Rect2i) -> Rect2:
	var cell := cell_size(box)
	var gap: float = box["gap"]
	var origin: Vector2 = box["content"].position
	return Rect2(
		origin + Vector2(cells.position) * (cell + Vector2(gap, gap)),
		Vector2(cells.size) * cell + Vector2(cells.size - Vector2i.ONE) * gap)


## The cell under [param point] (page coordinates), clamped into the grid.
static func cell_at(box: Dictionary, point: Vector2) -> Vector2i:
	var origin: Vector2 = box["content"].position
	var p := ((point - origin) / pitch(box)).floor()
	return Vector2i(clampi(int(p.x), 0, box["cols"] - 1), clampi(int(p.y), 0, box["rows"] - 1))


static func bounds(box: Dictionary) -> Rect2i:
	return Rect2i(0, 0, box["cols"], box["rows"])


## True when [param cells] lies inside the box and covers no block in
## [param list] other than those whose ids are in [param ignore].
static func fits(box: Dictionary, list: Array, cells: Rect2i, ignore: Array = []) -> bool:
	if not bounds(box).encloses(cells):
		return false
	for w: Dictionary in list:
		if not w["id"] in ignore and cells_of(w).intersects(cells):
			return false
	return true


## The free position for a block of [param block] cells nearest to
## [param near], or (-1, -1) when it fits nowhere.
static func free_spot(box: Dictionary, list: Array, block: Vector2i, near: Vector2i,
		ignore: Array = []) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_gap := INF
	for row in box["rows"] - block.y + 1:
		for col in box["cols"] - block.x + 1:
			var at := Vector2i(col, row)
			var gap := Vector2(at - near).length_squared()
			if gap < best_gap and fits(box, list, Rect2i(at, block), ignore):
				best = at
				best_gap = gap
	return best


## Ids of blocks in [param list] that overlap another block or stick out of
## the box. Packages edited by hand or migrated from pixels can have them.
static func conflicts(box: Dictionary, list: Array) -> Array[String]:
	var out: Array[String] = []
	for i in list.size():
		var a := cells_of(list[i])
		if not bounds(box).encloses(a):
			out.append(list[i]["id"])
			continue
		for j in list.size():
			if i != j and a.intersects(cells_of(list[j])):
				out.append(list[i]["id"])
				break
	return out
