extends Node
## Autoload: one running copy, window title, window size/position persistence.
##
## Three jobs:
##   - One copy at a time. A second one would quietly undo the first's work,
##     because both write the same layout file with no lock between them.
##   - Title. Godot names the window after the project alone, so the version
##     has to be applied at runtime. application/config/version stays the one
##     place the version is written down.
##   - Window state. The size, position and maximised state the user leaves the
##     window in are restored on the next run, clamped so the window always
##     lands somewhere visible even if the screen layout changed since.

const TITLE_FORMAT := "%s (V %s)"

const STATE_PATH := "user://window_state.cfg"
const STATE_SECTION := "window"
const POLL_INTERVAL := 0.5

## The port the running copy holds open. Nothing is ever done with it beyond
## the greeting below: that it cannot be bound twice is the whole mechanism.
## Loopback only, so nothing off this machine can reach it and no firewall
## rule is wanted. It sits in the private range and is deliberately not a
## round number, to keep out of the way of anything a user might also run.
const LOCK_PORT := 49815
## What the holder answers with, so a port held by something else can be told
## apart from a port held by us.
const LOCK_GREETING := "GUIBuilder/single-instance/1"
## How long to wait for that answer. The holder sends it from its own frame
## loop, so this is reached only when the holder is not GUI Builder at all.
const LOCK_REPLY_MS := 1500

var _saved_size := Vector2i.ZERO
var _saved_position := Vector2i.ZERO
var _saved_maximized := false
var _lock := TCPServer.new()


func _ready() -> void:
	if not _claim_single_instance():
		return
	_apply_title()

	# Inside the editor's Game view the editor owns the window's size, and
	# saving it would leave the next real run restored to that small panel.
	if Engine.is_embedded_in_editor():
		return
	_restore_window()

	# The editor's Stop button kills the process without a close request, and
	# so does a crash, so poll instead of relying on the shutdown path alone.
	var timer := Timer.new()
	timer.wait_time = POLL_INTERVAL
	timer.timeout.connect(_save_if_changed)
	add_child(timer)
	timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not Engine.is_embedded_in_editor():
		_save_if_changed()


## --- one copy at a time ----------------------------------------------------

## True when this process may carry on, having taken the lock.
##
## The lock is a listening socket rather than a lock file, because a file has
## to be cleaned up and a socket does not: the operating system takes the port
## back however the process ends, a crash or a kill included, so there is no
## stale lock to recover from and nothing to go wrong on a machine that lost
## power mid-session.
##
## A port can of course be held by something that is not GUI Builder, and
## refusing to start then would be a worse fault than the one being prevented.
## So a failed bind is not taken as proof. The holder is asked who it is, and
## only an answer in our own words counts; anything else, and this copy starts
## normally with a line in the log saying the lock was given up on.
func _claim_single_instance() -> bool:
	if _lock.listen(LOCK_PORT, "127.0.0.1") == OK:
		return true
	if not _lock_held_by_us():
		push_warning("port %d is held by something that is not GUI Builder, " % LOCK_PORT
				+ "so this copy starts without the single-instance lock")
		return true

	# The window is already up by the time an autoload runs, so without this a
	# second, empty copy of the application sits on screen behind a message
	# saying it is not going to open. Godot refuses to hide the main window
	# outright — "Can't change visibility of main window" — so it goes out of
	# the way instead.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	OS.alert("GUI Builder is already running.", "GUI Builder")
	get_tree().quit()
	return false


## Whether whoever holds the port answers the way a running GUI Builder does.
func _lock_held_by_us() -> bool:
	var asking := StreamPeerTCP.new()
	if asking.connect_to_host("127.0.0.1", LOCK_PORT) != OK:
		return false

	var wanted := LOCK_GREETING.length()
	var deadline := Time.get_ticks_msec() + LOCK_REPLY_MS
	while Time.get_ticks_msec() < deadline:
		asking.poll()
		var status := asking.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return false
		if asking.get_available_bytes() >= wanted:
			var said: Array = asking.get_partial_data(wanted)
			asking.disconnect_from_host()
			return (said[1] as PackedByteArray).get_string_from_ascii() == LOCK_GREETING
		OS.delay_msec(10)

	asking.disconnect_from_host()
	return false


