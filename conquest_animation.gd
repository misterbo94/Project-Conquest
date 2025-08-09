# ConquestAnimation.gd - Versione 5.0 con Gradient tra regioni
class_name ConquestAnimation
extends RefCounted

# === CLASSE DATI TILE ESTESA ===
class UnifiedTileData:
	var progress: float = 0.0
	var from_state_value: float = 0.5
	var to_state_value: float = 0.5
	var distance_to_mother: float = 0.0
	var is_in_own_region: bool = false
	var is_in_wave_zone: bool = false
	# ✅ NUOVI CAMPI PER GRADIENT
	var neighbor_state_value: float = 0.5      # Stato della regione confinante più vicina
	var distance_to_gradient: float = 0.0      # Distanza dal confine gradient (0-15 per gradient_tiles=8)
	var is_in_gradient_zone: bool = false      # True se dentro zona gradient con altre regioni
	
	func _init(prog: float = 0.0, from_val: float = 0.5, to_val: float = 0.5, dist: float = 0.0, own_region: bool = false, wave_zone: bool = false, neighbor_val: float = 0.5, grad_dist: float = 0.0, grad_zone: bool = false):
		progress = prog
		from_state_value = from_val
		to_state_value = to_val
		distance_to_mother = dist
		is_in_own_region = own_region
		is_in_wave_zone = wave_zone
		neighbor_state_value = neighbor_val
		distance_to_gradient = grad_dist
		is_in_gradient_zone = grad_zone

# === PROPRIETÀ ===
var mother_coord: Vector2i
var from_state: int
var to_state: int

# === TIMING ===
var wave_speed: float
var total_duration: float = 0.0
var elapsed_time: float = 0.0
var progress: float = 0.0

# === WAVE SYSTEM ===
var frontwave_radius: float = 0.0    # ✅ Fronte d'onda principale
var backwave_radius: float = 0.0     # ✅ Fronte d'onda ritardato
var max_wave_radius: float = 0.0
var is_conquest: bool = true
var gradient_tiles: int              # ✅ Ora serve per WAVE_ZONE_WIDTH

# === TILES ===
var region_tiles: Array[Vector2i] = []
var gradient_tiles_affected: Array[Vector2i] = []
var all_affected_tiles: Array[Vector2i] = []

# ✅ NUOVA CACHE GRADIENT
var gradient_neighbor_map: Dictionary = {}     # tile_coord → neighbor_state
var gradient_distance_map: Dictionary = {}    # tile_coord → distance_to_gradient

var is_completed: bool = false

func initialize(coord: Vector2i, from: int, to: int, settings: Dictionary, voronoi_map: Dictionary):
	mother_coord = coord
	from_state = from
	to_state = to
	
	wave_speed = settings.wave_speed
	gradient_tiles = settings.gradient_tiles
	
	is_conquest = _is_conquest_animation(from, to)
	
	# ✅ CALCOLA TILES E GRADIENT
	_calculate_affected_tiles(voronoi_map)
	_calculate_gradient_data(voronoi_map)
	
	total_duration = max_wave_radius / wave_speed
	if not is_conquest:
		total_duration = total_duration / settings.loss_speed_multiplier
	
	print("ConquestAnimation v5.0 con Gradient:")
	print("  Gradient tiles: ", gradient_tiles)
	print("  Region tiles: ", region_tiles.size())
	print("  Gradient tiles: ", gradient_tiles_affected.size())
	print("  Gradient neighbors calculated: ", gradient_neighbor_map.size())

func update(delta: float) -> bool:
	if is_completed:
		return true
	
	elapsed_time += delta
	progress = clamp(elapsed_time / total_duration, 0.0, 1.0)
	
	if is_conquest:
		frontwave_radius = max_wave_radius * progress
		backwave_radius = max(0.0, frontwave_radius - float(gradient_tiles))
	else:
		frontwave_radius = max_wave_radius * (1.0 - progress)
		backwave_radius = min(max_wave_radius, frontwave_radius + float(gradient_tiles))
	
	if progress >= 1.0:
		is_completed = true
		return true
	
	return false

