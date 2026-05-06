```markdown
# step11_bet_multiplier.md

## Technical Specification: Super Bet Multiplier System
**Target Engine:** Godot 4.x  
**Execution Agent:** Cursor (AI Coder)  
**Step:** 11 — Retrofit Super Bet Multiplier into `SlotMachineLogic.gd` and `SlotMachineUI.gd`.  
**Depends On:** Step 3 complete (`SlotMachineLogic.gd` functional). Step 6 complete (`SlotMachineUI.gd` functional). Step 2 complete (`SaveLoadManager` signals wired).  
**Modified Files:**  
- `res://src/core/SlotMachineLogic.gd` — logic changes only  
- `res://src/ui/SlotMachineUI.gd` — UI changes only  
- `res://src/scenes/Main.tscn` or `res://src/ui/SlotMachinePanel.tscn` — scene node additions

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **SlotMachineLogic.gd:** Zero UI code added. The bet multiplier value is passed in as a parameter — the logic layer never reads UI state directly.
- **SlotMachineUI.gd:** Zero game math added. The UI only reads `SaveLoadManager.spins` to determine which tiers are available. It passes the selected multiplier to `spin_reels()` as a parameter.
- **STRICTLY** use static typing on all new variables and function signatures.
- The `spin_reels(bet_multiplier: int)` signature already exists from Step 3. This step **modifies the internal implementation** of that function. The public signature does not change. No callers break.
- The bet multiplier persists only for the current session. It is **not** saved to `SaveLoadManager`. On game restart, it resets to `x1`.
- All valid multiplier tiers are declared as a typed constant Array in `SlotMachineUI.gd`. They are never hardcoded inline in logic branches.
- Confirm with the completion checklist before closing this step.

---

## SECTION 1: SYSTEM OVERVIEW

### What Changes in `SlotMachineLogic.gd`

The existing `spin_reels(bet_multiplier: int)` function already accepts `bet_multiplier` as a parameter and already multiplies coin rewards. This step extends that function to:

1. Apply `bet_multiplier` to **spin deduction** (already done — verify it is correct).
2. Apply `bet_multiplier` to **shield outcomes** — grants multiple shield units, capped at `SHIELD_MAX_HELD`.
3. Apply `bet_multiplier` to **attack outcomes** — packages multiple attack phases into the result payload.
4. Apply `bet_multiplier` to **raid outcomes** — packages multiple raid dig slots into the result payload.
5. Apply `bet_multiplier` to **spin reward outcomes** — grants multiplied free spins.
6. Emit enriched result Dictionary keys so UI and NPC systems can read multi-phase payloads.

### What Changes in `SlotMachineUI.gd`

1. Add a `BetBtn` node to the scene that cycles through valid multiplier tiers.
2. Add dynamic tier availability logic — tiers requiring more spins than the player has are skipped silently or shown as disabled.
3. Pass the selected multiplier into `spin_reels()` on every spin.
4. React to `SaveLoadManager.spins_changed` signal to re-evaluate tier availability after every spin.
5. Display the current multiplier state clearly in the button label.

---

## SECTION 2: MULTIPLIER TIER DEFINITIONS

### 2.1 Valid Tier Set

Declare this constant in `SlotMachineUI.gd`. It is the single source of truth for all valid multiplier values. The UI iterates this Array when cycling. No other Array of multiplier values may exist in the codebase.

```gdscript
## All valid Super Bet multiplier tiers in ascending order.
## The player cycles through these values with the Bet button.
## Tiers are skipped if SaveLoadManager.spins < tier value.
const BET_TIERS: Array[int] = [1, 2, 3, 5, 10]
```

### 2.2 Minimum Spin Requirement Per Tier

A tier is **available** if and only if `SaveLoadManager.spins >= tier_value`. This is the complete rule. No other condition gates tier availability.

| Tier | Minimum Spins Required | Spins Deducted Per Spin |
|---|---|---|
| x1 | 1 | 1 |
| x2 | 2 | 2 |
| x3 | 3 | 3 |
| x5 | 5 | 5 |
| x10 | 10 | 10 |

The x1 tier is **always available** as long as `spins >= 1`. It can never be disabled. If all higher tiers are unavailable, the UI must remain on x1.

