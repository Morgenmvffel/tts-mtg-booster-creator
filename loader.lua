#include json_parser

------ CONSTANTS
SCRYFALL_ID_BASE_URL = "https://api.scryfall.com/cards/"
SCRYFALL_MULTIVERSE_BASE_URL = "https://api.scryfall.com/cards/multiverse/"
SCRYFALL_SET_NUM_BASE_URL = "https://api.scryfall.com/cards/"
SCRYFALL_SEARCH_BASE_URL = "https://api.scryfall.com/cards/search/?q="
SCRYFALL_NAME_BASE_URL = "https://api.scryfall.com/cards/named/?exact="

PACK_ODDS_URL = "https://raw.githubusercontent.com/taw/magic-sealed-data/refs/heads/master/sealed_basic_data.json"

MAINDECK_POSITION_OFFSET = {2, 0.2, -0.2}
MAYBEBOARD_POSITION_OFFSET = {1.47, 0.2, 0.1286}
SIDEBOARD_POSITION_OFFSET = {-1.47, 0.2, 0.1286}
COMMANDER_POSITION_OFFSET = {0.7286, 0.2, -0.8257}
TOKENS_POSITION_OFFSET = {1.9, 0.2, 0.9}

POSITION_SPACING = -0.8

DEFAULT_CARDBACK = "https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg?version=0ddc8d41c3b69c2c3c4bb5d72669ffd7"
DEFAULT_LANGUAGE = "en"

--Pack Amounts
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
enableTokenButtons = false
blowCache = false
pngGraphics = true
spawnEverythingFaceDown = false

------ UTILITY
local function trim(s)
    if not s then return "" end

    local n = s:find"%S"
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
    printToColor(s, playerColor, {r=1, g=0, b=0})
end

local function printInfo(s)
    printToColor(s, playerColor)
end

local function stringToBool(s)
    -- It is truly ridiculous that this needs to exist.
    return (string.lower(s) == "true")
end

------ CARD SPAWNING
local function jsonForCardFace(face, position, rotationY, flipped)
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
        LuaScriptState = "",
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

     if enableTokenButtons and face.tokenData and face.tokenData[1] and face.tokenData[1].name and string.len(face.tokenData[1].name) > 0 then
         json.LuaScript =
            [[function onLoad(saved_data)
                if saved_data ~= "" then
                    tokens = JSON.decode(saved_data)
                else
                    tokens = {}
                end

                local pZ = -1.04
                for i, token in ipairs(tokens) do
                    self.createButton({label = token.name,
                        tooltip = "Create " .. token.name .. "\n" .. token.oracleText,
                        click_function = "gt" .. i,
                        function_owner = self,
                        width = math.max(400, 40 * string.len(token.name) + 40),
                        height = 100,
                        color = {1, 1, 1, 0.5},
                        hover_color = {1, 1, 1, .7},
                        font_color = {0, 0, 0, 2},
                        position = {.5, 0.5, pZ},
                        font_size = 75})
                    pZ = pZ + 0.28
                end
            end

            function onSave()
                return JSON.encode(tokens)
            end

            function gt1() getToken(1) end
            function gt2() getToken(2) end
            function gt3() getToken(3) end
            function gt4() getToken(4) end

            function getToken(i)
                token = tokens[i]
                spawnObject({
                    type = "Card",
                    sound = false,
                    rotation = self.getRotation(),
                    position = self.positionToWorld({-2.2,0.1,0}),
                    scale = self.getScale(),
                    callback_function = (function(obj)
                        obj.memo = ""
                        obj.setName(token.name)
                        obj.setDescription(token.oracleText)
                        obj.setCustomObject({
                            face = token.front,
                            back = token.back
                        })
                        if (parent) then
                          parent.call("CAddButtons",{obj, self})
                        end
                    end)
                })
            end
        ]]

        json.LuaScriptState=JSON.encode(face.tokenData)
     end

     return json
end

