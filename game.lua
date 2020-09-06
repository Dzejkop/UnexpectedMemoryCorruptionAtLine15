-------------------
-- Debug helpers --
-------------------
-- to be removed
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
-- CONSTANTS --

-- TIC-80's screen width, in pixels
SCR_WIDTH = 240

-- TIC-80's screen height, in pixels
SCR_HEIGHT = 136

-- TIC-80 default font's char width, in pixels
CHR_WIDTH = 10

-- TIC-80 default font's char height, in pixels
CHR_HEIGHT = 10

----------------
-- GAME STATE --

-- [Control words]
--- Creates a new control word from given bits.
--- Accepts bits in big-endian order.
function cw(b0, b1, b2, b3, b4, b5, b6, b7)
  return b0 << 7 | b1 << 6 | b2 << 5 | b3 << 4 | b4 << 3 | b5 << 2 | b6 << 1 | b7;
end

CWS = {
  [0] = cw(0, 0, 0, 0, 0, 0, 0, 1),
  [1] = cw(0, 0, 0, 0, 0, 0, 0, 0),
}
-- [/Control words]

-- [Interface]
-- Index of currently selected control word; 0..1 or `nil`
UI_SEL_CWORD = nil

-- Index of currently selected control word's bit; 0..7
UI_SEL_CWORD_BIT = 0

-- Index of currently active UI screen; see `UI_SCREENS`
UI_SCREEN = 1

UI_SCREENS = {
  -- Screen: Introduction
  [1] = {
    react = function()
      -- TODO <remove before deploying>
      -- UI_SEL_CWORD = 0
      -- ui_goto(2)
      -- TODO </>
      for i = 0,31 do
        if btnp(i) then
          UI_SEL_CWORD = 0
          ui_goto(2)
        end
      end
    end,

    render = function()
      print_centered("UNEXPECTED MEMORY CORRUPTION", 10, 10)
      print("Rules are simple:\nblah blah\nblah blah blah", 0, 40, 12)
      print_wavy("Press any key to start", SCR_HEIGHT - 15, 4)
    end,
  },

  -- Screen: Choosing control word
  [2] = {
    react = function()
      if btnp(4) then
        cw_toggle(UI_SEL_CWORD, UI_SEL_CWORD_BIT)
      end

      if btnp(6) then
        UI_SEL_CWORD_BIT = UI_SEL_CWORD_BIT - 1

        if UI_SEL_CWORD_BIT < 0 then
          UI_SEL_CWORD_BIT = 7
          UI_SEL_CWORD = (UI_SEL_CWORD - 1) % 2
        end
      end

      if btnp(7) then
        UI_SEL_CWORD_BIT = UI_SEL_CWORD_BIT + 1

        if UI_SEL_CWORD_BIT > 7 then
          UI_SEL_CWORD_BIT = 0
          UI_SEL_CWORD = (UI_SEL_CWORD + 1) % 2
        end
      end
    end,
  }
}
-- [/Interface]

----------------------
---- Control Word ----
----------------------

function cw_toggle(word_idx, bit_idx)
  bit_idx = 7 - bit_idx
  CWS[word_idx] = CWS[word_idx] ~ (1 << bit_idx)
end

function cw_get(word_idx, bit_idx)
  bit_idx = 7 - bit_idx
  return CWS[word_idx] & (1 << bit_idx) > 0
end

-------------
---- HUD ----
-------------

function hud_render()
  local hud_h = 24
  local hud_y = SCR_HEIGHT - hud_h

  function cw_render(x, word_idx)
    local y = hud_y + (hud_h - CHR_HEIGHT) / 2;

    for bit_idx = 0,7 do
      local bit = cw_get(word_idx, bit_idx) and 1 or 0
      local bit_color

      if bit == 1 then
        bit_color = 5
      else
        bit_color = 13
      end

      local bit_x = x
      local bit_y = y

      if word_idx == UI_SEL_CWORD and bit_idx == UI_SEL_CWORD_BIT then
        bit_y = bit_y - 3
        rect(bit_x, bit_y + 1.5 * CHR_HEIGHT, CHR_WIDTH, 1, 4)
      end

      print(bit, bit_x, bit_y, bit_color, true, 2)

      x = x + CHR_WIDTH + 2
    end
  end

  rect(0, hud_y, SCR_WIDTH, hud_h, 15)

  cw_render(10, 0)
  cw_render(SCR_WIDTH - 104, 1)
