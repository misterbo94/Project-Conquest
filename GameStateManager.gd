# GameStateManager.gd - Versione 7.0 Ibrida - FIXED
extends Node

const MAP_SIZE = Vector2i(36, 36)
enum RegionState { PLAYER1 = -1, NEUTRAL = 0, PLAYER2 = 1 }
enum AnimationType { CONQUEST, LOSS, NEUTRAL_TO_PLAYER, PLAYER_TO_NEUTRAL }

# === PARAMETRI ANIMAZIONE - CONST SEMPLICI ===
const WAVE_SPEED: float = 1.0
const LOSS_SPEED_MULTIPLIER: float = 9.0
const GRADIENT_TILES: int = 3
const MAX_DOT_SIZE: float = 0.65

# === ✅ CLASSE GRADIENT DATA OTTIMIZZATA ===
class StaticGradientData:
	var closest_foreign_mother: Vector2i = Vector2i(-1, -1)  # ✅ STATICO: non cambia mai
	var distance_to_border: int = 0                         # ✅ STATICO: distanza geometrica fissa
	var is_in_gradient_zone: bool = false                   # ✅ STATICO: coinvolgimento geometrico
	
	func _init(foreign_mother: Vector2i = Vector2i(-1, -1), border_dist: int = 0, in_zone: bool = false):
		closest_foreign_mother = foreign_mother
		distance_to_border = border_dist
		is_in_gradient_zone = in_zone

# === STATI CONSOLIDATI ===
var region_states: Dictionary = {}                     # mother_coord → RegionState
var _voronoi_map_cache: Dictionary = {}                # tile_coord → mother_coord

# === ✅ GRADIENT IBRIDO ===
var static_gradient_lookup: Dictionary = {}               # tile_coord → StaticGradientData (PRE-CALC)

# === TEXTURE SEPARATE ===
var control_texture: ImageTexture
var animation_texture: ImageTexture

# === SISTEMA ANIMAZIONI ===
var active_animations: Dictionary = {}

# === SISTEMA AURA ===
var aura_strength: Dictionary = {}

# === SIGNALS ===
signal state_changed(mother_coord: Vector2i, old_state: RegionState, new_state: RegionState)
signal animation_started(mother_coord: Vector2i, animation_type: AnimationType)
signal animation_completed(mother_coord: Vector2i, final_state: RegionState)
signal textures_updated(control_tex: ImageTexture, animation_tex: ImageTexture)

var ping: bool = false

func _ready():
	print("=== GameStateManager v7.0 Ibrida ===")
	print("Parametri const:")
	print("  WAVE_SPEED: ", WAVE_SPEED)
	print("  GRADIENT_TILES: ", GRADIENT_TILES)
	print("  MAX_DOT_SIZE: ", MAX_DOT_SIZE)
	set_process(true)

# === ✅ INIZIALIZZAZIONE CON PRE-CALCOLAZIONE STATICA ===
func initialize_regions(voronoi_map: Dictionary):
	print("Inizializzazione regioni v7.0 ibrida...")
	
	_voronoi_map_cache = voronoi_map
	region_states.clear()
	active_animations.clear()
	aura_strength.clear()
	static_gradient_lookup.clear()
	
	# Inizializza tutte le regioni come neutrali
	var mothers_set = {}
	for mother in voronoi_map.values():
		if not mothers_set.has(mother):
			mothers_set[mother] = true
			region_states[mother] = RegionState.NEUTRAL
			aura_strength[mother] = 0.0
	
	# ✅ PRE-CALCOLA SOLO DATI STATICI
	_precalculate_static_gradient_data(voronoi_map)
	
	_create_textures()
	print("Inizializzate ", region_states.size(), " regioni")
	print("Pre-calcolate ", static_gradient_lookup.size(), " tiles gradient statiche")

func _precalculate_static_gradient_data(voronoi_map: Dictionary):
	"""Pre-calcola SOLO dati geometrici statici"""
	print("Pre-calcolazione dati statici gradient...")
	
	var start_time = Time.get_ticks_msec()
	var processed_tiles = 0
	var gradient_zones_found = 0
	
	for x in range(MAP_SIZE.x):
		for y in range(MAP_SIZE.y):
			var tile_coord = Vector2i(x, y)
			
			if not voronoi_map.has(tile_coord):
				continue
			
			processed_tiles += 1
			var tile_mother = voronoi_map[tile_coord]
			
			# ✅ TROVA REGIONE ESTERNA PIÙ VICINA (statico)
			var closest_foreign_mother = _find_closest_foreign_mother(tile_coord, tile_mother, voronoi_map)
			
			if closest_foreign_mother == Vector2i(-1, -1):
				# Nessuna regione esterna: non è zona gradient
				static_gradient_lookup[tile_coord] = StaticGradientData.new()
				continue
			
			# ✅ CALCOLA DISTANCE_TO_BORDER (statico, geometrico)
			var distance_to_border = _calculate_distance_to_border(tile_coord, tile_mother, voronoi_map)
			
			# Salva solo dati statici
			var static_data = StaticGradientData.new(closest_foreign_mother, distance_to_border, true)
			static_gradient_lookup[tile_coord] = static_data
			gradient_zones_found += 1
	
	var elapsed_time = Time.get_ticks_msec() - start_time
	print("✅ Pre-calcolazione statica completata in ", elapsed_time, "ms")
	print("  Tiles processate: ", processed_tiles)
	print("  Zone gradient: ", gradient_zones_found)