-- Spawns the given card [faces] at [position].
-- Card will be face down if [flipped].
-- Calls [onFullySpawned] when the object is spawned.
local function spawnCard(faces, position, rotation, flipped, onFullySpawned)
    if not faces or not faces[1] then
        faces = {{
            name = card.name,
            oracleText = "Card not found",
            imageURI = "https://vignette.wikia.nocookie.net/yugioh/images/9/94/Back-Anime-2.png/revision/latest?cb=20110624090942",
        }}
    end

    -- Force flipped if the user asked for everything to be spawned face-down
    if spawnEverythingFaceDown then
        flipped = true
    end

    local jsonFace1 = jsonForCardFace(faces[1], position, rotation, flipped)

    if #faces > 1 then
        jsonFace1.States = {}
        for i=2,(#(faces)) do
            local jsonFaceI = jsonForCardFace(faces[i], position, rotation, flipped)

            jsonFace1.States[tostring(i)] = jsonFaceI
        end
    end

    local cardObj = spawnObjectJSON({json = JSON.encode(jsonFace1)})

    onFullySpawned(cardObj)

    return cardObj
end

-- Spawns a deck named [name] containing the given [cards] at [position].
-- Deck will be face down if [flipped].
-- Calls [onFullySpawned] when the object is spawned.
local function spawnDeck(cards, name, position, rotation, flipped, onFullySpawned, onError)
    local cardObjects = {}

    local sem = 0
    local function incSem() sem = sem + 1 end
    local function decSem() sem = sem - 1 end

    for _, card in ipairs(cards) do
        for i=1,(card.count or 1) do
            if not card.faces or not card.faces[1] then
                card.faces = {{
                    name = card.name,
                    oracleText = "Card not found",
                    imageURI = "https://vignette.wikia.nocookie.net/yugioh/images/9/94/Back-Anime-2.png/revision/latest?cb=20110624090942",
                }}
            end

            incSem()
            spawnCard(card.faces, position, rotation, flipped, function(obj)
                table.insert(cardObjects, obj)
                decSem()
            end)
        end
    end

    Wait.condition(
        function()
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
        end,
        function() return (sem == 0) end,
        5,
        function() onError("Error collating deck... timed out.") end
    )
end

local function sortCardsByRarity(cards)
    local rarityOrder = {
        "basic",
        "common",
        "special_guest",
        "uncommon",
        "showcase_cu",
        "retro_cu",
        "wildcard",
        "foil_showcase_cu",
        "rare_mythic",
        "foil_rare_mythic",
        "showcase_rare_mythic",
        "showcase_commander",
        "booster_fun",
        "foil_booster_fun",
        "foil_showcase_rare_mythic",
        "rare_mythic_with_boosterfun",
        "rare_mythic_with_showcase",
        "rare_mythic_showcase",
        "foil",
        "non_foil_land",
        "foil_basic",
        "foil_land",
        "basic",
        "land",
    }

        local rarityScore = {}
    for i, name in ipairs(rarityOrder) do
        rarityScore[name] = i
    end

    local function getCardRarityRank(card)
        local sheet = (card.sheetName or ""):lower()

        -- Exact match
        if rarityScore[sheet] then
            return rarityScore[sheet], sheet
        end

        -- Fallback keywords
        if sheet:find("uncommon") then return rarityScore["uncommon"] or 4, sheet end
        if sheet:find("common") then return rarityScore["common"] or 2, sheet end
        if sheet:find("rare") or sheet:find("mythic") then
            return rarityScore["rare_mythic"] or 9, sheet
        end

        return 9999, sheet -- Unknown: lowest rarity, sorted alphabetically
    end

    table.sort(cards, function(a, b)
        local rankA, nameA = getCardRarityRank(a)
        local rankB, nameB = getCardRarityRank(b)

        if rankA ~= rankB then
            return rankA > rankB -- descending rarity
        else
            return nameA < nameB -- ascending alphabetically for unknowns
        end
    end)
end

local function spawnBagWithCards(cards, bagName, position, flipped, onFullySpawned, onError)
    -- Sort cards alphabetically by sheetName (fallback to name if missing)
    sortCardsByRarity(cards)
    local containedObjects = {}
    local boosterName = ""

    for _, card in ipairs(cards) do
        for i = 1, (card.count or 1) do
            local faces = card.faces or {{
                name = card.name,
                oracleText = "Card not found",
                imageURI = "https://vignette.wikia.nocookie.net/yugioh/images/9/94/Back-Anime-2.png/revision/latest?cb=20110624090942",
            }}

            -- Build the card JSON with States for multiple faces
            local jsonFace1 = jsonForCardFace(faces[1], position, 0, flipped)

            if #faces > 1 then
                jsonFace1.States = {}
                for j = 2, #faces do
                    local jsonFaceJ = jsonForCardFace(faces[j], position, 0, flipped)
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
            scaleZ = 1,
        },
        Nickname = boosterName .. bagName,
        Description = "",
        ColorDiffuse = {r=1, g=1, b=1},
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
            DiffuseURL = "https://i.imgur.com/mzM3sQ6.png",
            NormalURL = "http://i.imgur.com/pEN77ux.png",
            Convex = true,
            MaterialIndex = 0,
            TypeIndex = 6,
            CastShadows = true,

            specular_intensity = 0.3,       -- Moderate shine
            specular_color = { r = 0.95, g = 0.98, b = 1.0 }, -- Neutral white highlight
            specular_sharpness = 5,         -- Clean but not razor-sharp
            fresnel_strength = 0.2
        },
        ContainedObjects = containedObjects,
        LuaScript = [[
            function onLoad()
                self.addContextMenuItem("Crack the Pack", unloadAllCards)
            end

            function unloadAllCards(player_color, position, object)
                local objects = self.getObjects()
                local basePos = self.positionToWorld({0, 2, 0})
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
                    yOffset = yOffset + 0.35
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

    local bagObj = spawnObjectJSON({ json = JSON.encode(bagJSON) })

    if bagObj then
        onFullySpawned(bagObj)
    else
        if onError then onError("Failed to spawn custom bag") end
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
    elseif (not highres_image) or image_status != "highres_scan" then
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

    if data.layout == "transform" or data.layout == "art_series" or data.layout == "double_sided" or data.layout == "modal_dfc" or data.layout == "double_faced_token" then
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
    local function incSem() sem = sem + 1 end
    local function decSem() sem = sem - 1 end

    local tokens = {}
    local tokenDataForButtons = {}

    local function addToken(name, uri)
        incSem()

        WebRequest.get(uri, function(webReturn)
            if webReturn.is_error or webReturn.error or string.len(webReturn.text) == 0 then
                log("Error fetching token: " ..webReturn.error or "unknown")
                decSem()
                return
            end

            local success, data = pcall(function() return jsondecode(webReturn.text) end)
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
                back = back,
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
            elseif part.component and (string.sub(part.type_line,1,6) == "Emblem" and not (string.sub(data.type_line,1,6) == "Emblem")) then
                addToken("Emblem", part.uri)
            end
        end
    end

    local card = parseCardData(cardID, data)

    -- Store token data on each face
    for _, face in ipairs(card.faces) do
        face.tokenData = tokenDataForButtons
    end

    Wait.condition(
        function() onSuccess(card, tokens) end,
        function() return (sem == 0) end,
        30,
        function() onError("Error loading card data... timed out.") end
    )
end

-- Queries scryfall by the [cardID].
-- cardID must define at least one of scryfallID, multiverseID, or name.
-- if forceNameQuery is true, will query scryfall by card name ignoring other data.
-- if forceSetNumLangQuery is true, will query scryfall by set/num/lang ignoring other data.
-- onSuccess is called with a populated card table, and a table of associated tokens.
local function queryCard(cardID, forceNameQuery, forceSetNumLangQuery, onSuccess, onError)
    local query_url

    local language_code = getLanguageCode()

    if forceNameQuery then
        query_url = SCRYFALL_NAME_BASE_URL .. cardID.name
    elseif forceSetNumLangQuery then
        query_url = SCRYFALL_SET_NUM_BASE_URL .. string.lower(cardID.setCode) .. "/" .. cardID.collectorNum .. "/" .. language_code
    elseif cardID.scryfallID and string.len(cardID.scryfallID) > 0 then
        query_url = SCRYFALL_ID_BASE_URL .. cardID.scryfallID
    elseif cardID.multiverseID and string.len(cardID.multiverseID) > 0 then
        query_url = SCRYFALL_MULTIVERSE_BASE_URL .. cardID.multiverseID
    elseif cardID.setCode and string.len(cardID.setCode) > 0 and cardID.collectorNum and string.len(cardID.collectorNum) > 0 then
        query_url = SCRYFALL_SET_NUM_BASE_URL .. string.lower(cardID.setCode) .. "/" .. cardID.collectorNum .. "/" .. language_code
    elseif cardID.setCode and string.len(cardID.setCode) > 0 then
        query_string = "order:released s:" .. string.lower(cardID.setCode) .. " " .. cardID.name
        query_url = SCRYFALL_SEARCH_BASE_URL .. query_string
    else
        query_url = SCRYFALL_NAME_BASE_URL .. cardID.name
    end

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
        return string.match(collectorNum, "^%d+")
    end

    for _, cardID in ipairs(cards) do
        incSem()
        queryCard(
            cardID,
            false,
            false,
            function (card, tokens) -- onSuccess
                if card.language != language and
                   (forceLanguage or (not cardID.scryfallID and not cardID.multiverseID)) then
                  -- We got the wrong language, and should re-query.
                  -- We requery if forceLanguage is enabled, or if the printing wasn't specified directly

                  -- TODO currently we just hope that the target language is available in the printing
                  -- we found. If it doesn't, we miss other printings that might have the right language.
                  -- This isn't easily solveable, since TTS crashes if we try to do large scryfall queries.

                  cardID.setCode = card.setCode
                  cardID.collectorNum = card.collectorNum
                  queryCard(cardID, false, true, onQuerySuccess,
                    function(e) -- onError, use the original language
                        onQuerySuccess(card, tokens)
                    end)
                else
                    -- We got the right language
                    onQuerySuccess(card, tokens)
                end
            end,
            function(e) -- onError
                -- try again, with collecter num cleaned.
                log("query by name for cardid:" .. cardID.collectorNum)
                cardID.collectorNum = cleanCollectorNum(cardID.collectorNum)
                queryCard(
                    cardID,
                    false,
                    false,
                    onQuerySuccess,
                    onQueryFailed
                )
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
local function loadDeck(cardIDs, deckName, onComplete, onError)
    local baseMaindeckPos = self.positionToWorld(MAINDECK_POSITION_OFFSET)
    local sideboardPosition = self.positionToWorld(SIDEBOARD_POSITION_OFFSET)
    local maybeboardPosition = self.positionToWorld(MAYBEBOARD_POSITION_OFFSET)
    local commanderPosition = self.positionToWorld(COMMANDER_POSITION_OFFSET)
    local tokensPosition = self.positionToWorld(TOKENS_POSITION_OFFSET)

    printInfo("Querying Scryfall for card data...")

    fetchCardData(cardIDs, function(cards, tokens)
        local packs = {}          -- packIndex -> list of cards
        local sideboard = {}
        local maybeboard = {}
        local commander = {}

        -- Categorize cards
        for _, card in ipairs(cards) do
            if card.maybeboard then
                table.insert(maybeboard, card)
            elseif card.sideboard then
                table.insert(sideboard, card)
            elseif card.commander then
                table.insert(commander, card)
            else
                local packIndex = card.packIndex or 1
                if not packs[packIndex] then
                    packs[packIndex] = {}
                end
                table.insert(packs[packIndex], card)
            end
        end

        printInfo("Spawning deck...")

        local packCount = 0
        for _ in pairs(packs) do packCount = packCount + 1 end

        local sem = packCount + 4  -- packs + sideboard + maybeboard + commander + tokens
        local function decSem() sem = sem - 1 end

        -- Spawn each pack pile side by side
        for packIndex, cardGroup in pairs(packs) do
            print("Spawning pack" .. packIndex)
            local relativeOffset = {
                MAINDECK_POSITION_OFFSET[1] + (packIndex - 1) * POSITION_SPACING,
                MAINDECK_POSITION_OFFSET[2],
                MAINDECK_POSITION_OFFSET[3]
            }
            local offset = self.positionToWorld(relativeOffset)

            spawnBagWithCards(cardGroup, deckName .. " - Pack " .. packIndex, offset, true,
                function() decSem() end,
                function(e) printErr(e); decSem() end
            )
        end

        -- Spawn sideboard
        spawnDeck(sideboard, deckName .. " - sideboard", sideboardPosition, 0, true,
            function() decSem() end,
            function(e) printErr(e); decSem() end
        )

        -- Spawn maybeboard
        spawnDeck(maybeboard, deckName .. " - maybeboard", maybeboardPosition, 0, true,
            function() decSem() end,
            function(e) printErr(e); decSem() end
        )

        -- Spawn commander
        spawnDeck(commander, deckName .. " - commanders", commanderPosition, 0, false,
            function() decSem() end,
            function(e) printErr(e); decSem() end
        )

        -- Spawn tokens
        spawnDeck(tokens, deckName .. " - tokens", tokensPosition, 90, false,
            function() decSem() end,
            function(e) printErr(e); decSem() end
        )

        -- Wait for all spawns to finish
        Wait.condition(
            function() onComplete() end,
            function() return (sem == 0) end,
            10,
            function() onError("Error spawning deck objects... timed out.") end
        )
    end, onError)
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
        table.insert(cardList, {id = id, weight = weight})
    end

    local allowDuplicates = sheetData.allow_duplicates == true
    local drawnSet = {}  -- tracks which cards we've already drawn

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

    return setCode, collectorNum
end


local function queryGeneratePacks(numPacks, onSuccess, onError)
    local code = PackCode
    local packInfo = MagicSealedMap[code]

    if not packInfo then
        print("Unknown pack code: " .. tostring(code))
        lock = false
        return
    end

    local allCards = {}

    for packIndex = 1, numPacks do
        local boosterLayout = pickWeighted(packInfo.boosters)

        for sheetName, count in pairs(boosterLayout.sheets) do
            local drawn = drawCardsFromSheet(packInfo.sheets[sheetName], count)

            for _, rawId in ipairs(drawn) do
                local setCode, collectorNum = parseCardId(rawId)

                table.insert(allCards, {
                    count = 1,
                    name = "",
                    setCode = setCode,
                    collectorNum = collectorNum,
                    sideboard = false,
                    commander = false,
                    packIndex = packIndex,
                    sheetName = sheetName,
                    packName = packInfo.name
                })
            end
        end
    end

    onSuccess(allCards, "")
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

        queryGeneratePacks(numberOfPacks,
            function(cardIDs, deckName)
                loadDeck(cardIDs, deckName,
                    function()
                        printToAll("Deck import complete!")
                        lock = false
                    end,
                    function(e)
                        printToAll("Deck load error: " .. tostring(e))
                        lock = false
                    end
                )
            end,
            function(e)
                printToAll("Query error: " .. tostring(e))
                lock = false
            end
        )
    end)

    if not success then
        printToAll("Pack generation failed: " .. tostring(err))
        lock = false
    end

    return 1
end

MagicSealedData = nil

--Load Booster stats
local function queryMagicSealedData()
    local url = PACK_ODDS_URL
    WebRequest.get(url, function(webReturn)
        if webReturn.error then
            onError("Web request error: " .. webReturn.error)
            return
        elseif webReturn.is_error then
            onError("Web request error: unknown")
            return
        elseif string.len(webReturn.text) == 0 then
            onError("Web request error: empty response")
            return
        end

        local success, data = pcall(function() return jsondecode(webReturn.text) end)
        if not success then
            onError("Failed to parse JSON response from Magic Sealed Data.")
            return
        elseif not data then
            onError("Empty response from Magic Sealed Data.")
            return
        end

        -- Store in global variable
        MagicSealedData = data
        MagicSealedMap = {}

        -- Index by code for quick lookup
        for _, entry in ipairs(data) do
            MagicSealedMap[entry.code] = entry
        end

        print("Magic Sealed Data loaded successfully.")

    end)
    
end

local function waitUntilDataReady(callback)
    Wait.condition(
        function() callback(MagicSealedData) end,
        function() return MagicSealedData ~= nil end
    )
end


local function buildDropdownFromData()
    local optionsXml = ""

    for i, entry in ipairs(MagicSealedData) do
        local selectedStr = ""
        if i == 1 then -- first option selected by default
            selectedStr = ' selected="true"'
            PackCode = entry.code -- also update your global var for the default
        end
        optionsXml = optionsXml .. string.format(
            '<Option value="%s"%s>%s</Option>',
            entry.code,   -- value attribute for code
            selectedStr,  -- add selected attribute if default
            entry.name    -- label
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

function onDropdownChanged(player, value, id)
    print("Dropdown changed. Received value:", value)
    -- Map name (label) back to code
    for _, entry in ipairs(MagicSealedData) do
        if entry.name == value then
            PackCode = entry.code
            -- print("Resolved PackCode:", PackCode)
            return
        end
    end
end


function onLoadPacksButton(_,pc,_)
    printToAll("Loading pack list...")
    queryMagicSealedData()
    waitUntilDataReady(function(data)
        self.removeButton(0)
        buildDropdownFromData()
    end)
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
                input.value = val  -- update input to reflect clamp
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
    
    if MagicSealedData == nil then
        self.createButton({
            click_function = "onLoadPacksButton",
            function_owner = self,
            label          = "Load Booster List",
            position       = {0, 0.1, -1.15},
            rotation       = {0, 0, 0},
            width          = 850,
            height         = 160,
            font_size      = 80,
            color          = {0.5, 0.5, 0.5},
            font_color     = {r=1, b=1, g=1},
            tooltip        = "Click to load packs from the Internet (Freezes the Game for a Minute!)",
        })
    end

    self.createInput({
        input_function = "onPackAmountInput",
        function_owner = self,
        label          = "Enter the Amount of Packs",
        alignment      = 2,
        position       = {-0.4, 0.1, 1.15},
        width          = 240,
        height         = 160,
        font_size      = 130,
        validation     = 2,
        value = packAmount,
    })


    self.createButton({
        click_function = "onGeneratePackButton",
        function_owner = self,
        label          = "Generate Packs",
        position       = {1, 0.1, 1.15},
        rotation       = {0, 0, 0},
        width          = 850,
        height         = 160,
        font_size      = 80,
        color          = {0.5, 0.5, 0.5},
        font_color     = {r=1, b=1, g=1},
        tooltip        = "Click to generate your packs",
    })

    self.createButton({
        click_function = "onToggleAdvancedButton",
        function_owner = self,
        label          = "...",
        position       = {2.25, 0.1, 1.15},
        rotation       = {0, 0, 0},
        width          = 160,
        height         = 160,
        font_size      = 100,
        color          = {0.5, 0.5, 0.5},
        font_color     = {r=1, b=1, g=1},
        tooltip        = "Click to open advanced menu",
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

function mtgdl__onTokenButtonsInput(_, value, _)
    enableTokenButtons = stringToBool(value)
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

    self.setDescription(
        [[
    Click on Load Booster List,
    Select the Booster you want.
    Type in the number of Boosters and click
    Generate Packs to get your Boosters.
    ]])

    math.randomseed(os.time())

    drawUI()
end