end

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

function Vec.trace(self, name)
  name = (name .. " = ") or ""
  trace(name .. "{ x = " .. self.x .. ", y = " .. self.y .. " }")
end

-----------------
---- Enemies ----
-----------------
ENEMIES = {
  LOST_SOUL = 1
}

enemies = {}

-----------------
---- Sprites ----
-----------------

SPRITES = {
  PLAYER = {
    IDLE_1 = 2,
    IDLE_2 = 4,
    RUN_1 = 6,
    RUN_2 = 8,
    IN_AIR = 10
  },
  LOST_SOUL = {
    FLYING = 224,
  }
}

----------------------
---- Enemy states ----
----------------------
STATES = {
  LOST_SOUL = {
    FLYING = 1
  }
}

----------------
---- Player ----
----------------

Player = {
  pos = Vec.new(30, 30),
  vel = Vec.new(0, 0),
  current_sprite = SPRITES.PLAYER.IDLE,
  speed = 1,
  collider = {
    offset = Vec.new(2, 3),
    size = Vec.new(11, 13)
  },
  is_on_ground = false
}

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
  IS_GROUND = 0
}

function lost_soul_handler(obj)
  if obj.state == LOST_SOUL_FLYING then
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

function game_init()
  enemies[1] = {
    type = LOST_SOUL,
    state = STATES.LOST_SOUL.FLYING,
    pos = Vec.new(10, 32),
    acc = Vec.new(0.07, 0.2),
    vel = Vec.new(0, 0),
    max_vel = Vec.new(3, 1.1),
    current_sprite = SPRITES.LOST_SOUL.FLYING,
    state = LOST_SOUL_FLYING,
    handler = lost_soul_handler
  }

  enemies[2] = {
    type = LOST_SOUL,
    state = STATES.LOST_SOUL.FLYING,
    pos = Vec.new(10, 48),
    acc = Vec.new(0.02, 0.1),
    vel = Vec.new(0, 0),
    max_vel = Vec.new(2.5, 1.1),
    current_sprite = SPRITES.LOST_SOUL.FLYING,
    state = LOST_SOUL_FLYING,
    handler = lost_soul_handler
  }
end

function find_tiles_below_collider()
  local collider_pos = Player.pos:add(Player.collider.offset)
  local below_left = collider_pos:add(Vec.down():mul(Player.collider.size.y))
  local below_right = collider_pos:add(Player.collider.size)

  below_left = below_left:mul(1 / 8):floor()
  below_right = below_right:mul(1 / 8):floor()

  return { below_left, below_right } -- NOTE: both could be the same tile
end

function game_update()
  -- go through enemies
  for i, v in ipairs(enemies) do
    spr(v.current_sprite, v.pos.x, v.pos.y, 0, 1, 0, 0, 2, 2)
    v.handler(v)
  end

  -- apply gravity
  if not Player.is_on_ground then
    Player.vel.y = Player.vel.y + 0.1
  end

  if btn(BUTTONS.RIGHT) then
    Player.vel.x = math.clamp(Player.vel.x + 0.1, -Player.speed, Player.speed)
  elseif btn(BUTTONS.LEFT) then
    Player.vel.x = math.clamp(Player.vel.x - 0.1, -Player.speed, Player.speed)
  else
    Player.vel.x = Player.vel.x * 0.7
  end

  -- Check for collisions with floor
  local tiles_below_player = find_tiles_below_collider()

  function is_tile_ground(tile)
    return fget(mget(tile.x, tile.y), FLAGS.IS_GROUND)
  end

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

  -- jump
  if Player.is_on_ground and btnp(BUTTONS.UP) then
    Player.vel = Player.vel:add(Vec:up():mul(2))
    Player.is_on_ground = false
  end

  -- Animations
  if not Player.is_on_ground then
    Player.current_sprite = SPRITES.PLAYER.IN_AIR
  elseif math.abs(Player.vel.x) > 0.01 then
    if math.floor(time() * 0.01) % 2 == 0 then
      Player.current_sprite = SPRITES.PLAYER.RUN_1
    else
      Player.current_sprite = SPRITES.PLAYER.RUN_2
    end
  else
    if math.floor(time() * 0.001) % 2 == 0 then
      Player.current_sprite = SPRITES.PLAYER.IDLE_1
    else
      Player.current_sprite = SPRITES.PLAYER.IDLE_2
    end
  end

  Player.pos = Player.pos:add(Player.vel)
