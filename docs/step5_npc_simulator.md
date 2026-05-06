```markdown
# step5_npc_simulator.md

## Technical Specification: NPC Offline Simulation Engine
**Target Engine:** Godot 4.x  
**Execution Agent:** Cursor (AI Coder)  
**Step:** 5 of 10 — Implement `NPCSimulator.gd` as the offline multiplayer simulation layer.  
**Depends On:** Step 2 complete (`SaveLoadManager` autoload). Step 4 complete (`VillageManager` node accessible). Step 3 complete (`SlotMachineLogic` signals defined).  
**Output File:** `res://src/entities/NPCSimulator.gd`

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **ZERO UI CODE.** No `Label`, `Button`, `Tween`, `AnimationPlayer`, `Control`, or any visual Node. This is pure simulation logic.
- **ZERO hardcoded NPC names or avatar IDs inline in logic functions.** All name pools and avatar ranges must be defined as constants or static data arrays at the top of the file.
- **NEVER** write directly to `SaveLoadManager.coins` or `SaveLoadManager.shields` via assignment. Use only `SaveLoadManager.consume_shield()`, `SaveLoadManager.spend_coins()`, `SaveLoadManager.add_coins()`.
- **NEVER** call `VillageManager.upgrade_item()` from this script. Village item downgrades are a separate operation defined in this spec — they write directly to `SaveLoadManager.village_items_state` with a dedicated private function.
- **STRICTLY** use static typing on every variable and function signature.
- This script is **not** an Autoload. It is instantiated as a child node of the main game scene and connected to `SlotMachineLogic`'s signals externally.
- All signals carry typed data payloads. The UI layer connects to these signals.
- `save_game()` must be called after any batch of mutations to persistent state.
- Confirm with the completion checklist before proceeding to Step 6.

---

## SECTION 1: ARCHITECTURAL ROLE

`NPCSimulator.gd` performs two distinct jobs:

**Job A — Retroactive Offline Attack Simulation:** On every game boot, it calculates how many NPC attacks occurred while the player was away, then applies their consequences (shield depletion, coin loss, building downgrade) to the current save state. The player sees a summary of what happened while they were offline.

**Job B — Live Raid Target Generation:** When `SlotMachineLogic` emits a `raid_triggered` signal, `NPCSimulator` generates a plausible fake NPC profile and loot pool for the player to raid in the current session.

### Data Flow

```
[Game Boot]
SaveLoadManager.last_login_timestamp
       │
       ▼
NPCSimulator.calculate_offline_events()
       │
       ├──▶ _compute_attack_count(delta_seconds) ──▶ Poisson approximation ──▶ N attacks
       │
       └──▶ for i in N:
               ├──▶ _resolve_single_attack()
               │       ├──▶ RhinoPet active? ──▶ block (70% chance)
               │       ├──▶ SaveLoadManager.consume_shield() ──▶ success? ──▶ attack blocked
               │       └──▶ no shield: _apply_unshielded_attack()
               │               ├──▶ SaveLoadManager.spend_coins(penalty)
               │               └──▶ _downgrade_random_village_item()
               │
               ├──▶ _build_offline_attack_log_entry(npc_profile, outcome)
               └──▶ offline_events_calculated(log_entries) signal emitted

[Raid Spin Result]
SlotMachineLogic.raid_triggered(raid_count)
       │
       ▼
NPCSimulator.generate_raid_target()
       │
       └──▶ Returns Dictionary { npc_name, avatar_id, loot_pool, village_level }
```

### Interaction Contract

| System | Interaction | Details |
|---|---|---|
| `SaveLoadManager` | **Reads:** `last_login_timestamp`, `shields`, `coins`, `current_village_level`, `village_items_state`, `pet_state` | Direct property read |
| `SaveLoadManager` | **Writes:** via `consume_shield()`, `spend_coins()` | Never direct assignment |
| `SaveLoadManager` | **Writes:** `village_items_state` element | Only via `_downgrade_random_village_item()` |
| `SaveLoadManager` | **Calls:** `save_game()` | After full offline batch completes |
| `SlotMachineLogic` | **Receives signal:** `raid_triggered(raid_count)` | Connected externally in main scene |
| `SlotMachineLogic` | **Receives signal:** `attack_triggered(attack_count)` | Connected externally in main scene — triggers live NPC attack display |
| `PetManager` (Step 9) | **Queried via:** `_is_rhino_active()` helper | Reads `SaveLoadManager.pet_state.rhino` timestamp |
| `VillageUI` (Step 6) | **Connects to signals** | Receives offline log and raid target data |

---

## SECTION 2: CONSTANTS AND STATIC DATA

Declare all of the following at the top of the file. These are the only permitted hardcoded values.

### 2.1 Simulation Tuning Constants

