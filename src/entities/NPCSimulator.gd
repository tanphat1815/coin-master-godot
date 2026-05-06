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

# ─── Simulation Tuning Constants ─────────────────────────────────────────────

## Expected number of NPC attacks per hour of offline time.
const ATTACK_RATE_PER_HOUR: float = 0.5

## Maximum number of offline attacks that can be applied in a single boot.
const MAX_OFFLINE_ATTACKS: int = 5

## Maximum offline window considered for attack calculation, in seconds (72 hours).
const MAX_OFFLINE_WINDOW_SECONDS: float = 259200.0

## Minimum offline time (seconds) before ANY attack simulation runs (5 minutes).
const MIN_OFFLINE_WINDOW_SECONDS: float = 300.0

## Fraction of coins deducted per unshielded attack.
const COIN_LOSS_FRACTION_PER_ATTACK: float = 0.08

## Minimum coin loss per unshielded attack regardless of balance.
const MIN_COIN_LOSS_PER_ATTACK: int = 100

## Rhino pet attack block probability when active.
const RHINO_BLOCK_PROBABILITY: float = 0.70

## Base loot pool multiplier for raid target generation.
const RAID_LOOT_BASE_MULTIPLIER: int = 50000

## Variance range for raid loot (±percentage as float 0.0-1.0).
const RAID_LOOT_VARIANCE: float = 0.30

## Number of items per village. Mirror of VillageManager constant.
const ITEMS_PER_VILLAGE: int = 5

## Maximum item level.
const MAX_ITEM_LEVEL: int = 5

# ─── NPC Name Pool ─────────────────────────────────────────────────────────────

const NPC_FIRST_NAMES: Array[String] = [
    "Iron", "Silver", "Gold", "Storm", "Frost", "Shadow", "Bright",
    "Thunder", "Swift", "Ember", "Stone", "Wild", "Dark", "Steel",
    "Rune", "Blaze", "Crimson", "Ancient", "Mystic", "Grim",
    "Savage", "Lone", "Battle", "Dread", "Warp", "Jade", "Copper",
    "Titan", "Viper", "Rogue", "Nomad", "Raven", "Wolf", "Bear",
    "Falcon", "Hawk", "Eagle", "Lion", "Dragon", "Phoenix"
]

const NPC_SECOND_NAMES: Array[String] = [
    "Master", "Lord", "King", "Raider", "Plunderer", "Seeker",
    "Bringer", "Crusher", "Slayer", "Runner", "Rider", "Walker",
    "Breaker", "Keeper", "Hunter", "Watcher", "Stalker", "Drifter",
    "Caster", "Forger", "Builder", "Reaper", "Striker", "Chaser",
    "Bane", "Fang", "Claw", "Shield", "Blade", "Arrow",
    "Storm", "Fire", "Ice", "Stone", "Wind", "Wave", "Light", "Night"
]

const AVATAR_ID_MIN: int = 1
const AVATAR_ID_MAX: int = 32

# ─── Private State ─────────────────────────────────────────────────────────────

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_offline_log: Array[Dictionary] = []
var _offline_events_processed: bool = false

# ─── Signals ───────────────────────────────────────────────────────────────────

## Emitted once after calculate_offline_events() completes its full batch.
signal offline_events_calculated(attack_log: Array)

## Emitted for each individual offline attack resolution during the batch.
signal offline_attack_resolved(entry: Dictionary)

## Emitted when generate_raid_target() completes.
signal raid_target_generated(raid_target: Dictionary)

## Emitted when a live attack outcome is resolved.
signal live_attack_resolved(live_attack: Dictionary)

## Emitted when the Rhino pet successfully blocks an attack.
signal rhino_block_activated(attack_index: int)

## Emitted when an unshielded attack downgrades a village item.
signal village_item_downgraded(item_index: int, new_level: int)


func _ready() -> void:
    _rng.randomize()


# ==============================================================================
# Core Public API
# ==============================================================================

