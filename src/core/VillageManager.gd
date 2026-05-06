# ==============================================================================
# VillageManager.gd
# Path: res://src/core/VillageManager.gd
# Role: Primary economic resource sink. Manages village upgrade progression.
# NO UI CODE OF ANY KIND. Pure economic state management.
# Access pattern: Instantiated in main scene. UI queries via public API.
# Signals: Emitted after state changes. UI layer connects to these.
# ==============================================================================
extends Node
class_name VillageManager

## Number of upgradeable items in every village. Structural constant — never read from JSON.
const ITEMS_PER_VILLAGE: int = 5

## Maximum star-level any single item can reach before it is considered complete.
const MAX_ITEM_LEVEL: int = 5

## Path to the village cost configuration file produced in Step 1.
const VILLAGE_COSTS_PATH: String = "res://src/data/village_costs.json"

## Multiplier applied to the total village cost to calculate the completion bonus.
## A player who completes a village receives this multiple of the village's total
## cumulative cost as a coin reward. Kept as a constant so it can be tuned
## without touching logic code. Value: 0.25 = 25% of total village spend returned.
const COMPLETION_BONUS_MULTIPLIER: float = 0.25

## Full parsed village data array from village_costs.json.
var _village_data: Array[Dictionary] = []

## Tracks whether _ready() successfully loaded and validated the config.
var _is_initialized: bool = false

## Cache of the total cumulative cost of the currently active village.
var _current_village_total_cost: int = 0

## Emitted when a single item is successfully upgraded.
signal item_upgraded(item_index: int, new_level: int, cost_paid: int)

## Emitted when all 5 items in a village reach MAX_ITEM_LEVEL.
signal village_completed(completed_village_level: int, new_village_level: int, bonus_coins_awarded: int)

## Emitted when upgrade_item() is called but can_upgrade_item() returns false.
signal upgrade_failed(item_index: int, reason: String)

## Emitted when the config file loads successfully or fails.
signal initialized(success: bool)


func _ready() -> void:
    _load_village_config()


func _load_village_config() -> void:
    var file: FileAccess = FileAccess.open(VILLAGE_COSTS_PATH, FileAccess.READ)
    if file == null:
        push_error("[VillageManager] Cannot open '%s'. OS error: %d" % [
            VILLAGE_COSTS_PATH, FileAccess.get_open_error()
        ])
        emit_signal("initialized", false)
        return

    var raw_text: String = file.get_as_text()
    file.close()

    var json_parser: JSON = JSON.new()
    var parse_result: Error = json_parser.parse(raw_text)
    if parse_result != OK:
        push_error("[VillageManager] JSON parse error at line %d: %s" % [
            json_parser.get_error_line(), json_parser.get_error_message()
        ])
        emit_signal("initialized", false)
        return

    var data = json_parser.get_data()
    if not data is Dictionary:
        push_error("[VillageManager] village_costs.json root is not a Dictionary.")
        emit_signal("initialized", false)
        return

    var raw_villages = data.get("villages", null)
    if not raw_villages is Array or raw_villages.is_empty():
        push_error("[VillageManager] 'villages' key missing or empty in village_costs.json.")
        emit_signal("initialized", false)
        return

    for village in raw_villages:
        if not village is Dictionary:
            push_warning("[VillageManager] Skipping non-Dictionary village entry.")
            continue
        if not (village.has("id") and village.has("name") and village.has("items")):
            push_warning("[VillageManager] Village missing required keys. Skipping: %s" % str(village.get("id", "unknown")))
            continue

        var items = village.get("items", null)
        if not items is Array or items.size() != ITEMS_PER_VILLAGE:
            push_warning("[VillageManager] Village %s has invalid items array (expected %d). Skipping." % [
                str(village.get("id", "?")), ITEMS_PER_VILLAGE
            ])
            continue

        var items_valid: bool = true
        for item in items:
            if not item is Dictionary:
                push_warning("[VillageManager] Non-Dictionary item in village %s. Skipping village." % str(village.get("id", "?")))
                items_valid = false
                break
            if not (item.has("item_index") and item.has("label") and item.has("upgrade_costs")):
                push_warning("[VillageManager] Item missing required keys in village %s. Skipping village." % str(village.get("id", "?")))
                items_valid = false
                break
            var costs = item.get("upgrade_costs", null)
            if not costs is Array or costs.size() != MAX_ITEM_LEVEL:
                push_warning("[VillageManager] Item upgrade_costs invalid in village %s (expected %d costs). Skipping village." % [
                    str(village.get("id", "?")), MAX_ITEM_LEVEL
                ])
                items_valid = false
                break

        if items_valid:
            _village_data.append(village)

    if _village_data.is_empty():
        push_error("[VillageManager] No valid villages after validation. Cannot initialize.")
        emit_signal("initialized", false)
        return

    _cache_current_village_total_cost()
    _is_initialized = true
    emit_signal("initialized", true)
    print("[VillageManager] Loaded %d villages successfully." % _village_data.size())