---

## SECTION 3: `SlotMachineLogic.gd` MODIFICATIONS

### 3.1 Reward Scaling Rules Per Reward Type

The following table defines the exact scaling behavior for every `reward_type` when `bet_multiplier > 1`. Implement these rules inside `spin_reels()`.

| `reward_type` | Scaling Rule | Cap / Special Behavior |
|---|---|---|
| `"coins"` | `final_value = base_reward * bet_multiplier` | No cap. Already implemented in Step 3 — verify. |
| `"spins"` | `final_value = base_reward * bet_multiplier` | No cap. Multiply free spin grants. |
| `"shield"` | `final_value = min(base_reward * bet_multiplier, SHIELD_MAX_HELD - SaveLoadManager.shields)` | Hard cap at `SHIELD_MAX_HELD`. Award only what fits. If zero fits, trigger overflow path. |
| `"attack"` | `final_value = base_reward * bet_multiplier` | No cap. Represents number of consecutive attack phases. Emitted in signal payload. |
| `"raid"` | `final_value = base_reward * bet_multiplier` | Represents number of dig slots available in the raid minigame. |

### 3.2 Modified `spin_reels()` — Shield Scaling Update

Locate the existing shield handling block in `spin_reels()`. Replace it with the following logic that correctly handles partial shield awards when the player is near the cap.

**Old behavior (Step 3):** If `shields >= SHIELD_MAX_HELD`, intercept entirely — refund spin + award compensation coins.

**New behavior (Step 11):** Shield overflow interception now uses the scaled value. Calculate how many shields actually fit. If zero fit, run the existing overflow interception path unchanged. If some but not all fit, award only the fitting amount — **no** partial overflow coin compensation for the remainder that did not fit.

```
shields_to_award = min(base_reward * bet_multiplier, SHIELD_MAX_HELD - SaveLoadManager.shields)

If shields_to_award <= 0:
    → Full overflow interception (same as Step 3 logic)
    → Refund bet_multiplier spins
    → Award _shield_overflow_coin_compensation coins
    → was_intercepted = true

If shields_to_award > 0 AND shields_to_award < (base_reward * bet_multiplier):
    → Partial award: call SaveLoadManager.add_shields(shields_to_award)
    → was_intercepted = false (partial fill is NOT an interception)
    → final_reward_value = shields_to_award (report actual awarded amount)

If shields_to_award == (base_reward * bet_multiplier):
    → Full award: call SaveLoadManager.add_shields(shields_to_award)
    → was_intercepted = false
```

### 3.3 Extended Result Dictionary Schema

The result Dictionary returned by `spin_reels()` must include these **additional keys** on top of the schema defined in Step 3. Add them to `_build_failure_dict()` as well with safe defaults.

```
KEY                       TYPE    DEFAULT   DESCRIPTION
──────────────────────────────────────────────────────────────────────────────
"attack_phases"           int     0         Number of consecutive attack phases
                                            the player executes. Equals
                                            final_reward_value when reward_type
                                            is "attack". Zero for all other types.
"raid_dig_slots"          int     0         Number of dig spots in the raid
                                            minigame. Equals final_reward_value
                                            when reward_type is "raid". Zero for
                                            all other types.
"shields_awarded"         int     0         Actual shields granted after cap clamp.
                                            Equals final_reward_value when
                                            reward_type is "shield".
"bet_multiplier_applied"  int     1         Echo of the bet_multiplier parameter.
                                            Redundant with "bet_multiplier" but
                                            explicit for logging clarity.
"event_points_awarded"    int     0         Reserved for EventManager integration
                                            (Step 7). Calculated as
                                            base_event_points * bet_multiplier.
                                            Zero until EventManager is implemented.
```

### 3.4 Full Modified `spin_reels()` Implementation