# === ✅ FUNZIONI HELPER STATICHE ===
func _find_closest_foreign_mother(tile_coord: Vector2i, own_mother: Vector2i, voronoi_map: Dictionary) -> Vector2i:
	"""Trova madre della regione esterna più vicina"""
	var min_distance = 999999.0
	var closest_foreign = Vector2i(-1, -1)
	
	# Cerca nel raggio esteso
	var search_radius = GRADIENT_TILES + 2
	for x in range(-search_radius, search_radius + 1):
		for y in range(-search_radius, search_radius + 1):
			if x == 0 and y == 0:
				continue
			
			var check_coord = tile_coord + Vector2i(x, y)
			if not voronoi_map.has(check_coord):
				continue
			
			var check_mother = voronoi_map[check_coord]
			if check_mother == own_mother:
				continue  # Stessa regione
			
			var distance = Vector2(x, y).length()
			if distance < min_distance:
				min_distance = distance
				closest_foreign = check_mother
	
	return closest_foreign

func _calculate_distance_to_border(tile_coord: Vector2i, own_mother: Vector2i, voronoi_map: Dictionary) -> int:
	"""Calcola distanza minima dal confine della propria regione"""
	var min_distance_to_foreign = GRADIENT_TILES + 1
	
	for x in range(-GRADIENT_TILES - 1, GRADIENT_TILES + 2):
		for y in range(-GRADIENT_TILES - 1, GRADIENT_TILES + 2):
			var check_coord = tile_coord + Vector2i(x, y)
			if not voronoi_map.has(check_coord):
				continue
			
			var check_mother = voronoi_map[check_coord]
			if check_mother != own_mother:
				# Tile esterna trovata
				var distance = max(abs(x), abs(y))  # Distanza Chebyshev
				min_distance_to_foreign = min(min_distance_to_foreign, distance)
	
	return clamp(min_distance_to_foreign, 1, GRADIENT_TILES)

# === ✅ CALCOLO DINAMICO DISTANCE_TO_GRADIENT ===
func get_gradient_data_for_tile(tile_coord: Vector2i) -> Dictionary:
	"""Calcola distance_to_gradient dinamicamente basato su stati correnti"""
	var static_data = static_gradient_lookup.get(tile_coord)
	if not static_data or not static_data.is_in_gradient_zone:
		return {
			"neighbor_state": 0.5,
			"distance_to_gradient": 0.0,
			"is_gradient_zone": false
		}
	
	# ✅ STATI DINAMICI
	var tile_mother = _voronoi_map_cache.get(tile_coord, Vector2i(-1, -1))
	var current_region_state = region_states.get(tile_mother, RegionState.NEUTRAL)
	var neighbor_region_state = region_states.get(static_data.closest_foreign_mother, RegionState.NEUTRAL)
	
	var current_state_value = _state_to_texture_value(current_region_state)
	var neighbor_state_value = _state_to_texture_value(neighbor_region_state)
	
	# ✅ FORMULA MAGICA DINAMICA
	var current_is_player1 = current_state_value < 0.4
	var A = 1.0 if current_is_player1 else 0.0
	var B = float(static_data.distance_to_border)
	var C = 2.0 * A * B - A - B + float(GRADIENT_TILES)
	
	return {
		"neighbor_state": neighbor_state_value,
		"distance_to_gradient": C,
		"is_gradient_zone": true
	}

# === ✅ PROCESSO ANIMAZIONI ===
func _process(delta: float):
	if active_animations.is_empty():
		return
	
	var completed_animations = []
	var needs_update = false
	
	for mother_coord in active_animations:
		var animation: ConquestAnimation = active_animations[mother_coord]
		
		if animation.update(delta):
			completed_animations.append(mother_coord)
			print("Animation completed: ", mother_coord)
		else:
			needs_update = true
	
	if needs_update or not completed_animations.is_empty():
		_update_animation_texture()
	
	for mother_coord in completed_animations:
		_complete_animation(mother_coord)

