class_name Grunt
extends CharacterBody2D
## The basic M2 enemy. It is always in exactly one state (a "state machine"):
##
##   PATROL --sees you--> ALERT --reaction time--> CHASE --close--> ATTACK
##     ^                                            |  ^              |
##     |                                    loses you  +---------------+
##     +---- gives up ---- SEARCH <-----------------+
##
## Gun enemies (carrying a pistol) also have AIM: when they can see you and
## you're in range, they stop, turn to you and fire after settings.shot_delay
## (0.2 s), with no warning. Their bullets fly like yours and walls, doors and
## furniture stop them. Fists and machete enemies only fight up close.
## Plus KNOCKED_DOWN (a door hit it) and DEAD. A bomb going off sends it to
## SEARCH toward the noise. One hit kills it; its hit kills you.
##
## Learning (M3): on each retry it reads the tactics the room has blocked
## (TacticTracker.get_active_counters()) and switches on a counter for each.
## Adapted grunts have glowing eyes and call out the counter they use:
##   DOOR_AMBUSH -> "HOLD":    won't walk into a doorway you're waiting at.
##   RUSH        -> "FEINT":   when you run at it, one quick step back, then it
##                             strikes: lunges at you or side-steps and punches.
##   LONG_RANGE  -> "COVER":   hides behind a wall for a moment while you hold a
##                             gun far away, then charges.
##   BOMB        -> "SCATTER": runs from a landed bomb and keeps apart from others.
## Counters never change its reaction time or reach, and never make it retreat
## for long: every back-off ends in an attack. Only short bursts are faster
## than its chase: the feint's lunge and the charge when it closes in.
##
## Doors: when you push open a door of its room, it turns to the door and
## goes ALERT, even before it can see you (unless door_alert_needs_sight is
## on and the door is behind its back).
##
## Sneaking: with notice_whole_room off it only sees what is in its vision
## cone (or right behind it, close_awareness_range). Walk up behind a
## patrolling enemy and it never knows you were there.
##
## Dogs (is_dog): dobermans. Fast, bite up close, no weapon, no learned
## counters; they growl "GRR" the moment they spot you. Grunts with stays_in_room (most of
## them in early levels) never step out of their own room: they chase you to
## their doorway and wait there.

const BULLET_SCENE := preload("res://scenes/weapons/bullet.tscn")
## Screen pixels inside the edge a gun enemy must be before it may fire.
const SCREEN_MARGIN := 12.0
## Shots in one machine gun burst.
const BURST_SHOTS := 5

enum State { PATROL, ALERT, CHASE, ATTACK, SEARCH, KNOCKED_DOWN, DEAD, AIM }

## All the tuning numbers. Edit res://data/grunt_settings.tres to change them.
@export var settings: EnemySettings
## Patrol route, as positions in the room. Empty = a guard who stands still.
@export var patrol_points: Array[Vector2] = []
## Which way a guard faces at the start (degrees, 0 = right, 90 = down).
@export var start_facing_degrees: float = 0.0
@export var body_color: Color = Color(0.45, 0.85, 0.35)   # toxic green (placeholder only)

