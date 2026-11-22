-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

--[[
================================================================================
MistUI - English Locale (Default)
================================================================================
Base locale. All keys use `true` (the key itself is the display value).

When adding new strings:
1. Add L[<your key>] = true here
2. Use L["Your String"] in your code
3. Add translations to other locale files
================================================================================
]]

-- Silent: the release is English only and every key is its English text, so a missing entry shows
-- that text instead of raising an error; npm run check reports missing entries before a release.
local L = LibStub("AceLocale-3.0-MistUI"):NewLocale("MistUI", "enUS", true, true)
if not L then return end

-- ============================================================================
-- CORE / GENERAL
-- ============================================================================

-- Combat lockdown messages
L["Cannot toggle editor mode during combat!"] = true
L["Editor mode closed for combat."] = true
L["Cannot reset positions during combat!"] = true
L["Cannot move frames during combat!"] = true
L["Cannot open options in combat."] = true
L["Options panel not available. Try /reload."] = true

-- Farm mode
L["Farm mode enabled"] = true
L["Farm mode disabled"] = true
L["Minimap module not available."] = true

-- Module availability
L["Editor mode not available."] = true
L["Position editor not available."] = true
L["Reset only supports resetting every position at once. Use /mistui reset."] = true
L["Minimap module restored to stock defaults"] = true
L["Targeting: %s"] = true
L["XP: %d/%d"] = true
L["XP: "] = true
L["Remaining: "] = true
L["Rested: "] = true

-- Errors
L["Error -- Addon 'MistUI_Options' not found or is disabled."] = true

-- ============================================================================
-- SLASH COMMANDS / HELP
-- ============================================================================

L["Unknown command: "] = true
L["=== MistUI Commands ==="] = true
L["/mistui or /mist - Open configuration"] = true
L["/mistui config - Open configuration"] = true
L["/mistui edit - Toggle editor mode (move UI elements)"] = true
L["/mistui reset - Reset all positions to defaults"] = true
L["/mistui status - Show module status"] = true
L["/mistui farm - Toggle farm mode (big minimap, chrome hidden)"] = true
L["/mistui version - Show version info"] = true
L["/mistui help - Show this help"] = true
L["/rl - Reload UI"] = true

-- ============================================================================
-- STATUS DISPLAY
-- ============================================================================

L["=== MistUI Status ==="] = true
L["Loaded"] = true
L["Editable Frames: "] = true
L["MistUI Version: "] = true

-- ============================================================================
-- EDITOR MODE
-- ============================================================================

L["Exit Edit Mode"] = true
L["Reset All Positions"] = true
L["Are you sure you want to reset all interface elements to their default positions?"] = true
L["Reset Position"] = true
L["Yes"] = true
L["No"] = true
L["Reload Now"] = true

-- Position presets (edit mode)
L["Position Preset"] = true
L["Save"] = true
L["Import"] = true
L["Cancel"] = true
L["Load"] = true
L["Delete"] = true
L["Select All"] = true
L["No position presets saved yet."] = true
L["Load position preset '%s'? This will overwrite your current element positions."] = true
L["Delete position preset '%s'? This cannot be undone."] = true
L["Enter a name for the imported position preset:"] = true
L["Imported Position Preset"] = true
L["Position preset saved: "] = true
L["Position preset loaded: "] = true
L["Position preset deleted: "] = true
L["Position preset imported: "] = true
L["Export Position Preset"] = true
L["Import Position Preset"] = true
L["Invalid position preset string."] = true
L["Not a valid MistUI position preset string."] = true
L["Layout not imported: it has a setting this version does not know or cannot use (%s)."] = true
L["Failed to export position preset."] = true
L["Delete Preset"] = true
L["Export Preset"] = true
L["Import Preset"] = true

-- ============================================================================
-- KEYBINDING MODULE
-- ============================================================================


-- ============================================================================
-- GAME MENU
-- ============================================================================


