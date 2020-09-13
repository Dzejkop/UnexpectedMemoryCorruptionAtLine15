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
  FLAG_CONTROL = 4,
  BORDER_PORTALS = 5
}

local TRACKS = {
  THEME = 0,
}

local SFX = {
  KILL = 1,
  JUMP = 3,
}

local SFX_CHANNEL = 0

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
  PLAYER_ACCELERATION = 220,
  PLAYER_DECCELERATION = 350,
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

function math.lerp(a, b, t)
  if t <= 0 then
    return a
  end

  if t >= 1 then
    return b
  end

  return a * (1 - t) + b * t
end

function math.lerpi(a, b, t)
  return math.floor(math.lerp(a, b, t))
end

---------------
---- Color ----
---------------

color = {}

function color.build_rgb(r, g, b)
  return (r << 16)
       + (g << 8)
       + b;
end

function color.split_rgb(c)
  return (c & 0xFF0000) >> 16
       , (c & 0x00FF00) >> 8
       , (c & 0x0000FF)
end

function color.lerp(a, b, t)
  local a_r, a_g, a_b = color.split_rgb(a)
  local b_r, b_g, b_b = color.split_rgb(b)

  local c_r = math.lerpi(a_r, b_r, t)
  local c_g = math.lerpi(a_g, b_g, t)
  local c_b = math.lerpi(a_b, b_b, t)

  return color.build_rgb(c_r, c_g, c_b)
end

function color.read(id)
  local r = peek(0x03FC0 + 3 * id + 0)
  local g = peek(0x03FC0 + 3 * id + 1)
  local b = peek(0x03FC0 + 3 * id + 2)

  return color.build_rgb(r, g, b)
end

