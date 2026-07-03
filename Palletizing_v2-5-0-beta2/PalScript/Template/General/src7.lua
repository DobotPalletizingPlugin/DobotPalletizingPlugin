-- 子线程，随主线程一起运行的并行程序，可设置I/O、通讯、变量等，不能调用运动指令。
SleepTime7 = 100  				--子线程等待时间，防止子线程占用CPU过高

local mqttFunc = require("libplugin_eco")


local function ToStr(tbl)
    local str = "{"
    for k, v in pairs(tbl) do
      str = str .. '"' .. k .. '":'
      if type(v) ~= "function" then
        if type(v) == "table" then
            if next(v) == nil then
                str = str .. '{}' .. ","
            else
                str = str .. ToStr(v) .. ","
            end
        elseif v == nil then
            str = str .. 'null' .. ","
        elseif type(v) == "string" then
            str = str .. '"' .. v .. '",'
        elseif type(v) == "number" or type(v) == "boolean" then
            str = str .. tostring(v) .. ","
        end
      end
    end
    str = str:sub(1, -2) .. "}"
    return str
end

local function encodeSimulateProcess(StepTime) 

    local ProcessStr = "["..StepTime..","

    local BoxListStr = "["
    local Conveyor = SimulateProcess.Conveyor
    if #Conveyor.Container == 0 then
        BoxListStr = BoxListStr.."]"
    else
        for k, v in pairs(Conveyor.Container) do
            BoxStr = "["..v.Id..","..v.Pallet..","..v.Location..","..v.State..","..v.Child.."]"
            if v == Conveyor.Container[#Conveyor.Container] then
                BoxListStr = BoxListStr..BoxStr .."]"
            else
                BoxListStr = BoxListStr..BoxStr .. ","
            end
        end
    end

    local BoxListStr1 = "["
    local Conveyor = SimulateProcess.Conveyor1
    if #Conveyor.Container == 0 then
        BoxListStr1 = BoxListStr1.."]"
    else
        for k, v in pairs(Conveyor.Container) do
            local BoxStr = "["..v.Id..","..v.Pallet..","..v.Location..","..v.State..","..v.Child.."]"
            if v == Conveyor.Container[#Conveyor.Container] then
                BoxListStr1 = BoxListStr1..BoxStr .."]"
            else
                BoxListStr1 = BoxListStr1..BoxStr .. ","
            end
        end
    end


    local BoxListOnLeft = "[]"
    --BoxListOnLeft = "["
    --LeftPallet = SimulateProcess.LeftPallet

    --if #LeftPallet.Container == 0 then
    --    BoxListOnLeft = BoxListOnLeft.."]"
    --else
    --    for k, v in pairs(LeftPallet.Container) do
    --        if v == LeftPallet.Container[#LeftPallet.Container] then
    --            BoxListOnLeft = BoxListOnLeft..v .."]"
    --        else
    --            BoxListOnLeft = BoxListOnLeft..v .. ","
    --        end
    --    end
    --end

    local BoxListOnRight = "[]"
    --BoxListOnRight = "["
    --RightPallet = SimulateProcess.RightPallet
    --if #RightPallet.Container == 0 then
    --    BoxListOnRight = BoxListOnRight.."]"
    --else
    --    for k, v in pairs(RightPallet.Container) do
    --        if v == RightPallet.Container[#RightPallet.Container] then
    --            BoxListOnRight = BoxListOnRight..v .."]"
    --        else
    --            BoxListOnRight = BoxListOnRight..v .. ","
    --        end
    --    end
    --end

    local ProcessLeft = "["..SimulateProcess.Capacity.FirstPallet.Layer..","..SimulateProcess.Capacity.FirstPallet.Box.."]"

    local ProcessRight = "["..SimulateProcess.Capacity.SecondPallet.Layer..","..SimulateProcess.Capacity.SecondPallet.Box.."]"

    local BoxCntStr = "["..SimulateProcess.BoxCount..','..SimulateProcess.SimulateTime..','..SimulateProcess.Statistic.BoxCount..','..SimulateProcess.Statistic.TotalTime..','..SimulateProcess.Statistic.LayerRate..','..SimulateProcess.Statistic.PalletRate.."]"

    local TimeRate = "["..Capacity.Num.Box..","..Time.Num.Hour..","..Time.Num.Minute..","..Time.Num.Second.."]"

    return ProcessStr..BoxListStr..","..BoxListStr1..","..BoxListOnLeft..","..BoxListOnRight..","..BoxCntStr..","..ProcessLeft..","..ProcessRight..","..TimeRate.."]"
end

local function PublishRealTime(StepTime)
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':realtime', encodeSimulateProcess(math.ceil(StepTime / 2)), 0, false)
end

local function PublishDestroy(Removes)
    local BoxListStr = "["

    for k, v in pairs(Removes) do
        BoxStr = "["..v.Id..","..v.Pallet..","..v.Child.."]"
        if v == Removes[#Removes] then
            BoxListStr = BoxListStr..BoxStr .."]"
        else
            BoxListStr = BoxListStr..BoxStr .. ","
        end
    end

    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':destroyBoxes', BoxListStr, 0, false)
end

local function Step(Time)

    local removes = {}
    local Left = {}

    local Left1 = {}

    local Conveyor = SimulateProcess.Conveyor
    local Container = Conveyor.Container

    if Conveyor.PlaceDelayTime <= 0 then
        local size = #Container
        Left = DeepCopy(Container)

        for i = 1, size do

            local B = Container[i]

            local MaxWalkDistance = Time * Conveyor.Speed * SimulateProcess.SimulateSpeed / 1000
            if i == 1 then             --第一个箱子
                if B.Location - MaxWalkDistance > B.Length / 2 then
                    B.Location = B.Location - MaxWalkDistance
                else
                    B.Location = B.Length / 2
                    removes[#removes + 1]=B
                end
            else
                local PreB = Container[i - 1]

                local EndLocation = PreB.Location + PreB.Length / 2 + B.Length / 2 + Conveyor.BoxInterval

                if B.Location - MaxWalkDistance > EndLocation then
                    B.Location = B.Location - MaxWalkDistance
                else
                    B.Location = EndLocation
                end
            end

            if i == size then
                if B.Location <= Conveyor.Length - B.Length * (size + 0.5) - Conveyor.BoxInterval * size then
                    Left = {}
                end
            end
        end
    else
        Conveyor.PlaceDelayTime = Conveyor.PlaceDelayTime - Time * SimulateProcess.SimulateSpeed
    end


    if WorkingMode == 2 then
        Conveyor = SimulateProcess.Conveyor1
        Container = Conveyor.Container

        if Conveyor.PlaceDelayTime <= 0 then

            local size = #Container
            Left1 = DeepCopy(Container)

            for i = 1, size do
                local B = Container[i]

                local MaxWalkDistance = Time * Conveyor.Speed * SimulateProcess.SimulateSpeed / 1000
                if i == 1 then             --第一个箱子
                    if B.Location - MaxWalkDistance > B.Length / 2 then
                        B.Location = B.Location - MaxWalkDistance
                    else
                        B.Location = B.Length / 2
                        removes[#removes + 1]=B
                    end
                else
                    local PreB = Container[i - 1]

                    local EndLocation = PreB.Location + PreB.Length / 2 + B.Length / 2 + Conveyor.BoxInterval

                    if B.Location - MaxWalkDistance > EndLocation then
                        B.Location = B.Location - MaxWalkDistance
                    else
                        B.Location = EndLocation
                    end
                end

                if i == size then
                    if B.Location <= Conveyor.Length - B.Length * (size + 0.5) - Conveyor.BoxInterval * size then
                        Left1 = {}
                    end
                end
                    
            end
        else
            Conveyor.PlaceDelayTime = Conveyor.PlaceDelayTime - Time * SimulateProcess.SimulateSpeed
        end
    end

    PublishRealTime(Time)
    Wait(SleepTime7)

    SimulateProcess.Conveyor.BoxArrived = Left
    SimulateProcess.Conveyor1.BoxArrived = Left1

    if #removes > 0 then
        -- PublishDestroy(removes)
        -- PublishDestroy(removes)
        PublishDestroy(removes)
        for k, v in pairs(removes) do
            if WorkingMode == 2 then
                if v.Pallet == 0 then
                    table.remove(SimulateProcess.Conveyor.Container, 1)
                else
                    table.remove(SimulateProcess.Conveyor1.Container, 1)
                end
            else
                table.remove(SimulateProcess.Conveyor.Container, 1)
            end
        end
    end
end

--------------------------------------------------------------
local function ChildProcess()
    Wait(SleepTime7)
	while true do
        if SimulateProcess.MqttConnected == 1 then
            if (StateMachine == FSMType.SL and FirstPallet.Mode == 2)
                or (StateMachine == FSMType.SR and SecondPallet.Mode == 2)
                or ((StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) and FirstPallet.Mode == 2) then
                SimulateProcess.SimulateTime = SimulateProcess.SimulateTime + SleepTime7
                if SimulateProcess.SimulateSpeed == 1 and SimulateProcess.Statistic.FirstArrived == 1 then
                    SimulateProcess.Statistic.TotalTime = SimulateProcess.Statistic.TotalTime + SleepTime7

                    if SimulateProcess.LeftPallet.CanCount or SimulateProcess.RightPallet.CanCount then
                        SimulateProcess.Statistic.PalletTotalTime = SimulateProcess.Statistic.PalletTotalTime +
                            SleepTime7
                    end
                end
                Step(SleepTime7)
            else
                Wait(1000)
            end
        else
            Wait(1000)
        end
	end
end

ChildProcess()