# ==============================================================================
# Core Public API
# ==============================================================================

func can_upgrade_item(item_index: int) -> bool:
    if not _is_initialized:
        return false
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return false

    var village_index: int = _get_current_village_index()
    if village_index < 0:
        return false

    var current_level: int = int(SaveLoadManager.village_items_state[item_index])
    if current_level >= MAX_ITEM_LEVEL:
        return false

    var cost: int = _get_upgrade_cost(item_index)
    if cost < 0:
        return false

    return SaveLoadManager.coins >= cost


func upgrade_item(item_index: int) -> void:
    # ── Guard Block ─────────────────────────────────────────────────────────────
    if not _is_initialized:
        emit_signal("upgrade_failed", item_index, "not_initialized")
        return

    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        emit_signal("upgrade_failed", item_index, "invalid_index")
        return

    var current_level: int = int(SaveLoadManager.village_items_state[item_index])

    if current_level >= MAX_ITEM_LEVEL:
        emit_signal("upgrade_failed", item_index, "item_already_maxed")
        return

    var cost: int = _get_upgrade_cost(item_index)
    if cost < 0:
        push_error("[VillageManager] Could not resolve upgrade cost for item %d at village level %d." % [
            item_index, SaveLoadManager.current_village_level
        ])
        emit_signal("upgrade_failed", item_index, "not_initialized")
        return

    var spend_success: bool = SaveLoadManager.spend_coins(cost)
    if not spend_success:
        emit_signal("upgrade_failed", item_index, "insufficient_coins")
        return

    # ── State Mutation ─────────────────────────────────────────────────────────
    var new_level: int = current_level + 1
    SaveLoadManager.village_items_state[item_index] = new_level

    SaveLoadManager.save_game()

    emit_signal("item_upgraded", item_index, new_level, cost)

    print("[VillageManager] Item %d upgraded to level %d. Cost: %d. Coins remaining: %d" % [
        item_index, new_level, cost, SaveLoadManager.coins
    ])

    # ── Completion Check ────────────────────────────────────────────────────────
    _check_village_completion()


# ==============================================================================
# Private Logic Functions
# ==============================================================================

func _check_village_completion() -> void:
    var items_state: Array = SaveLoadManager.village_items_state
    for i in range(ITEMS_PER_VILLAGE):
        if int(items_state[i]) < MAX_ITEM_LEVEL:
            return
    # All items are at MAX_ITEM_LEVEL.
    _execute_village_completion()


func _execute_village_completion() -> void:
    var completed_level: int = SaveLoadManager.current_village_level

    var bonus: int = max(1, int(float(_current_village_total_cost) * COMPLETION_BONUS_MULTIPLIER))
    SaveLoadManager.add_coins(bonus)

    SaveLoadManager.current_village_level += 1
    SaveLoadManager.village_items_state = [0, 0, 0, 0, 0]

    _cache_current_village_total_cost()

    SaveLoadManager.save_game()

    emit_signal("village_completed", completed_level, SaveLoadManager.current_village_level, bonus)

    print("[VillageManager] Village %d COMPLETED. Bonus: %d coins. Advancing to village %d." % [
        completed_level, bonus, SaveLoadManager.current_village_level
    ])


