# ==============================================================================
# BaseEvent.gd
# Path: res://src/events/BaseEvent.gd
# Role: Abstract base class for all live-ops events.
# DO NOT instantiate this class directly. Use concrete subclasses.
# Access pattern: Registered with EventManager via register_event().
# ==============================================================================
class_name BaseEvent
extends RefCounted

var event_id: String = ""
var event_name: String = "Unknown Event"
var start_time: int = 0
var end_time: int = 0
var is_active: bool = false


func _init_impl(p_event_id: String, p_event_name: String, p_start: int, p_end: int) -> void:
    event_id   = p_event_id
    event_name = p_event_name
    start_time = p_start
    end_time   = p_end


func _on_start() -> void:
    pass


func _on_end() -> void:
    pass


func get_remaining_seconds() -> int:
    if not is_active:
        return 0
    var now: int = int(Time.get_unix_time_from_system())
    return max(0, end_time - now)


func get_status() -> Dictionary:
    return {
        "event_id":   event_id,
        "event_name": event_name,
        "is_active":  is_active,
        "start_time": start_time,
        "end_time":   end_time,
        "remaining":  get_remaining_seconds()
    }
