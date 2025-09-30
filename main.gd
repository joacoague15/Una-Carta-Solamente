extends Node2D
class_name Level1

@onready var PlayerScene := preload("res://Player.tscn")
@onready var EnemyScene := preload("res://Enemy.tscn")

@export var grid_color: Color = Color(0, 0, 0, 1)             # celdas negras
@export var grid_border_color: Color = Color(0.25, 0.25, 0.25) # bordes opcionales
@export var pillar_texture: Texture2D                         # setéala en el editor
@export_range(0.3, 1.1, 0.05) var pillar_fill := 0.9          # qué tanto ocupa la textura en la celda

var player_node: Player
var enemy_nodes: Array[Enemy] = []

@onready var hud: HudOverlay = $"UI/HudOverlay"

@export var cols := 4
@export var rows := 5
@export var cell_size := Vector2i(96, 96)

@export var dice_right_margin := 16.0

@export var slot_icon_mv:  Texture2D
@export var slot_icon_atk: Texture2D
@export var slot_icon_def: Texture2D

@export var confirm_margin := Vector2(16, 16) # (derecha, abajo) dentro del panel del draft

@export var slot_icon_size := Vector2(28, 28)

# --- FX / Audio ---
@export var sfx_player_attack: AudioStream
@export var sfx_enemy_hit:     AudioStream
@export var sfx_enemy_die:     AudioStream
@export var sfx_block: 		   AudioStream

# --- Música ambiente ---
@export var bgm_stream: AudioStream 
@export var bgm_bus := "Master"    
@export var bgm_volume_db := -10.0    
@export var bgm_fadein_sec := 1.5        # duración del fade-in

@export var show_enemy_hp_hud := true
@export var enemy_hp_panel_margin := Vector2(12, 12)
@export var enemy_hp_panel_padding := Vector2(10, 8)
@export var enemy_hp_bar_size := Vector2(100, 8)
@export var enemy_hp_font_size := 16

enum Outcome { NONE, VICTORY, DEFEAT }
var outcome := Outcome.NONE

var _bgm: AudioStreamPlayer

# Un reproductor de SFX (o poné uno en la escena y apúntalo con $SFX)
var _sfx: AudioStreamPlayer

const P_STATS = { "hp": 6, "mv": 1, "atk": 1, "def": 1, "rng": 2 }
var   E_BASE  = { "hp": 2, "mv": 5, "atk": 4, "def": 4, "rng": 3 } 

var is_rolling_dice := false                # bloquea interacción mientras roda

var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()

# --- DRAFT / DADOS ---
var is_drafting := true
var draft_dice: Array[int] = []
var draft_assign_idx := {"mv": -1, "atk": -1, "def": -1} # guarda índices 0..2 de draft_dice
var draft_selected_die := -1
var draft_hovered_die := -1
var draft_hovered_confirm := false
var draft_pressed_confirm := false

func _roll_dice_final() -> void:
	draft_dice = [RunState.rng.randi_range(1,6), RunState.rng.randi_range(1,6), RunState.rng.randi_range(1,6)]
	draft_assign_idx = {"mv": -1, "atk": -1, "def": -1}
	draft_selected_die = -1
	is_drafting = true
	queue_redraw()

func _roll_dice_anim(duration := 0.6) -> void:
	is_rolling_dice = true
	var steps := int(ceil(duration / 0.06))
	for s in steps:
		draft_dice = [RunState.rng.randi_range(1,6), RunState.rng.randi_range(1,6), RunState.rng.randi_range(1,6)]
		queue_redraw()
		await get_tree().create_timer(0.06).timeout
	_roll_dice_final()
	is_rolling_dice = false

func _all_assigned() -> bool:
	return draft_assign_idx["mv"] != -1 and draft_assign_idx["atk"] != -1 and draft_assign_idx["def"] != -1

func _die_assigned(idx:int) -> bool:
	return draft_assign_idx["mv"] == idx or draft_assign_idx["atk"] == idx or draft_assign_idx["def"] == idx

# --- tablero/estado ---
func rc(row:int, col:int) -> Vector2i:
	return Vector2i(col - 1, row - 1)

var pillars := {
	rc(4, 2): true,
	rc(2, 2): true,
	rc(2, 4): true,
}

var player := {
	"pos": rc(1, 1),
	"hp": P_STATS["hp"],
	"mv": P_STATS["mv"],
	"atk": P_STATS["atk"],
	"def": P_STATS["def"],
	"rng": P_STATS["rng"],
}

var enemies := [
	{
		"name": "goblin1",
		"pos": rc(1, 4),
		"hp": E_BASE["hp"],
		"mv": E_BASE["mv"],
		"atk": E_BASE["atk"],
		"def": E_BASE["def"],
		"rng": E_BASE["rng"],
	},
	{
		"name": "goblin2",
		"pos": rc(3, 4),
		"hp": E_BASE["hp"],
		"mv": E_BASE["mv"],
		"atk": E_BASE["atk"],
		"def": E_BASE["def"],
		"rng": E_BASE["rng"],
	},
]

