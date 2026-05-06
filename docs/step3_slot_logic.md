```markdown
# step3_slot_logic.md

## Technical Specification: Slot Machine Logic Engine
**Target Engine:** Godot 4.x  
**Execution Agent:** Cursor (AI Coder)  
**Step:** 3 of 10 — Implement `SlotMachineLogic.gd` as a pure math core system.  
**Depends On:** Step 1 complete (`slot_weights.json` exists). Step 2 complete (`SaveLoadManager` autoload registered).  
**Output File:** `res://src/core/SlotMachineLogic.gd`

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **ZERO UI CODE.** No `Label`, `Button`, `Tween`, `AnimationPlayer`, `CanvasItem`, `Control`, or any Node subclass that renders to screen. This file is pure mathematical simulation.
- **ZERO hardcoded balance values.** All weights, reward values, and caps must be read from `slot_weights.json`. The only exception is the shield cap integer `5`, which is a game rule constant declared as a named constant, not a magic number.
- **NEVER** access `SaveLoadManager.coins` directly via assignment (`SaveLoadManager.coins = x`). Use **only** the public mutator functions: `add_coins()`, `spend_coins()`, `add_spins()`, `spend_spins()`, `add_shields()`.
- **STRICTLY** use static typing on every variable and function signature.
- This script is **not** an Autoload. It is instantiated as a child node of the main game scene and accessed via a node reference or a group query. Do not register it in `project.godot`.
- All signals emitted by this script carry data payloads. The UI layer in Step 6 will connect to these signals. This script does **not** know the UI exists.
- Confirm with the completion checklist before proceeding to Step 4.

---

## SECTION 1: ARCHITECTURAL ROLE

`SlotMachineLogic.gd` is the **resource faucet** of the game economy. It is the only system authorized to award coins, spins, shields from a spin action. It enforces all spin-cost deductions and all outcome business rules.

### Data Flow

```
slot_weights.json
       │
       ▼ (_ready)
SlotMachineLogic._outcome_table: Array[Dictionary]
SlotMachineLogic._weight_sum: int
       │
       ▼ (spin_reels called)
SaveLoadManager.forced_outcome_id ──▶ [Override Path]
       │                                     │
       ▼ (normal path)                       │
PRNG weighted selection                      │
       │◀───────────────────────────────────┘
       ▼
Outcome Dictionary selected
       │
       ├──▶ [Shield Cap Check] ──▶ [Intercept: refund spin + award coin compensation]
       │
       ▼
SaveLoadManager mutators called
       │
       ▼
Result Dictionary returned to caller (UI layer)
Signals emitted
```

### Interaction Contract With Other Systems

| System | Interaction Type | Details |
|---|---|---|
| `SaveLoadManager` | **Reads:** `spins`, `shields`, `forced_outcome_id` | Via direct property access (read-only) |
| `SaveLoadManager` | **Writes:** via mutators only | `spend_spins()`, `add_coins()`, `add_spins()`, `add_shields()` |
| `SaveLoadManager` | **Writes:** `forced_outcome_id` clear | Set to `""` after consuming override |
| `NPCSimulator` | **Calls:** `get_raid_outcome()` | Raid results trigger NPC simulation |
| `PetManager` | **Called by:** `SlotMachineLogic` after raid/attack outcomes | Checks if Foxy/Tiger pet buff is active |
| `SlotMachineUI` (Step 6) | **Connects to signals** | Never calls into UI from here |

---

## SECTION 2: CONSTANTS AND CONFIGURATION

Declare the following constants at the top of the file beneath the class declaration. These are the **only** permitted hardcoded values.

