local ADDON_NAME = ...

local MAP_ID = 2395
local ARCANA_ITEM_ID = 242241
local REFRESH_SECONDS = 2

local RUNESTONES = {
    { name = "Elrendar River Runestone", x = 0.4736, y = 0.5864 },
    { name = "Ath'ran Runestone", x = 0.3913, y = 0.5685 },
    { name = "Dawnstar Spire Runestone", x = 0.6176, y = 0.6172 },
    { name = "Sanctum of the Moon Runestone", x = 0.4115, y = 0.7381 },
    { name = "Sunstrider Isle Runestone", x = 0.4046, y = 0.1359 },
}

local frame, locationText, stateText, arcanaText, progressBar, progressText
local db
local elapsedSinceRefresh = 0
local debugNextScan = false

local function Strip(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    value = value:gsub("|H.-|h(.-)|h", "%1")
    value = value:gsub("\r", ""):gsub("\n+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return value ~= "" and value or nil
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint()
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
end

local function ApplyLockState()
    frame:EnableMouse(not db.locked)
    if db.locked then
        frame:RegisterForDrag()
    else
        frame:RegisterForDrag("LeftButton")
    end
end

local function ArcanaCount()
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(ARCANA_ITEM_ID, false, false, false) or 0
    end
    return GetItemCount(ARCANA_ITEM_ID, false, false, false) or 0
end

local function PositionXY(position)
    if not position then return nil, nil end
    if position.GetXY then return position:GetXY() end
    return position.x, position.y
end

local function NearestRunestone(position)
    local x, y = PositionXY(position)
    if not x or not y then return "Unknown Runestone" end

    local nearest, bestDistance
    for _, stone in ipairs(RUNESTONES) do
        local dx, dy = x - stone.x, y - stone.y
        local distance = dx * dx + dy * dy
        if not bestDistance or distance < bestDistance then
            nearest, bestDistance = stone, distance
        end
    end
    return nearest.name
end

local function CollectStrings(value, output, seen, depth)
    depth = depth or 0
    if depth > 5 then return end

    if type(value) == "string" then
        local text = Strip(value)
        if text and not seen[text] then
            seen[text] = true
            table.insert(output, text)
        end
        return
    end

    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        if type(child) == "string" then
            local keyText = type(key) == "string" and key:lower() or ""
            if keyText:find("text") or keyText:find("tooltip") or keyText:find("title")
                or keyText:find("description") or keyText:find("state") or keyText:find("label") then
                CollectStrings(child, output, seen, depth + 1)
            end
        elseif type(child) == "table" then
            CollectStrings(child, output, seen, depth + 1)
        end
    end
end

local function FindProgress(value, seen, depth)
    depth = depth or 0
    if depth > 5 or type(value) ~= "table" or seen[value] then return nil end
    seen[value] = true

    local pairsToCheck = {
        { "barValue", "barMax" },
        { "currentValue", "maxValue" },
        { "value", "maxValue" },
    }

    for _, fields in ipairs(pairsToCheck) do
        local current, maximum = value[fields[1]], value[fields[2]]
        if type(current) == "number" and type(maximum) == "number" and maximum > 0 then
            return current, maximum
        end
    end

    for _, child in pairs(value) do
        if type(child) == "table" then
            local current, maximum = FindProgress(child, seen, depth + 1)
            if current then return current, maximum end
        end
    end
end

local function WidgetVisualization(widget)
    if not C_UIWidgetManager then return nil end
    for name, getter in pairs(C_UIWidgetManager) do
        if type(name) == "string" and type(getter) == "function" and name:match("^Get.+VisualizationInfo$") then
            local ok, result = pcall(getter, widget.widgetID)
            if ok and type(result) == "table" then return result end
        end
    end
end

local function WidgetDetails(widgetSetID)
    local lines, seen = {}, {}
    local progressCurrent, progressMaximum
    if not widgetSetID or not C_UIWidgetManager or not C_UIWidgetManager.GetAllWidgetsBySetID then
        return lines
    end

    local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(widgetSetID)
    for _, widget in ipairs(widgets or {}) do
        local info = WidgetVisualization(widget)
        if info then
            CollectStrings(info, lines, seen, 0)
            if not progressCurrent then
                progressCurrent, progressMaximum = FindProgress(info, {}, 0)
            end
        end
    end
    return lines, progressCurrent, progressMaximum
end

local function ChooseState(poi)
    local lines = {}
    if Strip(poi.description) then table.insert(lines, Strip(poi.description)) end

    local widgetLines, current, maximum = WidgetDetails(poi.tooltipWidgetSet)
    for _, line in ipairs(widgetLines) do table.insert(lines, line) end

    local best, bestScore = "Runestone marker detected.", -1
    for _, line in ipairs(lines) do
        local lower = line:lower()
        local score = #line
        if lower == "runestone" or lower == "runestone state" or lower == "runestone state:" then
            score = -1
        elseif lower:find("latent arcana", 1, true) then
            score = score + 1000
        elseif lower:find("charg", 1, true) or lower:find("defend", 1, true)
            or lower:find("attack", 1, true) or lower:find("active", 1, true) then
            score = score + 500
        end
        if score > bestScore then best, bestScore = line, score end
    end
    return best, current, maximum, lines
end

local function AreaPoiIDs()
    local ids, seen = {}, {}
    for _, getter in ipairs({ C_AreaPoiInfo.GetAreaPOIForMap, C_AreaPoiInfo.GetEventsForMap }) do
        if getter then
            local ok, results = pcall(getter, MAP_ID)
            if ok then
                for _, id in ipairs(results or {}) do
                    if not seen[id] then seen[id] = true; table.insert(ids, id) end
                end
            end
        end
    end
    return ids
end

local function FindActiveRunestone()
    local best, bestScore
    for _, id in ipairs(AreaPoiIDs()) do
        local poi = C_AreaPoiInfo.GetAreaPOIInfo(MAP_ID, id)
        local name = poi and Strip(poi.name)
        if name and name:lower():find("runestone", 1, true) then
            local state, current, maximum, lines = ChooseState(poi)
            local lower = state:lower()
            local score = (poi.isCurrentEvent and 100 or 0) + (poi.shouldGlow and 50 or 0)
            if poi.tooltipWidgetSet then score = score + 25 end
            if lower:find("charg", 1, true) or lower:find("defend", 1, true)
                or lower:find("attack", 1, true) or lower:find("active", 1, true) then
                score = score + 200
            end
            if not bestScore or score > bestScore then
                bestScore = score
                best = { poi = poi, state = state, current = current, maximum = maximum, lines = lines }
            end
        end
    end
    return best
end

local function SetProgress(current, maximum)
    if current and maximum and maximum > 0 then
        progressBar:SetMinMaxValues(0, maximum)
        progressBar:SetValue(current)
        progressText:SetFormattedText("%.0f / %.0f (%.0f%%)", current, maximum, current / maximum * 100)
        progressBar:Show()
        frame:SetHeight(110)
    else
        progressBar:Hide()
        frame:SetHeight(86)
    end
end

local function UpdateDisplay()
    if not frame then return end
    arcanaText:SetFormattedText("Arcana: %d", ArcanaCount())

    local result = FindActiveRunestone()
    if result then
        locationText:SetText("Active: " .. NearestRunestone(result.poi.position))
        stateText:SetText(result.state)
        local lower = result.state:lower()
        if lower:find("defend", 1, true) or lower:find("attack", 1, true) then
            stateText:SetTextColor(1, 0.45, 0.2)
        elseif lower:find("charg", 1, true) or lower:find("arcana", 1, true) then
            stateText:SetTextColor(1, 0.82, 0.2)
        else
            stateText:SetTextColor(0.85, 0.85, 0.85)
        end
        SetProgress(result.current, result.maximum)

        if debugNextScan then
            print("|cff33ff99Runestone Tracker:|r POI " .. tostring(result.poi.areaPoiID))
            for i, line in ipairs(result.lines or {}) do print("  [" .. i .. "] " .. line) end
            debugNextScan = false
        end
    else
        locationText:SetText("Active: Not detected")
        stateText:SetText("No active runestone marker is currently available on the Eversong Woods map.")
        stateText:SetTextColor(0.65, 0.65, 0.65)
        SetProgress()
    end

    frame:SetShown(db.shown)
end

local function CreateTracker()
    frame = CreateFrame("Frame", "RunestoneTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(390, 86)
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 180)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.04, 0.04, 0.04, 0.92)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    frame:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + elapsed
        if elapsedSinceRefresh >= REFRESH_SECONDS then elapsedSinceRefresh = 0; UpdateDisplay() end
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Runestone Tracker")

    arcanaText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arcanaText:SetPoint("TOPRIGHT", -10, -9)

    locationText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    locationText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
    locationText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    locationText:SetJustifyH("LEFT")

    stateText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stateText:SetPoint("TOPLEFT", locationText, "BOTTOMLEFT", 0, -5)
    stateText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    stateText:SetJustifyH("LEFT")
    stateText:SetWordWrap(true)

    progressBar = CreateFrame("StatusBar", nil, frame)
    progressBar:SetPoint("BOTTOMLEFT", 10, 10)
    progressBar:SetPoint("BOTTOMRIGHT", -10, 10)
    progressBar:SetHeight(16)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.85, 0.65, 0.15)
    local background = progressBar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(0.12, 0.12, 0.12, 1)
    progressText = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("CENTER")

    ApplyLockState()
    UpdateDisplay()
