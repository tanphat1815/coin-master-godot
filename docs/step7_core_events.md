# step7_core_events.md

## Technical Specification: Live-Ops Event Framework
**Target Engine:** Godot 4.x
**Execution Agent:** Cursor (AI Coder)
**Step:** 7 of 10 — Implement `BaseEvent`, `EventManager`, and `Event_CoinCraze` as the live-ops event system.
**Depends On:** Step 3 complete (`SlotMachineLogic` signals available). Step 5 complete (`NPCSimulator` instantiated). Step 6 complete (UI wired, `Main.gd` orchestrator ready).
**Output Files:**
- `res://src/events/BaseEvent.gd`
- `res://src/events/EventManager.gd`
- `res://src/events/Event_CoinCraze.gd`
- `res://src/core/Main.gd` (updated — wire EventManager)
- `project.godot` (updated — register EventManager as Autoload)

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **ZERO game logic inside `EventManager` itself.** `EventManager` is a scheduler and signal router only. It does not contain coin multipliers, reward tables, or any gameplay math. All event-specific logic lives in concrete event classes that extend `BaseEvent`.
- **ZERO state mutation in `BaseEvent` virtual functions.** The `_on_start()` and `_on_end()` functions in `BaseEvent` are stubs — they do nothing. Only concrete event classes override them.
- **EventManager is an Autoload.** Unlike `SlotMachineLogic` or `NPCSimulator`, `EventManager` must be registered in `project.godot` so it is always accessible without needing a node reference.
- **All concrete event classes are non-Autoload.** `Event_CoinCraze` and future events are `extends BaseEvent` — they are registered with `EventManager` at runtime via `EventManager.register_event()`.
- **Scheduler polls via `_process()`, not timers.** `EventManager` uses `_process(delta)` to compare system time against event windows every frame. No `Timer` nodes are used.
- **The coin multiplier is applied AFTER `SlotMachineLogic` awards coins.** `Event_CoinCraze` subscribes to `SlotMachineLogic.spin_completed`, reads the result, and if `reward_type == "coins"`, calls `SaveLoadManager.add_coins()` with the extra amount. This post-process pattern is the only permitted modification path.
- **STRICTLY** use static typing on every variable and function signature.
- Confirm with the completion checklist before proceeding to Step 8.

---

## SECTION 1: ARCHITECTURAL ROLE

### 1.1 The Event System Architecture

```
SaveLoadManager.event_flags (persisted Dictionary)
       │
       │ read-only (EventManager reads, never writes directly)
       ▼
EventManager._process(delta)
       │  polls every frame
       │  compares Time.get_unix_time_from_system() vs event start/end
       ▼
┌─────────────────────────────────────────────────────────────┐
│   BaseEvent (abstract base — no concrete logic here)       │
│   properties: event_name, start_time, end_time, is_active   │
│   virtual: _on_start(), _on_end()                          │
└─────────────────────────┬───────────────────────────────────┘
                          │ extends
┌─────────────────────────▼───────────────────────────────────┐
│   Event_CoinCraze (concrete — CoinCraze-specific logic)     │
│   coin_multiplier: float = 2.0                             │
│   subscribes to SlotMachineLogic.spin_completed             │
│   override _on_start(): connect signal, print activation    │
│   override _on_end():   disconnect signal, print deactivation│
└─────────────────────────────────────────────────────────────┘
       │
       │ emits signals
       ▼
EventManager forwards:
  event_started(event_id: String, event_name: String)
  event_ended(event_id: String, event_name: String)
  all_events_checked(active_events: Array[String])
       │
       ▼
MainHUD subscribes → shows banner notifications
```

### 1.2 The Post-Process Multiplier Pattern

The coin multiplier is applied **after** `SlotMachineLogic` has already awarded coins and emitted `spin_completed`. This preserves the separation of concerns:

```
Player presses Spin
       │
       ▼
SlotMachineLogic.spin_reels()
       │
       ├──▶ SaveLoadManager.add_coins(base_reward)   ← already credited
       │
       ▼
spin_completed signal fires (result Dictionary)
       │
       ▼
Event_CoinCraze._on_spin_completed(result)      ← post-process
       │
       ├──▶ if result["reward_type"] != "coins": return (no action)
       │
       ├──▶ if not is_active: return (event not running)
       │
       ├──▶ extra: int = int(float(result["reward_value"]) * (coin_multiplier - 1.0))
       │
       ├──▶ if extra > 0: SaveLoadManager.add_coins(extra)
       │
       ├──▶ SaveLoadManager.save_game()
       │
       └──▶ print "[Event_CoinCraze] CoinCraze bonus: +%d extra coins!" % extra
```

### 1.3 Event Flag Schema (from `SaveLoadManager.event_flags`)

Each event in `SaveLoadManager.event_flags` follows this schema:

```gdscript
{
    "is_active":         bool,    # whether event is currently running
    "start_timestamp":   int,     # Unix timestamp when event begins
    "end_timestamp":     int      # Unix timestamp when event ends
}
```

`EventManager` reads these values every frame. **It does not write them.** Event activation/deactivation is controlled by external systems (server push, cheat codes, or future campaign manager). For this implementation, events are activated by calling `EventManager.activate_event(event_id)` — a dev/testing entry point.

### 1.4 Interaction Contract

