require('PalScript.Tool.Utils')

local ParamsHandle = {}
local PARAMS_PATH = '/dobot/userdata/user_project/process/pallet/params.json'

function ParamsHandle.Get()
    local readFile = ToolUtils.FileSysRead(PARAMS_PATH)
    EcoLog('ParamsHandle Get', readFile)
    if readFile.code == 0 then
        -- 读取成功操作,暂先返回字符串
        -- 如果此处进行json编码处理成table形式，原来为空数组的字段到上位机后会变成空对象，有报错风险
        return readFile.data
    else
        return '"[]"'
    end
end

function ParamsHandle.Set(data) return ToolUtils.FileSysWrite(PARAMS_PATH, data) end

function ParamsHandle.Delete() end

return ParamsHandle
