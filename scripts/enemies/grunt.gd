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
## Learning (M3): on each retry it reads the tactics the room has blocked
## (TacticTracker.get_active_counters()) and switches on a counter for each.
## Adapted grunts have glowing eyes and call out the counter they use:
##   DOOR_AMBUSH -> "HOLD":    won't walk into a doorway you're waiting at.
##   RUSH        -> "BACK":    backs away when you run at it (same speed as its chase).
##   LONG_RANGE  -> "COVER":   hides behind walls while you hold a gun far away.
##   BOMB        -> "SCATTER": runs from a landed bomb and keeps apart from others.
## Counters never change its speed, reaction time or reach.
##
## Doors: when you push open a door of its room, it turns to the door and
## goes ALERT, even before it can see you. Grunts with stays_in_room (most of
## them in early levels) never step out of their own room: they chase you to
## their doorway and wait there.

enum State { PATROL, ALERT, CHASE, ATTACK, SEARCH, KNOCKED_DOWN, DEAD }

## All the tuning numbers. Edit res://data/grunt_settings.tres to change them.
@export var settings: EnemySettings
## Patrol route, as positions in the room. Empty = a guard who stands still.
@export var patrol_points: Array[Vector2] = []
## Which way a guard faces at the start (degrees, 0 = right, 90 = down).
@export var start_facing_degrees: float = 0.0
@export var body_color: Color = Color(0.45, 0.85, 0.35)   # toxic green (placeholder only)

@export_group("Look")
## Sprite sheet: 64 x 64 cells, 12 per row, drawn facing up. Row 1 = walk
## cycle, row 2 = corpses (odd columns have a burst head). Empty = placeholder shapes.
@export var sheet: Texture2D
@export var sheet_rows: int = 3
## Sheet pixels to room pixels (the walking body is ~23 px wide in the sheet).
@export var sprite_scale: float = 0.6
## Room pixels walked per walk-cycle frame.
@export var stride_per_frame: float = 4.0
## The gun it drops when it dies (it still fights with fists for now).
## Empty = drops nothing.
@export var carried_weapon: WeaponData
## If on, it never leaves the room it starts in (LevelMap sets this).
@export var stays_in_room: bool = false
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
# Learning counters.
var _bark_text: String = ""
var _bark_time: float = 0.0
var _cover_point: Vector2
var _has_cover: bool = false
var _cover_timer: float = 0.0
var _flee_from: Vector2
var _flee_time: float = 0.0
var _home_room: int = -1

const SCATTER_TIME := 1.2   # a little longer than the bomb fuse
const SHEET_COLUMNS := 12
const PUNCH_FRAME := 3          # walk frame with one arm thrown forward
const KNOCKED_FRAME := SHEET_COLUMNS   # first corpse pose, no blood
const CLEAN_CORPSES := [0, 2, 4, 6, 8, 9, 10, 11]
const OUTLINE := preload("res://shaders/outline.gdshader")

var _sprite: Sprite2D
var _overlay: Node2D   # eyes, "!", barks and telegraphs, drawn above the sprite
var _walked: float = 0.0

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
	if not active_counters.is_empty():
		tell_color = TacticTracker.settings.adapted_eye_color
	Game.bomb_landed.connect(_on_bomb_landed)
	Game.door_opened.connect(_on_door_opened)
	var level := get_tree().get_first_node_in_group("level")
	if level:
		_home_room = level.room_at(global_position)
	_overlay = Node2D.new()
	_overlay.z_index = 1
	_overlay.draw.connect(_draw_overlay)
	if sheet:
		_sprite = Sprite2D.new()
		_sprite.texture = sheet
		_sprite.hframes = SHEET_COLUMNS
		_sprite.vframes = sheet_rows
		_sprite.scale = Vector2.ONE * sprite_scale
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = OUTLINE
		_sprite.material = material
		add_child(_sprite)
	add_child(_overlay)


