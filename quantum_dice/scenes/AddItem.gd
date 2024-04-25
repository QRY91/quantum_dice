extends Button




func _on_pressed():
	owner.find_child("Inventory").add_slot(str(randi() % 3))
