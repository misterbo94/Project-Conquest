# BaseMap.gd - Versione SEMPLICE
extends TileMapLayer
class_name BaseMap

var voronoi_map: Dictionary = {}
@onready var input_handler: InputHandler

func _ready():
	print("BaseMap SIMPLE inizializzazione...")
	_setup_dependencies()
	_initialize_map()
	print("BaseMap SIMPLE completato")

func _setup_dependencies():
	input_handler = get_node("InputHandler") as InputHandler
	if input_handler:
		input_handler.region_clicked.connect(_on_region_clicked)
	
	GameStateManager.textures_updated.connect(_on_textures_updated)

func _initialize_map():
	if material:
		material = material.duplicate()
	
	calculate_voronoi_map()
	GameStateManager.initialize_regions(voronoi_map)
	_setup_shader_parameters()

# === SHADER SETUP v2.3 ===
func _setup_shader_parameters():
	if not material:
		return
	
	var tile_size = tile_set.tile_size
	var world_to_local_matrix = get_global_transform().affine_inverse()
	var box_origin = map_to_local(Vector2i(0, 0))
	var diamond_tip_offset = Vector2(box_origin.x, box_origin.y - tile_size.y / 2.0)

	# Parametri base
	material.set_shader_parameter("grid_origin_offset", diamond_tip_offset)
	material.set_shader_parameter("world_to_local_transform", world_to_local_matrix)
	material.set_shader_parameter("tile_half_width", tile_size.x / 2.0)
	material.set_shader_parameter("tile_half_height", tile_size.y / 2.0)
	material.set_shader_parameter("map_size_in_tiles", Vector2(GameStateManager.MAP_SIZE))
	
	# ✅ PARAMETRI CONST DAL GAMESTATE MANAGER
	material.set_shader_parameter("gradient_tiles", GameStateManager.GRADIENT_TILES)
	material.set_shader_parameter("max_dot_size", GameStateManager.MAX_DOT_SIZE)
	
	# Texture
	material.set_shader_parameter("control_texture", GameStateManager.control_texture)
	material.set_shader_parameter("animation_texture", GameStateManager.animation_texture)
	
	print("Shader SIMPLE configurato con parametri const")

# [Il resto delle funzioni voronoi rimane uguale...]
func calculate_voronoi_map():
	print("Calcolo Voronoi...")
	voronoi_map.clear()
	
	var all_cells = get_used_cells()
	var mothers = _find_mother_tiles(all_cells)
	
	if mothers.is_empty():
		print("ERRORE: Nessuna tile madre trovata!")
		return
	
	for cell in all_cells:
		if cell.x < 0 or cell.x >= GameStateManager.MAP_SIZE.x or \
		   cell.y < 0 or cell.y >= GameStateManager.MAP_SIZE.y:
			continue
		
		var closest_mother = _find_closest_mother(cell, mothers)
		voronoi_map[cell] = closest_mother

func _find_mother_tiles(cells: Array) -> Array:
	var mothers = []
	for cell in cells:
		var tile_data = get_cell_tile_data(cell)
		if tile_data and tile_data.get_custom_data("mother_type"):
			mothers.append(cell)
	return mothers

func _find_closest_mother(cell: Vector2i, mothers: Array) -> Vector2i:
	if mothers.is_empty():
		return Vector2i(-1, -1)
	
	var min_dist = 999999
	var closest = mothers[0]
	
	for mother in mothers:
		var dist = cell.distance_squared_to(mother)
		if dist < min_dist:
			min_dist = dist
			closest = mother
	return closest

# === CALLBACKS v2.0 ===
func _on_region_clicked(_screen_pos: Vector2):  # ✅ FIX: Prefisso _ per parametro non usato
	print("BaseMap v2.3: Click ricevuto")
	
	var global_pos = get_global_mouse_position()
	var local_pos = to_local(global_pos)
	var tile_coord = local_to_map(local_pos)
	
	if tile_coord.x < 0 or tile_coord.x >= 36 or tile_coord.y < 0 or tile_coord.y >= 36:
		print("  Tile fuori bounds!")
		return
	
	if voronoi_map.has(tile_coord):
		var mother = voronoi_map[tile_coord]
		print("  Madre: ", mother)
		GameStateManager.cycle_region_state(mother)

func _on_textures_updated(control_tex: ImageTexture, animation_tex: ImageTexture):
	"""Callback per aggiornamento texture doppie"""
	print("BaseMap v2.3: Texture aggiornate ricevute")
	if material:
		material.set_shader_parameter("control_texture", control_tex)
		material.set_shader_parameter("animation_texture", animation_tex)


# ✅ FIX: Funzioni shader corrette per TileMapLayer
func get_shader_material() -> ShaderMaterial:
	"""Ritorna il materiale shader per aggiornamenti runtime"""
	if material and material is ShaderMaterial:
		return material as ShaderMaterial
	return null

func get_shader_parameter(param_name: String):
	"""Leggi valore parametro shader corrente"""
	var shader_material = get_shader_material()  # ✅ FIX: Rinominato per evitare shadow
	if shader_material:
		return shader_material.get_shader_parameter(param_name)
	return null