enum Phase { PLAYER, ENEMIES }
var phase := Phase.PLAYER
var moves_left := P_STATS["mv"]

# --- helpers ---
func _enemy_index_at(cell: Vector2i) -> int:
	for i in enemies.size():
		if enemies[i]["pos"] == cell:
			return i
	return -1

func _mouse_to_cell(mpos: Vector2) -> Vector2i:
	var local: Vector2 = to_local(mpos)  # respeta position+scale
	return Vector2i(floor(local.x / float(cell_size.x)), floor(local.y / float(cell_size.y)))

func _is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cols and c.y >= 0 and c.y < rows

func _is_blocked(cell: Vector2i) -> bool:
	if pillars.has(cell):
		return true
	if cell == player["pos"]:
		return true
	for e in enemies:
		if e["pos"] == cell:
			return true
	return false

func _is_blocked_for_enemy(cell: Vector2i, enemy_index:int) -> bool:
	if pillars.has(cell):
		return true
	if cell == player["pos"]:
		return true
	for j in enemies.size():
		if j == enemy_index:
			continue
		if enemies[j]["pos"] == cell:
			return true
	return false

func _adjacent_cells(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i(1,0), c + Vector2i(-1,0), c + Vector2i(0,1), c + Vector2i(0,-1)]

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# movimiento: orto=2, diag=3
func _move_cost(a: Vector2i, b: Vector2i) -> int:
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	if dx + dy == 1: return 2
	if dx == 1 and dy == 1: return 3
	return -1

# alcance: misma métrica 2/3, ignora obstáculos (si querés LOS, integramos después)
func _reach_cost(a: Vector2i, b: Vector2i) -> int:
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	var diag = min(dx, dy)
	var orto = abs(dx - dy)
	return diag * 3 + orto * 2
	
var player_attacked_this_turn := false
var _is_ending_turn := false
var _turn_ended_this_click := false

func _can_attack(attacker: Dictionary, target_pos: Vector2i) -> bool:
	return _reach_cost(attacker["pos"], target_pos) <= int(attacker["rng"])
	
func _has_attack_target() -> bool:
	for e in enemies:
		if _can_attack(player, e["pos"]):
			return true
	return false

func _maybe_auto_end_turn() -> bool:
	# Si no hay UI de draft activa, evaluamos auto-fin
	if is_drafting or _is_ending_turn:
		return false
	var no_moves := moves_left <= 1
	var can_attack := _has_attack_target()
	
	if no_moves and (player_attacked_this_turn or not can_attack):
		await _end_player_turn()
		return true
	return false

func _play_sfx(stream: AudioStream) -> void:
	if stream == null: return
	_sfx.stream = stream
	_sfx.play()
	
# sacudida corta del nodo (Node2D) sin romper su "grid"
func _shake_node(n: Node2D, amt := 6.0, dur := 0.12) -> void:
	if n == null: return
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var orig := n.position
	t.tween_property(n, "position", orig + Vector2(amt, 0), dur * 0.25)
	t.tween_property(n, "position", orig - Vector2(amt, 0), dur * 0.5)
	t.tween_property(n, "position", orig, dur * 0.25)

# destello rojo breve
func _flash_red(n: CanvasItem, dur := 0.18) -> void:
	if n == null: return
	var t := create_tween()
	t.tween_property(n, "modulate", Color(1,0.25,0.25,1), dur*0.5)
	t.tween_property(n, "modulate", Color(1,1,1,1), dur*0.5)
	
func _flash_block(n: CanvasItem, dur := 0.18) -> void:
	if n == null: return
	var t := create_tween()
	t.tween_property(n, "modulate", Color(0.6,0.8,1.0,1), dur*0.5)
	t.tween_property(n, "modulate", Color(1,1,1,1), dur*0.5)

func _ensure_enemy_max_hp() -> void:
	for i in enemies.size():
		if not enemies[i].has("max_hp"):
			enemies[i]["max_hp"] = int(enemies[i]["hp"])

func _draw_enemy_hp_hud() -> void:
	if not show_enemy_hp_hud:
		return
		
func _enemy_hp_snapshot() -> Array:
	var arr: Array = []
	for e in enemies:
		arr.append({
			"name": String(e.get("name","enemy")),
			"hp": int(e.get("hp",0)),
			"max": int(e.get("max_hp", e.get("hp",0))),
		})
	return arr
	
