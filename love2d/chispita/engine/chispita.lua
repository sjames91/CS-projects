-- Chispita for LÖVE, version 0.21. A port of the microStudio version: the
-- same functions, settings and behavior, file for file.
--
-- Load it once at the top of main.lua:
--   require("engine/chispita")
--
-- chispita_debug, chispita_helpers and chispita_crt are optional: take
-- their lines out below to leave them out of a game.

local here = (...):gsub("[^%./]+$", "")

require(here .. "chispita_screen")     -- microStudio-style screen, sprites, maps, mouse, keyboard
require(here .. "chispita_config")
require(here .. "chispita_main")
require(here .. "chispita_sprite")
require(here .. "chispita_collision")
require(here .. "chispita_map")
require(here .. "chispita_camera")
require(here .. "chispita_timers")
require(here .. "chispita_debug")      -- optional
require(here .. "chispita_helpers")    -- optional
require(here .. "chispita_crt")        -- optional
