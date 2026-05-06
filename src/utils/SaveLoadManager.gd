# ==============================================================================
# SaveLoadManager.gd
# Path: res://src/utils/SaveLoadManager.gd
# Role: Global Autoload Singleton — Single source of truth for all player state.
# DO NOT instantiate this class manually. Access via SaveLoadManager.coins etc.
# DO NOT reference any scene node from this script.
# ==============================================================================
extends Node

const SAVE_PATH: String = "user://savegame.save"
const SAVE_VERSION: int = 1

# ── Core Resources ─────────────────────────────────────────────────────────────
var coins: int = 500
var spins: int = 50
var shields: int = 0

# ── Progression ───────────────────────────────────────────────────────────────
var current_village_level: int = 1
var village_items_state: Array = [0, 0, 0, 0, 0]

# ── Timestamps ────────────────────────────────────────────────────────────────
var last_login_timestamp: int = 0

# ── Shop ─────────────────────────────────────────────────────────────────────
var purchased_one_time_offers: Array = []

# ── Trainer / Dev ─────────────────────────────────────────────────────────────
var forced_outcome_id: String = ""

# ── Subsystems ────────────────────────────────────────────────────────────────
var pet_state: Dictionary = {}
var event_flags: Dictionary = {}

# ── Internal ──────────────────────────────────────────────────────────────────
var _save_version: int = SAVE_VERSION
var _is_loaded: bool = false

signal game_saved
signal game_loaded
signal load_failed(reason: String)
signal coins_changed(new_value: int)
signal spins_changed(new_value: int)
signal shields_changed(new_value: int)


func _ready() -> void:
    _apply_defaults()
    load_game()


