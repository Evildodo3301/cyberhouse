extends Node
## Records how every kill happened, so the learning system (M3) has data
## to learn from. In M1 and M2 it only stores and prints reports; nothing
## reacts to them yet. Call it from anywhere with `TacticTracker.report_kill()`.
##
## Why an autoload? Restarting a room reloads the whole scene, which wipes
## every enemy and the room itself. An autoload is NOT reloaded, so what
## the room "remembers" about the player survives each instant restart.

## The room the player is in right now (set by each room when it starts).
var current_room_id: StringName = &""

## Reports per room: { room_id: [report, report, ...] }, oldest first.
var reports_by_room: Dictionary = {}
## Other events per room (player deaths, door knockdowns), same layout.
var events_by_room: Dictionary = {}


## Attempt number per room: 1 on first entry, +1 on every restart.
## Each report is stamped with it, so M3 can look at "the attempt that just ended".
var attempt_by_room: Dictionary = {}


## Called by each room in its _ready(). Restarting the same room keeps its memory.
func enter_room(room_id: StringName) -> void:
	current_room_id = room_id
	if not reports_by_room.has(room_id):
		reports_by_room[room_id] = []
	start_attempt()


## A new try at the current room (first entry or an instant restart).
func start_attempt() -> void:
	attempt_by_room[current_room_id] = attempt_by_room.get(current_room_id, 0) + 1


func current_attempt() -> int:
	return attempt_by_room.get(current_room_id, 0)


## Reports from one attempt of the current room (kills and events together).
func get_attempt_reports(attempt: int) -> Array:
	var all: Array = reports_by_room.get(current_room_id, []) + events_by_room.get(current_room_id, [])
	return all.filter(func(r): return r.get("attempt") == attempt)


## Tactics the enemies should counter right now. Each enemy reads this in
## _ready(). M2 stub: always empty. M3 fills it from the death reports.
func get_active_counters() -> Array:
	return []


## Called when a room is beaten: its memory is no longer needed.
func clear_room(room_id: StringName) -> void:
	reports_by_room.erase(room_id)
	events_by_room.erase(room_id)
	attempt_by_room.erase(room_id)


## Reports for the current room.
func get_room_reports() -> Array:
	return reports_by_room.get(current_room_id, [])


## Called when the player dies. Keys (see player.gd take_hit): killer_type
## ("enemy_melee", "enemy_gun", "own_bomb"), weapon, killer, player_position,
## in_doorway, door_id, behind_corner, player_speed, last_attack,
## last_attack_seconds_ago, noise_pulling_enemies.
func report_player_death(report: Dictionary) -> void:
	report["type"] = "player_death"
	report_event(report)


## Anything else worth remembering (door knockdowns, player deaths...).
func report_event(report: Dictionary) -> void:
	report["room_id"] = current_room_id
	report["attempt"] = current_attempt()
	report["time"] = Time.get_ticks_msec() / 1000.0
	if not events_by_room.has(current_room_id):
		events_by_room[current_room_id] = []
	events_by_room[current_room_id].append(report)
	print("[TacticTracker] event: %s" % report)


## Called by a target or enemy when it dies.
## Expected keys: weapon, distance, player_speed, at_door, chasing_noise.
func report_kill(report: Dictionary) -> void:
	report["room_id"] = current_room_id
	report["attempt"] = current_attempt()
	report["time"] = Time.get_ticks_msec() / 1000.0
	if not reports_by_room.has(current_room_id):
		reports_by_room[current_room_id] = []
	reports_by_room[current_room_id].append(report)
	print("[TacticTracker] %s kill #%d: %s" % [current_room_id, reports_by_room[current_room_id].size(), report])