-- ============================================================================
-- MINIMAP MODULE
-- ============================================================================

L["Minimap Buttons"] = true
L["Left-click to show or hide minimap addon buttons."] = "Left-Click to open minimap buttons."
L["Right-click to open MistUI settings."] = true
L["Shift-click to open Editor Mode."] = true

-- ============================================================================
-- EDITOR MODE LABELS (displayed on mover overlays)
-- ============================================================================

L["MainBar"] = "Main Bar"
L["RightBar"] = "Right Bar"
L["LeftBar"] = "Left Bar"
L["BottomBarLeft"] = "Bottom Left"
L["BottomBarRight"] = "Bottom Right"
L["XPBar"] = "XP Bar"
L["RepBar"] = "Rep Bar"
L["MinimapFrame"] = "Minimap"
L["LFGFrame"] = "Dungeon Eye"
L["DurabilityFrame"] = "Durability"
L["PlayerFrame"] = "Player"
L["ManaBar"] = "Mana Bar"
L["PetFrame"] = "Pet"
L["ToT"] = "ToT"
L["ToF"] = "ToF"
L["tot"] = "ToT"
L["fot"] = "FoT"
L["PartyFrames"] = "Party"
L["TargetFrame"] = "Target"
L["FocusFrame"] = "Focus"
L["BagsBar"] = "Bags"
L["MicroMenu"] = "Micro Menu"
L["VehicleExitOverlay"] = "Vehicle Exit"
L["StanceOverlay"] = "Stance Bar"
L["petbar"] = "Pet Bar"
L["boss"] = "Boss Frames"
L["Boss Frames"] = true
L["Raid Frames"] = true
L["Retail-style look for the game's raid frames, with a colored outline for debuffs you can dispel."] = true
L["PlayerCastbar"] = "Castbar"
L["TargetCastbar"] = "Target Castbar"
L["FocusCastbar"] = "Focus Castbar"
L["GCDAnchor"] = "GCD Indicator"
L["Global Cooldown"] = "Global Cooldown"
L["Enable GCD Indicator"] = "Enable GCD Indicator"
L["GCD Height"] = "GCD Height"
L["GCD Width"] = "GCD Width"
L["GCD Color"] = "GCD Color"
L["Always Show GCD Track"] = "Always Show GCD Track"
L["GCD Style"] = "GCD Style"
L["GCD Background"] = "GCD Background"
L["Show GCD Spark"] = "Show GCD Spark"
L["Flat"] = "Flat"
L["Framed"] = "Framed"
L["TooltipWidget"] = "Tooltip"
L["Buff"] = true
L["Debuffs"] = "Debuff"
L["WeaponEnchants"] = "Weapon Enchants"
L["Loot Roll"] = true
L["Quest Tracker"] = true
L["QuestTracker"] = "Quest Tracker"

-- Mover tooltip strings
L["Drag to move"] = true
L["Click to reset"] = true
L["Top"] = true
L["Bottom"] = true
L["Left"] = true
L["Right"] = true
L["Error Messages"] = true
L["ErrorMessages"] = true

-- Editor mode system messages
L["All editable frames shown for editing"] = true
L["All editable frames hidden, positions saved"] = true

-- Editor panel (Forever)
L["Editor Mode"] = true
L["Layout"] = true
L["Custom Layout"] = true
L["Show Grid"] = true
L["Snap to Grid"] = true
L["Undo Move"] = true
L["Save Layout"] = true
L["Delete Layout"] = true
L["Export Layout"] = true
L["Import Layout"] = true
L["Enter a name for the layout:"] = true
L["General"] = true

-- ============================================================================
-- COMPATIBILITY MODULE
-- ============================================================================

-- Conflict warning popup

-- Conflict reasons

-- Nameplate addon compatibility popup
L["Enable"] = true

