```markdown
# step4_village_progression.md

## Technical Specification: Village Progression System
**Target Engine:** Godot 4.x  
**Execution Agent:** Cursor (AI Coder)  
**Step:** 4 of 10 — Implement `VillageManager.gd` as the primary economic resource sink.  
**Depends On:** Step 1 complete (`village_costs.json` exists). Step 2 complete (`SaveLoadManager` autoload registered).  
**Output File:** `res://src/core/VillageManager.gd`

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **ZERO UI CODE.** No `Label`, `Button`, `Tween`, `AnimationPlayer`, `Control`, or any visual Node subclass. This is pure economic logic.
- **ZERO hardcoded cost values.** Every upgrade cost must be read from `village_costs.json`. The only permitted numeric constants are structural rules: `ITEMS_PER_VILLAGE = 5`, `MAX_ITEM_LEVEL = 5`.
- **NEVER** write directly to `SaveLoadManager.coins` or `SaveLoadManager.village_items_state` via assignment from outside the mutator pattern. Use `SaveLoadManager.spend_coins()` for deductions and write to `SaveLoadManager.village_items_state` only inside `VillageManager` methods that own that responsibility.
- **STRICTLY** use static typing on every variable and function signature.
- This script is **not** an Autoload. It is instantiated as a child node of the main game scene.
- All signals carry typed data payloads. The UI layer connects to these signals. This script does not know the UI exists.
- `save_game()` must be called at the end of every function that mutates persistent state.
- Confirm with the completion checklist before proceeding to Step 5.

---

## SECTION 1: ARCHITECTURAL ROLE

`VillageManager.gd` is the **primary economic sink** of the game. It is the only system authorized to consume coins for building upgrades and to advance `current_village_level`. It enforces all upgrade cost lookups, level cap rules, and village completion logic.

### Data Flow

```
village_costs.json
       │
       ▼ (_ready)
VillageManager._village_data: Array[Dictionary]
       │
       ├──▶ can_upgrade_item(item_index) ──▶ reads SaveLoadManager.coins
       │                                      reads SaveLoadManager.current_village_level
       │                                      reads SaveLoadManager.village_items_state
       │                                      returns bool (no mutation)
       │
       └──▶ upgrade_item(item_index)
               │
               ├──▶ can_upgrade_item() guard
               ├──▶ SaveLoadManager.spend_coins(cost)
               ├──▶ SaveLoadManager.village_items_state[item_index] += 1
               ├──▶ SaveLoadManager.save_game()
               ├──▶ emit item_upgraded signal
               │
               └──▶ [if all items == MAX_ITEM_LEVEL]
                       ├──▶ SaveLoadManager.add_coins(completion_bonus)
                       ├──▶ SaveLoadManager.current_village_level += 1
                       ├──▶ SaveLoadManager.village_items_state = [0,0,0,0,0]
                       ├──▶ SaveLoadManager.save_game()
                       └──▶ emit village_completed signal
```

### Interaction Contract With Other Systems

| System | Interaction Type | Details |
|---|---|---|
| `SaveLoadManager` | **Reads:** `coins`, `current_village_level`, `village_items_state` | Direct property access (read-only outside mutator calls) |
| `SaveLoadManager` | **Writes:** via `spend_coins()`, `add_coins()` | Never direct assignment to `coins` |
| `SaveLoadManager` | **Writes:** `village_items_state` element | Only inside `upgrade_item()` and `_execute_village_completion()` |
| `SaveLoadManager` | **Writes:** `current_village_level` | Only inside `_execute_village_completion()` |
| `SaveLoadManager` | **Calls:** `save_game()` | After every state mutation |
| `VillageUI` (Step 6) | **Connects to signals** | Reads query functions to render upgrade buttons |
| `SlotMachineLogic` | No direct interaction | Economy is separate. Coins flow in from slot; VillageManager drains them. |

---

## SECTION 2: CONSTANTS

Declare the following constants at the top of the file. These are the **only** permitted hardcoded numeric values.