| System | Role | Interaction |
|---|---|---|
| `SaveLoadManager` | Model — persists event state | `EventManager` reads `event_flags` every frame. `Event_CoinCraze` calls `add_coins()` for bonus coins. |
| `SlotMachineLogic` | Model — spin engine | `Event_CoinCraze` subscribes to `spin_completed`. It does not know events exist. |
| `BaseEvent` | Abstract base | Defines the event interface. No concrete logic. |
| `Event_CoinCraze` | Concrete event | Overrides `_on_start()` and `_on_end()`. Connects/disconnects `spin_completed`. |
| `EventManager` | Singleton scheduler | Polls time, calls `_on_start()`/`_on_end()`, emits lifecycle signals. |
| `Main.gd` | Orchestrator | Calls `EventManager.register_event()` for each concrete event class. |

---

## SECTION 2: DIRECTORY STRUCTURE

### 2.1 Files to CREATE

```
res://src/
├── events/
│   ├── BaseEvent.gd         ← NEW (abstract base class)
│   ├── EventManager.gd      ← NEW (Autoload singleton)
│   └── Event_CoinCraze.gd   ← NEW (concrete event)
```

### 2.2 Files to MODIFY

| File | Changes |
|---|---|
| `res://src/core/Main.gd` | Call `EventManager.register_event()` for each concrete event in `_ready()`. Wire `EventManager` lifecycle signals. |
| `res://project.godot` | Register `EventManager` as an Autoload: `EventManager="*res://src/events/EventManager.gd"` |

---

## SECTION 3: BASE EVENT — `BaseEvent.gd`

### 3.1 File Header and Class Declaration

`BaseEvent` is an abstract class. It uses `class_name BaseEvent` so that `EventManager` can store them as `BaseEvent` typed variables and call their virtual functions polymorphically.

```gdscript
# ==============================================================================
# BaseEvent.gd
# Path: res://src/events/BaseEvent.gd
# Role: Abstract base class for all live-ops events.
# DO NOT instantiate this class directly. Use concrete subclasses.
# Access pattern: Registered with EventManager via register_event().
# ==============================================================================
class_name BaseEvent
extends RefCounted
```

**Note:** `extends RefCounted` (not `Node`) is the correct choice because:
1. Events have no need for the scene tree — they are pure data/logic components.
2. `RefCounted` is lighter than `Node` and avoids the overhead of scene tree parenting.
3. `EventManager` holds them in typed arrays (`Array[BaseEvent]`).
4. They are automatically freed when `EventManager` removes them and no other references exist.

### 3.2 Properties (Instance Variables)

```gdscript
## Unique identifier string for this event. Used as the key in SaveLoadManager.event_flags.
## Set by the concrete subclass constructor or by EventManager on registration.
var event_id: String = ""

## Human-readable name of this event, shown in UI banners.
var event_name: String = "Unknown Event"

## Unix timestamp (seconds since epoch) when this event becomes active.
## Set at construction time by the system that activates the event.
var start_time: int = 0

## Unix timestamp when this event expires and becomes inactive.
var end_time: int = 0

## Whether this event is currently in its active window.
## Updated every frame by EventManager._process(). Read by UI to show banners.
var is_active: bool = false
```

### 3.3 Constructor (Virtual Initializer)

Concrete subclasses should override `_init_impl()` (not `_init`) to set their identity. `_init` is reserved by GDScript.

```gdscript
func _init_impl(p_event_id: String, p_event_name: String, p_start: int, p_end: int) -> void:
    event_id    = p_event_id
    event_name  = p_event_name
    start_time  = p_start
    end_time    = p_end
```

### 3.4 Virtual Functions

These are the hooks that `EventManager` calls at lifecycle boundaries. Concrete events override them to subscribe to signals, apply modifiers, or trigger UI updates.

```gdscript
## Called by EventManager when the event transitions from inactive → active.
## Override in subclasses to set up event effects (connect signals, apply modifiers).
## Default implementation does nothing.
func _on_start() -> void:
    pass


## Called by EventManager when the event transitions from active → inactive.
## Override in subclasses to tear down event effects (disconnect signals, remove modifiers).
## Default implementation does nothing.
func _on_end() -> void:
    pass
```

### 3.5 Utility Functions

```gdscript
## Returns the remaining duration of this event in seconds.
## Returns 0 if the event is already expired or inactive.
func get_remaining_seconds() -> int:
    if not is_active:
        return 0
    var now: int = int(Time.get_unix_time_from_system())
    return max(0, end_time - now)


## Returns a Dictionary summarizing the event state for logging/debugging.
func get_status() -> Dictionary:
    return {
        "event_id":   event_id,
        "event_name": event_name,
        "is_active":  is_active,
        "start_time": start_time,
        "end_time":   end_time,
        "remaining":  get_remaining_seconds()
    }
```

### 3.6 Full `BaseEvent.gd` Implementation

