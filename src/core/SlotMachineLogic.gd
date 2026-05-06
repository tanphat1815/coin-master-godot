# ==============================================================================
# SlotMachineLogic.gd
# Path: res://src/core/SlotMachineLogic.gd
# Role: Pure mathematical slot machine engine. Resource faucet for the economy.
# NO UI CODE OF ANY KIND. No Node rendering. No visual elements.
# Access pattern: Instantiated in main scene. Other systems call spin_reels().
# Signals: Emitted after outcome resolution. UI layer connects to these.
# ==============================================================================
extends Node
class_name SlotMachineLogic

## Maximum number of shields a player can hold simultaneously.
## Sourced from slot_weights.json max_held field, but also declared here
## as a named constant for defensive guard clarity.
const SHIELD_MAX_HELD: int = 5

## Path to the weighted probability configuration file.
const WEIGHTS_CONFIG_PATH: String = "res://src/data/slot_weights.json"

## Coin compensation awarded when a shield outcome is intercepted due to cap.
## Populated at runtime from the "coins_small" outcome in slot_weights.json.
var _shield_overflow_coin_compensation: int = 0

## The fully parsed and validated outcome table loaded from slot_weights.json.
var _outcome_table: Array[Dictionary] = []

## The sum of all weight integers in _outcome_table.
var _weight_sum: int = 0

## Tracks whether _ready() successfully loaded and validated the config.
var _is_initialized: bool = false

## Cache of the RandomNumberGenerator instance.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Singleton instance — set in _ready(), used by non-node systems to access signals.
static var _instance: SlotMachineLogic = null

## Emitted when a spin completes successfully.
signal spin_completed(result: Dictionary)

## Emitted when spin_reels() is called but the player has insufficient spins.
signal spin_failed_insufficient_spins(required: int, available: int)

## Emitted when a shield outcome is intercepted due to max capacity.
signal shield_overflow_intercepted(compensation_coins: int)

## Emitted when the forced_outcome_id override is consumed.
signal rng_override_consumed(outcome_id: String)

## Emitted after every spin that results in a Raid outcome.
signal raid_triggered(raid_count: int)

## Emitted after every spin that results in an Attack outcome.
signal attack_triggered(attack_count: int)


func _ready() -> void:
	_rng.randomize()
	_load_weights_config()
	_instance = self


func _load_weights_config() -> void:
	var file: FileAccess = FileAccess.open(WEIGHTS_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[SlotMachineLogic] Cannot open '%s'. OS error: %d" % [
			WEIGHTS_CONFIG_PATH, FileAccess.get_open_error()
		])
		return

	var raw_text: String = file.get_as_text()
	file.close()

	var json_parser: JSON = JSON.new()
	var parse_result: Error = json_parser.parse(raw_text)
	if parse_result != OK:
		push_error("[SlotMachineLogic] JSON parse error at line %d: %s" % [
			json_parser.get_error_line(), json_parser.get_error_message()
		])
		return

	var data = json_parser.get_data()
	if not data is Dictionary:
		push_error("[SlotMachineLogic] slot_weights.json root is not a Dictionary.")
		return

	var raw_outcomes = data.get("outcomes", null)
	if not raw_outcomes is Array or raw_outcomes.is_empty():
		push_error("[SlotMachineLogic] 'outcomes' key missing or empty in slot_weights.json.")
		return

	var required_keys: Array[String] = [
		"id", "label", "weight", "reward_type",
		"reward_value", "reward_tier", "three_of_a_kind_only"
	]

	for element in raw_outcomes:
		if not element is Dictionary:
			push_warning("[SlotMachineLogic] Skipping non-Dictionary outcome entry.")
			continue
		var valid: bool = true
		for key in required_keys:
			if not element.has(key):
				push_warning("[SlotMachineLogic] Outcome missing key '%s'. Skipping: %s" % [key, str(element)])
				valid = false
				break
		if valid:
			_outcome_table.append(element)

	if _outcome_table.is_empty():
		push_error("[SlotMachineLogic] No valid outcomes after validation. Cannot initialize.")
		return

	_weight_sum = 0
	for outcome in _outcome_table:
		_weight_sum += int(outcome["weight"])

	if _weight_sum == 0:
		push_error("[SlotMachineLogic] Total weight sum is 0. slot_weights.json is misconfigured.")
		return

	# Extract shield overflow compensation from coins_small reward_value.
	_shield_overflow_coin_compensation = 50
	for outcome in _outcome_table:
		if str(outcome.get("id", "")) == "coins_small":
			_shield_overflow_coin_compensation = int(outcome.get("reward_value", 50))
			break
	
	if _shield_overflow_coin_compensation == 50 and not _has_outcome("coins_small"):
		push_warning("[SlotMachineLogic] 'coins_small' outcome not found in table. Using fallback compensation: 50.")

	_is_initialized = true
	print("[SlotMachineLogic] Initialized. Outcomes: %d | Weight sum: %d | Shield compensation: %d" % [
		_outcome_table.size(), _weight_sum, _shield_overflow_coin_compensation
	])


