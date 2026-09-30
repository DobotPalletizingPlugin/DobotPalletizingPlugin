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
local MainApp = {threads = {},isSignalChecking = false}
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

    EcoLog('Modbus Connect Success！')
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
local PalletBusAddressMap = {
    [5000] = 0, [5001] = 1, [5002] = 2, [5004] = 3,
    [5010] = 4, [5011] = 5, [5012] = 6, [5013] = 7,
    [5014] = 8, [5015] = 9, [5016] = 10,
    [5020] = 11, [5021] = 12, [5024] = 13, [5025] = 14,
    [5030] = 16, [5038] = 22, [5039] = 23
}

function MethodCenter.ModbusWrite(data)
    if MethodCenter.ModbusID == nil then
        local errMsg = 'Modbus not connected'
        return ToolUtils.HttpResponse(false, errMsg,
                                      ToolVariables.RPC_ERR_CODE.Connect)
    end

    local bus = {attempted = 0, written = 0, values = {}, errors = {}}
    local modbusErrors = {}
    for k, v in ipairs(data) do
        local modbusAddress = math.floor(v['address'])
        local value = math.floor(v['value'])
        local modbusErr = SetHoldRegs(MethodCenter.ModbusID, modbusAddress, 1,
                                      {value}, "U16")
        if modbusErr ~= 0 then
            table.insert(modbusErrors, {address = modbusAddress,
                                        error = tostring(modbusErr)})
        end
        local busAddress = PalletBusAddressMap[modbusAddress]
        if busAddress ~= nil then
            bus.attempted = bus.attempted + 1
            if modbusErr == 0 then
                local ok, err = pcall(SetOutputInt, busAddress, value)
                if ok then
                    bus.written = bus.written + 1
                    table.insert(bus.values, {modbusAddress = modbusAddress,
                                              busAddress = busAddress,
                                              value = value})
                else
                    table.insert(bus.errors, {modbusAddress = modbusAddress,
                                              busAddress = busAddress,
                                              stage = "bus",
                                              error = "SetOutputInt: " .. tostring(err)})
                end
            else
                table.insert(bus.errors, {modbusAddress = modbusAddress,
                                          busAddress = busAddress,
                                          stage = "modbus",
                                          error = "SetHoldRegs code=" .. tostring(modbusErr)})
            end
        end
    end
    if #modbusErrors > 0 or #bus.errors > 0 then
        EcoLog("[BusSync][daemon] " ..
                   json.encode({bus = bus, modbusErrors = modbusErrors}))
    end
    local code = (#modbusErrors == 0 and #bus.errors == 0) and
                     ToolVariables.RPC_ERR_CODE.OK or
                     ToolVariables.RPC_ERR_CODE.Unknown
    return ToolUtils.HttpResponse(true, {bus = bus, modbusErrors = modbusErrors}, code)
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
        local result = MethodCenter.LiftkitManager.instance.Disconnect()
        if result == false then
            return ToolUtils.HttpResponse(false, 'LiftkitDisconnect Failed',
                                          ToolVariables.RPC_ERR_CODE.Unknown)
        end
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

-- 生产数据管理模块（守护线程和 RPC 共享）
-- 分片存储：current.json（写入中） + production_YYYYMMDD.json（归档）
-- 满了自动归档，减少文件数，方便备份拷贝
local ProductionData = {
    dir = "/dobot/userdata/user_project/process/pallet/productionData/",
    currentFile = "/dobot/userdata/user_project/process/pallet/productionData/current.json",
    maxFileSize = 1024 * 1024, -- 1MB，超过则归档
}

function ProductionData.readFile(path)
    local file = io.open(path, "r")
    if not file then return { records = {} } end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(json.decode, content)
    if ok and data then return data end
    return { records = {} }
end

function ProductionData.writeFile(path, data)
    local file = io.open(path, "w")
    if not file then
        EcoLog("ProductionData: write file failed, path=" .. path)
        return false
    end
    file:write(json.encode(data))
    file:close()
    return true
end

-- 归档当前文件：重命名带时间戳，新建空文件
function ProductionData.archiveCurrent()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local archivePath = ProductionData.dir .. "production_" .. timestamp .. ".json"
    local ok, err = os.rename(ProductionData.currentFile, archivePath)
    if not ok then
        EcoLog("ProductionData: archive failed: " .. tostring(err))
        return false
    end
    EcoLog("ProductionData: current file archived to " .. archivePath)
    ProductionData.writeFile(ProductionData.currentFile, { records = {} })
    return true
end

-- 添加新记录到当前文件（自动归档）
function ProductionData.appendRecord(record)
    local data = ProductionData.readFile(ProductionData.currentFile)
    table.insert(data.records, record)
    -- 检查文件大小，超过阈值则归档
    local file = io.open(ProductionData.currentFile, "r")
    if file then
        local size = file:seek("end")
        file:close()
        if size and size > ProductionData.maxFileSize then
            if ProductionData.archiveCurrent() then
                data = ProductionData.readFile(ProductionData.currentFile)
                table.insert(data.records, record)
            end
            -- 归档失败时继续写入当前文件，数据不丢失（文件会略超阈值）
        end
    end
    ProductionData.writeFile(ProductionData.currentFile, data)
end

-- 清理所有文件中超过180天的旧记录（按记录内的 startTime 判断）
function ProductionData.cleanupOldFiles()
    local cutoff = os.time() - 180 * 86400
    local handle = io.popen('find "' .. ProductionData.dir .. '" -name "*.json" -type f')
    if not handle then return end
    local result = handle:read("*a")
    handle:close()
    for filePath in result:gmatch("[^\n]+") do
        local data = ProductionData.readFile(filePath)
        local totalBefore = #data.records
        local newRecords = {}
        for _, record in ipairs(data.records) do
            if record.startTime and record.startTime >= cutoff then
                table.insert(newRecords, record)
            end
        end
        if #newRecords < totalBefore then
            if #newRecords > 0 then
                -- 部分过期，重写文件保留有效记录
                data.records = newRecords
                ProductionData.writeFile(filePath, data)
            elseif filePath == ProductionData.currentFile then
                -- current.json 是活动文件不能删除，清空记录即可
                ProductionData.writeFile(filePath, { records = {} })
            else
                -- 全部过期，直接删除文件
                os.remove(filePath)
            end
            EcoLog("ProductionData: cleanup " .. filePath .. ", removed " .. (totalBefore - #newRecords) .. " records")
        end
        ::continue::
    end
end

function ProductionData.queryRange(startDate, endDate, projectName)
    local function parseDate(dateStr)
        local y, m, d = dateStr:match("(%d+)-(%d+)-(%d+)")
        if not y then return nil end
        return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
    end

    local startTs = parseDate(startDate)
    local endTs = parseDate(endDate)
    if not startTs or not endTs then return false, "invalid date format" end
    if startTs > endTs then return false, "startDate must be before endDate" end

    local dayCount = math.floor((endTs - startTs) / 86400) + 1
    if dayCount > 180 then return false, "date range exceeds 180 days" end

    -- 读取所有分片文件，合并过滤
    local allRecords = {}
    local handle = io.popen('find "' .. ProductionData.dir .. '" -name "*.json" -type f')
    if handle then
        local result = handle:read("*a")
        handle:close()
        for filePath in result:gmatch("[^\n]+") do
            -- 从文件名提取归档日期做初步过滤（production_YYYYMMDD_HHMMSS.json）
            -- 注意：归档日期是文件写满被重命名的时间，文件中可能包含更早的记录
            -- 因此只能跳过归档日期完全在查询范围之前的文件，不能跳过之后的
            local fileDate = filePath:match("production_(%d%d%d%d%d%d%d%d)_")
            if fileDate then
                local fileTs = os.time({
                    year = tonumber(fileDate:sub(1, 4)),
                    month = tonumber(fileDate:sub(5, 6)),
                    day = tonumber(fileDate:sub(7, 8))
                })
                if fileTs and fileTs + 86399 < startTs then goto continue end
            end
            local data = ProductionData.readFile(filePath)
            for _, record in ipairs(data.records) do
                if record.startTime >= startTs and record.startTime <= endTs + 86399 then
                    if not projectName or projectName == "" or string.find(string.lower(record.projectName), string.lower(projectName), 1, true) then
                        table.insert(allRecords, record)
                    end
                end
            end
            ::continue::
        end
    end

    table.sort(allRecords, function(a, b) return a.startTime > b.startTime end)
    return true, { records = allRecords }
end

-- 守护线程：监听工程启停，持久化生产数据到文件
local function ProductionDataLoop()
    local function pfnExec()
        pcall(function() os.execute('mkdir -p "' .. ProductionData.dir .. '"') end)
        -- 初始化：确保 current.json 存在
        local file = io.open(ProductionData.currentFile, "r")
        if not file then
            ProductionData.writeFile(ProductionData.currentFile, { records = {} })
        else
            file:close()
        end

        -- 启动时清理一次，保证系统重启后即使不运行脚本也能清理过期数据
        local lastCleanupDate = ""
        do
            local today = os.date("%Y%m%d")
            ProductionData.cleanupOldFiles()
            lastCleanupDate = today
        end

        local prevRunning = false
        local currentRecord = nil
        local baselineCapacity = nil
        local isExhibitionMode = false  -- 标记本次运行是否为展会模式（启动时判定，停止时使用）
        local err, msg

        while true do
            err, msg = pcall(function()
                local scriptState = GetVal("ScriptState")
                local isRunning = (scriptState == true)
                local now = os.time()
                EcoLog("ProductionDataLoop: isRunning=" .. tostring(isRunning))

                if isRunning and not prevRunning then
                    -- 展会模式PalletWorkingMode = 3，通过此推断展会模式
                    -- 展会模式不记录生产数据
                    local workingMode = GetVal("PalletWorkingMode")
                    isExhibitionMode = (workingMode == 3)
                    if isExhibitionMode then
                        EcoLog(" --- daemon 检测到展会模式, 跳过生产数据记录 ---")
                    else
                        local projectName = GetVal("PalletProjectName")
                        local capacity = GetVal("PalletCapacity")
                        if capacity and type(capacity) == "table" then
                            baselineCapacity = {
                                pallet = tonumber(capacity.Pallet) or 0,
                                box = tonumber(capacity.Box) or 0
                            }
                        else
                            baselineCapacity = { pallet = 0, box = 0 }
                        end
                        currentRecord = {
                            projectName = tostring(projectName),
                            startTime = now,
                            endTime = nil,
                            boxCount = 0,
                            palletCount = 0,
                            runTime = 0
                        }
                        EcoLog(" --- daemon 检测到工程启动, 工程名: " .. tostring(projectName) ..
                            ", 启动前产能: " .. tostring(baselineCapacity.pallet) ..
                            ", " .. tostring(baselineCapacity.box))
                    end
                end

                if not isRunning and prevRunning then
                    if isExhibitionMode then
                        -- 展会模式不记录生产数据，仅复位标志
                        EcoLog(" --- daemon 检测到展会工程停止, 结束时间: " .. tostring(now) ..
                            "（展会模式，跳过生产数据记录） --- ")
                        isExhibitionMode = false
                    elseif currentRecord then
                        local record = currentRecord
                        currentRecord = nil
                        record.endTime = now
                        record.runTime = now - record.startTime

                        local capacity = GetVal("PalletCapacity")
                        if capacity and type(capacity) == "table" then
                            local curPallet = tonumber(capacity.Pallet) or 0
                            local curBox = tonumber(capacity.Box) or 0
                            record.palletCount = curPallet - baselineCapacity.pallet
                            record.boxCount = curBox - baselineCapacity.box

                            -- 运行期间计数被重置导致差值小于0时，直接取当前最新值
                            if record.palletCount < 0 then
                                record.palletCount = curPallet
                            end
                            if record.boxCount < 0 then
                                record.boxCount = curBox
                            end
                        end

                        local countMultipleData = GetVal("CountMultiple")
                        local countMultiple = 1
                        if countMultipleData and type(countMultipleData) == "table" then
                            countMultiple = tonumber(countMultipleData.value) or 1
                        end
                        if countMultiple <= 0 then countMultiple = 1 end
                        record.boxCount = record.boxCount * countMultiple

                        baselineCapacity = nil

                        if record.palletCount == 0 and record.boxCount == 0 then
                            EcoLog(" --- daemon 检测到工程停止, 结束时间: " .. tostring(now) ..
                                "（产能为0，跳过记录） --- ")
                        else
                            ProductionData.appendRecord(record)

                            EcoLog(" --- daemon 检测到工程停止, 结束时间: " .. tostring(now) ..
                                ", 记录已保存: pallet=" ..
                                tostring(record.palletCount) ..
                                ", box=" .. tostring(record.boxCount) ..
                                ", countMultiple=" .. tostring(countMultiple) ..
                                ", runtime=" ..
                                tostring(record.runTime) .. "s" .. " --- ")
                        end
                    else
                        EcoLog(" --- daemon 检测到工程停止, 结束时间: " .. tostring(now) ..
                            "（无进行中的生产记录） --- ")
                    end
                end

                -- 工程未运行时，每天清理一次超过180天的旧数据
                if not isRunning and prevRunning then
                    local today = os.date("%Y%m%d")
                    if today ~= lastCleanupDate then
                        ProductionData.cleanupOldFiles()
                        lastCleanupDate = today
                    end
                end

                prevRunning = isRunning
            end)
            if not err then
                EcoLog("ProductionDataLoop error: " .. tostring(msg))
            end
            Wait(1000)
        end
    end
    systhread.create(pfnExec)
end

-- RPC: 查询生产数据（时间段范围 + 可选工程名筛选）
function MethodCenter.GetProductionRecords(params)
    if not params then params = {} end
    local startDate = params.startDate or os.date("%Y-%m-%d")
    local endDate = params.endDate or startDate
    local projectName = params.projectName

    local ok, packed = pcall(function()
        return { ProductionData.queryRange(startDate, endDate, projectName) }
    end)
    if not ok then
        return ToolUtils.HttpResponse(false, tostring(packed),
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    end

    local success, result = packed[1], packed[2]
    if not success then
        return ToolUtils.HttpResponse(false, result,
                                      ToolVariables.RPC_ERR_CODE.Unknown)
    end
    return ToolUtils.HttpResponse(true, result, ToolVariables.RPC_ERR_CODE.OK)
end

function _PalletizingStationStopCallback()
    EcoLog("userAPI脚本停止运行导致触发了回调函数被调用，正在处理停止脚本流程......")
    MainApp.isSignalChecking = false
    SetVal("ScriptState", false)

    pcall(MethodCenter.LiftkitConnect)
    pcall(MethodCenter.LiftkitMoveStop)
    pcall(MethodCenter.LiftkitDisconnect)
    EcoLog("userAPI脚本停止运行导致触发了回调函数被调用，停止脚本流程处理完毕")
end

---------------------------------- 通用方法实现 ↑ -------------------------------------

function MainApp.run()
    MainApp.MqttCreate()
    SetVal("ScriptState", false) -- 初始化脚本状态为停止
    innerMonitorLogLoop() -- 启动日志监控与推送
    ProductionDataLoop() -- 启动生产数据持久化（含工程状态追踪）
    RegisteStopHandler("_PalletizingStationStopCallback") -- 调用生态接口注册回调函数

    MainApp.threads[1] = systhread.create(MainApp.RPCServerCreate)
    MainApp.threads[2] = systhread.create(MainApp.LiftkitStatusFresh)
    MainApp.threads[1]:wait()
    MainApp.threads[2]:wait()
end

MainApp.run()