@export_group("Look")
## The Art Director's HD frames (assets/characters/hd/, see HdBody):
## "enemy" (the suit with the implant code), or empty for the old sheet.
## Dogs always use the HD doberman.
@export var hd_character: String = "enemy"
## Room pixels walked per HD walk frame.
@export var hd_stride_per_frame: float = 8.0
## Sprite sheet: 64 x 64 cells, 12 per row, drawn facing up. Row 1 = walk
## cycle, row 2 = corpses (odd columns have a burst head). Empty = placeholder shapes.
@export var sheet: Texture2D
@export var sheet_rows: int = 3
## Sheet pixels to room pixels (the walking body is ~23 px wide in the sheet).
@export var sprite_scale: float = 0.6
## Room pixels walked per walk-cycle frame.
@export var stride_per_frame: float = 4.0
## What it holds and drops when it dies. A gun (the pistol) means it shoots
## you; a machete or nothing means it fights up close. Empty = drops nothing.
@export var carried_weapon: WeaponData
## If on, it never leaves the room it starts in (LevelMap sets this).
@export var stays_in_room: bool = false
## A doberman: placeholder dog body, bites, carries nothing, never adapts.
@export var is_dog: bool = false
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
## How long it has hidden this time, and the wait before it may hide again.
var _cover_spent: float = 0.0
var _cover_rest: float = 0.0
## RUSH feint: 0 = none, 1 = stepping back, 2 = striking.
var _feint_phase: int = 0
var _feint_left: float = 0.0
var _feint_cooldown: float = 0.0
var _feint_side: float = 0.0   # 0 = straight lunge, -1/+1 = side-step that way
## True while the player sits on it for a ground finisher: it can't get up.
var pinned: bool = false
## Charge burst: seconds left at charge speed, and the wait before the next.
var _charge_left: float = 0.0
var _charge_rest: float = 0.0
## Machine gun burst: shots still to fire, and when the next one goes.
var _burst_left: int = 0
var _next_shot: float = 0.0
## Seconds the muzzle flash still shows after a shot.
var _muzzle_time: float = 0.0
var _flee_from: Vector2
var _flee_time: float = 0.0
var _home_room: int = -1

const SCATTER_TIME := 1.2   # a little longer than the bomb fuse
const SHEET_COLUMNS := 12
const PUNCH_FRAME := 3          # walk frame with one arm thrown forward
const KNOCKED_FRAME := SHEET_COLUMNS   # first corpse pose, no blood
const CLEAN_CORPSES := [0, 2, 4, 6, 8, 9, 10, 11]
const OUTLINE := preload("res://shaders/outline.gdshader")
const FISTS := preload("res://data/weapons/fists.tres")
## Which HD animation each weapon uses.
const HD_ANIMS := {&"fists": "punch", &"machete": "machete", &"pistol": "pistol", &"shotgun": "shotgun", &"machine_gun": "machinegun"}
## Held weapons on the HD body: same size as on the old one.
const HD_SIZE := 1.0

var _sprite: Sprite2D
var _hd: HdBody               # the HD body (whole body in one sprite)
var _hd_attack: String = ""   # HD attack animation playing
var _hd_attack_time: float = 0.0
var _arms: Sprite2D    # the weapon's arms + weapon frames, on the body sprite
var _shine := BladeShine.new()   # glint along a blade in hand
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
	if is_dog:
		carried_weapon = null   # dogs bite; nothing to drop
	active_counters = [] if is_dog else TacticTracker.get_active_counters()
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
	var look := "dog" if is_dog else hd_character
	if look != "":
		_hd = HdBody.new()
		_hd.name = "HdBody"
		_hd.setup(look, Color.TRANSPARENT, look == "enemy")
		add_child(_hd)
		_hd.fit_collision()
	elif sheet:
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
		_arms = Sprite2D.new()
		_arms.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_arms.visible = false
		_sprite.add_child(_arms)
	add_child(_overlay)


## True if the room has blocked `tactic` and this grunt should counter it.
func counters(tactic: StringName) -> bool:
	return active_counters.has(tactic)


func is_alive() -> bool:
	return state != State.DEAD


var _feet: BloodyFeet


