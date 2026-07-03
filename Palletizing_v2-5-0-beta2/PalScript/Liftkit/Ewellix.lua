local LiftkitEwellix = {
    defaultIP = '192.168.5.100',
    socket = nil,
    isReading = false
}
LiftkitEwellix.Command = {
    GET_POSITION = 'get_position\n',
    GET_STATUS = 'get_status\n',
    GET_TYPE = 'get_type\n',
    GET_STROKE = 'get_stroke\n',
    GET_VIRTUALLIMITS = 'get_virtualLimits\n',
    SET_VIRTUALLIMITS = 'set_virtualLimits',
    MOVE_POSITION = 'moveTo_absolutePosition',
    MOVE_STOP = 'stop_moving\n'
}

-- 去除字符串前后空格、换行符等
local function string_trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end

-- 字符串分割，delimiter为分隔标志
local function string_split(str, delimiter)
    local result = {}
    local from = 1
    local delim_from = string.find(str, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(str, from, delim_from - 1))
        from = delim_from + string.len(delimiter)
        delim_from = string.find(str, delimiter, from)
    end
    table.insert(result, string.sub(str, from))
    return result
end

-- 从指定位置截取数组至末尾
local function table_splice(srcTable, startIndex)
    local dstTable = {}
    table.move(srcTable, startIndex, #srcTable, 1, dstTable)
    return dstTable
end

LiftkitEwellix.Connect = function(ip, port)
    local err = 0
    local Socket = nil
    local tcpData = {}
    err, Socket = TCPCreate(false, ip, port) -- 创建TCP客户端
    if err == 0 then -- 创建TCP成功
        err = TCPStart(Socket, 10) -- 建立TCP连接
        if err == 0 then -- 连接TPC成功
            EcoLog("Connect TCP Client Success!")
            LiftkitEwellix.socket = Socket
            return true
        else
            EcoLog("Connect TCP Client failed, code:", err)
            LiftkitEwellix.socket = nil
            TCPDestroy(Socket)
            return false
        end
    else
        EcoLog("Create TCP Client failed, code:", err)
        LiftkitEwellix.socket = nil
        TCPDestroy(Socket)
        return false
    end
end

LiftkitEwellix.Disconnect = function()
    if LiftkitEwellix.socket ~= nil then
        EcoLog('LiftkitDisconnect TCPDestroy')
        TCPDestroy(LiftkitEwellix.socket)
        LiftkitEwellix.socket = nil
    end
    return true
end

LiftkitEwellix.GetPosition = function()
    if LiftkitEwellix.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    return LiftkitEwellix.ReadTCPMessage(LiftkitEwellix.Command.GET_POSITION)
end

LiftkitEwellix.MoveTo = function(data)
    if LiftkitEwellix.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    return LiftkitEwellix.ReadTCPMessage(
               LiftkitEwellix.Command.MOVE_POSITION .. "," .. data .. "\n")
end

-- 伊维莱升降柱点动实现与点到点运动实现一致
LiftkitEwellix.JogTo = function(data) return LiftkitEwellix.MoveTo(data) end

LiftkitEwellix.MoveStop = function()
    if LiftkitEwellix.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    return LiftkitEwellix.ReadTCPMessage(LiftkitEwellix.Command.MOVE_STOP)
end

-- 未支持
LiftkitEwellix.GetAlarmCode = function() return true end

-- 未支持
LiftkitEwellix.Homing = function() return true end

LiftkitEwellix.ReadTCPMessage = function(command)
    EcoLog('----------------ReadTCPMessage ' .. command)

    if LiftkitEwellix.isReading == true then
        Wait(200)
        return LiftkitEwellix.ReadTCPMessage(command)
    end

    LiftkitEwellix.isReading = true
    TCPWrite(LiftkitEwellix.socket, command)
    Err, result = TCPRead(LiftkitEwellix.socket, 3, "string")
    if Err == 0 then
        LiftkitEwellix.isReading = false
        return LiftkitEwellix.TCPMessageHandle(result)
    else
        EcoLog("TCPRead failed, code: " .. Err)
        LiftkitEwellix.isReading = false
        return false
    end
end

LiftkitEwellix.TCPMessageHandle = function(str)
    local splitData = string_split(string_trim(str), ',')
    EcoLog('Message command: ' .. splitData[1] .. " state: " .. splitData[2])
    if splitData[2] == "OK" then
        return table_splice(splitData, 3)
    else
        return false
    end
end

return LiftkitEwellix
