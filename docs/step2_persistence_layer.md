```markdown
# step2_persistence_layer.md

## Technical Specification: Core Persistence Layer
**Target Engine:** Godot 4.x  
**Execution Agent:** Cursor (AI Coder)  
**Step:** 2 of 10 — Implement `SaveLoadManager.gd` as a global Autoload Singleton.  
**Depends On:** Step 1 complete. `res://src/data/` JSON files exist.  
**Output File:** `res://src/utils/SaveLoadManager.gd`

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **DO NOT** import or reference any scene node (`get_node`, `$Node`). This is a pure logic singleton.
- **DO NOT** hardcode any game balance values. This file manages state shape only.
- **DO NOT** write any UI code. No `Label`, no `Button`, no visual elements.
- **STRICTLY** use static typing on every variable and function signature (`var x: int`, `func foo() -> void`).
- **ALL** `FileAccess` operations must be wrapped in explicit `if` guards and `else` error branches.
- After writing the file, register it in `project.godot` under `[autoload]` as `SaveLoadManager="/src/utils/SaveLoadManager.gd"`.
- Confirm with the completion checklist at the end of this spec before proceeding to Step 3.

---

## SECTION 1: ARCHITECTURAL ROLE

`SaveLoadManager` is the **single source of truth** for all mutable player state at runtime. Every other system reads from and writes to this singleton. No other script may maintain its own persistent copy of player resources.

### Dependency Graph

```
SlotMachineLogic.gd  ──reads/writes──▶ SaveLoadManager.gd ──serializes──▶ user://savegame.save
VillageManager.gd    ──reads/writes──▶ SaveLoadManager.gd                        │
NPCSimulator.gd      ──reads/writes──▶ SaveLoadManager.gd                        │
PetManager.gd        ──reads/writes──▶ SaveLoadManager.gd              (IndexedDB on HTML5)
EventManager.gd      ──reads──────────▶ SaveLoadManager.gd
TrainerConsole.gd    ──writes─────────▶ SaveLoadManager.gd
```

### Platform I/O Routing (Automatic via Godot)

| Build Target | `user://` resolves to | Sync Mechanism |
|---|---|---|
| Windows `.exe` | `%APPDATA%\Godot\app_userdata\<project_name>\` | Synchronous filesystem write |
| macOS `.app` | `~/Library/Application Support/Godot/app_userdata/<project_name>/` | Synchronous filesystem write |
| Android `.apk` | Internal app sandbox (`/data/data/<package>/`) | Synchronous filesystem write |
| iOS `.ipa` | App Documents directory (sandboxed) | Synchronous filesystem write |
| HTML5 / Wasm | Browser **IndexedDB** via Emscripten virtual FS | **Requires explicit JS sync flush** |

**Critical HTML5 note:** On HTML5 exports, Godot's Emscripten layer maps `user://` to an in-memory virtual filesystem that is backed by IndexedDB. A write to `FileAccess` in GDScript updates the in-memory layer immediately but is **not persisted to IndexedDB until `JavaScriptBridge.eval()` flushes the Emscripten FS sync**. Without this flush, closing the browser tab loses all save data. `SaveLoadManager` must detect the HTML5 platform and call the sync flush after every `save_game()` invocation.

---

## SECTION 2: STATE DICTIONARY SCHEMA

### 2.1 Canonical Default State

The following Dictionary defines the **exact shape and default values** of a new player's save file. Every key listed here is mandatory. The `load_game()` function must validate that all keys exist after loading and inject missing keys with their defaults (forward-compatibility migration).

```
KEY                     TYPE            DEFAULT         DESCRIPTION
─────────────────────────────────────────────────────────────────────────────
coins                   int             500             Starting coin balance.
spins                   int             50              Starting spin balance.
shields                 int             0               Active shield count. Hard cap: 5.
current_village_level   int             1               Which village the player is on (1-indexed).
village_items_state     Array[int]      [0,0,0,0,0]     Upgrade level (0–5) for each of 5 items
                                                        in the current village. Reset to all-0
                                                        when village is completed.
last_login_timestamp    int             0               Unix epoch seconds. Set on every save.
                                                        Read by NPCSimulator to calculate
                                                        offline attack events on next load.
purchased_one_time_offers Array[String] []              SKU ids of consumed one-time shop offers.
forced_outcome_id       String          ""              TrainerConsole RNG override. Empty string
                                                        means no override active. Logic layer
                                                        clears this to "" after consuming it.
pet_state               Dictionary      (see 2.2)       Per-pet runtime data.
event_flags             Dictionary      (see 2.3)       Live-ops event scheduling state.
```