func _physics_process(delta: float) -> void:
	if _feet == null:
		_feet = BloodyFeet.new("dog" if is_dog else "enemy")
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
	_feint_cooldown = maxf(_feint_cooldown - delta, 0.0)
	_muzzle_time = maxf(_muzzle_time - delta, 0.0)
	_charge_left = maxf(_charge_left - delta, 0.0)
	_charge_rest = maxf(_charge_rest - delta, 0.0)
	_cover_rest = maxf(_cover_rest - delta, 0.0)

	if _flee_time > 0.0 and state != State.KNOCKED_DOWN:
		_scatter(delta)
		var fled_from := global_position
		move_and_slide()
		_feet.update(self, global_position, global_position - fled_from)
		_update_sprite(delta)
		queue_redraw()
		_overlay.queue_redraw()
		return

	match state:
		State.PATROL:
			_patrol()
			if sees:
				_enter(State.ALERT)
				if is_dog:
					_bark("GRR")
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
			elif _counter_move(player, sees, delta):
				pass
			elif sees and _can_shoot(player):
				_enter(State.AIM)
			else:
				_move_to(last_known_position, _chase_speed(player, sees))
		State.ATTACK:
			_attack(player)
		State.AIM:
			_aim(player)
		State.SEARCH:
			if not _hold_at_door(player):
				_search()
			if sees:
				_enter(State.CHASE)   # re-sighting: no reaction delay
		State.KNOCKED_DOWN:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _state_time >= settings.knockdown_time and not pinned:
				_enter(State.CHASE if sees else State.SEARCH)
	var was_at := global_position
	move_and_slide()
	if state != State.KNOCKED_DOWN:   # sliding on your back leaves no prints
		_feet.update(self, global_position, global_position - was_at)
	_update_sprite(delta)
	queue_redraw()
	_overlay.queue_redraw()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	if _feint_phase != 0:   # any change of plan ends the feint
		_feint_phase = 0
		_feint_cooldown = settings.feint_cooldown
	_arrived = false
	_look_time = 0.0
	if new_state == State.ATTACK:
		_start_hd_attack()
	if new_state in [State.ATTACK, State.AIM]:
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


## True if `point` is in the vision cone, in range and not behind a wall.
func _can_see_point(point: Vector2) -> bool:
	var to_point := point - global_position
	if to_point.length() > settings.vision_range:
		return false
	if absf(rad_to_deg(facing.angle_to(to_point))) > settings.vision_degrees * 0.5:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, point, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _on_noise_made(at: Vector2, loudness: float) -> void:
	if state in [State.DEAD, State.ATTACK, State.AIM, State.KNOCKED_DOWN]:
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
	if settings.door_alert_needs_sight and not _can_see_point(door_center):
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


## Normal chase speed, or a short burst when it closes in to attack: a
## melee enemy within charge_range of you speeds up for charge_time.
## (The 0.2 s reaction pause in ALERT always comes first.)
func _chase_speed(player: Node2D, sees: bool) -> float:
	if _charge_left <= 0.0 and _charge_rest <= 0.0 and sees and not has_gun() \
			and global_position.distance_to(player.global_position) <= settings.charge_range:
		_start_charge()
	return settings.chase_speed * (settings.charge_speed if _charge_left > 0.0 else 1.0)


func _start_charge() -> void:
	_charge_left = settings.charge_time
	_charge_rest = settings.charge_time + settings.charge_cooldown


## Gun enemies: in range, and nothing (wall, door, furniture) in the way.
func has_gun() -> bool:
	return carried_weapon != null and carried_weapon.kind == WeaponData.Kind.GUN


func _can_shoot(player: Node2D) -> bool:
	if not has_gun() or player == null:
		return false
	if global_position.distance_to(player.global_position) > carried_weapon.reach:
		return false
	if not on_screen():
		return false
	var ray := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 1 | 16)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


## True when you can see it on the screen (a little inside the edge). Gun
## enemies only fire from there: that and shot_delay are your only warning.
func on_screen() -> bool:
	var view := get_viewport().get_visible_rect().grow(-SCREEN_MARGIN)
	return view.has_point(get_viewport().get_canvas_transform() * global_position)


## Stands still and turns to you, then fires after shot_delay. It keeps
## turning until it fires: the delay is your only chance. An automatic gun
## (machine gun) fires a burst of BURST_SHOTS while it still has a clear shot.
func _aim(player: Node2D) -> void:
	velocity = Vector2.ZERO
	if not _struck:
		if player and player.is_alive():
			_attack_direction = global_position.direction_to(player.global_position)
		facing = _attack_direction
		if _state_time >= settings.shot_delay and not on_screen():
			_enter(State.CHASE)   # it slipped off screen: no shot
			return
		if _state_time >= settings.shot_delay:
			_struck = true
			_burst_left = BURST_SHOTS - 1 if carried_weapon.automatic else 0
			_next_shot = _state_time + carried_weapon.recovery_time
			_shoot()
		return
	if _burst_left > 0 and _state_time >= _next_shot:
		if player and player.is_alive() and _can_shoot(player):
			_attack_direction = global_position.direction_to(player.global_position)
			facing = _attack_direction
			_burst_left -= 1
			_next_shot = _state_time + carried_weapon.recovery_time
			_shoot()
		else:
			_burst_left = 0
	if _burst_left == 0 and _state_time >= _next_shot + settings.shot_recovery:
		_enter(State.CHASE)


