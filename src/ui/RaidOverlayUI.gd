# RaidOverlayUI.gd
class_name RaidOverlayUI
extends Control

var _hole_1: TextureButton
var _hole_2: TextureButton
var _hole_3: TextureButton
var _result_label: Label
var _ground_view: TextureRect

var _current_result: Dictionary = {}
var _dig_slots_remaining: int = 0
var _raid_in_progress: bool = false

func _ready() -> void:
    _hole_1 = get_node_or_null("Hole1") as TextureButton
    _hole_2 = get_node_or_null("Hole2") as TextureButton
    _hole_3 = get_node_or_null("Hole3") as TextureButton
    _result_label = get_node_or_null("ResultLabel") as Label
    _ground_view = get_node_or_null("GroundView") as TextureRect
    if _hole_1 != null: _hole_1.pressed.connect(_on_hole_1_pressed)
    if _hole_2 != null: _hole_2.pressed.connect(_on_hole_2_pressed)
    if _hole_3 != null: _hole_3.pressed.connect(_on_hole_3_pressed)
    if _result_label != null: _result_label.text = ""
    visible = false
    print("[RaidOverlayUI] Ready.")

func show_raid(result: Dictionary) -> void:
    _current_result = result
    _dig_slots_remaining = int(str(result.get("raid_dig_slots", "1")))
    _raid_in_progress = true
    visible = true
    modulate.a = 0.0
    var tween_in: Tween = create_tween()
    tween_in.tween_property(self, "modulate:a", 1.0, 0.25)
    await tween_in.finished
    if _result_label != null:
        var slot_word: String = "s" if _dig_slots_remaining != 1 else ""
        _result_label.text = "DIG! %d slot%s remaining" % [_dig_slots_remaining, slot_word]
    _enable_all_holes()

func _enable_all_holes() -> void:
    if _hole_1 != null: _hole_1.disabled = false
    if _hole_2 != null: _hole_2.disabled = false
    if _hole_3 != null: _hole_3.disabled = false

func _disable_all_holes() -> void:
    if _hole_1 != null: _hole_1.disabled = true
    if _hole_2 != null: _hole_2.disabled = true
    if _hole_3 != null: _hole_3.disabled = true

func _on_hole_1_pressed() -> void: _dig_from_hole(1)
func _on_hole_2_pressed() -> void: _dig_from_hole(2)
func _on_hole_3_pressed() -> void: _dig_from_hole(3)

func _dig_from_hole(hole_number: int) -> void:
    if not _raid_in_progress: return
    _dig_slots_remaining -= 1
    var hole: TextureButton
    if hole_number == 1: hole = _hole_1
    elif hole_number == 2: hole = _hole_2
    elif hole_number == 3: hole = _hole_3
    if hole != null: _dig_hole_animation(hole)
    if _result_label != null:
        if _dig_slots_remaining > 0:
            var slot_word: String = "s" if _dig_slots_remaining != 1 else ""
            _result_label.text = "DIG! %d slot%s remaining" % [_dig_slots_remaining, slot_word]
        else:
            _result_label.text = "Digging..."
    if _dig_slots_remaining <= 0: _finish_raid()

func _dig_hole_animation(hole: TextureButton) -> void:
    var tween: Tween = create_tween()
    tween.tween_property(hole, "scale", Vector2(0.7, 0.7), 0.1).set_trans(Tween.TRANS_BACK)
    tween.tween_property(hole, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC)

func _finish_raid() -> void:
    _raid_in_progress = false
    _disable_all_holes()
    if _result_label != null: _result_label.text = "Raid Complete! Loot collected!"
    await get_tree().create_timer(2.0).timeout
    _dismiss_overlay()

func _dismiss_overlay() -> void:
    var tween_out: Tween = create_tween()
    tween_out.tween_property(self, "modulate:a", 0.0, 0.3)
    await tween_out.finished
    visible = false
    _current_result = {}
    print("[RaidOverlayUI] Raid overlay dismissed.")
