-- NEW MODULE: Buffer handling utilities for Hydroxide (2024+)
-- Provides enhanced support for Roblox Buffer data type

local methods = {}

local function bufferToString(bufferData)
    if typeof(bufferData) ~= "buffer" then
        return tostring(bufferData)
    end
    
    local length = buffer.len(bufferData)
    if length == 0 then
        return "buffer.create(0) -- Empty buffer"
    end
    
    -- For small buffers, show hex representation
    if length <= 32 then
        local hexString = ""
        for i = 0, length - 1 do
            local byte = buffer.readu8(bufferData, i)
            hexString = hexString .. string.format("%02X ", byte)
        end
        return "buffer (" .. length .. " bytes): " .. hexString
    else
        -- For large buffers, just show size
        return "buffer.create(" .. length .. ") -- " .. length .. " bytes"
    end
end

local function bufferToHex(bufferData, maxBytes)
    if typeof(bufferData) ~= "buffer" then
        return ""
    end
    
    maxBytes = maxBytes or 256
    local length = math.min(buffer.len(bufferData), maxBytes)
    local hexString = ""
    
    for i = 0, length - 1 do
        if i > 0 and i % 16 == 0 then
            hexString = hexString .. "\n"
        end
        local byte = buffer.readu8(bufferData, i)
        hexString = hexString .. string.format("%02X ", byte)
    end
    
    if buffer.len(bufferData) > maxBytes then
        hexString = hexString .. "\n... (truncated)"
    end
    
    return hexString
end

local function bufferToArray(bufferData)
    if typeof(bufferData) ~= "buffer" then
        return {}
    end
    
    local length = buffer.len(bufferData)
    local array = {}
    
    for i = 0, length - 1 do
        array[i + 1] = buffer.readu8(bufferData, i)
    end
    
    return array
end

local function isBufferEmpty(bufferData)
    if typeof(bufferData) ~= "buffer" then
        return true
    end
    
    local length = buffer.len(bufferData)
    if length == 0 then
        return true
    end
    
    for i = 0, length - 1 do
        if buffer.readu8(bufferData, i) ~= 0 then
            return false
        end
    end
    
    return true
end

methods.bufferToString = bufferToString
methods.bufferToHex = bufferToHex
methods.bufferToArray = bufferToArray
methods.isBufferEmpty = isBufferEmpty

return methods
