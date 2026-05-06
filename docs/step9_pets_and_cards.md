# step9_pets_and_cards.md

## Technical Specification: Pets and Card Collection Systems
**Target Engine:** Godot 4.x
**Execution Agent:** Cursor (AI Coder)
**Step:** 9 of 10 — Implement `PetManager.gd` and `CardManager.gd` with full integration into `NPCSimulator` loot calculation.
**Depends On:** Step 5 complete (`NPCSimulator` instantiated). Step 7 complete (`EventManager` autoload). Step 8 complete (`Event_VikingQuest` registered, `_is_rhino_active()` updated).
**Output Files:**
- `res://src/core/PetManager.gd`
- `res://src/core/CardManager.gd`
- `res://src/data/card_sets.json`
- `res://src/data/card_chest_config.json`
- `res://src/entities/NPCSimulator.gd` (updated — apply pet loot multipliers)
- `res://src/core/Main.gd` (updated — instantiate PetManager and CardManager)
- `res://src/utils/SaveLoadManager.gd` (updated — initialize card collection in `_apply_defaults`)
- `res://project.godot` (optional — register PetManager as Autoload if needed)

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **PetManager is a Node** (not `RefCounted`) because it needs `_process()` to check pet timers in real time. Register it as an Autoload in `project.godot` after `SaveLoadManager` but after `EventManager`.
- **CardManager is a Node** (not `RefCounted`) because it emits signals that the UI layer subscribes to. Instantiate as a child of Main.gd alongside `PetManager`.
- **Pet buffs are applied at loot calculation time.** Foxy and Tiger multipliers are read from `SaveLoadManager.pet_state` inside `NPCSimulator.generate_raid_target()` and `NPCSimulator.on_live_attack_triggered()`. Do NOT modify `NPCSimulator` to import `PetManager` — it reads directly from `pet_state` dictionary.
- **Card collection persists in `SaveLoadManager.card_collection`.** This is initialized in `_apply_defaults()` and saved via `_build_save_dictionary()`.
- **Treat consumption is a no-op from PetManager's perspective.** `PetManager.activate_pet(pet_id)` writes the timestamp to `SaveLoadManager.pet_state[pet_id]`. It does NOT deduct Treat items — that logic lives in the Shop system (future step). For Step 9, Treat deduction is stubbed as a `push_warning`.
- **STRICTLY** use static typing on every variable and function signature.
- Confirm with the completion checklist before proceeding to Step 10.

---

## SECTION 1: ARCHITECTURAL ROLE

### 1.1 Pet System

Pets provide time-limited buffs activated by consuming a "Treat" item. Three pets:

| Pet | Buff Type | Effect | Bonus |
|---|---|---|---|
| **Foxy** | Raid Loot Boost | Increases `loot_pool` from `generate_raid_target()` | +119% |
| **Tiger** | Attack Loot Boost | Increases loot from live attacks | +410% |
| **Rhino** | Attack Block | Already implemented in `NPCSimulator._is_rhino_active()` | 70% block |

Foxy and Tiger are **new integration points** in `NPCSimulator`. Rhino was already implemented in Step 5 and enhanced in Step 8.

### 1.2 Card Collection System

Cards drop from chest-opening. Each card belongs to a themed Set. Collecting all cards in a Set awards a massive Spin bonus and emits `set_completed`.

| System | Role |
|---|---|
| `CardManager` | Manages chest opening, RNG card drops, set completion tracking, `set_completed` signal |
| `card_sets.json` | Static data: all card definitions, set groupings, card stars |
| `card_chest_config.json` | Static data: chest types, costs, drop rates, card pool weights |
| `SaveLoadManager.card_collection` | Persisted: owned card IDs, set completion flags |

### 1.3 Data Flow

```
[Player opens chest]
       │
       ▼
CardManager.open_chest(chest_id)   ← deducts coins
       │
       ▼
CardManager._roll_card()          ← weighted RNG
       │
       ├──▶ Duplicate? ──▶ CardManager._handle_duplicate() ──▶ coin compensation
       │
       ├──▶ New card ──▶ CardManager._handle_new_card()
       │              ├──▶ Add to SaveLoadManager.card_collection
       │              ├──▶ Check set completion
       │              │       └──▶ All cards in set collected?
       │              │               │
       │              │               ▼
       │              │       CardManager.set_completed(set_id) ──▶ emit signal
       │              │               └──▶ SaveLoadManager.add_spins(massive_payload)
       │              │
       └──▶ emit card_opened(new_card, is_duplicate)

[Player uses Treat on Foxy]
       │
       ▼
PetManager.activate_pet("foxy") ──▶ SaveLoadManager.pet_state["foxy"]["active_until_timestamp"] = now + 14400
       │
       ▼
PetManager._process(delta) ──▶ checks Foxy timer every frame
       │
       ▼ (if active) emit pet_buff_active(pet_id, seconds_remaining)

[NPCSimulator generates raid target]
       │
       ▼
generate_raid_target():
       │
       ├──▶ loot_pool = base calculation
       │
       ├──▶ if Foxy active: loot_pool *= 2.19   ← +119%
       └──▶ return loot_pool
```

### 1.4 Interaction Contract

| System | Role | Interaction |
|---|---|---|
| `SaveLoadManager` | Model — player state | Reads `pet_state` and `card_collection`. Writes pet timestamps and card ownership |
| `NPCSimulator` | Loot generation | Reads `pet_state["foxy"]` and `pet_state["tiger"]` directly for loot multipliers |
| `PetManager` | Pet timer manager | Writes `active_until_timestamp` to `pet_state`. Emits `pet_buff_active` |
| `CardManager` | Card RNG & set tracking | Writes to `card_collection`. Emits `card_opened`, `set_completed` |
| `EventManager` | Event scheduler | No direct interaction with pets or cards (future events may reference them) |

---

## SECTION 2: DIRECTORY STRUCTURE