func _push_enemy_hp_to_hud() -> void:
	if hud and "set_enemy_hp_list" in hud:
		hud.set_enemy_hp_list(_enemy_hp_snapshot())

	# armar líneas: name  hp/max
	var font := ThemeDB.fallback_font
	var fs := enemy_hp_font_size
	var lines: Array = []
	for e in enemies:
		var name := String(e.get("name", "enemy"))
		var hp := int(e.get("hp", 0))
		var max_hp := int(e.get("max_hp", hp))
		lines.append({"name": name, "hp": hp, "max": max_hp})

	if lines.is_empty():
		return

	# medir ancho de texto mayor vs barra
	var max_text_w := 0.0
	for L in lines:
		var txt := "%s  %d/%d" % [L["name"], L["hp"], L["max"]]
		max_text_w = max(max_text_w, font.get_string_size(txt, fs).x)

	var content_w = max(max_text_w, enemy_hp_bar_size.x)
	var content_h := 0.0
	for _i in lines.size():
		content_h += fs + 4            # línea de texto
		content_h += enemy_hp_bar_size.y + 6  # barra debajo

	var board_size := Vector2(cols * cell_size.x, rows * cell_size.y)
	var panel_size := Vector2(content_w, content_h) + enemy_hp_panel_padding * 2.0
	var panel_pos := Vector2(
		board_size.x - panel_size.x - enemy_hp_panel_margin.x,   # derecha
		board_size.y - panel_size.y - enemy_hp_panel_margin.y    # abajo
	)
	var panel := Rect2(panel_pos, panel_size)

	# panel
	draw_rect(panel, Color(0,0,0,0.5), true)
	draw_rect(panel, Color(1,1,1,0.9), false, 1.0)

	# contenido
	var x := panel_pos.x + enemy_hp_panel_padding.x
	var y := panel_pos.y + enemy_hp_panel_padding.y
	for L in lines:
		var txt := "%s  %d/%d" % [L["name"], L["hp"], L["max"]]
		draw_string(font, Vector2(x, y + font.get_ascent(fs)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))
		y += fs + 4

		# barra HP
		var ratio
		if (L["max"] > 0):
			ratio = clamp(float(L["hp"]) / float(L["max"]), 0.0, 1.0)
		else:
			ratio = 0.0
		
		var bar_rect := Rect2(Vector2(x, y), enemy_hp_bar_size)
		# fondo de barra
		draw_rect(bar_rect, Color(0.15,0.15,0.15,1.0), true)
		# fill (verde->rojo)
		var fill_rect := Rect2(bar_rect.position, Vector2(enemy_hp_bar_size.x * ratio, enemy_hp_bar_size.y))
		var col := Color(1.0 - ratio, ratio, 0.2, 1.0)
		draw_rect(fill_rect, col, true)
		# borde
		draw_rect(bar_rect, Color(1,1,1,0.8), false, 1.0)

		y += enemy_hp_bar_size.y + 6

func _rc_from_v2i(v: Vector2i) -> Vector2i:
	# tu rc(row,col) es rc(1,1) -> (0,0). Acá ya viene en coords 0-based.
	return v

func _build_level_from_runstate() -> void:
	var def := RunState.get_level_def(RunState.level)

	# --- Player ---
	player = {
		"pos": _rc_from_v2i(def["player_start"]),
		"hp": RunState.player_hp,          # se mantiene
		"mv": P_STATS["mv"],
		"atk": P_STATS["atk"],
		"def": P_STATS["def"],
		"rng": P_STATS["rng"],
	}

	# --- Enemigos base por nivel ---
	E_BASE = def["enemy_base"].duplicate(true)

	# --- Pilares ---
	pillars.clear()
	for p: Vector2i in def["pillars"]:
		pillars[p] = true

	# --- Enemigos ---
	enemies.clear()
	for ei in def["enemies"]:
		enemies.append({
			"name": String(ei.get("name","enemy")),
			"pos": _rc_from_v2i(ei["pos"]),
			"hp":  E_BASE["hp"],
			"mv":  E_BASE["mv"],
			"atk": E_BASE["atk"],
			"def": E_BASE["def"],
			"rng": E_BASE["rng"],
			"max_hp": E_BASE["hp"],
		})

	# --- Nodos enemigos (reset limpio) ---
	for n in enemy_nodes:
		if is_instance_valid(n): n.queue_free()
	enemy_nodes.clear()

	# --- Sin turn stats asignados aún, se tiran dados otra vez ---
	moves_left = P_STATS["mv"]  # valor base, pero hasta confirmar draft no jugará
	is_drafting = true
	player_attacked_this_turn = false
	_update_astar_solid_tiles()
	_sync_player_sprite(false)
	_sync_enemy_sprites(false)
	if hud:
		hud.set_enemy_stats({
			"mv": E_BASE["mv"], "atk": E_BASE["atk"], "def": E_BASE["def"], "rng": E_BASE["rng"]
		})
		hud.set_stats(player)
	_push_enemy_hp_to_hud()
	queue_redraw()

	# animación de dado + set final
	await _roll_dice_anim(0.6)


