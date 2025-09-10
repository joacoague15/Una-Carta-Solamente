extends Node2D
class_name Player

@onready var sprite: Sprite2D = $Sprite2D
@onready var tween: Tween = null

@export_range(0.3, 1.2, 0.05) var fill := 0.85  # cuánto “llena” la celda

func _ready() -> void:
	# crear Tween una sola vez
	tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	if sprite.texture:
		var tex := sprite.texture.get_size()
		var target := Vector2(96, 96) * fill  # valor por defecto hasta que llames set_cell
		var s := Vector2(target.x / tex.x, target.y / tex.y)
		sprite.scale = s
	sprite.centered = true

func set_cell(cell: Vector2i, cell_size: Vector2i, animate: bool = true) -> void:
	var target_pos = Vector2(
		cell.x * cell_size.x + cell_size.x * 0.5,
		cell.y * cell_size.y + cell_size.y * 0.5
	)

	if animate and tween:  # mover suavemente
		tween.kill()  # matar animaciones previas
		tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "position", target_pos, 0.25) # 0.25s duración
	else:  # teletransporte instantáneo
		position = target_pos

	# escalar para que “entre” en la celda
	if sprite.texture:
		var tex := sprite.texture.get_size()
		var target := Vector2(cell_size) * fill
		var s := Vector2(target.x / tex.x, target.y / tex.y)
		sprite.scale = s