func _has_outcome(id: String) -> bool:
	for o in _outcome_table:
		if str(o.get("id", "")) == id:
			return true
	return false


func spin_reels(bet_multiplier: int) -> Dictionary:
	# ── Guard Block ─────────────────────────────────────────────────────────────
	if not _is_initialized:
		return _build_failure_dict(bet_multiplier, "SlotMachineLogic not initialized.")

	if bet_multiplier < 1:
		push_warning("[SlotMachineLogic] bet_multiplier < 1. Clamping to 1.")
		bet_multiplier = 1

	if SaveLoadManager.spins < bet_multiplier:
		emit_signal("spin_failed_insufficient_spins", bet_multiplier, SaveLoadManager.spins)
		return _build_failure_dict(bet_multiplier, "Insufficient spins. Required: %d, Available: %d" % [
			bet_multiplier, SaveLoadManager.spins
		])

	# ── Spin Cost Deduction ─────────────────────────────────────────────────────
	SaveLoadManager.spend_spins(bet_multiplier)

	# ── Outcome Selection ────────────────────────────────────────────────────────
	var selected_outcome: Dictionary = _resolve_outcome_id()

	var reward_type: String = str(selected_outcome.get("reward_type", "coins"))
	var reward_tier: String = str(selected_outcome.get("reward_tier", "small"))
	var outcome_id: String  = str(selected_outcome.get("id", "coins_small"))
	var base_reward: int    = int(selected_outcome.get("reward_value", 0))

	# ── Shield Cap Interception (Step 11: scaled by bet_multiplier) ──────────────
	var final_reward_value: int = 0
	var attack_phases: int      = 0
	var raid_dig_slots: int    = 0
	var shields_awarded: int   = 0
	var was_intercepted: bool  = false
	var compensation_coins: int = 0

	if reward_type == "shield":
		var scaled: int = base_reward * bet_multiplier
		var can_hold: int = SHIELD_MAX_HELD - SaveLoadManager.shields
		var to_award: int = mini(scaled, can_hold)

		if to_award <= 0:
			SaveLoadManager.add_spins(bet_multiplier)
			SaveLoadManager.add_coins(_shield_overflow_coin_compensation)
			emit_signal("shield_overflow_intercepted", _shield_overflow_coin_compensation)
			was_intercepted = true
			compensation_coins = _shield_overflow_coin_compensation
			final_reward_value = 0
			shields_awarded = 0
		else:
			SaveLoadManager.add_shields(to_award)
			final_reward_value = to_award
			shields_awarded = to_award
			was_intercepted = false

	# ── Final Reward Calculation ──────────────────────────────────────────────────
	match reward_type:
		"coins":
			final_reward_value = base_reward * bet_multiplier
			SaveLoadManager.add_coins(final_reward_value)
		"spins":
			final_reward_value = base_reward * bet_multiplier
			SaveLoadManager.add_spins(final_reward_value)
		"attack":
			# x10 Attack = x10 treasure from ONE village (base_reward phases).
			final_reward_value = base_reward * bet_multiplier
			attack_phases = base_reward  # Always 1 village; only treasure is multiplied.
		"raid":
			final_reward_value = base_reward * bet_multiplier
			raid_dig_slots = final_reward_value
		"shield":
			pass  # Already handled above.
		_:
			push_warning("[SlotMachineLogic] Unknown reward_type '%s'. No resource awarded." % reward_type)

	# ── Post-Award Signal Emission ──────────────────────────────────────────────
	if reward_type == "raid" and not was_intercepted:
		emit_signal("raid_triggered", final_reward_value)
	if reward_type == "attack" and not was_intercepted:
		emit_signal("attack_triggered", final_reward_value)

	# ── Result Construction ─────────────────────────────────────────────────────
	var result: Dictionary = {
		"success":               true,
		"outcome_id":            outcome_id,
		"reward_type":           reward_type,
		"reward_value":          final_reward_value,
		"reward_tier":           reward_tier,
		"bet_multiplier":        bet_multiplier,
		"was_intercepted":       was_intercepted,
		"compensation_coins":     compensation_coins,
		"error_reason":          "",
		"triggers_raid":         reward_type == "raid" and not was_intercepted,
		"triggers_attack":       reward_type == "attack" and not was_intercepted,
		"attack_phases":         attack_phases,
		"raid_dig_slots":        raid_dig_slots,
		"shields_awarded":       shields_awarded,
		"bet_multiplier_applied": bet_multiplier,
		"event_points_awarded":   0
	}

	SaveLoadManager.save_game()
	emit_signal("spin_completed", result)

	print("[SlotMachineLogic] Spin resolved. Outcome: %s | Reward: %d %s | Bet: x%d" % [
		outcome_id, final_reward_value, reward_type, bet_multiplier
	])

	return result