```gdscript
# ==============================================================================
# BaseEvent.gd
# Path: res://src/events/BaseEvent.gd
# Role: Abstract base class for all live-ops events.
# DO NOT instantiate this class directly. Use concrete subclasses.
# Access pattern: Registered with EventManager via register_event().
# ==============================================================================
class_name BaseEvent
extends RefCounted

## Unique identifier string for this event. Key in SaveLoadManager.event_flags.
var event_id: String = ""

## Human-readable name for UI banners.
var event_name: String = "Unknown Event"

## Unix timestamp when event becomes active.
var start_time: int = 0

## Unix timestamp when event expires.
var end_time: int = 0

## Whether this event is currently within its active window.
## Updated every frame by EventManager._process().
var is_active: bool = false


## Initializer. Concrete subclasses call this from their own _init.
## Not override of GDScript _init — GDScript _init takes no named parameters here.
func _init_impl(p_event_id: String, p_event_name: String, p_start: int, p_end: int) -> void:
    event_id   = p_event_id
    event_name = p_event_name
    start_time = p_start
    end_time   = p_end


## Called by EventManager when the event transitions inactive → active.
## Override in concrete subclasses to set up event effects.
func _on_start() -> void:
    pass


## Called by EventManager when the event transitions active → inactive.
## Override in concrete subclasses to tear down event effects.
func _on_end() -> void:
    pass


## Returns remaining duration in seconds. 0 if inactive or expired.
func get_remaining_seconds() -> int:
    if not is_active:
        return 0
    var now: int = int(Time.get_unix_time_from_system())
    return max(0, end_time - now)


## Returns a Dictionary summarizing current state for logging.
func get_status() -> Dictionary:
    return {
        "event_id":   event_id,
        "event_name": event_name,
        "is_active":  is_active,
        "start_time": start_time,
        "end_time":   end_time,
        "remaining":  get_remaining_seconds()
    }
```

---

## SECTION 4: EVENT MANAGER — `EventManager.gd`

`EventManager` is an **Autoload singleton** that acts as the central scheduler for all live-ops events. It polls system time every frame and manages the lifecycle of registered `BaseEvent` instances.

### 4.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# EventManager.gd
# Path: res://src/events/EventManager.gd
# Role: Autoload singleton — event scheduler and lifecycle manager.
# Access pattern: Autoload (registered in project.godot). Access via EventManager.
# DO NOT instantiate manually. All concrete events register themselves with this.
# ==============================================================================
extends Node
class_name EventManager
```

**Registration in `project.godot`:**

```godot
[autoload]
EventManager="*res://src/events/EventManager.gd"
```

### 4.2 Signals

```gdscript
## Emitted when an event transitions from inactive to active.
## UI layer (MainHUD) subscribes to show banner notifications.
signal event_started(event_id: String, event_name: String)

## Emitted when an event transitions from active to inactive.
signal event_ended(event_id: String, event_name: String)

## Emitted once per frame after all events have been checked.
## active_event_ids: Array of event_id strings that are currently active.
signal all_events_checked(active_event_ids: Array[String])
```

### 4.3 Variables

```gdscript
## All registered event instances. Keyed by event_id string.
## EventManager OWNS these instances — it is responsible for their lifecycle.
var _registered_events: Dictionary = {}

## Snapshot of the previous frame's active event IDs.
## Used to detect state transitions (active → inactive or inactive → active).
var _previous_active_ids: Array[String] = []
```

### 4.4 `_ready()` Function

```gdscript
func _ready() -> void:
    print("[EventManager] Initialized. Registered events: %d" % _registered_events.size())
```

### 4.5 `_process(delta: float)` — Scheduler Loop

**This is the heartbeat of the event system.** It runs every frame, compares system time against each event's start/end timestamps, and fires lifecycle callbacks when transitions occur.

```gdscript
func _process(_delta: float) -> void:
    var current_time: int = int(Time.get_unix_time_from_system())
    var currently_active_ids: Array[String] = []

    # ── Check each registered event ─────────────────────────────────────────
    for event_id in _registered_events:
        var event: BaseEvent = _registered_events[event_id]
        if event == null:
            continue

        var was_active: bool = event.is_active
        var should_be_active: bool = (current_time >= event.start_time) and (current_time < event.end_time)

        # ── Transition: inactive → active ─────────────────────────────────────
        if should_be_active and not was_active:
            event.is_active = true
            event._on_start()
            emit_signal("event_started", event.event_id, event.event_name)
            print("[EventManager] Event started: %s (%s)" % [event.event_name, event.event_id])

        # ── Transition: active → inactive ──────────────────────────────────────
        elif not should_be_active and was_active:
            event.is_active = false
            event._on_end()
            emit_signal("event_ended", event.event_id, event.event_name)
            print("[EventManager] Event ended: %s (%s)" % [event.event_name, event.event_id])

        # ── Update snapshot ──────────────────────────────────────────────────
        if event.is_active:
            currently_active_ids.append(event_id)

    # ── Emit per-frame summary signal ───────────────────────────────────────
    emit_signal("all_events_checked", currently_active_ids)
    _previous_active_ids = currently_active_ids
```

### 4.6 Public Registration API

#### `register_event(event: BaseEvent) -> bool`

Registers a concrete event instance with the scheduler. Call this once per event type during `Main._ready()`.

```gdscript
func register_event(event: BaseEvent) -> bool:
    if event == null:
        push_error("[EventManager] Cannot register null event.")
        return false

    if event.event_id.is_empty():
        push_error("[EventManager] Cannot register event with empty event_id.")
        return false

    if _registered_events.has(event.event_id):
        push_warning("[EventManager] Event '%s' already registered. Replacing." % event.event_id)

    _registered_events[event.event_id] = event
    print("[EventManager] Event registered: %s (%s) | Window: %d → %d" % [
        event.event_name, event.event_id, event.start_time, event.end_time
    ])
    return true
```

#### `unregister_event(event_id: String) -> bool`

Removes an event from the scheduler. Call this if an event type is deprecated.

```gdscript
func unregister_event(event_id: String) -> bool:
    if not _registered_events.has(event_id):
        push_warning("[EventManager] Cannot unregister unknown event: %s" % event_id)
        return false

    var event: BaseEvent = _registered_events[event_id]
    if event.is_active:
        event.is_active = false
        event._on_end()

    _registered_events.erase(event_id)
    print("[EventManager] Event unregistered: %s" % event_id)
    return true