```gdscript
## Expected number of NPC attacks per hour of offline time.
## At 0.5: a player offline for 2 hours expects ~1 attack on average.
## Tune this to adjust aggression of the offline simulation.
const ATTACK_RATE_PER_HOUR: float = 0.5

## Maximum number of offline attacks that can be applied in a single boot.
## Prevents punishing players who were offline for very long periods.
## Even with 100 hours offline, the player receives at most this many attacks.
const MAX_OFFLINE_ATTACKS: int = 5

## Maximum offline window considered for attack calculation, in seconds.
## Offline time beyond this cap is ignored for attack probability.
## Set to 72 hours (259200 seconds) to prevent excessive punishment on return.
const MAX_OFFLINE_WINDOW_SECONDS: float = 259200.0

## Minimum offline time (seconds) before ANY attack simulation runs.
## Prevents triggering attacks on instant restarts or crash recoveries.
## Set to 5 minutes (300 seconds).
const MIN_OFFLINE_WINDOW_SECONDS: float = 300.0

## Fraction of the player's current coin balance deducted per unshielded attack.
## At 0.08: each successful attack costs the player 8% of their coins.
const COIN_LOSS_FRACTION_PER_ATTACK: float = 0.08

## Minimum coin loss per unshielded attack regardless of balance.
## Prevents zero-loss attacks when the player has very few coins.
const MIN_COIN_LOSS_PER_ATTACK: int = 100

## Rhino pet attack block probability when active (0.0 to 1.0).
## At 0.70: Rhino blocks 70% of incoming attacks while active.
const RHINO_BLOCK_PROBABILITY: float = 0.70

## Base loot pool multiplier for raid target generation.
## Raid target's loot = village_level * this value * random variance.
const RAID_LOOT_BASE_MULTIPLIER: int = 50000

## Variance range for raid loot (±percentage as float 0.0-1.0).
## At 0.3: loot varies ±30% from the base calculated amount.
const RAID_LOOT_VARIANCE: float = 0.30

## Number of items per village. Mirror of VillageManager constant.
## Redeclared here to avoid a hard dependency on VillageManager class.
const ITEMS_PER_VILLAGE: int = 5

## Maximum item level. Items at level 0 cannot be downgraded further.
const MAX_ITEM_LEVEL: int = 5
```

### 2.2 NPC Name Pool

```gdscript
## Pool of first name fragments used for procedural NPC name generation.
const NPC_FIRST_NAMES: Array[String] = [
    "Iron", "Silver", "Gold", "Storm", "Frost", "Shadow", "Bright",
    "Thunder", "Swift", "Ember", "Stone", "Wild", "Dark", "Steel",
    "Rune", "Blaze", "Crimson", "Ancient", "Mystic", "Grim",
    "Savage", "Lone", "Battle", "Dread", "Warp", "Jade", "Copper",
    "Titan", "Viper", "Rogue", "Nomad", "Raven", "Wolf", "Bear",
    "Falcon", "Hawk", "Eagle", "Lion", "Dragon", "Phoenix"
]

## Pool of second name fragments combined with first names.
const NPC_SECOND_NAMES: Array[String] = [
    "Master", "Lord", "King", "Raider", "Plunderer", "Seeker",
    "Bringer", "Crusher", "Slayer", "Runner", "Rider", "Walker",
    "Breaker", "Keeper", "Hunter", "Watcher", "Stalker", "Drifter",
    "Caster", "Forger", "Builder", "Reaper", "Striker", "Chaser",
    "Bane", "Fang", "Claw", "Shield", "Blade", "Arrow",
    "Storm", "Fire", "Ice", "Stone", "Wind", "Wave", "Light", "Night"
]

## Range of avatar IDs available in the asset system.
## avatar_id will be a random integer in [AVATAR_ID_MIN, AVATAR_ID_MAX].
## Matches the sprite filenames: avatar_001.png through avatar_032.png.
const AVATAR_ID_MIN: int = 1
const AVATAR_ID_MAX: int = 32
```

---

## SECTION 3: FULL GDSCRIPT IMPLEMENTATION SPEC

Write `res://src/entities/NPCSimulator.gd` with exactly the following structure.

### 3.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# NPCSimulator.gd
# Path: res://src/entities/NPCSimulator.gd
# Role: Offline attack simulation and live raid/attack NPC target generation.
# NO UI CODE. Pure simulation and data generation logic.
# Access pattern: Instantiated in main scene. Connected to SlotMachineLogic signals.
# Signals: Emitted after simulation completes. UI layer connects to these.
# ==============================================================================
extends Node
class_name NPCSimulator
```

### 3.2 Signals

```gdscript
## Emitted once after calculate_offline_events() completes its full batch.
## attack_log: Array of Dictionaries, one per simulated attack (including blocked ones).
## Each entry schema defined in Section 5.1.
signal offline_events_calculated(attack_log: Array)

## Emitted for each individual offline attack resolution during the batch.
## Used by UI to build a scrollable attack history notification panel.
signal offline_attack_resolved(entry: Dictionary)

## Emitted when generate_raid_target() completes.
## raid_target: Dictionary with npc_name, avatar_id, loot_pool, village_level.
signal raid_target_generated(raid_target: Dictionary)

## Emitted when a live attack outcome is resolved (from attack_triggered signal).
## live_attack: Dictionary with npc_profile and outcome data.
signal live_attack_resolved(live_attack: Dictionary)

## Emitted when the Rhino pet successfully blocks an attack during simulation.
signal rhino_block_activated(attack_index: int)

## Emitted when an unshielded attack successfully downgrades a village item.
## item_index: which item was downgraded. new_level: the item's level after downgrade.
signal village_item_downgraded(item_index: int, new_level: int)
```

### 3.3 Private State Variables

```gdscript
## Seeded RNG instance for all probabilistic decisions in this system.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Cached log of the most recent offline event batch.
## Cleared and rebuilt each time calculate_offline_events() runs.
var _last_offline_log: Array[Dictionary] = []

## Flag set to true after the first calculate_offline_events() call per session.
## Prevents double-calculation if called more than once on boot.
var _offline_events_processed: bool = false
```

### 3.4 `_ready()` Function

```gdscript
func _ready() -> void:
    _rng.randomize()
