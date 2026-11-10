var chispita_timers = []
var chispita_next_timer_id = 1

var chispita_dt = 1 / 60
var chispita_time = 0

function Chispita_deltaTime() {
  return chispita_dt
}

function Chispita_gameTime() {
  return chispita_time
}

function Chispita_perSecond(amount) {
  return amount * chispita_dt
}

function chispita_free_timer() {
  var t = 0
  for (var slot of chispita_timers) {
    if (!slot.active) {
      t = slot
      break
    }
  }
  if (!t) {
    t = {}
    chispita_timers.push(t)
  }
  t.active = 1
  t.while_paused = chispita_paused
  t.id = chispita_next_timer_id
  chispita_next_timer_id += 1
  t.elapsed = 0
  return t
}

function chispita_timer_handle(t) {
  var handle = {}
  handle.timer = t
  handle.id = t.id
  return handle
}

function chispita_add_timer(seconds, action, repeats) {
  var t = chispita_free_timer()
  t.kind = "timer"
  t.duration = seconds
  t.action = action
  t.repeats = repeats
  return chispita_timer_handle(t)
}

function Chispita_after(seconds, action) {
  return chispita_add_timer(seconds, action, 0)
}

function Chispita_every(seconds, action) {
  if (seconds <= 0) {
    chispita_warn("Chispita_every needs more than 0 seconds, or it runs every single frame.")
  }
  return chispita_add_timer(seconds, action, 1)
}

function Chispita_tween(o, field, to_value, seconds, ease) {
  if (!o) {
    chispita_warn("Chispita_tween was given nothing (0) to tween.")
    return 0
  }
  if (ease && ease != "linear" && ease != "smooth") {
    chispita_warn("Chispita_tween ease should be 'linear' or 'smooth', not " + ease + ".")
  }
  var t = chispita_free_timer()
  t.kind = "tween"
  t.duration = seconds
  t.target = o
  t.field = field
  t.from = o[field]
  t.to_value = to_value
  t.ease = ease
  if (!t.ease) t.ease = "linear"
  return chispita_timer_handle(t)
}

function Chispita_cancel(handle) {
  if (handle && handle.timer.id == handle.id) {
    handle.timer.active = 0
  }
}

function chispita_update_timers(dt, paused_only) {
  for (var t of chispita_timers) {
    if (!t.active) continue
    if (paused_only && !t.while_paused) continue
    t.elapsed += dt

    if (t.kind == "timer") {
      if (t.elapsed >= t.duration) {
        if (t.repeats) {
          t.elapsed -= t.duration
        } else {
          t.active = 0
        }

        var action = t.action
        action()
      }

    } else if (t.kind == "tween") {
      var k = 1
      if (t.duration > 0) k = Math.min(1, t.elapsed / t.duration)
      if (t.ease == "smooth") k = k * k * (3 - 2 * k)
      t.target[t.field] = t.from + (t.to_value - t.from) * k
      if (k >= 1) t.active = 0
    }
  }
}

function chispita_live_timers() {
  var count = 0
  for (var t of chispita_timers) {
    if (t.active) count += 1
  }
  return count
}
