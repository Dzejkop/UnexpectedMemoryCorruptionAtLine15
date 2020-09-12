-------------------------
---- Debug constants ----
-------------------------

local DBG_ALL_BITS_ALLOWED = false

--- TODO set to `false` before deploying
local DBG_SUDO_KEYS_ENABLED = true

-------------------
---- Constants ----
-------------------

-- TIC-80's screen width, in pixels
local SCR_WIDTH = 240

-- TIC-80's screen height, in pixels
local SCR_HEIGHT = 136

-- TIC-80 default font's char width, in pixels
local CHR_WIDTH = 6

-- TIC-80 default font's char height, in pixels
local CHR_HEIGHT = 6

-- Width of a single tile
local TILE_SIZE = 8

local BITS = {
  COLLISION = 0,
  GRAVITY = 1,
  SHIFT_POS_X = 2,
  SHIFT_POS_Y = 3,
  SLOW_MOTION = 4,
  FLAG_CONTROL = 5,
  BORDER_PORTALS = 6,
  DISENGAGE_MALEVOLENT_ORGANISM = 7,
}

local TRACKS = {
  VICTORY = 0,
}

local SFX = {
  JUMP = 3,
}

-- First 3 tracks for music, last channel for sfx
local SFX_CHANNEL = 3

-- Level where the player gets spawned; useful for debugging purposes
-- TODO set it to `2` before deploying
local FIRST_LEVEL = 2

--------------------
---- GAME STATE ----
--------------------

-- Ticks since the game started
local TICKS = 0

-- Determines how long (in seconds) the player can hold the
-- jump button, to have reduced gravity
local MAX_GRAVITY_REDUCT_TIME = 0.2

local PHYSICS = {
  GRAVITY_FORCE = 520,
  REDUCED_GRAVITY = 170,
  REVERSED_GRAVITY_FORCE = -10,
  PLAYER_ACCELERATION = 200,
  PLAYER_DECCELERATION = 600,
  PLAYER_JUMP_FORCE = 120
}

local RESPAWN_COOLDOWN_TICK_COUNTER = 0
local RESPAWN_COOLDOWN_TICKS = 60 * 4

--------------
---- Math ----
--------------

function math.clamp(value, min, max)
  if value < min then
    return min
  elseif value > max then
    return max
  else
    return value
  end
end

-------------
---- Vec ----
-------------

Vec = {}

function Vec.new(x, y)
  return setmetatable({
    x = x,
    y = y,
  }, { __index = Vec })
end

function Vec.one()
  return Vec.new(1, 1)
end

function Vec.zero()
  return Vec.new(0, 0)
end

function Vec.up()
  return Vec.new(0, -1)
end

function Vec.down()
  return Vec.new(0, 1)
end

function Vec.right()
  return Vec.new(1, 0)
end

function Vec.left()
  return Vec.new(-1, 0)
end

function Vec.add(self, other)
  return Vec.new(self.x + other.x, self.y + other.y)
end

function Vec.sub(self, other)
  return Vec.new(self.x - other.x, self.y - other.y)
end

function Vec.mul(self, factor)
  return Vec.new(self.x * factor, self.y * factor)
end

function Vec.floor(self)
  return Vec.new(math.floor(self.x), math.floor(self.y))
end

function Vec.x_vec(self)
  return Vec.new(self.x, 0)
end

function Vec.y_vec(self)
  return Vec.new(0, self.y)
end

function Vec.len(self)
  return math.sqrt(math.pow(self.x, 2) + math.pow(self.y, 2))
end

function Vec.distance_to(self, other)
  return other:sub(self):len()
end

function Vec.normalized(self)
  local len = self:len()
  return Vec.new(self.x / len, self.y / len)
end

function Vec.trace(self, name)
  if name then
    name = name .. " = "
  else
    name = ""
  end

  trace(name .. "{ x = " .. self.x .. ", y = " .. self.y .. " }")
end

-------------------
---- Iterators ----
-------------------

function iter(items)
  local i = 1

  return function()
    local ret = items[i]
    i = i + 1
    return ret
  end
end

function filter(items, predicate)
  return function()
    while true do
      local item = items()

      if item == nil then
        return nil
      else
        if predicate(item) then
          return item
        end
      end
    end
  end
end

----------------------
---- Control Word ----
----------------------

CW = {
  reg = 0,

  observers = {
    function(bit_idx)
      if bit_idx == BITS.COLLISION then
        PLAYER.is_on_ground = false
      elseif bit_idx == BITS.FLAG_CONTROL then
        PLAYER.pos, FLAG.pos = FLAG.pos, PLAYER.pos
        PLAYER.vel = PLAYER.vel:mul(1.5)
      elseif bit_idx == BITS.DISENGAGE_MALEVOLENT_ORGANISM then
        disengage_malevolent_organism()
      end
    end
  }
}

function CW.restart()
  CW.reg = 0
  CW.toggle(BITS.GRAVITY)
  CW.toggle(BITS.COLLISION)
  UI.VARS.SEL_CWORD_BIT = 0
end

function CW.is_set(bit_idx)
  return CW.reg & (1 << bit_idx) > 0
end

function CW.toggle(bit_idx)
  for _, observer in ipairs(CW.observers) do
    observer(bit_idx)
  end

  CW.reg = CW.reg ~ (1 << bit_idx)
end


--------------------
---- Corruption ----
--------------------

CORRUPTION = 0.0
CORRUPTION_DECAY_RATE = 1 / 120 -- will go from 1.0 to 0 in roughly 2 minutes
CORRUPTION_INCREMENT = 0.02

function increment_corruption()
  CORRUPTION = math.clamp(CORRUPTION + CORRUPTION_INCREMENT, 0, 1.0)
end

function update_corruption(delta)
  CORRUPTION = math.clamp(CORRUPTION - (delta * CORRUPTION_DECAY_RATE), 0, 1.0)
end

function calc_corruption()
  return CORRUPTION
end

function render_corruption()
  local corruption = calc_corruption()

  if corruption > 0.5 then
    local CHUNK_SIZE = 96
    for x=0,SCR_WIDTH,CHUNK_SIZE do
      for y=0,SCR_HEIGHT,CHUNK_SIZE do
        if math.random() < 0.01 then
          local color_offset = math.random(1, 5)
          for xx=0,CHUNK_SIZE do
            for yy=0,CHUNK_SIZE do
              local c = pix(x+xx, y+yy)
              c = (c + color_offset) % 15
              pix(x+xx, y+yy, c)
            end
          end
        end
      end
    end
  end

  if corruption > 0.7 then
    local CAGE_CORRUPTION = 0.005
    if math.random() < CAGE_CORRUPTION then
      EFFECTS:add(Cage:nicolas())
    end
  end

  if corruption > 0.8 then
    if math.random() < 0.002 then
      local color_shift = math.random(1, 16)
      for n=0,15 do
        local offset = n * 3
        -- I'm not actually sure, if these are actually RGB in that order, but that doesn't matter
        local r = peek(0x3fC0 + offset)
        local g = peek(0x3fC0 + 8 + offset)
        local b = peek(0x3fC0 + 16 + offset)
        poke(0x3fC0 + offset, (r + color_shift) % 255)
        poke(0x3fC0 + 8 + offset, (g + color_shift) % 255)
        poke(0x3fC0 + 16 + offset, (b + color_shift) % 255)
      end
    end
  end
end

function frame_random()
  if not CURRENT_T or CURRENT_T ~= T then
    CURRENT_T = T
    CURRENT_RAND = math.random()
  end

  return CURRENT_RAND
end

function render_corruption_scn(line)
  local corruption = calc_corruption()
  poke(0x3FF9, 0)
  poke(0x3FFA, 0)

  if corruption > 0.3 then
    if line > 0 and line < 60 and frame_random() < 0.025 then
      poke(0x3FFA, 15)
    end
  end

  if corruption > 0.7 then
    if math.random() < 0.01 then
      poke(0x3FFA, math.random(-8, 8))
    end
  end
end

-------------
---- HUD ----
-------------

HUD_HEIGHT = 24

function hud_render()
  local hud_y = SCR_HEIGHT - HUD_HEIGHT

  function render_background()
    rect(0, hud_y, SCR_WIDTH, HUD_HEIGHT, 15)
  end

  function render_control_word_register()
    -- Size of the blank space between control word groups
    local blank_space_width = 40

    local bit_x = (SCR_WIDTH - 8 * 2 * CHR_WIDTH - blank_space_width) / 2
    local bit_y = hud_y + (HUD_HEIGHT - CHR_HEIGHT) / 2 - 3

    for bit_idx = 0,7 do
      if bit_idx == 4 then
        bit_x = bit_x + blank_space_width
      end

      local bit = CW.is_set(bit_idx) and 1 or 0
      local bit_color

      if bit == 1 then
        bit_color = 5
      else
        bit_color = 13
      end

      if bit_idx >= LEVELS.allowed_cw_bits() then
        bit_color = 14
      end

      local bit_dy = 0

      if btn(BUTTONS.PREVIEW_BITS) then
        local bit_sprite = 289 + bit_idx

        if bit_idx >= LEVELS.allowed_cw_bits() then
          bit_sprite = 288
        end

        spr(
          bit_sprite,
          bit_x + 1,
          bit_y + 1,
          0
        )
      else
        if LEVELS.allowed_cw_bits() > 0 then
          if bit_idx == UI.VARS.SEL_CWORD_BIT then
            bit_dy = -2

            -- The character for `1` is somewhat visibly shorter, so our underline
            -- has to account for that
            if bit == 1 then
              rect(bit_x + 1, bit_y + 12, 10, 1, 4)
            else
              rect(bit_x - 1, bit_y + 12, 12, 1, 4)
            end
          end
        end

        print(bit, bit_x, bit_y + bit_dy, bit_color, true, 2)
      end

      bit_x = bit_x + 2 * CHR_WIDTH
    end
  end

  function render_restart()
    local color_a = 12
    local color_b = 14

    if TICKS % 60 > 30 then
      color_a, color_b = color_b, color_a
    end

    UiLabel
      :new()
      :with_xy(0, hud_y + 4)
      :with_wh(SCR_WIDTH, SCR_HEIGHT)
      :with_text("You are dead")
      :with_color(color_a)
      :with_centered()
      :render()

    UiLabel
      :new()
      :with_xy(0, hud_y + 14)
      :with_wh(SCR_WIDTH, SCR_HEIGHT)
      :with_text("Press any key to start over")
      :with_color(color_b)
      :with_centered()
      :render()
  end

  render_background()

  if PLAYER.is_dead then
    if is_respawn_allowed() then
      render_restart()
    end
  else
    render_control_word_register()
  end
