func _ready():
	print("Game: _ready() START")
	
	if not is_instance_valid(roll_animation_controller):
		printerr("CRITICAL: RollAnimationController node (expected @onready from Game.tscn) NOT FOUND or NOT VALID!")
	else:
		print("Game: RollAnimationController node found and valid.")
		
		# Connect to its signals
		if roll_animation_controller.has_signal("logical_roll_requested"):
			roll_animation_controller.logical_roll_requested.connect(_on_rac_logical_roll_requested)
			print("Game: Connected to RAC logical_roll_requested")
		
		if roll_animation_controller.has_signal("fanfare_start_requested"):
			roll_animation_controller.fanfare_start_requested.connect(_on_rac_fanfare_start_requested)
			print("Game: Connected to RAC fanfare_start_requested")
		
		if roll_animation_controller.has_signal("move_to_history_requested"):
			roll_animation_controller.move_to_history_requested.connect(_on_rac_move_to_history_requested)
			print("Game: Connected to RAC move_to_history_requested")
		
		if roll_animation_controller.has_signal("full_animation_sequence_complete"):
			roll_animation_controller.full_animation_sequence_complete.connect(_on_rac_full_animation_sequence_complete)
			print("Game: Connected to RAC full_animation_sequence_complete")

	print("Game: Setting up UI parent node...")
	if is_instance_valid(ui_canvas):
		print("Game: ui_canvas node found and valid, setting as UI parent.")
		SceneUIManager.set_ui_parent_node(ui_canvas)
	else:
		printerr("Game: CRITICAL - ui_canvas node not found, cannot set parent for SceneUIManager!")
		print("Game: Falling back to using Game node as UI parent.")
		SceneUIManager.set_ui_parent_node(self)

	print("Game: Setting up HUD...")
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		if is_instance_valid(ui_canvas): 
			ui_canvas.add_child(hud_instance)
			print("Game: Added HUD to ui_canvas")
		else: 
			add_child(hud_instance)
			printerr("Game: UICanvas not found for HUD, added directly to Game node")
		
		# Connect HUD signals
		if hud_instance.has_signal("inventory_toggled"): 
			hud_instance.inventory_toggled.connect(_on_hud_inventory_toggled)
			print("Game: Connected to HUD inventory_toggled")
		if hud_instance.has_signal("fanfare_animation_finished"): 
			hud_instance.fanfare_animation_finished.connect(_on_hud_fanfare_animation_finished)
			print("Game: Connected to HUD fanfare_animation_finished")
		else: 
			printerr("WARNING: HUD.gd needs 'fanfare_animation_finished' signal.")
		
		hud_instance.visible = false # Initially hidden
		print("Game: HUD setup complete")
		
		# Setup references for RollAnimationController again, now that hud_instance is valid
		if is_instance_valid(roll_animation_controller) and roll_animation_controller.has_method("setup_references"):
			roll_animation_controller.setup_references(roll_button, ui_canvas, hud_instance)
			print("Game: Updated RAC references with HUD")

	else: 
		printerr("ERROR: HUD.tscn not preloaded!")

	print("Game: Setting up SceneUIManager signals...")
	# Connect to SceneUIManager signals
	SceneUIManager.main_menu_start_game_pressed.connect(_on_main_menu_start_game)
	SceneUIManager.loot_screen_loot_selected.connect(_on_loot_selected)
	SceneUIManager.loot_screen_skipped.connect(_on_loot_screen_closed)
	SceneUIManager.game_over_retry_pressed.connect(_on_game_over_retry_pressed)
	SceneUIManager.game_over_main_menu_pressed.connect(_on_game_over_main_menu_pressed)
	print("Game: SceneUIManager signals connected")
	
	print("Game: Setting up roll button...")
	if is_instance_valid(roll_button): 
		roll_button.pressed.connect(_on_roll_button_pressed)
		print("Game: Roll button connected")
	
	print("Game: Setting up ProgressionManager signals...")
	if ProgressionManager.has_signal("game_phase_changed"): 
		ProgressionManager.game_phase_changed.connect(_on_progression_game_phase_changed)
	if ProgressionManager.has_signal("cornerstone_slot_unlocked"): 
		ProgressionManager.cornerstone_slot_unlocked.connect(_on_progression_cornerstone_unlocked)
	if ProgressionManager.has_signal("boss_indicator_update"): 
		ProgressionManager.boss_indicator_update.connect(_on_progression_boss_indicator_update)
	print("Game: ProgressionManager signals connected")

	print("Game: Setting initial game state and showing main menu...")
	current_game_roll_state = GameRollState.MENU
	SceneUIManager.show_main_menu()
	print("Game: Requested SceneUIManager to show main menu.")
	print("Game: _ready() END") 