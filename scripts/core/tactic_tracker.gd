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


## Called by each room in its _ready(). Restarting the same room keeps its memory.
func enter_room(room_id: StringName) -> void:
	current_room_id = room_id
	if not reports_by_room.has(room_id):
		reports_by_room[room_id] = []


## Called when a room is beaten: its memory is no longer needed.
func clear_room(room_id: StringName) -> void:
	reports_by_room.erase(room_id)


## Reports for the current room.
func get_room_reports() -> Array:
	return reports_by_room.get(current_room_id, [])


## Called by a target or enemy when it dies.
## Expected keys: weapon, distance, player_speed, at_door, chasing_noise.
func report_kill(report: Dictionary) -> void:
	report["room_id"] = current_room_id
	report["time"] = Time.get_ticks_msec() / 1000.0
	if not reports_by_room.has(current_room_id):
		reports_by_room[current_room_id] = []
	reports_by_room[current_room_id].append(report)
	print("[TacticTracker] %s kill #%d: %s" % [current_room_id, reports_by_room[current_room_id].size(), report])
