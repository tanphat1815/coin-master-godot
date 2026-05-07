# CURSOR IMPLEMENTATION BLUEPRINT
## Coin Master Clone — Main UI Scene & Signal Architecture
### Directive: Godot 4.6 or lastest | GDScript 2.0  or lastest| MVC Strict Separation

> **IMPORTANT — READ FIRST:** You are an AI Coder operating inside Godot 4.6 or lastest. The project scaffold, JSON data files, and all core logic singletons (`SaveLoadManager.gd`, `SlotMachineLogic.gd`, `VillageManager.gd`, `NPCSimulator.gd`, `PetManager.gd`, `CardManager.gd`) are already implemented. Do NOT rewrite them. Your sole task is to build the visual scene tree, wire signals, and implement animations as specified below. All UI scripts must emit signals only — zero math logic permitted in the UI layer.

---

## SECTION 1: GODOT SCENE TREE ARCHITECTURE (Z-INDEX / CANVASLAYER STRATEGY)

### 1.0 — Create the Root Scene

Create a new scene file at `res://scenes/MainGameUI.tscn`. The root node must be a `Node2D` named `MainGameUI`. Attach a new script at `res://src/ui/MainGameUI.gd`. This root node owns no visual content — it solely serves as a scene container and signal relay.

---

### 1.1 — CanvasLayer -1: Background

Add a `CanvasLayer` node as the first child of `MainGameUI`. Name it `LayerBackground`. Set `layer = -1`.

Inside `LayerBackground`, add a `TextureRect` named `BackgroundTexture`:
- Set `anchor_left = 0`, `anchor_top = 0`, `anchor_right = 1`, `anchor_bottom = 1` (full rect, use `PRESET_FULL_RECT`).
- Set `expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL`.
- Set `stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED`.
- Assign placeholder at `res://assets/sprites/bg/village_bg_placeholder.png`. The background texture will be swapped dynamically by `VillageManager` when the player advances villages.

Add a second child to `LayerBackground`: a `ColorRect` named `DimOverlay`:
- Full rect anchors.
- `color = Color(0, 0, 0, 0.18)` — a subtle vignette to ensure HUD legibility over busy village backgrounds.
- `mouse_filter = Control.MOUSE_FILTER_IGNORE`.

---

### 1.2 — CanvasLayer 0: Core Slot Machine

Add a second `CanvasLayer` as a child of `MainGameUI`. Name it `LayerSlotMachine`. Set `layer = 0`.

Inside `LayerSlotMachine`, add a `Control` node named `SlotMachineRoot`:
- Set anchors to `PRESET_CENTER` (anchor horizontally and vertically centered).
- Set `custom_minimum_size = Vector2(720, 260)`.
- This node is the slot machine's spatial anchor. All reel elements are children of this node.

#### 1.2.1 — Reel Container

Inside `SlotMachineRoot`, add an `HBoxContainer` named `ReelContainer`:
- `alignment = BoxContainer.ALIGNMENT_CENTER`.
- `separation = 8` (set via Theme overrides on the node, not globally).
- Full rect anchors within `SlotMachineRoot`.

Inside `ReelContainer`, add three identical child structures. Repeat this block three times, naming them `Reel1`, `Reel2`, `Reel3`:

```
VBoxContainer (named "Reel1")
  └── ClipContainer (Control node, clip_contents = true, custom_minimum_size = Vector2(160, 160))
        └── VBoxContainer named "ReelStrip1"
              ├── TextureRect named "Symbol_Top"    # height = 160, expand = FIT_WIDTH
              ├── TextureRect named "Symbol_Mid"    # This is the "visible" result slot
              └── TextureRect named "Symbol_Bot"    # height = 160
```

- Set `ClipContainer.clip_contents = true`. This is critical — it masks the strip scroll so only one symbol is visible at a time.
- Each `TextureRect` symbol must have `expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL` and `custom_minimum_size = Vector2(160, 160)`.
- Attach the script `res://src/ui/ReelUI.gd` to each `VBoxContainer` reel root.

#### 1.2.2 — Slot Machine Frame Overlay