func calculate_offline_events() -> void:
    # ── Idempotency Guard ──────────────────────────────────────────────────────
    if _offline_events_processed:
        push_warning("[NPCSimulator] calculate_offline_events() called more than once this session. Ignoring.")
        return

    # ── Time Delta Calculation ──────────────────────────────────────────────────
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

    # ── Attack Count Determination ──────────────────────────────────────────────
    var attack_count: int = _compute_attack_count(delta_seconds)
    print("[NPCSimulator] Offline window: %0.1fs (~%0.1f hours). Simulated attacks: %d." % [
        delta_seconds, delta_seconds / 3600.0, attack_count
    ])

    # ── Attack Resolution Loop ──────────────────────────────────────────────────
    _last_offline_log.clear()

    for i in range(attack_count):
        var npc_profile: Dictionary = _generate_npc_profile()
        var outcome: Dictionary = _resolve_single_attack(i, npc_profile)
        var log_entry: Dictionary = _build_offline_attack_log_entry(npc_profile, outcome)
        _last_offline_log.append(log_entry)
        emit_signal("offline_attack_resolved", log_entry)

    # ── Persistence and Completion ───────────────────────────────────────────────
    if attack_count > 0:
        SaveLoadManager.save_game()

    _offline_events_processed = true
    emit_signal("offline_events_calculated", _last_offline_log)
    print("[NPCSimulator] Offline simulation complete. %d events logged." % _last_offline_log.size())


func generate_raid_target() -> Dictionary:
    var npc_profile: Dictionary = _generate_npc_profile()
    var npc_village_level: int = _generate_npc_village_level()

    var base_loot: int = npc_village_level * RAID_LOOT_BASE_MULTIPLIER
    var variance_factor: float = 1.0 + _rng.randf_range(-RAID_LOOT_VARIANCE, RAID_LOOT_VARIANCE)
    var loot_pool: int = max(1, int(float(base_loot) * variance_factor))

    # ── Foxy Raid Loot Boost ───────────────────────────────────────────────────
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
    print("[NPCSimulator] Raid target generated: %s | Loot: %d | Protected: %s" % [
        result["npc_name"], result["loot_pool"], str(result["is_protected"])
    ])

    return result


func on_live_attack_triggered(attack_count: int) -> void:
    for i in range(max(1, attack_count)):
        var npc_profile: Dictionary = _generate_npc_profile()
        var npc_village_level: int = _generate_npc_village_level()
        var target_item_index: int = _rng.randi_range(0, ITEMS_PER_VILLAGE - 1)
        var npc_item_current_level: int = _rng.randi_range(1, MAX_ITEM_LEVEL)

        # ── Tiger Attack Loot Boost ─────────────────────────────────────────────
        var loot_bonus: int = 0
        if _is_tiger_active():
            loot_bonus = int(float(npc_village_level) * 1000.0 * (PetManager.TIGER_ATTACK_MULTIPLIER - 1.0))
            print("[NPCSimulator] Tiger active! Attack loot bonus: %,d" % loot_bonus)

        var live_attack: Dictionary = {
            "npc_name":              npc_profile.get("name", "Unknown"),
            "avatar_id":             npc_profile.get("avatar_id", AVATAR_ID_MIN),
            "npc_village_level":     npc_village_level,
            "target_item_index":     target_item_index,
            "npc_item_before_level": npc_item_current_level,
            "npc_item_after_level":  max(0, npc_item_current_level - 1),
            "attack_index":          i,
            "tiger_loot_bonus":      loot_bonus
        }

        emit_signal("live_attack_resolved", live_attack)
        print("[NPCSimulator] Live attack resolved vs %s. Item %d downgraded from %d to %d." % [
            live_attack["npc_name"],
            target_item_index,
            npc_item_current_level,
            live_attack["npc_item_after_level"]
        ])


# ==============================================================================
# Private Simulation Functions
# ==============================================================================

func _compute_attack_count(delta_seconds: float) -> int:
    var hours_elapsed: float = delta_seconds / 3600.0
    var lambda_t: float = ATTACK_RATE_PER_HOUR * hours_elapsed

    if lambda_t <= 0.0:
        return 0

    # Knuth Poisson sampling algorithm.
    var L: float = exp(-lambda_t)
    var k: int = 0
    var p: float = 1.0
    var iteration_cap: int = MAX_OFFLINE_ATTACKS * 10

    while true:
        k += 1
        var u: float = max(0.00001, _rng.randf())
        p *= u
        if p <= L:
            break
        if k >= iteration_cap:
            push_warning("[NPCSimulator] Poisson iteration cap reached. Clamping.")
            break

    var raw_count: int = max(0, k - 1)
    return min(raw_count, MAX_OFFLINE_ATTACKS)