```gdscript
## Maximum number of shields a player can hold simultaneously.
## Sourced from slot_weights.json max_held field, but also declared here
## as a named constant for defensive guard clarity.
const SHIELD_MAX_HELD: int = 5

## Path to the weighted probability configuration file.
const WEIGHTS_CONFIG_PATH: String = "res://src/data/slot_weights.json"

## Coin compensation awarded when a shield outcome is intercepted due to cap.
## This value is read from the "coins_small" outcome reward_value in the JSON.
## The constant name is used in code; the value is populated at runtime from JSON.
## DO NOT assign a literal integer here. Assign in _ready() after JSON load.
var _shield_overflow_coin_compensation: int = 0
```

---

## SECTION 3: FULL GDSCRIPT IMPLEMENTATION SPEC

Write the file `res://src/core/SlotMachineLogic.gd` with exactly the following structure. Implement every function described. Do not add functions beyond what is specified.

### 3.1 File Header and Class Declaration

```gdscript
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
```

### 3.2 Signals

Declare all signals with full typed payloads. The UI layer connects to these in Step 6. This script emits them; it never reads them.

```gdscript
## Emitted when a spin completes successfully. Carries the full result payload.
## result keys: outcome_id, reward_type, reward_value, reward_tier,
##              bet_multiplier, was_intercepted, compensation_coins
signal spin_completed(result: Dictionary)

## Emitted when spin_reels() is called but the player has insufficient spins.
signal spin_failed_insufficient_spins(required: int, available: int)

## Emitted when a shield outcome is intercepted due to max capacity.
## UI uses this to show a specific "shield full" notification.
signal shield_overflow_intercepted(compensation_coins: int)

## Emitted when the forced_outcome_id override is consumed.
## TrainerConsole listens to confirm override was applied.
signal rng_override_consumed(outcome_id: String)

## Emitted after every spin that results in a Raid outcome.
## NPCSimulator connects to this to begin raid target generation.
signal raid_triggered(raid_count: int)

## Emitted after every spin that results in an Attack outcome.
## NPCSimulator connects to this to begin attack target generation.
signal attack_triggered(attack_count: int)
```

### 3.3 Private State Variables

```gdscript
## The fully parsed and validated outcome table loaded from slot_weights.json.
## Each element is one outcome Dictionary matching the JSON schema from Step 1.
var _outcome_table: Array[Dictionary] = []

## The sum of all weight integers in _outcome_table.
## Computed once at load time. Used as the modulus for PRNG selection.
var _weight_sum: int = 0

## Tracks whether _ready() successfully loaded and validated the config.
## spin_reels() is a no-op and returns an error dict if this is false.
var _is_initialized: bool = false

## Cache of the RandomNumberGenerator instance.
## Seeded once at _ready() using Time for non-deterministic play sessions.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
```

### 3.4 `_ready()` Function

```gdscript
func _ready() -> void:
    _rng.randomize()
    _load_weights_config()
```

### 3.5 `_load_weights_config()` — Private Loader

**Full logic specification:**

1. Open `WEIGHTS_CONFIG_PATH` using `FileAccess.open()` with `FileAccess.READ`. Guard: if null, `push_error()` with OS error code. Set `_is_initialized = false`. Return.
2. Read full text with `get_as_text()`. Close file immediately.
3. Parse with `JSON.new()`. Guard: if parse result is not `OK`, `push_error()` with line and message. Return.
4. Retrieve parsed data. Guard: if root is not a Dictionary, `push_error()`. Return.
5. Read `data["outcomes"]`. Guard: if not an Array or empty, `push_error()`. Return.
6. Iterate over each element. Guard: skip any element that is not a Dictionary or is missing any of the seven required keys (`id`, `label`, `weight`, `reward_type`, `reward_value`, `reward_tier`, `three_of_a_kind_only`). Log a warning for each skipped element.
7. Append valid elements to `_outcome_table`.
8. Compute `_weight_sum` by summing the `weight` field of every element in `_outcome_table`.
9. Guard: if `_weight_sum == 0`, `push_error("Weight sum is zero. slot_weights.json is invalid.")`. Return.
10. Extract `_shield_overflow_coin_compensation` by finding the element in `_outcome_table` where `id == "coins_small"` and reading its `reward_value`. If not found, default to `50` and `push_warning()`.
11. Set `_is_initialized = true`.
12. Print: `"[SlotMachineLogic] Loaded %d outcomes. Total weight: %d." % [_outcome_table.size(), _weight_sum]`.