Add a `TextureRect` named `SlotFrame` as a child of `SlotMachineRoot` (sibling to `ReelContainer`), positioned to overlay the reels decoratively. Set `mouse_filter = MOUSE_FILTER_IGNORE`. Assign `res://assets/sprites/slot/slot_frame.png`. This is a purely cosmetic node.

---

### 1.3 — CanvasLayer 1: HUD & Controls

Add a `CanvasLayer` named `LayerHUD`. Set `layer = 1`.

#### 1.3.1 — Top Bar

Inside `LayerHUD`, add a `MarginContainer` named `TopBar`:
- Anchor preset: `PRESET_TOP_WIDE`.
- `size_flags_horizontal = SIZE_FILL`.
- Margins: `margin_top = 12`, `margin_left = 16`, `margin_right = 16`, `margin_bottom = 0`.

Inside `TopBar`, add an `HBoxContainer` named `TopBarInner`:
- `alignment = BoxContainer.ALIGNMENT_CENTER`.
- `separation = 12`.

Inside `TopBarInner`, add three `PanelContainer` nodes: `CoinPanel`, `StarPanel`, `ShieldPanel`. Each `PanelContainer` must use a `StyleBoxFlat` with:
- `bg_color = Color(0.08, 0.06, 0.02, 0.85)` (dark translucent gold-tinted).
- `corner_radius_top_left = corner_radius_top_right = corner_radius_bottom_left = corner_radius_bottom_right = 12`.
- `border_width_bottom = 2`, `border_color = Color(0.9, 0.75, 0.2, 1.0)` (gold border).

Inside each `PanelContainer`, add an `HBoxContainer` with padding margins of 8px, containing:
- A `TextureRect` (icon, `custom_minimum_size = Vector2(28, 28)`).
- A `Label` named `CoinLabel` / `StarLabel` / `ShieldLabel`.
  - Font size: `22px`, bold.
  - `vertical_alignment = VERTICAL_ALIGNMENT_CENTER`.

Attach the script `res://src/ui/TopBarHUD.gd` to `TopBarInner`.

#### 1.3.2 — Left Sidebar (Event Icons)

Inside `LayerHUD`, add a `ScrollContainer` named `LeftSidebar`:
- Anchor preset: `PRESET_LEFT_WIDE` with a fixed width of `72px`.
- `horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED`.
- `vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO`.

Inside `LeftSidebar`, add a `VBoxContainer` named `LeftEventList`:
- `alignment = BoxContainer.ALIGNMENT_BEGIN`.
- `separation = 8`.
- `size_flags_vertical = SIZE_EXPAND_FILL`.

Event icon buttons will be dynamically instantiated into `LeftEventList` at runtime by the event system. Each icon is a `TextureButton` with `custom_minimum_size = Vector2(60, 60)`. Do not hardcode event icons here.

#### 1.3.3 — Right Sidebar (Pets & Utilities)

Inside `LayerHUD`, add a `ScrollContainer` named `RightSidebar`:
- Anchor preset: `PRESET_RIGHT_WIDE`, width `72px`.
- Mirror of `LeftSidebar` configuration.

Inside `RightSidebar`, add a `VBoxContainer` named `RightPetList`:
- Same configuration as `LeftEventList`.
- Pet activation buttons will be instantiated dynamically by `PetManager`.

#### 1.3.4 — Bottom Footer (Spin Controls)

Inside `LayerHUD`, add a `MarginContainer` named `BottomFooter`:
- Anchor preset: `PRESET_BOTTOM_WIDE`.
- Margins: `margin_bottom = 20`, `margin_left = 16`, `margin_right = 16`.

Inside `BottomFooter`, add an `HBoxContainer` named `FooterInner`:
- `alignment = BoxContainer.ALIGNMENT_CENTER`.
- `separation = 20`.

**Spin Button:** Add a `TextureButton` named `SpinButton` inside `FooterInner`:
- `custom_minimum_size = Vector2(180, 180)`.
- Assign `res://assets/sprites/ui/spin_button_normal.png` to `texture_normal`.
- Assign `res://assets/sprites/ui/spin_button_pressed.png` to `texture_pressed`.
- Assign `res://assets/sprites/ui/spin_button_disabled.png` to `texture_disabled`.
- This button is the primary interaction point. Its `pressed` signal will be connected in Section 3.

