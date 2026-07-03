EcoLog("------------------ Palletizing daemon called --------------------")

-- 此段代码是加载脚本配置环境，尽量不要在这段代码的前面添加其他代码块
do
    local currentDir = debug.getinfo(1, "S").source
    currentDir = string.sub(currentDir, 2) -- filter out '@'
    currentDir = string.reverse(currentDir)
    local pos = string.find(currentDir, "/", 1, true)
    if nil == pos then pos = string.find(currentDir, "\\", 1, true) end
    currentDir = string.sub(currentDir, pos)
    currentDir = string.reverse(currentDir) .. "?.lua"
    pos = string.find(package.path, currentDir, 1, true)
    if nil == pos then package.path = currentDir .. ";" .. package.path end
end

require('PalScript.PalScriptLoader')
local MqttFunc = require("libplugin_eco")
local json = require("luaJson")
local MainApp = {threads = {}, isSignalChecking = false}
local MethodCenter = {
    ModbusID = nil,
    LiftkitManager = {connected = false, instance = nil}
}

local SignalMap = {
    palletConfirmEnable = 0, -- 新栈板到位确认按钮 0：不启用；1：启用
    buzzerEnable = 0, -- 是否启用蜂鸣器DO

    leftPalletConfirm = 0, -- 左栈板确认信号
    rightPalletConfirm = 0, -- 右栈板确认信号
    buzzerOn = 0, -- 蜂鸣器DO
    leftPalletReady = {0, 0}, -- 左栈板到位信号
    rightPalletReady = { 0, 0 }, -- 右栈板到位信号
    
    palletFResetL = false,
    palletFResetR = false
}

---------------------------------- MQTT相关 ↓ -------------------------------------

-- MQTT创建
function MainApp.MqttCreate()
    local createStatus, createErr = pcall(MqttFunc.MQTTCreate,
                                          ToolVariables.MQTT_ID, "127.0.0.1",
                                          1883, 600)
    if createStatus then
        local connectStatus, connectErr =
            pcall(MqttFunc.MQTTConnect, ToolVariables.MQTT_ID)
        if connectStatus ~= true then
            EcoLog("MQTT connect failed, error msg: " .. connectErr)
            return -1
        end
    else
        EcoLog("MQTT create failed, error msg: " .. createErr)
        return -1
    end
    return 0
end

-- MQTT发布
function MainApp.MqttPublish(connectId, topic, message)
    local count = 0
    while count < 3 do
        local status, err = pcall(MqttFunc.MQTTPublish, connectId, topic,
                                  message, 0, false)
        if status then break end
        count = count + 1
        EcoLog("MOTT Publish failed, error msg:" .. err)
    end
    -- 发布三次失败，重新创建
    if count == 3 then
        local disStatus, err = pcall(MqttFunc.MQTTDisconnect, connectId)
        if disStatus == false then EcoLog("断连MQTT" .. err) end
        EcoLog("ReCreate MQTT")
        local res = MainApp.MqttCreate()
        if res ~= -1 then
            local status, err = pcall(MqttFunc.MQTTPublish, connectId, topic,
                                      message, 0, false)
            -- 重新发布后依旧失败
            if status ~= true then
                EcoLog("After recreate MQTT, publish failed: " .. err)
            end
        end
    end
end

---------------------------------- MQTT相关 ↑ -------------------------------------

---------------------------------- RPC相关 ↓ -------------------------------------

-- 建立RPC通讯
function MainApp.RPCServerCreate()
    EcoLog("daemon rcp server thread has running.......")
    local _isOk, _data = pcall(ToolUtils.RPCServerCreate,
                               MainApp.RPCMethodHandler)
    if not _isOk then EcoLog(tostring(_data)) end
    EcoLog("daemon rcp server thread has finished!!!")
end

-- RPC 通讯方法处理
function MainApp.RPCMethodHandler(method, params)
    if nil ~= MethodCenter[method] then
        -- EcoLog('MethodCenter execute, method= ' .. method)
        -- EcoLog(params)
        local _isOk, result = pcall(MethodCenter[method], params)
        if not _isOk then
            EcoLog('MethodCenter, ' .. method .. ' method, error: ' .. result)
            return ToolUtils.HttpResponse(false, result,
                                          ToolVariables.RPC_ERR_CODE.Unknown)
        else
            return result
        end
    else
        local errMsg = 'MethodCenter, ' .. method .. ' method not found'
        return ToolUtils.HttpResponse(false, errMsg,
                                      ToolVariables.RPC_ERR_CODE.Method)
    end
end

---------------------------------- 信号检查循环 ↓ -------------------------------------
local function LightInit(palletIndex)
    if palletIndex == 0 then
        DO(1, 0) -- 黄灯灭
        DO(2, 0) -- 绿灯灭
        DO(3, 0) -- 红灯灭
    else
        DO(4, 0) -- 黄灯灭
        DO(5, 0) -- 绿灯灭
        DO(6, 0) -- 红灯灭
    end
