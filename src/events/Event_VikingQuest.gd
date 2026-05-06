# ==============================================================================
# Event_VikingQuest.gd
# Path: res://src/events/Event_VikingQuest.gd
# Role: Viking Quest live-ops mini-game event.
# Extends BaseEvent — managed by EventManager lifecycle.
# Contains: isolated VikingSlotCore, difficulty selection, progress bar, Raid Protection.
# ==============================================================================
class_name Event_VikingQuest
extends BaseEvent

## Duration of the Raid Protection buff granted by Viking spins, in seconds.
const RAID_PROTECTION_DURATION_SECONDS: int = 180  # 3 minutes

## Multiplier applied to the Viking spin cost based on selected difficulty.
## Easy   = 1x cost → lower risk, lower reward ceiling
## Normal = 3x cost → standard risk/reward
## Hard   = 10x cost → high risk, maximum reward ceiling
const DIFFICULTY_MULTIPLIERS: Dictionary = {
	"easy":   1,
	"normal": 3,
	"hard":   10
}

## Spin cost in coins at Easy difficulty, before multiplier.
const BASE_SPIN_COST: int = 5000

## Key used in SaveLoadManager.pet_state for the Viking Raid Protection buff.
## IMPORTANT: Never overwrite "rhino" — use a separate key.
const RAID_PROTECTION_KEY: String = "viking_raid_protection"

## Available difficulty levels.
enum VikingDifficulty { EASY, NORMAL, HARD }

## Maps VikingDifficulty enum values to string keys for DIFFICULTY_MULTIPLIERS.
const _DIFFICULTY_STRING_MAP: Dictionary = {
	VikingDifficulty.EASY:   "easy",
	VikingDifficulty.NORMAL: "normal",
	VikingDifficulty.HARD:   "hard"
}

## Currently selected difficulty.
var _selected_difficulty: VikingDifficulty = VikingDifficulty.NORMAL

## The isolated Viking slot engine. Instantiated in _init().
var _viking_slot: VikingSlotCore = VikingSlotCore.new()

## Local progress bar state. Does NOT persist to SaveLoadManager.
## Resets when Viking Quest event window closes.
var _progress_current: int = 0

## Tracks which tiers have been awarded (prevent double-claim within event window).
## Key: tier id string. Value: bool (true = already claimed).
var _tier_claimed: Dictionary = {}

## Cached progress tier definitions loaded from viking_weights.json.
var _progress_tiers: Array[Dictionary] = []

## Signal emitted when progress bar updates.
## value: int (current progress), max_value: int (next tier threshold)
signal progress_updated(value: int, max_value: int)

## Signal emitted when a tier reward becomes claimable.
## tier_id: String, reward_coins: int
signal tier_reached(tier_id: String, reward_coins: int)

## Signal emitted when Raid Protection is activated.
## expires_at: int (Unix timestamp)
signal raid_protection_activated(expires_at: int)


func _init() -> void:
	# Restore persisted state from SaveLoadManager.
	var saved_flags: Dictionary = SaveLoadManager.event_flags.get("viking_quest", {})
	_init_impl(
		"viking_quest",
		"Viking Quest",
		int(saved_flags.get("start_timestamp", 0)),
		int(saved_flags.get("end_timestamp", 0))
	)

	# Load progress tiers from viking_weights.json.
	_load_progress_tiers()

	# Sync is_active from persisted state on boot.
	if saved_flags.get("is_active", false):
		var now: int = int(Time.get_unix_time_from_system())
		if end_time > now:
			is_active = true
			_on_start()  # Immediately activate if window still valid


