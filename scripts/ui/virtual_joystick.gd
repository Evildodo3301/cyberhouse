class_name VirtualJoystick
extends Node2D
## A "floating" thumbstick: it appears wherever your thumb lands on its half
## of the screen, and follows that one finger until it lifts.
##
## Other scripts read `value` (a direction from -1 to 1 on each axis) and can
## listen to the `released` signal.

## Emitted when the finger lifts. `final_value` is the last stick direction
## (Vector2.ZERO if it stayed in the dead zone). `was_tap` is true for a
## quick touch that barely moved.
signal released(final_value: Vector2, was_tap: bool)

enum StickSide { LEFT, RIGHT }

## Which half of the screen this stick listens to.
@export var side: StickSide = StickSide.LEFT
## How far (in screen pixels) the knob can move from the center.
@export var radius: float = 40.0
## Real-world radius in cm (0 = use `radius` as is). Keeps the stick the same
## size under the thumb on phones and tablets.
@export var radius_cm: float = 1.1
## Small movements under this fraction of the radius are ignored.
@export var dead_zone: float = 0.2
## A touch shorter than this (seconds) that stays in the dead zone is a tap.
@export var tap_max_time: float = 0.25
## Touches in the top part of the screen are left for buttons (pause etc.).
@export var top_ui_margin: float = 48.0
## Neon color for the drawing.
@export var color: Color = Color(0.16, 0.94, 1.0)

## Other controls (like the bomb button) that sit inside this stick's half of
## the screen. Touches on them are left alone.
var blocked_by: Array[VirtualJoystick] = []

## Current stick direction. Length is between 0 and 1.
var value: Vector2 = Vector2.ZERO
## True while a finger is on this stick.
var is_active: bool = false

var _touch_index: int = -1   # which finger owns this stick (-1 = none)
var _center: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO
var _touch_start_ms: int = 0
var _left_dead_zone: bool = false


func _ready() -> void:
	_update_sizes()
	get_viewport().size_changed.connect(_update_sizes)


## Turns the real-world sizes (cm) into game pixels for this screen.
func _update_sizes() -> void:
	if radius_cm > 0.0:
		radius = ScreenUnits.cm(get_viewport(), radius_cm, 32.0, 56.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and _is_my_area(event.position):
			_start(event)
		elif not event.pressed and event.index == _touch_index:
			_finish()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_drag(event.position)


func _notification(what: int) -> void:
	# If the game pauses while a finger is down, forget that finger.
	if what == NOTIFICATION_PAUSED:
		_reset()


func _is_my_area(pos: Vector2) -> bool:
	var screen := get_viewport().get_visible_rect().size
	if pos.y < top_ui_margin:
		return false
	for other in blocked_by:
		if other.covers(pos):
			return false
	var on_left := pos.x < screen.x * 0.5
	return on_left if side == StickSide.LEFT else not on_left


## True if this control takes up the screen at `pos`. A floating stick has no
## fixed spot, so it never blocks anything. The bomb button overrides this.
func covers(_pos: Vector2) -> bool:
	return false


## Where the stick's center goes when a finger lands at `pos`.
## Floating stick: right under the finger. The bomb button overrides this.
func _start_center(pos: Vector2) -> Vector2:
	return pos


func _start(event: InputEventScreenTouch) -> void:
	_touch_index = event.index
	_center = _start_center(event.position)
	_knob = event.position
	_touch_start_ms = Time.get_ticks_msec()
	_left_dead_zone = false
	is_active = true
	value = Vector2.ZERO
	queue_redraw()


func _drag(pos: Vector2) -> void:
	var offset := (pos - _center).limit_length(radius)
	_knob = _center + offset
	var raw := offset / radius
	if raw.length() >= dead_zone:
		value = raw
		_left_dead_zone = true
	else:
		value = Vector2.ZERO
	queue_redraw()


func _finish() -> void:
	var held_time := (Time.get_ticks_msec() - _touch_start_ms) / 1000.0
	var was_tap := not _left_dead_zone and held_time <= tap_max_time
	var final_value := value
	_reset()
	released.emit(final_value, was_tap)


func _reset() -> void:
	_touch_index = -1
	is_active = false
	value = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if is_active:
		draw_arc(_center, radius, 0.0, TAU, 32, Color(color, 0.5), 2.0)
		draw_circle(_knob, radius * 0.4, Color(color, 0.6))
	else:
		# A faint hint showing where to put your thumb.
		var screen := get_viewport().get_visible_rect().size
		var hint_x := 90.0 if side == StickSide.LEFT else screen.x - 90.0
		draw_arc(Vector2(hint_x, screen.y - 80.0), radius, 0.0, TAU, 32, Color(color, 0.15), 2.0)
