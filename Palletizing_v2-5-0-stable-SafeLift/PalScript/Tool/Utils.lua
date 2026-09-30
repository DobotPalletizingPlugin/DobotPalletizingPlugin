require('PalScript.Tool.Variables')
local ToolUtils = {RPC_OK = false}

local PalletizingAppRPCMethodHandler = nil

------------------- RPC通讯 ----------------------

function ToolUtils.RPCServerCreate(requestCallback)
    PalletizingAppRPCMethodHandler = requestCallback
    local err, errMsg = RPCCreate(true, ToolVariables.RPC_NODENAME, 1) -- 此函数为服务端时，如果创建成功则阻塞，失败就立刻返回。
    if 0 == err then
        EcoLog("rpc server create success!!!")
    elseif -1 == err then
        EcoLog("rpc server create fail,errmsg=" .. tostring(errMsg))
    elseif -2 == err then
        EcoLog("rpc server create fail because of connect fail,errmsg=" ..
                   tostring(errMsg))
    elseif -3 == err then
        EcoLog("rpc server create fail because of invalid parameter,errmsg=" ..
                   tostring(errMsg))
    elseif -4 == err then
        EcoLog("rpc server create fail because of repeat create,errmsg=" ..
                   tostring(errMsg))
    else
        EcoLog("rpc server create fail,errmsg=" .. tostring(errMsg))
    end
end

function ToolUtils.RPCConnectDaemon()
    if not ToolUtils.RPC_OK then
        local err, errMsg = RPCCreate(false, ToolVariables.RPC_NODENAME)
        if 0 == err then
            ToolUtils.RPC_OK = true
            EcoLog("rpc client create success!!!")
            return true
        elseif -1 == err then
            EcoLog("rpc client create fail,errmsg=" .. tostring(errMsg))
        elseif -2 == err then
            EcoLog("rpc client create fail because of connect fail,errmsg=" ..
                       tostring(errMsg))
        elseif -3 == err then
            EcoLog(
                "rpc client create fail because of invalid parameter,errmsg=" ..
                    tostring(errMsg))
        elseif -4 == err then
            EcoLog("rpc client create fail because of repeat create,errmsg=" ..
                       tostring(errMsg))
        else
            EcoLog("rpc client create fail,errmsg=" .. tostring(errMsg))
        end
    end
    return false
end

function _PalletizingAppLuaRPCExecute(data)
    return PalletizingAppRPCMethodHandler(data.method, data.params)
end

function ToolUtils.RPCCallDaemon(data, timeoutMs)
    ToolUtils.RPCConnectDaemon()

    -- timeoutMs的时间判断，结合上下文看此段逻辑
    if nil == timeoutMs then
        timeoutMs = 10000
    elseif timeoutMs < 0 or timeoutMs > 10000 then
        timeoutMs = 0
    end

    local callInfo = {
        ToolVariables.RPC_NODENAME, -- rpc服务的节点名
        timeoutMs -- 最大的调用等待时间ms,填0或者不填表示无限等待直到返回,为(0,10000]表示等待的时间ms,其他值控制器不支持
    }

    local resultInfo, result = RPCCall(callInfo, "_PalletizingAppLuaRPCExecute",
                                       data)
    if resultInfo.isErr ~= 0 then
        EcoLog("rpcCallDeamon call fail,method:" .. data.method .. ",errmsg:" ..
                   tostring(resultInfo.errMsg))
        return nil
    else
        return result
    end
end

function ToolUtils.HttpResponse(isOk, data, errcode)
    local result = {}
    if isOk then
        result.code = errcode
        result.errmsg = ""
        result.data = data
    else
        result.code = errcode
        result.errmsg = data
        result.data = ""
        EcoLog(data)
    end
    return result
end

------------------- 控制器文件读写 ----------------------

function ToolUtils.FileSysRead(path)
    local file = io.open(path, "r")
    if file then
        local content = file:read("*a") -- 读取文件中的所有内容
        EcoLog('FileSysRead success: ' .. path)
        file:close()
        return {code = 0, data = content}
    else
        local errmsg = "Failed to open file."
        EcoLog(errmsg)
        return {code = 1, data = '', errmsg = errmsg}
    end
end

function ToolUtils.FileSysWrite(path, content)
    local file = io.open(path, "w")
    if file then
        file:write(content)
        file:close()
        return {code = 0}
    else
        local errmsg = "Failed to open file for writing."
        EcoLog(errmsg)
        return {code = 1, data = '', errmsg = errmsg}
    end
end

return ToolUtils
