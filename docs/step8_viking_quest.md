# step8_viking_quest.md

## Technical Specification: Viking Quest Event
**Target Engine:** Godot 4.x
**Execution Agent:** Cursor (AI Coder)
**Step:** 8 of 10 — Implement `Event_VikingQuest.gd` as a self-contained mini-game event.
**Depends On:** Step 5 complete (`NPCSimulator` exists). Step 7 complete (`BaseEvent`, `EventManager` autoload, `Event_CoinCraze` registered).
**Output Files:**
- `res://src/events/Event_VikingQuest.gd`
- `res://src/events/VikingSlotCore.gd`
- `res://src/core/Main.gd` (updated — register `Event_VikingQuest`)

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **ZERO coupling to `SlotMachineLogic`.** Viking Quest has its own completely isolated spin engine (`VikingSlotCore`). It does NOT call `SlotMachineLogic.spin_reels()`. It does NOT read from `slot_weights.json`. This is a standalone mini-game.
- **ZERO direct NPCSimulator mutation.** Raid Protection writes to `SaveLoadManager.pet_state` only. `NPCSimulator._is_rhino_active()` reads from that same dictionary — no direct cross-system coupling.
- **Viking spins cost Coins, not Spins.** Every Viking spin deducts `viking_spin_cost` from `SaveLoadManager.coins`. This is the core economic distinction from the main slot.
- **Raid Protection writes to `SaveLoadManager.pet_state["viking_raid_protection"]`**, a dedicated slot that `NPCSimulator._is_rhino_active()` already reads via `SaveLoadManager.pet_state.get("rhino", {})`. Use a sibling key `"viking_raid_protection"` — never overwrite the real Rhino pet state.
- **Progress bar is local state only.** It does NOT persist to `SaveLoadManager`. It resets when the Viking Quest event window closes. Only the Raid Protection buff persists.
- **EventManager manages lifecycle.** `Event_VikingQuest` extends `BaseEvent` and is registered via `EventManager.register_event()` in `Main.gd`. Its `_on_start()` / `_on_end()` open and close the Viking panel.
- **STRICTLY** use static typing on every variable and function signature.
- Confirm with the completion checklist before proceeding to Step 9.

---

## SECTION 1: ARCHITECTURAL ROLE

### 1.1 Viking Quest vs Main Slot Machine

| Property | Main Slot Machine (`SlotMachineLogic`) | Viking Quest (`VikingSlotCore`) |
|---|---|---|
| Currency spent | Spins | Coins |
| Spin trigger source | Player spin button | Viking spin button |
| Config file | `slot_weights.json` | `viking_weights.json` (new) |
| Progression system | None | Local progress bar (coins won → progress) |
| Special buff | None | Raid Protection (3 minutes) |
| Connected to NPCSimulator | Via `raid_triggered` signal | Via `SaveLoadManager.pet_state` write |

### 1.2 Data Flow

```
[Player clicks Viking Spin]
       │
       ▼
Event_VikingQuest._on_viking_spin_button_pressed()
       │
       ├──▶ Deduct viking_spin_cost from SaveLoadManager.coins
       │
       ▼
VikingSlotCore.spin_reels(difficulty)
       │
       ├──▶ Weighted random selection from viking_weights.json
       ├──▶ Returns outcome Dictionary
       │
       ▼
Award coins / trigger Raid Protection
       │
       ├──▶ Add coins to SaveLoadManager.coins
       ├──▶ Add coins to progress_bar.current_progress
       ├──▶ If outcome triggers protection: write pet_state["viking_raid_protection"]
       │
       ▼
Check tier completions
       │
       └──▶ for each tier: if progress >= tier.threshold and not claimed: mark claimable
               │
               ▼
UI updates (via signals from Event_VikingQuest)
```

### 1.3 Raid Protection Architecture

```
Event_VikingQuest grants Raid Protection
       │
       ├──▶ SaveLoadManager.pet_state["viking_raid_protection"] = {
               "active_until_timestamp": now + 180,   # 3 minutes
               "buff_type": "raid_protection"
           }
       │
       ▼
SaveLoadManager.save_game()
       │
       ▼
NPCSimulator._is_rhino_active() reads pet_state
       │
       ├──▶ First check: real Rhino pet (existing logic)
       │
       └──▶ NEW — Second check: viking_raid_protection
               │
               if pet_state.get("viking_raid_protection", {}).get("active_until_timestamp", 0) > now:
                   return true  ← blocks NPC attacks
```

