# ==============================================================================
# AttackOverlayUI.gd
# Path: res://src/ui/AttackOverlayUI.gd
# Role: Attack minigame overlay — screen flash, NPC village view, impact shake.
# ZERO game math. All data flows in via show_attack() calls only.
# ==============================================================================
class_name AttackOverlayUI
extends Control

var _flash: ColorRect
var _backdrop: ColorRect
var _result_label: Label
var _village_view: TextureRect

## Internal state for the current attack.
var _current_result: Dictionary = {}


func _ready() -> void:
	# Find child nodes.
	_backdrop    = get_node_or_null("Backdrop") as ColorRect
	_village_view = get_node_or_null("VillageView") as TextureRect
	_result_label = get_node_or_null("ResultLabel") as Label

	if _backdrop == null:
		push_error("[AttackOverlayUI] Backdrop ColorRect not found.")
	if _result_label == null:
		push_error("[AttackOverlayUI] ResultLabel not found.")

	visible = false
	print("[AttackOverlayUI] Ready.")


## Called by MainGameUI when a spin lands on "attack".
func show_attack(result: Dictionary) -> void:
	_current_result = result
	_start_flash_phase()


func _start_flash_phase() -> void:
	# Phase 1: Screen flash — white overlay, fade out.
	var flash: ColorRect = ColorRect.new()
	flash.color = Color(1.0, 1.0, 1.0, 0.85)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	var tween: Tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_EXPO)
	tween.tween_callback(flash.queue_free)
	await tween.finished

	_start_overlay_phase()


func _start_overlay_phase() -> void:
	# Phase 2: Show the attack overlay.
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	await tween.finished

	_populate_village_view()


func _populate_village_view() -> void:
	# Phase 3: Fetch village/NPC data from NPCSimulator and update UI.
	var npc_sim: Node = get_node_or_null("/root/Main/NPCSimulator")
	if npc_sim != null and npc_sim.has_method("generate_attack_target"):
		var target: Dictionary = npc_sim.generate_attack_target()
		var npc_name: String = str(target.get("npc_name", "Unknown"))
		var loot_text: String = ""

		var bet_applied: int = int(_current_result.get("bet_multiplier_applied", 1))
		if bet_applied > 1:
			loot_text = "x%d TREASURE!" % bet_applied
		else:
			loot_text = "Attack!"

		if _result_label != null:
			_result_label.text = loot_text

		# Placeholder: village texture would be loaded from target.get("texture_path", ...)
		# For now, set a tinted color to indicate village.
		if _village_view != null:
			_village_view.modulate = Color(0.8, 0.5, 0.5, 1.0)

		await get_tree().create_timer(0.5).timeout
		_trigger_impact_shake()
	else:
		# No NPCSimulator — just show generic attack.
		if _result_label != null:
			_result_label.text = "ATTACK!"
		await get_tree().create_timer(1.5).timeout
		_dismiss_overlay()


func _trigger_impact_shake() -> void:
	# Phase 4: Camera-style shake on the village view.
	if _village_view == null:
		await get_tree().create_timer(1.0).timeout
		_dismiss_overlay()
		return

	var original_pos: Vector2 = _village_view.position
	var intensity: float = 14.0
	var duration: float = 0.5
	var iterations: int = int(duration / 0.05)

	var tween: Tween = create_tween()
	tween.set_loops(iterations)
	tween.tween_property(_village_view, "position",
		original_pos + Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)),
		0.05).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): _village_view.position = original_pos)

	await get_tree().create_timer(duration).timeout
	_dismiss_overlay()


func _dismiss_overlay() -> void:
	# Phase 5: Fade out and hide.
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
	_current_result = {}
	print("[AttackOverlayUI] Attack overlay dismissed.")
