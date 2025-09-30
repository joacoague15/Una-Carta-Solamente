# HudOverlay.gd
extends Control
class_name HudOverlay

# ---------- Escalado ----------
@export var design_size := Vector2i(1920, 1080)
@export var min_scale := 1.0
@export var max_scale := 3.0
@export var ui_scale := 1.35

# ---------- Estilo base (a escala 1.0) ----------
@export var base_pad := 20.0
@export var base_gap := 12.0
@export var base_icon := 48.0
@export var base_font_px := 30
@export var panel_border_px := 3.0

# ---------- Iconos ----------
@export var icon_hp: Texture2D
@export var icon_mv: Texture2D
@export var icon_atk: Texture2D
@export var icon_def: Texture2D
@export var icon_rng: Texture2D

# ---------- Player breakdown ----------
@export var show_breakdown := true
@export var base_mv := 1
@export var base_atk := 1
@export var base_def := 1
@export var fixed_rng := 2   # rango siempre 2

# ---------- Panel Enemigo (arriba-derecha, 4 stats) ----------
@export var show_enemy_panel := true
@export var enemy_title := "ENEMIGO"
@export var enemy_font_px := 24

# ---------- Fonts ----------
@export var ui_font: Font
@export var enemy_font: Font   # opcional; si no, usa ui_font

# ---------- Panel HP Enemigos (abajo-derecha) ----------
@export var show_enemy_hp_panel := true
@export var enemy_hp_margin   := Vector2(16, 16)    # margen a los bordes de pantalla
@export var enemy_hp_bar_size := Vector2(140, 10)   # tamaño base de la barra
@export var enemy_hp_font_px  := 20

# ---------- Banner fin de partida ----------
@export var end_banner_font_px := 64
@export var end_banner_sub_px := 28

var _end_banner_visible := false
var _end_banner_text := ""
var _end_banner_sub := ""
var _end_banner_color := Color.WHITE

# ---------- Estado ----------
# Player
var _stats := {"hp": 6, "mv": 1, "atk": 1, "def": 1, "rng": 2}
# Enemy (uno solo, estático)
var _enemy := {"mv": 0, "atk": 0, "def": 0, "rng": 0}

var _enemy_hp_list: Array = []  # [{name:String, hp:int, max:int}]

# ---------- Lifecycle ----------
func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

# ---------- API desde el juego ----------
func set_stats(player_dict: Dictionary) -> void:
	for k in _stats.keys():
		if player_dict.has(k):
			_stats[k] = int(player_dict[k])
	queue_redraw()

func set_enemy_stats(enemy_dict: Dictionary) -> void:
	for k in _enemy.keys():
		if enemy_dict.has(k):
			_enemy[k] = int(enemy_dict[k])
	queue_redraw()

# ---------- Helpers ----------
func _calc_scale() -> float:
	var vp := get_viewport_rect().size
	var sx := vp.x / float(design_size.x)
	var sy := vp.y / float(design_size.y)
	return clamp(min(sx, sy) * ui_scale, min_scale, max_scale)

func _text_for_player(key: String) -> String:
	if key == "hp":
		return str(_stats["hp"])
	if key == "rng":
		return str(fixed_rng) # siempre 2

	var total := int(_stats.get(key, 1))
	var base := 1
	if key == "mv":  base = base_mv
	if key == "atk": base = base_atk
	if key == "def": base = base_def

	total = max(total, base)
	if show_breakdown:
		return str(base) + " (+" + str(max(0, total - base)) + ")"
	return str(total)
	
func _text_for_enemy(key: String) -> String:
	# enemigo: mostramos el valor tal cual, sin breakdown
	return str(int(_enemy.get(key, 0)))
	
func set_enemy_hp_list(list: Array) -> void:
	_enemy_hp_list = list
	queue_redraw()
	
