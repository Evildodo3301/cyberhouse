extends Node
## The room's memory of how you play (M3 "learning enemies").
##
## Every kill and every death gets a tactic tag. When you die, the room blocks
## two moves for the next retry: the move you died doing, and the move that
## got you the most kills in that attempt. Enemies read the blocked moves in
## _ready() and switch on a counter for each (see grunt.gd).
## Fairness: at least 2 tactics always stay open, the oldest block drops out
## first, and after 5 deaths in a room nothing new is blocked.
## Design: /mnt/project-files/ai/learning-enemies-concept.md
##
## Why an autoload? Restarting a room reloads the whole scene, which wipes
## every enemy and the room itself. An autoload is NOT reloaded, so what
## the room "remembers" about the player survives each instant restart.

## The four tactics of the first M3 build.
const DOOR_AMBUSH := &"DOOR_AMBUSH"
const RUSH := &"RUSH"
const LONG_RANGE := &"LONG_RANGE"
const BOMB := &"BOMB"
const TACTICS: Array[StringName] = [DOOR_AMBUSH, RUSH, LONG_RANGE, BOMB]

var settings: LearningSettings


func _ready() -> void:
	settings = load("res://data/learning_settings.tres")

## The room the player is in right now (set by each room when it starts).
var current_room_id: StringName = &""

## Reports per room: { room_id: [report, report, ...] }, oldest first.
var reports_by_room: Dictionary = {}
## Other events per room (player deaths, door knockdowns), same layout.
var events_by_room: Dictionary = {}


## Attempt number per room: 1 on first entry, +1 on every restart.
## Each report is stamped with it, so M3 can look at "the attempt that just ended".
var attempt_by_room: Dictionary = {}

## Blocked tactics per room, oldest first: { room_id: [tactic, ...] }.
var blocked_by_room: Dictionary = {}
## Player deaths per room (for the frustration valve).
var deaths_by_room: Dictionary = {}
## Blocks added by the last death, shown as "PATTERN LOGGED" on the restart.
var _new_blocks: Array[StringName] = []


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


## Tactics the enemies should counter right now. Each enemy reads this in _ready().
func get_active_counters() -> Array:
	return blocked_by_room.get(current_room_id, []).duplicate()


## The blocks the last death added, once (the restart flash shows them).
func take_new_blocks() -> Array[StringName]:
	var blocks := _new_blocks.duplicate()
	_new_blocks.clear()
	return blocks


## How many tactics can be blocked at once in this build.
func max_blocks() -> int:
	return mini(TACTICS.size() - settings.min_open_tactics, settings.max_blocked)


# ----------------------------------------------------------------- tagging

## Which tactic a kill used, or &"" if none fits clearly.
func tag_kill(report: Dictionary) -> StringName:
	if not report.has("enemy_state"):
		return &""   # training dummies don't teach the room anything
	var weapon: String = report.get("weapon", "")
	if weapon == "bomb":
		return BOMB
	if report.get("at_door", false):
		return DOOR_AMBUSH
	if weapon != "melee" and report.get("distance", 0.0) >= settings.long_range_distance:
		return LONG_RANGE
	if weapon == "melee" and report.get("player_speed", 0.0) >= settings.rush_speed:
		return RUSH
	return &""


## What the player was doing when they died, or &"" if it's not clear
## (better no counter than a wrong one).
func tag_death(report: Dictionary) -> StringName:
	if report.get("killer_type") == "own_bomb":
		return BOMB
	if report.get("in_doorway", false):
		return DOOR_AMBUSH
	var ago: float = report.get("last_attack_seconds_ago", -1.0)
	var recent := ago >= 0.0 and ago <= settings.recent_attack_seconds
	if recent and report.get("last_attack") == "gun":
		return LONG_RANGE
	if report.get("player_speed", 0.0) >= settings.rush_speed or (recent and report.get("last_attack") == "melee"):
		return RUSH
	return &""


## The tactic with the most kills in `attempt` (ties: the most recent one).
func best_tactic(attempt: int) -> StringName:
	var counts := {}
	var last_used := {}
	var order := 0
	for report in reports_by_room.get(current_room_id, []):
		order += 1
		var tactic: StringName = report.get("tactic", &"")
		if report.get("attempt") != attempt or tactic == &"":
			continue
		counts[tactic] = counts.get(tactic, 0) + 1
		last_used[tactic] = order
	var best: StringName = &""
	for tactic in counts:
		if best == &"" or counts[tactic] > counts[best] \
				or (counts[tactic] == counts[best] and last_used[tactic] > last_used[best]):
			best = tactic
	return best


func _learn_from_death(report: Dictionary) -> void:
	var deaths: int = deaths_by_room.get(current_room_id, 0) + 1
	deaths_by_room[current_room_id] = deaths
	if deaths > settings.frustration_deaths:
		return   # frustration valve: stop adding blocks until the room is cleared
	var to_block: Array[StringName] = []
	for tactic in [report.get("tactic", &""), best_tactic(report.get("attempt"))]:
		if tactic != &"" and not to_block.has(tactic):
			to_block.append(tactic)
	var blocked: Array = blocked_by_room.get(current_room_id, [])
	for tactic in to_block:
		blocked.erase(tactic)
		blocked.append(tactic)   # newest last
	while blocked.size() > max_blocks():
		blocked.pop_front()      # the oldest block drops out first
	blocked_by_room[current_room_id] = blocked
	_new_blocks = to_block
	if not to_block.is_empty():
		print("[TacticTracker] PATTERN LOGGED %s, blocked now %s" % [to_block, blocked])


## Called when a room is beaten: its memory is no longer needed.
func clear_room(room_id: StringName) -> void:
	reports_by_room.erase(room_id)
	events_by_room.erase(room_id)
	attempt_by_room.erase(room_id)
	blocked_by_room.erase(room_id)
	deaths_by_room.erase(room_id)
	_new_blocks.clear()


## Reports for the current room.
func get_room_reports() -> Array:
	return reports_by_room.get(current_room_id, [])


## Called when the player dies. Keys (see player.gd take_hit): killer_type
## ("enemy_melee", "enemy_gun", "own_bomb"), weapon, killer, player_position,
## in_doorway, door_id, behind_corner, player_speed, last_attack,
## last_attack_seconds_ago, noise_pulling_enemies.
func report_player_death(report: Dictionary) -> void:
	report["type"] = "player_death"
	report["tactic"] = tag_death(report)
	report_event(report)
	_learn_from_death(report)


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
	report["tactic"] = tag_kill(report)
	report["room_id"] = current_room_id
	report["attempt"] = current_attempt()
	report["time"] = Time.get_ticks_msec() / 1000.0
	if not reports_by_room.has(current_room_id):
		reports_by_room[current_room_id] = []
	reports_by_room[current_room_id].append(report)
	print("[TacticTracker] %s kill #%d: %s" % [current_room_id, reports_by_room[current_room_id].size(), report])
