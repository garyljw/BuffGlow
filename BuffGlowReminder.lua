-- BuffGlow Reminder
-- * Your player portrait glows when you're missing a long buff you can cast on yourself.
-- * Your target's nameplate (and target portrait) glows when a friendly player is
--   missing a buff you can give them.
-- * The glow is coloured like the buff's icon. If several buffs are missing, the
--   colour changes on each pulse (e.g. white -> gold for Fortitude + Inner Fire).
--
-- /bglow               - help
-- /bglow config        - open the options panel (also in Esc > Options > AddOns)
-- /bglow list          - your class's buffs and whether each is on
-- /bglow toggle <key>  - turn one buff on/off
-- /bglow target        - turn target glows (nameplate + target portrait) on/off
-- /bglow glowsize <n>  - portrait glow size (default 1.45)
-- /bglow fade <n>      - colour blend between buffs, 0-1 (default 0.6)
-- /bglow speed <n>     - seconds per pulse, 0.5-4 (default 1.6)
-- /bglow test          - show the glow for 5 seconds

local ADDON = ...
local _, CLASS = UnitClass("player")

-- Buff definitions ----------------------------------------------------------
-- spells : rank 1 IDs of every spell that satisfies this buff (single + group
--          versions). Matching is done by spell name, so all ranks count.
-- color  : glow colour, taken from the buff's icon
-- others : can be cast on other players (used for the target glow)
-- mineOnly: only counts if YOU cast it (paladin blessings)
-- partyOnly : target glow only for targets in your party (warrior shouts)
-- combatOnly: only glows while you're in combat (warrior shouts)
-- off    : disabled by default
local BUFFS = {
    MAGE = {
        { key = "intellect", label = "Arcane Intellect / Brilliance", spells = { 1459, 23028 }, color = { 0.45, 0.6, 1 }, others = true },
        { key = "armor", label = "Frost / Ice / Mage / Molten Armor", spells = { 168, 7302, 6117, 30482 }, color = { 0.6, 0.9, 1 } },
    },
    PRIEST = {
        { key = "fortitude", label = "Power Word: Fortitude", spells = { 1243, 21562 }, color = { 1, 1, 1 }, others = true },
        { key = "innerfire", label = "Inner Fire", spells = { 588 }, color = { 1, 0.75, 0.2 } },
        { key = "spirit", label = "Divine Spirit", spells = { 14752, 27681 }, color = { 0.7, 0.85, 1 }, others = true },
        { key = "shadowprot", label = "Shadow Protection", spells = { 976, 27683 }, color = { 0.6, 0.2, 0.9 }, others = true, off = true },
    },
    DRUID = {
        { key = "mark", label = "Mark / Gift of the Wild", spells = { 1126, 21849 }, color = { 0.9, 0.4, 1 }, others = true },
        { key = "thorns", label = "Thorns", spells = { 467 }, color = { 0.4, 0.9, 0.3 }, others = true },
        { key = "omen", label = "Omen of Clarity", spells = { 16864 }, color = { 0.6, 1, 0.85 } },
    },
    WARLOCK = {
        { key = "armor", label = "Demon Skin / Demon Armor / Fel Armor", spells = { 687, 706, 28176 }, color = { 0.65, 0.2, 1 } },
    },
    PALADIN = {
        { key = "blessing", label = "A Blessing from you", mineOnly = true, others = true, color = { 1, 0.85, 0.3 },
          spells = { 19740, 19742, 20217, 1038, 19977, 20911,      -- Might, Wisdom, Kings, Salvation, Light, Sanctuary
                     25782, 25894, 25898, 25895, 25890, 25899 } }, -- Greater versions
        { key = "rfury", label = "Righteous Fury", spells = { 25780 }, color = { 1, 0.45, 0.2 }, off = true },
    },
    SHAMAN = {
        { key = "shield", label = "Lightning / Water Shield", spells = { 324, 24398 }, color = { 0.3, 0.6, 1 } },
    },
    -- Shouts are short and cost rage, so they only glow in combat, and only
    -- glow on a target who's in your party (shouts don't reach anyone else).
    WARRIOR = {
        { key = "battleshout", label = "Battle Shout (in combat)", spells = { 6673 }, color = { 1, 0.3, 0.2 },
          others = true, partyOnly = true, combatOnly = true },
        { key = "commanding", label = "Commanding Shout (in combat)", spells = { 469 }, color = { 0.95, 0.8, 0.45 },
          others = true, partyOnly = true, combatOnly = true, off = true },
    },
}