**Bet Multiplier Toggle:** Add a `TextureButton` named `BetMultiplierButton` inside `FooterInner` as a sibling of `SpinButton`:
- `custom_minimum_size = Vector2(80, 80)`.
- Position it visually above-left of the Spin button using an `VBoxContainer` wrapper if needed.
- Add a `Label` child named `MultiplierLabel` overlaid on top of the button texture showing the current multiplier value (e.g., `"x1"`).
- `MultiplierLabel` must be set with `mouse_filter = MOUSE_FILTER_IGNORE` so clicks pass through to the `TextureButton`.

**Spin Count Label:** Add a `Label` named `SpinCountLabel` inside `FooterInner` as a sibling:
- Displays remaining spins (e.g., `"47"`).
- Font size: `28px`, bold, centered.
- `horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER`.

Attach the script `res://src/ui/SlotMachineUI.gd` to `BottomFooter`.

---

### 1.4 — CanvasLayer 2: Overlays & Popups

Add a `CanvasLayer` named `LayerOverlays`. Set `layer = 2`.

Inside `LayerOverlays`, add the following child nodes. All are hidden by default (`visible = false`). They are shown/hidden by signal-driven logic:

**A) `AttackOverlay` (Control, full rect anchors):**
- Contains `ColorRect` full-screen backdrop (`color = Color(0,0,0,0.7)`).
- Contains a `CenterContainer` with a `TextureRect` named `AttackVillageView` for the NPC village render.
- Contains a `Label` named `AttackResultLabel`.
- Attach script `res://src/ui/AttackOverlayUI.gd`.

**B) `RaidOverlay` (Control, full rect anchors):**
- Contains a `TextureRect` named `RaidGroundView` showing a digging scene asset.
- Contains three `TextureButton` nodes named `Hole1`, `Hole2`, `Hole3` laid out in an `HBoxContainer`.
- Contains a `Label` named `RaidResultLabel`.
- Attach script `res://src/ui/RaidOverlayUI.gd`.

**C) `ChestOpenOverlay` (Control, full rect anchors):**
- Contains a `CenterContainer` housing an `AnimationPlayer` node named `ChestAnimPlayer`.
- Contains a `TextureRect` named `ChestSprite`.
- Contains a `CPUParticles2D` named `BurstParticles` (initially `emitting = false`).
- Contains a `GridContainer` named `CardRevealGrid` (columns = 4) for displaying revealed cards.
- Attach script `res://src/ui/ChestOpenUI.gd`.

**D) `SettingsModal` (Control, full rect anchors):**
- Standard `PanelContainer` centered using `PRESET_CENTER`.
- `custom_minimum_size = Vector2(400, 500)`.
- Contains a `VBoxContainer` with placeholder settings options (Sound Toggle, Music Toggle, Close Button).
- Attach script `res://src/ui/SettingsModalUI.gd`.

---

### 1.5 — CanvasLayer 99: Trainer Console (Dev Mode)

Add a `CanvasLayer` named `LayerTrainer`. Set `layer = 99` (must render above all other layers).

Inside `LayerTrainer`, add a `PanelContainer` named `TrainerPanel`:
- `visible = false` by default.
- Anchor preset: `PRESET_TOP_LEFT`, with offset to position it top-left of the screen.
- `custom_minimum_size = Vector2(320, 480)`.
- Contains a `VBoxContainer` with the following children:
  - `Label` with text `"⚙ DEV TRAINER"`, font size 14, bold.
  - `HSeparator`.
  - `HBoxContainer`: `Label("Coins:")` + `SpinBox` named `CoinsInput` (max = 999999999).
  - `HBoxContainer`: `Label("Spins:")` + `SpinBox` named `SpinsInput` (max = 999999).
  - `HBoxContainer`: `Label("Shields:")` + `SpinBox` named `ShieldsInput` (max = 5).
  - `Button` named `InjectBtn` with text `"Inject Resources"`.
  - `HSeparator`.
  - `Label` with text `"Force RNG Result:"`.
  - `OptionButton` named `RNGOverrideDropdown` with items: `"None (Random)"`, `"3x Pig (Raid)"`, `"3x Hammer (Attack)"`, `"3x Coin"`, `"3x Shield"`, `"3x Energy"`.
  - `HSeparator`.
  - `Button` named `WipeStateBtn` with text `"⚠ WIPE SAVE DATA"`.