func _draw_enemy_hp_panel(scale_factor: float, vp_size: Vector2) -> void:
	if not show_enemy_hp_panel or _enemy_hp_list.is_empty():
		return

	var s := scale_factor
	var font := enemy_font if enemy_font else ui_font
	var fs := int(round(enemy_hp_font_px * s))
	var pad := base_pad * s
	var gap := base_gap * s * 0.6
	var bar_sz := enemy_hp_bar_size * s
	var margin := enemy_hp_margin * s

	# medir contenido
	var max_text_w := 0.0
	for L in _enemy_hp_list:
		var txt := "%s  %d/%d" % [String(L["name"]), int(L["hp"]), int(L["max"])]
		max_text_w = max(max_text_w, font.get_string_size(txt, fs).x)

	var content_w = max(max_text_w, bar_sz.x)
	var content_h := 0.0
	for _i in _enemy_hp_list.size():
		content_h += fs + 4.0 * s
		content_h += bar_sz.y + 6.0 * s

	var panel_size := Vector2(content_w, content_h) + Vector2(pad, pad) * 2.0

	# *** Abajo-derecha de la PANTALLA ***
	var pos := Vector2(
		vp_size.x - panel_size.x - margin.x,
		vp_size.y - panel_size.y - margin.y
	)
	var panel := Rect2(pos, panel_size)

	# panel
	draw_rect(panel, Color(0,0,0,0.75), true)
	draw_rect(panel, Color(1,1,1,1), false, panel_border_px)

	# contenido
	var x := pos.x + pad
	var y := pos.y + pad
	for L in _enemy_hp_list:
		var name := String(L["name"])
		var hp := int(L["hp"])
		var mx := int(L["max"])
		var txt := "%s  %d/%d" % [name, hp, mx]

		var baseline := y + font.get_ascent(fs)
		draw_string(font, Vector2(x, baseline), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		y += fs + 4.0 * s

		var ratio
		if (mx > 0):
			ratio = clamp(float(hp)/float(mx), 0.0, 1.0)
		else:
			ratio = 0.0
			
		var bar := Rect2(Vector2(x, y), bar_sz)
		draw_rect(bar, Color(0.15,0.15,0.15,1), true)
		draw_rect(Rect2(bar.position, Vector2(bar_sz.x * ratio, bar_sz.y)), Color(1.0 - ratio, ratio, 0.2, 1), true)
		draw_rect(bar, Color(1,1,1,0.9), false, 1.0)
		y += bar_sz.y + 6.0 * s
		
func show_end_banner(text:String, subtext:String="", color:Color=Color.WHITE) -> void:
	_end_banner_visible = true
	_end_banner_text = text
	_end_banner_sub = subtext
	_end_banner_color = color
	queue_redraw()

func hide_end_banner() -> void:
	_end_banner_visible = false
	queue_redraw()
	
func _draw_end_banner(s: float, vp: Vector2) -> void:
	if not _end_banner_visible:
		return
	# oscurecer pantalla
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0,0,0,0.55), true)

	var font := ui_font
	var fs := int(round(end_banner_font_px * s))
	var ss := int(round(end_banner_sub_px * s))
	var main_txt := _end_banner_text
	var sub_txt := _end_banner_sub

	var main_size := font.get_string_size(main_txt, fs)
	var sub_size
	if sub_txt == "":
		sub_size = Vector2.ZERO
	else:
		sub_size = font.get_string_size(sub_txt, ss)

	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var main_pos := Vector2(cx - main_size.x * 0.5, cy - (main_size.y + (sub_size.y + 16*s)) * 0.5 + font.get_ascent(fs))
	draw_string(font, main_pos, main_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _end_banner_color)

	if sub_txt != "":
		var sub_pos := Vector2(cx - sub_size.x * 0.5, main_pos.y + font.get_height(fs) + 16*s)
		draw_string(font, sub_pos, sub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(1,1,1,0.95))


