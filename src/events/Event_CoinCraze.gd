# ==============================================================================
# Event_CoinCraze.gd
# Path: res://src/events/Event_CoinCraze.gd
# Role: CoinCraze live-ops event. Doubles all coin spin rewards when active.
# DO NOT instantiate directly. Use EventManager.register_event() from Main.gd.
# Pattern: Post-process. Subscribes to SlotMachineLogic.spin_completed.
#           Awards extra coins AFTER SlotMachineLogic has already credited base reward.
# ==============================================================================
class_name Event_CoinCraze
extends BaseEvent

const COIN_MULTIPLIER: float = 2.0

var _is_connected: bool = false


func _init() -> void:
	var saved_flags: Dictionary = SaveLoadManager.event_flags.get("coin_craze", {})
	var saved_start:  int = int(saved_flags.get("start_timestamp", 0))
	var saved_end:    int = int(saved_flags.get("end_timestamp", 0))
	var saved_active: bool = bool(saved_flags.get("is_active", false))

	_init_impl("coin_craze", "CoinCraze", saved_start, saved_end)

	if saved_active:
		var now: int = int(Time.get_unix_time_from_system())
		if saved_end > now:
			is_active = true


func _on_start() -> void:
	if _is_connected:
		print("[Event_CoinCraze] Already connected. Ignoring duplicate _on_start().")
		return

	var instance: SlotMachineLogic = SlotMachineLogic.get_instance()
	if instance == null:
		push_error("[Event_CoinCraze] SlotMachineLogic not yet instantiated. Cannot connect signal.")
		return

	instance.spin_completed.connect(_on_spin_completed)
	_is_connected = true
	print("[Event_CoinCraze] ACTIVE. Coin multiplier: x%.1f." % COIN_MULTIPLIER)


func _on_end() -> void:
	if not _is_connected:
		print("[Event_CoinCraze] Already disconnected. Ignoring duplicate _on_end().")
		return

	var instance: SlotMachineLogic = SlotMachineLogic.get_instance()
	if instance != null and instance.spin_completed.is_connected(_on_spin_completed):
		instance.spin_completed.disconnect(_on_spin_completed)

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

	var extra_coins: int = int(float(base_reward) * (COIN_MULTIPLIER - 1.0))
	if extra_coins <= 0:
		return

	SaveLoadManager.add_coins(extra_coins)
	SaveLoadManager.save_game()

	print("[Event_CoinCraze] Bonus: +%,d coins (base: %,d)" % [extra_coins, base_reward])
