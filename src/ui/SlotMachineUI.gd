# ==============================================================================
# SlotMachineUI.gd
# Role: Infinite vertical scroll animation for Coin Master style slot machine.
# ==============================================================================
extends Control
class_name SlotMachineUI

signal spin_failed_insufficient_spins
signal all_reels_stopped(result: Dictionary)

## All valid Super Bet multiplier tiers in ascending order.
## Tiers are skipped if SaveLoadManager.spins < tier value.
const BET_TIERS: Array[int] = [1, 2, 3, 5, 10]

var _reels: Array[Control] = []
var _icons_containers: Array[Control] = []
var _pending_result: Dictionary = {}
var _is_spinning: bool = false
var _slot_logic: SlotMachineLogic

## Index into BET_TIERS pointing to the currently selected multiplier.
## Default 0 = x1. Resets to 0 on game restart (not persisted).
var _current_tier_index: int = 0

## Cached reference to the Bet multiplier toggle button node.
var _bet_button: Button = null

## Cached reference to a label showing the active multiplier above the reel area.
var _bet_display_label: Label = null

var _tex_coin   = preload("res://assets/sprites/ui/coin.svg")
var _tex_energy = preload("res://assets/sprites/ui/energy.svg")
var _tex_shield = preload("res://assets/sprites/ui/shield.svg")
var _tex_attack = preload("res://assets/sprites/ui/attack.svg")
var _tex_raid   = preload("res://assets/sprites/ui/raid.svg")

@onready var _spin_button: Button = $MainFrame/SpinBtn
@onready var _result_label: Label = $MainFrame/ResultLabel

func _ready() -> void:
	_reels.clear()
	_icons_containers.clear()
	for i in range(1, 4):
		var reel = get_node("MainFrame/ReelArea/ReelContainer/Reel%d" % i)
		var container = reel.get_node("Icons")
		_reels.append(reel)
		_icons_containers.append(container)
		_setup_initial_icons(container)

	_result_label.text = "Spin to play!"
	_result_label.pivot_offset = _result_label.size / 2.0
	_spin_button.pressed.connect(_on_spin_button_pressed)

	_slot_logic = SlotMachineLogic.get_instance()
	if _slot_logic != null:
		_slot_logic.spin_completed.connect(_on_spin_completed)
		_slot_logic.spin_failed_insufficient_spins.connect(_on_spin_failed)

	# Cache bet multiplier nodes.
	_bet_button = get_node_or_null("MainFrame/BetBtn") as Button
	_bet_display_label = get_node_or_null("MainFrame/BetMultiplierLabel") as Label

	if _bet_button != null:
		_bet_button.pressed.connect(_on_bet_button_pressed)
	else:
		push_warning("[SlotMachineUI] BetBtn not found in scene.")

	if _bet_display_label == null:
		push_warning("[SlotMachineUI] BetMultiplierLabel not found. Multiplier display disabled.")

	# Subscribe to spins_changed to re-evaluate tier availability.
	SaveLoadManager.spins_changed.connect(_on_spins_changed)

	_update_bet_button_display()
	_update_button_state()


func _setup_initial_icons(container: Control) -> void:
	var textures = [_tex_coin, _tex_energy, _tex_shield, _tex_attack, _tex_raid]
	container.get_node("IconTop").texture = textures.pick_random()
	container.get_node("IconMid").texture = textures.pick_random()
	container.get_node("IconBot").texture = textures.pick_random()
	container.position.y = 0


func _on_spin_button_pressed() -> void:
	if _is_spinning: return
	var active_multiplier: int = BET_TIERS[_current_tier_index]
	if _slot_logic != null and _slot_logic.can_spin(active_multiplier):
		_result_label.text = "SPINNING..."
		_slot_logic.spin_reels(active_multiplier)
	else:
		_result_label.text = "NOT ENOUGH SPINS!"


func _on_spin_completed(result: Dictionary) -> void:
	_pending_result = result
	_play_spin_animation()


func _play_spin_animation() -> void:
	_is_spinning = true
	_update_button_state()

	var stop_flags = [false, false, false]

	_scroll_reel(0, stop_flags)
	_scroll_reel(1, stop_flags)
	_scroll_reel(2, stop_flags)

	await get_tree().create_timer(1.2).timeout
	stop_flags[0] = true
	await get_tree().create_timer(0.6).timeout
	stop_flags[1] = true
	await get_tree().create_timer(0.6).timeout
	stop_flags[2] = true


func _scroll_reel(index: int, stop_flags: Array) -> void:
	var container = _icons_containers[index]
	var textures = [_tex_coin, _tex_energy, _tex_shield, _tex_attack, _tex_raid]
	var target_tex = _get_texture_for_type(_pending_result["reward_type"])

	var speed = 2200.0

	while true:
		var delta = get_process_delta_time()
		if delta == 0: delta = 1.0/60.0

		container.position.y += speed * delta

		if container.position.y >= 100.0:
			container.position.y -= 100.0
			container.get_node("IconBot").texture = container.get_node("IconMid").texture
			container.get_node("IconMid").texture = container.get_node("IconTop").texture

			if stop_flags[index]:
				container.get_node("IconMid").texture = target_tex
				container.position.y = 0
				_play_stop_bounce(container)
				break
			else:
				container.get_node("IconTop").texture = textures.pick_random()

		await get_tree().process_frame

	if index == 2:
		_finalize_spin_visuals()


