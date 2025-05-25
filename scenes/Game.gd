# res://scripts/Game.gd
# TABS FOR INDENTATION
extends Node2D

# --- Game State Enum ---
enum GameState {
	MENU,
	INITIALIZING_GAME,
	INITIALIZING_ROUND,
	PLAYING,
	ROLL_ANIMATION,
	PROCESSING_ROLL,
	LOOT_SELECTION,
	ROUND_SUMMARY,
	GAME_OVER
}
var current_game_state: GameState = GameState.MENU # Start in MENU state

var enable_debug_rolls: bool = true # Set to true for testing

# --- Player's DICE & Roll History (LOGIC ONLY) ---
var current_player_dice: Array[GlyphData] = []
var roll_history: Array[GlyphData] = [] # For current round's synergies
var last_rolled_glyph: GlyphData = null # Still useful for logic, HUD will also get it

# --- Scoring & Progression ---
var current_round_score: int = 0
var target_score: int = 0
var rolls_left: int = 0
var current_level: int = 1
var total_accumulated_score: int = 0
var high_score: int = 0
const HIGH_SCORE_FILE_PATH: String = "user://quantum_dice_highscore.dat" # Save in user data directory

# --- Configurable Game Parameters ---
const STARTING_ROLLS: int = 6
const BASE_TARGET_SCORE: int = 15
const TARGET_SCORE_PER_LEVEL_INCREASE: int = 7
const ROLLS_INCREASE_EVERY_X_LEVELS: int = 2
const MAX_ROLLS_CAP: int = 15 # Using the visual history slot count from HUD later if needed, or keep separate

# --- Synergy Tracking ---
var synergies_fired_this_round: Dictionary = {}

# --- Rune Phrases and Boons ---
var RUNE_PHRASES: Dictionary = {
	"SUN_POWER": {
		"id": "sun_power", # Unique ID for this phrase/boon
		"display_name": "Sun's Radiance",
		"runes_required": ["rune_sowilo", "rune_fehu"], # List of GlyphData IDs
		"boon_description": "All 'dice' type glyphs score +2 points for the rest of the run."
		# We'll add more boon effect data later if needed
	},
	"WATER_FLOW": {
		"id": "water_flow",
		"display_name": "Water's Flow",
		"runes_required": ["rune_laguz", "rune_ansuz"], # Example
		"boon_description": "Gain +1 max roll per round for the rest of the run (up to a new cap)."
	}
	# Add more phrases here later
}
var active_boons: Dictionary = {} # Key: boon_id, Value: true (or boon data)
var run_score_multiplier_boon: float = 1.0 # For boons affecting score directly
var extra_points_per_dice_glyph_boon: int = 0 # For "Sun's Radiance"
var extra_max_rolls_boon: int = 0 # For "Water's Flow"

# --- CORE UI Node References (Only those Game.gd directly interacts with for non-display logic) ---
@onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
# @onready var main_game_ui_root: Control = $UICanvas/MainGameUI # Optional: To show/hide the whole game UI block

# --- Scene Preloads & Instances ---
var main_menu_scene: PackedScene = preload("res://scenes/ui/MainMenu.tscn")
@onready var main_menu_instance: Control

var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
@onready var loot_screen_instance: Control

var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn") # Preload HUD scene
@onready var hud_instance: Control # Instance of the HUD

@onready var roll_animation_timer: Timer = $RollAnimationTimer

# --- Audio ---
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer # Path to your AudioStreamPlayer node

# Preload sound resources (replace with your actual file paths!)
#var sfx_ui_click: AudioStream = preload("res://assets/sfx/ui_click.wav") 
#var sfx_roll_start: AudioStream = preload("res://assets/sfx/roll_start.wav")
#var sfx_roll_land: AudioStream = preload("res://assets/sfx/roll_land.wav")
var sfx_synergy_pop: AudioStream = preload("res://assets/sfx/synergy_success.ogg")
var sfx_loot_appears: AudioStream = preload("res://assets/sfx/loot_appears.ogg") # When loot screen shows
var sfx_glyph_added: AudioStream = preload("res://assets/sfx/glyph_added.ogg")   # When loot is confirmed
#var sfx_round_win: AudioStream = preload("res://assets/sfx/round_win.wav")
#var sfx_game_over: AudioStream = preload("res://assets/sfx/game_over.wav")
# Add more as needed, e.g., sfx_round_loss if different from game_over