## Answers anyone asking who holds the port. This is the only traffic the lock
## socket ever carries.
func _process(_delta: float) -> void:
	if not _lock.is_listening() or not _lock.is_connection_available():
		return
	var asking := _lock.take_connection()
	asking.put_data(LOCK_GREETING.to_ascii_buffer())
	asking.disconnect_from_host()


## --- title -----------------------------------------------------------------

func _apply_title() -> void:
	var app_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if app_name.is_empty():
		return
	get_window().title = TITLE_FORMAT % [app_name, version] if not version.is_empty() else app_name


## --- window state ----------------------------------------------------------

## Usable area of the screen the window is on: the desktop minus the taskbar.
func _usable_rect() -> Rect2i:
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())


## Width/height the title bar and borders add on top of the client area.
func _decoration_margin() -> Vector2i:
	return DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()


## Shrinks a requested size until the window, frame included, fits the screen.
func _fit_to_screen(size: Vector2i) -> Vector2i:
	var limit := _usable_rect().size - _decoration_margin()
	return Vector2i(mini(size.x, maxi(limit.x, 1)), mini(size.y, maxi(limit.y, 1)))


## Keeps the whole frame on screen; a saved position from a monitor that is no
## longer attached would otherwise put the window out of reach.
func _clamp_position(position: Vector2i, size: Vector2i) -> Vector2i:
	var usable := _usable_rect()
	var frame := size + _decoration_margin()
	var max_x := usable.position.x + maxi(usable.size.x - frame.x, 0)
	var max_y := usable.position.y + maxi(usable.size.y - frame.y, 0)
	return Vector2i(
		clampi(position.x, usable.position.x, max_x),
		clampi(position.y, usable.position.y, max_y))


func _centered_position(size: Vector2i) -> Vector2i:
	var usable := _usable_rect()
	var frame := size + _decoration_margin()
	# Window positions are whole pixels; the half-pixel is not meaningful.
	@warning_ignore("integer_division")
	return usable.position + (usable.size - frame) / 2


func _restore_window() -> void:
	var window := get_window()
	var config := ConfigFile.new()
	if config.load(STATE_PATH) != OK:
		# First run: the project's start mode stands. A windowed start is only
		# shrunk to fit and centred; a maximised one needs nothing.
		if window.mode == Window.MODE_WINDOWED:
			window.size = _fit_to_screen(window.size)
			window.position = _centered_position(window.size)
		_remember()
		return

	var size := _fit_to_screen(config.get_value(STATE_SECTION, "size", window.size))
	var position: Vector2i = config.get_value(STATE_SECTION, "position", _centered_position(size))

	# The windowed geometry goes in first even when the window is about to be
	# maximised, so that un-maximising returns to it rather than to the
	# project's default size.
	window.mode = Window.MODE_WINDOWED
	window.size = size
	window.position = _clamp_position(position, size)
	if config.get_value(STATE_SECTION, "maximized", false):
		window.mode = Window.MODE_MAXIMIZED

	_saved_size = size
	_saved_position = window.position
	_saved_maximized = window.mode != Window.MODE_WINDOWED


func _remember() -> void:
	_saved_size = DisplayServer.window_get_size()
	_saved_position = DisplayServer.window_get_position()
	_saved_maximized = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED


func _save_if_changed() -> void:
	var mode := DisplayServer.window_get_mode()
	# Ignore a minimised window: its reported geometry is not worth restoring.
	if mode == DisplayServer.WINDOW_MODE_MINIMIZED:
		return

	# Maximised and full screen both report the screen's geometry, not the
	# user's, so the last windowed size and position are kept through them.
	var maximized := mode != DisplayServer.WINDOW_MODE_WINDOWED
	var size := _saved_size if maximized else DisplayServer.window_get_size()
	var position := _saved_position if maximized else DisplayServer.window_get_position()
	if size == _saved_size and position == _saved_position and maximized == _saved_maximized:
		return

	var config := ConfigFile.new()
	config.set_value(STATE_SECTION, "size", size)
	config.set_value(STATE_SECTION, "position", position)
	config.set_value(STATE_SECTION, "maximized", maximized)
	var err := config.save(STATE_PATH)
	if err != OK:
		push_warning("could not save window state: %s" % error_string(err))
		return
	_saved_size = size
	_saved_position = position
	_saved_maximized = maximized
