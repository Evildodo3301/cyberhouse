extends Node2D
## Runs one level: connects the pieces together, notices when every enemy
## is dead, then opens the exit (if the level has one).

## Unique name for this room. The learning system keeps its memory per room.
@export var room_id: StringName = &"m1_test_arena"

@onready var player: Player = $Player
@onready var touch_controls: TouchControls = $TouchControls
@onready var death_screen: DeathScreen = $DeathScreen


var _started_ms: int = 0


func _enter_tree() -> void:
	# Before the enemies' _ready(), so they read THIS level's learned counters.
	TacticTracker.enter_room(room_id)


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	# Hand the touch controls to the player and route button presses to it.
	player.touch_controls = touch_controls
	touch_controls.attack_requested.connect(player.request_attack)
	touch_controls.bomb_requested.connect(player.request_bomb)
	# Keep the counter on the bomb button in sync.
	touch_controls.bomb_button.bombs_left = player.bombs_left
	player.bombs_changed.connect(func(count): touch_controls.bomb_button.bombs_left = count)
	player.died.connect(func(_weapon): death_screen.show_death())
	# Weapon and ammo in the top-left corner.
	_add_weapon_label()
	# Learning enemies: "PATTERN LOGGED" after a death, and the blocked moves.
	var pattern_hud := PatternLogged.new()
	pattern_hud.name = "PatternLogged"
	add_child(pattern_hud)
	Game.enemy_died.connect(_on_enemy_died)
	# Score: "+400" popups on kills, a combo counter and the total.
	var score_board := ScoreBoard.new()
	score_board.name = "ScoreBoard"
	add_child(score_board)
	# Gunshots flash the void outside the map; kills change its colour.
	var void_flash := VoidFlash.new()
	void_flash.name = "VoidFlash"
	add_child(void_flash)


func _on_enemy_died(_enemy: Node2D) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_alive():
			return
	# Room beaten: the learning system can forget this room.
	TacticTracker.clear_room(room_id)
	var exit_zone := get_tree().get_first_node_in_group("exit")
	if exit_zone:
		exit_zone.unlock()
		exit_zone.reached.connect(_on_exit_reached)
		_show_banner("CLEAR - GET TO THE EXIT")
	else:
		_show_banner("ROOM CLEAR")


func _on_exit_reached() -> void:
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	var score: int = $ScoreBoard.score
	death_screen.show_message("LEVEL COMPLETE\n%d:%04.1f   SCORE %d\nTAP TO PLAY AGAIN" % [int(seconds) / 60, fmod(seconds, 60.0), score], Color(0.1, 0.6, 0.3, 0.35))


func _add_weapon_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	var label := Label.new()
	label.position = Vector2(44, 8)   # right of the pause button
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	add_child(layer)
	var show_weapon := func(weapon: WeaponData, ammo: int):
		label.text = weapon.display_name + ("  %d" % ammo if ammo >= 0 else "")
	player.weapon_changed.connect(show_weapon)
	show_weapon.call(player.weapon, player.ammo)


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
