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

local Plugin = {}

function Plugin.PalletizingAppUserScriptRunStateChanged(eventName)
    EcoLog(
        " --- PalletizingApp userAPI PalletizingAppUserScriptRunStateChanged  --- ",
        eventName)
    if eventName == 'pause' then
        ToolUtils.RPCCallDaemon({method = 'UserScriptPauseCallback'})
    elseif eventName == 'continue' then
        ToolUtils.RPCCallDaemon({method = 'UserScriptContinueCallback'})
    end
end

function Plugin.PalletizingStartSignalCheck()
    local data = {method = 'StartSignalCheck'}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.PalletizingStopSignalCheck()
    local data = {method = 'StopSignalCheck'}
    return ToolUtils.RPCCallDaemon(data)
end

function Plugin.OnRegist()
    EcoLog(" --- PalletizingApp userAPI Plugin.OnRegist  --- ")
    local callbackName = 'PalletizingAppUserScriptRunStateChanged'
    ExportFunction(callbackName, Plugin.PalletizingAppUserScriptRunStateChanged)
    ExportFunction("PalletizingStartSignalCheck", Plugin.PalletizingStartSignalCheck)
    ExportFunction("PalletizingStopSignalCheck", Plugin.PalletizingStopSignalCheck)
    -- RegistePauseHandler(callbackName) -- 调用生态框架接口注册回调函数
    -- RegisteContinueHandler(callbackName) -- 调用生态框架接口注册回调函数

end

return Plugin
