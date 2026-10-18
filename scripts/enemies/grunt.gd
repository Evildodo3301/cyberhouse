class_name Grunt
extends CharacterBody2D
## The basic M2 enemy. It is always in exactly one state (a "state machine"):
##
##   PATROL --sees you--> ALERT --reaction time--> CHASE --close--> ATTACK
##     ^                                            |  ^              |
##     |                                    loses you  +---------------+
##     +---- gives up ---- SEARCH <-----------------+
##
## Plus KNOCKED_DOWN (a door hit it) and DEAD. A bomb going off sends it to
## SEARCH toward the noise. One hit kills it; its hit kills you.
##
## M3 hooks already here: settings in a Resource, last known position,
## hearing, door awareness, a death report and a "tell" colour for the eyes.

enum State { PATROL, ALERT, CHASE, ATTACK, SEARCH, KNOCKED_DOWN, DEAD }

## All the tuning numbers. Edit res://data/grunt_settings.tres to change them.
@export var settings: EnemySettings
## Patrol route, as positions in the room. Empty = a guard who stands still.
@export var patrol_points: Array[Vector2] = []
## Which way a guard faces at the start (degrees, 0 = right, 90 = down).
@export var start_facing_degrees: float = 0.0
@export var body_color: Color = Color(0.45, 0.85, 0.35)   # toxic green
## The gun it drops when it dies (it still fights with fists for now).
## Empty = drops nothing.
@export var carried_weapon: WeaponData
## Eye glow used by M3 to show an enemy has adapted. Transparent = none.
@export var tell_color: Color = Color(0, 0, 0, 0)

var state: State = State.PATROL
var facing: Vector2 = Vector2.RIGHT
## Where it last saw (or heard) the player. M3 counters read this.
var last_known_position: Vector2
var chasing_noise: bool = false
## Tactics this enemy should counter (read from TacticTracker; empty in M2).
var active_counters: Array = []

var _state_time: float = 0.0
var _unseen_time: float = 0.0
var _home: Vector2
var _home_facing: Vector2
var _patrol_index: int = 0
var _attack_direction: Vector2 = Vector2.RIGHT
var _struck: bool = false
var _arrived: bool = false
var _look_time: float = 0.0

@onready var agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	if settings == null:
		settings = EnemySettings.new()
	add_to_group("targets")   # the player's swings and bombs can hit it
	add_to_group("enemies")
	_home = global_position
	facing = Vector2.from_angle(deg_to_rad(start_facing_degrees))
	_home_facing = facing
	last_known_position = global_position
	Game.noise_made.connect(_on_noise_made)
	active_counters = TacticTracker.get_active_counters()


func is_alive() -> bool:
	return state != State.DEAD


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_state_time += delta
	var player := _get_player()
	var sees := player != null and (_in_my_room(player) or _can_see(player))
	if sees:
		last_known_position = player.global_position
		_unseen_time = 0.0
		chasing_noise = false
	else:
		_unseen_time += delta

	match state:
		State.PATROL:
			_patrol()
			if sees:
				_enter(State.ALERT)
		State.ALERT:
			# Stops and turns to you: this pause is your chance to strike first.
			velocity = Vector2.ZERO
			facing = global_position.direction_to(last_known_position)
			if _state_time >= settings.reaction_time:
				_enter(State.CHASE)
		State.CHASE:
			if player == null:
				_enter(State.SEARCH)
			elif sees and global_position.distance_to(player.global_position) <= settings.attack_range:
				_enter(State.ATTACK)
			elif _unseen_time >= settings.lose_sight_time:
				_enter(State.SEARCH)
			else:
				_move_to(last_known_position, settings.chase_speed)
		State.ATTACK:
			_attack(player)
		State.SEARCH:
			_search()
			if sees:
				_enter(State.CHASE)   # re-sighting: no reaction delay
		State.KNOCKED_DOWN:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _state_time >= settings.knockdown_time:
				_enter(State.CHASE if sees else State.SEARCH)
	move_and_slide()
	queue_redraw()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_arrived = false
	_look_time = 0.0
	if new_state == State.ATTACK:
		_struck = false
		_attack_direction = global_position.direction_to(last_known_position)
		facing = _attack_direction


