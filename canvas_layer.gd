# HudOverlay.gd
extends Control
class_name HudOverlay

# Escalado
@export var design_size := Vector2i(1920, 1080)
@export var min_scale := 1.0
@export var max_scale := 3.0
@export var ui_scale := 1.35

# Estilo base (medidas a escala 1.0)
@export var base_pad := 20.0
@export var base_gap := 12.0
@export var base_icon := 48.0
@export var base_font_px := 30
@export var panel_border_px := 3.0

# Iconos
@export var icon_hp: Texture2D
@export var icon_mv: Texture2D
@export var icon_atk: Texture2D
@export var icon_def: Texture2D
@export var icon_rng: Texture2D

# --- Opcional: mostrar desglose "1 (+N)" ---
@export var show_breakdown := true

# Bases fijas que pediste
@export var base_mv := 1
@export var base_atk := 1
@export var base_def := 1
@export var fixed_rng := 2   # rango siempre 2

# Stats actuales (totales) que nos pasa el juego
var _stats := {"hp": 6, "mv": 1, "atk": 1, "def": 1, "rng": 2}

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	queue_redraw()

func set_stats(player_dict: Dictionary) -> void:
	# Guardamos los TOTALES que nos manda el main
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

func _text_for(key: String) -> String:
	if key == "hp":
		return str(_stats["hp"])
	if key == "rng":
		# siempre 2
		return str(fixed_rng)

	# mv / atk / def
	var total := int(_stats.get(key, 1))
	var base := 1
	if key == "mv":  base = base_mv
	if key == "atk": base = base_atk
	if key == "def": base = base_def

	total = max(total, base) # por si llega algo menor
	if show_breakdown:
		return str(base) + " (+" + str(max(0, total - base)) + ")"
	else:
		return str(total)

func _draw() -> void:
	var s := _calc_scale()
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	var icon_side := base_icon * s
	var gap := base_gap * s
	var pad := base_pad * s
	var font_px := int(round(base_font_px * s))

	var row_h = max(icon_side, float(font_px)) + 8.0 * s

	var order := ["hp", "mv", "atk", "def", "rng"]
	var icons := {
		"hp": icon_hp, "mv": icon_mv, "atk": icon_atk, "def": icon_def, "rng": icon_rng
	}

	# Calculamos el ancho real del texto más largo (soporta "1 (+12)")
	var max_text_w := 0.0
	for k in order:
		var t := _text_for(k)
		max_text_w = max(max_text_w, font.get_string_size(t, font_px).x)
	var text_w := max_text_w

	# Panel abajo-izquierda
	var extra_w := 60.0 * s   # ajustá este número a gusto
	var panel_w := pad + icon_side + gap + text_w + pad + extra_w
	var panel_h = pad + order.size() * row_h + pad
	var panel_pos := Vector2(pad, vp.y - panel_h - pad)

	# Fondo y borde
	draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(0, 0, 0, 1.0), true)
	draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(1, 1, 1, 1.0), false, panel_border_px)

	# Filas
	var y := panel_pos.y + pad
	for k in order:
		var tl := Vector2(panel_pos.x + pad, y)

		# Icono
		var tex: Texture2D = icons[k]
		if tex:
			draw_texture_rect(tex, Rect2(tl, Vector2(icon_side, icon_side)), false)

		# Texto
		var txt := _text_for(k)
		var text_size := font.get_string_size(txt, font_px)
		var baseline := tl.y + (icon_side + text_size.y) * 0.5
		var text_pos := Vector2(tl.x + icon_side + gap, baseline)
		draw_string(font, text_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color.WHITE)

		y += row_h
