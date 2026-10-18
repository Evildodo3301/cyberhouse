class_name Player
extends CharacterBody2D
## The hitman: moves, aims, punches, shoots and throws bombs.
##
## Every level starts with bare fists. Guns lie on the floor or drop from
## dead enemies: walk over one to pick it up. When a gun runs dry it falls
## to the floor and you are back to fists. Weapon numbers live in
## res://data/weapons/.
##
## Controls (both work at the same time):
##   Touch:    left thumb = move, right thumb = aim, lift right thumb = attack/shoot,
##             quick tap on the right = attack the nearest target in front,
##             BOMB button = throw a bomb.
##   Keyboard: WASD = move, arrow keys = aim, Space = attack, E = bomb (for PC testing).
##
## The body is two parts that turn on their own:
##   Torso = faces where you AIM (right stick), or where you walk when not aiming.
##   Legs  = face where you WALK, so you can run one way and swing another.

## Emitted the moment a swing kills something. The camera uses it to shake
## (and in M5 the hit sound will listen to it too, so they stay in sync).
signal killed_target(target: Node2D, direction: Vector2)
## Emitted when the bomb count changes, so the button can show it.
signal bombs_changed(bombs_left: int)
## Emitted when you pick up, use up or drop a weapon (and on every shot).
signal weapon_changed(weapon: WeaponData, ammo: int)
## Emitted once when the player dies. `weapon` is what killed them.
signal died(weapon: String)

const BOMB_SCENE := preload("res://scenes/weapons/bomb.tscn")
const PICKUP_SCENE := preload("res://scenes/weapons/weapon_pickup.tscn")
const BULLET_SCENE := preload("res://scenes/weapons/bullet.tscn")
const CROSSHAIR_TEXTURE := preload("res://assets/ui/crosshair.png")

## All the tuning numbers. Edit res://data/player_settings.tres to change them.
@export var settings: PlayerSettings
@export var body_color: Color = Color(1.0, 0.16, 0.54)   # neon pink
@export var accent_color: Color = Color(0.16, 0.94, 1.0) # neon cyan

## Set by main.gd. Can stay empty (keyboard only).
var touch_controls: TouchControls

## The direction the hitman is looking (always length 1). The torso shows it.
var facing: Vector2 = Vector2.RIGHT
## The direction the legs point, in radians. Follows movement only.
var legs_angle: float = 0.0
## Bombs left in this room.
var bombs_left: int = 0
## What you are holding, and shots left in it (-1 = not a gun).
var weapon: WeaponData
var ammo: int = -1
## True while the crosshair sits on someone your attack would hit.
var crosshair_on_target: bool = false
var _alive: bool = true
# Remembered for the death report.
var _last_attack: String = ""
var _last_attack_ms: int = -1
var _speed_before_death: float = 0.0

# The attack goes through three steps: READY -> WINDUP -> RECOVERY -> READY.
enum AttackState { READY, WINDUP, RECOVERY }
var _attack_state: AttackState = AttackState.READY
var _attack_timer: float = 0.0
var _attack_direction: Vector2 = Vector2.RIGHT
var _swing_flash: float = 0.0   # how long the swing arc stays visible
var _stride: float = 0.0   # distance walked, drives the step animation
var _muzzle_flash: float = 0.0   # seconds the flash at the barrel stays visible
var _crosshair: Sprite2D

@onready var _legs: Node2D = $Legs
@onready var _torso: Node2D = $Torso


func _ready() -> void:
	if settings == null:
		settings = PlayerSettings.new()   # fall back to default values
	if settings.start_weapon == null:
		settings.start_weapon = load("res://data/weapons/fists.tres")
	add_to_group("player")   # bombs look for this group
	bombs_left = settings.bombs_per_room
	# The parts are plain nodes so art can later drop a sprite into each one.
	_legs.draw.connect(_draw_legs)
	_torso.draw.connect(_draw_torso)
	_crosshair = Sprite2D.new()
	_crosshair.texture = CROSSHAIR_TEXTURE
	_crosshair.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_crosshair.top_level = true   # placed in room coordinates, not moved with us
	_crosshair.z_index = 10
	_crosshair.scale = Vector2.ONE * settings.crosshair_size / CROSSHAIR_TEXTURE.get_width()
	add_child(_crosshair)
	equip(settings.start_weapon, -1)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_update_movement(delta)
	_update_facing()
	_update_body(delta)
	if Input.is_action_just_pressed("attack"):
		request_attack(_keyboard_aim())   # ZERO = "nearest target", like a tap
	if Input.is_action_just_pressed("throw_bomb"):
		request_bomb(Vector2.ZERO)
	_update_attack(delta)
	_update_crosshair()
	_update_tracers(delta)
	queue_redraw()
	_legs.queue_redraw()
	_torso.queue_redraw()



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