Attach script `res://src/ui/TrainerConsole.gd` to `LayerTrainer`.

---

## SECTION 2: ANIMATION & TWEENING BLUEPRINTS

### 2.1 — Slot Machine Reel Spin Animation (Tween-Based)

Open `res://src/ui/SlotMachineUI.gd`. Implement the following spin animation logic. This script connects to `SlotMachineLogic` but contains ZERO math. It only drives visual state.

**Step 1 — Lock Inputs.** When spin is triggered, immediately call:
```gdscript
SpinButton.disabled = true
BetMultiplierButton.disabled = true
```

**Step 2 — Request Result from Logic Layer BEFORE animating.** Call the logic layer and store the result. The animation must know the predetermined outcome before playing so the reel stops on the correct symbol.

```gdscript
var result: Dictionary = SlotMachineLogic.spin_reels(current_bet_multiplier)
# result = { "outcome": "shield", "reward": 3 }
```

**Step 3 — Animate Each Reel with Staggered Tweens.**

For each reel index `i` in `[0, 1, 2]`, create an independent `Tween`. Use the following pattern:

```gdscript
func animate_reel(reel_strip: VBoxContainer, target_symbol_texture: Texture2D, delay: float) -> void:
    var strip_height: float = 160.0  # Height of one symbol slot
    var tween: Tween = create_tween()
    tween.set_ease(Tween.EASE_IN)
    tween.set_trans(Tween.TRANS_CUBIC)

    # Phase 1: Ease-in — scroll down slowly to simulate inertia spin-up
    tween.tween_property(reel_strip, "position:y", -strip_height * 2, 0.3).set_delay(delay)

    # Phase 2: High-speed looping — rapidly cycle symbols
    # Use a loop of 8 rapid increments (no easing)
    for _j in range(8):
        tween.tween_property(reel_strip, "position:y",
            reel_strip.position.y - strip_height, 0.05).set_trans(Tween.TRANS_LINEAR)

    # Phase 3: Pre-snap — slow down before final position
    tween.set_ease(Tween.EASE_OUT)
    tween.set_trans(Tween.TRANS_ELASTIC)

    # Set the Symbol_Mid TextureRect to the predetermined result texture
    reel_strip.get_node("Symbol_Mid").texture = target_symbol_texture

    # Snap to final position — elastic overshoot snap
    tween.tween_property(reel_strip, "position:y", 0.0, 0.45)

    # Phase 4: Callback — after last reel finishes, unlock inputs
    if delay >= 0.3:  # Only the last reel triggers the unlock
        tween.tween_callback(_on_all_reels_stopped.bind(result))
```

- Reel 1 delay: `0.0s`
- Reel 2 delay: `0.15s`
- Reel 3 delay: `0.30s`

**Step 4 — Unlock Inputs after Last Reel.** In `_on_all_reels_stopped(result: Dictionary)`:

```gdscript
func _on_all_reels_stopped(result: Dictionary) -> void:
    SpinButton.disabled = false
    BetMultiplierButton.disabled = false
    spin_completed.emit(result)
    # Do NOT process rewards here — emit the signal and let the Controller layer handle it
```

---

### 2.2 — Chest Opening Animation (AnimationPlayer-Based)

Open `res://src/ui/ChestOpenUI.gd`. The `ChestAnimPlayer` node must have four named animations defined. Define them as follows:

#### Animation: `"Idle"`
- Single keyframe at `0.0s`.
- `ChestSprite.scale = Vector2(1.0, 1.0)`.
- `ChestSprite.rotation = 0.0`.
- `BurstParticles.emitting = false`.

#### Animation: `"Shake"`
- Duration: `0.6s`. Loop: false.
- Keyframe track on `ChestSprite.rotation`:
  - `0.0s → 0.0 rad`
  - `0.1s → 0.08 rad`
  - `0.2s → -0.08 rad`
  - `0.3s → 0.10 rad`
  - `0.4s → -0.10 rad`
  - `0.5s → 0.05 rad`
  - `0.6s → 0.0 rad`