### 2.2 `pet_state` Sub-Schema Default

```
pet_state: {
    "foxy":  { "xp": 0, "level": 1, "active_until_timestamp": 0 },
    "tiger": { "xp": 0, "level": 1, "active_until_timestamp": 0 },
    "rhino": { "xp": 0, "level": 1, "active_until_timestamp": 0 }
}
```

### 2.3 `event_flags` Sub-Schema Default

```
event_flags: {
    "coin_craze":    { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
    "viking_quest":  { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
    "sea_of_fortune":{ "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
    "coin_cafe":     { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 },
    "boss_fight":    { "is_active": false, "start_timestamp": 0, "end_timestamp": 0 }
}
```

---

## SECTION 3: FULL GDSCRIPT IMPLEMENTATION SPEC

Write the file `res://src/utils/SaveLoadManager.gd` with **exactly** the following structure and logic. Implement every function described. Do not add extra functions beyond what is specified here—additional helpers belong in Step 3+.

### 3.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# SaveLoadManager.gd
# Path: res://src/utils/SaveLoadManager.gd
# Role: Global Autoload Singleton — Single source of truth for all player state.
# DO NOT instantiate this class manually. Access via SaveLoadManager.coins etc.
# DO NOT reference any scene node from this script.
# ==============================================================================
extends Node

const SAVE_PATH: String = "user://savegame.save"
const SAVE_VERSION: int = 1  # Increment when schema changes. Triggers migration.
```

### 3.2 State Variables Block

Declare every state variable with explicit static types matching the schema in Section 2. Declare them as public (no underscore prefix) so other autoloads can read them directly without a getter function. Group them with comments matching the schema table.

```gdscript
# ── Core Resources ────────────────────────────────────────────────────────────
var coins: int = 500
var spins: int = 50
var shields: int = 0

# ── Progression ───────────────────────────────────────────────────────────────
var current_village_level: int = 1
var village_items_state: Array = [0, 0, 0, 0, 0]

# ── Timestamps ────────────────────────────────────────────────────────────────
var last_login_timestamp: int = 0

# ── Shop ──────────────────────────────────────────────────────────────────────
var purchased_one_time_offers: Array = []

# ── Trainer / Dev ─────────────────────────────────────────────────────────────
var forced_outcome_id: String = ""

# ── Subsystems ────────────────────────────────────────────────────────────────
var pet_state: Dictionary = {}
var event_flags: Dictionary = {}

# ── Internal ──────────────────────────────────────────────────────────────────
var _save_version: int = SAVE_VERSION
var _is_loaded: bool = false
```

### 3.3 Signals

Declare these signals. Other systems subscribe to them to react to state changes without polling.

```gdscript
signal game_saved
signal game_loaded
signal load_failed(reason: String)
signal coins_changed(new_value: int)
signal spins_changed(new_value: int)
signal shields_changed(new_value: int)
```

### 3.4 `_ready()` Function

```gdscript
func _ready() -> void:
    # Build default sub-schemas before attempting load.
    # This ensures pet_state and event_flags are never null even if file is missing.
    _apply_defaults()
    load_game()
```

### 3.5 `_apply_defaults()` — Private Helper

This function sets the default values for complex sub-schemas. It is called by `_ready()` before `load_game()` and by `load_game()` internally to fill missing keys after parsing.

**Implement the following logic:**

1. Assign `pet_state` the default Dictionary from Section 2.2 **only if** `pet_state.is_empty()`.
2. Assign `event_flags` the default Dictionary from Section 2.3 **only if** `event_flags.is_empty()`.
3. **Do not** overwrite keys that already have data.

```gdscript
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
```

### 3.6 `_build_save_dictionary()` — Private Helper

Assembles and returns a single Dictionary containing all current runtime state. This is the object that gets serialized to JSON. No logic beyond assembly occurs here.

```gdscript
func _build_save_dictionary() -> Dictionary:
    return {
        "save_version":             _save_version,
        "coins":                    coins,
        "spins":                    spins,
        "shields":                  shields,
        "current_village_level":    current_village_level,
        "village_items_state":      village_items_state.duplicate(),
        "last_login_timestamp":     last_login_timestamp,
        "purchased_one_time_offers": purchased_one_time_offers.duplicate(),
        "forced_outcome_id":        forced_outcome_id,
        "pet_state":                pet_state.duplicate(true),
        "event_flags":              event_flags.duplicate(true)
    }