```gdscript
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
```

---

## SECTION 3: FULL GDSCRIPT IMPLEMENTATION SPEC

Write `res://src/core/VillageManager.gd` with exactly the following structure. Implement every function described.

### 3.1 File Header and Class Declaration

```gdscript
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
```

### 3.2 Signals

```gdscript
## Emitted when a single item is successfully upgraded.
## item_index: which of the 5 items (0-4) was upgraded.
## new_level: the item's level after upgrade (1-5).
## cost_paid: exact coin amount deducted for this upgrade.
signal item_upgraded(item_index: int, new_level: int, cost_paid: int)

## Emitted when all 5 items in a village reach MAX_ITEM_LEVEL.
## completed_village_level: the village number that was just finished (1-indexed).
## new_village_level: the village the player has advanced to.
## bonus_coins_awarded: the coin reward granted for completion.
signal village_completed(completed_village_level: int, new_village_level: int, bonus_coins_awarded: int)

## Emitted when upgrade_item() is called but can_upgrade_item() returns false.
## Provides a machine-readable reason for UI to display contextual feedback.
## reason: "insufficient_coins" | "item_already_maxed" | "not_initialized" | "invalid_index"
signal upgrade_failed(item_index: int, reason: String)

## Emitted when the config file loads successfully or fails.
## success: false if initialization failed. UI may wish to disable shop entirely.
signal initialized(success: bool)
```

### 3.3 Private State Variables

```gdscript
## Full parsed village data array from village_costs.json.
## Index 0 = village id 1, index 1 = village id 2, etc.
## Each element is a Dictionary matching the JSON schema from Step 1.
var _village_data: Array[Dictionary] = []

## Tracks whether _ready() successfully loaded and validated the config.
## All public methods are no-ops and return safe defaults if false.
var _is_initialized: bool = false

## Cache of the total cumulative cost of the currently active village.
## Recomputed every time current_village_level changes.
## Used to calculate the completion bonus without re-iterating all items.
var _current_village_total_cost: int = 0
```

### 3.4 `_ready()` Function

```gdscript
func _ready() -> void:
    _load_village_config()
```

### 3.5 `_load_village_config()` — Private Loader

**Full logic specification:**

1. Open `VILLAGE_COSTS_PATH` with `FileAccess.open(VILLAGE_COSTS_PATH, FileAccess.READ)`. Guard: if null, `push_error()` with OS error. Emit `initialized(false)`. Return.
2. Read full content with `get_as_text()`. Close file immediately.
3. Parse with `JSON.new()`. Guard: if parse result is not `OK`, `push_error()` with line and message. Emit `initialized(false)`. Return.
4. Retrieve parsed data. Guard: if root is not a Dictionary, `push_error()`. Emit `initialized(false)`. Return.
5. Read `data.get("villages", null)`. Guard: if not an Array or empty, `push_error()`. Emit `initialized(false)`. Return.
6. Iterate over each village element. For each:
   - Guard: must be a Dictionary with keys `id`, `name`, `items`.
   - Guard: `items` must be an Array of exactly `ITEMS_PER_VILLAGE` elements.
   - For each item in `items`: must have keys `item_index`, `label`, `upgrade_costs`. `upgrade_costs` must be an Array of exactly `MAX_ITEM_LEVEL` integers.
   - Skip malformed villages with `push_warning()`. Do not crash.
   - Append valid village Dictionaries to `_village_data`.
7. Guard: if `_village_data.is_empty()`, `push_error()`. Emit `initialized(false)`. Return.
8. Call `_cache_current_village_total_cost()`.
9. Set `_is_initialized = true`.
10. Emit `initialized(true)`.
11. Print: `"[VillageManager] Loaded %d villages." % _village_data.size()`.

```gdscript
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
```

---

## SECTION 4: CORE PUBLIC API

### 4.1 `can_upgrade_item(item_index: int) -> bool`

**Purpose:** Pure read-only query. No state mutation. Safe to call every frame for UI button state. Returns `true` only when ALL of the following conditions are satisfied simultaneously.

