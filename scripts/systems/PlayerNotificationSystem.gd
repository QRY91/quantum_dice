# res://scripts/systems/PlayerNotificationSystem.gd
# TABS FOR INDENTATION
extends Node

# For Phase 1, this is a very simple system that just prints to console.
# Later, this can be expanded to show messages on the UI.

# Signal to notify UI elements if they want to display the message
signal new_notification(message_text: String, duration: float)

func display_message(text: String, duration: float = 3.0):
	print("NOTIFICATION: ", text, " (Duration: ", duration, "s)")
	emit_signal("new_notification", text, duration)

# Example of how a UI element (e.g., in HUD.gd) could listen:
# In HUD.gd's _ready():
#   if PlayerNotificationSystem.has_signal("new_notification"):
#       PlayerNotificationSystem.new_notification.connect(_on_player_notification)
#
# func _on_player_notification(message_text: String, duration: float):
#   my_notification_label.text = message_text
#   get_tree().create_timer(duration).timeout.connect(func(): my_notification_label.text = "")
