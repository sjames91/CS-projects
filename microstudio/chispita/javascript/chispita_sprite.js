var chispita_sprites = []
var chispita_next_id = 1
var physics_on = "on"
var physics_off = "off"

  // Create a new sprite.
function chispita_new_sprite(x, y, shape, physics) {
  // Left out, a position is 0, as in microScript.
  if (!x) x = 0
  if (!y) y = 0

  // Basic sprite variables
  var s = {}
  s.id = chispita_next_id
  chispita_next_id += 1
  s.sprite_name = 0
  s.x = x
  s.y = y
  s.old_x = x
  s.old_y = y
  s.vx = 0
  s.vy = 0

  // Sprite physics variables
  s.active = 1
  s.physics = 1
  s.fall = 1
  s.fixed = 0
  s.kinematic = 0
  s.solid = 1
  s.bounciness = 0.3
  s.friction = 1
  s.air_friction = 1
  s.grounded = 0
  s.riding = 0
  s.group = "default"
  s.one_way = 0
  s.drop_through = 0
  s.mass = 1
  s.grip = 0
  s.rotate_hit_box = 1
  s.drag = 1
  s.lifetime = 0

  // Sprite hit box variables
  s.hit_box_shape = shape
  s.hit_offset_x = 0
  s.hit_offset_y = 0
  s.hit_parts = 0
  // Edges of the hit box, worked out each collision pass. Sprites with
  // physics off keep these, so they still sort with the rest.
  s.left = x
  s.right = x
  s.bottom = y
  s.top = y

  // Sprite hurt box variables
  s.hurt_box = 0
  s.hurt_box_shape = shape
  s.hurt_offset_x = 0
  s.hurt_offset_y = 0
  s.hurt_parts = 0

  //Hit and hurt boxes only make collision object once not every frame.
  s.hit_shape = {}
  s.hurt_shape = {}

  //Sprite triggers
  s.trigger = 0
  s.was_trigger = 0
  s.callback = 0  //every frame while touching: callback(self, other)
  s.on_enter = 0  // first frame touching
  s.on_exit = 0   // first frame after touching
  s.on_tile = 0   // touching a map tile: on_tile(self, tile)
  s.on_hurt = 0   //hurt box reached another sprite: on_hurt(self, other)
  s.contacts = {}
  s.old_contacts = {}
  s.tile_contacts = {}
  s.tile_touched = 0
  s.hurting = {}
  s.on_hit = 0
  s.hit_list = {}
  s.old_hit_list = {}

  //Sprite draw variables
  s.visible = 1
  s.layer = 1
  s.depth_sort = 0
  s.parallax = 1
  s.ui = 0
  s.fill = "fill"
  s.color = "rgb(255,255,255)"
  s.alpha = 1
  s.image = 0                   // name of a sprite from the sprite editor
  s.image_part = 0              // part of the image to draw (x, y, w, h in pixels), for tile sheets
  s.animations = {}             // name -> separate image, when not using a sheet
  s.animation = 0               // name of the animation playing, or 0
  s.sheet = 0                   // sprite sheet from Chispita_addSheet
  s.frame = 0                   // position in the current animation
  s.frame_time = 0
  s.animation_speed = 1         // 2 plays twice as fast, 0.5 half speed
  s.animation_done = 0          // 1 once a play-once animation has finished
  s.on_animation_end = 0        // function(self, name), at the end of each run
  s.flip_x = 0
  s.flip_y = 0
  s.rotation = 0                // degrees, only changes the drawing

  if (physics && physics != physics_on && physics != physics_off) {
    chispita_warn("physics should be physics_on or physics_off, not " + physics + ". Using physics_on.")
  }

  // Physics off
  if (physics == physics_off) {
    s.physics = 0
    s.fall = 0
    s.fixed = 1
    s.solid = 0
    s.bounciness = 0
  }

  //Draw sprites
  s.draw = function() {
    chispita_draw_sprite(s)
  }

  if (!chispita_sprite_fields) {
    chispita_sprite_fields = {}
    for (var key in s) {
      chispita_sprite_fields[key] = 1
    }
    for (var key of ["width", "height", "radius", "hit_width", "hit_height", "hit_radius", "hurt_width", "hurt_height", "hurt_radius", "removed", "was_hurting"]) {
      chispita_sprite_fields[key] = 1
    }
  }

  chispita_sprites.push(s)
  chispita_add_drawable(s)
  return s
}