end

local function LightYellowOn(palletIndex)
    if palletIndex == 0 then
        DO(1, 1) -- 黄灯常亮
        DO(2, 0) -- 绿灯灭
        DO(3, 0) -- 红灯灭
    else
        DO(4, 1) -- 黄灯常亮
        DO(5, 0) -- 绿灯灭
        DO(6, 0) -- 红灯灭
    end
end

local function BuzzerOff()
    if SignalMap.buzzerEnable == 1 then
        DO(SignalMap.buzzerOn, 0) -- 蜂鸣器灭
    end
end

local function CheckPalletState(palletIndex)
    if palletIndex == 0 then
        local workState = GetVal('LWorkState')
        if workState == 3 and
            (DI(SignalMap.leftPalletReady[1]) ~= 1 or
                DI(SignalMap.leftPalletReady[2]) ~= 1) then
            SignalMap.palletFResetL = true
            EcoLog('leftPalletReady palletFResetL')
            LightYellowOn(0)
        end
        if SignalMap.palletFResetL == true and
            (DI(SignalMap.leftPalletReady[1]) == 1 and
                DI(SignalMap.leftPalletReady[2]) == 1) then
            SignalMap.palletFResetL = false
            EcoLog('leftPalletReady palletSReset')
            SetVal('LButton', false)
            SetVal('LRSignal', true)
            LightInit(0)
            BuzzerOff()
        end
    else
        local workState = GetVal('RWorkState')
        EcoLog('RWorkState', workState)
        if workState == 3 and
            (DI(SignalMap.rightPalletReady[1]) ~= 1 or
                DI(SignalMap.rightPalletReady[2]) ~= 1) then
            SignalMap.palletFResetR = true
            EcoLog('rightPalletReady palletFResetR')
            LightYellowOn(1)
        end
        if SignalMap.palletFResetR == true and
            (DI(SignalMap.rightPalletReady[1]) == 1 and
                DI(SignalMap.rightPalletReady[2]) == 1) then
            SignalMap.palletFResetR = false
            EcoLog('rightPalletReady palletSReset')
            SetVal('RButton', false)
            SetVal('RRSignal', true)
            LightInit(1)
            BuzzerOff()
        end
    end
end

function MainApp.SignalCheckLoop()
    local configs = GetVal(ToolVariables.DATA_KEY.stationConfigs)
    if configs ~= nil then
        local signal = configs.basic.signal

        SignalMap.palletConfirmEnable = signal.pallet.palletConfirmEnable
        SignalMap.buzzerEnable = signal.other.buzzerEnable

        SignalMap.leftPalletConfirm = signal.pallet.leftPalletConfirm
        SignalMap.rightPalletConfirm = signal.pallet.rightPalletConfirm
        SignalMap.leftPalletReady = signal.pallet.leftPalletReady
        SignalMap.rightPalletReady = signal.pallet.rightPalletReady
        SignalMap.buzzerOn = signal.other.buzzerOn

        EcoLog(" --- SignalCheckLoop SignalMap  --- ", json.encode(SignalMap))

        local function pfnExec()
            MainApp.isSignalChecking = true
            while true do
                if MainApp.isSignalChecking == false then break end
                -- 检查栈板到位信号
                CheckPalletState(0)
                CheckPalletState(1)

                -- 检查栈板确认信号
                if SignalMap.palletConfirmEnable == 1 then
                    local leftPalletConfirmStatus = DI(
                                                        SignalMap.leftPalletConfirm) -- 左栈板确认信号
                    if leftPalletConfirmStatus == 1 then
                        -- EcoLog(" --- LeftPalletConfirm Success  --- ")
                        SetVal('LButton', true)
                    end

                    local rightPalletConfirmStatus = DI(
                                                         SignalMap.rightPalletConfirm) -- 右栈板确认信号
                    if rightPalletConfirmStatus == 1 then
                        -- EcoLog(" --- RightPalletConfirm Success  --- ")
                        SetVal('RButton', true)
                    end
                end
                Wait(500)
            end
        end
        systhread.create(pfnExec)
    end
end

---------------------------------- 通用方法实现 ↓ -------------------------------------

