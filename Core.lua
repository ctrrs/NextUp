local addonName, NextUp = ...
-- Not mixing in "AceEvent-3.0": its global frame "AceEvent30Frame" gets
-- attributed to whichever addon loads it first, so every other AceEvent
-- consumer's dispatch shows up under that addon in the profiler. Use a
-- private CreateFrame shim below to keep self:RegisterEvent working without
-- touching the global frame.
NextUp = LibStub("AceAddon-3.0"):NewAddon(NextUp, addonName, "AceConsole-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local ACD = LibStub("AceConfigDialog-3.0")

-- Private event-frame shim. Drop-in for the AceEvent mixin we removed above.
do
    local eventFrame = CreateFrame("Frame")
    local handlers = {}

    function NextUp:RegisterEvent(event, handlerName)
        eventFrame:RegisterEvent(event)
        handlers[event] = handlerName or event
    end

    function NextUp:UnregisterEvent(event)
        eventFrame:UnregisterEvent(event)
        handlers[event] = nil
    end

    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local h = handlers[event]
        if h and NextUp[h] then NextUp[h](NextUp, event, ...) end
    end)
end

-- Local references
local GetTime = GetTime
local format = string.format
local floor, ceil = math.floor, math.ceil
local tinsert, sort, wipe = table.insert, table.sort, _G.wipe
local IsInInstance = IsInInstance

-- Expanded Vibrant/Neon Palette
local PREDEFINED_COLORS = {
    {r = 1.00, g = 0.00, b = 0.40}, {r = 1.00, g = 0.40, b = 0.00}, {r = 1.00, g = 1.00, b = 0.00},
    {r = 0.00, g = 1.00, b = 0.20}, {r = 0.00, g = 1.00, b = 1.00}, {r = 0.20, g = 0.40, b = 1.00},
    {r = 0.60, g = 0.00, b = 1.00}, {r = 1.00, g = 0.00, b = 1.00}, {r = 1.00, g = 0.30, b = 0.30},
    {r = 0.00, g = 0.80, b = 0.80}, {r = 0.70, g = 1.00, b = 0.00}, {r = 1.00, g = 0.80, b = 0.00},
    {r = 1.00, g = 0.10, b = 0.10}, {r = 0.10, g = 1.00, b = 0.60}, {r = 0.50, g = 0.80, b = 1.00},
    {r = 0.90, g = 0.60, b = 1.00}, {r = 0.20, g = 1.00, b = 0.20}, {r = 1.00, g = 0.60, b = 0.20},
    {r = 0.40, g = 0.40, b = 1.00}, {r = 1.00, g = 0.20, b = 0.70},
}

-- Configuration Defaults
local defaults = {
    profile = {
        fontSize = 24,
        fontName = "Expressway",
        outline = "OUTLINE",
        shadow = false,
        textFormat = "in",
        showDecimals = true,
        decimalThreshold = 10,
        colorLogic = "semantic",
        colorMode = "random",
        fixedColor = {r = 1, g = 1, b = 1, a = 1},
        posX = 0,
        posY = 115,
        maxTimers = 1,
        growthDirection = "up",
        threshold = 15,
        enableInRaid = true,
        enableInDungeon = true,
        enableInWorld = true,
    }
}

-- Helper to convert RGB to Hex
local function RGBToHex(r, g, b)
    return format("%02x%02x%02x", floor((r or 1)*255), floor((g or 1)*255), floor((b or 1)*255))
end

-- Display Frames
local mainFrame = CreateFrame("Frame", "NextUpMainFrame", UIParent)
mainFrame:SetSize(1, 1)
mainFrame:Hide()

local ticker = CreateFrame("Frame")
ticker:Hide()

local timerLines = {}
local activeBars = {}
local sortedKeys = {}
local barCounter = 0
NextUp.testMode = false

-- Zone Check
function NextUp:IsAllowedInZone()
    if self.testMode then return true end
    local _, instanceType = IsInInstance()
    local db = self.db.profile
    if instanceType == "raid" then return db.enableInRaid end
    if instanceType == "party" then return db.enableInDungeon end
    if instanceType == "none" then return db.enableInWorld end
    return true
end