var game_over_screen_scene: PackedScene = preload("res://scenes/ui/GameOverScreen.tscn")
@onready var game_over_instance: Control

func _ready():
	_load_high_score()
	# --- 1. Assign Path to AnimatedRollButton ---
	# This @onready var should be at the class level:
	# @onready var roll_button: TextureButton = $UICanvas/MainGameUI/AnimatedRollButton
	# If you have the line `roll_button = $UICanvas/MainGameUI/AnimatedRollButton` here, ensure the class-level one is also correct.
	# For clarity, rely on the class-level @onready var.

	# --- 2. Instantiate and Setup HUD ---
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		var ui_canvas = get_node_or_null("UICanvas") # Safer way to get node
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(hud_instance)
		else:
			printerr("ERROR: UICanvas node not found for adding HUD! Adding to self.")
			add_child(hud_instance)
		if hud_instance.has_signal("inventory_toggled"):
			hud_instance.inventory_toggled.connect(Callable(self, "_on_hud_inventory_toggled"))
			print("DEBUG: Connected hud_instance.inventory_toggled signal.") # Debug
		else:
			printerr("ERROR: hud_instance does NOT have signal 'inventory_toggled'. Check HUD.gd")
		hud_instance.visible = false 
	else:
		printerr("ERROR: HUD.tscn not preloaded!")

	# --- 3. Instantiate and Setup Main Menu ---
	if main_menu_scene:
		main_menu_instance = main_menu_scene.instantiate()
		var ui_canvas = get_node_or_null("UICanvas")
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(main_menu_instance)
		else:
			add_child(main_menu_instance)
		if main_menu_instance.has_signal("start_game_pressed"):
			main_menu_instance.start_game_pressed.connect(Callable(self, "_on_main_menu_start_game"))
		else:
			printerr("ERROR: main_menu_instance does NOT have signal 'start_game_pressed'.")
	else:
		printerr("ERROR: MainMenu.tscn not preloaded!")

	# --- 4. Instantiate and Setup Loot Screen ---
	# ... (loot screen setup as before, ensure it's added to ui_canvas and hidden) ...
	if loot_screen_scene:
		loot_screen_instance = loot_screen_scene.instantiate()
		var ui_canvas = get_node_or_null("UICanvas")
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(loot_screen_instance)
		else:
			add_child(loot_screen_instance)
		# ... (connect loot_screen_instance signals) ...
		loot_screen_instance.hide()
	else:
		printerr("ERROR: LootScreen.tscn not preloaded correctly!")

	# --- Instantiate and Setup Game Over Screen ---
	if game_over_screen_scene:
		game_over_instance = game_over_screen_scene.instantiate()
		var ui_canvas = get_node_or_null("UICanvas")
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(game_over_instance)
		else:
			add_child(game_over_instance) # Fallback
		
		if game_over_instance.has_signal("retry_pressed"):
			game_over_instance.retry_pressed.connect(Callable(self, "_on_game_over_retry_pressed"))
		else:
			printerr("ERROR: game_over_instance does NOT have signal 'retry_pressed'.")
		
		if game_over_instance.has_signal("main_menu_pressed"):
			game_over_instance.main_menu_pressed.connect(Callable(self, "_on_game_over_main_menu_pressed"))
		else:
			printerr("ERROR: game_over_instance does NOT have signal 'main_menu_pressed'.")
		
		game_over_instance.hide() # Start hidden
	else:
		printerr("ERROR: GameOverScreen.tscn not preloaded!")

	# --- 5. Connect Roll Button Signal ---
	if is_instance_valid(roll_button): # roll_button is the @onready var
		roll_button.pressed.connect(Callable(self, "_on_roll_button_pressed"))
	else:
		printerr("ERROR: RollButton in _ready() is not valid for signal connection. Check path in @onready declaration.")
	
	# REMOVE connection for inventory_toggle_button from Game.gd's _ready()
	# REMOVE initial hiding of dice_face_scroll_container from Game.gd's _ready() - HUD handles its own children.
	# Connect RollAnimationTimer signal
	if is_instance_valid(roll_animation_timer):
		roll_animation_timer.timeout.connect(Callable(self, "_on_roll_animation_timer_timeout"))
		print("DEBUG: Connected roll_animation_timer.timeout signal.")
	else:
		printerr("ERROR: RollAnimationTimer node not found! Check path in @onready var or scene tree.")
		
			# Verify SFXPlayer
	if not is_instance_valid(sfx_player):
		printerr("ERROR: SFXPlayer node not found! Check path in @onready var.")
	# --- 6. Initial Game State ---
	current_game_state = GameState.MENU 
	print("Game scene _ready complete. Initial game state set to MENU.")

