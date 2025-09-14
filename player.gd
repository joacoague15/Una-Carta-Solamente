extends Node2D
class_name Player

@onready var sprite: Sprite2D = $Sprite2D
@onready var tween: Tween = null

@export_range(0.3, 1.2, 0.05) var fill := 1.0

var _last_cell_size: Vector2i = Vector2i(96, 96)

func _ready() -> void:
	tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	if sprite.texture:
		var tex := sprite.texture.get_size()
		var target := Vector2(_last_cell_size) * fill
		sprite.scale = target / tex
	sprite.centered = true

func set_stats(_mv:int, _atk:int, _def:int, _rng:int) -> void:
	# Intencionalmente vacío (ya no mostramos badges en el Player)
	pass

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

	# Rescalar sprite al tamaño de la celda
	if sprite.texture:
		var tex := sprite.texture.get_size()
		var target := Vector2(_last_cell_size) * fill
		sprite.scale = target / tex
