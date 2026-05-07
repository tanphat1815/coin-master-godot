# ==============================================================================
# MainHUD.gd
# Path: res://src/ui/MainHUD.gd
# Role: Persistent top-screen resource counters. Pure View — zero game logic.
# Access pattern: Attached to a CanvasLayer/HBoxContainer node in Main.tscn.
# Signals: Subscribes to SaveLoadManager signals. Emits no signals.
# ==============================================================================
extends Control
class_name MainHUD

var _coin_label: Label
var _spin_label: Label
var _shield_label: Label


func _ready() -> void:
	_coin_label   = $LeftHBox/CoinPanel/Margin/HBox/CoinLabel   as Label
	_spin_label   = $RightHBox/SpinPanel/SpinLabel             as Label
	_shield_label = $RightHBox/ShieldPanel/ShieldLabel           as Label

	if _coin_label == null:
		push_warning("[MainHUD] CoinLabel not found at new path.")
	if _spin_label == null:
		push_warning("[MainHUD] SpinLabel not found at new path.")
	if _shield_label == null:
		push_warning("[MainHUD] ShieldLabel not found at new path.")

	SaveLoadManager.coins_changed.connect(_on_coins_changed)
	SaveLoadManager.spins_changed.connect(_on_spins_changed)
	SaveLoadManager.shields_changed.connect(_on_shields_changed)

	_update_coin_label(SaveLoadManager.coins)
	_update_spin_label(SaveLoadManager.spins)
	_update_shield_label(SaveLoadManager.shields)

	print("[MainHUD] Initialized. Coins: %d | Spins: %d | Shields: %d" % [
		SaveLoadManager.coins, SaveLoadManager.spins, SaveLoadManager.shields
	])


func _exit_tree() -> void:
	if SaveLoadManager:
		if SaveLoadManager.coins_changed.has_connections():
			SaveLoadManager.coins_changed.disconnect(_on_coins_changed)
		if SaveLoadManager.spins_changed.has_connections():
			SaveLoadManager.spins_changed.disconnect(_on_spins_changed)
		if SaveLoadManager.shields_changed.has_connections():
			SaveLoadManager.shields_changed.disconnect(_on_shields_changed)


# ─── Signal Callbacks ────────────────────────────────────────────────────────────

func _on_coins_changed(new_value: int) -> void:
	_update_coin_label(new_value)


func _on_spins_changed(new_value: int) -> void:
	_update_spin_label(new_value)


func _on_shields_changed(new_value: int) -> void:
	_update_shield_label(new_value)


# ─── Label Update Helpers ────────────────────────────────────────────────────────

func _update_coin_label(value: int) -> void:
	if _coin_label != null:
		_coin_label.text = _format_large_number(value)


func _update_spin_label(value: int) -> void:
	if _spin_label != null:
		_spin_label.text = _format_large_number(value)


func _update_shield_label(value: int) -> void:
	if _shield_label != null:
		_shield_label.text = "%d/5" % value


func _format_large_number(n: int) -> String:
	if n >= 1_000_000_000:
		return "%.1fB" % (n / 1_000_000_000.0)
	if n >= 1_000_000:
		return "%.1fM" % (n / 1_000_000.0)
	if n >= 1_000:
		return "%.1fK" % (n / 1_000.0)
	return str(n)