Write the complete replacement implementation of `spin_reels()`. This replaces the Step 3 version entirely. Preserve all existing guard logic. Only the reward calculation and result construction sections change.

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
        return _build_failure_dict(bet_multiplier,
            "Insufficient spins. Required: %d, Available: %d" % [bet_multiplier, SaveLoadManager.spins])

    # ── Spin Cost Deduction ───────────────────────────────────────────────────
    # Deduct full bet_multiplier spins before outcome selection.
    SaveLoadManager.spend_spins(bet_multiplier)

    # ── Outcome Selection ─────────────────────────────────────────────────────
    var selected_outcome: Dictionary = _resolve_outcome_id()

    var reward_type: String = str(selected_outcome.get("reward_type", "coins"))
    var reward_tier: String = str(selected_outcome.get("reward_tier", "small"))
    var outcome_id: String  = str(selected_outcome.get("id", "coins_small"))
    var base_reward: int    = int(selected_outcome.get("reward_value", 0))

    # ── Per-Type Scaled Reward Calculation ────────────────────────────────────
    var final_reward_value: int  = 0
    var attack_phases: int       = 0
    var raid_dig_slots: int      = 0
    var shields_awarded: int     = 0
    var was_intercepted: bool    = false
    var compensation_coins: int  = 0

    match reward_type:

        "coins":
            final_reward_value = base_reward * bet_multiplier
            SaveLoadManager.add_coins(final_reward_value)

        "spins":
            final_reward_value = base_reward * bet_multiplier
            SaveLoadManager.add_spins(final_reward_value)

        "shield":
            var scaled: int = base_reward * bet_multiplier
            var can_hold: int = SHIELD_MAX_HELD - SaveLoadManager.shields
            var to_award: int = min(scaled, can_hold)

            if to_award <= 0:
                # Full overflow: no room at all. Refund spins + award coin compensation.
                SaveLoadManager.add_spins(bet_multiplier)
                SaveLoadManager.add_coins(_shield_overflow_coin_compensation)
                emit_signal("shield_overflow_intercepted", _shield_overflow_coin_compensation)
                was_intercepted = true
                compensation_coins = _shield_overflow_coin_compensation
                final_reward_value = 0
                shields_awarded = 0
            else:
                # Full or partial award: grant what fits, no compensation for remainder.
                SaveLoadManager.add_shields(to_award)
                final_reward_value = to_award
                shields_awarded = to_award
                was_intercepted = false

        "attack":
            # Each attack phase is one discrete attack execution against an NPC.
            # NPCSimulator reads attack_phases from the result payload.
            final_reward_value = base_reward * bet_multiplier
            attack_phases = final_reward_value
            # No SaveLoadManager mutation — NPC system handles via signal.

        "raid":
            # Each raid_dig_slot is one dig opportunity in the raid minigame.
            final_reward_value = base_reward * bet_multiplier
            raid_dig_slots = final_reward_value
            # No SaveLoadManager mutation — NPC system handles via signal.

        _:
            push_warning("[SlotMachineLogic] Unknown reward_type '%s'. No resource awarded." % reward_type)

    # ── Post-Award Signal Emission ────────────────────────────────────────────
    if reward_type == "raid" and not was_intercepted:
        emit_signal("raid_triggered", final_reward_value)
    if reward_type == "attack" and not was_intercepted:
        emit_signal("attack_triggered", final_reward_value)

    # ── Result Construction ───────────────────────────────────────────────────
    var result: Dictionary = {
        # Core fields (Step 3 schema — unchanged)
        "success":                true,
        "outcome_id":             outcome_id,
        "reward_type":            reward_type,
        "reward_value":           final_reward_value,
        "reward_tier":            reward_tier,
        "bet_multiplier":         bet_multiplier,
        "was_intercepted":        was_intercepted,
        "compensation_coins":     compensation_coins,
        "error_reason":           "",
        "triggers_raid":          reward_type == "raid" and not was_intercepted,
        "triggers_attack":        reward_type == "attack" and not was_intercepted,
        # Extended fields (Step 11 additions)
        "attack_phases":          attack_phases,
        "raid_dig_slots":         raid_dig_slots,
        "shields_awarded":        shields_awarded,
        "bet_multiplier_applied": bet_multiplier,
        "event_points_awarded":   0
    }

    SaveLoadManager.save_game()
    emit_signal("spin_completed", result)

    print("[SlotMachineLogic] Spin resolved. Outcome: %s | Reward: %d %s | Bet: x%d" % [
        outcome_id, final_reward_value, reward_type, bet_multiplier
    ])

    return result