-- 1. REFRESH LAYOUT
function NextUp:RefreshLayout()
    if not self.db then return end
    if not self:IsAllowedInZone() then
        mainFrame:Hide()
        ticker:Hide()
        return
    end

    local db = self.db.profile
    local now = GetTime()
    
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
    
    local fontPath = LSM:Fetch("font", db.fontName) or "Fonts\\FRIZQT__.TTF"
    
    wipe(sortedKeys)
    for key, data in pairs(activeBars) do
        local remaining = data.expiration - now
        if remaining > 0 and remaining <= db.threshold then
            tinsert(sortedKeys, key)
        elseif remaining <= 0 then
            activeBars[key] = nil
        end
    end
    
    sort(sortedKeys, function(a, b)
        return activeBars[a].expiration < activeBars[b].expiration
    end)
    
    for i = 1, 5 do
        if not timerLines[i] then
            timerLines[i] = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        end
        local line = timerLines[i]
        line:SetFont(fontPath, db.fontSize, db.outline ~= "NONE" and db.outline or "")
        if db.shadow then
            line:SetShadowColor(0, 0, 0, 1)
            line:SetShadowOffset(1, -1)
        else
            line:SetShadowColor(0, 0, 0, 0)
            line:SetShadowOffset(0, 0)
        end
        
        line:ClearAllPoints()
        local yOffset = (i - 1) * (db.fontSize + 5)
        if db.growthDirection == "down" then
            line:SetPoint("CENTER", mainFrame, "CENTER", 0, -yOffset)
        else
            line:SetPoint("CENTER", mainFrame, "CENTER", 0, yOffset)
        end
        line:Hide()
    end

    if #sortedKeys > 0 or self.testMode then
        mainFrame:Show()
        ticker:Show()
    else
        mainFrame:Hide()
        ticker:Hide()
    end
end