```

---

## SECTION 4: CORE PUBLIC API

### 4.1 `calculate_offline_events() -> void`

**Purpose:** Called exactly once per game session, immediately after `SaveLoadManager.load_game()` completes (connected to `SaveLoadManager.game_loaded` signal in the main scene). Calculates all NPC attacks that occurred while the player was offline and applies their consequences to the save state.

**Full logic specification (execute in this exact order):**

**Idempotency Guard:**

1. If `_offline_events_processed == true`: print warning and return. This function must only execute once per session.

**Time Delta Calculation:**

2. Read `var last_timestamp: int = SaveLoadManager.last_login_timestamp`.
3. If `last_timestamp == 0`: this is a new player with no prior session. Set `_offline_events_processed = true` and return. No attacks on first boot.
4. Read `var current_timestamp: int = int(Time.get_unix_time_from_system())`.
5. Calculate `var delta_seconds: float = float(current_timestamp - last_timestamp)`.
6. If `delta_seconds <= 0.0`: clamp to `0.0`. Log warning (system clock may have gone backwards).
7. If `delta_seconds < MIN_OFFLINE_WINDOW_SECONDS`: no simulation. Set `_offline_events_processed = true`. Print: `"[NPCSimulator] Offline window too short (%0.1fs). No attacks simulated."` Return.
8. Clamp `delta_seconds` to `MAX_OFFLINE_WINDOW_SECONDS` from above: `delta_seconds = min(delta_seconds, MAX_OFFLINE_WINDOW_SECONDS)`.

**Attack Count Determination:**

9. Call `var attack_count: int = _compute_attack_count(delta_seconds)`.
10. Print: `"[NPCSimulator] Offline window: %0.1fs. Simulated attacks: %d."` % [delta_seconds, attack_count]`.

**Attack Resolution Loop:**

11. Clear `_last_offline_log`.
12. For `i` in `range(attack_count)`:
    - Call `var npc_profile: Dictionary = _generate_npc_profile()`.
    - Call `var outcome: Dictionary = _resolve_single_attack(i, npc_profile)`.
    - Call `_build_offline_attack_log_entry(npc_profile, outcome)` and append to `_last_offline_log`.
    - Emit `offline_attack_resolved(entry)` immediately for that entry.

**Persistence and Completion:**

13. If `attack_count > 0`: call `SaveLoadManager.save_game()`.
14. Set `_offline_events_processed = true`.
15. Emit `offline_events_calculated(_last_offline_log)`.
16. Print: `"[NPCSimulator] Offline simulation complete. %d events logged."` % _last_offline_log.size()`.

```gdscript
func calculate_offline_events() -> void:
    if _offline_events_processed:
        push_warning("[NPCSimulator] calculate_offline_events() called more than once this session. Ignoring.")
        return

    var last_timestamp: int = SaveLoadManager.last_login_timestamp
    if last_timestamp == 0:
        print("[NPCSimulator] New player. No offline simulation needed.")
        _offline_events_processed = true
        return

    var current_timestamp: int = int(Time.get_unix_time_from_system())
    var delta_seconds: float = float(current_timestamp - last_timestamp)

    if delta_seconds <= 0.0:
        push_warning("[NPCSimulator] Negative or zero time delta detected (%0.1fs). System clock anomaly?" % delta_seconds)
        delta_seconds = 0.0

    if delta_seconds < MIN_OFFLINE_WINDOW_SECONDS:
        print("[NPCSimulator] Offline window too short (%0.1fs). No attacks simulated." % delta_seconds)
        _offline_events_processed = true
        return

    delta_seconds = min(delta_seconds, MAX_OFFLINE_WINDOW_SECONDS)

    var attack_count: int = _compute_attack_count(delta_seconds)
    print("[NPCSimulator] Offline window: %0.1fs (~%0.1f hours). Simulated attacks: %d." % [
        delta_seconds, delta_seconds / 3600.0, attack_count
    ])

    _last_offline_log.clear()

    for i in range(attack_count):
        var npc_profile: Dictionary = _generate_npc_profile()
        var outcome: Dictionary = _resolve_single_attack(i, npc_profile)
        var log_entry: Dictionary = _build_offline_attack_log_entry(npc_profile, outcome)
        _last_offline_log.append(log_entry)
        emit_signal("offline_attack_resolved", log_entry)

    if attack_count > 0:
        SaveLoadManager.save_game()

    _offline_events_processed = true
    emit_signal("offline_events_calculated", _last_offline_log)
    print("[NPCSimulator] Offline simulation complete. %d events logged." % _last_offline_log.size())
```

### 4.2 `generate_raid_target() -> Dictionary`

**Purpose:** Called when `SlotMachineLogic` emits `raid_triggered`. Generates a complete fake NPC target profile with a calculated loot pool for the player to raid. Emits `raid_target_generated` after building the result.

**Return Dictionary Schema:**

```
KEY                 TYPE        DESCRIPTION
────────────────────────────────────────────────────────────────────
"npc_name"          String      Procedurally generated display name.
"avatar_id"         int         Integer ID mapping to a sprite asset.
"loot_pool"         int         Coin amount available to raid. Calculated
                                from player's current village level.
"npc_village_level" int         Simulated village level of the NPC target.
                                Within ±2 of player's current level.
"is_protected"      bool        If true, this NPC "has shields" and raid
                                loot is reduced by 50%. Cosmetic only — no
                                actual shield state is checked. Determined
                                by random probability (30% chance protected).
"raid_slots"        int         Number of dig spots available (always 3).
                                Reserved for future Raid minigame UI use.
