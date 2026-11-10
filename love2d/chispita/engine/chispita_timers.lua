local min = math.min

chispita_timers = {}
chispita_next_timer_id = 1

chispita_dt = 1 / 60
chispita_time = 0

function Chispita_deltaTime()
  return chispita_dt
end

function Chispita_gameTime()
  return chispita_time
end

function Chispita_perSecond(amount)
  return amount * chispita_dt
end

function chispita_free_timer()
  local t = false
  for _, slot in ipairs(chispita_timers) do
    if not slot.active then
      t = slot
      break
    end
  end
  if not t then
    t = {}
    table.insert(chispita_timers, t)
  end
  t.active = true
  t.while_paused = chispita_paused
  t.id = chispita_next_timer_id
  chispita_next_timer_id = chispita_next_timer_id + 1
  t.elapsed = 0
  return t
end

function chispita_timer_handle(t)
  local handle = {}
  handle.timer = t
  handle.id = t.id
  return handle
end

function chispita_add_timer(seconds, action, repeats)
  local t = chispita_free_timer()
  t.kind = "timer"
  t.duration = seconds
  t.action = action
  t.repeats = repeats
  return chispita_timer_handle(t)
end

function Chispita_after(seconds, action)
  return chispita_add_timer(seconds, action, false)
end

function Chispita_every(seconds, action)
  if seconds <= 0 then
    chispita_warn("Chispita_every needs more than 0 seconds, or it runs every single frame.")
  end
  return chispita_add_timer(seconds, action, true)
end

function Chispita_tween(o, field, to_value, seconds, ease)
  if not o then
    chispita_warn("Chispita_tween was given nothing (nil) to tween.")
    return false
  end
  if ease and ease ~= "linear" and ease ~= "smooth" then
    chispita_warn("Chispita_tween ease should be 'linear' or 'smooth', not " .. tostring(ease) .. ".")
  end
  local t = chispita_free_timer()
  t.kind = "tween"
  t.duration = seconds
  t.target = o
  t.field = field
  t.from = o[field]
  t.to_value = to_value
  t.ease = ease
  if not t.ease then t.ease = "linear" end
  return chispita_timer_handle(t)
end

function Chispita_cancel(handle)
  if handle and handle.timer.id == handle.id then
    handle.timer.active = false
  end
end

function chispita_update_timers(dt, paused_only)
  for _, t in ipairs(chispita_timers) do
    if t.active and not (paused_only and not t.while_paused) then
      t.elapsed = t.elapsed + dt

      if t.kind == "timer" then
        if t.elapsed >= t.duration then
          if t.repeats then
            t.elapsed = t.elapsed - t.duration
          else
            t.active = false
          end

          local action = t.action
          action()
        end

      elseif t.kind == "tween" then
        local k = 1
        if t.duration > 0 then k = min(1, t.elapsed / t.duration) end
        if t.ease == "smooth" then k = k * k * (3 - 2 * k) end
        t.target[t.field] = t.from + (t.to_value - t.from) * k
        if k >= 1 then t.active = false end
      end
    end
  end
end

function chispita_live_timers()
  local count = 0
  for _, t in ipairs(chispita_timers) do
    if t.active then count = count + 1 end
  end
  return count
end
