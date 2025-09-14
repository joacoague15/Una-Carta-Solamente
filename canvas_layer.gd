# HudOverlay.gd
extends Control
class_name HudOverlay

# Escalado
@export var design_size := Vector2i(1920, 1080)
@export var min_scale := 1.0
@export var max_scale := 3.0
@export var ui_scale := 1.35      # subí/bajá todo el HUD

# Estilo base (medidas a escala 1.0)
@export var base_pad := 20.0      # padding interno del panel
@export var base_gap := 12.0      # espacio icono ↔ número
@export var base_icon := 48.0     # lado del icono (grande)
@export var base_font_px := 30    # tamaño de fuente (grande)
@export var panel_border_px := 3.0

# Iconos (asignalos en el Inspector)
@export var icon_hp: Texture2D
@export var icon_mv: Texture2D
@export var icon_atk: Texture2D
@export var icon_def: Texture2D
@export var icon_rng: Texture2D

# Stats a mostrar
var _stats := {"hp": 6, "mv": 4, "atk": 7, "def": 7, "rng": 2}

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)    # ocupa toda la pantalla
	mouse_filter = MOUSE_FILTER_IGNORE      # no bloquea clicks del juego
	queue_redraw()

func set_stats(player_dict: Dictionary) -> void:
	for k in _stats.keys():
		if player_dict.has(k):
			_stats[k] = int(player_dict[k])
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _calc_scale() -> float:
	var vp := get_viewport_rect().size
	var sx := vp.x / float(design_size.x)
	var sy := vp.y / float(design_size.y)
	return clamp(min(sx, sy) * ui_scale, min_scale, max_scale)

func _draw() -> void:
	var s := _calc_scale()
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	var icon_side := base_icon * s
	var gap := base_gap * s
	var pad := base_pad * s
	var font_px := int(round(base_font_px * s))

	# Altura de fila (un poco de aire extra)
	var row_h = max(icon_side, float(font_px)) + 8.0 * s

	# Orden e iconos
	var order := ["hp", "mv", "atk", "def", "rng"]
	var icons := {
		"hp": icon_hp, "mv": icon_mv, "atk": icon_atk, "def": icon_def, "rng": icon_rng
	}

	# --- Ancho del texto: usar una muestra ancha para que el panel no colapse.
	var sample_text := "888"  # 3 dígitos de referencia
	var sample_w := font.get_string_size(sample_text, font_px).x

	# Si querés medir el número real más ancho:
	# var max_text_w := 0.0
	# for k in order:
	#     max_text_w = max(max_text_w, font.get_string_size(str(_stats[k]), font_px).x)
	# var text_w := max(sample_w, max_text_w)
	var text_w := sample_w

	# --- Panel abajo-izquierda
	var panel_w := pad + icon_side + gap + text_w + pad
	var panel_h = pad + order.size() * row_h + pad
	var panel_pos := Vector2(pad, vp.y - panel_h - pad)

	# Fondo negro y borde blanco
	draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(0, 0, 0, 1.0), true)
	draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(1, 1, 1, 1.0), false, panel_border_px)

	# --- Filas
	var y := panel_pos.y + pad
	for k in order:
		var tl := Vector2(panel_pos.x + pad, y)

		# Icono
		var tex: Texture2D = icons[k]
		if tex:
			draw_texture_rect(tex, Rect2(tl, Vector2(icon_side, icon_side)), false)

		# Número centrado vertical respecto al icono
		var txt := str(_stats[k])
		var text_size := font.get_string_size(txt, font_px)
		var baseline := tl.y + (icon_side + text_size.y) * 0.5   # baseline ≈ centro
		var text_pos := Vector2(tl.x + icon_side + gap, baseline)
		draw_string(font, text_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color.WHITE)

		y += row_h
