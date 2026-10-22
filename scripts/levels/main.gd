extends Node2D
## Runs one level: connects the pieces together, notices when every enemy
## is dead, then opens the exit (if the level has one).

## Unique name for this room. The learning system keeps its memory per room.
@export var room_id: StringName = &"m1_test_arena"
## The level that comes after this one (empty = replay this one).
@export_file("*.tscn") var next_level: String = ""
## Levels with more than one floor: each floor is its own scene, and the
## stairs ("exit_walk" in the map) take you to `next_floor` behind a
## loading screen showing `stairs_picture`.
@export_file("*.tscn") var next_floor: String = ""
@export var stairs_picture: Texture2D
## Walking off up the stairs: how long, and the fade to black at the same time.
@export var stairs_walk_time: float = 0.9

@onready var player: Player = $Player
@onready var touch_controls: TouchControls = $TouchControls
@onready var death_screen: DeathScreen = $DeathScreen


var _started_ms: int = 0


func _enter_tree() -> void:
	# Before the enemies' _ready(), so they read THIS level's learned counters.
	TacticTracker.enter_room(room_id)


func _ready() -> void:
	# On an upper floor the clock carries on from the floor below.
	_started_ms = Time.get_ticks_msec() - int(Game.carried.get("seconds", 0.0) * 1000.0)
	# Hand the touch controls to the player and route button presses to it.
	player.touch_controls = touch_controls
	touch_controls.attack_requested.connect(player.request_attack)
	touch_controls.bomb_requested.connect(player.request_bomb)
	touch_controls.throw_requested.connect(player.request_throw)
	player.weapon_changed.connect(func(weapon, _ammo): touch_controls.throw_button.can_throw = weapon != player.settings.start_weapon)
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
	# Two-floor levels: say which floor you're on when you take the stairs.
	var map := get_node_or_null("LevelMap")
	if map and map.has_signal("floor_changed"):
		map.floor_changed.connect(func(storey: int): _show_banner("FLOOR %d" % storey))
	# Up the stairs with the weapon you were holding.
	if Game.carried.has("weapon"):
		player.equip(load(Game.carried.weapon), Game.carried.ammo)


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
	var exit_zone := get_tree().get_first_node_in_group("exit")
	if exit_zone.walk != Vector2.ZERO:
		# Stairs: you walk off on your own, then the next floor (or the end).
		player.auto_walk = exit_zone.walk
		if next_floor != "":
			await _fade_to_black(stairs_walk_time)
			var board: ScoreBoard = $ScoreBoard
			Game.take_stairs(next_floor, stairs_picture, {
				"score": board.score, "combo": board.combo, "combo_left": board._combo_left,
				"seconds": (Time.get_ticks_msec() - _started_ms) / 1000.0,
				"weapon": player.weapon.resource_path, "ammo": player.ammo,
			})
			return
		await get_tree().create_timer(stairs_walk_time).timeout
		player.auto_walk = Vector2.ZERO
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	var score: int = $ScoreBoard.score
	var next := "TAP FOR THE NEXT LEVEL" if next_level != "" else "TAP TO PLAY AGAIN"
	death_screen.next_scene = next_level
	death_screen.show_message("LEVEL COMPLETE\n%d:%04.1f   SCORE %d\n%s" % [int(seconds) / 60, fmod(seconds, 60.0), score, next], Color(0.1, 0.6, 0.3, 0.35))


func _add_weapon_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	var label := Label.new()
	label.position = Vector2(44, 8)   # right of the pause button
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	# The weapon's side-view icon, drawn 2x, with the name and ammo after it.
	var icon := TextureRect.new()
	icon.name = "WeaponIcon"
	icon.position = Vector2(44, 8)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(icon)
	add_child(layer)
	var show_weapon := func(weapon: WeaponData, ammo: int):
		label.text = weapon.display_name + ("  %d" % ammo if ammo >= 0 else "")
		icon.texture = weapon.icon
		icon.visible = weapon.icon != null
		if weapon.icon:
			icon.scale = Vector2(2, 2)
			icon.position.y = 18 - weapon.icon.get_height()
		label.position.x = 44 + (weapon.icon.get_width() * 2 + 8 if weapon.icon else 0)
	player.weapon_changed.connect(show_weapon)
	show_weapon.call(player.weapon, player.ammo)


func _fade_to_black(seconds: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9   # over the game and the controls
	var black := ColorRect.new()
	black.name = "FadeToBlack"
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	add_child(layer)
	await create_tween().tween_property(black, "color:a", 1.0, seconds).finished


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