func _resolve_single_attack(attack_index: int, _npc_profile: Dictionary) -> Dictionary:
    var outcome: Dictionary = {
        "blocked_by_rhino":      false,
        "blocked_by_shield":    false,
        "shields_remaining":    SaveLoadManager.shields,
        "coins_lost":           0,
        "item_downgraded":      false,
        "downgraded_item_index": -1,
        "downgraded_from_level": -1,
        "downgraded_to_level":   -1
    }

    # ── Rhino Pet Check ─────────────────────────────────────────────────────────
    if _is_rhino_active():
        if _rng.randf() < RHINO_BLOCK_PROBABILITY:
            outcome["blocked_by_rhino"] = true
            emit_signal("rhino_block_activated", attack_index)
            print("[NPCSimulator] Attack %d blocked by Rhino pet." % attack_index)
            return outcome

    # ── Shield Check ────────────────────────────────────────────────────────────
    if SaveLoadManager.consume_shield():
        outcome["blocked_by_shield"] = true
        outcome["shields_remaining"] = SaveLoadManager.shields
        print("[NPCSimulator] Attack %d blocked by shield. Shields remaining: %d." % [
            attack_index, SaveLoadManager.shields
        ])
        return outcome

    # ── Unshielded Attack ───────────────────────────────────────────────────────
    outcome["shields_remaining"] = 0
    _apply_unshielded_attack(outcome)
    return outcome


func _apply_unshielded_attack(outcome: Dictionary) -> void:
    # ── Coin Loss ────────────────────────────────────────────────────────────────
    var current_coins: int = SaveLoadManager.coins
    var coin_loss: int = int(float(current_coins) * COIN_LOSS_FRACTION_PER_ATTACK)
    coin_loss = max(MIN_COIN_LOSS_PER_ATTACK, coin_loss)
    coin_loss = min(coin_loss, current_coins)

    if coin_loss > 0:
        SaveLoadManager.spend_coins(coin_loss)

    outcome["coins_lost"] = coin_loss

    # ── Village Item Downgrade ──────────────────────────────────────────────────
    var downgrade_result: Dictionary = _downgrade_random_village_item()
    if not downgrade_result.is_empty():
        outcome["item_downgraded"]        = true
        outcome["downgraded_item_index"]  = downgrade_result["item_index"]
        outcome["downgraded_from_level"]  = downgrade_result["from_level"]
        outcome["downgraded_to_level"]    = downgrade_result["to_level"]
        emit_signal("village_item_downgraded",
            downgrade_result["item_index"],
            downgrade_result["to_level"]
        )

    print("[NPCSimulator] Unshielded attack! Coins lost: %d. Item downgraded: %s." % [
        coin_loss, str(not downgrade_result.is_empty())
    ])


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


func _generate_npc_profile() -> Dictionary:
    var first: String  = NPC_FIRST_NAMES[_rng.randi_range(0, NPC_FIRST_NAMES.size() - 1)]
    var second: String = NPC_SECOND_NAMES[_rng.randi_range(0, NPC_SECOND_NAMES.size() - 1)]
    var suffix: int    = _rng.randi_range(1, 9999)
    var display_name: String = "%s%s#%04d" % [first, second, suffix]
    var avatar_id: int = _rng.randi_range(AVATAR_ID_MIN, AVATAR_ID_MAX)

    return {
        "name":      display_name,
        "avatar_id": avatar_id
    }


func _generate_npc_village_level() -> int:
    var player_level: int = SaveLoadManager.current_village_level
    var offset: int = _rng.randi_range(-2, 2)
    return max(1, player_level + offset)


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


func _is_rhino_active() -> bool:
    var now: int = int(Time.get_unix_time_from_system())

    # ── Check real Rhino pet ──────────────────────────────────────────────────
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


func _is_foxy_active() -> bool:
    var foxy_data: Dictionary = SaveLoadManager.pet_state.get("foxy", {})
    var expires_at: int = int(foxy_data.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < expires_at


func _is_tiger_active() -> bool:
    var tiger_data: Dictionary = SaveLoadManager.pet_state.get("tiger", {})
    var expires_at: int = int(tiger_data.get("active_until_timestamp", 0))
    return int(Time.get_unix_time_from_system()) < expires_at


# ==============================================================================
# Public Query API
# ==============================================================================

func get_last_offline_log() -> Array:
    return _last_offline_log.duplicate(true)


func get_offline_events_processed() -> bool:
    return _offline_events_processed


func get_expected_attacks_per_hour() -> float:
    return ATTACK_RATE_PER_HOUR