```

### 3.7 `save_game()` — Public Function

**Full logic specification:**

1. Update `last_login_timestamp` to the current Unix time using `Time.get_unix_time_from_system()`. Cast to `int`.
2. Call `_build_save_dictionary()` to get the state snapshot.
3. Call `JSON.stringify()` on the dictionary with indent parameter `"\t"` for human-readable output.
4. Open `SAVE_PATH` using `FileAccess.open(SAVE_PATH, FileAccess.WRITE)`.
5. Guard: if `FileAccess.open` returns `null`, call `push_error()` with a descriptive message including the OS error string from `FileAccess.get_open_error()`. Emit `load_failed` signal with the error string. Return early.
6. Call `file.store_string(json_string)` on the opened file handle.
7. Call `file.close()` — mandatory, do not rely on reference counting.
8. Call `_flush_indexeddb_if_html5()` (defined in Section 3.9).
9. Print a debug confirmation: `"[SaveLoadManager] Game saved. Timestamp: " + str(last_login_timestamp)`.
10. Emit `game_saved` signal.

```gdscript
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
```

### 3.8 `load_game()` — Public Function

**Full logic specification:**

1. Check if `SAVE_PATH` exists using `FileAccess.file_exists(SAVE_PATH)`. If it does not exist, call `_handle_new_player()` and return.
2. Open `SAVE_PATH` using `FileAccess.open(SAVE_PATH, FileAccess.READ)`.
3. Guard: if file handle is `null`, call `push_error()` with OS error code. Call `_handle_new_player()` and return. Do not crash.
4. Read the full file content with `file.get_as_text()`. Call `file.close()` immediately after.
5. Instantiate a `JSON` object. Call `json_parser.parse(raw_text)`. Capture the return value as `var parse_result: Error`.
6. Guard: if `parse_result != OK`, call `push_error()` with `json_parser.get_error_message()` and `json_parser.get_error_line()`. Call `_handle_corrupted_save()` and return.
7. Assign the parsed data to a local `var data: Dictionary`. Guard: if `data` is not a Dictionary type (use `data is not Dictionary`), call `_handle_corrupted_save()` and return.
8. Call `_migrate_if_needed(data)` — schema version upgrade hook (Section 3.10).
9. Call `_apply_state_from_dictionary(data)` — populates all runtime variables (Section 3.11).
10. Call `_apply_defaults()` — fills any keys missing from older save files (forward-compat).
11. Set `_is_loaded = true`.
12. Print confirmation: `"[SaveLoadManager] Game loaded. Village: " + str(current_village_level) + " Coins: " + str(coins)`.
13. Emit `game_loaded` signal.

```gdscript
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
```

### 3.9 `_flush_indexeddb_if_html5()` — Private Platform Helper

This function resolves the HTML5 IndexedDB sync problem. On all non-HTML5 platforms it is a no-op. On HTML5 it calls the Emscripten FS sync function via `JavaScriptBridge`.

**Implementation logic:**

1. Check `OS.get_name() == "Web"`. If false, return immediately.
2. Check that `JavaScriptBridge.is_js_available()` is true. If false, `push_warning()` and return.
3. Execute the following JavaScript via `JavaScriptBridge.eval()` with the `use_global_execution_context` parameter set to `true`:

```javascript
FS.syncfs(false, function(err) {
    if (err) {
        console.error('[SaveLoadManager] IndexedDB sync failed:', err);
    } else {
        console.log('[SaveLoadManager] IndexedDB sync complete.');
    }
});
```

4. The GDScript call does **not** await this callback. It is fire-and-forget. The browser handles the async completion.
5. Print a GDScript-side log: `"[SaveLoadManager] HTML5 IndexedDB sync dispatched."`.

```gdscript
func _flush_indexeddb_if_html5() -> void:
    if OS.get_name() != "Web":
        return
    if not JavaScriptBridge.is_js_available():
        push_warning("[SaveLoadManager] JavaScriptBridge unavailable. IndexedDB flush skipped.")
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
```

### 3.10 `_migrate_if_needed(data: Dictionary)` — Private Schema Migration Hook

This function future-proofs the save system. When `SAVE_VERSION` is incremented in a future release, this function applies transformations to upgrade old save files.

**Implementation logic:**

1. Read `data.get("save_version", 0)` into a local `var file_version: int`.
2. If `file_version == SAVE_VERSION`, return immediately. No migration needed.
3. If `file_version < 1`: this is a pre-versioned save. Add a log warning. No data transformation is possible—leave data as-is and let `_apply_defaults()` fill gaps.
4. Set `data["save_version"] = SAVE_VERSION` to stamp the migrated file.
5. Print: `"[SaveLoadManager] Migrated save from version %d to %d." % [file_version, SAVE_VERSION]`.

```gdscript
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
```

### 3.11 `_apply_state_from_dictionary(data: Dictionary)` — Private State Hydrator

Reads each key from the parsed Dictionary and assigns it to the corresponding runtime variable. Uses `data.get(key, fallback)` on every single field — **never** direct bracket access `data["key"]` — to prevent KeyError crashes on partially written save files.

```gdscript
func _apply_state_from_dictionary(data: Dictionary) -> void:
    coins                   = int(data.get("coins", 500))
    spins                   = int(data.get("spins", 50))
    shields                 = int(data.get("shields", 0))
    current_village_level   = int(data.get("current_village_level", 1))
    last_login_timestamp    = int(data.get("last_login_timestamp", 0))
    forced_outcome_id       = str(data.get("forced_outcome_id", ""))

    # Array fields — validate type before assigning to prevent runtime errors.
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

    # Dictionary sub-schemas — validate type before assigning.
    var raw_pets = data.get("pet_state", {})
    if raw_pets is Dictionary:
        pet_state = raw_pets
    else:
        pet_state = {}  # _apply_defaults() will rebuild.

    var raw_events = data.get("event_flags", {})
    if raw_events is Dictionary:
        event_flags = raw_events
    else:
        event_flags = {}  # _apply_defaults() will rebuild.

    # Clamp values to valid ranges immediately after loading.
    coins   = max(0, coins)
    spins   = max(0, spins)
    shields = clamp(shields, 0, 5)
    current_village_level = max(1, current_village_level)