# --- Centralized Sound Playing Function ---
func play_sound(sound_resource: AudioStream, volume: int = 0):
	if not is_instance_valid(sfx_player):
		printerr("Cannot play sound: SFXPlayer node is not valid.")
		return
	if not is_instance_valid(sound_resource):
		printerr("Cannot play sound: Provided sound resource is not valid.")
		return
		
	sfx_player.stream = sound_resource
	if is_instance_valid(volume):
		sfx_player.volume_db = volume
	sfx_player.play()

func _process(delta):
	match current_game_state:
		GameState.MENU:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node):
				main_game_ui_node.visible = false # Hide main game area

			if is_instance_valid(hud_instance): 
				hud_instance.visible = false # Hide HUD too

			if is_instance_valid(main_menu_instance): # Ensure main_menu_instance is valid before calling show_menu
				main_menu_instance.show_menu() 
			
		GameState.INITIALIZING_GAME:
			# ... (as before) ...
			_initialize_new_game_session() 
			if is_instance_valid(hud_instance): hud_instance.reset_round_visuals()
			current_game_state = GameState.INITIALIZING_ROUND
			
		GameState.INITIALIZING_ROUND:
			# ... (as before) ...
			_initialize_current_round_setup()
			if is_instance_valid(hud_instance): 
				hud_instance.reset_round_visuals()
				var effective_max_rolls = min(STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS), MAX_ROLLS_CAP)
				hud_instance.update_rolls_display(rolls_left, effective_max_rolls)
				hud_instance.update_score_target_display(current_round_score, target_score)
				hud_instance.update_level_display(current_level)
				hud_instance.update_dice_inventory_display(current_player_dice)
				hud_instance.update_last_rolled_glyph_display(null)
			current_game_state = GameState.PLAYING
			
		GameState.PLAYING:
			var main_game_ui_node = get_node_or_null("UICanvas/MainGameUI")
			if is_instance_valid(main_game_ui_node) and not main_game_ui_node.visible:
				main_game_ui_node.visible = true # Ensure main game area is visible

			if is_instance_valid(hud_instance) and not hud_instance.visible: 
				hud_instance.visible = true # Show HUD
			_update_hud_elements() 
		GameState.ROLL_ANIMATION:
			# Game logic is paused here while the RollAnimationTimer runs.
			# The visual rolling animation (e.g., your AnimatedSprite2D on the button) plays.
			# No specific per-frame logic needed here from Game.gd for now.
			pass
			
		GameState.PROCESSING_ROLL:
			_process_the_finished_roll_outcome() # Handles logic, calls HUD updates internally now
			if rolls_left <= 0:
				current_game_state = GameState.ROUND_SUMMARY
			else:
				current_game_state = GameState.PLAYING
				
		GameState.LOOT_SELECTION:
			# Game.gd waits for signals from loot_screen_instance
			# HUD might be partially obscured or still visible
			pass 
			
		GameState.ROUND_SUMMARY:
			if current_round_score >= target_score:
				current_game_state = GameState.LOOT_SELECTION
				_prepare_and_show_loot_screen()
				#play_sound(sfx_round_win) # Play round win sound
			else:
				current_game_state = GameState.GAME_OVER
				# play_sound(sfx_round_loss_or_game_over) # Play round loss sound if different
				pass # Game Over sound will play in GAME_OVER state
				# _setup_game_over_ui() # Later
				
		GameState.GAME_OVER:
			if is_instance_valid(hud_instance): 
				hud_instance.visible = false 
			
			if total_accumulated_score > high_score: # Check/Save HS before showing screen
				high_score = total_accumulated_score
				_save_high_score()
			
			if is_instance_valid(game_over_instance) and not game_over_instance.visible:
				# This is where the data is passed
				print("DEBUG Game.gd: Calling game_over_instance.show_screen with score: ", total_accumulated_score, " and level: ", current_level) # DEBUG
				game_over_instance.show_screen(total_accumulated_score, current_level) 
				# You could also pass high_score if GameOverScreen is designed to show it:
				# game_over_instance.show_screen(total_accumulated_score, current_level, high_score)
			
			pass 

	# _update_all_ui_elements() # This function is now effectively replaced by specific calls to hud_instance


