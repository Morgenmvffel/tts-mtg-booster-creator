#include json_parser

------ CONSTANTS
SCRYFALL_ID_BASE_URL = "https://api.scryfall.com/cards/"
SCRYFALL_MULTIVERSE_BASE_URL = "https://api.scryfall.com/cards/multiverse/"
SCRYFALL_SET_NUM_BASE_URL = "https://api.scryfall.com/cards/"
SCRYFALL_SEARCH_BASE_URL = "https://api.scryfall.com/cards/search/?q="
SCRYFALL_NAME_BASE_URL = "https://api.scryfall.com/cards/named/?exact="
SCRYFALL_COLLECTION_URL = "https://api.scryfall.com/cards/collection"

PACK_ODDS_URL = "https://raw.githubusercontent.com/taw/magic-sealed-data/refs/heads/master/sealed_basic_data.json"
BOOSTER_INDEX_URL =
"https://raw.githubusercontent.com/Morgenmvffel/tts-mtg-booster-creator/refs/heads/master/booster_index.json"
BASE_BOOSTER_FILE_URL =
"https://raw.githubusercontent.com/Morgenmvffel/tts-mtg-booster-creator/refs/heads/master/booster"

BOOSTER_IMAGE_URL =
"https://steamusercontent-a.akamaihd.net/ugc/12048320118311789698/728EE5247F5FE466F92DAAC0E9997225CD3E8865/"
FOIL_EFFECT_URL =
"https://steamusercontent-a.akamaihd.net/ugc/18215652933654632959/A843EB4C96D1CE5E339D66F48A414D671B2CB4CC/"

MAINDECK_POSITION_OFFSET = { 1.89, 0.2, -0.04 }
TOKENS_POSITION_OFFSET = { 1.8, 0.2, 1 }

POSITION_SPACING = -0.756

DEFAULT_CARDBACK =
"https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg?version=0ddc8d41c3b69c2c3c4bb5d72669ffd7"
DEFAULT_LANGUAGE = "en"

-- Pack Amounts
MAX_PACK_AMOUNT = 6
MIN_PACK_AMOUNT = 1

-- API Rate Limiting and Timeouts
RATE_LIMIT_DELAY = 0.1  -- seconds between API requests (10 req/sec)
MAX_RETRY_ATTEMPTS = 5
RETRY_BACKOFF_BASE = 2  -- seconds for first retry (doubles each time)
RETRY_BACKOFF_MAX = 10  -- maximum seconds to wait
QUERY_TIMEOUT = 30      -- seconds before individual query times out
FETCH_TIMEOUT = 60      -- seconds before batch fetch times out
LOAD_TIMEOUT = 120      -- seconds before full load times out
TOKEN_RETRY_DELAY = 2   -- seconds to wait before retrying token fetch
COLLECTION_BATCH_SIZE = 75  -- Scryfall collection API limit

LANGUAGES = {
    ["en"] = "en",
    ["es"] = "es",
    ["sp"] = "sp",
    ["fr"] = "fr",
    ["de"] = "de",
    ["it"] = "it",
    ["pt"] = "pt",
    ["ja"] = "ja",
    ["jp"] = "ja",
    ["ko"] = "ko",
    ["kr"] = "ko",
    ["ru"] = "ru",
    ["zcs"] = "zcs",
    ["cs"] = "zcs",
    ["zht"] = "zht",
    ["ph"] = "ph",
    ["english"] = "en",
    ["spanish"] = "es",
    ["french"] = "fr",
    ["german"] = "de",
    ["italian"] = "it",
    ["portugese"] = "pt",
    ["japanese"] = "ja",
    ["korean"] = "ko",
    ["russian"] = "ru",
    ["chinese"] = "zhs",
    ["simplified chinese"] = "zhs",
    ["traditional chinese"] = "zht",
    ["phyrexian"] = "ph"
}

------ UI IDs
UI_ADVANCED_PANEL = "MTGBoosterGeneratorAdvancedPanel88bc1c"
UI_CARD_BACK_INPUT = "MTGDeckLoaderCardBackInput"
UI_LANGUAGE_INPUT = "MTGDeckLoaderLanguageInput"
UI_FORCE_LANGUAGE_TOGGLE = "MTGDeckLoaderForceLanguageToggleID"

------ GLOBAL STATE
lock = false
playerColor = nil
advanced = false
cardBackInput = ""
languageInput = ""
forceLanguage = false
enableFoil = true
blowCache = false
pngGraphics = true
spawnEverythingFaceDown = false
filteredBoosters = nil  -- Will store filtered boosters for random selection, nil means all boosters
randomBoostersPerPack = true  -- When true, each pack gets a random booster
useRandomBoosterSelection = false  -- True when generation was started from the Random button
useRandomSeed = true
currentSeed = nil
lastGenerationSeed = nil
seedInput = ""

-- Booster search/filter state
boosterSearchFilter = ""  -- current search text for dropdown filter

-- Booster filter options
filterDraft = true
filterCollector = true
filterPlay = true
filterSet = false
filterArena = false
filterPrerelease = false
filterJumpstart = true
filterTheme = false
filterOther = false
filterVintage = true
filterSLD = false

------ UTILITY
local function trim(s)
    if not s then
        return ""
    end

    local n = s:find "%S"
    return n and s:match(".*%S", n) or ""
end

local function underline(s)
    if not s or string.len(s) == 0 then
        return ""
    end

    return s .. '\n' .. string.rep('-', string.len(s)) .. '\n'
end

local function shallowCopyTable(t)
    if type(t) == 'table' then
        local copy = {}
        for key, val in pairs(t) do
            copy[key] = val
        end

        return copy
    end

    return {}
end

local function printErr(s)
    printToColor(s, playerColor, {
        r = 1,
        g = 0,
        b = 0
    })
end

local function printInfo(s)
    printToColor(s, playerColor)
end

local function stringToBool(s)
    -- It is truly ridiculous that this needs to exist.
    return (string.lower(s) == "true")
end

local function notifyPlayer(color, msg, rgb)
    local resolvedColor = nil

    if type(color) == "string" and color ~= "" then
        resolvedColor = color
    elseif color ~= nil then
        local success, extractedColor = pcall(function()
            return color.color
        end)

        if success and type(extractedColor) == "string" and extractedColor ~= "" then
            resolvedColor = extractedColor
        end
    end

    if resolvedColor ~= nil then
        local success
        if rgb then
            success = pcall(function()
                printToColor(msg, resolvedColor, rgb)
            end)
        else
            success = pcall(function()
                printToColor(msg, resolvedColor)
            end)
        end

        if success then
            return
        end
    end

    print(msg)
end

local function normalizeSeedValue(seedValue)
    local value = seedValue

    if type(value) == "string" then
        value = trim(value)
        if string.len(value) == 0 then
            return nil, "Seed cannot be empty."
        end

        local numericValue = tonumber(value)
        if numericValue then
            value = numericValue
        else
            -- Deterministically hash text seeds to a valid randomseed integer.
            local hash = 0
            local HASH_MOD = 2147483647
            for i = 1, string.len(value) do
                hash = (hash * 131 + string.byte(value, i)) % HASH_MOD
            end

            if hash == 0 then
                hash = 1
            end

            return hash
        end
    end

    value = tonumber(value)
    if not value then
        return nil, "Seed must be text or a valid number."
    end

    value = math.floor(value)
    if value < 0 then
        value = math.abs(value)
    end

    -- LuaJIT truncates math.randomseed to 32 bits; clamp to 31-bit positive
    -- range so large timestamps and manual large numbers don't collide.
    local SEED_MAX = 2147483647
    value = value % SEED_MAX
    if value == 0 then value = 1 end

    return value
end

local function getSeedText(seedValue)
    if seedValue == nil then
        return "n/a"
    end

    return tostring(seedValue)
