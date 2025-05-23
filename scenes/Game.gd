# res://scripts/Game.gd
extends Node2D

# --- Game State Enum ---
enum GameState {
	MENU,                 # For main menu (will implement later)
	INITIALIZING_GAME,    # For setting up a brand new game session
	INITIALIZING_ROUND,   # For setting up variables at the start of each round
	PLAYING,              # Player can roll the dice
	ROLL_ANIMATION,       # Visual dice roll animation is playing (placeholder for now)
	PROCESSING_ROLL,      # After animation, process roll outcome, check synergies
	LOOT_SELECTION,       # Player chooses a new glyph
	ROUND_SUMMARY,        # Display end-of-round results (win/lose this round)
	GAME_OVER             # Display final game over screen
}
var current_game_state: GameState = GameState.INITIALIZING_GAME # Start by initializing a new game

# --- Player's Die & Roll History ---
var current_player_die: Array[GlyphData] = []
var roll_history: Array[GlyphData] = [] # For current round's synergies
var last_rolled_glyph: GlyphData = null

# --- Scoring & Progression ---
var current_round_score: int = 0
var target_score: int = 0
var rolls_left: int = 0
var current_level: int = 1
var total_accumulated_score: int = 0 # Score accumulated across all levels in current game

# --- Configurable Game Parameters ---
const STARTING_ROLLS: int = 6
const BASE_TARGET_SCORE: int = 15
const TARGET_SCORE_PER_LEVEL_INCREASE: int = 7
const ROLLS_INCREASE_EVERY_X_LEVELS: int = 2 # Gain a roll every 2 levels

# --- Synergy Tracking ---
var synergies_fired_this_round: Dictionary = {} # Key: synergy_id (String), Value: true

# --- UI Node References (to be assigned in _ready via @onready) ---
@onready var score_label: Label
@onready var target_label: Label
@onready var rolls_label: Label
@onready var level_label: Label
@onready var roll_button: Button
@onready var die_face_display_container: HBoxContainer # To show current faces on die
@onready var last_roll_display: TextureRect        # To show the texture of the last rolled glyph
@onready var synergy_notification_label: Label     # For synergy messages
# --- Scene Preloads ---
var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn")
@onready var loot_screen_instance: Control # To hold the instanced loot screen

# Will be used later for instancing UI screens
# var menu_screen_scene: PackedScene = preload("res://scenes/ui/MenuScreen.tscn") # Example
# var loot_screen_scene: PackedScene = preload("res://scenes/ui/LootScreen.tscn") # Example


func _ready():
	# Assign UI Node References - Paths must match your scene tree structure!
	# We will create these nodes in Step 2.3. For now, they are just declared.
	# Example: score_label = get_node("CanvasLayer/MainUI/ScoreLabel") 
	# We'll fill these assignments after creating the UI in the scene editor.
	
	# Connect roll button signal (will also be done after creating the button)
	# if roll_button: roll_button.pressed.connect(_on_roll_button_pressed)
	# Assign UI Node References - Ensure paths match your scene tree!
	level_label = $UICanvas/MainGameUI/LevelLabel
	rolls_label = $UICanvas/MainGameUI/RollsLabel
	score_label = $UICanvas/MainGameUI/ScoreLabel
	target_label = $UICanvas/MainGameUI/TargetLabel
	last_roll_display = $UICanvas/MainGameUI/LastRollDisplay
	die_face_display_container = $UICanvas/MainGameUI/DieFaceDisplayContainer # Will use later
	roll_button = $UICanvas/MainGameUI/RollButton
	synergy_notification_label = $UICanvas/MainGameUI/SynergyNotificationLabel

	# Verify nodes are found (good for debugging)
	if not is_instance_valid(roll_button):
		printerr("ERROR: RollButton node not found! Check path in _ready().")
	if not is_instance_valid(score_label): # Add checks for other critical UI if desired
		printerr("ERROR: ScoreLabel node not found! Check path in _ready().")
	
	# Connect roll button signal
	if is_instance_valid(roll_button):
		roll_button.pressed.connect(_on_roll_button_pressed)
	
	print("Game scene ready. Initial game state:", GameState.keys()[current_game_state])
	# current_game_state is already INITIALIZING_GAME, so _process will pick it up.
