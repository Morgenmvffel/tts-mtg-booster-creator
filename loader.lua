#include json_parser

------ CONSTANTS
SCRYFALL_ID_BASE_URL = "https://api.scryfall.com/cards/"
SCRYFALL_MULTIVERSE_BASE_URL = "https://api.scryfall.com/cards/multiverse/"
SCRYFALL_SET_NUM_BASE_URL = "https://api.scryfall.com/cards/"
SCRYFALL_SEARCH_BASE_URL = "https://api.scryfall.com/cards/search/?q="
SCRYFALL_NAME_BASE_URL = "https://api.scryfall.com/cards/named/?exact="

PACK_ODDS_URL = "https://raw.githubusercontent.com/taw/magic-sealed-data/refs/heads/master/sealed_basic_data.json"
BOOSTER_INDEX_URL =
"https://raw.githubusercontent.com/Morgenmvffel/tts-mtg-booster-creator/refs/heads/master/booster_index.json"
BASE_BOOSTER_FILE_URL =
"https://raw.githubusercontent.com/Morgenmvffel/tts-mtg-booster-creator/refs/heads/master/booster"

BOOSTER_IMAGE_URL =
"https://steamusercontent-a.akamaihd.net/ugc/12048320118311789698/728EE5247F5FE466F92DAAC0E9997225CD3E8865/"
FOIL_EFFECT_URL =
"https://steamusercontent-a.akamaihd.net/ugc/18215652933654632959/A843EB4C96D1CE5E339D66F48A414D671B2CB4CC/"

MAINDECK_POSITION_OFFSET = { 2, 0.2, -0.2 }
TOKENS_POSITION_OFFSET = { 1.9, 0.2, 0.9 }

POSITION_SPACING = -0.8

DEFAULT_CARDBACK =
"https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg?version=0ddc8d41c3b69c2c3c4bb5d72669ffd7"
DEFAULT_LANGUAGE = "en"

-- Pack Amounts
MAX_PACK_AMOUNT = 6
MIN_PACK_AMOUNT = 1

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
UI_ADVANCED_PANEL = "MTGDeckLoaderAdvancedPanel"
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
        onFullySpawned(bagObj)
    else
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
        "modal_dfc" or data.layout == "double_faced_token" then
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

        WebRequest.get(uri, function(webReturn)
            if webReturn.is_error or webReturn.error or string.len(webReturn.text) == 0 then
                log("Error fetching token: " .. webReturn.error or "unknown")
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
    end, 30, function()
        onError("Error loading card data... timed out.")
    end)
end

