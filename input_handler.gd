# InputHandler.gd - VERSIONE CORRETTA
extends Node
class_name InputHandler

signal region_clicked(world_pos: Vector2)

@export var click_enabled: bool = true
@export var debug_clicks: bool = true

func _ready():
	print("InputHandler pronto")

func _unhandled_input(event: InputEvent):
	if not click_enabled: 
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# FIX: Usa il viewport per ottenere mouse position
		var world_pos = get_viewport().get_mouse_position()
		
		if debug_clicks:
			print("InputHandler: Click rilevato at ", world_pos)
		
		region_clicked.emit(world_pos)