```
res://src/core/
├── PetManager.gd        ← NEW
├── CardManager.gd       ← NEW
└── Main.gd             ← UPDATE

res://src/data/
├── card_sets.json       ← NEW
└── card_chest_config.json ← NEW

res://src/entities/
└── NPCSimulator.gd     ← UPDATE generate_raid_target(), on_live_attack_triggered()

res://src/utils/
└── SaveLoadManager.gd  ← UPDATE _apply_defaults(), _build_save_dictionary(), _apply_state_from_dictionary()

res://project.godot     ← UPDATE [autoload] PetManager
```

---

## SECTION 3: CARD DATA CONFIGURATIONS

### 3.1 `card_sets.json`

```json
{
  "sets": [
    {
      "id": "set_viking",
      "name": "Viking Adventure",
      "theme": "Lands of Vikings",
      "cards": [
        { "id": "vk_001", "name": "Viking Longship",    "star": 1 },
        { "id": "vk_002", "name": "Ax Warrior",         "star": 1 },
        { "id": "vk_003", "name": "Berserker Rage",      "star": 2 },
        { "id": "vk_004", "name": "Shield Maiden",        "star": 2 },
        { "id": "vk_005", "name": "Raven Banner",         "star": 3 },
        { "id": "vk_006", "name": "Dragon Helm",          "star": 3 },
        { "id": "vk_007", "name": "Thor's Hammer",        "star": 4 },
        { "id": "vk_008", "name": "Valhalla Gate",        "star": 5 }
      ],
      "completion_reward_spins": 50,
      "completion_reward_coins": 100000
    },
    {
      "id": "set_egypt",
      "name": "Ancient Egypt",
      "theme": "Ancient Egypt",
      "cards": [
        { "id": "eg_001", "name": "Pharaoh's Curse",     "star": 1 },
        { "id": "eg_002", "name": "Scarab Beetle",        "star": 1 },
        { "id": "eg_003", "name": "Hieroglyph Tablet",    "star": 2 },
        { "id": "eg_004", "name": "Anubis Guardian",      "star": 2 },
        { "id": "eg_005", "name": "Pyramid Power",        "star": 3 },
        { "id": "eg_006", "name": "Nile Serpent",         "star": 3 },
        { "id": "eg_007", "name": "Eye of Horus",         "star": 4 },
        { "id": "eg_008", "name": "Pharaoh's Tomb",       "star": 5 }
      ],
      "completion_reward_spins": 50,
      "completion_reward_coins": 100000
    },
    {
      "id": "set_alps",
      "name": "Snowy Alps",
      "theme": "Snowy Alps",
      "cards": [
        { "id": "al_001", "name": "Ice Crystal",         "star": 1 },
        { "id": "al_002", "name": "Frost Giant",          "star": 1 },
        { "id": "al_003", "name": "Avalanche",            "star": 2 },
        { "id": "al_004", "name": "Mountain Shrine",      "star": 2 },
        { "id": "al_005", "name": "Yodel Champion",       "star": 3 },
        { "id": "al_006", "name": "Alpine Wolf",          "star": 3 },
        { "id": "al_007", "name": "Summit Treasure",      "star": 4 },
        { "id": "al_008", "name": "Eternal Glacier",       "star": 5 }
      ],
      "completion_reward_spins": 50,
      "completion_reward_coins": 100000
    }
  ]
}
```

### 3.2 `card_chest_config.json`

```json
{
  "chests": [
    {
      "id": "chest_bronze",
      "display_name": "Bronze Chest",
      "cost_coins": 10000,
      "cost_gems": 0,
      "cards_per_open": 1,
      "drop_pool": "all_cards",
      "star_weights": {
        "1": 50,
        "2": 30,
        "3": 15,
        "4": 4,
        "5": 1
      }
    },
    {
      "id": "chest_gold",
      "display_name": "Gold Chest",
      "cost_coins": 50000,
      "cost_gems": 5,
      "cards_per_open": 3,
      "drop_pool": "all_cards",
      "star_weights": {
        "1": 30,
        "2": 30,
        "3": 25,
        "4": 12,
        "5": 3
      }
    },
    {
      "id": "chest_magic",
      "display_name": "Magic Chest",
      "cost_coins": 200000,
      "cost_gems": 15,
      "cards_per_open": 5,
      "drop_pool": "all_cards",
      "star_weights": {
        "1": 15,
        "2": 25,
        "3": 35,
        "4": 18,
        "5": 7
      }
    }
  ]
}
```

---

## SECTION 4: SAVE LOAD MANAGER UPDATES

### 4.1 `_apply_defaults()` — Add card collection initialization

After the `pet_state` initialization in `_apply_defaults()`, add card collection:

```gdscript
# After pet_state defaults (existing code):
#     "foxy":  { "xp": 0, "level": 1, "active_until_timestamp": 0 },
#     "tiger": { "xp": 0, "level": 1, "active_until_timestamp": 0 },
#     "rhino": { "xp": 0, "level": 1, "active_until_timestamp": 0 }

# ── Card Collection ────────────────────────────────────────────────────────
if not data.has("card_collection") or not data["card_collection"] is Dictionary:
    card_collection = {
        "owned_card_ids": [],    # Array of card id strings the player owns
        "completed_sets": [],    # Array of set id strings that are fully collected
        "total_duplicates": 0   # Total duplicate cards received (cosmetic stat)
    }
else:
    card_collection = data["card_collection"]
```

### 4.2 `_build_save_dictionary()` — Persist card collection

Add `card_collection` to the return Dictionary:

```gdscript
# Add inside _build_save_dictionary():
"card_collection": card_collection.duplicate(true),
```

### 4.3 `_apply_state_from_dictionary()` — Load card collection

Add after the `event_flags` section:

```gdscript
var raw_cards = data.get("card_collection", {})
if raw_cards is Dictionary:
    card_collection = {
        "owned_card_ids":   Array(raw_cards.get("owned_card_ids", [])),
        "completed_sets":   Array(raw_cards.get("completed_sets", [])),
        "total_duplicates": int(raw_cards.get("total_duplicates", 0))
    }
else:
    card_collection = {
        "owned_card_ids":   [],
        "completed_sets":   [],
        "total_duplicates": 0
    }
```

---

## SECTION 5: PET MANAGER — `PetManager.gd`

### 5.1 Class Declaration and Constants

```gdscript
# ==============================================================================
# PetManager.gd
# Path: res://src/core/PetManager.gd
# Role: Manages pet activation timers and exposes pet buff status to other systems.
# Registered as Autoload in project.godot AFTER SaveLoadManager and EventManager.
# Reads/writes SaveLoadManager.pet_state directly — no signal coupling needed.
# ==============================================================================
class_name PetManager
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

## Internal RNG for treat-related randomness.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
```

### 5.2 Properties

```gdscript
## Tracks which pet IDs had their buff activate this session (for debug).
var _session_active_pets: Array[String] = []
```

### 5.3 Signals

```gdscript
## Emitted every second while a pet buff is active.
## pet_id: "foxy", "tiger", or "rhino"
## seconds_remaining: seconds until buff expires (0 if expired).
## is_new_activation: true if this is the first emission for this activation window.
signal pet_buff_tick(pet_id: String, seconds_remaining: int, is_new_activation: bool)

## Emitted when a pet buff expires (went from active to inactive).
signal pet_buff_expired(pet_id: String)

## Emitted when a pet is successfully activated via activate_pet().
## pet_id: pet that was activated.
## expires_at: Unix timestamp when the buff will expire.
signal pet_activated(pet_id: String, expires_at: int)
```

### 5.4 `_ready()` and `_process()`

```gdscript
func _ready() -> void:
    _rng.randomize()
    print("[PetManager] Initialized. Valid pets: %s" % str(VALID_PET_IDS))


func _process(_delta: float) -> void:
    var now: int = int(Time.get_unix_time_from_system())

    for pet_id in VALID_PET_IDS:
        var pet_data: Dictionary = SaveLoadManager.pet_state.get(pet_id, {})
        var expires_at: int = int(pet_data.get("active_until_timestamp", 0))
        var was_active: bool = pet_data.get("_was_announced", false)
        var is_active: bool = now < expires_at

        if is_active:
            var remaining: int = expires_at - now
            # Detect new activation (first frame the timer is visible).
            if not was_active:
                SaveLoadManager.pet_state[pet_id]["_was_announced"] = true
                emit_signal("pet_activated", pet_id, expires_at)
                print("[PetManager] Pet '%s' ACTIVATED. Expires in %d seconds." % [pet_id, remaining])

            emit_signal("pet_buff_tick", pet_id, remaining, false)

        else:
            # Was previously active, now expired.
            if was_active:
                SaveLoadManager.pet_state[pet_id]["_was_announced"] = false
                emit_signal("pet_buff_expired", pet_id)
                print("[PetManager] Pet '%s' EXPIRED." % pet_id)
```

### 5.5 Public API

```gdscript
## Activates a pet for PET_ACTIVE_DURATION_SECONDS.
## Reads pet_id: "foxy", "tiger", or "rhino".
## Returns true if activation succeeded, false if invalid pet_id or Treat deduction failed.
func activate_pet(pet_id: String) -> bool:
    if pet_id not in VALID_PET_IDS:
        push_warning("[PetManager] Invalid pet_id: '%s'. Valid: %s" % [pet_id, str(VALID_PET_IDS)])
        return false

    # TODO (future shop integration): Deduct Treat item from inventory here.
    # For Step 9: stubbed. Uncomment when shop/inventory system is ready:
    # if not InventoryManager.try_consume_item("treat", 1):
    #     push_warning("[PetManager] Cannot activate pet '%s': no Treats available." % pet_id)
    #     return false

    var now: int = int(Time.get_unix_time_from_system())
    var expires_at: int = now + PET_ACTIVE_DURATION_SECONDS

    # Initialize pet slot if not present.
    if not SaveLoadManager.pet_state.has(pet_id):
        SaveLoadManager.pet_state[pet_id] = {
            "xp": 0, "level": 1, "active_until_timestamp": 0
        }

    SaveLoadManager.pet_state[pet_id]["active_until_timestamp"] = expires_at
    SaveLoadManager.pet_state[pet_id]["_was_announced"] = false
    SaveLoadManager.save_game()

    print("[PetManager] Pet '%s' activated. Expires at Unix: %d (in %d seconds)." % [
        pet_id, expires_at, PET_ACTIVE_DURATION_SECONDS
    ])

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
        var is_active: bool = is_pet_active(pet_id)
        result[pet_id] = {
            "is_active":        is_active,
            "seconds_remaining": get_pet_remaining_seconds(pet_id),
            "level":            int(SaveLoadManager.pet_state.get(pet_id, {}).get("level", 1)),
            "xp":               int(SaveLoadManager.pet_state.get(pet_id, {}).get("xp", 0))
        }
    return result
```

### 5.6 Full `PetManager.gd` Implementation

```gdscript
# ==============================================================================
# PetManager.gd
# Path: res://src/core/PetManager.gd
# Role: Manages pet activation timers and exposes pet buff status.
# Registered as Autoload after SaveLoadManager.
# ==============================================================================
class_name PetManager
extends Node

const PET_ACTIVE_DURATION_SECONDS: int = 14400
const FOXY_RAID_MULTIPLIER: float = 2.19
const TIGER_ATTACK_MULTIPLIER: float = 5.10
const VALID_PET_IDS: Array[String] = ["foxy", "tiger", "rhino"]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _session_active_pets: Array[String] = []

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


func is_pet_active(pet_id: String) -> bool:
    if pet_id not in VALID_PET_IDS:
        return false
    var pet_data: Dictionary = SaveLoadManager.pet_state.get(pet_id, {})
    var expires_at: int = int(pet_data.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < expires_at


func get_pet_remaining_seconds(pet_id: String) -> int:
    if pet_id not in VALID_PET_IDS:
        return 0
    var pet_data: Dictionary = SaveLoadManager.pet_state.get(pet_id, {})
    var expires_at: int = int(pet_data.get("active_until_timestamp", 0))
    return max(0, expires_at - int(Time.get_unix_time_from_system()))


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
```

