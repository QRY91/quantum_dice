# Quantum Dice: A Dice-Builder Roguelike

## Overview

Quantum Dice is a roguelike game where players build and customize their dice with unique glyphs, some of which exhibit quantum phenomena like superposition and entanglement. The core gameplay revolves around rolling these dice to achieve target scores, earning powerful boons and new glyphs as loot, and progressing through increasingly challenging rounds and boss encounters.

## How to Play

1.  **Objective:** Score enough points each round to meet the target score.
2.  **Rolling:** Click the large central dice button to roll your dice. The outcome is determined by the glyphs on your current dice set.
3.  **Scoring:** Each glyph has a base value. Synergies between glyphs on your history track, special cornerstone slot effects, and active boons can significantly increase your score.
4.  **Superposition:** Some glyphs are in a "superposition" and will collapse into one of several potential outcomes when rolled.
5.  **Entanglement:** Certain glyph pairs (like Photon Twins) are "entangled." Rolling one while its partner is on your dice can trigger bonus effects, like adding the partner's score.
6.  **Rune Boons:** Collecting specific sequences of Rune glyphs on your history track can activate powerful, run-long "boons" that provide passive benefits.
7.  **Loot & Progression:** Successfully completing a round allows you to choose new glyphs to add to your dice, making your future rolls more potent or versatile.
8.  **Rounds:** Progress through rounds with increasing target scores and limited rolls. Face boss encounters at key progression points.
9.  **In-Game Menu:** Press `Escape` or the gear icon to pause the game, access settings (audio, visual palettes), retry the run, or quit to the main menu.

## Core Gameplay Loop

1.  **Start Round:** `ProgressionManager` sets the target score and max rolls.
2.  **Player Rolls:**
    *   Player initiates a roll via the UI.
    *   `Game.gd` triggers `RollAnimationController` for visuals.
    *   `PlayerDiceManager` provides an initial glyph (could be superposition).
    *   If superposition, `GlyphData` resolves it to a final glyph.
    *   `RollAnimationController` shows the sequence, including collapse if any.
3.  **Score & Evaluate:**
    *   `Game.gd` calculates score based on the resolved glyph, checks for synergies, cornerstone bonuses, and applies effects from `BoonManager`.
    *   `ScoreManager` updates round and total scores.
    *   `HUD.gd` displays score changes and fanfares.
4.  **History & Effects:** The resolved glyph is added to a visual history track on the `HUD`. This track is used for synergy and boon activation.
5.  **Round End:**
    *   If rolls are exhausted or target score is met, `Game.gd` ends the round.
    *   **Win:** `ProgressionManager` processes the win, and `Game.gd` transitions to `LOOT_SELECTION` (player gets new glyphs from `GlyphDB` via `SceneUIManager`).
    *   **Loss:** `Game.gd` transitions to `GAME_OVER` (via `SceneUIManager`).
6.  **New Round:** If the player won and selected loot, a new round begins with updated parameters.

## High-Level Project Structure

The game is built in Godot Engine using GDScript.

*   **`Game.gd`:** The central orchestrator of the game loop, state management, and interaction between various systems.
*   **Manager Singletons (Autoloads):**
    *   **`PlayerDiceManager.gd`:** Manages the player's current set of dice faces (GlyphData).
    *   **`GlyphDB.gd`:** Database for all `GlyphData` resources; handles loading and providing glyphs for starting dice and loot.
    *   **`ProgressionManager.gd`:** Controls round structure, difficulty scaling, game phases, and boss encounters.
    *   **`ScoreManager.gd`:** Tracks current round score, total run score, and high scores.
    *   **`BoonManager.gd`:** Manages activation and effects of run-long boons from rune combinations.
    *   **`SceneUIManager.gd`:** Manages the display and transitions of full-screen UI panels (MainMenu, LootScreen, GameOverScreen).
    *   **`AudioManager.gd`:** Handles music and sound effects.
    *   **`PaletteManager.gd`:** Manages color palettes for UI theming.
*   **Key Scenes & Scripts:**
    *   **`GlyphData.gd` (Resource):** Defines the properties of each individual glyph.
    *   **`HUD.tscn` / `HUD.gd`:** The main in-game interface, displaying scores, roll history, inventory, etc. It contains `TrackManager.gd` for the visual roll history.
    *   **`RollAnimationController.tscn` / `RollAnimationController.gd`:** Manages the visual animation sequence of a dice roll, including superposition collapse.
    *   **UI Scenes (`scenes/ui/`):** Contain various menus like `MainMenu`, `InGameMenu`, `SettingsMenu`, `LootScreen`, etc.

## Future Development

This project is designed with modularity in mind, allowing for:
*   Easy addition of new Glyphs (dice faces, runes, superposition types, entangled pairs).
*   Expansion of Boon types and activation conditions.
*   Introduction of new game mechanics and progression milestones.
*   Further development of quantum-themed interactions. 