```

### 3.5 Updated `_build_failure_dict()`

Add the five new keys with safe defaults so all result Dictionary consumers never encounter missing keys.

```gdscript
func _build_failure_dict(bet_multiplier: int, reason: String) -> Dictionary:
    return {
        "success":                false,
        "outcome_id":             "",
        "reward_type":            "",
        "reward_value":           0,
        "reward_tier":            "",
        "bet_multiplier":         bet_multiplier,
        "was_intercepted":        false,
        "compensation_coins":     0,
        "error_reason":           reason,
        "triggers_raid":          false,
        "triggers_attack":        false,
        "attack_phases":          0,
        "raid_dig_slots":         0,
        "shields_awarded":        0,
        "bet_multiplier_applied": bet_multiplier,
        "event_points_awarded":   0
    }
```

---

## SECTION 4: `SlotMachineUI.gd` MODIFICATIONS

### 4.1 New Private State Variables

Add these variables to the existing variable block in `SlotMachineUI.gd`.

```gdscript
## Index into BET_TIERS pointing to the currently selected multiplier.
## Default 0 = x1. Resets to 0 on game restart (not persisted).
var _current_tier_index: int = 0

## Cached reference to the Bet multiplier toggle button node.
var _bet_button: Button

## Cached reference to a label showing the active multiplier above the reel area.
## Optional cosmetic display node — warn if not found but do not crash.
var _bet_display_label: Label
```

### 4.2 Scene Node Requirements

The following nodes must exist in `SlotMachinePanel.tscn`. Add them if they do not already exist. Cursor must modify the `.tscn` file directly or instruct the developer to add them via the Godot Editor.

```
SlotMachinePanel (Control — root, has SlotMachineUI.gd)
└── MainFrame (Panel)
    ├── ReelArea (Panel)          ← existing
    ├── ResultLabel (Label)       ← existing
    ├── BetMultiplierLabel (Label)
    │     anchors_preset: TOP_CENTER
    │     offset_top: 10
    │     text: "BET: x1"
    │     font_size: 18
    │     horizontal_alignment: CENTER
    │     modulate: Color(1.0, 0.85, 0.0, 1.0)  ← gold tint
    ├── BetBtn (Button)
    │     anchors_preset: BOTTOM_CENTER
    │     custom_minimum_size: Vector2(120, 36)
    │     offset_bottom: -90  ← positioned above SpinBtn
    │     text: "BET x1"
    └── SpinBtn (Button)          ← existing, offset_bottom unchanged
```

### 4.3 Updated `_ready()` Function

Add the following cache assignments and signal connections inside the existing `_ready()` function, after the existing node caching block.

```gdscript
# ── Cache new bet multiplier nodes ───────────────────────────────────────────
_bet_button = $MainFrame/BetBtn as Button
_bet_display_label = $MainFrame/BetMultiplierLabel as Label

if _bet_button == null:
    push_error("[SlotMachineUI] BetBtn not found. Add BetBtn to SlotMachinePanel.tscn.")
else:
    _bet_button.pressed.connect(_on_bet_button_pressed)

if _bet_display_label == null:
    push_warning("[SlotMachineUI] BetMultiplierLabel not found. Multiplier display disabled.")

# ── Subscribe to spins_changed to re-evaluate tier availability ───────────────
SaveLoadManager.spins_changed.connect(_on_spins_changed)

# ── Set initial bet display ───────────────────────────────────────────────────
_update_bet_button_display()
```

### 4.4 `_on_bet_button_pressed()` — Bet Toggle Handler

**Logic:** Advance `_current_tier_index` to the next **available** tier. Wrap around to index 0 (x1) after the last available tier. A tier is available if `SaveLoadManager.spins >= BET_TIERS[tier_index]`. Because x1 always requires only 1 spin, and the spin guard in `_on_spin_button_pressed()` already prevents spinning with 0 spins, x1 is always reachable.

```gdscript
func _on_bet_button_pressed() -> void:
    # Find the next available tier after the current one, wrapping around.
    var start_index: int = _current_tier_index
    var next_index: int = (start_index + 1) % BET_TIERS.size()

    # Iterate up to BET_TIERS.size() steps to find next available tier.
    # This prevents infinite loop if (hypothetically) all tiers were unavailable.
    var steps: int = 0
    while steps < BET_TIERS.size():
        if _is_tier_available(next_index):
            _current_tier_index = next_index
            break
        next_index = (next_index + 1) % BET_TIERS.size()
        steps += 1

    # If no higher tier is available, cycle back to x1 (index 0).
    if steps >= BET_TIERS.size():
        _current_tier_index = 0

    _update_bet_button_display()
    print("[SlotMachineUI] Bet tier changed to x%d." % BET_TIERS[_current_tier_index])
