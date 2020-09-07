---------------
-- CONSTANTS --

-- TIC-80's screen width, in pixels
SCR_WIDTH = 240

-- TIC-80's screen height, in pixels
SCR_HEIGHT = 136

-- TIC-80 default font's char width, in pixels
CHR_WIDTH = 6

-- TIC-80 default font's char height, in pixels
CHR_HEIGHT = 6

local BITS = {
  COLLISION = 0,
  GRAVITY = 1,
  DISENGAGE_MALEVOLENT_ORGANISM = 2
}

----------------
-- GAME STATE --

-- Ticks since the game started
TICKS = 0

CURRENT_LEVEL = 1

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
  local v = { x = x, y = y }
  setmetatable(v, { __index = Vec })
  return v
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

function Vec.normalized(self)
  local len = self:len()
  return Vec.new(self.x / len, self.y / len)
end

function Vec.trace(self, name)
  name = (name .. " = ") or ""
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
        Player.is_on_ground = false
      elseif bit_idx == BITS.DISENGAGE_MALEVOLENT_ORGANISM then
        disengage_malevolent_organism()
      end
    end
  }
}

function CW.is_set(bit_idx)
  bit_idx = 7 - bit_idx
  return CW.reg & (1 << bit_idx) > 0
end

function CW.toggle(bit_idx)
  for _, observer in ipairs(CW.observers) do
    observer(bit_idx)
  end
  bit_idx = 7 - bit_idx
  CW.reg = CW.reg ~ (1 << bit_idx)
end

-------------
---- HUD ----
-------------

function hud_render()
  local hud_h = 24
  local hud_y = SCR_HEIGHT - hud_h

  function render_background()
    rect(0, hud_y, SCR_WIDTH, hud_h, 15)
  end

  function render_control_word_register()
    -- Size of the blank space between control word groups
    local blank_space_width = 40

    local bit_x = (SCR_WIDTH - 8 * 2 * CHR_WIDTH - blank_space_width) / 2
    local bit_y = hud_y + (hud_h - CHR_HEIGHT) / 2 - 3

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

      local bit_dy = 0

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

      print(bit, bit_x, bit_y + bit_dy, bit_color, true, 2)

      bit_x = bit_x + 2 * CHR_WIDTH
    end
  end

  render_background()
  render_control_word_register()
end

-----------------
---- Enemies ----
-----------------
ENEMIES = {
  LOST_SOUL = 1,
  SPIDER = 2
}

enemies = {}

function enemy_type_to_height(type)
  if type == ENEMIES.LOST_SOUL then
    return 2
  elseif type == ENEMIES.SPIDER then
    return 1
  end
end

function enemy_type_to_collision_radius(type)
  if type == ENEMIES.LOST_SOUL then
    return 12
  elseif type == ENEMIES.SPIDER then
    return 8
  end
end

function disengage_malevolent_organism()
  -- Pick one
  enemy_idx = math.random(1, #enemies)

  -- Change activity
  for i, v in ipairs(enemies) do
    if i == enemy_idx then
      v.paused = true;
    else
      v.paused = false;
    end
  end
end

------------------------
---- Enemy painters ----
------------------------
function spider_painter(obj)
  spr(obj.current_sprite, obj.pos.x, obj.pos.y, 0, 1, 0, 0, 2, enemy_type_to_height(obj.type))
  line(obj.pos.x + 8, obj.pos.y, obj.pos.x + 8, obj.string_attached_at, 12)
end

function lost_soul_painter(obj)
  spr(obj.current_sprite, obj.pos.x, obj.pos.y, 0, 1, 0, 0, 2, enemy_type_to_height(obj.type))
end

------------------------
---- Enemy handlers ----
------------------------
function spider_handler(obj)
  if obj.state == STATES.SPIDER.LOWERING then
    obj.pos.y = obj.pos.y + obj.vel.y
    obj.current_len = obj.current_len + 1
    if obj.current_len == obj.max_len then
      obj.state = STATES.SPIDER.CRAWLING
    end
  elseif obj.state == STATES.SPIDER.CRAWLING then
    obj.pos.y = obj.pos.y - obj.vel.y
    obj.current_len = obj.current_len - 1
    if obj.current_len == 0 then
      obj.state = STATES.SPIDER.LOWERING
    end
  end
end

function lost_soul_handler(obj)
  if obj.state == STATES.LOST_SOUL.FLYING then
    obj.vel.x = obj.vel.x + obj.acc.x
    obj.pos.x = obj.pos.x + obj.vel.x

    obj.vel.y = obj.vel.y + obj.acc.y
    obj.pos.y = obj.pos.y + obj.vel.y
  end
  if obj.vel.x > obj.max_vel.x or obj.vel.x < -obj.max_vel.x then
    obj.acc.x = -obj.acc.x
  end
  if obj.vel.y > obj.max_vel.y or obj.vel.y < -obj.max_vel.y then
    obj.acc.y = -obj.acc.y
  end
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
    DEAD = 12
  },
  LOST_SOUL = {
    FLYING = 224,
  },
  SPIDER = {
    LOWERING = 242
  },
  POOF = {
    49, 50, 51, 64
  }
}

