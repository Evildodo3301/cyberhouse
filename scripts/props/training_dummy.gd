class_name TrainingDummy
extends Node2D
## A target to practice on in M1. It dies in one hit, leaves its body and
## blood on the floor for the rest of the room, and a new one stands up after
## a moment. Real enemies arrive in M2 and
## will use the same two functions: is_alive() and take_hit().

@export var respawn_time: float = 1.5
@export var color: Color = Color(1.0, 0.75, 0.2)   # neon amber

## Seconds it stays down after a door hits it.
@export var knockdown_time: float = 1.5

var _alive: bool = true
var _knocked: bool = false
var _start_position: Vector2


func _ready() -> void:
	add_to_group("targets")   # the player only attacks nodes in this group
	_start_position = position


func is_alive() -> bool:
	return _alive


## Called by the player's swing or a bomb. `weapon` is a label like "melee".
func take_hit(attacker: Node2D, direction: Vector2, weapon: String) -> void:
	if not _alive:
		return
	_alive = false
	_report_death(attacker, weapon)
	# The body and blood are painted onto the floor and stay for the whole
	# room. The dummy itself vanishes and a fresh one stands up later, so
	# you can keep practising while the floor fills up.
	var gore := get_tree().get_first_node_in_group("gore")
	if gore:
		gore.add_kill(global_position + direction * 10.0, direction, color, weapon)
	visible = false
	await get_tree().create_timer(respawn_time).timeout
	position = _start_position
	_alive = true
	visible = true


## A door slammed into it: it lies down for a moment (still killable).
func knock_down(_by: Node, direction: Vector2) -> void:
	if not _alive or _knocked:
		return
	_knocked = true
	var tween := create_tween()
	tween.tween_property(self, "position", position + direction * 12.0, 0.12)
	queue_redraw()
	await get_tree().create_timer(knockdown_time).timeout
	_knocked = false
	queue_redraw()


## Sends the "death report" the learning system (M3) will learn from.
func _report_death(attacker: Node2D, weapon: String) -> void:
	var player_speed := 0.0
	if attacker is CharacterBody2D:
		player_speed = attacker.velocity.length()
	TacticTracker.report_kill({
		"victim": name,
		"weapon": weapon,
		"distance": global_position.distance_to(attacker.global_position),
		"player_speed": player_speed,
		"at_door": false,        # doors arrive in M2
		"chasing_noise": false,  # hearing arrives in M2
	})


func _draw() -> void:
	if _knocked:
		draw_circle(Vector2.ZERO, 6.0, color.darkened(0.4))   # lying down
		return
	draw_circle(Vector2.ZERO, 7.0, color)
	draw_circle(Vector2.ZERO, 3.0, Color(0.1, 0.05, 0.15))
