---------------
-- CONSTANTS --

-- TIC-80's screen width, in pixels
SCR_WIDTH = 240

-- TIC-80's screen height, in pixels
SCR_HEIGHT = 136

-- TIC-80 default font's char width, in pixels
CHR_WIDTH = 7

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
       UI_SEL_CWORD = 0
       ui_goto(2)
      -- TODO </>

      for i = 0,31 do
        if btnp(i) then
          UI_SEL_CWORD = 0
          ui_goto(2)
        end
      end
    end,

    render = function()
      print_corrupted("UNEXPECTED MEMORY CORRUPTION", 10, 10)
      print("Rules are simple:\nblah blah\nblah blah blah", 0, 40, 12)
      print_wavy("Press any key to start", SCR_HEIGHT - 15, 4)
    end,
  },

  -- Screen: Choosing control word
  [2] = {
    react = function()
      if btnp(2) then
        UI_SEL_CWORD = (UI_SEL_CWORD - 1) % 4
      end

      if btnp(3) then
        UI_SEL_CWORD = (UI_SEL_CWORD + 1) % 4
      end

      if btnp(4) then
        ui_goto(3)
      end
    end,
  },

  -- Screen: Modifying control word
  [3] = {
    react = function()
      if btnp(2) then
        UI_SEL_CWORD_BIT = (UI_SEL_CWORD_BIT - 1) % 8
      end

      if btnp(3) then
        UI_SEL_CWORD_BIT = (UI_SEL_CWORD_BIT + 1) % 8
      end

      if btnp(4) then
        cw_toggle(UI_SEL_CWORD, UI_SEL_CWORD_BIT)
        ui_goto(2)
      end

      if btnp(5) then
        ui_goto(2)
      end
    end,

    render = function()
      local modal_width = 180
      local modal_height = 40
      local modal_x = (SCR_WIDTH - modal_width) / 2
      local modal_y = (SCR_HEIGHT - modal_height) / 3

      rect(
        modal_x,
        modal_y,
        modal_width,
        modal_height,
        15
      )

      for bit_idx = 0,7 do
        local bit = cw_get(UI_SEL_CWORD, bit_idx) and 1 or 0
        local bit_x = modal_x + 22 + 18 * bit_idx
        local bit_y = modal_y + 15
        local bit_color

        if bit then
          bit_color = 5
        else
          bit_color = 2
        end

        -- Underline currently selected bit
        if bit_idx == UI_SEL_CWORD_BIT then
          bit_y = bit_y - 5
          rect(bit_x - 1, bit_y + 1.3 * CHR_HEIGHT, 1.8 * CHR_WIDTH, 1, 4)
        end

        print(bit, bit_x, bit_y, bit_color, true, 2)
      end
    end,
  },
}
-- [/Interface]

-----------------------
---- Control words ----
-----------------------

function cw_toggle(word_idx, bit_idx)
  bit_idx = 7 - bit_idx
  CWS[word_idx] = CWS[word_idx] ~ (1 << bit_idx)
end

function cw_get(word_idx, bit_idx)
  bit_idx = 7 - bit_idx
  return CWS[word_idx] & (1 << bit_idx) > 0
end

function print_corrupted(text, y, color)
  local x = (SCR_WIDTH - CHR_WIDTH * #text) / 2

  for i = 1, #text do
    local ch = text:sub(i, i)

    print(ch, x, y, color, true)

    for _ = 0,math.random(1,5) do
      pix(
        x + CHR_WIDTH / 2 + math.random(-8, 8),
        y + math.random(-8, 12),
        math.random(0, 15)
      )
    end

    x = x + CHR_WIDTH
  end
end

function print_wavy(text, y, color)
  local x = (SCR_WIDTH - CHR_WIDTH * #text) / 2

  for i = 1, #text do
    local ch = text:sub(i, i)

    print(
      ch,
      x,
      y + 3 * math.sin(i + time() / 150),
      color,
      true
    )

    x = x + CHR_WIDTH
  end
end

function board_render()
  -- TODO
end

function hud_render()
  function cw_render(word_idx)
    local text = string.format("%.2X", CWS[word_idx])
    local pos_x = 35 + 50 * word_idx
    local pos_y = SCR_HEIGHT - 18

    -- Underline currently selected word
    if word_idx == UI_SEL_CWORD then
      pos_y = pos_y - 5
      rect(pos_x, pos_y + CHR_HEIGHT * 1.5, 3 * CHR_WIDTH, 1, 4)
    end

    print(text, pos_x, pos_y, 12, true, 2)
  end

  rect(0, SCR_HEIGHT - 29, SCR_WIDTH, SCR_HEIGHT, 15)

  cw_render(0)
  cw_render(1)
end

function ui_goto(state)
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

function TIC()
  cls()
  ui_react()

  if UI_SCREEN > 1 then
    board_render()
    hud_render()
  end

  ui_render()
end

-- <TILES>
-- 001:eccccccccc888888caaaaaaaca888888cacccccccacc0ccccacc0ccccacc0ccc
-- 002:ccccceee8888cceeaaaa0cee888a0ceeccca0ccc0cca0c0c0cca0c0c0cca0c0c
-- 003:eccccccccc888888caaaaaaaca888888cacccccccacccccccacc0ccccacc0ccc
-- 004:ccccceee8888cceeaaaa0cee888a0ceeccca0cccccca0c0c0cca0c0c0cca0c0c
-- 017:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 018:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 019:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 020:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- </TILES>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000304000000000
-- </SFX>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
