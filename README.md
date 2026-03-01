# The Purge: Suburban Survival

A co-op survival game for Roblox built with Luau and [Rojo](https://rojo.space/).

## Overview

Players spawn in a run-down suburban house and must scavenge the neighborhood for materials, food, and fuel to fortify their home, feed themselves, and keep their electricity running. Every few in-game days, a Purge night hits where waves of enemies assault the player's home. If the electricity goes out at any time, the same Purge enemies attack immediately.

**Goal:** Survive as many Purge nights as possible.

## Features

- **1-5 player co-op** with lobby matchmaking
- **3-zone neighborhood map** with escalating risk/reward
- **House fortification system** with tiered materials
- **Generator/electricity system** — power goes out = instant Purge attack
- **Hunger & cooking system** with recipes, buffs, and food spoilage
- **Purge nights** with scaling difficulty, enemy AI, and wave-based combat
- **Wildlife hunting** and fishing
- **Cosmetics-only monetization** (no pay-to-win)

## Project Structure

```
src/
├── shared/Modules/          # Shared configuration and data
│   ├── Config.lua           # All tunable game constants
│   ├── Enums.lua            # Game enumerations
│   ├── ItemDatabase.lua     # Complete item database (100+ items)
│   ├── RecipeDatabase.lua   # Cooking recipes
│   └── Utils.lua            # Utility functions
├── server/Services/         # Server-authoritative game logic
│   ├── GameManager.server.lua        # Core game loop, day/night, phases
│   ├── InventoryService.server.lua   # Player inventory management
│   ├── LootService.server.lua        # Loot spawning and respawning
│   ├── FortificationService.server.lua # House upgrade system
│   ├── ElectricityService.server.lua # Generator and power management
│   ├── PurgeService.server.lua       # Purge waves, enemy AI, scaling
│   ├── CookingService.server.lua     # Recipe cooking and stations
│   ├── CombatService.server.lua      # Melee/ranged combat
│   ├── NPCService.server.lua         # House defenders and wildlife
│   ├── LobbyService.server.lua       # Matchmaking and lobby
│   ├── DataService.server.lua        # DataStore persistence
│   ├── MonetizationService.server.lua # Shop, passes, cosmetics
│   └── MapBuilder.server.lua         # Procedural map generation
└── client/Controllers/      # Client-side UI and input
    ├── UIController.client.lua        # HUD (health, hunger, power, etc.)
    ├── InputController.client.lua     # Keybinds, sprint, combat input
    ├── AtmosphereController.client.lua # Audio, visuals, camera effects
    ├── InteractionController.client.lua # Proximity prompts, cooking UI
    └── LobbyUI.client.lua            # Lobby screen
```

## Setup

1. Install [Rojo](https://rojo.space/) (VS Code extension + CLI)
2. Clone this repository
3. Run `rojo serve` in the project root
4. Connect from Roblox Studio using the Rojo plugin
5. The game will sync all scripts into the correct services

## Technical Architecture

- **Server-authoritative** — all game logic runs on the server to prevent exploits
- **RemoteEvents/RemoteFunctions** for client-server communication
- **CollectionService tags** for categorizing interactable objects
- **PathfindingService** for NPC navigation
- **DataStoreService** for persistent player data
- **Modular design** — each system is independent and communicates via BindableEvents

## Game Modes

- **Endless** — survive as long as possible (leaderboard)
- **Survive X** — win after surviving a set number of Purges
- **Escape** — reach extraction point during a final Purge night
