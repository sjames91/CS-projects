-- Chispita 0.21 demo. Arrow keys move, UP jumps, D shows debug mode,
-- C changes the CRT preset.

require("engine/chispita")

local presets = { "off", "crisp", "soft", "arcade", "dreamy", "tv" }
local preset = 3

function love.load()
  Chispita_init()
  chispita_mode = "platformer"
  chispita_background = "rgb(20,16,42)"
  Chispita_crtPreset(presets[preset])

  level = Chispita_addMap("demo", 0, 0)
  Chispita_setOneWay(level, "plank")
  Chispita_limitCameraToMap(level)

  coins = Chispita_spawnFromMap(level, "coin")
  for _, coin in ipairs(coins) do
    coin.physics = false
  end

  player = Chispita_addRect(-200, 0, 10, 14)
  player.color = "rgb(255,210,63)"
  player.sprite_name = "player"
  Chispita_setTarget(player)
  Camera.smooth = 0.15

  score = 0
  score_text = Chispita_addText("SCORE 0", -140, 90, 8)
  score_text.ui = true
  preset_text = Chispita_addText("CRT: " .. presets[preset] .. "  (C to change)", 110, 90, 6)
  preset_text.ui = true
end

function love.update(dt)
  if keyboard.LEFT then player.vx = player.vx - 20 end
  if keyboard.RIGHT then player.vx = player.vx + 20 end
  if keyboard.press.UP and player.grounded then player.vy = 230 end
  if keyboard.press.D then Chispita_toggleDebug() end
  if keyboard.press.C then
    preset = preset % #presets + 1
    if presets[preset] == "off" then
      chispita_crt = false
    else
      Chispita_crtPreset(presets[preset])
    end
    preset_text.text = "CRT: " .. presets[preset] .. "  (C to change)"
  end

  for _, coin in ipairs(coins) do
    if coin.active and Chispita_overlaps(player, coin) then
      Chispita_remove(coin)
      Chispita_burst(coin.x, coin.y, 12, "rgb(255,220,80)", 80, 0.4, 2)
      score = score + 10
      score_text.text = "SCORE " .. score
    end
  end

  Chispita_update(dt)
end

function love.draw()
  Chispita_draw()
  Chispita_applyCrt()
end