func _initialize_new_game_session():
	print("Initializing new game session...")
	current_level = 1
	total_accumulated_score = 0
	current_player_dice.clear()
	_reset_boons_and_effects()

	if GlyphDB and not GlyphDB.starting_dice_configuration.is_empty():
		current_player_dice = GlyphDB.starting_dice_configuration.duplicate(true)
		print("Player dice initialized with: ", current_player_dice.size(), " faces.")
		if is_instance_valid(hud_instance): # Update HUD after dice are set
			hud_instance.update_dice_inventory_display(current_player_dice)
	else:
		printerr("Game Error: GlyphDB not ready or starting_dice_configuration is empty!")

func _get_effective_max_rolls_for_round() -> int: # New helper function
	var calculated_rolls = STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS)
	var max_rolls_with_boon = MAX_ROLLS_CAP + extra_max_rolls_boon # Apply boon to the cap
	return min(calculated_rolls, max_rolls_with_boon)
	
func _initialize_current_round_setup():
	print("Initializing round setup for level: ", current_level)
	current_round_score = 0
	target_score = BASE_TARGET_SCORE + (current_level - 1) * TARGET_SCORE_PER_LEVEL_INCREASE
	var calculated_rolls = STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS)
	rolls_left = _get_effective_max_rolls_for_round()
	
	
	# Logical resets
	roll_history.clear() 
	synergies_fired_this_round.clear()
	last_rolled_glyph = null 
	
	var effective_max = _get_effective_max_rolls_for_round()
	print("Round ", current_level, " initialized. Target: ", target_score, ". Rolls: ", rolls_left, " (Max possible: ", effective_max, ")")
	# HUD updates will be triggered by INITIALIZING_ROUND state in _process


func _update_hud_elements(): # New function to centralize HUD updates based on game state
	if not is_instance_valid(hud_instance): return

	var effective_max_rolls = _get_effective_max_rolls_for_round() # Use helper
	hud_instance.update_rolls_display(rolls_left, effective_max_rolls)
	hud_instance.update_score_target_display(current_round_score, target_score)
	hud_instance.update_level_display(current_level)
	hud_instance.update_last_rolled_glyph_display(last_rolled_glyph) # For the separate display
	
	# Update roll button disabled state
	if is_instance_valid(roll_button):
		roll_button.disabled = not (current_game_state == GameState.PLAYING and rolls_left > 0)


func _on_roll_button_pressed(): # In Game.gd
	if current_game_state == GameState.PLAYING and rolls_left > 0:
		print("Roll button pressed. Starting animation timer.")
		#play_sound(sfx_roll_start) # Play roll start sound
		current_game_state = GameState.ROLL_ANIMATION
		if is_instance_valid(roll_animation_timer):
			roll_animation_timer.start()
		else: # Fallback
			printerr("ERROR: RollAnimationTimer not valid.")
			current_game_state = GameState.PROCESSING_ROLL 
	else:
		print("Cannot roll. State:", GameState.keys()[current_game_state], "Rolls left:", rolls_left)


