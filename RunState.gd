# res://autoload/RunState.gd
extends Node

var initialized := false
var level := 1
var player_hp := 6  # se persiste entre niveles
var rng := RandomNumberGenerator.new()

# Definición de niveles (enemigos, pilares, posiciones, stats por nivel)
const LEVELS := {
	1: {
		"player_start": Vector2i(0, 4),  
		"pillars": [Vector2i(1,3), Vector2i(1,1), Vector2i(3,1)],
		"enemy_base": {"hp": 2, "mv": 5, "atk": 4, "def": 4, "rng": 3},
		"enemy_sprite": "goblin",
		"enemies": [
			{"name":"goblin 1","pos": Vector2i(2, 0)},
			{"name":"goblin 2","pos": Vector2i(3, 2)},
		],
	},
	2: {
		"player_start": Vector2i(3, 4),
		"pillars": [Vector2i(0, 2), Vector2i(3, 2), Vector2i(3, 3)],
		# Stats pedidos: 3 hp, 4 mv, 5 atk, 4 def, 4 rng
		"enemy_base": {"hp": 3, "mv": 4, "atk": 5, "def": 4, "rng": 4},
		"enemy_sprite": "skeleton",
		"enemies": [
			{"name":"skeleton 1","pos": Vector2i(2, 0)},
			{"name":"skeleton 2","pos": Vector2i(0, 1)},
		],
	},
	3: {
		"player_start": Vector2i(0, 4),
		"pillars": [Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 3)],
		# Stats pedidos: 3 hp, 4 mv, 5 atk, 4 def, 4 rng
		"enemy_base": {"hp": 5, "mv": 3, "atk": 7, "def": 7, "rng": 2},
		"enemy_sprite": "orc",
		"enemies": [
			{"name":"orc1","pos": Vector2i(3, 1)},
		],
	},
	4: {
		"player_start": Vector2i(4, 4),
		"pillars": [Vector2i(1, 1), Vector2i(1, 2), Vector2i(4, 2)],
		# Stats pedidos: 3 hp, 4 mv, 5 atk, 4 def, 4 rng
		"enemy_base": {"hp": 5, "mv": 5, "atk": 5, "def": 5, "rng": 5},
		"enemies": [
			{"name":"orc1","pos": Vector2i(1, 0)},
		],
	},
	5: {
		"player_start": Vector2i(0, 4),
		"pillars": [Vector2i(3, 1), Vector2i(1, 3), Vector2i(3, 3)],
		# Stats pedidos: 3 hp, 4 mv, 5 atk, 4 def, 4 rng
		"enemy_base": {"hp": 2, "mv": 5, "atk": 4, "def": 4, "rng": 3},
		"enemy_sprite": "spider",
		"enemies": [
			{"name":"spider 1","pos": Vector2i(0, 1)},
			{"name":"spider 2","pos": Vector2i(1, 4)},
			{"name":"spider 3","pos": Vector2i(4, 4)},

		],
	},
}

func reset_run() -> void:
	rng.randomize()
	initialized = true
	level = 1
	player_hp = 6

func next_level() -> void:
	level += 1

func get_level_def(l:int) -> Dictionary:
	return LEVELS.get(l, LEVELS[1])