**Conditions (all must pass):**

1. `_is_initialized == true`
2. `item_index >= 0 AND item_index < ITEMS_PER_VILLAGE`
3. Current item level from `SaveLoadManager.village_items_state[item_index]` is strictly less than `MAX_ITEM_LEVEL` (item is not already complete)
4. `SaveLoadManager.coins >= _get_upgrade_cost(item_index)` (player can afford it)
5. The current village level exists in `_village_data` (not beyond loaded data range)

If any condition fails, return `false`. Do not emit signals. Do not log. This function is called constantly by UI.

```gdscript
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
```

### 4.2 `upgrade_item(item_index: int) -> void`

**Purpose:** The single entry point for all upgrade purchase actions. Enforces the full upgrade transaction atomically.

**Full logic specification (execute in this exact order):**

**Guard Block:**

1. If `not _is_initialized`: emit `upgrade_failed(item_index, "not_initialized")`. Return.
2. If `item_index < 0 or item_index >= ITEMS_PER_VILLAGE`: emit `upgrade_failed(item_index, "invalid_index")`. Return.
3. Read current level: `var current_level: int = int(SaveLoadManager.village_items_state[item_index])`.
4. If `current_level >= MAX_ITEM_LEVEL`: emit `upgrade_failed(item_index, "item_already_maxed")`. Return.
5. Call `_get_upgrade_cost(item_index)` to get `var cost: int`.
6. If `cost < 0`: emit `upgrade_failed(item_index, "not_initialized")`. Push error. Return.
7. Call `SaveLoadManager.spend_coins(cost)`. If it returns `false` (insufficient coins): emit `upgrade_failed(item_index, "insufficient_coins")`. Return.

**State Mutation (execute only after all guards pass and coins deducted):**

8. Increment the item level: `SaveLoadManager.village_items_state[item_index] = current_level + 1`.
9. Read the new level into `var new_level: int = current_level + 1`.
10. Call `SaveLoadManager.save_game()`.
11. Emit `item_upgraded(item_index, new_level, cost)`.
12. Print: `"[VillageManager] Item %d upgraded to level %d. Cost: %d. Coins remaining: %d"`.

**Completion Check (execute after item_upgraded signal):**

13. Call `_check_village_completion()`.

```gdscript
func upgrade_item(item_index: int) -> void:
    # ── Guard Block ───────────────────────────────────────────────────────────
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

    # ── State Mutation ────────────────────────────────────────────────────────
    var new_level: int = current_level + 1
    SaveLoadManager.village_items_state[item_index] = new_level

    SaveLoadManager.save_game()

    emit_signal("item_upgraded", item_index, new_level, cost)

    print("[VillageManager] Item %d upgraded to level %d. Cost: %d. Coins remaining: %d" % [
        item_index, new_level, cost, SaveLoadManager.coins
    ])

    # ── Completion Check ──────────────────────────────────────────────────────
    _check_village_completion()
```

---

## SECTION 5: PRIVATE LOGIC FUNCTIONS

### 5.1 `_check_village_completion()` — Private Completion Evaluator

**Logic:** Iterates `SaveLoadManager.village_items_state`. If every element equals `MAX_ITEM_LEVEL`, calls `_execute_village_completion()`. Otherwise returns silently.

```gdscript
func _check_village_completion() -> void:
    var items_state: Array = SaveLoadManager.village_items_state
    for i in range(ITEMS_PER_VILLAGE):
        if int(items_state[i]) < MAX_ITEM_LEVEL:
            return
    # All items are at MAX_ITEM_LEVEL.
    _execute_village_completion()
```

### 5.2 `_execute_village_completion()` — Private Completion Handler

**Full logic specification (execute in this exact order):**

