# microStudio may run the engine files in any order, so each file that
# needs chispita_obj when it loads makes sure it exists.
if "chispita_obj" not in globals():
  class chispita_obj:
    """An object like microScript's: o.x and o["x"] are the same field, a
    field that was never set is None, and "for key in o" goes through the
    field names."""
    def __init__(self):
      object.__setattr__(self, "_fields", {})
    def __getattr__(self, name):
      if name.startswith("__"): raise AttributeError(name)
      return self._fields.get(name)
    def __setattr__(self, name, value): self._fields[name] = value
    def __getitem__(self, key): return self._fields.get(key)
    def __setitem__(self, key, value): self._fields[key] = value
    def __delitem__(self, key): self._fields.pop(key, None)
    def __contains__(self, key): return key in self._fields
    def __iter__(self): return iter(list(self._fields))
    def __len__(self): return len(self._fields)
    def __bool__(self): return True

chispita_sprites = []
chispita_next_id = 1
physics_on = "on"
physics_off = "off"

# Create a new sprite.
def chispita_new_sprite(x=None, y=None, shape=None, physics=None):
  global chispita_next_id
  # Left out, a position is 0, as in microScript.
  if not x: x = 0
  if not y: y = 0

  # Basic sprite variables
  s = chispita_obj()
  s.id = chispita_next_id
  chispita_next_id += 1
  s.sprite_name = 0
  s.x = x
  s.y = y
  s.old_x = x
  s.old_y = y
  s.vx = 0
  s.vy = 0

  # Sprite physics variables
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

  # Sprite hit box variables
  s.hit_box_shape = shape
  s.hit_offset_x = 0
  s.hit_offset_y = 0
  s.hit_parts = 0
  # Edges of the hit box, worked out each collision pass. Sprites with
  # physics off keep these, so they still sort with the rest.
  s.left = x
  s.right = x
  s.bottom = y
  s.top = y

  # Sprite hurt box variables
  s.hurt_box = 0
  s.hurt_box_shape = shape
  s.hurt_offset_x = 0
  s.hurt_offset_y = 0
  s.hurt_parts = 0

  #Hit and hurt boxes only make collision object once not every frame.
  s.hit_shape = chispita_obj()
  s.hurt_shape = chispita_obj()

  #Sprite triggers
  s.trigger = 0
  s.was_trigger = 0
  s.callback = 0 #every frame while touching: callback(self, other)
  s.on_enter = 0 # first frame touching
  s.on_exit = 0 # first frame after touching
  s.on_tile = 0 # touching a map tile: on_tile(self, tile)
  s.on_hurt = 0 #hurt box reached another sprite: on_hurt(self, other)
  s.contacts = chispita_obj()
  s.old_contacts = chispita_obj()
  s.tile_contacts = chispita_obj()
  s.tile_touched = 0
  s.hurting = chispita_obj()
  s.on_hit = 0
  s.hit_list = chispita_obj()
  s.old_hit_list = chispita_obj()

  #Sprite draw variables
  s.visible = 1
  s.layer = 1
  s.depth_sort = 0
  s.parallax = 1
  s.ui = 0
  s.fill = "fill"
  s.color = "rgb(255,255,255)"
  s.alpha = 1
  s.image = 0 # name of a sprite from the sprite editor
  s.image_part = 0 # part of the image to draw (x, y, w, h in pixels), for tile sheets
  s.animations = chispita_obj() # name -> separate image, when not using a sheet
  s.animation = 0 # name of the animation playing, or 0
  s.sheet = 0 # sprite sheet from Chispita_addSheet
  s.frame = 0 # position in the current animation
  s.frame_time = 0
  s.animation_speed = 1 # 2 plays twice as fast, 0.5 half speed
  s.animation_done = 0 # 1 once a play-once animation has finished
  s.on_animation_end = 0 # function(self, name), at the end of each run
  s.flip_x = 0
  s.flip_y = 0
  s.rotation = 0 # degrees, only changes the drawing

  if physics and physics != physics_on and physics != physics_off:
    chispita_warn("physics should be physics_on or physics_off, not " + chispita_str(physics) + ". Using physics_on.")

  # Physics off
  if physics == physics_off:
    s.physics = 0
    s.fall = 0
    s.fixed = 1
    s.solid = 0
    s.bounciness = 0

  #Draw sprites
  def draw():
    chispita_draw_sprite(s)
  s.draw = draw

  chispita_sprites.append(s)
  chispita_add_drawable(s)
  return s

