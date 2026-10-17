class_name Player
extends CharacterBody2D
## The hitman for Milestone 1: moves, aims and swings a melee weapon.
##
## Controls (both work at the same time):
##   Touch:    left thumb = move, right thumb = aim, lift right thumb = attack,
##             quick tap on the right = attack the nearest target in front,
##             BOMB button = throw a bomb.
##   Keyboard: WASD = move, arrow keys = aim, Space = attack, E = bomb (for PC testing).

## Emitted the moment a swing kills something. The camera uses it to shake
## (and in M5 the hit sound will listen to it too, so they stay in sync).
signal killed_target(target: Node2D, direction: Vector2)
## Emitted when the bomb count changes, so the button can show it.
signal bombs_changed(bombs_left: int)
## Emitted once when the player dies. `weapon` is what killed them.
signal died(weapon: String)

const BOMB_SCENE := preload("res://scenes/weapons/bomb.tscn")

## All the tuning numbers. Edit res://data/player_settings.tres to change them.
@export var settings: PlayerSettings
@export var body_color: Color = Color(1.0, 0.16, 0.54)   # neon pink
@export var accent_color: Color = Color(0.16, 0.94, 1.0) # neon cyan

## Set by main.gd. Can stay empty (keyboard only).
var touch_controls: TouchControls

## The direction the hitman is looking (always length 1).
var facing: Vector2 = Vector2.RIGHT
## Bombs left in this room.
var bombs_left: int = 0
var _alive: bool = true

# The attack goes through three steps: READY -> WINDUP -> RECOVERY -> READY.
enum AttackState { READY, WINDUP, RECOVERY }
var _attack_state: AttackState = AttackState.READY
var _attack_timer: float = 0.0
var _attack_direction: Vector2 = Vector2.RIGHT
var _swing_flash: float = 0.0   # how long the swing arc stays visible


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()   # fall back to default values
	add_to_group("player")   # bombs look for this group
	bombs_left = settings.bombs_per_room


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_update_movement(delta)
	_update_facing()
	if Input.is_action_just_pressed("attack"):
		request_attack(_keyboard_aim())   # ZERO = "nearest target", like a tap
	if Input.is_action_just_pressed("throw_bomb"):
		request_bomb(Vector2.ZERO)
	_update_attack(delta)
	queue_redraw()


# ---------------------------------------------------------------- movement

func _read_move_input() -> Vector2:
	if touch_controls and touch_controls.move_vector != Vector2.ZERO:
		return touch_controls.move_vector
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _update_movement(delta: float) -> void:
	var input := _read_move_input()
	if input != Vector2.ZERO:
		# Fixed speed in M1: the stick only chooses the direction.
		var target_velocity := input.normalized() * settings.move_speed
		var accel := settings.move_speed / maxf(settings.accel_time, 0.001)
		velocity = velocity.move_toward(target_velocity, accel * delta)
	else:
		var decel := settings.move_speed / maxf(settings.stop_time, 0.001)
		velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
	move_and_slide()   # moves the body and stops it at walls


# ------------------------------------------------------------------ aiming

func _keyboard_aim() -> Vector2:
	return Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")


## The direction the player is actively aiming, or ZERO when not aiming.
func get_aim_input() -> Vector2:
	if touch_controls and touch_controls.aim_vector != Vector2.ZERO:
		return touch_controls.aim_vector.normalized()
	return _keyboard_aim().normalized()


func _update_facing() -> void:
	# Don't turn in the middle of a swing.
	if _attack_state == AttackState.WINDUP:
		return
	var aim := get_aim_input()
	if aim != Vector2.ZERO:
		facing = aim                        # aiming wins...
	elif velocity.length() > 1.0:
		facing = velocity.normalized()      # ...otherwise face where you walk


## Aim assist: if a target sits close to the aim line, return the direction
## to it. Otherwise return the aim unchanged.
func assisted_direction(aim: Vector2) -> Vector2:
	var target := _find_target(aim, settings.aim_assist_range, settings.aim_assist_degrees)
	if target:
		return global_position.direction_to(target.global_position)
	return aim


## Finds the closest living target within `max_distance` and within
## `max_degrees` either side of `direction`. Returns null if none.
func _find_target(direction: Vector2, max_distance: float, max_degrees: float) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("targets"):
		var target := node as Node2D
		if target == null or not target.is_alive():
			continue
		var to_target := target.global_position - global_position
		var distance := to_target.length()
		if distance > max_distance or distance >= best_distance:
			continue
		if absf(rad_to_deg(direction.angle_to(to_target))) > max_degrees:
			continue
		best = target
		best_distance = distance
	return best


# ------------------------------------------------------------------ attack