```

#### `activate_event(event_id: String, duration_seconds: int) -> bool`

Dev/testing utility: activates an event immediately for a given duration. Writes to `SaveLoadManager.event_flags` so the activation survives a game restart.

```gdscript
func activate_event(event_id: String, duration_seconds: int) -> bool:
    if not _registered_events.has(event_id):
        push_error("[EventManager] Cannot activate unknown event: %s" % event_id)
        return false

    var now: int = int(Time.get_unix_time_from_system())
    var end: int = now + duration_seconds

    if not SaveLoadManager.event_flags.has(event_id):
        SaveLoadManager.event_flags[event_id] = {
            "is_active": false,
            "start_timestamp": 0,
            "end_timestamp": 0
        }

    SaveLoadManager.event_flags[event_id]["is_active"] = true
    SaveLoadManager.event_flags[event_id]["start_timestamp"] = now
    SaveLoadManager.event_flags[event_id]["end_timestamp"] = end

    var event: BaseEvent = _registered_events[event_id]
    event.start_time = now
    event.end_time   = end

    SaveLoadManager.save_game()
    print("[EventManager] Event '%s' activated for %d seconds (until %d)." % [
        event_id, duration_seconds, end
    ])
    return true
```

#### `deactivate_event(event_id: String) -> bool`

Dev/testing utility: immediately ends an event.

```gdscript
func deactivate_event(event_id: String) -> bool:
    if not _registered_events.has(event_id):
        push_error("[EventManager] Cannot deactivate unknown event: %s" % event_id)
        return false

    var event: BaseEvent = _registered_events[event_id]
    event.is_active  = false
    event.start_time = 0
    event.end_time   = 0

    if SaveLoadManager.event_flags.has(event_id):
        SaveLoadManager.event_flags[event_id]["is_active"]         = false
        SaveLoadManager.event_flags[event_id]["start_timestamp"]   = 0
        SaveLoadManager.event_flags[event_id]["end_timestamp"]     = 0
        SaveLoadManager.save_game()

    event._on_end()
    emit_signal("event_ended", event_id, event.event_name)
    print("[EventManager] Event '%s' deactivated." % event_id)
    return true
```

### 4.7 Public Query API

```gdscript
## Returns true if the given event_id is currently active.
func is_event_active(event_id: String) -> bool:
    if not _registered_events.has(event_id):
        return false
    var event: BaseEvent = _registered_events[event_id]
    return event.is_active


## Returns an Array of all currently active event IDs.
func get_active_events() -> Array[String]:
    var result: Array[String] = []
    for event_id in _registered_events:
        var event: BaseEvent = _registered_events[event_id]
        if event.is_active:
            result.append(event_id)
    return result


## Returns the BaseEvent instance for a given event_id, or null if not found.
func get_event(event_id: String) -> BaseEvent:
    return _registered_events.get(event_id, null)


## Returns a Dictionary of all registered events and their status.
func get_all_event_status() -> Dictionary:
    var result: Dictionary = {}
    for event_id in _registered_events:
        var event: BaseEvent = _registered_events[event_id]
        result[event_id] = event.get_status()
    return result
```

---

## SECTION 5: COIN CRAZE EVENT — `Event_CoinCraze.gd`

`Event_CoinCraze` is the first concrete event. When active, it doubles all coin rewards from slot spins by applying a post-process bonus to `SlotMachineLogic.spin_completed`.

### 5.1 File Header and Class Declaration

```gdscript
# ==============================================================================
# Event_CoinCraze.gd
# Path: res://src/events/Event_CoinCraze.gd
# Role: CoinCraze live-ops event. Doubles all coin spin rewards when active.
# DO NOT instantiate directly. Use EventManager.register_event() from Main.gd.
# ==============================================================================
class_name Event_CoinCraze
extends BaseEvent

## The coin reward multiplier applied while CoinCraze is active.
## 2.0 = double coins. 3.0 = triple coins.
## This value can be tuned without changing logic code.
const COIN_MULTIPLIER: float = 2.0

## Tracks whether we are currently connected to SlotMachineLogic.spin_completed.
## Prevents duplicate connections if _on_start() is called multiple times.
var _is_connected: bool = false
```

### 5.2 Constructor

Concrete events use `_init_impl()` to set their identity. `event_id` must match the key in `SaveLoadManager.event_flags` exactly.

```gdscript
func _init() -> void:
    # Fetch activation window from SaveLoadManager if available.
    # If the event was previously activated (persisted in save), use saved timestamps.
    # Otherwise, timestamps default to 0 (inactive) until activate_event() is called.
    var saved_flags: Dictionary = SaveLoadManager.event_flags.get("coin_craze", {})
    var saved_start: int  = int(saved_flags.get("start_timestamp", 0))
    var saved_end:   int  = int(saved_flags.get("end_timestamp", 0))
    var saved_active: bool = bool(saved_flags.get("is_active", false))

    _init_impl("coin_craze", "CoinCraze", saved_start, saved_end)

    # Sync is_active with persisted state immediately.
    var now: int = int(Time.get_unix_time_from_system())
    if saved_active and saved_end > now:
        is_active = true