def Chispita_addRect(x=None, y=None, width=None, height=None, physics=None):
  if width <= 0 or height <= 0:
    chispita_warn("Chispita_addRect needs a width and height above 0 (got " + chispita_str(width) + " by " + chispita_str(height) + ").")
  rect = chispita_new_sprite(x, y, "rect", physics)
  rect.width = width
  rect.height = height
  rect.hit_width = width
  rect.hit_height = height
  rect.hurt_width = width
  rect.hurt_height = height
  return rect

def Chispita_addCircle(x=None, y=None, radius=None, physics=None):
  if radius <= 0:
    chispita_warn("Chispita_addCircle needs a radius above 0 (got " + chispita_str(radius) + ").")
  circle = chispita_new_sprite(x, y, "circle", physics)
  circle.radius = radius
  circle.hit_radius = radius
  circle.hurt_radius = radius
  return circle

def Chispita_addCapsule(x=None, y=None, width=None, height=None, physics=None):
  if width <= 0 or height <= 0:
    chispita_warn("Chispita_addCapsule needs a width and height above 0 (got " + chispita_str(width) + " by " + chispita_str(height) + ").")
  if height < width:
    chispita_warn("Chispita_addCapsule: height should be at least the width. A capsule stands upright; use rotation to lay it down.")
    height = width
  capsule = chispita_new_sprite(x, y, "capsule", physics)
  capsule.width = width
  capsule.height = height
  capsule.hit_width = width
  capsule.hit_height = height
  capsule.hurt_width = width
  capsule.hurt_height = height
  return capsule

def chispita_make_part(s=None, kind=None, width=None, height=None, caller=None):
  if not s:
    chispita_warn(chispita_str(caller) + " was given nothing (0) to add a part to.")
    return 0
  sprite_width = s.width
  sprite_height = s.height
  if s.hit_box_shape == "circle":
    sprite_width = s.radius * 2
    sprite_height = s.radius * 2
  part = chispita_obj()
  part.kind = kind
  part.offset_x = 0
  part.offset_y = 0
  part.width = 0
  part.height = 0
  part.radius = 0
  if kind == "rect" or kind == "capsule":
    part.width = width
    part.height = height
    if not part.width: part.width = sprite_width
    if not part.height: part.height = sprite_height
    if part.width <= 0 or part.height <= 0:
      chispita_warn(chispita_str(caller) + ": a " + chispita_str(kind) + " part needs a width and height above 0.")
    if kind == "capsule" and part.height < part.width: part.height = part.width
  elif kind == "circle":
    part.radius = width
    if not part.radius: part.radius = min(sprite_width, sprite_height) / 2
    if part.radius <= 0:
      chispita_warn(chispita_str(caller) + ": a circle part needs a radius above 0.")
  else:
    chispita_warn(chispita_str(caller) + ": kind should be 'rect', 'circle' or 'capsule', not " + chispita_str(kind) + ".")
    return 0
  part.shape = chispita_obj()
  return part

def Chispita_addPart(s=None, kind=None, width=None, height=None):
  part = chispita_make_part(s, kind, width, height, "Chispita_addPart")
  if not part: return 0
  if not s.hit_parts: s.hit_parts = []
  s.hit_parts.append(part)
  return part

def Chispita_addHurtPart(s=None, kind=None, width=None, height=None):
  part = chispita_make_part(s, kind, width, height, "Chispita_addHurtPart")
  if not part: return 0
  if not s.hurt_parts: s.hurt_parts = []
  s.hurt_parts.append(part)
  return part

def Chispita_clearParts(s=None):
  if s: s.hit_parts = 0

def Chispita_clearHurtParts(s=None):
  if s: s.hurt_parts = 0

def Chispita_setSize(s=None, width=None, height=None):
  s.width = width
  s.height = height
  s.hit_width = width
  s.hit_height = height
  s.hurt_width = width
  s.hurt_height = height

def Chispita_setRadius(s=None, radius=None):
  s.radius = radius
  s.hit_radius = radius
  s.hurt_radius = radius

def Chispita_disable(o=None):
  if not o:
    chispita_warn("Chispita_disable was given nothing (0).")
    return
  o.active = 0
  o.visible = 0

def Chispita_enable(o=None):
  if not o:
    chispita_warn("Chispita_enable was given nothing (0).")
    return
  if o.removed:
    chispita_warn("Chispita_enable can't bring back something that was removed with Chispita_remove.")
    return
  o.active = 1
  o.visible = 1