func _calculate_gradient_data(voronoi_map: Dictionary):
	"""Calcola per ogni tile la regione confinante e distance_to_gradient"""
	gradient_neighbor_map.clear()
	gradient_distance_map.clear()
	
	var current_region_state = _state_to_texture_value(from_state)
	
	# Per ogni tile coinvolta nell'animazione
	for tile_coord in all_affected_tiles:
		var tile_mother = voronoi_map.get(tile_coord, Vector2i(-1, -1))
		
		if tile_mother == mother_coord:
			# ✅ TILE DELLA REGIONE PRINCIPALE
			var closest_foreign_state = _find_closest_foreign_region_state(tile_coord, voronoi_map)
			var distance_to_border = _calculate_distance_to_border(tile_coord, voronoi_map)
			
			# Formula magica del vecchio script
			var A = 1.0 if current_region_state < 0.4 else 0.0  # 1 se P1, 0 altrimenti
			var B = float(distance_to_border)  # 1 a gradient_tiles 
			var C = 2.0 * A * B - A - B + float(gradient_tiles)
			
			gradient_neighbor_map[tile_coord] = closest_foreign_state
			gradient_distance_map[tile_coord] = C
			
		else:
			# ✅ TILE DI REGIONE ESTERNA (nel gradient)
			var foreign_region_state = _get_region_state_from_mother(tile_mother, voronoi_map)
			var distance_to_our_border = _calculate_distance_to_region_border(tile_coord, mother_coord, voronoi_map)
			
			# Per tiles esterne, distance_to_gradient va da gradient_tiles (vicino alla nostra regione) a 1 (lontano)
			var distance_to_gradient = float(gradient_tiles) - distance_to_our_border + 1.0
			distance_to_gradient = clamp(distance_to_gradient, 1.0, float(gradient_tiles))
			
			gradient_neighbor_map[tile_coord] = foreign_region_state
			gradient_distance_map[tile_coord] = distance_to_gradient

func _find_closest_foreign_region_state(tile_coord: Vector2i, voronoi_map: Dictionary) -> float:
	"""Trova lo stato della regione esterna più vicina"""
	var min_distance = 999999.0
	var closest_foreign_mother = Vector2i(-1, -1)
	
	# Cerca in un raggio intorno alla tile
	for x in range(-gradient_tiles-2, gradient_tiles+3):
		for y in range(-gradient_tiles-2, gradient_tiles+3):
			var check_coord = tile_coord + Vector2i(x, y)
			if not voronoi_map.has(check_coord):
				continue
			
			var check_mother = voronoi_map[check_coord]
			if check_mother == mother_coord:
				continue  # Stesso madre, non è esterno
			
			var distance = tile_coord.distance_to(check_coord)
			if distance < min_distance:
				min_distance = distance
				closest_foreign_mother = check_mother
	
	if closest_foreign_mother == Vector2i(-1, -1):
		return 0.5  # Neutro di default
	
	return _get_region_state_from_mother(closest_foreign_mother, voronoi_map)

func _get_region_state_from_mother(mother_position: Vector2i, _voronoi_map: Dictionary) -> float:  # ✅ FIX: Rinominato parametro e prefisso _
	"""Ottiene lo stato della regione da coordinate madre"""
	# Per ora assumiamo che possiamo determinarlo. In futuro potrebbe servire accesso al GameStateManager
	# Placeholder: alternanza basata su coordinate per test
	var state_hash = (mother_position.x + mother_position.y) % 3  # ✅ FIX: Usa nuovo nome
	match state_hash:
		0: return 0.0  # P1
		1: return 0.5  # Neutral
		2: return 1.0  # P2
		_: return 0.5

func _calculate_distance_to_region_border(tile_coord: Vector2i, target_mother: Vector2i, voronoi_map: Dictionary) -> int:
	"""Calcola distanza dal confine di una regione specifica"""
	var min_distance = gradient_tiles + 1
	
	for x in range(-gradient_tiles-1, gradient_tiles+2):
		for y in range(-gradient_tiles-1, gradient_tiles+2):
			var check_coord = tile_coord + Vector2i(x, y)
			if not voronoi_map.has(check_coord):
				continue
			
			var check_mother = voronoi_map[check_coord]
			if check_mother == target_mother:
				var distance = max(abs(x), abs(y))
				min_distance = min(min_distance, distance)
	
	return clamp(min_distance, 1, gradient_tiles)

func _calculate_distance_to_border(tile_coord: Vector2i, voronoi_map: Dictionary) -> int:
	"""Calcola distanza dal confine della regione (1 = confine, gradient_tiles = centro)"""
	var min_distance_to_foreign = gradient_tiles + 1
	
	# Cerca tile esterne nel raggio
	for x in range(-gradient_tiles-1, gradient_tiles+2):
		for y in range(-gradient_tiles-1, gradient_tiles+2):
			var check_coord = tile_coord + Vector2i(x, y)
			if not voronoi_map.has(check_coord):
				continue
			
			var check_mother = voronoi_map[check_coord]
			if check_mother != mother_coord:
				# Tile esterna trovata
				var distance = max(abs(x), abs(y))  # Distanza Chebyshev
				min_distance_to_foreign = min(min_distance_to_foreign, distance)
	
	return clamp(min_distance_to_foreign, 1, gradient_tiles)