----------------------
---- Enemy states ----
----------------------
STATES = {
  LOST_SOUL = {
    FLYING = 1
  },
  SPIDER = {
    LOWERING = 1,
    CLIMBING = 2
  }
}

----------------
---- Player ----
----------------

-- determines how long (in seconds) the player can hold the
-- jump button, to have reduced gravity
MAX_GRAVITY_REDUCT_TIME = 0.2

Player = {
  pos = Vec.new(30, 8*10),
  vel = Vec.new(0, 0),
  current_sprite = SPRITES.PLAYER.IDLE,
  speed = 100,
  collider = {
    offset = Vec.new(2, 3),
    size = Vec.new(11, 13)
  },
  inverse_air_time = MAX_GRAVITY_REDUCT_TIME,
  is_on_ground = false,
  is_dead = false
}

function Player.collider_center(self)
  return self.pos
    :add(self.collider.offset)
    :add(self.collider.size:mul(1 / 2))
end

function Player.collider_bottom_right(self)
  return self.pos
    :add(self.collider.offset)
    :add(self.collider.size)
end

function Player.collider_bottom_left(self)
  return self.pos
    :add(self.collider.offset)
    :add(Vec.down():mul(self.collider.size.y))
end

function Player.collider_top_right(self)
  return self.pos
    :add(self.collider.offset)
    :add(Vec.right():mul(self.collider.size.x))
end

function Player.collider_top_left(self)
  return self.pos
    :add(self.collider.offset)
    :add(Vec.right():mul(self.collider.size.x))
end

function Player.turn(self)
  if self.vel.x > 0.1 then
    return 1
  elseif self.vel.x < -0.1 then
    return -1
  else
    return 0
  end
end

----------------
---- Levels ----
----------------

Level = {}

function Level.new()
  local level = {}
  setmetatable(level, { __index = Level })
  return level
end

LEVELS = {
  [1] = {
    spawn_location = Vec.new(10, 30),
    map_offset = Vec.new(0, 0)
  },
  [2] = {
    spawn_location = Vec.new(10, 30),
    map_offset = Vec.new(30, 0)
  }
}

function LEVELS.current_offset()
  return LEVELS[CURRENT_LEVEL].map_offset
end

---------------
---- Game -----
---------------

BUTTONS = {
  UP = 0,
  DOWN = 1,
  RIGHT = 3,
  LEFT = 2
}

FLAGS = {
  IS_GROUND = 0,
  IS_WIN = 1
}

