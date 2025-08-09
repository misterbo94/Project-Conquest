# animation_data.gd - Classe per gestire i dati di una singola animazione
class_name AnimationData
extends RefCounted

var mother_coord: Vector2i
var from_state: int
var to_state: int
var start_time: float
var duration: float
var progress: float = 0.0
var completed: bool = false

func _init(coord: Vector2i, from: int, to: int, dur: float):
	mother_coord = coord
	from_state = from
	to_state = to
	duration = dur
	start_time = Time.get_unix_time_from_system()

func update_progress(current_time: float, easing_func: Callable) -> bool:
	"""
	Aggiorna il progresso dell'animazione
	Ritorna true se l'animazione è completata
	"""
	var elapsed_time = current_time - start_time
	var raw_progress = elapsed_time / duration
	
	if raw_progress >= 1.0:
		progress = 1.0
		completed = true
		return true
	else:
		var old_progress = progress
		progress = easing_func.call(raw_progress)
		# Ritorna true se c'è stata una variazione significativa
		return abs(progress - old_progress) > 0.01

func get_interpolated_state() -> float:
	"""Calcola lo stato interpolato corrente"""
	return lerp(float(from_state), float(to_state), progress)

func get_texture_value() -> float:
	"""Converte lo stato interpolato in valore texture (formula magica)"""
	return (get_interpolated_state() + 1.0) * 0.5

func is_completed() -> bool:
	return completed

func get_debug_string() -> String:
	return "Animation[%s: %d→%d, progress=%.2f]" % [mother_coord, from_state, to_state, progress]
