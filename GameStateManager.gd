# GameStateManager.gd - Versione SEMPLICE con const
extends Node

const MAP_SIZE = Vector2i(36, 36)
enum RegionState { PLAYER1 = -1, NEUTRAL = 0, PLAYER2 = 1 }
enum AnimationType { CONQUEST, LOSS, NEUTRAL_TO_PLAYER, PLAYER_TO_NEUTRAL }

# === PARAMETRI ANIMAZIONE - CONST SEMPLICI ===
const WAVE_SPEED: float = 1.0                    # tiles per secondo
const LOSS_SPEED_MULTIPLIER: float = 9.0         # moltiplicatore per perdite
const GRADIENT_TILES: int = 3                   # raggio gradient
const MAX_DOT_SIZE: float = 0.65                 # dimensione massima dots

# === STATI CONSOLIDATI ===
var region_states: Dictionary = {}                     # mother_coord → RegionState
var _voronoi_map_cache: Dictionary = {}                # tile_coord → mother_coord

# === TEXTURE SEPARATE ===
var control_texture: ImageTexture                      # Stati puri + Aura
var animation_texture: ImageTexture                    # Dati animazioni attive

# === SISTEMA ANIMAZIONI ===
var active_animations: Dictionary = {}                 # mother_coord → ConquestAnimation

# === SISTEMA AURA ===
var aura_strength: Dictionary = {}                     # mother_coord → float [0.0-1.0]

# === SIGNALS ===
signal state_changed(mother_coord: Vector2i, old_state: RegionState, new_state: RegionState)
signal animation_started(mother_coord: Vector2i, animation_type: AnimationType)
signal animation_completed(mother_coord: Vector2i, final_state: RegionState)
signal textures_updated(control_tex: ImageTexture, animation_tex: ImageTexture)

var ping: bool = false  # Per cycling test

func _ready():
	print("=== GameStateManager SIMPLE Inizializzato ===")
	print("Parametri const:")
	print("  WAVE_SPEED: ", WAVE_SPEED)
	print("  GRADIENT_TILES: ", GRADIENT_TILES)
	print("  MAX_DOT_SIZE: ", MAX_DOT_SIZE)
	set_process(true)

# === PROCESSO ANIMAZIONI SEMPLIFICATO ===
func _process(delta: float):
	if active_animations.is_empty():
		return
	
	var completed_animations = []
	var needs_update = false
	
	# Aggiorna animazioni
	for mother_coord in active_animations:
		var animation: ConquestAnimation = active_animations[mother_coord]
		
		if animation.update(delta):
			completed_animations.append(mother_coord)
			print("Animation completed: ", mother_coord)
		else:
			needs_update = true
	
	# Aggiorna texture se necessario
	if needs_update or not completed_animations.is_empty():
		_update_animation_texture()
	
	# Completa animazioni finite
	for mother_coord in completed_animations:
		_complete_animation(mother_coord)

# === FUNZIONE SETTINGS SEMPLIFICATA ===
func get_animation_settings() -> Dictionary:
	"""Ritorna i parametri const come dictionary"""
	return {
		"wave_speed": WAVE_SPEED,
		"loss_speed_multiplier": LOSS_SPEED_MULTIPLIER,
		"gradient_tiles": GRADIENT_TILES,
		"max_dot_size": MAX_DOT_SIZE,
	}
# === INIZIALIZZAZIONE ===
func initialize_regions(voronoi_map: Dictionary):
	print("Inizializzazione regioni v2.0...")
	
	_voronoi_map_cache = voronoi_map
	region_states.clear()
	active_animations.clear()
	aura_strength.clear()
	
	# Inizializza tutte le regioni come neutrali
	var mothers_set = {}
	for mother in voronoi_map.values():
		if not mothers_set.has(mother):
			mothers_set[mother] = true
			region_states[mother] = RegionState.NEUTRAL
			aura_strength[mother] = 0.0  # Nessuna aura iniziale
	
	_create_textures()
	print("Inizializzate ", region_states.size(), " regioni")

# === GESTIONE STATI PRINCIPALI ===

func change_region_state(mother_coord: Vector2i, new_state: RegionState, animated: bool = true):
	"""Cambia stato con LOCK durante animazioni"""
	
	if not region_states.has(mother_coord):
		print("ERRORE: Regione ", mother_coord, " non esistente!")
		return false
	
	# ✅ LOCK STATE: Verifica se la regione è sotto lock
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

