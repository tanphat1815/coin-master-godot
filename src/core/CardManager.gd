# ==============================================================================
# CardManager.gd
# Path: res://src/core/CardManager.gd
# Role: Card collection, chest opening RNG, set completion.
# Instantiated as child of Main.gd. Emits signals for UI to consume.
# ==============================================================================
class_name CardManager
extends Node

const CARD_SETS_PATH: String = "res://src/data/card_sets.json"
const CHEST_CONFIG_PATH: String = "res://src/data/card_chest_config.json"
const DUPLICATE_COIN_COMPENSATION_PER_STAR: int = 500

var _card_sets: Dictionary = {}
var _card_registry: Dictionary = {}
var _chest_configs: Dictionary = {}
var _is_initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal card_opened(card: Dictionary, is_duplicate: bool, coins_compensation: int)
signal set_completed(set_id: String, reward_spins: int, reward_coins: int)
signal chest_opened_batch(cards: Array)
signal chest_open_failed(chest_id: String, reason: String)


func _init() -> void:
	_rng.randomize()
	_load_all_configs()


func _load_all_configs() -> void:
	_load_card_sets()
	_load_chest_configs()
	_is_initialized = not _card_sets.is_empty() and not _chest_configs.is_empty()
	if _is_initialized:
		print("[CardManager] Initialized. Sets: %d | Chests: %d | Cards: %d" % [
			_card_sets.size(), _chest_configs.size(), _card_registry.size()
		])
	else:
		push_error("[CardManager] Config load failed. Check JSON files.")


func _load_card_sets() -> void:
	var file: FileAccess = FileAccess.open(CARD_SETS_PATH, FileAccess.READ)
	if file == null:
		push_error("[CardManager] Cannot open card_sets.json.")
		return
	var raw_text: String = file.get_as_text()
	file.close()

	var parser: JSON = JSON.new()
	if parser.parse(raw_text) != OK:
		push_error("[CardManager] card_sets.json parse error.")
		return

	var data: Variant = parser.get_data()
	if not data is Dictionary:
		push_error("[CardManager] card_sets.json root invalid.")
		return

	var sets_array: Array = data.get("sets", [])
	for set_entry in sets_array:
		if not set_entry is Dictionary:
			continue
		var set_id: String = str(set_entry.get("id", ""))
		if set_id.is_empty():
			continue
		var cards: Array = set_entry.get("cards", [])
		_card_sets[set_id] = {
			"id": set_id,
			"name": str(set_entry.get("name", "")),
			"theme": str(set_entry.get("theme", "")),
			"cards": [],
			"completion_reward_spins": int(set_entry.get("completion_reward_spins", 0)),
			"completion_reward_coins": int(set_entry.get("completion_reward_coins", 0))
		}
		for card_entry in cards:
			if not card_entry is Dictionary:
				continue
			var card: Dictionary = {
				"id":     str(card_entry.get("id", "")),
				"name":   str(card_entry.get("name", "")),
				"star":   int(card_entry.get("star", 1)),
				"set_id": set_id
			}
			_card_sets[set_id]["cards"].append(card)
			_card_registry[card.get("id", "")] = card