var chispita_sprite_fields = 0
var chispita_field_verdicts = {}
var chispita_field_check_index = 0

function chispita_close_name(a, b) {
  if (a.length < 4 || b.length < 4) return 0
  var limit = 2
  if (b.length < 5) limit = 1
  if (Math.abs(a.length - b.length) > limit) return 0
  var previous = []
  for (var j = 0; j <= b.length; j++) {
    previous.push(j)
  }
  for (var i = 1; i <= a.length; i++) {
    var current = [i]
    var letter = a.substring(i - 1, i)
    for (var j = 1; j <= b.length; j++) {
      var cost = 1
      if (letter == b.substring(j - 1, j)) cost = 0
      current.push(Math.min(Math.min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost))
    }
    previous = current
  }
  return previous[b.length] <= limit
}

function chispita_check_fields(s) {
  for (var key in s) {
    if (chispita_sprite_fields[key]) continue
    var verdict = chispita_field_verdicts[key]
    if (!verdict) {
      verdict = "ok"
      for (var known in chispita_sprite_fields) {
        if (chispita_close_name(key, known)) {
          verdict = known
          break
        }
      }
      chispita_field_verdicts[key] = verdict
    }
    if (verdict != "ok") {
      chispita_warn("sprite #" + s.id + " has '" + key + "', which isn't a sprite setting. Did you mean '" + verdict + "'? (If it's your own variable, ignore this.)")
      chispita_field_verdicts[key] = "ok"
    }
  }
}

function chispita_check_sprite_fields() {
  var n = chispita_sprites.length
  if (n == 0 || !chispita_sprite_fields) return
  for (var k = 1; k <= Math.min(4, n); k++) {
    if (chispita_field_check_index >= n) chispita_field_check_index = 0
    chispita_check_fields(chispita_sprites[chispita_field_check_index])
    chispita_field_check_index += 1
  }
}

function Chispita_addRect(x, y, width, height, physics) {
  if (width <= 0 || height <= 0) {
    chispita_warn("Chispita_addRect needs a width and height above 0 (got " + width + " by " + height + ").")
  }
  var rect = chispita_new_sprite(x, y, "rect", physics)
  rect.width = width
  rect.height = height
  rect.hit_width = width
  rect.hit_height = height
  rect.hurt_width = width
  rect.hurt_height = height
  return rect
}

function Chispita_addCircle(x, y, radius, physics) {
  if (radius <= 0) {
    chispita_warn("Chispita_addCircle needs a radius above 0 (got " + radius + ").")
  }
  var circle = chispita_new_sprite(x, y, "circle", physics)
  circle.radius = radius
  circle.hit_radius = radius
  circle.hurt_radius = radius
  return circle
}

function Chispita_addCapsule(x, y, width, height, physics) {
  if (width <= 0 || height <= 0) {
    chispita_warn("Chispita_addCapsule needs a width and height above 0 (got " + width + " by " + height + ").")
  }
  if (height < width) {
    chispita_warn("Chispita_addCapsule: height should be at least the width. A capsule stands upright; use rotation to lay it down.")
    height = width
  }
  var capsule = chispita_new_sprite(x, y, "capsule", physics)
  capsule.width = width
  capsule.height = height
  capsule.hit_width = width
  capsule.hit_height = height
  capsule.hurt_width = width
  capsule.hurt_height = height
  return capsule
}