---

## SECTION 6: CARD MANAGER — `CardManager.gd`

### 6.1 Class Declaration and Constants

```gdscript
# ==============================================================================
# CardManager.gd
# Path: res://src/core/CardManager.gd
# Role: Manages card collection, chest opening, RNG drops, and set completion.
# Instantiated as child of Main.gd. Emits signals for UI to consume.
# NO direct SaveLoadManager writes except through helper functions.
# ==============================================================================
class_name CardManager
extends Node

## Path to card set definitions.
const CARD_SETS_PATH: String = "res://src/data/card_sets.json"

## Path to chest configuration.
const CHEST_CONFIG_PATH: String = "res://src/data/card_chest_config.json"

## Duplicate card compensation: percentage of the card's star value in coins.
## 1-star duplicate = 500 coins, 2-star = 1000, etc.
const DUPLICATE_COIN_COMPENSATION_PER_STAR: int = 500
```

### 6.2 Properties

```gdscript
## Fully loaded card set definitions from card_sets.json.
## Key: set_id string, Value: Dictionary with set metadata and cards array.
var _card_sets: Dictionary = {}

## Flat registry of all card definitions keyed by card_id.
## Key: card_id string, Value: Dictionary { id, name, star, set_id }.
var _card_registry: Dictionary = {}

## Loaded chest configurations keyed by chest_id.
var _chest_configs: Dictionary = {}

## Tracks whether configs loaded successfully.
var _is_initialized: bool = false

## RNG instance.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
```

### 6.3 Signals

```gdscript
## Emitted when a chest is successfully opened.
## card: Dictionary of the dropped card { id, name, star, set_id }
## is_duplicate: true if player already owned this card.
## coins_compensation: coins awarded if is_duplicate is true (0 otherwise).
signal card_opened(card: Dictionary, is_duplicate: bool, coins_compensation: int)

## Emitted when a card set is fully completed.
## set_id: string id of the completed set.
## reward_spins: number of spins awarded.
## reward_coins: number of coins awarded.
signal set_completed(set_id: String, reward_spins: int, reward_coins: int)

## Emitted when all cards in a chest open batch are revealed.
## cards: Array of card Dictionaries (size matches chest's cards_per_open).
signal chest_opened_batch(cards: Array)

## Emitted when a chest open fails (insufficient coins, invalid chest).
## chest_id: string id. reason: string error message.
signal chest_open_failed(chest_id: String, reason: String)
```

### 6.4 Constructor and Initialization

```gdscript
func _init() -> void:
    _rng.randomize()
    _load_all_configs()


func _load_all_configs() -> void:
    _load_card_sets()
    _load_chest_configs()
    _is_initialized = not _card_sets.is_empty() and not _chest_configs.is_empty()
    if _is_initialized:
        print("[CardManager] Initialized. Sets: %d | Chests: %d | Total cards: %d" % [
            _card_sets.size(), _chest_configs.size(), _card_registry.size()
        ])
    else:
        push_error("[CardManager] Failed to initialize. Check JSON files.")


func _load_card_sets() -> void:
    var file: FileAccess = FileAccess.open(CARD_SETS_PATH, FileAccess.READ)
    if file == null:
        push_error("[CardManager] Cannot open card_sets.json: %d" % FileAccess.get_open_error())
        return

    var raw_text: String = file.get_as_text()
    file.close()

    var json_parser: JSON = JSON.new()
    if json_parser.parse(raw_text) != OK:
        push_error("[CardManager] card_sets.json parse error: %s" % json_parser.get_error_message())
        return

    var data: Variant = json_parser.get_data()
    if not data is Dictionary:
        push_error("[CardManager] card_sets.json root is not a Dictionary.")
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
            "id":                    set_id,
            "name":                 str(set_entry.get("name", "")),
            "theme":                str(set_entry.get("theme", "")),
            "cards":                [],
            "completion_reward_spins":  int(set_entry.get("completion_reward_spins", 0)),
            "completion_reward_coins":  int(set_entry.get("completion_reward_coins", 0))
        }

        for card_entry in cards:
            if not card_entry is Dictionary:
                continue
            var card_id: String = str(card_entry.get("id", ""))
            var card: Dictionary = {
                "id":     card_id,
                "name":   str(card_entry.get("name", "")),
                "star":   int(card_entry.get("star", 1)),
                "set_id": set_id
            }
            _card_sets[set_id]["cards"].append(card)
            _card_registry[card_id] = card


func _load_chest_configs() -> void:
    var file: FileAccess = FileAccess.open(CHEST_CONFIG_PATH, FileAccess.READ)
    if file == null:
        push_error("[CardManager] Cannot open card_chest_config.json: %d" % FileAccess.get_open_error())
        return

    var raw_text: String = file.get_as_text()
    file.close()

    var json_parser: JSON = JSON.new()
    if json_parser.parse(raw_text) != OK:
        push_error("[CardManager] card_chest_config.json parse error: %s" % json_parser.get_error_message())
        return

    var data: Variant = json_parser.get_data()
    if not data is Dictionary:
        push_error("[CardManager] card_chest_config.json root is not a Dictionary.")
        return

    var chests_array: Array = data.get("chests", [])
    for chest_entry in chests_array:
        if not chest_entry is Dictionary:
            continue
        var chest_id: String = str(chest_entry.get("id", ""))
        if chest_id.is_empty():
            continue
        _chest_configs[chest_id] = {
            "id":              chest_id,
            "display_name":    str(chest_entry.get("display_name", "")),
            "cost_coins":      int(chest_entry.get("cost_coins", 0)),
            "cost_gems":       int(chest_entry.get("cost_gems", 0)),
            "cards_per_open":  int(chest_entry.get("cards_per_open", 1)),
            "drop_pool":       str(chest_entry.get("drop_pool", "all_cards")),
            "star_weights":    Dictionary(chest_entry.get("star_weights", {}))
        }
```