```gdscript
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
    _shield_overflow_coin_compensation = 50  # Safe default.
    for outcome in _outcome_table:
        if str(outcome["id"]) == "coins_small":
            _shield_overflow_coin_compensation = int(outcome["reward_value"])
            break
    if _shield_overflow_coin_compensation == 50:
        push_warning("[SlotMachineLogic] 'coins_small' outcome not found in table. Using fallback compensation: 50.")

    _is_initialized = true
    print("[SlotMachineLogic] Initialized. Outcomes: %d | Weight sum: %d | Shield compensation: %d" % [
        _outcome_table.size(), _weight_sum, _shield_overflow_coin_compensation
    ])
```

---

## SECTION 4: CORE PUBLIC API

### 4.1 `spin_reels(bet_multiplier: int) -> Dictionary`

This is the **single entry point** for all spin actions. It is called by the UI layer (Step 6). It returns a result Dictionary that the UI uses to drive animation and feedback. All resource mutation occurs inside this function via `SaveLoadManager` mutators.

#### Return Dictionary Schema

```
KEY                 TYPE        DESCRIPTION
────────────────────────────────────────────────────────────────────────────
"success"           bool        False if spin was blocked (insufficient spins,
                                not initialized). UI must check this first.
"outcome_id"        String      The id field of the selected outcome.
                                Empty string if success == false.
"reward_type"       String      The reward_type of the outcome. Empty if failed.
"reward_value"      int         Final awarded amount (after bet_multiplier applied
                                to coin outcomes). 0 if failed or intercepted.
"reward_tier"       String      Animation intensity hint for UI: small/medium/
                                large/jackpot. Empty if failed.
"bet_multiplier"    int         Echo of the input parameter.
"was_intercepted"   bool        True if shield cap triggered and outcome was
                                replaced with coin compensation.
"compensation_coins" int        Coin amount awarded during interception.
                                0 if was_intercepted == false.
"error_reason"      String      Human-readable failure reason. Empty if success.
"triggers_raid"     bool        True if outcome resulted in a raid event.
"triggers_attack"   bool        True if outcome resulted in an attack event.
```

#### Full Logic Specification

Implement `spin_reels()` with exactly the following ordered logic:

**Guard Block (execute before any state mutation):**

1. If `_is_initialized == false`: return `_build_failure_dict(bet_multiplier, "SlotMachineLogic not initialized.")`.
2. If `bet_multiplier < 1`: clamp to `1` and `push_warning()`. Do not reject.
3. If `SaveLoadManager.spins < bet_multiplier`: emit `spin_failed_insufficient_spins(bet_multiplier, SaveLoadManager.spins)`. Return `_build_failure_dict(bet_multiplier, "Insufficient spins.")`.

**Spin Cost Deduction (execute atomically before outcome selection):**

4. Call `SaveLoadManager.spend_spins(bet_multiplier)`. This is non-negotiable — cost is deducted before outcome is known, matching the economic model of the reference game. The `spend_spins()` call will always succeed here because the guard in step 3 already confirmed sufficiency.

**Outcome Selection:**

5. Call `_resolve_outcome_id()` (Section 4.2). This returns one outcome Dictionary from `_outcome_table`.

**Shield Cap Interception (execute before resource award):**

6. If `selected_outcome["reward_type"] == "shield"`:
   - Read `SaveLoadManager.shields`.
   - If `shields >= SHIELD_MAX_HELD`:
     - Refund the spin: call `SaveLoadManager.add_spins(bet_multiplier)`.
     - Award compensation: call `SaveLoadManager.add_coins(_shield_overflow_coin_compensation)`.
     - Emit `shield_overflow_intercepted(_shield_overflow_coin_compensation)`.
     - Build and return an interception result Dictionary (see step 11 for structure). Set `was_intercepted = true`, `compensation_coins = _shield_overflow_coin_compensation`, `reward_value = 0`.

