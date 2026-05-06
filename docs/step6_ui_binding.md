# step6_ui_binding.md

## Technical Specification: UI Binding Layer — MainHUD & SlotMachineUI
**Target Engine:** Godot 4.x
**Execution Agent:** Cursor (AI Coder)
**Step:** 6 of 10 — Implement `MainHUD.gd` and `SlotMachineUI.gd` as the pure View layer.
**Depends On:** Step 3 complete (`SlotMachineLogic` signals defined). Step 2 complete (`SaveLoadManager` autoload and signals available). Step 5 complete (`NPCSimulator` connected in main scene).
**Output Files:**
- `res://src/ui/MainHUD.gd`
- `res://src/ui/SlotMachineUI.gd`
- `res://src/ui/SlotMachinePanel.tscn`
- `res://src/scenes/Main.tscn` (updated)

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **ZERO GAME MATH CODE.** No `RandomNumberGenerator`, no probability calculations, no outcome resolution. `SlotMachineUI` calls `SlotMachineLogic.spin_reels()` only — it never decides the spin result. All math lives in `SlotMachineLogic`.
- **ZERO direct resource queries in Update loops.** Do NOT poll `SaveLoadManager.coins` inside `_process()` or `_physics_process()`. Counter labels update ONLY via signal subscriptions.
- **SPIN BUTTON MUST LOCK DURING ANIMATION.** The button's `disabled` state is the source of truth for input availability. It is set to `true` the instant a spin starts and set to `false` only when the Tween finishes.
- **NO Tween interpolates game state.** Tweens animate only visual properties (`position`, `modulate`, `scale`, `rotation`). The spin outcome is already decided by `SlotMachineLogic.spin_reels()` before any animation begins.
- **STRICTLY** use static typing on every variable and function signature.
- **All UI scripts are pure signal consumers.** They do not call `SaveLoadManager` mutators, do not call `VillageManager` methods, and do not write to any shared state.
- `MainHUD` and `SlotMachineUI` are **NOT** Autoloads. They are attached to nodes inside `Main.tscn`.
- Confirm with the completion checklist before proceeding to Step 7.

---

## SECTION 1: ARCHITECTURAL ROLE

### 1.1 The View–Model Separation

The game is built on a strict two-layer model:

```
┌─────────────────────────────────────────────────────────┐
│                    MODEL LAYER                          │
│  SaveLoadManager  SlotMachineLogic  VillageManager       │
│  NPCSimulator                                          │
│  — Pure data and logic. No visual code.                 │
│  — Emits typed signals carrying data payloads.          │
└──────────────────────┬──────────────────────────────────┘
                       │ signals (only channel)
┌──────────────────────▼──────────────────────────────────┐
│                    VIEW LAYER                           │
│  MainHUD.gd        SlotMachineUI.gd                     │
│  — Subscribes to Model signals.                        │
│  — Updates Control node properties (labels, buttons).  │
│  — Runs Tween animations.                              │
│  — Calls Model entry points (spin_reels()).            │
│  — Contains ZERO game math.                            │
└─────────────────────────────────────────────────────────┘
```

`MainHUD.gd` owns the persistent HUD elements (coin counter, spin counter, shield counter).

`SlotMachineUI.gd` owns the slot machine interaction: spin button, reel visuals, and the outcome reveal animation.

### 1.2 Data Flow

**Signal subscription flow (HUD):**

```
SaveLoadManager.coins_changed(new_value)
       │
       ▼
MainHUD._on_coins_changed(new_value)
       │
       └──▶ $CoinLabel.text = "%,d" % new_value

SaveLoadManager.spins_changed(new_value)
       │
       ▼
MainHUD._on_spins_changed(new_value)
       │
       └──▶ $SpinLabel.text = "%,d" % new_value

SaveLoadManager.shields_changed(new_value)
       │
       ▼
MainHUD._on_shields_changed(new_value)
       │
       └──▶ $ShieldLabel.text = "%d/5" % new_value
```

**Spin interaction flow:**

```
Player presses Spin button
       │
       ▼
SlotMachineUI._on_spin_button_pressed()
       │
       ├──▶ Disable Spin button (button.disabled = true)
       │
       ▼
SlotMachineLogic.spin_reels(1)
       │  (math happens here — outcome already decided)
       │
       ▼
spin_completed signal fires (carrying result Dictionary)
       │
       ▼
SlotMachineUI._on_spin_completed(result)
       │
       ├──▶ Play outcome Tween animation
       │
       ▼
Tween completes
       │
       ├──▶ Update result label with outcome text
       ├──▶ Re-enable Spin button (button.disabled = false)
       └──▶ Print: "[SlotMachineUI] Outcome displayed. Button unlocked."
```

**Raid/Attack overlay flow:**

```
SlotMachineLogic.raid_triggered(raid_count)
       │
       ▼
SlotMachineUI._on_raid_triggered(raid_count)
       │
       └──▶ Show "Raid!" indicator / overlay (cosmetic only)

SlotMachineLogic.attack_triggered(attack_count)
       │
       ▼
SlotMachineUI._on_attack_triggered(attack_count)
       │
       └──▶ Show "Attack!" indicator / overlay (cosmetic only)
```

### 1.3 Interaction Contract

