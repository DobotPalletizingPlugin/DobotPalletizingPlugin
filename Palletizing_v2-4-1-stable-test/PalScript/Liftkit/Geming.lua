local LiftkitGeming = {
    defaultIP = '192.168.5.100',
    socket = nil,
    isReading = false
}

-- 初始化
local function SV660Cinit()
    local socket = LiftkitGeming.socket
    SetHoldRegs(socket, 0x030a, 1, {0}, "U16")
    SetHoldRegs(socket, 0x0308, 1, {0}, "U16")
    SetHoldRegs(socket, 0x0200, 1, {1}, "U16")
    SetHoldRegs(socket, 0x0C09, 1, {1}, "U16")
    SetHoldRegs(socket, 0x0C0a, 1, {1}, "U16")
    SetHoldRegs(socket, 0x0500, 1, {2}, "U16")
    SetHoldRegs(socket, 0x1100, 1, {5}, "U16")
    SetHoldRegs(socket, 0x110e, 1, {1200}, "U16")
    SetHoldRegs(socket, 0x110f, 1, {300}, "U16")
    SetHoldRegs(socket, 0x1104, 1, {1}, "U16")
    SetHoldRegs(socket, 0x0604, 1, {500}, "U16") -- 点动速度

    SetHoldRegs(socket, 0x1700, 1, {1}, "U16") -- VDI1 
    SetHoldRegs(socket, 0x1702, 1, {28}, "U16") -- VDI2
    SetHoldRegs(socket, 0x1704, 1, {18}, "U16") -- VDI3 正转
    SetHoldRegs(socket, 0x1705, 1, {0}, "U16")
    SetHoldRegs(socket, 0x1706, 1, {19}, "U16") -- VDI4 反转
    SetHoldRegs(socket, 0x1707, 1, {0}, "U16")
    SetHoldRegs(socket, 0x1708, 1, {2}, "U16") -- VDI5 故障复位
    SetHoldRegs(socket, 0x1709, 1, {0}, "U16")
    SetHoldRegs(socket, 0x170a, 1, {32}, "U16") -- VDI6 原点复位使能
    SetHoldRegs(socket, 0x170b, 1, {0}, "U16")
    return true
end

-- 使能控制
local function SV660CPowerControl(poweron)
    local socket = LiftkitGeming.socket
    if poweron == 1 then
        SetHoldRegs(socket, 0x3100, 1, {1}, "U16")
    else
        SetHoldRegs(socket, 0x3100, 1, {0}, "U16")
    end
    return true
end

-- 运动控制
local function SV660CServoControl(position)
    if position == nil then EcoLog("position is nil") end
    local socket = LiftkitGeming.socket
    SetHoldRegs(socket, 0x110c, 2, {position * 10}, "U32")
    SetHoldRegs(socket, 0x3100, 1, {1}, "U16")
    SetHoldRegs(socket, 0x3100, 1, {3}, "U16")
    return true
end

-- 点动控制
-- value：点动方向，0为下降，1为上升
local function SV660CJogControl(value)
    local socket = LiftkitGeming.socket
    if value == 1 then
        SetHoldRegs(socket, 0x3100, 1, {5}, "U16")
    else
        SetHoldRegs(socket, 0x3100, 1, {9}, "U16")
    end
    return true
end

-- 停止运动
local function SV660CStopMoving()
    local socket = LiftkitGeming.socket
    SetHoldRegs(socket, 0x3100, 1, {1}, "U16")
    return true
end

-- 获取升降柱位置
function SV660CGetPostion()
    local socket = LiftkitGeming.socket
    local position = GetHoldRegs(socket, 0x0b07, 2, "U32")
    if position[1] == nil then return false end
    return position[1] / 10
end

-- 获取升降柱报警码
local function SV660CGetAlarmCode()
    local socket = LiftkitGeming.socket
    local code = GetHoldRegs(socket, 0x0b2d, 1, "U16")
    if code ~= nil and code[1] ~= nil then
        return string.format('%x', code[1])
    end
    return 0
end

-- 回零状态
local function WaitModbusHome(addr, bit)
    local socket = LiftkitGeming.socket
    while true do
        Wait(50)
        local B = 0
        local b = {}
        msg = GetHoldRegs(socket, addr, 1, "U16")
        EcoLog("msg[1]" .. msg[1])
        for a = 1, 16 do
            b[a] = msg[1] & (2 ^ (a - 1))
            if b[a] == (2 ^ bit) then
                EcoLog("回零ok")
                B = 1
                break
            end
            EcoLog(b[a])
        end
        if B == 1 then break end
    end
end

-- 回零
local function SV660CHoming()
    local socket = LiftkitGeming.socket

    SetHoldRegs(socket, 0x3100, 1, {1}, "U16") -- 使能
    SetHoldRegs(socket, 0x051e, 1, {1}, "U16") -- 回零使能选择
    SetHoldRegs(socket, 0x051f, 1, {7}, "U16") -- 回零模式
    SetHoldRegs(socket, 0x0528, 1, {2}, "U16") -- 偏移量设置模式
    SetHoldRegs(socket, 0x0524, 2, {(65536 - 100), 65535}, "U16") -- 回零偏移值-100
    SetHoldRegs(socket, 0x0520, 1, {600}, "U16") -- 回零速度
    SetHoldRegs(socket, 0x0521, 1, {100}, "U16") -- 回零低速
    Wait(500)
    SetHoldRegs(socket, 0x3100, 1, {33}, "U16") -- 回零
    Wait(500)
    WaitModbusHome(0x3001, 15) -- 等待回零完成
    SV660CServoControl(0)

    return true
end

LiftkitGeming.Connect = function()
    local err = 0
    local Socket = nil
    err, Socket = ModbusRTUCreate(1, 57600, "N", 8, 1)
    if err == 0 then
        EcoLog("Create Modbus Client Success!")
        LiftkitGeming.socket = Socket
        SV660Cinit()
        SV660CPowerControl(1)
        return true
    else
        EcoLog("Create Modbus Client failed, code:", err)
        return false
    end
end

LiftkitGeming.Disconnect = function()
    if LiftkitGeming.socket ~= nil then
        EcoLog('LiftkitDisconnect ModbusClose')
        SV660CPowerControl(0)
        ModbusClose(LiftkitGeming.socket)
    end
end

LiftkitGeming.GetPosition = function()
    if LiftkitGeming.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    return SV660CGetPostion()
end

LiftkitGeming.MoveTo = function(data)
    if LiftkitGeming.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    SV660CServoControl(data)
    return true
end

LiftkitGeming.JogTo = function(data)
    if LiftkitGeming.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    return SV660CJogControl(data)
end

LiftkitGeming.MoveStop = function()
    if LiftkitGeming.socket == nil then
        EcoLog('Liftkit not Connected')
        return false
    end
    return SV660CStopMoving()
end

LiftkitGeming.GetAlarmCode = function()
    local err = 0
    local Socket = nil
    err, Socket = ModbusRTUCreate(1, 57600, "N", 8, 1)
    if err == 0 then
        EcoLog("Create Modbus Client Success!")
        local result = SV660CGetAlarmCode()
        ModbusClose(Socket)
        return result.code
    else
        EcoLog("Create Modbus Client failed, code:", err)
        return -1
    end
end

-- todo:待处理回零失败 / 超时的返回
LiftkitGeming.Homing = function()
    SV660CHoming()
    return true
end

return LiftkitGeming
