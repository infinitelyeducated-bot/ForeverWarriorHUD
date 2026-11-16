--[[
ForeverWarriorHUD 2.0.0
A warrior HUD for WoW: Forever (Interface 16001, product wowf / Camelot).
Ported from ForeverWarriorHUD 1.9.2; standalone, shares nothing with it, and can
be enabled next to any other Forever<Class>HUD.

What it shows:
  * Resource bar: rage, rage gained per second.
  * Resource regeneration bar: measured per second over a one second window.
  * Swing timer with the full option set (colour, spark, text modes, ticks,
    ready flash, source, manual speed, reset on target change).
  * Combo points: present but off by default; this class has none.
  * 37 ability icons, each with a cooldown sweep, a numeric countdown and a
    ready flash. The countdown has its own toggle (Config tab, /fw cooldown).
  * 40 skins, named profiles, CTRL-drag with grid / snap / sticky edges,
    auto-hide out of combat, a reflowing four-tab options window.

New relative to the rogue reference:
  * Countdown text on every icon (whole seconds under a minute, m:ss under an
    hour), drawn on its own frame above the sweep and driven from the one
    existing update pass.
  * Ready flash: the icon border pulses to the skin's spark colour for 0.25 s
    when a cooldown ends.
  * Spell IDs are re-resolved from the client by spellbook name at login and
    whenever the spellbook changes, so the icon and the cooldown follow the rank
    this character actually knows. The table IDs are only the fallback.
  * Icons default to a 9-wide grid above the HUD instead of one stacked point.

Forever rules kept:
  * Cooldowns come from C_Spell.GetSpellCooldown(id) under pcall. A nil, secret
    or unreadable startTime / duration draws no number and raises no error; a
    duration at or under 1.51 s is the global cooldown and is ignored.
  * Secret values only feed widgets, never comparisons or arithmetic.
  * BackdropTemplate on every backdrop frame. Events registered one at a time
    under pcall. Public APIs only: no protected calls, no combat automation, no
    combat log, no writes outside SavedVariables.

Slash commands:
  /fw                        open the options panel
  /fw config | skins | profiles
  /fw skin <name>            apply a skin by name or key
  /fw save <name> | load <name>
  /fw show | hide            whole HUD on or off
  /fw energy|regen|swing|combo on|off   ("energy" is the rage bar)
  /fw cooldown on|off        countdown numbers on the icons
  /fw sticky | grid
  /fw orient h | v
  /fw scale 0.5..2.5
  /fw lock | unlock
  /fw reset
]]

local ADDON_NAME = ...
local FRHW_VERSION = "2.0.0"

-- Grid overlay + snap helpers (declared early; the frames are built later)
local gridFrame
local ALL_ITEMS = {}   -- filled once every element and icon exists
local db               -- declared here so Snap() below sees the real table
local ME = {}          -- mouse editing, notifications, menu art (see "Mouse editing")

-- How close two items must come, in screen pixels, before their edges stick.
local STICK_DISTANCE = 10

local function Snap(v)
    if not db or not db.gridSnap then return v end
    local g = db.gridSize or 20
    if g < 4 then g = 4 end
    return math.floor(v / g + 0.5) * g
end

local function ShowGrid()
    if not gridFrame then return end
    gridFrame:Show()
    gridFrame:Update()
end
local function HideGrid()
    if gridFrame then gridFrame:Hide() end
end

-----------------------------------------------------------------------
-- Warrior abilities we can track
-----------------------------------------------------------------------
-- id is the rank 1 spell ID and only a fallback: ResolveSpells() asks the client
-- for the ID behind each spellbook name, so a higher rank is followed
-- automatically. Unmarked IDs come from the spell table GlowingBars 2.8.2
-- ships for this client; the ones marked UNVERIFIED are classic rank 1 IDs
-- that were not confirmed here. "on" ships the icon enabled.
local ABILITIES = {
    { key = "charge",             name = "Charge",              id = 100    , on = true },
    { key = "intercept",          name = "Intercept",           id = 20252  , on = true },
    { key = "pummel",             name = "Pummel",              id = 6552   , on = true },
    { key = "overpower",          name = "Overpower",           id = 7384   , on = true },
    { key = "shieldbash",         name = "Shield Bash",         id = 72 },
    { key = "whirlwind",          name = "Whirlwind",           id = 1680   , on = true },
    { key = "bloodrage",          name = "Bloodrage",           id = 2687   , on = true },
    { key = "berserkerrage",      name = "Berserker Rage",      id = 18499  , on = true },
    { key = "revenge",            name = "Revenge",             id = 6572 },
    { key = "thunderclap",        name = "Thunder Clap",        id = 6343 },
    { key = "taunt",              name = "Taunt",               id = 355 },
    { key = "mockingblow",        name = "Mocking Blow",        id = 694 },
    { key = "disarm",             name = "Disarm",              id = 676 },
    { key = "intimidatingshout",  name = "Intimidating Shout",  id = 5246 },   -- UNVERIFIED on this client
    { key = "shieldblock",        name = "Shield Block",        id = 2565 },
    { key = "recklessness",       name = "Recklessness",        id = 1719 },
    { key = "retaliation",        name = "Retaliation",         id = 20230 },
    { key = "shieldwall",         name = "Shield Wall",         id = 871 },
    { key = "mortalstrike",       name = "Mortal Strike",       id = 12294 },
    { key = "bloodthirst",        name = "Bloodthirst",         id = 23881 },
    { key = "shieldslam",         name = "Shield Slam",         id = 23922 },
    { key = "laststand",          name = "Last Stand",          id = 12975 },
    { key = "deathwish",          name = "Death Wish",          id = 12328 },
    { key = "sweepingstrikes",    name = "Sweeping Strikes",    id = 12292 },
    { key = "piercinghowl",       name = "Piercing Howl",       id = 12323 },
    { key = "concussionblow",     name = "Concussion Blow",     id = 12809 },   -- UNVERIFIED on this client
    { key = "heroicstrike",       name = "Heroic Strike",       id = 78 },
    { key = "rend",               name = "Rend",                id = 772 },
    { key = "execute",            name = "Execute",             id = 5308 },
    { key = "hamstring",          name = "Hamstring",           id = 1715 },
    { key = "sunderarmor",        name = "Sunder Armor",        id = 7386 },
    { key = "cleave",             name = "Cleave",              id = 845 },
    { key = "slam",               name = "Slam",                id = 1464 },
    { key = "battleshout",        name = "Battle Shout",        id = 6673 },
    { key = "demoshout",          name = "Demoralizing Shout",  id = 1160 },
    { key = "victoryrush",        name = "Victory Rush",        id = 402927 },
    { key = "spearingstrike",     name = "Spearing Strike",     id = 1310222 },
}
local GLOBAL_COOLDOWN = 1.51

-----------------------------------------------------------------------
-- Saved defaults
-----------------------------------------------------------------------
-- The only decorative texture this addon draws with: tinted per skin.
local WHITE = "Interface\\BUTTONS\\WHITE8X8"
local SKIN_DEFAULT = "rogue_classic"

local DEFAULTS = {
    baseX = 0, baseY = -140,
    scale = 1.0,
    shown = true,
    locked = false,
    autoHide = true,
    autoHideOOC = false, -- hide the whole HUD while out of combat
    orientation = "h",
    gridSnap = true,     -- snap items to the grid overlay while dragging
    gridSize = 20,       -- grid cell size in screen pixels
    sticky = true,       -- items stick to each other's edges when moved close
    skin = SKIN_DEFAULT, -- palette + edge style, one of SKINS below
    custom = {},         -- custom colours: overrides on top of the skin, by palette part
    customOn = false,
    schemes = {},        -- saved custom colour sets, by name (kept by Reset to default)
    art = "high",        -- menu artwork: "high", "low" or "off" (needs the ForeverArt addon)
    artBanner = "a",     -- which header picture: "a" painted, "b" the alternate
    notify = { cdOnly = true, sweep = true, cooldownDark = true, readyFlash = true, activeGlow = true, usableDim = true, rangeTint = true },
    cooldownText = true, -- numeric countdown on every ability icon
    elements = {
        energy = { enabled = true, x = 0, y = 0,   w = 220, h = 16, alpha = 1.0, scale = 1.0, rot = 0,
                   showText = true },
        -- Energy regeneration, its own element so it can be moved and sized
        -- apart from the energy bar. It shows the measured energy per second
        -- against regenMax; the reading is our own arithmetic on values that
        -- passed IsReadable, never on a secret one.
        regen  = { enabled = false, x = 0, y = -44, w = 220, h = 8, alpha = 1.0, scale = 1.0, rot = 0,
                   regenMax = 25, showRate = true },
        -- The swing timer keeps its 1.9.0 options in the same table as its
        -- position and size, so profiles and Reset to default carry them
        -- without any extra bookkeeping. The defaults reproduce the 1.8.0 bar.
        swing  = { enabled = true, x = 0, y = -22, w = 220, h = 10, alpha = 1.0, scale = 1.0, rot = 0,
                   useSkinColor = true, r = 0.85, g = 0.85, b = 0.95, bgAlpha = 0.7,
                   spark = true, sparkSize = 20,
                   text = true, textMode = "elapsed",
                   ticks = false, tickCount = 4,
                   flash = false,
                   source = "event",
                   manual = false, manualSpeed = 2.0,
                   resetOnTarget = false },
        combo  = { enabled = false, x = 0, y = 22,  w = 12,  h = 10, alpha = 1.0, scale = 1.0, rot = 0 },
        -- the last few spells cast, newest first
        trail  = { enabled = true, x = 0, y = -72, w = 22, h = 22, alpha = 1.0, scale = 1.0, rot = 0 },
    },
    spells = {},
}
-- Nine icons to a row, centred over the HUD, so switching several on never
-- stacks them on one point.
for i, a in ipairs(ABILITIES) do
    local col, row = (i - 1) % 9, math.floor((i - 1) / 9)
    DEFAULTS.spells[a.key] = { enabled = a.on == true, x = (col - 4) * 30, y = 60 + row * 30,
                               w = 26, h = 26, alpha = 1.0, scale = 1.0, rot = 0 }
end
-- Everything a named profile stores. "profiles" is deliberately NOT in this
-- list: saved setups are kept apart from the live configuration, so resetting
-- to defaults or loading a profile can never delete them.
local CONFIG_KEYS = {
    "baseX", "baseY", "scale", "shown", "locked", "autoHide", "autoHideOOC",
    "orientation", "gridSnap", "gridSize", "sticky", "skin", "cooldownText", "notify", "custom", "customOn", "elements", "spells",
}
DEFAULTS.profiles = {}
local panel

-- Swing text modes, in the order the mode button cycles through them.
local SWING_TEXT_ORDER = { "elapsed", "remaining", "percent", "none" }
local SWING_TEXT_LABEL = {
    elapsed   = "Text: elapsed / total",
    remaining = "Text: remaining",
    percent   = "Text: percent",
    none      = "Text: none",
}