# Instantiate Loot Screen
	if loot_screen_scene:
		loot_screen_instance = loot_screen_scene.instantiate()
		# loot_screen_instance.hide() # LootScreen hides itself in its _ready
		# Add it to a CanvasLayer or directly to the Game scene tree
		# Ensure it's added under a node that's visible (e.g., UICanvas)
		var ui_canvas = $UICanvas # Assuming you have a CanvasLayer named UICanvas
		if is_instance_valid(ui_canvas):
			ui_canvas.add_child(loot_screen_instance)
		else: # Fallback if UICanvas isn't found, add directly to Game node
			printerr("UICanvas not found, adding loot screen to Game node directly.")
			add_child(loot_screen_instance)
			
			
			# Connect signals from LootScreen
		loot_screen_instance.loot_selected.connect(_on_loot_selected)
		loot_screen_instance.loot_screen_closed.connect(_on_loot_screen_closed)
	else:
		printerr("ERROR: LootScreen.tscn not preloaded correctly!")

func _process(delta):
	match current_game_state:
		GameState.INITIALIZING_GAME:
			_initialize_new_game_session()
			current_game_state = GameState.INITIALIZING_ROUND # Proceed to set up the first round
		GameState.INITIALIZING_ROUND:
			_initialize_current_round_setup()
			current_game_state = GameState.PLAYING
		GameState.PLAYING:
			# Most input for playing will be handled by button signals (like _on_roll_button_pressed)
			# Can add keyboard shortcuts here if needed, e.g., if Input.is_action_just_pressed("roll_dice"): _on_roll_button_pressed()
			pass
		GameState.ROLL_ANIMATION:
			# Placeholder: In a real game, an animation would play.
			# For now, we'll simulate it by directly going to processing.
			# print("Simulating Roll Animation...")
			# To make it feel a bit like an animation, you could use a short timer here
			# Or, for now, just transition directly:
			current_game_state = GameState.PROCESSING_ROLL
		GameState.PROCESSING_ROLL:
			_process_the_finished_roll_outcome() # This function will handle score, history, synergies
			if rolls_left <= 0:
				print("Out of rolls. Transitioning to ROUND_SUMMARY.")
				current_game_state = GameState.ROUND_SUMMARY
				# _setup_round_summary_ui() # Call function to prepare summary UI
			else:
				current_game_state = GameState.PLAYING # More rolls left, continue playing
		GameState.LOOT_SELECTION:
			# Logic for this state will likely be handled by a separate loot screen scene.
			# Game.gd might wait for a signal from the loot screen.
			pass

		GameState.ROUND_SUMMARY:
			# This state is entered when rolls_left hits 0
			# It decides whether to go to LOOT (win) or GAME_OVER (loss)
			if current_round_score >= target_score:
				print("Round won! Score:", current_round_score, "Target:", target_score)
				# DO NOT increment level or change to INITIALIZING_ROUND here yet.
				# Instead, change state to LOOT_SELECTION and let that state handle showing the UI.
				current_game_state = GameState.LOOT_SELECTION
				_prepare_and_show_loot_screen() # Call the function to setup and show the loot UI
			else:
				print("Round lost. Score:", current_round_score, "Target:", target_score)
				current_game_state = GameState.GAME_OVER
				# _setup_game_over_ui() # We'll make this UI later
		GameState.GAME_OVER:
			# For now, just print and allow restart (will build UI later)
			# print("GAME OVER! Final Score:", total_accumulated_score, "Reached Level:", current_level)
			# Allow restart via a key press for testing
			if Input.is_action_just_pressed("confirm_action"): # e.g. Enter key
				current_game_state = GameState.INITIALIZING_GAME
	
	_update_all_ui_elements() # Keep UI updated every frame

func _initialize_new_game_session():
	print("Initializing new game session...")
	current_level = 1
	total_accumulated_score = 0
	current_player_die.clear() # Clear the die only at the start of a completely new game

	if GlyphDB and not GlyphDB.starting_die_configuration.is_empty():
		current_player_die = GlyphDB.starting_die_configuration.duplicate(true) # Deep copy
		print("Player die initialized with starting configuration: ", current_player_die.size(), " faces.")
	else:
		printerr("Game Error: GlyphDB not ready or starting_die_configuration is empty for new game!")
		# Fallback: create some basic glyphs programmatically if needed, or handle error robustly
		# For now, this would be a critical error.
	
	# The first round setup will be handled by INITIALIZING_ROUND state next.

func _initialize_current_round_setup():
	print("Initializing round setup for level: ", current_level)
	current_round_score = 0
	# Target score scaling
	target_score = BASE_TARGET_SCORE + (current_level - 1) * TARGET_SCORE_PER_LEVEL_INCREASE
	# Rolls per round scaling
	rolls_left = STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS)
	
	roll_history.clear()
	synergies_fired_this_round.clear()
	last_rolled_glyph = null # Clear the display of the last rolled glyph
	
	print("Round ", current_level, " initialized. Target: ", target_score, ". Rolls: ", rolls_left)