func _process_the_finished_roll_outcome():
	if current_player_dice.is_empty():
		printerr("CRITICAL: Player dice is empty! Cannot process roll.")
		current_game_state = GameState.PLAYING
		return

	var rolled_glyph_index = randi() % current_player_dice.size()
	last_rolled_glyph = current_player_dice[rolled_glyph_index]

	if not is_instance_valid(last_rolled_glyph):
		printerr("CRITICAL: last_rolled_glyph invalid post-roll! Index: ", rolled_glyph_index)
		current_game_state = GameState.PLAYING 
		return

	print("Rolled: '", last_rolled_glyph.display_name, "' (Val: ", str(last_rolled_glyph.value), ")")
	
	# Update on-button glyph display (if it's different from the main hud_instance.last_roll_display)
	var rolled_glyph_display_on_button = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(rolled_glyph_display_on_button):
		rolled_glyph_display_on_button.texture = last_rolled_glyph.texture
		rolled_glyph_display_on_button.visible = true
		
	var score_from_glyph = last_rolled_glyph.value
	if last_rolled_glyph.type == "dice" and active_boons.has("sun_power"): # Check if boon is active
		score_from_glyph += extra_points_per_dice_glyph_boon
		print("Sun's Radiance Bonus! Dice glyph now scores: ", score_from_glyph)

	current_round_score += score_from_glyph
	total_accumulated_score += score_from_glyph # Use the potentially boosted score
	roll_history.append(last_rolled_glyph)

	if is_instance_valid(hud_instance): # Add rolled glyph to visual history track in HUD
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph)
	
	_check_and_apply_synergies() # This will call hud_instance.show_synergy_message()
	
	rolls_left -= 1
	# _update_hud_elements() will be called by _process in PLAYING or other states
	print("Roll processed. Score: ", current_round_score, ". Rolls left: ", rolls_left)


func add_glyph_to_player_dice(glyph_data: GlyphData):
	if glyph_data and glyph_data is GlyphData:
		current_player_dice.append(glyph_data)
		print("Added glyph '", glyph_data.display_name, "' to player dice. Total: ", current_player_dice.size())
		# HUD will be updated via _on_loot_selected -> hud_instance.update_dice_inventory_display
	else:
		printerr("Attempted to add invalid glyph data to dice.")


func _check_and_apply_synergies():
	if roll_history.is_empty():
		return

	# --- Re-declare these local variables here ---
	var total_synergy_bonus: int = 0
	var synergy_message: String = "" # To build a combined message if multiple trigger
	var new_boon_activated_message: String = "" # For boon specific messages

	# --- Synergy 1: Numeric Double ---
	if not synergies_fired_this_round.has("numeric_double"):
		var dice_values_seen: Dictionary = {}
		for roll_data in roll_history:
			if roll_data.type == "dice":
				if not dice_values_seen.has(roll_data.value):
					dice_values_seen[roll_data.value] = 1
				else:
					dice_values_seen[roll_data.value] += 1
				
				if dice_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 5 # Apply bonus to local var
					synergies_fired_this_round["numeric_double"] = true
					synergy_message += "NUMERIC DOUBLE! +5\n" # Append to local var
					sfx(10) 
					print("Synergy: Numeric Double triggered!")
					break 

	# --- Synergy 2: Roman Gathering ---
	if not synergies_fired_this_round.has("roman_gathering"):
		var roman_glyph_count: int = 0
		for roll_data in roll_history:
			if roll_data.type == "roman":
				roman_glyph_count += 1
		
		if roman_glyph_count >= 2:
			total_synergy_bonus += 10 # Apply bonus to local var
			synergies_fired_this_round["roman_gathering"] = true
			synergy_message += "ROMAN GATHERING! +10\n" # Append to local var
			sfx(11) 
			print("Synergy: Roman Gathering triggered!")

	# --- Synergy 3: Card Pair ---
	if not synergies_fired_this_round.has("card_pair"):
		var card_values_seen: Dictionary = {}
		for roll_data in roll_history:
			if roll_data.type == "card":
				if not card_values_seen.has(roll_data.value):
					card_values_seen[roll_data.value] = 1
				else:
					card_values_seen[roll_data.value] += 1

				if card_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 8 # Apply bonus to local var
					synergies_fired_this_round["card_pair"] = true
					synergy_message += "CARD PAIR! +8\n" # Append to local var
					sfx(12) 
					print("Synergy: Card Pair triggered!")
					break

