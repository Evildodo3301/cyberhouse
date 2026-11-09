extends Node2D
## The level exit. Locked (dim) until every enemy is dead, then it glows;
## step into it to finish the level.

signal reached

var rect: Rect2
## A staircase exit: the way you walk off once you step on it (ZERO = an
## ordinary exit, the level ends as soon as you reach it).
var walk := Vector2.ZERO
var open: bool = false
var _pulse: float = 0.0
var _done: bool = false


func _ready() -> void:
	add_to_group("exit")


func unlock() -> void:
	open = true


func _physics_process(delta: float) -> void:
	_pulse += delta
	queue_redraw()
	if not open or _done:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.is_alive() and rect.has_point(player.global_position):
		_done = true
		reached.emit()


func _draw() -> void:
	var glow := 0.25 + 0.2 * sin(_pulse * 4.0) if open else 0.08
	draw_rect(rect, Color(0.2, 1.0, 0.5, glow))
	draw_rect(rect, Color(0.2, 1.0, 0.5, 0.9 if open else 0.3), false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(-12, -3), "STAIRS" if walk != Vector2.ZERO else "EXIT", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x + 24, 8, Color(0.2, 1.0, 0.5, 0.9 if open else 0.4))
