chispita_timers = []
chispita_next_timer_id = 1

chispita_dt = 1 / 60
chispita_time = 0

def Chispita_deltaTime():
  return chispita_dt

def Chispita_gameTime():
  return chispita_time

def Chispita_perSecond(amount=None):
  return amount * chispita_dt

def chispita_free_timer():
  global chispita_next_timer_id
  t = 0
  for slot in chispita_timers:
    if not slot.active:
      t = slot
      break
  if not t:
    t = chispita_obj()
    chispita_timers.append(t)
  t.active = 1
  t.while_paused = chispita_paused
  t.id = chispita_next_timer_id
  chispita_next_timer_id += 1
  t.elapsed = 0
  return t

def chispita_timer_handle(t=None):
  handle = chispita_obj()
  handle.timer = t
  handle.id = t.id
  return handle

def chispita_add_timer(seconds=None, action=None, repeats=None):
  t = chispita_free_timer()
  t.kind = "timer"
  t.duration = seconds
  t.action = action
  t.repeats = repeats
  return chispita_timer_handle(t)

def Chispita_after(seconds=None, action=None):
  return chispita_add_timer(seconds, action, 0)

def Chispita_every(seconds=None, action=None):
  if seconds <= 0:
    chispita_warn("Chispita_every needs more than 0 seconds, or it runs every single frame.")
  return chispita_add_timer(seconds, action, 1)

def Chispita_tween(o=None, field=None, to_value=None, seconds=None, ease=None):
  if not o:
    chispita_warn("Chispita_tween was given nothing (0) to tween.")
    return 0
  if ease and ease != "linear" and ease != "smooth":
    chispita_warn("Chispita_tween ease should be 'linear' or 'smooth', not " + chispita_str(ease) + ".")
  t = chispita_free_timer()
  t.kind = "tween"
  t.duration = seconds
  t.target = o
  t.field = field
  t.from_value = o[field]
  t.to_value = to_value
  t.ease = ease
  if not t.ease: t.ease = "linear"
  return chispita_timer_handle(t)

def Chispita_cancel(handle=None):
  if handle and handle.timer.id == handle.id:
    handle.timer.active = 0

def chispita_update_timers(dt=None, paused_only=None):
  for t in chispita_timers:
    if not t.active: continue
    if paused_only and not t.while_paused: continue
    t.elapsed += dt

    if t.kind == "timer":
      if t.elapsed >= t.duration:
        if t.repeats:
          t.elapsed -= t.duration
        else:
          t.active = 0

        action = t.action
        action()

    elif t.kind == "tween":
      k = 1
      if t.duration > 0: k = min(1, t.elapsed / t.duration)
      if t.ease == "smooth": k = k * k * (3 - 2 * k)
      t.target[t.field] = t.from_value + (t.to_value - t.from_value) * k
      if k >= 1: t.active = 0

def chispita_live_timers():
  count = 0
  for t in chispita_timers:
    if t.active: count += 1
  return count