local myBuffs = BUFFS[CLASS]
if not myBuffs then return end -- nothing to track for this class

-- Spell helpers ---------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function Knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

local function BuildNames()
    for _, b in ipairs(myBuffs) do
        b.names = b.names or {}
        for _, id in ipairs(b.spells) do
            local n = SpellName(id)
            if n then b.names[n] = true end
        end
    end
end

local function CanCast(b)
    for _, id in ipairs(b.spells) do
        if Knows(id) then return true end
    end
    return false
end

-- The Forever client can hide aura details as "secret values" (mostly in
-- combat). Comparing or using one as a table key errors, so check first.
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Returns a list of { name, mine } for a unit's buffs. If any names are secret,
-- list.secret is set and HasBuff falls back to asking for each buff by name.
local function ScanAuras(unit)
    local list = {}
    for i = 1, 40 do
        local name, source
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end
            name, source = aura.name, aura.sourceUnit
        else
            local n, _, _, _, _, _, src = UnitBuff(unit, i)
            if not n then break end
            name, source = n, src
        end
        if IsSecret(name) then
            list.secret = true
        else
            local mine
            if source == nil then
                mine = false
            elseif IsSecret(source) then
                mine = "unknown"
            else
                mine = UnitIsUnit(source, "player")
            end
            list[#list + 1] = { name = name, mine = mine }
        end
    end
    return list
end

local function HasBuff(auras, b, unit)
    for _, a in ipairs(auras) do
        if b.names[a.name] and (not b.mineOnly or a.mine) then return true end
    end
    -- Some names were hidden: look each of this buff's names up directly.
    if auras.secret and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        for n in pairs(b.names) do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, n, "HELPFUL")
            if ok and aura then return true end
        end
    end
    return false
end

-- Settings --------------------------------------------------------------------
local defaults = { glowScale = 1.45, target = true, fade = 0.6, period = 1.6 }
local db

local function Enabled(b)
    local v = db.enabled[b.key]
    if v == nil then return not b.off end
    return v
end

-- Glow objects --------------------------------------------------------------
-- A glow is several soft, low-alpha layers of increasing size. Stacked, they
-- make a glow that fades outward. Circles use the round portrait mask.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LAYERS, LAYER_ALPHA = 8, 0.22
local PERIOD, MIN_ALPHA = 1.6, 0.35 -- default seconds per pulse, dimmest point
local glows = {}

local function CreateGlow(shape)
    local g = { shape = shape, colors = {}, layers = {} }
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    g.frame = f
    for i = 1, LAYERS do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetPoint("CENTER")
        t:SetColorTexture(1, 1, 1, LAYER_ALPHA)
        if shape == "circle" then
            local m = f:CreateMaskTexture()
            m:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            t:AddMaskTexture(m)
        end
        g.layers[i] = t
    end
    glows[#glows + 1] = g
    return g
end

-- Puts the glow behind `anchor` (a portrait or health bar).
-- circle: grows from the anchor's size to size * scale
-- rect:   grows `pad` pixels out from each edge
local function AttachGlow(g, anchor, parent, strata, level, scaleOrPad)
    local f = g.frame
    f:SetParent(parent)
    f:SetFrameStrata(strata)
    if level then f:SetFrameLevel(math.max(level, 0)) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    local w, h = anchor:GetWidth(), anchor:GetHeight()
    if not w or w <= 0 then w, h = 64, 64 end
    for i, t in ipairs(g.layers) do
        local k = i / LAYERS
        if g.shape == "circle" then
            local s = w + (w * scaleOrPad - w) * k
            t:SetSize(s, s)
        else
            t:SetSize(w + 2 * scaleOrPad * k, h + 2 * scaleOrPad * k)
        end
    end
    f:SetSize(w * 2, h * 2)
    g.anchor = anchor
end

local function SetGlowColors(g, colors)
    g.colors = colors
    g.current = nil
    if #colors > 0 and g.anchor then g.frame:Show() else g.frame:Hide() end
end

local function HideGlow(g)
    g.colors = {}
    g.frame:Hide()
end

-- One clock drives every glow so they all pulse together.
-- Colour blend: db.fade is how much of each pulse is spent blending into the
-- next buff's colour, centred on the dimmest point (0 = instant switch,
-- 1 = blend the whole way through).
local clock = 0
local function AnimateGlows(elapsed)
    -- Advance by phase (not time) so changing the speed doesn't make the glow jump.
    clock = clock + elapsed / (db and db.period or PERIOD)
    local phase = clock
    local alpha = MIN_ALPHA + (1 - MIN_ALPHA) * (0.5 + 0.5 * math.cos(phase * 2 * math.pi))
    -- Each pulse belongs to one buff colour (brightest at frac 0). While the glow
    -- dims and comes back up, the colour blends smoothly into the next buff's, so
    -- the next pulse peaks in its own colour without a hard switch.
    local step = math.floor(phase)
    local frac = phase - step
    local fade = db and db.fade or 0.6
    local t
    if fade <= 0 then
        t = frac >= 0.5 and 1 or 0
    else
        t = (frac - (0.5 - fade / 2)) / fade
        t = t < 0 and 0 or (t > 1 and 1 or t)
    end
    t = t * t * (3 - 2 * t) -- smoothstep: eases in and out of the blend
    for _, g in ipairs(glows) do
        local n = #g.colors
        if g.frame:IsShown() and n > 0 then
            g.frame:SetAlpha(alpha)
            local a = g.colors[step % n + 1]
            local b = g.colors[(step + 1) % n + 1]
            local r = a[1] + (b[1] - a[1]) * t
            local gr = a[2] + (b[2] - a[2]) * t
            local bl = a[3] + (b[3] - a[3]) * t
            for _, tex in ipairs(g.layers) do tex:SetVertexColor(r, gr, bl) end
        end
    end