func _get_player() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.is_alive():
		return player
	return null


# ------------------------------------------------------------------ senses

## True if the player stands in the same room as us (see notice_whole_room).
func _in_my_room(player: Node2D) -> bool:
	if not settings.notice_whole_room:
		return false
	var level := get_tree().get_first_node_in_group("level")
	if level == null:
		return false
	var room: int = level.room_at(global_position)
	return room >= 0 and room == level.room_at(player.global_position)


## True if the player is in the vision cone (or right behind it) and no wall
## or door is in between.
func _can_see(player: Node2D) -> bool:
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	if distance > settings.vision_range:
		return false
	var in_cone := absf(rad_to_deg(facing.angle_to(to_player))) <= settings.vision_degrees * 0.5
	if not in_cone and distance > settings.close_awareness_range:
		return false
	# Line of sight: a ray that only stops at walls (1) and doors (16).
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 1 | 16)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _on_noise_made(at: Vector2, loudness: float) -> void:
	if state in [State.DEAD, State.ATTACK, State.KNOCKED_DOWN]:
		return
	if global_position.distance_to(at) > settings.hearing_range * loudness:
		return
	if state in [State.PATROL, State.SEARCH]:
		last_known_position = at
		chasing_noise = true
		_enter(State.SEARCH)


# --------------------------------------------------------------- behaviour

func _patrol() -> void:
	if patrol_points.is_empty():
		# Guard: walk back to the post if pushed off it, then face the post direction.
		if global_position.distance_to(_home) > 4.0:
			_move_to(_home, settings.patrol_speed)
		else:
			velocity = Vector2.ZERO
			facing = _home_facing
		return
	var point := patrol_points[_patrol_index]
	if global_position.distance_to(point) > 4.0:
		_move_to(point, settings.patrol_speed)
		_state_time = 0.0
	else:
		velocity = Vector2.ZERO
		if _state_time >= settings.patrol_pause:
			_patrol_index = (_patrol_index + 1) % patrol_points.size()
			_state_time = 0.0


func _search() -> void:
	if not _arrived and global_position.distance_to(last_known_position) > 6.0 and _state_time < 6.0:
		_move_to(last_known_position, settings.chase_speed * 0.7)
		return
	# At the spot (or it took too long): look around, then go back to the route.
	_arrived = true
	velocity = Vector2.ZERO
	var delta := get_physics_process_delta_time()
	facing = facing.rotated(2.5 * delta)
	_look_time += delta
	if _look_time >= settings.search_look_time:
		chasing_noise = false
		_enter(State.PATROL)


func _attack(player: Node2D) -> void:
	velocity = Vector2.ZERO
	if not _struck and _state_time >= settings.attack_windup:
		_struck = true
		if player and _in_swing(player):
			player.take_hit(self, _attack_direction, "grunt_melee")
	if _state_time >= settings.attack_windup + settings.attack_recovery:
		_enter(State.CHASE)


func _in_swing(player: Node2D) -> bool:
	var to_player := player.global_position - global_position
	if to_player.length() > settings.attack_range + 6.0:
		return false
	return absf(rad_to_deg(_attack_direction.angle_to(to_player))) <= settings.attack_arc_degrees * 0.5


## Walks toward `target` along the navigation path (around walls, through doors).
func _move_to(target: Vector2, speed: float) -> void:
	agent.target_position = target
	var next := agent.get_next_path_position()
	if agent.is_navigation_finished() or next.distance_to(global_position) < 0.5:
		next = target   # no path yet (first frames): head straight there
	var direction := global_position.direction_to(next)
	velocity = direction * speed
	if direction != Vector2.ZERO:
		facing = direction


# ------------------------------------------------------------- getting hit

## One hit kills. Called by the player's swing or a bomb.
func take_hit(attacker: Node2D, direction: Vector2, weapon: String) -> void:
	if state == State.DEAD:
		return
	var state_name: String = State.keys()[state]
	state = State.DEAD
	velocity = Vector2.ZERO
	collision_layer = 0
	_report_death(attacker, weapon, state_name)
	var gore := get_tree().get_first_node_in_group("gore")
	if gore:
		gore.add_kill(global_position + direction * 8.0, direction, body_color, weapon)
	visible = false
	_drop_weapon(direction)
	Game.enemy_died.emit(self)