# --- Synergy 4: Simple Flush (3+ cards of same suit in history) ---
	if not synergies_fired_this_round.has("simple_flush"):
		var suit_counts: Dictionary = { # Dictionary to count occurrences of each suit
			"hearts": 0,
			"diamonds": 0,
			"clubs": 0,
			"spades": 0
		}
		var cards_in_history: Array[GlyphData] = [] # Collect only card type glyphs

		for roll_data in roll_history:
			if roll_data.type == "card" and is_instance_valid(roll_data) and roll_data.suit != "":
				cards_in_history.append(roll_data)
				if suit_counts.has(roll_data.suit):
					suit_counts[roll_data.suit] += 1
		
		# Check if any suit count reached 3 or more
		for suit_name in suit_counts:
			if suit_counts[suit_name] >= 3:
				var flush_bonus = 15 # Example bonus
				total_synergy_bonus += flush_bonus
				synergies_fired_this_round["simple_flush"] = true # Fire only once per round, even if multiple flushes
				synergy_message += "FLUSH (" + suit_name.capitalize() + ")! +" + str(flush_bonus) + "\n"
				sfx(13) # New placeholder SFX ID for flush
				print("Synergy: Simple Flush triggered for ", suit_name)
				break # Found a flush, no need to check other suits for this specific synergy trigger
				
# --- Check for Rune Phrase Boons ---
	var current_runes_in_history_ids: Array[String] = []
	for roll_data in roll_history:
		if roll_data.type == "rune":
			if is_instance_valid(roll_data) and roll_data.id != "": # Ensure ID is valid
				current_runes_in_history_ids.append(roll_data.id)
			else:
				printerr("DEBUG RUNE CHECK: Invalid rune roll_data in history.")


	if not current_runes_in_history_ids.is_empty():
		print("DEBUG RUNE CHECK: Runes in history this round: ", current_runes_in_history_ids) # DEBUG
		for phrase_key in RUNE_PHRASES:
			var phrase_data = RUNE_PHRASES[phrase_key]
			var phrase_id = phrase_data.id
			print("DEBUG RUNE CHECK: Checking phrase '", phrase_data.display_name, "' needs ", phrase_data.runes_required) # DEBUG
			
			if not active_boons.has(phrase_id):
				var all_required_runes_found = true
				for required_rune_id in phrase_data.runes_required:
					if not required_rune_id in current_runes_in_history_ids:
						all_required_runes_found = false
						print("DEBUG RUNE CHECK: Missing '", required_rune_id, "' for phrase '", phrase_data.display_name, "'") # DEBUG
						break 
				
				if all_required_runes_found:
					print("BOON ACTIVATED: ", phrase_data.display_name)
					active_boons[phrase_id] = true 
					new_boon_activated_message += "BOON: " + phrase_data.display_name + "!\n(" + phrase_data.boon_description + ")\n"
					_apply_boon_effect(phrase_id)
					# No break here if you want multiple distinct phrases to activate in one check
				#else: # Optional: print if a phrase check failed completely
					#print("DEBUG RUNE CHECK: Phrase '", phrase_data.display_name, "' not completed.")
			#else: # Optional: print if boon already active
				#print("DEBUG RUNE CHECK: Boon '", phrase_data.display_name, "' already active.")
	# --- Apply Bonuses to Game Score and Tell HUD to Display Message ---
	if total_synergy_bonus > 0:
		current_round_score += total_synergy_bonus
		total_accumulated_score += total_synergy_bonus
		print("Total synergy bonus this roll: ", total_synergy_bonus)
		# Prepend boon message if any activated this turn
		var final_message = new_boon_activated_message + synergy_message
		if is_instance_valid(hud_instance):
			hud_instance.show_synergy_message(final_message.strip_edges(true, true))
	elif not new_boon_activated_message.is_empty(): # Only a boon activated, no other synergy
		if is_instance_valid(hud_instance):
			hud_instance.show_synergy_message(new_boon_activated_message.strip_edges(true, true))
		play_sound(sfx_synergy_pop, 3) # Play synergy sound (once for any synergy batch)

	# Update HUD based on game state which might include boon effects
	_update_hud_elements() # This will reflect score changes

# --- Scene/UI Management Callbacks ---
func _on_main_menu_start_game():
	if is_instance_valid(main_menu_instance):
		main_menu_instance.hide_menu()
	# if is_instance_valid($UICanvas/MainGameUI): $UICanvas/MainGameUI.visible = true # HUD visibility handled by PLAYING state
	current_game_state = GameState.INITIALIZING_GAME
	#play_sound(sfx_ui_click)