- Keyframe track on `ChestSprite.scale`:
  - `0.0s → Vector2(1.0, 1.0)`
  - `0.3s → Vector2(1.08, 0.94)`
  - `0.6s → Vector2(1.0, 1.0)`
- At `0.6s`, use a `CallMethod` track to call `_on_shake_complete()`.

#### Animation: `"Burst"`
- Duration: `0.4s`. Loop: false.
- `BurstParticles.emitting = true` at `0.0s` via `CallMethod` track.
- `ChestSprite.scale` keyframes: `0.0s → (1.0, 1.0)`, `0.1s → (1.6, 1.6)`, `0.2s → (0.0, 0.0)` (chest disappears in expansion burst).
- At `0.35s`, use a `CallMethod` track to call `_on_burst_complete()`.

**CPUParticles2D configuration for `BurstParticles`:**
- `amount = 80`
- `lifetime = 1.2`
- `explosiveness = 0.9`
- `emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE`, `emission_sphere_radius = 5.0`
- `direction = Vector2(0, -1)`, `spread = 180.0`
- `initial_velocity_min = 200.0`, `initial_velocity_max = 450.0`
- `gravity = Vector2(0, 400)`
- `scale_amount_min = 8.0`, `scale_amount_max = 16.0`
- `color = Color(1.0, 0.85, 0.1)` (gold)

#### Animation: `"CardReveal"`
- Duration: computed dynamically — do NOT hardcode in AnimationPlayer. Instead, in `_on_burst_complete()`, iterate over the cards returned by `CardManager` and spawn them using staggered Tweens:

```gdscript
func _on_burst_complete() -> void:
    var cards: Array = CardManager.last_opened_cards  # Set by CardManager before emitting signal
    for i in range(cards.size()):
        var card_rect: TextureRect = preload("res://scenes/ui/CardWidget.tscn").instantiate()
        CardRevealGrid.add_child(card_rect)
        card_rect.texture = load(cards[i].texture_path)
        card_rect.scale = Vector2(0.0, 0.0)
        card_rect.modulate.a = 0.0

        var tween: Tween = create_tween()
        tween.set_delay(i * 0.12)
        tween.tween_property(card_rect, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tween.parallel().tween_property(card_rect, "modulate:a", 1.0, 0.2)
```

---

### 2.3 — Attack Transition & Impact Animation (Tween-Based)

When `SlotMachineLogic` emits an `attack_triggered` signal, the `AttackOverlayUI.gd` script must execute this sequence:

**Phase 1 — Screen Flash:** Instantiate a full-screen `ColorRect` dynamically, set `color = Color(1,1,1,0.9)`, add it as a temporary child of `LayerOverlays`. Tween its `modulate.a` from `0.9` to `0.0` over `0.3s` with `TRANS_EXPO`, then call `queue_free()` on it.

**Phase 2 — Show Overlay:** Set `AttackOverlay.visible = true`. Tween `AttackOverlay.modulate.a` from `0.0` to `1.0` over `0.2s`.

**Phase 3 — Populate NPC Village View:** Call `NPCSimulator.generate_attack_target()`. Assign the returned village texture and NPC name to `AttackVillageView` and a `Label` overlay.

**Phase 4 — Structure Downgrade Impact Shake:** For each structure being downgraded, apply a camera-style shake to `AttackVillageView` using a Tween:

```gdscript
func shake_structure(node: TextureRect, intensity: float = 12.0, duration: float = 0.4) -> void:
    var original_pos: Vector2 = node.position
    var tween: Tween = create_tween()
    tween.set_loops(int(duration / 0.05))
    tween.tween_property(node, "position",
        original_pos + Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)),
        0.05).set_trans(Tween.TRANS_LINEAR)
    tween.tween_callback(func(): node.position = original_pos)
```

Call `shake_structure()` on each targeted structure's visual node.

**Phase 5 — Dismiss:** After a `2.5s` wait (use `await get_tree().create_timer(2.5).timeout`), tween `AttackOverlay.modulate.a` from `1.0` to `0.0` over `0.3s`, then set `visible = false`.

---