### 1.4 Interaction Contract

| System | Role | Interaction |
|---|---|---|
| `SaveLoadManager` | Model — player state | `Event_VikingQuest` reads `coins`, writes `pet_state["viking_raid_protection"]` |
| `NPCSimulator` | Simulated multiplayer | Reads `pet_state` in `_is_rhino_active()` — already compatible with Viking Protection |
| `EventManager` | Event scheduler | Manages `_on_start()` / `_on_end()` lifecycle |
| `VikingSlotCore` | Isolated slot math engine | Independent from `SlotMachineLogic`. Owned by `Event_VikingQuest` |
| `BaseEvent` | Abstract base | Parent class of `Event_VikingQuest` |

---

## SECTION 2: DIRECTORY STRUCTURE

### 2.1 Files to CREATE

```
res://src/
├── events/
│   ├── Event_VikingQuest.gd   ← NEW
│   └── VikingSlotCore.gd     ← NEW (internal slot engine)
└── data/
    └── viking_weights.json   ← NEW (Viking Quest outcome table)
```

### 2.2 Files to MODIFY

| File | Changes |
|---|---|
| `res://src/core/Main.gd` | Add `EventManager.register_event(Event_VikingQuest.new())` |
| `res://src/entities/NPCSimulator.gd` | Update `_is_rhino_active()` to also check `viking_raid_protection` |

---

## SECTION 3: VIKING WEIGHTS CONFIG — `viking_weights.json`

Create `res://src/data/viking_weights.json` with an independent outcome table for the Viking mini-game slot.

```json
{
  "config": {
    "display_name": "Viking Quest",
    "description": "Spin for massive coin rewards!"
  },
  "outcomes": [
    {
      "id": "viking_coins_small",
      "label": "Small Bounty",
      "weight": 280,
      "reward_type": "coins",
      "reward_value": 500,
      "triggers_raid_protection": false
    },
    {
      "id": "viking_coins_medium",
      "label": "Medium Bounty",
      "weight": 200,
      "reward_type": "coins",
      "reward_value": 2000,
      "triggers_raid_protection": false
    },
    {
      "id": "viking_coins_large",
      "label": "Large Bounty",
      "weight": 100,
      "reward_type": "coins",
      "reward_value": 8000,
      "triggers_raid_protection": false
    },
    {
      "id": "viking_coins_mega",
      "label": "Mega Bounty",
      "weight": 30,
      "reward_type": "coins",
      "reward_value": 25000,
      "triggers_raid_protection": false
    },
    {
      "id": "viking_coins_ultra",
      "label": "Ultra Bounty",
      "weight": 5,
      "reward_type": "coins",
      "reward_value": 100000,
      "triggers_raid_protection": false
    },
    {
      "id": "viking_protected_spin",
      "label": "Protected Spin",
      "weight": 200,
      "reward_type": "coins",
      "reward_value": 1000,
      "triggers_raid_protection": true
    },
    {
      "id": "viking_raid_protection",
      "label": "Raid Protection!",
      "weight": 185,
      "reward_type": "raid_protection",
      "reward_value": 0,
      "triggers_raid_protection": false
    }
  ],
  "progress_tiers": [
    { "id": "tier_1", "threshold": 5000,  "reward_coins": 5000,  "label": "Tier 1 Reward" },
    { "id": "tier_2", "threshold": 20000, "reward_coins": 20000, "label": "Tier 2 Reward" },
    { "id": "tier_3", "threshold": 50000, "reward_coins": 50000, "label": "Tier 3 Reward" },
    { "id": "tier_4", "threshold": 100000, "reward_coins": 100000, "label": "Tier 4 Reward" },
    { "id": "tier_5", "threshold": 200000, "reward_coins": 200000, "label": "Jackpot!" }
  ]
}
```

---

## SECTION 4: VIKING SLOT CORE — `VikingSlotCore.gd`

`VikingSlotCore` is a private inner engine owned by `Event_VikingQuest`. It has no node attachment, no signals, and no UI code. It is a pure math class instantiated inside `Event_VikingQuest`.

