# Script da attaccare al nodo Camera2D
extends Camera2D

# ======== VARIABILI CONFIGURABILI DALL'INSPECTOR ========

# Velocità di movimento della camera (in pixel al secondo)
@export var pan_speed: float = 400.0

# Margine in pixel dal bordo dello schermo per attivare il movimento col mouse
@export var edge_margin: int = 50

# Sensibilità dello zoom con la rotellina del mouse
@export var zoom_sensitivity: float = 0.1

# Quanto velocemente si zooma tenendo premuti i tasti A/Z
@export var key_zoom_speed: float = 0.5

# Livelli di zoom minimo e massimo
@export var min_zoom: float = 0.5  # Zoom più lontano
@export var max_zoom: float = 5.0  # Zoom più vicino

# ==========================================================

func _process(delta: float):
	# Gestisce il movimento (pan) e lo zoom con i tasti
	handle_panning(delta)
	handle_key_zoom(delta)


func _unhandled_input(event: InputEvent):
	# Gestisce lo zoom con la rotellina del mouse
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			apply_zoom(1 + zoom_sensitivity) # Zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			apply_zoom(1 - zoom_sensitivity) # Zoom out


func handle_panning(delta: float):
	var move_direction = Vector2.ZERO
	
	# --- Movimento con la tastiera (Frecce direzionali o WASD) ---
	# Input.get_vector rileva le azioni predefinite e restituisce un vettore normalizzato
	move_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# --- Movimento con il mouse ai bordi ---
	if move_direction == Vector2.ZERO: # Diamo priorità alla tastiera
		var mouse_pos = get_viewport().get_mouse_position()
		var viewport_size = get_viewport().get_visible_rect().size
		
		#if mouse_pos.x < edge_margin:
			#move_direction.x = -1
		#elif mouse_pos.x > viewport_size.x - edge_margin:
			#move_direction.x = 1
			#
		#if mouse_pos.y < edge_margin:
			#move_direction.y = -1
		#elif mouse_pos.y > viewport_size.y - edge_margin:
			#move_direction.y = 1
			
	# Applica il movimento alla posizione della camera
	# Usiamo .normalized() per evitare movimenti diagonali più veloci
	position += move_direction.normalized() * pan_speed * delta


func handle_key_zoom(delta: float):
	var zoom_factor = 1.0 # Nessun cambiamento di default
	
	if Input.is_action_pressed("zoom_in"): # Tasto Z
		zoom_factor -= key_zoom_speed * delta
	if Input.is_action_pressed("zoom_out"): # Tasto A
		zoom_factor += key_zoom_speed * delta

	if zoom_factor != 1.0:
		apply_zoom(zoom_factor)


func apply_zoom(factor: float):
	# Applica il fattore di zoom
	zoom *= factor
	
	# Limita lo zoom tra i valori min e max
	zoom.x = clamp(zoom.x, min_zoom, max_zoom)
	zoom.y = clamp(zoom.y, min_zoom, max_zoom)
