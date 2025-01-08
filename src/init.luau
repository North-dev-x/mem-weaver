--!strict
--!optimize 2
local mod = {}

local config = {
	dyn_alloc = true;
}

local function trim(str)
	local trimmed, num = string.gsub(str, "[%c%p%s]", "")
	return trimmed
end

local cbor = require(script.CBOR)

type map<K,V> = {[K]: V}
type arr<V> = {V}

type buf_data = 
	number 
| string 
| boolean 
| map<tbl_data,tbl_data>
| arr<tbl_data>
| Vector3 
| Vector2
| Vector3int16
| Vector2int16
| Color3
| CFrame

type tbl_data = 
	number 
| string 
| boolean 
| map<tbl_data,tbl_data>
| arr<tbl_data>

export type buf = {
	buf: buffer;
	buf_positional: any;
	realloc: (buf, number) -> buf;
	len: (buf) -> number;
	cursor: number;
	clone: (buf) -> buf;
	free: (buf) -> ();
	serialize: (buf) -> BufSendable;
	read: (buf) -> {buf_data};
	read_at: (buf,number) -> buf_data;
	write: (buf, buf_data) -> buf;
	write_at: (buf,number,buf_data) -> buf;
} 

--> CONSTANTS <--
local U8_MAX = 255
local U8_MIN = 0

local U16_MAX = 65535
local U16_MIN = 0

local U32_MAX = 4294967295
local U32_MIN = 0

----------------

function write_float(buf: buffer, cursor: number, num: number): number -- returns the buffer length allocation
	local decimals = tostring(num)
	local i = decimals:find(".")
	decimals = decimals:sub(i :: number + 1) -- theres probably a better way to check how long a float is

	if decimals:len() <= 7 then
		buffer.writef32(buf,cursor,num)
		return 4
	elseif decimals:len() > 7 then
		buffer.writef64(buf,cursor,num)
		return 8
	end
	return 0
end

function write_u(buf: buffer, cursor: number, num: number): number
	if num > U8_MIN and num < U8_MAX then
		buffer.writeu8(buf,cursor,num)
		return 1;
	elseif num > U16_MIN and num < U16_MAX then
		buffer.writeu16(buf,cursor,num)
		return 2;
	elseif num > U32_MIN and num < U32_MAX then
		buffer.writeu32(buf,cursor,num)
		return 4;
	else

		local encoded = cbor.encode(num)
		buffer.writestring(buf,cursor,encoded)
		return string.len(encoded);
	end

	--return 0
end



function write_bool(buf: buffer, cursor: number, bool: boolean)
	if bool then
		buffer.writeu8(buf,cursor,1)
	else
		buffer.writeu8(buf,cursor,0)
	end
end

function free(buf: buf)
	table.clear(buf);
end

function realloc(buf: buffer): (buffer, number)
	local newsize = math.floor(buffer.len(buf) * 2)
	local newbuf = buffer.create(newsize)
	buffer.copy(newbuf,0,buf)
	return newbuf, newsize
end