### 4.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# VikingSlotCore.gd
# Path: res://src/events/VikingSlotCore.gd
# Role: Isolated slot math engine for Viking Quest mini-game.
# NO coupling to SlotMachineLogic. NO UI code. NO node references.
# Access pattern: Instantiated as a private member of Event_VikingQuest.
# ==============================================================================
class_name VikingSlotCore
extends RefCounted
```

### 4.2 Properties

```gdscript
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
```

### 4.3 Constructor

```gdscript
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

    var required_keys: Array[String] = ["id", "label", "weight", "reward_type", "reward_value", "triggers_raid_protection"]

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
```

### 4.4 Public API: `spin(difficulty: String) -> Dictionary`

Performs one Viking spin and returns the outcome. Called by `Event_VikingQuest`.

```gdscript
func spin(difficulty: String) -> Dictionary:
    if not _is_initialized:
        return _build_failure_dict("VikingSlotCore not initialized.")

    # Weighted random selection — identical algorithm to SlotMachineLogic.
    var roll: int = _rng.randi_range(0, _weight_sum - 1)
    for outcome in _outcomes:
        roll -= int(outcome["weight"])
        if roll < 0:
            return outcome.duplicate(true)  # Return copy to prevent mutation

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
```

---

## SECTION 5: EVENT VIKING QUEST — `Event_VikingQuest.gd`

### 5.1 File Header and Class Declaration

```gdscript
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
## Player's actual cost = _get_base_spin_cost() * _difficulty_cost_multiplier.
## Easy   = 1x cost → lower risk, lower reward ceiling
## Normal = 3x cost → standard risk/reward
## Hard   = 10x cost → high risk, maximum reward ceiling
const DIFFICULTY_MULTIPLIERS: Dictionary = {
    "easy":   1,
    "normal": 3,
    "hard":   10
}

## Spin cost in coins at Easy difficulty, before multiplier.
## Base cost scales with village level to keep stakes relevant.
const BASE_SPIN_COST: int = 5000

## Key used in SaveLoadManager.pet_state for the Viking Raid Protection buff.
## IMPORTANT: Never overwrite "rhino" — use a separate key.
const RAID_PROTECTION_KEY: String = "viking_raid_protection"
```

### 5.2 Difficulty Enum and Properties

```gdscript
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
```

### 5.3 Constructor

```gdscript
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
        if saved_end > now:
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
        _progress_tiers = data.get("progress_tiers", [])
    print("[Event_VikingQuest] Loaded %d progress tiers." % _progress_tiers.size())
```

### 5.4 `_on_start()` — Activate Viking Quest

Called by `EventManager` when the Viking Quest event window begins.

```gdscript
func _on_start() -> void:
    # Reset local progress for this event window.
    _progress_current = 0
    _tier_claimed.clear()

    print("[Event_VikingQuest] ACTIVE. Base spin cost: %,d coins. Difficulty: %s" % [
        BASE_SPIN_COST, _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal")
    ])
    print("[Event_VikingQuest] Progress tiers: %s" % str(_get_tier_thresholds()))

    # TODO for Step 9 (UI): Open Viking Quest UI panel here.
    # VikingQuestUI.open_panel()
```

### 5.5 `_on_end()` — Deactivate Viking Quest

Called by `EventManager` when the Viking Quest event window closes.

```gdscript
func _on_end() -> void:
    print("[Event_VikingQuest] ENDED. Final progress: %,d. Claiming remaining tiers..." % _progress_current)

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
                    print("[Event_VikingQuest] Auto-claimed tier '%s': %,d coins!" % [tier_id, reward])

    # TODO for Step 9 (UI): Close Viking Quest UI panel.
    # VikingQuestUI.close_panel()