function chispita_make_part(s, kind, width, height, caller) {
  if (!s) {
    chispita_warn(caller + " was given nothing (0) to add a part to.")
    return 0
  }
  var sprite_width = s.width
  var sprite_height = s.height
  if (s.hit_box_shape == "circle") {
    sprite_width = s.radius * 2
    sprite_height = s.radius * 2
  }
  var part = {}
  part.kind = kind
  part.offset_x = 0
  part.offset_y = 0
  part.width = 0
  part.height = 0
  part.radius = 0
  if (kind == "rect" || kind == "capsule") {
    part.width = width
    part.height = height
    if (!part.width) part.width = sprite_width
    if (!part.height) part.height = sprite_height
    if (part.width <= 0 || part.height <= 0) {
      chispita_warn(caller + ": a " + kind + " part needs a width and height above 0.")
    }
    if (kind == "capsule" && part.height < part.width) part.height = part.width
  } else if (kind == "circle") {
    part.radius = width
    if (!part.radius) part.radius = Math.min(sprite_width, sprite_height) / 2
    if (part.radius <= 0) {
      chispita_warn(caller + ": a circle part needs a radius above 0.")
    }
  } else {
    chispita_warn(caller + ": kind should be 'rect', 'circle' or 'capsule', not " + kind + ".")
    return 0
  }
  part.shape = {}
  return part
}

function Chispita_addPart(s, kind, width, height) {
  var part = chispita_make_part(s, kind, width, height, "Chispita_addPart")
  if (!part) return 0
  if (!s.hit_parts) s.hit_parts = []
  s.hit_parts.push(part)
  return part
}

function Chispita_addHurtPart(s, kind, width, height) {
  var part = chispita_make_part(s, kind, width, height, "Chispita_addHurtPart")
  if (!part) return 0
  if (!s.hurt_parts) s.hurt_parts = []
  s.hurt_parts.push(part)
  return part
}

function Chispita_clearParts(s) {
  if (s) s.hit_parts = 0
}

function Chispita_clearHurtParts(s) {
  if (s) s.hurt_parts = 0
}

function Chispita_setSize(s, width, height) {
  s.width = width
  s.height = height
  s.hit_width = width
  s.hit_height = height
  s.hurt_width = width
  s.hurt_height = height
}

function Chispita_setRadius(s, radius) {
  s.radius = radius
  s.hit_radius = radius
  s.hurt_radius = radius
}

function Chispita_disable(o) {
  if (!o) {
    chispita_warn("Chispita_disable was given nothing (0).")
    return
  }
  o.active = 0
  o.visible = 0
}

function Chispita_enable(o) {
  if (!o) {
    chispita_warn("Chispita_enable was given nothing (0).")
    return
  }
  if (o.removed) {
    chispita_warn("Chispita_enable can't bring back something that was removed with Chispita_remove.")
    return
  }
  o.active = 1
  o.visible = 1
}

var chispita_remove_queue = []

function Chispita_remove(o) {
  if (!o) {
    chispita_warn("Chispita_remove was given nothing (0).")
    return
  }
  if (o.removed) return
  o.removed = 1
  o.active = 0
  o.visible = 0
  chispita_remove_queue.push(o)
}

function chispita_purge_removed() {
  if (chispita_remove_queue.length == 0) return
  for (var o of chispita_remove_queue) {
    chispita_remove_from(chispita_sprites, o)
    chispita_remove_from(chispita_drawables, o)
    chispita_remove_from(chispita_maps, o)
    if (Camera.target == o) Camera.target = 0
    if (chispita_dragging == o) chispita_dragging = 0
  }
  for (var s of chispita_sprites) {
    if (s.riding && s.riding.removed) s.riding = 0
  }
  chispita_remove_queue = []
}

function Chispita_addSprite(image, x, y, width, height, physics) {
  if (image && image.frame_width) {
    if (!width) width = image.frame_width
    if (!height) height = width * image.frame_height / image.frame_width
    var character = Chispita_addRect(x, y, width, height, physics)
    Chispita_useSheet(character, image)
    return character
  }

  var picture = sprites[image]
  if (!picture) {
    chispita_warn("no sprite named " + image + ". Check the name in the sprite editor.")
    if (!width) width = 16
    if (!height) height = width
    return Chispita_addRect(x, y, width, height, physics)
  }
  if (!width) width = picture.width
  if (!height) height = width * picture.height / picture.width
  var rect = Chispita_addRect(x, y, width, height, physics)
  rect.image = image
  return rect
}


