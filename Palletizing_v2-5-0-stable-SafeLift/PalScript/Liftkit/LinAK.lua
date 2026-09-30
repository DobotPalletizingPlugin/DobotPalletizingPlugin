local LiftkitLinAK = {
    defaultIP = '192.168.5.123',
    socket = nil,
    isReading = false,
    heartBeatTimes = 0,
    stopRequestId = 0
}

local function LockCommunication(action, maxWaitMs)
    local waitedMs = 0
    maxWaitMs = maxWaitMs or 0
    while LiftkitLinAK.isReading == true do
        if waitedMs >= maxWaitMs then
            EcoLog('LinAK communication busy: ' .. action)
            return false
        end
        Wait(10)
        waitedMs = waitedMs + 10
    end
    LiftkitLinAK.isReading = true
    return true
end

local function UnlockCommunication()
    LiftkitLinAK.isReading = false
end

local function WriteRegister(socket, address, value)
    local succeeded, err = pcall(SetHoldRegs, socket, address, 1, { value })
    if not succeeded then
        EcoLog('LinAK SetHoldRegs exception, address: ' .. address .. ', error: ' .. tostring(err))
        return false
    end
    if err ~= 0 then
        EcoLog('LinAK SetHoldRegs failed, address: ' .. address .. ', error code: ' .. tostring(err))
        return false
    end
    return true
end

local function ReadRegisters(socket, address, count)
    local succeeded, result = pcall(GetHoldRegs, socket, address, count)
    if not succeeded then
        EcoLog('LinAK GetHoldRegs exception, address: ' .. address .. ', error: ' .. tostring(result))
        return nil
    end
    return result
end

-- 调用方持有通信锁，供独立心跳和运动等待共用。
local function WriteHeartBeat(socket)
    local nextHeartBeat = (LiftkitLinAK.heartBeatTimes + 1) % 256
    local result = WriteRegister(socket, 8193, nextHeartBeat)
    if result then
        LiftkitLinAK.heartBeatTimes = nextHeartBeat
        EcoLog('LinAK HeartBeat: ' .. LiftkitLinAK.heartBeatTimes)
    end
    return result
end

-- LinAK相关-hfq

-- LINAK 升降柱初始化 (对应 global.lua 中的 LINAKInit)
LiftkitLinAK.Init = function()
    local socket = LiftkitLinAK.socket
    if socket == nil then
        EcoLog('LinAK not Connected, cannot init')
        return false
    end
    if not LockCommunication('Init') then return false end
    -- 向寄存器 8194-8198 写入 251 (初始化/使能命令)
    local result = WriteRegister(socket, 8194, 64256) and
        WriteRegister(socket, 8195, 251) and
        WriteRegister(socket, 8196, 251) and
        WriteRegister(socket, 8197, 251) and
        WriteRegister(socket, 8198, 251)
    if result then
        Wait(500)
        EcoLog('LinAK Init completed')
    else
        EcoLog('LinAK Init failed')
    end
    UnlockCommunication()
    return result
end

LiftkitLinAK.Connect = function(ip, port)
    local err = 0
    local Socket = nil
    -- 创建 Modbus TCP 连接
    err, Socket = ModbusCreate(ip, port)
    if err == 0 and Socket ~= nil then
        EcoLog("LinAK Modbus Connect Success! ip: " .. ip .. ", port: " .. port)
        LiftkitLinAK.socket = Socket
        -- 初始化 LINAK 升降柱 (参考 global.lua 中的 LINAKInit)
        if LiftkitLinAK.Init() then
            return true
        end
        EcoLog('LinAK Modbus Connect failed during initialization')
        ModbusClose(Socket)
        LiftkitLinAK.socket = nil
        return false
    else
        EcoLog("LinAK Modbus Connect failed, code: " .. tostring(err))
        LiftkitLinAK.socket = nil
        return false
    end
end

LiftkitLinAK.Disconnect = function()
    LiftkitLinAK.stopRequestId = LiftkitLinAK.stopRequestId + 1
    if not LockCommunication('Disconnect', 1500) then return false end
    if LiftkitLinAK.socket ~= nil then
        EcoLog('LiftkitDisconnect ModbusClose')
        -- 先停止升降柱运动 (参考 global.lua 中的 LINAKStop)
        local stopResult = WriteRegister(LiftkitLinAK.socket, 8194, 64259)
        if stopResult then
            Wait(100)
        else
            EcoLog('LinAK Disconnect stop command failed, closing connection')
        end
        -- 关闭 Modbus 连接
        local succeeded, err = pcall(ModbusClose, LiftkitLinAK.socket)
        if not succeeded or err ~= 0 then
            EcoLog('LinAK ModbusClose failed: ' .. tostring(err))
            UnlockCommunication()
            return false
        end
        LiftkitLinAK.socket = nil
    end
    UnlockCommunication()
    return true