func _shoot() -> void:
	_muzzle_time = _muzzle_length()
	_start_hd_attack()
	var spread := deg_to_rad(randf_range(-carried_weapon.spread_degrees, carried_weapon.spread_degrees))
	var bullet: Bullet = BULLET_SCENE.instantiate()
	get_parent().add_child(bullet)
	bullet.fire(global_position + _attack_direction * 8.0, _attack_direction.rotated(spread), carried_weapon, self)
	bullet.weapon_id = "grunt_gun"


func _in_swing(player: Node2D) -> bool:
	var to_player := player.global_position - global_position
	if to_player.length() > settings.attack_range + 6.0:
		return false
	if to_player.length() < 8.0:
		return true   # you're right on top of it: no angle can miss you
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


## True if a stay-in-room grunt's next step would take it into a doorway,
## or within 24 px of one (so it can't hold a door open by standing in its
## push zone, whichever way it walks up to it).
func _leaving_room(direction: Vector2) -> bool:
	if not stays_in_room or _home_room < 0:
		return false
	var level := get_tree().get_first_node_in_group("level")
	if level == null:
		return false
	var next := global_position + direction * 4.0
	return level.leaves_room(_home_room, next) or level.near_doorway(next, 24.0)


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
func is_down() -> bool:
	return state == State.KNOCKED_DOWN


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
	if counters(TacticTracker.RUSH) and sees and _feint(player, delta):
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


## RUSH: a feint, never a retreat. When you run straight at it, it takes one
## quick step back (still facing you), then strikes: a short lunge straight at
## you, or a side-step round your swing and a punch. Its usual wind-up before
## the hit stays, so you can still react. Then no feint for a while.
func _feint(player: Node2D, delta: float) -> bool:
	var to_player := player.global_position - global_position
	if _feint_phase == 0:
		if _feint_cooldown > 0.0 or to_player.length() > 64.0:
			return false
		if player.velocity.dot(-to_player.normalized()) < 40.0:
			return false   # you aren't running at it
		_feint_phase = 1
		_feint_left = settings.feint_back_time
		_feint_side = [0.0, -1.0, 1.0][randi() % 3]
	_feint_left -= delta
	facing = to_player.normalized()
	if _feint_phase == 1:
		velocity = -to_player.normalized() * settings.chase_speed
		_bark("FEINT")
		if _feint_left <= 0.0:
			if _can_shoot(player):
				_enter(State.AIM)   # a gun enemy steps back, then shoots
				return true
			_feint_phase = 2
			_feint_left = settings.feint_strike_time
		return true
	# Strike: lunge in, curving to one side if it's side-stepping.
	var lunge := to_player.normalized()
	if _feint_side != 0.0:
		lunge = (lunge + lunge.orthogonal() * _feint_side * 0.9).normalized()
	velocity = lunge * settings.chase_speed * settings.feint_lunge_speed
	if _feint_left <= 0.0:
		_feint_phase = 0
		_feint_cooldown = settings.feint_cooldown
		return false
	return true