func _play_stop_bounce(container: Control) -> void:
	var tween = create_tween()
	container.position.y = -40
	tween.tween_property(container, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _finalize_spin_visuals() -> void:
	_is_spinning = false
	_update_button_state()

	var reward_type: String   = str(_pending_result.get("reward_type", ""))
	var reward_value: int     = int(_pending_result.get("reward_value", 0))
	var was_intercepted: bool = bool(_pending_result.get("was_intercepted", false))
	var attack_phases: int   = int(_pending_result.get("attack_phases", 0))
	var raid_dig_slots: int  = int(_pending_result.get("raid_dig_slots", 0))
	var bet_applied: int     = int(_pending_result.get("bet_multiplier_applied", 1))

	var display_text: String
	match reward_type:
		"coins":
			display_text = "+%d Coins!" % reward_value
			if bet_applied > 1:
				display_text += " (x%d BET)" % bet_applied
		"spins":
			display_text = "+%d Free Spins!" % reward_value
		"shield":
			if was_intercepted:
				display_text = "Shields Full! +%d Coins" % int(_pending_result.get("compensation_coins", 0))
			else:
				display_text = "+%d Shield%s!" % [reward_value, "s" if reward_value > 1 else ""]
		"raid":
			display_text = "RAID! %d Dig Slot%s!" % [raid_dig_slots, "s" if raid_dig_slots > 1 else ""]
		"attack":
			display_text = "ATTACK! x%d TREASURE!" % bet_applied
		_:
			display_text = "Spin Complete!"

	_result_label.text = display_text

	all_reels_stopped.emit(_pending_result)

	_result_label.scale = Vector2(0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(_result_label, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_ELASTIC)


func _get_texture_for_type(type: String) -> Texture2D:
	match type:
		"coins": return _tex_coin
		"spins": return _tex_energy
		"shield": return _tex_shield
		"attack": return _tex_attack
		"raid": return _tex_raid
	return _tex_coin


func _update_button_state() -> void:
	_spin_button.disabled = _is_spinning
	_spin_button.modulate = Color(0.6, 0.6, 0.6) if _is_spinning else Color.WHITE


func _on_bet_button_pressed() -> void:
	var start_index: int = _current_tier_index
	var next_index: int = (start_index + 1) % BET_TIERS.size()

	var steps: int = 0
	while steps < BET_TIERS.size():
		if _is_tier_available(next_index):
			_current_tier_index = next_index
			break
		next_index = (next_index + 1) % BET_TIERS.size()
		steps += 1

	if steps >= BET_TIERS.size():
		_current_tier_index = 0

	_update_bet_button_display()
	print("[SlotMachineUI] Bet tier changed to x%d." % BET_TIERS[_current_tier_index])


func _is_tier_available(tier_index: int) -> bool:
	if tier_index < 0 or tier_index >= BET_TIERS.size():
		return false
	return SaveLoadManager.spins >= BET_TIERS[tier_index]


func _update_bet_button_display() -> void:
	if not _is_tier_available(_current_tier_index):
		_auto_downgrade_tier()

	var active_multiplier: int = BET_TIERS[_current_tier_index]

	if _bet_button != null:
		_bet_button.text = "BET x%d" % active_multiplier

		var tier_color: Color
		match active_multiplier:
			1:
				tier_color = Color(1.0, 1.0, 1.0)
			2, 3:
				tier_color = Color(1.0, 0.9, 0.2)
			5:
				tier_color = Color(1.0, 0.6, 0.1)
			10:
				tier_color = Color(1.0, 0.2, 0.2)
			_:
				tier_color = Color(1.0, 1.0, 1.0)

		_bet_button.add_theme_color_override("font_color", tier_color)

	if _bet_display_label != null:
		_bet_display_label.text = "BET: x%d" % active_multiplier
		_bet_display_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.0) if active_multiplier > 1 else Color(1.0, 1.0, 1.0))


func _auto_downgrade_tier() -> void:
	var original_tier: int = BET_TIERS[_current_tier_index]

	for i in range(_current_tier_index, -1, -1):
		if _is_tier_available(i):
			if i != _current_tier_index:
				print("[SlotMachineUI] Bet auto-downgraded from x%d to x%d (insufficient spins)." % [
					original_tier, BET_TIERS[i]
				])
			_current_tier_index = i
			return

	_current_tier_index = 0


func _on_spins_changed(_new_spin_count: int) -> void:
	_update_bet_button_display()
	_update_button_state()


func _on_spin_failed(required: int, available: int) -> void:
	_result_label.text = "NOT ENOUGH SPINS! (%d/%d)" % [available, required]
	_is_spinning = false
	_update_button_state()
	
	var tween = create_tween()
	tween.tween_property(_result_label, "position:x", _result_label.position.x + 10, 0.05)
	tween.tween_property(_result_label, "position:x", _result_label.position.x - 10, 0.05)
	tween.tween_property(_result_label, "position:x", _result_label.position.x, 0.05)
