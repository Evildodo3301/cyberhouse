class_name PatternLogged
extends CanvasLayer
## The implant HUD for learning enemies (M3).
## - On a restart after a death: "PATTERN LOGGED: <move>" glitches on screen
##   for each move the room just blocked. It never pauses the game.
## - Always: a small "BLOCKED:" line, so you know which moves won't work.

## How long the glitch message stays up, in seconds.
@export var show_time: float = 1.4
@export var glitch_color: Color = Color(1.0, 0.25, 0.1)

var _message: Label
var _blocked: Label
var _time_left: float = 0.0


func _ready() -> void:
	layer = 6
	_message = _make_label(18, glitch_color)
	_message.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.position = Vector2(-160, 90)
	_message.size = Vector2(320, 60)
	_blocked = _make_label(10, Color(glitch_color, 0.8))
	_blocked.position = Vector2(44, 28)   # under the weapon name
	refresh()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## Reads the tracker: shows newly logged patterns and the blocked list.
func refresh() -> void:
	var blocked: Array = TacticTracker.get_active_counters()
	_blocked.text = "" if blocked.is_empty() else "BLOCKED: " + " · ".join(blocked.map(pretty))
	var new_blocks := TacticTracker.take_new_blocks()
	if new_blocks.is_empty():
		_message.visible = false
		return
	_message.text = "\n".join(new_blocks.map(func(t): return "PATTERN LOGGED: " + pretty(t)))
	_message.visible = true
	_time_left = show_time


static func pretty(tactic: StringName) -> String:
	return String(tactic).replace("_", " ")


func _process(delta: float) -> void:
	if not _message.visible:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_message.visible = false
		return
	# Glitch: jitter, colour split and the odd dropped frame.
	_message.position = Vector2(-160, 90) + Vector2(randf_range(-3, 3), randf_range(-1.5, 1.5))
	_message.modulate = Color(1, 1, 1, 0.0 if randf() < 0.12 else 1.0)
	_message.add_theme_color_override("font_color", glitch_color if randf() < 0.8 else Color(0.16, 0.94, 1.0))
