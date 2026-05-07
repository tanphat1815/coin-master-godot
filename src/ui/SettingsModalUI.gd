# ==============================================================================
# SettingsModalUI.gd
# Path: res://src/ui/SettingsModalUI.gd
# Role: Settings modal overlay — sound/music toggles, close button.
# ZERO game math. Only controls UI state.
# ==============================================================================
class_name SettingsModalUI
extends Control

var _sound_toggle: CheckButton
var _music_toggle: CheckButton
var _close_button: Button
var _title_label: Label

var _sound_enabled: bool = true
var _music_enabled: bool = true


func _ready() -> void:
	_sound_toggle = get_node_or_null("VBox/SoundToggle") as CheckButton
	_music_toggle = get_node_or_null("VBox/MusicToggle") as CheckButton
	_close_button = get_node_or_null("VBox/CloseBtn") as Button
	_title_label  = get_node_or_null("VBox/TitleLabel") as Label

	if _sound_toggle != null:
		_sound_toggle.toggled.connect(_on_sound_toggled)
		_sound_toggle.button_pressed = _sound_enabled
	if _music_toggle != null:
		_music_toggle.toggled.connect(_on_music_toggled)
		_music_toggle.button_pressed = _music_enabled
	if _close_button != null:
		_close_button.pressed.connect(_on_close_pressed)

	# Modal behavior: close on background click.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	print("[SettingsModalUI] Ready.")


func open() -> void:
	visible = true
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	get_tree().paused = true


func close() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	await tween.finished
	visible = false
	get_tree().paused = false


func _on_sound_toggled(toggled: bool) -> void:
	_sound_enabled = toggled
	print("[SettingsModalUI] Sound %s" % ("ON" if toggled else "OFF"))


func _on_music_toggled(toggled: bool) -> void:
	_music_enabled = toggled
	print("[SettingsModalUI] Music %s" % ("ON" if toggled else "OFF"))


func _on_close_pressed() -> void:
	close()