func get_animation_settings() -> Dictionary:
	return {
		"wave_speed": WAVE_SPEED,
		"loss_speed_multiplier": LOSS_SPEED_MULTIPLIER,
		"gradient_tiles": GRADIENT_TILES,
		"max_dot_size": MAX_DOT_SIZE,
	}

# === GESTIONE STATI ===
func change_region_state(mother_coord: Vector2i, new_state: RegionState, animated: bool = true):
	if not region_states.has(mother_coord):
		print("ERRORE: Regione ", mother_coord, " non esistente!")
		return false
	
	if is_region_locked(mother_coord):
		print("Regione ", mother_coord, " in LOCK STATE - cambio rifiutato")
		return false
	
	var old_state = region_states[mother_coord]
	if old_state == new_state:
		return false
	
	print("=== CAMBIO STATO CON LOCK ===")
	print("Regione: ", mother_coord, " ", _state_to_string(old_state), " → ", _state_to_string(new_state))
	
	if animated:
		_start_animated_transition(mother_coord, old_state, new_state)
	else:
		_immediate_state_change(mother_coord, old_state, new_state)
	
	return true

func _immediate_state_change(mother_coord: Vector2i, old_state: RegionState, new_state: RegionState):
	region_states[mother_coord] = new_state
	_update_control_texture()
	# ✅ AGGIORNA ANCHE GRADIENT PERCHÉ STATI SONO CAMBIATI
	_update_animation_texture()
	state_changed.emit(mother_coord, old_state, new_state)

func _start_animated_transition(mother_coord: Vector2i, from_state: RegionState, to_state: RegionState):
	var anim_type = _get_animation_type(from_state, to_state)
	var current_settings = get_animation_settings()
	
	var animation = ConquestAnimation.new()
	animation.initialize(mother_coord, int(from_state), int(to_state), current_settings, _voronoi_map_cache)
	
	active_animations[mother_coord] = animation
	
	_update_control_texture()
	_update_animation_texture()
	
	state_changed.emit(mother_coord, from_state, to_state)
	animation_started.emit(mother_coord, anim_type)

func _complete_animation(mother_coord: Vector2i):
	if not active_animations.has(mother_coord):
		return
	
	var animation: ConquestAnimation = active_animations[mother_coord]
	var final_state = animation.to_state
	
	print("Animazione completata: ", mother_coord, " → ", _state_to_string(final_state))
	
	region_states[mother_coord] = final_state
	active_animations.erase(mother_coord)
	
	_update_control_texture()
	_update_animation_texture()
	
	animation_completed.emit(mother_coord, final_state)

# === ✅ TEXTURE MANAGEMENT AGGIORNATO ===
func _create_textures():
	var img_control = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	var img_animation = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	
	control_texture = ImageTexture.create_from_image(img_control)
	animation_texture = ImageTexture.create_from_image(img_animation)
	
	_update_control_texture()
	_update_animation_texture()

func _update_control_texture():
	if not control_texture or _voronoi_map_cache.is_empty():
		return
	
	var img = control_texture.get_image()
	var coord_scale = float(MAP_SIZE.x - 1)
	img.fill(Color.BLACK)
	
	var tiles_by_mother = _group_tiles_by_mother()
	
	for mother in tiles_by_mother:
		var final_state = region_states.get(mother, RegionState.NEUTRAL)
		var state_value = _state_to_texture_value(final_state)
		var aura_value = aura_strength.get(mother, 0.0)
		
		var color_data = Color(
			float(mother.x) / coord_scale,
			float(mother.y) / coord_scale,
			state_value,
			aura_value
		)
		
		for cell_coord in tiles_by_mother[mother]:
			img.set_pixel(cell_coord.x, cell_coord.y, color_data)
	
	control_texture.update(img)

func _update_animation_texture():
	"""Aggiorna texture con gradient ibrido"""
	if not animation_texture or _voronoi_map_cache.is_empty():
		return
	
	var img = animation_texture.get_image()
	img.fill(Color.BLACK)
	
	if active_animations.is_empty():
		# ✅ GRADIENT STATICO
		_update_static_gradient_texture(img)
	else:
		# ✅ ANIMAZIONI + GRADIENT
		_update_animated_gradient_texture(img)
	
	animation_texture.update(img)
	textures_updated.emit(control_texture, animation_texture)