```

### 4.5 `_is_tier_available(tier_index: int) -> bool`

```gdscript
func _is_tier_available(tier_index: int) -> bool:
    if tier_index < 0 or tier_index >= BET_TIERS.size():
        return false
    return SaveLoadManager.spins >= BET_TIERS[tier_index]
```

### 4.6 `_update_bet_button_display()` — Visual State Updater

Updates the button label and color to reflect the current tier. Also validates that the current tier is still affordable after a spin — if not, auto-downgrades to the highest available tier.

```gdscript
func _update_bet_button_display() -> void:
    # Auto-downgrade if current tier is no longer affordable.
    if not _is_tier_available(_current_tier_index):
        _auto_downgrade_tier()

    var active_multiplier: int = BET_TIERS[_current_tier_index]

    if _bet_button != null:
        _bet_button.text = "BET x%d" % active_multiplier

        # Color tier feedback: x1 = white, x2/x3 = yellow, x5 = orange, x10 = red.
        var tier_color: Color
        match active_multiplier:
            1:
                tier_color = Color(1.0, 1.0, 1.0)
            2, 3:
                tier_color = Color(1.0, 0.9, 0.2)
            5:
                tier_color = Color(1.0, 0.6, 0.1)
            10:
                tier_color = Color(1.0, 0.2, 0.2)
            _:
                tier_color = Color(1.0, 1.0, 1.0)

        _bet_button.add_theme_color_override("font_color", tier_color)

    if _bet_display_label != null:
        _bet_display_label.text = "BET: x%d" % active_multiplier
        _bet_display_label.add_theme_color_override("font_color",
            Color(1.0, 0.85, 0.0) if active_multiplier > 1 else Color(1.0, 1.0, 1.0))
```

### 4.7 `_auto_downgrade_tier()` — Tier Downgrade on Insufficient Spins

Called when the currently selected tier becomes unavailable after a spin. Scans downward from the current index to find the highest still-available tier. Always finds x1 as the final fallback.

```gdscript
func _auto_downgrade_tier() -> void:
    var original_tier: int = BET_TIERS[_current_tier_index]

    # Scan from current index downward to 0.
    for i in range(_current_tier_index, -1, -1):
        if _is_tier_available(i):
            if i != _current_tier_index:
                print("[SlotMachineUI] Bet auto-downgraded from x%d to x%d (insufficient spins)." % [
                    original_tier, BET_TIERS[i]
                ])
            _current_tier_index = i
            return

    # Fallback — always land on x1.
    _current_tier_index = 0
```

### 4.8 `_on_spins_changed(new_spin_count: int)` — Reactive Spin Balance Handler

Connected to `SaveLoadManager.spins_changed`. Called after every spin deduction and every spin award. Re-evaluates display state so the bet button always reflects current affordability without requiring a frame poll.

```gdscript
func _on_spins_changed(_new_spin_count: int) -> void:
    _update_bet_button_display()
    _update_button_state()