**Resource Award (execute only if not intercepted):**

7. Compute `final_reward_value: int`:
   - If `reward_type == "coins"`: `final_reward_value = int(selected_outcome["reward_value"]) * bet_multiplier`.
   - If `reward_type == "spins"`: `final_reward_value = int(selected_outcome["reward_value"])`. Do **not** multiply spins by `bet_multiplier`.
   - If `reward_type == "shield"`: `final_reward_value = int(selected_outcome["reward_value"])`.
   - If `reward_type == "attack"`: `final_reward_value = int(selected_outcome["reward_value"])`.
   - If `reward_type == "raid"`: `final_reward_value = int(selected_outcome["reward_value"])`.

8. Call the appropriate `SaveLoadManager` mutator:
   - `"coins"` → `SaveLoadManager.add_coins(final_reward_value)`
   - `"spins"` → `SaveLoadManager.add_spins(final_reward_value)`
   - `"shield"` → `SaveLoadManager.add_shields(final_reward_value)`
   - `"attack"` → No SaveLoadManager mutation. Attack count passed to NPC system via signal.
   - `"raid"` → No SaveLoadManager mutation. Raid count passed to NPC system via signal.

**Post-Award Signal Emission:**

9. If `reward_type == "raid"`: emit `raid_triggered(final_reward_value)`.
10. If `reward_type == "attack"`: emit `attack_triggered(final_reward_value)`.

**Result Construction and Return:**

11. Build the result Dictionary with all fields from the schema above. Set `success = true`, `was_intercepted = false`, `compensation_coins = 0`, `error_reason = ""`.
12. Call `SaveLoadManager.save_game()`.
13. Emit `spin_completed(result)`.
14. Return `result`.

```gdscript
func spin_reels(bet_multiplier: int) -> Dictionary:
    # ── Guard Block ───────────────────────────────────────────────────────────
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

    # ── Spin Cost Deduction ───────────────────────────────────────────────────
    SaveLoadManager.spend_spins(bet_multiplier)

    # ── Outcome Selection ─────────────────────────────────────────────────────
    var selected_outcome: Dictionary = _resolve_outcome_id()

    var reward_type: String    = str(selected_outcome.get("reward_type", "coins"))
    var reward_tier: String    = str(selected_outcome.get("reward_tier", "small"))
    var outcome_id: String     = str(selected_outcome.get("id", "coins_small"))
    var base_reward: int       = int(selected_outcome.get("reward_value", 0))

    # ── Shield Cap Interception ───────────────────────────────────────────────
    if reward_type == "shield" and SaveLoadManager.shields >= SHIELD_MAX_HELD:
        SaveLoadManager.add_spins(bet_multiplier)
        SaveLoadManager.add_coins(_shield_overflow_coin_compensation)
        emit_signal("shield_overflow_intercepted", _shield_overflow_coin_compensation)

        var intercept_result: Dictionary = {
            "success":           true,
            "outcome_id":        outcome_id,
            "reward_type":       reward_type,
            "reward_value":      0,
            "reward_tier":       reward_tier,
            "bet_multiplier":    bet_multiplier,
            "was_intercepted":   true,
            "compensation_coins": _shield_overflow_coin_compensation,
            "error_reason":      "",
            "triggers_raid":     false,
            "triggers_attack":   false
        }
        SaveLoadManager.save_game()
        emit_signal("spin_completed", intercept_result)
        print("[SlotMachineLogic] Shield overflow intercepted. Compensation coins: %d" % _shield_overflow_coin_compensation)
        return intercept_result

    # ── Final Reward Calculation ──────────────────────────────────────────────
    var final_reward_value: int = 0
    match reward_type:
        "coins":
            final_reward_value = base_reward * bet_multiplier
            SaveLoadManager.add_coins(final_reward_value)
        "spins":
            final_reward_value = base_reward
            SaveLoadManager.add_spins(final_reward_value)
        "shield":
            final_reward_value = base_reward
            SaveLoadManager.add_shields(final_reward_value)
        "attack":
            final_reward_value = base_reward
            # No SaveLoadManager mutation. NPCSimulator handles via signal.
        "raid":
            final_reward_value = base_reward
            # No SaveLoadManager mutation. NPCSimulator handles via signal.
        _:
            push_warning("[SlotMachineLogic] Unknown reward_type '%s'. No resource awarded." % reward_type)

    # ── Post-Award Signal Emission ────────────────────────────────────────────
    if reward_type == "raid":
        emit_signal("raid_triggered", final_reward_value)
    if reward_type == "attack":
        emit_signal("attack_triggered", final_reward_value)

    # ── Result Construction ───────────────────────────────────────────────────
    var result: Dictionary = {
        "success":            true,
        "outcome_id":         outcome_id,
        "reward_type":        reward_type,
        "reward_value":       final_reward_value,
        "reward_tier":        reward_tier,
        "bet_multiplier":     bet_multiplier,
        "was_intercepted":    false,
        "compensation_coins": 0,
        "error_reason":       "",
        "triggers_raid":      reward_type == "raid",
        "triggers_attack":    reward_type == "attack"
    }

    SaveLoadManager.save_game()
    emit_signal("spin_completed", result)

    print("[SlotMachineLogic] Spin resolved. Outcome: %s | Reward: %d %s | Bet: x%d" % [
        outcome_id, final_reward_value, reward_type, bet_multiplier
    ])

    return result
```

