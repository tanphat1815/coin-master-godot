# ==============================================================================
# SlotMachineUI.gd
# Path: res://src/ui/SlotMachineUI.gd
# Role: Slot machine interaction and reel animation. Pure View — zero game math.
# Access pattern: Attached to SlotMachinePanel root node in SlotMachinePanel.tscn.
# Signals: Subscribes to SlotMachineLogic signals. Emits no signals.
# ==============================================================================
extends Control
class_name SlotMachineUI

const REEL_SPIN_DURATION: float = 1.5
const REVEAL_DURATION: float = 0.4

var _spin_button: Button
var _reel1: CanvasItem
var _reel2: CanvasItem
var _reel3: CanvasItem
var _result_label: Label
var _is_spinning: bool = false


func _ready() -> void:
	# ── Cache node references ────────────────────────────────────────────────────
	_spin_button  = $SpinButton  as Button
	_reel1       = $ReelContainer/Reel1       as CanvasItem
	_reel2       = $ReelContainer/Reel2       as CanvasItem
	_reel3       = $ReelContainer/Reel3       as CanvasItem
	_result_label = $ResultLabel as Label

	if _spin_button == null:
		push_error("[SlotMachineUI] SpinButton not found at $SpinButton.")
		return
	if _reel1 == null or _reel2 == null or _reel3 == null:
		push_error("[SlotMachineUI] One or more reel nodes not found.")
		return
	if _result_label == null:
		push_warning("[SlotMachineUI] ResultLabel not found at $ResultLabel.")

	# ── Initialize visual state ──────────────────────────────────────────────────
	_result_label.text = "Spin to play!"
	_result_label.modulate = Color.WHITE
	_reel1.position = Vector2(0, 0)
	_reel2.position = Vector2(0, 0)
	_reel3.position = Vector2(0, 0)

	# ── Wire button press ───────────────────────────────────────────────────────
	_spin_button.pressed.connect(_on_spin_button_pressed)

	# ── Subscribe to SlotMachineLogic signals ───────────────────────────────────
	var slot_logic: SlotMachineLogic = _find_slot_logic()
	if slot_logic != null:
		slot_logic.spin_completed.connect(_on_spin_completed)
		slot_logic.spin_failed_insufficient_spins.connect(_on_spin_failed)
		slot_logic.raid_triggered.connect(_on_raid_triggered)
		slot_logic.attack_triggered.connect(_on_attack_triggered)
		slot_logic.shield_overflow_intercepted.connect(_on_shield_overflow)
		print("[SlotMachineUI] Connected to SlotMachineLogic signals.")
	else:
		push_error("[SlotMachineUI] SlotMachineLogic node not found. Cannot connect signals.")

	# ── Initial button state ─────────────────────────────────────────────────────
	_update_button_state()
	print("[SlotMachineUI] Initialized.")


# ─── Input Entry Point ─────────────────────────────────────────────────────────

func _on_spin_button_pressed() -> void:
	# ── Spam guard ─────────────────────────────────────────────────────────────
	if _is_spinning:
		print("[SlotMachineUI] Spin ignored — animation in progress.")
		return

	# ── Sanity check ────────────────────────────────────────────────────────────
	var slot_logic: SlotMachineLogic = _find_slot_logic()
	if slot_logic == null:
		push_error("[SlotMachineUI] SlotMachineLogic not available.")
		return

	# ── Check if player can spin ────────────────────────────────────────────────
	if not slot_logic.can_spin(1):
		_spin_button.disabled = true
		_result_label.text = "Not enough spins!"
		print("[SlotMachineUI] Spin blocked — insufficient spins.")
		return

	# ── LOCK INPUT ─────────────────────────────────────────────────────────────
	_is_spinning = true
	_spin_button.disabled = true
	_result_label.text = "..."
	print("[SlotMachineUI] Spin initiated. Button locked.")

	# ── START VISUAL ANIMATION (runs in parallel with math) ─────────────────────
	_play_spin_animation()

	# ── CALL MODEL — outcome already decided before signal fires ─────────────────
	var _unused_result: Dictionary = slot_logic.spin_reels(1)


# ─── Animation ─────────────────────────────────────────────────────────────────