end

local function refreshSeedUI()
    pcall(function()
        self.UI.setAttribute("MTGSeedLastValue", "text", getSeedText(lastGenerationSeed))
        self.UI.setAttribute("MTGSeedInput", "text", seedInput)
        self.UI.setAttribute("MTGSeedInput", "interactable", tostring(not useRandomSeed))
    end)
end

local function setCurrentSeed(seedValue)
    local normalizedSeed, err = normalizeSeedValue(seedValue)
    if not normalizedSeed then
        return false, err
    end

    -- Always display the normalized seed so the shown value matches what
    -- was actually passed to math.randomseed (avoids overflow confusion).
    seedInput = tostring(normalizedSeed)
    currentSeed = normalizedSeed
    math.randomseed(normalizedSeed)
    refreshSeedUI()

    return true
end

local function randomizeSeed()
    local unixMsSeed = os.time() * 1000 + math.floor((Time.time % 1) * 1000)
    local timeSeed = unixMsSeed
    if timeSeed < 0 then
        timeSeed = math.abs(timeSeed)
    end

    if currentSeed ~= nil and timeSeed == currentSeed then
        timeSeed = timeSeed + 1
    end

    return setCurrentSeed(timeSeed)
end

local function prepareSeedForGeneration(playerColorForError)
    if useRandomSeed then
        local success, err = randomizeSeed()
        if not success then
            notifyPlayer(playerColorForError, "Failed to randomize seed: " .. tostring(err), { r = 1, g = 0, b = 0 })
            return false
        end
    else
        if currentSeed == nil then
            local success, err = setCurrentSeed(os.time())
            if not success then
                notifyPlayer(playerColorForError, "Failed to initialize seed: " .. tostring(err), { r = 1, g = 0, b = 0 })
                return false
            end
        else
            math.randomseed(currentSeed)
        end
    end

    lastGenerationSeed = currentSeed
    refreshSeedUI()

    return true
end

------ CARD SPAWNING
local function jsonForCardFace(face, position, rotationY, flipped, foil)
    local rotation = self.getRotation()

    local rotZ = rotation.z
    if flipped then
        rotZ = math.fmod(rotZ + 180, 360)
    end

    local json = {
        Name = "Card",
        Transform = {
            posX = position.x,
            posY = position.y,
            posZ = position.z,
            rotX = rotation.x,
            rotY = rotation.y + rotationY,
            rotZ = rotZ,
            scaleX = 1,
            scaleY = 1,
            scaleZ = 1
        },
        Nickname = face.name,
        Description = face.oracleText,
        Locked = false,
        Grid = true,
        Snap = true,
        IgnoreFoW = false,
        MeasureMovement = false,
        DragSelectable = true,
        Autoraise = true,
        Sticky = true,
        Tooltip = true,
        GridProjection = false,
        HideWhenFaceDown = true,
        Hands = true,
        CardID = 2440000,
        SidewaysCard = false,
        CustomDeck = {},
        LuaScript = "",
        LuaScriptState = ""
    }

    json.CustomDeck["24400"] = {
        FaceURL = face.imageURI,
        BackURL = getCardBack(),
        NumWidth = 1,
        NumHeight = 1,
        BackIsHidden = true,
        UniqueBack = false,
        Type = 0
    }

    if enableFoil and foil then
        json.LuaScript = [[

        decal = {
            name = "Foil",
            url = "https://steamusercontent-a.akamaihd.net/ugc/18215652933654632959/A843EB4C96D1CE5E339D66F48A414D671B2CB4CC/",
            position = Vector(0, 0.25, 0),
            rotation = Vector(90, 0, 0),
            scale = Vector(-2.14, -3.06, 1)
        }

        function onLoad(saved_data)
            if self.getDecals() == nil then
                self.addDecal(decal)
                -- log("added Decal")
            end
        end
    ]]
    end
    return json
end