| System | Role | Interaction |
|---|---|---|
| `SaveLoadManager` | Model — emits resource signals | `MainHUD` subscribes: `coins_changed`, `spins_changed`, `shields_changed` |
| `SlotMachineLogic` | Model — spin math engine | `SlotMachineUI` calls `spin_reels()`. `SlotMachineUI` subscribes: `spin_completed`, `spin_failed_insufficient_spins`, `raid_triggered`, `attack_triggered`, `shield_overflow_intercepted` |
| `SlotMachineUI` | View — slot machine visuals | Calls `SlotMachineLogic.spin_reels()`. Emits no signals. |
| `MainHUD` | View — HUD counters | Subscribes to SaveLoadManager signals. Emits no signals. |
| `Main.gd` | Scene orchestrator | Wires all connections in `_ready()`. Instantiates UI nodes. |

---

## SECTION 2: DIRECTORY STRUCTURE

### 2.1 Files to CREATE

```
res://src/
├── ui/
│   ├── MainHUD.gd              ← NEW
│   ├── SlotMachineUI.gd       ← NEW
│   └── SlotMachinePanel.tscn  ← NEW (packed scene)
└── scenes/
    └── Main.tscn              ← UPDATE (add nodes)
```

### 2.2 Files to MODIFY

| File | Changes |
|---|---|
| `res://src/core/Main.gd` | Import both UI scripts. Instantiate `SlotMachinePanel.tscn`. Subscribe to all required signals. Wire the full connection graph. |

---

## SECTION 3: MAIN HUD — `MainHUD.gd`

### 3.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# MainHUD.gd
# Path: res://src/ui/MainHUD.gd
# Role: Persistent top-screen resource counters. Pure View — zero game logic.
# Access pattern: Attached to a CanvasLayer/HBoxContainer node in Main.tscn.
# Signals: Subscribes to SaveLoadManager signals. Emits no signals.
# ==============================================================================
extends Control
class_name MainHUD
```

### 3.2 Node Path Requirements

The following node paths are relative to the node this script is attached to. The script assumes the following child hierarchy exists in the scene tree:

```
MainHUD (Control node — script attached here)
├── CoinPanel (HBoxContainer)
│   └── CoinLabel (Label)
├── SpinPanel (HBoxContainer)
│   └── SpinLabel (Label)
└── ShieldPanel (HBoxContainer)
    └── ShieldLabel (Label)
```

**In `SlotMachinePanel.tscn`** (separate scene):

```
SlotMachinePanel (Control node)
├── SpinButton (Button)
├── ResultLabel (Label)
├── Reel1 (ColorRect or Sprite2D)
├── Reel2 (ColorRect or Sprite2D)
└── Reel3 (ColorRect or Sprite2D)
```

### 3.3 Variables

```gdscript
## Cached references to label nodes. Initialized in _ready().
var _coin_label: Label
var _spin_label: Label
var _shield_label: Label
```

### 3.4 `_ready()` Function

```gdscript
func _ready() -> void:
    # Cache node references.
    _coin_label  = $CoinPanel/CoinLabel  as Label
    _spin_label  = $SpinPanel/SpinLabel  as Label
    _shield_label = $ShieldPanel/ShieldLabel as Label

    # Handle missing nodes gracefully.
    if _coin_label == null:
        push_warning("[MainHUD] CoinLabel not found at $CoinPanel/CoinLabel.")
    if _spin_label == null:
        push_warning("[MainHUD] SpinLabel not found at $SpinPanel/SpinLabel.")
    if _shield_label == null:
        push_warning("[MainHUD] ShieldLabel not found at $ShieldPanel/ShieldLabel.")

    # Subscribe to SaveLoadManager signals.
    SaveLoadManager.coins_changed.connect(_on_coins_changed)
    SaveLoadManager.spins_changed.connect(_on_spins_changed)
    SaveLoadManager.shields_changed.connect(_on_shields_changed)

    # Initialize labels with current values immediately (avoids 1-frame delay).
    _update_coin_label(SaveLoadManager.coins)
    _update_spin_label(SaveLoadManager.spins)
    _update_shield_label(SaveLoadManager.shields)

    print("[MainHUD] Initialized. Coins: %d | Spins: %d | Shields: %d" % [
        SaveLoadManager.coins, SaveLoadManager.spins, SaveLoadManager.shields
    ])
```

### 3.5 Signal Callbacks

Each callback receives the new value from the signal payload and delegates to a private update helper.

```gdscript
func _on_coins_changed(new_value: int) -> void:
    _update_coin_label(new_value)


func _on_spins_changed(new_value: int) -> void:
    _update_spin_label(new_value)


func _on_shields_changed(new_value: int) -> void:
    _update_shield_label(new_value)
```

### 3.6 Label Update Helpers

These are private functions that set the `text` property of each label. All formatting uses `%,d` for comma-separated integers.

```gdscript
func _update_coin_label(value: int) -> void:
    if _coin_label != null:
        _coin_label.text = "%,d" % value


func _update_spin_label(value: int) -> void:
    if _spin_label != null:
        _spin_label.text = "%,d" % value


func _update_shield_label(value: int) -> void:
    if _shield_label != null:
        _shield_label.text = "%d/5" % value
```

**Key formatting rules:**
- Coins: formatted as `%,d` (e.g., `1,234,567`). Uses GDScript's built-in integer formatting.
- Spins: same `%,d` format.
- Shields: `%d/5` format (e.g., `3/5`). Note: this is cosmetic only — actual shield cap is `5` from the Model layer.

---

## SECTION 4: SLOT MACHINE UI — `SlotMachineUI.gd`

### 4.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# SlotMachineUI.gd
# Path: res://src/ui/SlotMachineUI.gd
# Role: Slot machine interaction and reel animation. Pure View — zero game math.
# Access pattern: Attached to SlotMachinePanel root node in SlotMachinePanel.tscn.
# Signals: Subscribes to SlotMachineLogic signals. Emits no signals.
# ==============================================================================
extends Control
class_name SlotMachineUI
```

### 4.2 Constants