// Add text
function Chispita_addText(text, x, y, size, color) {
  // Left out, a position is 0, as in microScript.
  if (!x) x = 0
  if (!y) y = 0
  var t = {}
  t.text = text
  t.x = x
  t.y = y
  t.size = size
  if (!t.size) t.size = 10
  t.color = color
  if (!t.color) t.color = "rgb(255,255,255)"
  t.font = "BitCell"
  t.active = 1
  t.visible = 1
  t.layer = 3
  t.parallax = 1
  t.ui = 0

  t.draw = function() {
    screen.setFont(t.font)
    screen.drawText(t.text, chispita_screen_x(t, t.x), chispita_screen_y(t, t.y), chispita_screen_size(t, t.size), t.color)
  }

  chispita_add_drawable(t)
  return t
}


// Particles
var chispita_particles = []
var chispita_particle_layer = 0

function Chispita_burst(x, y, count, color, speed, life, size) {
  if (!count) count = 10
  if (!color) color = "rgb(255,255,255)"
  if (!speed) speed = 60
  if (!life) life = 0.5
  if (!size) size = 2

  if (!chispita_particle_layer) {
    chispita_particle_layer = {
      layer: 2,
      visible: 1,
      draw: function() {
        chispita_draw_particles()
      }
    }
    chispita_add_drawable(chispita_particle_layer)
  }

  var index = 0
  for (var i = 1; i <= count; i++) {
    while (index < chispita_particles.length) {
      if (!chispita_particles[index].active) break
      index += 1
    }
    if (index >= chispita_particles.length) {
      chispita_particles.push({})
    }
    var p = chispita_particles[index]
    var angle = random.next() * 360
    var this_speed = speed * (0.5 + random.next() * 0.5)
    p.active = 1
    p.x = x
    p.y = y
    p.vx = chispita_cosd(angle) * this_speed
    p.vy = chispita_sind(angle) * this_speed
    p.life = life
    p.max_life = life
    p.size = size
    p.color = color
  }
}

function chispita_update_particles(dt) {
  for (var p of chispita_particles) {
    if (!p.active) continue
    p.life -= dt
    if (p.life <= 0) {
      p.active = 0
    } else {
      p.vy -= chispita_particle_gravity * dt
      p.x += p.vx * dt
      p.y += p.vy * dt
    }
  }
}

function chispita_draw_particles() {
  for (var p of chispita_particles) {
    if (!p.active) continue
    screen.setAlpha(p.life / p.max_life)
    screen.fillRound(chispita_world_x(p.x), chispita_world_y(p.y), p.size * Camera.zoom, p.size * Camera.zoom, p.color)
  }
  screen.setAlpha(1)
}

function chispita_live_particles() {
  var count = 0
  for (var p of chispita_particles) {
    if (p.active) count += 1
  }
  return count
}

function Chispita_addSheet(image, frame_width, frame_height) {
  var sheet = {}
  sheet.is_sheet = 1
  sheet.image = image
  sheet.frame_width = frame_width
  sheet.frame_height = frame_height
  if (!sheet.frame_height) sheet.frame_height = frame_width
  sheet.animations = {}

  var picture = sprites[image]
  if (picture) {
    sheet.columns = Math.max(1, Math.floor(picture.width / sheet.frame_width))
    sheet.rows = Math.max(1, Math.floor(picture.height / sheet.frame_height))
  } else {
    chispita_warn("Chispita_addSheet: no sprite named " + image + ". Check the name in the sprite editor.")
    sheet.columns = 1
    sheet.rows = 1
  }
  return sheet
}

function chispita_make_animation(frames, fps, once) {
  var animation = {}
  animation.frames = frames
  animation.fps = fps
  if (!animation.fps) animation.fps = 8
  animation.once = once
  return animation
}

