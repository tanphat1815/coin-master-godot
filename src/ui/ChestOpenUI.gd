# ==============================================================================
# ChestOpenUI.gd
# Path: res://src/ui/ChestOpenUI.gd
# Role: Chest opening animation with AnimationPlayer and CPUParticles2D burst.
# ZERO game math. All data flows in via CardManager.chest_opened_batch signal.
# ==============================================================================
class_name ChestOpenUI
extends Control

var _chest_sprite: TextureRect
var _anim_player: AnimationPlayer
var _burst_particles: CPUParticles2D
var _card_grid: GridContainer
var _chest_type_label: Label

var _pending_cards: Array = []
var _current_chest_type: String = ""


func _ready() -> void:
	_chest_sprite     = get_node_or_null("ChestSprite") as TextureRect
	_anim_player     = get_node_or_null("ChestAnimPlayer") as AnimationPlayer
	_burst_particles = get_node_or_null("BurstParticles") as CPUParticles2D
	_card_grid       = get_node_or_null("CardRevealGrid") as GridContainer
	_chest_type_label = get_node_or_null("ChestTypeLabel") as Label

	if _burst_particles != null:
		_burst_particles.emitting = false

	visible = false
	_register_card_manager_signal()
	print("[ChestOpenUI] Ready.")


func _register_card_manager_signal() -> void:
	# Connect to CardManager signal so this overlay auto-triggers when chest is opened.
	var cm: Node = get_node_or_null("/root/Main/CardManager")
	if cm != null and cm.has_signal("chest_opened_batch"):
		if not cm.chest_opened_batch.is_connected(_on_cards_received):
			cm.chest_opened_batch.connect(_on_cards_received)


func _on_cards_received(cards: Array) -> void:
	_pending_cards = cards
	_start_chest_sequence()


func _start_chest_sequence() -> void:
	visible = true

	if _card_grid != null:
		for child in _card_grid.get_children():
			child.queue_free()

	if _burst_particles != null:
		_burst_particles.emitting = false

	modulate.a = 0.0
	var tween_in: Tween = create_tween()
	tween_in.tween_property(self, "modulate:a", 1.0, 0.2)
	await tween_in.finished

	# Shake phase.
	if _anim_player != null and _anim_player.has_animation("Shake"):
		_anim_player.play("Shake")
	else:
		await _manual_shake()
		_on_shake_complete()


func _manual_shake() -> void:
	if _chest_sprite == null:
		return
	var original_pos: Vector2 = _chest_sprite.position
	var tween: Tween = create_tween()
	for i in range(6):
		var angle: float = 0.08 if (i % 2 == 0) else -0.08
		var scale_val: float = 1.05 if i == 3 else 1.0
		tween.tween_property(_chest_sprite, "rotation", angle, 0.1)
		tween.parallel().tween_property(_chest_sprite, "scale", Vector2(scale_val, 2.0 - scale_val), 0.1)
	await tween.finished
	_chest_sprite.position = original_pos
	_chest_sprite.rotation = 0.0
	_chest_sprite.scale = Vector2(1.0, 1.0)


func _on_shake_complete() -> void:
	if _anim_player != null and _anim_player.has_animation("Burst"):
		_anim_player.play("Burst")
	else:
		_on_burst_complete()


func _on_burst_complete() -> void:
	_spawn_card_reveals(_pending_cards)

	var dismiss_delay: float = maxf(2.0, _pending_cards.size() * 0.12 + 1.5)
	await get_tree().create_timer(dismiss_delay).timeout
	_dismiss_overlay()


func _spawn_card_reveals(cards: Array) -> void:
	for i in range(cards.size()):
		var card_data: Dictionary = cards[i] as Dictionary
		var card_rect: TextureRect = _spawn_card_widget(card_data)
		if _card_grid != null:
			_card_grid.add_child(card_rect)

		card_rect.scale = Vector2(0.0, 0.0)
		card_rect.modulate.a = 0.0

		var tween: Tween = create_tween()
		tween.set_delay(i * 0.12)
		tween.tween_property(card_rect, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card_rect, "modulate:a", 1.0, 0.2)


func _spawn_card_widget(card_data: Dictionary) -> TextureRect:
	var card_rect: TextureRect = TextureRect.new()
	card_rect.custom_minimum_size = Vector2(80.0, 110.0)
	card_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL

	var tex_path: String = str(card_data.get("texture_path", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		card_rect.texture = load(tex_path) as Texture2D
	else:
		card_rect.modulate = Color(0.5, 0.5, 0.5, 1.0)

	return card_rect


func _dismiss_overlay() -> void:
	var tween_out: Tween = create_tween()
	tween_out.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween_out.finished
	visible = false
	_pending_cards = []
	_current_chest_type = ""
	print("[ChestOpenUI] Chest overlay dismissed.")
