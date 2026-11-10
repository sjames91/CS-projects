init = function()
  Chispita_init()
  player_init()
  level_init(1)
end

update = function()
  player_update()
  Chispita_update()
end

draw = function()
  Chispita_draw()
end
