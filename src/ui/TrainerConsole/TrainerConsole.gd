# ==============================================================================
# TrainerConsole.gd
# Path: res://src/ui/TrainerConsole.gd
# Role: Developer Tools overlay for QA testing and balance validation.
# PRODUCTION BUILD GUARD: All implementation is wrapped in #ifndef PRODUCTION_BUILD.
# Strip from production using Godot's export filter or feature tags.
# ==============================================================================
class_name TrainerConsole
extends CanvasLayer

## Z-index layer — renders above all other UI.
const TRAINER_LAYER: int = 100

## Duration trainer-activated events last, in seconds (24 hours).
const TRAINER_EVENT_DURATION_SECONDS: int = 86400

## Input action name for toggling visibility.
const TOGGLE_ACTION: String = "ui_trainer_toggle"

## Wipe confirmation timeout in seconds.
const WIPE_CONFIRM_TIMEOUT: float = 5.0

## Reference to the root Panel node from TrainerPanel.tscn.
var _panel: Control = null

## Tracks whether the trainer panel is currently visible.
var _is_visible: bool = false

## Tracks whether a wipe is awaiting confirmation.
var _wipe_pending: bool = false

## Countdown timer for wipe auto-cancel.
var _wipe_timer: float = 0.0

## Cached list of valid outcome IDs for the RNG dropdown.
var _outcome_ids: Array[String] = []


#ifndef PRODUCTION_BUILD

func _ready() -> void:
	var scene_path: String = "res://src/ui/TrainerConsole/TrainerPanel.tscn"
	var packed_scene: PackedScene = load(scene_path)
	if packed_scene == null:
		push_error("[TrainerConsole] Cannot load TrainerPanel.tscn from '%s'." % scene_path)
		return

	var instance: Node = packed_scene.instantiate()
	if instance == null:
		push_error("[TrainerConsole] Cannot instantiate TrainerPanel.tscn.")
		return

	add_child(instance)
	_panel = instance as Control

	if _panel != null:
		_panel.visible = false
		_panel.z_index = TRAINER_LAYER
		_wire_all_signals()
		print("[TrainerConsole] Trainer panel loaded. Z-index: %d" % TRAINER_LAYER)
	else:
		push_error("[TrainerConsole] TrainerPanel root is not a Control node.")

	_populate_rng_dropdown()
	_update_all_status_labels()
	print("[TrainerConsole] Ready. Toggle: Ctrl+Shift+T")


func _wire_all_signals() -> void:
	if _panel == null:
		return

	# Title bar
	_wire(_panel, "panel_bg/margin/vbox/title_bar/close_button", _on_close_pressed)

	# Resource injection
	_wire(_panel, "panel_bg/margin/vbox/section_resources/res_grid/coin_add_btn", _on_inject_coins)
	_wire(_panel, "panel_bg/margin/vbox/section_resources/res_grid/spin_add_btn", _on_inject_spins)
	_wire(_panel, "panel_bg/margin/vbox/section_resources/res_grid/shield_add_btn", _on_inject_shields)

	# RNG override
	_wire(_panel, "panel_bg/margin/vbox/section_rng/rng_apply_btn", _on_rng_apply)

	# Events
	_wire(_panel, "panel_bg/margin/vbox/section_events/coin_craze_row/coin_craze_btn", _on_toggle_coin_craze)
	_wire(_panel, "panel_bg/margin/vbox/section_events/viking_quest_row/viking_quest_btn", _on_toggle_viking_quest)
	_wire(_panel, "panel_bg/margin/vbox/section_events/deactivate_all_btn", _on_deactivate_all_events)

	# Pets
	_wire(_panel, "panel_bg/margin/vbox/section_pets/foxy_row/foxy_btn", _on_activate_foxy)
	_wire(_panel, "panel_bg/margin/vbox/section_pets/tiger_row/tiger_btn", _on_activate_tiger)
	_wire(_panel, "panel_bg/margin/vbox/section_pets/rhino_row/rhino_btn", _on_activate_rhino)

	# Cards
	_wire(_panel, "panel_bg/margin/vbox/section_cards/chest_btn", _on_open_gold_chest)

	# Wipe
	_wire(_panel, "panel_bg/margin/vbox/section_save/wipe_btn", _on_wipe_save_pressed)