## True if the room has blocked `tactic` and this grunt should counter it.
func counters(tactic: StringName) -> bool:
	return active_counters.has(tactic)


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
	_bark_time = maxf(_bark_time - delta, 0.0)

	if _flee_time > 0.0 and state != State.KNOCKED_DOWN:
		_scatter(delta)
		move_and_slide()
		_update_sprite(delta)
		queue_redraw()
		_overlay.queue_redraw()
		return

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
			elif not _counter_move(player, sees, delta):
				_move_to(last_known_position, settings.chase_speed)
		State.ATTACK:
			_attack(player)
		State.SEARCH:
			if not _hold_at_door(player):
				_search()
			if sees:
				_enter(State.CHASE)   # re-sighting: no reaction delay
		State.KNOCKED_DOWN:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _state_time >= settings.knockdown_time:
				_enter(State.CHASE if sees else State.SEARCH)
	move_and_slide()
	_update_sprite(delta)
	queue_redraw()
	_overlay.queue_redraw()


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


## You pushed open a door of its room: it turns to the door at once and goes
## ALERT (the "!"), then comes to look. Doors other enemies open are ignored.
func _on_door_opened(door: Node2D, opener: Node2D) -> void:
	if not opener.is_in_group("player") or not state in [State.PATROL, State.SEARCH]:
		return
	var level := get_tree().get_first_node_in_group("level")
	if level == null or _home_room < 0:
		return
	var door_center: Vector2 = door.center()
	var across: Vector2 = Vector2.from_angle(door.global_rotation).orthogonal() * 16.0
	var my_room: int = level.room_at(global_position)
	if my_room != level.room_at(door_center + across) and my_room != level.room_at(door_center - across):
		return
	last_known_position = door_center
	facing = global_position.direction_to(door_center)
	_enter(State.ALERT)


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
		if _move_to(last_known_position, settings.chase_speed * 0.7):
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
## Returns false if stays_in_room stopped it at the edge of its room.
func _move_to(target: Vector2, speed: float) -> bool:
	agent.target_position = target
	var next := agent.get_next_path_position()
	if agent.is_navigation_finished() or next.distance_to(global_position) < 0.5:
		next = target   # no path yet (first frames): head straight there
	var direction := global_position.direction_to(next)
	if counters(TacticTracker.BOMB) and state == State.CHASE:
		direction = _spread_out(direction)
	if _leaving_room(direction):
		velocity = Vector2.ZERO
		facing = global_position.direction_to(target)
		return false
	velocity = direction * speed
	if direction != Vector2.ZERO:
		facing = direction
	return true


## True if a stay-in-room grunt's next step would take it into a doorway.
## It looks 16 px ahead, so it stops far enough back that it can't hold the
## door open by standing in its push zone.
func _leaving_room(direction: Vector2) -> bool:
	if not stays_in_room or _home_room < 0:
		return false
	var level := get_tree().get_first_node_in_group("level")
	return level != null and level.leaves_room(_home_room, global_position + direction * 16.0)