1. Snapshot `var completed_level: int = SaveLoadManager.current_village_level` before incrementing.
2. Calculate completion bonus: `var bonus: int = int(float(_current_village_total_cost) * COMPLETION_BONUS_MULTIPLIER)`. Clamp to minimum of `1` to prevent zero bonus edge case.
3. Call `SaveLoadManager.add_coins(bonus)`.
4. Increment village level: `SaveLoadManager.current_village_level += 1`.
5. Reset items array: `SaveLoadManager.village_items_state = [0, 0, 0, 0, 0]`.
6. Call `_cache_current_village_total_cost()` to recompute the cache for the new village.
7. Call `SaveLoadManager.save_game()`.
8. Emit `village_completed(completed_level, SaveLoadManager.current_village_level, bonus)`.
9. Print: `"[VillageManager] Village %d COMPLETED. Bonus: %d coins. Advancing to village %d."`.

```gdscript
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
```

### 5.3 `_get_upgrade_cost(item_index: int) -> int` — Private Cost Resolver

Resolves the exact coin cost for upgrading a specific item from its current level to the next. Returns `-1` on any error condition (caller must guard against this).

**Logic:**

1. Call `_get_current_village_index()` to get `var village_index: int`. If `-1`, return `-1`.
2. Retrieve the village Dictionary: `_village_data[village_index]`.
3. Retrieve the `items` Array from the village Dictionary.
4. Guard: `item_index` must be a valid index in `items`. If not, return `-1`.
5. Retrieve the specific item Dictionary at `items[item_index]`.
6. Retrieve `upgrade_costs` Array from the item.
7. Read current level from `SaveLoadManager.village_items_state[item_index]`. This is the **0-indexed cost array index** — level 0 costs `upgrade_costs[0]`, level 1 costs `upgrade_costs[1]`, etc.
8. Guard: if `current_level >= MAX_ITEM_LEVEL`, return `-1` (item already maxed, no cost to resolve).
9. Guard: if `current_level >= upgrade_costs.size()`, return `-1` (array bounds safety).
10. Return `int(upgrade_costs[current_level])`.

```gdscript
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
```

### 5.4 `_get_current_village_index() -> int` — Private Index Resolver

Converts the 1-indexed `SaveLoadManager.current_village_level` to a 0-indexed array position in `_village_data`. Returns `-1` if the current village level exceeds the loaded data range (player is beyond all defined villages).

```gdscript
func _get_current_village_index() -> int:
    var index: int = SaveLoadManager.current_village_level - 1
    if index < 0 or index >= _village_data.size():
        return -1
    return index
```

### 5.5 `_cache_current_village_total_cost()` — Private Cost Cache Builder

Computes and caches the total cumulative coin cost to fully upgrade all items in the current village from level 0 to level 5. Used for completion bonus calculation. Called once at initialization and again each time the village advances.

**Logic:** Sum every integer in every `upgrade_costs` array across all 5 items for the current village. Store result in `_current_village_total_cost`. If village index is invalid (player is beyond loaded data), set cache to `0` and log a warning — this is non-fatal.

```gdscript
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
```

---

## SECTION 6: PUBLIC QUERY API (READ-ONLY, NO MUTATION)

These functions allow UI and other systems to read village state without triggering mutations. Safe to call every frame.

### 6.1 `get_item_current_level(item_index: int) -> int`

Returns current upgrade level (0–5) for the given item. Returns `-1` if index is invalid.

```gdscript
func get_item_current_level(item_index: int) -> int:
    if not _is_initialized:
        return -1
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return -1
    return int(SaveLoadManager.village_items_state[item_index])
```

### 6.2 `get_item_upgrade_cost(item_index: int) -> int`

Returns the coin cost to upgrade the given item to its next level. Returns `-1` if the item is maxed or index is invalid. UI uses this to display cost labels on upgrade buttons.

```gdscript
func get_item_upgrade_cost(item_index: int) -> int:
    if not _is_initialized:
        return -1
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return -1
    return _get_upgrade_cost(item_index)
```

### 6.3 `get_item_label(item_index: int) -> String`

Returns the display name of the item at the given index for the current village. Returns an empty String if not found.

```gdscript
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
```

