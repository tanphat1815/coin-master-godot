# ==============================================================================
# Main.gd
# Path: res://src/core/Main.gd
# Role: Minimal scene entry point and cross-system signal orchestrator.
# All game logic lives in dedicated subsystems. This file only wires them.
# ==============================================================================
extends Node2D

var slot_machine_logic: SlotMachineLogic
var npc_simulator: NPCSimulator
var slot_machine_ui: SlotMachineUI
var card_manager: CardManager


func _ready() -> void:
	print("[Main] CoinMaster booting...")

	add_to_group("main")

	# ── 1. Instantiate and add SlotMachineLogic ──────────────────────────────────
	slot_machine_logic = SlotMachineLogic.new()
	slot_machine_logic.name = "SlotMachineLogic"
	add_child(slot_machine_logic)
	print("[Main] SlotMachineLogic instantiated.")

	# ── 2. Instantiate and add NPCSimulator ─────────────────────────────────────
	npc_simulator = NPCSimulator.new()
	npc_simulator.name = "NPCSimulator"
	add_child(npc_simulator)
	print("[Main] NPCSimulator instantiated.")

	# ── 3. Add SlotMachinePanel (UI scene) ────────────────────────────────────
	var panel_scene: PackedScene = load("res://src/ui/SlotMachinePanel.tscn")
	if panel_scene != null:
		slot_machine_ui = panel_scene.instantiate() as SlotMachineUI
		if slot_machine_ui != null:
			$HUDCanvas.add_child(slot_machine_ui)
			print("[Main] SlotMachinePanel loaded.")
		else:
			push_error("[Main] Failed to instantiate SlotMachinePanel.")
	else:
		push_error("[Main] SlotMachinePanel.tscn not found at res://src/ui/SlotMachinePanel.tscn.")

	# ── 4. Card Manager ────────────────────────────────────────────────────────
	card_manager = CardManager.new()
	card_manager.name = "CardManager"
	add_child(card_manager)
	print("[Main] CardManager instantiated.")

	# ── 5. Event System (Step 7 + Step 8) ─────────────────────────────────────
	EventManager.register_event(Event_CoinCraze.new())

	var viking_quest: Event_VikingQuest = Event_VikingQuest.new()
	EventManager.register_event(viking_quest)

	print("[Main] Events registered.")

	# ── 6. Wire SaveLoadManager → NPCSimulator ─────────────────────────────
	SaveLoadManager.game_loaded.connect(_on_save_game_loaded)
	EventManager.all_events_checked.connect(func(_active_ids): _update_event_ui())

	# ── 7. Trainer Console ─────────────────────────────────────────────────────
	# Wrapped in preprocessor guard — only compiles in non-production builds.
	var trainer_scene: PackedScene = load("res://src/ui/TrainerConsole/TrainerConsole.tscn")
	if trainer_scene != null:
		var trainer: Node = trainer_scene.instantiate()
		if trainer != null:
			add_child(trainer)
			print("[Main] TrainerConsole instantiated.")
		else:
			push_warning("[Main] TrainerConsole.tscn returned null from instantiate().")
	else:
		push_warning("[Main] TrainerConsole.tscn not found — skipping trainer.")

	# ── 8. Wire Logic Signals ────────────────────────────────────────────────────
	if slot_machine_logic != null:
		slot_machine_logic.raid_triggered.connect(_on_raid_triggered)
		slot_machine_logic.attack_triggered.connect(_on_attack_triggered)
	
	if npc_simulator != null:
		npc_simulator.live_attack_resolved.connect(_on_live_attack_resolved)

	var event_container: VBoxContainer = VBoxContainer.new()
	event_container.name = "EventContainer"
	event_container.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE, 20)
	event_container.custom_minimum_size = Vector2(200, 0)
	event_container.offset_left = 20
	event_container.offset_top = 100 # Below the top HUD if any
	$HUDCanvas.add_child(event_container)
	
	# Initial event status check
	_update_event_ui()
	
	print("[Main] CoinMaster ready.")


func _update_event_ui() -> void:
	var container: VBoxContainer = $HUDCanvas.get_node_or_null("EventContainer")
	if container == null: return
	
	# Clear existing
	for child in container.get_children():
		child.queue_free()
		
	# Check active events
	for event_id in SaveLoadManager.event_flags.keys():
		var flags: Dictionary = SaveLoadManager.event_flags[event_id]
		if bool(flags.get("is_active", false)):
			var label: Label = Label.new()
			label.text = "🔥 EVENT: " + event_id.to_upper()
			label.add_theme_color_override("font_color", Color.GOLD)
			container.add_child(label)


func _on_save_game_loaded() -> void:
	if npc_simulator != null:
		npc_simulator.calculate_offline_events()


func _on_raid_triggered(_raid_count: int) -> void:
	if npc_simulator != null:
		npc_simulator.generate_raid_target()
	_show_notification("🐷 RAID TRIGGERED! Finding target...")


func _on_attack_triggered(_attack_count: int) -> void:
	if npc_simulator != null:
		npc_simulator.on_live_attack_triggered(_attack_count)


func _on_live_attack_resolved(data: Dictionary) -> void:
	var msg: String = "⚔️ ATTACKED %s!\nBuilding %d damaged!" % [data["npc_name"], data["target_item_index"]]
	_show_notification(msg)


func _show_notification(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.ORANGE_RED)
	
	# Position at bottom center
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 50)
	label.offset_top -= 150
	
	$HUDCanvas.add_child(label)
	
	# Animate and remove
	var tween: Tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.5).from(0.0)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.finished.connect(label.queue_free)