func _load_progress_tiers() -> void:
	var file: FileAccess = FileAccess.open(VikingSlotCore.CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("[Event_VikingQuest] Cannot open viking_weights.json for tiers.")
		return

	var raw_text: String = file.get_as_text()
	file.close()

	var json_parser: JSON = JSON.new()
	if json_parser.parse(raw_text) != OK:
		push_warning("[Event_VikingQuest] Failed to parse viking_weights.json for tiers.")
		return

	var data: Dictionary = json_parser.get_data()
	if data is Dictionary:
		var raw_tiers: Array = data.get("progress_tiers", [])
		_progress_tiers.clear()
		for t in raw_tiers:
			if t is Dictionary:
				_progress_tiers.append(t as Dictionary)
	print("[Event_VikingQuest] Loaded %d progress tiers." % _progress_tiers.size())


func _on_start() -> void:
	# Reset local progress for this event window.
	_progress_current = 0
	_tier_claimed.clear()

	print("[Event_VikingQuest] ACTIVE. Base spin cost: %d coins. Difficulty: %s" % [
		BASE_SPIN_COST, _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal")
	])


func _on_end() -> void:
	print("[Event_VikingQuest] ENDED. Final progress: %d. Claiming remaining tiers..." % _progress_current)

	# Auto-claim any unclaimed tiers as a loyalty bonus.
	for tier in _progress_tiers:
		var tier_id: String = str(tier.get("id", ""))
		if _progress_current >= int(tier.get("threshold", 0)):
			if not _tier_claimed.get(tier_id, false):
				var reward: int = int(tier.get("reward_coins", 0))
				if reward > 0:
					SaveLoadManager.add_coins(reward)
					SaveLoadManager.save_game()
					_tier_claimed[tier_id] = true
					print("[Event_VikingQuest] Auto-claimed tier '%s': %d coins!" % [tier_id, reward])


## Sets the Viking spin difficulty. Call this from the Viking UI before spinning.
## difficulty: one of VikingDifficulty.EASY, VikingDifficulty.NORMAL, VikingDifficulty.HARD
func set_difficulty(difficulty: VikingDifficulty) -> void:
	_selected_difficulty = difficulty
	print("[Event_VikingQuest] Difficulty set to %s. Spin cost: %d coins." % [
		_DIFFICULTY_STRING_MAP.get(difficulty, "normal"), _get_current_spin_cost()
	])


## Returns the current spin cost in coins.
func _get_current_spin_cost() -> int:
	var multiplier: int = int(DIFFICULTY_MULTIPLIERS.get(
		_DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal"), 3
	))
	return BASE_SPIN_COST * multiplier


## Returns the selected difficulty as a string.
func get_difficulty_string() -> String:
	return _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal")


## Executes one Viking spin. Call this from the Viking spin button handler.
## Returns a Dictionary with the spin result, or an error dict if insufficient coins.
func execute_spin() -> Dictionary:
	if not is_active:
		return _build_spin_failure("Viking Quest is not currently active.")

	var spin_cost: int = _get_current_spin_cost()

	# ── Deduct cost from Coins (not Spins!) ───────────────────────────────────
	if not SaveLoadManager.spend_coins(spin_cost):
		return _build_spin_failure("Not enough coins! Need %d." % spin_cost)

	# ── Execute isolated Viking slot spin ────────────────────────────────────
	var outcome: Dictionary = _viking_slot.spin(get_difficulty_string())

	if not bool(outcome.get("success", true)):
		# Refund coins on internal failure.
		SaveLoadManager.add_coins(spin_cost)
		return outcome

	# ── Apply rewards ─────────────────────────────────────────────────────────
	var reward_type: String = str(outcome.get("reward_type", ""))
	var reward_value: int = int(outcome.get("reward_value", 0))
	var triggers_protection: bool = bool(outcome.get("triggers_raid_protection", false))

	if reward_type == "coins" and reward_value > 0:
		# Apply difficulty-based reward multiplier.
		# Higher difficulty = higher actual reward received.
		var difficulty_mult: int = int(DIFFICULTY_MULTIPLIERS.get(
			get_difficulty_string(), 3
		))
		var final_reward: int = reward_value * difficulty_mult

		SaveLoadManager.add_coins(final_reward)

		# Update local progress bar.
		_add_progress(final_reward)

		print("[Event_VikingQuest] Won %d coins (×%d difficulty bonus). Progress: %d." % [
			final_reward, difficulty_mult, _progress_current
		])

	elif reward_type == "raid_protection":
		# Raid Protection outcome: award coins + protection buff.
		SaveLoadManager.add_coins(500)  # Small consolation prize.
		triggers_protection = true
		print("[Event_VikingQuest] Raid Protection outcome! Buff activated.")

	# ── Raid Protection buff ───────────────────────────────────────────────
	if triggers_protection:
		_grant_raid_protection()

	# ── Persist state ───────────────────────────────────────────────────────
	SaveLoadManager.save_game()

	# ── Build and return result ─────────────────────────────────────────────
	var result: Dictionary = outcome.duplicate(true)
	result["difficulty"] = get_difficulty_string()
	result["spin_cost_paid"] = spin_cost
	result["success"] = true
	return result


func _build_spin_failure(reason: String) -> Dictionary:
	return {
		"success": false,
		"outcome_id": "",
		"reward_type": "",
		"reward_value": 0,
		"triggers_raid_protection": false,
		"difficulty": get_difficulty_string(),
		"spin_cost_paid": 0,
		"error_reason": reason
	}


## Adds coins to the local progress bar and checks tier completions.
func _add_progress(coins_won: int) -> void:
	_progress_current += coins_won

	# Get the next unclaimed tier threshold.
	var next_threshold: int = _get_next_tier_threshold()

	emit_signal("progress_updated", _progress_current, next_threshold)

	# Check each tier.
	for tier in _progress_tiers:
		var tier_id: String = str(tier.get("id", ""))
		var threshold: int = int(tier.get("threshold", 0))
		var reward: int = int(tier.get("reward_coins", 0))

		if _progress_current >= threshold and not _tier_claimed.get(tier_id, false):
			_tier_claimed[tier_id] = true
			SaveLoadManager.add_coins(reward)
			SaveLoadManager.save_game()
			emit_signal("tier_reached", tier_id, reward)
			print("[Event_VikingQuest] Tier '%s' REACHED! Bonus: %d coins!" % [tier_id, reward])


## Returns the threshold of the next unclaimed tier.
func _get_next_tier_threshold() -> int:
	for tier in _progress_tiers:
		var tier_id: String = str(tier.get("id", ""))
		if not _tier_claimed.get(tier_id, false):
			return int(tier.get("threshold", 0))
	# All tiers claimed.
	return _progress_current


func _get_tier_thresholds() -> Array[int]:
	var result: Array[int] = []
	for tier in _progress_tiers:
		result.append(int(tier.get("threshold", 0)))
	return result


## Grants Raid Protection buff for RAID_PROTECTION_DURATION_SECONDS.
## Writes to SaveLoadManager.pet_state["viking_raid_protection"].
## NPCSimulator._is_rhino_active() reads this key and checks the timestamp.
func _grant_raid_protection() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var expires_at: int = now + RAID_PROTECTION_DURATION_SECONDS

	SaveLoadManager.pet_state[RAID_PROTECTION_KEY] = {
		"active_until_timestamp": expires_at,
		"buff_type": "raid_protection",
		"granted_at": now
	}

	emit_signal("raid_protection_activated", expires_at)
	print("[Event_VikingQuest] Raid Protection granted! Expires at Unix time: %d (in %d seconds)." % [
		expires_at, RAID_PROTECTION_DURATION_SECONDS
	])


## Checks if Raid Protection is currently active.
## Reads from SaveLoadManager.pet_state (does not write).
func is_raid_protection_active() -> bool:
	var protection_data: Dictionary = SaveLoadManager.pet_state.get(RAID_PROTECTION_KEY, {})
	var expires_at: int = int(protection_data.get("active_until_timestamp", 0))
	var now: int = int(Time.get_unix_time_from_system())
	return now < expires_at


## Returns seconds remaining on Raid Protection, or 0 if inactive.
func get_raid_protection_remaining_seconds() -> int:
	var protection_data: Dictionary = SaveLoadManager.pet_state.get(RAID_PROTECTION_KEY, {})
	var expires_at: int = int(protection_data.get("active_until_timestamp", 0))
	var now: int = int(Time.get_unix_time_from_system())
	return max(0, expires_at - now)


## Returns current Viking Quest state as a Dictionary.
func get_progress() -> Dictionary:
	return {
		"current": _progress_current,
		"next_tier_threshold": _get_next_tier_threshold(),
		"is_active": is_active,
		"spin_cost": _get_current_spin_cost(),
		"difficulty": get_difficulty_string()
	}
