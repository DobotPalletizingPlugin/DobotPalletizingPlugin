local LiftkitLinAK = {
    defaultIP = '192.168.5.123',
    socket = nil,
    isReading = false,
    heartBeatTimes = 0
}

-- LinAK相关-hfq

-- LINAK 升降柱初始化 (对应 global.lua 中的 LINAKInit)
LiftkitLinAK.Init = function()
    local socket = LiftkitLinAK.socket
    if socket == nil then
        EcoLog('LinAK not Connected, cannot init')
        return false
    end
    -- 向寄存器 8195-8198 写入 251 (初始化/使能命令)
    SetHoldRegs(socket, 8195, 1, { 251 })
    SetHoldRegs(socket, 8196, 1, { 251 })
    SetHoldRegs(socket, 8197, 1, { 251 })
    SetHoldRegs(socket, 8198, 1, { 251 })
    Wait(500)
    EcoLog('LinAK Init completed')
    return true
end

LiftkitLinAK.Connect = function(ip, port)
    local err = 0
    local Socket = nil
    -- 创建 Modbus TCP 连接
    err, Socket = ModbusCreate(ip, port)
    if err == 0 then
        EcoLog("LinAK Modbus Connect Success! ip: " .. ip .. ", port: " .. port)
        LiftkitLinAK.socket = Socket
        -- 初始化 LINAK 升降柱 (参考 global.lua 中的 LINAKInit)
        LiftkitLinAK.Init()
        return true
    else
        EcoLog("LinAK Modbus Connect failed, code: " .. err)
        LiftkitLinAK.socket = nil
        return false
    end
end

LiftkitLinAK.Disconnect = function()
    if LiftkitLinAK.socket ~= nil then
        EcoLog('LiftkitDisconnect ModbusClose')
        -- 先停止升降柱运动 (参考 global.lua 中的 LINAKStop)
        SetHoldRegs(LiftkitLinAK.socket, 8194, 1, { 64259 })
        Wait(100)
        -- 关闭 Modbus 连接
        ModbusClose(LiftkitLinAK.socket)
        LiftkitLinAK.socket = nil
    end
    return true
end

LiftkitLinAK.GetPosition = function()
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    -- 从寄存器 8449 读取位置 (参考 global.lua 中的 LINAKGetPostion)
    local position = GetHoldRegs(LiftkitLinAK.socket, 8449, 1)
    if position == nil or position[1] == nil then
        EcoLog('Liftkit GetPosition failed')
        return false
    end
    -- LINAK 返回的值是 0.1mm 为单位，转换为 mm
    return position[1] / 10
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

    local socket = LiftkitLinAK.socket
    local Err = 0
    local Status = 0

    -- 等待设备就绪 (参考 global.lua 中的 LINAKRun)
    repeat
        Err = GetHoldRegs(socket, 8452, 1)
        Status = GetHoldRegs(socket, 8451, 1)
        EcoLog("LinAK MoveTo: error code: " .. tostring(Err[1]) .. ", status: " .. tostring(Status[1]))
        -- 清除错误/准备运动
        SetHoldRegs(socket, 8194, 1, { 64256 })
    until (Err[1] == 0)

    -- 发送目标位置（LINAK 使用 0.1mm 为单位，需要乘以 10）
    local targetPosition = math.ceil(data * 10)
    SetHoldRegs(socket, 8194, 1, { targetPosition })
    EcoLog('LinAK MoveTo position: ' .. data .. 'mm (raw: ' .. targetPosition .. ')')
    return true
end

LiftkitLinAK.MoveStop = function()
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    -- 向寄存器 8194 写入 64259 (停止命令)
    SetHoldRegs(LiftkitLinAK.socket, 8194, 1, { 64259 })
    EcoLog('LinAK MoveStop completed')
    return true
end

LiftkitLinAK.HeartBeat = function()
    if LiftkitLinAK.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    if LiftkitLinAK.heartBeatTimes > 255 then
        LiftkitLinAK.heartBeatTimes = 0
    else
        LiftkitLinAK.heartBeatTimes = LiftkitLinAK.heartBeatTimes + 1
    end
    SetHoldRegs(LiftkitLinAK.socket, 8193, 1, { LiftkitLinAK.heartBeatTimes })
    EcoLog('LinAK HeartBeat: ' .. LiftkitLinAK.heartBeatTimes)
    return true
end

-- LINAK 升降柱点动实现与点到点运动实现一致
LiftkitLinAK.JogTo = function(data) return LiftkitLinAK.MoveTo(data) end


return LiftkitLinAK