function try_write(buf: buffer, cursor: number, val: buf_data): (buffer, number, number)
	local allocated = 0;
	local success, result, newsize = pcall(function()
		if type(val) == "number" then
			if val % 1 ~= 0 then
				allocated = write_float(buf,cursor,val)
			elseif val >= 0 then
				allocated = write_u(buf,cursor,val)
			elseif val < 0 then
				allocated = write_u(buf,cursor,math.abs(val))
			end
		elseif type(val) == "string" then
			val = trim(val)

			buffer.writestring(buf,cursor,val,#val)
			allocated = val:len()
		elseif type(val) == "boolean" then
			write_bool(buf,cursor,val)
			allocated = 1;
		elseif type(val) == "table" then
			local success, encoded = pcall(cbor.encode,val)
			if not success then
				error("CBOR ERROR: \n                ".. encoded)
			end
			buffer.writestring(buf,cursor,encoded)
			allocated = #encoded
		elseif type(val) == "vector" then
			local alloc = 12;
			buffer.writef32(buf,cursor,val.X)
			buffer.writef32(buf,cursor + 4,val.Y)
			buffer.writef32(buf,cursor + 8,val.Z)
			allocated = alloc
		elseif typeof(val) == "Vector3" then
			local alloc = 12;
			buffer.writef32(buf,cursor,val.X)
			buffer.writef32(buf,cursor + 4,val.Y)
			buffer.writef32(buf,cursor + 8,val.Z)
			allocated = alloc
		elseif typeof(val) == "Vector3int16" then
			local alloc = 6;
			buffer.writei16(buf,cursor,val.X)
			buffer.writei16(buf,cursor + 2,val.Y)
			buffer.writei16(buf,cursor + 4,val.Z)
			allocated = alloc
		elseif typeof(val) == "Vector2int16" then
			local alloc = 4;
			buffer.writei16(buf,cursor,val.X)
			buffer.writei16(buf,cursor + 2,val.Y)
		elseif typeof(val) == "CFrame" then
			local alloc = 24;
			local pos = val.Position
			local axis = val:ToAxisAngle()
			local rx, ry, rz = axis.X, axis.Y, axis.Z
			buffer.writef32(buf,cursor,pos.X)
			buffer.writef32(buf,cursor + 4,pos.Y)
			buffer.writef32(buf,cursor + 8,pos.Z)
			buffer.writef32(buf,cursor + 12,rx)
			buffer.writef32(buf,cursor + 16,ry)
			buffer.writef32(buf,cursor + 20,rz)

			allocated = alloc
		elseif typeof(val) == "Vector2" then
			local alloc = 8;
			buffer.writef32(buf,cursor,val.X)
			buffer.writef32(buf,cursor + 4,val.Y)
			allocated = alloc
		elseif typeof(val) == "Color3" then
			local alloc = 3;
			buffer.writeu8(buf,cursor,math.floor(val.R * 255))
			buffer.writeu8(buf,cursor + 1,math.floor(val.G * 255))
			buffer.writeu8(buf,cursor + 2,math.floor(val.B * 255))
			allocated = alloc
		end
		return buf, buffer.len(buf)
	end)
	if not success then
		if type(result) == "string" and result:find("CBOR") then
			error(result)
		end
		if config.dyn_alloc then
			warn("Buffer memory overflowed, but dynamic reallocation is enabled.")
			return try_write(realloc(buf), cursor, val)
		end
		local err = result
		result = buf
		newsize = 0;
		error("BUFFER OVERFLOW: ".. result)
	end
	return result, allocated, newsize
end

function read(buf: buf): {buf_data}
	local tbl = {}
	for i, data in buf.buf_positional do
		table.insert(tbl,read_at(buf,i))
	end
	return tbl
end

--[[
	convert a buf_data's type into a 3 byte or less string to represent it
]]
function into_type(val: buf_data, size: number): string
	if type(val) == "number" then
		local sizestr = tostring(size * 8)
		local typestr = ""

		if val % 1 == 0 then
			if val >= 0 then
				typestr = "u" -- u for unsigned
			else
				typestr = "n" -- n for negative
			end
		else
			typestr = "f" -- float
		end
		return typestr..sizestr
	elseif typeof(val) == "Vector3" then return "ve3"
	elseif typeof(val) == "CFrame" then return "cfr"
	elseif typeof(val) == "Vector2" then return "ve2"
	elseif typeof(val) == "Color3" then return "cl3"
	elseif typeof(val) == "Vector3int16" then return "v3i"
	elseif typeof(val) == "Vector2int16" then return "v2i"
	end
	return typeof(val):sub(1,3)
end

function get_highest_key(tbl): number
	local highest = 0;
	for k,v in tbl do
		if k > highest then highest = k end
	end
	return highest
end


function clone(self: buf): buf
	local cloned = buffer.create(self:len())
	buffer.copy(cloned,0,self.buf,0)
	return frombuf(cloned,self.buf_positional)
end

function self_realloc(self: buf, newsize): buf
	if newsize < self:len() then return error("Reallocation must create a larger buffer than it started with.") end
	local newbuf = buffer.create(newsize)
	buffer.copy(newbuf,0,self.buf,0)
	self.buf = newbuf
	return self
end

function write(self: buf, val: buf_data): buf
	local newbuf: buffer?, allocated: number = try_write(self.buf,self.cursor,val)
	local new_cursor_pos = allocated + self.cursor
	local valtype = into_type(val, allocated)

	table.insert(self.buf_positional, {o = self.cursor, t = valtype}) 
	if self.cursor ~= new_cursor_pos then self.cursor = new_cursor_pos end
	if newbuf then self.buf = newbuf end;
	return self
end

function write_at(self: buf, key: number, val: buf_data): buf
	local overwriting = self.buf_positional[key]

	local cursor = if #self.buf_positional ~= 0 then #self.buf_positional else 1;
	if overwriting then
		cursor = overwriting.o;
	end
	local newbuf: buffer?, allocated: number = try_write(self.buf,cursor,val)
	local new_cursor_pos = allocated + cursor
	local valtype = into_type(val, allocated)
	self.buf_positional[key] = {o = cursor, t = valtype}
	if self.cursor < new_cursor_pos then self.cursor = new_cursor_pos end
	if newbuf then self.buf = newbuf end;
	return self
end

function read_at(self: buf, i: number): buf_data
	local buf = self.buf
	local len = buffer.len(buf)
	local pos_data = self.buf_positional
	local data = self.buf_positional[i]
	local cursor: number = data.o :: number
	local type: string = data.t :: string
	if type ~= "str" and buffer["read"..type] then
		return buffer["read"..type](buf,cursor)
	elseif type:sub(1,1) == "n" then
		local size = type:sub(2,3)
		if size == "72" then
			local k,v = next(pos_data, i)
			local count
			if k then
				count = (v.o) - cursor;
			end
			return -cbor.decode(buffer.readstring(buf,cursor,count or len - cursor))
		else
			return -buffer["readu"..size](buf,cursor)
		end
	elseif type == "u72" then
		local k,v = next(pos_data, i)
		local count
		if k then
			count = (v.o) - cursor;
		end
		return cbor.decode(buffer.readstring(buf,cursor,count or len - cursor))
	elseif type == "str" then
		local k,v = next(pos_data, i)
		local count
		if k then
			count = (v.o) - cursor;
		end
		return trim(buffer.readstring(buf,cursor,count or len - cursor))
	elseif type == "boo" then
		return (buffer.readu8(buf, cursor) == 1)
	elseif type == "tab" then
		local k,v = next(pos_data, i)
		local count
		if k then
			count = (v.o) - cursor;
		end
		local decoded = cbor.decode(buffer.readstring(buf, cursor, count or len - cursor))
		return decoded
	elseif type == "ve3" then
		local vec = Vector3.new(
			buffer.readf32(buf, cursor),
			buffer.readf32(buf, cursor + 4),
			buffer.readf32(buf, cursor + 8)
		)
		return vec
	elseif type == "v3i" then
		local vec = Vector3int16.new(
			buffer.readi16(buf, cursor),
			buffer.readi16(buf, cursor + 2),
			buffer.readi16(buf, cursor + 4)
		)
		return vec
	elseif type == "cfr" then
		local x = buffer.readf32(buf, cursor)
		local y = buffer.readf32(buf, cursor + 4)
		local z = buffer.readf32(buf, cursor + 8)
		local rx = buffer.readf32(buf, cursor + 12)
		local ry = buffer.readf32(buf, cursor + 16)
		local rz = buffer.readf32(buf, cursor + 20)

		local axis = Vector3.new(rx, ry, rz)
		local angle = axis.Magnitude

		return CFrame.fromAxisAngle(axis,angle) + Vector3.new(x,y,z)
	elseif type == "ve2" then
		local vec = Vector2.new(
			buffer.readf32(buf, cursor),
			buffer.readf32(buf, cursor + 4)
		)
		return vec
	elseif type == "v2i" then
		local vec = Vector2int16.new(
			buffer.readi16(buf, cursor),
			buffer.readi16(buf, cursor + 2)
		)
		return vec
	elseif type == "cl3" then
		local color = Color3.fromRGB(
			buffer.readu8(buf, cursor),
			buffer.readu8(buf, cursor + 1),
			buffer.readu8(buf, cursor + 2)
		)
		return color
	end
	return "null"
end


type BufSendable = {
	d: buffer;
	r: buffer;
}

--[[
	Serializes the buffer into a sendable format.
]]
function mod.serialize(buf: buf): BufSendable
	local encoded: string = cbor.encode(buf.buf_positional)
	local relational_buf: buffer = buffer.create(#encoded)
	buffer.writestring(relational_buf,0,encoded)
	return {
		d = buf.buf;
		r = relational_buf
	} :: BufSendable
end

--[[
	Deserializes the buffer from a sendable format into a buffer object.
]]
function mod.deserialize(buf: BufSendable): buf
	local positional = cbor.decode(buffer.readstring(buf.r,0,buffer.len(buf.r)))
	return frombuf(buf.d,positional); -- construct a buffer object from the typedata and the buffer itself
end

--[[
	Deserializes the buffer from a sendable format into its underlying data.
]]
function mod.deser_read(buf: BufSendable): {buf_data}
	local positional = cbor.decode(buffer.readstring(buf.r,0,buffer.len(buf.r)))
	return read({
		buf = buf.d;
		buf_positional = positional;
	} :: buf)
end

--[[
	Returns the size of a given data type in bytes if it is supported.
]]
function mod.sizeof(t: buf_data): number
	if type(t) == "number" then
		if t % 1 == 0 then
			t = math.abs(t)
			if t > U8_MIN and t < U8_MAX then
				return 1;
			elseif t > U16_MIN and t < U16_MAX then
				return 2;
			elseif t > U32_MIN and t < U32_MAX then
				return 4;
			else
				return 9;
			end
		else
			local decimals = tostring(t)
			local i = decimals:find(".")
			decimals = decimals:sub(i :: number + 1)

			if decimals:len() <= 7 then
				return 4
			elseif decimals:len() > 7 then
				return 8
			end
		end
	elseif type(t) == "string" then return t:len();
	elseif type(t) == "table" then
		local encoded = cbor.encode(t)
		return string.len(encoded)
	elseif type(t) == "boolean" then return 1;
	elseif typeof(t) == "Color3" then return 3;
	elseif typeof(t) == "Vector3int16" then return 6;
	elseif typeof(t) == "Vector2int16" then return 4;
	elseif typeof(t) == "Vector3" then return 12;
	elseif typeof(t) == "Vector2" then return 8;
	elseif typeof(t) == "CFrame" then return 24;
	end
	return 0, error("Unsupported type: "..typeof(t))
end

function frombuf(toclone: buffer, positional): buf
	debug.setmemorycategory("buffers")
	local buf = buffer.create(buffer.len(toclone))
	buffer.copy(buf,0,toclone,0)
	return {
		buf = buf;
		buf_positional = positional;
		write = write;
		len = function(self: buf) return buffer.len(self.buf) end;
		realloc = self_realloc;
		read = read;
		read_at = read_at;
		write_at = write_at;
		cursor = buffer.len(buf);
		clone = clone;
		free = free;
		serialize = mod.serialize
	} :: buf
end

function new(_,byte_size: number): buf
	assert(byte_size % 1 == 0, "Expected integer, got floating point number "..byte_size)
	debug.setmemorycategory("buffers")

	return {
		buf = buffer.create(byte_size);
		buf_positional = {};
		write = write;
		len = function(self: buf) return buffer.len(self.buf) end;
		realloc = self_realloc;
		read = read;
		read_at = read_at;
		write_at = write_at;
		cursor = 0;
		clone = clone;
		free = free;
		serialize = mod.serialize
	} :: buf

end

return setmetatable(mod, {
	__call = new;
})