func _play_spin_animation() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)

	var reel_y_offset: float = 60.0

	# Reel 1: three-segment oscillation
	tween.tween_property(_reel1, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.33) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_reel1, "position:y", 0.0, REEL_SPIN_DURATION * 0.33) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_reel1, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.34) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Reel 2: phase-offset oscillation
	tween.tween_property(_reel2, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_reel2, "position:y", 0.0, REEL_SPIN_DURATION * 0.36) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_reel2, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.36) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Reel 3: different speed for visual variety
	tween.tween_property(_reel3, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.40) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_reel3, "position:y", 0.0, REEL_SPIN_DURATION * 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_reel3, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Result label pulse while spinning
	var pulse_tween: Tween = create_tween()
	pulse_tween.set_parallel(true)
	pulse_tween.tween_property(_result_label, "modulate:a", 0.4, REEL_SPIN_DURATION * 0.5)
	pulse_tween.tween_property(_result_label, "modulate:a", 1.0, REEL_SPIN_DURATION * 0.5)

	print("[SlotMachineUI] Spin animation started. Duration: %.1fs." % REEL_SPIN_DURATION)


func _play_reveal_animation(tier: String) -> void:
	var target_color: Color = Color.WHITE
	match tier:
		"large", "jackpot":
			target_color = Color.GOLD
		"medium":
			target_color = Color.SILVER
		_:
			target_color = Color.WHITE

	# Scale pop: up to 1.2x then back to 1.0x (sequential)
	var scale_tween: Tween = create_tween()
	scale_tween.tween_property(_result_label, "scale", Vector2(1.2, 1.2), REVEAL_DURATION * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(_result_label, "scale", Vector2(1.0, 1.0), REVEAL_DURATION * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	# Color flash
	var color_tween: Tween = create_tween()
	color_tween.set_parallel(true)
	color_tween.tween_property(_result_label, "modulate", target_color, REVEAL_DURATION * 0.3)
	color_tween.tween_property(_result_label, "modulate", Color.WHITE, REVEAL_DURATION * 0.7)

	print("[SlotMachineUI] Reveal animation played. Tier: %s" % tier)


# ─── Spin Result Handler ───────────────────────────────────────────────────────

func _on_spin_completed(result: Dictionary) -> void:
	if not _is_spinning:
		print("[SlotMachineUI] spin_completed received but _is_spinning is false. Ignoring.")
		return

	var reward_type:   String = str(result.get("reward_type", ""))
	var reward_value:  int    = int(result.get("reward_value", 0))
	var reward_tier:   String = str(result.get("reward_tier", "small"))
	var was_intercepted: bool = bool(result.get("was_intercepted", false))

	var display_text: String
	match reward_type:
		"coins":
			display_text = "+%d Coins!" % reward_value
		"spins":
			display_text = "+%d Free Spins!" % reward_value
		"shield":
			display_text = "+%d Shield!" % reward_value
		"raid":
			display_text = "Raid! %d spots!" % reward_value
		"attack":
			display_text = "Attack! %d targets!" % reward_value
		_:
			display_text = "Spin Complete!"

	if was_intercepted:
		var comp: int = int(result.get("compensation_coins", 0))
		display_text = "Shields Full! +%d Coins" % comp

	_result_label.text = display_text
	_play_reveal_animation(reward_tier)

	await get_tree().create_timer(REEL_SPIN_DURATION + REVEAL_DURATION).timeout
	_finalize_spin_complete()


func _finalize_spin_complete() -> void:
	_is_spinning = false
	_update_button_state()
	print("[SlotMachineUI] Outcome displayed. Button unlocked.")


# ─── Other Signal Callbacks ────────────────────────────────────────────────────

func _on_spin_failed(required: int, available: int) -> void:
	_is_spinning = false
	_result_label.text = "Need %d spins!" % required
	_spin_button.disabled = true
	print("[SlotMachineUI] Spin failed — insufficient spins (need %d, have %d)." % [required, available])


func _on_raid_triggered(_raid_count: int) -> void:
	print("[SlotMachineUI] Raid triggered! Count: %d" % _raid_count)


func _on_attack_triggered(_attack_count: int) -> void:
	print("[SlotMachineUI] Attack triggered! Count: %d" % _attack_count)


func _on_shield_overflow(compensation: int) -> void:
	print("[SlotMachineUI] Shield overflow intercepted. Compensation: %d coins." % compensation)


# ─── Button State ──────────────────────────────────────────────────────────────

func _update_button_state() -> void:
	var slot_logic: SlotMachineLogic = _find_slot_logic()
	if slot_logic != null and slot_logic.can_spin(1):
		_spin_button.disabled = false
	else:
		_spin_button.disabled = true


func _find_slot_logic() -> SlotMachineLogic:
	return SlotMachineLogic.get_instance()