function color.store(id, c)
  local r, g, b = color.split_rgb(c)

  poke(0x03FC0 + 3 * id + 0, r)
  poke(0x03FC0 + 3 * id + 1, g)
  poke(0x03FC0 + 3 * id + 2, b)
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
        local offset = LEVELS.shift_offset_pixels()
        local player_pos = PLAYER.pos:add(offset)
        local flag_pos = FLAG.pos:sub(offset)

        PLAYER.pos = flag_pos
        FLAG.pos = player_pos

        PLAYER.vel = PLAYER.vel:mul(1.5)
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

    local bit_x = (SCR_WIDTH - 6 * 2 * CHR_WIDTH - blank_space_width) / 2
    local bit_y = hud_y + (HUD_HEIGHT - CHR_HEIGHT) / 2 - 3

    for bit_idx = 0,5 do
      if bit_idx == 3 then
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
  local min_len = props.min_len or 0
  local max_len = props.max_len or 6
  local len = props.len or math.random(min_len, max_len)

  return setmetatable({
    position = props.pos,
    len = len,
    min_len = min_len,
    max_len = max_len,
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

    if self.len <= self.min_len then
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

  if PLAYER.is_dead and CW.is_set(BITS.FLAG_CONTROL) then
    spr(
      14,
      sprite.pos.x,
      sprite.pos.y,
      -1,
      1,
      0,
      0,
      2,
      2
    )
  else
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
end

FLAG = Flag:new()

----------------
---- Player ----
----------------

PLAYER_DIMENSION = Vec.new(2 * TILE_SIZE, 2 * TILE_SIZE)

PLAYER_RUNNING_ANIMATION = {
  switch_every = 0.3, -- seconds
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

  AUDIO.play_note(SFX.KILL, "C#3", 64, 15)
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
  if DBG_SUDO_KEYS_ENABLED then
    local x, y, left = mouse()

    if left then
      self.pos.x = x - TILE_SIZE
      self.pos.y = y - TILE_SIZE
    end
  end

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
      if LEVELS.has_next() then
        AUDIO.play_note(0, "C-5", 8, 11)
        AUDIO.play_note(0, "F-5", 8, 11)
        AUDIO.play_note(0, "A-5", 8, 11)

        UI.enter(function ()
          LEVELS.start_next()
        end)
      else
        UI.enter(function ()
          UI.SCREEN = 3
        end)
      end
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
      if self.pos.y > SCR_HEIGHT - HUD_HEIGHT then
        self.pos.y = -1.5 * TILE_SIZE
      elseif self.pos.y < -1.5 * TILE_SIZE then
        self.pos.y = SCR_HEIGHT - HUD_HEIGHT - TILE_SIZE
      elseif self.pos.x <= -TILE_SIZE then
        self.pos.x = SCR_WIDTH - TILE_SIZE - 1
      elseif self.pos.x >= SCR_WIDTH - TILE_SIZE then
        self.pos.x = -TILE_SIZE + 1
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

  -- Apply friction
  if self.is_on_ground then
    if math.abs(self.vel.x) > 1 then
      local sign = self.vel.x / math.abs(self.vel.x)
      self.vel.x = self.vel.x - PHYSICS.PLAYER_DECCELERATION * sign * delta
    end
  end

  local is_colliding_horizontally = false

  if CW.is_set(BITS.COLLISION) then
    is_colliding_horizontally = collisions_update()
  end

  if not self.is_dead then
    -- Process moving left or right
    if btn(BUTTONS.LEFT) or btn(BUTTONS.RIGHT) then
      local acc = 1.0
      local force = PHYSICS.PLAYER_ACCELERATION

      if self.is_on_ground then
        force = force + PHYSICS.PLAYER_DECCELERATION
      else
        force = 0.8 * force

        if CW.is_set(BITS.GRAVITY) then
          acc = 0.6
        else
          acc = 0.1
        end
      end

      if btn(BUTTONS.LEFT) then
        acc = -acc
      end

      local delta_vx = acc * force * delta

      self.vel.x = math.clamp(self.vel.x + delta_vx, -self.speed, self.speed)
      self.acc.x = acc
    else
      if math.abs(self.vel.x) < 10 then
        self.vel.x = 0
      end
    end

    -- Process jumping
    if self.is_on_ground and btnp(BUTTONS.UP) then
      self.vel = self.vel:add(Vec:up():mul(PHYSICS.PLAYER_JUMP_FORCE))
      self.is_on_ground = false

      AUDIO.play_note(SFX.JUMP, "C#5", 16, 12)
      EFFECTS:add(Poof:small(self:collider_bottom_center()))
    end
  end

  -- Apply collision
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

  if CW.is_set(BITS.BORDER_PORTALS) then
    local overflow_left_x = -sprite.pos.x - 1
    local overflow_right_x = sprite.pos.x + 2 * TILE_SIZE - SCR_WIDTH - 3

    if overflow_left_x > 0 then
      spr(
        sprite.id,
        SCR_WIDTH - overflow_left_x,
        sprite.pos.y,
        0,
        1,
        sprite.flip,
        0,
        2,
        2
      )
    elseif overflow_right_x > 0 then
      spr(
        sprite.id,
        overflow_right_x - TILE_SIZE * 2 + 2,
        sprite.pos.y,
        0,
        1,
        sprite.flip,
        0,
        2,
        2
      )
    end
  end

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
    allowed_cw_bits = 6,
  },

  -- Intro - Steering
  --
  -- Objective:
  -- - Introduce player to basic steering and physics (left, right, jumping)
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

  -- Intro - Bits
  --
  -- Objective:
  -- - Introduce player to the concept of bits (and spikes, although it's not
  --   strictly necessary to learn that at the moment)
  --
  -- Solutions:
  -- - Toggle the collision bit, reach the flag
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

  -- Intro - Hostile Terrain
  --
  -- Objective:
  -- - Introduce player to the first hostile item - spikes - and make the
  --   player use `a` / `s` to switch currently selected bit
  --
  -- Solutions:
  -- - Toggle the gravity bit, reach the flag
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

  -- Mushroom Tree
  --
  -- Objective:
  -- - Force player to jump outside the map, to show them that it's legal to
  --   use empty space at the top of the map
  {
    map_offset = Vec.new(60, 0),
    spawn_location = Vec.new(1 * TILE_SIZE, 1 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 2,

    build_enemies = function()
      return {
        SpiderEnemy:new({
          pos = Vec.new(6.5 * TILE_SIZE, 4 * TILE_SIZE),
          min_len = 6,
          max_len = 16,
          left_sign = 256,
          right_sign = 256,
        }),

        SpiderEnemy:new({
          pos = Vec.new(26 * TILE_SIZE, -TILE_SIZE),
          max_len = 16,
          left_sign = 259,
          right_sign = 261,
        }),
      }
    end
  },

    -- Spiky Floating Rooms
    --
    -- Objective:
    -- - Force player to use the shift-x bit
    -- - Hint to the player that green colored floor indicates linked teleporting locations
    --
    -- Solutions
    -- - use the shift-x bit, to teleport to the next room, and go to the flag
    {
      map_offset = Vec.new(60, 17),
      spawn_location = Vec.new(3 * TILE_SIZE, 4 * TILE_SIZE),
      flag_location = Vec.new(25 * TILE_SIZE, 4 * TILE_SIZE),
      allowed_cw_bits = 3,

      build_enemies = function()
        return {}
      end
    },

  -- Death Maze
  --
  -- Objective:
  -- - Force player to compose bits (i.e. toggle many of them at the same time)
  --
  -- Solutions:
  -- - Move a bit, toggle shift-x, toggle shift-y, move a bit, toggle shift-x
  -- - Toggle gravity, toggle collision, use fine-tuned movements to enable
  --   gravity back again while floating near the flag
  -- - Toggle shift-x, float above the spikes, toggle shift-x
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

  -- The Terminator
  --
  -- Objective:
  -- - Introduce player to the concept of enemies and teach them how to use the
  --   slow-motion bit
  {
    map_offset = Vec.new(120, 0),
    spawn_location = Vec.new(TILE_SIZE, TILE_SIZE),
    flag_location = Vec.new(28 * TILE_SIZE, 0 * TILE_SIZE),
    allowed_cw_bits = 4,

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

  -- Call Me by Your Name
  --
  -- Objective:
  -- - Introduce player to the flag-control bit
  --
  -- Solutions:
  -- - Enable the "flag control" bit, easily reach player with flag
  --
  -- TODO:
  -- - there are other solutions that don't involve switching the flag
  {
    map_offset = Vec.new(30, 17),
    spawn_location = Vec.new(4 * TILE_SIZE, 11 * TILE_SIZE),
    flag_location = Vec.new(23 * TILE_SIZE, 3 * TILE_SIZE),
    allowed_cw_bits = 5,
  },

  -- Now You're Thinking With Portals
  --
  -- Objectives:
  -- - Introduce player to the border-portals bit by forcing them to jump at
  --   the bottom of the map
  {
    map_offset = Vec.new(150, 0),
    spawn_location = Vec.new(1 * TILE_SIZE, 9 * TILE_SIZE),
    flag_location = Vec.new(21 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 6,
  },

  -- Jumping through hoops and different dimensions
  {
    map_offset = Vec.new(90, 34),
    spawn_location = Vec.new(25 * TILE_SIZE, 11 * TILE_SIZE),
    flag_location = Vec.new(3 * TILE_SIZE, 4 * TILE_SIZE),
    allowed_cw_bits = 6,
  },

  -- Now You're Thinking About Zordon
  --
  -- Objectives:
  -- - Fun
  -- - Reinforce player on using the border-portals bit
  {
    map_offset = Vec.new(150, 17),
    spawn_location = Vec.new(1 * TILE_SIZE, 9 * TILE_SIZE),
    flag_location = Vec.new(27 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 6,
  },

  -- Looking from Above
  {
    map_offset = Vec.new(0, 17),
    spawn_location = Vec.new(1 * TILE_SIZE, 1 * TILE_SIZE),
    flag_location = Vec.new(14 * TILE_SIZE, 2 * TILE_SIZE),
    allowed_cw_bits = 6,
  },

  -- Skulls Of Death
  {
    map_offset = Vec.new(180, 0),
    spawn_location = Vec.new(1 * TILE_SIZE, 11 * TILE_SIZE),
    flag_location = Vec.new(7 * TILE_SIZE, 11 * TILE_SIZE),
    allowed_cw_bits = 6,

    build_enemies = function()
      local MIN_Y = -6 * TILE_SIZE
      local MAX_Y = 7 * TILE_SIZE
      local CYCLE_LENGTH = 1.5
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
          cycle_length = CYCLE_LENGTH
        }),


        LostSoulEnemy:new({
          pos_start = Vec.new(7 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(7 * TILE_SIZE, MAX_Y),
          cycle_length = CYCLE_LENGTH
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(11 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(11 * TILE_SIZE, MAX_Y),
          cycle_length = CYCLE_LENGTH
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(15 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(15 * TILE_SIZE, MAX_Y),
          cycle_length = CYCLE_LENGTH
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(19 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(19 * TILE_SIZE, MAX_Y),
          cycle_length = CYCLE_LENGTH
        }),

        LostSoulEnemy:new({
          pos_start = Vec.new(23 * TILE_SIZE, MIN_Y),
          pos_end = Vec.new(23 * TILE_SIZE, MAX_Y),
          cycle_length = CYCLE_LENGTH
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

function LEVELS.has_next()
  return LEVELS[LEVEL + 1] ~= nil
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
    return 6
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
  if vec.x < 0 or vec.y < 0 or vec.x >= 30 or vec.y >= 14 then
    return nil
  end

  vec = vec:add(LEVELS.map_offset())

  if vec.x < 0 or vec.y < 0 then
    return nil
  else
    return mget(vec.x, vec.y)
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
    -- Screen: Intro
    [1] = {
      update = function(this)
        -- Avoid bugging game by keeping keys pressed for more than one frame
        if this.vars.started then
          return
        end

        if any_key() then
          this.vars.started = true

          AUDIO.play_note(0, "C-4", 8, 11)
          AUDIO.play_note(0, "E-4", 8, 11)
          AUDIO.play_note(0, "G-4", 8, 11)
          AUDIO.play_note(0, "B-4", 8, 11)
          AUDIO.play_note(0, "D-4", 8, 11)
          AUDIO.play_note(0, "G-4", 8, 11)
          AUDIO.play_note(0, "C-5", 8, 11)

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

      scanline = function(_, line)
        poke(0x3FF9, 0)
        poke(0x3FF9 + 1, 0)

        if line < 30 then
          if math.random() < 0.12 then
            poke(0x3FF9, math.random(-3, 3))
            poke(0x3FF9 + 1, math.random(-3, 3))
          end
        end
      end,

      vars = {
        started = false,
      }
    },

    -- Screen: Game
    [2] = {
      update = function(_, delta)
        -- If player's dead, allow them to respawn
        if PLAYER.is_dead then
          if is_respawn_allowed() and any_key() then
            LEVELS.restart()
          end
        end

        -- Handle the `Z` key
        if btnp(4) then
          if LEVELS.allowed_cw_bits() == 0 then
            AUDIO.play_note(0, "D#5", 4, 12)
          else
            if CW.is_set(UI.VARS.SEL_CWORD_BIT) then
              AUDIO.play_note(0, "D#5", 2, 12)
              AUDIO.play_note(0, "C#5", 2, 12)
            else
              AUDIO.play_note(0, "C#5", 2, 12)
              AUDIO.play_note(0, "D#5", 2, 12)
            end

            increment_corruption()
            CW.toggle(UI.VARS.SEL_CWORD_BIT)
          end
        end

        -- Handle the `A` key
        if btnp(6) then
          if LEVELS.allowed_cw_bits() == 0 then
            AUDIO.play_note(0, "D#5", 4, 12)
          else
            UI.VARS.SEL_CWORD_BIT = (UI.VARS.SEL_CWORD_BIT - 1) % LEVELS.allowed_cw_bits()
          end
        end

        -- Handle the `S` key
        if btnp(7) then
          if LEVELS.allowed_cw_bits() == 0 then
            AUDIO.play_note(0, "D#5", 4, 12)
          else
            UI.VARS.SEL_CWORD_BIT = (UI.VARS.SEL_CWORD_BIT + 1) % LEVELS.allowed_cw_bits()
          end
        end

        local timescale = TIMESCALE

        game_update(delta * timescale)
      end,

      render = function()
        game_render()
        hud_render()
        render_corruption()
      end,

      scanline = function(_, line)
        render_corruption_scn(line)
      end
    },

    -- Screen: Outro
    [3] = {
      update = function(this)
        local background = color.read(0)

        if this.vars.progress == 0 then
          color.store(1, background)
          color.store(2, background)
          color.store(3, background)
          color.store(4, background)
        end

        -- Start fade-in for the `UNEXPECTED MEMORY CORRUPTION` text
        if this.vars.progress >= 50 then
          local c = color.lerp(
            background,
            0x41A6f6,
            (this.vars.progress - 50) / 150
          )

          color.store(1, c)
        end

        -- Start fade-in for the `Thank you` text
        if this.vars.progress >= 180 then
          local c = color.lerp(
            background,
            0xFFFFFF,
            (this.vars.progress - 180) / 150
          )

          color.store(2, c)
        end

        -- Start fade-in for the `Created by` text
        if this.vars.progress >= 280 then
          local c = color.lerp(
            background,
            0xFFCD75,
            (this.vars.progress - 280) / 150
          )

          color.store(3, c)
        end

        -- Start fade-in for the `Unexpected Jam` text
        if this.vars.progress >= 380 then
          local c = color.lerp(
            background,
            0x38B764,
            (this.vars.progress - 380) / 150
          )

          color.store(4, c)
        end

        this.vars.progress = this.vars.progress + 1
      end,

      render = function(this)
        UiLabel
          :new()
          :with_xy(0, 8)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_text("UNEXPECTED MEMORY CORRUPTION")
          :with_color(1)
          :with_letter_spacing(2)
          :with_centered()
          :render()

        UiLabel
          :new()
          :with_xy(0, 40)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_line("You won, thank you for playing!")
          :with_color(2)
          :with_centered()
          :render()

        UiLabel
          :new()
          :with_xy(0, 70)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_line("Created by:")
          :with_color(3)
          :with_centered()
          :render()

        for author_idx, author in ipairs(this.vars.authors) do
          UiLabel
            :new()
            :with_xy(0, 75 + 8 * author_idx)
            :with_wh(SCR_WIDTH, SCR_HEIGHT)
            :with_line(author)
            :with_color(3)
            :with_centered()
            :render()
        end

        UiLabel
          :new()
          :with_xy(0, 125)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_line("Unexpected Jam, 2020")
          :with_color(4)
          :with_centered()
          :render()
      end,

      scanline = function(_, line)
        UI.SCREENS[1]:scanline(line)
      end,

      vars = {
        authors = {
          "J. Trad (aka dzejkop)",
          "R. Chabowski (aka mgr inz. Rafal)",
          "P. Wychowaniec (aka Patryk27)",
        },

        progress = 0,
      }
    },
  },

  -- Function that handles current screen transition, if any
  TRANSITION = nil,

  VARS = {
    -- Index of currently selected control word's bit; 0..7
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

function UI.update(delta)
  local screen = UI.SCREENS[UI.SCREEN]

  if screen.update then
    screen:update(delta)
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
    screen:scanline(line)
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

----------------
-- Ui / Label --
----------------

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

function TIC()
  local delta = seconds() - T

  T = seconds()

  UI.update(delta)

  cls()

  UI.render()
  AUDIO.update()

  TICKS = TICKS + 1
end

function SCN(line)
  UI.scanline(line)
end

music(TRACKS.THEME)

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
-- 014:000000dd00000dde0000ddee000ddeee000deee800ddeeee00deeeee00deeeee
-- 015:dd000000eee00000eeee00008eeee00088eeef008eeeeef08eeeeef08eeeeef0
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
-- 030:00deeeee00de888e00de8e8e00de888e00de88ee00de8e8e00deeeee00deeeee
-- 031:eeeeeef08e888ef08e8e8ef08e888ef08e8eeef08e8eeef0eeeeeef0eeeeeef0
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
-- 043:0ddddddd0ddddddd0ddd0d0d0ddd0d0d0ddd0d0d0ddd000d0ddd000d0dd0000d
-- 044:dddd0ddddddd0ddddddd0dddd0dd0dd0d00d0dd0d00d0dd0d00d0dd0d00d0dd0
-- 045:ddd00000dddddddddddddddd00000000dddddddddddd0000ddd00000dddddddd
-- 046:00000000ddd00000dddd000000000000d00000000000000000000000dd000000
-- 049:000000000000000000000000000cc000000cc000000000000000000000000000
-- 050:0000000000000000000cc00000cccc0000cccc00000cc0000000000000000000
-- 051:0000000000cccc000cccccc00cccccc00cccccc00cccccc000cccc0000000000
-- 052:a9999999a9999999a9999999a9999999a9999999a9999999a999999988888888
-- 053:9999999899999998999999989999999899999998999999989999999888888888
-- 054:aaaaaaaaa998a998a998a99888888888aaaaaaa8a998a998a998a99888888888
-- 055:aaaaaaaaaaabba88aabbbb88abbbbbb8abbbbbb8aabbbb88a88bb88888888888
-- 056:a9999998a9999998a9999998a9999998a9999998a9999998a999999888888888
-- 057:0dd0d00d0dd0d00d0dd0d00d0dd0d00d0dd0dd0dddd0ddddddd0ddddddd0dddd
-- 058:d0000dd0d000ddd0d000ddd0d0d0ddd0d0d0ddd0d0d0ddd0ddddddd0ddddddd0
-- 059:0dd0000d0dd0000d0dd0000d0d00000d0d0000000d0000000d00000000000000
-- 060:d00d0dd0d0000dd000000dd000000d0000000000000000000000000000000000
-- 061:dddddddddd000000ddddd000dd000000ddddddd0dddddddddddddddd00000000
-- 062:dddd000000000000000000000000000000000000ddd00000ddddddd000000000
-- 065:00cccc000cccccc0cccccccccccccccccccccccccccccccc0cccccc000cccc00
-- 066:0000000000000000000000000000c000000cc000000000000000000000000000
-- 068:aaaaa998aaaa9998aaa99998aa999988a9999888999988889998888888888888
-- 073:000000000ddddddd00000ddd000000000000000000000000000000000000dddd
-- 074:00000000dddddddddddddddd0ddddddd000000dd000ddddd000000dddddddddd
-- 080:666666666777777f6777777f6777777f6777777f6777777f6777777fffffffff
-- 089:000000dd00000000000000000000000d000000000000dddd00000ddd00000000
-- 090:dddddddd00000ddd0000dddddddddddd00000000dddddddddddddddd00000ddd
-- 096:00000000000000000000000f000000000000000f000000000000000f00f00fff
-- 097:000000000000000f000000000000000f0000000ff0000000f000000fffffffff
-- 098:0000000000000000f00000000000000000000000f0000000f0000000ff0f0f00
-- 112:00f0ffff0000000f0000000f0000000f0000000f0000000f0000000f0f00ffff
-- 113:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
-- 114:fff0ff00f0000000f0000000f0000000f0000000f0000000f0000000ffff0f00
-- 115:fffffffff0000ffffff00f0ff000000ff000000fff00000fff000fffffffffff
-- 128:00f0f0ff0000000f0000000f00000000000000000000000f0000000000000000
-- 129:fffffffff000000f0000000ff000000f000000000000000f0000000000000000
-- 130:fff00f00f000000000000000f000000000000000f00000000000000000000000
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
-- 034:0000400000044400004444400000400000040000000040000000040000004000
-- 035:0000000000000000000440000040040404000044000004440000000000000000
-- 036:0000000000040000000040000000040000000400004040000044000000444000
-- 037:0000000000020000002224000020240000000400000004000000040000000000
-- 038:0000000000400000004400004444400444444004004400000040000000000000
-- 039:00000000000aaa0000a000a000a444a0000a4a0000a040a000a444a0000aaa00
-- 040:000000000000000000000cc00000ccd0000ccd000043d0000044000000000000
-- </SPRITES>

-- <MAP>
-- 000:3232323232323232326332323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323203030334340000000012121212021212111134000000000000000000323203030334340000000012121212121212000000001111340000000000320000000000000000000000000000000000000000000000000000000054640000000000000000000042a5320000000032d23200000000000000000000824252000042520000425200004252000042520000425200004252000082000000000000000000000000000000000000000000000000000000000000
-- 001:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000000001212120212121202121200000000000000000000323200000000000000001212121212021212121134000000000000000000820000000000000000000000000000000000000000000000000000000055650000000000000000000042a5320000000032d23200000000000000000000834353000043530000435300004353000043530000435300004353000083000000000000000000000000000000000000000000000000000000000000
-- 002:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000003121202121212121212121212000000000000000000323200000000000000001212120212121202121200000000000000000000830000000000000000000000000000000000000000000000000000000032320000000000000000000042a5320000000032d23200000000000000000000820000000000000000000000000000000000000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 003:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323203030303030312121212121212120212121212120000000084111111323203030303030303121202121212121212121212000000848484111111320000000000000000000000000000000000000000000000000000000000006262626262626262626262a5626262626262d23232323200000032323232830000000000000000000000000000000000000000000000000000000083000000000000000000000000000000000000000000000000000000000000
-- 004:32000000000000000000000000000000000000000000000000000000003232000000000000000000000000000000000000000000000000000000003232000000000000001212000022222200000012000000000000000011003282000000000000121212121212121202121212121200000000000011003200000000000000000000000000000000000000000000000000000000000032b2b2b2b2b2b2b2b2b2b2a5c2c2c2c2c2c2d24200000000000000000032820000000000000000000000000000000000000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 005:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000000000000002222220000000000000000000000000000328300000000000000121200000505050000001200000000000000000000320000000000000000000000000000000000000000000000000000000000003232323232323232323232a4000000000000d24200000000000000000032830000000000000000000000000000000000000000000000000000000083000000000000000000000000000000000000000000000000000000000000
-- 006:3200000000000000000000000000000000000000000000000000000000633200000000000000000000000000000000000000000000000000000000323200000000001010100000002222220000000000000000000000000000323200000000001010100000000505050000000000000000000000000000320000000000000000000000000000000000000000000000000000000000003200000000000000000032a400cadaeafa00d24200000000000000000032820000000000101010000000000000000000000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 007:3200000000000000000000000000000000636272000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000000100000002222220000000000000000000000000000323200000000000000100000002222220000000000000000000000000000320000000000000000000000000000000000000000000000000000000000003200000000000000000032a400cbdbebfb00d242000000000000000000328300000000000092000000009200000000000000a2000000000000000083000000000000000000000000000000000000000000000000000000000000
-- 008:3200000000000000000000000000000000000000000000000000000000443200000000000000000000000000000000000000000000000000000000323200000000000000000000002222220000000000000000000000000000323200000000000000000000222222220000000000000000000000000000320000000000000000000000000000000000000000000000000000000000003200000000000000000032a400ccdcecfc00d242000000000000000000328200003232323293a33232329332323232323293a3323232323200000082000000000000000000000000000000000000000000000000000000000000
-- 009:3200000000000000000000000000000000000000000000000000000000323200000000000000000000000000000000000000000000000000000000323200000000000000000000102222220000000000000000000000000000323200000000000000000000102222220000000010000000121212121212320000000000000000000000000000000000000000000000000000000000003200000000000000000032a400cdddedfd00d24200000000000000000032830000323232326272320032623200000000326272320000000000000083000000000000000000000000000000000000000000000000000000000000
-- 010:32000000000000000000000000000062720000000000000000000000003232000000000000000000000000000000000000000000000000000000003232000000000000000000001022222200000000000000000000000000003232000000000000000000001000222222220000100000000000c8d8c8d83200c8d80000000000000000000000000000000000000000000000000000003200000000000000000032a400cedeeefe00d24200000000000000000032820000323200000000000010000000000000000000000000000000000082000000000000000000000000000000000000000000000000000000000000
-- 011:32000000000000000000000000000000000000000000000000005464003232005464000000a292a292a29292a292a292a29292a292a200000000003232000000000000000000001022222200000000000000000000000054643232425292a200000092a200102222220000000000000000000000005464326272627262726272627262726272627262726272627262726272627262723200000000000000000032a400cfdfefff00d24200000000000000000032830000323200000000000010000000000000000000000000000000546483000000000000000000000000000000000000000000000000000000000000
-- 012:32000000000000000000000000000000000000000000000000005565003232005565000093a393a393a39393a393a393a39393a393a300000000003232000000000000000000001022222200000000000000000000000000653232435393a300000093a300102222220000000000000000000000005565326272627262726272627262726272627262726272627262726272627262723200000000000000000032a4000000000000d24200000000000000000032820000323292a200000000100000000092a2000000000000000000006582000000000000000000000000000000000000000000000000000000000000
-- 013:3200000032323232323232627232000000000000000000323232323232323232323232121212121212121212121212121212121212121232323232323232323232323232323232326262626262626232323232323232323232323232323232222222323232326262626262626232222222323232323232320000000000000000000000000000000000000000000000000000000000003232323200000032323232a4000000000000d23232323200000032323232833232323293a383323232833232323293a3833232328332833232323283000000000000000000000000000000000000000000000000000000000000
-- 014:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000121212120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cadaeafa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200001200cbdbebfb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:0000000000000032d2323232323232323232323232a563000000000000003232323232323232323232323232323232323232323232323232323232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a4000000000000d3e3000000000000000000001200001200ccdcecfc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:0000000000000032d2b2b2b2b2b2b2b2b2b2b2b2b2a5630000000000000032d2e2b2c2b2c2b2c2b2c2b2c2b2c24252b2c2b2c2b2c2b2c2425294a432000092a2a292a200000000000000000092a2a292a292a292a2a292a200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a4000000000000d3e3000000000000000000001200001200cdddedfd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:0000000000000063d2320000000000000000000032a5320000000000000032d3e3b3c3b3c3b3c3b3c3b3c3b3c34353b3c3b3c3b3c3b3c3435395a53200943232323232e20000000000000094323232323232323232323232e2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000095a5000000000000d2e2000000000000000000001200001200cedeeefe000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:0000000000007363d2320000000000000000000032a5327300000000000032d2e20000000000000000000000009432000000000000000032e394a43200953200000032e30000000000000095320000000000000000000032e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a4000000000000d3e3000000000000000000001200001200cfdfefff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:0000000000000063d2320000000063630000000032a5320000000000000032d3e30000000000000000000000009582000000000000000032e395a53200953200000032e20000000000000095320000000000000000000032e2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a400cadaeafa00d3e300000000000000000000121212120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:0000000000000032d2320000000000000000000032a5630000000000000032d2e200000000000000000000000000833232e3000000627232e394a43200953200000032e30000000000000094320000000000000000000032e2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a400cbdbebfb00d3e300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 023:0000000000000063d2320000000000000000000032a5320000000000000032d3e30000000000000000000000000000b2c200000000b2c2000095a53200953222222232e20000000000000094323222222232323232323232e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000095a500ccdcecfc00d2e200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 024:3263326363326363d2320000000000000000000032a5323263323263326332d2e20000000000000000000000000000b3c300000000b3c3000094a43200953282738232e30000000000000095328273823232323282738232e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a400cdddedfd00d3e300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 025:b2b2b2b2b2b2b2b2b2320000000000000000000032c2c2c2c2c2c2c2c2c232d3e300000000000000000000000000000000000000000000000095a5320000c3838283b3000000000000000000c3838283b3b3c3c3838283b300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a400cedeeefe00d3e300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 026:32323232323232323244636300000000000063634432323232323232323232d2e200000000000000000000000000000000000000000000000094a432000000b383c30000000000000000000000b383c300000000b383c30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000095a500cfdfefff00d2e200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 027:c3c3c3c3c3c3c3c3c3000000000000000000000000c3c3c3c3c3c3c3c30032d3e300000000000000000000000000000000000000000000000095a53200000000b300000000000000000000000000b3000000000000b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a4000000000000d3e300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 028:00000000000000000000000000000000000000000000000000000000000032d2e200000000000000000000000000000000000000000000000094a4320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000095a5000000000000d3e300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 029:00000000000000000000000000000000000000000000000000000000000032d3e300000000000000000000000000000000000000000000000095a5320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000094a4000000000000d3e300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 030:0000000000000000000000000000000000000000000000000000000000003232323232323232323232323232323232323232323232323232323232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003232320000000000000094a4000000000000d3e300000000000000323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 034:323232323232323232323232323232323232323232323232323232323232323232323232322222323232323232323232322222222232323232323232323232322222222232323232323232000000000000000000000000000000323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 035:320000000000000000000000003292a2324252323232323232000000003232000000003200000000323292a23232000000000000000000000000000000000000000000000000000000003200000000000000000000000000000032e2b3c3b3c3943200000000000032320000000000000000000000000032326272627262723262726272627232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 036:320000000000000000000000003293a3324353323232323232000000003232000000002200000000223293a33232000000000000000000000092a292a292a200000000000000000000003200000000000000000000000000000032e30092a20095820000000000003232000000000000000000000000003232b2c2b2c2b2c232b2c2b2c2b2c232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 037:323232323232323232323222223292a2323262723232323232000000003232000000002200000000223292a23232000000000000000000000093a393a393a300000000000000000000003200000000000000000000000000000032e20032320094830000000000003232000000000000320000000000008232b3c3b3c3b3c332b3c3b3c3b3c332320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 038:3292a292a292a292a2923200003293a3323232323232323232000000003232323232323200000000323293a33232323232222222223232323232323232323232222222223232323232323200000000000000000000000000000032e3000000009532000000000000323200000000000032000000000000833292a292a292a23292a292a292a232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 039:3293a393a393a393a3933200003292a2323232324252323232000000003232000000000000000000003292a2a292a292a292a292a292a292a292a2a232323200000000000000000000003200000000000000000000000000000032e2000000009432000000000000328200000000000032000000000000323293a393a393a33293a393a393a332320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 040:32323232323232323232320000323232323232324353323232323232323232000000000000000000003293a3a393a393a393a393a393a393a393a3a332323200000000000000000000003200000000000000000000000000000032e300222200958200000000000032833232222232323232323232323232326272627262728262726272627232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 041:32323232323232323232320000323232323232323262723232323232323232000000000000000000003232323232323232323232323232323232323232320000000000000000000000003200000000000000000000000000000032e200b3c30094830000000000003232b3c3b3c3b3c382b3c3b3c3b3c332320000000000008300000000000032320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 042:32324252323232627282320000323232323282323232323232323232323232000000000000000000000000000032323232323232323232323232323232000000000000000000000000003200000000000000000000000000000032e300000000953200000000000082320000000000008300000000000032820000000000003200000000000032320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 043:32324353323232323283320000323232328283323232323232323232323232000000000000000000000000000032323232323232323232323232323232000000000000000000000000003200000000000000000000000000000032e200000000943200000000000083320000000000003200000000000032830000000000003200000000000032320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 044:32323232627232323232320000000000008300000000000000000000003232000000000000000000000000000032323232323232323232323232323200000000000000000000000000003200000000000000000000000000000082e300000000953200000000000032320000000000003200000000000032320000000000003200000000000032320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 045:32323242523232323232320000000000000000000000000000000000003232550000000000000000000000000032323232323232323232323232323200000000000000000000000000003200000000000000000000000000000083e200000000943200000000000000000000000000003200000000000032320000000000000000000000000032320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 046:32323243533232323232320000000000000000000000000000000000003232323232323232222232000000000000000032323232323232323232323200000000222222220000000000003200000000000000000000000000000032e392a292a2953200000000000000000000000000003200000000000032320000000000000000000000000032320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 047:323232323232323232323222223232323232323232323232323232323232323232323232323232323200000000000000935293529352935293529352000000324252425232000000000032000000000000000000000000000000323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 048:000000000000000000000000000000000000000000000000000000000000323232323232323232323232320000000000529352935293529352935293000062724353435362720000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
-- 004:0abbccc9a9898b488f99996433345500
-- 005:0ddddddddcba966789aabbbba7432211
-- 006:000a9876554433333334445566778890
-- 007:000009765433333333445677889abcdd
-- </WAVES>

-- <SFX>
-- 000:000f0001000f00000001000e00010000000e00010000000e00020000000f00010001000e00000001000f000000020001000e00000001000f00000001300000000000
-- 001:030008000500031f03500e9204a30ab503b503c505c503c304c107cf03cd13cb03c909c90fba03bb03ad038f070109020303030003000e0003000380700000000000
-- 002:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000
-- 003:01520162017301830193119421a421b541b651c761c781d791d7a1d0d1d0e1d0f150f110f100f100f100f100f100f100f100f100f100f100f100f100c00000000000
-- 016:4400440044004400540064008400c400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400f400071000000000
-- 017:650065006500550055005500550055006500650065007500750065006500550065006500650065007500850085007500650065005500550055006500370000000000
-- 018:65006500550055005500550065006500650065006500650075008500850085009500a500a500a500a500b500b500c500d500d500e500e500f500f500300000000000
-- 019:4702370327022701270f470d570d57004702370337023700470e370d370e370137034703470237013700370e470037023703370337023700370f470e501000000000
-- 020:c601c6d2c6b2c684c675c647f620f610f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600110000000000
-- </SFX>

-- <PATTERNS>
-- 000:400001100001400001400003400005100001400001100001400001100001400001400005400003000000000000000000400001100001400001400003400005100001400001100001400001100001400001400005400003100001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:400043000041000041000041400043000041000041000041400043000041000041000041400043000021000021000000400043000000000000000000400043000000000000000000400043000000000000000000400043000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:900001100001900001900003900005100001900001100001900001100001900001900005900003000000000000000000900001100001900001900003900005100001900001100001900001100001900001900005900003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:900043000041000041000041900043000041000041000041900043000041000041000041900043000021000021000000900043000000000000000000900043000000000000000000900043000000000000000000900043000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:800001100001800001800003800005100001800001100001800001100001800001800005800003000000000000000000800001100001800001800003800005100001800001100001800001100001800001800005800003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:800043000041000041000041800043000041000041000041800043000041000041000041800043000021000021000000800043000000000000000000800043000000000000000000800043000000000000000000800043000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:600001100001600001600003600005100001600001100001600001100001600001600005600003000000000000000000600001100001600001600003600005100001600001100001600001100001600001600005600003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:600043000041000041000041600043000041000041000041600043000041000041000041600043000021000021000000600043000000000000000000600043000000000000000000600043000000000000000000600043000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:400019100011400019100011800019100011800019100011900019b00019100011900019b00019100011900019800019400019100011400019100011800019100011800019100011900019b00019100011900019b00019100011900019800019000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:900019100011900019100011d00019100011d0001910001140001b60001b10001140001b60001b10001140001bd00019900019100011900019100011d00019100011d0001910001140001b60001b10004140001b60001b10001140001bd00019000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:800019100031800019100011600019100011600019100011400019d00017100011400019d00017100011400017600017800019100011800019100011600019100011600019100011400019d00017100011400019d00017100011400017800017000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:600019100011600019100011400019100011400019100011d00017900017100011d00017900017100011600017800017600019100011600019100011400019100011400019100011d00017900017100011d00017900017100011600017800017000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:65563b80543b10043180003b10003160003b80543b100431b0003b100031b0003b100031b0003b100031b0003b100031b0003bd0543b100431d0003b100031d0003b100031d0003bb0543b10043160003b10003180003b100031000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:b55639905439100431900039100031b00039905439100431600039100031400039100031600039100031400039100031b00039905439100431900039100031b00039905439100431600039100031400039100031600039100031400039100031000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:65563b80543b10041180003b60543b10041160003b80543b10041180003bb0543b00043110003100003100001100001160003b80543b10043180003b60543b10043160003b80543b10043180003bb0543b000431100031000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:60003b40543b10043160003b40003b10003160003b40543b10043160003b40543bd00039b0003900043110003100000060003b40543b10043160003b40003b10003160003b40543b10043160003b40543bd00039b00039000431100031000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:180000180a00301b00180a05301b45581c00702d00581c85702dc5781c85502dc55410007c1000000000000000000000ec0200
-- </TRACKS>

-- <FLAGS>
-- 000:00000000000000000000000000000000000000000000000000000000000000000010101010101010104040404040400000000000101010101040404040404000000000001020200000404000000000000000000000202000004040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