-----------------------------------------------------------------------
-- Skins: 40 palettes plus an edge style each
-----------------------------------------------------------------------
-- A skin only recolours. bar = energy fill, swing = swing fill, combo = combo
-- points, barBg = energy background, spark = swing spark and ready flash,
-- text = every label, accent = headers / rules / selected tab, border = bar
-- outlines and the window edge, panel = window background, iconEdge = spell
-- icon border. Bar colours are kept dark enough for the light text to read on
-- top of them (the test suite checks the contrast of every skin but the first,
-- which is the 1.8.0 look kept as it was).
--
-- style picks the edge treatment drawn around bars, combo points and icons:
--   flat   no outline                     line   1 px outline
--   bevel  outline, light top, dark base  rune   outline with corner pips
--   ember  outline with a glowing base    frost  outline with an icy top edge
--   gilded outline with accent inlays top and bottom
local SKINS = {
    { key = "rogue_classic", name = "Rogue Classic", style = "flat",
      bar = { 1.00, 0.96, 0.41 }, swing = { 0.85, 0.85, 0.95 }, combo = { 1.00, 0.60, 0.00 },
      accent = { 0.20, 0.80, 1.00 }, text = { 1.00, 1.00, 1.00 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.25, 0.24, 0.1025, 0.70 }, border = { 0.35, 0.35, 0.40, 1.00 },
      panel = { 0.05, 0.05, 0.07, 0.94 }, iconEdge = { 0.20, 0.20, 0.20, 1.00 } },
    { key = "emberforge", name = "Emberforge", style = "ember",
      bar = { 0.86, 0.36, 0.10 }, swing = { 0.66, 0.30, 0.18 }, combo = { 1.00, 0.62, 0.15 },
      accent = { 1.00, 0.55, 0.18 }, text = { 1.00, 0.95, 0.88 }, spark = { 1.00, 0.85, 0.50 },
      barBg = { 0.16, 0.06, 0.03, 0.80 }, border = { 0.50, 0.22, 0.08, 1.00 },
      panel = { 0.09, 0.05, 0.04, 0.95 }, iconEdge = { 0.62, 0.27, 0.10, 1.00 } },
    { key = "frostgrave", name = "Frostgrave", style = "frost",
      bar = { 0.20, 0.50, 0.80 }, swing = { 0.34, 0.52, 0.66 }, combo = { 0.55, 0.85, 1.00 },
      accent = { 0.60, 0.88, 1.00 }, text = { 0.93, 0.97, 1.00 }, spark = { 0.85, 0.95, 1.00 },
      barBg = { 0.04, 0.09, 0.16, 0.80 }, border = { 0.30, 0.50, 0.66, 1.00 },
      panel = { 0.04, 0.07, 0.11, 0.95 }, iconEdge = { 0.40, 0.65, 0.85, 1.00 } },
    { key = "venomdusk", name = "Venomdusk", style = "line",
      bar = { 0.28, 0.56, 0.14 }, swing = { 0.42, 0.30, 0.58 }, combo = { 0.70, 0.95, 0.20 },
      accent = { 0.66, 0.92, 0.26 }, text = { 0.94, 1.00, 0.90 }, spark = { 0.80, 1.00, 0.50 },
      barBg = { 0.05, 0.11, 0.04, 0.80 }, border = { 0.26, 0.44, 0.14, 1.00 },
      panel = { 0.05, 0.07, 0.06, 0.95 }, iconEdge = { 0.36, 0.60, 0.18, 1.00 } },
    { key = "runeblade", name = "Runeblade", style = "rune",
      bar = { 0.22, 0.42, 0.78 }, swing = { 0.40, 0.40, 0.72 }, combo = { 0.45, 0.80, 1.00 },
      accent = { 0.40, 0.78, 1.00 }, text = { 0.92, 0.96, 1.00 }, spark = { 0.70, 0.90, 1.00 },
      barBg = { 0.04, 0.07, 0.15, 0.80 }, border = { 0.24, 0.38, 0.62, 1.00 },
      panel = { 0.04, 0.05, 0.10, 0.95 }, iconEdge = { 0.30, 0.55, 0.90, 1.00 } },
    { key = "cryptlight", name = "Cryptlight", style = "bevel",
      bar = { 0.36, 0.52, 0.40 }, swing = { 0.46, 0.48, 0.38 }, combo = { 0.75, 0.95, 0.70 },
      accent = { 0.70, 0.95, 0.72 }, text = { 0.92, 0.98, 0.90 }, spark = { 0.85, 1.00, 0.85 },
      barBg = { 0.06, 0.09, 0.07, 0.80 }, border = { 0.30, 0.40, 0.32, 1.00 },
      panel = { 0.05, 0.07, 0.06, 0.95 }, iconEdge = { 0.42, 0.58, 0.44, 1.00 } },
    { key = "wyrmfire", name = "Wyrmfire", style = "ember",
      bar = { 0.82, 0.24, 0.12 }, swing = { 0.74, 0.42, 0.10 }, combo = { 1.00, 0.80, 0.20 },
      accent = { 1.00, 0.72, 0.20 }, text = { 1.00, 0.95, 0.85 }, spark = { 1.00, 0.90, 0.45 },
      barBg = { 0.15, 0.04, 0.03, 0.80 }, border = { 0.52, 0.16, 0.08, 1.00 },
      panel = { 0.09, 0.04, 0.04, 0.95 }, iconEdge = { 0.70, 0.22, 0.10, 1.00 } },
    { key = "bloodmoon", name = "Bloodmoon", style = "bevel",
      bar = { 0.66, 0.10, 0.14 }, swing = { 0.52, 0.20, 0.26 }, combo = { 0.95, 0.30, 0.30 },
      accent = { 0.92, 0.26, 0.30 }, text = { 1.00, 0.92, 0.92 }, spark = { 1.00, 0.60, 0.60 },
      barBg = { 0.13, 0.02, 0.03, 0.82 }, border = { 0.42, 0.08, 0.10, 1.00 },
      panel = { 0.08, 0.03, 0.04, 0.95 }, iconEdge = { 0.60, 0.12, 0.14, 1.00 } },
    { key = "ashen_covenant", name = "Ashen Covenant", style = "flat",
      bar = { 0.44, 0.44, 0.46 }, swing = { 0.52, 0.48, 0.44 }, combo = { 0.80, 0.78, 0.74 },
      accent = { 0.82, 0.80, 0.76 }, text = { 0.96, 0.95, 0.93 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.08, 0.08, 0.08, 0.80 }, border = { 0.34, 0.33, 0.32, 1.00 },
      panel = { 0.07, 0.07, 0.07, 0.95 }, iconEdge = { 0.42, 0.41, 0.40, 1.00 } },
    { key = "deepstone", name = "Deepstone", style = "bevel",
      bar = { 0.36, 0.42, 0.50 }, swing = { 0.46, 0.42, 0.36 }, combo = { 0.62, 0.74, 0.86 },
      accent = { 0.58, 0.72, 0.86 }, text = { 0.93, 0.95, 0.98 }, spark = { 0.85, 0.90, 1.00 },
      barBg = { 0.06, 0.07, 0.09, 0.82 }, border = { 0.28, 0.32, 0.38, 1.00 },
      panel = { 0.05, 0.06, 0.08, 0.95 }, iconEdge = { 0.36, 0.42, 0.50, 1.00 } },
    { key = "hollow_lantern", name = "Hollow Lantern", style = "gilded",
      bar = { 0.76, 0.46, 0.10 }, swing = { 0.50, 0.40, 0.56 }, combo = { 1.00, 0.82, 0.35 },
      accent = { 1.00, 0.80, 0.32 }, text = { 1.00, 0.96, 0.86 }, spark = { 1.00, 0.92, 0.60 },
      barBg = { 0.12, 0.07, 0.03, 0.80 }, border = { 0.52, 0.36, 0.10, 1.00 },
      panel = { 0.07, 0.05, 0.07, 0.95 }, iconEdge = { 0.72, 0.50, 0.14, 1.00 } },
    { key = "gilded_reliquary", name = "Gilded Reliquary", style = "gilded",
      bar = { 0.68, 0.50, 0.12 }, swing = { 0.56, 0.24, 0.24 }, combo = { 1.00, 0.86, 0.40 },
      accent = { 1.00, 0.84, 0.38 }, text = { 1.00, 0.97, 0.88 }, spark = { 1.00, 0.95, 0.70 },
      barBg = { 0.11, 0.08, 0.03, 0.82 }, border = { 0.62, 0.48, 0.16, 1.00 },
      panel = { 0.08, 0.06, 0.04, 0.95 }, iconEdge = { 0.80, 0.62, 0.20, 1.00 } },
    { key = "plaguewick", name = "Plaguewick", style = "line",
      bar = { 0.46, 0.52, 0.12 }, swing = { 0.44, 0.36, 0.50 }, combo = { 0.82, 0.92, 0.28 },
      accent = { 0.80, 0.92, 0.30 }, text = { 0.97, 1.00, 0.88 }, spark = { 0.90, 1.00, 0.55 },
      barBg = { 0.08, 0.09, 0.03, 0.80 }, border = { 0.36, 0.42, 0.12, 1.00 },
      panel = { 0.06, 0.07, 0.04, 0.95 }, iconEdge = { 0.50, 0.58, 0.16, 1.00 } },
    { key = "stormcall", name = "Stormcall", style = "rune",
      bar = { 0.26, 0.40, 0.86 }, swing = { 0.44, 0.46, 0.66 }, combo = { 0.70, 0.80, 1.00 },
      accent = { 0.66, 0.78, 1.00 }, text = { 0.94, 0.96, 1.00 }, spark = { 0.90, 0.95, 1.00 },
      barBg = { 0.04, 0.06, 0.16, 0.80 }, border = { 0.26, 0.34, 0.66, 1.00 },
      panel = { 0.04, 0.05, 0.11, 0.95 }, iconEdge = { 0.34, 0.46, 0.90, 1.00 } },
    { key = "iron_vigil", name = "Iron Vigil", style = "bevel",
      bar = { 0.40, 0.46, 0.52 }, swing = { 0.50, 0.44, 0.40 }, combo = { 0.78, 0.84, 0.90 },
      accent = { 0.74, 0.82, 0.90 }, text = { 0.95, 0.97, 0.99 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.07, 0.08, 0.09, 0.82 }, border = { 0.36, 0.40, 0.44, 1.00 },
      panel = { 0.06, 0.07, 0.08, 0.95 }, iconEdge = { 0.46, 0.52, 0.58, 1.00 } },
    { key = "obsidian_oath", name = "Obsidian Oath", style = "line",
      bar = { 0.38, 0.22, 0.56 }, swing = { 0.30, 0.34, 0.44 }, combo = { 0.72, 0.50, 1.00 },
      accent = { 0.70, 0.48, 1.00 }, text = { 0.95, 0.92, 1.00 }, spark = { 0.85, 0.70, 1.00 },
      barBg = { 0.05, 0.03, 0.09, 0.85 }, border = { 0.30, 0.20, 0.46, 1.00 },
      panel = { 0.03, 0.03, 0.05, 0.96 }, iconEdge = { 0.44, 0.28, 0.66, 1.00 } },
    { key = "sunken_choir", name = "Sunken Choir", style = "frost",
      bar = { 0.12, 0.52, 0.56 }, swing = { 0.26, 0.44, 0.60 }, combo = { 0.45, 0.92, 0.88 },
      accent = { 0.42, 0.90, 0.86 }, text = { 0.90, 1.00, 0.99 }, spark = { 0.70, 1.00, 0.95 },
      barBg = { 0.03, 0.10, 0.11, 0.80 }, border = { 0.16, 0.42, 0.46, 1.00 },
      panel = { 0.03, 0.07, 0.08, 0.95 }, iconEdge = { 0.20, 0.58, 0.62, 1.00 } },
    { key = "thornmantle", name = "Thornmantle", style = "line",
      bar = { 0.24, 0.50, 0.24 }, swing = { 0.50, 0.38, 0.22 }, combo = { 0.62, 0.88, 0.40 },
      accent = { 0.60, 0.86, 0.40 }, text = { 0.94, 1.00, 0.90 }, spark = { 0.80, 1.00, 0.60 },
      barBg = { 0.04, 0.10, 0.04, 0.80 }, border = { 0.24, 0.40, 0.20, 1.00 },
      panel = { 0.05, 0.07, 0.04, 0.95 }, iconEdge = { 0.32, 0.56, 0.28, 1.00 } },
    { key = "wolfsbane", name = "Wolfsbane", style = "rune",
      bar = { 0.50, 0.30, 0.72 }, swing = { 0.40, 0.44, 0.56 }, combo = { 0.82, 0.62, 1.00 },
      accent = { 0.80, 0.60, 1.00 }, text = { 0.97, 0.93, 1.00 }, spark = { 0.90, 0.80, 1.00 },
      barBg = { 0.08, 0.05, 0.13, 0.80 }, border = { 0.40, 0.26, 0.58, 1.00 },
      panel = { 0.06, 0.04, 0.09, 0.95 }, iconEdge = { 0.56, 0.36, 0.80, 1.00 } },
    { key = "cinderhall", name = "Cinderhall", style = "ember",
      bar = { 0.70, 0.30, 0.20 }, swing = { 0.56, 0.44, 0.38 }, combo = { 1.00, 0.56, 0.32 },
      accent = { 1.00, 0.52, 0.30 }, text = { 1.00, 0.94, 0.90 }, spark = { 1.00, 0.75, 0.50 },
      barBg = { 0.13, 0.06, 0.04, 0.82 }, border = { 0.46, 0.22, 0.16, 1.00 },
      panel = { 0.08, 0.05, 0.05, 0.95 }, iconEdge = { 0.62, 0.28, 0.20, 1.00 } },
    { key = "moonwell", name = "Moonwell", style = "frost",
      bar = { 0.34, 0.44, 0.84 }, swing = { 0.46, 0.50, 0.70 }, combo = { 0.78, 0.86, 1.00 },
      accent = { 0.76, 0.84, 1.00 }, text = { 0.95, 0.97, 1.00 }, spark = { 0.92, 0.96, 1.00 },
      barBg = { 0.05, 0.07, 0.16, 0.80 }, border = { 0.34, 0.42, 0.72, 1.00 },
      panel = { 0.04, 0.05, 0.11, 0.95 }, iconEdge = { 0.44, 0.56, 0.94, 1.00 } },
    { key = "serpent_coil", name = "Serpent Coil", style = "line",
      bar = { 0.16, 0.54, 0.36 }, swing = { 0.52, 0.46, 0.18 }, combo = { 0.50, 0.95, 0.60 },
      accent = { 0.46, 0.92, 0.58 }, text = { 0.92, 1.00, 0.94 }, spark = { 0.75, 1.00, 0.80 },
      barBg = { 0.03, 0.10, 0.07, 0.80 }, border = { 0.18, 0.44, 0.30, 1.00 },
      panel = { 0.04, 0.07, 0.05, 0.95 }, iconEdge = { 0.22, 0.62, 0.42, 1.00 } },
    { key = "bonewarden", name = "Bonewarden", style = "bevel",
      bar = { 0.56, 0.50, 0.38 }, swing = { 0.46, 0.44, 0.42 }, combo = { 0.92, 0.88, 0.74 },
      accent = { 0.92, 0.87, 0.72 }, text = { 0.99, 0.97, 0.92 }, spark = { 1.00, 0.98, 0.90 },
      barBg = { 0.10, 0.09, 0.07, 0.80 }, border = { 0.48, 0.44, 0.34, 1.00 },
      panel = { 0.07, 0.07, 0.06, 0.95 }, iconEdge = { 0.64, 0.58, 0.44, 1.00 } },
    { key = "nightshade", name = "Nightshade", style = "rune",
      bar = { 0.46, 0.16, 0.52 }, swing = { 0.30, 0.30, 0.56 }, combo = { 0.88, 0.46, 0.94 },
      accent = { 0.86, 0.44, 0.92 }, text = { 0.98, 0.92, 1.00 }, spark = { 1.00, 0.70, 1.00 },
      barBg = { 0.08, 0.03, 0.10, 0.84 }, border = { 0.38, 0.16, 0.44, 1.00 },
      panel = { 0.05, 0.03, 0.07, 0.96 }, iconEdge = { 0.56, 0.22, 0.64, 1.00 } },
    { key = "dawnsteel", name = "Dawnsteel", style = "gilded",
      bar = { 0.50, 0.52, 0.60 }, swing = { 0.68, 0.46, 0.26 }, combo = { 1.00, 0.84, 0.56 },
      accent = { 1.00, 0.82, 0.54 }, text = { 1.00, 0.98, 0.94 }, spark = { 1.00, 0.95, 0.80 },
      barBg = { 0.08, 0.08, 0.10, 0.80 }, border = { 0.52, 0.52, 0.58, 1.00 },
      panel = { 0.07, 0.07, 0.09, 0.95 }, iconEdge = { 0.70, 0.66, 0.56, 1.00 } },
    { key = "grimoire", name = "Grimoire", style = "rune",
      bar = { 0.44, 0.24, 0.30 }, swing = { 0.40, 0.36, 0.56 }, combo = { 0.86, 0.66, 0.96 },
      accent = { 0.84, 0.64, 0.94 }, text = { 0.98, 0.94, 0.98 }, spark = { 0.95, 0.80, 1.00 },
      barBg = { 0.08, 0.04, 0.06, 0.84 }, border = { 0.40, 0.24, 0.34, 1.00 },
      panel = { 0.06, 0.04, 0.06, 0.96 }, iconEdge = { 0.56, 0.34, 0.50, 1.00 } },
    { key = "torchbearer", name = "Torchbearer", style = "ember",
      bar = { 0.80, 0.44, 0.08 }, swing = { 0.58, 0.36, 0.22 }, combo = { 1.00, 0.76, 0.28 },
      accent = { 1.00, 0.74, 0.26 }, text = { 1.00, 0.96, 0.86 }, spark = { 1.00, 0.90, 0.55 },
      barBg = { 0.14, 0.07, 0.02, 0.80 }, border = { 0.56, 0.32, 0.08, 1.00 },
      panel = { 0.08, 0.06, 0.03, 0.95 }, iconEdge = { 0.76, 0.44, 0.10, 1.00 } },
    { key = "verdant_ruin", name = "Verdant Ruin", style = "bevel",
      bar = { 0.30, 0.50, 0.30 }, swing = { 0.44, 0.48, 0.40 }, combo = { 0.70, 0.90, 0.56 },
      accent = { 0.68, 0.88, 0.54 }, text = { 0.95, 1.00, 0.92 }, spark = { 0.85, 1.00, 0.75 },
      barBg = { 0.05, 0.09, 0.05, 0.80 }, border = { 0.28, 0.40, 0.26, 1.00 },
      panel = { 0.05, 0.07, 0.05, 0.95 }, iconEdge = { 0.38, 0.56, 0.36, 1.00 } },
    { key = "saltbound", name = "Saltbound", style = "flat",
      bar = { 0.30, 0.48, 0.54 }, swing = { 0.52, 0.50, 0.44 }, combo = { 0.74, 0.90, 0.92 },
      accent = { 0.72, 0.88, 0.90 }, text = { 0.95, 0.99, 0.99 }, spark = { 0.90, 1.00, 1.00 },
      barBg = { 0.05, 0.08, 0.09, 0.80 }, border = { 0.30, 0.42, 0.46, 1.00 },
      panel = { 0.05, 0.07, 0.08, 0.95 }, iconEdge = { 0.38, 0.54, 0.58, 1.00 } },
    { key = "wraithglass", name = "Wraithglass", style = "frost",
      bar = { 0.30, 0.52, 0.50 }, swing = { 0.42, 0.46, 0.56 }, combo = { 0.66, 0.98, 0.92 },
      accent = { 0.64, 0.96, 0.90 }, text = { 0.93, 1.00, 0.99 }, spark = { 0.80, 1.00, 0.98 },
      barBg = { 0.04, 0.09, 0.09, 0.72 }, border = { 0.30, 0.52, 0.50, 0.90 },
      panel = { 0.04, 0.07, 0.08, 0.92 }, iconEdge = { 0.40, 0.70, 0.66, 1.00 } },
    { key = "emberwood", name = "Emberwood", style = "ember",
      bar = { 0.60, 0.34, 0.16 }, swing = { 0.40, 0.46, 0.24 }, combo = { 0.98, 0.66, 0.34 },
      accent = { 0.96, 0.64, 0.32 }, text = { 1.00, 0.95, 0.88 }, spark = { 1.00, 0.82, 0.55 },
      barBg = { 0.11, 0.06, 0.03, 0.82 }, border = { 0.44, 0.26, 0.14, 1.00 },
      panel = { 0.08, 0.06, 0.04, 0.95 }, iconEdge = { 0.60, 0.36, 0.18, 1.00 } },
    { key = "silver_chalice", name = "Silver Chalice", style = "gilded",
      bar = { 0.48, 0.50, 0.54 }, swing = { 0.56, 0.30, 0.36 }, combo = { 0.92, 0.94, 0.98 },
      accent = { 0.90, 0.92, 0.97 }, text = { 1.00, 1.00, 1.00 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.09, 0.09, 0.10, 0.80 }, border = { 0.60, 0.62, 0.66, 1.00 },
      panel = { 0.07, 0.07, 0.08, 0.95 }, iconEdge = { 0.78, 0.80, 0.84, 1.00 } },
    { key = "rotgarden", name = "Rotgarden", style = "line",
      bar = { 0.40, 0.44, 0.18 }, swing = { 0.48, 0.30, 0.34 }, combo = { 0.80, 0.84, 0.36 },
      accent = { 0.78, 0.82, 0.36 }, text = { 0.98, 0.99, 0.88 }, spark = { 0.95, 1.00, 0.60 },
      barBg = { 0.07, 0.08, 0.03, 0.82 }, border = { 0.34, 0.38, 0.16, 1.00 },
      panel = { 0.06, 0.07, 0.04, 0.95 }, iconEdge = { 0.48, 0.54, 0.22, 1.00 } },
    { key = "starfall", name = "Starfall", style = "rune",
      bar = { 0.30, 0.26, 0.70 }, swing = { 0.50, 0.40, 0.66 }, combo = { 1.00, 0.90, 0.56 },
      accent = { 1.00, 0.88, 0.54 }, text = { 0.97, 0.96, 1.00 }, spark = { 1.00, 0.96, 0.80 },
      barBg = { 0.05, 0.04, 0.13, 0.82 }, border = { 0.30, 0.28, 0.62, 1.00 },
      panel = { 0.04, 0.04, 0.09, 0.96 }, iconEdge = { 0.44, 0.40, 0.90, 1.00 } },
    { key = "trollhunt", name = "Trollhunt", style = "bevel",
      bar = { 0.20, 0.50, 0.44 }, swing = { 0.62, 0.36, 0.24 }, combo = { 0.98, 0.60, 0.36 },
      accent = { 0.96, 0.58, 0.34 }, text = { 0.95, 1.00, 0.97 }, spark = { 1.00, 0.85, 0.65 },
      barBg = { 0.03, 0.09, 0.08, 0.80 }, border = { 0.22, 0.42, 0.38, 1.00 },
      panel = { 0.04, 0.07, 0.06, 0.95 }, iconEdge = { 0.28, 0.60, 0.54, 1.00 } },
    { key = "brimstone", name = "Brimstone", style = "ember",
      bar = { 0.74, 0.46, 0.06 }, swing = { 0.62, 0.22, 0.14 }, combo = { 1.00, 0.84, 0.20 },
      accent = { 1.00, 0.82, 0.18 }, text = { 1.00, 0.97, 0.84 }, spark = { 1.00, 0.95, 0.50 },
      barBg = { 0.13, 0.08, 0.02, 0.82 }, border = { 0.54, 0.36, 0.06, 1.00 },
      panel = { 0.08, 0.06, 0.03, 0.95 }, iconEdge = { 0.74, 0.50, 0.08, 1.00 } },
    { key = "gloam", name = "Gloam", style = "flat",
      bar = { 0.36, 0.30, 0.48 }, swing = { 0.44, 0.38, 0.44 }, combo = { 0.76, 0.68, 0.90 },
      accent = { 0.74, 0.66, 0.88 }, text = { 0.96, 0.94, 0.99 }, spark = { 0.92, 0.88, 1.00 },
      barBg = { 0.06, 0.05, 0.08, 0.82 }, border = { 0.32, 0.28, 0.42, 1.00 },
      panel = { 0.05, 0.05, 0.07, 0.95 }, iconEdge = { 0.44, 0.38, 0.58, 1.00 } },
    { key = "frostfang", name = "Frostfang", style = "frost",
      bar = { 0.30, 0.56, 0.72 }, swing = { 0.44, 0.50, 0.58 }, combo = { 0.80, 0.95, 1.00 },
      accent = { 0.78, 0.94, 1.00 }, text = { 0.95, 0.99, 1.00 }, spark = { 0.92, 1.00, 1.00 },
      barBg = { 0.05, 0.10, 0.14, 0.80 }, border = { 0.34, 0.56, 0.70, 1.00 },
      panel = { 0.04, 0.07, 0.10, 0.95 }, iconEdge = { 0.46, 0.74, 0.92, 1.00 } },
    { key = "beastcaller", name = "Beastcaller", style = "line",
      bar = { 0.56, 0.40, 0.20 }, swing = { 0.34, 0.48, 0.26 }, combo = { 0.96, 0.74, 0.40 },
      accent = { 0.94, 0.72, 0.38 }, text = { 1.00, 0.97, 0.90 }, spark = { 1.00, 0.88, 0.60 },
      barBg = { 0.10, 0.07, 0.04, 0.82 }, border = { 0.44, 0.32, 0.18, 1.00 },
      panel = { 0.07, 0.06, 0.04, 0.95 }, iconEdge = { 0.60, 0.44, 0.22, 1.00 } },
    { key = "vaultlight", name = "Vaultlight", style = "gilded",
      bar = { 0.60, 0.52, 0.22 }, swing = { 0.38, 0.44, 0.60 }, combo = { 1.00, 0.92, 0.56 },
      accent = { 1.00, 0.90, 0.52 }, text = { 1.00, 0.98, 0.90 }, spark = { 1.00, 0.97, 0.75 },
      barBg = { 0.10, 0.09, 0.04, 0.82 }, border = { 0.58, 0.50, 0.22, 1.00 },
      panel = { 0.07, 0.07, 0.05, 0.95 }, iconEdge = { 0.78, 0.68, 0.28, 1.00 } },
}
local SKIN_BY_KEY = {}
for _, s in ipairs(SKINS) do SKIN_BY_KEY[s.key] = s end
FRHW_SKINS = SKINS   -- read-only view for macros and the test suite

-- Edit mode: only while the config window is open may anything be moved.
local function EditMode()
    return panel ~= nil and panel:IsShown()
end

-- Whether the HUD should be on screen right now. Auto-hide out of combat is
-- the only rule that can hide everything at once; the config window being
-- open always shows it, so an element can still be found and dragged.
local function HudVisible()
    if not db or not db.shown then return false end
    if db.autoHideOOC and not EditMode() then
        if not UnitAffectingCombat("player") then return false end
    end
    return true
end

local function DeepCopy(t)
    local n = {}
    for k, v in pairs(t) do n[k] = (type(v) == "table") and DeepCopy(v) or v end
    return n
end

-- Standard Forever guard: nil is not readable, secret values are not readable,
-- and canaccessvalue confirms this code may look at it.
local function IsReadable(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    if canaccessvalue and not canaccessvalue(v) then return false end
    return true
end

-- Forward declarations
local ApplyElement, ApplySpell, ApplyAll, RefreshConfig, RefreshProfileList
local ApplySkin, PaintSwing, LayoutSwing, ReflowAll

-----------------------------------------------------------------------
-- Element frames (energy, swing, combo)
-----------------------------------------------------------------------
local function MakeStatusBar(name, r, g, b)
    local bar = CreateFrame("StatusBar", name, UIParent)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarColor(r, g, b, 1)
    bar:SetFrameStrata("MEDIUM")
    bar.bg = bar:CreateTexture(nil, "BORDER")
    bar.bg:SetAllPoints(true)
    bar.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    bar.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.7)
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:Hide()
    return bar
end

local energy = MakeStatusBar("ForeverWarriorHUD_Energy", 1.0, 0.96, 0.41)
energy.value = energy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
energy.value:SetPoint("CENTER")

local swing = MakeStatusBar("ForeverWarriorHUD_Swing", 0.85, 0.85, 0.95)
swing.time = swing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
swing.time:SetPoint("CENTER")

-- Energy regeneration: a second, independent bar. It is its own frame, so it
-- drags and resizes on its own exactly like the energy bar does.
local regen = MakeStatusBar("ForeverWarriorHUD_Regen", 0.35, 0.72, 0.95)
regen.value = regen:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
regen.value:SetPoint("CENTER")

local cpHolder = CreateFrame("Frame", "ForeverWarriorHUD_Combo", UIParent)
cpHolder:SetFrameStrata("MEDIUM")
local MAX_COMBO_POINTS = 5
local cpBars = {}
for i = 1, MAX_COMBO_POINTS do
    local b = CreateFrame("StatusBar", nil, cpHolder)
    b:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    b:SetMinMaxValues(0, 1)
    b:SetStatusBarColor(1, 0.6, 0, 1)
    b:SetAlpha(0.2)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetAllPoints(true)
    b.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    b.bg:SetVertexColor(1, 0.6, 0, 0.15)
    cpBars[i] = b
end

local elems = { energy = energy, swing = swing, combo = cpHolder, regen = regen }

-----------------------------------------------------------------------
-- Spell reminder icons
-----------------------------------------------------------------------
local spellIcons = {}
for _, a in ipairs(ABILITIES) do
    local btn = CreateFrame("Frame", "ForeverWarriorHUD_Spell_" .. a.key, UIParent, "BackdropTemplate")
    btn:SetSize(26, 26)
    btn:SetFrameStrata("MEDIUM")
    btn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
                      edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                      edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    btn:SetBackdropColor(0, 0, 0, 0.6)
    btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints(btn.icon)
    btn.cd:SetDrawEdge(false)
    -- our own countdown text replaces the template's numbers, so there is one
    -- number per icon and it has a toggle
    btn.cd:SetHideCountdownNumbers(true)
    if btn.cd.SetSwipeColor then btn.cd:SetSwipeColor(0, 0, 0, 0.75) end
    -- a font string on the icon itself would be drawn under the Cooldown child
    -- frame; this holder sits above it
    btn.over = CreateFrame("Frame", nil, btn)
    btn.over:SetAllPoints(btn)
    -- the number must never be covered: its holder is a strata above the HUD
    if btn.over.SetFrameStrata then btn.over:SetFrameStrata("HIGH") end
    if btn.over.SetFrameLevel and btn.cd.GetFrameLevel then
        btn.over:SetFrameLevel(btn.cd:GetFrameLevel() + 2)
    end
    btn.timer = btn.over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if btn.timer.SetDrawLayer then btn.timer:SetDrawLayer("OVERLAY", 7) end
    -- bottom right corner of the box
    btn.timer:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.timer:SetJustifyH("RIGHT")
    btn.timer:SetShadowColor(0, 0, 0, 1)
    btn.timer:SetShadowOffset(1, -1)
    btn.timer:SetText("")
    -- lit while the ability's own effect is on the player
    btn.glow = btn.over:CreateTexture(nil, "BACKGROUND")
    btn.glow:SetTexture(WHITE)
    btn.glow:SetAllPoints(btn)
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetVertexColor(1, 0.85, 0.3, 0.35)
    btn.glow:Hide()
    -- the light that flashes over the picture when the ability is ready again
    btn.ready = btn.over:CreateTexture(nil, "ARTWORK")
    btn.ready:SetTexture(WHITE)
    btn.ready:SetAllPoints(btn)
    btn.ready:SetBlendMode("ADD")
    btn.ready:SetVertexColor(1, 1, 0.8, 1)
    btn.ready:Hide()
    btn.spell = a
    btn.spellId = a.id   -- replaced by ResolveSpells() once the client answers
    spellIcons[a.key] = btn
end