### 6.4 `get_current_village_name() -> String`

Returns the thematic name of the current village. Returns empty String if beyond loaded data.

```gdscript
func get_current_village_name() -> String:
    if not _is_initialized:
        return ""
    var village_index: int = _get_current_village_index()
    if village_index < 0:
        return "Unknown Village"
    return str(_village_data[village_index].get("name", ""))
```

### 6.5 `get_village_completion_percentage() -> float`

Returns a float from `0.0` to `1.0` representing the fraction of total upgrade levels completed in the current village. Used by UI progress bars. Each of 5 items has 5 levels, so total possible = 25 level-points.

```gdscript
func get_village_completion_percentage() -> float:
    if not _is_initialized:
        return 0.0
    var total_possible: int = ITEMS_PER_VILLAGE * MAX_ITEM_LEVEL
    var total_achieved: int = 0
    for i in range(ITEMS_PER_VILLAGE):
        total_achieved += int(SaveLoadManager.village_items_state[i])
    return float(total_achieved) / float(total_possible)
```

### 6.6 `get_completion_bonus_preview() -> int`

Returns the coin bonus the player would receive if they completed the current village right now. UI uses this to display the completion reward without triggering it.

```gdscript
func get_completion_bonus_preview() -> int:
    return max(1, int(float(_current_village_total_cost) * COMPLETION_BONUS_MULTIPLIER))
```

### 6.7 `is_item_maxed(item_index: int) -> bool`

Returns `true` if the item at `item_index` is already at `MAX_ITEM_LEVEL`. UI uses this to grey out upgrade buttons.

```gdscript
func is_item_maxed(item_index: int) -> bool:
    if item_index < 0 or item_index >= ITEMS_PER_VILLAGE:
        return false
    return int(SaveLoadManager.village_items_state[item_index]) >= MAX_ITEM_LEVEL
```

### 6.8 `is_village_data_available_for_level(village_level: int) -> bool`

Returns `true` if the given village level has a corresponding entry in the loaded data. UI uses this to warn the player when they have progressed beyond defined content.

```gdscript
func is_village_data_available_for_level(village_level: int) -> bool:
    if not _is_initialized:
        return false
    var index: int = village_level - 1
    return index >= 0 and index < _village_data.size()
```

### 6.9 `is_initialized() -> bool`

```gdscript
func is_initialized() -> bool:
    return _is_initialized
```

---

## SECTION 7: EDGE CASE REGISTRY

| Edge Case | Trigger Condition | Handling |
|---|---|---|
| **Player at max village** | `current_village_level` exceeds `_village_data.size()` | `_get_current_village_index()` returns `-1`. All cost lookups return `-1`. `can_upgrade_item()` returns `false`. Game shows "no more content" state without crashing. |
| **Simultaneous maxed items** | All 5 items reach level 5 in the same `upgrade_item()` call | `_check_village_completion()` evaluates all 5 after the mutation. Fires once. No double-fire risk because `village_items_state` is reset before next possible check. |
| **Direct array write safety** | `SaveLoadManager.village_items_state` is an `Array`, not `Array[int]` | All reads must use `int(...)` cast. All writes must be integers. Never assume type from JSON-loaded data. |
| **Bonus on final village** | Player completes last defined village | `_execute_village_completion()` increments `current_village_level` beyond data. Cache sets to `0`. All queries return graceful defaults. Game does not crash. |
| **Corrupted items state** | `village_items_state` loaded with wrong size or non-integer values | `int(SaveLoadManager.village_items_state[i])` casts silently. If size is wrong, index guards in `can_upgrade_item()` and `_get_upgrade_cost()` catch out-of-range access. |
| **spend_coins() race condition** | UI calls `upgrade_item()` twice before first save completes | GDScript is single-threaded. The second call enters the guard block, finds coins already deducted by first call, `spend_coins()` returns `false`, emits `upgrade_failed`. No double-spend. |
| **Zero cost village item** | JSON contains `"upgrade_costs": [0, 0, 0, 0, 0]` | `spend_coins(0)` succeeds trivially. Upgrade proceeds. `_cache_current_village_total_cost()` includes zeros in sum. Bonus calculated on zero total = zero (min clamped to 1). |
| **NaN or float in JSON costs** | JSON has `"upgrade_costs": [1.5, ...]` | `int(upgrade_costs[current_level])` truncates to integer. No crash. Cost is floored. |
| **Negative item_index from UI** | UI passes `-1` via accident | Guard `item_index < 0` catches it. Emits `upgrade_failed` with `"invalid_index"`. |

