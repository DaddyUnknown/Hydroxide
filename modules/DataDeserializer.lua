-- NEW MODULE: Data Deserializer for Hydroxide (2026)
-- Automatic decryption and formatting of encrypted remote arguments

local DataDeserializer = {}

local HttpService = game:GetService("HttpService")

-- Deserializer cache
local deserializerCache = {}

-- Detect data encoding type
local function detectEncoding(data)
    if type(data) ~= "string" then
        return "none", 0
    end
    
    local encodings = {}
    
    -- Base64 detection
    if data:match("^[A-Za-z0-9+/]+=*$") and #data % 4 == 0 then
        encodings.base64 = 0.9
    end
    
    -- Hex detection
    if data:match("^[0-9A-Fa-f]+$") and #data % 2 == 0 then
        encodings.hex = 0.8
    end
    
    -- JSON detection
    if (data:match("^%s*{.*}%s*$") or data:match("^%s*%[.*%]%s*$")) then
        encodings.json = 0.95
    end
    
    -- URL encoding detection
    if data:match("%%[0-9A-Fa-f][0-9A-Fa-f]") then
        encodings.urlencoded = 0.7
    end
    
    -- Binary detection (contains non-printable chars)
    local nonPrintable = 0
    for i = 1, #data do
        local byte = data:byte(i)
        if byte < 32 or byte > 126 then
            nonPrintable = nonPrintable + 1
        end
    end
    if nonPrintable / #data > 0.3 then
        encodings.binary = 0.85
    end
    
    -- Find best match
    local bestEncoding = "none"
    local bestScore = 0
    for encoding, score in pairs(encodings) do
        if score > bestScore then
            bestScore = score
            bestEncoding = encoding
        end
    end
    
    return bestEncoding, bestScore
end

-- Base64 decode
local function decodeBase64(data)
    local success, result = pcall(function()
        -- Try game's base64 if available
        if game:GetService("HttpService").DecodeBase64 then
            return game:GetService("HttpService"):DecodeBase64(data)
        end
        
        -- Fallback to manual decode
        local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        local decoded = {}
        data = data:gsub('[^' .. b64chars .. '=]', '')
        
        for i = 1, #data, 4 do
            local a, b, c, d = data:byte(i, i + 3)
            a = b64chars:find(string.char(a)) - 1
            b = b64chars:find(string.char(b)) - 1
            c = c and (b64chars:find(string.char(c)) - 1) or 0
            d = d and (b64chars:find(string.char(d)) - 1) or 0
            
            table.insert(decoded, string.char(bit32.rshift(a * 4 + bit32.rshift(b, 4), 0)))
            if c > 0 then
                table.insert(decoded, string.char(bit32.band(b * 16 + bit32.rshift(c, 2), 255)))
            end
            if d > 0 then
                table.insert(decoded, string.char(bit32.band(c * 64 + d, 255)))
            end
        end
        
        return table.concat(decoded)
    end)
    
    return success and result or nil
end

-- Hex decode
local function decodeHex(data)
    local decoded = data:gsub('..', function(cc)
        return string.char(tonumber(cc, 16))
    end)
    return decoded
end

