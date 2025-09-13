extends Node2D
class_name Player

@onready var sprite: Sprite2D = $Sprite2D
@onready var tween: Tween = null

@export_range(0.3, 1.2, 0.05) var fill := 1  # cuánto “llena” la celda el sprite principal

@export var badge_y_offset := -4.0      # desplaza todos los badges un poco hacia arriba (negativo = arriba)
@export var badge_x_offset := -4.0      # desplaza todos los badges un poco hacia la izquierda (negativo = izquierda)
@export var badge_gap := 2.0            # separación entre icono y número dentro del badge

# Sprites de esquina (asignalos en el Inspector)
@export var icon_mv: Texture2D
@export var icon_atk: Texture2D
@export var icon_def: Texture2D
@export var icon_rng: Texture2D

@export_range(0.1, 2.0, 0.05) var icon_scale := 0.9

# Tamaño/estilo de badges
@export var badge_size := Vector2(14, 14)
@export var badge_pad := 2.0
@export var badge_font_size := 16

var _last_cell_size: Vector2i = Vector2i(96, 96)

# Stats que se muestran en los badges
var stat_mv: int = 0
var stat_atk: int = 0
var stat_def: int = 0
var stat_rng: int = 0

# refs a nodos creados (sprite + label por esquina)
var _badges := {
	"mv": {"sprite": null, "label": null},
	"atk": {"sprite": null, "label": null},
	"def": {"sprite": null, "label": null},
	"rng": {"sprite": null, "label": null},
}

func _ready() -> void:
	tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	if sprite.texture:
		var tex := sprite.texture.get_size()
		var target := Vector2(_last_cell_size) * fill
		sprite.scale = target / tex
	sprite.centered = true

	_create_badges_if_needed()
	_layout_badges()
	_update_badge_numbers()
	queue_redraw()

func set_stats(mv:int, atk:int, def:int, rng:int) -> void:
	stat_mv = mv
	stat_atk = atk
	stat_def = def
	stat_rng = rng
	_update_badge_numbers()
	_layout_badges()  # reubica el texto según su tamaño real

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

	# escalar al tamaño de celda
	if sprite.texture:
		var tex := sprite.texture.get_size()
		var target := Vector2(_last_cell_size) * fill
		sprite.scale = target / tex

	_layout_badges()
	_update_badge_numbers()
	queue_redraw()

func _create_badges_if_needed() -> void:
	# Crea 4 Sprite2D + 4 Label y los guarda en _badges
	for key in ["mv","atk","def","rng"]:
		if _badges[key]["sprite"] == null:
			var s := Sprite2D.new()
			s.centered = false
			s.z_index = 10
			add_child(s)
			_badges[key]["sprite"] = s

		if _badges[key]["label"] == null:
			var lbl := Label.new()
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.z_index = 11
			# colores/outline (opcional)
			lbl.add_theme_color_override("font_color", Color(1,1,1))
			lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.9))
			lbl.add_theme_constant_override("outline_size", 2)
			add_child(lbl)
			_badges[key]["label"] = lbl

	# asignar texturas
	if icon_mv:  (_badges["mv"]["sprite"]  as Sprite2D).texture = icon_mv
	if icon_atk: (_badges["atk"]["sprite"] as Sprite2D).texture = icon_atk
	if icon_def: (_badges["def"]["sprite"] as Sprite2D).texture = icon_def
	if icon_rng: (_badges["rng"]["sprite"] as Sprite2D).texture = icon_rng

func _layout_badges() -> void:
	var half := Vector2(_last_cell_size) * 0.5
	var base_map := {
		"mv":  Vector2(-half.x + badge_pad,                          -half.y + badge_pad),
		"atk": Vector2( half.x - badge_pad - badge_size.x,           -half.y + badge_pad),
		"def": Vector2(-half.x + badge_pad,                           half.y - badge_pad - badge_size.y),
		"rng": Vector2( half.x - badge_pad - badge_size.x,            half.y - badge_pad - badge_size.y),
	}

	# El icono ocupa un cuadrado del alto del badge. El número va a la derecha.
	var icon_side := badge_size.y * icon_scale
	var icon_size := Vector2(icon_side, icon_side)

	for key in base_map.keys():
		var pos = base_map[key] + Vector2(badge_x_offset, badge_y_offset)
		var spr: Sprite2D = _badges[key]["sprite"]
		var lbl: Label    = _badges[key]["label"]

		# --- Icono (izquierda) ---
		if spr:
			spr.position = pos
			if spr.texture:
				var ts := spr.texture.get_size()
				if ts.x > 0.0 and ts.y > 0.0:
					spr.scale = icon_size / ts
			else:
				spr.scale = Vector2.ONE
			spr.position = spr.position.round()  # snap a pixel

		# --- Número (derecha del icono) ---
		if lbl:
			lbl.set("theme_override_font_sizes/font_size", badge_font_size)
			# Pedimos el tamaño mínimo del label (alto del texto con esa fuente)
			var min_size := lbl.get_minimum_size()
			# Lo colocamos pegado a la derecha del icono, centrado verticalmente respecto al icono
			var text_pos = pos + Vector2(icon_size.x + badge_gap, max(0.0, (icon_size.y - min_size.y) * 0.5))
			lbl.position = text_pos.round()
			# No fuerzo lbl.size a badge_size (evita anchos negativos). Dejalo que mida lo que necesite.


func _update_badge_numbers() -> void:
	(_badges["mv"]["label"]  as Label).text = str(stat_mv)
	(_badges["atk"]["label"] as Label).text = str(stat_atk)
	(_badges["def"]["label"] as Label).text = str(stat_def)
	(_badges["rng"]["label"] as Label).text = str(stat_rng)