```gdscript
## Duration of the reel spin animation in seconds.
## The reels "spin" (visually cycle) for this duration before stopping.
const REEL_SPIN_DURATION: float = 1.5

## Duration of the outcome reveal animation in seconds.
## After reels stop, a brief scale/fade pop plays to signal the result.
const REVEAL_DURATION: float = 0.4

## Total animation duration = REEL_SPIN_DURATION + REVEAL_DURATION.
## Spin button remains locked for this entire period.
```

### 4.3 Variables

```gdscript
## Cached reference to the spin button. Initialized in _ready().
var _spin_button: Button

## Cached references to the three reel visual nodes.
## These are ColorRect or Sprite2D nodes that get their position animated.
var _reel1: CanvasItem
var _reel2: CanvasItem
var _reel3: CanvasItem

## Cached reference to the result display label.
var _result_label: Label

## Tracks whether a spin animation is currently in progress.
## Used to prevent spin-spam: ignore button presses while this is true.
var _is_spinning: bool = false
```

### 4.4 `_ready()` Function

```gdscript
func _ready() -> void:
    # ── Cache node references ────────────────────────────────────────────────
    _spin_button  = $SpinButton  as Button
    _reel1       = $Reel1       as CanvasItem
    _reel2       = $Reel2       as CanvasItem
    _reel3       = $Reel3       as CanvasItem
    _result_label = $ResultLabel as Label

    # Handle missing nodes.
    if _spin_button == null:
        push_error("[SlotMachineUI] SpinButton not found at $SpinButton.")
        return
    if _reel1 == null or _reel2 == null or _reel3 == null:
        push_error("[SlotMachineUI] One or more reel nodes not found.")
        return
    if _result_label == null:
        push_warning("[SlotMachineUI] ResultLabel not found at $ResultLabel.")

    # ── Initialize visual state ─────────────────────────────────────────────
    _result_label.text = "Spin to play!"
    _result_label.modulate = Color.WHITE

    # Set initial reel visual positions (stopped state).
    # The actual stop positions are cosmetic — the math is in SlotMachineLogic.
    _reel1.position = Vector2(0, 0)
    _reel2.position = Vector2(0, 0)
    _reel3.position = Vector2(0, 0)

    # ── Wire button press ────────────────────────────────────────────────────
    _spin_button.pressed.connect(_on_spin_button_pressed)

    # ── Subscribe to SlotMachineLogic signals ──────────────────────────────
    # slot_machine_logic is a direct child node reference.
    # The parent scene (Main.gd) ensures this node exists before _ready runs.
    var slot_logic: SlotMachineLogic = $"/root".get_node_or_null("Main/SlotMachineLogic") as SlotMachineLogic
    if slot_logic == null:
        # Fallback: search by path in scene tree
        slot_logic = get_node_or_null("../SlotMachineLogic") as SlotMachineLogic

    if slot_logic != null:
        slot_logic.spin_completed.connect(_on_spin_completed)
        slot_logic.spin_failed_insufficient_spins.connect(_on_spin_failed)
        slot_logic.raid_triggered.connect(_on_raid_triggered)
        slot_logic.attack_triggered.connect(_on_attack_triggered)
        slot_logic.shield_overflow_intercepted.connect(_on_shield_overflow)
        print("[SlotMachineUI] Connected to SlotMachineLogic signals.")
    else:
        push_error("[SlotMachineUI] SlotMachineLogic node not found. Cannot connect signals.")

    # ── Initial button state ────────────────────────────────────────────────
    # Enable button only if player has at least 1 spin.
    _update_button_state()
    print("[SlotMachineUI] Initialized.")
```

### 4.5 `_on_spin_button_pressed()` — Input Entry Point

**CRITICAL: This function is the ONLY entry point for initiating a spin. All other code paths must go through this function.**

```gdscript
func _on_spin_button_pressed() -> void:
    # ── Spam guard ─────────────────────────────────────────────────────────
    if _is_spinning:
        print("[SlotMachineUI] Spin ignored — animation in progress.")
        return

    # ── Sanity check: is SlotMachineLogic available? ───────────────────────
    var slot_logic: SlotMachineLogic = _find_slot_logic()
    if slot_logic == null:
        push_error("[SlotMachineUI] SlotMachineLogic not available.")
        return

    # ── Check if player can spin ─────────────────────────────────────────────
    if not slot_logic.can_spin(1):
        # Disable button visually and exit.
        _spin_button.disabled = true
        _result_label.text = "Not enough spins!"
        print("[SlotMachineUI] Spin blocked — insufficient spins.")
        return

    # ── LOCK INPUT ──────────────────────────────────────────────────────────
    _is_spinning = true
    _spin_button.disabled = true
    _result_label.text = "..."
    print("[SlotMachineUI] Spin initiated. Button locked.")

    # ── START VISUAL ANIMATION (runs in parallel with math) ──────────────────
    _play_spin_animation()

    # ── CALL MODEL — outcome is already decided before signal fires ──────────
    var result: Dictionary = slot_logic.spin_reels(1)
    # Result is returned synchronously. Signal will fire next.
    # _on_spin_completed handles the post-math display.
    # The animation and signal are decoupled — animation started above,
    # signal handling happens in _on_spin_completed.
```

### 4.6 `_play_spin_animation()` — Visual Reel Spin

Uses Godot's built-in `Tween` node (created programmatically, not from scene).

The animation simulates reels spinning by rapidly cycling their visual position. Since there are no actual sprite textures in this spec, the reels are represented by `ColorRect` nodes that slide vertically in a loop.