```

**Full logic specification:**

1. Generate `npc_profile` via `_generate_npc_profile()`.
2. Calculate NPC village level: `var npc_village_level: int = _generate_npc_village_level()`.
3. Calculate base loot: `var base_loot: int = npc_village_level * RAID_LOOT_BASE_MULTIPLIER`.
4. Apply variance: multiply base_loot by a random float in range `[1.0 - RAID_LOOT_VARIANCE, 1.0 + RAID_LOOT_VARIANCE]`. Cast result to `int`.
5. Determine protection status: `var is_protected: bool = _rng.randf() < 0.30`.
6. If `is_protected`: multiply loot by `0.5`. Cast to int. Enforce minimum of `1`.
7. Clamp final loot to minimum of `1` in all cases.
8. Build result Dictionary.
9. Emit `raid_target_generated(result)`.
10. Print: `"[NPCSimulator] Raid target generated: %s | Loot: %d | Protected: %s"`.
11. Return result.

```gdscript
func generate_raid_target() -> Dictionary:
    var npc_profile: Dictionary = _generate_npc_profile()
    var npc_village_level: int = _generate_npc_village_level()

    var base_loot: int = npc_village_level * RAID_LOOT_BASE_MULTIPLIER
    var variance_factor: float = 1.0 + _rng.randf_range(-RAID_LOOT_VARIANCE, RAID_LOOT_VARIANCE)
    var loot_pool: int = max(1, int(float(base_loot) * variance_factor))

    var is_protected: bool = _rng.randf() < 0.30
    if is_protected:
        loot_pool = max(1, int(float(loot_pool) * 0.5))

    var result: Dictionary = {
        "npc_name":         npc_profile.get("name", "Unknown"),
        "avatar_id":        npc_profile.get("avatar_id", AVATAR_ID_MIN),
        "loot_pool":        loot_pool,
        "npc_village_level": npc_village_level,
        "is_protected":     is_protected,
        "raid_slots":       3
    }

    emit_signal("raid_target_generated", result)
    print("[NPCSimulator] Raid target generated: %s | Loot: %d | Protected: %s" % [
        result["npc_name"], result["loot_pool"], str(result["is_protected"])
    ])

    return result
```

### 4.3 `on_live_attack_triggered(attack_count: int) -> void`

**Purpose:** Connected to `SlotMachineLogic.attack_triggered` signal. Resolves a live (in-session) attack event against a simulated NPC target for the player to execute, generating an attack result summary for the UI.

**Logic:** Generate `attack_count` NPC profiles. For each, generate a fake village with a randomly selected downgrade target. Build a live attack summary Dictionary. Emit `live_attack_resolved` for each.

```gdscript
func on_live_attack_triggered(attack_count: int) -> void:
    for i in range(max(1, attack_count)):
        var npc_profile: Dictionary = _generate_npc_profile()
        var npc_village_level: int = _generate_npc_village_level()

        # Randomly pick which item on the NPC's village will be downgraded.
        var target_item_index: int = _rng.randi_range(0, ITEMS_PER_VILLAGE - 1)

        # Simulate the NPC item level within a plausible range.
        var npc_item_current_level: int = _rng.randi_range(1, MAX_ITEM_LEVEL)

        var live_attack: Dictionary = {
            "npc_name":              npc_profile.get("name", "Unknown"),
            "avatar_id":             npc_profile.get("avatar_id", AVATAR_ID_MIN),
            "npc_village_level":     npc_village_level,
            "target_item_index":     target_item_index,
            "npc_item_before_level": npc_item_current_level,
            "npc_item_after_level":  max(0, npc_item_current_level - 1),
            "attack_index":          i
        }

        emit_signal("live_attack_resolved", live_attack)
        print("[NPCSimulator] Live attack resolved vs %s. Item %d downgraded from %d to %d." % [
            live_attack["npc_name"],
            target_item_index,
            npc_item_current_level,
            live_attack["npc_item_after_level"]
        ])
```

---

## SECTION 5: PRIVATE SIMULATION FUNCTIONS

### 5.1 `_compute_attack_count(delta_seconds: float) -> int`

**Purpose:** Uses a Poisson distribution approximation to determine how many NPC attacks occurred during the offline window. Poisson is the mathematically correct distribution for modeling the number of independent events occurring in a fixed time interval at a known average rate.

**Mathematical Model:**

The Poisson probability mass function gives the probability of exactly `k` events in interval `t` with rate `λ` per unit time:

```
P(k events) = (λt)^k * e^(-λt) / k!

Where:
  λ = ATTACK_RATE_PER_HOUR (events per hour)
  t = delta_seconds / 3600.0 (hours elapsed)
  k = number of attacks (0, 1, 2, ...)
  λt = expected number of attacks (the mean of the distribution)
```

**Implementation:** Rather than computing the full PMF (which requires factorial and exponential functions), use the **Knuth algorithm** for Poisson sampling. This algorithm generates an exact Poisson-distributed random variate using only a uniform RNG:

```
Algorithm (Knuth, 1969):
  L = e^(-λt)
  k = 0
  p = 1.0
  do:
    k = k + 1
    u = uniform random in (0, 1]
    p = p * u
  while p > L
  return k - 1
```

This produces exact Poisson variates without lookup tables. It is O(λt) per call — acceptable since `λt` is small (≤ `ATTACK_RATE_PER_HOUR * MAX_OFFLINE_WINDOW_SECONDS / 3600.0` = 0.5 * 72 = 36 iterations maximum, capped by `MAX_OFFLINE_ATTACKS`).

```gdscript
func _compute_attack_count(delta_seconds: float) -> int:
    # Convert offline window to hours for the rate calculation.
    var hours_elapsed: float = delta_seconds / 3600.0

    # Lambda: expected number of attacks in this window.
    var lambda_t: float = ATTACK_RATE_PER_HOUR * hours_elapsed

    # Edge case: zero expected attacks means zero actual attacks.
    if lambda_t <= 0.0:
        return 0

    # Knuth Poisson sampling algorithm.
    # L = e^(-lambda_t). Using exp() from GDScript's built-in math.
    var L: float = exp(-lambda_t)
    var k: int = 0
    var p: float = 1.0

    # Safety iteration limit to prevent infinite loop on extreme lambda values.
    # MAX_OFFLINE_ATTACKS serves as the hard ceiling regardless of RNG output.
    var iteration_cap: int = MAX_OFFLINE_ATTACKS * 10

    while true:
        k += 1
        # randf() returns [0,1). Avoid exactly 0 by adding tiny epsilon.
        var u: float = max(0.00001, _rng.randf())
        p *= u
        if p <= L:
            break
        if k >= iteration_cap:
            push_warning("[NPCSimulator] Poisson iteration cap reached. Clamping.")
            break

    # k-1 is the Poisson variate. Clamp to [0, MAX_OFFLINE_ATTACKS].
    var raw_count: int = max(0, k - 1)
    return min(raw_count, MAX_OFFLINE_ATTACKS)
