# ==============================================================================
# Main.gd
# Path: res://src/core/Main.gd
# Role: Minimal scene entry point and cross-system signal orchestrator.
# All game logic lives in dedicated subsystems. This file only wires them.
# ==============================================================================
extends Node2D

# References to overlay nodes on the scene tree.
var _attack_overlay: Control = null
var _raid_overlay: Control = null
var _chest_overlay: Control = null
var _settings_modal: Control = null

var slot_machine_logic: SlotMachineLogic
var npc_simulator: NPCSimulator
var slot_machine_ui: SlotMachineUI
var card_manager: CardManager

# Cached pending values from SlotMachineLogic signals.
# These are captured when signals fire during spin_reels(),
# then consumed in _on_slot_result after animation completes.
var _pending_attack_count: int = 0
var _pending_raid_count: int = 0
var _pending_spin_result: Dictionary = {}


func _ready() -> void:
	print("[Main] CoinMaster booting...")

	add_to_group("main")

	# ── 1. SlotMachineLogic ──────────────────────────────────────────────────────
	slot_machine_logic = SlotMachineLogic.new()
	slot_machine_logic.name = "SlotMachineLogic"
	add_child(slot_machine_logic)
	print("[Main] SlotMachineLogic instantiated.")

	# ── 2. NPCSimulator ─────────────────────────────────────────────────────────
	npc_simulator = NPCSimulator.new()
	npc_simulator.name = "NPCSimulator"
	add_child(npc_simulator)
	print("[Main] NPCSimulator instantiated.")

	# ── 3. SlotMachinePanel (UI scene) ─────────────────────────────────────────
	var panel_scene: PackedScene = load("res://src/ui/SlotMachinePanel.tscn")
	if panel_scene != null:
		slot_machine_ui = panel_scene.instantiate() as SlotMachineUI
		if slot_machine_ui != null:
			$HUDCanvas.add_child(slot_machine_ui)
			slot_machine_ui.all_reels_stopped.connect(_on_slot_result)
			print("[Main] SlotMachinePanel loaded.")
		else:
			push_error("[Main] Failed to instantiate SlotMachinePanel.")
	else:
		push_error("[Main] SlotMachinePanel.tscn not found.")

	# ── 4. CardManager ─────────────────────────────────────────────────────────
	card_manager = CardManager.new()
	card_manager.name = "CardManager"
	add_child(card_manager)
	print("[Main] CardManager instantiated.")

	# ── 5. Event System ────────────────────────────────────────────────────────
	EventManager.register_event(Event_CoinCraze.new())
	EventManager.register_event(Event_VikingQuest.new())
	print("[Main] Events registered.")

	# ── 6. SaveLoadManager ─────────────────────────────────────────────────────
	SaveLoadManager.game_loaded.connect(_on_save_game_loaded)
	EventManager.all_events_checked.connect(func(_active_ids): _update_event_ui())

	# ── 7. Trainer Console → LayerTrainer (layer 99) ────────────────────────────
	var trainer_scene: PackedScene = load("res://src/ui/TrainerConsole/TrainerConsole.tscn")
	if trainer_scene != null:
		var trainer: Node = trainer_scene.instantiate()
		if trainer != null:
			var layer_trainer: CanvasLayer = get_node_or_null("LayerTrainer")
			if layer_trainer != null:
				layer_trainer.add_child(trainer)
			else:
				add_child(trainer)
			print("[Main] TrainerConsole instantiated on LayerTrainer.")
		else:
			push_warning("[Main] TrainerConsole.tscn returned null.")
	else:
		push_warning("[Main] TrainerConsole.tscn not found — skipping trainer.")

	# ── 8. Cache overlay references ─────────────────────────────────────────────
	_attack_overlay = get_node_or_null("LayerOverlays/AttackOverlay")
	_raid_overlay   = get_node_or_null("LayerOverlays/RaidOverlay")
	_chest_overlay  = get_node_or_null("LayerOverlays/ChestOpenOverlay")
	_settings_modal = get_node_or_null("LayerOverlays/SettingsModal")

	if _attack_overlay != null: _attack_overlay.visible = false
	if _raid_overlay   != null: _raid_overlay.visible   = false
	if _chest_overlay  != null: _chest_overlay.visible  = false
	if _settings_modal != null: _settings_modal.visible = false

	# ── 9. Wire SlotMachineLogic signals ───────────────────────────────────────
	# Note: We NO LONGER connect attack_triggered/raid_triggered here
	# to prevent them from showing up before the animation ends.
	# Logic outcomes are handled in _on_slot_result instead.

	# ── 10. Wire NPCSimulator signals ────────────────────────────────────────────
	if npc_simulator != null:
		npc_simulator.live_attack_resolved.connect(_on_live_attack_resolved)
		npc_simulator.raid_target_generated.connect(_on_raid_target_generated)

	# ── 11. Event container ─────────────────────────────────────────────────────
	var event_container: VBoxContainer = VBoxContainer.new()
	event_container.name = "EventContainer"
	event_container.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE, 20)
	event_container.custom_minimum_size = Vector2(200, 0)
	event_container.offset_left = 20
	event_container.offset_top = 100
	$HUDCanvas.add_child(event_container)

	_update_event_ui()
	print("[Main] CoinMaster ready.")