```gdscript
func _play_spin_animation() -> void:
    # Create a new Tween node. It will clean itself up after completing.
    var tween: Tween = create_tween()
    tween.set_parallel(true)

    # ── Reel 1: vertical oscillation loop ──────────────────────────────────
    # The reel visually "spins" by moving up and down repeatedly.
    # We use Tween's LOOP mode for continuous oscillation.
    var reel_y_offset: float = 60.0  # pixels of vertical travel

    tween.tween_property(_reel1, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.33) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(_reel1, "position:y", 0.0, REEL_SPIN_DURATION * 0.33) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(_reel1, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.34) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

    # ── Reel 2: phase-offset oscillation (slightly behind reel 1) ───────────
    tween.tween_property(_reel2, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.28) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(_reel2, "position:y", 0.0, REEL_SPIN_DURATION * 0.36) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(_reel2, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.36) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

    # ── Reel 3: different speed to look more chaotic ────────────────────────
    tween.tween_property(_reel3, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.40) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(_reel3, "position:y", 0.0, REEL_SPIN_DURATION * 0.30) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(_reel3, "position:y", reel_y_offset, REEL_SPIN_DURATION * 0.30) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

    # ── Result label pulses while spinning ──────────────────────────────────
    var pulse_tween: Tween = create_tween()
    pulse_tween.set_parallel(true)
    pulse_tween.tween_property(_result_label, "modulate:a", 0.4, REEL_SPIN_DURATION * 0.5)
    pulse_tween.tween_property(_result_label, "modulate:a", 1.0, REEL_SPIN_DURATION * 0.5)

    # Note: we do NOT await the tween here. The animation runs independently.
    # The signal handler (_on_spin_completed) will finalize the state.
    print("[SlotMachineUI] Spin animation started. Duration: %.1fs." % REEL_SPIN_DURATION)
```

### 4.7 `_on_spin_completed(result: Dictionary)` — Outcome Reveal

This is the most critical function. It runs after `SlotMachineLogic.spin_reels()` has already resolved the outcome. Its only job is to display the result visually.

```gdscript
func _on_spin_completed(result: Dictionary) -> void:
    # Guard: ignore if called while not spinning (should not happen but be safe).
    if not _is_spinning:
        print("[SlotMachineUI] spin_completed received but _is_spinning is false. Ignoring.")
        return

    var reward_type:  String = str(result.get("reward_type", ""))
    var reward_value:  int    = int(result.get("reward_value", 0))
    var reward_tier:  String = str(result.get("reward_tier", "small"))
    var outcome_id:   String = str(result.get("outcome_id", ""))
    var was_intercepted: bool = bool(result.get("was_intercepted", false))

    # ── Determine display text based on reward type ─────────────────────────
    var display_text: String
    match reward_type:
        "coins":
            display_text = "+%,d Coins!" % reward_value
        "spins":
            display_text = "+%d Free Spins!" % reward_value
        "shield":
            display_text = "+%d Shield!" % reward_value
        "raid":
            display_text = "Raid! %d spots!" % reward_value
        "attack":
            display_text = "Attack! %d targets!" % reward_value
        _:
            display_text = "Spin Complete!"

    if was_intercepted:
        var comp: int = int(result.get("compensation_coins", 0))
        display_text = "Shields Full! +%,d Coins" % comp

    _result_label.text = display_text

    # ── Play reveal animation ────────────────────────────────────────────────
    _play_reveal_animation(reward_tier)

    # ── Unlock input after full animation duration ───────────────────────────
    # The button must remain disabled for the full REVEAL_DURATION
    # after the outcome is known.
    await get_tree().create_timer(REEL_SPIN_DURATION + REVEAL_DURATION).timeout
    _finalize_spin_complete()


func _finalize_spin_complete() -> void:
    # Re-enable the spin button.
    _is_spinning = false
    _update_button_state()
    print("[SlotMachineUI] Outcome displayed. Button unlocked.")
```

### 4.8 `_play_reveal_animation(reward_tier: String)` — Outcome Pop

Plays a scale-and-color pop to highlight the outcome tier.

```gdscript
func _play_reveal_animation(tier: String) -> void:
    # Determine color based on tier.
    var target_color: Color = Color.WHITE
    match tier:
        "large", "jackpot":
            target_color = Color.GOLD
        "medium":
            target_color = Color.SILVER
        _:
            target_color = Color.WHITE

    # Scale pop: scale up to 1.2x then back to 1.0x.
    var tween: Tween = create_tween()
    tween.tween_property(_result_label, "scale", Vector2(1.2, 1.2), REVEAL_DURATION * 0.4) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.tween_property(_result_label, "scale", Vector2(1.0, 1.0), REVEAL_DURATION * 0.6) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN

    # Color flash.
    var color_tween: Tween = create_tween()
    color_tween.tween_property(_result_label, "modulate", target_color, REVEAL_DURATION * 0.3)
    color_tween.tween_property(_result_label, "modulate", Color.WHITE, REVEAL_DURATION * 0.7)

    print("[SlotMachineUI] Reveal animation played. Tier: %s" % tier)
```

### 4.9 Other Signal Callbacks