## LONG_RANGE: while you hold a gun and stand far away, it ducks behind the
## nearest wall, but only for cover_max_time: then it charges you anyway.
## Beat it: get close, wait for the charge, or use fists.
func _take_cover(player: Node2D, delta: float) -> bool:
	if player == null or not player.has_gun() or _cover_rest > 0.0:
		return false
	if global_position.distance_to(player.global_position) <= 64.0:
		return false   # you're close now: charge
	_cover_spent += delta
	if _cover_spent >= settings.cover_max_time:
		_cover_spent = 0.0
		_cover_rest = settings.cover_cooldown
		_bark("GO")
		_start_charge()   # out of cover at a sprint
		return false
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
	if _hd:
		_update_hd(delta)
		return
	if _sprite == null:
		_walked += velocity.length() * delta   # the placeholder dog's legs
		return
	if state == State.KNOCKED_DOWN:
		_sprite.frame = KNOCKED_FRAME
		_arms.visible = false
		return
	_sprite.rotation = facing.angle() + PI * 0.5
	_sprite.position = facing * _attack_shift()
	var arms_frame := _arms_frame()
	if state == State.ATTACK and arms_frame < 0:
		# No arm frames: twist back in the wind-up, whip through at the hit.
		var t := _state_time / maxf(settings.attack_windup, 0.01)
		_sprite.rotation += -0.5 * minf(t, 1.0) if not _struck else lerpf(-0.5, 0.5, minf((t - 1.0) * 6.0, 1.0))
	_arms.visible = arms_frame >= 0
	if arms_frame >= 0:
		var held: WeaponData = carried_weapon if carried_weapon else FISTS
		_arms.texture = held.enemy_attack_overlay
		_arms.hframes = held.attack_frames
		_arms.frame = arms_frame
		if held.blade_shine:
			_shine.update(delta, velocity.length() > 10.0 or state == State.ATTACK)
	if state == State.ATTACK and not _struck and arms_frame < 0:
		_sprite.frame = PUNCH_FRAME
	elif velocity.length() > 5.0:
		_walked += velocity.length() * delta
		_sprite.frame = int(_walked / stride_per_frame) % SHEET_COLUMNS
	else:
		_sprite.frame = 0


## HD body: the attack playing, else the gun up while aiming or standing,
## the walk while moving, or standing still. Knocked down: dark, still.
func _update_hd(delta: float) -> void:
	var moving := velocity.length() > 5.0
	if moving:
		_walked += velocity.length() * delta
	_hd.face(facing)
	_hd.position = Vector2.ZERO if _hd_attack != "" else facing * _attack_shift()
	_hd.modulate = Color(0.55, 0.55, 0.55) if state == State.KNOCKED_DOWN else Color.WHITE
	if _hd_attack != "":
		_hd_attack_time += delta
		if _hd_attack_time >= _hd.length(_hd_attack):
			_hd_attack = ""
	if state == State.KNOCKED_DOWN:
		_hd_attack = ""
		_hd.show_anim("idle", 0)
	elif _hd_attack != "":
		_hd.show_anim(_hd_attack, _hd.frame_at(_hd_attack, _hd_attack_time))
	elif has_gun() and not moving and _hd.has_anim(_weapon_anim()):
		_hd.show_anim(_weapon_anim(), 0)   # gun up
	elif moving:
		var walk := "trot" if is_dog else "walk"
		_hd.show_anim(walk, int(_walked / hd_stride_per_frame) % _hd.frame_count(walk))
	else:
		_hd.show_anim("idle", 0)
	if carried_weapon and carried_weapon.blade_shine:
		_shine.update(delta, moving or state == State.ATTACK)


## The HD animation for what it holds (a dog bites).
func _weapon_anim() -> String:
	if is_dog:
		return "bite"
	return HD_ANIMS.get(carried_weapon.id if carried_weapon else &"fists", "punch")


func _start_hd_attack() -> void:
	if _hd and _hd.has_anim(_weapon_anim()):
		_hd_attack = _weapon_anim()
		_hd_attack_time = 0.0


## Which arm frame to show (-1 = none): a weapon in hand always (frame 0),
## bare fists only while punching. Melee: wind-up, hit, follow-through.
## Gun: the shot, then the recoil.
func _arms_frame() -> int:
	var held: WeaponData = carried_weapon if carried_weapon else FISTS
	if held.enemy_attack_overlay == null:
		return -1
	var last := held.attack_frames - 1
	if has_gun():
		if _muzzle_time > 0.0:
			return 1 if _muzzle_time > _muzzle_length() * 0.5 else last
		return 0
	if state == State.ATTACK:
		if not _struck:
			return 1
		return 2 if _state_time - settings.attack_windup < 0.06 else last
	return 0 if carried_weapon else -1


