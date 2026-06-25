local ToolVariables = {}

ToolVariables.RPC_NODENAME = "Dobot_Lifting_Plugin_RPC_NodeName_Palletizing"
ToolVariables.MQTT_ID = "PalletizingMQTTClient"

ToolVariables.RPC_ERR_CODE = {
    OK = 0,      -- 无错误
    Param = 1,   -- 参数错误
    Method = 2,  -- 未找到对应方法
    Connect = 3, -- 连接错误
    Unknown = 4  -- 未知错误
}

ToolVariables.DATA_KEY = {
    stationConfigs = "palletizing-station-configs",
    temporarySave = "palletizing-temporary-save",
    autoTranstition = "palletizing-auto-transition",
    manufacturerConfigs = "palletizing-manufacturer-configs",
    patternLibrary = "palletizing-pattern-library-major" -- major用于区分花王版本字段
}

return ToolVariables