chispita_remove_queue = []

def Chispita_remove(o=None):
  if not o:
    chispita_warn("Chispita_remove was given nothing (0).")
    return
  if o.removed: return
  o.removed = 1
  o.active = 0
  o.visible = 0
  chispita_remove_queue.append(o)

def chispita_purge_removed():
  global chispita_dragging, chispita_remove_queue
  if len(chispita_remove_queue) == 0: return
  for o in chispita_remove_queue:
    chispita_remove_from(chispita_sprites, o)
    chispita_remove_from(chispita_drawables, o)
    chispita_remove_from(chispita_maps, o)
    if Camera.target == o: Camera.target = 0
    if chispita_dragging == o: chispita_dragging = 0
  for s in chispita_sprites:
    if s.riding and s.riding.removed: s.riding = 0
  chispita_remove_queue = []

def Chispita_addSprite(image=None, x=None, y=None, width=None, height=None, physics=None):
  if isinstance(image, chispita_obj) and image.frame_width:
    if not width: width = image.frame_width
    if not height: height = width * image.frame_height / image.frame_width
    character = Chispita_addRect(x, y, width, height, physics)
    Chispita_useSheet(character, image)
    return character

  picture = chispita_lookup(sprites, image)
  if not picture:
    chispita_warn("no sprite named " + chispita_str(image) + ". Check the name in the sprite editor.")
    if not width: width = 16
    if not height: height = width
    return Chispita_addRect(x, y, width, height, physics)
  if not width: width = picture.width
  if not height: height = width * picture.height / picture.width
  rect = Chispita_addRect(x, y, width, height, physics)
  rect.image = image
  return rect


# Add text
def Chispita_addText(text=None, x=None, y=None, size=None, color=None):
  # Left out, a position is 0, as in microScript.
  if not x: x = 0
  if not y: y = 0
  t = chispita_obj()
  t.text = text
  t.x = x
  t.y = y
  t.size = size
  if not t.size: t.size = 10
  t.color = color
  if not t.color: t.color = "rgb(255,255,255)"
  t.font = "BitCell"
  t.active = 1
  t.visible = 1
  t.layer = 3
  t.parallax = 1
  t.ui = 0

  def draw():
    screen.setFont(t.font)
    screen.drawText(t.text, chispita_screen_x(t, t.x), chispita_screen_y(t, t.y), chispita_screen_size(t, t.size), t.color)
  t.draw = draw

  chispita_add_drawable(t)
  return t


# Particles
chispita_particles = []
chispita_particle_layer = 0

def Chispita_burst(x=None, y=None, count=None, color=None, speed=None, life=None, size=None):
  global chispita_particle_layer
  if not count: count = 10
  if not color: color = "rgb(255,255,255)"
  if not speed: speed = 60
  if not life: life = 0.5
  if not size: size = 2

  if not chispita_particle_layer:
    chispita_particle_layer = chispita_obj()
    chispita_particle_layer.layer = 2
    chispita_particle_layer.visible = 1
    chispita_particle_layer.draw = chispita_draw_particles
    chispita_add_drawable(chispita_particle_layer)

  index = 0
  for i in range(1, count + 1):
    while index < len(chispita_particles):
      if not chispita_particles[index].active: break
      index += 1
    if index >= len(chispita_particles):
      chispita_particles.append(chispita_obj())
    p = chispita_particles[index]
    angle = random.next() * 360
    this_speed = speed * (0.5 + random.next() * 0.5)
    p.active = 1
    p.x = x
    p.y = y
    p.vx = chispita_cosd(angle) * this_speed
    p.vy = chispita_sind(angle) * this_speed
    p.life = life
    p.max_life = life
    p.size = size
    p.color = color

def chispita_update_particles(dt=None):
  for p in chispita_particles:
    if not p.active: continue
    p.life -= dt
    if p.life <= 0:
      p.active = 0
    else:
      p.vy -= chispita_particle_gravity * dt
      p.x += p.vx * dt
      p.y += p.vy * dt

def chispita_draw_particles():
  for p in chispita_particles:
    if not p.active: continue
    screen.setAlpha(p.life / p.max_life)
    screen.fillRound(chispita_world_x(p.x), chispita_world_y(p.y), p.size * Camera.zoom, p.size * Camera.zoom, p.color)
  screen.setAlpha(1)