---

## SECTION 5: WEIGHTED RANDOM SELECTION ALGORITHM

### 5.1 `_resolve_outcome_id()` — Private PRNG Core

This function implements the **weighted random selection algorithm**. It is the mathematical heart of the slot engine. It must handle the RNG override path (Trainer mode) and the normal PRNG path as two completely separate branches.

#### Algorithm: Weighted Cumulative Selection

The algorithm works as follows:
1. Generate a random integer `roll` in range `[0, _weight_sum - 1]` inclusive.
2. Iterate through `_outcome_table` in order.
3. Subtract each outcome's `weight` from `roll`.
4. The first outcome where `roll` becomes negative after subtraction is the selected outcome.

This produces selection probability exactly equal to `weight / _weight_sum` for each outcome, with O(n) time complexity acceptable for a table of ~11 outcomes.

#### Override Path (Trainer / Dev Mode)

Before executing the PRNG, check `SaveLoadManager.forced_outcome_id`. If it is a non-empty String:
1. Search `_outcome_table` for an element where `id == forced_outcome_id`.
2. If found: clear `SaveLoadManager.forced_outcome_id = ""`. Emit `rng_override_consumed(forced_outcome_id)`. Return the found element.
3. If not found: `push_warning()` with the invalid id. Clear `SaveLoadManager.forced_outcome_id = ""`. Fall through to normal PRNG path. Do not crash.

```gdscript
func _resolve_outcome_id() -> Dictionary:
    # ── Override Path (Trainer Dev Mode) ─────────────────────────────────────
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

    # ── Normal PRNG Weighted Selection ────────────────────────────────────────
    # Roll a random integer across the full weight space.
    var roll: int = _rng.randi_range(0, _weight_sum - 1)

    for outcome in _outcome_table:
        roll -= int(outcome["weight"])
        if roll < 0:
            return outcome

    # Fallback: should be mathematically unreachable if _weight_sum is correct.
    # Return last element defensively rather than returning an empty Dictionary.
    push_warning("[SlotMachineLogic] PRNG fallback triggered. Check weight sum integrity.")
    return _outcome_table[_outcome_table.size() - 1]
```

---

## SECTION 6: PRIVATE HELPER FUNCTIONS

### 6.1 `_build_failure_dict(bet_multiplier: int, reason: String) -> Dictionary`

