## Config

`dyn_alloc`: Whether or not to use dynamic buffer reallocation.
This will cause the buffer to double in size every time it would overflow, rather than throwing an error.

`if dyn_alloc == false`
```luau
local alloc = require(mem-weaver)

local buf = alloc(2)
	:write(3000000) -- ERROR: BUFFER OVERFLOW
```

`if dyn_alloc == true
```luau
local alloc = require(mem-weaver)

local buf = alloc(2)
	:write(3000000) -- double memory size to 4;
	:write(328749) -- double memory size to 8
```

Dynamic reallocation can be convenient, but every time a buffer is reallocated it introduces slowdowns in the process. 
It is better to over-allocate than to under-allocate.
## Sizes
A reference of the size(in bytes) of all supported types.
#### float
`f32` - 
	Represents a floating-point value with 7 digits of precision.
	Takes up 4 bytes of space.
`f64` - 
	Represents a floating-point value with 15 digits of precision.
	Takes up 8 bytes of space.

#### int
`i8` - 
	Represents integers between -255 and 255. 
	Takes up 1 byte of space.
`i16` - 
	Represents integers between -65,535 and 65,535. 
	Takes up 2 bytes of space.
`i32` - 
	Represents integers between -4,294,967,295 and 4,294,967,295. 
	Takes up 4 bytes of space.
`i72 -
	Represents integers between -9,007,199,254,740,992 and 9,007,199,254,740,992.
	Takes up 9 bytes of space due to needing to be encoded as a CBOR string.
	
#### string
Equal in size to its length, i.e.
`"four"` is 4 characters and 4 bytes in length.
To get the length in bytes of any given string, use `string.len(str)`.

#### boolean
Represented by an i8, which takes up 1 byte of space.

#### table
Tables have a dynamic size at runtime, which is hard to keep track of.
Try to over-allocate at the start, and scale down until it overflows if you need precision.

#### Vector3
Vector3 is represented by 3 `f32`s, taking up 12 bytes of space.
#### Vector2
Vector2 is represented by 2 `f32`s, taking up 8 bytes of space.
#### CFrame
CFrame is represented by 6 `f32`s, taking up 24 bytes of space.

## Buffer Objects

#### Creation:

Call the module as a function, with a number of bytes to allocate.
```luau
local alloc = require(mem-weaver)

local buf = alloc(20) -- Create a buffer with a size of 20 bytes.
```

Buffer objects have the following interface:
#### write
```luau
function write(self: buf, val: buf_data): buf
```
Push `val` into the end of the buffer.
`val` must be one of the supported types.

Returns itself, so `write` can be chained like so:
```luau
local buf = alloc(8)
	:write(200) -- 1 byte i8
	:write("four") -- 4 byte string
	:write("two") -- 3 byte string
```

#### write_at
```luau
function write_at(self: buf, key: number, val: buf_data): buf
```
Replace the given `key` in the buffer with `val`.
Can be used to rewrite buffers that have already been written to.

If there is no key at `key` in the buffer, behaves functionally the same as `:write()`.

This can cause memory corruption if the amount of bytes you write to the `key` exceeds the amount of bytes it held before, due to it overflowing into the next key in the buffer.

###### Safe:
```luau
local buf = alloc(20)
	:write(Vector3.new(0,200,-30)) -- writes 12 bytes to position 1 in the buffer
	:write(math.pi) -- writes 8 bytes to position 2 in the buffer

-- rewrites position 1 in the buffer with another vector3
buf:write_at(1, Player.Character.HumanoidRootPart.Position)
```
###### Unsafe:
```luau
local buf = alloc(12)
	:write("this") -- writes 4 bytes to position 1 in the buffer
	:write(math.pi) -- writes 8 bytes to position 2 in the buffer

--[[ 
uh oh! we overwrite the string with a larger string, encroaching on 
the memory space that position 2 takes up, corrupting both pieces of memory
]]
buf:write_at(1, "Hello, world!)

-- Attempting to read the corrupted memory will give unpredictable results
print(buf:read()) -- outputs {[1] = "Hell", [2] = 3.174034971262635}
```


#### read
```luau
function read(buf: buf): {buf_data}
```
Dumps all the data in the buffer into a table and returns it.

#### read_at
```luau
function read_at(self: buf, i: number): buf_data
```
Returns the data from the buffer in the given position.

Buffer positions represent the order in which `:write()` was called.

Usage:
```luau
local buf = alloc(4)
	:write(true) -- 1
	:write(false) -- 2
	:write(false) -- 3
	:write(true) -- 4

print(buf:read_at(1)) -- true
print(buf:read_at(3)) -- false
```

#### realloc
```luau
function realloc(self: buf, new_size: number): buf
```
Reallocates the buffer to the new size, if it is larger than the current buffer size.
#### clone
```luau
function clone(self: buf): buf
```
Returns a deep copy of the buffer.

#### free
```luau
function free(self: buf): ()
```
Clears the buffer object, allowing it to be garbage collected.
It is recommended to call this when finished with any buffer.

#### serialize
```luau
function mod.serialize(buf: buf): BufSendable
```
Serializes the buffer into a network-sendable format.
This should always be used when sending a buffer over the network (RemoteEvent, RemoteFunction, UnreliableRemoteEvent)

Usage:
```luau
local buf = alloc(24)
	:write(chr.HumanoidRootPart.CFrame)

game.ReplicatedStorage.SomeEvent:FireServer(buf:serialize())
```

Can also be used by calling the module function: 
```luau
local buf = alloc(24)
	:write(chr.HumanoidRootPart.CFrame)

game.ReplicatedStorage.SomeEvent:FireServer(alloc.serialize(buf))
```

## Module Functions

#### serialize
```luau
function mod.serialize(buf: buf): BufSendable
```
Works the same as buf:serialize().

#### deserialize
```luau
function mod.deserialize(buf: BufSendable): buf
```
Deserializes a network-sendable buffer format into a new buffer object.

Usage:
```luau
local alloc = require(mem-weaver)

game.ReplicatedStorage.SomeEvent.OnServerEvent:Connect(function(plr, received)
	local buf = alloc.deserialize(received)
	print(buf:read())
end)
```

#### deser_read
```luau
function mod.deser_read(buf: BufSendable): {buf_data}
```
Deserializes a network-sendable buffer format into its underlying data.

Usage:
```luau
local alloc = require(mem-weaver)

game.ReplicatedStorage.SomeEvent.OnServerEvent:Connect(function(plr, received)
	print(alloc.deser_read(received))
end)
```

#### sizeof
```luau
function mod.sizeof(t: buf_data): number
```
Returns the size in bytes of the given data, if it is supported.

Has a high time complexity when used on tables.

