extends Node
## Entry scene: hands control to the Game autoload.

func _ready() -> void:
	Game.call_deferred("goto_menu")
	queue_free()