function Chispita_addAnimation(sheet, name, row, first, count, fps, once) {
  if (!sheet.frame_width) {
    chispita_warn("Chispita_addAnimation needs a sheet from Chispita_addSheet.")
    return
  }
  if (row >= sheet.rows || first + count > sheet.columns) {
    chispita_warn("animation " + name + " goes past the edge of its sheet (" + sheet.columns + " columns, " + sheet.rows + " rows).")
  }
  var frames = []
  for (var i = 0; i <= count - 1; i++) {
    frames.push(row * sheet.columns + first + i)
  }
  sheet.animations[name] = chispita_make_animation(frames, fps, once)
}

function Chispita_addAnimationFrames(sheet, name, frames, fps, once) {
  sheet.animations[name] = chispita_make_animation(frames, fps, once)
}

function Chispita_useSheet(s, sheet) {
  if (!sheet.frame_width) {
    chispita_warn("Chispita_useSheet needs a sheet from Chispita_addSheet.")
    return
  }
  s.sheet = sheet
  s.image = sheet.image
  s.image_part = {}
  s.image_part.w = sheet.frame_width
  s.image_part.h = sheet.frame_height
  s.animation = 0
  chispita_show_sheet_frame(s, 0)
}

function chispita_show_sheet_frame(s, frame_number) {
  var sheet = s.sheet
  s.image_part.x = (frame_number % sheet.columns) * sheet.frame_width
  s.image_part.y = Math.floor(frame_number / sheet.columns) * sheet.frame_height
}

function Chispita_play(s, name, restart) {
  if (s.sheet) {
    var animation = s.sheet.animations[name]
    if (!animation) {
      chispita_warn("sprite #" + s.id + " has no animation named " + name + ". Add it with Chispita_addAnimation first.")
      return
    }
    if (s.animation == name && !restart) return
    s.animation = name
    s.frame = 0
    s.frame_time = 0
    s.animation_done = 0
    chispita_show_sheet_frame(s, animation.frames[0])
    return
  }

  var image = s.animations[name]
  if (image) {
    s.image = image
    s.animation = name
  } else {
    chispita_warn("sprite #" + s.id + " has no animation named " + name + ". Give it a sheet, or set its animations." + name + " to an image.")
  }
}

function chispita_update_animations(dt) {
  for (var s of chispita_sprites) {
    if (!(s.active && s.sheet && s.animation) || s.animation_done) continue
    var animation = s.sheet.animations[s.animation]
    s.frame_time += dt * animation.fps * s.animation_speed

    while (s.frame_time >= 1) {
      s.frame_time -= 1
      s.frame += 1
      if (s.frame >= animation.frames.length) {
        if (animation.once) {
          s.frame = animation.frames.length - 1
          s.animation_done = 1
        } else {
          s.frame = 0
        }
        if (s.on_animation_end) {
          var f = s.on_animation_end
          f(s, s.animation)
        }
        break
      }
    }

    var current = s.sheet.animations[s.animation]
    chispita_show_sheet_frame(s, current.frames[s.frame])
  }
}


// Sprite movement
function chispita_begin_frame() {
  for (var s of chispita_sprites) {
    s.grounded = 0
    if (s.trigger) {
      s.old_contacts = s.contacts
      s.contacts = {}
      s.was_trigger = 1
    } else if (s.was_trigger) {
      s.contacts = {}
      s.old_contacts = {}
      s.was_trigger = 0
    }

    if (s.tile_touched) {
      s.tile_contacts = {}
      s.tile_touched = 0
    }

    if (s.on_hit) {
      s.old_hit_list = s.hit_list
      s.hit_list = {}
    }
  }
}

function chispita_move_sprites(dt) {
  for (var s of chispita_sprites) {
    if (s.active && s.physics && s.kinematic && !s.fixed) {
      s.old_x = s.x
      s.old_y = s.y
      s.x += s.vx * dt
      s.y += s.vy * dt
    }
  }

  for (var s of chispita_sprites) {
    if (s.active && s.physics && !s.fixed && !s.kinematic) {
      s.old_x = s.x
      s.old_y = s.y
      if (s.fall && chispita_mode == "platformer") {
        s.vy -= chispita_gravity * dt
      }
      if (s.riding && s.riding.active) {
        s.x += s.riding.x - s.riding.old_x
        s.y += s.riding.y - s.riding.old_y
      }
      s.riding = 0
      s.x += s.vx * dt
      s.y += s.vy * dt
    }
  }
}

