# GameStateManager.gd - Stati e logica semplificata
extends Node

const MAP_SIZE = Vector2i(36, 36)
enum RegionState { BLUE = -1, NEUTRAL = 0, RED = 1 }

var region_states: Dictionary = {}
var control_texture: ImageTexture
var _voronoi_map_cache: Dictionary = {}

signal texture_updated(new_texture: ImageTexture)

func _ready():
	print("GameStateManager inizializzato")

func initialize_regions(voronoi_map: Dictionary):
	print("Inizializzazione regioni...")
	_voronoi_map_cache = voronoi_map
	region_states.clear()
	
	# Trova tutte le madri uniche e inizializza come neutre
	var mothers_set = {}
	for mother in voronoi_map.values():
		if not mothers_set.has(mother):
			mothers_set[mother] = true
			region_states[mother] = RegionState.NEUTRAL
	
	_create_control_texture()
	print("Inizializzate ", region_states.size(), " regioni come neutre")

# === CICLO STATI SEMPLICE ===
# === VERSIONE CORRETTA del match statement ===
func cycle_region_state(mother_coord: Vector2i):
	if not region_states.has(mother_coord): 
		print("ERRORE: Regione ", mother_coord, " non trovata!")
		return
	
	var current_state = region_states[mother_coord]
	
	# Versione più semplice con if/elif
	var next_state: int
	if current_state == RegionState.NEUTRAL:
		next_state = RegionState.BLUE
	elif current_state == RegionState.BLUE:
		next_state = RegionState.RED
	elif current_state == RegionState.RED:
		next_state = RegionState.NEUTRAL
	else:
		next_state = RegionState.NEUTRAL
	
	region_states[mother_coord] = next_state
	_update_control_texture()
	
	print("Regione ", mother_coord, ": ", _state_to_string(current_state), " → ", _state_to_string(next_state))

func _state_to_string(state: int) -> String:
	match state:
		RegionState.BLUE: return "BLUE"
		RegionState.NEUTRAL: return "NEUTRAL"
		RegionState.RED: return "RED"
		_: return "UNKNOWN"

# === TEXTURE MANAGEMENT ===
func _create_control_texture():
	var img = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	control_texture = ImageTexture.create_from_image(img)
	_update_control_texture()

func _update_control_texture():
	if not control_texture or _voronoi_map_cache.is_empty(): 
		return
	
	var img = control_texture.get_image()
	var coord_scale = float(MAP_SIZE.x - 1)
	
	for cell_coord in _voronoi_map_cache:
		if cell_coord.x < 0 or cell_coord.x >= MAP_SIZE.x or \
		   cell_coord.y < 0 or cell_coord.y >= MAP_SIZE.y:
			continue
		
		var mother = _voronoi_map_cache[cell_coord]
		var state = region_states.get(mother, RegionState.NEUTRAL)
		
		# Formula magica: (-1,0,1) → (0.0,0.5,1.0)
		var state_value = (float(state) + 1.0) * 0.5
		
		var color_data = Color(
			float(mother.x) / coord_scale,
			float(mother.y) / coord_scale,
			state_value,
			1.0
		)
		img.set_pixel(cell_coord.x, cell_coord.y, color_data)
	
	control_texture.update(img)
	texture_updated.emit(control_texture)