# --- setup ---
func _ready() -> void:
	if not RunState.initialized:
		RunState.reset_run()
	
	add_child(hud)
	player_node = PlayerScene.instantiate()
	add_child(player_node)
	
	_layout_board()  # primero escala/centra el tablero
	player_node.set_cell(player["pos"], cell_size, false)  # sin animación
	
	rng.randomize()
	_roll_dice_final()  # mostrar UI de dados al inicio

	_init_astar()
	_update_astar_solid_tiles()
	get_viewport().size_changed.connect(_on_viewport_resized)
	queue_redraw()
	
	_ensure_enemy_max_hp()
	_push_enemy_hp_to_hud()
	
	if not _sfx:
		_sfx = AudioStreamPlayer.new()
		add_child(_sfx)
		
	await _build_level_from_runstate()
	
	for e in enemies:
		var n: Enemy = EnemyScene.instantiate()
		add_child(n)
		
		n.set_cell(e["pos"], cell_size, false)
		enemy_nodes.append(n)
		
	# --- Música ambiente ---
	if bgm_stream:
		_bgm = AudioStreamPlayer.new()
		_bgm.stream = bgm_stream
		_bgm.bus = bgm_bus
		# intento de loop si el recurso lo soporta (Ogg/Wav)
		if "loop" in bgm_stream:
			bgm_stream.loop = true
		_bgm.volume_db = -40.0  # arranca bajo para el fade-in
		add_child(_bgm)
		_bgm.play()
		# fade-in suave
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_bgm, "volume_db", bgm_volume_db, bgm_fadein_sec)
		
		if hud:
			hud.set_enemy_stats({
				"mv": E_BASE["mv"],
				"atk": E_BASE["atk"],
				"def": E_BASE["def"],
				"rng": E_BASE["rng"]
			})
			hud.set_stats(player)

func _sync_player_sprite(animate: bool = true) -> void:
	if player_node:
		player_node.set_cell(player["pos"], cell_size, animate)
		
func _sync_enemy_sprites(animate: bool = true) -> void:
	var count = min(enemy_nodes.size(), enemies.size())
	for i in count:
		enemy_nodes[i].set_cell(enemies[i]["pos"], cell_size, animate)

func _on_viewport_resized() -> void:
	_layout_board()
	queue_redraw()

func _layout_board() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var board_size: Vector2 = Vector2(cols * cell_size.x, rows * cell_size.y)
	var s = min(vp_size.x / board_size.x, vp_size.y / board_size.y)
	scale = Vector2(s, s)
	position = (vp_size - board_size * s) * 0.5

