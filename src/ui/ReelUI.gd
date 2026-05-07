# ==============================================================================
# ReelUI.gd
# Path: res://src/ui/ReelUI.gd
# Role: Per-reel tween-based spin animation.
# Each reel is an independent VBoxContainer with 3 TextureRects.
# This script drives the visual scroll — zero game math.
# ==============================================================================
class_name ReelUI
extends VBoxContainer

## The icon textures for each reel position.
var _icon_top: TextureRect
var _icon_mid: TextureRect
var _icon_bot: TextureRect

## Textures for each reward type.
var _tex_coin:   Texture2D
var _tex_energy:  Texture2D
var _tex_shield:  Texture2D
var _tex_attack:  Texture2D
var _tex_raid:   Texture2D

## The predetermined result for this reel.
var _target_texture: Texture2D = null

## Height of one symbol slot in pixels.
const STRIP_HEIGHT: float = 160.0

## Whether this reel is currently animating.
var _is_spinning: bool = false


func _ready() -> void:
	_icon_top = get_node_or_null("Symbol_Top") as TextureRect
	_icon_mid = get_node_or_null("Symbol_Mid") as TextureRect
	_icon_bot = get_node_or_null("Symbol_Bot") as TextureRect

	_preload_textures()
	_set_random_initial_state()


func _preload_textures() -> void:
	_tex_coin  = preload("res://assets/sprites/ui/coin.svg")
	_tex_energy = preload("res://assets/sprites/ui/energy.svg")
	_tex_shield = preload("res://assets/sprites/ui/shield.svg")
	_tex_attack = preload("res://assets/sprites/ui/attack.svg")
	_tex_raid  = preload("res://assets/sprites/ui/raid.svg")


func _set_random_initial_state() -> void:
	var all_textures: Array[Texture2D] = [_tex_coin, _tex_energy, _tex_shield, _tex_attack, _tex_raid]
	if _icon_top != null:
		_icon_top.texture = all_textures[randi() % all_textures.size()]
	if _icon_mid != null:
		_icon_mid.texture = all_textures[randi() % all_textures.size()]
	if _icon_bot != null:
		_icon_bot.texture = all_textures[randi() % all_textures.size()]


func get_texture_for_type(type: String) -> Texture2D:
	match type:
		"coins":  return _tex_coin
		"spins":  return _tex_energy
		"shield": return _tex_shield
		"attack": return _tex_attack
		"raid":   return _tex_raid
	return _tex_coin


## Kick off the spin animation with a staggered delay.
## delay: seconds to wait before this reel starts spinning.
func start_spin(target_type: String, delay: float) -> void:
	_target_texture = get_texture_for_type(target_type)
	_is_spinning = true
	_run_tween_sequence(delay)


func _run_tween_sequence(delay: float) -> void:
	# Phase 1: Ease-in — slow scroll-up to simulate inertia spin-up.
	var t1: Tween = create_tween()
	t1.set_parallel(true)
	t1.tween_property(self, "position:y", -STRIP_HEIGHT * 2.0, 0.3).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Phase 2: Fast looping — cycle symbols rapidly.
	for _j in range(8):
		t1.tween_property(self, "position:y",
			position.y - STRIP_HEIGHT, 0.05).set_trans(Tween.TRANS_LINEAR)

	await get_tree().create_timer(delay + 0.4).timeout

	# Pre-snap: set the middle texture to the target before snapping.
	if _icon_mid != null and _target_texture != null:
		_icon_mid.texture = _target_texture

	# Phase 3: Elastic snap to final position.
	var t2: Tween = create_tween()
	t2.set_ease(Tween.EASE_OUT)
	t2.set_trans(Tween.TRANS_ELASTIC)
	t2.tween_property(self, "position:y", 0.0, 0.45)

	await t2.finished
	_is_spinning = false


func is_spinning() -> bool:
	return _is_spinning
