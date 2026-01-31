# TTS MTG Booster Creator - AI Coding Assistant Guide

## Project Overview
This is a **Tabletop Simulator (TTS) mod** that generates Magic: The Gathering booster packs dynamically by fetching card data from Scryfall and spawning physical card objects in-game. The project bridges Python data processing with Lua scripting for TTS.

## Architecture

### Two-Language System
- **Python (`booster_splitter.py`)**: Downloads and preprocesses booster pack probability data from [taw/magic-sealed-data](https://github.com/taw/magic-sealed-data)
- **Lua (`loader.lua`)**: Main TTS script that loads booster definitions, queries Scryfall API, and spawns 3D card objects in the game

### Key Data Flow
1. Python fetches `sealed_basic_data.json` from upstream repo → splits into individual `booster/*.json` files → generates `booster_index.json`
2. Lua script loads booster index on startup → user selects pack type → weighted random selection generates pack contents → Scryfall API queries fetch card images → TTS spawns cards as 3D objects

### Critical Files
- **[loader.lua](../loader.lua)**: 1343-line main script. Uses `#include json_parser` preprocessor directive (see below)
- **[json_parser.lua](../json_parser.lua)**: Custom JSON parser (TTS's native parser causes crashes on large objects)
- **[booster_splitter.py](../booster_splitter.py)**: Data pipeline script. Adds `sheet_order` field to preserve card slot ordering
- **[ui.xml](../ui.xml)**: TTS UI definition for pack selector, language options, foil toggles
- **[booster_index.json](../booster_index.json)**: Master list of 500+ booster types (name/code mappings)
- **booster/*.json**: Individual pack definitions with weighted sheets and card probabilities

## Development Workflow

### TTS Script Development
**Critical**: The VS Code TTS Lua extension has a known bug. Fix by editing:
```
%HOME%\.vscode\extensions\rolandostar.tabletopsimulator-lua-1.1.3\dist\extension.js
```
Change line 9406 from `node_modules.asar` to `node_modules`

### `#include` Directive
The `#include json_parser` at the top of [loader.lua](../loader.lua#L1) is **NOT standard Lua**. This is:
- A TTS-specific preprocessor directive
- Must be manually inlined when saving to TTS if not using the VS Code plugin
- The plugin handles this automatically

### Testing Changes
1. Load mod in Tabletop Simulator
2. Use [VS Code TTS Lua extension](https://marketplace.visualstudio.com/items?itemName=rolandostar.tabletopsimulator-lua) for live editing
3. Replace script contents via plugin interface
4. Test pack generation in-game

### Python Data Updates
```powershell
python booster_splitter.py  # Regenerates booster files from upstream
```
This overwrites `booster/*.json` and `booster_index.json` with latest pack definitions.

## Project Conventions

### Lua Patterns
- **Global state**: Variables like `lock`, `playerColor`, `advanced` track UI/generation state
- **Async handling**: Heavy use of `Wait.condition()` for Scryfall API calls (example: [loader.lua](../loader.lua#L808-L812))
- **Coroutines**: Pack generation uses `startLuaCoroutine(self, "generatePacks")` to avoid blocking
- **Custom JSON**: Always use `json.encode()/json.decode()` from `json_parser.lua`, never TTS's built-in JSON

### Scryfall Integration
- **Base URLs**: Defined as constants at top of [loader.lua](../loader.lua#L3-L9)
- **Card ID format**: Uses `set:collector_number` notation (e.g., `"afr:262"`)
- **Image caching**: `pickImageURI()` function adds cache-busting params when `blowCache` enabled
- **Language handling**: Maps user input via `LANGUAGES` table, queries Scryfall with lang codes
- **Required headers**: All Scryfall API requests include `User-Agent: TTSMTGBoosterCreator/1.0` and `Accept: application/json` headers per [Scryfall API requirements](https://scryfall.com/docs/api)

### Booster Pack Format
Example structure from [afr-draft.json](../booster/afr-draft.json):
```json
{
  "code": "afr-draft",
  "boosters": [{"sheets": {...}, "weight": 2, "sheet_order": ["basic", "common", ...]}],
  "sheets": {"basic": {"cards": {"afr:262": 1, ...}, "total_weight": 20}, ...}
}
```
- **`sheet_order`**: Added by Python script to preserve slot ordering in packs
- **`balance_colors`**: Sheet property for color distribution (used in limited formats)
- **Weighted selection**: `pickWeighted()` and `pickCard()` functions handle probability

### UI State Management
- Advanced panel toggle via [ui.xml](../ui.xml#L6) shows/hides options
- Settings persist in global vars: `enableFoil`, `pngGraphics`, `spawnEverythingFaceDown`, `forceLanguage`
- Card back/language inputs use `onEndEdit` callbacks

## Common Tasks

### Adding New Pack Types
1. Update upstream `magic-sealed-data` repo (external)
2. Run `python booster_splitter.py` to fetch changes
3. New packs automatically appear in dropdown (loaded from `booster_index.json`)

### Modifying Card Spawn Behavior
- **Position**: Edit `MAINDECK_POSITION_OFFSET` and `TOKENS_POSITION_OFFSET` constants
- **Spacing**: Adjust `POSITION_SPACING` for pack separation
- **Foil effects**: Modify `jsonForCardFace()` Lua decal code at [loader.lua](../loader.lua#L187-L207)

### Debugging Scryfall Queries
Check `handleCardResponse()` function ([loader.lua](../loader.lua#L615)) for error handling. Enable `blowCache = true` to bypass image caching during testing.

## External Dependencies
- **Scryfall API**: No auth required, rate-limited (~10 req/sec)
- **GitHub raw URLs**: Used for booster data (`BASE_BOOSTER_FILE_URL`)
- **Steam CDN**: Hosts booster bag graphics (`BOOSTER_IMAGE_URL`, `FOIL_EFFECT_URL`)

## Gotchas
- TTS's native `JSON.decode()` **crashes** on large objects → always use custom parser
- Pack generation is async → changes to spawn logic must account for `Wait.condition()` timing
- The `#include` directive won't work outside TTS context (breaks standard Lua linters)
- Set codes in booster JSONs don't always match Scryfall set codes (handle case-by-case)