```gdscript
func _on_spin_failed(required: int, available: int) -> void:
    # This fires when SlotMachineLogic.spin_reels() was called but spins < bet.
    # The UI should show an error and keep the button disabled.
    _is_spinning = false
    _result_label.text = "Need %d spins!" % required
    _spin_button.disabled = true
    print("[SlotMachineUI] Spin failed — insufficient spins (need %d, have %d)." % [required, available])


func _on_raid_triggered(raid_count: int) -> void:
    # Cosmetic: flash a "Raid!" indicator.
    # The actual raid logic is handled by NPCSimulator (Step 5).
    print("[SlotMachineUI] Raid triggered! Count: %d" % raid_count)


func _on_attack_triggered(attack_count: int) -> void:
    # Cosmetic: flash an "Attack!" indicator.
    # The actual attack logic is handled by NPCSimulator (Step 5).
    print("[SlotMachineUI] Attack triggered! Count: %d" % attack_count)


func _on_shield_overflow(compensation: int) -> void:
    # Fires when shield outcome is intercepted by the cap.
    # The result label will already show the intercept text from _on_spin_completed.
    print("[SlotMachineUI] Shield overflow intercepted. Compensation: %d coins." % compensation)
```

### 4.10 Button State Management

```gdscript
func _update_button_state() -> void:
    var slot_logic: SlotMachineLogic = _find_slot_logic()
    if slot_logic != null and slot_logic.can_spin(1):
        _spin_button.disabled = false
    else:
        _spin_button.disabled = true


func _find_slot_logic() -> SlotMachineLogic:
    # Try sibling node first.
    var found: SlotMachineLogic = get_node_or_null("../SlotMachineLogic") as SlotMachineLogic
    if found != null:
        return found
    # Fallback: search from root.
    return get_node_or_null("/root/Main/SlotMachineLogic") as SlotMachineLogic
```

---

## SECTION 5: SLOT MACHINE PANEL SCENE — `SlotMachinePanel.tscn`

Create a new packed scene file at `res://src/ui/SlotMachinePanel.tscn`.

The scene is a `Control` node (uses `CanvasItem`/`Control` as root so it can be embedded in any layout) containing the visual elements for the slot machine.

```tscn
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/SlotMachineUI.gd" id="1_ui"]

[node name="SlotMachinePanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_ui")

[node name="ReelContainer" type="HBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -120.0
offset_top = -60.0
offset_right = 120.0
offset_bottom = 60.0
grow_horizontal = 2
grow_vertical = 2
alignment = 1

[node name="Reel1" type="ColorRect" parent="ReelContainer"]
custom_minimum_size = Vector2(70, 100)
layout_mode = 2
size_flags_horizontal = 3
color = Color(0.2, 0.4, 0.8, 1)

[node name="Reel2" type="ColorRect" parent="ReelContainer"]
custom_minimum_size = Vector2(70, 100)
layout_mode = 2
size_flags_horizontal = 3
color = Color(0.4, 0.2, 0.8, 1)

[node name="Reel3" type="ColorRect" parent="ReelContainer"]
custom_minimum_size = Vector2(70, 100)
layout_mode = 2
size_flags_horizontal = 3
color = Color(0.8, 0.4, 0.2, 1)

[node name="ResultLabel" type="Label" parent="."]
layout_mode = 1
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -200.0
offset_top = -120.0
offset_right = 200.0
offset_bottom = -80.0
grow_horizontal = 2
grow_vertical = 0
text = "Spin to play!"
horizontal_alignment = 1
vertical_alignment = 1

[node name="SpinButton" type="Button" parent="."]
layout_mode = 1
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -80.0
offset_top = -60.0
offset_right = 80.0
offset_bottom = -10.0
grow_horizontal = 2
grow_vertical = 0
text = "SPIN"
```

**Note on Reel nodes:** The `ColorRect` nodes above are placeholders. In a production build, replace them with `Sprite2D` nodes displaying slot symbol textures. The animation code uses `position` and `modulate` properties which work identically on `ColorRect` and `Sprite2D`.

---

## SECTION 6: MAIN SCENE UPDATES — `Main.gd`

The `Main.gd` script is the **scene orchestrator**. It does NOT contain game logic. It is responsible for:
1. Instantiating and adding `SlotMachineLogic` and `NPCSimulator` nodes.
2. Connecting all cross-system signals.
3. Adding the `SlotMachinePanel` scene to the tree.
4. (Optionally) adding a `MainHUD` CanvasLayer if it is not already in the scene.

### 6.1 Updated `Main.gd`

```gdscript
# ==============================================================================
# Main.gd
# Path: res://src/core/Main.gd
# Role: Minimal scene entry point and cross-system signal orchestrator.
# All game logic lives in dedicated subsystems. This file only wires them.
# ==============================================================================
extends Node2D

## Reference to the SlotMachineLogic instance.
var slot_machine_logic: SlotMachineLogic

## Reference to the NPCSimulator instance.
var npc_simulator: NPCSimulator

## Reference to the SlotMachineUI panel instance.
var slot_machine_ui: SlotMachineUI


func _ready() -> void:
    print("[Main] CoinMaster booting...")

    # ── 1. Instantiate and add SlotMachineLogic ──────────────────────────────
    slot_machine_logic = SlotMachineLogic.new()
    slot_machine_logic.name = "SlotMachineLogic"
    add_child(slot_machine_logic)
    print("[Main] SlotMachineLogic instantiated.")

    # ── 2. Instantiate and add NPCSimulator ───────────────────────────────────
    npc_simulator = NPCSimulator.new()
    npc_simulator.name = "NPCSimulator"
    add_child(npc_simulator)
    print("[Main] NPCSimulator instantiated.")

    # ── 3. Add SlotMachinePanel (UI scene) ────────────────────────────────────
    var panel_scene: PackedScene = load("res://src/ui/SlotMachinePanel.tscn")
    if panel_scene != null:
        slot_machine_ui = panel_scene.instantiate() as SlotMachineUI
        if slot_machine_ui != null:
            add_child(slot_machine_ui)
            print("[Main] SlotMachinePanel loaded.")
        else:
            push_error("[Main] Failed to instantiate SlotMachinePanel.")
    else:
        push_error("[Main] SlotMachinePanel.tscn not found at res://src/ui/SlotMachinePanel.tscn.")

    # ── 4. Wire SaveLoadManager → NPCSimulator (Step 5 contract) ─────────────
    SaveLoadManager.game_loaded.connect(_on_save_game_loaded)

    # ── 5. Wire SlotMachineLogic → NPCSimulator ────────────────────────────────
    if slot_machine_logic != null:
        slot_machine_logic.raid_triggered.connect(_on_raid_triggered)
        slot_machine_logic.attack_triggered.connect(_on_attack_triggered)

    print("[Main] CoinMaster ready.")


func _on_save_game_loaded() -> void:
    # Trigger offline simulation after save data is available.
    if npc_simulator != null:
        npc_simulator.calculate_offline_events()


func _on_raid_triggered(raid_count: int) -> void:
    # Forward raid signal to NPCSimulator for target generation.
    if npc_simulator != null:
        npc_simulator.generate_raid_target()


func _on_attack_triggered(attack_count: int) -> void:
    # Forward attack signal to NPCSimulator for live attack resolution.
    if npc_simulator != null:
        npc_simulator.on_live_attack_triggered(attack_count)
```