-- SexyMap compatibility popup
L["MistUI"] = true
L["This specialization uses the MistUI profile \"%s\". Switch to it now? The interface reloads."] = true
L["Switch and Reload"] = true
L["MistUI artwork is missing, so its frames show as green boxes.\n\nClose the game, double-click Install-Artwork.cmd in the Interface\\AddOns\\MistUI folder, then start the game again. The README on the project page has steps for other systems."] = true
L["Artwork missing: close the game and run MistUI\\Install-Artwork.cmd, then start the game again."] = true

-- SexyMap options panel

-- SexyMap slash commands

-- ============================================================================
-- STATIC POPUPS (shared between modules)
-- ============================================================================

L["Changing this setting requires a UI reload to apply correctly."] = true
L["URL"] = true
L["Not Now"] = true
L["Disable"] = true
L["Party/Arena Background"] = true

-- Bag Sort
L["Sort Bags"] = true
L["Sort Bank"] = true
L["Sort Items"] = true
L["Click to sort items by type, rarity, and name."] = true
L["Clear Locked Slots"] = true
L["Click to clear all locked bag slots."] = true
L["Click the lock-clear button to remove all locked slots."] = true
L["Hover an item or slot, then type /sortlock."] = true
L["Slot locked (bag %d, slot %d)."] = true
L["Slot unlocked (bag %d, slot %d)."] = true
L["Could not clear locks (config not ready)."] = true
L["Cleared all sort-locked slots."] = true

-- Sell Scrap
L["Sell Scrap"] = true
L["Click to sell all gray (poor) items to vendor."] = true
L["A merchant window must be open."] = true
L["Open a merchant window first to sell scrap items."] = true
L["Sold %d scrap item(s) for %s."] = true
L["No scrap items to sell."] = true
L["The merchant window closed before all scrap was sold."] = true
L["Skipped %d scrap item(s): item details still loading or the slot changed."] = true

-- Guild Bank Sort
L["You must be at the guild bank."] = true
L["Could not determine the current guild bank tab."] = true
L["You need full deposit and withdraw access to this tab to sort it."] = true
L["This guild bank tab is already sorted!"] = true
L["Sort this guild bank tab? Depending on your server, this may be logged and count against your guild's shared withdrawal allowance, the same as moving items by hand."] = true
L["Sort"] = true
L["Click to sort items in the currently open guild bank tab."] = true
L["Never moves items between tabs."] = true
L["Sort Guild Bank Tab"] = true

-- Micromenu Latency

-- ============================================================================
-- STABILIZATION PATCH STRINGS
-- ============================================================================

