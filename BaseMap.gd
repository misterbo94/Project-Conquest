# BaseMap.gd - Rendering e coordinate
extends TileMapLayer
class_name BaseMap

var voronoi_map: Dictionary = {}

# === DEPENDENCIES ===
@onready var input_handler: InputHandler

func _ready():
	print("BaseMap inizializzazione...")
	_setup_dependencies()
	_initialize_map()

func _setup_dependencies():
	# Trova InputHandler come nodo figlio
	input_handler = get_node("InputHandler") as InputHandler
	if not input_handler:
		print("ERRORE: InputHandler non trovato come nodo figlio!")
		return
	
	# Setup connessioni
	input_handler.region_clicked.connect(_on_region_clicked)
	GameStateManager.texture_updated.connect(_on_texture_updated)
	print("Connessioni stabilite")

func _initialize_map():
	if material: 
		material = material.duplicate()
		print("Materiale shader duplicato")
	
	calculate_voronoi_map()
	GameStateManager.initialize_regions(voronoi_map)
	_setup_shader_parameters()
	print("BaseMap inizializzazione completata")

# === VORONOI SEMPLIFICATO ===
func calculate_voronoi_map():
	print("Calcolo Voronoi...")
	voronoi_map.clear()
	
	var all_cells = get_used_cells()
	var mothers = _find_mother_tiles(all_cells)
	
	if mothers.is_empty():
		print("ERRORE: Nessuna tile madre trovata!")
		return
	
	print("Trovate ", mothers.size(), " madri: ", mothers)
	
	for cell in all_cells:
		var closest_mother = _find_closest_mother(cell, mothers)
		voronoi_map[cell] = closest_mother
	
	print("Voronoi completato: ", mothers.size(), " regioni")

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

# === CALLBACKS ===
func _on_region_clicked(world_pos: Vector2):
	print("BaseMap: Click ricevuto at ", world_pos)
	
	var tile_coord = local_to_map(to_local(world_pos))
	print("  Convertito in tile: ", tile_coord)
	
	if voronoi_map.has(tile_coord):
		var mother = voronoi_map[tile_coord]
		print("  Madre trovata: ", mother)
		GameStateManager.cycle_region_state(mother)
	else:
		print("  Tile non trovata nel voronoi_map!")

func _on_texture_updated(new_texture: ImageTexture):
	print("BaseMap: Texture aggiornata ricevuta")
	if material:
		material.set_shader_parameter("control_texture", new_texture)

# === SHADER SETUP ===
func _setup_shader_parameters():
	if not material: 
		print("ERRORE: Nessun materiale shader!")
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
	material.set_shader_parameter("control_texture", GameStateManager.control_texture)
	
	# Parametri pattern (se esistono)
	if material.get_property_list().any(func(p): return p.name == "gradient_width"):
		material.set_shader_parameter("gradient_width", 8.0)
		material.set_shader_parameter("dither_type", 1)
		material.set_shader_parameter("dither_scale", 3.0)
	
	print("Parametri shader configurati")