func get_tile_animation_data(tile_coord: Vector2i) -> UnifiedTileData:
	"""Calcola dati completi con gradient"""
	var distance_to_mother = tile_coord.distance_to(mother_coord)
	var is_in_own_region = tile_coord in region_tiles
	
	# ✅ DATI GRADIENT
	var neighbor_state = gradient_neighbor_map.get(tile_coord, 0.5)
	var grad_distance = gradient_distance_map.get(tile_coord, 0.0)
	var is_in_gradient = grad_distance > 0.0
	
	# Calcolo progresso locale (backwave logic)
	var local_progress = 0.0
	var is_in_wave_zone = false
	
	if is_conquest:
		if distance_to_mother <= frontwave_radius and distance_to_mother >= backwave_radius:
			is_in_wave_zone = true
			if gradient_tiles > 0:
				var zone_position = (frontwave_radius - distance_to_mother) / float(gradient_tiles)
				local_progress = clamp(zone_position, 0.0, 1.0)
			else:
				local_progress = 1.0
		elif distance_to_mother < backwave_radius:
			local_progress = 1.0
		else:
			local_progress = 0.0
	else:
		if distance_to_mother >= frontwave_radius and distance_to_mother <= backwave_radius:
			is_in_wave_zone = true
			if gradient_tiles > 0:
				var zone_position = (distance_to_mother - frontwave_radius) / float(gradient_tiles)
				local_progress = clamp(zone_position, 0.0, 1.0)
			else:
				local_progress = 1.0
		elif distance_to_mother > backwave_radius:
			local_progress = 1.0
		else:
			local_progress = 0.0
	
	return UnifiedTileData.new(
		local_progress,
		_state_to_texture_value(from_state),
		_state_to_texture_value(to_state),
		distance_to_mother,
		is_in_own_region,
		is_in_wave_zone,
		neighbor_state,           # ✅ Stato regione confinante
		grad_distance,            # ✅ Distance to gradient
		is_in_gradient            # ✅ Flag gradient zone
	)

func _calculate_affected_tiles(voronoi_map: Dictionary):
	region_tiles.clear()
	gradient_tiles_affected.clear()
	all_affected_tiles.clear()
	
	# Regione principale
	for tile_coord in voronoi_map:
		if voronoi_map[tile_coord] == mother_coord:
			region_tiles.append(tile_coord)
			all_affected_tiles.append(tile_coord)
			var distance = mother_coord.distance_to(tile_coord)
			max_wave_radius = max(max_wave_radius, distance)
	
	# Gradient
	var gradient_candidates = {}
	for region_tile in region_tiles:
		for x in range(-gradient_tiles, gradient_tiles + 1):
			for y in range(-gradient_tiles, gradient_tiles + 1):
				if x == 0 and y == 0:
					continue
				
				var neighbor = region_tile + Vector2i(x, y)
				var tile_distance = max(abs(x), abs(y))
				
				if tile_distance <= gradient_tiles and voronoi_map.has(neighbor):
					var neighbor_mother = voronoi_map[neighbor]
					
					if neighbor_mother != mother_coord:
						gradient_candidates[neighbor] = true
	
	for gradient_tile in gradient_candidates:
		gradient_tiles_affected.append(gradient_tile)
		all_affected_tiles.append(gradient_tile)
		var distance_from_mother = mother_coord.distance_to(gradient_tile)
		max_wave_radius = max(max_wave_radius, distance_from_mother)

func get_debug_string() -> String:
	var type_str = "CONQUEST" if is_conquest else "LOSS"
	return "ConquestAnimation[%s: %s %s→%s, %.1f%%, F=%.1f B=%.1f/%.1f]" % [
		mother_coord, type_str, from_state, to_state, progress * 100.0, 
		frontwave_radius, backwave_radius, max_wave_radius
	]

func _is_conquest_animation(from: int, to: int) -> bool:
	return from == 0 or (from != 0 and to != 0)

func _state_to_texture_value(state: int) -> float:
	return (float(state) + 1.0) * 0.5