### 6.2 Updated `Main.tscn`

The scene needs to include a `MainHUD` node as well. Update the existing `Main.tscn` to add the HUD layer:

```tscn
[gd_scene load_steps=3 format=3 uid="uid://placeholder_main"]

[ext_resource type="Script" path="res://src/core/Main.gd" id="1"]
[ext_resource type="Script" path="res://src/ui/MainHUD.gd" id="2_hud"]

[node name="Main" type="Node2D"]
script = ExtResource("1")

[node name="HUDCanvas" type="CanvasLayer" parent="."]

[node name="MainHUD" type="Control" parent="HUDCanvas"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 0.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("2_hud")

[node name="CoinPanel" type="HBoxContainer" parent="HUDCanvas/MainHUD"]
layout_mode = 1
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -150.0
offset_top = 10.0
offset_right = -10.0
offset_bottom = 50.0
grow_horizontal = 0
alignment = 2

[node name="CoinIcon" type="Label" parent="HUDCanvas/MainHUD/CoinPanel"]
layout_mode = 2
text = "🪙"

[node name="CoinLabel" type="Label" parent="HUDCanvas/MainHUD/CoinPanel"]
layout_mode = 2
text = "0"

[node name="SpinPanel" type="HBoxContainer" parent="HUDCanvas/MainHUD"]
layout_mode = 1
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -300.0
offset_top = 10.0
offset_right = -160.0
offset_bottom = 50.0
grow_horizontal = 0
alignment = 2

[node name="SpinIcon" type="Label" parent="HUDCanvas/MainHUD/SpinPanel"]
layout_mode = 2
text = "🔄"

[node name="SpinLabel" type="Label" parent="HUDCanvas/MainHUD/SpinPanel"]
layout_mode = 2
text = "0"

[node name="ShieldPanel" type="HBoxContainer" parent="HUDCanvas/MainHUD"]
layout_mode = 1
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -450.0
offset_top = 10.0
offset_right = -310.0
offset_bottom = 50.0
grow_horizontal = 0
alignment = 2

[node name="ShieldIcon" type="Label" parent="HUDCanvas/MainHUD/ShieldPanel"]
layout_mode = 2
text = "🛡️"

[node name="ShieldLabel" type="Label" parent="HUDCanvas/MainHUD/ShieldPanel"]
layout_mode = 2
text = "0/5"
```

---

## SECTION 7: ARCHITECTURAL CONSTRAINTS & GOTCHAS

### 7.1 Absolute Prohibitions

| Prohibition | Reason |
|---|---|
| Do NOT import `SlotMachineLogic` inside `MainHUD.gd` | `MainHUD` is HUD-only. It has no business with slot math. |
| Do NOT import `VillageManager` inside `SlotMachineUI.gd` | UI knows nothing about village state. |
| Do NOT call `SaveLoadManager.add_coins()` from any UI script | Only Model layer calls mutators. |
| Do NOT write `SaveLoadManager.coins = x` from any UI script | Same reason. |
| Do NOT call `slot_machine_logic.spin_reels()` from `MainHUD` | Slot spin is the responsibility of `SlotMachineUI`. |
| Do NOT put game math in `_play_spin_animation()` | Animation is cosmetic. Outcome is pre-determined. |
| Do NOT use `randi()` or `RandomNumberGenerator` in any UI script | RNG belongs in `SlotMachineLogic` only. |

### 7.2 Input Locking Contract

The spin button must be **disabled** (`disabled = true`) from the moment the player presses it until the Tween fully completes the outcome reveal.

The `disabled` property is the **single source of truth** for spin availability. The `can_spin()` check is only a pre-flight guard — the lock is enforced by the disabled flag.

```
Time 0ms:     Player clicks Spin → _is_spinning = true, button.disabled = true
Time 0ms:     _play_spin_animation() starts (non-blocking)
Time 0ms:     slot_machine_logic.spin_reels() called → returns immediately
Time 0ms:     spin_completed signal fires → _on_spin_completed queued
Time ~1500ms: Tweens complete
Time ~1900ms: _finalize_spin_complete() runs → _is_spinning = false, button.disabled = false
```

If the player clicks the button while `_is_spinning == true`, the press is ignored:

```gdscript
func _on_spin_button_pressed() -> void:
    if _is_spinning:
        print("[SlotMachineUI] Spin ignored — animation in progress.")
        return
    # ... proceed
```

### 7.3 Godot Tween Gotchas

