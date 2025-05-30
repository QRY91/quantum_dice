# res://scripts/managers/SceneUIManager.gd
# TABS FOR INDENTATION
extends Node

# --- Signals that Game.gd will connect to ---
signal main_menu_start_game_pressed
signal loot_screen_loot_selected(chosen_glyph: GlyphData)
signal loot_screen_skipped
signal loot_screen_inventory_requested # <<< NEW SIGNAL
signal game_over_retry_pressed
signal game_over_main_menu_pressed

# --- Scene Preloads ---
var main_menu_scene: PackedScene = preload("res://scenes/ui/MainMenu.tscn")
var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
var game_over_screen_scene: PackedScene = preload("res://scenes/ui/GameOverScreen.tscn")

# --- Instance References (Managed by this manager) ---
var main_menu_instance: Control = null
var loot_screen_instance: Control = null
var game_over_instance: Control = null

var ui_parent_node: Node = null

func _ready():
	print("SceneUIManager: Initialized.")

func set_ui_parent_node(parent: Node):
	if is_instance_valid(parent):
		ui_parent_node = parent
		print("SceneUIManager: UI Parent Node set.")
		_ensure_scenes_instantiated()
	else:
		printerr("SceneUIManager: Invalid UI Parent Node provided.")

func _ensure_scenes_instantiated():
	if not is_instance_valid(ui_parent_node):
		printerr("SceneUIManager: Cannot instantiate UI scenes, ui_parent_node not set.")
		return

	# Main Menu
	if main_menu_scene and not is_instance_valid(main_menu_instance):
		main_menu_instance = main_menu_scene.instantiate()
		ui_parent_node.add_child(main_menu_instance)
		if main_menu_instance.has_signal("start_game_pressed"):
			main_menu_instance.start_game_pressed.connect(_on_main_menu_start_game_internal) # Callable self implied
		main_menu_instance.hide()
		print("SceneUIManager: MainMenu instantiated.")

	# Loot Screen
	if loot_screen_scene and not is_instance_valid(loot_screen_instance): # loot_screen_instance is the Control node
		var loot_screen_root_canvas_layer = loot_screen_scene.instantiate() # This is the CanvasLayer
		if not is_instance_valid(loot_screen_root_canvas_layer):
			printerr("SceneUIManager: Failed to instantiate loot_screen_scene.")
			return

		ui_parent_node.add_child(loot_screen_root_canvas_layer)
		
		# Get the actual Control node which has the script
		var control_node = loot_screen_root_canvas_layer.get_node_or_null("LootScreen") 
		if not is_instance_valid(control_node) or not control_node is Control:
			printerr("SceneUIManager: Failed to get 'LootScreen' Control child from instantiated LootScreenCanvasLayer. Found: %s" % str(control_node))
			loot_screen_root_canvas_layer.queue_free() # Clean up
			return 
		
		loot_screen_instance = control_node # Assign the Control node

		# Connect signals to loot_screen_instance (the Control node)
		if loot_screen_instance.has_signal("loot_selected"):
			loot_screen_instance.loot_selected.connect(_on_loot_selected_internal)
		if loot_screen_instance.has_signal("skip_loot_pressed"):
			loot_screen_instance.skip_loot_pressed.connect(_on_loot_skipped_internal)
		# Connect to the LootScreen's request for inventory
		if loot_screen_instance.has_signal("request_inventory_panel_show"): # Signal from LootScreen.gd
			loot_screen_instance.request_inventory_panel_show.connect(_on_loot_screen_inventory_requested_internal) # Callable self implied
		else:
			printerr("SceneUIManager: LootScreen instance is missing 'request_inventory_panel_show' signal.")
		
		loot_screen_root_canvas_layer.hide() # Hide the CanvasLayer (root)
		print("SceneUIManager: LootScreen (CanvasLayer structure) instantiated.")

	# Game Over Screen
	if game_over_screen_scene and not is_instance_valid(game_over_instance):
		game_over_instance = game_over_screen_scene.instantiate()
		ui_parent_node.add_child(game_over_instance)
		if game_over_instance.has_signal("retry_pressed"):
			game_over_instance.retry_pressed.connect(_on_game_over_retry_internal)
		if game_over_instance.has_signal("main_menu_pressed"):
			game_over_instance.main_menu_pressed.connect(_on_game_over_main_menu_internal)
		game_over_instance.hide()
		print("SceneUIManager: GameOverScreen instantiated.")