-----------------------------------------------------------------------
-- Skin plumbing: decorative textures and the list of things to repaint
-----------------------------------------------------------------------
-- Every decorative texture is WHITE8X8 tinted with SetVertexColor, so there
-- is no texture path here that could be missing on this client.
local function Decor(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(WHITE)
    return t
end

-- Widgets register themselves here as they are built; ApplySkin walks the
-- lists. That is what lets one skin change repaint the options window
-- without any per-widget colour code.
local skinned = {
    text = {},        -- font strings in the skin's text colour
    accentText = {},  -- font strings in the accent colour (section headers)
    dividers = {},    -- 1 px rules
    headerBars = {},  -- tinted bars behind section headers
    gutters = {},     -- scrollbar gutters
    sliders = {},     -- OptionsSliderTemplate sliders (track + thumb tint)
    tabs = {},        -- selected-tab accent bars
}

-- True while a refresh or a reflow is driving the widgets. Slider handlers
-- still update their value label but do not write to db, so neither resizing
-- the window nor repainting the panel can change the saved configuration.
local suppress = false

-----------------------------------------------------------------------
-- Swing extras (1.9.0): ready flash and tick marks
-----------------------------------------------------------------------
swing.flash = Decor(swing, "OVERLAY")
swing.flash:SetAllPoints(true)
swing.flash:SetBlendMode("ADD")
swing.flash:Hide()
swing.ticks = {}

-- Size the spark and lay the tick marks out over the bar. Called from
-- ApplyElement("swing"), so it follows width, height and orientation.
LayoutSwing = function(e)
    local size = e.sparkSize or 20
    swing.spark:SetSize(size, e.h * size / 10)   -- 20 px wide = twice the bar height, as before
    if not e.spark then swing.spark:Hide() end
    if not e.flash then swing.flash:Hide() end
    swing.time:SetShown(e.text and e.textMode ~= "none")
    local n = e.ticks and e.tickCount or 0
    for i = 1, n do
        local t = swing.ticks[i]
        if not t then
            t = Decor(swing, "OVERLAY")
            swing.ticks[i] = t
        end
        t:ClearAllPoints()
        if ME.Vertical(e) then
            -- a turned bar is e.h wide and e.w tall
            t:SetPoint("BOTTOMLEFT", swing, "BOTTOMLEFT", 0, e.w * i / (n + 1))
            t:SetSize(e.h, 1)
        else
            t:SetPoint("TOPLEFT", swing, "TOPLEFT", e.w * i / (n + 1), 0)
            t:SetSize(1, e.h)
        end
        t:Show()
    end
    for i = n + 1, #swing.ticks do swing.ticks[i]:Hide() end
    PaintSwing()
end

-----------------------------------------------------------------------
-- Edge kits: the textures a skin's style flag draws around a frame
-----------------------------------------------------------------------
-- Outlines sit 1 px OUTSIDE the frame and inlays inside it, so a style never
-- changes a frame's size or position. Spell icons already have a backdrop
-- border, so their kit is "inner": inlays and pips only.
local edgeKits = {}
local function MakeEdges(fr, inner)
    local k = {}
    local function Piece()
        local t = Decor(fr, "OVERLAY")
        t:Hide()
        return t
    end
    if not inner then
        local top, bottom, left, right = Piece(), Piece(), Piece(), Piece()
        top:SetPoint("BOTTOMLEFT", fr, "TOPLEFT", -1, 0)
        top:SetPoint("BOTTOMRIGHT", fr, "TOPRIGHT", 1, 0)
        top:SetHeight(1)
        bottom:SetPoint("TOPLEFT", fr, "BOTTOMLEFT", -1, 0)
        bottom:SetPoint("TOPRIGHT", fr, "BOTTOMRIGHT", 1, 0)
        bottom:SetHeight(1)
        left:SetPoint("TOPRIGHT", fr, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMRIGHT", fr, "BOTTOMLEFT", 0, 0)
        left:SetWidth(1)
        right:SetPoint("TOPLEFT", fr, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMLEFT", fr, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(1)
        k.sides = { top, bottom, left, right }
    end
    local inset = inner and 1 or 0
    k.hi = Piece()
    k.hi:SetPoint("TOPLEFT", fr, "TOPLEFT", inset, -inset)
    k.hi:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -inset, -inset)
    k.hi:SetHeight(1)
    k.lo = Piece()
    k.lo:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", inset, inset)
    k.lo:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -inset, inset)
    k.lo:SetHeight(1)
    -- corner pips: on the outline for bars, just inside the border for icons
    k.pips = {}
    local corners = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
    local d = inner and 1 or -1
    for i = 1, 4 do
        local sx = (i == 1 or i == 3) and 1 or -1
        local sy = (i <= 2) and -1 or 1
        local p = Piece()
        p:SetSize(3, 3)
        p:SetPoint(corners[i], fr, corners[i], sx * d, sy * d)
        k.pips[i] = p
    end
    edgeKits[#edgeKits + 1] = k
    return k
end

local function PaintEdges(k, skin)
    local st = skin.style
    local ar, ag, ab = skin.accent[1], skin.accent[2], skin.accent[3]
    if k.sides then
        for i = 1, 4 do
            k.sides[i]:SetVertexColor(skin.border[1], skin.border[2], skin.border[3], skin.border[4])
            k.sides[i]:SetShown(st ~= "flat")
        end
    end
    k.hi:Hide(); k.hi:SetHeight(1); k.hi:SetBlendMode("BLEND")
    k.lo:Hide(); k.lo:SetHeight(1); k.lo:SetBlendMode("BLEND")
    for i = 1, 4 do k.pips[i]:Hide() end
    if st == "bevel" then
        k.hi:SetVertexColor(1, 1, 1, 0.28); k.hi:Show()
        k.lo:SetVertexColor(0, 0, 0, 0.40); k.lo:Show()
    elseif st == "rune" then
        for i = 1, 4 do
            k.pips[i]:SetVertexColor(ar, ag, ab, 1)
            k.pips[i]:Show()
        end
    elseif st == "ember" then
        k.hi:SetVertexColor(0, 0, 0, 0.30); k.hi:Show()
        k.lo:SetHeight(2); k.lo:SetBlendMode("ADD")
        k.lo:SetVertexColor(ar, ag, ab, 0.60); k.lo:Show()
    elseif st == "frost" then
        k.hi:SetHeight(2)
        k.hi:SetVertexColor(1, 1, 1, 0.38); k.hi:Show()
        for i = 1, 4 do
            k.pips[i]:SetVertexColor(1, 1, 1, 0.55)
            k.pips[i]:Show()
        end
    elseif st == "gilded" then
        k.hi:SetVertexColor(ar, ag, ab, 0.75); k.hi:Show()
        k.lo:SetVertexColor(ar, ag, ab, 0.75); k.lo:Show()
    end
end

MakeEdges(energy)
MakeEdges(swing)
MakeEdges(regen)
for i = 1, MAX_COMBO_POINTS do MakeEdges(cpBars[i]) end
for _, a in ipairs(ABILITIES) do MakeEdges(spellIcons[a.key], true) end

-----------------------------------------------------------------------
-- Dragging: only while the config window is open. Hold CTRL and left-drag an
-- element or an icon to move that one item. The grid is on screen for as long
-- as the window is open, and a dropped item snaps to it and sticks to the
-- edges of the items it comes close to.
-----------------------------------------------------------------------
-- centre of a frame in UIParent units, independent of the frame's own scale
local function ScreenCenter(fr)
    local x, y = fr:GetCenter()
    if not x then return nil end
    local k = fr:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, y * k
end

-- Width and height of a frame in UIParent units.
local function ScreenSize(fr)
    local k = fr:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (fr:GetWidth() or 0) * k, (fr:GetHeight() or 0) * k
end

-- Drop the frame where it was released and let the caller write the final
-- position, so a snapped or stuck position is what actually gets saved.
local function FinishDrag(self, reapply)
    self:StopMovingOrSizing()
    if reapply then reapply() end
end

-- Move an item so its edge abuts the nearest neighbour's edge. Everything
-- here is in offset space (the same units cfg.x / cfg.y are stored in), so a
-- stuck position can be written straight into the configuration. "Close" is
-- measured as the gap between the two edges, not the distance between
-- centres, so a bar dropped a few pixels beside another one clicks into place
-- whatever their sizes are. Nothing here runs unless the sticky option is on.
local function StickToNeighbours(self, cx, cy, ux, uy)
    -- snap off = the item stays exactly where it was released
    if not db.sticky or not db.gridSnap then return cx, cy end
    local mw, mh = ScreenSize(self)
    local best, bestGap, bestAxis
    for _, other in ipairs(ALL_ITEMS) do
        if other ~= self and other:IsShown() and (not other.IsVisible or other:IsVisible()) then
            local ox, oy = ScreenCenter(other)
            if ox then
                local ow, oh = ScreenSize(other)
                -- gap between the facing edges; below zero the two overlap on that axis
                local gx = math.abs(cx - (ox - ux - db.baseX)) - (ow + mw) / 2
                local gy = math.abs(cy - (oy - uy - db.baseY)) - (oh + mh) / 2
                local gap, axis
                if gy < 0 and math.abs(gx) <= STICK_DISTANCE then
                    gap, axis = math.abs(gx), "x"      -- beside it: left or right edge
                elseif gx < 0 and math.abs(gy) <= STICK_DISTANCE then
                    gap, axis = math.abs(gy), "y"      -- above or below it
                end
                if gap and (not bestGap or gap < bestGap) then
                    best, bestGap, bestAxis = other, gap, axis
                end
            end
        end
    end
    if not best then return cx, cy end
    local ox, oy = ScreenCenter(best)
    if not ox then return cx, cy end
    local ocx = ox - ux - db.baseX
    local ocy = oy - uy - db.baseY
    local ow, oh = ScreenSize(best)
    -- line up centres or an outer edge, whichever is nearest, if it is close already
    local function Align(v, o, half)
        local pick, d = nil, STICK_DISTANCE
        for _, cand in ipairs({ o, o + half, o - half }) do
            local dd = math.abs(v - cand)
            if dd <= d then pick, d = cand, dd end
        end
        return pick
    end
    local stuckX, stuckY = false, false
    if bestAxis == "x" then
        cx = ocx + (cx >= ocx and 1 or -1) * (ow + mw) / 2
        stuckX = true
        local a = Align(cy, ocy, (oh - mh) / 2)
        if a then cy, stuckY = a, true end
    else
        cy = ocy + (cy >= ocy and 1 or -1) * (oh + mh) / 2
        stuckY = true
        local a = Align(cx, ocx, (ow - mw) / 2)
        if a then cx, stuckX = a, true end
    end
    return cx, cy, stuckX, stuckY
end

-----------------------------------------------------------------------
-- Mouse editing. Everything here only acts while the options window is open
-- (and Lock is off). Hover an item, hold CTRL, then:
--   left button held     the item follows the cursor until release
--   mouse wheel          bigger / smaller
--   right button held    turn it by dragging; it stays where you leave it
--   right double-click   back to its original orientation (no CTRL needed)
-- Position, size and rotation are therefore NOT in the options window.
-----------------------------------------------------------------------
ME.SCALE_STEP = 0.05   -- per wheel notch
ME.DOUBLE = 0.4        -- seconds between the two clicks of a double-click

function ME.Active()
    return db ~= nil and not db.locked and EditMode()
end

-- Bars and rows turn in quarter turns (a status bar cannot be drawn at an
-- angle); icons turn freely, with a soft stop on the quarters.
function ME.Norm(rot, free)
    rot = (tonumber(rot) or 0) % 360
    if free then
        local q = math.floor(rot / 90 + 0.5) * 90
        if math.abs(rot - q) <= 4 then rot = q end
        rot = math.floor(rot + 0.5)
    else
        rot = math.floor(rot / 90 + 0.5) * 90
    end
    return rot % 360
end
function ME.Vertical(e) return (e.rot or 0) % 180 == 90 end
function ME.Reversed(e) return (e.rot or 0) >= 180 end
-- which place the i-th of n pieces takes in a row that may be reversed
function ME.Slot(e, i, n)
    if ME.Reversed(e) then return n + 1 - i end
    return i
end
-- the end of a bar its fill grows towards
function ME.SparkAnchor(e)
    if ME.Vertical(e) then return ME.Reversed(e) and "BOTTOM" or "TOP" end
    return ME.Reversed(e) and "LEFT" or "RIGHT"
end

-- angle of the cursor around an item's centre, in degrees
function ME.CursorAngle(fr)
    local fx, fy = ScreenCenter(fr)
    if not fx or not GetCursorPosition then return nil end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    x, y = x / s, y / s
    if x == fx and y == fy then return nil end
    return math.deg((math.atan2 or math.atan)(y - fy, x - fx))
end

-- left button released: snap, stick, store
function ME.Drop(self)
    self._dragging = false
    self:StopMovingOrSizing()
    local cfg = self._cfg()
    local fx, fy = ScreenCenter(self)
    local ux, uy = UIParent:GetCenter()
    if fx and ux then
        local cx = fx - ux - db.baseX
        local cy = fy - uy - db.baseY
        -- stick from where the item was really let go (never from a grid-rounded
        -- place), then the grid takes whichever axis did not stick
        local sx, sy
        cx, cy, sx, sy = StickToNeighbours(self, cx, cy, ux, uy)
        if not sx then cx = Snap(cx) end
        if not sy then cy = Snap(cy) end
        cfg.x = math.floor(cx + 0.5)
        cfg.y = math.floor(cy + 0.5)
    end
    FinishDrag(self, self._reapply)
end

-- while the right button is held: follow the cursor round the centre
function ME.Turn(self)
    local a = ME.CursorAngle(self)
    if not a or not ME.startAngle then return end
    local cfg = self._cfg()
    local rot = ME.Norm(ME.startRot + (a - ME.startAngle), self._freeRot)
    if rot ~= (cfg.rot or 0) then
        cfg.rot = rot
        ME.turned = true
        self._reapply()
    end
end

function ME.Watch()
    local fr = ME.held
    if fr and fr._rotating then ME.Turn(fr) return end
    if not (fr and fr._dragging) then
        ME.held = nil
        ME.watch:SetScript("OnUpdate", nil)
    end
end

function ME.Down(self, button)
    if not ME.Active() then return end
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    if button == "LeftButton" then
        self:StartMoving()
        self._dragging = true
        ME.held = self
    elseif button == "RightButton" then
        self._rotating = true
        ME.held = self
        ME.turned = false
        ME.startAngle = ME.CursorAngle(self)
        ME.startRot = self._cfg().rot or 0
        ME.watch:SetScript("OnUpdate", ME.Watch)
    end
end

function ME.Up(self, button)
    if button == "LeftButton" then
        if self._dragging then
            ME.Drop(self)
            ME.held = nil
        end
    elseif button == "RightButton" then
        local turned = false
        if self._rotating then
            ME.Turn(self)
            turned = ME.turned
            self._rotating = false
            ME.held = nil
            ME.watch:SetScript("OnUpdate", nil)
        end
        if not ME.Active() then return end
        if turned then
            self._lastRight = nil   -- the end of a turn is not a click
            return
        end
        local now = GetTime()
        if self._lastRight and now - self._lastRight <= ME.DOUBLE then
            self._lastRight = nil
            self._cfg().rot = 0
            self._reapply()
        else
            self._lastRight = now
        end
    end
end

function ME.Wheel(self, delta)
    if not ME.Active() then return end
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    local cfg = self._cfg()
    local sc = (cfg.scale or 1) + ((delta > 0) and ME.SCALE_STEP or -ME.SCALE_STEP)
    sc = math.floor(sc * 100 + 0.5) / 100
    if sc < 0.2 then sc = 0.2 elseif sc > 4 then sc = 4 end
    cfg.scale = sc
    self._reapply()
end

-- hover: light the item up and say what the mouse does to it
function ME.Enter(self)
    if not EditMode() then return end
    if self._edit then self._edit:SetVertexColor(0.2, 0.8, 1, 0.5) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self._label or "HUD item", 1, 1, 1)
    if db.locked then
        GameTooltip:AddLine("Locked. Untick Lock on the HUD tab to edit.", 1, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("CTRL + hold left button: move", nil, nil, nil, true)
        GameTooltip:AddLine("CTRL + mouse wheel: size", nil, nil, nil, true)
        GameTooltip:AddLine(self._freeRot and "CTRL + hold right button and drag: turn"
            or "CTRL + hold right button and drag: turn (quarter turns)", nil, nil, nil, true)
        GameTooltip:AddLine("Right double-click: original orientation", nil, nil, nil, true)
    end
    GameTooltip:Show()
end
function ME.Leave(self)
    if self._edit then self._edit:SetVertexColor(0.2, 0.8, 1, 0.25) end
    GameTooltip:Hide()
end

-- the options window closed with something still in the hand
function ME.Cancel()
    local fr = ME.held
    if fr then
        if fr._dragging then ME.Drop(fr) end
        fr._rotating = false
    end
    ME.held = nil
    ME.watch:SetScript("OnUpdate", nil)
end

ME.watch = CreateFrame("Frame")

-- Places in a page remembered while it is built, so a later section can put
-- its rows next to the options they belong to instead of on a tab of its own.
ME.mark = {}
function ME.Mark(key, flow, child)
    ME.mark[key] = { flow = flow, child = child, at = #flow.rows }
end
-- fn() appends rows to the marked flow; they are moved up to the mark.
function ME.InsertRows(key, fn)
    local m = ME.mark[key]
    local flow = m.flow
    local before = #flow.rows
    fn()
    local added = #flow.rows - before
    if added == 0 then return end
    local moved = {}
    for i = 1, added do moved[i] = table.remove(flow.rows, before + 1) end
    for i = 1, added do table.insert(flow.rows, m.at + i, moved[i]) end
    for _, other in pairs(ME.mark) do
        if other.flow == flow and other.at > m.at then other.at = other.at + added end
    end
    m.at = m.at + added
end

local function MakeDraggable(fr, getCfg, reapply, label, free)
    fr:SetMovable(true)
    fr:SetClampedToScreen(true)
    fr._cfg, fr._reapply, fr._label, fr._freeRot = getCfg, reapply, label, free
    fr:SetScript("OnMouseDown", ME.Down)
    fr:SetScript("OnMouseUp", ME.Up)
    fr:SetScript("OnMouseWheel", ME.Wheel)
    fr:SetScript("OnEnter", ME.Enter)
    fr:SetScript("OnLeave", ME.Leave)
    -- no mouse at all unless the options window is open
    fr:EnableMouse(false)
    if fr.EnableMouseWheel then fr:EnableMouseWheel(false) end
end
ME.MakeDraggable = MakeDraggable   -- for the sections that add their own items

-----------------------------------------------------------------------
-- Recent actions: the last few spells you cast, newest first, fading out
-----------------------------------------------------------------------
ME.TRAIL = 4          -- icons in the row
ME.TRAIL_LIFE = 6     -- seconds an icon stays
local trail = CreateFrame("Frame", "ForeverWarriorHUD_Trail", UIParent)
trail:SetFrameStrata("MEDIUM")
trail.icons, trail.log = {}, {}
for i = 1, ME.TRAIL do
    local t = trail:CreateTexture(nil, "ARTWORK")
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    trail.icons[i] = t
end

function ME.LayoutTrail(fr, e)
    local n, gap = ME.TRAIL, 2
    local vert = ME.Vertical(e)
    if vert then fr:SetSize(e.w, n * e.h + (n - 1) * gap) else fr:SetSize(n * e.w + (n - 1) * gap, e.h) end
    for i = 1, n do
        local t = fr.icons[i]
        local slot = ME.Slot(e, i, n) - 1
        t:ClearAllPoints()
        t:SetSize(e.w, e.h)
        if vert then
            t:SetPoint("BOTTOM", fr, "BOTTOM", 0, slot * (e.h + gap))
        else
            t:SetPoint("LEFT", fr, "LEFT", slot * (e.w + gap), 0)
        end
    end
    ME.PaintTrail()
end

-- alpha by age; with the options window open empty places show faintly so
-- the row can be found and grabbed
function ME.PaintTrail()
    local now = GetTime()
    for i = 1, ME.TRAIL do
        local t, entry = trail.icons[i], trail.log[i]
        local left = entry and (ME.TRAIL_LIFE - (now - entry.at)) or 0
        if left > 0 then
            t:SetTexture(entry.icon)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetAlpha(math.min(1, left / 2))
            t:Show()
        elseif EditMode() then
            t:SetTexture(WHITE)
            t:SetVertexColor(1, 1, 1, 0.12)
            t:SetAlpha(1)
            t:Show()
        else
            t:Hide()
        end
    end
end

-- UNIT_SPELLCAST_SUCCEEDED for the player. A spell ID the client keeps secret
-- is simply not logged.
function ME.LogCast(spellID)
    if not IsReadable(spellID) or type(spellID) ~= "number" then return end
    local icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and IsReadable(info.iconID) then icon = info.iconID end
    end
    if not icon then return end
    table.insert(trail.log, 1, { icon = icon, at = GetTime(), id = spellID })
    trail.log[ME.TRAIL + 1] = nil
    ME.PaintTrail()
end

-----------------------------------------------------------------------
-- Notifications on the ability icons. One row here = one toggle on the
-- Abilities tab, one saved field, one line in the profile clamp.
-----------------------------------------------------------------------
ME.NOTIFY = {
    { key = "cdOnly",     label = "Show an ability only while on cooldown" },
    { key = "sweep",      label = "Clock sweep while on cooldown" },
    { key = "cooldownDark", label = "Darken an ability while it is on cooldown" },
    { key = "readyFlash", label = "Flash when an ability comes off cooldown" },
    { key = "activeGlow", label = "Glow while the ability's effect is on you" },
    { key = "usableDim",  label = "Dim abilities you cannot use right now" },
    { key = "rangeTint",  label = "Red tint when the target is out of range" },
}
ME.FLASH = 0.35   -- seconds the ready flash lasts
ME.FADE = 0.45    -- seconds the icon then takes to fade out
-- How visible an ability icon is right now. btn._cooling and btn._readyAt are
-- set by UpdateSpellIcon from plain values only.
function ME.IconFade(btn, now)
    local base = btn._alpha or 1
    if not db or not db.notify or not db.notify.cdOnly or EditMode() or btn._cooling then
        btn._fading = nil
        if not btn._cooling and db and db.notify and not db.notify.cdOnly then btn._readyAt = nil end
        btn.ready:Hide()
        btn:SetAlpha(base)
        return
    end
    local flash = db.notify.readyFlash and ME.FLASH or 0
    local t = btn._readyAt and (now - btn._readyAt)
    if not t or t < 0 or t >= flash + ME.FADE then
        btn._readyAt, btn._fading = nil, nil
        btn.ready:Hide()
        btn:SetAlpha(0)
    elseif t < flash then
        btn._fading = true
        btn:SetAlpha(base)
        -- two quick pulses of light
        btn.ready:SetAlpha(0.7 * math.abs(math.cos(t / flash * math.pi * 2)))
        btn.ready:Show()
    else
        btn._fading = true
        btn.ready:Hide()
        btn:SetAlpha(base * (1 - (t - flash) / ME.FADE))
    end
end
function ME.ClampNotify(src)
    if type(db.notify) ~= "table" then db.notify = {} end
    for _, n in ipairs(ME.NOTIFY) do
        db.notify[n.key] = not (type(src) == "table" and src[n.key] == false)
    end
end

-- Usable / in range / effect active, each read under pcall and only compared
-- after IsReadable. Anything the client will not tell leaves the icon plain.
function ME.IconState(btn, id)
    local n = db.notify
    local dim, red, active = false, false, false
    if n.usableDim and C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, id)
        if ok and IsReadable(usable) and usable == false then dim = true end
    end
    if n.rangeTint and C_Spell and C_Spell.IsSpellInRange then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, id, "target")
        if ok and IsReadable(inRange) and inRange == false then red = true end
    end
    if n.activeGlow and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and IsReadable(aura) and type(aura) == "table" then active = true end
    end
    -- on cooldown: the picture goes dark and grey, under the clock sweep
    local cooling = n.cooldownDark and btn._cdStart ~= nil
    if red then btn.icon:SetVertexColor(1, 0.3, 0.3, 1)
    elseif cooling then btn.icon:SetVertexColor(0.35, 0.35, 0.35, 1)
    elseif dim then btn.icon:SetVertexColor(0.4, 0.4, 0.4, 1)
    else btn.icon:SetVertexColor(1, 1, 1, 1) end
    if btn.icon.SetDesaturated then btn.icon:SetDesaturated(cooling and true or false) end
    btn.glow:SetShown(active)
end

-----------------------------------------------------------------------
-- A small drop-down: a button that opens a list. Built from plain frames so
-- it does not depend on any menu template of the client.
-----------------------------------------------------------------------
function ME.Dropdown(parent, name, label, options, get, set)
    local dd = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    dd:SetSize(190, 22)
    dd._kind = "button"
    dd.options = options
    dd.list = CreateFrame("Frame", name .. "List", dd, "BackdropTemplate")
    dd.list:SetFrameStrata("DIALOG")
    dd.list:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    dd.list:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    dd.list:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    dd.list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    dd.list:SetSize(190, #options * 22 + 4)
    dd.list:Hide()
    dd.items = {}
    function dd.Refresh()
        local cur = get()
        local text = tostring(cur)
        for _, o in ipairs(options) do
            if o.value == cur then text = o.text end
        end
        dd:SetText(label .. ": " .. text)
    end
    for i, o in ipairs(options) do
        local b = CreateFrame("Button", name .. "Item" .. i, dd.list, "UIPanelButtonTemplate")
        b:SetSize(186, 20)
        b:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * 22))
        b:SetText(o.text)
        b:SetScript("OnClick", function()
            dd.list:Hide()
            set(o.value)
            dd.Refresh()
        end)
        dd.items[i] = b
    end
    dd:SetScript("OnClick", function() dd.list:SetShown(not dd.list:IsShown()) end)
    dd:SetScript("OnHide", function() dd.list:Hide() end)
    return dd