L["/mistui debug on|off|status - Toggle diagnostic logging"] = true
L["Usage: /mistui debug on|off|status"] = true
L["Debug mode is %s"] = true
L["Debug mode enabled"] = true
L["Debug mode disabled"] = true
L["enabled"] = true
L["disabled"] = true
L["/mistui errors - Show recorded MistUI errors (on|off|clear)"] = true
L["/mistui report - Show a report to copy into a bug report"] = true
L["Mist-UI report"] = true
L["Copy this text (Ctrl+C) into your bug report."] = true
L["/mistui mouse - Show what is under the mouse pointer"] = true
L["/mistui plates - Save the layout of the name plates on screen"] = true
L["/mistui nameplates on|off - Turn the nameplate module on or off"] = true
L["/mistui perf - Measure where the addon spends its time"] = true
L["Nameplates module not available."] = true
L["Nameplates are %s. Usage: /mistui nameplates on|off"] = true
L["/mistui worldmap on|off - Turn the new world map on or off (after a reload)"] = true
L["World map module not available."] = true
L["The world map is %s. Usage: /mistui worldmap on|off"] = true
L["Nothing under the mouse takes clicks."] = true
L["Under the mouse, topmost first:"] = true
L["Error log cleared."] = true
L["Error log is %s"] = true
L["Error log is %s, %d recorded. Usage: /mistui errors on|off|clear"] = true
L["Enabled"] = true
L["Disabled"] = true
L["Legacy refresh failed for"] = true
L["Test Pet"] = true
L["=== BANK SCAN DEBUG ==="] = true
L["Registered Modules:"] = true
L["No modules registered in ModuleRegistry"] = true
L["load-once"] = true
L["Cooldown Text"] = true
L["Cooldown text on action buttons"] = true
L["Range Indicator"] = true
L["Cast Bar"] = true
L["Custom player, target, and focus cast bars"] = true
L["Interrupted by %s"] = true
L["Player Frame"] = true
L["Retail-styled boss target frames"] = true
L["Retail-styled player unit frame"] = true
L["ModuleRegistry:Register requires name and moduleTable"] = true
L["ModuleRegistry: Module already registered -"] = true
L["ModuleRegistry: Registered module -"] = true
L["order:"] = true
L["ModuleRegistry: Refresh failed for"] = true
L["CombatQueue:Add requires id and func"] = true
L["CombatQueue: Registered PLAYER_REGEN_ENABLED"] = true
L["CombatQueue: Queued operation -"] = true
L["CombatQueue: Removed operation -"] = true
L["CombatQueue: Processing"] = true
L["queued operations"] = true
L["CombatQueue: Failed to execute"] = true
L["CombatQueue: Executed -"] = true
L["CombatQueue: Unregistered PLAYER_REGEN_ENABLED"] = true
L["CombatQueue: Immediate execution failed -"] = true

-- ============================================================================
-- RELEASE PREP STRINGS
-- ============================================================================

L["Buttons"] = true
L["Action button styling and enhancements"] = true
L["Equipment"] = true
L["Usable"] = true
L["Normal"] = true
L["Trade"] = true
L["Customize target/focus aura icons and timers."] = true
L["Aura Borders"] = true
L["Modern borders on buff and debuff icons."] = true
L["Dark Mode"] = true
L["Item Quality"] = true
L["Color item borders by quality in bags, character panel, bank, and merchant"] = true
L["Character Item Counts"] = true
L["Shows per-character bag, bank, and equipped item counts in item tooltips."] = true
L["Bags: %d"] = true
L["Bank: %d"] = true
L["Equipped: %d"] = true
L["Total: %d (%s)"] = true
L["Automatic Equipment Comparison"] = true
L["Compare equippable items with your equipped gear without holding Shift, including item links opened from chat."] = true
L["Item Level"] = true
L["Show item level on gear icons in bags, character panel, bank, and more"] = true
L["Item Level: %d"] = true
L["Repair Cost"] = true
L["No Repairs Needed"] = true
L["Buff Frame"] = true
L["Custom buff frame styling, positioning and toggle button"] = true
L["Chat Mods"] = true
L["Chat enhancements: hide buttons, editbox position, URL copy, chat copy, link hover, tell target"] = true
L["Bag Sort"] = true
L["Sort bags and bank items with buttons"] = true
L["%s any bag slot (item or empty) to lock or unlock it."] = true
L["Alt"] = true
L["Ctrl"] = true
L["Shift"] = true
L["Left Click"] = true
L["Right Click"] = true
L["Middle Click"] = true
L["Bag Skin"] = true
L["Retail-style skin for the stock bag windows"] = true
L["Bagster"] = true
L["All-in-one bag replacement with filtering and search"] = true
L["Alt Gold"] = true
L["Show the gold of your other characters when hovering the money in your bags"] = true
-- Character Panel
L["Character Panel"] = true