func _update_all_ui_elements():
	# Check if node is valid before trying to access its properties
	if is_instance_valid(score_label): score_label.text = "Score: " + str(current_round_score)
	if is_instance_valid(target_label): target_label.text = "Target: " + str(target_score)
	if is_instance_valid(rolls_label): rolls_label.text = "Rolls: " + str(rolls_left) + "/" + str(STARTING_ROLLS + int((current_level - 1) / ROLLS_INCREASE_EVERY_X_LEVELS)) # Show max rolls too
	if is_instance_valid(level_label): level_label.text = "Level: " + str(current_level)
	
	if is_instance_valid(last_roll_display):
		if is_instance_valid(last_rolled_glyph) and last_rolled_glyph.texture:
			last_roll_display.texture = last_rolled_glyph.texture
		else:
			last_roll_display.texture = null # Clear texture if no valid last roll

	# Update die face display container (actual visual update logic will be a separate function)
	# _update_player_die_visual_display() 

	if is_instance_valid(roll_button):
		roll_button.disabled = not (current_game_state == GameState.PLAYING and rolls_left > 0)
	
	if is_instance_valid(synergy_notification_label):
		# Logic to show/hide/fade synergy messages will go here or in a dedicated function
		pass


func _on_roll_button_pressed():
	if current_game_state == GameState.PLAYING and rolls_left > 0:
		print("Roll button pressed.")
		current_game_state = GameState.ROLL_ANIMATION # Transition to animation state
	else:
		print("Cannot roll. State:", GameState.keys()[current_game_state], "Rolls left:", rolls_left)

func _process_the_finished_roll_outcome():
	if current_player_die.is_empty():
		printerr("Cannot process roll: Player die is empty!")
		current_game_state = GameState.PLAYING # Or some error state
		return

	var rolled_glyph_index = randi() % current_player_die.size()
	last_rolled_glyph = current_player_die[rolled_glyph_index]

	if not is_instance_valid(last_rolled_glyph):
		printerr("Rolled glyph is not valid!")
		# Potentially pick another or handle error
		current_game_state = GameState.PLAYING 
		return

	print("Rolled: '", last_rolled_glyph.display_name, "' (Type: ", last_rolled_glyph.type, ", Value: ", str(last_rolled_glyph.value), ")")
	
	# Apply score
	current_round_score += last_rolled_glyph.value
	total_accumulated_score += last_rolled_glyph.value 
	
	# Add to history for synergies
	roll_history.append(last_rolled_glyph)
	_check_and_apply_synergies()
	
	rolls_left -= 1
	print("Roll processed. Score: ", current_round_score, ". Rolls left: ", rolls_left)
	# The next state (PLAYING or ROUND_SUMMARY) will be determined by _process based on rolls_left


# --- Functions to be implemented/expanded later ---

func add_glyph_to_player_die(glyph_data: GlyphData):
	if glyph_data and glyph_data is GlyphData:
		current_player_die.append(glyph_data)
		print("Added glyph '", glyph_data.display_name, "' to player die. Total faces: ", current_player_die.size())
		# _update_player_die_visual_display() # Refresh UI showing die faces
	else:
		printerr("Attempted to add invalid glyph data to die.")

func display_synergy_activation_message(message: String, points: int):
	if is_instance_valid(synergy_notification_label):
		synergy_notification_label.text = message + " +" + str(points) + "!"
		# Create a timer to clear the message after a few seconds
		var clear_timer = get_tree().create_timer(2.5) # Display for 2.5 seconds
		clear_timer.timeout.connect(func(): 
			if is_instance_valid(synergy_notification_label): 
				synergy_notification_label.text = ""
		)
	sfx(5) # Placeholder for synergy sound - ensure you have SFX set up for this ID

# Placeholder for SFX, replace with actual AudioStreamPlayer calls
func sfx(sfx_id: int):
	print("SFX Player: Playing sound id ", sfx_id) 
	# Example: $AudioStreamPlayerSFX.stream = load("res://assets/sfx/sound_" + str(sfx_id) + ".wav")
	#          $AudioStreamPlayerSFX.play()

func _prepare_and_show_loot_screen():
	print("Preparing loot screen...")
	if not is_instance_valid(loot_screen_instance):
		printerr("Loot screen instance is not valid! Skipping loot.")
		# Fallback: If loot screen somehow fails, still progress
		_on_loot_screen_closed() # Call the function that handles skipping loot
		return

	# Get loot options from GlyphDB
	# Exclude faces already on the player's die to offer variety (optional)
	var loot_options = GlyphDB.get_random_loot_options(3, current_player_die) 
	
	if loot_options.is_empty():
		print("No loot options available (all unique glyphs might be owned or defined). Skipping loot.")
		_on_loot_screen_closed() # Treat as if loot was skipped
		return

	loot_screen_instance.display_loot_options(loot_options)
	# LootScreen shows itself. Game.gd effectively pauses here by being in LOOT_SELECTION state.