func _wire(root: Node, path: String, callable: Callable) -> void:
	var node: Node = root.get_node_or_null(path)
	if node is Button:
		(node as Button).pressed.connect(callable)
	elif node != null:
		push_warning("[TrainerConsole] Node at '%s' is not a Button: %s" % [path, node.get_class()])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		_toggle_visibility()


func _process(delta: float) -> void:
	if not _wipe_pending:
		return
	_wipe_timer -= delta
	if _wipe_timer <= 0.0:
		_cancel_wipe()


func _toggle_visibility() -> void:
	if _panel == null:
		return
	_is_visible = not _is_visible
	_panel.visible = _is_visible
	if _is_visible:
		_refresh_all_ui_values()
		print("[TrainerConsole] Opened.")
	else:
		_cancel_wipe()
		print("[TrainerConsole] Closed.")


func _on_close_pressed() -> void:
	if _is_visible:
		_toggle_visibility()


# ─── Resource Injection ───────────────────────────────────────────────────────

func _on_inject_coins() -> void:
	var line_edit: LineEdit = _get_node(_panel,
		"panel_bg/margin/vbox/section_resources/res_grid/coin_value") as LineEdit
	if line_edit == null:
		return
	var raw: String = line_edit.text.strip_edges()
	if raw.is_empty():
		return
	var amount: int = int(raw)
	if amount <= 0:
		return
	SaveLoadManager.add_coins(amount)
	SaveLoadManager.save_game()
	line_edit.text = ""
	print("[TrainerConsole] Injected %,d coins." % amount)


func _on_inject_spins() -> void:
	var line_edit: LineEdit = _get_node(_panel,
		"panel_bg/margin/vbox/section_resources/res_grid/spin_value") as LineEdit
	if line_edit == null:
		return
	var raw: String = line_edit.text.strip_edges()
	if raw.is_empty():
		return
	var amount: int = int(raw)
	if amount <= 0:
		return
	SaveLoadManager.add_spins(amount)
	SaveLoadManager.save_game()
	line_edit.text = ""
	print("[TrainerConsole] Injected %,d spins." % amount)


func _on_inject_shields() -> void:
	var line_edit: LineEdit = _get_node(_panel,
		"panel_bg/margin/vbox/section_resources/res_grid/shield_value") as LineEdit
	if line_edit == null:
		return
	var raw: String = line_edit.text.strip_edges()
	if raw.is_empty():
		return
	var amount: int = int(raw)
	if amount <= 0:
		return
	SaveLoadManager.add_shields(amount)
	SaveLoadManager.save_game()
	line_edit.text = ""
	print("[TrainerConsole] Injected %d shields." % amount)


# ─── RNG Override ─────────────────────────────────────────────────────────────

func _populate_rng_dropdown() -> void:
	var option_button: OptionButton = _get_node(_panel,
		"panel_bg/margin/vbox/section_rng/rng_option") as OptionButton
	if option_button == null:
		return

	option_button.clear()
	option_button.add_item("(Random - Use RNG)", 0)

	var slot_logic: SlotMachineLogic = SlotMachineLogic.get_instance()
	if slot_logic != null and slot_logic.is_initialized():
		_outcome_ids = slot_logic.get_all_outcome_ids()
		for i in range(_outcome_ids.size()):
			option_button.add_item(_outcome_ids[i], i + 1)

	print("[TrainerConsole] RNG dropdown: %d outcomes." % _outcome_ids.size())


func _on_rng_apply() -> void:
	var option_button: OptionButton = _get_node(_panel,
		"panel_bg/margin/vbox/section_rng/rng_option") as OptionButton
	if option_button == null:
		return

	var selected_id: int = option_button.get_selected_id()

	if selected_id == 0:
		SaveLoadManager.forced_outcome_id = ""
		SaveLoadManager.save_game()
		print("[TrainerConsole] RNG override cleared.")
		return

	var outcome_index: int = selected_id - 1
	if outcome_index >= 0 and outcome_index < _outcome_ids.size():
		SaveLoadManager.forced_outcome_id = _outcome_ids[outcome_index]
		SaveLoadManager.save_game()
		print("[TrainerConsole] RNG override set: '%s'" % SaveLoadManager.forced_outcome_id)