### 6.5 Public API: Chest Opening

```gdscript
## Opens a chest of the specified type. Deducts cost, rolls cards, handles duplicates.
## Returns void. Results are emitted via signals.
func open_chest(chest_id: String) -> void:
    if not _is_initialized:
        emit_signal("chest_open_failed", chest_id, "CardManager not initialized.")
        return

    var chest: Dictionary = _chest_configs.get(chest_id, {})
    if chest.is_empty():
        emit_signal("chest_open_failed", chest_id, "Unknown chest_id: '%s'" % chest_id)
        return

    var cost_coins: int = int(chest.get("cost_coins", 0))
    var cost_gems: int = int(chest.get("cost_gems", 0))

    # Deduct coins.
    if cost_coins > 0:
        if not SaveLoadManager.spend_coins(cost_coins):
            emit_signal("chest_open_failed", chest_id,
                "Not enough coins! Need %,d." % cost_coins)
            return

    # Deduct gems (stubbed — no gem system yet).
    if cost_gems > 0:
        push_warning("[CardManager] Gem cost for chest '%s' not yet implemented. Deducting coins only." % chest_id)

    # Roll cards.
    var cards_per_open: int = int(chest.get("cards_per_open", 1))
    var opened_cards: Array[Dictionary] = []

    for i in range(cards_per_open):
        var card: Dictionary = _roll_card(chest)
        opened_cards.append(card)

    # Emit batch signal first.
    emit_signal("chest_opened_batch", opened_cards)

    # Process each card individually.
    for card in opened_cards:
        _process_card_result(card)

    SaveLoadManager.save_game()
    print("[CardManager] Chest '%s' opened. Cards: %s" % [
        chest_id, str(opened_cards.map(func(c): return c.get("id", "")))
    ])
```

### 6.6 Card Roll RNG

```gdscript
## Rolls for a single card based on chest's star weight distribution.
## Returns card Dictionary from _card_registry.
func _roll_card(chest: Dictionary) -> Dictionary:
    var star_weights: Dictionary = chest.get("star_weights", {})
    var weight_sum: int = 0
    for v in star_weights.values():
        weight_sum += int(v)

    if weight_sum == 0:
        push_warning("[CardManager] No star weights defined for chest. Defaulting to 1-star.")
        weight_sum = 1

    # Step 1: Roll a star rarity.
    var roll: int = _rng.randi_range(0, weight_sum - 1)
    var selected_star: int = 1

    for star_key in ["1", "2", "3", "4", "5"]:
        var w: int = int(star_weights.get(star_key, 0))
        roll -= w
        if roll < 0:
            selected_star = int(star_key)
            break

    # Step 2: Collect all cards of that star rarity.
    var candidates: Array[Dictionary] = []
    for card in _card_registry.values():
        if int(card.get("star", 1)) == selected_star:
            candidates.append(card)

    if candidates.is_empty():
        # Fallback: any card.
        candidates.assign(_card_registry.values())

    # Step 3: Random pick from candidates.
    var chosen: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
    return chosen.duplicate(true)
```

### 6.7 Card Result Processing

```gdscript
## Processes a single card drop: checks duplicate, awards compensation, updates collection.
func _process_card_result(card: Dictionary) -> void:
    var card_id: String = str(card.get("id", ""))
    var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])
    var is_duplicate: bool = card_id in owned_ids
    var compensation: int = 0

    if is_duplicate:
        var star: int = int(card.get("star", 1))
        compensation = star * DUPLICATE_COIN_COMPENSATION_PER_STAR
        SaveLoadManager.add_coins(compensation)
        SaveLoadManager.card_collection["total_duplicates"] += 1
        print("[CardManager] Duplicate card '%s' (★%d). Compensation: %,d coins." % [
            card_id, star, compensation
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
```

### 6.8 Set Completion Logic

```gdscript
## Checks if all cards in a set are now owned. Awards reward and emits set_completed.
func _check_set_completion(set_id: String) -> void:
    if set_id.is_empty():
        return

    var completed_sets: Array = SaveLoadManager.card_collection.get("completed_sets", [])
    if set_id in completed_sets:
        return  # Already completed.

    var set_data: Dictionary = _card_sets.get(set_id, {})
    if set_data.is_empty():
        return

    var set_cards: Array = set_data.get("cards", [])
    var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])

    # Check if every card in the set is now owned.
    var all_owned: bool = true
    for set_card in set_cards:
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

        print("[CardManager] SET COMPLETED: '%s'! Reward: %d spins, %,d coins!" % [
            set_id, reward_spins, reward_coins
        ])
```

### 6.9 Query API

```gdscript
## Returns the current collection progress for a specific set.
## Returns Dictionary: { owned: int, total: int, is_complete: bool }
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


## Returns overall collection statistics.
func get_collection_stats() -> Dictionary:
    var owned_ids: Array = SaveLoadManager.card_collection.get("owned_card_ids", [])
    return {
        "total_owned":       owned_ids.size(),
        "total_cards":      _card_registry.size(),
        "total_sets":       _card_sets.size(),
        "completed_sets":   SaveLoadManager.card_collection.get("completed_sets", []).size(),
        "total_duplicates": SaveLoadManager.card_collection.get("total_duplicates", 0)
    }


## Returns all chest configurations for UI display.
func get_all_chest_configs() -> Array:
    return _chest_configs.values()


## Returns whether configs loaded successfully.
func is_ready() -> bool:
    return _is_initialized
```