function game_init()
  CW.toggle(BITS.COLLISION)
  CW.toggle(BITS.GRAVITY)

  enemies[1] = {
    type = ENEMIES.LOST_SOUL,
    pos = Vec.new(10, 32),
    acc = Vec.new(0.07, 0.2),
    vel = Vec.new(0, 0),
    max_vel = Vec.new(3, 1.1),
    current_sprite = SPRITES.LOST_SOUL.FLYING,
    state = STATES.LOST_SOUL.FLYING,
    handler = lost_soul_handler,
    painter = lost_soul_painter,
    paused = false
  }

  enemies[2] = {
    type = ENEMIES.LOST_SOUL,
    pos = Vec.new(10, 48),
    acc = Vec.new(0.02, 0.1),
    vel = Vec.new(0, 0),
    max_vel = Vec.new(2.5, 1.1),
    current_sprite = SPRITES.LOST_SOUL.FLYING,
    state = STATES.LOST_SOUL.FLYING,
    handler = lost_soul_handler,
    painter = lost_soul_painter,
    paused = false
  }

  enemies[3] = {
    type = ENEMIES.SPIDER,
    string_attached_at = 16,
    pos = Vec.new(8*20, 16),
    acc = Vec.new(0, 0),
    vel = Vec.new(0, 0.5),
    current_len = 0,
    max_len = 8*7,
    max_vel = 0,
    current_sprite = SPRITES.SPIDER.LOWERING,
    state = STATES.SPIDER.LOWERING,
    handler = spider_handler,
    painter = spider_painter,
    paused = false
  }

  CW.toggle(BITS.DISENGAGE_MALEVOLENT_ORGANISM) -- requires enemies to be initialized
end

function find_tiles_below_collider()
  local below_left = Player:collider_bottom_left()
    :mul(1 / 8)
    :floor()

  local below_center = Player:collider_center()
    :add(Vec.down())
    :mul(1 / 8)
    :floor()

  local below_right = Player:collider_bottom_right()
    :mul(1 / 8)
    :floor()

  return { below_left, below_center, below_right }
end

function find_tiles_in_front_of_player()
  local forward = Player:collider_center()
    :mul(1 / 8)
    :add(Player.vel:x_vec():normalized())

  return { forward }
end

function find_tiles_above_player()
  local top_left = Player:collider_top_left()
    :mul(1 / 8)
    :floor()
  local top_right = Player:collider_top_right()
    :mul(1 / 8)
    :floor()

  return { top_left, top_right }
end

function game_update(delta)
  -- go through enemies
  for _, v in ipairs(enemies) do
    if not v.paused then
      v.handler(v)
    end
    v.painter(v)

    -- check collision with player
    x1 = v.pos.x
    y1 = v.pos.y
    x2 = Player.pos.x
    y2 = Player.pos.y
    distance = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    if distance < enemy_type_to_collision_radius(v.type) then
      if not Player.is_dead then
        Player.is_dead = true
        Player.current_sprite = SPRITES.PLAYER.DEAD
      end
    end
  end

  if Player then player_update(delta) end
end

function game_mget(vec)
  local offset = LEVELS.current_offset()
  local offset_vec = vec:add(offset:mul(1))
  return mget(offset_vec.x, offset_vec.y)
end

function collisions_update()
  function is_tile_ground(tile)
    return fget(game_mget(tile), FLAGS.IS_GROUND)
  end

  -- collisions below player
  local tiles_below_player = find_tiles_below_collider()
  local tile_below_player = filter(iter(tiles_below_player), is_tile_ground)()

  if tile_below_player ~= nil then
    if not Player.is_on_ground then
      Player.vel.y = 0
      Player.is_on_ground = true
      Player.pos.y = (tile_below_player.y - 2) * 8
    end
  elseif Player.is_on_ground then
    Player.is_on_ground = false
  end

  -- collisions to the sides
  local tiles_to_the_right_of_player = find_tiles_in_front_of_player()

  local tile_to_the_right_of_player = filter(iter(tiles_to_the_right_of_player), is_tile_ground)()
  local is_colliding_horizontally = tile_to_the_right_of_player ~= nil

  -- collisions above player
  local tiles_above_player = find_tiles_above_player()
  local tile_above_player = filter(iter(tiles_above_player), is_tile_ground)()

  if Player.vel.y < 0 and tile_above_player ~= nil then
    Player.vel.y = 0
  end

  return is_colliding_horizontally
end

local PHYSICS = {
  GRAVITY_FORCE = 520,
  REDUCED_GRAVITY = 170,
  REVERSED_GRAVITY_FORCE = -10,
  PLAYER_ACCELERATION = 200,
  PLAYER_DECCELERATION = 600,
  PLAYER_JUMP_FORCE = 120
}