# ─── Event Triggers ─────────────────────────────────────────────────────────────

func _get_now() -> int:
	return int(Time.get_unix_time_from_system())


func _activate_event(event_id: String) -> void:
	var now: int = _get_now()
	var end: int = now + TRAINER_EVENT_DURATION_SECONDS

	if not SaveLoadManager.event_flags.has(event_id):
		push_warning("[TrainerConsole] Unknown event_id: '%s'" % event_id)
		return

	SaveLoadManager.event_flags[event_id]["is_active"] = true
	SaveLoadManager.event_flags[event_id]["start_timestamp"] = now
	SaveLoadManager.event_flags[event_id]["end_timestamp"] = end
	SaveLoadManager.save_game()

	print("[TrainerConsole] Event '%s' activated for %d seconds." % [event_id, TRAINER_EVENT_DURATION_SECONDS])
	_update_all_status_labels()


func _deactivate_event(event_id: String) -> void:
	if not SaveLoadManager.event_flags.has(event_id):
		return
	SaveLoadManager.event_flags[event_id]["is_active"] = false
	SaveLoadManager.save_game()
	print("[TrainerConsole] Event '%s' deactivated." % event_id)
	_update_all_status_labels()


func _on_toggle_coin_craze() -> void:
	var flags: Dictionary = SaveLoadManager.event_flags.get("coin_craze", {})
	if bool(flags.get("is_active", false)):
		_deactivate_event("coin_craze")
	else:
		_activate_event("coin_craze")


func _on_toggle_viking_quest() -> void:
	var flags: Dictionary = SaveLoadManager.event_flags.get("viking_quest", {})
	if bool(flags.get("is_active", false)):
		_deactivate_event("viking_quest")
	else:
		_activate_event("viking_quest")


func _on_deactivate_all_events() -> void:
	for event_id in SaveLoadManager.event_flags.keys():
		SaveLoadManager.event_flags[event_id]["is_active"] = false
		SaveLoadManager.event_flags[event_id]["start_timestamp"] = 0
		SaveLoadManager.event_flags[event_id]["end_timestamp"] = 0
	SaveLoadManager.save_game()
	print("[TrainerConsole] All events deactivated.")
	_update_all_status_labels()


# ─── Pet Activation ───────────────────────────────────────────────────────────

func _on_activate_foxy() -> void:
	_activate_pet("foxy")


func _on_activate_tiger() -> void:
	_activate_pet("tiger")


func _on_activate_rhino() -> void:
	_activate_pet("rhino")


func _activate_pet(pet_id: String) -> void:
	if PetManager == null:
		push_warning("[TrainerConsole] PetManager not available (not an Autoload?).")
		return
	var success: bool = PetManager.activate_pet(pet_id)
	if success:
		print("[TrainerConsole] Pet '%s' activated." % pet_id)
	else:
		push_warning("[TrainerConsole] Failed to activate pet '%s'." % pet_id)
	_update_all_status_labels()


# ─── Card Chest ────────────────────────────────────────────────────────────────

func _on_open_gold_chest() -> void:
	var result_label: Label = _get_node(_panel,
		"panel_bg/margin/vbox/section_cards/chest_result") as Label

	var main_node: Node = get_tree().get_first_node_in_group("main")
	if main_node == null:
		if result_label:
			result_label.text = "Main node not found."
		return

	var card_manager: Node = main_node.get_node_or_null("CardManager")
	if card_manager == null or not card_manager.has_method("open_chest"):
		if result_label:
			result_label.text = "CardManager not ready."
		return

	card_manager.open_chest("chest_gold")
	if result_label:
		result_label.text = "Gold chest opened."
	print("[TrainerConsole] Gold chest opened via trainer.")


# ─── Save Wipe ───────────────────────────────────────────────────────────────

