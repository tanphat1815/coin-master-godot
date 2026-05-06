# ==============================================================================
# PetManager.gd
# Path: res://src/core/PetManager.gd
# Role: Manages pet activation timers and exposes pet buff status.
# Registered as Autoload after SaveLoadManager.
# NOTE: No class_name declaration — PetManager is registered via project.godot [autoload].
# ==============================================================================
extends Node

## Duration each pet remains active after Treat consumption, in seconds.
## 14400 seconds = 4 hours.
const PET_ACTIVE_DURATION_SECONDS: int = 14400

## Loot multiplier when Foxy is active: 1.0 + 1.19 = 2.19 (119% boost).
const FOXY_RAID_MULTIPLIER: float = 2.19

## Loot multiplier when Tiger is active: 1.0 + 4.10 = 5.10 (410% boost).
const TIGER_ATTACK_MULTIPLIER: float = 5.10

## Valid pet IDs that can be activated.
const VALID_PET_IDS: Array[String] = ["foxy", "tiger", "rhino"]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal pet_buff_tick(pet_id: String, seconds_remaining: int, is_new_activation: bool)
signal pet_buff_expired(pet_id: String)
signal pet_activated(pet_id: String, expires_at: int)


func _ready() -> void:
	_rng.randomize()
	print("[PetManager] Initialized. Valid pets: %s" % str(VALID_PET_IDS))


func _process(_delta: float) -> void:
	var now: int = int(Time.get_unix_time_from_system())

	for pet_id in VALID_PET_IDS:
		var pet_data: Dictionary = SaveLoadManager.pet_state.get(pet_id, {})
		var expires_at: int = int(pet_data.get("active_until_timestamp", 0))
		var was_announced: bool = bool(pet_data.get("_was_announced", false))
		var is_active: bool = now < expires_at

		if is_active:
			var remaining: int = expires_at - now
			if not was_announced:
				SaveLoadManager.pet_state[pet_id]["_was_announced"] = true
				emit_signal("pet_activated", pet_id, expires_at)
				print("[PetManager] Pet '%s' ACTIVATED. Expires in %d seconds." % [pet_id, remaining])

			emit_signal("pet_buff_tick", pet_id, remaining, false)
		else:
			if was_announced:
				SaveLoadManager.pet_state[pet_id]["_was_announced"] = false
				emit_signal("pet_buff_expired", pet_id)
				print("[PetManager] Pet '%s' EXPIRED." % pet_id)


## Activates a pet for PET_ACTIVE_DURATION_SECONDS.
## Reads pet_id: "foxy", "tiger", or "rhino".
## Returns true if activation succeeded, false if invalid pet_id.
func activate_pet(pet_id: String) -> bool:
	if pet_id not in VALID_PET_IDS:
		push_warning("[PetManager] Invalid pet_id: '%s'." % pet_id)
		return false

	# TODO (future): Deduct Treat item from inventory:
	# if not InventoryManager.try_consume_item("treat", 1):
	#     return false

	var now: int = int(Time.get_unix_time_from_system())
	var expires_at: int = now + PET_ACTIVE_DURATION_SECONDS

	if not SaveLoadManager.pet_state.has(pet_id):
		SaveLoadManager.pet_state[pet_id] = {
			"xp": 0, "level": 1, "active_until_timestamp": 0
		}

	SaveLoadManager.pet_state[pet_id]["active_until_timestamp"] = expires_at
	SaveLoadManager.pet_state[pet_id]["_was_announced"] = false
	SaveLoadManager.save_game()

	print("[PetManager] Pet '%s' activated. Expires at Unix: %d." % [pet_id, expires_at])
	return true


## Returns true if the specified pet is currently active.
func is_pet_active(pet_id: String) -> bool:
	if pet_id not in VALID_PET_IDS:
		return false
	var pet_data: Dictionary = SaveLoadManager.pet_state.get(pet_id, {})
	var expires_at: int = int(pet_data.get("active_until_timestamp", 0))
	return int(Time.get_unix_time_from_system()) < expires_at


## Returns seconds remaining on a pet's active buff, or 0 if inactive.
func get_pet_remaining_seconds(pet_id: String) -> int:
	if pet_id not in VALID_PET_IDS:
		return 0
	var pet_data: Dictionary = SaveLoadManager.pet_state.get(pet_id, {})
	var expires_at: int = int(pet_data.get("active_until_timestamp", 0))
	return max(0, expires_at - int(Time.get_unix_time_from_system()))


## Returns a Dictionary with all pet buff statuses for UI display.
func get_all_pet_status() -> Dictionary:
	var result: Dictionary = {}
	for pet_id in VALID_PET_IDS:
		result[pet_id] = {
			"is_active":         is_pet_active(pet_id),
			"seconds_remaining":  get_pet_remaining_seconds(pet_id),
			"level":             int(SaveLoadManager.pet_state.get(pet_id, {}).get("level", 1)),
			"xp":                int(SaveLoadManager.pet_state.get(pet_id, {}).get("xp", 0))
		}
	return result