-- URL decode
local function decodeURL(data)
    data = data:gsub('+', ' ')
    data = data:gsub('%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return data
end

-- JSON decode
local function decodeJSON(data)
    local success, result = pcall(function()
        return HttpService:JSONDecode(data)
    end)
    return success and result or nil
end

-- Buffer to readable format
local function bufferToReadable(data)
    if typeof(data) ~= "buffer" then
        return nil
    end
    
    local length = buffer.len(data)
    local readable = {
        length = length,
        hex = "",
        ascii = "",
        bytes = {}
    }
    
    -- Generate hex and ASCII representation
    for i = 0, math.min(length - 1, 255) do
        local byte = buffer.readu8(data, i)
        readable.hex = readable.hex .. string.format("%02X ", byte)
        readable.ascii = readable.ascii .. ((byte >= 32 and byte <= 126) and string.char(byte) or ".")
        table.insert(readable.bytes, byte)
    end
    
    if length > 256 then
        readable.hex = readable.hex .. "... (truncated)"
        readable.ascii = readable.ascii .. "..."
    end
    
    return readable
end

-- Main deserialize function
function DataDeserializer.deserialize(data, forceType)
    -- Check cache
    local cacheKey = type(data) == "string" and data or tostring(data)
    if deserializerCache[cacheKey] then
        return deserializerCache[cacheKey]
    end
    
    local result = {
        original = data,
        type = typeof(data),
        encoding = "none",
        decoded = nil,
        formatted = nil,
        confidence = 0
    }
    
    -- Handle buffer type
    if typeof(data) == "buffer" then
        result.encoding = "buffer"
        result.decoded = bufferToReadable(data)
        result.formatted = result.decoded
        result.confidence = 1.0
        deserializerCache[cacheKey] = result
        return result
    end
    
    -- Handle non-string types
    if type(data) ~= "string" then
        result.formatted = tostring(data)
        deserializerCache[cacheKey] = result
        return result
    end
    
    -- Detect encoding
    local encoding, confidence = detectEncoding(data)
    result.encoding = forceType or encoding
    result.confidence = confidence
    
    -- Attempt decode
    if result.encoding == "base64" then
        result.decoded = decodeBase64(data)
        -- Try to decode further if result is JSON
        if result.decoded then
            local jsonDecoded = decodeJSON(result.decoded)
            if jsonDecoded then
                result.formatted = jsonDecoded
                result.encoding = "base64+json"
            else
                result.formatted = result.decoded
            end
        end
    elseif result.encoding == "hex" then
        result.decoded = decodeHex(data)
        result.formatted = result.decoded
    elseif result.encoding == "json" then
        result.decoded = decodeJSON(data)
        result.formatted = result.decoded
    elseif result.encoding == "urlencoded" then
        result.decoded = decodeURL(data)
        result.formatted = result.decoded
    elseif result.encoding == "binary" then
        result.formatted = "Binary data (" .. #data .. " bytes)"
        result.decoded = data
    else
        result.formatted = data
    end
    
    -- Cache result
    deserializerCache[cacheKey] = result
    return result
end

-- Deserialize all arguments in a call
function DataDeserializer.deserializeArgs(args)
    local deserialized = {}
    
    for i, arg in ipairs(args) do
        deserialized[i] = DataDeserializer.deserialize(arg)
    end
    
    return deserialized
end

-- Format deserialized data for display
function DataDeserializer.formatForDisplay(deserializedData, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    
    if type(deserializedData.formatted) == "table" then
        local output = "{\n"
        for k, v in pairs(deserializedData.formatted) do
            output = output .. indentStr .. "  " .. tostring(k) .. " = "
            if type(v) == "table" then
                output = output .. DataDeserializer.formatForDisplay({formatted = v}, indent + 1)
            else
                output = output .. tostring(v)
            end
            output = output .. ",\n"
        end
        output = output .. indentStr .. "}"
        return output
    elseif deserializedData.type == "buffer" and deserializedData.decoded then
        local buf = deserializedData.decoded
        local output = string.format("Buffer (%d bytes):\n", buf.length)
        output = output .. indentStr .. "Hex: " .. buf.hex .. "\n"
        output = output .. indentStr .. "ASCII: " .. buf.ascii
        return output
    else
        return tostring(deserializedData.formatted)
    end
end

-- Attempt multiple decoding strategies
function DataDeserializer.smartDecode(data)
    local results = {}
    
    -- Try all encoding types
    local encodings = {"base64", "hex", "json", "urlencoded"}
    for _, encoding in ipairs(encodings) do
        local result = DataDeserializer.deserialize(data, encoding)
        if result.decoded then
            table.insert(results, result)
        end
    end
    
    -- Sort by confidence
    table.sort(results, function(a, b) return a.confidence > b.confidence end)
    
    return results
end

-- Clear cache
function DataDeserializer.clearCache()
    deserializerCache = {}
end

-- Get cache statistics
function DataDeserializer.getCacheStats()
    local count = 0
    for _ in pairs(deserializerCache) do
        count = count + 1
    end
    
    return {
        entries = count,
        memoryEstimate = count * 100 -- Rough estimate in bytes
    }
end

-- Detect if data might be encrypted (not just encoded)
function DataDeserializer.detectEncryption(data)
    if type(data) ~= "string" then
        return false, "Not a string"
    end
    
    -- Calculate entropy (high entropy = likely encrypted)
    local freq = {}
    for i = 1, #data do
        local byte = data:byte(i)
        freq[byte] = (freq[byte] or 0) + 1
    end
    
    local entropy = 0
    for _, count in pairs(freq) do
        local p = count / #data
        entropy = entropy - (p * math.log(p) / math.log(2))
    end
    
    -- High entropy suggests encryption
    if entropy > 7.5 then
        return true, string.format("High entropy: %.2f (likely encrypted)", entropy)
    else
        return false, string.format("Low entropy: %.2f (likely not encrypted)", entropy)
    end
end

-- Format multiple deserialize attempts
function DataDeserializer.formatSmartDecodeResults(results)
    local output = "=== Smart Decode Results ===\n\n"
    
    for i, result in ipairs(results) do
        output = output .. string.format("%d. Encoding: %s (Confidence: %.0f%%)\n",
            i, result.encoding, result.confidence * 100)
        output = output .. "   Decoded: " .. DataDeserializer.formatForDisplay(result) .. "\n\n"
    end
    
    return output
end

return DataDeserializer