```

### 3.12 `_handle_new_player()` — Private New Game Initializer

Called when no save file exists. Applies all defaults and immediately saves to create the file.

```gdscript
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
```

### 3.13 `_handle_corrupted_save()` — Private Corruption Recovery

Called when the save file exists but cannot be parsed. Backs up the corrupted file and resets to new player state.

```gdscript
func _handle_corrupted_save() -> void:
    push_error("[SaveLoadManager] Corrupted save detected. Backing up and resetting.")

    # Rename corrupted file for post-mortem inspection.
    var backup_path: String = "user://savegame_corrupted_%d.bak" % int(Time.get_unix_time_from_system())
    var dir: DirAccess = DirAccess.open("user://")
    if dir != null:
        dir.rename("savegame.save", backup_path.replace("user://", ""))
        print("[SaveLoadManager] Corrupted save backed up to: %s" % backup_path)

    _handle_new_player()
```

### 3.14 Public Resource Mutator Helpers

These are the **only** functions other systems call to modify resources. They enforce business rules (clamping, caps) and emit change signals so the UI layer can react without polling. Implementing these here prevents every calling system from reimplementing cap logic independently.

```gdscript
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
```

---

## SECTION 4: AUTOLOAD REGISTRATION

After writing `SaveLoadManager.gd`, add the following entry to `res://project.godot` under the `[autoload]` section. If the section does not exist, create it.

```ini
[autoload]

SaveLoadManager="*res://src/utils/SaveLoadManager.gd"
```

The `*` prefix instructs Godot to instantiate the script as a node and add it to the scene tree automatically. This makes `SaveLoadManager` accessible globally by name from any script without `get_node()`.

---

## SECTION 5: HTML5 EXPORT CONFIGURATION REQUIREMENTS

When configuring the HTML5 export preset in Godot's Export dialog, the following settings are **mandatory** for IndexedDB persistence to function:

| Setting | Required Value | Reason |
|---|---|---|
| `Vram Texture Compression → For Web` | Enabled | Reduces initial load time so FS init completes before first save |
| `HTML → Experimental Virtual Keyboard` | Disabled | Reduces JS runtime conflicts with Emscripten FS layer |
| Export template | `Web (Runnable)` debug or `Web` release | Do not use the `SharedArrayBuffer` template unless COOP/COEP headers are confirmed on the hosting server |
| Godot project setting `application/run/main_loop_type` | Default | Do not override — custom main loops can interfere with Emscripten's FS sync timing |