-- Spawns the given card [faces] at [position].
-- Card will be face down if [flipped].
-- Calls [onFullySpawned] when the object is spawned.
local function spawnCard(faces, position, rotation, flipped, onFullySpawned)
    if not faces or not faces[1] then
        faces = { {
            name = card.name,
            oracleText = "Card not found",
            imageURI =
            "https://vignette.wikia.nocookie.net/yugioh/images/9/94/Back-Anime-2.png/revision/latest?cb=20110624090942"
        } }
    end

    -- Force flipped if the user asked for everything to be spawned face-down
    if spawnEverythingFaceDown then
        flipped = true
    end

    local jsonFace1 = jsonForCardFace(faces[1], position, rotation, flipped, false)

    if #faces > 1 then
        jsonFace1.States = {}
        for i = 2, (#(faces)) do
            local jsonFaceI = jsonForCardFace(faces[i], position, rotation, flipped, false)

            jsonFace1.States[tostring(i)] = jsonFaceI
        end
    end

    local cardObj = spawnObjectJSON({
        json = JSON.encode(jsonFace1)
    })

    onFullySpawned(cardObj)

    return cardObj
end

-- Spawns a deck named [name] containing the given [cards] at [position].
-- Deck will be face down if [flipped].
-- Calls [onFullySpawned] when the object is spawned.
local function spawnDeck(cards, name, position, rotation, flipped, onFullySpawned, onError)
    local cardObjects = {}

    local sem = 0
    local function incSem()
        sem = sem + 1
    end
    local function decSem()
        sem = sem - 1
    end

    for _, card in ipairs(cards) do
        for i = 1, (card.count or 1) do
            if not card.faces or not card.faces[1] then
                card.faces = { {
                    name = card.name,
                    oracleText = "Card not found",
                    imageURI =
                    "https://vignette.wikia.nocookie.net/yugioh/images/9/94/Back-Anime-2.png/revision/latest?cb=20110624090942"
                } }
            end

            incSem()
            spawnCard(card.faces, position, rotation, flipped, function(obj)
                table.insert(cardObjects, obj)
                decSem()
            end)
        end
    end

    Wait.condition(function()
        local deckObject

        if cardObjects[1] and cardObjects[2] then
            deckObject = cardObjects[1].putObject(cardObjects[2])
            if success and deckObject then
                deckObject.setPosition(position)
                deckObject.setName(name)
            else
                deckObject = cardObjects[1]
            end
        else
            deckObject = cardObjects[1]
        end

        onFullySpawned(deckObject)
    end, function()
        return (sem == 0)
    end, 5, function()
        onError("Error collating packs... timed out.")
    end)
end

local function sortCardsBySheetOrder(cards, sheetOrder)
    -- Create a mapping of sheet names to their index in sheetOrder
    local sheetIndex = {}
    for i, sheet in ipairs(sheetOrder) do
        sheetIndex[sheet] = i
    end

    -- Function to get the sheet index for sorting
    local function getCardSheetIndex(card)
        local sheet = (card.sheetName or ""):lower()

        -- If the sheet is in the sheetOrder, return its index, otherwise return a high index to place it at the end
        if sheetIndex[sheet] then
            return sheetIndex[sheet]
        else
            -- Log a message if the sheetName is not in the sheetOrder
            log("Warning: sheetName '" .. sheet .. "' not found in sheetOrder.")
            return #sheetOrder + 1 -- Place this card at the end if the sheet is not found in sheetOrder
        end
    end

    -- Sort cards based on their sheet order in reverse
    table.sort(cards, function(a, b)
        local indexA = getCardSheetIndex(a)
        local indexB = getCardSheetIndex(b)

        -- First, sort by reversed sheet order (descending index)
        if indexA ~= indexB then
            return indexA > indexB -- Reverse the order (descending index)
        end

        -- If they are from the same sheet, fallback to sorting alphabetically by sheetName (or use the collectorNum as a tie-breaker if needed)
        return a.collectorNum < b.collectorNum
    end)
end

local function spawnBagWithCards(cards, bagName, position, flipped, sheetOrder, onFullySpawned, onError)
    log("spawnBagWithCards: Creating bag '" .. bagName .. "' with " .. #cards .. " cards")
    -- Sort cards alphabetically by sheetName (fallback to name if missing)
    -- log(sheetOrder)
    sortCardsBySheetOrder(cards, sheetOrder)
    local containedObjects = {}
    local boosterName = ""

    for _, card in ipairs(cards) do
        for i = 1, (card.count or 1) do
            local faces = card.faces or { {
                name = card.name,
                oracleText = "Card not found",
                imageURI =
                "https://vignette.wikia.nocookie.net/yugioh/images/9/94/Back-Anime-2.png/revision/latest?cb=20110624090942"
            } }

            -- Build the card JSON with States for multiple faces
            local jsonFace1 = jsonForCardFace(faces[1], position, 0, flipped, card.foil)

            if #faces > 1 then
                jsonFace1.States = {}
                for j = 2, #faces do
                    local jsonFaceJ = jsonForCardFace(faces[j], position, 0, flipped, card.foil)
                    jsonFace1.States[tostring(j)] = jsonFaceJ
                end
            end

            table.insert(containedObjects, jsonFace1)
        end
        boosterName = card.packName
    end

    local bagJSON = {
        Name = "Custom_Model_Bag",
        Transform = {
            posX = position[1],
            posY = position[2],
            posZ = position[3],
            rotX = 0,
            rotY = 180,
            rotZ = 0,
            scaleX = 1,
            scaleY = 1,
            scaleZ = 1
        },
        Nickname = boosterName .. bagName,
        Description = "",
        ColorDiffuse = {
            r = 1,
            g = 1,
            b = 1
        },
        Locked = false,
        Grid = true,
        Snap = true,
        Autoraise = true,
        Sticky = true,
        Tooltip = true,
        MeshCollider = false,
        MaterialIndex = -1,
        MeshIndex = -1,
        CustomMesh = {
            MeshURL = "http://pastebin.com/raw/PqfGKtKR",
            DiffuseURL = BOOSTER_IMAGE_URL,
            NormalURL = "http://i.imgur.com/pEN77ux.png",
            Convex = true,
            MaterialIndex = 0,
            TypeIndex = 6,
            CastShadows = true,

            specular_intensity = 0.3, -- Moderate shine
            specular_color = {
                r = 0.95,
                g = 0.98,
                b = 1.0
            },                      -- Neutral white highlight
            specular_sharpness = 5, -- Clean but not razor-sharp
            fresnel_strength = 0.2
        },
        ContainedObjects = containedObjects,
        LuaScript = [[
            function onLoad()
                self.addContextMenuItem("Crack the Pack", unloadAllCards)
            end

            function unloadAllCards(player_color, position, object)
                local objects = self.getObjects()
                local basePos = self.positionToWorld({0, 0.5, 0})
                local yOffset = 0

                for i, obj in ipairs(objects) do
                    self.takeObject({
                        guid = obj.guid,
                        position = {basePos.x, basePos.y + yOffset, basePos.z},
                        smooth = false,
                        callback_function = function(takenObj)
                            takenObj.setRotationSmooth({0, 180, 0})
                        end
                    })
                    yOffset = yOffset + 0.2
                end

                Wait.time(checkEmptyAndDestroy, 0.5)
            end

            function onObjectLeaveContainer(container, leaving_object)
                if container == self then
                    Wait.time(checkEmptyAndDestroy, 0.2)
                end
            end

            function checkEmptyAndDestroy()
                if #self.getObjects() == 0 then
                    self.destruct()
                end
            end
        ]]
    }

    local bagObj = spawnObjectJSON({
        json = JSON.encode(bagJSON)
    })

    if bagObj then
        log("spawnBagWithCards: Successfully spawned bag '" .. bagName .. "'")
        onFullySpawned(bagObj)
    else
        log("spawnBagWithCards: FAILED to spawn bag '" .. bagName .. "'")
        if onError then
            onError("Failed to spawn custom bag")
        end
    end
end

------ SCRYFALL
local function stripScryfallImageURI(uri)
    if not uri or string.len(uri) == 0 then
        return ""
    end

    return uri:match("(.*)%?") or ""
end

local function pickImageURI(cardData, highres_image, image_status)
    if not cardData or not cardData.image_uris then
        return ""
    end

    local highres_image
    if highres_image == nil then
        highres_image = cardData.highres_image
    end

    local image_status
    if image_status == nil then
        image_status = cardData.image_status
    end

    local uri
    if pngGraphics and cardData.image_uris.png then
        uri = stripScryfallImageURI(cardData.image_uris.png)
    else
        uri = stripScryfallImageURI(cardData.image_uris.large)
    end

    local sep
    if uri:find("?") then
        sep = "&"
    else
        sep = "?"
    end

    if blowCache then
        local cachebuster = string.gsub(tostring(Time.time), "%.", "-")

        uri = uri .. sep .. "CACHEBUSTER_" .. cachebuster
    elseif (not highres_image) or image_status ~= "highres_scan" then
        uri = uri .. sep .. "LOWRES_CACHEBUSTER"
    end

    return uri
end

-- Returns a nicely formatted card name with type_line and cmc
local function getAugmentedName(cardData)
    local name = cardData.name:gsub('"', '') or ""

    if cardData.type_line then
        name = name .. '\n' .. cardData.type_line
    end

    if cardData.cmc then
        name = name .. '\n' .. cardData.cmc .. ' CMC'
    end

    return name
end

-- Returns a nicely formatted oracle text with power/toughness or loyalty
-- if present
local function getAugmentedOracleText(cardData)
    local oracleText = cardData.oracle_text:gsub('"', "'")

    if cardData.power and cardData.toughness then
        oracleText = oracleText .. '\n[b]' .. cardData.power .. '/' .. cardData.toughness .. '[/b]'
    elseif cardData.loyalty then
        oracleText = oracleText .. '\n[b]' .. tostring(cardData.loyalty) .. '[/b]'
    end

    return oracleText
end

-- Collects oracle text from multiple faces if present
local function collectOracleText(cardData)
    local oracleText = ""

    if cardData.card_faces then
        for i, face in ipairs(cardData.card_faces) do
            oracleText = oracleText .. underline(face.name) .. getAugmentedOracleText(face)

            if i < #cardData.card_faces then
                oracleText = oracleText .. '\n\n'
            end
        end
    else
        oracleText = getAugmentedOracleText(cardData)
    end

    return oracleText
end

local function parseCardData(cardID, data)
    local card = shallowCopyTable(cardID)

    card.name = getAugmentedName(data)
    card.oracleText = collectOracleText(data)
    card.faces = {}
    card.scryfallID = data.id
    card.oracleID = data.oracle_id
    card.language = data.lang
    card.setCode = data.set
    card.collectorNum = data.collector_number

    if data.layout == "transform" or data.layout == "art_series" or data.layout == "double_sided" or data.layout ==
        "modal_dfc" or data.layout == "double_faced_token" or data.layout == "reversible_card" then
        for i, face in ipairs(data.card_faces) do
            card.faces[i] = {
                imageURI = pickImageURI(face, data.highres_image, data.image_status),
                name = getAugmentedName(face),
                oracleText = card.oracleText
            }
        end
    else
        card.faces[1] = {
            imageURI = pickImageURI(data),
            name = card.name,
            oracleText = card.oracleText
        }
    end

    return card
end

-- Parses scryfall response data for a card.
-- Queries for tokens and associated cards.
-- onSuccess is called with a populated card table, and list of tokens.
local function handleCardResponse(cardID, data, onSuccess, onError)
    local sem = 0
    local function incSem()
        sem = sem + 1
    end
    local function decSem()
        sem = sem - 1
    end

    local tokens = {}
    local tokenDataForButtons = {}

    local function addToken(name, uri)
        incSem()

        local headers = {
            ["User-Agent"] = "TTSMTGBoosterCreator/1.0",
            ["Accept"] = "application/json;q=0.9,*/*;q=0.8"
        }

        WebRequest.custom(uri, "GET", true, "", headers, function(webReturn)
            if webReturn.is_error or webReturn.error or string.len(webReturn.text) == 0 then
                local errorMsg = webReturn.error or "unknown"
                
                -- Handle 429 rate limit with retry
                if errorMsg:match("429") then
                    log("Rate limited (429) for token, retrying in " .. TOKEN_RETRY_DELAY .. " seconds...")
                    Wait.time(function()
                        addToken(name, uri)
                    end, TOKEN_RETRY_DELAY)
                    -- Don't decrement semaphore here - the retry will handle it
                    return
                end
                
                log("Error fetching token: " .. errorMsg)
                decSem()
                return
            end

            local success, data = pcall(function()
                return jsondecode(webReturn.text)
            end)
            if not success or not data or data.object == "error" then
                log("Error fetching token: JSON Parse")
                decSem()
                return
            end

            local token = parseCardData({}, data)

            token.name = name

            table.insert(tokens, token)

            -- Store pared down token data for token buttons
            local front
            local back
            if token.faces[1] then
                front = token.faces[1].imageURI
            end
            if token.faces[2] then
                back = token.faces[2].imageURI
            else
                back = getCardBack()
            end

            table.insert(tokenDataForButtons, {
                name = token.name,
                oracleText = token.oracleText,
                front = front,
                back = back
            })

            decSem()
        end)
    end

    -- On normal cards, check for tokens or related effects (i.e. city's blessing)
    if data.all_parts and not (data.layout == "token" or data.type_line == "Card") then
        for _, part in ipairs(data.all_parts) do
            if part.component and (part.type_line == "Card" or part.component == "token") then
                addToken(part.name, part.uri)
                -- shorten name on emblems
            elseif part.component and
                (string.sub(part.type_line, 1, 6) == "Emblem" and not (string.sub(data.type_line, 1, 6) == "Emblem")) then
                addToken("Emblem", part.uri)
            end
        end
    end

    local card = parseCardData(cardID, data)

    -- Store token data on each face
    for _, face in ipairs(card.faces) do
        face.tokenData = tokenDataForButtons
    end

    Wait.condition(function()
        onSuccess(card, tokens)
    end, function()
        return (sem == 0)
    end, QUERY_TIMEOUT, function()
        onError("Error loading card data... timed out.")
    end)
end

-- Queries scryfall by the [cardID].
-- cardID must define at least one of scryfallID, multiverseID, or name.
-- if forceNameQuery is true, will query scryfall by card name ignoring other data.
-- if forceSetNumLangQuery is true, will query scryfall by set/num/lang ignoring other data.
-- onSuccess is called with a populated card table, and a table of associated tokens.
local function queryCard(cardID, forceStandardLanguage, onSuccess, onError, retryCount)
    retryCount = retryCount or 0
    
    -- Validate input
    if not cardID or not cardID.setCode or not cardID.collectorNum then
        local errMsg = "Invalid cardID: missing setCode or collectorNum"
        log(errMsg)
        onError(errMsg)
        return
    end
    
    if retryCount > MAX_RETRY_ATTEMPTS then
        log("Max retries exceeded for card: " .. cardID.setCode .. ":" .. cardID.collectorNum)
        onError("Max retries exceeded")
        return
    end
    
    local query_url

    local language_code = getLanguageCode()

    if forceStandardLanguage and string.len(cardID.setCode) > 0 and string.len(cardID.collectorNum) > 0 then
        query_url = SCRYFALL_SET_NUM_BASE_URL .. string.lower(cardID.setCode) .. "/" .. cardID.collectorNum
    elseif string.len(cardID.setCode) > 0 and string.len(cardID.collectorNum) > 0 then
        query_url = SCRYFALL_SET_NUM_BASE_URL ..
        string.lower(cardID.setCode) .. "/" .. cardID.collectorNum .. "/" .. language_code
    else
        local errMsg = "Empty setCode or collectorNum for card"
        log(errMsg)
        onError(errMsg)
        return
    end

    log("queryCard: " .. query_url)

    local headers = {
        ["User-Agent"] = "TTSMTGBoosterCreator/1.0",
        ["Accept"] = "application/json;q=0.9,*/*;q=0.8"
    }

    local webRequest = WebRequest.custom(query_url, "GET", true, "", headers, function(webReturn)
        if webReturn.is_error or webReturn.error then
            local errorMsg = webReturn.error or "unknown error"
            
            -- Handle 429 rate limit with exponential backoff
            if errorMsg:match("429") then
                local backoffTime = math.min(RETRY_BACKOFF_BASE * (2 ^ retryCount), RETRY_BACKOFF_MAX)
                log(string.format("[RATE-LIMIT] 429 for %s:%s - retry #%d in %.1fs", cardID.setCode, cardID.collectorNum, retryCount + 1, backoffTime))
                Wait.time(function()
                    queryCard(cardID, forceStandardLanguage, onSuccess, onError, retryCount + 1)
                end, backoffTime)
                return
            end
            
            log(string.format("[ERROR] WebRequest failed for %s:%s - %s", cardID.setCode, cardID.collectorNum, errorMsg))
            onError("Web request error: " .. errorMsg)
            return
        elseif string.len(webReturn.text) == 0 then
            log(string.format("[ERROR] Empty response for %s:%s", cardID.setCode, cardID.collectorNum))
            onError("empty response")
            return
        end

        local success, data = pcall(function() return jsondecode(webReturn.text) end)

        if not success then
            onError("failed to parse JSON response")
            return
        elseif not data then
            onError("empty JSON response")
            return
        elseif data.object == "error" then
            onError("failed to find card")
            return
        end

        -- Grab the first card if response is a list
        if data.object == "list" then
            if data.total_cards == 0 or not data.data or not data.data[1] then
                onError("failed to find card")
                return
            end

            data = data.data[1]
        end

        handleCardResponse(cardID, data, onSuccess, onError)
    end)
end

-- Queries multiple cards using Scryfall's Collection API (bulk endpoint)
-- Much faster than individual queries - batches up to 75 cards per request
local function queryCardCollection(cardIDs, onSuccess, onError, retryCount)
    retryCount = retryCount or 0
    
    if retryCount > MAX_RETRY_ATTEMPTS then
        log("[ERROR] Max retries exceeded for collection query")
        onError("Max retries exceeded")
        return
    end
    
    -- Build the identifiers array for the collection API
    local identifiers = {}
    for _, cardID in ipairs(cardIDs) do
        table.insert(identifiers, {
            set = string.lower(cardID.setCode),
            collector_number = cardID.collectorNum
        })
    end
    
    -- Create the request body
    local requestBody = jsonencode({
        identifiers = identifiers
    })
    
    log(string.format("queryCardCollection: Fetching %d cards in bulk", #cardIDs))
    
    local headers = {
        ["User-Agent"] = "TTSMTGBoosterCreator/1.0",
        ["Accept"] = "application/json;q=0.9,*/*;q=0.8",
        ["Content-Type"] = "application/json"
    }
    
    local webRequest = WebRequest.custom(SCRYFALL_COLLECTION_URL, "POST", true, requestBody, headers, function(webReturn)
        if webReturn.is_error or webReturn.error then
            local errorMsg = webReturn.error or "unknown error"
            
            -- Handle 429 rate limit with exponential backoff
            if errorMsg:match("429") then
                local backoffTime = math.min(RETRY_BACKOFF_BASE * (2 ^ retryCount), RETRY_BACKOFF_MAX)
                log(string.format("[RATE-LIMIT] 429 for collection query - retry #%d in %.1fs", retryCount + 1, backoffTime))
                Wait.time(function()
                    queryCardCollection(cardIDs, onSuccess, onError, retryCount + 1)
                end, backoffTime)
                return
            end
            
            log("[ERROR] Collection API request failed: " .. errorMsg)
            onError("Collection API error: " .. errorMsg)
            return
        elseif string.len(webReturn.text) == 0 then
            log("[ERROR] Empty response from collection API")
            onError("empty response")
            return
        end
        
        local success, data = pcall(function() return jsondecode(webReturn.text) end)
        
        if not success then
            onError("failed to parse JSON response")
            return
        elseif not data then
            onError("empty JSON response")
            return
        elseif data.object == "error" then
            onError("Collection API returned error: " .. (data.details or "unknown"))
            return
        end
        
        -- Process all returned cards
        if not data.data or #data.data == 0 then
            log("[WARNING] Collection API returned no cards")
            onSuccess({})
            return
        end
        
        -- Create a map of cards by set:collector_number for quick lookup
        local cardMap = {}
        for _, cardData in ipairs(data.data) do
            local key = string.lower(cardData.set) .. ":" .. cardData.collector_number
            cardMap[key] = cardData
        end
        
        -- Match returned cards to our cardIDs in order, handling missing cards
        local results = {}
        for _, cardID in ipairs(cardIDs) do
            local key = string.lower(cardID.setCode) .. ":" .. cardID.collectorNum
            local cardData = cardMap[key]
            
            if cardData then
                table.insert(results, {
                    cardID = cardID,
                    data = cardData
                })
            else
                log(string.format("[WARNING] Card not found in collection response: %s:%s", cardID.setCode, cardID.collectorNum))
                -- We'll need to query this one individually later
                table.insert(results, {
                    cardID = cardID,
                    data = nil
                })
            end
        end
        
        onSuccess(results)
    end)
end

-- Queries card data for all cards using bulk Collection API
local function fetchCardData(cards, onComplete, onError)
    log("fetchCardData: Starting bulk fetch for " .. #cards .. " cards")
    local sem = 0
    local function incSem() sem = sem + 1 end
    local function decSem() sem = sem - 1 end

    local cardData = {}
    local tokensData = {}

    local function cleanCollectorNum(collectorNum)
        return string.match(collectorNum, "%d+")
    end

    -- Split cards into batches of COLLECTION_BATCH_SIZE (75)
    local batches = {}
    for i = 1, #cards, COLLECTION_BATCH_SIZE do
        local batch = {}
        for j = i, math.min(i + COLLECTION_BATCH_SIZE - 1, #cards) do
            table.insert(batch, cards[j])
        end
        table.insert(batches, batch)
    end

    log(string.format("fetchCardData: Split into %d batches", #batches))

    -- Process each batch with a slight delay
    local batchDelay = 0
    for batchIndex, batch in ipairs(batches) do
        incSem()
        Wait.time(function()
            queryCardCollection(batch, function(results)
                -- Process results and handle cards that need individual queries
                local cardsNeedingRetry = {}
                
                for _, result in ipairs(results) do
                    if result.data then
                        -- Card found, process it
                        incSem()
                        handleCardResponse(result.cardID, result.data, function(card, tokens)
                            table.insert(cardData, card)
                            for _, token in ipairs(tokens) do
                                table.insert(tokensData, token)
                            end
                            decSem()
                        end, function(e)
                            log("[ERROR] Failed to process card from collection: " .. e)
                            decSem()
                        end)
                    else
                        -- Card not found in collection, need individual query
                        table.insert(cardsNeedingRetry, result.cardID)
                    end
                end

                -- Query missing cards individually
                for _, cardID in ipairs(cardsNeedingRetry) do
                    incSem()
                    
                    local function safeOnSuccess(card, tokens)
                        table.insert(cardData, card)
                        for _, token in ipairs(tokens) do
                            table.insert(tokensData, token)
                        end
                        decSem()
                    end
                    
                    local function safeOnError(e)
                        log("[ERROR] Individual query failed: " .. e)
                        decSem()
                    end
                    
                    -- Try with original collector number first (preserves 'a' suffix for DFCs)
                    log(string.format("[RETRY] Individual query for missing card: %s:%s", cardID.setCode, cardID.collectorNum))
                    
                    queryCard(cardID, false, safeOnSuccess, function(e)
                        -- Try again with cleaned collector number
                        log(string.format("[RETRY] Cleaning collector number for %s:%s", cardID.setCode, cardID.collectorNum))
                        local cleanedCardID = {
                            setCode = cardID.setCode,
                            collectorNum = cleanCollectorNum(cardID.collectorNum),
                            foil = cardID.foil,
                            packIndex = cardID.packIndex,
                            sheetName = cardID.sheetName,
                            packName = cardID.packName
                        }
                        
                        queryCard(cleanedCardID, false, safeOnSuccess, function(e)
                            -- Final fallback: standard language
                            log(string.format("[RETRY] Falling back to standard language for %s:%s", cleanedCardID.setCode, cleanedCardID.collectorNum))
                            queryCard(cleanedCardID, true, safeOnSuccess, safeOnError)
                        end)
                    end)
                end

                decSem()
            end, function(e)
                log("[ERROR] Batch collection query failed: " .. e)
                decSem()
            end)
        end, batchDelay)
        batchDelay = batchDelay + RATE_LIMIT_DELAY
    end

    Wait.condition(
        function()
            log("fetchCardData: Complete. Fetched " .. #cardData .. " cards and " .. #tokensData .. " tokens")
            onComplete(cardData, tokensData)
        end,
        function() return (sem == 0) end,
        FETCH_TIMEOUT,
        function()
            log("fetchCardData: TIMEOUT - sem = " .. sem .. ", fetched " .. #cardData .. " of " .. #cards .. " cards")
            onError("Error loading card images... timed out.")
        end
    )
end

-- Queries for the given card IDs, collates deck, and spawns objects.
local function loadDeck(packs, deckName, onComplete, onError)
    local tokensPosition = self.positionToWorld(TOKENS_POSITION_OFFSET)

    printInfo("Querying Scryfall for card data...")
    log("loadDeck: Processing " .. #packs .. " packs")

    local sem = #packs -- Semaphore for packs
    local function decSem()
        sem = sem - 1
        log("loadDeck: Pack complete. Remaining: " .. sem)
    end

    -- Table to collect all tokens
    local allTokens = {}

    -- Process packs sequentially to avoid overwhelming Scryfall API
    local currentPackIndex = 1
    
    local function processNextPack()
        if currentPackIndex > #packs then
            -- All packs processed, deduplicate and spawn tokens
            local uniqueTokens = {}
            local tokenKeys = {}
            for _, token in ipairs(allTokens) do
                local key = token.scryfallID or token.oracleID or token.name
                if not tokenKeys[key] then
                    tokenKeys[key] = true
                    table.insert(uniqueTokens, token)
                end
            end
            
            log("loadDeck: All packs processed. Spawning " .. #uniqueTokens .. " unique tokens (deduplicated from " .. #allTokens .. " total)")
            spawnDeck(uniqueTokens, deckName .. " - tokens", tokensPosition, 90, false, function()
                log("loadDeck: Tokens spawned successfully")
                onComplete()
            end
            , function(e)
                log("loadDeck: Token spawn error: " .. tostring(e))
                printErr(e)
                onComplete()
            end)
            return
        end
        
        local packIndex = currentPackIndex
        local pack = packs[packIndex]
        local cardIDsForPack = pack.cards
        log("loadDeck: Starting pack " .. packIndex .. " with " .. #cardIDsForPack .. " cards")
        
        currentPackIndex = currentPackIndex + 1

        fetchCardData(cardIDsForPack, function(cards, tokens)
            -- After fetching the data for this pack, we can spawn the cards for this pack
            -- printInfo("Spawning pack " .. packIndex)

            local relativeOffset = {
                MAINDECK_POSITION_OFFSET[1] + (packIndex - 1) * POSITION_SPACING,
                MAINDECK_POSITION_OFFSET[2],
                MAINDECK_POSITION_OFFSET[3]
            }
            local offset = self.positionToWorld(relativeOffset)

            -- Spawn cards for this pack
            log("loadDeck: Spawning bag for pack " .. packIndex .. " with " .. #cards .. " cards")
            spawnBagWithCards(cards, deckName .. " - Pack " .. packIndex, offset, false, pack.sheetOrder, function()
                log("loadDeck: Bag spawned successfully for pack " .. packIndex)
                decSem()
                
                -- Process next pack after this one completes
                processNextPack()
            end, function(e)
                printErr(e)
                decSem()
                
                -- Process next pack even on error
                processNextPack()
            end)

            -- Collect all tokens for later spawning
            for _, token in ipairs(tokens) do
                table.insert(allTokens, token)
            end
        end, function(e)
            -- Error callback for fetchCardData
            printErr("Failed to fetch card data for pack " .. packIndex .. ": " .. tostring(e))
            decSem()
            
            -- Process next pack even on error
            processNextPack()
        end)
    end
    
    -- Start processing first pack
    processNextPack()

    -- Spawn all tokens at once after all packs are processed
    -- (This Wait.condition is now just a safety net since processNextPack handles completion)
    Wait.condition(function()
        -- This should not normally be reached, but included as safety
        if sem == 0 and currentPackIndex > #packs then
            log("loadDeck: Safety check - ensuring completion")
        end
    end, function()
        return sem == 0 and currentPackIndex > #packs
    end, LOAD_TIMEOUT, function()
        log("loadDeck: TIMEOUT - sem = " .. sem .. ", processed " .. (currentPackIndex - 1) .. " of " .. #packs .. " packs")
        onError("Error spawning deck objects... timed out.")
    end)
end


local function pickWeighted(options)
    local totalWeight = 0
    for _, option in ipairs(options) do
        totalWeight = totalWeight + option.weight
    end

    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, option in ipairs(options) do
        cumulative = cumulative + option.weight
        if roll < cumulative then
            return option
        end
    end

    return options[#options] -- fallback
end

local function pickCard(cardList)
    local total = 0
    for _, entry in ipairs(cardList) do
        total = total + entry.weight
    end

    local r = math.random() * total
    local cumulative = 0
    for _, entry in ipairs(cardList) do
        cumulative = cumulative + entry.weight
        if r < cumulative then
            return entry.id
        end
    end

    return cardList[#cardList].id -- fallback
end

local function drawCardsFromSheet(sheetData, count)
    local selected = {}

    -- Handle fixed sheets: draw all cards as listed, with exact quantities
    if sheetData.fixed then
        for cardId, quantity in pairs(sheetData.cards) do
            for _ = 1, quantity do
                table.insert(selected, cardId)
            end
        end
        return selected
    end

    -- Cache the card list structure on the sheet data to avoid rebuilding
    if not sheetData._cardListCache then
        sheetData._cardListCache = {}
        for id, weight in pairs(sheetData.cards) do
            table.insert(sheetData._cardListCache, {
                id = id,
                weight = weight
            })
        end
    end

    local allowDuplicates = sheetData.allow_duplicates == true

    if allowDuplicates then
        -- Simple case: just pick randomly with replacement
        for _ = 1, count do
            local pick = pickCard(sheetData._cardListCache)
            table.insert(selected, pick)
        end
    else
        -- No duplicates: pick from remaining cards
        local drawnSet = {}
        local availableCards = sheetData._cardListCache
        
        for _ = 1, count do
            if #availableCards == 0 then
                -- Shouldn't happen, but fallback to allowing duplicates
                availableCards = sheetData._cardListCache
            end

            local pick = pickCard(availableCards)
            
            if not drawnSet[pick] then
                drawnSet[pick] = true
                
                -- Remove the drawn card from available pool
                local newAvailable = {}
                for _, card in ipairs(availableCards) do
                    if card.id ~= pick then
                        table.insert(newAvailable, card)
                    end
                end
                availableCards = newAvailable
            end
            
            table.insert(selected, pick)
        end
    end

    return selected
end

local function parseCardId(cardId)
    -- Handles cases like: "tdm:98" or "tdm:98:foil"
    local parts = {}
    for part in string.gmatch(cardId, "([^:]+)") do
        table.insert(parts, part)
    end

    local setCode = parts[1] or ""
    local collectorNum = parts[2] or ""
    local isFoil = (parts[3] == "foil")

    return setCode, collectorNum, isFoil
end

local function queryGeneratePacks(numPacks, onSuccess, onError)
    local function doPackGeneration(packIndex, packCode, onPackComplete, onPackError)
        -- Fetch booster info for this pack
        local boosterMeta = nil
        for _, entry in ipairs(BoosterIndex or {}) do
            if entry.code == packCode then
                boosterMeta = entry
                break
            end
        end

        if not boosterMeta then
            onPackError("Booster entry not found in index for code: " .. tostring(packCode))
            return
        end

        -- Use cached data if available
        if BoosterDataCache[packCode] then
            local packInfo = BoosterDataCache[packCode]
            local boosterLayout = pickWeighted(packInfo.boosters)

            local pack = {
                cards = {},
                sheetOrder = boosterLayout.sheet_order,
            }

            for _, sheetName in ipairs(boosterLayout.sheet_order) do
                local count = boosterLayout.sheets[sheetName]
                local drawn = drawCardsFromSheet(packInfo.sheets[sheetName], count)

                for _, rawId in ipairs(drawn) do
                    local setCode, collectorNum, isFoil = parseCardId(rawId)

                    local cardData = {
                        count = 1,
                        name = "",
                        setCode = setCode,
                        collectorNum = collectorNum,
                        foil = isFoil,
                        packIndex = packIndex,
                        sheetName = sheetName,
                        packName = packInfo.name
                    }

                    table.insert(pack.cards, cardData)
                end
            end

            onPackComplete(pack)
            return
        end

        -- Fetch the booster JSON
        local boosterUrl = BASE_BOOSTER_FILE_URL .. "/" .. boosterMeta.code .. ".json"
        
        local headers = {
            ["User-Agent"] = "TTSMTGBoosterCreator/1.0",
            ["Accept"] = "application/json;q=0.9,*/*;q=0.8"
        }

        WebRequest.custom(boosterUrl, "GET", true, "", headers, function(webReturn)
            if webReturn.error or webReturn.is_error or string.len(webReturn.text) == 0 then
                onPackError("Failed to fetch booster data for " .. packCode)
                return
            end

            local success, data = pcall(function()
                return jsondecode(webReturn.text)
            end)
            if not success or not data then
                onPackError("Failed to parse booster JSON for " .. packCode)
                return
            end

            BoosterDataCache[packCode] = data
            local packInfo = data
            local boosterLayout = pickWeighted(packInfo.boosters)

            local pack = {
                cards = {},
                sheetOrder = boosterLayout.sheet_order,
            }

            for _, sheetName in ipairs(boosterLayout.sheet_order) do
                local count = boosterLayout.sheets[sheetName]
                local drawn = drawCardsFromSheet(packInfo.sheets[sheetName], count)

                for _, rawId in ipairs(drawn) do
                    local setCode, collectorNum, isFoil = parseCardId(rawId)

                    local cardData = {
                        count = 1,
                        name = "",
                        setCode = setCode,
                        collectorNum = collectorNum,
                        foil = isFoil,
                        packIndex = packIndex,
                        sheetName = sheetName,
                        packName = packInfo.name
                    }

                    table.insert(pack.cards, cardData)
                end
            end

            onPackComplete(pack)
        end)
    end

    -- Generate packs sequentially
    local allPacks = {}
    local currentPack = 0
    local fixedRandomPackCode = nil
    
    local function generateNextPack()
        currentPack = currentPack + 1
        if currentPack > numPacks then
            onSuccess(allPacks, "")
            return
        end

        -- Determine booster code for this pack
        local packCode
        if useRandomBoosterSelection then
            local availableBoosters = filteredBoosters or BoosterIndex
            if not availableBoosters or #availableBoosters == 0 then
                onError("No boosters available for random selection. Adjust filters in Advanced menu.")
                return
            end

            if randomBoostersPerPack then
                local randomIndex = math.random(1, #availableBoosters)
                packCode = availableBoosters[randomIndex].code
            else
                if not fixedRandomPackCode then
                    local randomIndex = math.random(1, #availableBoosters)
                    fixedRandomPackCode = availableBoosters[randomIndex].code
                end
                packCode = fixedRandomPackCode
            end
        else
            packCode = PackCode
        end

        doPackGeneration(currentPack, packCode, function(pack)
            table.insert(allPacks, pack)
            generateNextPack()
        end, function(e)
            onError(e)
        end)
    end

    generateNextPack()
end

function generatePacks()
    if lock then
        log("Error: Pack Generation started while importer locked.")
        return 1
    end

    lock = true

    local success, err = pcall(function()
        local numberOfPacks = getPackAmountValue()

        printToAll("Starting pack generation...")

        queryGeneratePacks(numberOfPacks, function(packs, deckName)
            loadDeck(packs, deckName, function()
                printToAll("Pack generation complete!")
                lock = false
            end, function(e)
                printToAll("Pack load error: " .. tostring(e))
                lock = false
            end)
        end, function(e)
            printToAll("Query error: " .. tostring(e))
            lock = false
        end)
    end)

    if not success then
        printToAll("Pack generation failed: " .. tostring(err))
        lock = false
    end

    return 1
end

BoosterIndex = nil
BoosterDataCache = {}

local function escapeXml(str)
    str = string.gsub(str, "&", "&amp;")
    str = string.gsub(str, "<", "&lt;")
    str = string.gsub(str, ">", "&gt;")
    str = string.gsub(str, '"', "&quot;")
    str = string.gsub(str, "'", "&apos;")
    return str
end

local baseXmlCache = nil  -- base XML without the selector panel, cached for search rebuilds

local function buildDropdownPanel(filter)
    local lowerFilter = string.lower(filter or "")
    local matches = {}

    for _, entry in ipairs(BoosterIndex) do
        if lowerFilter == "" or
           string.find(string.lower(entry.name), lowerFilter, 1, true) or
           string.find(string.lower(entry.code), lowerFilter, 1, true) then
            table.insert(matches, entry)
        end
    end

    -- Keep the current pack selected if it is still visible; otherwise default to the first match
    local currentVisible = false
    for _, entry in ipairs(matches) do
        if entry.code == PackCode then
            currentVisible = true
            break
        end
    end
    if not currentVisible then
        PackCode = (#matches > 0) and matches[1].code or ""
    end

    local optionsXml = ""
    for _, entry in ipairs(matches) do
        optionsXml = optionsXml .. string.format('<Option value="%s">%s</Option>',
            escapeXml(entry.code), escapeXml(entry.name))
    end
    if #matches == 0 then
        optionsXml = '<Option value="">No results found</Option>'
    end

    return string.format([[
        <Panel id="MTGPackGeneratorSelector" position="80 -122 -10" rotation="180 180 0" width="300" height="300">
            <InputField id="boosterSearch" position="80 3 0" width="453" height="30"
                placeholder="Search boosters..." onEndEdit="mtgdl__onSearchInput" text="%s"/>
            <Dropdown id="dynamicDropdown" position="80 -30 0" onValueChanged="onDropdownChanged" width="453" height="30" scrollSensitivity="30" dropdownHeight="190" itemHeight="45">
                %s
            </Dropdown>
        </Panel>
    ]], escapeXml(filter or ""), optionsXml)
end

local function buildDropdownFromIndex()
    baseXmlCache = self.UI.getXml()
    self.UI.setXml(buildDropdownPanel(boosterSearchFilter or "") .. baseXmlCache)
end

local function findFirstMatchingBooster(filter)
    local lowerFilter = string.lower(filter or "")
    if lowerFilter == "" then
        return nil
    end

    for _, entry in ipairs(BoosterIndex or {}) do
        if string.find(string.lower(entry.name), lowerFilter, 1, true) or
           string.find(string.lower(entry.code), lowerFilter, 1, true) then
            return entry
        end
    end

    return nil
end

local function queryBoosterIndex()
    local url = BOOSTER_INDEX_URL
    
    local headers = {
        ["User-Agent"] = "TTSMTGBoosterCreator/1.0",
        ["Accept"] = "application/json;q=0.9,*/*;q=0.8"
    }

    WebRequest.custom(url, "GET", true, "", headers, function(webReturn)
        if webReturn.error or webReturn.is_error or string.len(webReturn.text) == 0 then
            onError("Failed to fetch booster index: " .. (webReturn.error or "Unknown error"))
            return
        end

        local success, data = pcall(function()
            return jsondecode(webReturn.text)
        end)
        if not success or not data then
            onError("Failed to parse booster index JSON.")
            return
        end

        BoosterIndex = data

        print("Booster index loaded.")
        buildDropdownFromIndex()
        applyBoosterFilters()
    end)
end

function onDropdownChanged(player, value, id)
    -- print("Dropdown changed. Received value:", value)
    -- The option value is the code; keep a label fallback for compatibility.
    for _, entry in ipairs(BoosterIndex) do
        if entry.code == value or entry.name == value then
            PackCode = entry.code
            -- print("Resolved PackCode:", PackCode)
            return
        end
    end
end

function mtgdl__onSearchInput(player, value)
    local nextFilter = value or ""
    if nextFilter == boosterSearchFilter then
        return
    end

    boosterSearchFilter = nextFilter

    local match = findFirstMatchingBooster(nextFilter)
    if match then
        PackCode = match.code
    end
end

------ UI
local function drawUI()
    local _inputs = self.getInputs()
    local packAmount = 6

    if _inputs ~= nil then
        for i, input in pairs(self.getInputs()) do
            if input.label == "Enter the Amount of Packs" then
                local val = tonumber(input.value) or MIN_PACK_AMOUNT
                if val > MAX_PACK_AMOUNT then
                    val = MAX_PACK_AMOUNT
                    input.value = val -- update input to reflect clamp
                elseif val < MIN_PACK_AMOUNT then
                    val = MIN_PACK_AMOUNT
                    input.value = val
                end
                packAmount = val
                log("Pack amount set to: " .. packAmount)
            end
        end
    end
    self.clearInputs()
    self.clearButtons()

    self.createInput({
        input_function = "onPackAmountInput",
        function_owner = self,
        label = "Enter the Amount of Packs",
        alignment = 2,
        position = { -1, 0.1, 1.15 },
        width = 150,
        height = 150,
        font_size = 120,
        validation = 2,
        value = packAmount
    })

    self.createButton({
        click_function = "onGeneratePackButton",
        function_owner = self,
        label = "Generate Packs",
        position = { 0.1, 0.1, 1.15 },
        rotation = { 0, 0, 0 },
        width = 800,
        height = 150,
        font_size = 80,
        color = { 0.5, 0.5, 0.5 },
        font_color = {
            r = 1,
            b = 1,
            g = 1
        },
        tooltip = "Click to generate your selected packs"
    })

    self.createButton({
        click_function = "onRandomBoosterButton",
        function_owner = self,
        label = "Random",
        position = { 1.4, 0.1, 1.15 },
        rotation = { 0, 0, 0 },
        width = 350,
        height = 150,
        font_size = 70,
        color = { 0.3, 0.5, 0.3 },
        font_color = {
            r = 1,
            b = 1,
            g = 1
        },
        tooltip = "Click to generate random booster(s). Uses Booster Filters in the Advanced menu."
    })

    self.createButton({
        click_function = "onToggleAdvancedButton",
        function_owner = self,
        label = "...",
        position = { 2.1, 0.1, 1.15 },
        rotation = { 0, 0, 0 },
        width = 150,
        height = 150,
        font_size = 100,
        color = { 0.5, 0.5, 0.5 },
        font_color = {
            r = 1,
            b = 1,
            g = 1
        },
        tooltip = "Click to open advanced menu"
    })

    if advanced then
        self.UI.show(UI_ADVANCED_PANEL)
    else
        self.UI.hide(UI_ADVANCED_PANEL)
    end
end

function getPackAmountValue()
    for i, input in pairs(self.getInputs()) do
        if input.label == "Enter the Amount of Packs" then
            local val = tonumber(input.value) or MIN_PACK_AMOUNT
            if val > MAX_PACK_AMOUNT then
                val = MAX_PACK_AMOUNT
            elseif val < MIN_PACK_AMOUNT then
                val = MIN_PACK_AMOUNT
            end
            return val
        end
    end

    return MIN_PACK_AMOUNT
end

function onPackAmountInput(_, _, _)
end

function onOpenPackSelectorButton(_, pc, _)

end

function onGeneratePackButton(_, pc, _)
    if lock then
        printToColor("Another pack is currently generated. Please wait for that to finish.", pc)
        return
    end

    if not prepareSeedForGeneration(pc) then
        return
    end

    useRandomBoosterSelection = false
    playerColor = pc
    startLuaCoroutine(self, "generatePacks")
end

function onRandomBoosterButton(_, pc, _)
    if lock then
        printToColor("Another pack is currently generated. Please wait for that to finish.", pc)
        return
    end

    if not BoosterIndex or #BoosterIndex == 0 then
        printToColor("Booster index not yet loaded. Please wait.", pc)
        return
    end

    if not prepareSeedForGeneration(pc) then
        return
    end

    useRandomBoosterSelection = true
    playerColor = pc
    startLuaCoroutine(self, "generatePacks")
end

function onToggleAdvancedButton(_, _, _)
    advanced = not advanced
    drawUI()
end

function getCardBack()
    if not cardBackInput or string.len(cardBackInput) == 0 then
        return DEFAULT_CARDBACK
    else
        return cardBackInput
    end
end

function mtgdl__onCardBackInput(_, value, _)
    cardBackInput = value
end

function getLanguageCode()
    if not languageInput or string.len(languageInput) == 0 then
        return DEFAULT_LANGUAGE
    else
        local code = LANGUAGES[string.lower(trim(languageInput))]

        return (code or DEFAULT_LANGUAGE)
    end
end

function mtgdl__onLanguageInput(_, value, _)
    languageInput = value
end

function mtgdl__onForceLanguageInput(_, value, _)
    forceLanguage = stringToBool(value)
end

function mtgdl__onFoilInput(_, value, _)
    enableFoil = stringToBool(value)
end

function mtgdl__onBlowCacheInput(_, value, _)
    blowCache = stringToBool(value)
end

function mtgdl__onPNGGraphicsInput(_, value, _)
    pngGraphics = stringToBool(value)
end

function mtgdl__onFaceDownInput(_, value, _)
    spawnEverythingFaceDown = stringToBool(value)
end

function mtgdl__onRandomBoostersPerPackInput(_, value, _)
    randomBoostersPerPack = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onUseRandomSeedInput(_, value, _)
    useRandomSeed = stringToBool(value)
    refreshSeedUI()
end

function mtgdl__onSeedInput(player, value, _)
    if lock then
        notifyPlayer(player, "Cannot change seed while pack generation is running.")
        refreshSeedUI()
        return
    end

    if useRandomSeed then
        notifyPlayer(player, "Disable 'Use Random Seed' to enter a manual seed.")
        refreshSeedUI()
        return
    end

    seedInput = trim(value or "")
    if string.len(seedInput) == 0 then
        refreshSeedUI()
        return
    end

    local success, err = setCurrentSeed(seedInput)
    if not success then
        notifyPlayer(player, "Invalid seed: " .. tostring(err), { r = 1, g = 0, b = 0 })
        seedInput = tostring(currentSeed or "")
        refreshSeedUI()
        return
    end

    if tonumber(seedInput) then
        notifyPlayer(player, "Seed set to " .. tostring(currentSeed))
    else
        notifyPlayer(player, "Seed set to '" .. seedInput .. "' (numeric: " .. tostring(currentSeed) .. ")")
    end
end

function onRandomizeSeedButton(_, pc, _)
    if lock then
        notifyPlayer(pc, "Cannot change seed while pack generation is running.")
        return
    end

    local success, err = randomizeSeed()
    if not success then
        notifyPlayer(pc, "Failed to randomize seed: " .. tostring(err), { r = 1, g = 0, b = 0 })
        return
    end

    notifyPlayer(pc, "Seed randomized to " .. tostring(currentSeed))
end

function applyBoosterFilters()
    if not BoosterIndex then
        return
    end

    local filtered = {}
    
    for _, booster in ipairs(BoosterIndex) do
        local code = string.lower(booster.code)
        local shouldInclude = false

        -- Check for SLD category
        if string.sub(code, 1, 3) == "sld" then
            shouldInclude = filterSLD
        elseif string.find(code, "-") then
            -- Has hyphen - categorize by suffix
            if string.find(code, "-draft") then
                shouldInclude = filterDraft
            elseif string.find(code, "-collector%-sample") then
                shouldInclude = filterOther
            elseif string.find(code, "-collector") then
                shouldInclude = filterCollector
            elseif string.find(code, "-play") then
                shouldInclude = filterPlay
            elseif string.find(code, "-set") then
                shouldInclude = filterSet
            elseif string.find(code, "-arena") then
                shouldInclude = filterArena
            elseif string.find(code, "-prerelease") then
                shouldInclude = filterPrerelease
            elseif string.find(code, "-jumpstart") then
                shouldInclude = filterJumpstart
            elseif string.find(code, "-theme") then
                shouldInclude = filterTheme
            else
                -- Other hyphenated codes (box-topper, bundle-promo, etc.)
                shouldInclude = filterOther
            end
        else

            shouldInclude = filterVintage
        end

        if shouldInclude then
            table.insert(filtered, booster)
        end
    end

    filteredBoosters = (#filtered > 0) and filtered or BoosterIndex
end

function mtgdl__onFilterDraftInput(_, value, _)
    filterDraft = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterCollectorInput(_, value, _)
    filterCollector = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterPlayInput(_, value, _)
    filterPlay = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterSetInput(_, value, _)
    filterSet = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterArenaInput(_, value, _)
    filterArena = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterPrereleaseInput(_, value, _)
    filterPrerelease = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterJumpstartInput(_, value, _)
    filterJumpstart = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterThemeInput(_, value, _)
    filterTheme = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterOtherInput(_, value, _)
    filterOther = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterVintageInput(_, value, _)
    filterVintage = stringToBool(value)
    applyBoosterFilters()
end

function mtgdl__onFilterSLDInput(_, value, _)
    filterSLD = stringToBool(value)
    applyBoosterFilters()
end

------ TTS CALLBACKS
function onLoad()
    self.setName("MTG Booster Generator")

    self.setDescription([[
    Select the Booster you want from the List.
    Type in the number of Boosters and click
    Generate Packs to get your Boosters.
    ]])

    setCurrentSeed(os.time())
    drawUI()
    refreshSeedUI()
    queryBoosterIndex()
end