```

### 5.2 `_resolve_single_attack(attack_index: int, npc_profile: Dictionary) -> Dictionary`

**Purpose:** Applies the consequence of one NPC attack against the player's current state. Checks Rhino pet, checks shields, and if neither blocks, applies damage.

**Return Dictionary Schema (outcome):**

```
KEY                     TYPE        DESCRIPTION
────────────────────────────────────────────────────────────────────────
"blocked_by_rhino"      bool        True if Rhino pet intercepted this attack.
"blocked_by_shield"     bool        True if a shield was consumed.
"shields_remaining"     int         Shield count after this attack resolved.
"coins_lost"            int         Coin amount deducted (0 if blocked).
"item_downgraded"       bool        True if a village item was downgraded.
"downgraded_item_index" int         Index of downgraded item (-1 if none).
"downgraded_from_level" int         Item level before downgrade (-1 if none).
"downgraded_to_level"   int         Item level after downgrade (-1 if none).
```

**Full logic specification:**

1. Initialize outcome Dictionary with all keys set to safe defaults.
2. **Rhino Check:** Call `_is_rhino_active()`. If true:
   - Roll `_rng.randf()`. If `< RHINO_BLOCK_PROBABILITY`:
     - Set `outcome["blocked_by_rhino"] = true`.
     - Emit `rhino_block_activated(attack_index)`.
     - Print: `"[NPCSimulator] Attack %d blocked by Rhino pet."`.
     - Return outcome immediately.
3. **Shield Check:** Call `SaveLoadManager.consume_shield()`. If returns `true` (shield was consumed):
   - Set `outcome["blocked_by_shield"] = true`.
   - Set `outcome["shields_remaining"] = SaveLoadManager.shields`.
   - Print: `"[NPCSimulator] Attack %d blocked by shield. Shields remaining: %d."`.
   - Return outcome immediately.
4. **Unshielded Attack Resolution:**
   - Set `outcome["shields_remaining"] = 0`.
   - Call `_apply_unshielded_attack(outcome)` — this mutates `outcome` in place and calls the SaveLoadManager mutators.
   - Return outcome.

```gdscript
func _resolve_single_attack(attack_index: int, npc_profile: Dictionary) -> Dictionary:
    var outcome: Dictionary = {
        "blocked_by_rhino":      false,
        "blocked_by_shield":     false,
        "shields_remaining":     SaveLoadManager.shields,
        "coins_lost":            0,
        "item_downgraded":       false,
        "downgraded_item_index": -1,
        "downgraded_from_level": -1,
        "downgraded_to_level":   -1
    }

    # ── Rhino Pet Check ───────────────────────────────────────────────────────
    if _is_rhino_active():
        if _rng.randf() < RHINO_BLOCK_PROBABILITY:
            outcome["blocked_by_rhino"] = true
            emit_signal("rhino_block_activated", attack_index)
            print("[NPCSimulator] Attack %d blocked by Rhino pet." % attack_index)
            return outcome

    # ── Shield Check ──────────────────────────────────────────────────────────
    if SaveLoadManager.consume_shield():
        outcome["blocked_by_shield"] = true
        outcome["shields_remaining"] = SaveLoadManager.shields
        print("[NPCSimulator] Attack %d blocked by shield. Shields remaining: %d." % [
            attack_index, SaveLoadManager.shields
        ])
        return outcome

    # ── Unshielded Attack ─────────────────────────────────────────────────────
    outcome["shields_remaining"] = 0
    _apply_unshielded_attack(outcome)
    return outcome
```

### 5.3 `_apply_unshielded_attack(outcome: Dictionary) -> void`

**Purpose:** Applies coin loss and building downgrade when a player has no shields and Rhino did not block. Mutates the `outcome` Dictionary in place AND mutates `SaveLoadManager` state.

**Full logic specification:**

1. **Coin Loss Calculation:**
   - `var coin_loss: int = int(float(SaveLoadManager.coins) * COIN_LOSS_FRACTION_PER_ATTACK)`.
   - Clamp to minimum: `coin_loss = max(MIN_COIN_LOSS_PER_ATTACK, coin_loss)`.
   - Clamp to maximum of current balance: `coin_loss = min(coin_loss, SaveLoadManager.coins)`.
   - Call `SaveLoadManager.spend_coins(coin_loss)`. The return value of `spend_coins` may be `false` only if `coins == 0` — in that case coin_loss was already clamped to 0 by the min(coin_loss, 0) rule. Handle gracefully.
   - Set `outcome["coins_lost"] = coin_loss`.

2. **Village Item Downgrade:**
   - Call `_downgrade_random_village_item()`. This returns a Dictionary with keys `item_index`, `from_level`, `to_level`. If it returns an empty Dictionary (no downgradeable items found), skip downgrade fields.
   - If result is not empty:
     - Set `outcome["item_downgraded"] = true`.
     - Set `outcome["downgraded_item_index"] = result["item_index"]`.
     - Set `outcome["downgraded_from_level"] = result["from_level"]`.
     - Set `outcome["downgraded_to_level"] = result["to_level"]`.
     - Emit `village_item_downgraded(result["item_index"], result["to_level"])`.

3. Print: `"[NPCSimulator] Unshielded attack! Coins lost: %d. Item downgraded: %s."`.

```gdscript
func _apply_unshielded_attack(outcome: Dictionary) -> void:
    # ── Coin Loss ─────────────────────────────────────────────────────────────
    var current_coins: int = SaveLoadManager.coins
    var coin_loss: int = int(float(current_coins) * COIN_LOSS_FRACTION_PER_ATTACK)
    coin_loss = max(MIN_COIN_LOSS_PER_ATTACK, coin_loss)
    coin_loss = min(coin_loss, current_coins)

    if coin_loss > 0:
        SaveLoadManager.spend_coins(coin_loss)

    outcome["coins_lost"] = coin_loss

    # ── Village Item Downgrade ─────────────────────────────────────────────────
    var downgrade_result: Dictionary = _downgrade_random_village_item()
    if not downgrade_result.is_empty():
        outcome["item_downgraded"]       = true
        outcome["downgraded_item_index"] = downgrade_result["item_index"]
        outcome["downgraded_from_level"] = downgrade_result["from_level"]
        outcome["downgraded_to_level"]   = downgrade_result["to_level"]
        emit_signal("village_item_downgraded",
            downgrade_result["item_index"],
            downgrade_result["to_level"]
        )

    print("[NPCSimulator] Unshielded attack! Coins lost: %d. Item downgraded: %s." % [
        coin_loss, str(not downgrade_result.is_empty())
    ])
