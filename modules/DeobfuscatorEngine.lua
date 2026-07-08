-- NEW MODULE: Deobfuscator Engine for Hydroxide (2026)
-- Bypass anti-decompile protection and rename obfuscated variables

local DeobfuscatorEngine = {}

local requiredMethods = {
    ["getGc"] = true,
    ["getInfo"] = true,
    ["getConstants"] = true,
    ["getUpvalues"] = true,
}

-- Known obfuscation patterns
local obfuscationPatterns = {
    -- Luraph patterns
    luraph = {
        pattern = "^l__[%w_]+__[%d]+$",
        type = "Luraph",
        confidence = 0.9
    },
    -- Ironbrew patterns
    ironbrew = {
        pattern = "^II[il1I]+[il1I]+$",
        type = "Ironbrew",
        confidence = 0.85
    },
    -- PSU patterns
    psu = {
        pattern = "^[A-Z][A-Z0-9]{15,}$",
        type = "PSU",
        confidence = 0.8
    },
    -- Moonsec patterns
    moonsec = {
        pattern = "^[a-z]+_[0-9]+_[a-z]+$",
        type = "Moonsec",
        confidence = 0.75
    },
    -- Generic random patterns
    random = {
        pattern = "^[%w_]{20,}$",
        type = "Generic",
        confidence = 0.6
    }
}

-- Cache for deobfuscated names
local nameCache = {}
local variableCounter = {}

-- Detect obfuscation type
local function detectObfuscationType(name)
    for _, pattern in pairs(obfuscationPatterns) do
        if name:match(pattern.pattern) then
            return pattern.type, pattern.confidence
        end
    end
    return "Unknown", 0
end

-- Generate meaningful name
local function generateMeaningfulName(originalName, context, valueType)
    -- Check cache first
    if nameCache[originalName] then
        return nameCache[originalName]
    end
    
    local prefix = ""
    
    -- Determine prefix based on type
    if valueType == "function" then
        prefix = "func_"
    elseif valueType == "table" then
        prefix = "tbl_"
    elseif valueType == "string" then
        prefix = "str_"
    elseif valueType == "number" then
        prefix = "num_"
    elseif valueType == "boolean" then
        prefix = "bool_"
    else
        prefix = "var_"
    end
    
    -- Add context if available
    if context and #context > 0 then
        prefix = context .. "_" .. prefix
    end
    
    -- Generate unique counter
    if not variableCounter[prefix] then
        variableCounter[prefix] = 1
    else
        variableCounter[prefix] = variableCounter[prefix] + 1
    end
    
    local newName = prefix .. variableCounter[prefix]
    nameCache[originalName] = newName
    
    return newName
end

-- Analyze string constants for hints
local function analyzeConstants(func)
    local hints = {}
    local success, constants = pcall(getConstants, func)
    
    if success and constants then
        for _, constant in pairs(constants) do
            if type(constant) == "string" then
                -- Look for common patterns
                if constant:match("^[A-Z][a-z]+$") then
                    table.insert(hints, constant)
                end
                
                -- Look for remote names
                if constant:match("Remote") or constant:match("Event") or constant:match("Function") then
                    table.insert(hints, constant)
                end
            end
        end
    end
    
    return hints
end