// Sprite friction
function chispita_friction_factor(amount, frames) {
  if (frames == 1) return amount
  return Math.pow(amount, frames)
}

function chispita_apply_friction(dt) {
  var frames = dt * 60
  if (frames <= 0) return
  var ground = chispita_friction_factor(chispita_friction, frames)
  var air = chispita_friction_factor(chispita_air_friction, frames)

  for (var s of chispita_sprites) {
    if (s.active && s.physics && !s.fixed && !s.kinematic && s.drag > 0) {
      if (chispita_mode == "platformer") {
        if (s.grounded) {
          s.vx *= chispita_drag_keep(ground * chispita_friction_factor(s.friction, frames), s.drag)
        } else {
          s.vx *= chispita_drag_keep(air * chispita_friction_factor(s.air_friction, frames), s.drag)
        }
      } else if (chispita_mode == "topdown") {
        var keep = chispita_drag_keep(ground * chispita_friction_factor(s.friction, frames), s.drag)
        s.vx *= keep
        s.vy *= keep
      }
    }
  }
}

function chispita_drag_keep(keep, drag) {
  if (drag == 1) return keep
  return 1 - (1 - keep) * drag
}

function chispita_update_lifetimes(dt) {
  for (var s of chispita_sprites) {
    if (s.lifetime > 0 && s.active) {
      s.lifetime -= dt
      if (s.lifetime <= 0) Chispita_remove(s)
    }
  }
}

// Sprite drawing
function chispita_draw_sprite(s) {
  if (s.alpha <= 0) return
  var x = chispita_screen_x(s, s.x)
  var y = chispita_screen_y(s, s.y)
  var w = 0
  var h = 0
  if (s.hit_box_shape == "circle") {
    w = chispita_screen_size(s, s.radius * 2)
    h = w
  } else {
    w = chispita_screen_size(s, s.width)
    h = chispita_screen_size(s, s.height)
  }

  var margin = Math.max(w, h) / 2
  if (s.rotation) margin = Math.max(w, h)
  if (x + margin < -screen.width / 2 || x - margin > screen.width / 2) return
  if (y + margin < -screen.height / 2 || y - margin > screen.height / 2) return

  if (s.alpha != 1) screen.setAlpha(s.alpha)
  if (s.rotation) screen.setDrawRotation(s.rotation)

  if (s.image) {
    var flipped = s.flip_x || s.flip_y
    if (flipped) {
      var scale_x = 1
      var scale_y = 1
      if (s.flip_x) scale_x = -1
      if (s.flip_y) scale_y = -1
      screen.setDrawScale(scale_x, scale_y)
    }
    if (s.image_part) {
      var p = s.image_part
      screen.drawSpritePart(s.image, p.x, p.y, p.w, p.h, x, y, w, h)
    } else {
      screen.drawSprite(s.image, x, y, w, h)
    }
    if (flipped) screen.setDrawScale(1, 1)
  } else if (s.hit_box_shape == "circle") {
    if (s.fill == "fill") {
      screen.fillRound(x, y, w, h, s.color)
    } else {
      screen.drawRound(x, y, w, h, s.color)
    }
  } else if (s.hit_box_shape == "capsule") {
    if (s.fill == "fill") {
      screen.fillRoundRect(x, y, w, h, w / 2, s.color)
    } else {
      screen.drawRoundRect(x, y, w, h, w / 2, s.color)
    }
  } else {
    if (s.fill == "fill") {
      screen.fillRect(x, y, w, h, s.color)
    } else {
      screen.drawRect(x, y, w, h, s.color)
    }
  }

  if (s.rotation) screen.setDrawRotation(0)
  if (s.alpha != 1) screen.setAlpha(1)
}