## Its gun flies out of its hand in the direction of the killing blow.
func _drop_weapon(direction: Vector2) -> void:
	if carried_weapon == null:
		return
	var pickup: WeaponPickup = preload("res://scenes/weapons/weapon_pickup.tscn").instantiate()
	pickup.weapon = carried_weapon
	get_parent().add_child.call_deferred(pickup)
	var fling_direction := direction.rotated(randf_range(-0.6, 0.6))
	pickup.fling.call_deferred(global_position, fling_direction)


## A door slammed into it: it falls and can't act for a moment.
func knock_down(_by: Node, direction: Vector2) -> void:
	if state == State.DEAD:
		return
	velocity = direction * 160.0
	_enter(State.KNOCKED_DOWN)
	TacticTracker.report_event({"type": "door_knockdown", "victim": name})


func _report_death(attacker: Node2D, weapon: String, state_name: String) -> void:
	var player_speed := 0.0
	if attacker is CharacterBody2D:
		player_speed = attacker.velocity.length()
	TacticTracker.report_kill({
		"victim": name,
		"weapon": weapon,
		"distance": global_position.distance_to(attacker.global_position),
		"player_speed": player_speed,
		"at_door": _near_door(),
		"chasing_noise": chasing_noise,
		"enemy_state": state_name,
	})


func _near_door() -> bool:
	for door in get_tree().get_nodes_in_group("doors"):
		if global_position.distance_to(door.global_position) <= door.length + 8.0:
			return true
	return false


# ---------------------------------------------------------------- drawing
# Placeholder shapes until the Art Director's sprites arrive (M5).

func _draw() -> void:
	var angle := facing.angle()
	if settings.show_vision_cone and state != State.KNOCKED_DOWN:
		var half := deg_to_rad(settings.vision_degrees * 0.5)
		var cone := PackedVector2Array([Vector2.ZERO])
		for i in 9:
			cone.append(Vector2.from_angle(angle - half + 2.0 * half * i / 8.0) * settings.vision_range)
		var alert := state in [State.ALERT, State.CHASE, State.ATTACK]
		draw_colored_polygon(cone, Color(1, 0.2, 0.2, 0.07) if alert else Color(1, 1, 1, 0.04))

	if state == State.KNOCKED_DOWN:
		# Lying on the floor.
		draw_set_transform(Vector2.ZERO, angle)
		draw_circle(Vector2.ZERO, 6.0, body_color.darkened(0.3))
		draw_circle(Vector2(8, 0), 3.5, body_color.darkened(0.3))
		draw_set_transform(Vector2.ZERO, 0.0)
		return

	draw_circle(Vector2.ZERO, 7.0, body_color)
	draw_line(Vector2.ZERO, facing * 9.0, Color(0.1, 0.1, 0.1), 3.0)
	if carried_weapon:
		# The gun it will drop, held at its side.
		var hand := facing.orthogonal() * 5.0 + facing * 6.0
		draw_line(hand, hand + facing * 6.0, carried_weapon.color, 2.5)
	if tell_color.a > 0.0:
		draw_circle(facing * 4.0, 2.0, tell_color)   # M3 adaptation tell

	if state == State.ALERT:
		# The "!" warning.
		draw_line(Vector2(0, -20), Vector2(0, -13), Color(1, 0.9, 0.2), 2.5)
		draw_circle(Vector2(0, -10), 1.3, Color(1, 0.9, 0.2))
	elif state == State.ATTACK and not _struck:
		# Wind-up telegraph: a red arc where the swing will land.
		var half_arc := deg_to_rad(settings.attack_arc_degrees * 0.5)
		var a := _attack_direction.angle()
		draw_arc(Vector2.ZERO, settings.attack_range, a - half_arc, a + half_arc, 12, Color(1, 0.15, 0.1, 0.9), 2.0)
	elif state == State.SEARCH:
		draw_string(ThemeDB.fallback_font, Vector2(-3, -10), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.9, 0.2))