function update_player_physics(delta)
  -- apply gravity
  if CW.is_set(BITS.GRAVITY) then
    if not Player.is_on_ground then
      if btn(BUTTONS.UP) and Player.inverse_air_time > 0 then
        Player.vel.y = Player.vel.y + PHYSICS.REDUCED_GRAVITY * delta
      else
        Player.vel.y = Player.vel.y + PHYSICS.GRAVITY_FORCE * delta
      end

      Player.inverse_air_time = Player.inverse_air_time - delta
    else
      Player.inverse_air_time = MAX_GRAVITY_REDUCT_TIME
    end
  else
    Player.vel.y = Player.vel.y + PHYSICS.REVERSED_GRAVITY_FORCE * delta
  end

  local is_colliding_horizontally = false
  if CW.is_set(BITS.COLLISION) then
    is_colliding_horizontally = collisions_update()
  end

  if not Player.is_dead then
    local steering_factor
    if Player.is_on_ground then
      steering_factor = 1.0
    else
      if CW.is_set(BITS.GRAVITY) then
        steering_factor = 0.6
      else
        steering_factor = 0.1
      end
    end
    if btn(BUTTONS.RIGHT) then
      Player.vel.x = math.clamp(Player.vel.x + PHYSICS.PLAYER_ACCELERATION * delta * steering_factor, -Player.speed, Player.speed)
    elseif btn(BUTTONS.LEFT) then
      Player.vel.x = math.clamp(Player.vel.x - PHYSICS.PLAYER_ACCELERATION * delta * steering_factor, -Player.speed, Player.speed)
    else
      if Player.is_on_ground then
        if math.abs(Player.vel.x) > 1 then
          local sign = Player.vel.x / math.abs(Player.vel.x)
          Player.vel.x = Player.vel.x - PHYSICS.PLAYER_DECCELERATION * sign * delta
          if math.abs(Player.vel.x) < 10 then -- at 10 pixels/s reduce to 0
            Player.vel.x = 0
          end
        end
      end
    end

    -- jump
    if Player.is_on_ground and btnp(BUTTONS.UP) then
      Player.vel = Player.vel:add(Vec:up():mul(PHYSICS.PLAYER_JUMP_FORCE))
      Player.is_on_ground = false
      AUDIO.play_note(0, "G#5", 2, 10)
    end
  end

  if math.abs(Player.vel.x) > 0 and is_colliding_horizontally then
    Player.vel.x = 0
  end

  if Player.vel.y > 0 and Player.is_on_ground then
    Player.vel.y = 0
  end

  Player.pos = Player.pos:add(Player.vel:mul(delta))
end

local run_animation_state = {
  switch_every = 0.2, -- seconds
  timer = 0,
  last_change_at = 0,
  current = 1,
  frames = { SPRITES.PLAYER.RUN_1, SPRITES.PLAYER.RUN_2 }
}

local idle_animation_state = {
  switch_every = 0.75, -- seconds
  last_change_at = 0,
  current = 1,
  frames = { SPRITES.PLAYER.IDLE_1, SPRITES.PLAYER.IDLE_2 }
}

