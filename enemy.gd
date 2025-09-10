extends Node2D
class_name Enemy

@onready var sprite: Sprite2D = $Sprite2D
@onready var tween: Tween = null

@export_range(0.3, 1.2, 0.05) var fill := 0.85
@export var texture: Texture2D

var _last_cell_size: Vector2i = Vector2i(96, 96)

func _ready() -> void:
	tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	if texture:
		sprite.texture = texture
	_rescale_to_cell()
	sprite.centered = true

func set_texture(tex: Texture2D) -> void:
	texture = tex
	sprite.texture = tex
	_rescale_to_cell()

func set_cell(cell: Vector2i, cell_size: Vector2i, animate: bool = true) -> void:
	_last_cell_size = cell_size
	var target_pos = Vector2(
		cell.x * cell_size.x + cell_size.x * 0.5,
		cell.y * cell_size.y + cell_size.y * 0.5
	)

	if animate and tween:
		tween.kill()
		tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "position", target_pos, 0.25)
	else:
		position = target_pos

	_rescale_to_cell()

func _rescale_to_cell() -> void:
	if sprite.texture:
		var tex_size := sprite.texture.get_size()
		var target := Vector2(_last_cell_size) * fill
		var s := Vector2(target.x / tex_size.x, target.y / tex_size.y)
		sprite.scale = s