--[[
描述：Modbus连接
参数：ip：Modbus连接的ip地址；port：端口号；
]] --
function MethodCenter.ModbusConnect(data)
    if MethodCenter.ModbusID ~= nil then ModbusClose(MethodCenter.ModbusID) end

    local err, modbusID = ModbusCreate(data.ip, data.port)
    if err ~= 0 then
        -- Modbus连接失败
        local errMsg = 'Modbus Connect Failed'
        return ToolUtils.HttpResponse(false, errMsg,
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end

    EcoLog('Modbus Connect Success')
    MethodCenter.ModbusID = modbusID
    return ToolUtils.HttpResponse(true, nil, ToolVariables.RPC_ERR_CODE.OK)
end

-- Modbus断开连接
function MethodCenter.ModbusDisconnect()
    if MethodCenter.ModbusID ~= nil then ModbusClose(MethodCenter.ModbusID) end
    MethodCenter.ModbusID = nil
    return ToolUtils.HttpResponse(true, nil, ToolVariables.RPC_ERR_CODE.OK)
end

--[[
描述：Modbus读取
参数：data：寄存器地址，table形式
]] --
function MethodCenter.ModbusRead(data)
    if MethodCenter.ModbusID == nil then
        local errMsg = 'Modbus not connected'
        return ToolUtils.HttpResponse(false, errMsg,
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end

    local result = {}
    for k, v in ipairs(data) do
        local buffer = GetHoldRegs(MethodCenter.ModbusID, v, 1, "U16")
        if buffer[1] ~= nil then
            table.insert(result, buffer[1])
        else
            table.insert(result, false)
        end
    end
    return ToolUtils.HttpResponse(true, result, ToolVariables.RPC_ERR_CODE.OK)
end

--[[
描述：Modbus写入
参数：data：寄存器地址，table形式 { [1]={address=1, value=1} }
]] --
function MethodCenter.ModbusWrite(data)
    if MethodCenter.ModbusID == nil then
        local errMsg = 'Modbus not connected'
        return ToolUtils.HttpResponse(false, errMsg,
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end

    for k, v in ipairs(data) do
        SetHoldRegs(MethodCenter.ModbusID, math.floor(v['address']), 1,
                    {math.floor(v['value'])}, "U16")
    end
    return ToolUtils.HttpResponse(true, nil, ToolVariables.RPC_ERR_CODE.OK)
end

function MethodCenter.GetLiftkitInstance()
    local configs = GetVal(ToolVariables.DATA_KEY.stationConfigs)
    if configs.basic.lift == 0 then return false end
    if configs.basic.liftBrand == 1 then
        return LiftkitGeming
    elseif configs.basic.liftBrand == 3 then
        return LiftkitLinAK
    else
        return LiftkitEwellix
    end
end

--[[
描述：升降柱连接
data：ip：升降柱连接的ip地址；port：端口号；
]] --
function MethodCenter.LiftkitConnect(data)
    if data == nil then data = {ip = "192.168.5.100", port = 50001} end
    -- 如果已连接，返回标准格式
    if MethodCenter.LiftkitManager.connected then
        return ToolUtils.HttpResponse(true, "Already connected",
                                      ToolVariables.RPC_ERR_CODE.OK)
    end

    local liftkitInstance = MethodCenter.GetLiftkitInstance()
    if not liftkitInstance then
        -- 升降柱功能未启用，返回标准格式
        return ToolUtils.HttpResponse(true, "Liftkit disabled",
                                      ToolVariables.RPC_ERR_CODE.OK)
    else
        MethodCenter.LiftkitManager.instance = liftkitInstance

        -- 添加日志确认执行到这里
        EcoLog('Attempting to connect liftkit: ' .. data.ip .. ':' .. data.port)

        local result = MethodCenter.LiftkitManager.instance.Connect(data.ip,
                                                                    data.port)

        EcoLog('Liftkit connect result: ' .. tostring(result))
        if result then
            -- 连接成功
            MethodCenter.LiftkitManager.connected = true
            EcoLog('Liftkit connected successfully, calling HttpResponse')
            return ToolUtils.HttpResponse(true, nil,
                                          ToolVariables.RPC_ERR_CODE.OK)
        else
            -- 连接失败
            MethodCenter.LiftkitManager.connected = false
            EcoLog('Liftkit connection failed, calling HttpResponse')
            return ToolUtils.HttpResponse(false, 'LiftkitConnect Failed',
                                          ToolVariables.RPC_ERR_CODE.Unknown)
        end
    end
end

-- 升降柱断开连接
function MethodCenter.LiftkitDisconnect()
    if MethodCenter.LiftkitManager.instance ~= nil then
        MethodCenter.LiftkitManager.instance.Disconnect()
        MethodCenter.LiftkitManager.instance = nil
        MethodCenter.LiftkitManager.connected = false
    end
    return ToolUtils.HttpResponse(true, nil, ToolVariables.RPC_ERR_CODE.OK)
end

-- 升降柱获取当前位置
function MethodCenter.LiftkitGetPosition()
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitGetPosition Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end

    local result = MethodCenter.LiftkitManager.instance.GetPosition()
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

-- 升降柱移动
function MethodCenter.LiftkitMoveTo(data)
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitMoveTo Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end
    local result = MethodCenter.LiftkitManager.instance.MoveTo(data)
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

function MethodCenter.LiftkitJogTo(data)
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitJogTo Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end
    local result = MethodCenter.LiftkitManager.instance.JogTo(data)
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

function MethodCenter.LiftkitMoveStop()
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitMoveStop Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end
    local result = MethodCenter.LiftkitManager.instance.MoveStop()
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

function MethodCenter.LiftkitGetAlarmCode()
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitGetAlarmCode Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end
    local result = MethodCenter.LiftkitManager.instance.GetAlarmCode()
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

function MethodCenter.LiftkitHoming()
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitHoming Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end
    local result = MethodCenter.LiftkitManager.instance.Homing()
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

function MethodCenter.LiftkitHeartBeat()
    if MethodCenter.LiftkitManager.instance == nil then
        return ToolUtils.HttpResponse(false, 'LiftkitHeartBeat Not Connect',
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end
    local result = MethodCenter.LiftkitManager.instance.HeartBeat()
    if result == false then
        return ToolUtils.HttpResponse(false, nil,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    else
        return ToolUtils.HttpResponse(true, result,
                                      ToolVariables.RPC_ERR_CODE.OK)
    end
end

function MethodCenter.MqttPublish(data)
    MainApp.MqttPublish(ToolVariables.MQTT_ID, data.topic, data.data)
end

function MethodCenter.StartSignalCheck() MainApp.SignalCheckLoop() end

function MethodCenter.StopSignalCheck()
    EcoLog(" --- PalletizingApp daemon StopSignalCheck  --- ")
    MainApp.isSignalChecking = false
end

-- 状态轮询，MQTT发送给界面
function MainApp.LiftkitStatusFresh()
    while true do
        if MethodCenter.LiftkitManager.connected and nil ~=
            MethodCenter.LiftkitManager.instance then
            Wait(1000)
            local data = {}
            local position = MethodCenter.LiftkitGetPosition()
            EcoLog('LiftkitGetPosition', position)
            if position.code == 0 then
                data["position"] = position.data
                MainApp.MqttPublish(ToolVariables.MQTT_ID,
                                    "/Palletizing/status", json.encode(data))
            end
        else
            Wait(1000)
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- 日志监控推送线程
local function innerMonitorLog(port)
    local err, sock = TCPCreate(false, "127.0.0.1", port)
    if 0 ~= err then
        EcoLog("-------innerMonitorLog TCPCreate fail,err=" .. tostring(err))
        return false
    end
    local strTopic = "/mqtt/weld/printLog/" .. tostring(port)
    local result
    err = TCPStart(sock, 0)
    if 0 ~= err then
        EcoLog("-------innerMonitorLog TCPStart fail,err=" .. tostring(err))
        goto sockExit
    end
    EcoLog("-------innerMonitorLog starting......:port=" .. tostring(port))
    while true do
        err, result = TCPRead(sock, 0, "string")
        if err ~= 0 then
            EcoLog("-------innerMonitorLog TCPStart fail,err=" .. tostring(err))
            goto sockExit
        elseif type(result) == "string" then
            MainApp.MqttPublish(ToolVariables.MQTT_ID, strTopic, result)
        end
    end
    ::sockExit::
    TCPDestroy(sock)
    sock = nil
    return false
end

local function innerMonitorLogLoop()
    local function pfnExec(port)
        local err, msg
        while true do
            err, msg = pcall(innerMonitorLog, port)
            EcoLog("-------innerMonitorLogLoop end,err=" .. tostring(err) ..
                       ",msg=" .. tostring(msg))
            Wait(3000)
        end
    end
    systhread.create(pfnExec, 65501) -- 监控打印日志
    systhread.create(pfnExec, 65503) -- 监控报错日志
end

function _PalletizingStationStopCallback()
    EcoLog(
        "userAPI脚本停止运行导致触发了回调函数被调用，正在处理停止脚本流程......")
    MainApp.isSignalChecking = false

    pcall(MethodCenter.LiftkitConnect)
    pcall(MethodCenter.LiftkitMoveStop)
    pcall(MethodCenter.LiftkitDisconnect)
    EcoLog(
        "userAPI脚本停止运行导致触发了回调函数被调用，停止脚本流程处理完毕")
end

---------------------------------- 通用方法实现 ↑ -------------------------------------

function MainApp.run()
    MainApp.MqttCreate()
    innerMonitorLogLoop() -- 启动日志监控与推送
    RegisteStopHandler("_PalletizingStationStopCallback") -- 调用生态接口注册回调函数

    MainApp.threads[1] = systhread.create(MainApp.RPCServerCreate)
    MainApp.threads[2] = systhread.create(MainApp.LiftkitStatusFresh)
    MainApp.threads[1]:wait()
    MainApp.threads[2]:wait()
end

MainApp.run()

