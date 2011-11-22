local bit = require'bit'

local base = 36
local tmin = 1
local tmax = 26
local skew = 38
local damp = 700
local initial_bias = 72
local initial_n = 0x80
local delimiter = 0x2D

 -- Bias adaptation function
local adapt = function(delta, numpoints, firsttime)
	if(firsttime) then
		delta = math.floor(delta / damp)
	else
		delta = bit.rshift(delta, 1)
	end

	delta = delta + math.floor(delta / numpoints)

	local k = 0
	while(delta > math.floor(((base - tmin) * tmax) / 2)) do
		delta = math.floor(delta / (base - tmin))
		k = k + base
	end

	return math.floor(k + (base - tmin + 1) * delta / (delta + skew))
end

local punycode_encode
do
	-- tests whether cp is a basic code point:
	local basic = function(cp)
		return cp < 0x80
	end

	-- returns the basic code point whose value
	-- (when used for representing integers) is d, which needs to be in
	-- the range 0 to base-1.
	local encode_digit = function(d)
		return d + 22 + 75 * (d < 26 and 1 or 0)
		--  0..25 map to ASCII a..z
		-- 26..35 map to ASCII 0..9
	end

	local offset = {0, 0x3000, 0xE0000, 0x3C00000}
	local utf8code = function(U, ...)
		local numBytes = select('#', ...)
		for i=1, numBytes do
			local b = select(i, ...)
			U = bit.lshift(U, 6) + bit.band(b, 63)
		end

		return U - offset[numBytes + 1]
	end

	local toUCS4 = function(str)
		local out = {}
		for c in str:gmatch'([%z\1-\127\194-\244][\128-\191]*)' do
			table.insert(out, utf8code(string.byte(c, 1, -1)))
		end

		return out
	end

	function punycode_encode(input)
		if(type(input) == 'string') then
			input = toUCS4(input)
		end

		local output = {}

		-- Initialize the state
		local n = initial_n
		local delta = 0
		local bias = initial_bias

		-- Handle the basic code poinst
		for j = 1, #input do
			local c = input[j]
			if(basic(c)) then
				table.insert(output, string.char(c))
			end
		end

		local h = #output
		local b = h

		-- h is the number of code points that have been handled, b is the
		-- number of basic code points.

		if(b > 0) then
			table.insert(output, string.char(delimiter))
		end

		-- Main encoding loop
		while(h < #input) do
			-- All non-basic code points < n have been
			-- handled already.  Find the next larger one
			local m = math.huge
			for j = 1, #input do
				local c = input[j]
				if(c >= n and c < m) then
					m = c
				end
			end

			delta = delta + (m - n) * (h + 1)
			n = m

			for j = 1, #input do
				local cp = input[j]
				if(cp < n) then
					delta = delta + 1
				end

				if(cp == n) then
					local q = delta
					local k = base
					while(true) do
						local t
						if(k <= bias) then
							t = tmin
						else
							if(k >= bias + tmax) then
								t = tmax
							else
								t = k - bias
							end
						end

						if(q < t) then break end

						table.insert(output, string.char(encode_digit(t + (q - t) % (base - t))))
						q = math.floor((q - t) / (base - t))

						k = k + base
					end

					table.insert(output, string.char(encode_digit(q)))
					bias = adapt(delta, h + 1, h == b)
					delta = 0
					h = h +1
				end
			end

			delta = delta + 1
			n = n + 1
		end

		return table.concat(output)
	end
end

local idn_encode
do
	function idn_encode(domain)
		local labels = {}
		for label in domain:gmatch('([^.]+)%.?') do
			-- Domain names can only consist of a-z, A-Z, 0-9, - and aren't allowed
			-- to start or end with a hyphen
			local first, last = label:sub(1, 1), label:sub(2, 2)
			if(first == '-' or last == '-') then
				return nil, 'Invalid DNS label'
			end

			if(label:match('^[a-zA-Z0-9-]+$')) then
				table.insert(labels, label)
			elseif(label:sub(1,1) ~= '-' and label:sub(2,2) ~= '-') then
				local plabel = punycode_encode(label)
				table.insert(labels, string.format('xn--%s', plabel))
			end
		end

		return table.concat(labels, '.')
	end
end

return {
	encode = idn_encode,

	punycode = {
		encode = punycode_encode,
	},
}