## How far the body leans along `facing`: back in the wind-up, a lunge at
## the hit, a kick back on each shot.
func _attack_shift() -> float:
	if _muzzle_time > 0.0:
		return -2.0 * _muzzle_time / _muzzle_length()
	if state != State.ATTACK:
		return 0.0
	if not _struck:
		return -1.5 * minf(_state_time / maxf(settings.attack_windup, 0.01), 1.0)
	var after := _state_time - settings.attack_windup
	return 3.5 * maxf(1.0 - after / maxf(settings.attack_recovery, 0.01), 0.0)


## The corpse the gore layer paints when it dies (empty = placeholder shapes).
func _corpse() -> Dictionary:
	if _hd:
		# The Art Director's death, then its dead pose: one of four, at random.
		return {"pixel": _hd.who, "size": _hd.size(), "variant": HdBody.death_variant(_hd.who)}
	if is_dog:
		return {"dog": true}
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
		var alert := state in [State.ALERT, State.CHASE, State.ATTACK, State.AIM]
		draw_colored_polygon(cone, Color(1, 0.2, 0.2, 0.07) if alert else Color(1, 1, 1, 0.04))
	if _sprite or _hd:
		return   # the sprite shows the body
	if is_dog:
		_draw_dog(angle)
		return
	if state == State.KNOCKED_DOWN:
		# Lying on the floor.
		draw_set_transform(Vector2.ZERO, angle)
		draw_circle(Vector2.ZERO, 6.0, body_color.darkened(0.3))
		draw_circle(Vector2(8, 0), 3.5, body_color.darkened(0.3))
		draw_set_transform(Vector2.ZERO, 0.0)
		return
	draw_circle(Vector2.ZERO, 7.0, body_color)
	draw_line(Vector2.ZERO, facing * 9.0, Color(0.1, 0.1, 0.1), 3.0)


## Placeholder doberman (until the Creative Director's art): a long dark
## body with tan legs and snout, pointy ears, a short tail; it lies on its
## side when knocked down. Drawn pointing along +x, then turned.
func _draw_dog(angle: float) -> void:
	var coat := body_color
	var tan := Color(0.72, 0.45, 0.22)
	var outline := Color(0.05, 0.03, 0.03)
	draw_set_transform(Vector2.ZERO, angle)
	if state == State.KNOCKED_DOWN:
		draw_set_transform(Vector2.ZERO, angle, Vector2(1.0, 1.4))
	var step := sin(_walked * 0.6) * 2.0 if velocity.length() > 5.0 else 0.0
	for leg in [Vector2(5, 3.5), Vector2(5, -3.5), Vector2(-5, 3.5), Vector2(-5, -3.5)]:
		var swing: float = step if (leg.x > 0) == (leg.y > 0) else -step
		draw_circle(leg + Vector2(swing, signf(leg.y) * 0.8), 1.4, tan)
	draw_set_transform(Vector2.ZERO, angle, Vector2(1.0, 0.55) if state != State.KNOCKED_DOWN else Vector2(1.0, 0.8))
	draw_circle(Vector2.ZERO, 8.0, outline)
	draw_circle(Vector2.ZERO, 7.0, coat)
	draw_set_transform(Vector2.ZERO, angle)
	draw_line(Vector2(-7, 0), Vector2(-11, 0), coat, 2.0)   # tail
	draw_circle(Vector2(8, 0), 3.6, outline)                 # head
	draw_circle(Vector2(8, 0), 3.0, coat)
	draw_circle(Vector2(11, 0), 1.6, tan)                    # snout
	draw_colored_polygon(PackedVector2Array([Vector2(6, -2), Vector2(4, -5), Vector2(8, -2.5)]), coat)   # ears
	draw_colored_polygon(PackedVector2Array([Vector2(6, 2), Vector2(4, 5), Vector2(8, 2.5)]), coat)
	if state in [State.ALERT, State.CHASE, State.ATTACK]:
		draw_circle(Vector2(9, -1.2), 0.7, Color(1, 0.2, 0.15))   # angry eyes
		draw_circle(Vector2(9, 1.2), 0.7, Color(1, 0.2, 0.15))
	draw_set_transform(Vector2.ZERO, 0.0)