**Gotcha 1: Awaiting Tweens vs. non-awaited Tweens**
- `create_tween()` returns a `Tween` that runs independently unless you `await` it.
- We intentionally do NOT `await` the spin animation. The function `_on_spin_button_pressed()` returns immediately after starting the animation.
- The unlock logic runs in `_on_spin_completed` via a `create_timer().timeout` await.
- If you accidentally `await` the spin animation, the button will be locked for the full animation duration AND the function will be blocking — causing frame drops and input freeze.

**Gotcha 2: `set_parallel(true)` vs. `set_parallel(false)`**
- `set_parallel(true)` (default): all `tween_property()` calls in the same `create_tween()` chain run simultaneously. Used for the spin animation where all 3 reels move at once.
- `set_parallel(false)`: tweens in the chain run sequentially. Used for the reveal pop (scale up then scale back).
- Mixing parallel and sequential tweens requires separate `create_tween()` calls.

**Gotcha 3: ColorRect vs Sprite2D**
- Both inherit from `CanvasItem`. `position`, `modulate`, `scale` properties are identical.
- If replacing ColorRect with Sprite2D for reel symbols, the animation code requires zero changes.

**Gotcha 4: Tween cleanup**
- Programmatically created Tweens (`create_tween()`) auto-free when they complete. No manual `tween.kill()` needed.
- If you manually `add_child(tween)` for long-lived tweens, you must `tween.kill()` in `_exit_tree()`.

**Gotcha 5: `Label.modulate` vs `Label.self_modulate`**
- `modulate` affects the node and all children. `self_modulate` affects only the node itself.
- Use `modulate` for the result label to also affect any icon children.

### 7.4 Signal Connection Gotchas

**Gotcha 6: Signal subscriptions in `_ready()`**
- Always cache node references BEFORE connecting signals that refer to those nodes.
- If `_spin_button` is null, connecting `_spin_button.pressed` will crash at runtime.
- Always include null guards after `as` casting: `if node == null: push_error(...)`.

**Gotcha 7: Callable signature must match signal signature**
- `SaveLoadManager.coins_changed.connect(_on_coins_changed)` requires `_on_coins_changed(new_value: int)`.
- If the callback signature is wrong (e.g., `()` or `(float)`), Godot prints a runtime warning and the callback never fires.
- This is a silent failure — always verify callback signatures match signal declarations.

**Gotcha 8: Disconnecting signals in `_exit_tree()`**
- For nodes that persist across scene changes, disconnect signals in `_exit_tree()` to avoid duplicate connections on re-enter.
- Since `MainHUD` and `SlotMachineUI` are children of `Main` and live for the entire session, signal disconnection on exit is optional but recommended:

```gdscript
func _exit_tree() -> void:
    if SaveLoadManager:
        SaveLoadManager.coins_changed.disconnect(_on_coins_changed)
        SaveLoadManager.spins_changed.disconnect(_on_spins_changed)
        SaveLoadManager.shields_changed.disconnect(_on_shields_changed)
```

### 7.5 Scene Loading Gotchas

**Gotcha 9: `load()` vs `preload()`**
- `load("path")` returns a `Resource` lazily. Use when the resource may not be needed.
- `preload("path")` evaluates at script parse time. Use for resources always needed.
- For the panel scene: use `load()` inside `_ready()` to keep startup lean.

**Gotcha 10: `instantiate()` vs `instance()`**
- Godot 4 uses `PackedScene.instantiate()`. (Godot 3 used `instance()`).
- Using `instance()` in Godot 4 will cause a runtime error.

---

## SECTION 8: EDGE CASE REGISTRY

| Edge Case | Trigger Condition | Handling |
|---|---|---|
| **Signal arrives before `_ready()` completes** | Race condition on very slow startup | Both `_on_spin_completed` and `_on_spin_button_pressed` guard with `_is_spinning` check. |
| **Signal fires but SlotMachineLogic node missing** | Scene wiring error | `push_error()` in `_ready()`. Button shows "System Error". |
| **Player clicks Spin with 0 spins** | `can_spin(1) == false` | Pre-flight check in `_on_spin_button_pressed`. Button disabled. Message shown. |
| **Player double-clicks Spin during animation** | `_is_spinning == true` | Early return in `_on_spin_button_pressed`. Ignored silently. |
| **Tween animation still running when second spin signal arrives** | Extremely fast signal dispatch | `_is_spinning` guards prevent re-entry. Second `_on_spin_completed` ignored by guard. |
| **Reel ColorRect nodes missing from scene** | Typo in node paths | Null check in `_ready()`. `push_error()` if null. Animation skipped. |
| **SaveLoadManager not registered as Autoload** | project.godot misconfiguration | `SaveLoadManager` reference returns `null`. Signal connection will crash. This is a fatal configuration error — `push_error()` is insufficient. Add an explicit runtime assert. |
| **shield_overflow_intercepted fires but result already shown** | Intercepted outcome overwrites normal | `_on_spin_completed` handles `was_intercepted` flag. Text updated accordingly. |
| **Raid/Attack signals fire while animation in progress** | Normal — outcome can trigger raid | Cosmetic only. `_on_raid_triggered` and `_on_attack_triggered` are print-only in this step. |
| **Label node null in update helper** | Scene layout mismatch | Each update helper checks `!= null` before setting `.text`. Safe no-op. |
| **Spin button disabled but `_is_spinning` also somehow false** | State inconsistency | `_update_button_state()` syncs disabled flag with `can_spin()`. Call after any state change. |

---

## SECTION 9: COMPLETION CHECKLIST

Before proceeding to Step 7, Cursor must confirm ALL of the following:

**File Existence:**
- [ ] `res://src/ui/MainHUD.gd` exists with `class_name MainHUD`
- [ ] `res://src/ui/SlotMachineUI.gd` exists with `class_name SlotMachineUI`
- [ ] `res://src/ui/SlotMachinePanel.tscn` exists as a valid packed scene
- [ ] `res://src/core/Main.gd` is updated with the orchestrator code
- [ ] `res://src/scenes/Main.tscn` is updated with HUD and panel nodes

**Architecture — Separation of Concerns:**
- [ ] `MainHUD.gd` contains ZERO references to `SlotMachineLogic`, `VillageManager`, or `NPCSimulator`
- [ ] `MainHUD.gd` contains ZERO calls to `SaveLoadManager` mutators (`add_coins`, `spend_coins`, etc.)
- [ ] `SlotMachineUI.gd` contains ZERO calls to `SaveLoadManager` mutators
- [ ] `SlotMachineUI.gd` contains ZERO calls to `VillageManager` methods
- [ ] `SlotMachineUI.gd` calls `SlotMachineLogic.spin_reels()` — no other spin math exists in the View layer

**Signal Wiring:**
- [ ] `MainHUD._ready()` subscribes to `SaveLoadManager.coins_changed`
- [ ] `MainHUD._ready()` subscribes to `SaveLoadManager.spins_changed`
- [ ] `MainHUD._ready()` subscribes to `SaveLoadManager.shields_changed`
- [ ] `SlotMachineUI._ready()` subscribes to `SlotMachineLogic.spin_completed`
- [ ] `SlotMachineUI._ready()` subscribes to `SlotMachineLogic.spin_failed_insufficient_spins`
- [ ] `SlotMachineUI._ready()` subscribes to `SlotMachineLogic.raid_triggered`
- [ ] `SlotMachineUI._ready()` subscribes to `SlotMachineLogic.attack_triggered`
- [ ] `Main._ready()` connects `SaveLoadManager.game_loaded` to `NPCSimulator.calculate_offline_events()`
- [ ] `Main._ready()` connects `SlotMachineLogic.raid_triggered` to `NPCSimulator.generate_raid_target()`
- [ ] `Main._ready()` connects `SlotMachineLogic.attack_triggered` to `NPCSimulator.on_live_attack_triggered()`

**Input Locking:**
- [ ] `_spin_button.disabled = true` is set immediately inside `_on_spin_button_pressed()`
- [ ] `_is_spinning = true` is set immediately inside `_on_spin_button_pressed()`
- [ ] `_spin_button.disabled = false` is set inside `_finalize_spin_complete()` ONLY
- [ ] `_is_spinning = false` is set inside `_finalize_spin_complete()` ONLY
- [ ] `_on_spin_button_pressed()` returns early if `_is_spinning == true`
- [ ] `_on_spin_completed()` returns early if `_is_spinning == false` (guard on signal)

**Animation:**
- [ ] `_play_spin_animation()` uses `create_tween()` (Godot 4 API, NOT `Tween.new()`)
- [ ] Tweens are NOT awaited — animation runs independently
- [ ] Button unlock is delayed by `REEL_SPIN_DURATION + REVEAL_DURATION` via `create_timer()`
- [ ] `_play_reveal_animation()` uses a separate `create_tween()` (sequential, not parallel)
- [ ] `REVEL_DURATION` and `REEL_SPIN_DURATION` are declared as named constants

**Label Formatting:**
- [ ] Coins label uses `%,d` formatting (comma thousands separator)
- [ ] Spins label uses `%,d` formatting
- [ ] Shields label uses `%d/5` format

**Null Safety:**
- [ ] All node cache assignments (`_coin_label = $... as Label`) are followed by null checks
- [ ] `push_error()` used for fatal missing nodes (SpinButton, SlotMachineLogic)
- [ ] `push_warning()` used for non-fatal missing nodes (ResultLabel, reel nodes)
- [ ] All update helpers guard against null label references

**Logging:**
- [ ] `MainHUD._ready()` prints initialization message with current resource values
- [ ] `SlotMachineUI._ready()` prints initialization message
- [ ] `SlotMachineUI._on_spin_button_pressed()` prints "Spin initiated. Button locked."
- [ ] `SlotMachineUI._finalize_spin_complete()` prints "Outcome displayed. Button unlocked."
- [ ] All log messages include `[ClassName]` prefix

**Static Typing:**
- [ ] All variables have explicit type annotations (`: Label`, `: Button`, `: bool`, etc.)
- [ ] All function parameters have type annotations (`: int`, `: Dictionary`, `: String`, etc.)
- [ ] All function return types are declared (`: void`, `: Dictionary`, `: bool`, etc.)

**Scene Integrity:**
- [ ] `project.godot` registers `SaveLoadManager` as Autoload (already done — do not change)
- [ ] `SlotMachineLogic` and `NPCSimulator` are NOT registered as Autoloads
- [ ] `Main.tscn` main_scene entry is `res://src/scenes/Main.tscn` (unchanged)

**DO NOT proceed to Step 7 until this checklist is fully verified.**

---

## SECTION 10: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 7 will build `res://src/core/EventManager.gd` to handle global game events (CoinCraze, VikingQuest, SeaOfFortune, CoinCafe, BossFight). `EventManager` connects to `SlotMachineLogic.spin_completed` as a post-processor to apply event multipliers to coin rewards. It reads from `SaveLoadManager.event_flags` and emits `event_triggered` and `event_expired` signals that `MainHUD` will display as banner notifications. Step 7 also introduces the in-game shop UI and the `ShopManager.gd` system that handles one-time offers and spin pack purchases.
