-- 随主程序一起运行的并行程序，可设置I/O、变量等，不能调用运动指令。
-- Version: Lua 5.4.0
SleepTime6 = 1000 --子线程等待时间，防止子线程占用CPU过高
local mqttFunc = require("libplugin_eco")


function DealMessage(Topic, Data)
    if Topic == 'simulateSpeed' then
        SimulateProcess.SimulateSpeed = tonumber(Data)
        SimulateProcess.Statistic.BoxCount = 0
        SimulateProcess.Statistic.TotalTime = 0
        SimulateProcess.Statistic.LayerRate = 0              --码垛完一层时平均节拍
        SimulateProcess.Statistic.PalletNum = 0              --剁数
        SimulateProcess.Statistic.PalletTotalTime = 0        --剁有效计时
        SimulateProcess.Statistic.PalletRate = 0             --单栈板耗时

        if SimulateProcess.SimulateSpeed > 1 then
            SimulateProcess.LeftPallet.CanCount = 0
            SimulateProcess.RightPallet.CanCount = 0
        end

        LogInfo("SimulateSpeed: %s", SimulateProcess.SimulateSpeed)
    end
end


local function ChildProcess()
	while true do
        if SimulateProcess.MqttConnected == 1 then
            LogInfo("WAIT Message!")
            local sub = mqttFunc.MQTTSubscribe(ConnectId, "simulateSpeed", 1)
            mqttFunc.MQTTWait(ConnectId, "DealMessage")
        end
        Wait(SleepTime6)
	end
end

ChildProcess()