## SECTION 3: SIGNAL WIRING & STATE MANAGEMENT (MVC)

**RULE — NEVER BREAK:** No `Label`, `TextureRect`, `Button`, or any other UI node script may read from `SaveLoadManager` directly inside a game loop. All UI updates must be driven by signals emitted from logic layers. UI scripts connect to signals and update display only.

---

### 3.1 — TopBarHUD.gd — Connecting to SaveLoadManager

In `TopBarHUD.gd`, in the `_ready()` function, connect to the `SaveLoadManager` autoload signals:

```gdscript
func _ready() -> void:
    SaveLoadManager.coins_changed.connect(_on_coins_changed)
    SaveLoadManager.spins_changed.connect(_on_spins_changed)
    SaveLoadManager.shields_changed.connect(_on_shields_changed)
    # Populate initial values immediately on scene load
    _on_coins_changed(SaveLoadManager.game_state.coins)
    _on_spins_changed(SaveLoadManager.game_state.spins)
    _on_shields_changed(SaveLoadManager.game_state.shields)

func _on_coins_changed(new_value: int) -> void:
    CoinLabel.text = _format_large_number(new_value)

func _on_spins_changed(new_value: int) -> void:
    SpinCountLabel.text = str(new_value)

func _on_shields_changed(new_value: int) -> void:
    ShieldLabel.text = str(new_value) + "/5"

func _format_large_number(n: int) -> String:
    if n >= 1_000_000_000: return "%.1fB" % (n / 1_000_000_000.0)
    if n >= 1_000_000: return "%.1fM" % (n / 1_000_000.0)
    if n >= 1_000: return "%.1fK" % (n / 1_000.0)
    return str(n)
```

**Ensure `SaveLoadManager.gd` emits these signals** — if they are not yet defined in the autoload, add them now:
```gdscript
signal coins_changed(new_value: int)
signal spins_changed(new_value: int)
signal shields_changed(new_value: int)
```
Emit each signal inside the relevant setter function in `SaveLoadManager.gd`.

---

### 3.2 — SlotMachineUI.gd — Connecting Spin Button to Logic

In `SlotMachineUI.gd`, define the current bet multiplier state and connect signals:

```gdscript
const MULTIPLIER_CYCLE: Array[int] = [1, 2, 3, 5, 10]
var _multiplier_index: int = 0
var current_bet_multiplier: int = 1

signal spin_completed(result: Dictionary)

func _ready() -> void:
    SpinButton.pressed.connect(_on_spin_pressed)
    BetMultiplierButton.pressed.connect(_on_multiplier_pressed)
    SaveLoadManager.spins_changed.connect(_on_spins_changed)

func _on_spin_pressed() -> void:
    # Guard: do not call logic if not enough spins
    if SaveLoadManager.game_state.spins < current_bet_multiplier:
        _play_insufficient_spins_feedback()
        return
    # Retrieve result from logic layer BEFORE animating
    var result: Dictionary = SlotMachineLogic.spin_reels(current_bet_multiplier)
    # Begin animation sequence (see Section 2.1)
    _start_reel_animation(result)

func _on_multiplier_pressed() -> void:
    _multiplier_index = (_multiplier_index + 1) % MULTIPLIER_CYCLE.size()
    current_bet_multiplier = MULTIPLIER_CYCLE[_multiplier_index]
    _update_multiplier_ui()

func _update_multiplier_ui() -> void:
    MultiplierLabel.text = "x%d" % current_bet_multiplier
    # Disable x10 if spins < 10
    if SaveLoadManager.game_state.spins < 10 and current_bet_multiplier == 10:
        _multiplier_index = 0
        current_bet_multiplier = 1
        MultiplierLabel.text = "x1"

func _on_spins_changed(new_value: int) -> void:
    SpinButton.disabled = (new_value <= 0)
    _update_multiplier_ui()

func _play_insufficient_spins_feedback() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(SpinButton, "modulate", Color(1, 0.3, 0.3), 0.1)
    tween.tween_property(SpinButton, "modulate", Color(1, 1, 1), 0.2)
```

---

### 3.3 — Bet Multiplier Propagation to Logic