func _apply_defaults() -> void:
    if pet_state.is_empty():
        pet_state = {
            "foxy":  { "xp": 0, "level": 1, "active_until_timestamp": 0 },
            "tiger": { "xp": 0, "level": 1, "active_until_timestamp": 0 },
            "rhino": { "xp": 0, "level": 1, "active_until_timestamp": 0 }
        }
    if event_flags.is_empty():
        event_flags = {
            "coin_craze":     { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
            "viking_quest":   { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
            "sea_of_fortune": { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
            "coin_cafe":      { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
            "boss_fight":     { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 }
        }


func _build_save_dictionary() -> Dictionary:
    return {
        "save_version":              _save_version,
        "coins":                     coins,
        "spins":                     spins,
        "shields":                   shields,
        "current_village_level":     current_village_level,
        "village_items_state":       village_items_state.duplicate(),
        "last_login_timestamp":       last_login_timestamp,
        "purchased_one_time_offers": purchased_one_time_offers.duplicate(),
        "forced_outcome_id":         forced_outcome_id,
        "pet_state":                 pet_state.duplicate(true),
        "event_flags":               event_flags.duplicate(true)
    }


func save_game() -> void:
    last_login_timestamp = int(Time.get_unix_time_from_system())
    var save_data: Dictionary = _build_save_dictionary()
    var json_string: String = JSON.stringify(save_data, "\t")

    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        var err: int = FileAccess.get_open_error()
        push_error("[SaveLoadManager] SAVE FAILED. Cannot open '%s'. OS error: %d" % [SAVE_PATH, err])
        emit_signal("load_failed", "Save write error: %d" % err)
        return

    file.store_string(json_string)
    file.close()

    _flush_indexeddb_if_html5()

    print("[SaveLoadManager] Game saved. Timestamp: %d" % last_login_timestamp)
    emit_signal("game_saved")


func load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        print("[SaveLoadManager] No save file found. Initializing new player.")
        _handle_new_player()
        return

    var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        var err: int = FileAccess.get_open_error()
        push_error("[SaveLoadManager] LOAD FAILED. Cannot open '%s'. OS error: %d" % [SAVE_PATH, err])
        _handle_new_player()
        return

    var raw_text: String = file.get_as_text()
    file.close()

    var json_parser: JSON = JSON.new()
    var parse_result: Error = json_parser.parse(raw_text)

    if parse_result != OK:
        push_error("[SaveLoadManager] JSON PARSE ERROR at line %d: %s" % [
            json_parser.get_error_line(),
            json_parser.get_error_message()
        ])
        _handle_corrupted_save()
        return

    var data = json_parser.get_data()
    if not data is Dictionary:
        push_error("[SaveLoadManager] Save file root is not a Dictionary. Treating as corrupt.")
        _handle_corrupted_save()
        return

    _migrate_if_needed(data)
    _apply_state_from_dictionary(data)
    _apply_defaults()

    _is_loaded = true
    print("[SaveLoadManager] Game loaded. Village: %d | Coins: %d | Spins: %d" % [
        current_village_level, coins, spins
    ])
    emit_signal("game_loaded")


func _flush_indexeddb_if_html5() -> void:
    # On non-Web platforms this is a no-op. On Web, OS.get_name() == "Web"
    # is already confirmed, so JavaScriptBridge.eval() is safe to call.
    if OS.get_name() != "Web":
        return

    JavaScriptBridge.eval("""
        FS.syncfs(false, function(err) {
            if (err) {
                console.error('[SaveLoadManager] IndexedDB sync failed:', err);
            } else {
                console.log('[SaveLoadManager] IndexedDB sync complete.');
            }
        });
    """, true)

    print("[SaveLoadManager] HTML5 IndexedDB sync dispatched.")


func _migrate_if_needed(data: Dictionary) -> void:
    var file_version: int = int(data.get("save_version", 0))
    if file_version == SAVE_VERSION:
        return

    push_warning("[SaveLoadManager] Save file version mismatch. File: %d | Current: %d. Migrating." % [
        file_version, SAVE_VERSION
    ])

    # Migration block — add version-specific transformations here in future steps.
    # Example structure (do not remove this comment block):
    # if file_version < 2:
    #     data["new_field_added_in_v2"] = default_value

    data["save_version"] = SAVE_VERSION
    print("[SaveLoadManager] Migration complete. Stamped version %d." % SAVE_VERSION)


func _apply_state_from_dictionary(data: Dictionary) -> void:
    coins                   = int(data.get("coins", 500))
    spins                   = int(data.get("spins", 50))
    shields                 = int(data.get("shields", 0))
    current_village_level   = int(data.get("current_village_level", 1))
    last_login_timestamp    = int(data.get("last_login_timestamp", 0))
    forced_outcome_id       = str(data.get("forced_outcome_id", ""))

    var raw_items = data.get("village_items_state", [0, 0, 0, 0, 0])
    if raw_items is Array and raw_items.size() == 5:
        village_items_state = raw_items
    else:
        push_warning("[SaveLoadManager] village_items_state invalid. Resetting to defaults.")
        village_items_state = [0, 0, 0, 0, 0]

    var raw_offers = data.get("purchased_one_time_offers", [])
    if raw_offers is Array:
        purchased_one_time_offers = raw_offers
    else:
        purchased_one_time_offers = []

    var raw_pets = data.get("pet_state", {})
    if raw_pets is Dictionary:
        pet_state = raw_pets
    else:
        pet_state = {}

    var raw_events = data.get("event_flags", {})
    if raw_events is Dictionary:
        event_flags = raw_events
    else:
        event_flags = {}

    coins   = max(0, coins)
    spins   = max(0, spins)
    shields = clamp(shields, 0, 5)
    current_village_level = max(1, current_village_level)


func _handle_new_player() -> void:
    print("[SaveLoadManager] Initializing new player state.")
    coins                   = 500
    spins                   = 50
    shields                 = 0
    current_village_level   = 1
    village_items_state     = [0, 0, 0, 0, 0]
    last_login_timestamp    = 0
    purchased_one_time_offers = []
    forced_outcome_id       = ""
    pet_state               = {}
    event_flags             = {}
    _apply_defaults()
    _is_loaded = true
    save_game()
    emit_signal("game_loaded")


func _handle_corrupted_save() -> void:
    push_error("[SaveLoadManager] Corrupted save detected. Backing up and resetting.")

    var backup_path: String = "user://savegame_corrupted_%d.bak" % int(Time.get_unix_time_from_system())
    var dir: DirAccess = DirAccess.open("user://")
    if dir != null:
        dir.rename("savegame.save", backup_path.replace("user://", ""))
        print("[SaveLoadManager] Corrupted save backed up to: %s" % backup_path)

    _handle_new_player()


# ==============================================================================
# Public Resource Mutator Helpers
# Only functions other systems call to modify resources.
# ==============================================================================

func add_coins(amount: int) -> void:
    coins = max(0, coins + amount)
    emit_signal("coins_changed", coins)


func spend_coins(amount: int) -> bool:
    if coins < amount:
        return false
    coins -= amount
    emit_signal("coins_changed", coins)
    return true


func add_spins(amount: int) -> void:
    spins = max(0, spins + amount)
    emit_signal("spins_changed", spins)


func spend_spins(amount: int) -> bool:
    if spins < amount:
        return false
    spins -= amount
    emit_signal("spins_changed", spins)
    return true


func add_shields(amount: int) -> void:
    shields = min(5, shields + amount)
    emit_signal("shields_changed", shields)


func consume_shield() -> bool:
    if shields <= 0:
        return false
    shields -= 1
    emit_signal("shields_changed", shields)
    return true


func is_loaded() -> bool:
    return _is_loaded