end

local function Help()
    print("|cff33ff99Runestone Tracker commands:|r")
    print("/rst show, hide, toggle, lock, unlock, reset, scan, debug")
end

local function SlashCommand(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "show" then db.shown = true; UpdateDisplay()
    elseif command == "hide" then db.shown = false; frame:Hide()
    elseif command == "toggle" then db.shown = not db.shown; frame:SetShown(db.shown)
    elseif command == "lock" then db.locked = true; ApplyLockState(); print("|cff33ff99Runestone Tracker:|r locked.")
    elseif command == "unlock" then db.locked = false; ApplyLockState(); print("|cff33ff99Runestone Tracker:|r unlocked.")
    elseif command == "reset" then frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180); SavePosition()
    elseif command == "scan" then UpdateDisplay()
    elseif command == "debug" then debugNextScan = true; UpdateDisplay()
    else Help() end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "AREA_POIS_UPDATED", "UPDATE_ALL_UI_WIDGETS", "UPDATE_UI_WIDGET", "BAG_UPDATE_DELAYED", "ZONE_CHANGED_NEW_AREA" }) do
    events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        RunestoneTrackerDB = RunestoneTrackerDB or {}
        db = RunestoneTrackerDB
        if db.shown == nil then db.shown = true end
        if db.locked == nil then db.locked = false end
        CreateTracker()
        SLASH_RUNESTONETRACKER1 = "/rst"
        SLASH_RUNESTONETRACKER2 = "/runestonetracker"
        SlashCmdList.RUNESTONETRACKER = SlashCommand
        C_Timer.After(1, UpdateDisplay)
    elseif frame then
        C_Timer.After(0.1, UpdateDisplay)
    end
end)