end

-- The three glows -------------------------------------------------------------
local playerGlow = CreateGlow("circle")
local targetGlow = CreateGlow("circle")
local plateGlow  = CreateGlow("rect")

local function PlayerPortraitTex()
    return PlayerPortrait or (PlayerFrame and PlayerFrame.portrait)
        or (PlayerFrame and PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.PlayerPortrait)
end

local function TargetPortraitTex()
    return TargetFramePortrait or (TargetFrame and TargetFrame.portrait)
        or (TargetFrame and TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.Portrait)
end

local function AttachPortraitGlows()
    local p = PlayerPortraitTex()
    if p then AttachGlow(playerGlow, p, PlayerFrame, "BACKGROUND", nil, db.glowScale) end
    local t = TargetPortraitTex()
    if t then AttachGlow(targetGlow, t, TargetFrame, "BACKGROUND", nil, db.glowScale) end
end

local function AttachPlateGlow()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
        plateGlow.anchor, plateGlow.plate = nil, nil
        return false
    end
    if plateGlow.plate ~= plate then
        local uf = plate.UnitFrame
        local bar = uf and (uf.healthBar or uf.HealthBar)
        local anchor = (bar and bar:IsVisible() and bar) or (uf and uf:IsVisible() and uf) or plate
        AttachGlow(plateGlow, anchor, plate, plate:GetFrameStrata(), anchor:GetFrameLevel() - 1, 10)
        plateGlow.plate = plate
    end
    return true
end

-- Update ----------------------------------------------------------------------
local testUntil = 0