-- 2. DRAW UPDATE
local lastUpdate = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    lastUpdate = lastUpdate + elapsed
    if lastUpdate < 0.033 then return end
    lastUpdate = 0
    
    local now = GetTime()
    local db = NextUp.db.profile
    local needsLayout = false

    -- Self-Regulating Internal Test Mode
    if NextUp.testMode then
        local currentTestBars = 0
        for i=1,3 do if activeBars["NextUp_Test"..i] then currentTestBars = currentTestBars + 1 end end
        
        if currentTestBars < 3 then
            for i=1,3 do
                local key = "NextUp_Test"..i
                if not activeBars[key] then
                    activeBars[key] = {
                        text = "Test Mechanic "..i,
                        expiration = now + (i * 7) + math.random(5),
                        color = PREDEFINED_COLORS[math.random(#PREDEFINED_COLORS)],
                        module = "INTERNAL"
                    }
                    needsLayout = true
                end
            end
        end
    end

    -- Process Expired
    for key, data in pairs(activeBars) do
        if (data.expiration - now) <= 0 then
            activeBars[key] = nil
            needsLayout = true
        end
    end

    if needsLayout then NextUp:RefreshLayout() end

    -- Render Loop
    local activeCount = 0
    for i = 1, 5 do
        local key = sortedKeys[i]
        local line = timerLines[i]
        if key and i <= db.maxTimers and activeBars[key] then
            local data = activeBars[key]
            local remaining = data.expiration - now
            if remaining > 0 then
                local connector = db.textFormat == "in" and " in " or ": "
                local timeString = (db.showDecimals and remaining <= db.decimalThreshold) and format("%.1fs", remaining) or format("%ds", ceil(remaining))

                if db.colorLogic == "semantic" then
                    local nameHex = (db.colorMode == "fixed") and RGBToHex(db.fixedColor.r, db.fixedColor.g, db.fixedColor.b) or RGBToHex(data.color.r, data.color.g, data.color.b)
                    local timeHex = "ffffff"
                    if remaining <= 2 then timeHex = "ff0000" elseif remaining <= 5 then timeHex = "ff9900" end
                    line:SetText(format("|cff%s%s|r|cffffffff%s|r|cff%s%s|r", nameHex, data.text, connector, timeHex, timeString))
                else
                    line:SetText(format("%s%s%s", data.text, connector, timeString))
                    if db.colorMode == "fixed" then
                        line:SetTextColor(db.fixedColor.r, db.fixedColor.g, db.fixedColor.b, db.fixedColor.a)
                    else
                        line:SetTextColor(data.color.r, data.color.g, data.color.b)
                    end
                end
                line:Show()
                activeCount = activeCount + 1
            end
        elseif line then
            line:Hide()
        end
    end

    if activeCount == 0 and not NextUp.testMode then
        mainFrame:Hide()
        ticker:Hide()
    end
end)

-- BigWigs Callbacks
function NextUp:BigWigs_StartBar(event, module, key, barText, time)
    local actualModule, actualKey, actualText, actualTime
    if type(event) == "string" and event:find("BigWigs_") then
        actualModule, actualKey, actualText, actualTime = module, key, barText, time
    else
        actualModule, actualKey, actualText, actualTime = event, module, key, barText
    end

    -- In WoW 12.0+ instances, spell names (barText) are secret values and cannot
    -- be used as table keys or in string.format. Build safe key and display text.
    local finalKey
    if actualKey ~= nil and not issecretvalue(actualKey) then
        finalKey = actualKey
    elseif actualText ~= nil and not issecretvalue(actualText) then
        finalKey = actualText
    else
        barCounter = barCounter + 1
        finalKey = "bar_" .. barCounter
    end

    local displayText
    if actualText ~= nil and not issecretvalue(actualText) then
        displayText = actualText
    elseif actualKey ~= nil and not issecretvalue(actualKey) then
        displayText = tostring(actualKey)
    else
        displayText = "?"
    end

    activeBars[finalKey] = {
        text = displayText,
        expiration = GetTime() + (tonumber(actualTime) or 0),
        color = PREDEFINED_COLORS[math.random(#PREDEFINED_COLORS)],
        module = actualModule
    }
    self:RefreshLayout()
end

function NextUp:BigWigs_StopBar(event, module, key)
    local k = (type(event) == "string" and event:find("BigWigs_")) and key or module
    -- Secret keys can't be looked up; bar will expire naturally
    if k ~= nil and not issecretvalue(k) and activeBars[k] then
        activeBars[k] = nil
        self:RefreshLayout()
    end
end

-- Clear all bars for a specific module or generic test stop
function NextUp:BigWigs_StopBars(event, module)
    local targetModule = (type(event) == "string" and event:find("BigWigs_")) and module or event
    local needsRefresh = false
    for k, v in pairs(activeBars) do
        if v.module == targetModule or targetModule == "Test" then
            activeBars[k] = nil
            needsRefresh = true
        end
    end
    if needsRefresh then self:RefreshLayout() end
end

-- Emergency cleanup for victory/defeat/test disable
function NextUp:BigWigs_OnBossCleanup()
    for k, v in pairs(activeBars) do
        if v.module ~= "INTERNAL" then
            activeBars[k] = nil
        end
    end
    self:RefreshLayout()
end

-- Options Table
local function GetOptions()
    return {
        name = "|cff00ff00Next Up|r Settings",
        type = "group",
        args = {
            description = { type = "description", name = "Minimalist BigWigs timer display. All settings applied instantly.\n", order = 1 },
            testGroup = {
                name = "Testing Tools",
                type = "group",
                inline = true,
                order = 2,
                args = {
                    testMode = {
                        name = function() return NextUp.testMode and "STOP TEST" or "START TEST" end,
                        type = "execute",
                        func = function()
                            NextUp.testMode = not NextUp.testMode
                            if not NextUp.testMode then
                                for i = 1, 3 do activeBars["NextUp_Test" .. i] = nil end
                            end
                            NextUp:RefreshLayout()
                        end,
                        width = 1.8,
                        order = 1,
                    },
                    openBW = {
                        name = "OPEN BIGWIGS",
                        type = "execute",
                        func = function()
                            if _G.SlashCmdList["BigWigs"] then _G.SlashCmdList["BigWigs"]("")
                            elseif _G.SlashCmdList["BW"] then _G.SlashCmdList["BW"]("") end
                        end,
                        width = 1.8,
                        order = 2,
                    },
                }
            },
            visibilityGroup = {
                name = "Visibility & Content",
                type = "group",
                inline = true,
                order = 5,
                args = {
                    enableInRaid = {
                        name = "Enable in Raids",
                        type = "toggle",
                        get = function() return NextUp.db.profile.enableInRaid end,
                        set = function(_, v) NextUp.db.profile.enableInRaid = v; NextUp:RefreshLayout() end,
                        order = 1,
                    },
                    enableInDungeon = {
                        name = "Enable in Dungeons",
                        type = "toggle",
                        get = function() return NextUp.db.profile.enableInDungeon end,
                        set = function(_, v) NextUp.db.profile.enableInDungeon = v; NextUp:RefreshLayout() end,
                        order = 2,
                    },
                    enableInWorld = {
                        name = "Enable in Open World",
                        type = "toggle",
                        get = function() return NextUp.db.profile.enableInWorld end,
                        set = function(_, v) NextUp.db.profile.enableInWorld = v; NextUp:RefreshLayout() end,
                        order = 3,
                    },
                }
            },
            textGroup = {
                name = "Text Customization",
                type = "group",
                inline = true,
                order = 10,
                args = {
                    fontName = {
                        name = "Font Family",
                        type = "select",
                        dialogControl = 'LSM30_Font',
                        values = LSM:HashTable("font"),
                        get = function() return NextUp.db.profile.fontName end,
                        set = function(_, v) NextUp.db.profile.fontName = v; NextUp:RefreshLayout() end,
                        order = 1,
                    },
                    fontSize = {
                        name = "Font Size",
                        type = "range",
                        min = 10, max = 120, step = 1,
                        get = function() return NextUp.db.profile.fontSize end,
                        set = function(_, v) NextUp.db.profile.fontSize = v; NextUp:RefreshLayout() end,
                        order = 2,
                    },
                    outline = {
                        name = "Outline",
                        type = "select",
                        values = {["NONE"] = "None", ["OUTLINE"] = "Thin", ["THICKOUTLINE"] = "Thick"},
                        get = function() return NextUp.db.profile.outline end,
                        set = function(_, v) NextUp.db.profile.outline = v; NextUp:RefreshLayout() end,
                        order = 3,
                    },
                    shadow = {
                        name = "Shadow",
                        type = "toggle",
                        get = function() return NextUp.db.profile.shadow end,
                        set = function(_, v) NextUp.db.profile.shadow = v; NextUp:RefreshLayout() end,
                        order = 4,
                    },
                    textFormat = {
                        name = "Format Style",
                        type = "select",
                        values = {["colon"] = "Name: 10s", ["in"] = "Name in 10s"},
                        get = function() return NextUp.db.profile.textFormat end,
                        set = function(_, v) NextUp.db.profile.textFormat = v end,
                        order = 5,
                    },
                    showDecimals = {
                        name = "Enable Decimals",
                        type = "toggle",
                        get = function() return NextUp.db.profile.showDecimals end,
                        set = function(_, v) NextUp.db.profile.showDecimals = v end,
                        order = 6,
                    },
                    decimalThreshold = {
                        name = "Decimal Threshold (Seconds)",
                        type = "range",
                        min = 0, max = 15, step = 0.5,
                        get = function() return NextUp.db.profile.decimalThreshold end,
                        set = function(_, v) NextUp.db.profile.decimalThreshold = v end,
                        disabled = function() return not NextUp.db.profile.showDecimals end,
                        order = 7,
                        width = "full",
                    },
                }
            },
            colorGroup = {
                name = "Color Settings",
                type = "group",
                inline = true,
                order = 20,
                args = {
                    colorLogic = {
                        name = "Coloring Logic",
                        type = "select",
                        values = {["uniform"] = "Uniform Color", ["semantic"] = "Multicolor (Alerts)"},
                        get = function() return NextUp.db.profile.colorLogic end,
                        set = function(_, v) NextUp.db.profile.colorLogic = v end,
                        order = 1,
                    },
                    colorMode = {
                        name = "Name Color Mode",
                        type = "select",
                        values = {["fixed"] = "Fixed Color", ["random"] = "Random Color (Vibrant Palette)"},
                        get = function() return NextUp.db.profile.colorMode end,
                        set = function(_, v) NextUp.db.profile.colorMode = v end,
                        order = 2,
                    },
                    fixedColor = {
                        name = "Select Name Color",
                        type = "color",
                        hasAlpha = true,
                        get = function() 
                            local c = NextUp.db.profile.fixedColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a) 
                            NextUp.db.profile.fixedColor = {r=r, g=g, b=b, a=a}
                        end,
                        disabled = function() return NextUp.db.profile.colorMode ~= "fixed" end,
                        order = 3,
                    },
                }
            },
            displayGroup = {
                name = "Display Rules",
                type = "group",
                inline = true,
                order = 30,
                args = {
                    maxTimers = {
                        name = "Max Timers",
                        type = "range",
                        min = 1, max = 5, step = 1,
                        get = function() return NextUp.db.profile.maxTimers end,
                        set = function(_, v) NextUp.db.profile.maxTimers = v; NextUp:RefreshLayout() end,
                        order = 1,
                    },
                    growthDirection = {
                        name = "Growth Direction",
                        type = "select",
                        values = {["up"] = "Grow Upwards", ["down"] = "Grow Downwards"},
                        get = function() return NextUp.db.profile.growthDirection end,
                        set = function(_, v) NextUp.db.profile.growthDirection = v; NextUp:RefreshLayout() end,
                        order = 2,
                    },
                    threshold = {
                        name = "Visibility Threshold (Seconds)",
                        type = "range",
                        min = 1, max = 30, step = 1,
                        get = function() return NextUp.db.profile.threshold end,
                        set = function(_, v) NextUp.db.profile.threshold = v; NextUp:RefreshLayout() end,
                        width = "full",
                        order = 3,
                    },
                }
            },
            positionGroup = {
                name = "Screen Position",
                type = "group",
                inline = true,
                order = 40,
                args = {
                    posX = {
                        name = "Horizontal (X Offset)",
                        type = "range",
                        min = -floor(GetScreenWidth()/2), max = floor(GetScreenWidth()/2), step = 1,
                        get = function() return NextUp.db.profile.posX end,
                        set = function(_, v) NextUp.db.profile.posX = v; NextUp:RefreshLayout() end,
                        width = "full",
                        order = 1,
                    },
                    posY = {
                        name = "Vertical (Y Offset)",
                        type = "range",
                        min = -floor(GetScreenHeight()/2), max = floor(GetScreenHeight()/2), step = 1,
                        get = function() return NextUp.db.profile.posY end,
                        set = function(_, v) NextUp.db.profile.posY = v; NextUp:RefreshLayout() end,
                        width = "full",
                        order = 2,
                    },
                }
            },
            dangerGroup = {
                name = "Danger Zone",
                type = "group",
                inline = true,
                order = 100,
                args = {
                    reset = {
                        name = "Reset to Defaults",
                        type = "execute",
                        desc = "Revert all settings to the factory defaults. This will reload the UI.",
                        func = function() StaticPopup_Show("NEXTUP_CONFIRM_RESET") end,
                        width = "full",
                        order = 1,
                    },
                }
            }
        }
    }
end

StaticPopupDialogs["NEXTUP_CONFIRM_RESET"] = {
    text = "Are you sure you want to reset Next Up settings to defaults? This will reload the UI.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        NextUpDB = {}
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function NextUp:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("NextUpDB", defaults, true)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("NextUp", GetOptions)
    self:RegisterChatCommand("nextup", "OpenMenu")
    self:RegisterChatCommand("nu", "OpenMenu")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "RefreshLayout")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshLayout")
    self:RefreshLayout()
end

function NextUp:OpenMenu()
    if ACD.OpenFrames["NextUp"] then ACD:Close("NextUp") else ACD:Open("NextUp") end
end

function NextUp:OnEnable()
    if BigWigsLoader then
        BigWigsLoader.RegisterMessage(self, "BigWigs_StartBar")
        BigWigsLoader.RegisterMessage(self, "BigWigs_StopBar")
        BigWigsLoader.RegisterMessage(self, "BigWigs_StopBars")
        BigWigsLoader.RegisterMessage(self, "BigWigs_OnBossWin", "BigWigs_OnBossCleanup")
        BigWigsLoader.RegisterMessage(self, "BigWigs_OnBossWipe", "BigWigs_OnBossCleanup")
        BigWigsLoader.RegisterMessage(self, "BigWigs_OnTestStop", "BigWigs_OnBossCleanup")
        BigWigsLoader.RegisterMessage(self, "BigWigs_OnTestDisable", "BigWigs_OnBossCleanup")
        BigWigsLoader.RegisterMessage(self, "BigWigs_OnBossDisable", "BigWigs_OnBossCleanup")
    end
end
