extends Node2D
class_name Level1

@export var cols := 4
@export var rows := 5
@export var cell_size := Vector2i(96, 96)

const P_STATS = { "hp": 6, "mv": 4, "atk": 2, "def": 2, "rng": 2 }
const E_STATS = { "hp": 2, "mv": 3, "atk": 1, "def": 1, "rng": 2 }

var astar := AStarGrid2D.new()

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

# --- setup ---
func _ready() -> void:
	_init_astar()
	_update_astar_solid_tiles()
	_layout_board()
	get_viewport().size_changed.connect(_on_viewport_resized)
	queue_redraw()

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
		
func _move_cost(a: Vector2i, b: Vector2i) -> int:
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	# adyacente ortogonal
	if dx + dy == 1:
		return 2
	# adyacente diagonal
	if dx == 1 and dy == 1:
		return 3
	# no es adyacente
	return -1

# Costo de alcance (igual a movimiento: diag=3, orto=2)
func _reach_cost(a: Vector2i, b: Vector2i) -> int:
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	var diag = min(dx, dy)
	var orto = abs(dx - dy)
	return diag * 3 + orto * 2
	
func _can_attack(attacker: Dictionary, target_pos: Vector2i) -> bool:
	return _reach_cost(attacker["pos"], target_pos) <= int(attacker["rng"])

# --- input / turns ---
func _input(event: InputEvent) -> void:
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
		# ¿está al alcance según el rango? (usa puntos 2/3)
		if _can_attack(player, enemies[idx]["pos"]):
			_player_attack(idx)
			moves_left = 0  # o moves_left -= 1 si querés que cueste punto de acción
			_update_astar_solid_tiles()
			queue_redraw()
			_end_player_turn()
		# si no está al alcance, no hace nada
		return

	# Si es celda vacía: sólo permitir mover adyacente y con puntos suficientes
	var cost := _move_cost(player["pos"], cell)
	if cost == -1:
		return  # no es adyacente (ni orto ni diag)
	if _is_blocked(cell):
		return
	if moves_left < cost:
		return

	player["pos"] = cell
	moves_left -= cost
	_update_astar_solid_tiles()
	queue_redraw()

	if moves_left <= 0:
		_end_player_turn()

func _player_attack(enemy_index:int) -> void:
	var e = enemies[enemy_index]
	var dmg = max(0, player["atk"] - e["def"])
	e["hp"] -= dmg
	if e["hp"] <= 0:
		enemies.remove_at(enemy_index)
	_update_astar_solid_tiles()
	queue_redraw()

func _end_player_turn() -> void:
	phase = Phase.ENEMIES
	_enemy_phase()
	phase = Phase.PLAYER
	moves_left = player["mv"]
	_update_astar_solid_tiles()
	queue_redraw()

func _enemy_phase() -> void:
	# 1) cada enemigo intenta acercarse, gastando su "mv" en pasos de 2/3
	for i in enemies.size():
		var budget := int(enemies[i]["mv"])
		if budget < 2:
			continue  # no le alcanza ni para un paso ortogonal

		_update_astar_solid_tiles()
		astar.set_point_solid(enemies[i]["pos"], false)

		# si ya está adyacente, no camina
		if _manhattan(enemies[i]["pos"], player["pos"]) != 1:
			# objetivos: celdas ortogonalmente adyacentes al player que no estén bloqueadas
			var goals := _adjacent_cells(player["pos"]).filter(
				func(c): return _is_inside(c) and not _is_blocked_for_enemy(c, i)
			)
			if goals.is_empty():
				goals = [player["pos"]]  # fallback

			# mejor path a alguna goal
			var best_path := []
			for g in goals:
				var p := astar.get_id_path(enemies[i]["pos"], g)
				if p.is_empty():
					continue
				if best_path.is_empty() or p.size() < best_path.size():
					best_path = p

			# avanzar paso a paso mientras alcance el budget
			if not best_path.is_empty():
				var curr = enemies[i]["pos"]
				for step_idx in range(1, best_path.size()):
					var nxt : Vector2i = best_path[step_idx]
					# por si otro enemigo se metió: chequeo de bloqueo dinámico
					if _is_blocked_for_enemy(nxt, i):
						break

					var step_cost := _move_cost(curr, nxt)
					if step_cost == -1 or budget < step_cost:
						break

					curr = nxt
					budget -= step_cost
					enemies[i]["pos"] = curr
					# si ya quedó adyacente, podés cortar
					if _manhattan(enemies[i]["pos"], player["pos"]) == 1:
						break

		_update_astar_solid_tiles()

	# 2) daño combinado de todos los enemigos cuyo alcance (2/3) llegue al player
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

	# Player + etiqueta
	var player_label := "HP:%d MV:%d ATK:%d DEF:%d RNG:%d" % [
		player["hp"], player["mv"], player["atk"], player["def"], player["rng"]
	]
	_draw_unit_with_label(player["pos"], Color(0.2,0.8,1.0,1.0), player_label)

	# Enemigos + etiqueta
	for e in enemies:
		var enemy_label := "%s  HP:%d ATK:%d DEF:%d RNG:%d" % [
			e["name"], e["hp"], e["atk"], e["def"], e["rng"]
		]
		_draw_unit_with_label(e["pos"], Color(1.0,0.35,0.35,1.0), enemy_label)

func _draw_unit_with_label(cell: Vector2i, col: Color, label_text: String) -> void:
	var r := Rect2(Vector2(cell) * Vector2(cell_size), Vector2(cell_size))
	var inset := 8.0
	var rr := Rect2(r.position + Vector2(inset, inset), r.size - Vector2(2*inset, 2*inset))
	draw_rect(rr, col, true)
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