end

-----------------
---- Enemies ----
-----------------

SPIDER_ENEMY_DIMENSION = Vec.new(2 * TILE_SIZE, 1 * TILE_SIZE)
LOST_SOUL_ENEMY_DIMENSION = Vec.new(2 * TILE_SIZE, 2 * TILE_SIZE)

Enemies = {}

function Enemies:new()
  return setmetatable({
    -- Currently alive enemies
    active_enemies = {},
  }, { __index = Enemies })
end

function Enemies:clear()
  self.active_enemies = {}
end

function Enemies:add(enemy)
  table.insert(self.active_enemies, enemy)
end

function Enemies:add_many(enemies)
  for _, enemy in ipairs(enemies) do
    self:add(enemy)
  end
end

function Enemies:update(delta)
  for _, enemy in ipairs(self.active_enemies) do
    if not enemy.paused then
      if enemy.update then
        enemy:update(delta)
      end
    end

    -- Check collision with player
    if enemy.collision_radius then
      local level_offset = LEVELS.shift_offset_pixels()
      local distance = PLAYER.pos:distance_to(enemy:pos():sub(level_offset))

      if distance < enemy:collision_radius() then
        if not PLAYER.is_dead then
          PLAYER:kill()
        end
      end
    end
  end
end

function Enemies:render()
  for _, enemy in ipairs(self.active_enemies) do
    if enemy.render then
      enemy:render()
    end
  end
end