func _init_astar() -> void:
	astar.region = Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	astar.cell_size = Vector2(cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()

func _update_astar_solid_tiles() -> void:
	for y in range(rows):
		for x in range(cols):
			astar.set_point_solid(Vector2i(x, y), pillars.has(Vector2i(x,y)))
			
	astar.set_point_solid(player["pos"], true)
	for e in enemies:
		astar.set_point_solid(e["pos"], true)
		
func _on_victory() -> void:
	if outcome != Outcome.NONE: return
	RunState.player_hp = int(player["hp"])
	outcome = Outcome.VICTORY
	if hud and "show_end_banner" in hud:
		hud.show_end_banner("¡Victoria!", "Cargando siguiente nivel…", Color(0.7,1.0,0.7,1.0))
	await get_tree().create_timer(1.0).timeout
	RunState.next_level()
	outcome = Outcome.NONE
	await _build_level_from_runstate()

func _goto_level2() -> void:
	var path := "res://main2.tscn"
	if ResourceLoader.exists(path):
		get_tree().change_scene_to_file(path)
	else:
		if hud and "show_end_banner" in hud:
			hud.show_end_banner("¡Victoria!", "Cargando siguiente nivel…", Color(0.7,1.0,0.7,1.0))

func _on_defeat() -> void:
	if outcome != Outcome.NONE: return
	outcome = Outcome.DEFEAT
	if hud and "show_end_banner" in hud:
		hud.show_end_banner("Derrota", "Clic o tecla para reiniciar", Color(1.0,0.6,0.6,1.0))

# --- input / turns ---
func _input(event: InputEvent) -> void:
	if outcome != Outcome.NONE:
		if outcome == Outcome.DEFEAT:
			if (event is InputEventMouseButton and not event.pressed) or (event is InputEventKey and event.pressed):
				RunState.reset_run()
				outcome = Outcome.NONE
				await _build_level_from_runstate()
		return
	
	# Primero, si estamos en la UI de dados, consumimos el input ahí.
	if is_drafting:
		if is_rolling_dice:
			return 
		
		var local_pos := to_local(get_viewport().get_mouse_position())
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_draft_press(local_pos)
				_handle_draft_click(local_pos)
			else:
				_handle_draft_release()
		elif event is InputEventMouseMotion:
			_handle_draft_hover(local_pos)
		return

	if phase != Phase.PLAYER:
		return

	# Sólo mouse (click izquierdo)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _mouse_to_cell(get_viewport().get_mouse_position())
		_on_player_click(cell)

func _on_player_click(cell: Vector2i) -> void:
	if not _is_inside(cell) or moves_left <= 0 or _is_ending_turn:
		return

	# ¿click a un enemigo?
	var idx := _enemy_index_at(cell)
	if idx != -1:
		if _can_attack(player, enemies[idx]["pos"]):
			# Esperamos a que termine la animación/FX del ataque
			await _player_attack(idx)
			
			if outcome != Outcome.NONE:
				return

			# Cerramos el turno SIEMPRE tras atacar (con guard para evitar doble cierre)
			if not _is_ending_turn:
				await _end_player_turn()
		return

	# Si es celda vacía: sólo adyacente y con puntos suficientes
	var cost := _move_cost(player["pos"], cell)
	if cost == -1: return
	if _is_blocked(cell): return
	if moves_left < cost: return

	player["pos"] = cell
	moves_left -= cost
	_update_astar_solid_tiles()
	_sync_player_sprite()
	queue_redraw()

	# Intento auto-fin sólo para movimiento (ataque ya fuerza fin arriba)
	var ended := await _maybe_auto_end_turn()
	if ended:
		return

	# Si no terminó automáticamente y ya no hay movimientos, cerramos turno (con guard)
	if moves_left <= 0 and not _is_ending_turn:
		await _end_player_turn()
		
# animación y limpieza del enemigo muerto
func _enemy_die(enemy_index: int) -> void:
	if enemy_index < 0 or enemy_index >= enemy_nodes.size():
		return
	var node := enemy_nodes[enemy_index]
	
	_push_enemy_hp_to_hud()

	# sonido de muerte
	_play_sfx(sfx_enemy_die)

	# si hay animación "die", la usamos
	var played_anim := false
	if node.has_node("AnimationPlayer"):
		var ap: AnimationPlayer = node.get_node("AnimationPlayer")
		if ap.has_animation("die"):
			ap.play("die")
			played_anim = true
			# Esperamos que termine (si la anim tiene "autoplay next" o track end):
			await ap.animation_finished

	# fallback: tween de desvanecer + escala
	if not played_anim:
		var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(node, "scale", node.scale * 0.1, 0.22)
		t.parallel().tween_property(node, "modulate", Color(1,1,1,0), 0.22)
		await t.finished

	# remover data y nodo
	enemies.remove_at(enemy_index)
	enemy_nodes.remove_at(enemy_index)

	_update_astar_solid_tiles()
	_sync_enemy_sprites(false)
	queue_redraw()
	
	# ¿Victoria?
	if enemies.is_empty():
		await _on_victory()

func _player_attack(enemy_index:int) -> void:
	player_attacked_this_turn = true
	var e = enemies[enemy_index]
	var target_node := enemy_nodes[enemy_index]

	_play_sfx(sfx_player_attack)
	_shake_node(player_node, 8.0, 0.15)
	if player_node.has_node("AnimationPlayer"):
		var ap: AnimationPlayer = player_node.get_node("AnimationPlayer")
		if ap.has_animation("attack"):
			ap.play("attack")

	var dmg_raw := int(player["atk"]) - int(e["def"])
	var dmg = max(0, dmg_raw)

	if dmg <= 0:
		# BLOQUEO (sin daño)
		_flash_block(target_node)
		_shake_node(target_node, 4.0, 0.12)
		_play_sfx(sfx_block)
		return

	e["hp"] -= dmg
	_play_sfx(sfx_enemy_hit)
	_flash_red(target_node)
	_shake_node(target_node, 10.0, 0.15)
	_push_enemy_hp_to_hud()

	if e["hp"] <= 0:
		await _enemy_die(enemy_index)
		_push_enemy_hp_to_hud()
		if enemies.is_empty():
			await _on_victory()
			return
	else:
		_update_astar_solid_tiles()
		_sync_enemy_sprites(false)
		queue_redraw()

func _end_player_turn() -> void:
	if _is_ending_turn:
		return
	_is_ending_turn = true
	
	# si ya hay fin de partida, no sigas
	if outcome != Outcome.NONE:
		_is_ending_turn = false
		return
	
	# pausa de claridad
	await get_tree().create_timer(0.5).timeout
	
	phase = Phase.ENEMIES
	
	if outcome != Outcome.NONE:
		_is_ending_turn = false
		return
	
	await _enemy_phase()
	_sync_enemy_sprites(true)

	phase = Phase.PLAYER
	moves_left = player["mv"]
	player_attacked_this_turn = false
	_update_astar_solid_tiles()
	queue_redraw()
	await _maybe_auto_end_turn()
	
	_is_ending_turn = false

func _enemy_phase() -> void:
	# Procesamos enemigo por enemigo: mover -> pequeña pausa -> atacar (si puede)
	for i in range(enemies.size()):
		# si el player ya murió, corta la fase
		if player["hp"] <= 0:
			break

		# --- MOVIMIENTO ---
		var budget := int(enemies[i]["mv"])
		if budget >= 2:
			_update_astar_solid_tiles()
			astar.set_point_solid(enemies[i]["pos"], false)

			# si no está adyacente, buscamos la mejor celda adyacente al player
			if _manhattan(enemies[i]["pos"], player["pos"]) != 1:
				var goals := _adjacent_cells(player["pos"]).filter(
					func(c): return _is_inside(c) and not _is_blocked_for_enemy(c, i)
				)
				if goals.is_empty():
					goals = [player["pos"]]

				var best_path := []
				for g in goals:
					var p := astar.get_id_path(enemies[i]["pos"], g)
					if p.is_empty(): 
						continue
					if best_path.is_empty() or p.size() < best_path.size():
						best_path = p

				if not best_path.is_empty():
					var curr = enemies[i]["pos"]
					for step_idx in range(1, best_path.size()):
						var nxt: Vector2i = best_path[step_idx]
						if _is_blocked_for_enemy(nxt, i):
							break
						var step_cost := _move_cost(curr, nxt)
						if step_cost == -1 or budget < step_cost:
							break
						curr = nxt
						budget -= step_cost
						enemies[i]["pos"] = curr
						# si ya quedó adyacente, frenamos
						if _manhattan(enemies[i]["pos"], player["pos"]) == 1:
							break

		_update_astar_solid_tiles()
		_sync_enemy_sprites(true)
		queue_redraw()

		# --- ESPERA 0.2s ANTES DE ATACAR ---
		await get_tree().create_timer(0.2).timeout

		# --- ATAQUE (si está en alcance) ---
		var e = enemies[i]
		if _can_attack(e, player["pos"]):
			# daño por enemigo individual
			var total_atk := int(e["atk"])
			var def_val = max(1, int(player["def"]))
			var dmg := int(floor(float(total_atk) / float(def_val)))
			if dmg > 0:
				player["hp"] -= dmg

				# FX de golpe al player
				_flash_red(player_node)
				_shake_node(player_node, 10.0, 0.15)
				_play_sfx(sfx_enemy_hit)

				if hud:
					hud.set_stats(player)
					
			else:
				_flash_block(player_node)
				_shake_node(player_node, 4.0, 0.12)
				_play_sfx(sfx_block)

			# ¿Derrota?
			if player["hp"] <= 0:
				await _on_defeat()
				return

# --- DRAFT UI (dibujado + clicks) ---
func _draft_layout() -> Dictionary:
	var board_size := Vector2(cols * cell_size.x, rows * cell_size.y)
	var die_size := Vector2(64, 64)
	var slot_size := Vector2(120, 36)
	var button_size := Vector2(160, 36)
	var spacing := 12.0
	
	# Anchos totales
	var total_dice_w := die_size.x * 3 + spacing * 2
	var total_slots_w := slot_size.x * 3 + spacing * 2
	var total_ui_w = max(total_dice_w, total_slots_w)
	
	# Altura total del bloque de draft
	var total_ui_h := die_size.y + 20 + slot_size.y + 20 + button_size.y

	# Origen del panel (centrado en el tablero)
	var ui_start := Vector2(
		(board_size.x - total_ui_w) * 0.5,
		(board_size.y - total_ui_h) * 0.5
	)
	
		# -------- DADOS (alineados a la derecha del panel) --------
	# x0 es el inicio de la fila de dados; se alinea al borde derecho con un margen
	var dice_x0 = ui_start.x + total_ui_w - total_dice_w - dice_right_margin
	# Evitar que se “pisen” hacia la izquierda si el margen es grande
	dice_x0 = max(dice_x0, ui_start.x)

	var die_rects: Array[Rect2] = []
	for i in 3:
		var p := Vector2(dice_x0 + i * (die_size.x + spacing), ui_start.y)
		die_rects.append(Rect2(p, die_size))

	# -------- SLOTS (centrados) --------
	var slots_x0 = ui_start.x + (total_ui_w - total_slots_w) * 0.5
	var slots_y := ui_start.y + die_size.y + 20
	var slots := {
		"mv":  Rect2(Vector2(slots_x0 + 0 * (slot_size.x + spacing), slots_y), slot_size),
		"atk": Rect2(Vector2(slots_x0 + 1 * (slot_size.x + spacing), slots_y), slot_size),
		"def": Rect2(Vector2(slots_x0 + 2 * (slot_size.x + spacing), slots_y), slot_size),
	}

	# -------- CONFIRMAR (centrado) --------
	var confirm_pos := Vector2(
		ui_start.x + total_ui_w - button_size.x - confirm_margin.x,
		ui_start.y + total_ui_h - button_size.y - confirm_margin.y
	)
	var confirm_rect := Rect2(confirm_pos, button_size)

	# Panel oscuro que cubre el tablero
	var panel_rect := Rect2(Vector2.ZERO, board_size)

	return {
		"die_rects": die_rects,
		"slots": slots,
		"confirm": confirm_rect,
		"panel": panel_rect
}

func _handle_draft_hover(local_pos: Vector2) -> void:
	if is_rolling_dice:
		return
	
	var L := _draft_layout()
	var old_hovered_die := draft_hovered_die
	var old_hovered_confirm := draft_hovered_confirm
	draft_hovered_die = -1
	draft_hovered_confirm = false

	# Check if mouse is over any die
	for i in draft_dice.size():
		if L["die_rects"][i].has_point(local_pos):
			draft_hovered_die = i
			break

	# Check if mouse is over confirm button (only when it's visible)
	var can_confirm := _all_assigned()
	if can_confirm and (L["confirm"] as Rect2).has_point(local_pos):
		draft_hovered_confirm = true

	# Redraw if hover state changed
	if old_hovered_die != draft_hovered_die or old_hovered_confirm != draft_hovered_confirm:
		queue_redraw()

func _handle_draft_press(local_pos: Vector2) -> void:
	if is_rolling_dice:
		return
	
	var L := _draft_layout()
	var can_confirm := _all_assigned()
	var old_pressed := draft_pressed_confirm
	draft_pressed_confirm = false

	# Check if pressing confirm button
	if can_confirm and (L["confirm"] as Rect2).has_point(local_pos):
		draft_pressed_confirm = true

	if old_pressed != draft_pressed_confirm:
		queue_redraw()

func _handle_draft_release() -> void:
	var old_pressed := draft_pressed_confirm
	draft_pressed_confirm = false

	if old_pressed:
		queue_redraw()

func _handle_draft_click(local_pos: Vector2) -> void:
	if is_rolling_dice:
		return
	
	var L := _draft_layout()
	# Click en dados
	for i in draft_dice.size():
		if L["die_rects"][i].has_point(local_pos):
			# si ese dado ya estaba asignado a un slot, lo “desasignamos”
			if _die_assigned(i):
				for k in draft_assign_idx.keys():
					if draft_assign_idx[k] == i:
						draft_assign_idx[k] = -1
						break
			draft_selected_die = i
			queue_redraw()
			return

	# Click en slots
	for k in ["mv","atk","def"]:
		var r: Rect2 = L["slots"][k]
		if r.has_point(local_pos):
			# si el slot ya tenía un dado y no hay selección, levantamos ese dado
			if draft_selected_die == -1 and draft_assign_idx[k] != -1:
				draft_selected_die = draft_assign_idx[k]
				draft_assign_idx[k] = -1
			# si hay un dado seleccionado, lo ponemos aquí (si estaba en otro slot, se mueve)
			elif draft_selected_die != -1:
				# quitar de cualquier otro slot
				for kk in draft_assign_idx.keys():
					if draft_assign_idx[kk] == draft_selected_die:
						draft_assign_idx[kk] = -1
				draft_assign_idx[k] = draft_selected_die
				draft_selected_die = -1
			queue_redraw()
			return

	# Click en Confirmar
	var can_confirm := _all_assigned() and not is_rolling_dice
	if can_confirm and (L["confirm"] as Rect2).has_point(local_pos):
		player["mv"]  = P_STATS["mv"]  + draft_dice[draft_assign_idx["mv"]]
		player["atk"] = P_STATS["atk"] + draft_dice[draft_assign_idx["atk"]]
		player["def"] = P_STATS["def"] + draft_dice[draft_assign_idx["def"]]
		player["rng"] = P_STATS["rng"]

		moves_left = player["mv"]
		is_drafting = false
		player_attacked_this_turn = false
		if hud: 
			hud.set_stats(player)
		_update_astar_solid_tiles()
		_sync_player_sprite()
		queue_redraw()
		_maybe_auto_end_turn()
		return

func _draw_draft_ui() -> void:
	var L := _draft_layout()
	# fondo semitransparente sobre el tablero
	draw_rect(L["panel"], Color(0,0,0,0.35), true)

	var font := ThemeDB.fallback_font
	var fs := 16

	# dados
	for i in draft_dice.size():
		var r: Rect2 = L["die_rects"][i]
		var is_assigned := _die_assigned(i)
		var is_selected := (draft_selected_die == i)
		var is_hovered := (draft_hovered_die == i)

		# Background color with hover and selected states
		var bg_color: Color
		if is_selected:
			# Gray with reduced opacity for selected state
			bg_color = Color(0.4, 0.4, 0.4, 0.8)
		elif is_hovered and not is_assigned:
			# Lighter black for hover
			bg_color = Color(0.15, 0.15, 0.15, 1)
		else:
			# Black background
			bg_color = Color(0, 0, 0, 1)

		draw_rect(r, bg_color, true)
		draw_rect(r, Color(1,1,1,1), false, 2.0)

		var txt := str(draft_dice[i])
		var txt_size := font.get_string_size(txt, fs)
		var pos := Vector2(
			r.position.x + (r.size.x - txt_size.x) * 0.5,
			r.position.y + (r.size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs)
		)
		var ts := font.get_string_size(txt, fs)
		var col
		if is_assigned:
			col = Color(0.8,0.8,0.8,0.7)
		else:
			col = Color(1,1,1,1)

		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# slots
	for k in ["mv","atk","def"]:
		var r2: Rect2 = L["slots"][k]
		var idx = draft_assign_idx[k]

		# fondo + borde
		var hovered := r2.has_point(to_local(get_viewport().get_mouse_position()))
		var bg_col
		
		if hovered:
			bg_col = Color(0.12,0.12,0.12,1)
		else:
			bg_col = Color(0.10,0.10,0.10,1)
		
		draw_rect(r2, bg_col, true)
		draw_rect(r2, Color(1,1,1,1), false, 2.0)

		# ícono del slot
		var icon: Texture2D = null
		if k == "mv":  icon = slot_icon_mv
		if k == "atk": icon = slot_icon_atk
		if k == "def": icon = slot_icon_def

		var icon_rect := Rect2(
			r2.position + Vector2(6, (r2.size.y - slot_icon_size.y) * 0.5),
			slot_icon_size
		)

		if icon:
			draw_texture_rect(icon, icon_rect, false)
		else:
			# fallback a label si no asignaste ícono
			var label := String(k).to_upper()
			draw_string(font, r2.position + Vector2(8, r2.size.y*0.6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))

		# valor (si hay dado asignado)
		var txt
		if idx == -1:
			txt = ""
		else:
			txt = str(draft_dice[idx])
		
		var txt_size := font.get_string_size(txt, fs)
		var value_x
		
		if icon:
			value_x = icon_rect.position.x + slot_icon_size.x + 10
		else:
			value_x = icon_rect.position.x + 10
		
		if icon:
			value_x = icon_rect.position.x + (slot_icon_size.x) + 10
		else:
			value_x = icon_rect.position.x + 10
		
		var value_pos := Vector2(
			value_x,
			r2.position.y + (r2.size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs)
		)
		draw_string(font, value_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))
		
		# ---- CONFIRMAR ----
		var can_confirm := _all_assigned()
		if can_confirm:
			var rc: Rect2 = L["confirm"]
			var confirm_bg_color: Color
			if draft_pressed_confirm:
				confirm_bg_color = Color(0.2, 0.2, 0.2, 1)
			elif draft_hovered_confirm:
				confirm_bg_color = Color(0.15, 0.15, 0.15, 1)
			else:
				confirm_bg_color = Color(0, 0, 0, 1)
			draw_rect(rc, confirm_bg_color, true)
			draw_rect(rc, Color(1,1,1,1), false, 2.0)

			var ctxt := "Confirmar"
			var csize := font.get_string_size(ctxt, fs)
			var cx := rc.position.x + (rc.size.x - csize.x) * 0.5
			var cy := rc.position.y + (rc.size.y - font.get_height(fs)) * 0.5 + font.get_ascent(fs)
			draw_string(font, Vector2(cx, cy), ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))

# --- drawing ---
func _draw() -> void:
	# tablero
	for y in range(rows):
		for x in range(cols):
			var r := Rect2(Vector2(x, y) * Vector2(cell_size), Vector2(cell_size))
			draw_rect(r, grid_color, true)
			draw_rect(r, grid_border_color, false, 1.0)

	# pilares
	for p in pillars.keys():
		var cell_pos := Vector2(p) * Vector2(cell_size)
		var cell_rect := Rect2(cell_pos, Vector2(cell_size))
		if pillar_texture:
			var target_size := Vector2(cell_size) * pillar_fill
			var offset := (Vector2(cell_size) - target_size) * 0.5
			var dst := Rect2(cell_pos + offset, target_size)
			draw_texture_rect(pillar_texture, dst, false)
		else:
			draw_rect(cell_rect, Color(0.35, 0.35, 0.4, 1.0), true)

	# UI de dados encima
	if is_drafting:
		_draw_draft_ui()
		
	# HUD de HP de enemigos (siempre encima)
	_draw_enemy_hp_hud()
		
func _draw_stats_hud() -> void:
	var board_w := float(cols * cell_size.x)
	var board_h := float(rows * cell_size.y)

	var font := ThemeDB.fallback_font