## Turns the two body parts. The torso snaps to the aim; the legs turn
## smoothly toward the way we move, and ignore the aim completely.
func _update_body(delta: float) -> void:
	_torso.rotation = facing.angle()   # angle() = atan2(y, x)
	var speed := velocity.length()
	if speed > settings.legs_idle_speed:
		# How far to turn this frame. Using exp() makes the turn feel the same
		# at 30 or 120 frames per second.
		var weight := 1.0 - exp(-settings.legs_turn_speed * delta)
		# lerp_angle takes the short way round (never spins 350 degrees).
		legs_angle = lerp_angle(legs_angle, velocity.angle(), weight)
		_stride += speed * delta
	else:
		_stride = 0.0   # idle: feet back together under the torso
	_legs.rotation = legs_angle


## Aim assist: if a target sits close to the aim line, return the direction
## to it. Otherwise return the aim unchanged.
func assisted_direction(aim: Vector2) -> Vector2:
	var assist_range := weapon.reach if has_gun() else settings.aim_assist_range
	var target := _find_target(aim, assist_range, settings.aim_assist_degrees)
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
		var tap_range := weapon.reach if has_gun() else settings.tap_assist_radius
		var target := _find_target(facing, tap_range, settings.tap_assist_degrees)
		direction = global_position.direction_to(target.global_position) if target else facing
	else:
		direction = assisted_direction(direction.normalized())
	_attack_direction = direction
	facing = direction
	_attack_state = AttackState.WINDUP
	_attack_timer = weapon.windup_time
	_last_attack = "gun" if has_gun() else "melee"
	_last_attack_ms = Time.get_ticks_msec()


func _update_attack(delta: float) -> void:
	_swing_flash = maxf(_swing_flash - delta, 0.0)
	if _attack_state == AttackState.READY:
		return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	if _attack_state == AttackState.WINDUP:
		if has_gun():
			_fire()
		else:
			_strike()
		_attack_state = AttackState.RECOVERY
		_attack_timer = weapon.recovery_time
	else:
		_attack_state = AttackState.READY


## The moment the swing lands: hit every target inside the arc.
func _strike() -> void:
	_swing_flash = 0.08
	for target in _targets_in_swing(_attack_direction):
		target.take_hit(self, _attack_direction, "melee")
		_play_kill_feedback(target)


## Everyone a melee swing in `direction` would hit right now.
func _targets_in_swing(direction: Vector2) -> Array[Node2D]:
	var hits: Array[Node2D] = []
	var half_arc := weapon.arc_degrees * 0.5
	for node in get_tree().get_nodes_in_group("targets"):
		var target := node as Node2D
		if target == null or not target.is_alive():
			continue
		var to_target := target.global_position - global_position
		# A little extra reach for the target's own size.
		if to_target.length() > weapon.reach + 8.0:
			continue
		if absf(rad_to_deg(direction.angle_to(to_target))) > half_arc:
			continue
		hits.append(target)
	return hits


# --------------------------------------------------------------------- guns

func has_gun() -> bool:
	return weapon != null and weapon.kind == WeaponData.Kind.GUN


