# ==============================================================================
# CardWidget.gd
# Path: res://src/ui/CardWidget.gd
# Role: Individual card display widget for the card collection/chest reveal.
# Zero game logic — purely visual.
# ==============================================================================
class_name CardWidget
extends PanelContainer

var _card_texture: TextureRect
var _star_label: Label
var _name_label: Label

var _card_id: String = ""
var _star_count: int = 1


func _ready() -> void:
	_card_texture = get_node_or_null("CardTexture") as TextureRect
	_star_label  = get_node_or_null("StarLabel") as Label
	_name_label  = get_node_or_null("NameLabel") as Label


func set_card_data(card_data: Dictionary) -> void:
	_card_id = str(card_data.get("id", ""))

	var tex_path: String = str(card_data.get("texture_path", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		if _card_texture != null:
			_card_texture.texture = load(tex_path) as Texture2D

	var name_text: String = str(card_data.get("name", "Card"))
	if _name_label != null:
		_name_label.text = name_text

	_star_count = int(card_data.get("star", 1))
	if _star_label != null:
		_star_label.text = _format_stars(_star_count)


func _format_stars(count: int) -> String:
	var stars: String = ""
	for i in range(count):
		stars += "★"
	return stars