## How far ahead the gun's barrel is drawn (the HD enemy holds it out at
## the end of his body).
func _muzzle_distance() -> float:
	return 12.0 if _hd else 14.0


## How long the muzzle fire shows: the art's frames, or a quick flash.
func _muzzle_length() -> float:
	if carried_weapon and carried_weapon.fire_texture:
		return carried_weapon.fire_frames / carried_weapon.fire_fps
	return 0.06


## Everything drawn on top of the body: gun, eyes, warnings and barks.
func _draw_overlay() -> void:
	var o := _overlay
	if state == State.KNOCKED_DOWN:
		return
	if _hd and carried_weapon and carried_weapon.blade_shine:
		var points := _hd.blade_points(o) if _hd.current.ends_with(_weapon_anim()) else []
		if points.is_empty() and carried_weapon.floor_texture:
			var size := carried_weapon.held_size() * HD_SIZE
			var at := Transform2D(facing.angle(), facing.orthogonal() * 5.0 + facing * _attack_shift())
			points = HdBody.held_blade_points(carried_weapon, at, Rect2(Vector2(0, -size.y / 2.0), size))
		if points.size() == 2:
			_shine.draw(o, points[0], points[1], 2.5)
	elif _arms and _arms.visible and carried_weapon and carried_weapon.blade_shine:
		var line := BladeShine.blade_line(_arms.texture, carried_weapon.attack_frames, _arms.frame)
		if not line.is_empty():
			var to_me := get_global_transform().affine_inverse() * _arms.get_global_transform()
			_shine.draw(o, to_me * line[0], to_me * line[1], 2.5)
	if carried_weapon:
		# The gun it will drop, held at its side.
		var hand := facing.orthogonal() * 5.0 if _hd else facing.orthogonal() * 5.0 + facing * 6.0
		if carried_weapon.enemy_attack_overlay and _sprite:
			pass   # the arm frames show the weapon in hand
		elif _hd and _hd.current.ends_with(_weapon_anim()):
			pass   # the HD frames show it (attacking, or gun up)
		elif carried_weapon.floor_texture:
			var size := carried_weapon.held_size() * (HD_SIZE if _hd else 1.0)
			o.draw_set_transform(hand + facing * _attack_shift(), facing.angle())
			o.draw_texture_rect(carried_weapon.floor_texture, Rect2(Vector2(0, -size.y / 2.0), size), false)
			o.draw_set_transform(Vector2.ZERO)
		else:
			o.draw_line(hand, hand + facing * 6.0, carried_weapon.color, 2.5)
	if _muzzle_time > 0.0:
		var art := carried_weapon.fire_texture if carried_weapon else null
		if art and has_gun():
			var frame := int((_muzzle_length() - _muzzle_time) * carried_weapon.fire_fps)
			var rect := WeaponData.frame_rect(art, carried_weapon.fire_frames, frame)
			o.draw_set_transform(facing * _muzzle_distance(), facing.angle())
			var drawn := rect.size * carried_weapon.art_scale
			o.draw_texture_rect_region(art, Rect2(Vector2(0, -drawn.y / 2.0), drawn), rect)
			o.draw_set_transform(Vector2.ZERO)
		else:
			o.draw_circle(facing * _muzzle_distance(), 3.0, Color(1, 0.95, 0.6))
	if tell_color.a > 0.0:
		# Glowing eyes: this grunt has learned your moves.
		var eyes := facing * (-6.0 if _hd else 3.0)   # HD: the head is behind the middle of the body
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