func _on_loot_selected(chosen_glyph: GlyphData):
	print("Game: Loot selected - ", chosen_glyph.display_name)
	add_glyph_to_player_die(chosen_glyph)
	
	current_level += 1 # Level up after successful loot selection
	total_accumulated_score += 50 # Bonus points for completing round and getting loot
	
	current_game_state = GameState.INITIALIZING_ROUND # Proceed to next round
	# LootScreen hides itself

func _on_loot_screen_closed():
	# Called if loot screen is closed without a selection (e.g., by pressing cancel)
	# Or if no loot options were available.
	print("Game: Loot screen closed, proceeding to next round without new glyph.")
	current_level += 1 # Still level up for winning the round
	current_game_state = GameState.INITIALIZING_ROUND
# res://scripts/Game.gd
# ... (other functions) ...

func _check_and_apply_synergies():
	if roll_history.is_empty():
		return # No history, no synergies

	var total_synergy_bonus: int = 0
	var synergy_message: String = "" # To build a combined message if multiple trigger

	# --- Synergy 1: Numeric Double (two "dice" type faces with the same value) ---
	if not synergies_fired_this_round.has("numeric_double"):
		var dice_values_seen: Dictionary = {} # Store {value: count}
		for roll_data in roll_history:
			if roll_data.type == "dice":
				if not dice_values_seen.has(roll_data.value):
					dice_values_seen[roll_data.value] = 1
				else:
					dice_values_seen[roll_data.value] += 1
				
				if dice_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 5
					synergies_fired_this_round["numeric_double"] = true
					synergy_message += "NUMERIC DOUBLE! +5\n"
					sfx(10) # Placeholder SFX ID for this synergy
					print("Synergy: Numeric Double triggered!")
					break # Trigger once per round for this synergy

	# --- Synergy 2: Roman Gathering (at least two "roman" type faces) ---
	if not synergies_fired_this_round.has("roman_gathering"):
		var roman_glyph_count: int = 0
		for roll_data in roll_history:
			if roll_data.type == "roman":
				roman_glyph_count += 1
		
		if roman_glyph_count >= 2:
			total_synergy_bonus += 10
			synergies_fired_this_round["roman_gathering"] = true
			synergy_message += "ROMAN GATHERING! +10\n"
			sfx(11) # Placeholder SFX ID
			print("Synergy: Roman Gathering triggered!")

	# --- Synergy 3: Card Pair (two "cards" type faces with the same value) ---
	# Note: This assumes your "card" glyphs have their point value in `glyph.value`
	if not synergies_fired_this_round.has("card_pair"):
		var card_values_seen: Dictionary = {} # Store {value: count}
		for roll_data in roll_history:
			if roll_data.type == "card": # Assuming type is "card"
				if not card_values_seen.has(roll_data.value):
					card_values_seen[roll_data.value] = 1
				else:
					card_values_seen[roll_data.value] += 1

				if card_values_seen[roll_data.value] >= 2:
					total_synergy_bonus += 8 # Example bonus
					synergies_fired_this_round["card_pair"] = true
					synergy_message += "CARD PAIR! +8\n"
					sfx(12) # Placeholder SFX ID
					print("Synergy: Card Pair triggered!")
					break # Trigger once

	# --- Apply Bonuses and Display Message ---
	if total_synergy_bonus > 0:
		current_round_score += total_synergy_bonus
		total_accumulated_score += total_synergy_bonus # Also add to overall score
		print("Total synergy bonus this roll: ", total_synergy_bonus)
		display_synergy_activation_message_custom(synergy_message.strip_edges()) # Use custom display

	# Update UI immediately after potential score change
	_update_all_ui_elements()


# Modify or create this function to handle potentially multi-line synergy messages
func display_synergy_activation_message_custom(full_message: String):
	if is_instance_valid(synergy_notification_label) and not full_message.is_empty():
		synergy_notification_label.text = full_message
		# Autowrap for label if message is long (enable in Inspector for the Label node)
		# Inspector > Control > Text > Autowrap Mode: Word (or similar)
		
		var clear_timer = get_tree().create_timer(3.0) # Display for 3 seconds
		clear_timer.timeout.connect(func(): 
			if is_instance_valid(synergy_notification_label): 
				synergy_notification_label.text = ""
		)
	# The sfx() calls are now inside each synergy block.