end

function game_render()
  map()

  -- needs to be made persistent between frames
  local flip = 0
  if Player.vel.x < -0.01 then
    flip = 1
  end
  spr(Player.current_sprite, Player.pos.x, Player.pos.y, 0, 1, flip, 0, 2, 2)
end

------------
---- UI ----
------------

function ui_goto(state)
  if state == 2 then
    game_init()
  end
  UI_SCREEN = state
end

function ui_react()
  local screen = UI_SCREENS[UI_SCREEN]

  if screen.react then
    screen.react()
  end
end

function ui_render()
  local screen = UI_SCREENS[UI_SCREEN]

  if screen.render then
    screen.render()
  end
end

function print_centered(text, y, color)
  local x = (SCR_WIDTH - 0.6 * CHR_WIDTH * #text) / 2
  print(text, x, y, color, true)
end

function print_wavy(text, y, color)
  local x = (SCR_WIDTH - 0.7 * CHR_WIDTH * #text) / 2

  for i = 1, #text do
    local ch = text:sub(i, i)

    print(
      ch,
      x,
      y + 3 * math.sin(i + time() / 150),
      color,
      true
    )

    x = x + 0.7 * CHR_WIDTH
  end
end

----------------
---- System ----
----------------

function TIC()
  cls()
  ui_react()

  if UI_SCREEN > 1 then
    game_render()
    game_update()
    hud_render()
  end

  ui_render()
end

function SCN(line)
  poke(0x3FF9, 0)

  if UI_SCREEN == 1 then
    if line < 30 then
      if math.random() < 0.1 then
        poke(0x3FF9, math.random(-8, 8))
      end
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
-- 010:0000070000000700000777770077000000770202007702000077020000770200
-- 011:0000000000000000777777000000070000000700200007000200070020000700
-- 018:0099020000990202009900000009999900009990000099000000900000009900
-- 019:2000090000000900000009009999990000099900000990000009000000099000
-- 020:0099020000990200009902020099000000099999000099900000900000009900
-- 021:0200090020000900000009000000090099999900000999000009000000099000
-- 022:0077020000770202007700000007777700007700000070000000770000000000
-- 023:2000070000000700000007007777770000077700000770000007000000077000
-- 024:0077020000770202007700000007777700007770000077000000700000007700
-- 025:2000070000000700000007007777770000077000000700000007700000000000
-- 026:0077020200770000000777770000770000007000000070000000700000000000
-- 027:0000070000000700777777000007700000070000000700000007000000000000
-- 033:3333333332222221322222213222222132222221322222213222222111111111
-- 034:5555555556666667566666675666666756666667566666675666666777777777
-- 035:aaaaaaaaa9999998a9999998a9999998a9999998a9999998a999999888888888
-- 065:6666666666666666660000006600000066000000660000006600000066000000
-- 066:6666666666666666000000000000000000000000000000000000000000000000
-- 067:6666666666666666000000000000000000000000000000000000000000000000
-- 068:6666666666666666000000660000006600000066000000660000006600000066
-- 081:6600000066000000660000006600000066000000660000006600000066000000
-- 084:0000006600000066000000660000006600000066000000660000006600000066
-- 097:6600000066000000660000006600000066000000660000006666666666666666
-- 098:0000000000000000000000000000000000000000000000006666666666666666
-- 099:0000000000000000000000000000000000000000000000006666666666666666
-- 100:0000006600000066000000660000006600000066000000666666666666666666
-- 224:0000000000000444000444440044400400440000004440040044444400444444
-- 225:0000000044444400444444404444444044444440400044404000040044044400
-- 240:0000444400004404000444440004444400000444000004040000040400000000
-- 241:4444440004444400444444004444400044440000404040004040400000000000
-- </TILES>

-- <MAP>
-- 001:323222323232323232323232323232323232323232323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:320000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:320000000000000000000000000000000000003232320000000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:320000000000000000000000000000000000003232323200000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:322200000000000000000000000000000000323232323232000000000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:323232323232323232323232323232323232323232323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:323232323232323232323232323232323232323232323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:323232323232323232323232323232323232323232323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:323232323232323232323232323232323232323232323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000304000000000
-- </SFX>

-- <FLAGS>
-- 000:00000000000000000000000000000000000000000000000000000000000000000010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