func is_region_locked(mother_coord: Vector2i) -> bool:
	"""Una regione è in lock se sta animando (conquista O perdita)"""
	return active_animations.has(mother_coord)

func get_lock_reason(mother_coord: Vector2i) -> String:
	"""Debug: spiega perché una regione è in lock"""
	if not is_region_locked(mother_coord):
		return "Non in lock"
	
	var animation: ConquestAnimation = active_animations[mother_coord]
	var type_str = "CONQUEST" if animation.is_conquest else "LOSS"
	return "Lock: %s in corso (%.1f%%, %.1fs rimaste)" % [
		type_str, 
		animation.progress * 100.0,
		animation.total_duration - animation.elapsed_time
	]

func _immediate_state_change(mother_coord: Vector2i, old_state: RegionState, new_state: RegionState):
	"""Cambio immediato senza animazione"""
	region_states[mother_coord] = new_state
	_update_control_texture()
	state_changed.emit(mother_coord, old_state, new_state)

func _start_animated_transition(mother_coord: Vector2i, from_state: RegionState, to_state: RegionState):
	"""Avvia transizione animata con parametri centralizzati"""
	
	# Determina tipo di animazione
	var anim_type = _get_animation_type(from_state, to_state)
	
	# ✅ USA PARAMETRI CENTRALIZZATI AGGIORNATI
	var current_settings = get_animation_settings()
	
	# Crea animazione
	var animation = ConquestAnimation.new()
	animation.initialize(mother_coord, int(from_state), int(to_state), current_settings, _voronoi_map_cache)
	
	# Registra animazione
	active_animations[mother_coord] = animation
	
	# Aggiorna texture
	_update_control_texture()
	_update_animation_texture()
	
	state_changed.emit(mother_coord, from_state, to_state)
	animation_started.emit(mother_coord, anim_type)
	
	print("Animazione v3.3 avviata: ", _animation_type_to_string(anim_type))
	print("  Durata calcolata: ", animation.total_duration, "s")
	print("  Wave speed: ", current_settings.wave_speed, " tiles/s")
	print("  Gradient tiles: ", current_settings.gradient_tiles)

func _complete_animation(mother_coord: Vector2i):
	"""Completa e rimuove un'animazione - FIX: Applica stato finale QUI"""
	if not active_animations.has(mother_coord):
		return
	
	var animation: ConquestAnimation = active_animations[mother_coord]
	var final_state = animation.to_state  # ✅ Usa lo stato finale dell'animazione
	
	print("Animazione completata: ", mother_coord, " → ", _state_to_string(final_state))
	
	# ✅ FIX: Applica lo stato finale SOLO ora
	region_states[mother_coord] = final_state
	
	# Rimuovi animazione
	active_animations.erase(mother_coord)
	
	# Aggiorna texture
	_update_control_texture()    # Nuovo stato applicato
	_update_animation_texture()  # Animazione rimossa
	
	animation_completed.emit(mother_coord, final_state)

# === HELPER FUNCTIONS ===
func _get_animation_type(from_state: RegionState, to_state: RegionState) -> AnimationType:
	if from_state == RegionState.NEUTRAL:
		return AnimationType.NEUTRAL_TO_PLAYER
	elif to_state == RegionState.NEUTRAL:
		return AnimationType.PLAYER_TO_NEUTRAL
	else:
		return AnimationType.CONQUEST  # Diretto P1 ↔ P2

func _state_to_string(state: RegionState) -> String:
	match state:
		RegionState.PLAYER1: return "PLAYER1"
		RegionState.NEUTRAL: return "NEUTRAL"  
		RegionState.PLAYER2: return "PLAYER2"
		_: return "UNKNOWN"

func _animation_type_to_string(anim_type: AnimationType) -> String:
	match anim_type:
		AnimationType.CONQUEST: return "CONQUEST"
		AnimationType.LOSS: return "LOSS"
		AnimationType.NEUTRAL_TO_PLAYER: return "NEUTRAL_TO_PLAYER"
		AnimationType.PLAYER_TO_NEUTRAL: return "PLAYER_TO_NEUTRAL"
		_: return "UNKNOWN"

# === TEXTURE MANAGEMENT ===
func _create_textures():
	"""Crea entrambe le texture"""
	var img_control = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	var img_animation = Image.create(MAP_SIZE.x, MAP_SIZE.y, false, Image.FORMAT_RGBA8)
	
	control_texture = ImageTexture.create_from_image(img_control)
	animation_texture = ImageTexture.create_from_image(img_animation)
	
	_update_control_texture()
	_update_animation_texture()