```

### 5.4 `_downgrade_random_village_item() -> Dictionary`

**Purpose:** Selects a random village item that is currently above level 0 and decrements it by 1. Writes directly to `SaveLoadManager.village_items_state`. Returns a summary Dictionary, or an empty Dictionary if no items can be downgraded.

**Full logic specification:**

1. Read `var items_state: Array = SaveLoadManager.village_items_state`.
2. Build a list of eligible indices: items where `int(items_state[i]) > 0`.
3. If eligible list is empty: return `{}`. No downgrade possible (all items at level 0).
4. Pick a random index from the eligible list using `_rng.randi_range(0, eligible.size() - 1)`.
5. Read `var from_level: int = int(items_state[chosen_index])`.
6. Set `SaveLoadManager.village_items_state[chosen_index] = from_level - 1`.
7. Return `{ "item_index": chosen_index, "from_level": from_level, "to_level": from_level - 1 }`.

**Critical note:** Do NOT call `SaveLoadManager.save_game()` here. Save is called once at the end of the full offline batch in `calculate_offline_events()`. Calling save inside this loop would be redundant and expensive.

```gdscript
func _downgrade_random_village_item() -> Dictionary:
    var items_state: Array = SaveLoadManager.village_items_state
    var eligible_indices: Array[int] = []

    for i in range(ITEMS_PER_VILLAGE):
        if i < items_state.size() and int(items_state[i]) > 0:
            eligible_indices.append(i)

    if eligible_indices.is_empty():
        return {}

    var pick: int = _rng.randi_range(0, eligible_indices.size() - 1)
    var chosen_index: int = eligible_indices[pick]
    var from_level: int = int(items_state[chosen_index])
    var to_level: int = from_level - 1

    SaveLoadManager.village_items_state[chosen_index] = to_level

    return {
        "item_index": chosen_index,
        "from_level": from_level,
        "to_level":   to_level
    }
```

### 5.5 `_generate_npc_profile() -> Dictionary`

**Purpose:** Procedurally generates a fake NPC identity. Used by both offline simulation and raid generation.

```gdscript
func _generate_npc_profile() -> Dictionary:
    var first: String = NPC_FIRST_NAMES[_rng.randi_range(0, NPC_FIRST_NAMES.size() - 1)]
    var second: String = NPC_SECOND_NAMES[_rng.randi_range(0, NPC_SECOND_NAMES.size() - 1)]
    var name: String = first + second

    # Append a short numeric suffix to reduce perceived repetition.
    var suffix: int = _rng.randi_range(1, 9999)
    var display_name: String = "%s#%04d" % [name, suffix]

    var avatar_id: int = _rng.randi_range(AVATAR_ID_MIN, AVATAR_ID_MAX)

    return {
        "name":      display_name,
        "avatar_id": avatar_id
    }
```

### 5.6 `_generate_npc_village_level() -> int`

**Purpose:** Generates a simulated village level for an NPC target. Skewed to be near the player's current level to maintain plausibility.

**Logic:** Base = `SaveLoadManager.current_village_level`. Add a random offset in range `[-2, +2]`. Clamp to minimum of `1`.

```gdscript
func _generate_npc_village_level() -> int:
    var player_level: int = SaveLoadManager.current_village_level
    var offset: int = _rng.randi_range(-2, 2)
    return max(1, player_level + offset)
```

### 5.7 `_build_offline_attack_log_entry(npc_profile: Dictionary, outcome: Dictionary) -> Dictionary`

**Purpose:** Combines the NPC profile and attack outcome into a single flat log entry Dictionary suitable for UI rendering.

```gdscript
func _build_offline_attack_log_entry(npc_profile: Dictionary, outcome: Dictionary) -> Dictionary:
    return {
        "npc_name":              npc_profile.get("name", "Unknown"),
        "avatar_id":             npc_profile.get("avatar_id", AVATAR_ID_MIN),
        "blocked_by_rhino":      outcome.get("blocked_by_rhino", false),
        "blocked_by_shield":     outcome.get("blocked_by_shield", false),
        "shields_remaining":     outcome.get("shields_remaining", 0),
        "coins_lost":            outcome.get("coins_lost", 0),
        "item_downgraded":       outcome.get("item_downgraded", false),
        "downgraded_item_index": outcome.get("downgraded_item_index", -1),
        "downgraded_from_level": outcome.get("downgraded_from_level", -1),
        "downgraded_to_level":   outcome.get("downgraded_to_level", -1)
    }