---

## SECTION 8: UPGRADE TRANSACTION ATOMICITY CONTRACT

The upgrade transaction must be treated as atomic: **either all steps succeed or no state changes at all.**

The ordering in `upgrade_item()` enforces this:

```
1. ALL guards evaluated        → No state touched yet
2. spend_coins() called        → Coins deducted (point of no return)
3. village_items_state mutated → Level incremented
4. save_game() called          → State persisted
5. Signals emitted             → Observers notified
```

If the game crashes between steps 2 and 4 (extremely rare in single-threaded GDScript but possible via OS kill), the player loses the coins but does not gain the level. This is acceptable — the alternative (level gained without coin deduction) would be economically exploitable. Step 4 (`save_game()`) is called as early as safely possible to minimize this window.

**DO NOT** reorder these steps for any reason.

---

## SECTION 9: UNIT TEST VERIFICATION PROTOCOL

### Test A: Initialization
1. Run project.
2. **Expected:** Console prints `"[VillageManager] Loaded 10 villages successfully."`.
3. **Expected:** `village_manager.is_initialized() == true`.
4. **Expected:** `initialized` signal fires with `true`.

### Test B: Cost Query Accuracy
1. Ensure `SaveLoadManager.current_village_level == 1` and `SaveLoadManager.village_items_state == [0,0,0,0,0]`.
2. Call `village_manager.get_item_upgrade_cost(0)`.
3. **Expected:** Returns `155000` (matches `village_costs.json` village 1, item 0, upgrade_costs[0]).
4. Set `SaveLoadManager.village_items_state[0] = 2`.
5. **Expected:** `get_item_upgrade_cost(0)` returns `310000` (upgrade_costs[2]).

### Test C: Insufficient Coins Block
1. Set `SaveLoadManager.coins = 0` via Trainer.
2. Call `village_manager.upgrade_item(0)`.
3. **Expected:** `upgrade_failed` signal fires with `"insufficient_coins"`.
4. **Expected:** `SaveLoadManager.village_items_state[0]` unchanged.

### Test D: Successful Upgrade Round-Trip
1. Set `SaveLoadManager.coins = 500000`.
2. Call `village_manager.upgrade_item(0)` (cost = 155000 for level 0→1).
3. **Expected:** `SaveLoadManager.coins == 345000`.
4. **Expected:** `SaveLoadManager.village_items_state[0] == 1`.
5. **Expected:** `item_upgraded` signal fires with `item_index=0, new_level=1, cost_paid=155000`.
6. **Expected:** `SaveLoadManager.save_game()` was called (check log for save confirmation).

### Test E: Village Completion Flow
1. Set `SaveLoadManager.current_village_level = 1`.
2. Set `SaveLoadManager.village_items_state = [4, 5, 5, 5, 5]` (one item at level 4, rest maxed).
3. Set `SaveLoadManager.coins = 999999999`.
4. Call `village_manager.upgrade_item(0)` (upgrades item 0 from level 4 to 5).
5. **Expected:** All 5 items now at level 5. `_check_village_completion()` fires.
6. **Expected:** `village_completed` signal fires with `completed_village_level=1, new_village_level=2`.
7. **Expected:** `SaveLoadManager.current_village_level == 2`.
8. **Expected:** `SaveLoadManager.village_items_state == [0, 0, 0, 0, 0]`.
9. **Expected:** `SaveLoadManager.coins` increased by the completion bonus.
10. **Expected:** Console prints completion message with bonus amount.