```

### 4.9 Updated `_on_spin_button_pressed()` — Pass Multiplier to Logic

Locate the existing `_on_spin_button_pressed()` from Step 6. Change the `spin_reels()` call to pass the active multiplier from `BET_TIERS[_current_tier_index]`.

**Change this line:**
```gdscript
var _unused_result: Dictionary = slot_logic.spin_reels(1)
```

**To this:**
```gdscript
var active_multiplier: int = BET_TIERS[_current_tier_index]
var _unused_result: Dictionary = slot_logic.spin_reels(active_multiplier)
```

Also update the `can_spin()` check to use the active multiplier:

**Change:**
```gdscript
if not slot_logic.can_spin(1):
```

**To:**
```gdscript
var active_multiplier: int = BET_TIERS[_current_tier_index]
if not slot_logic.can_spin(active_multiplier):
```

### 4.10 Updated `_on_spin_completed()` — Display Multi-Phase Results

Locate the existing `_on_spin_completed()` handler. Extend the `match reward_type` display string block to include multi-phase information from the new result keys.

```gdscript
func _on_spin_completed(result: Dictionary) -> void:
    if not _is_spinning:
        return

    var reward_type: String    = str(result.get("reward_type", ""))
    var reward_value: int      = int(result.get("reward_value", 0))
    var was_intercepted: bool  = bool(result.get("was_intercepted", false))
    var attack_phases: int     = int(result.get("attack_phases", 0))
    var raid_dig_slots: int    = int(result.get("raid_dig_slots", 0))
    var bet_applied: int       = int(result.get("bet_multiplier_applied", 1))

    var display_text: String
    match reward_type:
        "coins":
            display_text = "+%d Coins!" % reward_value
            if bet_applied > 1:
                display_text += " (x%d BET)" % bet_applied
        "spins":
            display_text = "+%d Free Spins!" % reward_value
        "shield":
            if was_intercepted:
                display_text = "Shields Full! +%d Coins" % int(result.get("compensation_coins", 0))
            else:
                display_text = "+%d Shield%s!" % [reward_value, "s" if reward_value > 1 else ""]
        "raid":
            display_text = "RAID! %d Dig Slot%s!" % [raid_dig_slots, "s" if raid_dig_slots > 1 else ""]
        "attack":
            display_text = "ATTACK! x%d Phase%s!" % [attack_phases, "s" if attack_phases > 1 else ""]
        _:
            display_text = "Spin Complete!"

    _result_label.text = display_text
    _play_reveal_animation(result)

    await get_tree().create_timer(REEL_SPIN_DURATION + REVEAL_DURATION).timeout
    _finalize_spin_complete()
```

### 4.11 Updated `_update_button_state()` — Use Active Multiplier

```gdscript
func _update_button_state() -> void:
    var slot_logic: SlotMachineLogic = _find_slot_logic()
    var active_multiplier: int = BET_TIERS[_current_tier_index]
    if slot_logic != null and slot_logic.can_spin(active_multiplier):
        _spin_button.disabled = false
    else:
        _spin_button.disabled = true