```

### 5.8 `_is_rhino_active() -> bool`

**Purpose:** Checks whether the Rhino pet's active buff is currently in effect. Reads from `SaveLoadManager.pet_state` without importing `PetManager`. This avoids a circular dependency — `PetManager` (Step 9) and `NPCSimulator` both exist without knowing about each other.

**Logic:** Read `SaveLoadManager.pet_state.get("rhino", {})`. Check `active_until_timestamp`. If current Unix time is less than that timestamp, Rhino is active.

```gdscript
func _is_rhino_active() -> bool:
    var rhino_state: Dictionary = SaveLoadManager.pet_state.get("rhino", {})
    var active_until: int = int(rhino_state.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < active_until
```

---

## SECTION 6: PUBLIC QUERY API

### 6.1 `get_last_offline_log() -> Array`

Returns the attack log from the most recent offline simulation. Used by UI to display the notification panel after loading.

```gdscript
func get_last_offline_log() -> Array:
    return _last_offline_log.duplicate(true)
```

### 6.2 `get_offline_events_processed() -> bool`

Returns whether offline simulation has already run this session.

```gdscript
func get_offline_events_processed() -> bool:
    return _offline_events_processed
```

### 6.3 `get_expected_attacks_per_hour() -> float`

Returns the configured attack rate. Used by Trainer overlay to display current simulation parameters.

```gdscript
func get_expected_attacks_per_hour() -> float:
    return ATTACK_RATE_PER_HOUR
```

---

## SECTION 7: SIGNAL CONNECTION INSTRUCTIONS (FOR MAIN SCENE)

These connections must be made in the main scene script after both `SlotMachineLogic` and `NPCSimulator` nodes are added to the scene tree. Do not make these connections inside `NPCSimulator.gd` itself (would create hard coupling).

```gdscript
# In the main scene's _ready() function:

# Connect offline simulation to trigger after save loads.
SaveLoadManager.game_loaded.connect(npc_simulator.calculate_offline_events)

# Connect live spin outcomes to NPC simulator.
slot_machine_logic.raid_triggered.connect(func(count): npc_simulator.generate_raid_target())
slot_machine_logic.attack_triggered.connect(npc_simulator.on_live_attack_triggered)
```

---

## SECTION 8: POISSON DISTRIBUTION VALIDATION TABLE

The following table validates `_compute_attack_count()` outputs against analytical expectations. Cursor must verify these approximate matches using a 10,000-iteration Monte Carlo loop in a temporary test script.

| Offline Hours | λt (Expected Attacks) | Expected P(0 attacks) | Expected P(1 attack) | Expected P(2+ attacks) |
|---|---|---|---|---|
| 0.08h (5 min) | 0.042 | 95.9% | 4.0% | 0.08% |
| 1h | 0.5 | 60.7% | 30.3% | 9.0% |
| 2h | 1.0 | 36.8% | 36.8% | 26.4% |
| 4h | 2.0 | 13.5% | 27.1% | 59.4% |
| 10h | 5.0 | 0.67% | 3.37% | 95.96% (capped at 5) |
| 72h (cap) | 36.0 | ~0% | ~0% | 100% (capped at 5) |

Monte Carlo validation: over 10,000 calls with `delta_seconds = 7200.0` (2h), the mean of returned values must fall within `[0.8, 1.2]` (i.e., within 20% of the theoretical mean of 1.0).

---

## SECTION 9: EDGE CASE REGISTRY

| Edge Case | Trigger Condition | Handling |
|---|---|---|
| **First boot** | `last_login_timestamp == 0` | Return immediately. Zero attacks. No log emitted with entries. |
| **System clock went backward** | `current_timestamp < last_login_timestamp` | `delta_seconds` is negative or zero. Clamp to 0. No attacks simulated. Warning logged. |
| **Instant restart** | `delta_seconds < MIN_OFFLINE_WINDOW_SECONDS` | No simulation. Return after setting `_offline_events_processed`. |
| **Very long offline** | `delta_seconds > MAX_OFFLINE_WINDOW_SECONDS` | Clamp to cap. Poisson draws against capped value. Max damage bounded. |
| **All village items at level 0** | Player just started or was fully attacked | `_downgrade_random_village_item()` returns `{}`. Outcome logs `item_downgraded = false`. Attack still applies coin loss. |
| **Zero coins during attack** | `SaveLoadManager.coins == 0` | `coin_loss` clamped to `min(MIN_COIN_LOSS_PER_ATTACK, 0) = 0`. `spend_coins(0)` called harmlessly. |
| **Double call guard** | `calculate_offline_events()` called twice | Second call logs warning and returns immediately. State not re-mutated. |
| **Rhino data missing** | `pet_state` does not contain `"rhino"` key | `_is_rhino_active()` reads `.get("rhino", {})` safely. Returns `false`. No crash. |
| **MAX_OFFLINE_ATTACKS = 0** | Config accidentally set to 0 | Loop runs 0 times. Empty log emitted. Signal fires with empty array. No crash. |
| **Poisson generates > MAX_OFFLINE_ATTACKS** | High lambda, lucky RNG | `min(raw_count, MAX_OFFLINE_ATTACKS)` clamps output before loop. |
| **village_items_state wrong size** | Corrupted save | `_downgrade_random_village_item()` checks `i < items_state.size()` before reading. Returns `{}` if all indices out of range. |
| **NPC name collision** | Same first+second+suffix | Statistically negligible (40×38×9999 ≈ 15M combinations). Acceptable. No deduplication needed. |

---

## SECTION 10: UNIT TEST VERIFICATION PROTOCOL

### Test A: No Simulation on First Boot
1. Set `SaveLoadManager.last_login_timestamp = 0`.
2. Call `npc_simulator.calculate_offline_events()`.
3. **Expected:** `offline_events_calculated` fires with empty Array.
4. **Expected:** No coins deducted, no items downgraded.

### Test B: Short Window Suppression
1. Set `last_login_timestamp` to `current_unix_time - 60` (60 seconds ago).
2. Call `calculate_offline_events()`.
3. **Expected:** Console prints short window message. No attacks. Empty log.

### Test C: Attack Count Distribution (Statistical)
1. Write a temporary loop calling `npc_simulator._compute_attack_count(7200.0)` 10,000 times.
2. **Expected:** Mean of results falls within `[0.8, 1.2]`.
3. **Expected:** No result ever exceeds `MAX_OFFLINE_ATTACKS`.

### Test D: Shield Consumption on Attack
1. Set `SaveLoadManager.shields = 2`.
2. Set `last_login_timestamp` to force exactly 1 attack (use `_compute_attack_count` override via Trainer in Step 10, or set timestamp manually).
3. Call `calculate_offline_events()`.
4. **Expected:** If Rhino inactive and shield consumed: `SaveLoadManager.shields == 1`. Coins unchanged. No downgrade.

### Test E: Unshielded Full Attack
1. Set `SaveLoadManager.shields = 0`. Ensure Rhino inactive (`active_until_timestamp = 0`).
2. Set `SaveLoadManager.coins = 1000000`.
3. Set `SaveLoadManager.village_items_state = [3, 2, 4, 1, 5]`.
4. Force 1 attack via timestamp manipulation.
5. **Expected:** `SaveLoadManager.coins < 1000000` (coins deducted).
6. **Expected:** Exactly one item in `village_items_state` is decremented by 1.
7. **Expected:** `village_item_downgraded` signal fires.
8. **Expected:** Log entry has `"item_downgraded": true`.

### Test F: Raid Target Generation
1. Set `SaveLoadManager.current_village_level = 5`.
2. Call `npc_simulator.generate_raid_target()`.
3. **Expected:** Returns Dictionary with all 6 required keys.
4. **Expected:** `npc_village_level` is in range `[3, 7]` (player level ± 2).
5. **Expected:** `loot_pool >= 1`.
6. **Expected:** `raid_slots == 3`.
7. **Expected:** `raid_target_generated` signal fires.

### Test G: Double-Call Idempotency
1. Call `calculate_offline_events()` twice in the same session.
2. **Expected:** Second call logs warning and returns immediately.
3. **Expected:** Coins and items are only mutated once (from the first call).

### Test H: Rhino Block
1. Set `SaveLoadManager.pet_state.rhino.active_until_timestamp` to `current_unix + 10000`.
2. Force 3 attacks.
3. **Expected:** Across many test runs, approximately 70% of attacks are blocked by Rhino.
4. **Expected:** `rhino_block_activated` signal fires for each blocked attack.

---

## SECTION 11: COMPLETION CHECKLIST

Before proceeding to Step 6, Cursor must confirm ALL of the following:

- [ ] `res://src/entities/NPCSimulator.gd` exists with `class_name NPCSimulator`
- [ ] File is **NOT** registered as an Autoload in `project.godot`
- [ ] Zero UI node references exist anywhere in the file
- [ ] `calculate_offline_events()` is guarded by `_offline_events_processed` flag — cannot run twice
- [ ] `calculate_offline_events()` returns immediately if `last_login_timestamp == 0`
- [ ] `calculate_offline_events()` clamps `delta_seconds` to `MAX_OFFLINE_WINDOW_SECONDS` from above
- [ ] `calculate_offline_events()` suppresses simulation when `delta_seconds < MIN_OFFLINE_WINDOW_SECONDS`
- [ ] `_compute_attack_count()` implements the Knuth Poisson algorithm with a safety iteration cap
- [ ] `_compute_attack_count()` clamps output to `MAX_OFFLINE_ATTACKS`
- [ ] `_resolve_single_attack()` checks Rhino first, then shields, then applies damage — in that exact order
- [ ] `_apply_unshielded_attack()` uses `SaveLoadManager.spend_coins()` — never direct assignment
- [ ] `_downgrade_random_village_item()` does NOT call `save_game()` — batch save only
- [ ] `_downgrade_random_village_item()` returns empty Dictionary when all items are at level 0
- [ ] `_downgrade_random_village_item()` writes to `SaveLoadManager.village_items_state` directly — not via `VillageManager.upgrade_item()`
- [ ] `_is_rhino_active()` uses `SaveLoadManager.pet_state.get("rhino", {})` — no direct `PetManager` import
- [ ] `generate_raid_target()` clamps `loot_pool` to minimum of `1` in all paths
- [ ] `generate_raid_target()` emits `raid_target_generated` signal before returning
- [ ] All 6 signals declared with typed parameters
- [ ] NPC name pool constants contain at least 30 entries each
- [ ] All variables and function signatures use static typing
- [ ] `save_game()` is called exactly once after the full offline batch, not inside the per-attack loop

**DO NOT proceed to Step 6 until this checklist is fully verified.**

---

## SECTION 12: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 6 will build `res://src/ui/MainHUD.gd` and `res://src/ui/SlotMachineUI.gd`. `SlotMachineUI` connects to `SlotMachineLogic.spin_completed` to drive reel animations via Godot's `Tween` node. It connects to `spin_failed_insufficient_spins` to disable the spin button. `MainHUD` connects to `SaveLoadManager.coins_changed`, `spins_changed`, and `shields_changed` signals to update counter labels reactively. Neither UI script contains any game math — they are pure signal consumers and visual responders. All input is locked during Tween animation to prevent spin-spam desynchronization.
```