-- Queries scryfall by the [cardID].
-- cardID must define at least one of scryfallID, multiverseID, or name.
-- if forceNameQuery is true, will query scryfall by card name ignoring other data.
-- if forceSetNumLangQuery is true, will query scryfall by set/num/lang ignoring other data.
-- onSuccess is called with a populated card table, and a table of associated tokens.
local function queryCard(cardID, forceStandardLanguage, onSuccess, onError)
    local query_url

    local language_code = getLanguageCode()

    if forceStandardLanguage and cardID.setCode and string.len(cardID.setCode) > 0 and cardID.collectorNum and string.len(cardID.collectorNum) > 0 then
        query_url = SCRYFALL_SET_NUM_BASE_URL .. string.lower(cardID.setCode) .. "/" .. cardID.collectorNum
    elseif cardID.setCode and string.len(cardID.setCode) > 0 and cardID.collectorNum and string.len(cardID.collectorNum) > 0 then
        query_url = SCRYFALL_SET_NUM_BASE_URL ..
        string.lower(cardID.setCode) .. "/" .. cardID.collectorNum .. "/" .. language_code
    end

    -- log(query_url)

    webRequest = WebRequest.get(query_url, function(webReturn)
        if webReturn.is_error or webReturn.error then
            onError("Web request error: " .. webReturn.error or "unknown")
            return
        elseif string.len(webReturn.text) == 0 then
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

-- Queries card data for all cards.
-- TODO use the bulk api (blocked by JSON decode issue)
local function fetchCardData(cards, onComplete, onError)
    local sem = 0
    local function incSem() sem = sem + 1 end
    local function decSem() sem = sem - 1 end

    local cardData = {}
    local tokensData = {}

    local function onQuerySuccess(card, tokens)
        table.insert(cardData, card)
        for _, token in ipairs(tokens) do
            table.insert(tokensData, token)
        end
        decSem()
    end

    local function onQueryFailed(e)
        log("Error querying scryfall: " .. e)
        decSem()
    end

    local language = getLanguageCode()

    local function cleanCollectorNum(collectorNum)
        return string.match(collectorNum, "%d+")
    end

    for _, cardID in ipairs(cards) do
        incSem()
        queryCard(
            cardID,
            false,
            function(card, tokens)  -- onSuccess
                onQuerySuccess(card, tokens)
            end,
            function(e) -- onError
                -- try again, with collecter num cleaned.
                log("query retry for cardid:" .. cardID.setCode .. ":" .. cardID.collectorNum)
                cardID.collectorNum = cleanCollectorNum(cardID.collectorNum)
                queryCard(
                    cardID,
                    false,
                    onQuerySuccess,
                    function(e)
                        log("language retry for cardid:" .. cardID.setCode .. ":" .. cardID.collectorNum)
                        cardID.collectorNum = cleanCollectorNum(cardID.collectorNum)
                        queryCard(
                            cardID,
                            true,
                            onQuerySuccess,
                            onQueryFailed
                        )
                    end)
            end)
    end

    Wait.condition(
        function() onComplete(cardData, tokensData) end,
        function() return (sem == 0) end,
        30,
        function() onError("Error loading card images... timed out.") end
    )
end

-- Queries for the given card IDs, collates deck, and spawns objects.
local function loadDeck(packs, deckName, onComplete, onError)
    local tokensPosition = self.positionToWorld(TOKENS_POSITION_OFFSET)

    printInfo("Querying Scryfall for card data...")

    local sem = #packs -- Semaphore for packs
    local function decSem() sem = sem - 1 end

    -- Table to collect all tokens
    local allTokens = {}

    -- Loop through each pack and call fetchCardData for each pack's card IDs
    for packIndex, pack in ipairs(packs) do
        local cardIDsForPack = pack.cards -- Get card IDs for this pack

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
            spawnBagWithCards(cards, deckName .. " - Pack " .. packIndex, offset, false, pack.sheetOrder, function()
                decSem()
            end, function(e)
                printErr(e)
                decSem()
            end)

            -- Collect all tokens for later spawning
            for _, token in ipairs(tokens) do
                table.insert(allTokens, token)
            end
        end, function(e)
            -- Error callback for fetchCardData
            printErr("Failed to fetch card data for pack " .. packIndex .. ": " .. tostring(e))
            decSem()
        end)
    end

    -- Spawn all tokens at once after all packs are processed
    Wait.condition(function()
        -- Spawn the collected tokens only after all async fetch and card spawning are complete
        spawnDeck(allTokens, deckName .. " - tokens", tokensPosition, 90, false, function()
            decSem()
        end
        , function(e)
            printErr(e)
            decSem()
        end)
        onComplete()
    end, function()
        return sem == 0 -- Wait for all packs to be processed
    end, 10, function()
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
        if roll <= cumulative then
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
        if r <= cumulative then
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

    -- Regular random weighted draw
    local cardList = {}
    for id, weight in pairs(sheetData.cards) do
        table.insert(cardList, {
            id = id,
            weight = weight
        })
    end

    local allowDuplicates = sheetData.allow_duplicates == true
    local drawnSet = {} -- tracks which cards we've already drawn

    for _ = 1, count do
        local pick
        local attempts = 0

        repeat
            pick = pickCard(cardList)
            attempts = attempts + 1
        until allowDuplicates or not drawnSet[pick] or attempts > 50

        if not allowDuplicates then
            drawnSet[pick] = true
        end

        table.insert(selected, pick)
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
    local code = PackCode

    local function doPackGeneration(packInfo)
        local packs = {} -- This will hold each pack with cards and tokens.

        for packIndex = 1, numPacks do
            local boosterLayout = pickWeighted(packInfo.boosters)

            local pack = {
                cards = {},                             -- Array to store card data for this pack.
                sheetOrder = boosterLayout.sheet_order, -- Store the sheet order for later use
            }

            -- Loop through the sheet_order to respect the order of the sheets
            for _, sheetName in ipairs(boosterLayout.sheet_order) do
                local count = boosterLayout.sheets[sheetName]
                local drawn = drawCardsFromSheet(packInfo.sheets[sheetName], count)

                for _, rawId in ipairs(drawn) do
                    local setCode, collectorNum, isFoil = parseCardId(rawId)

                    local cardData = {
                        count = 1,
                        name = "", -- Add actual card name here if needed.
                        setCode = setCode,
                        collectorNum = collectorNum,
                        foil = isFoil,
                        packIndex = packIndex,
                        sheetName = sheetName, -- Keep track of which sheet the card came from
                        packName = packInfo.name
                    }

                    -- Add each drawn card to the 'cards' array
                    table.insert(pack.cards, cardData)
                end
            end

            -- Add the current pack to the list of packs
            table.insert(packs, pack)
        end

        onSuccess(packs, "")
    end

    -- Use cached data if available
    if BoosterDataCache[code] then
        doPackGeneration(BoosterDataCache[code])
        return
    end

    -- Find the booster file entry
    local boosterMeta = nil
    for _, entry in ipairs(BoosterIndex or {}) do
        if entry.code == code then
            boosterMeta = entry
            break
        end
    end

    if not boosterMeta then
        onError("Booster entry not found in index for code: " .. tostring(code))
        return
    end

    -- Fetch the booster JSON
    local boosterUrl = BASE_BOOSTER_FILE_URL .. "/" .. boosterMeta.code .. ".json"
    WebRequest.get(boosterUrl, function(webReturn)
        if webReturn.error or webReturn.is_error or string.len(webReturn.text) == 0 then
            onError("Failed to fetch booster data for " .. code)
            return
        end

        local success, data = pcall(function()
            return jsondecode(webReturn.text)
        end)
        if not success or not data then
            onError("Failed to parse booster JSON for " .. code)
            return
        end

        BoosterDataCache[code] = data
        doPackGeneration(data)
    end)
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

local function buildDropdownFromIndex()
    local optionsXml = ""

    for i, entry in ipairs(BoosterIndex) do
        local selectedStr = ""
        if i == 1 then
            selectedStr = ' selected="true"'
            PackCode = entry.code
        end
        optionsXml = optionsXml .. string.format('<Option value="%s"%s>%s</Option>', entry.code, -- value
            selectedStr,                                                                         -- selected="true" if first
            entry.name                                                                           -- label shown in dropdown
        )
    end

    local old_xml = self.UI.getXml()

    local xml = string.format([[
        <Panel id="MTGPackGeneratorSelector" position="80 -120 -10" rotation="180 180 0" width="300" height="300">
            <Dropdown id="dynamicDropdown" position="82 -10 0" onValueChanged="onDropdownChanged" width="470" height="30" scrollSensitivity="30">
                %s
            </Dropdown>
        </Panel>
    ]], optionsXml)

    self.UI.setXml(xml .. old_xml)
end

local function queryBoosterIndex()
    local url = BOOSTER_INDEX_URL
    WebRequest.get(url, function(webReturn)
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
    end)
end

function onDropdownChanged(player, value, id)
    -- print("Dropdown changed. Received value:", value)
    -- Map name (label) back to code
    for _, entry in ipairs(BoosterIndex) do
        if entry.name == value then
            PackCode = entry.code
            -- print("Resolved PackCode:", PackCode)
            return
        end
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
        position = { -0.4, 0.1, 1.15 },
        width = 240,
        height = 160,
        font_size = 130,
        validation = 2,
        value = packAmount
    })

    self.createButton({
        click_function = "onGeneratePackButton",
        function_owner = self,
        label = "Generate Packs",
        position = { 1, 0.1, 1.15 },
        rotation = { 0, 0, 0 },
        width = 850,
        height = 160,
        font_size = 80,
        color = { 0.5, 0.5, 0.5 },
        font_color = {
            r = 1,
            b = 1,
            g = 1
        },
        tooltip = "Click to generate your packs"
    })

    self.createButton({
        click_function = "onToggleAdvancedButton",
        function_owner = self,
        label = "...",
        position = { 2.25, 0.1, 1.15 },
        rotation = { 0, 0, 0 },
        width = 160,
        height = 160,
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
        self.UI.show("MTGDeckLoaderAdvancedPanel")
    else
        self.UI.hide("MTGDeckLoaderAdvancedPanel")
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

------ TTS CALLBACKS
function onLoad()
    self.setName("MTG Booster Generator")

    self.setDescription([[
    Select the Booster you want from the List.
    Type in the number of Boosters and click
    Generate Packs to get your Boosters.
    ]])

    math.randomseed(os.time())
    drawUI()
    queryBoosterIndex()
end