local function MissingColors(unit, onlyOthers)
    local auras = ScanAuras(unit)
    local colors = {}
    local inCombat = UnitAffectingCombat("player")
    local inParty = onlyOthers and UnitInParty(unit)
    for _, b in ipairs(myBuffs) do
        if Enabled(b) and (not onlyOthers or b.others)
            and (not b.combatOnly or inCombat)
            and (not onlyOthers or not b.partyOnly or inParty)
            and CanCast(b) and not HasBuff(auras, b, unit) then
            colors[#colors + 1] = b.color
        end
    end
    return colors
end

local function TestColors()
    local colors = {}
    for _, b in ipairs(myBuffs) do
        if Enabled(b) then colors[#colors + 1] = b.color end
    end
    return colors
end

local function Update()
    if not db then return end
    local testing = GetTime() < testUntil

    -- Player
    if testing then
        SetGlowColors(playerGlow, TestColors())
    elseif UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
        HideGlow(playerGlow)
    else
        SetGlowColors(playerGlow, MissingColors("player", false))
    end

    -- Target: friendly, alive, online, another player
    local colors = {}
    if db.target and UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
        and UnitCanAssist("player", "target") and not UnitIsDeadOrGhost("target") and UnitIsConnected("target") then
        colors = MissingColors("target", true)
    end
    SetGlowColors(targetGlow, colors)
    if #colors > 0 and AttachPlateGlow() then
        SetGlowColors(plateGlow, colors)
    else
        HideGlow(plateGlow)
    end
end

-- Events ----------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
events:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterUnitEvent("UNIT_AURA", "player", "target")

local sinceUpdate = 0
events:SetScript("OnUpdate", function(_, elapsed)
    AnimateGlows(elapsed)
    -- Taxi start/end has no reliable event in every client, so poll lightly.
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate >= 1 then sinceUpdate = 0; Update() end
end)

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        BuffGlowReminderDB = BuffGlowReminderDB or {}
        db = BuffGlowReminderDB
        for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
        db.enabled = db.enabled or {}
        BuildNames()
        AttachPortraitGlows()
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" and arg1 and UnitIsUnit(arg1, "target") then
        plateGlow.plate, plateGlow.anchor = nil, nil
        HideGlow(plateGlow)
    end
    if event == "PLAYER_TARGET_CHANGED" then plateGlow.plate = nil end
    if event == "PLAYER_ENTERING_WORLD" then BuildNames(); AttachPortraitGlows() end
    Update()
end)

-- Slash command -------------------------------------------------------------
local function Print(msg) print("|cffb48cffBuffGlow Reminder:|r " .. msg) end

local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- Options panel (Esc > Options > AddOns > BuffGlow Reminder) -------------------------
local panel = CreateFrame("Frame", "BuffGlowReminderOptionsPanel")
panel.name = "BuffGlow Reminder"
panel:Hide()

local refreshing = false
local buffChecks = {}

local function MakeCheck(parent, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.label = cb.text or cb.Text
    if not cb.label then
        cb.label = cb:CreateFontString(nil, "ARTWORK")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    cb.label:SetFontObject("GameFontHighlight")
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

local function BuildPanel()
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("BuffGlow Reminder")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(560)
    sub:SetJustifyH("LEFT")
    sub:SetText("Glows around your portrait when you're missing one of these buffs, and around a friendly target when they're missing one you can give. The glow takes the buff's colour and cycles through them if several are missing.")

    local className, classFile = UnitClass("player")
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    header:SetText("Buffs to watch (" .. (cc and Hex({ cc.r, cc.g, cc.b }) or "") .. className .. "|r)")

    local y = -100
    for _, b in ipairs(myBuffs) do
        local cb = MakeCheck(panel, 16, y, function(checked)
            db.enabled[b.key] = checked
            Update()
        end)
        cb.buff = b
        buffChecks[#buffChecks + 1] = cb
        y = y - 28
    end

    y = y - 16
    local tgtHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tgtHeader:SetPoint("TOPLEFT", 16, y)
    tgtHeader:SetText("Target")
    y = y - 20
    panel.targetCheck = MakeCheck(panel, 16, y, function(checked)
        db.target = checked
        Update()
    end)
    panel.targetCheck.label:SetText("Glow on a friendly player's nameplate and target portrait when they're missing a buff you can give")

    -- Slider with a label above and the value to the right. Values snap to 0.05.
    local function MakeSlider(sy, labelText, minV, maxV, format, onChange)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", 16, sy)
        label:SetText(labelText)

        local slider = CreateFrame("Slider", nil, panel)
        slider:SetPoint("TOPLEFT", 20, sy - 22)
        slider:SetSize(220, 17)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(0.05)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider:EnableMouse(true)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0, 0, 0, 0.6)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(6)
        local valueText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)
        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value * 20 + 0.5) / 20
            valueText:SetText(format(value))
            if refreshing then return end
            onChange(value)
            testUntil = GetTime() + 3 -- show the glow while adjusting
            Update()
        end)
        return slider
    end

    y = y - 48
    panel.slider = MakeSlider(y, "Portrait glow size", 1, 3,
        function(v) return string.format("%.2f", v) end,
        function(v) db.glowScale = v; AttachPortraitGlows() end)

    y = y - 56
    panel.fadeSlider = MakeSlider(y, "Colour blend between buffs (when several are missing)", 0, 1,
        function(v)
            if v == 0 then return "instant switch" end
            return string.format("%d%% of each pulse", math.floor(v * 100 + 0.5))
        end,
        function(v) db.fade = v end)

    y = y - 56
    panel.periodSlider = MakeSlider(y, "Pulse speed (seconds per pulse, lower is faster)", 0.5, 4,
        function(v) return string.format("%.2f s", v) end,
        function(v) db.period = v end)

    local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    test:SetPoint("TOPLEFT", 16, y - 64)
    test:SetSize(160, 24)
    test:SetText("Test glow (5 seconds)")
    test:SetScript("OnClick", function()
        testUntil = GetTime() + 5
        Update()
    end)
