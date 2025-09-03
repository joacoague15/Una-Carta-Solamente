extends Node2D
class_name Level1

@export var cols := 4
@export var rows := 5
@export var cell_size := Vector2i(96, 96)

const P_STATS = { "hp": 6, "mv": 1, "atk": 2, "def": 2, "rng": 1 }
const E_STATS = { "hp": 2, "mv": 1, "atk": 1, "def": 1, "rng": 1 }

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

# hover de mouse para mostrar stats del enemigo
var hover_cell: Vector2i = Vector2i(-1, -1)

# --- helpers ---
func _enemy_index_at(cell: Vector2i) -> int:
	for i in enemies.size():
		if enemies[i]["pos"] == cell:
			return i
	return -1

func _mouse_to_cell(mpos: Vector2) -> Vector2i:
	var local := mpos - global_position
	return Vector2i(floor(local.x / cell_size.x), floor(local.y / cell_size.y))

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

func _in_range(a: Vector2i, b: Vector2i, rng:int) -> bool:
	return _manhattan(a, b) <= rng

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# --- setup ---
func _ready() -> void:
	_init_astar()
	_update_astar_solid_tiles()
	queue_redraw()

func _init_astar() -> void:
	astar.region = Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	astar.cell_size = Vector2(cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
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
	# track hover para UI
	if event is InputEventMouseMotion:
		var c := _mouse_to_cell(event.position)
		if _is_inside(c) and c != hover_cell:
			hover_cell = c
			queue_redraw()

	if phase == Phase.PLAYER:
		# Click para mover/atacar
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var cell := _mouse_to_cell(get_viewport().get_mouse_position())
			_on_player_click(cell)

		# Teclado opcional
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_W, KEY_UP]:
				_try_move_player(Vector2i(0, -1))
			elif event.keycode in [KEY_S, KEY_DOWN]:
				_try_move_player(Vector2i(0, 1))
			elif event.keycode in [KEY_A, KEY_LEFT]:
				_try_move_player(Vector2i(-1, 0))
			elif event.keycode in [KEY_D, KEY_RIGHT]:
				_try_move_player(Vector2i(1, 0))
			elif event.keycode == KEY_ENTER:
				_end_player_turn()

func _on_player_click(cell: Vector2i) -> void:
	if not _is_inside(cell):
		return

	# 1) Click enemigo adyacente → atacar
	var idx := _enemy_index_at(cell)
	if idx != -1 and _manhattan(player["pos"], cell) == 1:
		_player_attack(idx)
		return

	# 2) Click casillero vacío → moverse por path (hasta moves_left)
	if _is_blocked(cell) or moves_left <= 0:
		return

	_update_astar_solid_tiles()
	astar.set_point_solid(player["pos"], false)
	astar.set_point_solid(cell, false)

	var path := astar.get_id_path(player["pos"], cell)
	if path.is_empty():
		_update_astar_solid_tiles()
		return

	var steps = min(moves_left, path.size() - 1)
	if steps <= 0:
		_update_astar_solid_tiles()
		return

	player["pos"] = path[steps]
	moves_left -= steps

	_update_astar_solid_tiles()
	queue_redraw()

	if moves_left <= 0:
		_end_player_turn()

func _try_move_player(dir: Vector2i) -> void:
	if moves_left <= 0:
		return
	var target = player["pos"] + dir
	if _is_inside(target) and not _is_blocked(target):
		player["pos"] = target
		moves_left -= 1
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
	for i in enemies.size():
		_update_astar_solid_tiles()
		astar.set_point_solid(enemies[i]["pos"], false)

		# Si ya está adyacente, ataca; si no, mover y luego atacar si llega
		if not _in_range(enemies[i]["pos"], player["pos"], enemies[i]["rng"]):
			# path a una casilla adyacente al jugador
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
				var steps = min(enemies[i]["mv"], best_path.size() - 1) # primer punto = pos actual
				if steps > 0:
					enemies[i]["pos"] = best_path[steps]

		_update_astar_solid_tiles()

		# atacar si quedó en rango
		if _in_range(enemies[i]["pos"], player["pos"], enemies[i]["rng"]):
			_enemy_attack(i)

func _enemy_attack(i:int) -> void:
	var e = enemies[i]
	# Daño = floor(enemigo.atk / player.def), acumulable si varios pegan.
	var def_val = max(1, player["def"]) # evitar div/0
	var dmg := int(floor(float(e["atk"]) / float(def_val)))
	player["hp"] -= dmg
	if player["hp"] <= 0:
		print("Player defeated")

# --- drawing / HUD ---
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

	# unidades
	_draw_unit(player["pos"], Color(0.2,0.8,1.0,1.0))
	for e in enemies:
		_draw_unit(e["pos"], Color(1.0,0.35,0.35,1.0))

	# HUD: jugador (arriba-izquierda)
	var font := ThemeDB.fallback_font
	var font_size := 18
	var hp_text := "Player HP: %d | ATK:%d DEF:%d RNG:%d" % [player["hp"], player["atk"], player["def"], player["rng"]]
	draw_string(font, Vector2(8, 18), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1,1,1,1))

	# HUD: enemigo (arriba-derecha): el que esté bajo el mouse (si hay)
	var idx := _enemy_index_at(hover_cell)
	var enemy_text := "Enemy: —"
	if idx != -1:
		var ee = enemies[idx]
		enemy_text = "%s HP:%d ATK:%d DEF:%d RNG:%d" % [ee["name"], ee["hp"], ee["atk"], ee["def"], ee["rng"]]
	# esquina derecha con margen
	var right_x := float(cols * cell_size.x) - 260.0
	draw_string(font, Vector2(right_x, 18), enemy_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1,1,1,1))

func _draw_unit(cell: Vector2i, col: Color) -> void:
	var r := Rect2(Vector2(cell) * Vector2(cell_size), Vector2(cell_size))
	var inset := 8.0
	var rr := Rect2(r.position + Vector2(inset, inset), r.size - Vector2(2*inset, 2*inset))
	draw_rect(rr, col, true)