```

---

## SECTION 5: NPCSimulator INTEGRATION FOR MULTI-PHASE ATTACKS

`NPCSimulator.on_live_attack_triggered(attack_count: int)` already accepts `attack_count`. Since `SlotMachineLogic` now emits `attack_triggered(final_reward_value)` where `final_reward_value = base_reward * bet_multiplier`, the NPC simulator already receives the correct multi-phase count via the signal payload. **No changes are required to `NPCSimulator.gd`** for attack phase scaling to work.

For raid dig slots: `SlotMachineLogic` emits `raid_triggered(final_reward_value)` where `final_reward_value = base_reward * bet_multiplier`. The raid dig slot count is available in the result Dictionary as `"raid_dig_slots"`. The Raid UI minigame (future step) reads this from the result Dictionary — `NPCSimulator.generate_raid_target()` does not need modification.

---

## SECTION 6: EVENT MANAGER INTEGRATION STUB

`"event_points_awarded"` is included in the result Dictionary with value `0` until the EventManager (Step 7) is fully wired. When Step 7 is implemented, EventManager connects to `spin_completed` and reads `"event_points_awarded"` = `base_event_points * bet_multiplier`. The formula is applied inside EventManager's `_on_spin_completed()` handler — **not** inside `SlotMachineLogic`. This preserves separation of concerns.

The stub line in `spin_reels()` that currently sets `"event_points_awarded": 0` must remain as-is. EventManager will override its own counter independently.

---

## SECTION 7: EDGE CASE REGISTRY

| Edge Case | Trigger | Handling |
|---|---|---|
| **Spin balance drops mid-session below active tier** | Player spins at x10, balance goes from 10 to 0 | `spins_changed` signal triggers `_update_bet_button_display()` → `_auto_downgrade_tier()` → lands on x1. Spin button disabled (0 spins). |
| **Player tries to activate x10 with 9 spins** | Button press cycles past x10 | `_is_tier_available()` returns false for index 4. Loop skips it. Next available tier is selected. |
| **All tiers unavailable (0 spins)** | Balance hits zero | `_auto_downgrade_tier()` always finds x1 at index 0. x1 requires `spins >= 1`. With 0 spins, `_is_tier_available(0)` is false BUT `_update_button_state()` disables SpinBtn. BetBtn remains showing x1 but SpinBtn is disabled. No spin can be initiated. |
| **bet_multiplier passed as 0 from UI bug** | Logic defensive check | `spin_reels()` clamps to 1, logs warning. Never crashes. |
| **Shield x10 bet, player has 3 shields, cap is 5** | `to_award = min(10, 5-3) = 2` | Awards 2 shields. No overflow interception. No coin compensation for the 8 that did not fit. `shields_awarded = 2` in result. |
| **Shield x10 bet, player already at max 5** | `to_award = min(10, 0) = 0` | Full overflow interception. Spins refunded. Compensation coins awarded. `was_intercepted = true`. |
| **Attack x10 generates 10 attack phases** | `attack_phases = 10` | Emitted in signal. NPCSimulator loop runs 10 iterations. Each generates one NPC attack result. Performance: 10 Dictionary allocations per signal — acceptable. |
| **Raid x10 generates 10 dig slots** | `raid_dig_slots = 10` | Stored in result. Raid UI minigame (future) caps display at available dig spots. Logic does not cap. |
| **Session multiplier persists after game reload** | App closed mid-session with x5 active | `_current_tier_index` is not persisted. Resets to 0 (x1) on next `_ready()` call. Intentional — avoids confusing the player. |
| **BET_TIERS constant modified by future developer** | A new tier like x25 is added | All logic iterates `BET_TIERS` dynamically. Color match block in `_update_bet_button_display()` falls through to default white for undefined tiers. Functional but unstyled — add a color entry when adding a tier. |

---

## SECTION 8: UNIT TEST VERIFICATION PROTOCOL

### Test A: Tier Availability Gating
1. Set `SaveLoadManager.spins = 4`.
2. Click BetBtn repeatedly.
3. **Expected:** Cycles through x1, x2, x3 only. x5 and x10 are never reached.
4. **Expected:** BetBtn label never shows "BET x5" or "BET x10".

### Test B: Auto-Downgrade on Spin Depletion
1. Set `SaveLoadManager.spins = 10`. Select x10 tier.
2. Spin once (spins become 0 assuming no spin reward).
3. **Expected:** After spin, `_current_tier_index` resets to 0 (x1). BetBtn shows "BET x1". SpinBtn is disabled.

### Test C: Coin Reward Scaling
1. Set `forced_outcome_id = "coins_medium"` (`reward_value = 200`). Set `bet_multiplier` to x5.
2. Set `SaveLoadManager.coins = 0`, `spins = 10`.
3. Spin.
4. **Expected:** `SaveLoadManager.coins == 1000` (200 × 5).
5. **Expected:** `SaveLoadManager.spins == 5` (10 - 5).
6. **Expected:** Result `"bet_multiplier_applied" == 5`.

### Test D: Spin Reward Scaling
1. Set `forced_outcome_id = "spins_single"` (`reward_value = 1`). Set `bet_multiplier` to x3.
2. Set `SaveLoadManager.spins = 5`.
3. Spin.
4. **Expected:** `SaveLoadManager.spins == 5` (5 - 3 + (1 × 3)).

### Test E: Shield Partial Fill
1. Set `SaveLoadManager.shields = 4`. `SHIELD_MAX_HELD = 5`.
2. Set `forced_outcome_id = "shield_single"` (`reward_value = 1`). Set `bet_multiplier` to x5.
3. Spin.
4. **Expected:** `shields_to_award = min(1*5, 5-4) = min(5, 1) = 1`. `SaveLoadManager.shields == 5`.
5. **Expected:** `result["shields_awarded"] == 1`. `result["was_intercepted"] == false`.
6. **Expected:** No overflow compensation coins awarded.

### Test F: Shield Full Overflow with Multiplier
1. Set `SaveLoadManager.shields = 5`. Set `bet_multiplier` to x3. Set `spins = 10`.
2. Force `shield_single` outcome.
3. **Expected:** `to_award = min(3, 0) = 0`. Full overflow interception.
4. **Expected:** `SaveLoadManager.spins` returns to `10` (deducted then refunded).
5. **Expected:** `SaveLoadManager.shields` remains `5`.
6. **Expected:** `result["was_intercepted"] == true`.

### Test G: Attack Phase Count
1. Set `forced_outcome_id = "attack_single"` (`reward_value = 1`). Set `bet_multiplier` to x5.
2. Spin.
3. **Expected:** `result["attack_phases"] == 5`.
4. **Expected:** `attack_triggered` signal fires with value `5`.
5. **Expected:** NPCSimulator `on_live_attack_triggered(5)` generates 5 NPC attack entries.

### Test H: Raid Dig Slot Count
1. Set `forced_outcome_id = "raid_single"` (`reward_value = 1`). Set `bet_multiplier` to x3.
2. Spin.
3. **Expected:** `result["raid_dig_slots"] == 3`.
4. **Expected:** `raid_triggered` signal fires with value `3`.

### Test I: BetBtn Color Feedback
1. Cycle through all available tiers.
2. **Expected:** x1 → white label. x2/x3 → yellow. x5 → orange. x10 → red.
3. **Expected:** `BetMultiplierLabel` text matches active tier at all times.

### Test J: Failure Dict Completeness
1. Set `SaveLoadManager.spins = 0`. Attempt `spin_reels(1)`.
2. **Expected:** Returned Dictionary contains ALL keys including the 5 new Step 11 keys with value `0` or `1`.
3. **Expected:** No KeyError when UI reads `result["attack_phases"]` or `result["raid_dig_slots"]`.

---

## SECTION 9: COMPLETION CHECKLIST

Before closing Step 11, Cursor must confirm ALL of the following:

- [ ] `BET_TIERS: Array[int] = [1, 2, 3, 5, 10]` constant declared in `SlotMachineUI.gd`
- [ ] `_current_tier_index` initializes to `0` and is never saved to `SaveLoadManager`
- [ ] `_on_bet_button_pressed()` skips unavailable tiers and wraps to x1 when none are available above
- [ ] `_auto_downgrade_tier()` is called inside `_update_bet_button_display()` — never skipped
- [ ] `SaveLoadManager.spins_changed` is connected to `_on_spins_changed()` in `_ready()`
- [ ] `_on_spin_button_pressed()` passes `BET_TIERS[_current_tier_index]` to `spin_reels()`
- [ ] `_update_button_state()` checks `can_spin(active_multiplier)` not `can_spin(1)`
- [ ] `spin_reels()` deducts `bet_multiplier` spins (already true from Step 3 — verified)
- [ ] Coin rewards multiplied by `bet_multiplier` (already true from Step 3 — verified)
- [ ] Spin rewards multiplied by `bet_multiplier` (new in Step 11)
- [ ] Shield partial fill logic implemented: `to_award = min(scaled, SHIELD_MAX_HELD - shields)`
- [ ] Shield full overflow (to_award == 0) still refunds `bet_multiplier` spins and awards compensation coins
- [ ] Shield partial fill does NOT award compensation coins for unfilled remainder
- [ ] `attack_phases = base_reward * bet_multiplier` stored in result and emitted via `attack_triggered`
- [ ] `raid_dig_slots = base_reward * bet_multiplier` stored in result and emitted via `raid_triggered`
- [ ] `_build_failure_dict()` includes all 5 new keys with safe defaults
- [ ] `_on_spin_completed()` UI handler reads `attack_phases` and `raid_dig_slots` from result for display
- [ ] `BetMultiplierLabel` node exists in `SlotMachinePanel.tscn`
- [ ] `BetBtn` node exists in `SlotMachinePanel.tscn` positioned above `SpinBtn`
- [ ] Color override applied to BetBtn per tier: white/yellow/orange/red
- [ ] Zero math logic added to `SlotMachineUI.gd` beyond tier availability check
- [ ] Zero UI node references added to `SlotMachineLogic.gd`
- [ ] All new variables and functions use static typing
```