```

### 5.3 `_on_start()` — Activation Hook

Called by `EventManager` when `is_active` transitions from `false` to `true`.

```gdscript
func _on_start() -> void:
    # Guard: prevent double-connection if _on_start() is called twice.
    if _is_connected:
        print("[Event_CoinCraze] Already connected. Ignoring duplicate _on_start().")
        return

    # Subscribe to SlotMachineLogic spin completion.
    # This is the ONLY signal Event_CoinCraze listens to.
    SlotMachineLogic.spin_completed.connect(_on_spin_completed)
    _is_connected = true

    print("[Event_CoinCraze] ACTIVE. Coin multiplier: x%.1f. Listening for spins." % COIN_MULTIPLIER)
```

### 5.4 `_on_end()` — Deactivation Hook

Called by `EventManager` when `is_active` transitions from `true` to `false`.

```gdscript
func _on_end() -> void:
    # Guard: prevent double-disconnection if _on_end() is called twice.
    if not _is_connected:
        print("[Event_CoinCraze] Already disconnected. Ignoring duplicate _on_end().")
        return

    # Unsubscribe from SlotMachineLogic to stop applying bonuses.
    if SlotMachineLogic.spin_completed.is_connected(_on_spin_completed):
        SlotMachineLogic.spin_completed.disconnect(_on_spin_completed)

    _is_connected = false
    print("[Event_CoinCraze] Deactivated. Coin bonus ended.")
```

### 5.5 `_on_spin_completed(result: Dictionary)` — The Bonus Logic

This is the heart of the coin multiplier. It runs as a post-process after `SlotMachineLogic` has already credited the base coins.

```gdscript
func _on_spin_completed(result: Dictionary) -> void:
    # ── Early exit guards ─────────────────────────────────────────────────
    if not is_active:
        return

    var reward_type: String = str(result.get("reward_type", ""))
    if reward_type != "coins":
        # Only coins are affected by CoinCraze.
        return

    var base_reward: int = int(result.get("reward_value", 0))
    if base_reward <= 0:
        return

    # ── Calculate bonus ───────────────────────────────────────────────────
    # The multiplier applies to the reward_value from SlotMachineLogic.
    # If SlotMachineLogic awarded 500 coins, CoinCraze adds (500 × 0.5) = 250 extra.
    # Total received by player = 500 + 250 = 750 = 500 × 1.5... but we want ×2.
    # Correct formula: extra = base_reward × (COIN_MULTIPLIER - 1.0)
    # If COIN_MULTIPLIER = 2.0, extra = base_reward × 1.0 = 100% bonus.
    var extra_coins: int = int(float(base_reward) * (COIN_MULTIPLIER - 1.0))

    if extra_coins <= 0:
        return

    # ── Apply bonus ──────────────────────────────────────────────────────
    SaveLoadManager.add_coins(extra_coins)
    SaveLoadManager.save_game()

    print("[Event_CoinCraze] CoinCraze bonus: +%,d extra coins! (base: %,d | total: %,d)" % [
        extra_coins, base_reward, base_reward + extra_coins
    ])
```

### 5.6 Full `Event_CoinCraze.gd` Implementation

```gdscript
# ==============================================================================
# Event_CoinCraze.gd
# Path: res://src/events/Event_CoinCraze.gd
# Role: CoinCraze live-ops event. Doubles all coin spin rewards when active.
# DO NOT instantiate directly. Use EventManager.register_event() from Main.gd.
# Pattern: Post-process. Subscribes to SlotMachineLogic.spin_completed.
#          Awards extra coins AFTER SlotMachineLogic has already credited base reward.
# ==============================================================================
class_name Event_CoinCraze
extends BaseEvent

## Coin multiplier while active. 2.0 = double, 3.0 = triple, etc.
const COIN_MULTIPLIER: float = 2.0

## Guard against duplicate signal connections.
var _is_connected: bool = false


func _init() -> void:
    # Restore persisted activation window if event was previously activated.
    var saved_flags: Dictionary = SaveLoadManager.event_flags.get("coin_craze", {})
    var saved_start:  int = int(saved_flags.get("start_timestamp", 0))
    var saved_end:    int = int(saved_flags.get("end_timestamp", 0))
    var saved_active: bool = bool(saved_flags.get("is_active", false))

    _init_impl("coin_craze", "CoinCraze", saved_start, saved_end)

    # Sync is_active with persisted state on boot.
    if saved_active:
        var now: int = int(Time.get_unix_time_from_system())
        if saved_end > now:
            is_active = true


func _on_start() -> void:
    if _is_connected:
        return

    SlotMachineLogic.spin_completed.connect(_on_spin_completed)
    _is_connected = true
    print("[Event_CoinCraze] ACTIVE. Coin multiplier: x%.1f." % COIN_MULTIPLIER)


func _on_end() -> void:
    if not _is_connected:
        return

    if SlotMachineLogic.spin_completed.is_connected(_on_spin_completed):
        SlotMachineLogic.spin_completed.disconnect(_on_spin_completed)

    _is_connected = false
    print("[Event_CoinCraze] Deactivated. Bonus ended.")


func _on_spin_completed(result: Dictionary) -> void:
    if not is_active:
        return

    var reward_type: String = str(result.get("reward_type", ""))
    if reward_type != "coins":
        return

    var base_reward: int = int(result.get("reward_value", 0))
    if base_reward <= 0:
        return

    # extra = base × (multiplier - 1.0)
    # COIN_MULTIPLIER=2.0 → bonus = base × 1.0 = 100% extra
    var extra_coins: int = int(float(base_reward) * (COIN_MULTIPLIER - 1.0))
    if extra_coins <= 0:
        return

    SaveLoadManager.add_coins(extra_coins)
    SaveLoadManager.save_game()

    print("[Event_CoinCraze] Bonus: +%,d coins (base: %,d)" % [extra_coins, base_reward])
