extends Node2D
## The M1 test scene. Its only job is to connect the pieces together.

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


func _unhandled_input(event: InputEvent) -> void:
	# Press R on a keyboard to restart the room (instant restart test).
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		Game.restart_room()
	# Press B to cycle the blood setting: full, reduced, off.
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_B:
		Game.cycle_blood_level()
