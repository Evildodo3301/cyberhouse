class_name TouchControls
extends CanvasLayer
## The on-screen controls: a move stick (left), an aim stick (right), a bomb
## button and a THROW button (right, above the aim zone) and a pause button. The player reads
## `move_vector` and `aim_vector`, and listens to `attack_requested` and
## `bomb_requested`.

## Emitted when the player should attack.
## `direction` is the aimed direction, or Vector2.ZERO for a quick tap
## (meaning "attack the nearest enemy in front of me").
signal attack_requested(direction: Vector2)
## Emitted when the player should throw the weapon they hold.
## `direction` is the dragged direction, or Vector2.ZERO for a tap.
signal throw_requested(direction: Vector2)
## Emitted when the player should throw a bomb.
## `direction` is the dragged direction, or Vector2.ZERO for a tap
## (meaning "throw where I'm aiming or facing").
signal bomb_requested(direction: Vector2)

@onready var move_stick: VirtualJoystick = $MoveStick
@onready var aim_stick: VirtualJoystick = $AimStick
@onready var bomb_button: BombButton = $BombButton
@onready var throw_button: ThrowButton = $ThrowButton
@onready var pause_button: Button = $PauseButton

## Movement direction from the left stick.
var move_vector: Vector2:
	get:
		return move_stick.value

## Aim direction from the right stick (ZERO when not aiming).
var aim_vector: Vector2:
	get:
		return aim_stick.value


func _ready() -> void:
	# The aim stick must ignore touches that land on the bomb button.
	aim_stick.blocked_by.append(bomb_button)
	aim_stick.blocked_by.append(throw_button)
	throw_button.bomb = bomb_button
	throw_button.released.connect(_on_throw_released)
	aim_stick.released.connect(_on_aim_released)
	bomb_button.released.connect(_on_bomb_released)
	pause_button.pressed.connect(_on_pause_pressed)


func _on_aim_released(final_value: Vector2, was_tap: bool) -> void:
	if was_tap:
		attack_requested.emit(Vector2.ZERO)
	elif final_value != Vector2.ZERO:
		# Lifting the thumb while aiming = attack in that direction.
		attack_requested.emit(final_value.normalized())
	# Otherwise the thumb slid back to the center before lifting:
	# treat it as "cancel", no attack.


func _on_bomb_released(final_value: Vector2, was_tap: bool) -> void:
	if was_tap or final_value == Vector2.ZERO:
		bomb_requested.emit(Vector2.ZERO)
	else:
		bomb_requested.emit(final_value.normalized())


func _on_throw_released(final_value: Vector2, was_tap: bool) -> void:
	if was_tap or final_value == Vector2.ZERO:
		throw_requested.emit(Vector2.ZERO)
	else:
		throw_requested.emit(final_value.normalized())


func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	pause_button.text = "▶" if get_tree().paused else "II"