# --- Public Methods for Game.gd to Call ---
func show_main_menu():
	_ensure_scenes_instantiated()
	if is_instance_valid(main_menu_instance):
		if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
		if is_instance_valid(game_over_instance): game_over_instance.hide()
		
		if main_menu_instance.has_method("show_menu"):
			main_menu_instance.show_menu()
		else:
			main_menu_instance.show()
		print("SceneUIManager: Showing MainMenu.")
	else:
		printerr("SceneUIManager: MainMenu instance not valid to show.")

func hide_main_menu():
	if is_instance_valid(main_menu_instance):
		if main_menu_instance.has_method("hide_menu"):
			main_menu_instance.hide_menu()
		else:
			main_menu_instance.hide()
		print("SceneUIManager: Hiding MainMenu.")

func show_loot_screen(loot_options: Array):
	_ensure_scenes_instantiated() # Ensures loot_screen_instance (Control) and its CanvasLayer parent are set up
	if is_instance_valid(loot_screen_instance):
		if loot_screen_instance.has_method("display_loot_options"):
			loot_screen_instance.display_loot_options(loot_options)
			
			var root_node = loot_screen_instance.get_parent() # Should be the CanvasLayer
			if is_instance_valid(root_node): # Could check `if root_node is CanvasLayer:` for more safety
				root_node.show()
				print("SceneUIManager: Showing LootScreen (via its root CanvasLayer).")
			else:
				printerr("SceneUIManager: LootScreen's root node (CanvasLayer) not found for showing. Attempting to show loot_screen_instance directly.")
				loot_screen_instance.show() # Fallback, might not be what's intended if structure is wrong
		else:
			printerr("SceneUIManager: LootScreen Control instance missing display_loot_options method.")
	else:
		printerr("SceneUIManager: LootScreen Control instance not valid to show.")

func hide_loot_screen():
	if is_instance_valid(loot_screen_instance):
		var root_node = loot_screen_instance.get_parent() # Should be the CanvasLayer
		if is_instance_valid(root_node):
			root_node.hide()
			print("SceneUIManager: Hiding LootScreen (via its root CanvasLayer).")
		else:
			printerr("SceneUIManager: LootScreen's root node (CanvasLayer) not found for hiding. Attempting to hide loot_screen_instance directly.")
			loot_screen_instance.hide() # Fallback
	# No need to print error if loot_screen_instance itself is invalid, show_loot_screen would have handled it.


func show_game_over_screen(final_score: int, round_reached: int):
	_ensure_scenes_instantiated()
	if is_instance_valid(game_over_instance):
		if game_over_instance.has_method("show_screen"):
			game_over_instance.show_screen(final_score, round_reached)
			print("SceneUIManager: Showing GameOverScreen.")
		else:
			printerr("SceneUIManager: GameOverScreen missing show_screen method.")
			game_over_instance.show()
	else:
		printerr("SceneUIManager: GameOverScreen instance not valid to show.")

func hide_game_over_screen():
	if is_instance_valid(game_over_instance):
		if game_over_instance.has_method("hide_screen"):
			game_over_instance.hide_screen()
		else:
			game_over_instance.hide()
		print("SceneUIManager: Hiding GameOverScreen.")


# --- Internal Signal Handlers from UI Scenes ---
func _on_main_menu_start_game_internal():
	print("SceneUIManager: MainMenu Start Game pressed. Emitting signal.")
	emit_signal("main_menu_start_game_pressed")
	hide_main_menu()

func _on_loot_selected_internal(chosen_glyph: GlyphData):
	print("SceneUIManager: Loot selected. Emitting signal.")
	emit_signal("loot_screen_loot_selected", chosen_glyph)
	hide_loot_screen()

func _on_loot_skipped_internal():
	print("SceneUIManager: Loot skipped. Emitting signal.")
	emit_signal("loot_screen_skipped")
	hide_loot_screen()

# NEW internal handler for LootScreen's inventory request
func _on_loot_screen_inventory_requested_internal():
	print("SceneUIManager: LootScreen requested inventory. Emitting 'loot_screen_inventory_requested' signal.")
	emit_signal("loot_screen_inventory_requested")
	# Note: SceneUIManager does NOT hide the loot screen here. Game.gd manages HUD inventory visibility.

func _on_game_over_retry_internal():
	print("SceneUIManager: GameOver Retry pressed. Emitting signal.")
	emit_signal("game_over_retry_pressed")
	hide_game_over_screen()

func _on_game_over_main_menu_internal():
	print("SceneUIManager: GameOver MainMenu pressed. Emitting signal.")
	emit_signal("game_over_main_menu_pressed")
	hide_game_over_screen()