-- Pets & Mounts
L["All"] = true
L["Flying"] = true
L["Quest"] = true
L["Character Gold"] = true
L["No other characters recorded yet"] = true
L["(current)"] = true
L["Total"] = true
L["Micro Menu"] = true
L["Main Bars"] = true
L["Main action bars, status bars, scaling and positioning"] = true
L["Minimap"] = true
L["Custom minimap styling, positioning, tracking icons and calendar"] = true
L["Quest tracker positioning and styling"] = true
L["Tooltip"] = true
L["Enhanced tooltip styling with class colors and health bars"] = true
L["Nameplates"] = true
L["Apply MistUI nameplate styling."] = true
L["Unit Frame Layers"] = true
L["Micro menu and bags system styling and positioning"] = true
L["%s's Inventory"] = true
L["%s's Bank"] = true
L["Bags"] = true
L["Bank"] = true
L["|cff00ff00Left-Click|r to toggle bag display"] = true
L["|cff00ff00Right-Click|r to toggle inventory"] = true
L["|cff00ff00Right-Click|r to toggle bank"] = true
L["|cff00ff00Drag|r to move"] = true
L["|cff00ff00Alt+Right-Click|r to reset position"] = true
L["|cff00ff00Left-Click|r to show this bag's items"] = true
L["|cff00ff00Left-Click|r to hide this bag's items"] = true
L["|cff00ff00Drag|r to move this bag"] = true
L["|cff00ff00Right-Click|r to see another character's items"] = true
L["Characters"] = true
L["Log in once with another character of this realm to see its items here."] = true
L["Sort complete."] = true
L["Some item details are still loading. Try the sort again in a moment."] = true
L["Sort stopped."] = true
L["(%s ago)"] = true
L["Click again while sorting to stop."] = true
L["Sort stopped because a move did not finish (bag %d, slot %d). Try again, or lock that slot."] = true
L["Sort stopped because the items in your bags changed (bag %d, slot %d). Sort again."] = true
L["Bags already sorted!"] = true
L["You must be at the bank."] = true
L["Bank already sorted!"] = true
L["Reputation: "] = true

L["Double-Click to Copy"] = true
L["Copy Text"] = true

-- Version Check Module
L["Version Check"] = true

-- ============================================================================
-- FRAME DIAGNOSTIC COMMANDS
-- ============================================================================

L["hidden"] = true
-- Equipment manager pane
L["Panel settings"] = true
L["Fade Map While Moving"] = true
L["Moving Map Alpha"] = true
L["Background"] = true
L["Dark"] = true

-- ============================================================================
-- PANELS TAB / GEAR SUMMARY
-- ============================================================================


--MERCHANT MODULE
L["Merchant"] = true
L["Retail-style vendor window chrome"] = true
L["Quest Dialog"] = true
L["Retail-style quest and gossip window chrome"] = true

-- World Map
L["World Map"] = true
L["Retail-style world map with breadcrumb navigation and a quest log side panel"] = true
L["Map & Quest Log"] = true
L["World"] = true
L["Maximize"] = true
L["Show Quest Log"] = true
L["Hide Quest Log"] = true
L["Show Landmarks"] = true
L["No quests on this map."] = true
L["Untrack"] = true
L["Abandon"] = true
L["Share"] = true
L["Click to view on Map"] = true
L["Search Quest Log"] = true
L["World map module disabled: %s replaces the same map frame."] = true
L["Cursor"] = true
L["Show Map Coordinates"] = true

-- Level Up Enhance Module
L["List"] = true

-- ============================================================================
-- LOW HP ALERT MODULE
-- ============================================================================

L["Low HP Alert"] = true
L["Plays a sound and flashes the screen edges when your HP drops below the threshold."] = true
L["Personal Resource Display"] = true
L["PersonalResource"] = true
L["Add Health and Resource below your Character."] = true
L["Combo Points"] = true
L["Combo points as orbs under the player frame and/or on the target frame."] = true
L["ComboPoints"] = "Combo Points"
L["DKRunes"] = "Death Knight Runes"
L["ClassPower"] = "Class Power"
L["TotemFrame"] = "Totem Timers"
L["Totem Timers"] = true
L["The round totem timers under the player frame, with the HD ring and their own spot in the editor."] = true
L["Hide When Empty"] = true
L["Hide the orbs at 0 points instead of showing them empty."] = true
L["Show a bar above the player cast bar that fills while the global cooldown runs."] = true