Returns a fully formed failure result Dictionary. The UI layer can safely read all keys without null checks because the schema is always complete.

```gdscript
func _build_failure_dict(bet_multiplier: int, reason: String) -> Dictionary:
    return {
        "success":            false,
        "outcome_id":         "",
        "reward_type":        "",
        "reward_value":       0,
        "reward_tier":        "",
        "bet_multiplier":     bet_multiplier,
        "was_intercepted":    false,
        "compensation_coins": 0,
        "error_reason":       reason,
        "triggers_raid":      false,
        "triggers_attack":    false
    }
```

---

## SECTION 7: PUBLIC QUERY API (READ-ONLY, NO MUTATION)

These functions allow the UI and other systems to query the slot engine state without triggering any mutations. They are safe to call at any time.

### 7.1 `get_outcome_probability(outcome_id: String) -> float`

Returns the exact probability (0.0 to 1.0) of a given outcome based on current weight table. Used by Trainer overlay for display. Returns `-1.0` if outcome_id is not found.

```gdscript
func get_outcome_probability(outcome_id: String) -> float:
    if not _is_initialized or _weight_sum == 0:
        return -1.0
    for outcome in _outcome_table:
        if str(outcome.get("id", "")) == outcome_id:
            return float(int(outcome["weight"])) / float(_weight_sum)
    return -1.0
```

### 7.2 `get_all_outcome_ids() -> Array[String]`

Returns an Array of all outcome id strings. Used by TrainerConsole to populate the override dropdown.

```gdscript
func get_all_outcome_ids() -> Array[String]:
    var ids: Array[String] = []
    for outcome in _outcome_table:
        ids.append(str(outcome.get("id", "")))
    return ids
```

### 7.3 `can_spin(bet_multiplier: int) -> bool`

Returns true if the player currently has enough spins for the given bet. UI uses this to enable/disable the spin button without triggering a spin.

```gdscript
func can_spin(bet_multiplier: int) -> bool:
    if not _is_initialized:
        return false
    return SaveLoadManager.spins >= max(1, bet_multiplier)
```

### 7.4 `is_initialized() -> bool`

```gdscript
func is_initialized() -> bool:
    return _is_initialized
```

---

## SECTION 8: BET MULTIPLIER CONTRACT

The `bet_multiplier` parameter in `spin_reels()` represents how many spins the player wagers in a single activation. The following rules are enforced by this spec:

| Rule | Implementation |
|---|---|
| Minimum value is 1 | Clamped in guard block. Never rejected, only corrected with a warning. |
| Valid values: 1, 2, 3, 5, 10 | UI enforces this set. `SlotMachineLogic` accepts any positive integer for forward-compatibility. |
| Coin rewards are multiplied | `final_reward_value = base_reward * bet_multiplier` for `reward_type == "coins"` only. |
| Spin/Shield/Attack/Raid rewards are NOT multiplied | Fixed counts regardless of bet. This matches the economic model of the reference game. |
| Spin deduction uses full multiplier | `spend_spins(bet_multiplier)` always deducts the full wager before outcome selection. |
| Shield overflow refunds full multiplier | `add_spins(bet_multiplier)` in interception path returns the exact amount spent. |

---

## SECTION 9: EDGE CASE REGISTRY

Document all non-obvious edge cases and their exact handling. Cursor must verify each of these works correctly in testing.