### 6.10 Full `CardManager.gd` Implementation

```gdscript
# ==============================================================================
# CardManager.gd
# Path: res://src/core/CardManager.gd
# Role: Card collection, chest opening RNG, set completion.
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
    else:
        owned_ids.append(card_id)
        SaveLoadManager.card_collection["owned_card_ids"] = owned_ids
        _check_set_completion(card.get("set_id", ""))

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
        "total_owned":       owned_ids.size(),
        "total_cards":      _card_registry.size(),
        "total_sets":       _card_sets.size(),
        "completed_sets":   SaveLoadManager.card_collection.get("completed_sets", []).size(),
        "total_duplicates": SaveLoadManager.card_collection.get("total_duplicates", 0)
    }


func get_all_chest_configs() -> Array:
    return _chest_configs.values()


func is_ready() -> bool:
    return _is_initialized
```

---

## SECTION 7: NPC SIMULATOR UPDATE — Pet Loot Multipliers

Update `generate_raid_target()` to apply the Foxy multiplier, and update `on_live_attack_triggered()` to apply the Tiger multiplier.

### 7.1 Updated `generate_raid_target()`

Add the Foxy multiplier block after the base loot calculation:

```gdscript
func generate_raid_target() -> Dictionary:
    var npc_profile: Dictionary = _generate_npc_profile()
    var npc_village_level: int = _generate_npc_village_level()

    var base_loot: int = npc_village_level * RAID_LOOT_BASE_MULTIPLIER
    var variance_factor: float = 1.0 + _rng.randf_range(-RAID_LOOT_VARIANCE, RAID_LOOT_VARIANCE)
    var loot_pool: int = max(1, int(float(base_loot) * variance_factor))

    # ── Foxy Raid Loot Boost ────────────────────────────────────────────────
    if _is_foxy_active():
        loot_pool = int(float(loot_pool) * PetManager.FOXY_RAID_MULTIPLIER)
        print("[NPCSimulator] Foxy active! Raid loot boosted to: %,d" % loot_pool)

    var is_protected: bool = _rng.randf() < 0.30
    if is_protected:
        loot_pool = max(1, int(float(loot_pool) * 0.5))

    var result: Dictionary = {
        "npc_name":          npc_profile.get("name", "Unknown"),
        "avatar_id":         npc_profile.get("avatar_id", AVATAR_ID_MIN),
        "loot_pool":         loot_pool,
        "npc_village_level": npc_village_level,
        "is_protected":      is_protected,
        "raid_slots":        3
    }

    emit_signal("raid_target_generated", result)
    return result
```

### 7.2 Updated `on_live_attack_triggered()`

Add the Tiger multiplier block when emitting the live attack result:

```gdscript
func on_live_attack_triggered(attack_count: int) -> void:
    for i in range(max(1, attack_count)):
        var npc_profile: Dictionary = _generate_npc_profile()
        var npc_village_level: int = _generate_npc_village_level()
        var target_item_index: int = _rng.randi_range(0, ITEMS_PER_VILLAGE - 1)
        var npc_item_current_level: int = _rng.randi_range(1, MAX_ITEM_LEVEL)

        # ── Tiger Attack Loot Boost ──────────────────────────────────────────
        var loot_bonus: int = 0
        if _is_tiger_active():
            loot_bonus = int(float(npc_village_level) * 1000.0 * (PetManager.TIGER_ATTACK_MULTIPLIER - 1.0))
            print("[NPCSimulator] Tiger active! Attack loot bonus: %,d" % loot_bonus)

        var live_attack: Dictionary = {
            "npc_name":             npc_profile.get("name", "Unknown"),
            "avatar_id":            npc_profile.get("avatar_id", AVATAR_ID_MIN),
            "npc_village_level":    npc_village_level,
            "target_item_index":     target_item_index,
            "npc_item_before_level": npc_item_current_level,
            "npc_item_after_level":  max(0, npc_item_current_level - 1),
            "attack_index":         i,
            "tiger_loot_bonus":     loot_bonus
        }

        emit_signal("live_attack_resolved", live_attack)
```

### 7.3 New Helper Functions in NPCSimulator

Add these private helper functions near the bottom of `NPCSimulator.gd`:

```gdscript
func _is_foxy_active() -> bool:
    var foxy_data: Dictionary = SaveLoadManager.pet_state.get("foxy", {})
    var expires_at: int = int(foxy_data.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < expires_at


func _is_tiger_active() -> bool:
    var tiger_data: Dictionary = SaveLoadManager.pet_state.get("tiger", {})
    var expires_at: int = int(tiger_data.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < expires_at
```

---

## SECTION 8: MAIN SCENE UPDATES — `Main.gd`

Add `PetManager` and `CardManager` instantiation:

```gdscript
func _ready() -> void:
    print("[Main] CoinMaster booting...")

    # ── 1. Slot Machine Logic ──────────────────────────────────────────────
    slot_machine_logic = SlotMachineLogic.new()
    slot_machine_logic.name = "SlotMachineLogic"
    add_child(slot_machine_logic)

    # ── 2. NPC Simulator ────────────────────────────────────────────────────
    npc_simulator = NPCSimulator.new()
    npc_simulator.name = "NPCSimulator"
    add_child(npc_simulator)

    # ── 3. Slot Machine UI ─────────────────────────────────────────────────
    var panel_scene: PackedScene = load("res://src/ui/SlotMachinePanel.tscn")
    if panel_scene != null:
        slot_machine_ui = panel_scene.instantiate() as SlotMachineUI
        if slot_machine_ui != null:
            add_child(slot_machine_ui)

    # ── 4. Card Manager ────────────────────────────────────────────────────
    var card_manager: CardManager = CardManager.new()
    card_manager.name = "CardManager"
    add_child(card_manager)
    print("[Main] CardManager instantiated.")

    # ── 5. Event System ────────────────────────────────────────────────────
    EventManager.register_event(Event_CoinCraze.new())
    EventManager.register_event(Event_VikingQuest.new())
    print("[Main] Events registered.")

    # ── 6. Wire SaveLoadManager → NPCSimulator ─────────────────────────────
    SaveLoadManager.game_loaded.connect(_on_save_game_loaded)
    print("[Main] Boot complete.")


func _on_save_game_loaded() -> void:
    npc_simulator.calculate_offline_events()
```