## Ask for an attack. `direction` = where to swing, or ZERO for a quick tap
## (swing at the nearest target in front, or straight ahead if there is none).
func request_attack(direction: Vector2) -> void:
	if not _alive or _attack_state != AttackState.READY:
		return   # still swinging or recovering
	if direction == Vector2.ZERO:
		var target := _find_target(facing, settings.tap_assist_radius, settings.tap_assist_degrees)
		direction = global_position.direction_to(target.global_position) if target else facing
	else:
		direction = assisted_direction(direction.normalized())
	_attack_direction = direction
	facing = direction
	_attack_state = AttackState.WINDUP
	_attack_timer = settings.windup_time


func _update_attack(delta: float) -> void:
	_swing_flash = maxf(_swing_flash - delta, 0.0)
	if _attack_state == AttackState.READY:
		return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	if _attack_state == AttackState.WINDUP:
		_strike()
		_attack_state = AttackState.RECOVERY
		_attack_timer = settings.recovery_time
	else:
		_attack_state = AttackState.READY


## The moment the swing lands: hit every target inside the arc.
func _strike() -> void:
	_swing_flash = 0.08
	var half_arc := settings.melee_arc_degrees * 0.5
	for node in get_tree().get_nodes_in_group("targets"):
		var target := node as Node2D
		if target == null or not target.is_alive():
			continue
		var to_target := target.global_position - global_position
		# A little extra reach for the target's own size.
		if to_target.length() > settings.melee_range + 8.0:
			continue
		if absf(rad_to_deg(_attack_direction.angle_to(to_target))) > half_arc:
			continue
		target.take_hit(self, _attack_direction, "melee")
		_play_kill_feedback(target)


## Everything that makes a kill feel heavy happens here, at the same moment:
## freeze, shake (via the signal), vibration.
func _play_kill_feedback(target: Node2D) -> void:
	killed_target.emit(target, _attack_direction)
	if settings.kill_vibration_ms > 0:
		Input.vibrate_handheld(settings.kill_vibration_ms)
	Game.hit_stop(settings.hit_stop_time)


# -------------------------------------------------------------------- bomb

## Throw a bomb. `direction` = where to throw, or ZERO for "where I'm aiming,
## or facing if I'm not aiming".
func request_bomb(direction: Vector2) -> void:
	if not _alive or bombs_left <= 0:
		return
	if direction == Vector2.ZERO:
		var aim := get_aim_input()
		direction = aim if aim != Vector2.ZERO else facing
	facing = direction.normalized()
	bombs_left -= 1
	bombs_changed.emit(bombs_left)
	var bomb: Bomb = BOMB_SCENE.instantiate()
	get_parent().add_child(bomb)   # into the room, so it doesn't move with us
	bomb.throw(global_position, facing, settings, self)


# ------------------------------------------------------------------- death

func is_alive() -> bool:
	return _alive


## One hit kills, for the player too (bomb now, enemies in M2).
func take_hit(attacker: Node2D, direction: Vector2, weapon: String) -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	TacticTracker.report_player_death({
		"weapon": weapon,
		"killer": attacker.name if attacker else "",
		"player_position": global_position,
	})
	var gore := get_tree().get_first_node_in_group("gore")
	if gore:
		gore.add_kill(global_position, direction, body_color, weapon)
	died.emit(weapon)
	Game.shake(settings.big_shake)
	if settings.big_vibration_ms > 0:
		Input.vibrate_handheld(settings.big_vibration_ms)
	Game.hit_stop(settings.death_freeze_time)
	queue_redraw()


# ---------------------------------------------------------------- drawing
# Placeholder neon shapes until the Art Director's sprites arrive (M5).

func _draw() -> void:
	if not _alive:
		return   # the body is painted on the floor by the gore layer

	# Aim line: always shows where a swing or bomb will go.
	# Right stick held: it follows the right stick.
	# Otherwise: it follows the way you face, which follows the left stick.
	if _attack_state == AttackState.READY:
		var aim := get_aim_input()
		var aiming := aim != Vector2.ZERO
		if not aiming:
			aim = facing
		var dir := assisted_direction(aim)
		var locked := dir != aim
		var alpha := 0.9 if locked else (0.35 if aiming else settings.move_aim_line_alpha)
		var reach := settings.aim_assist_range if aiming or locked else settings.melee_range + 6.0
		draw_line(dir * 10.0, dir * reach, Color(accent_color, alpha), 1.0)

	# Body and a "visor" showing which way he faces.
	draw_circle(Vector2.ZERO, 7.0, body_color)
	draw_line(Vector2.ZERO, facing * 10.0, accent_color, 3.0)

	# Wind-up: a thin outline of where the swing is about to land.
	var half_arc := deg_to_rad(settings.melee_arc_degrees * 0.5)
	var angle := _attack_direction.angle()
	if _attack_state == AttackState.WINDUP:
		draw_arc(Vector2.ZERO, settings.melee_range, angle - half_arc, angle + half_arc, 12, Color(1, 1, 1, 0.4), 1.0)
	# The swing itself: a bright, thick arc for a few frames.
	if _swing_flash > 0.0:
		draw_arc(Vector2.ZERO, settings.melee_range * 0.8, angle - half_arc, angle + half_arc, 12, Color(1, 1, 1, 0.95), 5.0)