func _on_wipe_save_pressed() -> void:
	if not _wipe_pending:
		_wipe_pending = true
		_wipe_timer = WIPE_CONFIRM_TIMEOUT
		var label: Label = _get_node(_panel,
			"panel_bg/margin/vbox/section_save/wipe_confirm_label") as Label
		if label != null:
			label.text = "Press WIPE again within %d seconds to CONFIRM!" % int(WIPE_CONFIRM_TIMEOUT)
		print("[TrainerConsole] Wipe armed.")
	else:
		_execute_wipe()


func _execute_wipe() -> void:
	_wipe_pending = false
	_wipe_timer = 0.0

	var save_path: String = "user://savegame.save"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)

	# Reset all state directly then re-initialize via _apply_defaults().
	SaveLoadManager.coins = 500
	SaveLoadManager.spins = 50
	SaveLoadManager.shields = 0
	SaveLoadManager.current_village_level = 1
	SaveLoadManager.village_items_state = [0, 0, 0, 0, 0]
	SaveLoadManager.pet_state = {}
	SaveLoadManager.card_collection = {
		"owned_card_ids":   [],
		"completed_sets":   [],
		"total_duplicates": 0
	}
	SaveLoadManager.event_flags = {}
	SaveLoadManager.forced_outcome_id = ""
	SaveLoadManager._apply_defaults()
	SaveLoadManager.save_game()
	SaveLoadManager.load_game()

	_update_all_status_labels()
	print("[TrainerConsole] WIPE complete.")


func _cancel_wipe() -> void:
	if not _wipe_pending:
		return
	_wipe_pending = false
	_wipe_timer = 0.0
	var label: Label = _get_node(_panel,
		"panel_bg/margin/vbox/section_save/wipe_confirm_label") as Label
	if label != null:
		label.text = "Press WIPE again to confirm"


# ─── UI Refresh ───────────────────────────────────────────────────────────────

func _refresh_all_ui_values() -> void:
	_populate_rng_dropdown()
	_update_all_status_labels()


func _update_all_status_labels() -> void:
	if _panel == null:
		return
	_update_event_status("coin_craze",
		"panel_bg/margin/vbox/section_events/coin_craze_row/coin_craze_status")
	_update_event_status("viking_quest",
		"panel_bg/margin/vbox/section_events/viking_quest_row/viking_quest_status")
	_update_pet_status("foxy",
		"panel_bg/margin/vbox/section_pets/foxy_row/foxy_status")
	_update_pet_status("tiger",
		"panel_bg/margin/vbox/section_pets/tiger_row/tiger_status")
	_update_pet_status("rhino",
		"panel_bg/margin/vbox/section_pets/rhino_row/rhino_status")


func _update_event_status(event_id: String, node_path: String) -> void:
	var label: Label = _get_node(_panel, node_path) as Label
	if label == null:
		return
	var flags: Dictionary = SaveLoadManager.event_flags.get(event_id, {})
	var is_active: bool = bool(flags.get("is_active", false))
	var end_ts: int = int(flags.get("end_timestamp", 0))
	var now: int = _get_now()

	if is_active and end_ts > now:
		var remaining: int = end_ts - now
		var hours: int = int(remaining / 3600.0)
		var minutes: int = int((remaining % 3600) / 60.0)
		label.text = "ACTIVE (%dh %dm)" % [hours, minutes]
		label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		label.text = "Inactive"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func _update_pet_status(pet_id: String, node_path: String) -> void:
	var label: Label = _get_node(_panel, node_path) as Label
	if label == null:
		return
	if PetManager == null:
		label.text = "N/A"
		return
	var is_active: bool = PetManager.is_pet_active(pet_id)
	if is_active:
		var remaining: int = PetManager.get_pet_remaining_seconds(pet_id)
		var hours: int = int(remaining / 3600.0)
		var minutes: int = int((remaining % 3600) / 60.0)
		label.text = "ACTIVE (%dh %dm)" % [hours, minutes]
		label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		label.text = "Inactive"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


# ─── Utility ───────────────────────────────────────────────────────────────────

func _get_node(root: Node, path: String) -> Node:
	if root == null:
		return null
	return root.get_node_or_null(path)


#endif  # PRODUCTION_BUILD