func _update_static_gradient_texture(img: Image):
	"""Aggiorna texture gradient statico con calcolo dinamico ottimizzato"""
	for tile_coord in static_gradient_lookup:
		if tile_coord.x < 0 or tile_coord.x >= MAP_SIZE.x or \
		   tile_coord.y < 0 or tile_coord.y >= MAP_SIZE.y:
			continue
		
		var grad_data_dict = get_gradient_data_for_tile(tile_coord)
		
		if not grad_data_dict.is_gradient_zone:
			continue
		
		var tile_mother = _voronoi_map_cache.get(tile_coord, Vector2i(-1, -1))
		var current_state_value = 0.5
		if tile_mother != Vector2i(-1, -1):
			var current_region_state = region_states.get(tile_mother, RegionState.NEUTRAL)
			current_state_value = _state_to_texture_value(current_region_state)
		
		var normalized_distance = grad_data_dict.distance_to_gradient / float(GRADIENT_TILES * 2 - 1)
		
		var color_data = Color(
			0.0,                                    # R: nessuna animazione
			current_state_value,                    # G: stato corrente tile
			grad_data_dict.neighbor_state,          # B: stato vicino
			normalized_distance                     # A: distance_to_gradient dinamica
		)
		
		img.set_pixel(tile_coord.x, tile_coord.y, color_data)

func _update_animated_gradient_texture(img: Image):
	"""Aggiorna texture con animazioni + gradient"""
	for mother_coord in active_animations:
		var animation: ConquestAnimation = active_animations[mother_coord]
		
		for cell_coord in animation.all_affected_tiles:
			if cell_coord.x < 0 or cell_coord.x >= MAP_SIZE.x or \
			   cell_coord.y < 0 or cell_coord.y >= MAP_SIZE.y:
				continue
			
			# ✅ ANIMAZIONE + GRADIENT COMBINATI
			var anim_data = animation.get_tile_animation_data(cell_coord)
			var grad_data_dict = get_gradient_data_for_tile(cell_coord)
			
			var normalized_distance = 0.0
			if grad_data_dict.is_gradient_zone:
				normalized_distance = grad_data_dict.distance_to_gradient / float(GRADIENT_TILES * 2 - 1)
			
			var color_data = Color(
				anim_data.progress,                 # R: progresso animazione
				anim_data.from_state_value,         # G: stato iniziale
				grad_data_dict.neighbor_state,      # B: stato regione confinante (da gradient)
				normalized_distance                 # A: distance_to_gradient dinamica
			)
			
			img.set_pixel(cell_coord.x, cell_coord.y, color_data)

func _group_tiles_by_mother() -> Dictionary:
	var tiles_by_mother = {}
	
	for cell_coord in _voronoi_map_cache:
		if cell_coord.x < 0 or cell_coord.x >= MAP_SIZE.x or \
		   cell_coord.y < 0 or cell_coord.y >= MAP_SIZE.y:
			continue
		
		var mother = _voronoi_map_cache[cell_coord]
		if not tiles_by_mother.has(mother):
			tiles_by_mother[mother] = []
		tiles_by_mother[mother].append(cell_coord)
	
	return tiles_by_mother

# === HELPER FUNCTIONS ===
func _get_animation_type(from_state: RegionState, to_state: RegionState) -> AnimationType:
	if from_state == RegionState.NEUTRAL:
		return AnimationType.NEUTRAL_TO_PLAYER
	elif to_state == RegionState.NEUTRAL:
		return AnimationType.PLAYER_TO_NEUTRAL
	else:
		return AnimationType.CONQUEST

func _state_to_string(state: RegionState) -> String:
	match state:
		RegionState.PLAYER1: return "PLAYER1"
		RegionState.NEUTRAL: return "NEUTRAL"  
		RegionState.PLAYER2: return "PLAYER2"
		_: return "UNKNOWN"

func _state_to_texture_value(state: RegionState) -> float:
	return (float(state) + 1.0) * 0.5

func is_region_locked(mother_coord: Vector2i) -> bool:
	return active_animations.has(mother_coord)

func is_region_animating(mother_coord: Vector2i) -> bool:
	return active_animations.has(mother_coord)

func get_region_state(mother_coord: Vector2i) -> RegionState:
	return region_states.get(mother_coord, RegionState.NEUTRAL)

func set_aura_strength(mother_coord: Vector2i, strength: float):
	aura_strength[mother_coord] = clamp(strength, 0.0, 1.0)
	_update_control_texture()

func cycle_region_state(mother_coord: Vector2i):
	var current_state = get_region_state(mother_coord)
	var next_state: RegionState
	
	if current_state == RegionState.NEUTRAL and ping:
		next_state = RegionState.PLAYER1
		ping = !ping
	elif current_state == RegionState.NEUTRAL and !ping:
		next_state = RegionState.PLAYER2
		ping = !ping
	else:
		next_state = RegionState.NEUTRAL
	
	change_region_state(mother_coord, next_state, true)
