extends Node2D
class_name Level1

@onready var PlayerScene := preload("res://Player.tscn")
@onready var EnemyScene := preload("res://Enemy.tscn")

var player_node: Player
var enemy_nodes: Array[Enemy] = []

@export var cols := 4
@export var rows := 5
@export var cell_size := Vector2i(96, 96)

const P_STATS = { "hp": 6, "mv": 1, "atk": 1, "def": 1, "rng": 2 }
const E_STATS = { "hp": 2, "mv": 3, "atk": 1, "def": 1, "rng": 2 }

var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()

# --- DRAFT / DADOS ---
var is_drafting := true
var draft_dice: Array[int] = []
var draft_assign_idx := {"mv": -1, "atk": -1, "def": -1} # guarda índices 0..2 de draft_dice
var draft_selected_die := -1

func _roll_dice() -> void:
	draft_dice = [rng.randi_range(1, 6), rng.randi_range(1, 6), rng.randi_range(1, 6)]
	draft_assign_idx = {"mv": -1, "atk": -1, "def": -1}
	draft_selected_die = -1
	is_drafting = true
	queue_redraw()

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
		"name": "spider1",
		"pos": rc(1, 4),
		"hp": E_STATS["hp"],
		"mv": E_STATS["mv"],
		"atk": E_STATS["atk"],
		"def": E_STATS["def"],
		"rng": E_STATS["rng"],
	},
	{
		"name": "spider2",
		"pos": rc(3, 4),
		"hp": E_STATS["hp"],
		"mv": E_STATS["mv"],
		"atk": E_STATS["atk"],
		"def": E_STATS["def"],
		"rng": E_STATS["rng"],
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

func _can_attack(attacker: Dictionary, target_pos: Vector2i) -> bool:
	return _reach_cost(attacker["pos"], target_pos) <= int(attacker["rng"])

# --- setup ---
func _ready() -> void:
	player_node = PlayerScene.instantiate()
	add_child(player_node)
	
	_layout_board()  # primero escala/centra el tablero
	player_node.set_cell(player["pos"], cell_size, false)  # sin animación
	
	rng.randomize()
	_roll_dice()  # mostrar UI de dados al inicio

	_init_astar()
	_update_astar_solid_tiles()
	get_viewport().size_changed.connect(_on_viewport_resized)
	queue_redraw()
	
	for e in enemies:
		var n: Enemy = EnemyScene.instantiate()
		add_child(n)
		
		n.set_cell(e["pos"], cell_size, false)
		enemy_nodes.append(n)

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
			astar.set_point_solid(Vector2i(x, y), false)
	for p in pillars.keys():
		astar.set_point_solid(p, true)
	astar.set_point_solid(player["pos"], true)
	for e in enemies:
		astar.set_point_solid(e["pos"], true)

# --- input / turns ---
func _input(event: InputEvent) -> void:
	# Primero, si estamos en la UI de dados, consumimos el input ahí.
	if is_drafting:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_draft_click(to_local(get_viewport().get_mouse_position()))
		return

	if phase != Phase.PLAYER:
		return

	# Sólo mouse (click izquierdo)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _mouse_to_cell(get_viewport().get_mouse_position())
		_on_player_click(cell)

func _on_player_click(cell: Vector2i) -> void:
	if not _is_inside(cell) or moves_left <= 0:
		return

	# ¿click a un enemigo?
	var idx := _enemy_index_at(cell)
	if idx != -1:
		if _can_attack(player, enemies[idx]["pos"]):
			_player_attack(idx)
			moves_left = 0
			_update_astar_solid_tiles()
			_sync_player_sprite()
			queue_redraw()
			_end_player_turn()
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

	if moves_left <= 0:
		_end_player_turn()

func _player_attack(enemy_index:int) -> void:
	var e = enemies[enemy_index]
	var dmg = max(0, player["atk"] - e["def"])
	e["hp"] -= dmg
	if e["hp"] <= 0:
		# eliminar data y sprite en el mismo índice
		enemies.remove_at(enemy_index)
		var node := enemy_nodes[enemy_index]
		enemy_nodes.remove_at(enemy_index)
		if is_instance_valid(node):
			node.queue_free()
	_update_astar_solid_tiles()
	_sync_enemy_sprites(false) # reacomoda índices por si quedaron corridos
	queue_redraw()

func _end_player_turn() -> void:
	phase = Phase.ENEMIES
	_enemy_phase()
	_sync_enemy_sprites(true)
	phase = Phase.PLAYER
	moves_left = player["mv"]
	_update_astar_solid_tiles()
	queue_redraw()

func _enemy_phase() -> void:
	# 1) mover con presupuesto (2/3 por paso) hacia adyacencia
	for i in enemies.size():
		var budget := int(enemies[i]["mv"])
		if budget < 2:
			continue

		_update_astar_solid_tiles()
		astar.set_point_solid(enemies[i]["pos"], false)

		if _manhattan(enemies[i]["pos"], player["pos"]) != 1:
			var goals := _adjacent_cells(player["pos"]).filter(
				func(c): return _is_inside(c) and not _is_blocked_for_enemy(c, i)
			)
			if goals.is_empty():
				goals = [player["pos"]]
			var best_path := []
			for g in goals:
				var p := astar.get_id_path(enemies[i]["pos"], g)
				if p.is_empty(): continue
				if best_path.is_empty() or p.size() < best_path.size():
					best_path = p
			if not best_path.is_empty():
				var curr = enemies[i]["pos"]
				for step_idx in range(1, best_path.size()):
					var nxt: Vector2i = best_path[step_idx]
					if _is_blocked_for_enemy(nxt, i): break
					var step_cost := _move_cost(curr, nxt)
					if step_cost == -1 or budget < step_cost: break
					curr = nxt
					budget -= step_cost
					enemies[i]["pos"] = curr
					if _manhattan(enemies[i]["pos"], player["pos"]) == 1:
						break
		_update_astar_solid_tiles()

	# 2) daño combinado por alcance (2/3)
	var total_atk := 0
	for e in enemies:
		if _can_attack(e, player["pos"]):
			total_atk += int(e["atk"])
	if total_atk > 0:
		var def_val = max(1, int(player["def"]))
		var dmg := int(floor(float(total_atk) / float(def_val)))
		player["hp"] -= dmg
	if player["hp"] <= 0:
		print("Player defeated")

# --- DRAFT UI (dibujado + clicks) ---
func _draft_layout() -> Dictionary:
	# Layout base en coordenadas locales del tablero
	var pad := 12.0
	var die_size := Vector2(64, 64)
	var spacing := 12.0
	var base := Vector2(pad, pad)
	var die_rects: Array[Rect2] = []
	for i in 3:
		die_rects.append(Rect2(base + Vector2((die_size.x + spacing) * i, 0), die_size))
	var slot_size := Vector2(120, 36)
	var slots := {
		"mv": Rect2(base + Vector2(0, die_size.y + 20), slot_size),
		"atk": Rect2(base + Vector2(130, die_size.y + 20), slot_size),
		"def": Rect2(base + Vector2(260, die_size.y + 20), slot_size),
	}
	var confirm_rect := Rect2(base + Vector2(0, die_size.y + 20 + 48), Vector2(140, 36))
	var panel_rect := Rect2(Vector2.ZERO, Vector2(cols * cell_size.x, rows * cell_size.y))
	return {
		"die_rects": die_rects,
		"slots": slots,
		"confirm": confirm_rect,
		"panel": panel_rect
	}

func _handle_draft_click(local_pos: Vector2) -> void:
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
	var can_confirm := _all_assigned()
	if can_confirm and (L["confirm"] as Rect2).has_point(local_pos):
		player["mv"]  = P_STATS["mv"]  + draft_dice[draft_assign_idx["mv"]]
		player["atk"] = P_STATS["atk"] + draft_dice[draft_assign_idx["atk"]]
		player["def"] = P_STATS["def"] + draft_dice[draft_assign_idx["def"]]
		player["rng"] = P_STATS["rng"]

		moves_left = player["mv"]
		is_drafting = false
		_update_astar_solid_tiles()
		_sync_player_sprite()
		queue_redraw()
		return

func _draw_draft_ui() -> void:
	var L := _draft_layout()
	# fondo semitransparente sobre el tablero
	draw_rect(L["panel"], Color(0,0,0,0.35), true)

	var font := ThemeDB.fallback_font
	var fs := 16

	# título
	var title := "Asigná los dados a MV / ATK / DEF"
	var title_size := font.get_string_size(title, fs)
	draw_string(font, Vector2(12, -8 + fs + 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))

	# dados
	for i in draft_dice.size():
		var r: Rect2 = L["die_rects"][i]
		var is_assigned := _die_assigned(i)
		var is_selected := (draft_selected_die == i)
		if is_selected:
			draw_rect(r, Color(0.25,0.5,1,1), true)
		else:
			draw_rect(r, Color(0.2,0.2,0.2,1), true)
		
		draw_rect(r, Color(1,1,1,1), false, 2.0)
		var txt := str(draft_dice[i])
		var ts := font.get_string_size(txt, fs)
		var pos := r.position + (r.size - ts) * 0.5 + Vector2(0, fs*0.2)
		var col
		if is_assigned:
			col = Color(0.8,0.8,0.8,0.7)
		else:
			col = Color(1,1,1,1)	
		
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# slots
	for k in ["mv","atk","def"]:
		var r2: Rect2 = L["slots"][k]
		var label := String(k).to_upper()
		var idx = draft_assign_idx[k]
		var txt
		
		if idx == -1:
			txt = label + ": —"
		else:
			txt =  label + ": " + str(draft_dice[idx])
		
		draw_rect(r2, Color(0.1,0.1,0.1,1), true)
		draw_rect(r2, Color(1,1,1,1), false, 2.0)
		draw_string(font, r2.position + Vector2(8, r2.size.y*0.6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))

	# botón confirmar
	var can_confirm := _all_assigned()
	var rc: Rect2 = L["confirm"]
	
	if can_confirm:
		draw_rect(rc, Color(0.15,0.45,0.15,1), true)
	else:
		draw_rect(rc, Color(0.2,0.2,0.2,1), true)
		
	draw_rect(rc, Color(1,1,1,1), false, 2.0)
	draw_string(font, rc.position + Vector2(8, rc.size.y*0.6), "Confirmar", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))