end

-----------------------------------------------------------------------
-- Menu artwork. The pictures live in the optional ForeverArt addon; without
-- it (or with "Off") the window is the plain skin colours.
-----------------------------------------------------------------------
ME.ART = "Interface\\AddOns\\ForeverArt\\warrior\\"
ME.HEADER = 80   -- height of the header band, banner included

function ME.ArtInfo()
    local a = _G.ForeverArt
    if type(a) ~= "table" or type(a.classes) ~= "table" then return nil end
    return a.classes["warrior"]
end

-- show the middle of a picture so it keeps its shape in a box of another shape
function ME.Crop(tex, boxW, boxH, picAspect)
    if not boxW or not boxH or boxW <= 0 or boxH <= 0 then return end
    local box = boxW / boxH
    if box > picAspect then
        local v = picAspect / box
        tex:SetTexCoord(0, 1, (1 - v) / 2, (1 + v) / 2)
    else
        local h = box / picAspect
        tex:SetTexCoord((1 - h) / 2, (1 + h) / 2, 0, 1)
    end
end

function ME.FitArt()
    local w, h = panel:GetWidth(), panel:GetHeight()
    ME.Crop(panel.artBack, w - 2, h - ME.HEADER - 2, 1)
    ME.Crop(panel.artBanner, w - 2, ME.HEADER - 1, 4)
end

function ME.ApplyArt()
    if not db then return end
    local info = ME.ArtInfo()
    local q = db.art
    local on = info ~= nil and q ~= "off"
    local sfx = (q == "low") and "_lo.tga" or "_hi.tga"
    -- ForeverArt says which pictures it really has for this class; a piece it
    -- does not list is never asked for, so a missing file cannot show as a
    -- blank square
    local hasBack = on and info.backdrop == true
    local hasBanner = on and (info.banner == true or info.banner2 == true)
    local hasCrest = on and info.crest == true
    panel.artBack:SetShown(hasBack)
    panel.artShade:SetShown(hasBack)
    panel.artBanner:SetShown(hasBanner)
    panel.artCrest:SetShown(hasCrest)
    if on then
        local banner = "banner"
        if info.banner2 == true and (db.artBanner == "b" or info.banner ~= true) then banner = "banner2" end
        if hasBack then panel.artBack:SetTexture(ME.ART .. "backdrop" .. sfx) end
        if hasBanner then panel.artBanner:SetTexture(ME.ART .. banner .. sfx) end
        if hasCrest then panel.artCrest:SetTexture(ME.ART .. "crest" .. sfx) end
        ME.FitArt()
    end
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOPLEFT", hasCrest and 86 or 12, -(ME.HEADER / 2 - 9))
    if ME.artDD then ME.artDD.Refresh() end
    if ME.bannerDD then
        ME.bannerDD.Refresh()
        ME.bannerDD:SetShown(on and info.banner == true and info.banner2 == true)
    end
    if ME.artNote then
        ME.artNote:SetText(info and "" or "Needs the ForeverArt addon.")
    end
end

elems.trail = trail

-----------------------------------------------------------------------
-- Custom colours. A custom scheme is a set of overrides on top of the chosen
-- skin: any part the player has not coloured keeps the skin's colour, and the
-- skin still picks the edge style. Schemes are saved by name in db.schemes,
-- apart from the live configuration (Reset to default keeps them).
-----------------------------------------------------------------------
ME.PARTS = {
    { key = "bar",      label = "Resource bar" },
    { key = "swing",    label = "Swing bar" },
    { key = "barBg",    label = "Bar background", alpha = true },
    { key = "spark",    label = "Spark and ready flash" },
    { key = "text",     label = "Text" },
    { key = "accent",   label = "Accent: headers, regen bar, glow" },
    { key = "border",   label = "Borders", alpha = true },
    { key = "panel",    label = "Window background", alpha = true },
    { key = "combo",    label = "Combo points" },
    { key = "iconEdge", label = "Icon border", alpha = true },
}
ME.PART = {}
for _, p in ipairs(ME.PARTS) do ME.PART[p.key] = p end
ME.MAX_SCHEMES = 40

-- { r, g, b [, a] } with every number in 0..1, or nil if it is not a colour
function ME.CleanColor(c, alpha)
    if type(c) ~= "table" then return nil end
    local out = {}
    for i = 1, 3 do
        local v = tonumber(c[i])
        if not v or v ~= v then return nil end
        out[i] = math.max(0, math.min(1, v))
    end
    if alpha then
        local a = tonumber(c[4])
        if not a or a ~= a then a = 1 end
        out[4] = math.max(0, math.min(1, a))
    end
    return out
end
function ME.CleanPalette(src)
    local out = {}
    if type(src) == "table" then
        for _, p in ipairs(ME.PARTS) do out[p.key] = ME.CleanColor(src[p.key], p.alpha) end
    end
    return out
end
function ME.ClampCustom(src, on)
    db.custom = ME.CleanPalette(src)
    db.customOn = on == true
end
-- the skin as painted: the chosen one, or the chosen one with the overrides
function ME.CustomSkin(base)
    if not (db and db.customOn and type(db.custom) == "table") then return base end
    local s = setmetatable({ _base = base }, { __index = base })
    for k, v in pairs(db.custom) do s[k] = v end
    return s
end
function ME.SetPart(key, r, g, b, a)
    local p = ME.PART[key]
    if not p or not db then return false end
    local c = ME.CleanColor({ r, g, b, a }, p.alpha)
    if not c then return false end
    if type(db.custom) ~= "table" then db.custom = {} end
    db.custom[key] = c
    db.customOn = true
    ApplySkin()   -- repaint with the current skin
    return true
end
function ME.SchemeName(s)
    s = tostring(s or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s > 32 then s = s:sub(1, 32) end
    return s
end
function ME.SchemeNames()
    local names = {}
    if db and type(db.schemes) == "table" then
        for name in pairs(db.schemes) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    table.sort(names, function(x, y) return x:lower() < y:lower() end)
    return names
end
function ME.SaveScheme(name)
    name = ME.SchemeName(name)
    if name == "" then return false, "Type a name for the colours first." end
    if type(db.schemes) ~= "table" then db.schemes = {} end
    if db.schemes[name] == nil and #ME.SchemeNames() >= ME.MAX_SCHEMES then
        return false, "Colour scheme limit reached (" .. ME.MAX_SCHEMES .. "). Delete one first."
    end
    db.schemes[name] = ME.CleanPalette(db.custom)
    return true, "Saved colours '" .. name .. "'."
end
function ME.LoadScheme(name)
    name = ME.SchemeName(name)
    local s = type(db.schemes) == "table" and db.schemes[name] or nil
    if type(s) ~= "table" then return false, "No saved colours named '" .. name .. "'." end
    db.custom = ME.CleanPalette(s)
    db.customOn = true
    ApplySkin()   -- repaint with the current skin
    return true, "Loaded colours '" .. name .. "'."
end
function ME.DeleteScheme(name)
    name = ME.SchemeName(name)
    if type(db.schemes) ~= "table" or db.schemes[name] == nil then
        return false, "No saved colours named '" .. name .. "'."
    end
    db.schemes[name] = nil
    return true, "Deleted colours '" .. name .. "'."
end

-- A list that opens under a button: used for the saved colour schemes.
function ME.OpenList(owner, names, onPick)
    local l = ME.list
    if not l then
        l = CreateFrame("Frame", "ForeverWarriorHUDList", panel, "BackdropTemplate")
        l:SetFrameStrata("DIALOG")
        l:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        l:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
        l:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        l.items = {}
        ME.list = l
    end
    if l:IsShown() and l.owner == owner then l:Hide() return end
    l.owner = owner
    local n = math.max(1, #names)
    for i = 1, n do
        local b = l.items[i]
        if not b then
            b = CreateFrame("Button", "ForeverWarriorHUDListItem" .. i, l, "UIPanelButtonTemplate")
            b:SetSize(176, 20)
            b:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * 22))
            l.items[i] = b
        end
        local name = names[i]
        b:SetText(name or "Nothing saved yet")
        b:SetScript("OnClick", function()
            l:Hide()
            if name then onPick(name) end
        end)
        b:Show()
    end
    for i = n + 1, #l.items do l.items[i]:Hide() end
    l:SetSize(180, n * 22 + 4)
    l:ClearAllPoints()
    l:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    l:Show()
end

-- The colour wheel. A ColorSelect widget draws the hue / saturation wheel and
-- the brightness bar itself; if this client will not create one, three
-- sliders stand in for it. Every change is applied live; Cancel puts the
-- starting colour back.
function ME.BuildWheel()
    local w = CreateFrame("Frame", "ForeverWarriorHUDWheel", panel, "BackdropTemplate")
    w:SetFrameStrata("DIALOG")
    w:SetSize(214, 286)
    w:EnableMouse(true)
    w:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    w:SetBackdropColor(0.04, 0.04, 0.06, 0.98)
    w:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("TOPLEFT", 10, -8)
    local function Slider(name, label, y, fn)
        local s = CreateFrame("Slider", name, w, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 14, y)
        s:SetWidth(186)
        s:SetHeight(14)
        s:SetMinMaxValues(0, 1)
        s:SetValueStep(0.01)
        _G[name .. "Low"]:SetText("")
        _G[name .. "High"]:SetText("")
        _G[name .. "Text"]:SetText(label)
        s:SetScript("OnValueChanged", function(_, v)
            if w.setting then return end
            fn(math.floor(v * 100 + 0.5) / 100)
            w.Changed()
        end)
        return s
    end
    local ok, cs = pcall(CreateFrame, "ColorSelect", "ForeverWarriorHUDWheelCS", w)
    if ok and cs and cs.SetColorWheelTexture and cs.SetColorRGB then
        cs:SetSize(190, 128)
        cs:SetPoint("TOPLEFT", 12, -28)
        local wt = cs:CreateTexture(nil, "ARTWORK")
        wt:SetSize(128, 128)
        wt:SetPoint("TOPLEFT", 0, 0)
        cs:SetColorWheelTexture(wt)
        local th = cs:CreateTexture(nil, "OVERLAY")
        th:SetTexture(WHITE)
        th:SetSize(6, 6)
        cs:SetColorWheelThumbTexture(th)
        local vt = cs:CreateTexture(nil, "ARTWORK")
        vt:SetSize(26, 128)
        vt:SetPoint("TOPLEFT", wt, "TOPRIGHT", 18, 0)
        cs:SetColorValueTexture(vt)
        local vth = cs:CreateTexture(nil, "OVERLAY")
        vth:SetTexture(WHITE)
        vth:SetSize(32, 4)
        cs:SetColorValueThumbTexture(vth)
        cs:SetScript("OnColorSelect", function(_, r, g, b)
            if w.setting then return end
            w.r, w.g, w.b = r, g, b
            w.Changed()
        end)
        w.cs = cs
    else
        w.rs = Slider("ForeverWarriorHUDWheelR", "Red", -44, function(v) w.r = v end)
        w.gs = Slider("ForeverWarriorHUDWheelG", "Green", -84, function(v) w.g = v end)
        w.bs = Slider("ForeverWarriorHUDWheelB", "Blue", -124, function(v) w.b = v end)
    end
    w.alpha = Slider("ForeverWarriorHUDWheelA", "Opacity", -180, function(v) w.a = v end)
    w.swatch = w:CreateTexture(nil, "ARTWORK")
    w.swatch:SetTexture(WHITE)
    w.swatch:SetSize(44, 18)
    w.swatch:SetPoint("TOPLEFT", 14, -204)
    w.info = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.info:SetPoint("LEFT", w.swatch, "RIGHT", 8, 0)
    function w.Paint()
        w.swatch:SetVertexColor(w.r, w.g, w.b, w.hasAlpha and w.a or 1)
        local t = string.format("%d  %d  %d", math.floor(w.r * 255 + 0.5), math.floor(w.g * 255 + 0.5), math.floor(w.b * 255 + 0.5))
        if w.hasAlpha then t = t .. string.format("   %d%%", math.floor(w.a * 100 + 0.5)) end
        w.info:SetText(t)
    end
    function w.Changed()
        w.Paint()
        if w.onChange then w.onChange(w.r, w.g, w.b, w.hasAlpha and w.a or nil) end
    end
    w.ok = CreateFrame("Button", "ForeverWarriorHUDWheelOK", w, "UIPanelButtonTemplate")
    w.ok:SetSize(88, 22)
    w.ok:SetPoint("BOTTOMLEFT", 12, 10)
    w.ok:SetText("Done")
    w.ok:SetScript("OnClick", function() w:Hide() end)
    w.cancel = CreateFrame("Button", "ForeverWarriorHUDWheelCancel", w, "UIPanelButtonTemplate")
    w.cancel:SetSize(88, 22)
    w.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    w.cancel:SetText("Cancel")
    w.cancel:SetScript("OnClick", function()
        local o = w.orig
        w.r, w.g, w.b, w.a = o[1], o[2], o[3], o[4]
        w.Changed()
        w:Hide()
    end)
    w:Hide()
    ME.wheel = w
    return w
end

function ME.OpenWheel(owner, title, r, g, b, a, hasAlpha, onChange)
    local w = ME.wheel or ME.BuildWheel()
    w.onChange = nil
    w.setting = true
    w.r, w.g, w.b, w.a = r, g, b, a or 1
    w.orig = { r, g, b, a or 1 }
    w.hasAlpha = hasAlpha and true or false
    w.title:SetText(title)
    if w.cs then
        w.cs:SetColorRGB(r, g, b)
    else
        w.rs:SetValue(r); w.gs:SetValue(g); w.bs:SetValue(b)
    end
    w.alpha:SetValue(w.a)
    w.alpha:SetShown(w.hasAlpha)
    w.setting = false
    w.Paint()
    w.onChange = onChange
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    w:Show()
end

MakeDraggable(energy,   function() return db.elements.energy end, function() ApplyElement("energy") end, "Rage bar")
MakeDraggable(regen,    function() return db.elements.regen end,  function() ApplyElement("regen") end, "Rage regen")
MakeDraggable(swing,    function() return db.elements.swing end,  function() ApplyElement("swing") end, "Swing timer")
MakeDraggable(cpHolder, function() return db.elements.combo end,  function() ApplyElement("combo") end, "Combo points")
MakeDraggable(trail,    function() return db.elements.trail end,  function() ApplyElement("trail") end, "Recent actions")
for key, btn in pairs(spellIcons) do
    -- icons are the items that turn to any angle
    MakeDraggable(btn, function() return db.spells[key] end, function() ApplySpell(key) end, btn.spell.name, true)
