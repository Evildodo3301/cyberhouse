class_name EnemySettings
extends Resource
## Every number that controls how an enemy behaves, kept in ONE place
## (open res://data/grunt_settings.tres to tweak them in the Inspector).
##
## The learning system (M3) gives enemies counters by changing values like
## these, so they must never be hard-coded inside the enemy script.
## Distances are in pixels (16 px = one character width).

@export_group("Movement")
## Walking speed on patrol.
@export var patrol_speed: float = 45.0
## Running speed when chasing. The player runs at 96.
@export var chase_speed: float = 100.0
## Pause at each patrol point, in seconds.
@export var patrol_pause: float = 0.8

@export_group("Senses")
## Seconds between seeing you and attacking. The main fairness knob.
## Creative Director asked for faster enemies: 0.2 (design doc default 0.25).
@export var reaction_time: float = 0.2
## When on, it notices you the moment you step into its room, wherever it is
## looking and even behind a pillar. It still waits out reaction_time (the
## "!") before it charges, so you get a fair split second.
@export var notice_whole_room: bool = true
## Width of the vision cone, in degrees.
@export var vision_degrees: float = 90.0
## How far it can see (8 character widths).
@export var vision_range: float = 128.0
## It also notices you this close, even behind its back.
@export var close_awareness_range: float = 16.0
## When on, a door you open only alerts it if it can see that door (it is
## in its vision cone and nothing is in between), so you can slip in behind
## its back. Off = any door of its room alerts it.
@export var door_alert_needs_sight: bool = false
## How far a noise of loudness 1.0 carries.
@export var hearing_range: float = 600.0
## After losing sight of you for this long, it starts searching.
@export var lose_sight_time: float = 0.6
## How long it looks around at your last known position before giving up.
@export var search_look_time: float = 2.0

@export_group("Attack")
## Starts a swing when you're this close.
@export var attack_range: float = 18.0
## Telegraph before its swing lands (a red arc shows it).
@export var attack_windup: float = 0.18
## Pause after a swing before it can act again.
@export var attack_recovery: float = 0.45
## Width of its swing, in degrees.
@export var attack_arc_degrees: float = 100.0

@export_group("Charge")
## Close enough (px) and it bursts toward you to attack (melee enemies, and
## any enemy coming out of COVER).
@export var charge_range: float = 56.0
## Burst speed, times chase_speed, and how long the burst lasts.
@export var charge_speed: float = 1.4
@export var charge_time: float = 0.5
## Seconds after a burst before it can burst again.
@export var charge_cooldown: float = 1.2

@export_group("Gun")
## Seconds between a gun enemy turning to you and firing. No warning is shown:
## this is all the time you get to react (Fianso: "few milliseconds").
@export var shot_delay: float = 0.2
## Pause after each shot before it can shoot again.
@export var shot_recovery: float = 0.6

@export_group("Learned counters")
## RUSH counter: when you run at it, it steps back this long (one step)...
@export var feint_back_time: float = 0.25
## ...then strikes for up to this long: a lunge at you or a side-step and a punch.
@export var feint_strike_time: float = 0.4
## Speed of that lunge, times chase_speed. Short, so it's a surprise, not a chase.
@export var feint_lunge_speed: float = 1.35
## Seconds before it can feint again. It never backs off over and over.
@export var feint_cooldown: float = 2.5
## LONG_RANGE counter: longest it hides behind cover before it charges you...
@export var cover_max_time: float = 1.5
## ...and how long before it will hide again.
@export var cover_cooldown: float = 3.0

@export_group("Doors")
## Seconds it stays down after a door slams into it.
@export var knockdown_time: float = 1.5
## Pause before walking through a doorway (0 in M2; an M3 counter can raise it).
@export var door_pause_time: float = 0.0

@export_group("Debug")
## Draw the vision cone (design: on for M2 testing, decide later).
@export var show_vision_cone: bool = true