## BOMB counter: keeps a gap from other grunts so one bomb can't get them all.
## The result is still length 1, so it never makes the grunt faster.
func _spread_out(direction: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not other.is_alive():
			continue
		var gap: Vector2 = global_position - other.global_position
		if gap.length() < 40.0 and gap.length() > 0.1:
			push += gap.normalized() * (1.0 - gap.length() / 40.0)
	if push == Vector2.ZERO:
		return direction
	_bark("SCATTER")
	return (direction + push).normalized()


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
		gore.add_kill(global_position + direction * 8.0, direction, body_color, weapon, _corpse())
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
		if global_position.distance_to(door.center()) <= door.length * 0.5 + 12.0:
			return true
	return false


# ---------------------------------------------------------------- counters

## Runs the counter for a blocked tactic, if one applies right now.
## Returns true if it decided how to move this frame.
func _counter_move(player: Node2D, sees: bool, delta: float) -> bool:
	if _hold_at_door(player):
		return true
	if counters(TacticTracker.RUSH) and sees and _back_off(player):
		return true
	if counters(TacticTracker.LONG_RANGE) and _take_cover(player, delta):
		return true
	return false


func _bark(text: String) -> void:
	_bark_text = text
	_bark_time = 0.8


## DOOR_AMBUSH: you are waiting at a doorway on the other side, so it stops
## short of the door and waits, facing it. Beat it: go in another way or go to it.
func _hold_at_door(player: Node2D) -> bool:
	if player == null or not counters(TacticTracker.DOOR_AMBUSH):
		return false
	var level := get_tree().get_first_node_in_group("level")
	for door in get_tree().get_nodes_in_group("doors"):
		var door_center: Vector2 = door.center()
		if player.global_position.distance_to(door_center) > 36.0:
			continue
		if global_position.distance_to(door_center) > 64.0:
			continue
		if level and level.room_at(global_position) == level.room_at(player.global_position):
			continue   # you're already on its side: no ambush to avoid
		velocity = Vector2.ZERO
		facing = global_position.direction_to(door_center)
		_bark("HOLD")
		return true
	return false


## RUSH: when you run straight at it, it backs away, still facing you.
## It only moves at its normal chase speed. Beat it: gun, bomb, or pin it to a wall.
func _back_off(player: Node2D) -> bool:
	var away := global_position - player.global_position
	if away.length() > 64.0:
		return false
	var closing: float = player.velocity.dot(away.normalized())
	if closing < 40.0:
		return false
	velocity = away.normalized() * settings.chase_speed
	facing = -away.normalized()
	_bark("BACK")
	return true


## LONG_RANGE: while you hold a gun and stand far away, it hides behind the
## nearest wall and waits. Beat it: get close, or drop the gun and use fists.
func _take_cover(player: Node2D, delta: float) -> bool:
	if player == null or not player.has_gun():
		return false
	if global_position.distance_to(player.global_position) <= 64.0:
		return false   # you're close now: charge
	_cover_timer -= delta
	if _cover_timer <= 0.0:
		_cover_timer = 0.5
		_has_cover = _find_cover(player.global_position)
	if not _has_cover:
		return false
	if global_position.distance_to(_cover_point) > 4.0:
		_move_to(_cover_point, settings.chase_speed)
	else:
		velocity = Vector2.ZERO
		facing = global_position.direction_to(player.global_position)
	_bark("COVER")
	return true


## Looks for a nearby spot it can walk to in a straight line that you can't see.
func _find_cover(from: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	for radius in [20.0, 36.0, 52.0, 68.0, 84.0, 100.0]:
		var best_distance := INF
		for i in 16:
			var spot: Vector2 = global_position + Vector2.from_angle(TAU * i / 16.0) * radius
			var point := PhysicsPointQueryParameters2D.new()
			point.position = spot
			point.collision_mask = 1 | 16
			if not space.intersect_point(point).is_empty():
				continue   # inside a wall
			if not space.intersect_ray(PhysicsRayQueryParameters2D.create(global_position, spot, 1 | 16)).is_empty():
				continue   # can't walk there in a straight line
			if space.intersect_ray(PhysicsRayQueryParameters2D.create(from, spot, 1 | 16)).is_empty():
				continue   # you could see it there
			var distance := spot.distance_to(from)
			if distance < best_distance:   # the hidden spot closest to you
				best_distance = distance
				_cover_point = spot
		if best_distance < INF:
			return true
	return false


## BOMB: a bomb landed close by, so it runs straight away from it.
func _on_bomb_landed(at: Vector2, blast_radius: float) -> void:
	if state == State.DEAD or not counters(TacticTracker.BOMB):
		return
	if global_position.distance_to(at) > blast_radius + 24.0:
		return
	_flee_from = at
	_flee_time = SCATTER_TIME


func _scatter(delta: float) -> void:
	_flee_time -= delta
	var away := global_position - _flee_from
	velocity = (away.normalized() if away != Vector2.ZERO else facing) * settings.chase_speed
	facing = -velocity.normalized()   # keeps an eye on the bomb
	_bark("SCATTER")
	if _flee_time <= 0.0:
		_enter(State.CHASE if _get_player() else State.SEARCH)


# ------------------------------------------------------------------ sprite

## Picks the sheet frame: walk cycle while moving, punch pose in the wind-up,
## lying pose when knocked down. The sheet faces up, so turn by +90 degrees.
func _update_sprite(delta: float) -> void:
	if _sprite == null:
		return
	if state == State.KNOCKED_DOWN:
		_sprite.frame = KNOCKED_FRAME
		return
	_sprite.rotation = facing.angle() + PI * 0.5
	if state == State.ATTACK and not _struck:
		_sprite.frame = PUNCH_FRAME
	elif velocity.length() > 5.0:
		_walked += velocity.length() * delta
		_sprite.frame = int(_walked / stride_per_frame) % SHEET_COLUMNS
	else:
		_sprite.frame = 0


## The corpse the gore layer paints when it dies (empty = placeholder shapes).
func _corpse() -> Dictionary:
	if sheet == null:
		return {}
	var clean: int = CLEAN_CORPSES.pick_random()
	var burst: int = [1, 3, 5, 7].pick_random()
	return {
		"texture": sheet,
		"region": Rect2(clean * 64, 64, 64, 64),
		"burst_region": Rect2(burst * 64, 64, 64, 64),
		"scale": sprite_scale,
	}


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
	if _sprite:
		return   # the sprite shows the body
	if state == State.KNOCKED_DOWN:
		# Lying on the floor.
		draw_set_transform(Vector2.ZERO, angle)
		draw_circle(Vector2.ZERO, 6.0, body_color.darkened(0.3))
		draw_circle(Vector2(8, 0), 3.5, body_color.darkened(0.3))
		draw_set_transform(Vector2.ZERO, 0.0)
		return
	draw_circle(Vector2.ZERO, 7.0, body_color)
	draw_line(Vector2.ZERO, facing * 9.0, Color(0.1, 0.1, 0.1), 3.0)


## Everything drawn on top of the body: gun, eyes, warnings and barks.
func _draw_overlay() -> void:
	var o := _overlay
	if state == State.KNOCKED_DOWN:
		return
	if carried_weapon:
		# The gun it will drop, held at its side.
		var hand := facing.orthogonal() * 5.0 + facing * 6.0
		o.draw_line(hand, hand + facing * 6.0, carried_weapon.color, 2.5)
	if tell_color.a > 0.0:
		# Glowing eyes: this grunt has learned your moves.
		var eyes := facing * 3.0
		o.draw_circle(eyes, 3.5, Color(tell_color, 0.25))
		o.draw_circle(eyes + facing.orthogonal() * 2.0, 1.4, tell_color)
		o.draw_circle(eyes - facing.orthogonal() * 2.0, 1.4, tell_color)
	if _bark_time > 0.0:
		# The counter it is using right now.
		var bark_color := tell_color if tell_color.a > 0.0 else Color(1, 0.9, 0.2)
		o.draw_string(ThemeDB.fallback_font, Vector2(-16, -24), _bark_text, HORIZONTAL_ALIGNMENT_CENTER, 32, 8, Color(bark_color, minf(_bark_time * 3.0, 1.0)))
	if state == State.ALERT:
		# The "!" warning.
		o.draw_line(Vector2(0, -20), Vector2(0, -13), Color(1, 0.9, 0.2), 2.5)
		o.draw_circle(Vector2(0, -10), 1.3, Color(1, 0.9, 0.2))
	elif state == State.ATTACK and not _struck:
		# Wind-up telegraph: a red arc where the swing will land.
		var half_arc := deg_to_rad(settings.attack_arc_degrees * 0.5)
		var a := _attack_direction.angle()
		o.draw_arc(Vector2.ZERO, settings.attack_range, a - half_arc, a + half_arc, 12, Color(1, 0.15, 0.1, 0.9), 2.0)
	elif state == State.SEARCH:
		o.draw_string(ThemeDB.fallback_font, Vector2(-3, -10), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.9, 0.2))
