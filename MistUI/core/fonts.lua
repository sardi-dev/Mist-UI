-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

-- ============================================================================
-- MistUI - Centralized Font System
-- Single source of truth for locale-aware font selection.
-- Loaded early (via MistUI.xml) so config.lua, database.lua, and all modules
-- can reference addon.Fonts instead of hardcoding font paths.
-- ============================================================================
--
-- The 5.4.8 client ships different fonts per locale:
--   enUS/deDE/frFR/esES/esMX/ptBR : Fonts\FRIZQT__.TTF  + Fonts\ARIALN.TTF
--   ruRU                           : Fonts\FRIZQT___CYR.TTF (Cyrillic)
--   koKR                           : Fonts\2002.TTF (Korean CJK glyphs)
--   zhCN                           : Fonts\ARKai_T.ttf (Simplified Chinese)
--   zhTW                           : Fonts\bLEI00D.TTF (Traditional Chinese)
--
-- Custom fonts (FiraSansCondensed-SemiBold.ttf, PTSansNarrow.ttf) cover Latin-1, Eastern European
-- and Cyrillic, but carry no CJK glyphs. This module selects the correct system
-- font for each locale, falling back to the custom font when safe.
-- ============================================================================

local addon = select(2, ...)

local _locale = GetLocale()

-- ============================================================================
-- FONT TABLES PER LOCALE
-- ============================================================================

-- CJK/Cyrillic font map: locale -> system font that contains the required glyphs
local LOCALE_SYSTEM_FONTS = {
    koKR = "Fonts\\2002.TTF",
    zhCN = "Fonts\\ARKai_T.ttf",
    zhTW = "Fonts\\bLEI00D.TTF",
    ruRU = "Fonts\\FRIZQT___CYR.TTF",
}

-- Only CJK is beyond the bundled fonts; forcing the client font on ruRU would strip the
-- Latin accents every other shipped language needs, so ruRU is deliberately absent here.
local LOCALE_CJK_FONTS = {
    koKR = LOCALE_SYSTEM_FONTS.koKR,
    zhCN = LOCALE_SYSTEM_FONTS.zhCN,
    zhTW = LOCALE_SYSTEM_FONTS.zhTW,
}

-- Does this locale need a system font instead of custom Latin-only fonts?
local _needsSystemFont = (LOCALE_SYSTEM_FONTS[_locale] ~= nil)

-- ============================================================================
-- RESOLVED FONT PATHS
-- ============================================================================

local Fonts = {}

--- Primary UI font (unit frames, tooltips, game menu, general text).
-- Uses FRIZQT__.TTF on Latin locales, locale-specific font on CJK/Cyrillic.
Fonts.PRIMARY = LOCALE_SYSTEM_FONTS[_locale] or "Fonts\\FRIZQT__.TTF"

--- Action bar font (hotkeys, macros, cooldowns, page numbers).
-- Uses Fira Sans Condensed on Latin and Cyrillic locales for a modern retail look,
-- falls back to the locale system font on CJK.
Fonts.ACTIONBAR = LOCALE_CJK_FONTS[_locale]
    or [[Interface\AddOns\MistUI\Fonts\FiraSansCondensed-SemiBold.ttf]]

--- Narrow UI font (options panel, editor mode labels).
-- PTSansNarrow.ttf on Latin and Cyrillic locales, locale system font on CJK.
Fonts.NARROW = LOCALE_CJK_FONTS[_locale]
    or [[Interface\AddOns\MistUI_Options\fonts\PTSansNarrow.ttf]]

--- ARIALN replacement: used where database defaults previously hardcoded ARIALN.
-- On Latin locales ARIALN is fine; on CJK/Cyrillic we substitute the system font.
Fonts.ARIALN = LOCALE_SYSTEM_FONTS[_locale] or "Fonts\\ARIALN.TTF"

--- Whether the current locale requires a system font (CJK or Cyrillic).
Fonts.needsSystemFont = _needsSystemFont

--- The raw locale string (e.g. "enUS", "koKR").
Fonts.locale = _locale

-- ============================================================================
-- EXPORT
-- ============================================================================

addon.Fonts = Fonts
