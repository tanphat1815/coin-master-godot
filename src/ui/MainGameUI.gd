# ==============================================================================
# MainGameUI.gd
# Path: res://src/ui/MainGameUI.gd
# Role: Root scene controller and signal router.
# Wires SlotMachineUI spin results to overlay systems.
# All logic/math stays in core systems — this file only routes signals.
# ==============================================================================
class_name MainGameUI
extends Node2D

## Reference to the slot machine UI node (BottomFooter).
var _slot_ui: SlotMachineUI = null

## Reference to the top bar HUD.
var _top_bar: Control = null

## References to overlay nodes.
var _attack_overlay: Control = null
var _raid_overlay: Control = null
var _chest_overlay: Control = null
var _settings_modal: Control = null

## Reference to the bottom footer (contains SlotMachineUI script).
var _bottom_footer: Control = null


func _ready() -> void:
	print("[MainGameUI] Initializing...")

	# Cache overlay references.
	_attack_overlay = _find_child("AttackOverlay")
	_raid_overlay   = _find_child("RaidOverlay")
	_chest_overlay  = _find_child("ChestOpenOverlay")
	_settings_modal = _find_child("SettingsModal")
	_bottom_footer  = _find_child("BottomFooter")

	# Cache slot UI (BottomFooter carries SlotMachineUI script).
	if _bottom_footer is SlotMachineUI:
		_slot_ui = _bottom_footer as SlotMachineUI
		_slot_ui.all_reels_stopped.connect(_on_slot_result)
		print("[MainGameUI] SlotMachineUI signal wired.")
	else:
		push_error("[MainGameUI] BottomFooter not found or not SlotMachineUI.")

	# Cache top bar.
	_top_bar = _find_child("TopBar")

	# Ensure overlays are hidden at start.
	if _attack_overlay != null:
		_attack_overlay.visible = false
	if _raid_overlay != null:
		_raid_overlay.visible = false
	if _chest_overlay != null:
		_chest_overlay.visible = false
	if _settings_modal != null:
		_settings_modal.visible = false

	# Wire NPCSimulator attack/raid signals to overlays.
	var npc_sim: Node = get_node_or_null("/root/Main/NPCSimulator")
	if npc_sim != null:
		npc_sim.live_attack_resolved.connect(_on_live_attack_resolved)
		npc_sim.raid_target_generated.connect(_on_raid_target_generated)

	print("[MainGameUI] Ready.")


func _find_child(name: String) -> Node:
	var result: Node = get_node_or_null(name)
	if result == null:
		result = get_node_or_null("LayerOverlays/" + name)
	if result == null:
		result = get_node_or_null("LayerHUD/" + name)
	return result


# ─── Slot Result Router ────────────────────────────────────────────────────────

func _on_slot_result(result: Dictionary) -> void:
	var reward_type: String = str(result.get("reward_type", ""))

	match reward_type:
		"attack":
			_show_attack_overlay(result)
		"raid":
			_show_raid_overlay(result)
		"coins", "spins", "shield":
			pass  # SaveLoadManager already updated; TopBarHUD reacts via signal.
		_:
			push_warning("[MainGameUI] Unknown slot reward_type: '%s'" % reward_type)


# ─── Attack Overlay ────────────────────────────────────────────────────────────

func _show_attack_overlay(result: Dictionary) -> void:
	if _attack_overlay == null:
		push_warning("[MainGameUI] AttackOverlay not found.")
		return
	_attack_overlay.show_attack(result)


func _on_live_attack_resolved(_entry: Dictionary) -> void:
	pass  # TopBar already updated via SaveLoadManager signal.


# ─── Raid Overlay ──────────────────────────────────────────────────────────────

func _show_raid_overlay(result: Dictionary) -> void:
	if _raid_overlay == null:
		push_warning("[MainGameUI] RaidOverlay not found.")
		return
	_raid_overlay.show_raid(result)


func _on_raid_target_generated(_target: Dictionary) -> void:
	pass  # RaidOverlay receives the signal directly.


# ─── Chest Overlay ────────────────────────────────────────────────────────────

func show_chest_overlay() -> void:
	if _chest_overlay == null:
		push_warning("[MainGameUI] ChestOpenOverlay not found.")
		return
	_chest_overlay.visible = true
	if _chest_overlay.has_method("start_chest_animation"):
		_chest_overlay.start_chest_animation()


# ─── Settings Modal ───────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if _settings_modal != null and _settings_modal.visible:
				_settings_modal.visible = false