func _load_chest_configs() -> void:
	var file: FileAccess = FileAccess.open(CHEST_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[CardManager] Cannot open card_chest_config.json.")
		return
	var raw_text: String = file.get_as_text()
	file.close()

	var parser: JSON = JSON.new()
	if parser.parse(raw_text) != OK:
		push_error("[CardManager] card_chest_config.json parse error.")
		return

	var data: Variant = parser.get_data()
	if not data is Dictionary:
		push_error("[CardManager] card_chest_config.json root invalid.")
		return

	for chest_entry in data.get("chests", []):
		if not chest_entry is Dictionary:
			continue
		var chest_id: String = str(chest_entry.get("id", ""))
		if chest_id.is_empty():
			continue
		_chest_configs[chest_id] = {
			"id":             chest_id,
			"display_name":   str(chest_entry.get("display_name", "")),
			"cost_coins":     int(chest_entry.get("cost_coins", 0)),
			"cost_gems":      int(chest_entry.get("cost_gems", 0)),
			"cards_per_open": int(chest_entry.get("cards_per_open", 1)),
			"drop_pool":      str(chest_entry.get("drop_pool", "all_cards")),
			"star_weights":   Dictionary(chest_entry.get("star_weights", {}))
		}


func open_chest(chest_id: String) -> void:
	if not _is_initialized:
		emit_signal("chest_open_failed", chest_id, "CardManager not initialized.")
		return

	var chest: Dictionary = _chest_configs.get(chest_id, {})
	if chest.is_empty():
		emit_signal("chest_open_failed", chest_id, "Unknown chest_id.")
		return

	var cost_coins: int = int(chest.get("cost_coins", 0))
	var cost_gems: int = int(chest.get("cost_gems", 0))

	if cost_coins > 0 and not SaveLoadManager.spend_coins(cost_coins):
		emit_signal("chest_open_failed", chest_id, "Not enough coins!")
		return

	if cost_gems > 0:
		push_warning("[CardManager] Gem cost for chest '%s' not yet implemented." % chest_id)

	var cards_per_open: int = int(chest.get("cards_per_open", 1))
	var opened_cards: Array[Dictionary] = []
	for i in range(cards_per_open):
		opened_cards.append(_roll_card(chest))

	emit_signal("chest_opened_batch", opened_cards)
	for card in opened_cards:
		_process_card_result(card)
	SaveLoadManager.save_game()
	print("[CardManager] Chest '%s' opened. %d cards." % [chest_id, opened_cards.size()])


func _roll_card(chest: Dictionary) -> Dictionary:
	var star_weights: Dictionary = chest.get("star_weights", {})
	var weight_sum: int = 0
	for v in star_weights.values():
		weight_sum += int(v)
	if weight_sum == 0:
		weight_sum = 1

	var roll: int = _rng.randi_range(0, weight_sum - 1)
	var selected_star: int = 1
	for star_key in ["1", "2", "3", "4", "5"]:
		roll -= int(star_weights.get(star_key, 0))
		if roll < 0:
			selected_star = int(star_key)
			break

	var candidates: Array[Dictionary] = []
	for card in _card_registry.values():
		if int(card.get("star", 1)) == selected_star:
			candidates.append(card)
	if candidates.is_empty():
		candidates.assign(_card_registry.values())

	return candidates[_rng.randi_range(0, candidates.size() - 1)].duplicate(true)


func _process_card_result(card: Dictionary) -> void:
	var card_id: String = str(card.get("id", ""))
	var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])
	var is_duplicate: bool = card_id in owned_ids
	var compensation: int = 0

	if is_duplicate:
		compensation = int(card.get("star", 1)) * DUPLICATE_COIN_COMPENSATION_PER_STAR
		SaveLoadManager.add_coins(compensation)
		SaveLoadManager.card_collection["total_duplicates"] += 1
		print("[CardManager] Duplicate card '%s' (★%d). Compensation: %,d coins." % [
			card_id, card.get("star", 1), compensation
		])
	else:
		owned_ids.append(card_id)
		SaveLoadManager.card_collection["owned_card_ids"] = owned_ids
		_check_set_completion(card.get("set_id", ""))
		print("[CardManager] New card: '%s' ★%d. Collection: %d/%d" % [
			card_id, card.get("star", 1),
			owned_ids.size(), _card_registry.size()
		])

	emit_signal("card_opened", card, is_duplicate, compensation)


func _check_set_completion(set_id: String) -> void:
	if set_id.is_empty():
		return
	var completed_sets: Array = SaveLoadManager.card_collection.get("completed_sets", [])
	if set_id in completed_sets:
		return
	var set_data: Dictionary = _card_sets.get(set_id, {})
	if set_data.is_empty():
		return
	var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])
	var all_owned: bool = true
	for set_card in set_data.get("cards", []):
		if str(set_card.get("id", "")) not in owned_ids:
			all_owned = false
			break
	if all_owned:
		completed_sets.append(set_id)
		SaveLoadManager.card_collection["completed_sets"] = completed_sets
		var reward_spins: int = int(set_data.get("completion_reward_spins", 0))
		var reward_coins: int = int(set_data.get("completion_reward_coins", 0))
		if reward_spins > 0:
			SaveLoadManager.add_spins(reward_spins)
		if reward_coins > 0:
			SaveLoadManager.add_coins(reward_coins)
		emit_signal("set_completed", set_id, reward_spins, reward_coins)
		SaveLoadManager.save_game()
		print("[CardManager] SET COMPLETED: '%s'! Spins: %d | Coins: %,d" % [
			set_id, reward_spins, reward_coins
		])


func get_set_progress(set_id: String) -> Dictionary:
	var set_data: Dictionary = _card_sets.get(set_id, {})
	if set_data.is_empty():
		return {"owned": 0, "total": 0, "is_complete": false}
	var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])
	var owned_count: int = 0
	for card in set_data.get("cards", []):
		if str(card.get("id", "")) in owned_ids:
			owned_count += 1
	var completed_sets: Array = SaveLoadManager.card_collection.get("completed_sets", [])
	return {
		"owned":       owned_count,
		"total":       set_data.get("cards", []).size(),
		"is_complete": set_id in completed_sets
	}


func get_collection_stats() -> Dictionary:
	var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])
	return {
		"total_owned":      owned_ids.size(),
		"total_cards":      _card_registry.size(),
		"total_sets":       _card_sets.size(),
		"completed_sets":   SaveLoadManager.card_collection.get("completed_sets", []).size(),
		"total_duplicates": SaveLoadManager.card_collection.get("total_duplicates", 0)
	}


func get_all_chest_configs() -> Array:
	return _chest_configs.values()


func is_ready() -> bool:
	return _is_initialized