func _update_control_texture():
	"""Aggiorna texture degli stati puri + aura"""
	if not control_texture or _voronoi_map_cache.is_empty():
		return
	
	var img = control_texture.get_image()
	var coord_scale = float(MAP_SIZE.x - 1)
	
	# Clear dell'immagine
	img.fill(Color.BLACK)
	
	# Raggruppa tiles per madre
	var tiles_by_mother = _group_tiles_by_mother()
	
	# Aggiorna ogni regione
	for mother in tiles_by_mother:
		var final_state = region_states.get(mother, RegionState.NEUTRAL)
		var state_value = _state_to_texture_value(final_state)
		var aura_value = aura_strength.get(mother, 0.0)
		
		var color_data = Color(
			float(mother.x) / coord_scale,      # R: mother_coord.x
			float(mother.y) / coord_scale,      # G: mother_coord.y
			state_value,                        # B: stato puro
			aura_value                          # A: aura strength
		)
		
		# Applica a tutte le tiles della regione
		for cell_coord in tiles_by_mother[mother]:
			img.set_pixel(cell_coord.x, cell_coord.y, color_data)
	
	control_texture.update(img)

func _update_animation_texture():
	"""Aggiorna texture delle animazioni - AGGIORNATO per nuova API"""
	if not animation_texture or _voronoi_map_cache.is_empty():
		return
	
	var img = animation_texture.get_image()
	img.fill(Color.BLACK)
	
	if active_animations.is_empty():
		animation_texture.update(img)
		textures_updated.emit(control_texture, animation_texture)
		return
	
	# ✅ AGGIORNA PER TUTTE LE TILES COINVOLTE (regione + gradient)
	for mother_coord in active_animations:
		var animation: ConquestAnimation = active_animations[mother_coord]
		
		# ✅ USA LE TILES COINVOLTE DALLA NUOVA LOGICA
		for cell_coord in animation.all_affected_tiles:
			# Verifica bounds
			if cell_coord.x < 0 or cell_coord.x >= MAP_SIZE.x or \
			   cell_coord.y < 0 or cell_coord.y >= MAP_SIZE.y:
				continue
			
			# ✅ USA LA NUOVA API
			var anim_data = animation.get_tile_animation_data(cell_coord)
			
			var color_data = Color(
				anim_data.progress,           # R: progresso animazione
				anim_data.from_state_value,   # G: stato iniziale
				anim_data.to_state_value,     # B: stato finale
				anim_data.distance_to_mother  # A: distanza dalla madre (era wave_distance)
			)
			
			img.set_pixel(cell_coord.x, cell_coord.y, color_data)
	
	animation_texture.update(img)
	textures_updated.emit(control_texture, animation_texture)

func _group_tiles_by_mother() -> Dictionary:
	"""Raggruppa tiles per regione madre per efficienza"""
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

func _state_to_texture_value(state: RegionState) -> float:
	"""Converte stato in valore texture normalizzato"""
	return (float(state) + 1.0) * 0.5  # -1→0.0, 0→0.5, 1→1.0

# === API PUBBLICHE ===
func is_region_animating(mother_coord: Vector2i) -> bool:
	return active_animations.has(mother_coord)

func get_region_state(mother_coord: Vector2i) -> RegionState:
	return region_states.get(mother_coord, RegionState.NEUTRAL)

func set_aura_strength(mother_coord: Vector2i, strength: float):
	"""Imposta forza aura per Tier 2 buildings"""
	aura_strength[mother_coord] = clamp(strength, 0.0, 1.0)
	_update_control_texture()

func stop_all_animations():
	"""Ferma tutte le animazioni"""
	for mother_coord in active_animations.keys():
		_complete_animation(mother_coord)
# === BACKWARDS COMPATIBILITY ===
func cycle_region_state(mother_coord: Vector2i):
	"""Metodo compatibile per test"""
	var current_state = get_region_state(mother_coord)
	var next_state: RegionState
	
	# Ciclo ping-pong: NEUTRAL ↔ PLAYER1 ↔ NEUTRAL ↔ PLAYER2
	if current_state == RegionState.NEUTRAL and ping:
		next_state = RegionState.PLAYER1
		ping = !ping
	elif current_state == RegionState.NEUTRAL and !ping:
		next_state = RegionState.PLAYER2
		ping = !ping
	else:
		next_state = RegionState.NEUTRAL
	
	change_region_state(mother_coord, next_state, true)
