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

var _tex_coin   = preload("res://assets/sprites/ui/coin.svg")
var _tex_energy = preload("res://assets/sprites/ui/energy.svg")
var _tex_shield = preload("res://assets/sprites/ui/shield.svg")
var _tex_attack = preload("res://assets/sprites/ui/attack.svg")
var _tex_raid   = preload("res://assets/sprites/ui/raid.svg")

var _spin_button: Button
var _reel1: CanvasItem
var _reel2: CanvasItem
var _reel3: CanvasItem
var _result_label: Label
var _is_spinning: bool = false
var _slot_logic: SlotMachineLogic

func _ready() -> void:
	# ── Cache node references ────────────────────────────────────────────────────
	_spin_button  = $MainFrame/SpinBtn
	_result_label = $MainFrame/ResultLabel
	_reel1       = $MainFrame/ReelArea/ReelContainer/Reel1
	_reel2       = $MainFrame/ReelArea/ReelContainer/Reel2
	_reel3       = $MainFrame/ReelArea/ReelContainer/Reel3
	
	if _spin_button == null:
		push_error("[SlotMachineUI] SpinButton not found at new path.")
		return
	if _reel1 == null or _reel2 == null or _reel3 == null:
		push_error("[SlotMachineUI] One or more reel nodes not found at new paths.")
		return
	
	# ── Initialize visual state ──────────────────────────────────────────────────
	_result_label.text = "Spin to play!"
	_result_label.modulate = Color.WHITE
	_result_label.pivot_offset = _result_label.size / 2.0

	# ── Wire button press ───────────────────────────────────────────────────────
	_spin_button.pressed.connect(_on_spin_button_pressed)

	# ── Subscribe to SlotMachineLogic signals ───────────────────────────────────
	_slot_logic = SlotMachineLogic.get_instance()
	if _slot_logic != null:
		_slot_logic.spin_completed.connect(_on_spin_completed)
		_slot_logic.spin_failed_insufficient_spins.connect(_on_spin_failed)
		print("[SlotMachineUI] Connected to SlotMachineLogic signals.")
	else:
		push_error("[SlotMachineUI] SlotMachineLogic node not found.")

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
	# We want reels to start at the same time, but each reel to follow its own sequence.
	# So we create one tween and use parallel for the first movement of each reel.
	var tween: Tween = create_tween()
	var reel_y_offset: float = 40.0

	# Reel 1
	tween.tween_property(_reel1, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_reel1, "position:y", -reel_y_offset, REEL_SPIN_DURATION * 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_reel1, "position:y", 0.0, REEL_SPIN_DURATION * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Reel 2 (Start parallel to Reel 1)
	tween.parallel().tween_property(_reel2, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_reel2, "position:y", -reel_y_offset, REEL_SPIN_DURATION * 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_reel2, "position:y", 0.0, REEL_SPIN_DURATION * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Reel 3 (Start parallel to Reel 1)
	tween.parallel().tween_property(_reel3, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_reel3, "position:y", -reel_y_offset, REEL_SPIN_DURATION * 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_reel3, "position:y", 0.0, REEL_SPIN_DURATION * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Result label pulse while spinning
	var pulse_tween: Tween = create_tween().set_loops()
	pulse_tween.tween_property(_result_label, "modulate:a", 0.3, 0.3)
	pulse_tween.tween_property(_result_label, "modulate:a", 1.0, 0.3)
	
	# Stop pulse when main tween finishes
	tween.finished.connect(func(): pulse_tween.kill(); _result_label.modulate.a = 1.0)

	print("[SlotMachineUI] Spin animation started. Duration: %.1fs." % REEL_SPIN_DURATION)


func _play_reveal_animation(result: Dictionary) -> void:
	var reward_type: String = str(result.get("reward_type", "coins"))
	var tier: String = str(result.get("reward_tier", "small"))
	
	var target_color: Color = Color.WHITE
	var texture: Texture2D = _tex_coin
	
	match reward_type:
		"coins":
			target_color = Color(1.0, 1.0, 0.9)
			texture = _tex_coin
		"spins":
			target_color = Color(0.9, 0.9, 1.0)
			texture = _tex_energy
		"shield":
			target_color = Color(0.95, 0.95, 1.0)
			texture = _tex_shield
		"attack":
			target_color = Color(1.0, 0.9, 0.9)
			texture = _tex_attack
		"raid":
			target_color = Color(1.0, 0.9, 1.0)
			texture = _tex_raid

	# Update Reels
	for reel in [_reel1, _reel2, _reel3]:
		reel.color = target_color
		var icon_rect = reel.get_node_or_null("Icon")
		if icon_rect:
			icon_rect.texture = texture

	# Scale pop for the result label
	var scale_tween: Tween = create_tween()
	scale_tween.tween_property(_result_label, "scale", Vector2(1.2, 1.2), REVEAL_DURATION * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(_result_label, "scale", Vector2(1.0, 1.0), REVEAL_DURATION * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	# Color flash for the result label
	var flash_color: Color = Color.WHITE
	if tier == "large" or tier == "jackpot": flash_color = Color.GOLD
	
	var color_tween: Tween = create_tween()
	color_tween.set_parallel(true)
	color_tween.tween_property(_result_label, "modulate", flash_color, REVEAL_DURATION * 0.3)
	color_tween.tween_property(_result_label, "modulate", Color.WHITE, REVEAL_DURATION * 0.7)

	print("[SlotMachineUI] Reveal animation played. Reward: %s (%s)" % [reward_type, tier])


# ─── Spin Result Handler ───────────────────────────────────────────────────────

func _on_spin_completed(result: Dictionary) -> void:
	if not _is_spinning:
		print("[SlotMachineUI] spin_completed received but _is_spinning is false. Ignoring.")
		return

	var reward_type:   String = str(result.get("reward_type", ""))
	var reward_value:  int    = int(result.get("reward_value", 0))
	# reward_tier and was_intercepted are used implicitly or can be underscored if needed
	var _reward_tier:  String = str(result.get("reward_tier", "small"))
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
	_play_reveal_animation(result)

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