func _prepare_and_show_loot_screen():
	# ... (same as before, calls loot_screen_instance.display_loot_options) ...
	print("DEBUG: Attempting to connect loot_screen_instance signals...")
	if loot_screen_instance.has_signal("loot_selected"):
		var error_code = loot_screen_instance.loot_selected.connect(Callable(self, "_on_loot_selected"))
		if error_code == OK:
				print("DEBUG: 'loot_selected' signal connected successfully to _on_loot_selected.")
		else:
			printerr("ERROR: Failed to connect 'loot_selected' signal. Error code: ", error_code)
	else:
		printerr("ERROR: loot_screen_instance does NOT have signal 'loot_selected'.")
		print("Preparing loot screen...")
		if not is_instance_valid(loot_screen_instance):
			printerr("Loot screen instance is not valid! Skipping loot.")
			_on_loot_screen_closed()
		return
	var loot_options = GlyphDB.get_random_loot_options(3) # Removed current_player_dice from here
	if not loot_options.is_empty():
		loot_screen_instance.display_loot_options(loot_options)
		play_sound(sfx_loot_appears) # Sound when loot screen becomes active
	elif loot_options.is_empty():
		print("No loot options available. Skipping loot.")
		_on_loot_screen_closed()
		return
	loot_screen_instance.display_loot_options(loot_options)

func _on_loot_selected(chosen_glyph: GlyphData):
	print("Game: Loot selected - ", chosen_glyph.display_name)
	add_glyph_to_player_dice(chosen_glyph)
	if is_instance_valid(hud_instance):
		hud_instance.update_dice_inventory_display(current_player_dice)
	
	current_level += 1
	total_accumulated_score += 50 
	play_sound(sfx_glyph_added) # Sound for confirming loot choice
	
	# Defer the state change to avoid issues with input processing order
	call_deferred("set_game_state_deferred", GameState.INITIALIZING_ROUND)
	print("Game: Loot selected. Deferred state change to INITIALIZING_ROUND.")


func _on_loot_screen_closed():
	print("Game: Loot screen closed, proceeding to next round without new glyph.")
	current_level += 1 
	
	# Defer the state change
	call_deferred("set_game_state_deferred", GameState.INITIALIZING_ROUND)
	print("Game: Loot screen closed. Deferred state change to INITIALIZING_ROUND.")


# New helper function to actually set the state when called deferred
func set_game_state_deferred(new_state: GameState):
	current_game_state = new_state
	print("Game: State now set to ", GameState.keys()[new_state], " via deferred call.")

# --- SFX Placeholder ---
func sfx(sfx_id: int): # This can stay in Game.gd or move to an Audio Manager Autoload
	print("SFX Player: Playing sound id ", sfx_id)

func _on_hud_inventory_toggled(is_inventory_visible: bool):
	print("Game: Received HUD inventory_toggled signal. Visible: ", is_inventory_visible)
	if is_inventory_visible:
		if is_instance_valid(hud_instance):
			# This is where Game.gd tells HUD to update its content with the current dice
			hud_instance.update_dice_inventory_display(current_player_dice)
	# HUD itself handles its dice_face_scroll_container.visible state

func _on_roll_animation_timer_timeout():
	# Ensure we only process this if we were actually in the ROLL_ANIMATION state.
	# This prevents issues if the timer somehow fires at an unexpected time.
	if current_game_state == GameState.ROLL_ANIMATION:
		print("Roll animation timer timeout. Processing roll outcome.")
		#play_sound(sfx_roll_land) # Play roll land sound
		current_game_state = GameState.PROCESSING_ROLL
	else:
		print("RollAnimationTimer timeout, but game state was not ROLL_ANIMATION. State: ", GameState.keys()[current_game_state])

func _on_game_over_retry_pressed():
	print("Game: Retry pressed from Game Over screen.")
	if is_instance_valid(game_over_instance):
		game_over_instance.hide_screen() # hide_screen() is now in GameOverScreen.gd
	current_game_state = GameState.INITIALIZING_GAME # Start a new game

func _on_game_over_main_menu_pressed():
	print("Game: Main Menu pressed from Game Over screen.")
	if is_instance_valid(game_over_instance):
		game_over_instance.hide_screen()
	current_game_state = GameState.MENU # Go to main menu

