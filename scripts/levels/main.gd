extends Node2D
## The test room: connects the pieces together and notices when every enemy
## is dead.

## Unique name for this room. The learning system keeps its memory per room.
@export var room_id: StringName = &"m1_test_arena"

@onready var player: Player = $Player
@onready var touch_controls: TouchControls = $TouchControls
@onready var death_screen: DeathScreen = $DeathScreen


func _ready() -> void:
	TacticTracker.enter_room(room_id)
	# Hand the touch controls to the player and route button presses to it.
	player.touch_controls = touch_controls
	touch_controls.attack_requested.connect(player.request_attack)
	touch_controls.bomb_requested.connect(player.request_bomb)
	# Keep the counter on the bomb button in sync.
	touch_controls.bomb_button.bombs_left = player.bombs_left
	player.bombs_changed.connect(func(count): touch_controls.bomb_button.bombs_left = count)
	player.died.connect(func(_weapon): death_screen.show_death())
	Game.enemy_died.connect(_on_enemy_died)


func _on_enemy_died(_enemy: Node2D) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_alive():
			return
	# Room beaten: the learning system can forget this room.
	TacticTracker.clear_room(room_id)
	_show_banner("ROOM CLEAR")


## Big text across the top of the screen (placeholder until the UI pass).
func _show_banner(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.16, 0.94, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.position.y = 56
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	add_child(layer)


func _unhandled_input(event: InputEvent) -> void:
	# Press R on a keyboard to restart the room (instant restart test).
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		Game.restart_room()
	# Press B to cycle the blood setting: full, reduced, off.
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_B:
		Game.cycle_blood_level()