## Fires the gun: each bullet flies across the room (Bullet) and kills the
## first target it meets, unless a wall or a closed door stops it first.
func _fire() -> void:
	ammo -= 1
	_muzzle_flash = 0.05
	for i in maxi(weapon.pellets, 1):
		var spread := deg_to_rad(randf_range(-weapon.spread_degrees, weapon.spread_degrees))
		var bullet: Bullet = BULLET_SCENE.instantiate()
		get_parent().add_child(bullet)
		bullet.fire(global_position, _attack_direction.rotated(spread), weapon, self)
	if weapon.noise_loudness > 0.0:
		Game.make_noise(global_position, weapon.noise_loudness)   # enemies hear it
	if weapon.shake > 0.0:
		Game.shake(weapon.shake, _attack_direction)
	weapon_changed.emit(weapon, ammo)
	if ammo <= 0:
		_drop_weapon(_attack_direction.rotated(PI * 0.75))   # empty: toss it aside


## Where a bullet fired in `direction` would stop, and who it would hit.
## Returns {"end": Vector2, "target": Node2D or null}.
func trace_shot(direction: Vector2) -> Dictionary:
	var reach := weapon.reach if has_gun() else 0.0
	var end := global_position + direction * reach
	var query := PhysicsRayQueryParameters2D.create(global_position, end, 1 | 16)
	var wall := get_world_2d().direct_space_state.intersect_ray(query)
	if not wall.is_empty():
		end = wall.position
	# The closest living target whose body (about 7 px) the bullet passes through.
	var best: Node2D = null
	var best_along := INF
	var length := global_position.distance_to(end)
	for node in get_tree().get_nodes_in_group("targets"):
		var target := node as Node2D
		if target == null or not target.is_alive():
			continue
		var offset := target.global_position - global_position
		var along := offset.dot(direction)   # how far down the bullet's path
		if along < 0.0 or along > length + 4.0 or along >= best_along:
			continue
		if absf(offset.cross(direction)) > 7.0:   # how far to the side of it
			continue
		best = target
		best_along = along
	if best:
		end = global_position + direction * best_along
	return {"end": end, "target": best}


## Hold a new weapon. `new_ammo` = -1 for a full one.
func equip(new_weapon: WeaponData, new_ammo: int) -> void:
	weapon = new_weapon
	ammo = new_weapon.ammo if new_ammo < 0 else new_ammo
	if not has_gun():
		ammo = -1
	weapon_changed.emit(weapon, ammo)


## Called by a WeaponPickup we walk over. Only empty hands pick things up.
func try_pick_up(pickup: WeaponPickup) -> bool:
	if not _alive or weapon != settings.start_weapon or not pickup.is_usable():
		return false
	equip(pickup.weapon, pickup.ammo)
	return true


func _drop_weapon(direction: Vector2) -> void:
	var dropped: WeaponPickup = PICKUP_SCENE.instantiate()
	dropped.weapon = weapon
	dropped.ammo = maxi(ammo, 0)
	get_parent().add_child.call_deferred(dropped)
	dropped.fling.call_deferred(global_position, direction, 90.0)
	equip(settings.start_weapon, -1)


func _update_tracers(delta: float) -> void:
	_muzzle_flash = maxf(_muzzle_flash - delta, 0.0)


# --------------------------------------------------------------- crosshair

## The crosshair sits at the end of your reach in the direction you aim
## (or face, when not aiming), and turns red when your attack would hit.
func _update_crosshair() -> void:
	var aim := get_aim_input()
	if aim == Vector2.ZERO:
		aim = facing
	var direction := assisted_direction(aim)
	var point: Vector2
	if has_gun():
		var shot := trace_shot(direction)
		point = shot.end
		crosshair_on_target = shot.target != null
	else:
		point = global_position + direction * weapon.reach
		crosshair_on_target = not _targets_in_swing(direction).is_empty()
	# Keep it on screen even when the gun reaches further than you can see.
	var view := get_canvas_transform().affine_inverse() * get_viewport_rect()
	point = point.clamp(view.position + Vector2.ONE * 6.0, view.end - Vector2.ONE * 6.0)
	_crosshair.global_position = point
	_crosshair.modulate = settings.crosshair_hit_color if crosshair_on_target else settings.crosshair_color


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
	_last_attack = "bomb"
	_last_attack_ms = Time.get_ticks_msec()
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
	_speed_before_death = velocity.length()
	velocity = Vector2.ZERO
	_report_death(attacker, weapon)
	var gore := get_tree().get_first_node_in_group("gore")
	if gore:
		gore.add_kill(global_position, direction, body_color, weapon)
	died.emit(weapon)
	Game.shake(settings.big_shake)
	if settings.big_vibration_ms > 0:
		Input.vibrate_handheld(settings.big_vibration_ms)
	Game.hit_stop(settings.death_freeze_time)
	queue_redraw()
	_legs.queue_redraw()
	_torso.queue_redraw()
	_crosshair.visible = false