end

LiftkitLinAK.GetPosition = function()
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    if not LockCommunication('GetPosition') then return false end
    -- 从寄存器 8449 读取位置 (参考 global.lua 中的 LINAKGetPostion)
    local position = ReadRegisters(LiftkitLinAK.socket, 8449, 1)
    if position == nil or position[1] == nil then
        EcoLog('Liftkit GetPosition failed')
        UnlockCommunication()
        return false
    end
    -- LINAK 返回的值是 0.1mm 为单位，转换为 mm
    local result = position[1] / 10
    UnlockCommunication()
    return result
end

LiftkitLinAK.MoveTo = function(data)
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    if data == nil then
        EcoLog('MoveTo position is nil!')
        return false
    end

    local stopRequestId = LiftkitLinAK.stopRequestId
    if not LockCommunication('MoveTo', 500) then return false end
    local socket = LiftkitLinAK.socket
    if socket == nil then
        EcoLog('Liftkit not Connected')
        UnlockCommunication()
        return false
    end
    local maxRetry = 60
    local maxWaitMs = 6500
    local startTime = Systime()
    local isReady = false
    local communicationFailed = false
    local moveCancelled = false
    local lastHeartBeatTime = nil

    -- 等待清错时仍需维持心跳，不能依赖被通信锁挡住的外部心跳。
    local function KeepHeartBeat()
        if lastHeartBeatTime == nil or Systime() - lastHeartBeatTime >= 300 then
            if not WriteHeartBeat(socket) then return false end
            lastHeartBeatTime = Systime()
        end
        return true
    end

    -- 等待设备就绪 (参考 global.lua 中的 LINAKRun)，同时限制重试次数和实际耗时
    for i = 1, maxRetry do
        if LiftkitLinAK.stopRequestId ~= stopRequestId then
            moveCancelled = true
            break
        end
        if Systime() - startTime >= maxWaitMs then break end
        if not KeepHeartBeat() then
            communicationFailed = true
            break
        end

        local Err = ReadRegisters(socket, 8452, 1)
        if Systime() - startTime >= maxWaitMs then break end
        local Status = ReadRegisters(socket, 8451, 1)
        if Systime() - startTime >= maxWaitMs then break end
        local errCode = Err and Err[1]
        local statusCode = Status and Status[1]
        EcoLog("LinAK MoveTo: error code: " .. tostring(errCode) .. ", status: " .. tostring(statusCode) .. ", retry: " .. i)

        if errCode == nil then
            EcoLog('LinAK MoveTo read error failed')
            communicationFailed = true
            break
        end
        if errCode == 0 then
            isReady = true
            break
        end

        -- 清除错误/准备运动
        if not WriteRegister(socket, 8194, 64256) then
            communicationFailed = true
            break
        end
        Wait(100)
    end

    if not isReady then
        if moveCancelled then
            EcoLog('LinAK MoveTo cancelled by stop request')
        elseif not communicationFailed then
            EcoLog('LinAK MoveTo timeout waiting error clear')
        end
        UnlockCommunication()
        return false
    end

    if LiftkitLinAK.stopRequestId ~= stopRequestId or
        Systime() - startTime >= maxWaitMs then
        EcoLog('LinAK MoveTo cancelled before target command')
        UnlockCommunication()
        return false
    end
    if not KeepHeartBeat() or LiftkitLinAK.stopRequestId ~= stopRequestId or
        Systime() - startTime >= maxWaitMs then
        UnlockCommunication()
        return false
    end

    -- 发送目标位置（LINAK 使用 0.1mm 为单位，需要乘以 10）
    local targetPosition = math.ceil(data * 10)
    local result = WriteRegister(socket, 8194, targetPosition)
    if result then
        EcoLog('LinAK MoveTo position: ' .. data .. 'mm (raw: ' .. targetPosition .. ')')
    end
    UnlockCommunication()
    return result
end

LiftkitLinAK.MoveStop = function()
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    LiftkitLinAK.stopRequestId = LiftkitLinAK.stopRequestId + 1
    if not LockCommunication('MoveStop', 1500) then return false end
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        UnlockCommunication()
        return false
    end
    -- 向寄存器 8194 写入 64259 (停止命令)
    local result = WriteRegister(LiftkitLinAK.socket, 8194, 64259)
    if result then EcoLog('LinAK MoveStop completed') end
    UnlockCommunication()
    return result
end

LiftkitLinAK.HeartBeat = function()
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    if not LockCommunication('HeartBeat') then return false end
    local result = WriteHeartBeat(LiftkitLinAK.socket)
    UnlockCommunication()
    return result
end

-- LINAK 升降柱点动实现与点到点运动实现一致
LiftkitLinAK.JogTo = function(data) return LiftkitLinAK.MoveTo(data) end


return LiftkitLinAK