func _update_event_ui() -> void:
	var container: VBoxContainer = $HUDCanvas.get_node_or_null("EventContainer")
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
	for event_id in SaveLoadManager.event_flags.keys():
		var flags: Dictionary = SaveLoadManager.event_flags[event_id]
		if bool(flags.get("is_active", false)):
			var label: Label = Label.new()
			label.text = "EVENT: " + event_id.to_upper()
			label.add_theme_color_override("font_color", Color.GOLD)
			container.add_child(label)


func _on_save_game_loaded() -> void:
	if npc_simulator != null:
		npc_simulator.calculate_offline_events()


# ─── SlotMachineLogic signal handlers ────────────────────────────────────────
# These fire DURING spin_reels(), before animation completes.
# We cache the values and defer overlay display to _on_slot_result.

func _on_attack_triggered(attack_count: int) -> void:
	_pending_attack_count = attack_count
	print("[Main] Attack triggered (%d phases) — deferring overlay until animation ends." % attack_count)


func _on_raid_triggered(raid_count: int) -> void:
	_pending_raid_count = raid_count
	print("[Main] Raid triggered (%d slots) — deferring overlay until animation ends." % raid_count)


# ─── SlotMachineUI signal handler ───────────────────────────────────────────
# Fires AFTER animation completes. Here we show overlays using cached data.

func _on_slot_result(result: Dictionary) -> void:
	_pending_spin_result = result
	var reward_type: String = str(result.get("reward_type", ""))

	match reward_type:
		"attack":
			var attack_phases = result.get("attack_phases", 1)
			if attack_phases > 0 and npc_simulator != null:
				npc_simulator.on_live_attack_triggered(attack_phases)
			# Show attack overlay.
			if _attack_overlay != null and _attack_overlay.has_method("show_attack"):
				_attack_overlay.show_attack(result)

		"raid":
			var raid_slots = result.get("raid_dig_slots", 3)
			if raid_slots > 0 and npc_simulator != null:
				npc_simulator.generate_raid_target()
			# Show raid overlay.
			if _raid_overlay != null and _raid_overlay.has_method("show_raid"):
				_raid_overlay.show_raid(result)

		"coins", "spins", "shield":
			pass  # SaveLoadManager already updated; TopBarHUD reacts via signal.

		_:
			push_warning("[Main] Unknown slot reward_type: '%s'" % reward_type)

	_pending_spin_result = {}


# ─── NPCSimulator signal handlers ────────────────────────────────────────────

func _on_live_attack_resolved(data: Dictionary) -> void:
	var npc_name: String = str(data.get("npc_name", "Unknown"))
	_show_notification("ATTACKED %s! Building damaged!" % npc_name)


func _on_raid_target_generated(target: Dictionary) -> void:
	pass  # RaidOverlay has its own handler wired here if needed.


# ─── Utility ─────────────────────────────────────────────────────────────────

func _show_notification(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.ORANGE_RED)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 50)
	label.offset_top -= 150
	$HUDCanvas.add_child(label)

	var tween: Tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.5).from(0.0)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.finished.connect(label.queue_free)
