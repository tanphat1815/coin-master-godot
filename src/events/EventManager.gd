# ==============================================================================
# EventManager.gd
# Path: res://src/events/EventManager.gd
# Role: Autoload singleton — event scheduler and lifecycle manager.
# Access pattern: Autoload (registered in project.godot). Access via EventManager.
# DO NOT instantiate manually. All concrete events register themselves with this.
# ==============================================================================
extends Node

signal event_started(event_id: String, event_name: String)
signal event_ended(event_id: String, event_name: String)
signal all_events_checked(active_event_ids: Array[String])

var _registered_events: Dictionary = {}
var _previous_active_ids: Array[String] = []


func _ready() -> void:
	print("[EventManager] Initialized. Registered events: %d" % _registered_events.size())


func _process(_delta: float) -> void:
	var current_time: int = int(Time.get_unix_time_from_system())
	var currently_active_ids: Array[String] = []

	for event_id in _registered_events:
		var event: BaseEvent = _registered_events[event_id]
		if event == null:
			continue

		var was_active: bool = event.is_active
		var should_be_active: bool = (current_time >= event.start_time) and (current_time < event.end_time)

		if should_be_active and not was_active:
			event.is_active = true
			event._on_start()
			emit_signal("event_started", event.event_id, event.event_name)
			print("[EventManager] Event started: %s (%s)" % [event.event_name, event.event_id])

		elif not should_be_active and was_active:
			event.is_active = false
			event._on_end()
			emit_signal("event_ended", event.event_id, event.event_name)
			print("[EventManager] Event ended: %s (%s)" % [event.event_name, event.event_id])

		if event.is_active:
			currently_active_ids.append(event_id)

	emit_signal("all_events_checked", currently_active_ids)
	_previous_active_ids = currently_active_ids


# ─── Registration API ─────────────────────────────────────────────────────────────

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


func deactivate_event(event_id: String) -> bool:
	if not _registered_events.has(event_id):
		push_error("[EventManager] Cannot deactivate unknown event: %s" % event_id)
		return false

	var event: BaseEvent = _registered_events[event_id]
	event.is_active  = false
	event.start_time = 0
	event.end_time   = 0

	if SaveLoadManager.event_flags.has(event_id):
		SaveLoadManager.event_flags[event_id]["is_active"]        = false
		SaveLoadManager.event_flags[event_id]["start_timestamp"]  = 0
		SaveLoadManager.event_flags[event_id]["end_timestamp"]   = 0
		SaveLoadManager.save_game()

	event._on_end()
	emit_signal("event_ended", event_id, event.event_name)
	print("[EventManager] Event '%s' deactivated." % event_id)
	return true


# ─── Query API ──────────────────────────────────────────────────────────────────

func is_event_active(event_id: String) -> bool:
	if not _registered_events.has(event_id):
		return false
	var event: BaseEvent = _registered_events[event_id]
	return event.is_active


func get_active_events() -> Array[String]:
	var result: Array[String] = []
	for event_id in _registered_events:
		var event: BaseEvent = _registered_events[event_id]
		if event.is_active:
			result.append(event_id)
	return result


func get_event(event_id: String) -> BaseEvent:
	return _registered_events.get(event_id, null)


func get_all_event_status() -> Dictionary:
	var result: Dictionary = {}
	for event_id in _registered_events:
		var event: BaseEvent = _registered_events[event_id]
		result[event_id] = event.get_status()
	return result
