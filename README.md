# tts-mtg-booster-creator
Tabletop Simulator script to create MTG booster packs

## Tools and Links
* Card fetching based on https://github.com/omstrumpf/tts-mtg-importer
* Booster pack odds based on https://github.com/taw/magic-sealed-data

## Features
* Generates MTG booster from magics history into Tabletop Simulator
* Grabs related tokens

## Workshop Mod
Mod available on [steam workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3522241980).

## Contributing
Load up the mod in tabletop simulator, and replace the existing script with your changes.

I recommend using [this vs-code plugin](https://marketplace.visualstudio.com/items?itemName=rolandostar.tabletopsimulator-lua) that interfaces directly with the game - it makes script editing much more usable. 
Theres error with the current version of vs-code and the plugin to fix it edit:
```%HOME%\.vscode\extensions\rolandostar.tabletopsimulator-lua-1.1.3\dist\extension.js and on line 9406, change node_modules.asar to node_modules.```

Some shenanigans are required to get the #import statement to work properly - or, if you're lazy, simply inline `json_parser.lua` manually when saving to TTS.
