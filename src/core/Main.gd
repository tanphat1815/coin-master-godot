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


func _ready() -> void:
	print("[Main] CoinMaster booting...")

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
			add_child(slot_machine_ui)
			print("[Main] SlotMachinePanel loaded.")
		else:
			push_error("[Main] Failed to instantiate SlotMachinePanel.")
	else:
		push_error("[Main] SlotMachinePanel.tscn not found at res://src/ui/SlotMachinePanel.tscn.")

	# ── 4. Event System (Step 7) ─────────────────────────────────────────────
	EventManager.register_event(Event_CoinCraze.new())
	print("[Main] Events registered.")

	# ── 5. Wire SaveLoadManager → NPCSimulator ─────────────────────────────
	SaveLoadManager.game_loaded.connect(_on_save_game_loaded)

	# ── 6. Wire SlotMachineLogic → NPCSimulator ──────────────────────────────────
	if slot_machine_logic != null:
		slot_machine_logic.raid_triggered.connect(_on_raid_triggered)
		slot_machine_logic.attack_triggered.connect(_on_attack_triggered)

	print("[Main] CoinMaster ready.")


func _on_save_game_loaded() -> void:
	if npc_simulator != null:
		npc_simulator.calculate_offline_events()


func _on_raid_triggered(raid_count: int) -> void:
	if npc_simulator != null:
		npc_simulator.generate_raid_target()


func _on_attack_triggered(attack_count: int) -> void:
	if npc_simulator != null:
		npc_simulator.on_live_attack_triggered(attack_count)