def chispita_live_particles():
  count = 0
  for p in chispita_particles:
    if p.active: count += 1
  return count

def Chispita_addSheet(image=None, frame_width=None, frame_height=None):
  sheet = chispita_obj()
  sheet.is_sheet = 1
  sheet.image = image
  sheet.frame_width = frame_width
  sheet.frame_height = frame_height
  if not sheet.frame_height: sheet.frame_height = frame_width
  sheet.animations = chispita_obj()

  picture = chispita_lookup(sprites, image)
  if picture:
    sheet.columns = max(1, math.floor(picture.width / sheet.frame_width))
    sheet.rows = max(1, math.floor(picture.height / sheet.frame_height))
  else:
    chispita_warn("Chispita_addSheet: no sprite named " + chispita_str(image) + ". Check the name in the sprite editor.")
    sheet.columns = 1
    sheet.rows = 1
  return sheet

def chispita_make_animation(frames=None, fps=None, once=None):
  animation = chispita_obj()
  animation.frames = frames
  animation.fps = fps
  if not animation.fps: animation.fps = 8
  animation.once = once
  return animation

def Chispita_addAnimation(sheet=None, name=None, row=None, first=None, count=None, fps=None, once=None):
  if not sheet.frame_width:
    chispita_warn("Chispita_addAnimation needs a sheet from Chispita_addSheet.")
    return
  if row >= sheet.rows or first + count > sheet.columns:
    chispita_warn("animation " + chispita_str(name) + " goes past the edge of its sheet (" + chispita_str(sheet.columns) + " columns, " + chispita_str(sheet.rows) + " rows).")
  frames = []
  for i in range(count):
    frames.append(row * sheet.columns + first + i)
  sheet.animations[name] = chispita_make_animation(frames, fps, once)

def Chispita_addAnimationFrames(sheet=None, name=None, frames=None, fps=None, once=None):
  sheet.animations[name] = chispita_make_animation(frames, fps, once)

def Chispita_useSheet(s=None, sheet=None):
  if not sheet.frame_width:
    chispita_warn("Chispita_useSheet needs a sheet from Chispita_addSheet.")
    return
  s.sheet = sheet
  s.image = sheet.image
  s.image_part = chispita_obj()
  s.image_part.w = sheet.frame_width
  s.image_part.h = sheet.frame_height
  s.animation = 0
  chispita_show_sheet_frame(s, 0)

def chispita_show_sheet_frame(s=None, frame_number=None):
  sheet = s.sheet
  s.image_part.x = (frame_number % sheet.columns) * sheet.frame_width
  s.image_part.y = math.floor(frame_number / sheet.columns) * sheet.frame_height

def Chispita_play(s=None, name=None, restart=None):
  if s.sheet:
    animation = s.sheet.animations[name]
    if not animation:
      chispita_warn("sprite #" + chispita_str(s.id) + " has no animation named " + chispita_str(name) + ". Add it with Chispita_addAnimation first.")
      return
    if s.animation == name and not restart: return
    s.animation = name
    s.frame = 0
    s.frame_time = 0
    s.animation_done = 0
    chispita_show_sheet_frame(s, animation.frames[0])
    return

  image = s.animations[name]
  if image:
    s.image = image
    s.animation = name
  else:
    chispita_warn("sprite #" + chispita_str(s.id) + " has no animation named " + chispita_str(name) + ". Give it a sheet, or set its animations." + chispita_str(name) + " to an image.")

def chispita_update_animations(dt=None):
  for s in chispita_sprites:
    if not (s.active and s.sheet and s.animation) or s.animation_done: continue
    animation = s.sheet.animations[s.animation]
    s.frame_time += dt * animation.fps * s.animation_speed

    while s.frame_time >= 1:
      s.frame_time -= 1
      s.frame += 1
      if s.frame >= len(animation.frames):
        if animation.once:
          s.frame = len(animation.frames) - 1
          s.animation_done = 1
        else:
          s.frame = 0
        if s.on_animation_end:
          f = s.on_animation_end
          f(s, s.animation)
        break

    current = s.sheet.animations[s.animation]
    chispita_show_sheet_frame(s, current.frames[s.frame])


# Sprite movement
def chispita_begin_frame():
  for s in chispita_sprites:
    s.grounded = 0
    if s.trigger:
      s.old_contacts = s.contacts
      s.contacts = chispita_obj()
      s.was_trigger = 1
    elif s.was_trigger:
      s.contacts = chispita_obj()
      s.old_contacts = chispita_obj()
      s.was_trigger = 0

    if s.tile_touched:
      s.tile_contacts = chispita_obj()
      s.tile_touched = 0

    if s.on_hit:
      s.old_hit_list = s.hit_list
      s.hit_list = chispita_obj()

