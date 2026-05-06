# ==============================================================================
# SlotMachineUI.gd
# Role: Infinite vertical scroll animation for Coin Master style slot machine.
# ==============================================================================
extends Control
class_name SlotMachineUI

signal spin_failed_insufficient_spins
signal all_reels_stopped(result: Dictionary)

var _reels: Array[Control] = []
var _icons_containers: Array[Control] = []
var _pending_result: Dictionary = {}
var _is_spinning: bool = false
var _slot_logic: SlotMachineLogic

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
	
	_update_button_state()


func _setup_initial_icons(container: Control) -> void:
	var textures = [_tex_coin, _tex_energy, _tex_shield, _tex_attack, _tex_raid]
	container.get_node("IconTop").texture = textures.pick_random()
	container.get_node("IconMid").texture = textures.pick_random()
	container.get_node("IconBot").texture = textures.pick_random()
	container.position.y = 0


func _on_spin_button_pressed() -> void:
	if _is_spinning: return
	_result_label.text = "SPINNING..."
	# Passing 1 as default bet multiplier to match SlotMachineLogic requirements
	_slot_logic.spin_reels(1)


func _on_spin_completed(result: Dictionary) -> void:
	_pending_result = result
	_play_spin_animation()


func _play_spin_animation() -> void:
	_is_spinning = true
	_update_button_state()
	
	var stop_flags = [false, false, false]
	
	# Start scrolling for each reel
	_scroll_reel(0, stop_flags)
	_scroll_reel(1, stop_flags)
	_scroll_reel(2, stop_flags)
	
	# Staggered stop sequence
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
	
	var speed = 2200.0 # Fast spin speed
	
	while true:
		var delta = get_process_delta_time()
		if delta == 0: delta = 1.0/60.0
		
		container.position.y += speed * delta
		
		if container.position.y >= 100.0:
			container.position.y -= 100.0
			# Shift textures down: Top -> Mid, Mid -> Bot
			container.get_node("IconBot").texture = container.get_node("IconMid").texture
			container.get_node("IconMid").texture = container.get_node("IconTop").texture
			
			if stop_flags[index]:
				# Set final result to middle row and STOP
				container.get_node("IconMid").texture = target_tex
				container.position.y = 0
				_play_stop_bounce(container)
				break
			else:
				# Keep randomizing the top one for variety
				container.get_node("IconTop").texture = textures.pick_random()

		await get_tree().process_frame

	# When the last reel stops, show the final results
	if index == 2:
		_finalize_spin_visuals()


func _play_stop_bounce(container: Control) -> void:
	var tween = create_tween()
	container.position.y = -40
	tween.tween_property(container, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _finalize_spin_visuals() -> void:
	_is_spinning = false
	_update_button_state()
	
	var reward_type = _pending_result["reward_type"]
	var reward_value = _pending_result["reward_value"]
	var was_intercepted = _pending_result.get("was_intercepted", false)
	
	var msg = "+%d %s!" % [reward_value, reward_type.capitalize()]
	if was_intercepted:
		var comp = _pending_result.get("compensation_coins", 0)
		msg = "Shields Full! +%d Coins" % comp
		
	_result_label.text = msg
	
	# Emit signal so other systems (like Main.gd) can show notifications/events
	all_reels_stopped.emit(_pending_result)
	
	# Scale pulse victory effect
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


func _on_spin_failed(required: int, available: int) -> void:
	_result_label.text = "NOT ENOUGH SPINS! (%d/%d)" % [available, required]
	_is_spinning = false
	_update_button_state()
	
	var tween = create_tween()
	tween.tween_property(_result_label, "position:x", _result_label.position.x + 10, 0.05)
	tween.tween_property(_result_label, "position:x", _result_label.position.x - 10, 0.05)
	tween.tween_property(_result_label, "position:x", _result_label.position.x, 0.05)
