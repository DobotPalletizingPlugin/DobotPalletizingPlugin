-- 子线程，随主线程一起运行的并行程序，可设置I/O、通讯、变量等，不能调用运动指令。
SleepTime5 = 100  				--子线程等待时间，防止子线程占用CPU过高

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
            local BoxStr = "["..v.Id..","..v.Type..","..v.Location..","..v.State.."]"
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
            local BoxStr = "["..v.Id..","..v.Type..","..v.Location..","..v.State.."]"
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

local function PublishDestroy(ids)
    local Str = "["
    for k, v in pairs(ids) do
        if v == ids[#ids] then
            Str = Str..v .."]"
        else
            Str = Str..v .. ","
        end
    end
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':destroy', Str, 0, false)
end

local function GenerateBox(ConveyorNo)

    if ConveyorNo == 0 then
        Conveyor = SimulateProcess.Conveyor
    else
        Conveyor = SimulateProcess.Conveyor1
    end

    Container = Conveyor.Container

    local BoxDirection
    if ConveyorNo == 0 then
        BoxSize = FirstPallet.BoxProperty
        BoxDirection = FirstPalletBoxDirection
    else
        BoxSize = SecondPallet.BoxProperty
        BoxDirection = SecondPalletBoxDirection
    end

    local BoxLength = BoxSize.BoxLength
    if BoxDirection ~= 1 then
        BoxLength = BoxSize.BoxWidth
    end
    
    local Location = BoxLength * 0.5

    if #Container > 0 then
        LastBox = Container[#Container]

        --计算是否还有位置,没有就不生成箱子
        if LastBox.Location < BoxLength * 1.5 then
            return
        end
    end

    local B
    if BoxDirection == 1 then
        B = Box:new(0, Location, ConveyorNo, BoxSize.BoxLength, BoxSize.BoxWidth)
    else
        B = Box:new(0, Location, ConveyorNo, BoxSize.BoxWidth, BoxSize.BoxLength)
    end
    table.insert(Container, B) 
end


local function Step(Time)

    local Arrived = {}
    -- local SecondArrived

    local Arrived1 = {}
    -- local SecondArrived1

    local Conveyor = SimulateProcess.Conveyor
    local Container = Conveyor.Container

    if Conveyor.PickDelayTime <= 0 then
        local size = #Container
        for i = 1, size do

            local B = Container[i]

            local MaxWalkDistance = Time * Conveyor.Speed * SimulateProcess.SimulateSpeed / 1000
            if i == 1 then             --第一个箱子
                if B.Location + MaxWalkDistance <= Conveyor.Length - B.Length / 2 then
                    B.Location = B.Location + MaxWalkDistance
                else
                    B.Location = Conveyor.Length - B.Length / 2
                    Arrived[1] = B
                end
            else
                local PreB = Container[i - 1]

                local EndLocation = PreB.Location - PreB.Length / 2 - B.Length / 2 - Conveyor.BoxInterval

                if B.Location + MaxWalkDistance <= EndLocation then
                    B.Location = B.Location + MaxWalkDistance
                else
                    B.Location = EndLocation
                    if Arrived[1] and i <= 4 then
                        Arrived[i] = B
                    end
                end
            end
        end
    else
        Conveyor.PickDelayTime = Conveyor.PickDelayTime - Time * SimulateProcess.SimulateSpeed
    end


    if WorkingMode == 2 then
        Conveyor = SimulateProcess.Conveyor1
        Container = Conveyor.Container

        if Conveyor.PickDelayTime <= 0 then
            local size = #Container
            for i = 1, size do

                --local usedTime = Systime()
                local B = Container[i]

                local MaxWalkDistance = Time * Conveyor.Speed * SimulateProcess.SimulateSpeed / 1000
                if i == 1 then             --第一个箱子
                    if B.Location + MaxWalkDistance <= Conveyor.Length - B.Length / 2 then
                        B.Location = B.Location + MaxWalkDistance
                    else
                        B.Location = Conveyor.Length - B.Length / 2
                        Arrived1[1] = B
                    end
                else
                    local PreB = Container[i - 1]

                    local EndLocation = PreB.Location - PreB.Length / 2 - B.Length / 2 - Conveyor.BoxInterval

                    if B.Location + MaxWalkDistance <= EndLocation then
                        B.Location = B.Location + MaxWalkDistance
                    else
                        B.Location = EndLocation
                        if Arrived1[1] and i <= 4 then
                            Arrived1[i] = B
                        end
                    end
                end
            end
        else
            Conveyor.PickDelayTime = Conveyor.PickDelayTime - Time * SimulateProcess.SimulateSpeed
        end
    end

    PublishRealTime(Time)
    Wait(SleepTime5)
    SimulateProcess.Conveyor.BoxArrived = Arrived
    -- SimulateProcess.Conveyor.SecondBoxArrived = SecondArrived

    SimulateProcess.Conveyor1.BoxArrived = Arrived1
    -- SimulateProcess.Conveyor1.SecondBoxArrived = SecondArrived1
end

local function ClearOnRobot()
    local Container = SimulateProcess.Conveyor.Container
    if #Container > 2 then
        if Container[1].State == 1 then
            table.remove(Container, 1)
        end
        if Container[1].State == 1 then
            table.remove(Container, 1)
        end
    end

    Container1 = SimulateProcess.Conveyor1.Container
    if #Container1 > 2 then
        if Container1[1].State == 1 then
            table.remove(Container1, 1)
        end
        if Container1[1].State == 1 then
            table.remove(Container1, 1)
        end
    end
end

--------------------------------------------------------------
local function ChildProcess()
    local TotalTime = 0
    
    Wait(SleepTime5)
	while true do

        if SimulateProcess.MqttConnected == 1 then
            if (StateMachine == FSMType.SL and FirstPallet.Mode == 1)
                or (StateMachine == FSMType.SR and SecondPallet.Mode == 1)
                or ((StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) and FirstPallet.Mode == 1) then
                TotalTime = TotalTime + SleepTime5
                if TotalTime >= SimulateProcess.GenerateInterval then
                    TotalTime = 0
                    GenerateBox(0)
                    if WorkingMode == 2 then
                        GenerateBox(1)
                    end
                end
                SimulateProcess.SimulateTime = SimulateProcess.SimulateTime + SleepTime5

                if SimulateProcess.SimulateSpeed == 1 and SimulateProcess.Statistic.FirstArrived == 1 then
                    SimulateProcess.Statistic.TotalTime = SimulateProcess.Statistic.TotalTime + SleepTime5

                    if SimulateProcess.LeftPallet.CanCount or SimulateProcess.RightPallet.CanCount then
                        SimulateProcess.Statistic.PalletTotalTime = SimulateProcess.Statistic.PalletTotalTime +
                            SleepTime5
                    end
                end

                Step(SleepTime5)
                ClearOnRobot()
            else
                Wait(1000)
            end
        else
            Wait(1000)
        end
	end
end


ChildProcess()

