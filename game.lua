-- title:  game title
-- author: game developer
-- desc:   short description
-- script: lua

--------------------------------------
---------------- Config---------------
--------------------------------------

Config = {
	runGame = false
}

--------------------------------------
------------------ Dir ---------------
--------------------------------------

Dir = {
	Up = 0,
	Right = 1,
	Down = 2,
	Left = 3,
	MAX = 4
}

function Dir.toOffset(self)
	if self == Dir.Up then
		return Vec.new(0, -1)
	elseif self == Dir.Right then
		return Vec.new(1, 0)
	elseif self == Dir.Down then
		return Vec.new(0, 1)
	elseif self == Dir.Left then
		return Vec.new(-1, 0)
	else
		return nil
	end
end

--------------------------------------
------------------ Vec ---------------
--------------------------------------

Vec = {}

function Vec.new(x, y)
	local v = { x = x, y = y }
	setmetatable(v, {__index = Vec})
	return v
end

function Vec.add(self, other)
	return Vec.new(self.x + other.x, self.y + other.y)
end

function Vec.mult(self, factor)
	return Vec.new(self.x * factor, self.y * factor)
end

function Vec.eq(self, other)
	return (self.x == other.x) and (self.y == other.y)
end

function rotateClockwise(dir)
	return (dir + 1) % Dir.MAX
end

function rotateCounter(dir)
	return (dir - 1) % Dir.MAX
end

--------------------------------------
--------------- Game Code ------------
--------------------------------------

function TIC()
	if not Config.runGame then
		return
	end

	cls()
end

--------------------------------------
----------------- Tests --------------
--------------------------------------

function TESTS()
	cls()

	-- Dirs
	assert(
		rotateClockwise(Dir.Up)
		==
		Dir.Right
	)
	assert(
		rotateClockwise(Dir.Down)
		==
		Dir.Left
	)
	assert(
		rotateCounter(Dir.Up)
		==
		Dir.Left
	)

	-- Dir -> Offset
	assert(
		Dir.toOffset(Dir.Up)
		:eq(Vec.new(0, -1))
	)
end

TESTS()

-- <TILES>
-- 001:eccccccccc888888caaaaaaaca888888cacccccccacc2ccccacc2ccccacc2ccc
-- 002:ccccceee8888cceeaaaa0cee888a0ceeccca0ccc2cca0c0c2cca0c0c2cca0c0c
-- 003:eccccccccc888888caaaaaaaca888888cacccccccacccccccacc2ccccacc2ccc
-- 004:ccccceee8888cceeaaaa0cee888a0ceeccca0cccccca0c0c2cca0c0c2cca0c0c
-- 017:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 018:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 019:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 020:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 033:2200002220000002000000000000000000000000000000002000000222000022
-- 200:0000000000002000000222000022220000222000002220000002200000000000
-- </TILES>

-- <SPRITES>
-- 000:0002200000022000002222000022220002222220022222200022220000022000
-- 001:0002200000222200002222000022220000022000000000000000000000000000
-- 002:0002200000022000000220000000000000000000000000000000000000000000
-- </SPRITES>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200200000000000
-- 001:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005000000000
-- 002:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005000000000
-- </SFX>

-- <PATTERNS>
-- 000:400006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:400006500006100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:100000100000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2e26c86333c57
-- </PALETTE>

