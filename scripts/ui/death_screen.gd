class_name DeathScreen
extends CanvasLayer
## Shown when the player dies: red tint and "TAP TO RETRY".
## Any tap (or any key) restarts the room instantly.

## Ignore taps for this long after dying, so the finger that was already on
## the screen doesn't restart by accident.
@export var input_delay: float = 0.25

## Set when a level is finished: the tap goes to this scene instead.
var next_scene: String = ""
var _shown_at_ms: int = -1
var _tint: ColorRect
var _label: Label


func _ready() -> void:
	layer = 10   # draw above the touch controls
	visible = false
	_tint = ColorRect.new()
	var tint := _tint
	tint.color = Color(0.6, 0.0, 0.1, 0.35)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	_label = Label.new()
	var label := _label
	label.text = "TAP TO RETRY"
	label.add_theme_font_size_override("font_size", 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(label)


## Same screen with other words and colour (used for LEVEL COMPLETE).
func show_message(text: String, tint_color: Color) -> void:
	_label.text = text
	_tint.color = tint_color
	show_death()


func show_death() -> void:
	visible = true
	_shown_at_ms = Time.get_ticks_msec()


func _input(event: InputEvent) -> void:
	if not visible or Time.get_ticks_msec() - _shown_at_ms < input_delay * 1000.0:
		return
	var tapped: bool = event is InputEventScreenTouch and event.pressed
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	if tapped or key:
		get_viewport().set_input_as_handled()
		if next_scene != "":
			Game.load_level(next_scene)
		else:
			Game.restart_room()