```

---

## SECTION 6: MAIN SCENE UPDATES — `Main.gd`

`Main.gd` registers all concrete event classes with `EventManager` during `_ready()`. This is the only change required.

### 6.1 Updated `Main.gd`

Add the event registration block after the `NPCSimulator` instantiation:

```gdscript
func _ready() -> void:
    print("[Main] CoinMaster booting...")

    # ── 1. SlotMachineLogic ─────────────────────────────────────────────────
    slot_machine_logic = SlotMachineLogic.new()
    slot_machine_logic.name = "SlotMachineLogic"
    add_child(slot_machine_logic)
    print("[Main] SlotMachineLogic instantiated.")

    # ── 2. NPCSimulator ─────────────────────────────────────────────────────
    npc_simulator = NPCSimulator.new()
    npc_simulator.name = "NPCSimulator"
    add_child(npc_simulator)
    print("[Main] NPCSimulator instantiated.")

    # ── 3. SlotMachinePanel UI ───────────────────────────────────────────────
    var panel_scene: PackedScene = load("res://src/ui/SlotMachinePanel.tscn")
    if panel_scene != null:
        slot_machine_ui = panel_scene.instantiate() as SlotMachineUI
        if slot_machine_ui != null:
            add_child(slot_machine_ui)
            print("[Main] SlotMachinePanel loaded.")
        else:
            push_error("[Main] Failed to instantiate SlotMachinePanel.")
    else:
        push_error("[Main] SlotMachinePanel.tscn not found.")

    # ── 4. Event System (Step 7) ─────────────────────────────────────────────
    # Register all concrete event classes with EventManager.
    # Events restore their persisted activation window from SaveLoadManager.event_flags.
    var coin_craze: Event_CoinCraze = Event_CoinCraze.new()
    EventManager.register_event(coin_craze)
    print("[Main] Events registered.")

    # ── 5. Signal wiring ─────────────────────────────────────────────────────
    SaveLoadManager.game_loaded.connect(_on_save_game_loaded)

    if slot_machine_logic != null:
        slot_machine_logic.raid_triggered.connect(_on_raid_triggered)
        slot_machine_logic.attack_triggered.connect(_on_attack_triggered)

    print("[Main] CoinMaster ready.")
```

### 6.2 `project.godot` Autoload Update

Add `EventManager` to the `[autoload]` section:

```godot
[autoload]
SaveLoadManager="*res://src/utils/SaveLoadManager.gd"
EventManager="*res://src/events/EventManager.gd"
```

**Note:** `EventManager` must be registered **after** `SaveLoadManager` because `Event_CoinCraze._init()` reads from `SaveLoadManager.event_flags`. Godot autoloads are loaded in the order they appear in `project.godot`, so `SaveLoadManager` must come first.

---

## SECTION 7: EXTENDING WITH FUTURE EVENTS

The architecture is designed for extensibility. Adding new events requires only two steps:

### Step A: Create the concrete event class

```gdscript
# Event_VikingQuest.gd
class_name Event_VikingQuest
extends BaseEvent

const LOOT_BONUS_MULTIPLIER: float = 1.5

func _init() -> void:
    var saved_flags: Dictionary = SaveLoadManager.event_flags.get("viking_quest", {})
    _init_impl("viking_quest", "Viking Quest",
        int(saved_flags.get("start_timestamp", 0)),
        int(saved_flags.get("end_timestamp", 0))
    )
    if saved_flags.get("is_active", false):
        is_active = true

func _on_start() -> void:
    SlotMachineLogic.raid_triggered.connect(_on_raid_triggered)
    print("[Event_VikingQuest] ACTIVE. Raid loot bonus: x%.1f." % LOOT_BONUS_MULTIPLIER)

func _on_end() -> void:
    if SlotMachineLogic.raid_triggered.is_connected(_on_raid_triggered):
        SlotMachineLogic.raid_triggered.disconnect(_on_raid_triggered)
    print("[Event_VikingQuest] Deactivated.")

func _on_raid_triggered(count: int) -> void:
    # Apply loot bonus — post-process pattern
    pass
```

### Step B: Register in `Main.gd`

```gdscript
EventManager.register_event(Event_VikingQuest.new())
```

No changes to `EventManager` are needed for new event types.

---

## SECTION 8: ARCHITECTURAL CONSTRAINTS & GOTCHAS

### 8.1 Absolute Prohibitions

| Prohibition | Reason |
|---|---|
| Do NOT put event logic inside `EventManager._process()` | Scheduler only. All gameplay logic in concrete event classes. |
| Do NOT use `Timer` nodes for event scheduling | Use `_process(delta)` for polling. Timers add unnecessary node overhead. |
| Do NOT call `SaveLoadManager` mutators from `EventManager` | `EventManager` reads `event_flags` only. Events write to `event_flags`. |
| Do NOT instantiate `Event_CoinCraze` in `_ready()` without registering it | Unregistered events are never checked by the scheduler. |
| Do NOT connect signals in event constructors (`_init`) | Connect in `_on_start()`. Disconnect in `_on_end()`. Constructor is too early — `SlotMachineLogic` may not be initialized. |
| Do NOT use `is_instance_valid()` to check if an event exists | Events are `RefCounted`, not `Object`/`Node`. Use `_registered_events.has(event_id)`. |

### 8.2 Godot `_process` Gotchas

**Gotcha 1: `_process` runs every frame — keep it fast**
- The `_process` function runs on every frame (60+ times per second). Never do I/O, string concatenation in loops, or expensive operations here.
- Only compare timestamps and call virtual functions on state transitions. All heavy work happens in signal callbacks.

**Gotcha 2: `delta` parameter**
- `_process(delta)` receives the frame time in seconds. We don't use it in this implementation because event scheduling is time-based, not delta-based. Name it `_delta` to suppress unused-variable warnings.

**Gotcha 3: `_physics_process` vs `_process`**
- Use `_process()` for event scheduling. `_physics_process()` is locked to the physics tick (default 60 Hz) and may cause timing drift. `_process()` uses the display refresh rate.

### 8.3 Signal Connection Gotchas

**Gotcha 4: Always check `is_connected()` before disconnecting**
- Godot throws a runtime error if you call `disconnect()` on a signal that is not currently connected. Always guard:

```gdscript
if SlotMachineLogic.spin_completed.is_connected(_on_spin_completed):
    SlotMachineLogic.spin_completed.disconnect(_on_spin_completed)