```

### 5.6 Difficulty Selection API

```gdscript
## Sets the Viking spin difficulty. Call this from the Viking UI before spinning.
## difficulty: one of VikingDifficulty.EASY, VikingDifficulty.NORMAL, VikingDifficulty.HARD
func set_difficulty(difficulty: VikingDifficulty) -> void:
    _selected_difficulty = difficulty
    var cost: int = _get_current_spin_cost()
    print("[Event_VikingQuest] Difficulty set to %s. Spin cost: %,d coins." % [
        _DIFFICULTY_STRING_MAP.get(difficulty, "normal"), cost
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
```

### 5.7 Core Spin API — `_execute_spin()` — The Main Entry Point

This function is called by the Viking UI (Step 9) when the player presses the Viking spin button. It orchestrates cost deduction, spin execution, reward application, and progress tracking.

```gdscript
## Executes one Viking spin. Call this from the Viking spin button handler.
## Returns a Dictionary with the spin result, or an error dict if insufficient coins.
func execute_spin() -> Dictionary:
    if not is_active:
        return _build_spin_failure("Viking Quest is not currently active.")

    var spin_cost: int = _get_current_spin_cost()

    # ── Deduct cost from Coins (not Spins!) ────────────────────────────────
    if not SaveLoadManager.spend_coins(spin_cost):
        return _build_spin_failure("Not enough coins! Need %,d." % spin_cost)

    # ── Execute isolated Viking slot spin ───────────────────────────────────
    var outcome: Dictionary = _viking_slot.spin(_DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal"))

    if not bool(outcome.get("success", true)):
        # Refund coins on internal failure.
        SaveLoadManager.add_coins(spin_cost)
        return outcome

    # ── Apply rewards ──────────────────────────────────────────────────────
    var reward_type: String = str(outcome.get("reward_type", ""))
    var reward_value: int = int(outcome.get("reward_value", 0))
    var triggers_protection: bool = bool(outcome.get("triggers_raid_protection", false))

    if reward_type == "coins" and reward_value > 0:
        # Apply difficulty-based reward multiplier.
        # Higher difficulty = higher actual reward received.
        var difficulty_mult: int = int(DIFFICULTY_MULTIPLIERS.get(
            _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal"), 3
        ))
        var final_reward: int = reward_value * difficulty_mult

        SaveLoadManager.add_coins(final_reward)

        # Update local progress bar.
        _add_progress(final_reward)

        print("[Event_VikingQuest] Won %,d coins (×%d difficulty bonus). Progress: %,d." % [
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
    result["difficulty"] = _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal")
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
        "difficulty": _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal"),
        "spin_cost_paid": 0,
        "error_reason": reason
    }
```

### 5.8 Progress Bar System

```gdscript
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
            print("[Event_VikingQuest] Tier '%s' REACHED! Bonus: %,d coins!" % [tier_id, reward])


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
```

### 5.9 Raid Protection System

```gdscript
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
```

### 5.10 Full `Event_VikingQuest.gd` Implementation

```gdscript
# ==============================================================================
# Event_VikingQuest.gd
# Path: res://src/events/Event_VikingQuest.gd
# Role: Viking Quest live-ops mini-game event.
# Extends BaseEvent — managed by EventManager lifecycle.
# ==============================================================================
class_name Event_VikingQuest
extends BaseEvent

const RAID_PROTECTION_DURATION_SECONDS: int = 180
const RAID_PROTECTION_KEY: String = "viking_raid_protection"
const BASE_SPIN_COST: int = 5000

const DIFFICULTY_MULTIPLIERS: Dictionary = {
    "easy":   1,
    "normal": 3,
    "hard":   10
}

enum VikingDifficulty { EASY, NORMAL, HARD }

const _DIFFICULTY_STRING_MAP: Dictionary = {
    VikingDifficulty.EASY:   "easy",
    VikingDifficulty.NORMAL: "normal",
    VikingDifficulty.HARD:   "hard"
}

var _selected_difficulty: VikingDifficulty = VikingDifficulty.NORMAL
var _viking_slot: VikingSlotCore = VikingSlotCore.new()
var _progress_current: int = 0
var _tier_claimed: Dictionary = {}
var _progress_tiers: Array[Dictionary] = []

signal progress_updated(value: int, max_value: int)
signal tier_reached(tier_id: String, reward_coins: int)
signal raid_protection_activated(expires_at: int)


func _init() -> void:
    var saved_flags: Dictionary = SaveLoadManager.event_flags.get("viking_quest", {})
    _init_impl(
        "viking_quest", "Viking Quest",
        int(saved_flags.get("start_timestamp", 0)),
        int(saved_flags.get("end_timestamp", 0))
    _load_progress_tiers()
    if saved_flags.get("is_active", false):
        var now: int = int(Time.get_unix_time_from_system())
        if saved_end > now:
            is_active = true
            _on_start()


func _load_progress_tiers() -> void:
    var file: FileAccess = FileAccess.open(VikingSlotCore.CONFIG_PATH, FileAccess.READ)
    if file == null:
        return
    var raw_text: String = file.get_as_text()
    file.close()
    var json_parser: JSON = JSON.new()
    if json_parser.parse(raw_text) != OK:
        return
    var data: Variant = json_parser.get_data()
    if data is Dictionary:
        _progress_tiers = data.get("progress_tiers", [])


func _on_start() -> void:
    _progress_current = 0
    _tier_claimed.clear()
    print("[Event_VikingQuest] ACTIVE. Base cost: %,d | Difficulty: %s" % [
        BASE_SPIN_COST, _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal")
    ])


func _on_end() -> void:
    print("[Event_VikingQuest] ENDED. Final progress: %,d." % _progress_current)
    for tier in _progress_tiers:
        var tier_id: String = str(tier.get("id", ""))
        if _progress_current >= int(tier.get("threshold", 0)):
            if not _tier_claimed.get(tier_id, false):
                var reward: int = int(tier.get("reward_coins", 0))
                if reward > 0:
                    SaveLoadManager.add_coins(reward)
                    SaveLoadManager.save_game()
                    _tier_claimed[tier_id] = true
                    print("[Event_VikingQuest] Auto-claimed tier '%s': %,d coins!" % [tier_id, reward])


func set_difficulty(difficulty: VikingDifficulty) -> void:
    _selected_difficulty = difficulty
    print("[Event_VikingQuest] Difficulty set to: %s" % _DIFFICULTY_STRING_MAP.get(difficulty, "normal"))


func _get_current_spin_cost() -> int:
    var mult: int = int(DIFFICULTY_MULTIPLIERS.get(
        _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal"), 3))
    return BASE_SPIN_COST * mult


func get_difficulty_string() -> String:
    return _DIFFICULTY_STRING_MAP.get(_selected_difficulty, "normal")


func execute_spin() -> Dictionary:
    if not is_active:
        return _build_spin_failure("Viking Quest is not currently active.")

    var spin_cost: int = _get_current_spin_cost()

    if not SaveLoadManager.spend_coins(spin_cost):
        return _build_spin_failure("Not enough coins! Need %,d." % spin_cost)

    var outcome: Dictionary = _viking_slot.spin(get_difficulty_string())
    if not bool(outcome.get("success", true)):
        SaveLoadManager.add_coins(spin_cost)
        return outcome

    var reward_type:  String = str(outcome.get("reward_type", ""))
    var reward_value:  int    = int(outcome.get("reward_value", 0))
    var triggers_prot: bool    = bool(outcome.get("triggers_raid_protection", false))

    if reward_type == "coins" and reward_value > 0:
        var diff_mult: int = int(DIFFICULTY_MULTIPLIERS.get(get_difficulty_string(), 3))
        var final_reward: int = reward_value * diff_mult
        SaveLoadManager.add_coins(final_reward)
        _add_progress(final_reward)
        print("[Event_VikingQuest] Won %,d coins. Progress: %,d." % [final_reward, _progress_current])

    elif reward_type == "raid_protection":
        SaveLoadManager.add_coins(500)
        triggers_prot = true
        print("[Event_VikingQuest] Raid Protection triggered!")

    if triggers_prot:
        _grant_raid_protection()

    SaveLoadManager.save_game()

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


func _add_progress(coins_won: int) -> void:
    _progress_current += coins_won
    var next_threshold: int = _get_next_tier_threshold()
    emit_signal("progress_updated", _progress_current, next_threshold)

    for tier in _progress_tiers:
        var tier_id: String = str(tier.get("id", ""))
        var threshold: int = int(tier.get("threshold", 0))
        var reward: int = int(tier.get("reward_coins", 0))
        if _progress_current >= threshold and not _tier_claimed.get(tier_id, false):
            _tier_claimed[tier_id] = true
            SaveLoadManager.add_coins(reward)
            SaveLoadManager.save_game()
            emit_signal("tier_reached", tier_id, reward)
            print("[Event_VikingQuest] Tier '%s' REACHED! Bonus: %,d coins!" % [tier_id, reward])


func _get_next_tier_threshold() -> int:
    for tier in _progress_tiers:
        var tier_id: String = str(tier.get("id", ""))
        if not _tier_claimed.get(tier_id, false):
            return int(tier.get("threshold", 0))
    return _progress_current


func _grant_raid_protection() -> void:
    var now: int = int(Time.get_unix_time_from_system())
    var expires_at: int = now + RAID_PROTECTION_DURATION_SECONDS
    SaveLoadManager.pet_state[RAID_PROTECTION_KEY] = {
        "active_until_timestamp": expires_at,
        "buff_type": "raid_protection",
        "granted_at": now
    }
    emit_signal("raid_protection_activated", expires_at)
    print("[Event_VikingQuest] Raid Protection active until Unix time: %d" % expires_at)


func is_raid_protection_active() -> bool:
    var data: Dictionary = SaveLoadManager.pet_state.get(RAID_PROTECTION_KEY, {})
    var expires_at: int = int(data.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < expires_at


func get_raid_protection_remaining_seconds() -> int:
    var data: Dictionary = SaveLoadManager.pet_state.get(RAID_PROTECTION_KEY, {})
    var expires_at: int = int(data.get("active_until_timestamp", 0))
    return max(0, expires_at - int(Time.get_unix_time_from_system()))


func get_progress() -> Dictionary:
    return {
        "current": _progress_current,
        "next_tier_threshold": _get_next_tier_threshold(),
        "is_active": is_active,
        "spin_cost": _get_current_spin_cost(),
        "difficulty": get_difficulty_string()
    }
```

---

## SECTION 6: NPCSIMULATOR UPDATE — Raid Protection Integration

`NPCSimulator.gd` must be updated to check the Viking Raid Protection buff alongside the real Rhino pet.

### 6.1 Updated `_is_rhino_active()`

Replace the existing `_is_rhino_active()` function in `NPCSimulator.gd` with this enhanced version:

```gdscript
func _is_rhino_active() -> bool:
    var now: int = int(Time.get_unix_time_from_system())

    # ── Check real Rhino pet ──────────────────────────────────────────────
    var rhino_state: Dictionary = SaveLoadManager.pet_state.get("rhino", {})
    var rhino_expires: int = int(rhino_state.get("active_until_timestamp", 0))
    if now < rhino_expires:
        return true

    # ── Check Viking Raid Protection buff ───────────────────────────────────
    var viking_protection: Dictionary = SaveLoadManager.pet_state.get("viking_raid_protection", {})
    var viking_expires: int = int(viking_protection.get("active_until_timestamp", 0))
    if now < viking_expires:
        print("[NPCSimulator] Attack blocked by Viking Raid Protection (until %d)." % viking_expires)
        return true

    return false
```

**Important:** The Rhino pet and Viking Raid Protection both use the same check mechanism (`active_until_timestamp`), but they are stored in separate keys (`"rhino"` vs `"viking_raid_protection"`). They do NOT interfere with each other.

---

## SECTION 7: MAIN SCENE UPDATES — `Main.gd`

Add `Event_VikingQuest` registration alongside `Event_CoinCraze`:

```gdscript
func _ready() -> void:
    # ... existing code ...

    # ── Event System (Step 7 + Step 8) ─────────────────────────────────────
    var coin_craze: Event_CoinCraze = Event_CoinCraze.new()
    EventManager.register_event(coin_craze)

    var viking_quest: Event_VikingQuest = Event_VikingQuest.new()
    EventManager.register_event(viking_quest)

    print("[Main] Events registered.")
```

---

## SECTION 8: ARCHITECTURAL CONSTRAINTS & GOTCHAS

### 8.1 Absolute Prohibitions

| Prohibition | Reason |
|---|---|
| Do NOT call `SlotMachineLogic.spin_reels()` from `Event_VikingQuest` | Viking has its own isolated engine (`VikingSlotCore`). No coupling to main slot. |
| Do NOT write to `SaveLoadManager.pet_state["rhino"]` | Viking Protection uses `"viking_raid_protection"` key only. Never touch the real Rhino pet. |
| Do NOT persist `_progress_current` to `SaveLoadManager` | Progress bar is local to the event window. Resets on `_on_end()`. |
| Do NOT call `VikingSlotCore` methods from outside `Event_VikingQuest` | `VikingSlotCore` is a private implementation detail. |
| Do NOT call `execute_spin()` when `is_active == false` | Guard in `execute_spin()` returns failure dict. UI must check `is_active`. |

### 8.2 Coin vs Spin Gotchas

**Gotcha 1: Viking spins cost Coins, not Spins**
- `execute_spin()` calls `SaveLoadManager.spend_coins(spin_cost)`, NOT `spend_spins()`.
- The Viking panel UI (Step 9) must display the Coin balance, not the Spin counter, as the relevant currency.

**Gotcha 2: Progress bar does NOT persist across sessions**
- If the player quits and relaunches within the Viking Quest event window, their progress bar resets to 0. Only the Raid Protection buff persists (it is stored in `pet_state`).
- This is intentional — it mirrors the original game's behavior.

**Gotcha 3: Difficulty changes spin cost, not outcome probability**
- The difficulty multiplier only affects `reward_value × multiplier` when coins are awarded. It does NOT change the probability of winning.
- A Hard spin and an Easy spin have identical outcome probabilities — Hard just pays more and rewards more.

### 8.3 Raid Protection Gotchas

**Gotcha 4: Raid Protection does not stack**
- Calling `_grant_raid_protection()` while protection is already active simply overwrites `active_until_timestamp` with a new expiry (now + 180 seconds). It does not add time.
- The buff is always 3 minutes from the most recent grant.

**Gotcha 5: `NPCSimulator._is_rhino_active()` reads two separate keys**
- `"rhino"` — real Rhino pet (Step 9)
- `"viking_raid_protection"` — Viking Protection (this step)
- Both are checked in a single function. No changes needed to `NPCSimulator` beyond the `_is_rhino_active()` update.

**Gotcha 6: Raid Protection write is safe even if Rhino pet is also active**
- `SaveLoadManager.pet_state["viking_raid_protection"]` is a separate dictionary entry from `pet_state["rhino"]`. Writing to one does not affect the other.

### 8.4 Difficulty Gotchas

**Gotcha 7: Difficulty is per-event-session, not per-spin**
- `set_difficulty()` changes the difficulty for all subsequent spins in the current Viking Quest window.
- If the player changes difficulty mid-session, all future spins use the new cost.

**Gotcha 8: Hard difficulty cost can exceed player balance**
- `execute_spin()` checks `spend_coins(spin_cost)` and returns a failure dict if insufficient. No crash.
- UI (Step 9) should disable the spin button or show a warning if `spin_cost > SaveLoadManager.coins`.

---

## SECTION 9: EDGE CASE REGISTRY

| Edge Case | Trigger | Handling |
|---|---|---|
| **Player has 0 coins** | Balance insufficient for even Easy spin | `execute_spin()` returns failure dict with "Not enough coins". Button disabled in UI (Step 9). |
| **Player changes difficulty while animation running** | UI race condition | Difficulty affects `execute_spin()` which is called on button press. Animation UI update is cosmetic. |
| **Tier reached during Viking Quest but event ends** | `_on_end()` fires | Auto-claims all reached tiers. Coins added. Logged. |
| **Raid Protection already active → player gets another protection outcome** | Second `triggers_raid_protection` outcome | `_grant_raid_protection()` overwrites expiry to now+180s. No stack. Duration refreshed. |
| **Player quits mid-Viking Quest** | App closed | Progress bar lost. Raid Protection persists via `SaveLoadManager.pet_state`. |
| **Viking Quest activates on boot (saved active state)** | Player quit while event was running | `is_active` synced from save in `_init()`. `_on_start()` called immediately. Progress bar reset. |
| **NPC attacks while Viking Protection active** | `NPCSimulator._resolve_single_attack()` calls `_is_rhino_active()` | Both Rhino and Viking Protection checked in one function. Attack blocked if either is active. |
| **Coin frenzy (CoinCraze) active while Viking spins** | Both events active simultaneously | `Event_CoinCraze` listens to `SlotMachineLogic.spin_completed` — it does NOT touch Viking spins. No interaction. |
| **viking_weights.json missing** | Config file absent | `VikingSlotCore._is_initialized = false`. `execute_spin()` returns failure dict. Game does not crash. |

---

## SECTION 10: COMPLETION CHECKLIST

Before proceeding to Step 9, Cursor must confirm ALL of the following:

**File Existence:**
- [ ] `res://src/data/viking_weights.json` exists with valid JSON
- [ ] `res://src/events/VikingSlotCore.gd` exists with `class_name VikingSlotCore`
- [ ] `res://src/events/Event_VikingQuest.gd` exists with `class_name Event_VikingQuest`
- [ ] `NPCSimulator.gd` is updated with enhanced `_is_rhino_active()`
- [ ] `Main.gd` registers both `Event_CoinCraze` and `Event_VikingQuest`

**VikingSlotCore:**
- [ ] `extends RefCounted` (not `Node`)
- [ ] `CONFIG_PATH = "res://src/data/viking_weights.json"`
- [ ] Loads outcomes from JSON in `_init()`
- [ ] Weighted random selection in `spin()` (same algorithm as `SlotMachineLogic`)
- [ ] `_build_failure_dict()` returns complete schema
- [ ] `duplicate(true)` on returned outcome to prevent mutation

**Event_VikingQuest:**
- [ ] `extends BaseEvent`
- [ ] `RAID_PROTECTION_DURATION_SECONDS = 180`
- [ ] `BASE_SPIN_COST = 5000`
- [ ] `DIFFICULTY_MULTIPLIERS` dictionary with easy/normal/hard
- [ ] `VikingDifficulty` enum declared
- [ ] `_viking_slot: VikingSlotCore = VikingSlotCore.new()` in property declaration
- [ ] `_load_progress_tiers()` parses `progress_tiers` from JSON
- [ ] `_on_start()` resets progress and tier claimed state
- [ ] `_on_end()` auto-claims all reached tiers
- [ ] `execute_spin()` deducts `spend_coins()`, NOT `spend_spins()`
- [ ] `execute_spin()` applies difficulty multiplier to reward
- [ ] `execute_spin()` checks `is_active` first
- [ ] `execute_spin()` calls `_grant_raid_protection()` when outcome triggers it
- [ ] `_grant_raid_protection()` writes to `pet_state[RAID_PROTECTION_KEY]`, NOT `pet_state["rhino"]`
- [ ] `_grant_raid_protection()` sets `active_until_timestamp = now + 180`
- [ ] `is_raid_protection_active()` reads from `pet_state` without writing
- [ ] `_add_progress()` emits `progress_updated` signal
- [ ] `_add_progress()` emits `tier_reached` for each newly reached tier
- [ ] `_get_next_tier_threshold()` returns current threshold (no claim needed if all claimed)
- [ ] `set_difficulty()` accepts `VikingDifficulty` enum
- [ ] `get_progress()` returns a Dictionary with `current`, `next_tier_threshold`, `is_active`, `spin_cost`, `difficulty`

**NPCSimulator Update:**
- [ ] `_is_rhino_active()` checks both `"rhino"` and `"viking_raid_protection"`
- [ ] `viking_raid_protection` check logs the block with `"[NPCSimulator] Attack blocked by Viking Raid Protection"`
- [ ] No other changes to `NPCSimulator.gd`

**Separation of Concerns:**
- [ ] `Event_VikingQuest` does NOT call `SlotMachineLogic.spin_reels()`
- [ ] `Event_VikingQuest` does NOT read `slot_weights.json`
- [ ] `VikingSlotCore` does NOT call `SaveLoadManager` mutators
- [ ] `VikingSlotCore` does NOT emit signals
- [ ] Progress bar state (`_progress_current`, `_tier_claimed`) is NOT written to `SaveLoadManager`

**viking_weights.json:**
- [ ] `"outcomes"` array has at least 7 outcome entries
- [ ] All outcomes have required keys: `id`, `label`, `weight`, `reward_type`, `reward_value`, `triggers_raid_protection`
- [ ] `weight` values sum to a non-zero total
- [ ] At least one outcome has `triggers_raid_protection: true`
- [ ] `"progress_tiers"` array has exactly 5 tier entries
- [ ] Each tier has `id`, `threshold`, `reward_coins`, `label`

**Static Typing:**
- [ ] All variables have explicit type annotations
- [ ] All function parameters have type annotations
- [ ] All function return types declared

**Logging:**
- [ ] `VikingSlotCore._init()` prints initialization message
- [ ] `Event_VikingQuest._init()` prints tier count
- [ ] `Event_VikingQuest._on_start()` prints activation
- [ ] `Event_VikingQuest._on_end()` prints final progress and auto-claims
- [ ] `execute_spin()` prints coin gain and progress
- [ ] `_grant_raid_protection()` prints expiry timestamp
- [ ] All log messages include `[ClassName]` prefix

**DO NOT proceed to Step 9 until this checklist is fully verified.**

---

## SECTION 11: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 9 will build `res://src/core/PetManager.gd` to manage the Foxy, Tiger, and Rhino pet activation system. `PetManager` reads `SaveLoadManager.pet_state` and applies timed buffs: Foxy boosts raid loot by 119%, Tiger boosts attack loot by 410%, and Rhino blocks NPC attacks. Step 9 also builds the Viking Quest UI panel (`VikingQuestUI.gd` and `VikingQuestPanel.tscn`) that displays the difficulty selector, spin button, progress bar, tier list, and Raid Protection timer — wiring everything to `Event_VikingQuest` and `EventManager` lifecycle signals.
