class_name BombButton
extends VirtualJoystick
## A round button that sits above the aim zone, on the right side.
##   Tap it:  throw a bomb where you're aiming (or facing).
##   Drag from it, then lift: throw in the dragged direction.
## It is a VirtualJoystick that stays in one fixed spot, so it reuses all the
## finger-tracking code. The bomb count is drawn on the button.

## Button center, measured from the bottom-right corner of the screen.
@export var offset_from_corner: Vector2 = Vector2(120, 190)
## Text color for the counter.
@export var count_color: Color = Color(1, 1, 1)

## Shown on the button. Set by the player.
var bombs_left: int = 0:
	set(new_value):
		bombs_left = new_value
		queue_redraw()


func get_button_center() -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	return screen - offset_from_corner


func covers(pos: Vector2) -> bool:
	# A little extra room so a slightly-off tap doesn't start an aim instead.
	return pos.distance_to(get_button_center()) <= radius * 1.25


func _is_my_area(pos: Vector2) -> bool:
	return covers(pos)


func _start_center(_pos: Vector2) -> Vector2:
	return get_button_center()


func _draw() -> void:
	var center := get_button_center()
	var alpha := 0.9 if bombs_left > 0 else 0.25
	draw_circle(center, radius, Color(color, 0.18 * alpha))
	draw_arc(center, radius, 0.0, TAU, 32, Color(color, alpha), 2.0)
	if is_active:
		draw_circle(_knob, radius * 0.35, Color(color, 0.6))
	var font := ThemeDB.fallback_font
	var label := "BOMB %d" % bombs_left
	var size := 12
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center + Vector2(-text_width * 0.5, size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(count_color, alpha))
