class_name VoidFlash
extends Node
## The void outside the map (everything that isn't floor or wall) is never
## black: it slowly cycles through neon colours all the time (blue, orange,
## teal, pink...), and each gunshot flashes it a bright warm colour for an
## instant. The courtyards and the area round the house show it.

## Seconds for one full trip round the colour wheel.
@export var cycle_seconds: float = 8.0
## How bright and colourful the void is between shots.
@export var saturation: float = 0.75
@export var brightness: float = 0.42
## The colour a shot flashes it.
@export var flash_color: Color = Color(1.0, 0.62, 0.45)
## Seconds a shot's flash lasts (about two frames).
@export var flash_time: float = 0.06

## 1 right after a shot, fading to 0 over flash_time.
var strength: float = 0.0
var hue: float = 0.55   # starts on blue
var _base: Color


func _ready() -> void:
	_base = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	Game.shot_fired.connect(_on_shot)
	RenderingServer.set_default_clear_color(current_color())


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(_base)


func _on_shot(weapon: WeaponData) -> void:
	if weapon.void_flash > 0.0:
		strength = clampf(weapon.void_flash, 0.0, 1.0)


func current_color() -> Color:
	var cycle := Color.from_hsv(hue, saturation, brightness)
	return cycle.lerp(flash_color, strength)


func _process(delta: float) -> void:
	hue = fposmod(hue + delta / cycle_seconds, 1.0)
	strength = maxf(strength - delta / flash_time, 0.0)
	RenderingServer.set_default_clear_color(current_color())