| Edge Case | Trigger Condition | Handling |
|---|---|---|
| **Shield overflow** | `reward_type == "shield"` AND `SaveLoadManager.shields >= 5` | Refund `bet_multiplier` spins. Award `_shield_overflow_coin_compensation` coins. Return intercepted result. Do NOT call `add_shields()`. |
| **Invalid override id** | `forced_outcome_id` set to a string not matching any outcome `id` | Log warning. Clear `forced_outcome_id`. Fall through to PRNG. Never crash. |
| **Zero bet_multiplier** | Caller passes `0` or negative | Clamp to `1`. Log warning. Continue. |
| **Spins exactly equal to bet** | `SaveLoadManager.spins == bet_multiplier` | Allowed. Guard passes. Player spends their last spin. |
| **Spins become zero after raid/attack** | Normal flow | Valid state. No special handling needed. NPC events fire via signal. |
| **Weight sum mismatch** | PRNG loop exhausts table without returning | Defensive fallback returns `_outcome_table.last()`. Logs warning. Never returns null. |
| **Config file missing at runtime** | `WEIGHTS_CONFIG_PATH` not found | `_is_initialized = false`. All `spin_reels()` calls return failure dict. Game is unplayable but does not crash. Error is logged. |
| **Malformed JSON in config** | `slot_weights.json` has syntax error | Same as above. `_is_initialized = false`. |
| **Outcome with weight 0** | JSON contains `"weight": 0` | Passes validation (no required minimum). Contributes 0 to `_weight_sum`. Effectively unreachable but not rejected. Useful for disabling outcomes without removing them. |
| **Pet buff active during raid** | `reward_type == "raid"` AND Foxy pet is active | `SlotMachineLogic` emits `raid_triggered`. It does NOT apply the Foxy multiplier. `PetManager` (Step 9) intercepts `raid_triggered` and applies its buff to the final loot calculation. Separation of concerns is mandatory. |
| **Event multiplier active** | `CoinCraze` event doubles coin rewards | `SlotMachineLogic` calculates base reward. `EventManager` (Step 7) connects to `spin_completed` signal and applies its multiplier as a post-process. `SlotMachineLogic` does not know events exist. |

---

## SECTION 10: UNIT TEST VERIFICATION PROTOCOL

After Cursor writes the file, verify these scenarios before marking Step 3 complete. Use a temporary test script attached to a Node in a test scene, or use Godot's built-in debugger expression evaluator.

### Test A: Initialization
1. Run the project.
2. **Expected:** Console prints `"[SlotMachineLogic] Initialized. Outcomes: 11 | Weight sum: 1000"`.
3. **Expected:** `slot_machine_node.is_initialized() == true`.

### Test B: Normal Coin Spin
1. Set `SaveLoadManager.spins = 10` via Trainer.
2. Call `slot_machine_node.spin_reels(1)`.
3. **Expected:** `SaveLoadManager.spins == 9` (or 10 if a spin outcome landed).
4. **Expected:** Returned Dictionary has `"success": true`.
5. **Expected:** `spin_completed` signal fires.

### Test C: Bet Multiplier Coin Scaling
1. Force outcome to `coins_medium` via `SaveLoadManager.forced_outcome_id = "coins_medium"`. `coins_medium` has `reward_value: 200`.
2. Call `spin_reels(3)`.
3. **Expected:** `reward_value` in returned Dictionary is `600` (200 × 3).
4. **Expected:** `SaveLoadManager.coins` increased by exactly 600.

### Test D: Shield Overflow Interception
1. Set `SaveLoadManager.shields = 5` (max).
2. Force outcome to `shield_single` via `SaveLoadManager.forced_outcome_id = "shield_single"`.
3. Call `spin_reels(1)`.
4. **Expected:** `SaveLoadManager.shields` remains `5`. No call to `add_shields()`.
5. **Expected:** `SaveLoadManager.spins` is back to pre-spin value (spin refunded).
6. **Expected:** `SaveLoadManager.coins` increased by `_shield_overflow_coin_compensation`.
7. **Expected:** Returned Dictionary has `"was_intercepted": true`.
8. **Expected:** `shield_overflow_intercepted` signal fires.

### Test E: Insufficient Spins Block
1. Set `SaveLoadManager.spins = 2`.
2. Call `spin_reels(5)`.
3. **Expected:** Returned Dictionary has `"success": false`, `"error_reason"` is non-empty.
4. **Expected:** `SaveLoadManager.spins` remains `2`. No deduction occurred.
5. **Expected:** `spin_failed_insufficient_spins` signal fires with `required=5, available=2`.