function disengage_malevolent_organism()
  if #ENEMIES.active_enemies == 0 then
    return
  end

  -- Pick one
  enemy_idx = math.random(1, #ENEMIES.active_enemies)

  -- Change activity
  for i, v in ipairs(ENEMIES.active_enemies) do
    if i == enemy_idx then
      v.paused = true
    else
      v.paused = false
    end
  end
end

ENEMIES = Enemies:new()

-----------------------------
---- Enemies / Lost Soul ----
-----------------------------

LOST_SOUL_ENEMY = {
  SPRITES = {
    BY_STATE = {
      [1] = 224,
    },
  },

  STATES = {
    FLYING = 1,
  },
}

LostSoulEnemy = {}

function LostSoulEnemy:new(props)
  return setmetatable({
    pos_start = props.pos_start,
    pos_end = props.pos_end,
    cycle_length = props.cycle_length, -- how long it takes to get from start to end in seconds
    cycle_val = 0.0, -- between 0 and 1, incremented by delta/cycle_length
    on_cycle = true
  }, { __index = LostSoulEnemy })
end

function LostSoulEnemy:update(delta)
  if TICKS % math.random(15, 45) == 0 then
    local pos = self:pos()
      :sub(LEVELS.shift_offset_pixels())
      :add(Vec.one():mul(TILE_SIZE))
      :add(Vec.new(math.random(-10, 10), math.random(-10, 10)))

    EFFECTS:add(Poof:small(pos))
  end

  local increment = delta / self.cycle_length
  if not self.on_cycle then
    increment = -increment
  end

  self.cycle_val = math.clamp(self.cycle_val + increment, 0, 1)

  if self.cycle_val == 0 then
    self.on_cycle = true
  elseif self.cycle_val == 1 then
    self.on_cycle = false
  end
end

function LostSoulEnemy:width()
  return LOST_SOUL_ENEMY_DIMENSION.x
end

function LostSoulEnemy:height()
  return LOST_SOUL_ENEMY_DIMENSION.y
end

function LostSoulEnemy:render()
  local offset = LEVELS.shift_offset_pixels()
  local pos = self:pos():sub(offset)

  spr(
    LOST_SOUL_ENEMY.SPRITES.BY_STATE[LOST_SOUL_ENEMY.STATES.FLYING],
    pos.x,
    pos.y,
    0,
    1,
    0,
    0,
    2,
    2
  )
end

function LostSoulEnemy:pos()
  function smoothstep(x)
    x = math.clamp(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)
  end

  local cycle_pos = smoothstep(self.cycle_val)

  local to_end = self.pos_end:sub(self.pos_start)
  return self.pos_start:add(to_end:mul(cycle_pos))
end

function LostSoulEnemy:collision_radius()
  return 12
end

--------------------------
---- Enemies / Spider ----
--------------------------

SPIDER_ENEMY = {
  SPRITES = {
    DEFAULT = 242,
  },

  STATES = {
    LOWERING = 1,
    CRAWLING = 2,
  },
}

SpiderEnemy = {}

function SpiderEnemy:new(props)
  return setmetatable({
    position = props.pos,
    len = props.len or 1,
    max_len = props.max_len or 6,
    left_sign = props.left_sign,
    right_sign = props.right_sign,
    state = SPIDER_ENEMY.STATES.LOWERING,
  }, { __index = SpiderEnemy })
end

function SpiderEnemy:update()
  if self.state == SPIDER_ENEMY.STATES.LOWERING then
    if TICKS % 5 == 0 then
      self.len = self.len + 1
    end

    if self.len >= self.max_len then
      self.state = SPIDER_ENEMY.STATES.CRAWLING
    end
  elseif self.state == SPIDER_ENEMY.STATES.CRAWLING then
    if TICKS % 10 == 0 then
      self.len = self.len - 1
    end

    if self.len <= 0 then
      self.state = SPIDER_ENEMY.STATES.LOWERING
    end
  end
end

function SpiderEnemy:width()
  return SPIDER_ENEMY_DIMENSION.x
end

function SpiderEnemy:height()
  return SPIDER_ENEMY_DIMENSION.y
end

function SpiderEnemy:render()
  local offset = LEVELS.shift_offset_pixels()
  local pos = self.position:sub(offset)

  line(
    pos.x + TILE_SIZE,
    pos.y,
    pos.x + TILE_SIZE,
    pos.y + self.len + 2,
    12
  )

  spr(
    SPIDER_ENEMY.SPRITES.DEFAULT,
    pos.x,
    pos.y + self.len,
    0,
    1,
    0,
    0,
    2,
    1
  )

  if self.left_sign then
    spr(
      self.left_sign,
      pos.x,
      pos.y + self.len + TILE_SIZE
    )
  end

  if self.right_sign then
    spr(
      self.right_sign,
      pos.x + TILE_SIZE,
      pos.y + self.len + TILE_SIZE
    )
  end
end

function SpiderEnemy:collision_radius()
  return 10
end

function SpiderEnemy:pos()
  return self.position
end

-----------------
---- Sprites ----
-----------------

SPRITES = {
  PLAYER = {
    IDLE_1 = 2,
    IDLE_2 = 4,
    RUN_1 = 6,
    RUN_2 = 8,
    IN_AIR = 10,
    PAUSED = 12,
    DEAD = 14,
    OVERFLOW_ARROW_1 = 272,
    OVERFLOW_ARROW_2 = 273,
  },

  POOF = {
    65,
    51,
    50,
    49
  },

  CAGE = {
    172
  }
}

------------------------
---- Visual Effects ----
------------------------

Effects = {}

function Effects:new()
  return setmetatable({
    -- Currently active effects
    active_effects = {},
  }, { __index = Effects })
end

function Effects:clear()
  self.active_effects = {}
end

function Effects:add(effect)
  table.insert(self.active_effects, effect)
end

function Effects:update(delta)
  local removed_effects = 0

  for i, effect in ipairs(self.active_effects) do
    if effect:update(delta) then
      table.remove(self.active_effects, i - removed_effects)
      removed_effects = removed_effects + 1
    end
  end
end

function Effects:render()
  for _, effect in ipairs(self.active_effects) do
    effect:render()
  end
end

EFFECTS = Effects:new()

--------------------------------
---- Visual Effects / Utils ----
--------------------------------

function polar_to_cartesian(r, theta)
  return Vec.new(r * math.cos(theta), r * math.sin(theta))
end

-------------------------------
---- Visual Effects / Cage ----
-------------------------------
local CAGE_SPRITE = 172
local CAGE_TILE_WIDTH = 4
local CAGE_TILE_HEIGHT = 6

Cage = {}

function Cage:nicolas(pos)
  return setmetatable({
    pos = Vec.new(
      math.random(0, SCR_WIDTH - TILE_SIZE * (CAGE_TILE_WIDTH + 2)),
      math.random(0, SCR_HEIGHT - TILE_SIZE * (CAGE_TILE_HEIGHT +3))),
    flip = math.random(0 ,1),
    scale = math.random() * 3.0 + 0.5,
    sprites = SPRITES.CAGE,
    timer = 0,
  }, { __index = Cage })
end

function Cage:render(pos)
  spr(
    CAGE_SPRITE,
    self.pos.x,
    self.pos.y,
    -1,
    self.scale,
    self.flip,
    0,
    CAGE_TILE_WIDTH,
    CAGE_TILE_HEIGHT
  )
end

function Cage:update(delta)
  self.timer = self.timer + delta
  if self.timer > 1 then
    return true
  end
  return false
end

-------------------------------
---- Visual Effects / Poof ----
-------------------------------

Poof = {}

function Poof:regular(pos)
  return setmetatable({
    pos = pos,
    sprites = SPRITES.POOF,
    current_sprite = 1,
    timer = 0,
    max_life = 1.0,
    time_2_radius = 250,
    num_of_arms = 8,
    angle = math.pi / 4
  }, { __index = Poof })
end

function Poof:small(pos)
  return setmetatable({
    pos = pos,
    sprites = SPRITES.POOF,
    current_sprite = 1,
    timer = 0,
    max_life = 0.3,
    time_2_radius = 40,
    num_of_arms = 6,
    angle = 45
  }, { __index = Poof })
end

function Poof:update(delta)
  self.timer = self.timer + delta
  local time_boundary = self.max_life / #self.sprites

  if self.timer < time_boundary then
    self.current_sprite = 2
  elseif self.timer < 2 * time_boundary then
    self.current_sprite = 3
  elseif self.timer < 3 * time_boundary then
    self.current_sprite = 4
  else
    self.current_sprite = 0
    return true
  end

  return false
end

function spr_center(spr_idx, x, y, w, h, color_key)
  spr(spr_idx, x - (w / 2), y - (h / 2), color_key)
end

function Poof:render()
  local current_sprite = self.sprites[self.current_sprite]
  local arm_angle = math.pi * 2 / self.num_of_arms

  for poof=0,self.num_of_arms do
    local poof_pos = self.pos:add(polar_to_cartesian(self.timer * self.time_2_radius, self.angle + arm_angle * poof))

    spr_center(
      current_sprite,
      poof_pos.x,
      poof_pos.y,
      TILE_SIZE,
      TILE_SIZE,
      0
    )
  end
end

--------------
---- Flag ----
--------------

FLAG_DATA = {
  SPRITES = {
    STAND = {
      TOP = 274,
      BOTTOM = 275,
    },

    CLOTH = {
      [0] = 276,
      [1] = 277,
      [2] = 278,
      [3] = 279,
      [4] = 280,
      [5] = 281,
    },
  },
}

Flag = {}

function Flag:new()
  return setmetatable({
    pos = nil,
    cloth = {
      state_idx = 0,
    },
  }, { __index = Flag })
end

function Flag:restart(pos)
  self.pos = pos
end

function Flag:update()
  if self.pos == nil then
    return
  end

  if TICKS % 7 == 0 then
    self.cloth.state_idx = (self.cloth.state_idx + 1) % (#FLAG_DATA.SPRITES.CLOTH + 1)
  end
end

function Flag:sprite()
  local offset = LEVELS.shift_offset_pixels()
  local pos = self.pos:sub(offset)
  local flip = 0

  return {
    pos = pos,
    flip = flip,
  }
end

function Flag:render()
  if self.pos == nil then
    return
  end

  local sprite = self:sprite()

  if CW.is_set(BITS.FLAG_CONTROL) then
    local player_sprite = PLAYER:sprite()

    sprite.pos = player_sprite.pos
    sprite.flip = player_sprite.flip
  end

  spr(
    FLAG_DATA.SPRITES.STAND.TOP,
    sprite.pos.x + TILE_SIZE,
    sprite.pos.y,
    0
  )

  spr(
    FLAG_DATA.SPRITES.STAND.BOTTOM,
    sprite.pos.x + TILE_SIZE,
    sprite.pos.y + TILE_SIZE,
    0
  )

  if sprite.flip == 1 then
    spr(
      FLAG_DATA.SPRITES.CLOTH[self.cloth.state_idx],
      sprite.pos.x + TILE_SIZE + 2,
      sprite.pos.y,
      0,
      1,
      1
    )
  else
    spr(
      FLAG_DATA.SPRITES.CLOTH[self.cloth.state_idx],
      sprite.pos.x,
      sprite.pos.y,
      0
    )
  end
end

FLAG = Flag:new()

----------------
---- Player ----
----------------

PLAYER_DIMENSION = Vec.new(2 * TILE_SIZE, 2 * TILE_SIZE)

PLAYER_RUNNING_ANIMATION = {
  switch_every = 0.2, -- seconds
  timer = 0,
  last_change_at = 0,
  current = 1,
  frames = { SPRITES.PLAYER.RUN_1, SPRITES.PLAYER.RUN_2 }
}

PLAYER_IDLING_ANIMATION = {
  switch_every = 0.75, -- seconds
  last_change_at = 0,
  current = 1,
  frames = { SPRITES.PLAYER.IDLE_1, SPRITES.PLAYER.IDLE_2 }
}

Player = {}

function Player:new()
  return setmetatable({
    pos = Vec.new(0, 0),
    vel = Vec.new(0, 0),
    acc = Vec.new(0, 0),
    speed = 100,
    collider = {
      offset = Vec.new(2, 3),
      size = Vec.new(11, 13)
    },
    inverse_air_time = MAX_GRAVITY_REDUCT_TIME,
    is_on_ground = false,
    is_dead = false,
  }, { __index = Player })
end

function Player:restart(spawn_location)
  self.pos = spawn_location
  self.vel = Vec.new(0, 0)
  self.acc = Vec.new(0, 0)
  self.is_on_ground = false
  self.is_dead = false
end

function Player:collider_bottom_center()
  return self:collider_bottom_left()
    :add(Vec.right():mul(self.collider.size.x / 2))
end

function Player:collider_center()
  return self.pos
    :add(self.collider.offset)
    :add(self.collider.size:mul(0.5))
end

function Player:collider_bottom_right()
  return self.pos
    :add(self.collider.offset)
    :add(self.collider.size)
end

function Player:collider_bottom_left()
  return self.pos
    :add(self.collider.offset)
    :add(Vec.down():mul(self.collider.size.y))
end

function Player:collider_top_right()
  return self.pos
    :add(self.collider.offset)
    :add(Vec.right():mul(self.collider.size.x))
end

function Player:collider_top_left()
  return self.pos
    :add(self.collider.offset)
    :add(Vec.right():mul(self.collider.size.x))
end

function Player:kill()
  self.is_dead = true

  AUDIO.play_note(1, "C#3", 64, 10)
  EFFECTS:add(Poof:regular(self:collider_center()))

  RESPAWN_COOLDOWN_TICK_COUNTER = 0
end

function Player:width()
  return PLAYER_DIMENSION.x
end

function Player:height()
  return PLAYER_DIMENSION.y
end

function Player:update(delta)
  self:update_physics(delta)

  local offset = LEVELS.shift_offset_pixels():mul(-1)
  local pos = self:collider_center()

  if self.is_dead then
    -- Simulate tombstone's friction
    if self.vel.y > 0 and math.abs(self.vel.y) < 5 then
      self.vel.y = self.vel.y * 2
    end

    self.vel.x = self.vel.x / 1.045

    -- Intentional fall-through: even if player's dead, let them win using
    -- tombstone drifting (i.e. tombstone touching the flag)
  end

  -- Check if player touches the flag
  local flag_pos = FLAG.pos:add(offset)

  local touches_flag =
        pos.x >= flag_pos.x - 0.5 * TILE_SIZE
    and pos.y >= flag_pos.y - 0.0 * TILE_SIZE
    and pos.x <= flag_pos.x + 2.0 * TILE_SIZE
    and pos.y <= flag_pos.y + 3.0 * TILE_SIZE

  if touches_flag then
    if not UI.TRANSITION then
      music(TRACKS.VICTORY, -1, -1, false)

      UI.enter(function ()
        LEVELS.start_next()
      end)
    end
  end

  if not self.is_dead then
    local touched_tile = self
      :collider_center()
      :mul(1 / TILE_SIZE)
      :floor()

    -- Check if player touches spikes
    if fget(game_mget(touched_tile), FLAGS.IS_HURT) then
      self:kill()
    end

    -- Check if player is inside a wall
    if CW.is_set(BITS.COLLISION) and fget(game_mget(touched_tile), FLAGS.IS_GROUND) then
      self:kill()
    end

    -- Check if player is outside the map
    if CW.is_set(BITS.BORDER_PORTALS) then
      if self.pos.y >= SCR_HEIGHT then
        self.pos.y = 0 + 1
      elseif self.pos.y <= -(TILE_SIZE * 2) then
        self.pos.y = SCR_HEIGHT - TILE_SIZE * 2 - 1
      elseif self.pos.x <= 0 - TILE_SIZE then
        self.pos.x = SCR_WIDTH - TILE_SIZE
      elseif self.pos.x > SCR_WIDTH - TILE_SIZE then
        self.pos.x = 0 - TILE_SIZE
      end
    else
      -- We're allowing player to go _just slightly_ outside the map to account
      -- for "creative solutions" like jumping outside-and-back-inside the map
      local allowed_offset = 50

      local within_map =
      self.pos.x >= -allowed_offset
        and self.pos.y >= -allowed_offset
        and self.pos.x < SCR_WIDTH + allowed_offset
        and self.pos.y < SCR_HEIGHT + allowed_offset

      if not within_map then
        self:kill()
      end
    end
  end

  -- Update animations
  if math.abs(self.vel.x) > 1 then
    PLAYER_RUNNING_ANIMATION.timer = PLAYER_RUNNING_ANIMATION.timer + (0.05 * delta * math.abs(self.vel.x))

    if PLAYER_RUNNING_ANIMATION.timer - PLAYER_RUNNING_ANIMATION.last_change_at > PLAYER_RUNNING_ANIMATION.switch_every then
      PLAYER_RUNNING_ANIMATION.current = 1 + ((PLAYER_RUNNING_ANIMATION.current + 2) % #PLAYER_RUNNING_ANIMATION.frames)
      PLAYER_RUNNING_ANIMATION.last_change_at = PLAYER_RUNNING_ANIMATION.timer
    end
  else
    if T - PLAYER_IDLING_ANIMATION.last_change_at > PLAYER_IDLING_ANIMATION.switch_every then
      PLAYER_IDLING_ANIMATION.current = 1 + ((PLAYER_IDLING_ANIMATION.current + 2) % #PLAYER_IDLING_ANIMATION.frames)
      PLAYER_IDLING_ANIMATION.last_change_at = T
    end
  end
end

function Player:update_physics(delta)
  -- Apply gravity
  if CW.is_set(BITS.GRAVITY) then
    if not self.is_on_ground then
      if btn(BUTTONS.UP) and self.inverse_air_time > 0 then
        self.vel.y = self.vel.y + PHYSICS.REDUCED_GRAVITY * delta
      else
        self.vel.y = self.vel.y + PHYSICS.GRAVITY_FORCE * delta
      end

      self.inverse_air_time = self.inverse_air_time - delta
    else
      self.inverse_air_time = MAX_GRAVITY_REDUCT_TIME
    end
  else
    self.vel.y = self.vel.y + PHYSICS.REVERSED_GRAVITY_FORCE * delta
  end

  local is_colliding_horizontally = false

  if CW.is_set(BITS.COLLISION) then
    is_colliding_horizontally = collisions_update()
  end

  if not self.is_dead then
    local steering_factor

    if self.is_on_ground then
      steering_factor = 1.0
    else
      if CW.is_set(BITS.GRAVITY) then
        steering_factor = 0.6
      else
        steering_factor = 0.1
      end
    end

    if btn(BUTTONS.RIGHT) then
      self.vel.x = math.clamp(self.vel.x + PHYSICS.PLAYER_ACCELERATION * delta * steering_factor, -self.speed, self.speed)
      self.acc.x = 1
    elseif btn(BUTTONS.LEFT) then
      self.vel.x = math.clamp(self.vel.x - PHYSICS.PLAYER_ACCELERATION * delta * steering_factor, -self.speed, self.speed)
      self.acc.x = -1
    else
      if self.is_on_ground then
        if math.abs(self.vel.x) > 1 then
          local sign = self.vel.x / math.abs(self.vel.x)
          self.vel.x = self.vel.x - PHYSICS.PLAYER_DECCELERATION * sign * delta

          -- at 10 pixels/s reduce to 0
          if math.abs(self.vel.x) < 10 then
            self.vel.x = 0
          end
        end
      end
    end

    -- jump
    if self.is_on_ground and btnp(BUTTONS.UP) then
      self.vel = self.vel:add(Vec:up():mul(PHYSICS.PLAYER_JUMP_FORCE))
      self.is_on_ground = false

      AUDIO.play_note(SFX.JUMP, "C#5", 16, 10)
      EFFECTS:add(Poof:small(self:collider_bottom_center()))
    end
  end

  if math.abs(self.vel.x) > 0 and is_colliding_horizontally then
    self.vel.x = 0
  end

  if self.vel.y > 0 and self.is_on_ground then
    self.vel.y = 0
  end

  self.pos = self.pos:add(self.vel:mul(delta))
end

function Player:sprite()
  local id = SPRITES.PLAYER.IDLE_1
  local pos = self.pos
  local flip = 0

  if self.is_dead then
    id = SPRITES.PLAYER.DEAD
  else
    if self.acc.x < 0 then
      flip = 1
    end

    if not self.is_on_ground then
      id = SPRITES.PLAYER.IN_AIR
    elseif math.abs(self.vel.x) > 1 then
      id = PLAYER_RUNNING_ANIMATION.frames[PLAYER_RUNNING_ANIMATION.current]
    else
      id = PLAYER_IDLING_ANIMATION.frames[PLAYER_IDLING_ANIMATION.current]
    end
  end

  return {
    id = id,
    pos = pos,
    flip = flip,
  }
end

function Player:render()
  local sprite = self:sprite()

  if CW.is_set(BITS.FLAG_CONTROL) then
    local offset = LEVELS.shift_offset_pixels()

    sprite.id = SPRITES.PLAYER.PAUSED
    sprite.pos = FLAG.pos:sub(offset)
    sprite.flip = 0
  end

  spr(
    sprite.id,
    sprite.pos.x,
    sprite.pos.y,
    0,
    1,
    sprite.flip,
    0,
    2,
    2
  )

  -- When player's outside the map, render an array indicating player's
  -- position for user
  if not CW.is_set(BITS.BORDER_PORTALS) and TICKS % 20 > 10 then
    local min_x = -TILE_SIZE
    local min_y = -TILE_SIZE
    local max_x = SCR_WIDTH - 2 * TILE_SIZE
    local max_y = SCR_HEIGHT - HUD_HEIGHT - 2 * TILE_SIZE

    local overflows_top = self.pos.y < min_y
    local overflows_right = self.pos.x > max_x
    local overflows_bottom = self.pos.y > max_y
    local overflows_left = self.pos.x < min_x

    if overflows_top or overflows_right or overflows_bottom or overflows_left then
      local dir

      if overflows_top then
        if overflows_right then
          dir = 2
        elseif overflows_left then
          dir = 7
        else
          dir = 0
        end
      elseif overflows_bottom then
        if overflows_right then
          dir = 3
        elseif overflows_left then
          dir = 5
        else
          dir = 4
        end
      else
        if overflows_right then
          dir = 2
        else
          dir = 6
        end
      end

      local arrow_id
      local arrow_rotate

      if dir % 2 == 0 then
        arrow_id = SPRITES.PLAYER.OVERFLOW_ARROW_1
        arrow_rotate = math.ceil(dir / 2)
      else
        arrow_id = SPRITES.PLAYER.OVERFLOW_ARROW_2
        arrow_rotate = math.ceil((dir - 1) / 2)
      end

      local arrow_x = math.clamp(self.pos.x, min_x, max_x) + TILE_SIZE
      local arrow_y = math.clamp(self.pos.y, min_y, max_y) + TILE_SIZE

      spr(
        arrow_id,
        arrow_x,
        arrow_y,
        0,
        1,
        0,
        arrow_rotate
      )
    end
  end
end

PLAYER = Player:new()

----------------
---- Levels ----
----------------

LEVEL = 1

LEVELS = {
  -- Test, debug level
  {
    map_offset = Vec.new(210, 119),
    spawn_location = Vec.new(1 * TILE_SIZE, 11 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 8,
  },

  -- No bits, only small platforms
  {
    map_offset = Vec.new(0, 0),
    spawn_location = Vec.new(4 * TILE_SIZE, 4 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 0,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(2 * TILE_SIZE, TILE_SIZE),
          max_len = 16,
          left_sign = 258,
          right_sign = 256,
        }),
      }
    end,
  },

  -- first bit only, player has to jump down to reach the flag
  -- teaches:
  -- 1. Spikes kill
  -- 2. Can jump down
  {
    map_offset = Vec.new(0, 34),
    spawn_location = Vec.new(1 * TILE_SIZE, 1 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 1,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(26 * TILE_SIZE, TILE_SIZE),
          max_len = 16,
          left_sign = 261,
          right_sign = 262,
        }),
      }
    end
  },

  -- First 2 bits only
  -- Spikes along the floor, cannot jump over it
  -- has to use null gravity to go over it
  {
    map_offset = Vec.new(30, 0),
    spawn_location = Vec.new(26 * TILE_SIZE, 4 * TILE_SIZE),
    flag_location = Vec.new(2 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 2,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(2 * TILE_SIZE, TILE_SIZE),
          max_len = 16,
          left_sign = 260,
          right_sign = 261,
        }),
      }
    end
  },

  -- First mushroom level
  -- player can jump over the mushroom, leaving the map
  -- or use the shift level bit, to teleport to the over side
  {
    map_offset = Vec.new(60, 0),
    spawn_location = Vec.new(1 * TILE_SIZE, 1 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 3,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(25 * TILE_SIZE, -8, 1 * TILE_SIZE),
          max_len = 16,
          left_sign = 259,
          right_sign = 261,
        }),
      }
    end
  },

  -- Death maze level
  -- So far 3 ways to win:
  -- 1 - the way it was designed, use the shift bit to teleport a couple times and get to the flag
  -- 2 - float above the level using null gravity and no collision
  -- 3 - shift x, float above the spikes to go left, unshift x, you're near the flag
  {
    map_offset = Vec.new(30, 34),
    spawn_location = Vec.new(136, 8),
    flag_location = Vec.new(1 * TILE_SIZE, 10 * TILE_SIZE),
    allowed_cw_bits = 4,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(2 * TILE_SIZE, TILE_SIZE),
          max_len = 8,
          left_sign = 262,
        }),
      }
    end
  },

  -- Introduction to enemies, enables the slow mo bit
  {
    map_offset = Vec.new(120, 0),
    spawn_location = Vec.new(TILE_SIZE, TILE_SIZE),
    flag_location = Vec.new(28 * TILE_SIZE, 0 * TILE_SIZE),
    allowed_cw_bits = 5,

    build_enemies = function()
      return {
        LostSoulEnemy:new({
          pos_start = Vec.new(12 * TILE_SIZE, 8 * TILE_SIZE),
          pos_end = Vec.new(12 * TILE_SIZE, 10 * TILE_SIZE),
          cycle_length = 1.0,
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(15 * TILE_SIZE, 5 * TILE_SIZE),
          pos_end = Vec.new(20 * TILE_SIZE, 5 * TILE_SIZE),
          cycle_length = 1.0,
        }),
      }
    end
  },

  -- The Second Mushroom level
  -- teaches that the dead player can still win
  -- NOTE: This is very hard for players to figure out
  {
    map_offset = Vec.new(90, 0),
    spawn_location = Vec.new(8, 9 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 2,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(25 * TILE_SIZE, -8, 1 * TILE_SIZE),
          max_len = 16,
          left_sign = nil,
          right_sign = nil,
        }),

        SpiderEnemy:new({
          pos = Vec.new(19 * TILE_SIZE - (TILE_SIZE / 2), 5 * TILE_SIZE, 1 * TILE_SIZE),
          max_len = 32,
          left_sign = nil,
          right_sign = nil,
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(2 * TILE_SIZE, 5 * TILE_SIZE),
          pos_end = Vec.new(4 * TILE_SIZE, 5 * TILE_SIZE),
          cycle_length = 1.0
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(21 * TILE_SIZE, 5 * TILE_SIZE),
          pos_end = Vec.new(21 * TILE_SIZE, 9 * TILE_SIZE),
          cycle_length = 1.0
        }),

        SpiderEnemy:new({
          pos = Vec.new(23 * TILE_SIZE, 10 * TILE_SIZE),
          max_len = 8,
          left_sign = nil,
          right_sign = nil,
        }),
      }
    end
  },

  -- Now You're Thinking With Portals
  -- enables the portal bit
  {
    map_offset = Vec.new(150, 0),
    spawn_location = Vec.new(8, 9 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 8,
  },

  -- Skulls of death, impossibility
  {
    map_offset = Vec.new(180, 0),
    spawn_location = Vec.new(1 * TILE_SIZE, 11 * TILE_SIZE),
    flag_location = Vec.new(7 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 8,

    build_enemies = function()
      local MIN_Y = -6 * TILE_SIZE;
      local MAX_Y = 9 * TILE_SIZE;
      return {
        SpiderEnemy:new({
          pos = Vec.new(9 * TILE_SIZE + (TILE_SIZE >> 1), 9 * TILE_SIZE),
          max_len = 24,
          left_sign = nil,
          right_sign = nil,
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(3 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(3 * TILE_SIZE, MAX_Y),
          cycle_length = 1.0
        }),


        LostSoulEnemy:new({
          pos_start = Vec.new(7 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(7 * TILE_SIZE, MAX_Y),
          cycle_length = 1.0
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(11 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(11 * TILE_SIZE, MAX_Y),
          cycle_length = 1.0
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(15 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(15 * TILE_SIZE, MAX_Y),
          cycle_length = 1.0
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(19 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(19 * TILE_SIZE, MAX_Y),
          cycle_length = 1.0
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(23 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(23 * TILE_SIZE, MAX_Y),
          cycle_length = 1.0
        }),
      }
    end
  },
}

function LEVELS.start(id)
  EFFECTS:clear()
  ENEMIES:clear()

  local level = LEVELS[id]

  if level.build_enemies then
    ENEMIES:add_many(level.build_enemies())
  end

  PLAYER:restart(level.spawn_location)
  FLAG:restart(level.flag_location)
  CW:restart()

  LEVEL = id
end

function LEVELS.restart()
  LEVELS.start(LEVEL)
end

function LEVELS.start_next()
  LEVELS.start(LEVEL + 1)
end

function LEVELS.start_prev()
  LEVELS.start(LEVEL - 1)
end

function LEVELS.map_offset()
  local offset = LEVELS.shift_offset()

  return LEVELS[LEVEL].map_offset:add(offset)
end

function LEVELS.shift_offset()
  local offset = Vec.new(0, 0)

  if CW.is_set(BITS.SHIFT_POS_X) then
    offset = offset:add(Vec.new(15, 0))
  end

  if CW.is_set(BITS.SHIFT_POS_Y) then
    offset = offset:add(Vec.new(0, 8))
  end

  return offset
end

function LEVELS.shift_offset_pixels()
  return LEVELS.shift_offset():mul(TILE_SIZE)
end

function LEVELS.allowed_cw_bits()
  if DBG_ALL_BITS_ALLOWED then
    return 8
  end

  return LEVELS[LEVEL].allowed_cw_bits
end

---------------
---- Game -----
---------------

BUTTONS = {
  UP = 0,
  DOWN = 1,
  LEFT = 2,
  RIGHT = 3,
  PREVIEW_BITS = 5,
}

FLAGS = {
  IS_GROUND = 0,
  IS_HURT = 2,
}

function is_respawn_allowed()
  RESPAWN_COOLDOWN_TICK_COUNTER = RESPAWN_COOLDOWN_TICK_COUNTER + 1
  if RESPAWN_COOLDOWN_TICK_COUNTER >= RESPAWN_COOLDOWN_TICKS then
    return true
  end
  return false
end

function find_tiles_below_collider()
  local below_left = PLAYER:collider_bottom_left()
    :mul(1 / TILE_SIZE)
    :floor()

  local below_center = PLAYER:collider_center()
    :add(Vec.down():mul(PLAYER.collider.size.y / 2))
    :mul(1 / TILE_SIZE)
    :floor()

  local below_right = PLAYER:collider_bottom_right()
    :mul(1 / TILE_SIZE)
    :floor()

  return { below_left, below_center, below_right }
end

function find_tiles_in_front_of_player()
  local forward = PLAYER:collider_center()
    :mul(1 / TILE_SIZE)
    :add(PLAYER.vel:x_vec():normalized())

  return { forward }
end

function find_tiles_above_player()
  local top_left = PLAYER:collider_top_left()
    :mul(1 / TILE_SIZE)
    :floor()

  local top_right = PLAYER:collider_top_right()
    :mul(1 / TILE_SIZE)
    :floor()

  return { top_left, top_right }
end

function game_mget(vec)
  local offset = LEVELS.map_offset()
  local offset_vec = vec:add(offset:mul(1))

  if offset_vec.x < 0 or offset_vec.y < 0 then
    return nil
  else
    return mget(offset_vec.x, offset_vec.y)
  end
end

function collisions_update()
  function is_tile_ground(tile)
    return fget(game_mget(tile), FLAGS.IS_GROUND)
  end

  -- collisions below player
  local tiles_below_player = find_tiles_below_collider()
  local tile_below_player = filter(iter(tiles_below_player), is_tile_ground)()

  if tile_below_player ~= nil then
    if not PLAYER.is_on_ground then
      PLAYER.vel.y = 0
      PLAYER.is_on_ground = true
      PLAYER.pos.y = (tile_below_player.y - 2) * TILE_SIZE
    end
  elseif PLAYER.is_on_ground then
    PLAYER.is_on_ground = false
  end

  -- collisions to the sides
  local tiles_to_the_right_of_player = find_tiles_in_front_of_player()

  local tile_to_the_right_of_player = filter(iter(tiles_to_the_right_of_player), is_tile_ground)()
  local is_colliding_horizontally = tile_to_the_right_of_player ~= nil

  -- collisions above player
  local tiles_above_player = find_tiles_above_player()
  local tile_above_player = filter(iter(tiles_above_player), is_tile_ground)()

  if PLAYER.vel.y < 0 and tile_above_player ~= nil then
    PLAYER.vel.y = 0
  end

  return is_colliding_horizontally
end

function game_update(delta)
  if DBG_SUDO_KEYS_ENABLED then
    -- `[`
    if keyp(39) then
      LEVELS:start_prev()
    end

    -- `]`
    if keyp(40) then
      LEVELS:start_next()
    end
  end

  EFFECTS:update(delta)
  ENEMIES:update(delta)
  FLAG:update()
  PLAYER:update(delta)
  update_corruption(delta)
end

function game_render()
  local offset = LEVELS.map_offset()

  map(offset.x, offset.y)

  EFFECTS:render()
  ENEMIES:render()
  FLAG:render()
  PLAYER:render()
end

------------
---- UI ----
------------

UI = {
  -- Index of currently active UI screen; see `UI.SCREENS`
  SCREEN = 1,

  SCREENS = {
    -- Screen: Introduction
    [1] = {
      update = function(screen)
        -- Avoid bugging game by keeping keys pressed for more than one frame
        if screen.vars.started then
          return
        end

        if any_key() then
          screen.vars.started = true

          AUDIO.play_note(0, "C-4", 8)
          AUDIO.play_note(0, "E-4", 8)
          AUDIO.play_note(0, "G-4", 8)
          AUDIO.play_note(0, "B-4", 8)
          AUDIO.play_note(0, "D-4", 8)
          AUDIO.play_note(0, "G-4", 8)
          AUDIO.play_note(0, "C-5", 8)

          UI.enter(2)
        end
      end,

      render = function()
        UiLabel
          :new()
          :with_xy(0, 8)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_text("UNEXPECTED MEMORY CORRUPTION")
          :with_color(10)
          :with_letter_spacing(2)
          :with_centered()
          :render()

        UiLabel
          :new()
          :with_xy(0, 40)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_line("Use $1, $2 and $0 to move.\n")
          :with_line("Use $3, $4, $5 and $6 to modify control bits and change game's behavior.\n")
          :with_line("Discover what each bit does, find your way to the flag and have fun!")
          :render()

        UiLabel
          :new()
          :with_xy(0, SCR_HEIGHT - 12)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_text("press any key to start")
          :with_color(4)
          :with_centered()
          :with_wavy()
          :render()
      end,

      scanline = function(line)
        poke(0x3FF9, 0)

        if line < 30 then
          if math.random() < 0.1 then
            poke(0x3FF9, math.random(-8, 8))
          end
        end
      end,

      vars = {
        started = false,
      }
    },

    -- Screen: Game
    [2] = {
      update = function()
        if PLAYER.is_dead then
          if is_respawn_allowed() and any_key() then
            LEVELS.restart()
          end

          return
        end

        if btnp(4) then
          if LEVELS.allowed_cw_bits() == 0 then
            AUDIO.play_note(0, "D#5", 4, 12)
          else
            if CW.is_set(UI.VARS.SEL_CWORD_BIT) then
              AUDIO.play_note(0, "D#5", 2, 10)
              AUDIO.play_note(0, "C#5", 2, 10)
            else
              AUDIO.play_note(0, "C#5", 2, 10)
              AUDIO.play_note(0, "D#5", 2, 10)
            end

            increment_corruption()
            CW.toggle(UI.VARS.SEL_CWORD_BIT)
          end
        end

        if btnp(6) then
          if LEVELS.allowed_cw_bits() == 0 then
            AUDIO.play_note(0, "D#5", 4, 12)
          else
            UI.VARS.SEL_CWORD_BIT = (UI.VARS.SEL_CWORD_BIT - 1) % LEVELS.allowed_cw_bits()
          end
        end

        if btnp(7) then
          if LEVELS.allowed_cw_bits() == 0 then
            AUDIO.play_note(0, "D#5", 4, 12)
          else
            UI.VARS.SEL_CWORD_BIT = (UI.VARS.SEL_CWORD_BIT + 1) % LEVELS.allowed_cw_bits()
          end
        end
      end,

      scanline = function(line)
        render_corruption_scn(line)
      end
    },
  },

  -- Function that handles current screen transition, if any
  TRANSITION = nil,

  VARS = {
    -- Index of currently selected control word's bit; 0..4
    SEL_CWORD_BIT = 0,
  }
}

function UI.enter(arg)
  function create_transition(on_screen_blacked_out)
    local completion = 0
    local has_called_callback = false

    return function()
      if completion >= 2.0 then
        return true
      end

      if completion >= 1.0 then
        if not has_called_callback and on_screen_blacked_out then
          on_screen_blacked_out()
          has_called_callback = true
        end
      end

      for x = 0,SCR_WIDTH do
        for y = 0,SCR_HEIGHT do
          if completion <= 1.0 then
            if x < (completion * SCR_WIDTH) then
              pix(x, y, 0)
            end
          else
            if x > ((completion - 1.0) * SCR_WIDTH) then
              pix(x, y, 0)
            end
          end
        end
      end

      completion = completion + 0.04
    end
  end

  if type(arg) == "number" then
    local screen_idx = arg

    UI.TRANSITION = create_transition(function ()
      if screen_idx == 2 then
        LEVELS.start(FIRST_LEVEL)
      end

      UI.SCREEN = screen_idx
    end)
  else
    UI.TRANSITION = create_transition(arg)
  end
end

function UI.update()
  local screen = UI.SCREENS[UI.SCREEN]

  if screen.update then
    screen:update()
  end
end

function UI.render()
  local screen = UI.SCREENS[UI.SCREEN]

  if screen.render then
    screen:render()
  end

  if UI.TRANSITION then
    if UI.TRANSITION() then
      UI.TRANSITION = nil
    end
  end
end

function UI.scanline(line)
  local screen = UI.SCREENS[UI.SCREEN]

  if screen.scanline then
    screen.scanline(line)
  end
end

function any_key()
  for i = 0,31 do
    if btnp(i) then
      return true
    end
  end

  for i = 1,65 do
    if keyp(i) then
      return true
    end
  end

  return false
end

-------------
-- UiLabel --

UiLabel = {}

function UiLabel:new()
  return setmetatable({
    xy = Vec.new(0, 0),
    wh = nil,
    text = "",
    color = 12,
    letter_spacing = 0,
    centered = false,
    wavy = false,
  }, { __index = UiLabel })
end

function UiLabel:with_xy(x, y)
  self.xy = Vec.new(x, y)
  return self
end

function UiLabel:with_wh(w, h)
  self.wh = Vec.new(w, h)
  return self
end

function UiLabel:with_text(text)
  self.text = self.text .. text
  return self
end

function UiLabel:with_line(line)
  return self:with_text(line .. "\n")
end

function UiLabel:with_color(color)
  self.color = color
  return self
end

function UiLabel:with_letter_spacing(letter_spacing)
  self.letter_spacing = letter_spacing
  return self
end

function UiLabel:with_centered()
  self.centered = true
  return self
end

function UiLabel:with_wavy()
  self.wavy = true
  return self
end

function UiLabel:render()
  local bb = self:_bounding_box()

  -- Caret's X position, in pixels
  local cx = bb.tl.x

  -- Caret's Y position, in pixels
  local cy = bb.tl.y

  function inc_cy()
    cy = cy + CHR_HEIGHT + 2
    cx = bb.tl.x
  end

  function inc_cx(delta)
    cx = cx + delta

    if bb.br then
      if cx >= bb.br.x then
        inc_cy()
      end
    end
  end

  local i = 0

  while i < #self.text do
    i = i + 1

    local prev_ch2 = self.text:sub(i - 2, i - 2)
    local prev_ch = self.text:sub(i - 1, i - 1)
    local ch = self.text:sub(i, i)

    -- Adjust to character's kerning
    cx = cx + self._kerning(prev_ch2, prev_ch, ch)

    if ch == '\n' then
      -- Special syntax: \n forces new line
      inc_cy()
    elseif ch == '$' then
      -- Special syntax: $<num> renders sprite with specified id

      -- Skip `$`
      i = i + 1

      -- Read sprite's number
      ch = self.text:sub(i, i)

      -- Render sprite
      spr(256 + tonumber(ch), cx - 3, cy - 1)

      inc_cx(7)
    else
      local dy = 0

      if self.wavy then
        dy = 3 * math.sin(i + time() / 150)
      end

      -- If printing current character would overflow our label's bounding box,
      -- automatically move on to the next line
      if bb.br then
        if cx + CHR_WIDTH >= bb.br.x then
          inc_cy()
        end
      end

      print(ch, cx, cy + dy, self.color, true)

      inc_cx(CHR_WIDTH + self.letter_spacing)
    end
  end
end

--- Returns delta-x that adjusts for given character's kerning
function UiLabel._kerning(prev_ch2, prev_ch, ch)
  -- Upper-cases
  if ch == 'I' or ch == 'T' or ch == 'Y' then
    return -1
  end

  -- Lower-cases
  if prev_ch == 'i' or ch == 'l' then
    return -1
  end

  if ch == 'i' then
    return -2
  end

  -- Miscellaneous
  if prev_ch2 == '$' and ch ~= ',' then
    return -4
  end

  if ch == '!' then
    return -1
  end

  if prev_ch == ',' then
    return -2
  end

  return 0
end

function UiLabel:_bounding_box()
  local bb = {
    -- Label's top-left corner
    tl = self.xy,
  }

  if self.centered then
    local actual_width = 0

    for i = 1, #self.text do
      local prev_ch2 = self.text:sub(i - 2, i - 2)
      local prev_ch = self.text:sub(i - 1, i - 1)
      local ch = self.text:sub(i, i)

      actual_width =
        actual_width
        + CHR_WIDTH
        + self._kerning(prev_ch2, prev_ch, ch)
        + self.letter_spacing
    end

    bb.tl.x = bb.tl.x + (self.wh.x - actual_width) / 2
  end

  -- If label's supposed to be constrained in a box, calculate label's
  -- bottom-right corner too
  if self.wh then
    bb.br = bb.tl:add(self.wh)
  end

  return bb
end

---------------
---- Audio ----
---------------

AUDIO = {
  QUEUED_NOTES = {}
}

function AUDIO.update()
  if #AUDIO.QUEUED_NOTES == 0 then
    return
  end

  local current_note = AUDIO.QUEUED_NOTES[1]
  local next_note = AUDIO.QUEUED_NOTES[2]

  if TICKS >= current_note.started_at + current_note.duration - 1 then
    table.remove(AUDIO.QUEUED_NOTES, 1)

    if next_note then
      next_note.started_at = TICKS

      sfx(
        next_note.sfx,
        next_note.note,
        next_note.duration,
        SFX_CHANNEL,
        next_note.volume
      )
    end
  end
end

function AUDIO.play_note(sfx_id, note, duration, volume)
  local started_at

  volume = volume or 15

  if #AUDIO.QUEUED_NOTES == 0 then
    sfx(sfx_id, note, duration, SFX_CHANNEL, volume)
    started_at = TICKS
  end

  table.insert(AUDIO.QUEUED_NOTES, {
    sfx = sfx_id,
    note = note,
    duration = duration,
    volume = volume,
    started_at = started_at,
  })
end

----------------
---- System ----
----------------

function seconds()
  return time() / 1000
end

T = seconds()

TIMESCALE = 1.0
SLOW_MOTION_TIMESCALE = 0.2

function TIC()
  local delta = seconds() - T
  T = seconds()

  UI.update()

  cls()

  local timescale = TIMESCALE
  if CW.is_set(BITS.SLOW_MOTION) then
    timescale = SLOW_MOTION_TIMESCALE
  end

  if UI.SCREEN > 1 then
    game_render()
    game_update(delta * timescale)
    hud_render()
  end

  UI.render()
  render_corruption()
  AUDIO.update()

  TICKS = TICKS + 1
end

function SCN(line)
  UI.scanline(line)
end

-------------------
-- Debug helpers --
-------------------
-- TODO remove before deploying
function tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent+1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))
    else
      print(formatting .. v)
    end
  end
end

---------------
---- Tests ----
---------------

function TESTS()
  -- test iter utils
  local numbers = { 1, 2, 3, 4, 5 }
  local first_even = filter(iter(numbers), function(n) return n % 2 == 0 end)()
  assert(first_even == 2)

  local first_larger_than_4 = filter(iter(numbers), function(n) return n > 4 end)()
  assert(first_larger_than_4 == 5)

  local no_such_number = filter(iter(numbers), function(n) return n == 123 end)()
  assert(no_such_number == nil)
end

TESTS()

-- <TILES>
-- 002:0000000000000400000004000004444400440000004402020044020000440200
-- 003:0000000000000000000000004444440000000400000004002000040002000400
-- 004:0000000000000000000004000000040000044444004400000044020200440200
-- 005:0000000000000000000000000000000044444400000004000000040020000400
-- 006:0000000000000400000004000004444400440000004402020044020000440200
-- 007:0000000000000000000000004444440000000400000004002000040002000400
-- 008:0000000000000400000004000004444400440000004402020044020000440200
-- 009:0000000000000000000000004444440000000400000004002000040002000400
-- 010:0000040000000400000444440044000000440202004402000044020000440200
-- 011:0000000000000000444444000000040000000400200004000200040020000400
-- 012:0000000000000e0000000e00000eeeee00ee000000ee0d0d00ee0d0000ee0d00
-- 013:000000000000000000000000eeeeee0000000e0000000e00d0000e000d000e00
-- 014:0000eeee000eeeee00eeeeee00eeeeee0eeeeeee0eefffefeeefefefeeefffef
-- 015:eeee0000eeeee000eeeeee00eeeeee00eeeeeee0efffeee0efefeeeeefffeeee
-- 018:0044020000440202004400000004444400004440000044000000400000004400
-- 019:2000040000000400000004004444440000044400000440000004000000044000
-- 020:0044020000440200004402020044000000044444000044400000400000004400
-- 021:0200040020000400000004000000040044444400000444000004000000044000
-- 022:0044020000440202004400000004444400004400000040000000440000000000
-- 023:2000040000000400000004004444440000044400000440000004000000044000
-- 024:0044020000440202004400000004444400004440000044000000400000004400
-- 025:2000040000000400000004004444440000044000000400000004400000000000
-- 026:0044020200440000000444440000440000004000000040000000400000000000
-- 027:0000040000000400444444000004400000040000000400000004000000000000
-- 028:00ee0d0000ee0d0d00ee0000000eeeee0000eee00000ee000000e0000000ee00
-- 029:d0000e0000000e0000000e00eeeeee00000eee00000ee000000e0000000ee000
-- 030:eeeffeefeeefefefeeefefefeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
-- 031:efeeeeeeefeeeeeeefeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
-- 032:33333333322cc22132cccc213cccccc13cccccc1322ccc213222222111111111
-- 033:3333333332222221322222213222222132222221322222213222222111111111
-- 034:5555555556666667566666675666666756666667566666675666666777777777
-- 035:aaaaaaaaa9999998a9999998a9999998a9999998a9999998a999999888888888
-- 036:aaaaaaaaa9999999a9999999a9999999a9999999a9999999a9999999a9999999
-- 037:aaaaaaaa99999998999999989999999899999998999999989999999899999998
-- 038:aaaaaaaaa9999999a9999999a9999999a9999999a9999999a999999988888888
-- 039:aaaaaaaa99999998999999989999999899999998999999989999999888888888
-- 040:aaaaaaaaa9999998a9999998a9999998a9999998a9999998a9999998a9999998
-- 041:0000000000000000000000000000000000d000000dd000000dd0000d0dd0d00d
-- 042:00000000000000d0000000d0000000d0d00000d0d0000dd0d0000dd0d0000dd0
-- 049:000000000000000000000000000cc000000cc000000000000000000000000000
-- 050:0000000000000000000cc00000cccc0000cccc00000cc0000000000000000000
-- 051:0000000000cccc000cccccc00cccccc00cccccc00cccccc000cccc0000000000
-- 052:a9999999a9999999a9999999a9999999a9999999a9999999a999999988888888
-- 053:9999999899999998999999989999999899999998999999989999999888888888
-- 056:a9999998a9999998a9999998a9999998a9999998a9999998a999999888888888
-- 057:0dd0d00d0dd0d00d0dd0d00d0dd0d00d0dd0dd0dddd0ddddddd0ddddddd0dddd
-- 058:d0000dd0d000ddd0d000ddd0d0d0ddd0d0d0ddd0d0d0ddd0ddddddd0ddddddd0
-- 065:00cccc000cccccc0cccccccccccccccccccccccccccccccc0cccccc000cccc00
-- 066:0000000000000000000000000000c000000cc000000000000000000000000000
-- 080:666666666777777f6777777f6777777f6777777f6777777f6777777fffffffff
-- 172:0000000000000000000000000000000d00000ccc0000fccc0000dccc0000cccc
-- 173:0000000e000ddcccfdcccccccccccccccccccccccccccccccccccccccccccccc
-- 174:ccccf000ccccce00ccccccdecccccccccccccccccccccccccccccccccccccccc
-- 175:000000000000000000000000d0000000c0000000ce000000cd000000ccd00000
-- 188:000fcccc000ecccc000dccc0000ccc00000ccfec000cefcc0000ecce0000cccd
-- 189:cccccccceddeedcc000000f00edddefdce000dcc0edcd0dc0cefcccc0000defc
-- 190:ccccccccccccccccdcccccd0dccccc00cccccccccccccccdcccccccccccc0cce
-- 191:ccccd000ccccd000000fd00000000000ccce0000000df000dcd0d0000fc0e000
-- 204:000ecccc000ecccc000dcccc000dcccc000dcccc000ecccc000ecccc000efecc
-- 205:ccdddccccccccccccccccccccccccccccccccccccccccce0cccccd0dcccccd0c
-- 206:cdcc0ccd0cccedccddccefcceeccd0dcccccc0fc0eccce0cccccceddcccccdee
-- 207:0000ec00cddddc00cccccc00cccccd00cccccc00cccccd00cccccd00ccccce00
-- 220:000ecccc000ecccc000dcccc000dcccc000dcccc000ecccc000ecccc000efecc
-- 221:ccdddccccccccccccccccccccccccccccccccccccccccce0cccccd0dcccccd0c
-- 222:dfccd0fdcccc0dccccccccccccccccccccccccdeffee0000cccccc00cccccc00
-- 223:ccccce00cccccf00ccccc000ccccf000cccc0000dccde000dcced000cccec000
-- 224:0000444400444444044444444444000444440044444404440444444400044404
-- 225:4404000000444400444444404000444440004444440044444440444004444000
-- 236:000ecccc0000cccc0000dccc00000dcc000000cc0000000c0000000e00000000
-- 237:cccd00fdccccf00dcccccd00ccccccccccccccccccccccccdccccccc0ecccccc
-- 238:cccccf00ccccc00000000000cccccffccccccccccccccccccccccccccccccccc
-- 239:dccec000dcced000cccde000ccdd0000ccf00000cc000000cd000000cf000000
-- 240:0004444400004040000040400000004000000040000000400000000000000000
-- 241:4444400004040000040400000400000004000000000000000000000000000000
-- 242:0000000066000000006606660000666606660676000006660006600000600000
-- 243:0000000000000066666066006766000066606660666000000006600000000600
-- 253:00dccccc000dcccc0000eccc00000ecc0000000f000000000000000000000000
-- 254:cccccccccccccccdccccccd0cccccd00eeeef000000000000000000000000000
-- 255:e000000000000000000000000000000000000000000000000000000000000000
-- </TILES>

-- <SPRITES>
-- 000:eeeeeee0eeeceeefeeccceefecececefeeeceeefeeeceeefeeeeeeef0fffffff
-- 001:eeeeeee0eeeceeefeeceeeefecccccefeeceeeefeeeceeefeeeeeeef0fffffff
-- 002:eeeeeee0eeeceeefeeeeceefecccccefeeeeceefeeeceeefeeeeeeef0fffffff
-- 003:eeeeeee0eeccceefeceeecefecccccefeceeecefeceeecefeeeeeeef0fffffff
-- 004:eeeeeee0eeecccefeeceeeefeeeceeefeeeeceefeccceeefeeeeeeef0fffffff
-- 005:eeeeeee0ecccccefeeeeceefeeeceeefeeceeeefecccccefeeeeeeef0fffffff
-- 006:eeeeeee0eceeecefeececeefeeeceeefeececeefeceeecefeeeeeeef0fffffff
-- 016:0000000000044000004444000444444000044200000442000004420000022000
-- 017:0000000000044440000044400004444000444240044420000042000000200000
-- 018:0000000000000000000000004400000044000000440000004400000044000000
-- 019:4400000044000000440000004400000044000000440000004400000044000000
-- 020:0000000000000000000000000022222200222222002222220022222200000000
-- 021:0000000000000000000000200022222200222222002222220022220200000000
-- 022:0000000000000000000022000022222200222222002222220022002200000000
-- 023:0000000000000000000220000002222200022222000222220000022200000000
-- 024:0000000000000000002200000022222200222222002222220000222200000000
-- 025:0000000000000000002000000022222200222222002222220002222200000000
-- 032:00000000000ee00000e00e0000e00e0000000e000000e000000000000000e000
-- 033:0004400000044000000440000444444000444400000440000000000099999999
-- 034:000c00c000c00c000006000c022660c022222000222320002233200002220000
-- 035:0000000000000000000440000040040404000044000004440000000000000000
-- 036:0000000000040000000040000000040000000400004040000044000000444000
-- 037:00000000000aaa0000a000a000a444a0000a4a0000a040a000a444a0000aaa00
-- 038:0000000000020000002224000020240000000400000004000000040000000000
-- 039:0444000000440400040400404000000440000004040040400040440000004440
-- 040:000000000000000000000cc00000ccd0000ccd000043d0000044000000000000
-- </SPRITES>

-- <MAP>
-- 000:32323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232030303343434d2d2d212121212021212111134d2111134d2d2d2d2d232320303033434340000001212121212121200000000111134d2d2d2d2d232000000000000000000000000000000000000000000000000000000005464000000000000820000008200000000000000000000000000000000000000824252000042520000425200004252000042520000425200004252000082000000000000000000000000000000000000000000000000000000000000
-- 001:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000000001212120212121202121200c2c2c20000000000003232000000000000d2d21212121212021212121134d2c2c200000000000082000000000000000000000000000000000000000000000000000000005565000000000000830000008300000000000000000000000000000000000000834353000043530000435300004353000043530000435300004353000083000000000000000000000000000000000000000000000000000000000000
-- 002:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000003121202121212121212121212c2c2c2000000000000323200000000000000001212120212121202121200c2c2c200000000000083000000000000000000000000000000000000000000000000000000003232121212121212820000008212121212121212121212000000000000000000820000000000000000000000000000000000000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 003:320000000000000000000000000000000000000000000000000000000032320000000000000000000000000000000000000000000000000000000032320303030303031212121212121212021212121212c2c2848484111111323203030303030303121202121212121212121212c2c2c2848484111111320000000000000000000000000000000000000000000000000000000000001200000000008300000083000000000000004252c200c2000000000000008300000000000000000000000000000000000000c200c200000000000083000000000000000000000000000000000000000000000000000000000000
-- 004:32000000000000000000000000000000000000000000000000000000003232000000000000000000000000000000000000000000000000000000003232000000000000001212000022222200000012000000000000000011003282000000000000121212121212121202121212121200000000000011003200000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000043530000c20000000000000082000000000000000000000000000000000000000000c200000000000082000000000000000000000000000000000000000000000000000000000000
-- 005:320000000000000000000000000000000000000000000000000000000032320000000000000000000000000000000000000000000000000000000032320000000000000000000000222222c2c2c2c2000000000000000000003283000000000000001212000005050500000012000000000000000000003200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c2c242520000000000000000000083000000000000000000000000000000c2c2000000000000000000000083000000000000000000000000000000000000000000000000000000000000
-- 006:320000000000000000000000000000000000000000000000000000000032320000000000000000000000000000000000000000000000000000000032320000000000101010000000222222c2c2c2c20000000000000000000032320000000000101010000000050505c2c2c2c20000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000101010000000000000c2c2c2435300000000000000000000820000000000101010000000000000c2c2c2000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 007:320000000000000000000000000000000032000000000000000000000032320000000000000000000000000000000000000000000000000000000032320000000000000010000000222222c2c2c2c20000000000000000000032320000000000000010000000222222c2c2c2c2000000000000000000003200000000000000000000000000000000000000000000000000000000000012222222000000001000000000000000c2c24252000000000042520000128300000000000092000000009200000000c20000a2000000000000000083000000000000000000000000000000000000000000000000000000000000
-- 008:320000000000000000000000000000000000000000000000000000000032320000000000000000000000000000000000000000000000000000000032320000000000000000000000222222c2c2c2c20000000000000000000032320000000000000000000022222222c2c2c2c20000000000000000000032000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000c2c2c24353000000000043530000128200003232323293a33232329332323232323293a3323232323200000082000000000000000000000000000000000000000000000000000000000000
-- 009:320000000000000000000000000000000000000000000000000000000032320000000000000000000000000000000000000000000000000000000032320000000000000000000010222222c2c2c2c21000000000000000000032320000000000000000000010222222c2c2c2c21000000012121212121232000000000000000000000000000000000000000000000000000000000000120000000000000000000010000000c2c2c2425200000000004252000012830000323232326272320032623200c2c2c2326272320000000000000083000000000000000000000000000000000000000000000000000000000000
-- 010:320000000000000000000000000000320000000000000000000000000032320000000000000000000000000000000000000000000000000000000032320000000000000000000010222222c2c2c2c210000000000000000000323200000000000000000000100022222222c2c2100000000000c8d8c8d83200c8d8000000000000000000000000000000000000000000000000000000120000000000820000008210000000c2c2c2435300000000004353000012820000323200000000000010000000c2c2c2000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 011:32000000000000000000000000000000000000000000000000005464003232005464000000a292a292a29292a292a292a29292a292a2000000000032320000000000000000000010222222c2c2c2c2757500000000000054643232425292a200000092a20010222222c2c2c2c275750000000092a2546432627262726272627262726272627262726272627262726272627262726272120000000000830000008310000000c2c2c2425275000000004252546412830000323200000000000010000000c2c200000075000000000000546483000000000000000000000000000000000000000000000000000000000000
-- 012:32000000000000000000000000000000000000000000000000005565003232005565000093a393a393a39393a393a393a39393a393a3000000000032320000000000000000000010222222b2b2b2b2b2b2b2b2b2b2b20000653232435393a300000093a30010222222b2b2b2b2b2b2b2b2b2b293a3556532627262726272627262726272627262726272627262726272627262726272120000000000820000008210000000b2b2b24353b2b2b2b2b24353006512820000323292a20000000010000000b292a20000b2b2b2b2b20000006582000000000000000000000000000000000000000000000000000000000000
-- 013:320000003232323232323232323200000000000000000000000000323232323232323212121212121212121212121212121212121212123232323232323232323222222232323232626262626262623222222232323232323232323232323222222232323232626262626262623222222232323232323232000000000000000000000000000000000000000000000000000000000000121212121212830000008312121212000012121212121212121212121212832222222293a322222222222222222293a3222222222222222222222283000000000000000000000000000000000000000000000000000000000000
-- 014:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b2b2b2b2b2b2b20000000000000000000000e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000121212120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b2b2b2000000000000000000000000000000000000000000e2e2e2e2e2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cadaeafa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cbdbebfb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200ccdcecfc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cdddedfd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cedeeefe000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cfdfefff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000121212120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 034:323232323232323232323232323232323232323232323232323232323232323232323232322222323232323232323232322222222232323232323232323232322222222232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 035:320000000000000000000000003292a2324252323232323232000000003232000000003200000000323292a232320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 036:320000000000000000000000003293a3324353323232323232000000003232000000002200000000223293a33232000000000000000000000092a292a292a2000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 037:323232323232323232323222223292a2323262723232323232000000003232000000002200000000223292a23232000000000000000000000093a393a393a3000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 038:3292a292a292a292a2923200003293a3323232323232323232000000003232323232323200000000323293a332323232322222222232323232323232323232322222222232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 039:3293a393a393a393a3933200003292a2323232324252323232000000003232000000000000000000003292a2a292a292a292a292a292a292a292a2a2323232000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 040:32323232323232323232320000323232323232324353323232323232323232000000000000000000003293a3a393a393a393a393a393a393a393a3a3323232000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 041:323232323232323232323200003232323232323232627232323232323232320000000000000000000032323232323232323232323232323232323232323200000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 042:323242523232326272823200003232323232823232323232323232323232320000000000000000000000000000323232323232323232323232323232320000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 043:323243533232323232833200003232323282833232323232323232323232320000000000000000000000000000323232323232323232323232323232320000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 044:323232326272323232323200000000000083000000000000000000000032320000000000000000000000000000323232323232323232323232323232000000003232323200000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 045:323232425232323232323200000000000000000000000000000000000032325500000000000000000000000000323232323232323232323232323232000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 046:323232435332323232323200000000000000000000000000000000000032323232323232322222320000000000000000323232323232323232323232000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 047:323232323232323232323222223232323232323232323232323232323232323232323232323232323200000000000000935293529352935293529352000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 048:000000000000000000000000000000000000000000000000000000000000323232323232323232323232320000000000529352935293529352935293000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 049:000000000000000000000000000000000000000000000000000000000000323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 119:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000323232323232323232323232323232323232323232323232323232323232
-- 120:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 121:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 122:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 123:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 124:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 125:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 126:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 127:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 128:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 129:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 130:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 131:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000032
-- 132:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000323232323232323232323232323232323232323232323232323232323232
-- 135:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d4d4d4d4d40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0d88ddddddd9dcc899633cccc99887ac
-- 003:0000eeedcb98642fffffffedcba97520
-- </WAVES>

-- <SFX>
-- 000:020f0201020f02000201020e02010200020e02010200020e02020200020f02010201020e02000201020f020002020201020e02000201020f02000201300000000000
-- 001:030008000500031f03500e9204a30ab503b503c505c503c304c107cf03cd13cb03c909c90fba03bb03ad038f070109020303030003000e000300038070b000000000
-- 002:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000307000000000
-- 003:01520162017301830193119421a421b541b651c761c781d791d7a1d0d1d0e1d0f150f110f100f100f100f100f100f100f100f100f100f100f100f100c00000000000
-- </SFX>

-- <PATTERNS>
-- 000:400026800026b00026000000100020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300
-- </TRACKS>

-- <FLAGS>
-- 000:00000000000000000000000000000000000000000000000000000000000000000010101010101010104040000000000000000000101000001040400000000000000000000020200000000000000000000000000000202000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

