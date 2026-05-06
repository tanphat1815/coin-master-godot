# ==============================================================================
# VikingSlotCore.gd
# Path: res://src/events/VikingSlotCore.gd
# Role: Isolated slot math engine for Viking Quest mini-game.
# NO coupling to SlotMachineLogic. NO UI code. NO node references.
# Access pattern: Instantiated as a private member of Event_VikingQuest.
# ==============================================================================
class_name VikingSlotCore
extends RefCounted

## Path to Viking Quest outcome configuration.
const CONFIG_PATH: String = "res://src/data/viking_weights.json"

## Loaded outcome table from viking_weights.json.
var _outcomes: Array[Dictionary] = []

## Sum of all outcome weights.
var _weight_sum: int = 0

## Cached RNG. Seeded once at construction.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Tracks whether the config loaded successfully.
var _is_initialized: bool = false


func _init() -> void:
    _rng.randomize()
    _load_config()


func _load_config() -> void:
    var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
    if file == null:
        push_error("[VikingSlotCore] Cannot open '%s'. OS error: %d" % [
            CONFIG_PATH, FileAccess.get_open_error()
        ])
        return

    var raw_text: String = file.get_as_text()
    file.close()

    var json_parser: JSON = JSON.new()
    var parse_result: Error = json_parser.parse(raw_text)
    if parse_result != OK:
        push_error("[VikingSlotCore] JSON parse error at line %d: %s" % [
            json_parser.get_error_line(), json_parser.get_error_message()
        ])
        return

    var data: Dictionary = json_parser.get_data()
    if not data is Dictionary:
        push_error("[VikingSlotCore] viking_weights.json root is not a Dictionary.")
        return

    var raw_outcomes: Array = data.get("outcomes", [])
    if raw_outcomes.is_empty():
        push_error("[VikingSlotCore] 'outcomes' key missing or empty.")
        return

    var required_keys: Array[String] = [
        "id", "label", "weight", "reward_type", "reward_value", "triggers_raid_protection"
    ]

    for element in raw_outcomes:
        if not element is Dictionary:
            continue
        var valid: bool = true
        for key in required_keys:
            if not element.has(key):
                valid = false
                break
        if valid:
            _outcomes.append(element)

    if _outcomes.is_empty():
        push_error("[VikingSlotCore] No valid outcomes after validation.")
        return

    _weight_sum = 0
    for outcome in _outcomes:
        _weight_sum += int(outcome["weight"])

    if _weight_sum == 0:
        push_error("[VikingSlotCore] Total weight sum is 0.")
        return

    _is_initialized = true
    print("[VikingSlotCore] Initialized. Outcomes: %d | Weight sum: %d" % [
        _outcomes.size(), _weight_sum
    ])


func spin(_difficulty: String) -> Dictionary:
    if not _is_initialized:
        return _build_failure_dict("VikingSlotCore not initialized.")

    # Weighted random selection — identical algorithm to SlotMachineLogic.
    var roll: int = _rng.randi_range(0, _weight_sum - 1)
    for outcome in _outcomes:
        roll -= int(outcome["weight"])
        if roll < 0:
            return outcome.duplicate(true)

    push_warning("[VikingSlotCore] PRNG fallback. Check weight sum.")
    return _outcomes[_outcomes.size() - 1].duplicate(true)


func _build_failure_dict(reason: String) -> Dictionary:
    return {
        "success": false,
        "outcome_id": "",
        "label": "",
        "reward_type": "",
        "reward_value": 0,
        "triggers_raid_protection": false,
        "error_reason": reason
    }