### Test F: Maxed Item Rejection
1. Set `SaveLoadManager.village_items_state[2] = 5`.
2. Call `village_manager.upgrade_item(2)`.
3. **Expected:** `upgrade_failed` signal fires with `"item_already_maxed"`.
4. **Expected:** Coins unchanged.

### Test G: Beyond-Data Village Graceful Handling
1. Set `SaveLoadManager.current_village_level = 999`.
2. Call `village_manager.can_upgrade_item(0)`.
3. **Expected:** Returns `false`. No crash. No error log (only a warning is acceptable).
4. Call `village_manager.get_current_village_name()`.
5. **Expected:** Returns `"Unknown Village"`. No crash.

### Test H: Completion Bonus Calculation
1. Set `SaveLoadManager.current_village_level = 1`.
2. Village 1 total cost = sum of all upgrade_costs across 5 items = `(155000+232500+310000+387500+465000) + (186000+279000+372000+465000+558000) + (232000+348000+464000+580000+696000) + (210000+315000+420000+525000+630000) + (263000+394500+526000+657500+789000)` = `9,460,000`.
3. Expected bonus = `int(9460000.0 * 0.25)` = `2,365,000`.
4. Complete village (set all items to 5, trigger completion).
5. **Expected:** Coins increased by exactly `2,365,000`.

---

## SECTION 10: COMPLETION CHECKLIST

Before proceeding to Step 5, Cursor must confirm ALL of the following:

- [ ] `res://src/core/VillageManager.gd` exists with `class_name VillageManager`
- [ ] File is **NOT** registered as an Autoload in `project.godot`
- [ ] Zero UI node references exist anywhere in the file
- [ ] `_load_village_config()` guards against: null file handle, JSON parse error, non-Dictionary root, missing `"villages"` key, wrong item count per village, wrong upgrade_costs array length per item
- [ ] `can_upgrade_item()` contains zero state mutations — pure read-only query
- [ ] `upgrade_item()` calls `spend_coins()` before mutating `village_items_state` — no exceptions
- [ ] `upgrade_item()` calls `save_game()` immediately after mutating `village_items_state` — before any signals
- [ ] `_check_village_completion()` only fires `_execute_village_completion()` when all 5 items equal `MAX_ITEM_LEVEL`
- [ ] `_execute_village_completion()` resets `village_items_state` to exactly `[0, 0, 0, 0, 0]`
- [ ] `_execute_village_completion()` calls `_cache_current_village_total_cost()` after incrementing village level
- [ ] `_execute_village_completion()` calls `save_game()` after all mutations and before emitting `village_completed`
- [ ] `_get_upgrade_cost()` uses `current_level` as the 0-indexed array position into `upgrade_costs`
- [ ] `_get_upgrade_cost()` returns `-1` for maxed items, invalid index, and out-of-range village
- [ ] Completion bonus uses `COMPLETION_BONUS_MULTIPLIER` constant — no magic float literal
- [ ] Completion bonus is clamped to minimum of `1` via `max(1, ...)`
- [ ] All 4 signals declared with typed parameters: `item_upgraded`, `village_completed`, `upgrade_failed`, `initialized`
- [ ] All variables and function signatures use static typing
- [ ] No hardcoded cost integers anywhere in the file

**DO NOT proceed to Step 5 until this checklist is fully verified.**

---

## SECTION 11: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 5 will build `res://src/entities/NPCSimulator.gd`. It will implement `calculate_offline_events()` called by `SaveLoadManager` on game load using `last_login_timestamp` delta. It will implement `generate_raid_target() -> Dictionary` called by `SlotMachineLogic` when `raid_triggered` signal fires. It will read `SaveLoadManager.shields`, call `SaveLoadManager.consume_shield()`, and optionally call `SaveLoadManager.spend_coins()` for successful attacks. It will use a Poisson-approximated probability model to determine how many NPC attacks occurred while the player was offline.
```