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
local Plugin = {};
Plugin.suckerSocket = nil

function Plugin.OnUninstall()
    EcoLog("-------Plugin.OnUninstall---- Palletizing ----");
end

function Plugin.OnInstall()
    EcoLog("-------Plugin.OnInstall---- Palletizing ----");
end

------------------- Modbus相关 ----------------------
function Plugin.ModbusConnect(ip, port)
    local data = {
        method = 'ModbusConnect',
        params = {["ip"] = ip, ["port"] = port}
    }
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.ModbusDisconnect()
    local data = {method = 'ModbusDisconnect'}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.ModbusRead(params)
    local data = {method = 'ModbusRead', params = params}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.ModbusWrite(params)
    local data = {method = 'ModbusWrite', params = params}
    return ToolUtils.RPCCallDaemon(data)
end

------------------- 升降柱相关 ----------------------
function Plugin.LiftkitConnect(ip, port)
    local data = {
        method = 'LiftkitConnect',
        params = {["ip"] = ip, ["port"] = port}
    }
    return ToolUtils.RPCCallDaemon(data, 10000)
end

function Plugin.LiftkitDisconnect()
    local data = {method = 'LiftkitDisconnect'}
    return ToolUtils.RPCCallDaemon(data, 2000)
end

function Plugin.LiftkitGetPosition()
    local data = {method = 'LiftkitGetPosition'}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.LiftkitMoveTo(postiion)
    local data = {method = 'LiftkitMoveTo', params = postiion}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.LiftkitJogTo(value)
    local data = {method = 'LiftkitJogTo', params = value}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.LiftkitMoveStop()
    local data = {method = 'LiftkitMoveStop'}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.LiftkitGetAlarmCode()
    local data = {method = 'LiftkitGetAlarmCode'}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.LiftkitHoming()
    local data = {method = 'LiftkitHoming'}
    return ToolUtils.RPCCallDaemon(data, 600000)
end

------------------- 控制器数据库信息存取 ----------------------
function Plugin.GetStationConfigs()
    local configs = GetVal(ToolVariables.DATA_KEY.stationConfigs)
    if configs == nil then return false end
    return configs
end

function Plugin.SetStationConfigs(configs)
    SetVal(ToolVariables.DATA_KEY.stationConfigs, configs)
    return true
end

function Plugin.GetTemporarySave()
    local data = GetVal(ToolVariables.DATA_KEY.temporarySave)
    if not data or not data['index'] or data['index'] < 0 then return false end
    EcoLog('GetTemporarySave', data)
    return data
end

function Plugin.SetTemporarySave(data, index)
    EcoLog('SetTemporarySave', data)
    local table = {}
    table['data'] = data
    table['index'] = index
    SetVal(ToolVariables.DATA_KEY.temporarySave, table)
    return true
end

function Plugin.GetAutoTrasition()
    local data = GetVal(ToolVariables.DATA_KEY.autoTranstition)
    EcoLog('GetAutoTrasition', data)
    if data == nil then return false end
    return data
end

function Plugin.SetAutoTrasition(data)
    EcoLog('SetAutoTrasition', data)
    SetVal(ToolVariables.DATA_KEY.autoTranstition, data)
    return true
end

function Plugin.GetManufacturerConfigs()
    local data = GetVal(ToolVariables.DATA_KEY.manufacturerConfigs)
    EcoLog('GetManufacturerConfigs', data)
    if data == nil then return false end
    return data
end

function Plugin.SetManufacturerConfigs(data)
    EcoLog('SetManufacturerConfigs', data)
    SetVal(ToolVariables.DATA_KEY.manufacturerConfigs, data)
    return true
end

function Plugin.GetPatternLibrary()
    local data = GetVal(ToolVariables.DATA_KEY.patternLibrary)
    EcoLog('GetPatternLibrary', data)
    if data == nil then return false end
    return data
end

function Plugin.SetPatternLibrary(data)
    EcoLog('SetPatternLibrary', data)
    SetVal(ToolVariables.DATA_KEY.patternLibrary, data)
    return true
end

------------------- 控制器文件读写 ----------------------
function Plugin.FileSysRead(path) return ToolUtils.FileSysRead(path) end

function Plugin.FileSysWrite(path, content)
    return ToolUtils.FileSysWrite(path, content)
end

function Plugin.GetParams() return ParamsHandle.Get() end

function Plugin.SetParams(data) return ParamsHandle.Set(data) end

function Plugin.GetProjectTemplate(mode) return TemplateLoader.GetContent(mode) end

-- 控制器数据库通用读取接口
function Plugin.DatabaseRead(key) return GetVal(key) end

-- 控制器数据库通用设置接口
function Plugin.DatabaseWrite(key, value) return SetVal(key, value) end

------------------- 吸盘相关 ----------------------

-- DO控制(通用吸盘)
function Plugin.SetDOState(address, on)
    for i, v in ipairs(address) do
        if v ~= nil and v > 0 then
            if v > 28 then
                ToolDO(v - 28, on)
            else
                DO(v, on)
            end
        end
    end
    return true
end

-- TCP控制(Piab吸盘)
function Plugin.SetSuctionTCP(on)
    if on == 1 then
        if Plugin.suckerSocket ~= nil then
            TCPDestroy(Plugin.suckerSocket)
            Plugin.suckerSocket = nil
        end

        local Err = 0
        SetTool485(115200, "N", 1)
        Err, socket = TCPCreate(false, "127.0.0.1", 60000) -- 创建TCP客户端
        Err = TCPStart(socket, 5) -- 建立TCP连接
        if Err == 0 then
            Plugin.suckerSocket = socket
            TCPWrite(socket, {
                0x01, 0x07, 0x00, 0x01, 0x00, 0x29, 0x02, 0x01, 0x00, 0x82
            })
            return true
        else
            TCPDestroy(socket)
            Plugin.suckerSocket = nil
            return false
        end
    else
        if Plugin.suckerSocket ~= nil then
            TCPWrite(socket, {
                0x01, 0x07, 0x00, 0x01, 0x00, 0x29, 0x02, 0x00, 0x00, 0x97
            })
            TCPDestroy(Plugin.suckerSocket)
            Plugin.suckerSocket = nil
        end
        return true
    end
end

return Plugin;