-- Talents

-- ============================================================================
-- SPELLBOOK MODULE
-- ============================================================================


-- Dropdown placeholder
L["Click to select"] = true

-- ============================================================================
-- EDITOR SETTINGS (per-frame dialog of the editor)
-- ============================================================================

-- Editor settings
L["AND (both required)"] = true
L["OR (either condition)"] = true
L["Visibility"] = true
L["Always Hidden"] = true
L["Show on Hover Only"] = true
L["Show in Combat Only"] = true
L["Hide in Combat"] = true
L["Hover/Combat Logic"] = true
L["Current Value"] = true
L["Percentage"] = true
L["Numbers + %"] = true
L["Current / Max"] = true
L["Auto"] = true
L["Text Format"] = true
L["Format Large Numbers"] = true
L["Always Show Health Text"] = true
L["Always Show Mana Text"] = true
L["Class Portrait"] = true
L["Alternative Class Icons"] = true
L["Race Portrait"] = true
L["Show PvP Icon"] = true
L["Scale"] = true
L["Fat Health Bar"] = true
L["Hide Mana Bar"] = true
L["Dragon Decoration"] = true
L["None"] = true
L["Elite (Retail)"] = true
L["RareElite (Retail)"] = true
L["Class Color Health"] = true
L["Text Display"] = true
L["Appearance"] = true
L["Glow Effects"] = true
L["Show Rest Glow"] = true
L["Show Combat Flash"] = true
L["Combat Flash Opacity"] = true
L["Alternate Mana (Druid)"] = true
L["Always Show"] = true
L["Percentage + Current/Max"] = true
L["Mana Bar Width"] = true
L["Mana Bar Height"] = true
L["Mana Bar Texture"] = true
L["MistUI (Default)"] = true
L["Classic Bar"] = true
L["Flat Solid"] = true
L["Smooth"] = true
L["Aluminium"] = true
L["LiteStep"] = true
L["Show Buffs"] = true
L["Show Debuffs"] = true
L["Show Name Background"] = true
L["Show Buff/Debuff on Focus"] = true
L["X Position"] = true
L["Y Position"] = true
L["Threat Glow"] = true
L["Orientation"] = true
L["Vertical"] = true
L["Horizontal"] = true
L["Vertical Padding"] = true
L["Horizontal Padding"] = true
L["Width"] = true
L["Height"] = true
L["Show Icon"] = true
L["Icon Size"] = true
L["Modern Icon Border"] = true
L["Text Mode"] = true
L["Simple (Name Only)"] = true
L["Detailed (Name + Time)"] = true
L["Time Precision"] = true
L["Max Time Precision"] = true
L["Behavior"] = true
L["Hold Time (Success)"] = true
L["Hold Time (Interrupt)"] = true
L["Latency Indicator"] = true
L["Enable Latency Indicator"] = true
L["Latency Alpha"] = true
L["Top Left"] = true
L["Bottom Left"] = true
L["Top Right"] = true
L["Bottom Right"] = true
L["Columns"] = true
L["Buttons Shown"] = true
L["Button Spacing"] = true
L["Change Button Order"] = true
L["Button Order"] = true
L["Gryphons"] = true
L["Style"] = true
L["Classic"] = true
L["Retail"] = true
L["Hidden"] = true
L["Gryphon Scale"] = true
L["Gryphon Offset X"] = true
L["Gryphon Offset Y"] = true
L["Size & Scale"] = true
L["Bar Width"] = true
L["Bar Height"] = true
L["Rested XP"] = true
L["Show Rested XP Background"] = true
L["Show Rested XP Mark"] = true
L["Always Show Text"] = true
L["Show XP Percentage"] = true
L["Experience Bar Scale"] = true
L["Reputation Bar Scale"] = true
L["Icon Spacing"] = true
L["Invert Button Order"] = true
L["Hide on Vehicle"] = true
L["Show Latency Indicator"] = true
L["Enable Bagster"] = true
L["Button Size"] = true
L["Text Visibility"] = true
L["Show Hotkey Text"] = true
L["Minimap Buttons Collector"] = true
L["Circle"] = true
L["Arrow"] = true
L["Addon Button Skin"] = true
L["Addon Button Fade"] = true
L["Basic Settings"] = true
L["Border Alpha"] = true
L["Addon Button Distance"] = true
L["Time & Calendar"] = true
L["Show Clock"] = true
L["Clock Font Size"] = true
L["Show Calendar"] = true
L["Display Settings"] = true
L["Zoom Buttons"] = true
L["Zone Text Font Size"] = true
L["Preset"] = true
L["Opacity"] = true
L["Separate Weapon Enchants"] = true
L["Show Spell IDs"] = true
L["Buff Icon Scale"] = true
L["Buffs Per Row"] = true
L["Max Buff Rows"] = true
L["Buff Horizontal Gap"] = true
L["Buff Vertical Gap"] = true
L["Buff Order"] = true
L["Default Order"] = true
L["Player Buffs First"] = true
L["Other Player Buffs First"] = true
L["Duration Buffs First"] = true
L["Show Toggle Button"] = true
L["Layout Preview"] = true
L["Enable Layout Preview"] = true
L["Preview Buff Count"] = true
L["Enable Aura Borders"] = true
L["Border Style"] = true
L["Detailed"] = true
L["Rounded"] = true
L["Square"] = true
L["MistUI Square"] = true
L["Aura Tooltips"] = true
L["Debuff Icon Scale"] = true
L["Debuffs Per Row"] = true
L["Max Debuff Rows"] = true
L["Debuff Horizontal Gap"] = true
L["Debuff Vertical Gap"] = true
L["Debuff Attached Offset Y"] = true
L["Preview Debuff Count"] = true
L["Anchor to Cursor"] = true
L["Cursor Anchor Offset X"] = true
L["Cursor Anchor Offset Y"] = true
L["Class-Colored Border"] = true
L["Class-Colored Name"] = true
L["Target of Target"] = true
L["Styled Health Bar"] = true
L["Show Aura Source"] = true
L["Font Size"] = true
L["Custom Height"] = true
L["Size"] = true
L["Narrow"] = true
L["Wide"] = true
L["Health Bar Height"] = true
L["Short"] = true
L["Tall"] = true
L["Power Bar Height"] = true
L["Padding"] = true
L["Always"] = true
L["In Combat"] = true
L["Hide Health Bar"] = true
L["Hide Power Bar"] = true
L["Hide Alternate Power Bar"] = true
L["Show Class Color"] = true
L["Show Bar Text"] = true
L["Color"] = true
L["Enable Dark Mode"] = true
L["Combat"] = true
L["Action Bars"] = true
L["Bottom Left Bar"] = true
L["Bottom Right Bar"] = true
L["Right Bar"] = true
L["Left Bar"] = true
L["Button Appearance"] = true
L["Main Bar Only Background"] = true
L["Hide Main Bar Art"] = true
L["Hide Button Backgrounds"] = true
L["Button Tooltips"] = true
L["Never"] = true
L["Show Count Text"] = true
L["Show Macro Names"] = true
L["Hotkey Font Size"] = true
L["Show Cooldown Text"] = true
L["Min Duration"] = true
L["Whole Seconds"] = true
L["Show cooldown text in whole seconds, without the tenths under 5 seconds."] = true

-- Addon Manager
L["Turn it back on from the AddOns list at character selection."] = true

-- ============================================================================
-- PROFESSIONS
-- ============================================================================

-- ============================================================================
-- FLIGHT MAP & MAIL
-- ============================================================================
L["Mail"] = true