```

**Gotcha 5: Signal connection is idempotent in Godot 4**
- Unlike Godot 3, connecting the same callable twice in Godot 4 does NOT duplicate the callback. However, disconnecting when not connected still throws an error.

**Gotcha 6: `is_connected()` returns `Callable` in Godot 4**
- In Godot 4, `signal.is_connected(method: Callable)` returns a `Callable` (truthy) or `null` (falsy), not a bool. Use it in a boolean context:

```gdscript
if SlotMachineLogic.spin_completed.is_connected(_on_spin_completed):
    # connected
```

### 8.4 RefCounted vs Node Gotchas

**Gotcha 7: `RefCounted` objects are auto-freed**
- When `EventManager` calls `_registered_events.erase(event_id)`, the `BaseEvent` instance's refcount drops to 0 and it is freed automatically.
- Do NOT hold additional references to event instances outside `EventManager`. It could prevent garbage collection.

**Gotcha 8: `RefCounted` has no `_ready()` or `_process()`**
- Lifecycle hooks are handled by `EventManager`. Events are pure logic classes, not scene nodes.

---

## SECTION 9: EDGE CASE REGISTRY

| Edge Case | Trigger Condition | Handling |
|---|---|---|
| **Event activated but SlotMachineLogic not yet ready** | Event activated before game fully loads | `_on_spin_completed` is called but `is_active` guard returns early. No action. |
| **Event active on game boot** | Event was active when player quit | `Event_CoinCraze._init()` reads persisted timestamps. `is_active` synced from save. `EventManager._process()` calls `_on_start()` immediately. |
| **Event expires while player is mid-spin** | Normal — event window ends during animation | `_on_end()` disconnects signal immediately. The in-flight spin's `spin_completed` fires without the event listener. Bonus not applied for that spin. |
| **Two events both try to modify coins** | Future multi-event stacking | Each event disconnects cleanly. `save_game()` called after each. No conflict. |
| **activate_event() called on already-active event** | Dev cheat code double-call | `activate_event()` overwrites `start_time`/`end_time` and saves. `EventManager._process()` sees the new window and does not re-fire `_on_start()`. |
| **`event_id` mismatch in concrete event vs SaveLoadManager** | Typo in event_id string | `SaveLoadManager.event_flags.get("wrong_id", {})` returns empty dict. Event initializes with 0 timestamps. Never activates. Add assert or log. |
| **Event `_on_start()` called while already connected** | Race condition on rapid activate/deactivate | `_is_connected` guard prevents double-connection. |
| **Event unregistered while active** | `unregister_event()` called mid-window | `unregister_event()` calls `_on_end()` before erasing. Signal disconnected cleanly. |
| **Event window is zero-length** | `start_time == end_time` | `should_be_active` condition is `current_time >= start AND current_time < end`. Zero-length windows are never active. |
| **System clock changed during session** | User adjusts system time | `Time.get_unix_time_from_system()` can jump forward or backward. `EventManager` handles negative deltas via the `>=` / `<` comparisons. `EventManager` does not use delta accumulation — it compares absolute timestamps. |

---

## SECTION 10: UNIT TEST VERIFICATION PROTOCOL

### Test A: Event Registration
1. Call `EventManager.register_event(Event_CoinCraze.new())`.
2. **Expected:** `EventManager.get_event("coin_craze")` returns the instance.
3. **Expected:** `EventManager.get_all_event_status()` contains `"coin_craze"`.

### Test B: Event Activation via activate_event()
1. Call `EventManager.activate_event("coin_craze", 3600)`.
2. Wait 2 frames.
3. **Expected:** `EventManager.is_event_active("coin_craze")` returns `true`.
4. **Expected:** `Event_CoinCraze` signal is connected to `_on_spin_completed`.

### Test C: Coin Bonus Applied
1. Set `SaveLoadManager.spins = 10`.
2. Activate `coin_craze` event.
3. Call `SlotMachineLogic.spin_reels(1)` with forced outcome `coins_small` (reward_value: 100).
4. **Expected:** `SlotMachineLogic` awards 100 coins via `add_coins(100)`.
5. **Expected:** `Event_CoinCraze._on_spin_completed` awards extra 100 coins (COIN_MULTIPLIER - 1.0 = 1.0).
6. **Expected:** Total coin gain = 200.

### Test D: Non-Coin Reward Ignored
1. Activate `coin_craze` event.
2. Call `spin_reels(1)` with forced outcome `spins_single`.
3. **Expected:** `Event_CoinCraze` does NOT call `add_coins()`.
4. **Expected:** Total coin balance unchanged.

### Test E: Event Expiry Cleanup
1. Activate `coin_craze` for 1 second.
2. Wait 2 seconds.
3. **Expected:** `EventManager.is_event_active("coin_craze")` returns `false`.
4. **Expected:** `SlotMachineLogic.spin_completed.is_connected(_on_spin_completed)` returns falsy.

### Test F: Event Persistence on Boot
1. Activate `coin_craze` for 3600 seconds. Call `SaveLoadManager.save_game()`.
2. Call `Event_CoinCraze.new()` (simulate new session).
3. **Expected:** `_init()` reads persisted timestamps. `is_active = true` if within window.

---

## SECTION 11: COMPLETION CHECKLIST

Before proceeding to Step 8, Cursor must confirm ALL of the following:

**File Existence:**
- [ ] `res://src/events/BaseEvent.gd` exists with `class_name BaseEvent`
- [ ] `res://src/events/EventManager.gd` exists with `class_name EventManager`
- [ ] `res://src/events/Event_CoinCraze.gd` exists with `class_name Event_CoinCraze`
- [ ] `project.godot` has `EventManager` registered in `[autoload]` section
- [ ] `SaveLoadManager` precedes `EventManager` in the `[autoload]` list

