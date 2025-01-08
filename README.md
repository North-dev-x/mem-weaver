`mem-weaver` is a low(ish)-level, strictly-typed module for creating, writing to, reading from, serializing, and deserializing buffers over the network.

Buffers can make events fire faster due to using less bandwidth.

## Supported Types
The buffers fully support the following types:
- float (32 and 64)
- integer
	Supported with 8, 16, and 32 bit integers.
	64 bit integers *are* supported, but they have to be encoded as a string, 
	which takes up an extra byte (9 bytes instead of 8).
- string
	 Strings only support ASCII characters.
- boolean
- tables
	Tables only support simple datatypes, Vector3, Vector2, and CFrame are not supported within tables.
- Vector3
- Vector3int16
- Vector2
- Vector2int16
- Color3
- CFrame

## Usage
The module revolves around the creation of buffer objects.
Buffer objects hold a set amount of memory at runtime.

Usage example:
```luau
-- CLIENT --
local alloc = require(mem-weaver)

local buf = alloc(8) -- Creates a buffer with 8 bytes of space.
	:write(3000) -- 2 bytes, 16 bit integer
	:write("four") -- 4 bytes, 4 character string
	:write(true) -- 1 byte, boolean
	:write(3) -- 1 byte, 8 bit integer

print(buf:read()) -- {[1] = 3000, [2] = "four", [3] = true, [4] = 3}
print(buf:read_at(3)) -- true

-- Serialize the buffer into a network-sendable format.
game.ReplicatedStorage.ExampleRemote:FireServer(buf:serialize())
buf:free() -- Remember to free your buffer!

-- SERVER --
local alloc = require(mem-weaver)

game.ReplicatedStorage.ExampleRemote.OnServerEvent:Connect(function(plr, received)
	-- Deserialize the received buffer into a buffer object.
	local buf = alloc.deserialize(received)
	print(buf:read()) -- {[1] = 3000, [2] = "four", [3] = true, [4] = 3}
	buf:free()
end)
```


## Documentation
Read more [here.](Docs.md)
