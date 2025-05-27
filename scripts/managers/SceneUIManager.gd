# res://scripts/managers/SceneUIManager.gd
# TABS FOR INDENTATION
extends Node

# --- Signals that Game.gd will connect to ---
signal main_menu_start_game_pressed
signal loot_screen_loot_selected(chosen_glyph: GlyphData)
signal loot_screen_skipped
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

# Parent node for UI scenes (e.g., Game.gd's UICanvas)
# This needs to be set by Game.gd after SceneUIManager is ready.
var ui_parent_node: Node = null

func _ready():
	print("SceneUIManager: Initialized.")

func set_ui_parent_node(parent: Node):
	if is_instance_valid(parent):
		ui_parent_node = parent
		print("SceneUIManager: UI Parent Node set.")
		_ensure_scenes_instantiated() # Instantiate scenes once parent is known
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
			main_menu_instance.start_game_pressed.connect(Callable(self, "_on_main_menu_start_game_internal"))
		main_menu_instance.hide() # Start hidden
		print("SceneUIManager: MainMenu instantiated.")

	# Loot Screen
	if loot_screen_scene and not is_instance_valid(loot_screen_instance):
		loot_screen_instance = loot_screen_scene.instantiate()
		ui_parent_node.add_child(loot_screen_instance)
		if loot_screen_instance.has_signal("loot_selected"):
			loot_screen_instance.loot_selected.connect(Callable(self, "_on_loot_selected_internal"))
		if loot_screen_instance.has_signal("skip_loot_pressed"): # Assuming LootScreen.gd has this
			loot_screen_instance.skip_loot_pressed.connect(Callable(self, "_on_loot_skipped_internal"))
		loot_screen_instance.hide()
		print("SceneUIManager: LootScreen instantiated.")

	# Game Over Screen
	if game_over_screen_scene and not is_instance_valid(game_over_instance):
		game_over_instance = game_over_screen_scene.instantiate()
		ui_parent_node.add_child(game_over_instance)
		if game_over_instance.has_signal("retry_pressed"):
			game_over_instance.retry_pressed.connect(Callable(self, "_on_game_over_retry_internal"))
		if game_over_instance.has_signal("main_menu_pressed"):
			game_over_instance.main_menu_pressed.connect(Callable(self, "_on_game_over_main_menu_internal"))
		game_over_instance.hide()
		print("SceneUIManager: GameOverScreen instantiated.")


# --- Public Methods for Game.gd to Call ---
func show_main_menu():
	_ensure_scenes_instantiated() # Ensure it's ready
	if is_instance_valid(main_menu_instance):
		# Hide others
		if is_instance_valid(loot_screen_instance): loot_screen_instance.hide()
		if is_instance_valid(game_over_instance): game_over_instance.hide()
		# Game.gd will hide HUD and MainGameUI itself
		
		if main_menu_instance.has_method("show_menu"): # If MainMenu.gd has a specific show method
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
	_ensure_scenes_instantiated()
	if is_instance_valid(loot_screen_instance):
		if loot_screen_instance.has_method("display_loot_options"):
			loot_screen_instance.display_loot_options(loot_options) # Assumes this method also calls .show()
			# If not, call loot_screen_instance.show() here
			print("SceneUIManager: Showing LootScreen with options.")
		else:
			printerr("SceneUIManager: LootScreen missing display_loot_options method.")
			loot_screen_instance.show() # Basic show as fallback
	else:
		printerr("SceneUIManager: LootScreen instance not valid to show.")

func hide_loot_screen():
	if is_instance_valid(loot_screen_instance):
		loot_screen_instance.hide()
		print("SceneUIManager: Hiding LootScreen.")


func show_game_over_screen(final_score: int, round_reached: int):
	_ensure_scenes_instantiated()
	if is_instance_valid(game_over_instance):
		if game_over_instance.has_method("show_screen"):
			game_over_instance.show_screen(final_score, round_reached) # Assumes this method also calls .show()
			print("SceneUIManager: Showing GameOverScreen.")
		else:
			printerr("SceneUIManager: GameOverScreen missing show_screen method.")
			game_over_instance.show() # Basic show
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
	hide_main_menu() # Manager can decide to hide it

func _on_loot_selected_internal(chosen_glyph: GlyphData):
	print("SceneUIManager: Loot selected. Emitting signal.")
	emit_signal("loot_screen_loot_selected", chosen_glyph)
	hide_loot_screen()

func _on_loot_skipped_internal():
	print("SceneUIManager: Loot skipped. Emitting signal.")
	emit_signal("loot_screen_skipped")
	hide_loot_screen()

func _on_game_over_retry_internal():
	print("SceneUIManager: GameOver Retry pressed. Emitting signal.")
	emit_signal("game_over_retry_pressed")
	hide_game_over_screen()

func _on_game_over_main_menu_internal():
	print("SceneUIManager: GameOver MainMenu pressed. Emitting signal.")
	emit_signal("game_over_main_menu_pressed")
	hide_game_over_screen()