# ---------- Dibujo ----------
func _draw() -> void:
	var s := _calc_scale()
	var vp := get_viewport_rect().size
	_draw_end_banner(s, vp)  
	var font := ui_font
	
	_draw_enemy_hp_panel(s, vp)

	# === Panel Player (abajo-izquierda) ===
	var icon_side := base_icon * s
	var gap := base_gap * s
	var pad := base_pad * s
	var font_px := int(round(base_font_px * s))
	var row_h = max(icon_side, float(font_px)) + 8.0 * s

	var order_p := ["hp", "mv", "atk", "def", "rng"]
	var icons := {
		"hp": icon_hp, "mv": icon_mv, "atk": icon_atk, "def": icon_def, "rng": icon_rng
	}

	var max_text_w := 0.0
	for k in order_p:
		var t := _text_for_player(k)
		max_text_w = max(max_text_w, font.get_string_size(t, font_px).x)

	var extra_w := 60.0 * s
	var panel_w := pad + icon_side + gap + max_text_w + pad + extra_w
	var panel_h = pad + order_p.size() * row_h + pad
	var panel_pos := Vector2(pad, vp.y - panel_h - pad)

	draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(0, 0, 0, 1.0), true)
	draw_rect(Rect2(panel_pos, Vector2(panel_w, panel_h)), Color(1, 1, 1, 1.0), false, panel_border_px)

	var y := panel_pos.y + pad
	for k in order_p:
		var tl := Vector2(panel_pos.x + pad, y)
		var tex: Texture2D = icons[k]
		if tex:
			draw_texture_rect(tex, Rect2(tl, Vector2(icon_side, icon_side)), false)

		var txt := _text_for_player(k)
		var text_size := font.get_string_size(txt, font_px)
		var baseline := tl.y + (icon_side + text_size.y) * 0.5
		var text_pos := Vector2(tl.x + icon_side + gap, baseline)
		var outline_px := int(round(2.0 * s))
		if outline_px > 0:
			draw_string_outline(font, text_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, outline_px, Color(0,0,0,1))
		draw_string(font, text_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color.WHITE)
		y += row_h

	# === Panel Enemigo (arriba-derecha, 4 stats) ===
	if show_enemy_panel:
		var f := font
		var fp := int(round(enemy_font_px * s))
		var pad2 := base_pad * s
		var gap2 := base_gap * s * 0.9
		var icon_side2 := base_icon * s * 0.85

		var order_e := ["mv", "atk", "def", "rng"]
		var max_text_w_e := 0.0
		for k in order_e:
			var t := _text_for_enemy(k)
			max_text_w_e = max(max_text_w_e, f.get_string_size(t, fp).x)

		# ancho: icono + gap + texto más largo
		var content_w := pad2 + icon_side2 + gap2 + max_text_w_e + pad2
		var title_w := f.get_string_size(enemy_title, fp).x
		var panel_w2 = max(pad2 + title_w + pad2, content_w + 60)
		var row_h2 = max(icon_side2, float(fp)) + 6.0 * s
		var panel_h2 = pad2 + fp + 6.0*s + order_e.size() * row_h2 + pad2

		var pos := Vector2(vp.x - panel_w2 - pad2, pad2)

		draw_rect(Rect2(pos, Vector2(panel_w2, panel_h2)), Color(0,0,0,1), true)
		draw_rect(Rect2(pos, Vector2(panel_w2, panel_h2)), Color(1,1,1,1), false, panel_border_px)

		# título
		var tpos := Vector2(pos.x + pad2, pos.y + pad2 + fp)
		draw_string(f, tpos, enemy_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fp, Color.WHITE)

		# filas
		var y2 := pos.y + pad2 + fp + 6.0*s
		for k in order_e:
			var tl2 := Vector2(pos.x + pad2, y2)

			var itex: Texture2D = null
			if k == "mv":  itex = icon_mv
			if k == "atk": itex = icon_atk
			if k == "def": itex = icon_def
			if k == "rng": itex = icon_rng

			if itex:
				draw_texture_rect(itex, Rect2(tl2, Vector2(icon_side2, icon_side2)), false)

			var txt := _text_for_enemy(k)
			var txt_size := f.get_string_size(txt, fp)
			var baseline := tl2.y + (icon_side2 + txt_size.y) * 0.5
			var text_pos := Vector2(tl2.x + icon_side2 + gap2, baseline)
			draw_string(f, text_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fp, Color.WHITE)

			y2 += row_h2