**Server-side header requirement for SharedArrayBuffer builds:**

If the HTML5 host serves the game with `SharedArrayBuffer` enabled (required for multi-threaded Wasm), the server **must** include these HTTP response headers or the browser will refuse to load the page:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

If hosting on a static server (GitHub Pages, Netlify) without header control, use the **non-threaded** HTML5 export template. `SaveLoadManager`'s `_flush_indexeddb_if_html5()` works correctly on both threaded and non-threaded builds.

---

## SECTION 6: UNIT TEST VERIFICATION PROTOCOL

After Cursor writes the file, manually verify these scenarios before marking Step 2 complete:

### Test A: New Player Flow
1. Delete `user://savegame.save` if it exists (use Trainer in Step 10, or delete manually from `%APPDATA%`).
2. Run the project.
3. **Expected:** Console prints `"No save file found. Initializing new player."` followed by `"Game saved."` and `"Game loaded."`.
4. **Expected:** `coins == 500`, `spins == 50`, `shields == 0`, `village_items_state == [0,0,0,0,0]`.

### Test B: Round-Trip Save/Load
1. In Godot's script debugger or via a temporary test script, call:
   ```gdscript
   SaveLoadManager.add_coins(12345)
   SaveLoadManager.save_game()
   ```
2. Restart the project (F5 stop, F5 run).
3. **Expected:** Console prints `"Game loaded."` with `Coins: 12545`.

### Test C: Corruption Recovery
1. Open `user://savegame.save` in a text editor. Delete half the content. Save.
2. Run the project.
3. **Expected:** Console prints JSON parse error, backup file created with `.bak` extension, game resets to new player defaults without crashing.

### Test D: HTML5 IndexedDB Flush (requires browser build)
1. Export to HTML5. Serve locally with `python -m http.server`.
2. Open in Chrome. Play briefly. Close tab.
3. Reopen the same URL in Chrome.
4. **Expected:** Previous coin/spin balance is retained. Browser console shows `[SaveLoadManager] IndexedDB sync complete.`.

### Test E: Shield Cap Enforcement
1. Call `SaveLoadManager.add_shields(10)`.
2. **Expected:** `SaveLoadManager.shields == 5`. No exception.

---

## SECTION 7: COMPLETION CHECKLIST

Before proceeding to Step 3, Cursor must confirm ALL of the following:

- [ ] `res://src/utils/SaveLoadManager.gd` exists
- [ ] File is registered in `project.godot` under `[autoload]` with `*` prefix
- [ ] All variables are statically typed (`var x: int`, not `var x`)
- [ ] `save_game()` updates `last_login_timestamp` before serializing
- [ ] `save_game()` calls `file.close()` before calling `_flush_indexeddb_if_html5()`
- [ ] `load_game()` uses `data.get(key, fallback)` — never bare `data["key"]`
- [ ] `load_game()` handles missing file, null file handle, JSON parse error, and non-Dictionary root as four distinct code paths
- [ ] `_flush_indexeddb_if_html5()` is a no-op on all non-Web platforms
- [ ] `_flush_indexeddb_if_html5()` checks `JavaScriptBridge.is_js_available()` before calling `eval()`
- [ ] `_handle_corrupted_save()` renames the broken file before resetting
- [ ] `add_shields()` clamps to maximum of 5
- [ ] `spend_coins()` and `spend_spins()` return `bool` and do not allow negative balances
- [ ] No scene node references (`get_node`, `$`) exist anywhere in the file
- [ ] No hardcoded balance values beyond the schema defaults defined in this spec
- [ ] Zero `.tscn` or UI files were created in this step

**DO NOT proceed to Step 3 until this checklist is fully verified.**

---

## SECTION 8: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 3 will build `res://src/core/SlotMachineLogic.gd`. It will call `SaveLoadManager.spend_spins()`, `SaveLoadManager.add_coins()`, and `SaveLoadManager.add_shields()` exclusively — never mutating `SaveLoadManager.coins` directly. It will read `SaveLoadManager.forced_outcome_id` at the start of every spin and clear it to `""` after consuming it. It will load probability data from `res://src/data/slot_weights.json` in its `_ready()` function.
```