def chispita_move_sprites(dt=None):
  for s in chispita_sprites:
    if s.active and s.physics and s.kinematic and not s.fixed:
      s.old_x = s.x
      s.old_y = s.y
      s.x += s.vx * dt
      s.y += s.vy * dt

  for s in chispita_sprites:
    if s.active and s.physics and not s.fixed and not s.kinematic:
      s.old_x = s.x
      s.old_y = s.y
      if s.fall and chispita_mode == "platformer":
        s.vy -= chispita_gravity * dt
      if s.riding and s.riding.active:
        s.x += s.riding.x - s.riding.old_x
        s.y += s.riding.y - s.riding.old_y
      s.riding = 0
      s.x += s.vx * dt
      s.y += s.vy * dt

# Sprite friction
def chispita_friction_factor(amount=None, frames=None):
  if frames == 1: return amount
  return math.pow(amount, frames)

def chispita_apply_friction(dt=None):
  frames = dt * 60
  if frames <= 0: return
  ground = chispita_friction_factor(chispita_friction, frames)
  air = chispita_friction_factor(chispita_air_friction, frames)

  for s in chispita_sprites:
    if s.active and s.physics and not s.fixed and not s.kinematic and s.drag > 0:
      if chispita_mode == "platformer":
        if s.grounded:
          s.vx *= chispita_drag_keep(ground * chispita_friction_factor(s.friction, frames), s.drag)
        else:
          s.vx *= chispita_drag_keep(air * chispita_friction_factor(s.air_friction, frames), s.drag)
      elif chispita_mode == "topdown":
        keep = chispita_drag_keep(ground * chispita_friction_factor(s.friction, frames), s.drag)
        s.vx *= keep
        s.vy *= keep

def chispita_drag_keep(keep=None, drag=None):
  if drag == 1: return keep
  return 1 - (1 - keep) * drag

def chispita_update_lifetimes(dt=None):
  for s in chispita_sprites:
    if s.lifetime > 0 and s.active:
      s.lifetime -= dt
      if s.lifetime <= 0: Chispita_remove(s)

# Sprite drawing
def chispita_draw_sprite(s=None):
  if s.alpha <= 0: return
  x = chispita_screen_x(s, s.x)
  y = chispita_screen_y(s, s.y)
  w = 0
  h = 0
  if s.hit_box_shape == "circle":
    w = chispita_screen_size(s, s.radius * 2)
    h = w
  else:
    w = chispita_screen_size(s, s.width)
    h = chispita_screen_size(s, s.height)

  margin = max(w, h) / 2
  if s.rotation: margin = max(w, h)
  if x + margin < -screen.width / 2 or x - margin > screen.width / 2: return
  if y + margin < -screen.height / 2 or y - margin > screen.height / 2: return

  if s.alpha != 1: screen.setAlpha(s.alpha)
  if s.rotation: screen.setDrawRotation(s.rotation)

  if s.image:
    flipped = s.flip_x or s.flip_y
    if flipped:
      scale_x = 1
      scale_y = 1
      if s.flip_x: scale_x = -1
      if s.flip_y: scale_y = -1
      screen.setDrawScale(scale_x, scale_y)
    if s.image_part:
      p = s.image_part
      screen.drawSpritePart(s.image, p.x, p.y, p.w, p.h, x, y, w, h)
    else:
      screen.drawSprite(s.image, x, y, w, h)
    if flipped: screen.setDrawScale(1, 1)
  elif s.hit_box_shape == "circle":
    if s.fill == "fill":
      screen.fillRound(x, y, w, h, s.color)
    else:
      screen.drawRound(x, y, w, h, s.color)
  elif s.hit_box_shape == "capsule":
    if s.fill == "fill":
      screen.fillRoundRect(x, y, w, h, w / 2, s.color)
    else:
      screen.drawRoundRect(x, y, w, h, w / 2, s.color)
  else:
    if s.fill == "fill":
      screen.fillRect(x, y, w, h, s.color)
    else:
      screen.drawRect(x, y, w, h, s.color)

  if s.rotation: screen.setDrawRotation(0)
  if s.alpha != 1: screen.setAlpha(1)