func _get_upgrade_cost(item_index: int) -> int:
    var village_index: int = _get_current_village_index()
    if village_index < 0:
        return -1

    var village: Dictionary = _village_data[village_index]
    var items: Array = village.get("items", [])

    if item_index < 0 or item_index >= items.size():
        return -1

    var item: Dictionary = items[item_index]
    var upgrade_costs: Array = item.get("upgrade_costs", [])

    var current_level: int = int(SaveLoadManager.village_items_state[item_index])

    if current_level >= MAX_ITEM_LEVEL:
        return -1

    if current_level >= upgrade_costs.size():
        push_error("[VillageManager] upgrade_costs array too short for item %d at level %d." % [
            item_index, current_level
        ])
        return -1

    return int(upgrade_costs[current_level])


func _get_current_village_index() -> int:
    var index: int = SaveLoadManager.current_village_level - 1
    if index < 0 or index >= _village_data.size():
        return -1
    return index


func _cache_current_village_total_cost() -> void:
    var village_index: int = _get_current_village_index()
    if village_index < 0:
        push_warning("[VillageManager] Cannot cache village cost: village %d not in loaded data. Player may be beyond defined villages." % SaveLoadManager.current_village_level)
        _current_village_total_cost = 0
        return

    var village: Dictionary = _village_data[village_index]
    var items: Array = village.get("items", [])
    var total: int = 0

    for item in items:
        if not item is Dictionary:
            continue
        var costs: Array = item.get("upgrade_costs", [])
        for cost_value in costs:
            total += int(cost_value)

    _current_village_total_cost = total
    print("[VillageManager] Village %d total cost cached: %d coins." % [
        SaveLoadManager.current_village_level, _current_village_total_cost
    ])


# ==============================================================================
# Public Query API (Read-only, no mutation)
# ==============================================================================

func get_item_current_level(item_index: int) -> int:
    if not _is_initialized:
        return -1
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return -1
    return int(SaveLoadManager.village_items_state[item_index])


func get_item_upgrade_cost(item_index: int) -> int:
    if not _is_initialized:
        return -1
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return -1
    return _get_upgrade_cost(item_index)


func get_item_label(item_index: int) -> String:
    if not _is_initialized:
        return ""
    var village_index: int = _get_current_village_index()
    if village_index < 0:
        return ""
    var items: Array = _village_data[village_index].get("items", [])
    if item_index < 0 or item_index >= items.size():
        return ""
    return str(items[item_index].get("label", ""))


func get_current_village_name() -> String:
    if not _is_initialized:
        return ""
    var village_index: int = _get_current_village_index()
    if village_index < 0:
        return "Unknown Village"
    return str(_village_data[village_index].get("name", ""))


func get_village_completion_percentage() -> float:
    if not _is_initialized:
        return 0.0
    var total_possible: int = ITEMS_PER_VILLAGE * MAX_ITEM_LEVEL
    var total_achieved: int = 0
    for i in range(ITEMS_PER_VILLAGE):
        total_achieved += int(SaveLoadManager.village_items_state[i])
    return float(total_achieved) / float(total_possible)


func get_completion_bonus_preview() -> int:
    return max(1, int(float(_current_village_total_cost) * COMPLETION_BONUS_MULTIPLIER))


func is_item_maxed(item_index: int) -> bool:
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return false
    return int(SaveLoadManager.village_items_state[item_index]) >= MAX_ITEM_LEVEL


func is_village_data_available_for_level(village_level: int) -> bool:
    if not _is_initialized:
        return false
    var index: int = village_level - 1
    return index >= 0 and index < _village_data.size()


func is_initialized() -> bool:
    return _is_initialized