func _load_high_score():
	if FileAccess.file_exists(HIGH_SCORE_FILE_PATH):
		var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.READ)
		if is_instance_valid(file):
			high_score = file.get_as_text().to_int() # Or file.get_32() if saved as binary int
			file.close()
			print("High score loaded: ", high_score)
		else:
			printerr("Failed to open high score file for reading. Error: ", FileAccess.get_open_error())
	else:
		print("No high score file found. Starting fresh.")

func _save_high_score():
	var file = FileAccess.open(HIGH_SCORE_FILE_PATH, FileAccess.WRITE)
	if is_instance_valid(file):
		file.store_string(str(high_score)) # Save as string
		# Or: file.store_32(high_score) # Save as binary integer
		file.close()
		print("New high score saved: ", high_score)
	else:
		printerr("Failed to open high score file for writing. Error: ", FileAccess.get_open_error())

func _apply_boon_effect(boon_id: String):
	if boon_id == "sun_power":
		extra_points_per_dice_glyph_boon = 2
		print("Sun's Radiance boon active: 'dice' glyphs +2 pts.")
	elif boon_id == "water_flow":
		extra_max_rolls_boon = 1 # This will be used in calculating effective max rolls
		print("Water's Flow boon active: +1 max roll per round.")
		# Important: Need to update HUD immediately if max rolls changed
		_update_hud_elements() 


func _reset_boons_and_effects(): # Call this at the start of a new game
	active_boons.clear()
	run_score_multiplier_boon = 1.0
	extra_points_per_dice_glyph_boon = 0
	extra_max_rolls_boon = 0
	print("All boons and run-specific effects reset.")
	
func _unhandled_input(event: InputEvent): # Add this function if it doesn't exist
	if not enable_debug_rolls:
		return
	if not current_game_state == GameState.PLAYING: # Only allow debug rolls during PLAYING state
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var forced_glyph: GlyphData = null
		if event.keycode == KEY_1: forced_glyph = GlyphDB.get_glyph_by_id("rune_sowilo")
		elif event.keycode == KEY_2: forced_glyph = GlyphDB.get_glyph_by_id("rune_fehu")
		elif event.keycode == KEY_3: forced_glyph = GlyphDB.get_glyph_by_id("rune_laguz")
		# Add more keys for other runes or specific glyphs

		if is_instance_valid(forced_glyph):
			print("DEBUG: Forcing roll of: ", forced_glyph.display_name)
			last_rolled_glyph = forced_glyph # Override what would have been rolled
			# Manually trigger the rest of the roll processing logic normally called after randi()
			_process_forced_roll_outcome() # A new function similar to _process_the_finished_roll_outcome
			get_viewport().set_input_as_handled()


func _process_forced_roll_outcome():
	# This function is a stripped-down version of _process_the_finished_roll_outcome,
	# as last_rolled_glyph is already set.
	if not is_instance_valid(last_rolled_glyph):
		printerr("CRITICAL: Forced last_rolled_glyph is invalid!")
		return

	print("DEBUG Forcing - Rolled: '", last_rolled_glyph.display_name, "' (Val: ", str(last_rolled_glyph.value), ")")
	
	var rolled_glyph_display_on_button = roll_button.get_node_or_null("RolledGlyphOnButtonDisplay")
	if is_instance_valid(rolled_glyph_display_on_button):
		rolled_glyph_display_on_button.texture = last_rolled_glyph.texture
		rolled_glyph_display_on_button.visible = true
	
	var score_from_glyph = last_rolled_glyph.value
	if last_rolled_glyph.type == "dice" and active_boons.has("sun_power"):
		score_from_glyph += extra_points_per_dice_glyph_boon
	current_round_score += score_from_glyph
	total_accumulated_score += score_from_glyph 
	roll_history.append(last_rolled_glyph)

	if is_instance_valid(hud_instance):
		hud_instance.add_glyph_to_visual_history(last_rolled_glyph)
	
	_check_and_apply_synergies()
	
	rolls_left -= 1 # Still consume a roll
	print("DEBUG Forced Roll Processed. Score: ", current_round_score, ". Rolls left: ", rolls_left)
	
	# After processing, determine next game state
	if rolls_left <= 0:
		current_game_state = GameState.ROUND_SUMMARY
	else:
		current_game_state = GameState.PLAYING # Or directly update HUD if not relying on state change in _process
	_update_hud_elements() # Update HUD immediately