Also add the `CardManager` import at the top:

```gdscript
var slot_machine_logic: SlotMachineLogic
var npc_simulator: NPCSimulator
var slot_machine_ui: SlotMachineUI
var card_manager: CardManager  # NEW
```

### 8.1 `project.godot` Update

Register `PetManager` as an Autoload **after** `SaveLoadManager`:

```ini
[autoload]

SaveLoadManager="*res://src/utils/SaveLoadManager.gd"
EventManager="*res://src/events/EventManager.gd"
PetManager="*res://src/core/PetManager.gd"
```

> **Important:** `PetManager` must be an Autoload so it can use `_process()` to check pet timers every frame. `CardManager` is NOT an Autoload — it is instantiated as a child of Main.gd because it does not need real-time timer polling.

---

## SECTION 9: ARCHITECTURAL CONSTRAINTS & GOTCHAS

### 9.1 Absolute Prohibitions

| Prohibition | Reason |
|---|---|
| Do NOT call `SaveLoadManager.coins = value` directly | Use `add_coins()`, `spend_coins()` only |
| Do NOT import `NPCSimulator` inside `PetManager` | Pet buffs are read from `pet_state` dictionary by `NPCSimulator` |
| Do NOT import `PetManager` inside `NPCSimulator` | `NPCSimulator` reads `pet_state` directly to avoid circular coupling |
| Do NOT call `save_game()` inside `_roll_card()` or `_process_card_result()` | Save is called once per chest open batch in `open_chest()` |
| Do NOT mutate `pet_state["foxy"]` etc. from `CardManager` | Separate concerns — cards and pets are independent |
| Do NOT call `_check_set_completion()` for already-completed sets | Guard in function returns early if set is in `completed_sets` |

### 9.2 Pet Timer Gotchas

**Gotcha 1: `_was_announced` is session-only state**
- The `_was_announced` flag is NOT persisted — it resets on game restart.
- This means the `pet_activated` signal fires again when the player returns while a pet is still active.
- This is intentional: the player should see the UI feedback even after a restart mid-session.

**Gotcha 2: Foxy multiplier is multiplicative with Viking difficulty**
- Foxy's `×2.19` applies to the base loot_pool from `generate_raid_target()`.
- If the player is also in Viking Quest Hard mode (which boosts Viking reward value), Foxy does NOT affect Viking spins — Foxy only affects `NPCSimulator.generate_raid_target()` loot.

**Gotcha 3: Tiger loot bonus is an additive component**
- Tiger adds `village_level × 1000 × 4.10` to the attack loot value.
- This is NOT a multiplier on the entire loot pool — it is an additive bonus component stored in `live_attack["tiger_loot_bonus"]`.
- The UI should display this bonus separately when `tiger_loot_bonus > 0`.

### 9.3 Card Gotchas

**Gotcha 4: Duplicate card compensation is per-card**
- Each card in a multi-card chest (Gold = 3, Magic = 5) is processed individually.
- A player can get 3 duplicates in one Gold Chest opening — they receive 3 separate compensation payouts.

**Gotcha 5: Set completion is checked after every new card drop**
- The order of drops does not matter — if the 8th card in a set is the last one needed, `set_completed` fires immediately after that drop.
- No separate "check all sets" call is needed.

**Gotcha 6: `card_sets.json` and `card_chest_config.json` are loaded on CardManager construction**
- If the files are missing or malformed, `_is_initialized = false` and `open_chest()` emits `chest_open_failed`.
- The game does not crash — chest opening gracefully fails with a signal.

**Gotcha 7: `card_collection` is nested in `SaveLoadManager.pet_state` is NOT nested**
- `SaveLoadManager.card_collection` is a sibling of `pet_state`, not nested inside it.
- `pet_state` stores `{ "foxy": {...}, "tiger": {...}, "rhino": {...} }` and `"viking_raid_protection"`.
- `card_collection` stores `{ "owned_card_ids": [], "completed_sets": [], "total_duplicates": 0 }`.
- These are separate top-level keys in `SaveLoadManager`.

---

## SECTION 10: EDGE CASE REGISTRY