The `current_bet_multiplier` integer is passed as an argument directly to `SlotMachineLogic.spin_reels(bet_multiplier)`. The logic layer is solely responsible for all multiplication of rewards. The UI layer must not perform any reward arithmetic.

---

### 3.4 — Post-Spin Signal Dispatch (Controller Relay)

In `MainGameUI.gd` (the root controller script), connect the `spin_completed` signal from `SlotMachineUI` and route it to the appropriate overlay system:

```gdscript
func _ready() -> void:
    var slot_ui = $LayerHUD/BottomFooter
    slot_ui.spin_completed.connect(_on_spin_result)

func _on_spin_result(result: Dictionary) -> void:
    match result.outcome:
        "attack":
            $LayerOverlays/AttackOverlay.show_attack(result)
        "raid":
            $LayerOverlays/RaidOverlay.show_raid(result)
        "shield", "coin", "energy":
            pass  # SaveLoadManager already updated; TopBarHUD reacts via signal automatically
        _:
            push_warning("Unknown spin outcome: " + result.outcome)
```

---

### 3.5 — TrainerConsole.gd — Dev Mode Wiring

In `TrainerConsole.gd`:

```gdscript
func _ready() -> void:
    InjectBtn.pressed.connect(_on_inject_pressed)
    WipeStateBtn.pressed.connect(_on_wipe_pressed)
    # Toggle visibility with keyboard shortcut
    set_process_unhandled_key_input(true)

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_D:
            TrainerPanel.visible = !TrainerPanel.visible

func _on_inject_pressed() -> void:
    SaveLoadManager.game_state.coins += int(CoinsInput.value)
    SaveLoadManager.game_state.spins += int(SpinsInput.value)
    SaveLoadManager.game_state.shields = mini(
        int(ShieldsInput.value),
        SaveLoadManager.MAX_SHIELDS
    )
    SaveLoadManager.save_game()
    # Signals in SaveLoadManager will automatically update the HUD

func _on_wipe_pressed() -> void:
    SaveLoadManager.wipe_save()
    get_tree().reload_current_scene()
```

The `RNGOverrideDropdown` selection must be read inside `SlotMachineLogic.gd` (not in UI). Add a globally accessible `rng_override: String = ""` variable to `SlotMachineLogic.gd`. In `TrainerConsole.gd`, set it directly:

```gdscript
func _on_rng_dropdown_changed(index: int) -> void:
    var options: Array[String] = ["", "raid_pig", "attack_hammer", "coin", "shield", "energy"]
    SlotMachineLogic.rng_override = options[index]
```

Connect `RNGOverrideDropdown.item_selected.connect(_on_rng_dropdown_changed)` in `_ready()`.

---

## FINAL CHECKLIST FOR CURSOR

Before marking this implementation complete, verify all of the following:

- [ ] `MainGameUI.tscn` saved with all 5 CanvasLayers (`-1`, `0`, `1`, `2`, `99`).
- [ ] `ClipContainer.clip_contents = true` on all three reel clip containers.
- [ ] `SpinButton.disabled` is set to `true` during tween animation and restored in `_on_all_reels_stopped()`.
- [ ] No arithmetic (multiplication, division, probability) exists in any file inside `/src/ui/`.
- [ ] All Labels in `TopBarHUD.gd` update only via signal callbacks, never via polling in `_process()`.
- [ ] `current_bet_multiplier` is passed as an argument to `SlotMachineLogic.spin_reels()` — it is NOT computed inside `SlotMachineUI.gd`.
- [ ] `ChestAnimPlayer` has four animations defined: `Idle`, `Shake`, `Burst`, `CardReveal`.
- [ ] `CPUParticles2D` (`BurstParticles`) has `emitting = false` by default.
- [ ] `LayerTrainer` has `layer = 99` and `TrainerPanel.visible = false` by default.
- [ ] `TrainerConsole.gd` modifies `SaveLoadManager.game_state` directly and calls `save_game()` — it does NOT bypass the save system.
- [ ] All overlay nodes (`AttackOverlay`, `RaidOverlay`, `ChestOpenOverlay`, `SettingsModal`) are `visible = false` at scene load.
- [ ] `MainGameUI.gd` acts as the signal router between `SlotMachineUI` result emissions and overlay visibility logic.