# --- drawing ---
func _draw() -> void:
	# tablero
	for y in range(rows):
		for x in range(cols):
			var r := Rect2(Vector2(x, y) * Vector2(cell_size), Vector2(cell_size))
			draw_rect(r, Color(0.12,0.12,0.12,1.0), true)
			draw_rect(r, Color(0.25,0.25,0.25,1.0), false, 2.0)

	# pilares
	for p in pillars.keys():
		var rr := Rect2(Vector2(p) * Vector2(cell_size), Vector2(cell_size))
		draw_rect(rr, Color(0.35,0.35,0.4,1.0), true)

	# unidades con etiquetas
	var player_label := "HP:%d MV:%d ATK:%d DEF:%d RNG:%d" % [
		player["hp"], player["mv"], player["atk"], player["def"], player["rng"]
	]
	var player_cell_rect := Rect2(Vector2(player["pos"]) * Vector2(cell_size), Vector2(cell_size))
	_draw_unit_label(player_cell_rect, player_label, player["pos"].y == 0)

	for e in enemies:
		var enemy_label := "%s  HP:%d ATK:%d DEF:%d RNG:%d" % [
			e["name"], e["hp"], e["atk"], e["def"], e["rng"]
		]
		_draw_unit_with_label(e["pos"], Color(1.0,0.35,0.35,1.0), enemy_label)

	# UI de dados encima
	if is_drafting:
		_draw_draft_ui()

func _draw_unit_with_label(cell: Vector2i, col: Color, label_text: String) -> void:
	var r := Rect2(Vector2(cell) * Vector2(cell_size), Vector2(cell_size))
	var inset := 8.0
	var rr := Rect2(r.position + Vector2(inset, inset), r.size - Vector2(2*inset, 2*inset))
	_draw_unit_label(r, label_text, cell.y == 0)

func _draw_unit_label(cell_rect: Rect2, text: String, is_top_row: bool=false) -> void:
	var font := ThemeDB.fallback_font
	var fs := 14
	var pad := Vector2(6, 4)
	var text_size: Vector2 = font.get_string_size(text, fs)
	var top_left_x := cell_rect.position.x + (cell_rect.size.x - text_size.x) * 0.5
	var top_left_y := cell_rect.position.y - fs - 6
	if is_top_row and top_left_y < 0.0:
		top_left_y = cell_rect.position.y + cell_rect.size.y + 6
	var bg_rect := Rect2(Vector2(top_left_x, top_left_y) - pad, text_size + pad * 2.0)
	draw_rect(bg_rect, Color(0,0,0,0.6), true)
	var baseline := top_left_y + fs
	draw_string(font, Vector2(top_left_x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1,1,1,1))