| Edge Case | Trigger | Handling |
|---|---|---|
| Player opens chest with 0 coins | `spend_coins()` fails | `chest_open_failed` signal emitted. No cards deducted. |
| All card sets completed | All cards owned | `open_chest()` continues working (new cards can't exist). Player accumulates duplicates. |
| Card JSON files missing | Files absent | `_is_initialized = false`. `open_chest()` emits `chest_open_failed`. No crash. |
| Duplicate star_weights in chest config | Malformed JSON | `_roll_card()` falls back to `weight_sum = 1`. All cards equally likely. |
| Pet activated while already active | `activate_pet()` called again | Overwrites `active_until_timestamp` to now + 14400. Duration refreshed, not extended. |
| Player quits with pet active | App closed | Pet timer persists via `SaveLoadManager.pet_state`. On restart, `PetManager._process()` detects active pet and fires `pet_activated`. |
| Foxy and Tiger both active | Both pets on cooldown | Both multipliers apply independently. Raid gets ×2.19, attack gets additive bonus. |
| Treat deduction stubbed | No inventory system yet | `activate_pet()` always succeeds. Treat cost is TODO for future shop step. |
| Card from set that is already complete | Re-opened | `_check_set_completion()` returns immediately. No double reward. |
| `owned_card_ids` corrupted (not Array) | Corrupted save | `_apply_state_from_dictionary()` validates and resets to `[]` if invalid. |

---

## SECTION 11: COMPLETION CHECKLIST

**File Existence:**
- [ ] `res://src/data/card_sets.json` valid JSON with at least 3 sets, each with 8 cards
- [ ] `res://src/data/card_chest_config.json` valid JSON with 3 chest types
- [ ] `res://src/core/PetManager.gd` with `class_name PetManager`, registered as Autoload
- [ ] `res://src/core/CardManager.gd` with `class_name CardManager`
- [ ] `NPCSimulator.gd` updated with `_is_foxy_active()`, `_is_tiger_active()`, and loot multiplier integration
- [ ] `SaveLoadManager.gd` updated with `card_collection` in defaults, save, and load
- [ ] `Main.gd` instantiates `CardManager` as child node

**PetManager:**
- [ ] `extends Node` (not `RefCounted`)
- [ ] Registered as Autoload in `project.godot` after `SaveLoadManager` and `EventManager`
- [ ] `_process(delta)` checks all 3 pet timers every frame
- [ ] `_was_announced` flag prevents duplicate `pet_activated` signals per activation window
- [ ] `FOXY_RAID_MULTIPLIER = 2.19` (+119%)
- [ ] `TIGER_ATTACK_MULTIPLIER = 5.10` (+410%)
- [ ] `activate_pet()` writes `active_until_timestamp = now + 14400`
- [ ] `activate_pet()` calls `SaveLoadManager.save_game()`
- [ ] `is_pet_active()` reads from `pet_state` without writing
- [ ] `get_all_pet_status()` returns Dictionary with `is_active`, `seconds_remaining`, `level`, `xp` per pet
- [ ] `pet_buff_tick` emitted every frame while active
- [ ] `pet_buff_expired` emitted once when transition from active to inactive

**CardManager:**
- [ ] `extends Node`
- [ ] `card_sets.json` and `card_chest_config.json` loaded in `_init()`
- [ ] `_is_initialized` set correctly after config load
- [ ] `_card_registry` flat Dictionary keyed by card_id
- [ ] `_card_sets` nested Dictionary keyed by set_id
- [ ] `open_chest()` deducts coins before rolling
- [ ] `open_chest()` calls `SaveLoadManager.save_game()` after processing
- [ ] `_roll_card()` uses two-step RNG: star rarity first, then card pick from that rarity pool
- [ ] Star weight lookup: `star_weights` dict keys are strings ("1", "2"...) not ints
- [ ] `_process_card_result()` detects duplicate, awards compensation, emits `card_opened`
- [ ] `_check_set_completion()` checks ALL cards in set before emitting `set_completed`
- [ ] `set_completed` awards spins AND coins from `completion_reward_spins/coins` in JSON
- [ ] `set_completed` guard: early return if set already in `completed_sets`
- [ ] Duplicate compensation formula: `star × 500` coins
- [ ] `get_set_progress()` returns `{owned, total, is_complete}`
- [ ] `get_collection_stats()` returns `{total_owned, total_cards, total_sets, completed_sets, total_duplicates}`

**NPCSimulator Integration:**
- [ ] `generate_raid_target()` applies `FOXY_RAID_MULTIPLIER` to `loot_pool` if Foxy active
- [ ] `on_live_attack_triggered()` adds `tiger_loot_bonus` to live attack result if Tiger active
- [ ] `_is_foxy_active()` reads `pet_state["foxy"]["active_until_timestamp"]`
- [ ] `_is_tiger_active()` reads `pet_state["tiger"]["active_until_timestamp"]`
- [ ] No `PetManager` import in `NPCSimulator` — reads `pet_state` directly
- [ ] Rhino check unchanged — `_is_rhino_active()` still checks `pet_state["rhino"]`

**SaveLoadManager Updates:**
- [ ] `_apply_defaults()` initializes `card_collection` with `owned_card_ids`, `completed_sets`, `total_duplicates`
- [ ] `_build_save_dictionary()` includes `"card_collection": card_collection.duplicate(true)`
- [ ] `_apply_state_from_dictionary()` validates and loads `card_collection` from save data
- [ ] `card_collection` is a sibling of `pet_state`, NOT nested inside it

**Separation of Concerns:**
- [ ] `PetManager` does NOT call `NPCSimulator` —单向, NPC reads pet_state
- [ ] `CardManager` does NOT call `PetManager` or `NPCSimulator`
- [ ] `NPCSimulator` does NOT import `PetManager` — reads `pet_state` dictionary

**Static Typing:** All variables, parameters, return types typed.

**Logging:**
- [ ] `PetManager._ready()` prints initialization
- [ ] `PetManager.activate_pet()` prints activation
- [ ] `PetManager._process()` prints expiration
- [ ] `NPCSimulator.generate_raid_target()` prints Foxy boost when active
- [ ] `NPCSimulator.on_live_attack_triggered()` prints Tiger bonus when active
- [ ] `CardManager._init()` prints config load summary
- [ ] `CardManager._check_set_completion()` prints set completion with rewards
- [ ] `CardManager._process_card_result()` prints new card and duplicate
- [ ] All log messages include `[ClassName]` prefix

**DO NOT proceed to Step 10 until this checklist is fully verified.**

---

## SECTION 12: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 10 will build `res://src/ui/TrainerConsole.gd` as a Developer Tools overlay for QA. It will implement resource injection (instant coin/spin/gem editing), RNG override for slot outcomes, time dilation to fast-forward event activation windows, state wiping for fresh-play testing, and a Pet/Cards debug panel to instantly activate pets and open chests for balance testing. Step 10 also performs final integration verification, confirming all 10 steps compile without errors, all signals are correctly connected, and the save/load cycle is fully functional.