function player_update(delta)
  update_player_physics(delta)

  -- Check is colliding with flag
  local player_occupied_tile = Player:collider_center():mul(1 / 8):floor()
  if fget(game_mget(player_occupied_tile), FLAGS.IS_WIN) then
    if not UI.TRANSITION then
      UI.enter(function ()
        CURRENT_LEVEL = CURRENT_LEVEL + 1
      end)
    end
  end

  -- Animations
  if not Player.is_dead then
    local x = math.abs(Player.vel.x)
    if not Player.is_on_ground then
      Player.current_sprite = SPRITES.PLAYER.IN_AIR
    elseif math.abs(Player.vel.x) > 1 then
      run_animation_state.timer = run_animation_state.timer + (0.05 * delta * math.abs(Player.vel.x))
      if run_animation_state.timer - run_animation_state.last_change_at > run_animation_state.switch_every then
        run_animation_state.current = 1 + ((run_animation_state.current + 2) % #run_animation_state.frames)
        run_animation_state.last_change_at = run_animation_state.timer
      end
      Player.current_sprite = run_animation_state.frames[run_animation_state.current]
    else
      if T - idle_animation_state.last_change_at > idle_animation_state.switch_every then
        idle_animation_state.current = 1 + ((idle_animation_state.current + 2) % #idle_animation_state.frames)
        idle_animation_state.last_change_at = T
      end
      Player.current_sprite = idle_animation_state.frames[idle_animation_state.current]
    end
  end
end

function game_render()
  local offset = LEVELS.current_offset()
  map(offset.x, offset.y)

  -- needs to be made persistent between frames
  local flip = 0
  if Player.vel.x < -0.01 and not Player.is_dead then
    flip = 1
  end
  spr(Player.current_sprite, Player.pos.x, Player.pos.y, 0, 1, flip, 0, 2, 2)
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
      update = function()
        for i = 0,31 do
          if btnp(i) then
            AUDIO.play_note(0, "C-4", 8)
            AUDIO.play_note(0, "E-4", 8)
            AUDIO.play_note(0, "G-4", 8)
            AUDIO.play_note(0, "B-4", 8)
            AUDIO.play_note(0, "D-4", 8)
            AUDIO.play_note(0, "G-4", 8)
            AUDIO.play_note(0, "C-5", 8)

            UI.enter(2)
          end
        end
      end,

      render = function()
        UiLabel
          :new()
          :with_xy(0, 8)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_text("UNEXPECTED MEMORY CORRUPTION")
          :with_color(10)
          :with_letter_spacing(1.2)
          :with_centered()
          :render()

        UiLabel
          :new()
          :with_xy(0, 40)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_line("Use $1, $2 and $0 to move.\n")
          :with_line("Use $3, $4 and $5 to modify control bits and change game's behavior.\n")
          :with_line("Discover what each bit does, find your way out and have fun!")
          :render()

        UiLabel
          :new()
          :with_xy(0, SCR_HEIGHT - 12)
          :with_wh(SCR_WIDTH, SCR_HEIGHT)
          :with_text("press any button to start")
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
    },

    -- Screen: Game
    [2] = {
      update = function()
        if btnp(4) then
          if CW.is_set(UI.VARS.SEL_CWORD_BIT) then
            AUDIO.play_note(0, "D#5", 2, 10)
            AUDIO.play_note(0, "C#5", 2, 10)
          else
            AUDIO.play_note(0, "C#5", 2, 10)
            AUDIO.play_note(0, "D#5", 2, 10)
          end

          CW.toggle(UI.VARS.SEL_CWORD_BIT)
        end

        if btnp(6) then
          UI.VARS.SEL_CWORD_BIT = (UI.VARS.SEL_CWORD_BIT - 1) % 8
        end

        if btnp(7) then
          UI.VARS.SEL_CWORD_BIT = (UI.VARS.SEL_CWORD_BIT + 1) % 8
        end
      end,
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
        game_init()
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
    screen.update()
  end
end

function UI.render()
  local screen = UI.SCREENS[UI.SCREEN]

  if screen.render then
    screen.render()
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

-------------
-- UiLabel --

UiLabel = {}
UiLabel.__index = UiLabel

function UiLabel:new()
  return setmetatable({
    xy = Vec.new(0, 0),
    wh = nil,
    text = "",
    color = 12,
    letter_spacing = 0,
    centered = false,
    wavy = false,
  }, UiLabel)
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
        0,
        next_note.volume
      )
    end
  end
end

function AUDIO.play_note(sfx_id, note, duration, volume)
  local started_at

  volume = volume or 15

  if #AUDIO.QUEUED_NOTES == 0 then
    sfx(sfx_id, note, duration, 0, volume)
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

function TIC()
  local delta = seconds() - T
  T = seconds()

  UI.update()

  cls()

  if UI.SCREEN > 1 then
    game_render()
    game_update(delta)
    hud_render()
  end

  UI.render()
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
-- 002:0000000000000900000009000009999900990000009902020099020000990200
-- 003:0000000000000000000000009999990000000900000009002000090002000900
-- 004:0000000000000000000009000000090000099999009900000099020200990200
-- 005:0000000000000000000000000000000099999900000009000000090020000900
-- 006:0000000000000700000007000007777700770000007702020077020000770200
-- 007:0000000000000000000000007777770000000700000007002000070002000700
-- 008:0000000000000700000007000007777700770000007702020077020000770200
-- 009:0000000000000000000000007777770000000700000007002000070002000700
-- 010:0000040000000400000444440044000000440202004402000044020000440200
-- 011:0000000000000000444444000000040000000400200004000200040020000400
-- 012:0000eeee000eeeee00eeeeee00eeeeee0eeeeeee0ee000e0eee0e0e0eee000e0
-- 013:eeee0000eeeee000eeeeee00eeeeee00eeeeeee0e000eee0e0e0eeeee000eeee
-- 018:0099020000990202009900000009999900009990000099000000900000009900
-- 019:2000090000000900000009009999990000099900000990000009000000099000
-- 020:0099020000990200009902020099000000099999000099900000900000009900
-- 021:0200090020000900000009000000090099999900000999000009000000099000
-- 022:0077020000770202007700000007777700007700000070000000770000000000
-- 023:2000070000000700000007007777770000077700000770000007000000077000
-- 024:0077020000770202007700000007777700007770000077000000700000007700
-- 025:2000070000000700000007007777770000077000000700000007700000000000
-- 026:0044020200440000000444440000440000004000000040000000400000000000
-- 027:0000040000000400444444000004400000040000000400000004000000000000
-- 028:eee00ee0eee0e0e0eee0e0e0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
-- 029:e0eeeeeee0eeeeeee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
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
-- 069:0000000000000000000000000002200000022222000222220002222200000222
-- 070:0000000000000000000000002244000022440000224400002244000000440000
-- 086:0044000000440000004400000044000000440000004400000044000000440000
-- 224:0000000000000444000444440044400400440000004440040044444400444444
-- 225:0000000044444400444444404444444044444440400044404000040044044400
-- 240:0000444400004404000444440004444400000444000004040000040400000000
-- 241:4444440004444400444444004444400044440000404040004040400000000000
-- 242:0000000066000000006606660000666606660676000006660006600000600000
-- 243:0000000000000066666066006766000066606660666000000006600000000600
-- </TILES>

-- <SPRITES>
-- 000:eeeeeee0eeeceeefeeccceefecececefeeeceeefeeeceeefeeeeeeef0fffffff
-- 001:eeeeeee0eeeceeefeeceeeefecccccefeeceeeefeeeceeefeeeeeeef0fffffff
-- 002:eeeeeee0eeeceeefeeeeceefecccccefeeeeceefeeeceeefeeeeeeef0fffffff
-- 003:eeeeeee0eeccceefeceeecefecccccefeceeecefeceeecefeeeeeeef0fffffff
-- 004:eeeeeee0eeecccefeeceeeefeeeceeefeeeeceefeccceeefeeeeeeef0fffffff
-- 005:eeeeeee0ecccccefeeeeceefeeeceeefeeceeeefecccccefeeeeeeef0fffffff
-- </SPRITES>

-- <MAP>
-- 001:323222323232323232323232323232323232323232323232323232323232121212121212121212121212121212121212121212121212121212121212000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:320000000000000000000000000000000000000000000000000000000032120000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:320000000000000000000082000000000000003232320000000000000032120000000000000000000012000000000000001212120000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:3200000000000000004252830092a292a2920082425232000000546400321200546400000000001212120092a292a292001212121200000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:3222000000000000004353627293a393a3933283435332320000556500321200556500000000001212121293a393a393121212121212000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:323232323232323232323232323232323232323232323232323232323232121212121212121212121212121212121212121212121212121212121212000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:323232323232323232323232323232323232323232323232323232323232121212121212121212121212121212121212121212121212121212121212000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:323232323232323232323232323232323232323232323232323232323232121212121212121212121212121212121212121212121212121212121212000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:323232323232323232323232323232323232323232323232323232323232121212121212121212121212121212121212121212121212121212121212000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0d88ddddddd9dcc899633cccc99887ac
-- </WAVES>

-- <SFX>
-- 000:020f0201020f02000201020e02010200020e02010200020e02020200020f02010201020e02000201020f020002020201020e02000201020f02000201300000000000
-- </SFX>

-- <FLAGS>
-- 000:00000000000000000000000000000000000000000000000000000000000000000010101010101010100000000000000000000000101000001000000000000000000000000020200000000000000000000000000000202000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