## The "death move" data the learning system (M3) tags deaths with.
func _report_death(attacker: Node2D, weapon: String) -> void:
	var killer_type := "enemy_melee"
	if weapon == "bomb":
		killer_type = "own_bomb"
	elif weapon.ends_with("gun"):
		killer_type = "enemy_gun"
	var door_id := ""
	for door in get_tree().get_nodes_in_group("doors"):
		if global_position.distance_to(door.center()) <= door.length * 0.5 + 8.0:
			door_id = door.door_id
	var noise_pulling := get_tree().get_nodes_in_group("enemies").any(
		func(e): return e.is_alive() and e.chasing_noise)
	var since_attack := -1.0
	if _last_attack_ms >= 0:
		since_attack = (Time.get_ticks_msec() - _last_attack_ms) / 1000.0
	TacticTracker.report_player_death({
		"killer_type": killer_type,
		"weapon": weapon,
		"killer": attacker.name if attacker else "",
		"player_position": global_position,
		"in_doorway": door_id != "",
		"door_id": door_id,
		"behind_corner": false,   # TODO M3: needs a corner check against the walls
		"player_speed": _speed_before_death,
		"last_attack": _last_attack,
		"last_attack_seconds_ago": since_attack,
		"noise_pulling_enemies": noise_pulling,
	})


# ---------------------------------------------------------------- drawing
# Placeholder neon shapes until the Art Director's sprites arrive (M5).

func _draw() -> void:
	if not _alive:
		return   # the body is painted on the floor by the gore layer

	# Muzzle flash at the end of the barrel.
	if _muzzle_flash > 0.0:
		draw_circle(_attack_direction * 15.0, 3.0, Color(1, 0.95, 0.6))
	if has_gun():
		return   # the swing arcs below are for melee only

	# Wind-up: a thin outline of where the swing is about to land.
	var half_arc := deg_to_rad(weapon.arc_degrees * 0.5)
	var angle := _attack_direction.angle()
	if _attack_state == AttackState.WINDUP:
		draw_arc(Vector2.ZERO, weapon.reach, angle - half_arc, angle + half_arc, 12, Color(1, 1, 1, 0.4), 1.0)
	# The swing itself: a bright, thick arc for a few frames.
	if _swing_flash > 0.0:
		draw_arc(Vector2.ZERO, weapon.reach * 0.8, angle - half_arc, angle + half_arc, 12, Color(1, 1, 1, 0.95), 5.0)


# Both parts are drawn pointing right (+x). Their node rotation turns them.

func _draw_legs() -> void:
	if not _alive:
		return
	# Feet swing forward and back in turn, one full cycle per stride_length.
	var step := sin(_stride / maxf(settings.stride_length, 1.0) * TAU) * 6.0
	var foot_color := body_color.darkened(0.6)
	_legs.draw_rect(Rect2(Vector2(step - 3.0, -5.0), Vector2(6, 3.5)), foot_color)
	_legs.draw_rect(Rect2(Vector2(-step - 3.0, 1.5), Vector2(6, 3.5)), foot_color)


func _draw_torso() -> void:
	if not _alive:
		return
	# Shoulders: an oval, wide across, narrow front to back.
	_torso.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.6, 1.0))
	_torso.draw_circle(Vector2.ZERO, 7.0, body_color)
	_torso.draw_set_transform(Vector2.ZERO)
	_torso.draw_circle(Vector2(0.5, 0), 3.5, body_color.lightened(0.25))   # head
	_torso.draw_line(Vector2(2, 0), Vector2(10, 0), accent_color, 3.0)   # visor / arm
	if has_gun():
		_torso.draw_rect(Rect2(8, -1.5, 7, 3), weapon.color)   # the gun in hand