**BaseEvent:**
- [ ] `extends RefCounted` (NOT `Node`)
- [ ] Properties: `event_id`, `event_name`, `start_time`, `end_time`, `is_active`
- [ ] `func _init_impl(p_event_id, p_event_name, p_start, p_end)` declared
- [ ] Virtual `_on_start()` and `_on_end()` declared (stub implementation with `pass`)
- [ ] `get_remaining_seconds()` implemented
- [ ] `get_status()` returns a Dictionary

**EventManager:**
- [ ] `extends Node` (NOT `RefCounted` — must be a node for autoload)
- [ ] Registered as Autoload in `project.godot`
- [ ] `_process(delta)` polls every frame with `Time.get_unix_time_from_system()`
- [ ] Detects inactive → active transitions and calls `event._on_start()`
- [ ] Detects active → inactive transitions and calls `event._on_end()`
- [ ] Emits `event_started`, `event_ended`, and `all_events_checked` signals
- [ ] `register_event()` guards against null and duplicate event_id
- [ ] `unregister_event()` calls `_on_end()` before erasing
- [ ] `activate_event()` writes to both `BaseEvent` properties AND `SaveLoadManager.event_flags`
- [ ] `activate_event()` calls `save_game()` to persist activation
- [ ] `is_event_active()` returns false for unregistered event_id (no crash)
- [ ] `get_all_event_status()` returns a Dictionary keyed by event_id

**Event_CoinCraze:**
- [ ] `extends BaseEvent`
- [ ] `COIN_MULTIPLIER: float = 2.0` declared as a named constant
- [ ] `_init()` reads from `SaveLoadManager.event_flags.get("coin_craze", {})`
- [ ] `_init()` syncs `is_active` from persisted state on boot
- [ ] `_on_start()` connects to `SlotMachineLogic.spin_completed`
- [ ] `_on_start()` guarded by `_is_connected` flag
- [ ] `_on_end()` disconnects `spin_completed` signal
- [ ] `_on_end()` guarded by `_is_connected` flag
- [ ] `_on_spin_completed` checks `is_active` first (early return)
- [ ] `_on_spin_completed` only applies to `reward_type == "coins"`
- [ ] `_on_spin_completed` calculates `extra = base × (COIN_MULTIPLIER - 1.0)`
- [ ] `_on_spin_completed` calls `add_coins(extra)` and `save_game()`
- [ ] `is_connected()` check before `disconnect()` (Godot 4 safety)

**Main.gd Integration:**
- [ ] `Event_CoinCraze.new()` instantiated in `_ready()`
- [ ] `EventManager.register_event()` called for each event
- [ ] `Main.gd` does NOT import or instantiate `EventManager` — it is already global

**Separation of Concerns:**
- [ ] `EventManager` contains ZERO coin multiplier logic
- [ ] `EventManager` contains ZERO references to `SlotMachineLogic` outcome types
- [ ] `BaseEvent` contains ZERO concrete game effects
- [ ] `Event_CoinCraze` does NOT call `SlotMachineLogic` mutators directly

**Static Typing:**
- [ ] All variables have explicit type annotations
- [ ] All function parameters have type annotations
- [ ] All function return types declared (`: void`, `: bool`, `: int`, `: Dictionary`, `: Array[String]`)

**Logging:**
- [ ] `EventManager._ready()` prints initialization message
- [ ] `EventManager.register_event()` prints event name, id, and window
- [ ] `EventManager._process()` prints transition messages (start/end)
- [ ] `Event_CoinCraze._on_start()` prints "ACTIVE" with multiplier
- [ ] `Event_CoinCraze._on_end()` prints "Deactivated"
- [ ] `Event_CoinCraze._on_spin_completed()` prints bonus amount

**DO NOT proceed to Step 8 until this checklist is fully verified.**

---

## SECTION 12: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 8 will build `res://src/core/ShopManager.gd` to handle the in-game shop. `ShopManager` manages one-time offers (single-purchase items) and recurring spin packs (replenishing purchases). It reads from `shop_items.json` (created in Step 1) and emits `offer_purchased` and `offer_expired` signals. Step 8 also builds the shop UI panel (`ShopUI.gd` and `ShopPanel.tscn`) that displays available offers, handles purchase confirmation, and wires to `SaveLoadManager` for coin deduction and spin grant.
