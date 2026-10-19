class_name ThrowButton
extends BombButton
## The THROW button, above the bomb button.
##   Tap it:  throw what you're holding where you're aiming (or at the
##            nearest enemy in front of you).
##   Drag from it, then lift: throw in the dragged direction.
## A thrown weapon knocks down the first enemy it hits, then lies on the floor.

## The bomb button it sits above (set by TouchControls). Placing it from the
## bomb button keeps the two apart on every screen size.
var bomb: BombButton

## True while you hold something you can throw (not bare fists).
var can_throw: bool = false:
	set(new_value):
		can_throw = new_value
		queue_redraw()


func get_button_center() -> Vector2:
	if bomb:
		return bomb.get_button_center() + Vector2(0, -bomb.radius * 2.8)
	return super.get_button_center()


func _draw() -> void:
	var center := get_button_center()
	var alpha := 0.9 if can_throw else 0.25
	draw_circle(center, radius, Color(color, 0.18 * alpha))
	draw_arc(center, radius, 0.0, TAU, 32, Color(color, alpha), 2.0)
	if is_active:
		draw_circle(_knob, radius * 0.35, Color(color, 0.6))
	var font := ThemeDB.fallback_font
	var size := 12
	var text_width := font.get_string_size("THROW", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center + Vector2(-text_width * 0.5, size * 0.35), "THROW", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(count_color, alpha))