func _resolve_outcome_id() -> Dictionary:
	# ── Override Path (Trainer Dev Mode) ────────────────────────────────────────
	var override_id: String = SaveLoadManager.forced_outcome_id
	if not override_id.is_empty():
		for outcome in _outcome_table:
			if str(outcome.get("id", "")) == override_id:
				SaveLoadManager.forced_outcome_id = ""
				emit_signal("rng_override_consumed", override_id)
				print("[SlotMachineLogic] RNG override consumed: '%s'" % override_id)
				return outcome
		push_warning("[SlotMachineLogic] forced_outcome_id '%s' not found in table. Falling through to PRNG." % override_id)
		SaveLoadManager.forced_outcome_id = ""

	# ── Normal PRNG Weighted Selection ──────────────────────────────────────────
	var roll: int = _rng.randi_range(0, _weight_sum - 1)

	for outcome in _outcome_table:
		roll -= int(outcome["weight"])
		if roll < 0:
			return outcome

	push_warning("[SlotMachineLogic] PRNG fallback triggered. Check weight sum integrity.")
	return _outcome_table[_outcome_table.size() - 1]


func _build_failure_dict(bet_multiplier: int, reason: String) -> Dictionary:
	return {
		"success":               false,
		"outcome_id":            "",
		"reward_type":           "",
		"reward_value":         0,
		"reward_tier":          "",
		"bet_multiplier":        bet_multiplier,
		"was_intercepted":      false,
		"compensation_coins":    0,
		"error_reason":         reason,
		"triggers_raid":        false,
		"triggers_attack":      false,
		"attack_phases":        0,
		"raid_dig_slots":       0,
		"shields_awarded":      0,
		"bet_multiplier_applied": bet_multiplier,
		"event_points_awarded":  0
	}


# ==============================================================================
# Public Query API (Read-only, no mutation)
# ==============================================================================

func get_outcome_probability(outcome_id: String) -> float:
	if not _is_initialized or _weight_sum == 0:
		return -1.0
	for outcome in _outcome_table:
		if str(outcome.get("id", "")) == outcome_id:
			return float(int(outcome["weight"])) / float(_weight_sum)
	return -1.0


func get_all_outcome_ids() -> Array[String]:
	var ids: Array[String] = []
	for outcome in _outcome_table:
		ids.append(str(outcome.get("id", "")))
	return ids


func can_spin(bet_multiplier: int) -> bool:
	if not _is_initialized:
		return false
	return SaveLoadManager.spins >= max(1, bet_multiplier)


func is_initialized() -> bool:
	return _is_initialized


## Returns the singleton instance, or null if not yet instantiated.
static func get_instance() -> SlotMachineLogic:
	return _instance
