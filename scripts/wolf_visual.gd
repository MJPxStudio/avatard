# wolf_visual.gd
# Attach to a Node2D child of the wolf CharacterBody2D
# Draws a simple placeholder wolf shape until real sprites are added
extends Node2D

func _draw() -> void:
	# Body
	draw_circle(Vector2(0, 0), 10, Color("8B4513"))
	# Head
	draw_circle(Vector2(0, -12), 7, Color("8B4513"))
	# Ears
	draw_circle(Vector2(-5, -18), 3, Color("6B3410"))
	draw_circle(Vector2(5, -18), 3, Color("6B3410"))
	# Eyes
	draw_circle(Vector2(-3, -13), 1.5, Color("ff4400"))
	draw_circle(Vector2(3, -13), 1.5, Color("ff4400"))