-- Deobfuscate upvalues
function DeobfuscatorEngine.deobfuscateUpvalues(func)
    local success, upvalues = pcall(getUpvalues, func)
    if not success or not upvalues then
        return {}
    end
    
    local deobfuscated = {}
    local hints = analyzeConstants(func)
    local context = (#hints > 0 and hints[1]) or "upval"
    
    for name, value in pairs(upvalues) do
        local obfType, confidence = detectObfuscationType(name)
        
        if confidence > 0.5 then
            local newName = generateMeaningfulName(name, context, type(value))
            deobfuscated[name] = {
                original = name,
                deobfuscated = newName,
                type = type(value),
                obfuscationType = obfType,
                confidence = confidence,
                value = value
            }
        else
            deobfuscated[name] = {
                original = name,
                deobfuscated = name,
                type = type(value),
                obfuscationType = "None",
                confidence = 1.0,
                value = value
            }
        end
    end
    
    return deobfuscated
end

-- Deobfuscate constants
function DeobfuscatorEngine.deobfuscateConstants(func)
    local success, constants = pcall(getConstants, func)
    if not success or not constants then
        return {}
    end
    
    local deobfuscated = {}
    
    for i, constant in pairs(constants) do
        local constType = type(constant)
        local isObfuscated = false
        
        -- Check if string constant looks obfuscated
        if constType == "string" and #constant > 15 then
            local obfType, confidence = detectObfuscationType(constant)
            if confidence > 0.5 then
                isObfuscated = true
            end
        end
        
        deobfuscated[i] = {
            index = i,
            value = constant,
            type = constType,
            isObfuscated = isObfuscated,
            displayValue = (constType == "string" and #constant > 50) 
                and (constant:sub(1, 50) .. "...") 
                or tostring(constant)
        }
    end
    
    return deobfuscated
end

-- Scan entire GC for obfuscated code
function DeobfuscatorEngine.scanGC()
    local results = {
        totalFunctions = 0,
        obfuscatedFunctions = 0,
        detectedObfuscators = {},
        suspiciousFunctions = {}
    }
    
    for _, func in pairs(getGc()) do
        if type(func) == "function" then
            results.totalFunctions = results.totalFunctions + 1
            
            local success, info = pcall(getInfo, func)
            if success and info then
                local source = info.source or ""
                local name = info.name or "anonymous"
                
                -- Check function name
                local obfType, confidence = detectObfuscationType(name)
                
                if confidence > 0.5 then
                    results.obfuscatedFunctions = results.obfuscatedFunctions + 1
                    
                    -- Track obfuscator type
                    if not results.detectedObfuscators[obfType] then
                        results.detectedObfuscators[obfType] = 0
                    end
                    results.detectedObfuscators[obfType] = results.detectedObfuscators[obfType] + 1
                    
                    table.insert(results.suspiciousFunctions, {
                        func = func,
                        name = name,
                        obfuscationType = obfType,
                        confidence = confidence,
                        source = source
                    })
                end
            end
        end
    end
    
    return results
end

-- Create deobfuscation map for a closure
function DeobfuscatorEngine.createDeobfuscationMap(func)
    return {
        upvalues = DeobfuscatorEngine.deobfuscateUpvalues(func),
        constants = DeobfuscatorEngine.deobfuscateConstants(func),
        info = pcall(getInfo, func) and getInfo(func) or {}
    }
end

-- Format deobfuscation report
function DeobfuscatorEngine.formatReport(scanResults)
    local output = "=== Deobfuscator Engine Report ===\n\n"
    
    output = output .. "📊 Scan Statistics:\n"
    output = output .. string.format("  Total Functions: %d\n", scanResults.totalFunctions)
    output = output .. string.format("  Obfuscated Functions: %d (%.1f%%)\n", 
        scanResults.obfuscatedFunctions,
        (scanResults.obfuscatedFunctions / math.max(1, scanResults.totalFunctions)) * 100)
    output = output .. "\n"
    
    if next(scanResults.detectedObfuscators) then
        output = output .. "🔍 Detected Obfuscators:\n"
        for obfType, count in pairs(scanResults.detectedObfuscators) do
            output = output .. string.format("  %s: %d functions\n", obfType, count)
        end
        output = output .. "\n"
    end
    
    if #scanResults.suspiciousFunctions > 0 then
        output = output .. "⚠️ Top 10 Suspicious Functions:\n"
        for i = 1, math.min(10, #scanResults.suspiciousFunctions) do
            local func = scanResults.suspiciousFunctions[i]
            output = output .. string.format("  %d. %s (%s) - Confidence: %.0f%%\n",
                i, func.name, func.obfuscationType, func.confidence * 100)
        end
        output = output .. "\n"
    end
    
    return output
end

-- Auto-rename obfuscated variables in display
function DeobfuscatorEngine.getReadableName(originalName, context, valueType)
    return generateMeaningfulName(originalName, context, valueType)
end

-- Clear cache
function DeobfuscatorEngine.clearCache()
    nameCache = {}
    variableCounter = {}
end

-- Export deobfuscation map as Lua code
function DeobfuscatorEngine.exportAsLua(deobfMap)
    local output = "-- Deobfuscated variable map\nlocal deobfuscated = {\n"
    
    -- Export upvalues
    output = output .. "  upvalues = {\n"
    for original, data in pairs(deobfMap.upvalues) do
        output = output .. string.format("    ['%s'] = '%s', -- %s\n",
            original, data.deobfuscated, data.type)
    end
    output = output .. "  },\n"
    
    -- Export constants
    output = output .. "  constants = {\n"
    for i, data in pairs(deobfMap.constants) do
        if data.isObfuscated then
            output = output .. string.format("    [%d] = '%s', -- obfuscated\n",
                i, data.displayValue)
        end
    end
    output = output .. "  }\n}\n\nreturn deobfuscated"
    
    return output
end

-- Heuristic to detect VM-based obfuscation
function DeobfuscatorEngine.detectVMObfuscation(func)
    local success, constants = pcall(getConstants, func)
    if not success or not constants then
        return false, "Unknown"
    end
    
    local vmIndicators = {
        hasOpcodes = false,
        hasBytecodePattern = false,
        hasVMLoop = false
    }
    
    for _, constant in pairs(constants) do
        if type(constant) == "number" then
            -- Check for opcode-like numbers (0-255 range, lots of them)
            if constant >= 0 and constant <= 255 then
                vmIndicators.hasOpcodes = true
            end
        elseif type(constant) == "string" then
            -- Check for bytecode patterns
            if constant:match("\x1b") or constant:match("^\x00\x01") then
                vmIndicators.hasBytecodePattern = true
            end
        end
    end
    
    -- Check info for VM patterns
    local info = pcall(getInfo, func) and getInfo(func)
    if info and info.source then
        if info.source:match("vm") or info.source:match("virtual") then
            vmIndicators.hasVMLoop = true
        end
    end
    
    local vmScore = 0
    if vmIndicators.hasOpcodes then vmScore = vmScore + 1 end
    if vmIndicators.hasBytecodePattern then vmScore = vmScore + 2 end
    if vmIndicators.hasVMLoop then vmScore = vmScore + 2 end
    
    if vmScore >= 2 then
        return true, "VM-based obfuscation detected"
    else
        return false, "No VM detected"
    end
end

DeobfuscatorEngine.RequiredMethods = requiredMethods
return DeobfuscatorEngine