end
for _, fr in pairs(elems) do ALL_ITEMS[#ALL_ITEMS + 1] = fr end
for _, btn in pairs(spellIcons) do ALL_ITEMS[#ALL_ITEMS + 1] = btn end

-- mouse is enabled only while the config window is open; a faint outline
-- shows which items can be grabbed (hold Shift and drag)
local function SetItemsInteractive(on)
    if ME.onInteractive then ME.onInteractive(on) end
    for _, fr in ipairs(ALL_ITEMS) do
        fr:EnableMouse(on)
        if fr.EnableMouseWheel then fr:EnableMouseWheel(on) end
        if not fr._edit then
            local t = fr:CreateTexture(nil, "OVERLAY")
            t:SetAllPoints(true)
            t:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            t:SetVertexColor(0.2, 0.8, 1, 0.25)
            t:Hide()
            fr._edit = t
        end
        fr._edit:SetShown(on)
        if on and not fr:IsShown() then fr._ghost = true end
    end
end

-----------------------------------------------------------------------
-- Options panel with tabs
-----------------------------------------------------------------------
panel = CreateFrame("Frame", "ForeverWarriorHUDPanel", UIParent, "BackdropTemplate")
panel:SetSize(480, 660)
panel:SetPoint("CENTER")
panel:SetResizable(true)
if panel.SetResizeBounds then panel:SetResizeBounds(430, 360, 900, 860) end
-- A flat WHITE8X8 backdrop instead of the dialog art, so the skin's panel and
-- border colours paint the window exactly.
panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
panel:Hide()
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetScript("OnShow", function() SetItemsInteractive(true); ShowGrid(); ApplyAll() end)
panel:SetScript("OnHide", function() ME.Cancel(); SetItemsInteractive(false); HideGrid(); ApplyAll() end)
-- every page is laid out again from the new width (see ReflowAll), and the
-- grid is redrawn for the new screen size
panel:SetScript("OnSizeChanged", function() if panel.artBack then ME.FitArt() end; if ReflowAll then ReflowAll() end; if gridFrame and gridFrame:IsShown() then gridFrame:Update() end end)
tinsert(UISpecialFrames, "ForeverWarriorHUDPanel")

-- Header: tinted band, title, thin accent rule
panel.headerBand = Decor(panel, "BORDER")
panel.headerBand:SetPoint("TOPLEFT", 1, -1)
panel.headerBand:SetPoint("TOPRIGHT", -1, -1)
panel.headerBand:SetHeight(ME.HEADER - 1)
panel.rule = Decor(panel, "ARTWORK")
panel.rule:SetPoint("TOPLEFT", 1, -ME.HEADER)
panel.rule:SetPoint("TOPRIGHT", -1, -ME.HEADER)
panel.rule:SetHeight(1)

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.title:SetPoint("TOPLEFT", 12, -(ME.HEADER / 2 - 9))
-- Artwork (ForeverArt): a backdrop behind the pages, a banner in the header
-- and the class crest. All hidden until ME.ApplyArt finds the pictures.
panel.artBack = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
panel.artBack:SetPoint("TOPLEFT", 1, -ME.HEADER)
panel.artBack:SetPoint("BOTTOMRIGHT", -1, 1)
panel.artBack:Hide()
-- a veil over the backdrop so small text always reads
panel.artShade = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
panel.artShade:SetTexture(WHITE)
panel.artShade:SetVertexColor(0, 0, 0, 0.45)
panel.artShade:SetAllPoints(panel.artBack)
panel.artShade:Hide()
panel.artBanner = panel:CreateTexture(nil, "BORDER", nil, 1)
panel.artBanner:SetPoint("TOPLEFT", 1, -1)
panel.artBanner:SetPoint("TOPRIGHT", -1, -1)
panel.artBanner:SetHeight(ME.HEADER - 1)
panel.artBanner:Hide()
panel.artCrest = panel:CreateTexture(nil, "ARTWORK")
panel.artCrest:SetSize(68, 68)
panel.artCrest:SetPoint("TOPLEFT", 10, -6)
panel.artCrest:Hide()
panel.title:SetText("ForeverWarriorHUD")

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)

-- Footer: thin rule, then version and the drag hint
panel.footRule = Decor(panel, "ARTWORK")
panel.footRule:SetPoint("BOTTOMLEFT", 1, 22)
panel.footRule:SetPoint("BOTTOMRIGHT", -1, 22)
panel.footRule:SetHeight(1)
panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.hint:SetPoint("BOTTOMLEFT", 12, 7)
panel.hint:SetText("v" .. FRHW_VERSION .. "  -  CTRL + left: move   wheel: size   right: turn.  See the Help tab.")

-- bottom-right resize grip
local grip = CreateFrame("Button", nil, panel)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() panel:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(100, 20)
resetBtn:SetPoint("TOPRIGHT", -34, -6)
resetBtn:SetText("Reset to default")
resetBtn:SetScript("OnClick", function() StaticPopup_Show("FRHW_CONFIRM_RESET") end)

-- Four pages of content between the tab strip and the footer
local pageHUD    = CreateFrame("Frame", nil, panel)
pageHUD:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageHUD:SetPoint("BOTTOMRIGHT", -8, 26)
local pageConfig = CreateFrame("Frame", nil, panel)
pageConfig:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageConfig:SetPoint("BOTTOMRIGHT", -8, 26)
pageConfig:Hide()
local pageSkins = CreateFrame("Frame", nil, panel)
pageSkins:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageSkins:SetPoint("BOTTOMRIGHT", -8, 26)
pageSkins:Hide()
local pageProfiles = CreateFrame("Frame", nil, panel)
pageProfiles:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageProfiles:SetPoint("BOTTOMRIGHT", -8, 26)
pageProfiles:Hide()

-- Tabs keep PanelTabButtonTemplate; each gets a thin bar that is shown only
-- on the selected tab and tinted with the skin's accent colour.
local TABS = {}
local function SelectTab(which)
    local found = TABS[1]
    for _, t in ipairs(TABS) do
        if t.key == which then found = t end
    end
    for _, t in ipairs(TABS) do
        if t == found then
            t.page:Show()
            PanelTemplates_SelectTab(t.button)
        else
            t.page:Hide()
            PanelTemplates_DeselectTab(t.button)
        end
        t.button.accent:SetShown(t == found)
    end
    if found.key == "profiles" and RefreshProfileList then RefreshProfileList() end
end

local function AddTab(key, name, label, page)
    local tab = CreateFrame("Button", name, panel, "PanelTabButtonTemplate")
    if #TABS == 0 then
        tab:SetPoint("TOPLEFT", 12, -(ME.HEADER + 4))
    elseif #TABS == 5 then
        -- a sixth tab starts a second row; the pages move down to make room
        tab:SetPoint("TOPLEFT", 12, -(ME.HEADER + 30))
        ME.tabRows = 2
    else
        tab:SetPoint("LEFT", TABS[#TABS].button, "RIGHT", 4, 0)
    end
    tab:SetText(label)
    tab.accent = Decor(tab, "OVERLAY")
    tab.accent:SetPoint("BOTTOMLEFT", 6, 2)
    tab.accent:SetPoint("BOTTOMRIGHT", -6, 2)
    tab.accent:SetHeight(2)
    tab.accent:SetShown(#TABS == 0)   -- the HUD page is the one shown at load
    skinned.tabs[#skinned.tabs + 1] = tab.accent
    tab:SetScript("OnClick", function() SelectTab(key) end)
    TABS[#TABS + 1] = { key = key, button = tab, page = page }
    if ME.tabRows == 2 then
        for _, t in ipairs(TABS) do
            t.page:ClearAllPoints()
            t.page:SetPoint("TOPLEFT", 8, -(ME.HEADER + 64))
            t.page:SetPoint("BOTTOMRIGHT", -8, 26)
        end
    end
    return tab
end
AddTab("hud",      "FRHWTabHUD",      "HUD",      pageHUD)
AddTab("config",   "FRHWTabConfig",   "Abilities", pageConfig)
AddTab("skins",    "FRHWTabSkins",    "Skins",    pageSkins)
AddTab("profiles", "FRHWTabProfiles", "Profiles", pageProfiles)

-----------------------------------------------------------------------
-- Grid overlay (drawn only while an item is being dragged)
-----------------------------------------------------------------------
gridFrame = CreateFrame("Frame", "ForeverWarriorHUDGrid", UIParent)
gridFrame:SetAllPoints(UIParent)
gridFrame:SetFrameStrata("BACKGROUND")
gridFrame:Hide()
gridFrame.lines = {}
gridFrame.Update = function(self)
    if not db then return end
    local g = db.gridSize or 20
    if g < 4 then g = 4 end
    local w, h = UIParent:GetSize()
    local cx, cy = w / 2, h / 2
    local needed = math.ceil(w / g) + math.ceil(h / g) + 2
    for i = #self.lines + 1, needed do
        self.lines[i] = self:CreateTexture(nil, "BACKGROUND")
        self.lines[i]:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    end
    local n = 0
    for x = cx % g, w, g do
        n = n + 1
        local l = self.lines[n]
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
        l:SetSize(1, h)
        l:SetVertexColor(1, 1, 1, 0.08)
        l:Show()
    end
    for y = cy % g, h, g do
        n = n + 1
        local l = self.lines[n]
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        l:SetSize(w, 1)
        l:SetVertexColor(1, 1, 1, 0.08)
        l:Show()
    end
    for i = n + 1, #self.lines do self.lines[i]:Hide() end
end

-- Shared widget factories, parented to a given page. Sliders are compact:
-- the value sits inside the track and the label above it, so rows never
-- collide with the row below. The x / y / width passed in are only a first
-- placement; the page layout (ReflowFlow) positions every control from the
-- width that is actually available.
local function MakeCheck(parent, name, x, y, label, onClick)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(22, 22)
    local t = _G[name .. "Text"]
    t:SetFontObject(GameFontHighlightSmall)
    t:ClearAllPoints()
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", onClick)
    cb._kind = "check"
    skinned.text[#skinned.text + 1] = t
    return cb
end

local function MakeSlider(parent, name, x, y, width, minV, maxV, step, label, onChanged)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(width)
    s:SetHeight(14)
    _G[name .. "Low"]:SetFontObject(GameFontHighlightSmall)
    _G[name .. "High"]:SetFontObject(GameFontHighlightSmall)
    _G[name .. "Text"]:SetFontObject(GameFontHighlightSmall)
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    _G[name .. "Text"]:SetText(label)
    s.val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.val:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    -- skin-tinted strip behind the template's own track art
    s.track = Decor(s, "BACKGROUND")
    s.track:SetPoint("TOPLEFT", 0, -3)
    s.track:SetPoint("BOTTOMRIGHT", 0, 3)
    s:SetScript("OnValueChanged", function(self, v)
        if step >= 1 then v = math.floor(v + 0.5)
        else v = math.floor(v * 100 + 0.5) / 100 end
        s.val:SetText(tostring(v))
        -- a refresh or a reflow is moving the slider, not the user
        if suppress then return end
        onChanged(v)
    end)
    s._kind = "slider"
    skinned.sliders[#skinned.sliders + 1] = s
    skinned.text[#skinned.text + 1] = _G[name .. "Low"]
    skinned.text[#skinned.text + 1] = _G[name .. "High"]
    skinned.text[#skinned.text + 1] = _G[name .. "Text"]
    skinned.text[#skinned.text + 1] = s.val
    return s
end

local function MakeButton(parent, text, x, by, w, h, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, by)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b._kind = "button"
    return b
end

-- One divider style for the whole window: 1 px, low alpha, full content width.
local function MakeDivider(parent)
    local t = Decor(parent, "ARTWORK")
    t:SetHeight(1)
    skinned.dividers[#skinned.dividers + 1] = t
    return t
end

-- Section header: accent-coloured text on a small tinted bar.
local function MakeHeader(parent, text)
    local h = {}
    h.bar = Decor(parent, "BACKGROUND")
    h.fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.fs:SetText(text)
    skinned.headerBars[#skinned.headerBars + 1] = h.bar
    skinned.accentText[#skinned.accentText + 1] = h.fs
    return h
end

-----------------------------------------------------------------------
-- Responsive layout
-----------------------------------------------------------------------
-- 1.8.0 placed every control at a fixed x offset inside a 430 px scroll
-- child, so widening the window left dead space and narrowing it pushed the
-- right column under the scrollbar. Now each scrolling page is a "flow": a
-- list of rows that is laid out again from the scroll frame's width whenever
-- that width changes. Two columns and a gutter are derived from the width.
local LAYOUT = {
    pad = 6,            -- left / right margin inside the scroll child
    gutter = 20,        -- space between the two columns
    minWidth = 340,     -- never lay out narrower than this (the panel stops at 430)
    scrollGutter = 26,  -- strip to the right of a scroll frame that holds its scrollbar
    pageInset = 16,     -- pages are inset 8 px from the panel on each side
    check = 24, slider = 28, header = 24, divider = 8, note = 26,   -- row heights
    headerCheck = 64,   -- room at the right of a section header for its toggle
}

local function Columns(width)
    local colW = math.floor((width - 2 * LAYOUT.pad - LAYOUT.gutter) / 2)
    return LAYOUT.pad, LAYOUT.pad + colW + LAYOUT.gutter, colW
end

-- Width available to a scroll child. The scroll frame is anchored on two
-- corners, so its width follows the panel; if the client has not resolved
-- that rectangle yet (it can report 0 before the first layout pass) fall back
-- to the panel's own explicit width.
local function ScrollWidth(scroll)
    local w = scroll:GetWidth()
    if not w or w <= 0 then
        w = panel:GetWidth() - LAYOUT.pageInset - LAYOUT.scrollGutter
    end
    if w < LAYOUT.minWidth then w = LAYOUT.minWidth end
    return math.floor(w)
end

-- A scroll frame whose scrollbar lives in its own gutter. The frame stops
-- scrollGutter px short of the page edge and the bar is pinned inside that
-- strip, so the scroll child can be exactly as wide as the scroll frame
-- without anything sitting under the bar.
local function MakeScroll(name, page, top)
    local scroll = CreateFrame("ScrollFrame", name, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top)
    scroll:SetPoint("BOTTOMRIGHT", -LAYOUT.scrollGutter, 4)
    local child = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(child)
    local bar = _G[name .. "ScrollBar"] or scroll.ScrollBar
    if bar and bar.ClearAllPoints then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -16)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 16)
    end
    local gutter = Decor(page, "BACKGROUND")
    gutter:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    gutter:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 4)
    skinned.gutters[#skinned.gutters + 1] = gutter
    scroll:HookScript("OnSizeChanged", function() if ReflowAll then ReflowAll() end end)
    return scroll, child
end

local FLOWS = {}
local function NewFlow(scroll, child)
    local flow = { scroll = scroll, child = child, rows = {} }
    FLOWS[#FLOWS + 1] = flow
    return flow
end
-- Row kinds: a pair of controls (left / right column, optionally two half
-- width buttons sharing the left column), a section header with its toggle,
-- a divider, or a full-width note.
local function Row(flow, h, left, right, left2)
    flow.rows[#flow.rows + 1] = { h = h, left = left, right = right, left2 = left2 }
end
local function HeaderRow(flow, text, check)
    flow.rows[#flow.rows + 1] = { h = LAYOUT.header, header = MakeHeader(flow.child, text), check = check }
end
local function DividerRow(flow)
    flow.rows[#flow.rows + 1] = { h = LAYOUT.divider, divider = MakeDivider(flow.child) }
end
local function NoteRow(flow, text)
    local fs = flow.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    skinned.text[#skinned.text + 1] = fs
    flow.rows[#flow.rows + 1] = { h = LAYOUT.note, note = fs }
end

local function PlaceCell(w, x, y, width, rowH)
    w:ClearAllPoints()
    if w._kind == "slider" then
        w:SetPoint("TOPLEFT", x, y - 12)   -- 12 px above the track for the label
        w:SetWidth(width)
    elseif w._kind == "button" then
        w:SetPoint("TOPLEFT", x, y - math.floor((rowH - 22) / 2))
        w:SetWidth(width)
    else
        w:SetPoint("TOPLEFT", x, y - math.floor((rowH - 22) / 2))
    end
end

local function ReflowFlow(flow, width)
    local lx, rx, colW = Columns(width)
    local full = width - 2 * LAYOUT.pad
    local y = -4
    for i = 1, #flow.rows do
        local row = flow.rows[i]
        if row.header then
            row.header.bar:ClearAllPoints()
            row.header.bar:SetPoint("TOPLEFT", lx, y - 1)
            row.header.bar:SetSize(full, 18)
            row.header.fs:ClearAllPoints()
            row.header.fs:SetPoint("TOPLEFT", lx + 6, y - 4)
            if row.check then
                row.check:ClearAllPoints()
                row.check:SetPoint("TOPLEFT", lx + full - LAYOUT.headerCheck, y + 1)
            end
        elseif row.divider then
            row.divider:ClearAllPoints()
            row.divider:SetPoint("TOPLEFT", lx, y - 4)
            row.divider:SetSize(full, 1)
        elseif row.note then
            row.note:ClearAllPoints()
            row.note:SetPoint("TOPLEFT", lx, y - 2)
            row.note:SetWidth(full)
        else
            if row.left2 then
                local half = math.floor((colW - 4) / 2)
                PlaceCell(row.left, lx, y, half, row.h)
                PlaceCell(row.left2, lx + half + 4, y, half, row.h)
            elseif row.left then
                PlaceCell(row.left, lx, y, colW, row.h)
            end
            if row.right then PlaceCell(row.right, rx, y, colW, row.h) end
        end
        y = y - row.h
    end
    flow.child:SetSize(width, -y + 8)
    flow.width = width
end

-- ============================ HUD tab ============================
-- HUD tab content sits in a scroll frame too, so a resized-small panel still
-- reaches every control.
local hudScroll, hudChild = MakeScroll("FRHWHudScroll", pageHUD, -4)
local hudFlow = NewFlow(hudScroll, hudChild)

local showCB = MakeCheck(hudChild, "FRHWShowCB", 12, -6, "Show HUD", function(self)
    db.shown = self:GetChecked() and true or false
    ApplyAll()
end)
local lockCB = MakeCheck(hudChild, "FRHWLockCB", 120, -6, "Lock", function(self)
    db.locked = self:GetChecked() and true or false
end)
local autoCB = MakeCheck(hudChild, "FRHWAutoCB", 220, -6, "Auto-hide combo at 0", function(self)
    db.autoHide = self:GetChecked() and true or false
end)
local autoOOC = MakeCheck(hudChild, "FRHWAutoOOCCB", 12, -6, "Auto-hide out of combat", function(self)
    db.autoHideOOC = self:GetChecked() and true or false
    ApplyAll()
end)
local snapCB = MakeCheck(hudChild, "FRHWSnapCB", 12, -34, "Snap items to grid", function(self)
    db.gridSnap = self:GetChecked() and true or false
end)
local stickyCB = MakeCheck(hudChild, "FRHWStickyCB", 200, -34, "Stick items together", function(self)
    db.sticky = self:GetChecked() and true or false
end)
local gridSlider = MakeSlider(hudChild, "FRHWGridSlider", 240, -34, 190, 8, 64, 1, "Grid size", function(v)
    db.gridSize = v
end)

Row(hudFlow, LAYOUT.check, showCB, lockCB)
Row(hudFlow, LAYOUT.check, autoCB, autoOOC)
Row(hudFlow, LAYOUT.check, snapCB, stickyCB)
Row(hudFlow, LAYOUT.slider, gridSlider)
DividerRow(hudFlow)

-- Swing timer options. All of them live in db.elements.swing next to the
-- bar's position and size; the widgets are kept in one table so the refresh
-- code does not need a local per control.
local swingUI = {}
local function BuildSwingOptions(flow)
    local function cfg() return db.elements.swing end
    local function apply() ApplyElement("swing") end
    local function Check(name, label, field)
        return MakeCheck(hudChild, name, 0, 0, label, function(self)
            cfg()[field] = self:GetChecked() and true or false
            apply()
        end)
    end
    local function Slider(name, minV, maxV, step, label, field)
        return MakeSlider(hudChild, name, 0, 0, 190, minV, maxV, step, label, function(v)
            cfg()[field] = v
            apply()
        end)
    end
    -- Moving a colour slider means "I want my own colour", so it also turns
    -- the skin colour off; otherwise the sliders would appear to do nothing.
    local function Colour(name, label, field)
        return MakeSlider(hudChild, name, 0, 0, 190, 0, 1, 0.05, label, function(v)
            cfg()[field] = v
            cfg().useSkinColor = false
            swingUI.skinCB:SetChecked(false)
            apply()
        end)
    end

    swingUI.skinCB = Check("FRHWSW_SkinColor", "Use skin colour", "useSkinColor")
    swingUI.bgAlpha = Slider("FRHWSW_BgAlpha", 0, 1, 0.05, "Background opacity", "bgAlpha")
    swingUI.r = Colour("FRHWSW_R", "Bar red", "r")
    swingUI.g = Colour("FRHWSW_G", "Bar green", "g")
    swingUI.b = Colour("FRHWSW_B", "Bar blue", "b")
    swingUI.sparkSize = Slider("FRHWSW_SparkSize", 8, 40, 1, "Spark size", "sparkSize")
    swingUI.sparkCB = Check("FRHWSW_Spark", "Spark", "spark")
    swingUI.flashCB = Check("FRHWSW_Flash", "Ready flash (last 0.2 s)", "flash")
    swingUI.textCB = Check("FRHWSW_Text", "Text", "text")
    swingUI.textBtn = MakeButton(hudChild, SWING_TEXT_LABEL.elapsed, 0, 0, 190, 22, function()
        local cur, nextMode = cfg().textMode, SWING_TEXT_ORDER[1]
        for i, mode in ipairs(SWING_TEXT_ORDER) do
            if mode == cur then nextMode = SWING_TEXT_ORDER[i % #SWING_TEXT_ORDER + 1] end
        end
        cfg().textMode = nextMode
        apply(); FRHW_RefreshPanel()
    end, "FRHWSW_TextMode")
    swingUI.ticksCB = Check("FRHWSW_Ticks", "Ticks", "ticks")
    swingUI.tickCount = Slider("FRHWSW_TickCount", 1, 10, 1, "Tick count", "tickCount")
    swingUI.sourceBtn = MakeButton(hudChild, "Source: PLAYER_SWING", 0, 0, 190, 22, function()
        cfg().source = (cfg().source == "poll") and "event" or "poll"
        apply(); FRHW_RefreshPanel()
    end, "FRHWSW_Source")
    swingUI.resetCB = Check("FRHWSW_ResetOnTarget", "Reset on target change", "resetOnTarget")
    swingUI.manualCB = Check("FRHWSW_Manual", "Manual speed override", "manual")
    swingUI.manualSpeed = Slider("FRHWSW_ManualSpeed", 0.5, 4, 0.05, "Manual speed (s)", "manualSpeed")

    Row(flow, LAYOUT.slider, swingUI.skinCB, swingUI.bgAlpha)
    Row(flow, LAYOUT.slider, swingUI.r, swingUI.g)
    Row(flow, LAYOUT.slider, swingUI.b, swingUI.sparkSize)
    Row(flow, LAYOUT.check, swingUI.sparkCB, swingUI.flashCB)
    Row(flow, LAYOUT.slider, swingUI.textCB, swingUI.textBtn)
    Row(flow, LAYOUT.slider, swingUI.ticksCB, swingUI.tickCount)
    Row(flow, LAYOUT.slider, swingUI.sourceBtn, swingUI.resetCB)
    Row(flow, LAYOUT.slider, swingUI.manualCB, swingUI.manualSpeed)
end

-- Energy regen options. The bar is its own element (position, size, opacity,
-- scale and X/Y are in the shared element block above); these two are what the
-- bar measures and whether it prints the number.
local regenUI = {}
local function BuildRegenOptions(flow)
    local function cfg() return db.elements.regen end
    local function apply() ApplyElement("regen") end
    regenUI.rateCB = MakeCheck(hudChild, "FRHWREG_Rate", 0, 0, "Show rage / sec", function(self)
        cfg().showRate = self:GetChecked() and true or false
        apply()
    end)
    regenUI.maxSlider = MakeSlider(hudChild, "FRHWREG_Max", 0, 0, 190, 5, 60, 1, "Full at (rage/s)", function(v)
        cfg().regenMax = v
        apply()
    end)
    Row(flow, LAYOUT.check, regenUI.rateCB, regenUI.maxSlider)
end

local ELEMENT_INFO = {
    { key = "energy", label = "Rage bar", wmin = 60, wmax = 400, hmin = 4, hmax = 40 },
    { key = "regen",  label = "Rage regen", wmin = 60, wmax = 400, hmin = 4, hmax = 40 },
    { key = "swing",  label = "Swing timer",  wmin = 60, wmax = 400, hmin = 4, hmax = 40 },
    { key = "combo",  label = "Combo points", wmin = 4,  wmax = 60,  hmin = 4, hmax = 60 },
    { key = "trail",  label = "Recent actions", wmin = 10, wmax = 60, hmin = 10, hmax = 60 },
}
-- Width, height and opacity only: place, size and rotation are done with the
-- mouse on the item itself.
local elemCB, elemW, elemH, elemA = {}, {}, {}, {}
for _, info in ipairs(ELEMENT_INFO) do
    local key = info.key
    elemCB[key] = MakeCheck(hudChild, "FRHWCB_" .. key, 340, 0, "Show", function(self)
        db.elements[key].enabled = self:GetChecked() and true or false
        ApplyElement(key)
    end)
    elemW[key] = MakeSlider(hudChild, "FRHWW_" .. key, 12,  0, 190, info.wmin, info.wmax, 1, "Width", function(v)
        db.elements[key].w = v; ApplyElement(key)
    end)
    elemH[key] = MakeSlider(hudChild, "FRHWH_" .. key, 240, 0, 190, info.hmin, info.hmax, 1, "Height", function(v)
        db.elements[key].h = v; ApplyElement(key)
    end)
    elemA[key] = MakeSlider(hudChild, "FRHWA_" .. key, 12,  0, 190, 0.1, 1, 0.05, "Opacity", function(v)
        db.elements[key].alpha = v; ApplyElement(key)
    end)
    HeaderRow(hudFlow, info.label, elemCB[key])
    Row(hudFlow, LAYOUT.slider, elemW[key], elemH[key])
    if key == "energy" then
        -- the number on the bar has its own switch, next to the bar's options
        ME.valueCB = MakeCheck(hudChild, "FRHWEnergyText", 0, 0, "Show the value as text", function(self)
            db.elements.energy.showText = self:GetChecked() and true or false
            ApplyElement("energy")
        end)
        Row(hudFlow, LAYOUT.slider, elemA[key], ME.valueCB)
    else
        Row(hudFlow, LAYOUT.slider, elemA[key])
    end
    if key == "swing" then BuildSwingOptions(hudFlow) end
    if key == "regen" then BuildRegenOptions(hudFlow) end
    ME.Mark(key, hudFlow, hudChild)   -- where this element's later rows go (2 build: its text options)
    DividerRow(hudFlow)
end

local function ResetToDefaults()
    -- saved profiles are deliberately kept: only the live configuration resets
    local kept = type(db.profiles) == "table" and db.profiles or {}
    local keptSchemes = type(db.schemes) == "table" and db.schemes or {}
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(DEFAULTS) do db[k] = (type(v) == "table") and DeepCopy(v) or v end
    db.profiles = kept
    db.schemes = keptSchemes
    ApplySkin(db.skin)
    ApplyAll(); FRHW_RefreshPanel()
    if RefreshProfileList then RefreshProfileList() end
end
FRHW_ResetToDefaults = ResetToDefaults
StaticPopupDialogs["FRHW_CONFIRM_RESET"] = {
    text = "Reset ForeverWarriorHUD to defaults? Every position, size, scale, opacity, toggle, swing option, the countdown text and the skin go back to their original values. Saved profiles are kept.",
    button1 = YES, button2 = NO,
    OnAccept = function() ResetToDefaults() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
NoteRow(hudFlow, "Place, size and turn every item with the mouse on the item itself. The Help tab shows how.")

-- ========================== Config tab ==========================
local cfgScroll, cfgChild = MakeScroll("FRHWConfigScroll", pageConfig, -4)
local cfgFlow = NewFlow(cfgScroll, cfgChild)

NoteRow(cfgFlow, "Switch an ability on, then place it with the mouse: hold CTRL and the left button on its icon.")

-- One toggle for the countdown numbers on every icon. Kept in a table so the
-- main chunk does not grow another local.
local cdUI = {}
cdUI.cb = MakeCheck(cfgChild, "FRHWCFG_CooldownText", 6, 0, "Show countdown numbers on the icons", function(self)
    db.cooldownText = self:GetChecked() and true or false
    if cdUI.refresh then cdUI.refresh() end
end)
HeaderRow(cfgFlow, "Notifications on every icon")
Row(cfgFlow, LAYOUT.check, cdUI.cb)
ME.Mark("timer", cfgFlow, cfgChild)

-- What the icons tell you, one switch each.
ME.notifyCB = {}
for _, n in ipairs(ME.NOTIFY) do
    local key = n.key
    ME.notifyCB[key] = MakeCheck(cfgChild, "FRHWN_" .. key, 6, 0, n.label, function(self)
        db.notify[key] = self:GetChecked() and true or false
        for _, b in pairs(spellIcons) do b._cdStart = nil end   -- redraw the sweeps
        if cdUI.refresh then cdUI.refresh() end
    end)
    -- one to a row: the labels are sentences
    Row(cfgFlow, LAYOUT.check, ME.notifyCB[key])
end
DividerRow(cfgFlow)

local cfgCB, cfgA = {}, {}
for _, a in ipairs(ABILITIES) do
    local key = a.key
    cfgCB[key] = MakeCheck(cfgChild, "FRHWCFGCB_" .. key, 340, 0, "On", function(self)
        db.spells[key].enabled = self:GetChecked() and true or false
        ApplySpell(key)
    end)
    cfgA[key] = MakeSlider(cfgChild, "FRHWCFGA_" .. key, 6,   0, 190, 0.1, 1, 0.05, "Opacity", function(v)
        db.spells[key].alpha = v; ApplySpell(key)
    end)
    HeaderRow(cfgFlow, a.name, cfgCB[key])
    Row(cfgFlow, LAYOUT.slider, cfgA[key])
    -- a thin divider under each spell keeps the list readable
    DividerRow(cfgFlow)
end

RefreshConfig = function()
    cdUI.cb:SetChecked(db.cooldownText)
    for _, n in ipairs(ME.NOTIFY) do ME.notifyCB[n.key]:SetChecked(db.notify[n.key]) end
    for _, a in ipairs(ABILITIES) do
        local key = a.key
        cfgCB[key]:SetChecked(db.spells[key].enabled)
        cfgA[key]:SetValue(db.spells[key].alpha or 1)
    end
end

-- =========================== Skins tab ===========================
-- A preview strip of the active palette, then a scrolling grid of 40 swatch
-- buttons. Each swatch is painted with its own skin, so the grid doubles as
-- the catalogue. Clicking one applies it.
local skinUI = { chips = {}, buttons = {} }
skinUI.title = pageSkins:CreateFontString(nil, "OVERLAY", "GameFontNormal")
skinUI.title:SetPoint("TOPLEFT", 6, -60)
-- Menu artwork, next to the skins it is drawn with
ME.artDD = ME.Dropdown(pageSkins, "FRHWArtDD", "Menu artwork", {
    { value = "high", text = "High resolution" },
    { value = "low",  text = "Low resolution" },
    { value = "off",  text = "Off" },
}, function() return db and db.art or "high" end, function(v) db.art = v; ME.ApplyArt() end)
ME.artDD:SetPoint("TOPLEFT", 6, -4)
ME.bannerDD = ME.Dropdown(pageSkins, "FRHWBannerDD", "Header picture", {
    { value = "a", text = "Painted" },
    { value = "b", text = "Alternate" },
}, function() return db and db.artBanner or "a" end, function(v) db.artBanner = v; ME.ApplyArt() end)
ME.bannerDD:SetPoint("TOPLEFT", 202, -4)
ME.artNote = pageSkins:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ME.artNote:SetPoint("TOPLEFT", 202, -9)
ME.artNote:SetText("")
-- Custom colours: tick to use them, click a colour chip below to change it,
-- and keep a set under a name.
ME.customCB = MakeCheck(pageSkins, "FRHWCustomCB", 6, -30, "Custom colours", function(self)
    db.customOn = self:GetChecked() and true or false
    ApplySkin()
end)
ME.schemeBox = CreateFrame("EditBox", "FRHWSchemeBox", pageSkins, "InputBoxTemplate")
ME.schemeBox:SetSize(92, 20)
ME.schemeBox:SetPoint("TOPLEFT", 126, -31)
ME.schemeBox:SetAutoFocus(false)
ME.schemeBox:SetMaxLetters(32)
ME.schemeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
ME.schemeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
local function SchemeSay(ok, msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r " .. tostring(msg))
    return ok
end
ME.schemeSave = MakeButton(pageSkins, "Save", 224, -30, 46, 22, function()
    SchemeSay(ME.SaveScheme(ME.schemeBox:GetText()))
end, "FRHWSchemeSave")
ME.schemeLoad = MakeButton(pageSkins, "Load", 272, -30, 46, 22, function(self)
    ME.OpenList(self, ME.SchemeNames(), function(name)
        if SchemeSay(ME.LoadScheme(name)) then ME.schemeBox:SetText(name); FRHW_RefreshPanel() end
    end)
end, "FRHWSchemeLoad")
ME.schemeDel = MakeButton(pageSkins, "Delete", 320, -30, 56, 22, function()
    SchemeSay(ME.DeleteScheme(ME.schemeBox:GetText()))
end, "FRHWSchemeDelete")
skinned.accentText[#skinned.accentText + 1] = skinUI.title

do
    local parts = {
        { "bar", "bar" }, { "swing", "swing" }, { "barBg", "bg" }, { "spark", "spark" },
        { "text", "text" }, { "accent", "accent" }, { "border", "border" },
        { "panel", "panel" }, { "combo", "combo" }, { "iconEdge", "edge" },
    }
    for i, part in ipairs(parts) do
        local chip = { field = part[1] }
        -- a thin light frame keeps dark colours visible on a dark window
        chip.edge = Decor(pageSkins, "BORDER")
        chip.tex = Decor(pageSkins, "ARTWORK")
        chip.label = pageSkins:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chip.label:SetText(part[2])
        if chip.label.SetWordWrap then chip.label:SetWordWrap(false) end
        skinned.text[#skinned.text + 1] = chip.label
        chip.btn = CreateFrame("Button", "FRHWChip_" .. part[1], pageSkins)
        chip.btn:SetScript("OnClick", function(self)
            local key = part[1]
            local p, c = ME.PART[key], ME.current[key]
            ME.OpenWheel(self, p.label, c[1], c[2], c[3], c[4], p.alpha, function(r, g, b, a)
                ME.SetPart(key, r, g, b, a)
                ME.customCB:SetChecked(true)
            end)
        end)
        chip.btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ME.PART[part[1]].label, 1, 1, 1)
            GameTooltip:AddLine("Click to choose a colour" .. (ME.PART[part[1]].alpha and " and its opacity" or ""), nil, nil, nil, true)
            GameTooltip:Show()
        end)
        chip.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        skinUI.chips[i] = chip
    end
end
skinUI.rule = MakeDivider(pageSkins)
skinUI.scroll, skinUI.child = MakeScroll("FRHWSkinScroll", pageSkins, -114)

do
    local swatchParts = { "bar", "swing", "combo", "accent", "text", "spark" }
    for i, skin in ipairs(SKINS) do
        local b = CreateFrame("Button", "FRHWSkinBtn_" .. skin.key, skinUI.child, "BackdropTemplate")
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        b:SetBackdropColor(skin.panel[1], skin.panel[2], skin.panel[3], 1)
        b:SetBackdropBorderColor(skin.border[1], skin.border[2], skin.border[3], 1)
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetPoint("TOPLEFT", 5, -5)
        b.name:SetText(skin.name)
        b.name:SetTextColor(skin.text[1], skin.text[2], skin.text[3], 1)
        b.chips = {}
        for j, field in ipairs(swatchParts) do
            local c = Decor(b, "ARTWORK")
            c:SetVertexColor(skin[field][1], skin[field][2], skin[field][3], 1)
            b.chips[j] = c
        end
        -- shown on the active skin only
        b.sel = Decor(b, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", 1, -1)
        b.sel:SetPoint("TOPRIGHT", -1, -1)
        b.sel:SetHeight(2)
        b.sel:SetVertexColor(skin.accent[1], skin.accent[2], skin.accent[3], 1)
        b.sel:Hide()
        b.skin = skin
        b:SetScript("OnClick", function(self) FRHW_SetSkin(self.skin.key) end)
        skinUI.buttons[i] = b
    end
end

-- Preview strip from the page width, grid from the scroll frame width: as many
-- columns as fit at the minimum cell width, then the cells stretch to fill.
local function ReflowSkins(width)
    local pad = LAYOUT.pad
    local pageW = width + LAYOUT.scrollGutter
    local n, gap = #skinUI.chips, 3
    local chipW = math.floor((pageW - 2 * pad - (n - 1) * gap) / n)
    for i, chip in ipairs(skinUI.chips) do
        local x = pad + (i - 1) * (chipW + gap)
        chip.edge:ClearAllPoints()
        chip.edge:SetPoint("TOPLEFT", x - 1, -77)
        chip.edge:SetSize(chipW + 2, 16)
        chip.btn:ClearAllPoints()
        chip.btn:SetPoint("TOPLEFT", x - 1, -77)
        chip.btn:SetSize(chipW + 2, 16)
        chip.tex:ClearAllPoints()
        chip.tex:SetPoint("TOPLEFT", x, -78)
        chip.tex:SetSize(chipW, 14)
        chip.label:ClearAllPoints()
        chip.label:SetPoint("TOPLEFT", x, -95)
        chip.label:SetWidth(chipW)
    end
    skinUI.rule:ClearAllPoints()
    skinUI.rule:SetPoint("TOPLEFT", pad, -110)
    skinUI.rule:SetSize(pageW - 2 * pad, 1)

    local cellMin, cellH, cellGap = 118, 36, 6
    local cols = math.floor((width - 2 * pad + cellGap) / (cellMin + cellGap))
    if cols < 1 then cols = 1 end
    local cellW = math.floor((width - 2 * pad - (cols - 1) * cellGap) / cols)
    local rows = math.ceil(#skinUI.buttons / cols)
    for i, b in ipairs(skinUI.buttons) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", pad + col * (cellW + cellGap), -(4 + row * (cellH + cellGap)))
        b:SetSize(cellW, cellH)
        local cw = math.floor((cellW - 10 - (#b.chips - 1) * 2) / #b.chips)
        for j, c in ipairs(b.chips) do
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", 5 + (j - 1) * (cw + 2), 5)
            c:SetSize(cw, 8)
        end
    end
    skinUI.child:SetSize(width, 8 + rows * (cellH + cellGap))
    skinUI.width = width
end

-- Lay every scrolling page out again. Runs once at build time, on every size
-- change of the panel or of a scroll frame, and at login. A page whose width
-- did not change is skipped, so dragging the window taller costs nothing.
ReflowAll = function(force)
    local was = suppress
    suppress = true
    for _, flow in ipairs(FLOWS) do
        local w = ScrollWidth(flow.scroll)
        if force or flow.width ~= w then ReflowFlow(flow, w) end
    end
    local sw = ScrollWidth(skinUI.scroll)
    if force or skinUI.width ~= sw then ReflowSkins(sw) end
    suppress = was
end
ReflowAll(true)

-- ========================= Profiles tab =========================
-- A profile is a plain copy of CONFIG_KEYS taken out of db. The copies live in
-- db.profiles, which ResetToDefaults and LoadProfile never write to, so a saved
-- setup survives both. Nothing here runs unless the options window is open.
local MAX_PROFILE_NAME = 32
local MAX_PROFILES = 40

local function TrimName(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("[%c]", "")
    if #s > MAX_PROFILE_NAME then s = s:sub(1, MAX_PROFILE_NAME) end
    return s
end

local function CaptureConfig()
    local out = {}
    for _, k in ipairs(CONFIG_KEYS) do
        local v = db[k]
        out[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return out
end

-- Numbers coming back from SavedVariables can be strings or out of range if the
-- file was hand-edited; clamp instead of trusting them.
local function Num(v, minV, maxV, fallback)
    v = tonumber(v)
    if not v then return fallback end
    if v ~= v then return fallback end          -- NaN
    if minV and v < minV then v = minV end
    if maxV and v > maxV then v = maxV end
    return v
end

-- The swing timer's own options. Used when a profile is applied and once at
-- login, so a 1.8.0 profile (which has none of these fields) or a hand-edited
-- file ends up with valid values instead of nils or strings.
local function ClampSwing(e, s, def)
    e.useSkinColor  = s.useSkinColor ~= false
    e.r             = Num(s.r, 0, 1, def.r)
    e.g             = Num(s.g, 0, 1, def.g)
    e.b             = Num(s.b, 0, 1, def.b)
    e.bgAlpha       = Num(s.bgAlpha, 0, 1, def.bgAlpha)
    e.spark         = s.spark ~= false
    e.sparkSize     = Num(s.sparkSize, 8, 40, def.sparkSize)
    e.text          = s.text ~= false
    e.textMode      = SWING_TEXT_LABEL[s.textMode] and s.textMode or def.textMode
    e.ticks         = s.ticks == true
    e.tickCount     = math.floor(Num(s.tickCount, 1, 10, def.tickCount) + 0.5)
    e.flash         = s.flash == true
    e.source        = (s.source == "poll") and "poll" or "event"
    e.manual        = s.manual == true
    e.manualSpeed   = Num(s.manualSpeed, 0.5, 4, def.manualSpeed)
    e.resetOnTarget = s.resetOnTarget == true
end

local function ApplyConfig(src)
    if type(src) ~= "table" then return false end
    db.baseX       = Num(src.baseX, -2000, 2000, DEFAULTS.baseX)
    db.baseY       = Num(src.baseY, -2000, 2000, DEFAULTS.baseY)
    db.scale       = Num(src.scale, 0.5, 2.5, DEFAULTS.scale)
    db.gridSize    = Num(src.gridSize, 8, 64, DEFAULTS.gridSize)
    db.shown       = src.shown ~= false
    db.locked      = src.locked == true
    db.autoHide    = src.autoHide ~= false
    db.autoHideOOC = src.autoHideOOC == true
    db.gridSnap    = src.gridSnap ~= false
    db.sticky      = src.sticky ~= false
    db.cooldownText = src.cooldownText ~= false
    db.orientation = "h"   -- kept for old profiles only: every item has its own rotation now
    ME.ClampNotify(src.notify)
    ME.ClampCustom(src.custom, src.customOn)
    -- an unknown skin name (older profile, renamed skin, hand edit) is the default look
    db.skin        = SKIN_BY_KEY[src.skin] and src.skin or SKIN_DEFAULT
    -- elements
    if type(db.elements) ~= "table" then db.elements = {} end
    for key, def in pairs(DEFAULTS.elements) do
        local s = type(src.elements) == "table" and src.elements[key] or nil
        if type(db.elements[key]) ~= "table" then db.elements[key] = DeepCopy(def) end
        local e = db.elements[key]
        if type(s) == "table" then
            e.enabled = s.enabled ~= false
            e.x       = Num(s.x, -2000, 2000, def.x)
            e.y       = Num(s.y, -2000, 2000, def.y)
            e.w       = Num(s.w, 4, 600, def.w)
            e.h       = Num(s.h, 4, 600, def.h)
            e.alpha   = Num(s.alpha, 0.05, 1, def.alpha)
            e.scale   = Num(s.scale, 0.2, 4, def.scale)
            -- a profile from before 2.0 has no rotation: "vertical" becomes a quarter turn
            if s.rot == nil and src.orientation == "v" then e.rot = 90 else e.rot = ME.Norm(s.rot, false) end
            if key == "energy" then e.showText = s.showText ~= false end
            if key == "swing" then ClampSwing(e, s, def) end
            if key == "regen" then
                e.regenMax = Num(s.regenMax, 5, 60, def.regenMax)
                e.showRate = s.showRate ~= false
            end
        else
            db.elements[key] = DeepCopy(def)
        end
    end
    -- spells
    if type(db.spells) ~= "table" then db.spells = {} end
    for key, def in pairs(DEFAULTS.spells) do
        local s = type(src.spells) == "table" and src.spells[key] or nil
        if type(db.spells[key]) ~= "table" then db.spells[key] = DeepCopy(def) end
        local e = db.spells[key]
        if type(s) == "table" then
            e.enabled = s.enabled == true
            e.x       = Num(s.x, -2000, 2000, def.x)
            e.y       = Num(s.y, -2000, 2000, def.y)
            e.w       = Num(s.w, 6, 200, def.w)
            e.h       = Num(s.h, 6, 200, def.h)
            e.rot     = ME.Norm(s.rot, true)
            e.alpha   = Num(s.alpha, 0.05, 1, def.alpha)
            e.scale   = Num(s.scale, 0.2, 4, def.scale)
        else
            db.spells[key] = DeepCopy(def)
        end
    end
    ApplySkin(db.skin)
    ApplyAll()
    FRHW_RefreshPanel()
    return true
end

local function ProfileNames()
    local names = {}
    if type(db) == "table" and type(db.profiles) == "table" then
        for name in pairs(db.profiles) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local function ProfileCount()
    return #ProfileNames()
end

local function SaveProfile(name)
    name = TrimName(name)
    if name == "" then return false, "Type a profile name first." end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if db.profiles[name] == nil and ProfileCount() >= MAX_PROFILES then
        return false, "Profile limit reached (" .. MAX_PROFILES .. "). Delete one first."
    end
    db.profiles[name] = { version = FRHW_VERSION, savedAt = time and time() or nil, config = CaptureConfig() }
    return true, "Saved profile '" .. name .. "'."
end

local function LoadProfile(name)
    name = TrimName(name)
    local p = type(db.profiles) == "table" and db.profiles[name] or nil
    if type(p) ~= "table" or type(p.config) ~= "table" then
        return false, "No saved profile named '" .. name .. "'."
    end
    if not ApplyConfig(p.config) then return false, "Profile '" .. name .. "' is unreadable." end
    return true, "Loaded profile '" .. name .. "'."
end

local function DeleteProfile(name)
    name = TrimName(name)
    if type(db.profiles) ~= "table" or db.profiles[name] == nil then
        return false, "No saved profile named '" .. name .. "'."
    end
    db.profiles[name] = nil
    return true, "Deleted profile '" .. name .. "'."
end

local profileNameBox, profileStatus, profileScroll, profileChild
local profileRows = {}
local selectedProfile

local function SetStatus(msg)
    if profileStatus then profileStatus:SetText(msg or "") end
end

local function SelectProfile(name)
    selectedProfile = name
    RefreshProfileList()
end

RefreshProfileList = function()
    if not profileChild then return end
    local names = ProfileNames()
    if selectedProfile and not (type(db.profiles) == "table" and db.profiles[selectedProfile]) then
        selectedProfile = nil
    end
    local rowH = 20
    for i = 1, #names do
        local row = profileRows[i]
        if not row then
            row = CreateFrame("Button", nil, profileChild, "UIPanelButtonTemplate")
            row:SetSize(276, rowH - 2)
            row:SetScript("OnClick", function(self)
                SelectProfile(self.profileName)
            end)
            row.sel = row:CreateTexture(nil, "OVERLAY")
            row.sel:SetAllPoints(true)
            row.sel:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            row.sel:SetVertexColor(0.2, 0.8, 1, 0.25)
            row.sel:Hide()
            profileRows[i] = row
        end
        row.profileName = names[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * rowH))
        row:SetText(names[i])
        row.sel:SetShown(names[i] == selectedProfile)
        row:Show()
    end
    for i = #names + 1, #profileRows do profileRows[i]:Hide() end
    profileChild:SetSize(276, math.max(1, #names * rowH))
    if profileScroll then profileScroll:SetVerticalScroll(0) end
end

local function DoSave(name)
    local ok, msg = SaveProfile(name)
    SetStatus(msg)
    if ok then
        selectedProfile = TrimName(name)
        RefreshProfileList()
    end
end

local function RequestSave()
    if not EditMode() then return end
    local name = TrimName(profileNameBox and profileNameBox:GetText() or "")
    if name == "" then SetStatus("Type a profile name first.") return end
    if type(db.profiles) == "table" and db.profiles[name] ~= nil then
        FRHW_PendingProfile = name
        StaticPopup_Show("FRHW_CONFIRM_OVERWRITE", name)
    else
        DoSave(name)
    end
end

local function RequestLoad()
    if not EditMode() then return end
    if not selectedProfile then SetStatus("Select a saved profile first.") return end
    local ok, msg = LoadProfile(selectedProfile)
    SetStatus(msg)
    if ok and profileNameBox then profileNameBox:SetText(selectedProfile) end
end

local function RequestDelete()
    if not EditMode() then return end
    if not selectedProfile then SetStatus("Select a saved profile first.") return end
    FRHW_PendingProfile = selectedProfile
    StaticPopup_Show("FRHW_CONFIRM_DELETE", selectedProfile)
end

StaticPopupDialogs["FRHW_CONFIRM_OVERWRITE"] = {
    text = "A profile named '%s' already exists. Overwrite it with the current setup?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local name = FRHW_PendingProfile
        FRHW_PendingProfile = nil
        if name then DoSave(name) end
    end,
    OnCancel = function() FRHW_PendingProfile = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["FRHW_CONFIRM_DELETE"] = {
    text = "Delete the saved profile '%s'? The HUD itself is not changed.",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local name = FRHW_PendingProfile
        FRHW_PendingProfile = nil
        if name then
            local ok, msg = DeleteProfile(name)
            SetStatus(msg)
            if ok and selectedProfile == name then selectedProfile = nil end
            RefreshProfileList()
        end
    end,
    OnCancel = function() FRHW_PendingProfile = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local profNote = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profNote:SetPoint("TOPLEFT", 6, -4)
profNote:SetWidth(400)
profNote:SetJustifyH("LEFT")
profNote:SetText("Positions, sizes, opacity, visibility, grid, sticky, skin, countdown.")

local nameLabel = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nameLabel:SetPoint("TOPLEFT", 6, -28)
nameLabel:SetText("Name")

profileNameBox = CreateFrame("EditBox", "FRHWProfileNameBox", pageProfiles, "InputBoxTemplate")
profileNameBox:SetSize(212, 20)
profileNameBox:SetPoint("TOPLEFT", 40, -25)
profileNameBox:SetAutoFocus(false)
profileNameBox:SetMaxLetters(MAX_PROFILE_NAME)
profileNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
profileNameBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    RequestSave()
end)

local saveBtn = MakeButton(pageProfiles, "Save", 254, -25, 56, 20, RequestSave)
saveBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Save profile", 1, 1, 1)
    GameTooltip:AddLine("Stores the current setup under the name on the left.", nil, nil, nil, true)
    GameTooltip:AddLine("Asks before replacing a name that already exists.", nil, nil, nil, true)
    GameTooltip:Show()
end)
saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local listHeader = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
listHeader:SetPoint("TOPLEFT", 6, -54)
listHeader:SetText("Saved profiles")

profileScroll = CreateFrame("ScrollFrame", "FRHWProfileScroll", pageProfiles, "UIPanelScrollFrameTemplate")
profileScroll:SetPoint("TOPLEFT", 6, -66)
profileScroll:SetPoint("BOTTOMRIGHT", pageProfiles, "BOTTOMLEFT", 290, 44)
profileChild = CreateFrame("Frame", nil, profileScroll)
profileChild:SetSize(276, 1)
profileScroll:SetScrollChild(profileChild)

local loadBtn = MakeButton(pageProfiles, "Load", 298, -66, 116, 22, RequestLoad)
local delBtn  = MakeButton(pageProfiles, "Delete", 298, -92, 116, 22, RequestDelete)

profileStatus = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profileStatus:SetPoint("TOPLEFT", 298, -120)
profileStatus:SetWidth(116)
profileStatus:SetJustifyH("LEFT")
profileStatus:SetText("")

local profHelp = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
profHelp:SetPoint("BOTTOMLEFT", 6, 6)
profHelp:SetWidth(400)
profHelp:SetJustifyH("LEFT")
profHelp:SetText("Profiles are stored in SavedVariables and are not part of Reset to default. "
    .. "Loading a profile replaces the current setup; saved profiles themselves are never changed.")

-- the profiles page keeps its fixed layout; its labels still follow the skin
skinned.text[#skinned.text + 1] = profNote
skinned.text[#skinned.text + 1] = nameLabel
skinned.text[#skinned.text + 1] = listHeader
skinned.text[#skinned.text + 1] = profileStatus
skinned.text[#skinned.text + 1] = profHelp

-- ============================ Help tab ============================
-- How the interface works, in the window itself. Built with the same row
-- layout as the other pages, so it reflows with the window.
do
    local pageHelp = CreateFrame("Frame", nil, panel)
    pageHelp:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
    pageHelp:SetPoint("BOTTOMRIGHT", -8, 26)
    pageHelp:Hide()
    local scroll, child = MakeScroll("FRHWHelpScroll", pageHelp, -4)
    local flow = NewFlow(scroll, child)
    local function Para(text)
        NoteRow(flow, text)
        -- help lines are longer than option notes: three lines of room
        flow.rows[#flow.rows].h = 40
    end
    HeaderRow(flow, "Editing the HUD with the mouse")
    Para("This only works while this window is open and Lock (HUD tab) is off. Point at any bar or icon: it lights up and a tooltip names it.")
    Para("MOVE: hold CTRL, then hold the left mouse button on the item. It follows the cursor. Let go to drop it.")
    Para("SIZE: hold CTRL and roll the mouse wheel over the item. Up is bigger, down is smaller.")
    Para("TURN: hold CTRL, then hold the right mouse button on the item and drag around it. It stays as you leave it.")
    Para("STRAIGHTEN: double-click the right mouse button on the item. It goes back to its original orientation.")
    Para("Icons turn to any angle. Bars, combo points and the recent-actions row turn in quarter turns; their text stays upright.")
    DividerRow(flow)
    HeaderRow(flow, "Lining things up")
    Para("The grid is on screen while this window is open. \"Snap items to grid\" drops an item on the nearest grid line; \"Grid size\" sets the spacing.")
    Para("\"Stick items together\" makes an item dropped right next to another one click against its edge. It needs Snap to be on.")
    Para("With this window closed the HUD cannot be clicked or moved at all, so it never gets in the way of the game.")
    Para("This HUD only starts on a warrior. On any other class it stays completely off: nothing on screen, nothing saved.")
    DividerRow(flow)
    HeaderRow(flow, "What is on screen")
    Para("Rage bar and rage regen: your resource and how fast it is coming in. Swing timer: your auto-attack. Each has a Show box on the HUD tab.")
    Para("Combo points: kept for layout parity with the other class HUDs, off by default because this class has none.")
    Para("Recent actions: the last spells you cast, newest first, fading out after a few seconds.")
    Para("Ability icons: one per ability, switched on one by one on the Abilities tab. On cooldown the icon goes dark, a clock sweep runs round it, and the time left counts down to the hundredth of a second in its bottom-right corner, always on top.")
    Para("An icon also flashes when it is ready, glows while its effect is on you, and dims or turns red when you cannot use it. Each of these has its own switch.")
    DividerRow(flow)
    HeaderRow(flow, "The tabs")
    Para("HUD: show or hide each element, its width, height and opacity, plus the swing timer and regen options. Nothing here moves or scales an item; that is the mouse.")
    Para("Abilities: a switch for every notification, then every ability with its own On box and opacity.")
    Para("Skins: the menu artwork (High resolution, Low resolution or Off) and 40 colour skins. Profiles: save, load and delete named setups.")
    Para("Your own colours: on the Skins tab click any colour in the strip (bar, swing, text and so on). A colour wheel opens; the parts that can be see-through also get an Opacity slider. Changes show at once; Cancel puts the old colour back.")
    Para("Tick or untick \"Custom colours\" to switch between your colours and the plain skin. Type a name and press Save to keep a set; Load brings one back; Delete removes it. Saved colour sets survive Reset to default.")
    Para("\"Reset to default\" (top right) asks first and keeps your saved profiles.")
    DividerRow(flow)
    HeaderRow(flow, "Commands")
    Para("/fw opens or closes this window. /fw help opens this page. /fw abilities, /fw skins and /fw profiles open those tabs.")
    Para("/fw show | hide, /fw lock | unlock, /fw energy|regen|swing|combo|trail on|off, /fw cooldown on|off, /fw sticky, /fw grid.")
    Para("/fw skin <name>, /fw save <name>, /fw load <name>, /fw reset.")
    DividerRow(flow)
    AddTab("help", "FRHWTabHelp", "Help", pageHelp)
    ReflowAll(true)
end

-----------------------------------------------------------------------
-- Apply positions, sizes, visibility
-----------------------------------------------------------------------
ApplyElement = function(key)
    if not db then return end
    local e = db.elements[key]
    local fr = elems[key]
    if not e or not fr then return end
    fr:ClearAllPoints()
    local sc = db.scale * (e.scale or 1)
    fr:SetPoint("CENTER", UIParent, "CENTER", (db.baseX + e.x) / sc, (db.baseY + e.y) / sc)
    fr:SetScale(sc)
    local spacing = 2
    -- dot-level fill alpha (dim vs full) is separate; it is re-scaled by the
    -- element's own opacity so both controls work together.
    local baseAlpha = e.alpha or 1
    if key == "combo" then
        if ME.Vertical(e) then
            fr:SetSize(e.w, MAX_COMBO_POINTS * e.h + (MAX_COMBO_POINTS - 1) * spacing)
            for i = 1, MAX_COMBO_POINTS do
                local b = cpBars[i]
                b:SetOrientation("VERTICAL")
                b:SetSize(e.w, e.h)
                b:ClearAllPoints()
                b:SetPoint("BOTTOM", fr, "BOTTOM", 0, (ME.Slot(e, i, MAX_COMBO_POINTS) - 1) * (e.h + spacing))
            end
        else
            fr:SetSize(MAX_COMBO_POINTS * e.w + (MAX_COMBO_POINTS - 1) * spacing, e.h)
            for i = 1, MAX_COMBO_POINTS do
                local b = cpBars[i]
                b:SetOrientation("HORIZONTAL")
                b:SetSize(e.w, e.h)
                b:ClearAllPoints()
                b:SetPoint("LEFT", fr, "LEFT", (ME.Slot(e, i, MAX_COMBO_POINTS) - 1) * (e.w + spacing), 0)
            end
        end
    elseif key == "trail" then
        ME.LayoutTrail(fr, e)
    else
        -- a quarter turn swaps width and height; a half turn fills the other way
        local vert = ME.Vertical(e)
        if vert then fr:SetSize(e.h, e.w) else fr:SetSize(e.w, e.h) end
        fr:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
        if fr.SetReverseFill then fr:SetReverseFill(ME.Reversed(e)) end
        if key == "energy" then fr.value:SetShown(e.showText ~= false) end
        if key == "swing" then
            LayoutSwing(e)   -- spark size, tick marks, colours
        elseif key == "regen" then
            fr.spark:Hide()  -- the regen bar has no spark of its own
        else
            fr.spark:SetSize(20, e.h * 2)
        end
    end
    fr:SetAlpha(baseAlpha)
    if db.shown and e.enabled and HudVisible() then fr:Show() else fr:Hide() end
end

ApplySpell = function(key)
    if not db then return end
    local cfg = db.spells[key]
    local btn = spellIcons[key]
    if not cfg or not btn then return end
    btn:ClearAllPoints()
    local sc = db.scale * (cfg.scale or 1)
    btn:SetPoint("CENTER", UIParent, "CENTER", (db.baseX + cfg.x) / sc, (db.baseY + cfg.y) / sc)
    btn:SetScale(sc)
    btn:SetSize(cfg.w, cfg.h)
    btn._alpha = cfg.alpha or 1
    ME.IconFade(btn, GetTime())
    -- the picture turns; the border, the sweep and the number stay upright
    if btn.icon.SetRotation then btn.icon:SetRotation(math.rad(cfg.rot or 0)) end
    if db.shown and cfg.enabled and HudVisible() then btn:Show() else btn:Hide() end
end

ApplyAll = function()
    ApplyElement("energy")
    ApplyElement("regen")
    ApplyElement("swing")
    ApplyElement("combo")
    ApplyElement("trail")
    for key in pairs(spellIcons) do ApplySpell(key) end
end
-- exposed so a macro or a test can re-apply the live configuration on demand
FRHW_ApplyAll = function() if db then ApplyAll() end end
FRHW_ApplyElement = function(key) if db then ApplyElement(key) end end

-----------------------------------------------------------------------
-- Skins: repaint the HUD and the options window
-----------------------------------------------------------------------
local currentSkin = SKIN_BY_KEY[SKIN_DEFAULT]

-- r, g, b, a of a palette entry, with an optional alpha override
local function Col(c, a)
    return c[1], c[2], c[3], a or c[4] or 1
end

-- The swing bar's colours depend on both the skin and the user's own swing
-- options, so they are painted here and called from ApplySkin and from
-- ApplyElement("swing") alike.
PaintSwing = function()
    if not db then return end
    local e = db.elements.swing
    local r, g, b = currentSkin.swing[1], currentSkin.swing[2], currentSkin.swing[3]
    if not e.useSkinColor then r, g, b = e.r, e.g, e.b end
    swing:SetStatusBarColor(r, g, b, 1)
    -- same rule as 1.8.0: the background is the bar colour at a quarter strength
    swing.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, e.bgAlpha)
    swing.time:SetTextColor(Col(currentSkin.text, 1))
    swing.spark:SetVertexColor(Col(currentSkin.spark, 1))
    swing.flash:SetVertexColor(Col(currentSkin.spark, 0.45))
    for i = 1, #swing.ticks do
        swing.ticks[i]:SetVertexColor(Col(currentSkin.text, 0.5))
    end
end

-- Palette and edge style only: nothing here sets a point, a size or a scale,
-- so switching skins cannot move or resize anything.
ApplySkin = function(key)
    local skin = SKIN_BY_KEY[key or (db and db.skin)] or SKIN_BY_KEY[SKIN_DEFAULT]
    skin = ME.CustomSkin(skin)
    currentSkin = skin
    ME.current = skin

    -- HUD
    energy:SetStatusBarColor(Col(skin.bar, 1))
    energy.bg:SetVertexColor(Col(skin.barBg))
    energy.value:SetTextColor(Col(skin.text, 1))
    -- the regen bar reads as a cooler sibling of the energy bar: the same
    -- accent, dimmed, so the two are distinguishable without a new palette entry
    regen:SetStatusBarColor(Col(skin.accent, 1))
    regen.bg:SetVertexColor(Col(skin.barBg))
    regen.value:SetTextColor(Col(skin.text, 1))
    PaintSwing()
    for i = 1, MAX_COMBO_POINTS do
        cpBars[i]:SetStatusBarColor(Col(skin.combo, 1))
        cpBars[i].bg:SetVertexColor(Col(skin.combo, 0.15))
    end
    for _, btn in pairs(spellIcons) do
        btn:SetBackdropBorderColor(Col(skin.iconEdge))
        btn.timer:SetTextColor(Col(skin.text, 1))
        btn._flashUntil = nil   -- a running ready flash would keep the old colour
        btn.glow:SetVertexColor(Col(skin.accent, 0.35))
    end
    for i = 1, #edgeKits do PaintEdges(edgeKits[i], skin) end

    -- options window
    panel:SetBackdropColor(Col(skin.panel))
    panel:SetBackdropBorderColor(Col(skin.border))
    panel.headerBand:SetVertexColor(Col(skin.accent, 0.10))
    panel.rule:SetVertexColor(Col(skin.accent, 0.85))
    panel.footRule:SetVertexColor(Col(skin.accent, 0.30))
    panel.title:SetTextColor(Col(skin.accent, 1))
    panel.hint:SetTextColor(Col(skin.text, 0.75))
    for i = 1, #skinned.text do skinned.text[i]:SetTextColor(Col(skin.text, 1)) end
    for i = 1, #skinned.accentText do skinned.accentText[i]:SetTextColor(Col(skin.accent, 1)) end
    for i = 1, #skinned.dividers do skinned.dividers[i]:SetVertexColor(Col(skin.accent, 0.18)) end
    for i = 1, #skinned.headerBars do skinned.headerBars[i]:SetVertexColor(Col(skin.accent, 0.16)) end
    for i = 1, #skinned.gutters do skinned.gutters[i]:SetVertexColor(Col(skin.border, 0.15)) end
    for i = 1, #skinned.tabs do skinned.tabs[i]:SetVertexColor(Col(skin.accent, 1)) end
    for i = 1, #skinned.sliders do
        local s = skinned.sliders[i]
        s.track:SetVertexColor(Col(skin.accent, 0.14))
        -- the thumb is template art: tint it where the template exposes it,
        -- halfway to white so a dark accent does not turn it black
        local thumb = s.GetThumbTexture and s:GetThumbTexture()
        if thumb and thumb.SetVertexColor then
            thumb:SetVertexColor((skin.accent[1] + 1) / 2, (skin.accent[2] + 1) / 2, (skin.accent[3] + 1) / 2, 1)
        end
    end

    -- Skins tab: preview strip and the marker on the active swatch
    skinUI.title:SetText("Skin: " .. skin.name .. "   (" .. skin.style .. " edges)" .. (skin._base and "  + custom colours" or "") .. "   click a colour to change it")
    for i = 1, #skinUI.chips do
        local chip = skinUI.chips[i]
        chip.tex:SetVertexColor(Col(skin[chip.field], 1))
        chip.edge:SetVertexColor(Col(skin.text, 0.35))
    end
    for i = 1, #skinUI.buttons do
        local b = skinUI.buttons[i]
        b.sel:SetShown(b.skin == (skin._base or skin))
    end
    ME.ApplyArt()
end

-- Choose a skin: stores it and repaints. Returns false for an unknown key.
function FRHW_SetSkin(key)
    if not db or not SKIN_BY_KEY[key] then return false end
    db.skin = key
    ApplySkin(key)
    return true
end

function FRHW_RefreshPanel()
    if not db then return end
    -- SetValue fires OnValueChanged; with suppress set the sliders only update
    -- their labels, so showing the configuration can never rewrite it (a value
    -- outside a slider's range used to be clamped back into db here).
    local was = suppress
    suppress = true
    showCB:SetChecked(db.shown)
    lockCB:SetChecked(db.locked)
    autoCB:SetChecked(db.autoHide)
    autoOOC:SetChecked(db.autoHideOOC)
    snapCB:SetChecked(db.gridSnap)
    stickyCB:SetChecked(db.sticky)
    gridSlider:SetValue(db.gridSize or 20)
    for _, info in ipairs(ELEMENT_INFO) do
        local key = info.key
        elemCB[key]:SetChecked(db.elements[key].enabled)
        elemW[key]:SetValue(db.elements[key].w)
        elemH[key]:SetValue(db.elements[key].h)
        elemA[key]:SetValue(db.elements[key].alpha or 1)
    end
    local sw = db.elements.swing
    swingUI.skinCB:SetChecked(sw.useSkinColor)
    swingUI.bgAlpha:SetValue(sw.bgAlpha)
    swingUI.r:SetValue(sw.r)
    swingUI.g:SetValue(sw.g)
    swingUI.b:SetValue(sw.b)
    swingUI.sparkSize:SetValue(sw.sparkSize)
    swingUI.sparkCB:SetChecked(sw.spark)
    swingUI.flashCB:SetChecked(sw.flash)
    swingUI.textCB:SetChecked(sw.text)
    swingUI.textBtn:SetText(SWING_TEXT_LABEL[sw.textMode] or SWING_TEXT_LABEL.elapsed)
    swingUI.ticksCB:SetChecked(sw.ticks)
    swingUI.tickCount:SetValue(sw.tickCount)
    swingUI.sourceBtn:SetText(sw.source == "poll" and "Source: UnitAttackSpeed" or "Source: PLAYER_SWING")
    swingUI.resetCB:SetChecked(sw.resetOnTarget)
    swingUI.manualCB:SetChecked(sw.manual)
    swingUI.manualSpeed:SetValue(sw.manualSpeed)
    regenUI.rateCB:SetChecked(db.elements.regen.showRate)
    regenUI.maxSlider:SetValue(db.elements.regen.regenMax or 25)
    ME.valueCB:SetChecked(db.elements.energy.showText ~= false)
    ME.customCB:SetChecked(db.customOn)
    ME.artDD.Refresh()
    ME.bannerDD.Refresh()
    RefreshConfig()
    suppress = was
    if RefreshProfileList and pageProfiles:IsShown() then RefreshProfileList() end
end

-----------------------------------------------------------------------
-- Data updates — reads go to widgets, never into our own compare
-----------------------------------------------------------------------
local swingDuration = 0
local swingElapsed  = 0

-- Rage: power type 1 on this client, the same in every stance.
local function PowerIndex()
    return 1
end

local function UpdateEnergy()
    local idx = PowerIndex()
    local cur = UnitPower("player", idx)
    local max = UnitPowerMax("player", idx)
    energy:SetMinMaxValues(0, max)
    energy:SetValue(cur)
    energy.value:SetFormattedText("%d / %d", cur, max)
end

-- Energy regeneration, measured rather than guessed: the difference in energy
-- across a short window, divided by the window's length. Both readings went
-- through IsReadable first, so nothing secret is ever subtracted here.
local regenLast, regenAccum, regenRate, regenIndex = nil, 0, 0, nil
local REGEN_WINDOW = 1.0
local regenGain = 0

local function UpdateRegen(elapsed)
    local e = db.elements.regen
    local idx = PowerIndex()
    if idx ~= regenIndex then
        -- a different resource (a form change): the old sample means nothing
        regenIndex = idx
        regenLast, regenAccum, regenRate = nil, 0, 0
        regenGain = 0
        regen:SetValue(0)
        regen.value:SetText(e.showRate and "0.0 /s" or "")
    end
    local cur = UnitPower("player", idx)
    if not IsReadable(cur) then return end
    if regenLast == nil then
        regenLast = cur
        return
    end
    regenAccum = regenAccum + (elapsed or 0)
    local delta = cur - regenLast
    regenLast = cur
    if delta < 0 then
        -- a spend, not a tick: restart the window so the drop does not read as
        -- negative regeneration
        regenAccum = 0
        regenRate = 0
        regenGain = 0
    else
        -- everything gained since the window opened counts, not just the
        -- change seen by the sample that happens to close it
        regenGain = regenGain + delta
        if regenAccum >= REGEN_WINDOW then
            regenRate = regenGain / regenAccum
            regenAccum = 0
            regenGain = 0
        end
    end
    local full = e.regenMax or 25
    regen:SetMinMaxValues(0, full)
    regen:SetValue(math.min(regenRate, full))
    if e.showRate then
        regen.value:SetFormattedText("%.1f /s", regenRate)
    else
        regen.value:SetText("")
    end
end

-- Where the swing duration comes from. Whatever this returns is a plain,
-- readable number: the manual override is our own value, the event duration
-- was checked with IsReadable when it arrived, and UnitAttackSpeed is only
-- used after IsReadable says so. Nothing unreadable ever reaches arithmetic.
local function SwingDuration(e)
    if e.manual then return e.manualSpeed end
    if e.source == "poll" then
        -- polling fallback: ask for the attack speed every frame
        local spd = UnitAttackSpeed("player")
        if IsReadable(spd) and spd > 0 then return spd end
    end
    if IsReadable(swingDuration) and swingDuration > 0 then return swingDuration end
    local spd = UnitAttackSpeed("player")
    if IsReadable(spd) and spd > 0 then
        swingDuration = spd
        return spd
    end
    return nil
end

local function UpdateSwingBar(elapsed)
    local e = db.elements.swing
    local dur = SwingDuration(e)
    if not dur then return end
    swingElapsed = swingElapsed + elapsed
    if swingElapsed > dur then swingElapsed = swingElapsed % dur end
    swing:SetMinMaxValues(0, dur)
    swing:SetValue(swingElapsed)
    local remaining = dur - swingElapsed
    if e.text and e.textMode ~= "none" then
        if e.textMode == "remaining" then
            swing.time:SetFormattedText("%.2f s", remaining)
        elseif e.textMode == "percent" then
            swing.time:SetFormattedText("%d%%", math.floor(swingElapsed / dur * 100 + 0.5))
        else
            swing.time:SetFormattedText("%.2f / %.2f s", swingElapsed, dur)
        end
        swing.time:Show()
    else
        swing.time:Hide()
    end
    local anchor = ME.SparkAnchor(e)
    if e.spark and swingElapsed / dur >= 0.01 then
        swing.spark:ClearAllPoints()
        swing.spark:SetPoint("CENTER", swing:GetStatusBarTexture(), anchor)
        swing.spark:Show()
    else
        swing.spark:Hide()
    end
    -- ready flash: the swing lands within the next 0.2 s
    swing.flash:SetShown(e.flash and remaining <= 0.2)
end

function FRHW_UpdateCombo()
    local cp = GetComboPoints("player", "target")
    if not IsReadable(cp) then
        cp = UnitPower("player", 14)   -- Enum.PowerType.ComboPoints on Mainline
    end
    if IsReadable(cp) then
        if db.autoHide and cp == 0 and not UnitAffectingCombat("player") then
            for i = 1, MAX_COMBO_POINTS do cpBars[i]:Hide() end
            return
        end
        for i = 1, MAX_COMBO_POINTS do
            cpBars[i]:Show()
            cpBars[i]:SetAlpha(i <= cp and 1 or 0.2)
            cpBars[i]:SetValue(1)
        end
    else
        -- secret path: no arithmetic on cp at all (that would throw).
        -- Each dot is a 1-unit window of the total; the widget clamps the
        -- secret value internally, so dot i fills exactly when cp >= i.
        for i = 1, MAX_COMBO_POINTS do
            cpBars[i]:Show()
            cpBars[i]:SetAlpha(1)
            cpBars[i]:SetMinMaxValues(i - 1, i)
            cpBars[i]:SetValue(cp)
        end
    end
end

-- Ask the client which spell ID is behind each spellbook name. Rank 1 IDs are
-- what the table holds; a character who knows rank 5 gets rank 5's icon and
-- cooldown. Anything the client cannot name keeps the table ID.
local function ResolveSpells()
    for _, btn in pairs(spellIcons) do
        local a = btn.spell
        local id = a.id
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, a.name)
            if ok and type(info) == "table" and IsReadable(info.spellID) and IsReadable(info.name)
                and type(info.spellID) == "number" and info.name == a.name then
                id = info.spellID
            end
        end
        if id ~= btn.spellId then
            btn.spellId = id
            btn.iconReady = false
            btn._cdStart, btn._cdDur = nil, nil
        end
    end
end

-- "7" under a minute, "2:05" under an hour. Only ever called with a plain
-- number that passed IsReadable.
local function FormatRemaining(rem)
    -- under a minute: seconds and hundredths ("7.43"); above it, minutes and seconds
    if rem < 60 then return string.format("%.2f", rem) end
    local sec = math.ceil(rem)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Cooldown reading: the same shape GlowingBars uses on this client. One pass
-- per icon does the sweep, the countdown text and the ready flash; there is no
-- per-icon OnUpdate, so a hidden icon costs nothing.
local function UpdateSpellIcon(btn)
    local id = btn.spellId
    -- Icon texture: set once it resolves (nil until the client caches the spell)
    if not btn.iconReady and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.iconID then
            btn.icon:SetTexture(info.iconID)
            btn.iconReady = true
        elseif C_Spell.RequestLoadSpellData then
            pcall(C_Spell.RequestLoadSpellData, id)
        end
    end
    local now = GetTime()
    ME.IconState(btn, id)
    -- Ready flash: the border sits at the skin's spark colour for 0.25 s
    if btn._flashUntil and now >= btn._flashUntil then
        btn._flashUntil = nil
        btn:SetBackdropBorderColor(Col(currentSkin.iconEdge))
    end
    local ok, info
    if C_Spell and C_Spell.GetSpellCooldown then ok, info = pcall(C_Spell.GetSpellCooldown, id) end
    if not ok or type(info) ~= "table" then
        btn.timer:SetText("")
        btn._cooling = false
        return
    end
    local start = info.startTime
    local dur = info.duration
    -- nil or secret: no number, no arithmetic, no error. The sweep is left as
    -- it was; it runs out on its own.
    if not IsReadable(start) or not IsReadable(dur) or type(start) ~= "number" or type(dur) ~= "number" then
        btn.timer:SetText("")
        -- the numbers are hidden from addons (combat): "isActive" is still told.
        -- If even that is missing the icon stays on screen rather than vanish.
        local act = info.isActive
        if IsReadable(act) and type(act) == "boolean" then
            if act then
                btn._wasOnCd = true
            elseif btn._wasOnCd then
                btn._wasOnCd = false
                btn._readyAt = now
            end
            btn._cooling = act
        else
            btn._cooling = true
            btn._wasOnCd = false
        end
        return
    end
    local remaining = 0
    if dur > GLOBAL_COOLDOWN then remaining = start + dur - now end
    if remaining > 0 then
        if btn._cdStart ~= start or btn._cdDur ~= dur then
            if db.notify.sweep then btn.cd:SetCooldown(start, dur) else btn.cd:Clear() end
            btn._cdStart, btn._cdDur = start, dur
        end
        btn._wasOnCd = true
        btn._cooling = true
        if db.cooldownText and remaining < 3600 then
            btn.timer:SetText(FormatRemaining(remaining))
        else
            btn.timer:SetText("")
        end
    else
        if btn._cdStart then
            btn.cd:Clear()
            btn._cdStart, btn._cdDur = nil, nil
        end
        btn.timer:SetText("")
        btn._cooling = false
        if btn._wasOnCd then
            -- on cooldown -> ready: flash once
            btn._wasOnCd = false
            btn._readyAt = now
            if db.notify.readyFlash then
                btn._flashUntil = now + 0.25
                btn:SetBackdropBorderColor(Col(currentSkin.spark, 1))
            end
        end
    end
end

local spellTick = 0
local function UpdateAllSpells()
    spellTick = 0
    for key, btn in pairs(spellIcons) do
        if btn:IsShown() then
            UpdateSpellIcon(btn)
            ME.IconFade(btn, GetTime())
        end
    end
end

cdUI.refresh = UpdateAllSpells   -- the Config toggle repaints the icons at once

-- Hundredths need every frame. This touches only icons that are on a cooldown
-- already read by the pass above (plain numbers), and asks the client nothing.
function ME.TickTimers()
    local now = GetTime()
    -- the ready flash and the fade are drawn every frame
    for _, btn in pairs(spellIcons) do
        if btn._fading and btn:IsShown() then ME.IconFade(btn, now) end
    end
    if not db.cooldownText then return end
    for _, btn in pairs(spellIcons) do
        if btn._cdStart and btn:IsShown() then
            local rem = btn._cdStart + btn._cdDur - now
            if rem > 0 and rem < 60 then btn.timer:SetText(FormatRemaining(rem)) end
        end
    end
end

-----------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "UNIT_POWER_UPDATE" then
        if elems.energy:IsShown() then UpdateEnergy() end
        if elems.regen:IsShown() then UpdateRegen(0) end
        if elems.combo:IsShown() then FRHW_UpdateCombo() end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        -- combat state drives auto-hide out of combat, so re-apply on the way
        -- in and out of combat as well as on a target change
        if event ~= "PLAYER_TARGET_CHANGED" and db and db.autoHideOOC then ApplyAll() end
        if elems.combo:IsShown() then FRHW_UpdateCombo() end
        -- optional: a new target restarts the swing bar
        if event == "PLAYER_TARGET_CHANGED" and db and db.elements.swing.resetOnTarget then
            swingElapsed = 0
        end
    elseif event == "PLAYER_SWING" then
        -- arg1 = duration of the swing just started; units are unverified, so
        -- accept seconds directly and only divide when it clearly came in ms.
        if IsReadable(arg1) and arg1 > 0 then
            if arg1 >= 300 then swingDuration = arg1 / 1000
            elseif arg1 >= 0.3 and arg1 < 30 then swingDuration = arg1 end
        end
        swingElapsed = 0
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_DATA_LOAD_RESULT" then
        UpdateAllSpells()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, cast GUID, spell ID
        if elems.trail:IsShown() then ME.LogCast(arg3) end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- a new rank or a new spell: ask the client for the IDs again
        ResolveSpells()
        UpdateAllSpells()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then
        -- the resource may have changed with the form
        if elems.energy:IsShown() then UpdateEnergy() end
        if elems.regen:IsShown() then UpdateRegen(0) end
        if elems.combo:IsShown() then FRHW_UpdateCombo() end
    end
end)
-- Register one at a time under pcall: an unknown event throws and would abort load.
local wantedEvents = {
    "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_SWING", "SPELL_UPDATE_COOLDOWN", "SPELL_DATA_LOAD_RESULT",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "UPDATE_SHAPESHIFT_FORM",
}
for i = 1, #wantedEvents do
    local ev = wantedEvents[i]
    pcall(function() driver:RegisterEvent(ev) end)
end
pcall(function() driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player") end)
pcall(function() driver:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") end)
pcall(function() driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end)
driver:SetScript("OnUpdate", function(_, elapsed)
    if not db then return end
    if elems.swing:IsShown() then UpdateSwingBar(elapsed) end
    if elems.energy:IsShown() then UpdateEnergy() end
    if elems.regen:IsShown() then UpdateRegen(elapsed) end
    if elems.combo:IsShown() then FRHW_UpdateCombo() end
    if elems.trail:IsShown() then ME.PaintTrail() end
    -- ten passes a second is plenty for whole-second numbers; cooldown events
    -- call UpdateAllSpells directly, so a new cooldown still shows at once
    spellTick = spellTick + elapsed
    if spellTick >= 0.1 then UpdateAllSpells() else ME.TickTimers() end
end)

-----------------------------------------------------------------------
-- Boot
-----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    -- only for the warrior: the class is asked once, here
    local okClass, _, classFile = pcall(UnitClass, "player")
    if not (okClass and IsReadable(classFile) and classFile == "WARRIOR") then
        ME.wrongClass = true
        for _, fr in ipairs(ALL_ITEMS) do fr:Hide() end
        panel:Hide()
        if gridFrame then gridFrame:Hide() end
        driver:SetScript("OnUpdate", nil)
        driver:SetScript("OnEvent", nil)
        if driver.UnregisterAllEvents then driver:UnregisterAllEvents() end
        return
    end
    if type(ForeverWarriorHUD_DB) ~= "table" then ForeverWarriorHUD_DB = {} end
    db = ForeverWarriorHUD_DB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = (type(v) == "table") and DeepCopy(v) or v end
    end
    -- upgrade from 1.3.0 and older: old x/y become the base offset
    if db.point ~= nil then
        db.baseX = db.x or 0
        db.baseY = db.y or -140
        db.point, db.x, db.y = nil, nil, nil
    end
    for key, v in pairs(DEFAULTS.elements) do
        if type(db.elements[key]) ~= "table" then db.elements[key] = DeepCopy(v) end
        for kk, vv in pairs(v) do
            if db.elements[key][kk] == nil then db.elements[key][kk] = vv end
        end
    end
    if type(db.spells) ~= "table" then db.spells = {} end
    for key, v in pairs(DEFAULTS.spells) do
        if type(db.spells[key]) ~= "table" then db.spells[key] = DeepCopy(v) end
        for kk, vv in pairs(v) do
            if db.spells[key][kk] == nil then db.spells[key][kk] = vv end
        end
    end
    -- saved profiles: own table, never rebuilt from defaults
    if type(db.profiles) ~= "table" then db.profiles = {} end
    -- swing options: fill and clamp, so an upgrade from 1.8.0 or a hand-edited
    -- file cannot leave a nil or a string where the swing bar expects a number
    ClampSwing(db.elements.swing, db.elements.swing, DEFAULTS.elements.swing)
    -- an unknown skin name falls back to the default look
    if not SKIN_BY_KEY[db.skin] then db.skin = SKIN_DEFAULT end
    db.cooldownText = db.cooldownText ~= false
    ResolveSpells()
    ME.ClampNotify(db.notify)
    ME.ClampCustom(db.custom, db.customOn)
    if type(db.schemes) ~= "table" then db.schemes = {} end
    if db.art ~= "low" and db.art ~= "off" then db.art = "high" end
    if db.artBanner ~= "b" then db.artBanner = "a" end
    -- before 2.0 one switch turned every bar; now each item has its own rotation
    for _, e in pairs(db.elements) do
        if db.orientation == "v" and (e.rot or 0) == 0 then e.rot = 90 end
        e.rot = ME.Norm(e.rot, false)
    end
    db.orientation = "h"
    for _, sp in pairs(db.spells) do sp.rot = ME.Norm(sp.rot, true) end
    ApplySkin(db.skin)
    ApplyAll()
    ReflowAll(true)
    FRHW_RefreshPanel()
    RefreshProfileList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r " .. FRHW_VERSION
        .. " loaded — /fw for options, /fw help for how it works, /fw abilities for spell tracking, /fw skins for skins, /fw profiles for saved setups.")
end)

-----------------------------------------------------------------------
-- Slash commands
-----------------------------------------------------------------------
SLASH_FOREVERWARRIORHUD1 = "/fw"
SlashCmdList.FOREVERWARRIORHUD = function(msg)
    if ME.wrongClass or not db then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r is for the warrior class and stays off on this character.")
        return
    end
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()
    if msg == "" or msg == "options" or msg == "panel" then
        if panel:IsShown() then panel:Hide() else panel:Show(); SelectTab("hud"); FRHW_RefreshPanel() end
    elseif msg == "config" or msg == "abilities" then
        panel:Show(); SelectTab("config"); FRHW_RefreshPanel()
    elseif msg == "profiles" or msg == "profile" then
        panel:Show(); SelectTab("profiles"); FRHW_RefreshPanel()
    elseif msg == "skins" then
        panel:Show(); SelectTab("skins"); FRHW_RefreshPanel()
    elseif msg:match("^skin%s") then
        -- accept the key ("gilded_reliquary") or the display name ("Gilded Reliquary")
        local want = msg:match("^skin%s+(.+)$"):gsub("%s+", "_")
        if FRHW_SetSkin(want) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r skin: " .. SKIN_BY_KEY[want].name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r no skin named '" .. want .. "'. Open /fw skins for the list.")
        end
    elseif msg:match("^save") then
        -- profile names keep their case, so take them from the raw message
        local name = raw:match("^%S+%s+(.+)$")
        if not EditMode() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r open the options window first (/fw profiles) to save a profile.")
        elseif not name or name == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r usage: /fw save <name>")
        elseif type(db.profiles) == "table" and db.profiles[TrimName(name)] ~= nil then
            FRHW_PendingProfile = TrimName(name)
            StaticPopup_Show("FRHW_CONFIRM_OVERWRITE", TrimName(name))
        else
            local ok, m = SaveProfile(name)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r " .. m)
            if ok then selectedProfile = TrimName(name); RefreshProfileList() end
        end
    elseif msg:match("^load") then
        local name = raw:match("^%S+%s+(.+)$")
        if not EditMode() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r open the options window first (/fw profiles) to load a profile.")
        elseif not name or name == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r usage: /fw load <name>")
        else
            local ok, m = LoadProfile(name)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r " .. m)
            if ok then selectedProfile = TrimName(name); RefreshProfileList() end
        end
    elseif msg == "show" then db.shown = true;  ApplyAll()
    elseif msg == "hide" then db.shown = false; ApplyAll()
    elseif msg == "lock" then db.locked = true
    elseif msg == "unlock" then db.locked = false
    elseif msg:match("^energy") or msg:match("^regen") or msg:match("^swing") or msg:match("^combo") or msg:match("^trail") then
        local key, st = msg:match("^(%a+)%s*(%a*)")
        if elems[key] then
            if st == "off" then db.elements[key].enabled = false
            elseif st == "on" or st == "" then db.elements[key].enabled = true end
            ApplyElement(key)
        end
    elseif msg:match("^cooldown") then
        local st = msg:match("^cooldown%s+(%a+)")
        if st == "on" then db.cooldownText = true
        elseif st == "off" then db.cooldownText = false
        else db.cooldownText = not db.cooldownText end
        FRHW_RefreshPanel(); UpdateAllSpells()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r countdown numbers " .. (db.cooldownText and "on" or "off"))
    elseif msg:match("^sticky") then
        db.sticky = not db.sticky; FRHW_RefreshPanel()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r sticky items " .. (db.sticky and "on" or "off"))
    elseif msg:match("^grid") then
        db.gridSnap = not db.gridSnap; FRHW_RefreshPanel()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r snap to grid " .. (db.gridSnap and "on" or "off"))
    elseif msg == "help" or msg == "?" then
        panel:Show(); SelectTab("help"); FRHW_RefreshPanel()
    elseif msg == "reset" then
        StaticPopup_Show("FRHW_CONFIRM_RESET")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD|r /fw, /fw help, /fw abilities, /fw skins, /fw profiles, show|hide, "
            .. "energy|regen|swing|combo|trail on|off, cooldown on|off, lock|unlock, sticky, grid, skin <name>, save <name>, load <name>, reset")
    end
end