end

local function RefreshPanel()
    if not db then return end
    refreshing = true
    for _, cb in ipairs(buffChecks) do
        local b = cb.buff
        cb:SetChecked(Enabled(b))
        local known = CanCast(b) and "" or "  |cff888888(not learned)|r"
        cb.label:SetText(Hex(b.color) .. b.label .. "|r" .. known)
    end
    panel.targetCheck:SetChecked(db.target)
    panel.slider:SetValue(db.glowScale)
    panel.fadeSlider:SetValue(db.fade)
    panel.periodSlider:SetValue(db.period)
    refreshing = false
end

BuildPanel()
panel:SetScript("OnShow", RefreshPanel)

local OpenPanel
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    OpenPanel = function() Settings.OpenToCategory(category:GetID()) end
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    OpenPanel = function()
        -- called twice: a long-standing Blizzard quirk where the first call only opens the frame
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

SLASH_BUFFGLOWREMINDER1 = "/bglow"
SLASH_BUFFGLOWREMINDER2 = "/buffglowreminder"
SlashCmdList.BUFFGLOWREMINDER = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "config" or msg == "options" then
        if OpenPanel then OpenPanel() else Print("Options panel isn't available in this client.") end
        return
    elseif msg == "list" then
        for _, b in ipairs(myBuffs) do
            local state = Enabled(b) and "|cff00ff00on|r" or "|cffff4040off|r"
            local known = CanCast(b) and "" or " |cff888888(not learned)|r"
            Print(Hex(b.color) .. b.key .. "|r - " .. b.label .. ": " .. state .. known)
        end
    elseif msg:match("^toggle") then
        local key = msg:match("^toggle%s+(%S+)")
        for _, b in ipairs(myBuffs) do
            if b.key == key then
                db.enabled[key] = not Enabled(b)
                Print(b.label .. ": " .. (db.enabled[key] and "on" or "off"))
                Update()
                return
            end
        end
        Print("Unknown buff. Use /bglow list to see the keys.")
    elseif msg == "target" then
        db.target = not db.target
        Print("Target glows: " .. (db.target and "on" or "off"))
    elseif msg:match("^glowsize") then
        local n = tonumber(msg:match("^glowsize%s+([%d%.]+)"))
        if n and n >= 1 and n <= 3 then
            db.glowScale = n
            AttachPortraitGlows()
            testUntil = GetTime() + 5
            Print("Glow size set to " .. n .. " (showing for 5 seconds).")
        else
            Print("Usage: /bglow glowsize 1.45   (between 1 and 3)")
        end
    elseif msg:match("^fade") then
        local n = tonumber(msg:match("^fade%s+([%d%.]+)"))
        if n and n >= 0 and n <= 1 then
            db.fade = n
            testUntil = GetTime() + 5
            Print("Colour blend set to " .. n .. " (showing for 5 seconds).")
        else
            Print("Usage: /bglow fade 0.6   (0 = instant switch, 1 = blend the whole pulse)")
        end
    elseif msg:match("^speed") then
        local n = tonumber(msg:match("^speed%s+([%d%.]+)"))
        if n and n >= 0.5 and n <= 4 then
            db.period = n
            testUntil = GetTime() + 5
            Print("Pulse speed set to " .. n .. " seconds per pulse (showing for 5 seconds).")
        else
            Print("Usage: /bglow speed 1.6   (seconds per pulse, 0.5 to 4)")
        end
    elseif msg == "test" then
        testUntil = GetTime() + 5
        Print("Showing glow for 5 seconds.")
    else
        Print("/bglow config | list | toggle <key> | target | glowsize <n> | fade <n> | speed <n> | test")
    end
    Update()
end
