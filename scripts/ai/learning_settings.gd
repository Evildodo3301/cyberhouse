class_name LearningSettings
extends Resource
## The numbers behind the learning enemies (M3). Design doc:
## /mnt/project-files/ai/learning-enemies-concept.md

@export_group("Fairness")
## Tactics that always stay open. Max blocked = tactics - this (never above max_blocked).
@export var min_open_tactics: int = 2
@export var max_blocked: int = 3
## After this many deaths in one room, no new blocks until the room is cleared.
@export var frustration_deaths: int = 5

@export_group("Tagging")
## A melee kill (or death) at this speed or faster counts as a RUSH (player top speed is 96).
@export var rush_speed: float = 60.0
## A gun kill from this far or further counts as LONG_RANGE (px).
@export var long_range_distance: float = 48.0
## A death counts as "while doing X" if you attacked this recently (seconds).
@export var recent_attack_seconds: float = 1.0

@export_group("Look")
## Eye glow of enemies that have adapted.
@export var adapted_eye_color: Color = Color(1.0, 0.25, 0.1)