### Test F: RNG Override and Cleanup
1. Set `SaveLoadManager.forced_outcome_id = "raid_triple"`.
2. Call `spin_reels(1)`.
3. **Expected:** Returned `"outcome_id" == "raid_triple"`.
4. **Expected:** `SaveLoadManager.forced_outcome_id == ""` after the call.
5. **Expected:** `rng_override_consumed` signal fires with `"raid_triple"`.
6. **Expected:** `raid_triggered` signal fires with `reward_value == 3`.

### Test G: Invalid Override Falls Through
1. Set `SaveLoadManager.forced_outcome_id = "nonexistent_id_xyz"`.
2. Call `spin_reels(1)`.
3. **Expected:** A warning is logged. The spin completes normally with a PRNG-selected outcome.
4. **Expected:** `SaveLoadManager.forced_outcome_id == ""` after the call.
5. **Expected:** No crash.

### Test H: Probability Distribution Sanity (Statistical)
1. Run 1000 spins in a loop using a temporary test script with unlimited spins granted.
2. Tally each `outcome_id`.
3. **Expected:** `coins_small` appears approximately 34% of the time (weight 340/1000).
4. **Expected:** `raid_triple` appears approximately 0.7% of the time (weight 7/1000).
5. Acceptable variance: ±5 percentage points over 1000 samples.

---

## SECTION 11: COMPLETION CHECKLIST

Before proceeding to Step 4, Cursor must confirm ALL of the following:

- [ ] `res://src/core/SlotMachineLogic.gd` exists with `class_name SlotMachineLogic`
- [ ] File is **NOT** registered as an Autoload in `project.godot`
- [ ] Zero UI node references exist in the file (`Label`, `Button`, `Control`, `CanvasItem`, `Tween`, `AnimationPlayer` — none present)
- [ ] `_load_weights_config()` guards against: null file handle, JSON parse failure, non-Dictionary root, missing `"outcomes"` key, empty outcome table, zero weight sum
- [ ] `spin_reels()` deducts spins **before** selecting the outcome
- [ ] `spin_reels()` uses `SaveLoadManager.add_coins()`, never `SaveLoadManager.coins +=`
- [ ] Shield cap check uses `SHIELD_MAX_HELD` constant, not the magic number `5`
- [ ] Shield overflow path refunds the full `bet_multiplier` spins, not a fixed `1`
- [ ] Coin rewards are multiplied by `bet_multiplier`; spin/shield/attack/raid rewards are not
- [ ] `_resolve_outcome_id()` clears `SaveLoadManager.forced_outcome_id` after consuming override
- [ ] `_resolve_outcome_id()` falls through to PRNG if override id is not found in table
- [ ] PRNG fallback (unreachable path) returns last table element, never `null` or empty Dictionary
- [ ] All seven signal declarations are present with typed parameters
- [ ] `get_all_outcome_ids()` returns an `Array[String]`, used by TrainerConsole in Step 10
- [ ] `save_game()` is called at the end of every successful `spin_reels()` execution
- [ ] All variables and function signatures use static typing
- [ ] No hardcoded coin values except `_shield_overflow_coin_compensation` which is populated from JSON at runtime

**DO NOT proceed to Step 4 until this checklist is fully verified.**

---

## SECTION 12: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 4 will build `res://src/core/VillageManager.gd`. It will load `village_costs.json` and expose `can_upgrade_item(item_index: int) -> bool` and `upgrade_item(item_index: int) -> void`. It will call `SaveLoadManager.spend_coins()` and read `SaveLoadManager.village_items_state` directly. It will emit a `village_completed` signal when all 5 items reach level 5, trigger a large coin bonus via `SaveLoadManager.add_coins()`, increment `SaveLoadManager.current_village_level`, and reset `SaveLoadManager.village_items_state` to `[0,0,0,0,0]`.
```