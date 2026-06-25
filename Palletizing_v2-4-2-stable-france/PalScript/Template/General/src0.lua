--------------------------------------------------------------
--此文件仅用于定义执行运动
---------------------------------------------------------------
--局部常量
local mqttFunc = require("libplugin_eco")
local Dir =
{
    Forward = 1,  --正向运动
    Backward = -1 --反向运动
}
local LDAcc = ToolAccWithBox
local LDVel = ToolSpeedWithBox
local NLDAcc = ToolAccWithoutBox
local NLDVel = ToolSpeedWithoutBox
local LiftingPoint = {}        --升降柱安全点位
local PartPick = { pose = {} } --隔板取料点
if HighLoadFunc == true then
    LiftingPoint = DeepCopy(LiftingSafetyPoint_HL)
else
    LiftingPoint = DeepCopy(LiftingSafetyPoint)
end
---------------------------------------------------------------
--局部变量
local SingleMotion = false --单次运动信号
local SyncSignal = false   --同步信号
local LiftingHeight = 0    --升降柱高度
local SyncMotionVel = 1    --机器人-升降柱相对运动速度
local PrePallet = 1        --缠膜栈板号
local PrePoseHeight = 0    --缠膜高度
---------------------------------------------------------------
-- 系统初始化
---------------------------------------------------------------
--坐标系重定义。
local function SetCoordinate(PalletNumber, PalletNum)
    PalletNumber.Layer = GetLayerCnt(PalletName, PalletNum)
    PalletNumber.Coordinate.UserNum = GetPalletUser(PalletName, PalletNum)
    local CTool = GetPalletTool(PalletName, ToolType.Conc)
    PalletNumber.Coordinate.ToolNum = CTool[1]
    PalletNumber.BoxProperty.BoxWeight = GetBoxLoad(PalletName, PalletNum)
    local PalletUser = CalcUser(PalletNumber.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
    PalletUser[3] = PalletUser[3] + PalletNumber.ProcessNum.PalletHeight
    SetUser(PalletNumber.Coordinate.UserNum, PalletUser)
    HomePointPose = PositiveKin(HomePoint,
        { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })
    if (PalletNumber.Partition.Enable == true) then
        local ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
        if (ProjectType == 1) then
            local PartPickJoint = { joint = {} }
            PartPickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
            PartPick = PositiveKin(PartPickJoint)
        else
            PartPick.pose = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.pose)
            PartPick.pose[3] = PartPick.pose[3] - PalletNumber.ProcessNum.PalletHeight
        end
    end
end
---------------------------------------------------------------
--状态初始化
local function InitFSM()
    GetEnableStatus()
    if (FirstPallet.StateValue.Enable == 1)
        and (SecondPallet.StateValue.Enable == 1) then
        ExecuteSafeModule(FirstPallet, SecondPallet)
        ExecuteSafeModule(SecondPallet, FirstPallet)
        Wait(Time.Thread.s0)
        if (PalletBeInPlaceOKButton == false or SimulateMode == 1) then
            GetPalletStatus(FirstPallet)
            GetPalletStatus(SecondPallet)
            if (FirstPallet.State.Replace == false and SecondPallet.State.Replace == false) then
                TriLightStatus(FirstPallet, Light.Red.On)
                TriLightStatus(SecondPallet, Light.Red.On)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            elseif (FirstPallet.State.Replace == false and SecondPallet.State.Replace == true) then
                TriLightStatus(FirstPallet, Light.Red.On)
                TriLightStatus(SecondPallet, Light.Init)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            elseif (FirstPallet.State.Replace == true and SecondPallet.State.Replace == false) then
                TriLightStatus(FirstPallet, Light.Init)
                TriLightStatus(SecondPallet, Light.Red.On)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            end
                
            Pallet = Left
        else
            Pallet = Idle
        end
        if WorkingMode == 0 then
            StateMachine = FSMType.SLR
            LogInfo("Initialized single conveyor dual pallet mode!")
        else
            StateMachine = FSMType.DLR
            LogInfo("Initialized dual conveyor dual pallet mode!")
        end
        SetCoordinate(SecondPallet, Right)
        SetCoordinate(FirstPallet, Left)
    else
        if (FirstPallet.StateValue.Enable == 1) then
            ExecuteSafeModule(FirstPallet, SecondPallet)
            GetPalletStatus(FirstPallet)
            if (FirstPallet.State.Replace == false and PalletBeInPlaceOKButton == false) then
                TriLightStatus(FirstPallet, Light.Red.On)
                TriLightStatus(SecondPallet, Light.Init)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            end
            Pallet = Left
            StateMachine = FSMType.SL
            SetCoordinate(FirstPallet, Left)
            LogInfo("Initialized single conveyor single left pallet mode!")
        elseif (SecondPallet.StateValue.Enable == 1) then
            ExecuteSafeModule(SecondPallet, FirstPallet)
            GetPalletStatus(SecondPallet)
            if (SecondPallet.State.Replace == false and PalletBeInPlaceOKButton == false) then
                TriLightStatus(FirstPallet, Light.Init)
                TriLightStatus(SecondPallet, Light.Red.On)
                Alarm("Lost Pallet!", ErrorMessage.Type.PalletErr)
            end
            Pallet = Right
            StateMachine = FSMType.SR
            SetCoordinate(SecondPallet, Right)
            LogInfo("Initialized single conveyor single right pallet mode!")
        else
            StateMachine = FSMType.IDLE
            TriLightStatus(FirstPallet, Light.Red.On)
            TriLightStatus(SecondPallet, Light.Red.On)
            Alarm("Pallet not enabled!", ErrorMessage.Type.PalletEnableErr)
        end
    end
end
--------------------------------------------------------------
--初始化数据获取模式
local function InitStorageMode()
    StorageMode = GetVal("PalletPowerDown")
    LogInfo("%s", (StorageMode == 0) and "Get working data from controller global variables!" or
        "Get working data from registers!")
    SetVal("PalletProjectName", PalletName)
    SetVal("LWorkState", StateType.Idle)
    SetVal("RWorkState", StateType.Idle)
    SetVal("ScriptState", true)
    if StorageMode == nil then
        StorageMode = 1
        SetVal("PalletTime", Time.Num)
        SetVal("PalletCapacity", Capacity.Num)
        SetVal("PalletWorkingDataA", FirstPallet.PalletNum)
        SetVal("PalletWorkingDataB", SecondPallet.PalletNum)
    end
    if (GetVal("PalletPartNumA") == nil) then
        SetVal("PalletPartNumA", FirstPallet.Partition.RePartNum)
    end
    if (GetVal("PalletPartNumB") == nil) then
        SetVal("PalletPartNumB", SecondPallet.Partition.RePartNum)
    end
    if (GetVal("PalletPartPlaceA") == nil) then
        SetVal("PalletPartPlaceA", FirstPallet.Partition.Place)
    end
    if (GetVal("PalletPartPlaceB") == nil) then
        SetVal("PalletPartPlaceB", SecondPallet.Partition.Place)
    end
end

---------------------------------------------------------------
--根据隔板余量传感器同步隔板数量（src0启动阶段/运动前使用）
--DI = ON/1：认为料仓有隔板，恢复默认隔板数量，并写入Modbus/SetVal
--DI = OFF/0：认为料仓无隔板，将剩余隔板数量置为0，并写入Modbus/SetVal
local function SyncPartitionRemainBySensor(PalletNumber, ForceLog)
    if (PalletNumber == nil) or (PalletNumber.Partition == nil) then
        return
    end

    if (PalletNumber.Partition.Enable ~= true) or (PalletNumber.Mode ~= WorkType.Pallet) then
        return
    end

    if (PartSensorCfg == nil) or (PartSensorCfg.Enable ~= true) then
        return
    end

    if (PartSensorCfg.Port == nil) or (PartSensorCfg.Port.A == nil) then
        LogWarn("Partition remain sensor DI is not configured!")
        return
    end

    if SimulateMode == 1 then
        return
    end

    local DelayTime = PartSensorCfg.DelayTime or 0
    local SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)

    if DelayTime > 0 then
        Wait(DelayTime)
        SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)
    end

    local TargetPartNum = 0
    if SensorState == ON then
        TargetPartNum = PalletNumber.ProcessNum.PartitionNum
    end

    if (PalletNumber.Partition.RePartNum ~= TargetPartNum) or (ForceLog == true) then
        PalletNumber.Partition.RePartNum = TargetPartNum
        WritePartNum(PalletNumber)
        if SensorState == ON then
            LogInfo("Partition remain sensor DI%s is ON before ACK/motion. Restore remaining partition number to default and write Modbus: %s.",
                tostring(PartSensorCfg.Port.A), tostring(PalletNumber.Partition.RePartNum))
        else
            LogWarn("Partition remain sensor DI%s is OFF before ACK/motion. Set remaining partition number to 0 and write Modbus.",
                tostring(PartSensorCfg.Port.A))
        end
    end
end
---------------------------------------------------------------
--启动阶段同步两侧隔板数量。必须在ACK/隔板不足判断前执行，否则HMI仍会看到旧的0。
local function SyncAllPartitionRemainBySensor(ForceLog)
    SyncPartitionRemainBySensor(FirstPallet, ForceLog)
    SyncPartitionRemainBySensor(SecondPallet, ForceLog)
end
---------------------------------------------------------------
--升降柱运动命令
---------------------------------------------------------------
-----------------------------仿真------------------------------
--发送升降台升降动作消息
local function PublishLiftAction(Dest, UsedTime)
    local ActionStr = "[" .. Dest .. "," .. math.ceil(UsedTime) .. "]"
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':liftAction', ActionStr, 0, false)
end
---------------------------------------------------------------
--模拟升降台升降  
local function SimulateLiftingColumnMove(dest)
    LogInfo("Lifting column move to %s!", dest)
    LiftingColumn = SimulateProcess.LiftingColumn
    if LiftingColumn.LiftingHeight ~= dest then
        local UsedTime = math.floor(math.abs(LiftingColumn.LiftingHeight - dest) / LiftingColumn.Speed / SimulateProcess.SimulateSpeed * 1000)
        UsedTime = math.ceil(UsedTime / 100) * 100
        LiftingColumn.UsedTime = UsedTime * 1.0
        LiftingColumn.LiftingHeight = dest
        LogInfo("Lifting column move to %s, used time %s ms!", LiftingColumn.LiftingHeight, LiftingColumn.UsedTime)
        if (StateMachine == FSMType.DLR and Pallet ~= PrePallet) then
            PublishLiftAction(dest, LiftingColumn.UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            --Wait(100)
        else
            PublishLiftAction(dest, LiftingColumn.UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            -- PublishLiftAction(dest, UsedTime)
            --Wait(100)
        end
    end
end
---------------------------------------------------------------
--发送机械臂抓取动作消息  
local function PublishRobotAction()

    local BoxOnRobotStr = "["
    RobotContainer = SimulateProcess.BoxOnRobot

    if #RobotContainer == 0 then
        BoxOnRobotStr = BoxOnRobotStr.."]"
    else
        for k, v in pairs(RobotContainer) do
            local BoxStr = "["..v.Id..","..v.Layer..","..v.Pallet..","..v.State..","..v.Child.."]"
            if v == RobotContainer[#RobotContainer] then
                BoxOnRobotStr = BoxOnRobotStr..BoxStr .."]"
            else
                BoxOnRobotStr = BoxOnRobotStr..BoxStr .. ","
            end
        end
    end

    Joint = GetAngle().joint

    local JointStr = "["..Joint[1]..","..Joint[2]..","..Joint[3]..","..Joint[4]..","..Joint[5]..","..Joint[6].."]"
    local ActionStr = "["..BoxOnRobotStr..","..JointStr.."]"

    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':robotAction', ActionStr, 0, false)
end
---------------------------------------------------------------
--发送机械臂抓取动作消息  
local function PublishPartitionAction(action, palletNum)
    local Joint = GetAngle().joint
    local JointStr = "["..Joint[1]..","..Joint[2]..","..Joint[3]..","..Joint[4]..","..Joint[5]..","..Joint[6].."]"

    local ActionStr = "["..action..","..JointStr..","..palletNum.."]"
    mqttFunc.MQTTPublish(ConnectId, SimulateProcess.Id..':partitionAction', ActionStr, 0, false)
end
---------------------------------------------------------------
--更新箱子抓取状态
local function UpdatePickBoxState(PalletNumber, CPoint)
    local ContainerIn = SimulateProcess.BoxOnRobot
    local Conveyor = SimulateProcess.PresentConveyor

    if CPoint.Paras.Mode == MotionType.Norm then
    
        if PalletNumber.Mode == WorkType.Pallet then

            ContainerOut = Conveyor.Container

            Conveyor.PickDelayTime = Time.Pick.In
            if CPoint.Paras.Sucker > 0 then --吸多个箱子时
                for i = 1, math.ceil(0.5 * CPoint.Paras.Sucker) + 1 do
                    table.insert(ContainerIn, ContainerOut[i]) 
                end
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + math.ceil(0.5 * CPoint.Paras.Sucker) + 1
            elseif CPoint.Paras.Sucker == -1 then -- 多吸单放
                for i = 1, math.abs(PalletSuckerFunction) do
                    table.insert(ContainerIn, ContainerOut[i]) 
                end
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + PalletSuckerFunction
            else --吸单个箱子时
                table.insert(ContainerIn, ContainerOut[1])
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + 1
            end

            for k, v in pairs(ContainerIn) do
                v:setState(1)
                v:setLayer(PalletNumber.PalletNum.LayerCount)
                v:setIndex(SimulateProcess.LayerBoxIndex)
                v:setPickIndex(SimulateProcess.PickIndex)
                v:setPallet(Pallet)
            end
        else
            local ContainerIn = SimulateProcess.BoxOnRobot
            local ConveyorNo = Pallet
            local BoxSize = PalletNumber.BoxProperty

            local BoxDirection
            if ConveyorNo == 0 then
                BoxDirection = FirstPalletBoxDirection
            else
                BoxDirection = SecondPalletBoxDirection
            end

            if CPoint.Paras.Sucker > 0 then ---吸多个箱子时
                for i = 1, math.ceil(0.5 * CPoint.Paras.Sucker) + 1 do
                    local B
                    if BoxDirection == 0 then
                        B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxWidth, BoxSize.BoxLength)
                    else
                        B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxLength, BoxSize.BoxWidth)
                    end
                    
                    table.insert(ContainerIn, B)
                    B:setId(PalletNumber.PalletNum.NextBoxCount)
                    B:setState(1)
                    B:setLayer(PalletNumber.PalletNum.LayerCount)
                    B:setIndex(SimulateProcess.LayerBoxIndex)
                    B:setPickIndex(SimulateProcess.PickIndex)
                    B:setPallet(Pallet)
                    B:setChild(i - 1)
                end
                SimulateProcess.BoxCount = SimulateProcess.BoxCount + math.ceil(0.5 * CPoint.Paras.Sucker) + 1
                -- elseif CPoint.Paras.Sucker == -1 then
                --     for i = 1, PalletSuckerFunction do
                --         local B
                --         if BoxDirection == 0 then
                --             B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxWidth, BoxSize.BoxLength)
                --         else
                --             B = Box:new(0, Conveyor.Length - BoxSize.BoxWidth * (0.5 * i) - Conveyor.BoxInterval * (i - 1), ConveyorNo, BoxSize.BoxLength, BoxSize.BoxWidth)
                --         end
                    
                --         table.insert(ContainerIn, B)
                --         B:setId(PalletNumber.PalletNum.NextBoxCount)
                --         B:setState(1)
                --         B:setLayer(PalletNumber.PalletNum.LayerCount)
                --         B:setIndex(SimulateProcess.LayerBoxIndex)
                --         B:setPickIndex(SimulateProcess.PickIndex)
                --         B:setPallet(Pallet)
                --         B:setChild(i - 1)
                --     end
                --     SimulateProcess.BoxCount = SimulateProcess.BoxCount + PalletSuckerFunction
            else
                local B
                if BoxDirection == 0 then
                    B = Box:new(0, Conveyor.Length - 0.5 * BoxSize.BoxWidth, ConveyorNo, BoxSize.BoxWidth,
                        BoxSize.BoxLength)
                else
                    B = Box:new(0, Conveyor.Length - 0.5 * BoxSize.BoxLength, ConveyorNo, BoxSize.BoxLength,
                        BoxSize.BoxWidth)
                end
                table.insert(ContainerIn, B)

                B:setId(PalletNumber.PalletNum.NextBoxCount)
                B:setState(1)
                B:setLayer(PalletNumber.PalletNum.LayerCount)
                B:setIndex(SimulateProcess.LayerBoxIndex)
                B:setPickIndex(SimulateProcess.PickIndex)
                B:setPallet(Pallet)

                SimulateProcess.BoxCount = SimulateProcess.BoxCount + 1
            end
        end
            
        SimulateProcess.LayerBoxIndex = SimulateProcess.LayerBoxIndex + 1
        SimulateProcess.PickIndex = SimulateProcess.PickIndex + 1
        
        PublishRobotAction()
        -- PublishRobotAction()
        -- PublishRobotAction()
    else
        PublishPartitionAction(1, Pallet)
        -- PublishPartitionAction(1, Pallet)
        -- PublishPartitionAction(1, Pallet)
    end
end
---------------------------------------------------------------
--更新箱子放下状态
local function UpdatePlaceBoxState(PalletNumber, CPoint)
    ContainerOut = SimulateProcess.BoxOnRobot
    local TempBoxOnRobot = DeepCopy(SimulateProcess.BoxOnRobot)
    if CPoint.Paras.Mode == MotionType.Norm then
        if PalletNumber.Mode == WorkType.Pallet then
            if PalletNumber == FirstPallet then
                ContainerIn = SimulateProcess.LeftPallet.Container
            else
                ContainerIn = SimulateProcess.RightPallet.Container
            end

            if CPoint.Paras.Sucker == -1 then
                local value = ContainerOut[1]
                ContainerIn[#ContainerIn + 1] = value.id
                value:setState(2)
                if SimulateProcess.SimulateSpeed == 1 then
                    SimulateProcess.Statistic.BoxCount = SimulateProcess.Statistic.BoxCount + 1
                end
            else 
              for k, v in pairs(ContainerOut) do
                  ContainerIn[#ContainerIn + 1] = v.Id
                  v:setState(2)
                  if SimulateProcess.SimulateSpeed == 1 then
                      SimulateProcess.Statistic.BoxCount = SimulateProcess.Statistic.BoxCount + 1
                  end
              end
            end
            if CPoint.Paras.Sucker == -1 then
                SimulateProcess.BoxOnRobot = { SimulateProcess.BoxOnRobot[1] }
            end
        else
            SimulateProcess.PresentConveyor.PlaceDelayTime = Time.Place.In
            ContainerIn = SimulateProcess.PresentConveyor.Container
            for k, v in pairs(ContainerOut) do
                ContainerIn[#ContainerIn + 1] = v
                v:setState(0)
                if SimulateProcess.SimulateSpeed == 1 then
                    SimulateProcess.Statistic.BoxCount = SimulateProcess.Statistic.BoxCount + 1
                end
            end
        end

        LogInfo("%s", SimulateProcess.BoxOnRobot)
        PublishRobotAction()
        -- PublishRobotAction()
        -- PublishRobotAction()


        if PalletNumber.Mode == WorkType.Pallet then
            if CPoint.Paras.Sucker == -1 then
                table.remove(TempBoxOnRobot, 1)
                SimulateProcess.BoxOnRobot = TempBoxOnRobot
            else 
                for i = 1, #ContainerOut do
                    table.remove(ContainerOut, 1)
                end
            end
        else
            for i = 1, #ContainerOut do
                table.remove(ContainerOut, 1)
            end
        end

    else
        PublishPartitionAction(0, Pallet)
        -- PublishPartitionAction(0, Pallet)
        -- PublishPartitionAction(0, Pallet)
    end
end
---------------------------------------------------------------
--检测传送带上是否还有箱子
local function CheckBoxOnConveyor(Conveyor, PalletNo)
    for k, v in pairs(Conveyor.Container) do
        if v.Pallet == PalletNo then
            return true
        end
    end

    return false
end
---------------------------------------------------------------
--统计仿真码垛节拍
local function StatisticLayerRate()
    if SimulateProcess.Statistic.TotalTime > 0 then
        SimulateProcess.Statistic.LayerRate = math.floor(SimulateProcess.Statistic.BoxCount / SimulateProcess.Statistic.TotalTime * 1000 * 60 * 10)
    end
end
---------------------------------------------------------------
--统计单栈板耗时
local function StatisticPalletRate(PalletSide)
    if PalletSide.CanCount == 1 then
        SimulateProcess.Statistic.PalletNum = SimulateProcess.Statistic.PalletNum + 1
        SimulateProcess.Statistic.PalletRate = math.floor(SimulateProcess.Statistic.PalletTotalTime / 1000 / 60 /
            SimulateProcess.Statistic.PalletNum * 10)
    end

    if SimulateProcess.SimulateSpeed > 1 then
        PalletSide.CanCount = 0
    else
        PalletSide.CanCount = 1
    end
end
---------------------------------------------------------------
----------------------------实际-------------------------------
--与升降轴建立通讯
local function InitLifting()
    if SimulateMode == 1 then
        if (Communication.Lifting.Mode == LiftingType.EWELLIX) then
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.EWELLIX.MaxDistance
        elseif (Communication.Lifting.Mode == LiftingType.GeMinG) then
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.GeMinG.MaxDistance
        elseif (Communication.Lifting.Mode == LiftingType.ZT3ILC) then
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.ZT3ILC.MaxDistance
        else
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.LINAK.MaxDistance
        end
        LogInfo("Simulate mode: CreateTcpConnection not excute!")
        return
    end

    local Err = 0
    local CurrentHeight
    local SwitchCommMode =
    {
        [LiftingType.EWELLIX] = function()
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.EWELLIX.MaxDistance
            Err, Communication.Lifting.Brand.EWELLIX.Tcp.Socket = TCPCreate(false,
                Communication.Lifting.Brand.EWELLIX.Tcp.Ip, Communication.Lifting.Brand.EWELLIX.Tcp.Port) --创建TCP客户端
            LogInfo("Attempting to create TCP connection to EWELLIX lifting at %s:%d!",
                Communication.Lifting.Brand.EWELLIX.Tcp.Ip, Communication.Lifting.Brand.EWELLIX.Tcp.Port)
        end,
        [LiftingType.GeMinG] = function()
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.GeMinG.MaxDistance
            Err, Communication.Lifting.Brand.GeMinG.ModbusRTU.Id = ModbusRTUCreate(
                Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.BaudRate,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.Parity,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.DataBit,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.StopBit)
            LogInfo("Attempting to create modbus RTU connection to GeMinG lifting with slave ID %d!",
                Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId)
        end,
        [LiftingType.ZT3ILC] = function()
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.ZT3ILC.MaxDistance
            Err, Communication.Lifting.Brand.ZT3ILC.Modbus.Id = ModbusCreate(
                Communication.Lifting.Brand.ZT3ILC.Modbus.Ip,
                Communication.Lifting.Brand.ZT3ILC.Modbus.Port)
            LogInfo("Attempting to create modbus TCP connection to ZT3ILC lifting at %s:%d!",
                Communication.Lifting.Brand.ZT3ILC.Modbus.Ip, Communication.Lifting.Brand.ZT3ILC.Modbus.Port)
        end,
        [LiftingType.LINAK] = function()
            Communication.Lifting.CMaxDis = Communication.Lifting.Brand.LINAK.MaxDistance
            Err, Communication.Lifting.Brand.LINAK.Modbus.Id = ModbusCreate(
                Communication.Lifting.Brand.LINAK.Modbus.Ip,
                Communication.Lifting.Brand.LINAK.Modbus.Port)
            LogInfo("Attempting to create modbus TCP connection to Linak lifting at %s:%d!",
                Communication.Lifting.Brand.LINAK.Modbus.Ip, Communication.Lifting.Brand.LINAK.Modbus.Port)
        end
    }
    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
    else
        Alarm("CommMode is error!", ErrorMessage.Type.WorkingDataErr)
    end
    if (Err == 0) then
        LogInfo("Communication initialization completed!")
    else
        Alarm("Communication initialization failed!", ErrorMessage.Type.LinkErr)
    end

    local SwitchCommInitMode =
    {
        [LiftingType.EWELLIX] = function()
            LogInfo("Create tcp client success!")
            Err = EWLInit()
            Err, CurrentHeight = EWLGetPosition()
            if (Communication.Lifting.StopFlag == true) then
                Communication.Lifting.StopFlag = false
                Err, CurrentHeight = EWLGetPosition()
            end
        end,
        [LiftingType.GeMinG] = function()
            LogInfo("Create RTUModbus client success!")
            SV660CInit()
            SV660CEnable(1)
            CurrentHeight = SV660CGetPostion()[1]
            if CurrentHeight == nil then
                Err = 1
            else
                CurrentHeight = 0.1 * CurrentHeight
            end
        end,
        [LiftingType.ZT3ILC] = function()
            LogInfo("Create modbus client success!")
            ZC01Init()
            ZC01Enable(1)
            CurrentHeight = ZC01GetPostion()[1]
            if CurrentHeight == nil then
                Err = 1
            else
                CurrentHeight = ConvertFloat(CurrentHeight)
            end
        end,
        [LiftingType.LINAK] = function()
            LogInfo("Create modbus client success!")
            LINAKInit()
            CurrentHeight = LINAKGetPostion()
            if CurrentHeight == nil then
                Err = 1
            else
                CurrentHeight = 0.1 * CurrentHeight
            end
        end
    }

    local switch_init_mode = SwitchCommInitMode[Communication.Lifting.Mode]
    if switch_init_mode then
        switch_init_mode()
    else
        Alarm("switch_init_mode is error!", ErrorMessage.Type.WorkingDataErr)
    end
    if Err == 0 then
        LogInfo("Communication connection success!")
    else
        Alarm("Lifting connection failed!", ErrorMessage.Type.LinkErr)
    end

    if (CurrentHeight == nil) then
        LogError("Lifting height: %s", tostring(CurrentHeight))
        Alarm("Lifting Data Error!", ErrorMessage.Type.LiftingDataErr)
    else
        LiftingHeight = math.ceil(CurrentHeight)
    end
    LogInfo("Initialized lifting success!")
end
---------------------------------------------------------------
--实时获取升降柱高度
local function GetLiftingHeight(CLH)
    local Err = 0
    local Res = 0
    local SwitchCommMode =
    {
        [LiftingType.EWELLIX] = function()
            Err, Res = EWLGetPosition()
            if ((Res >= CLH - 3) and (Res <= CLH + 3)) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end,
        [LiftingType.GeMinG] = function()
            local RLH = math.ceil(CLH * 10)
            Res = SV660CGetPostion()
            if ((Res[1] <= RLH + 10) and (Res[1] >= RLH - 10)) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end,
        [LiftingType.ZT3ILC] = function()
            Res = math.ceil(ZC01GetPostion())
            if ((Res <= math.ceil(CLH + 1)) and (Res >= math.ceil(CLH - 1))) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end,
        [LiftingType.LINAK] = function()
            local RLH = math.ceil(CLH * 10)
            Res = LINAKGetPostion()
            if ((Res <= RLH + 30) and (Res >= RLH - 30)) then
                SyncMotionVel = NLDVel
                LogInfo("Lifting motion completed!")
            end
        end
    }
    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]

    if (SyncSignal == true and SimulateMode == 0) then
        if switch_mode then
            switch_mode()
        else
            Alarm("CommMode is error, please check it!", ErrorMessage.Type.LiftingStateErr)
        end
    end
end
---------------------------------------------------------------
--等待升降柱到位运动
local function LiftingMotion(CLH)
    local Res = 0
    local Err = 0
    local StartTime = os.time()
    local Timeout = 60 --60s 超时报警
    local SwitchCommMode =
    {
        [LiftingType.EWELLIX] = function()
            repeat
                Err, Res = EWLGetPosition()
                if Err ~= 0 then
                    Alarm("Lifting state error!", ErrorMessage.Type.LiftingStateErr)
                end
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    EWLRun(CLH)
                end
                if (os.time() - StartTime > Timeout) then
                    Alarm("Lifting motion timeout!", ErrorMessage.Type.LiftingStateErr)
                end
                LogInfo("Lifting motion position is %s mm! ", Res)
                Wait(100)
            until ((Res <= CLH + 3) and (Res >= CLH - 3))
        end,
        [LiftingType.GeMinG] = function()
            local RLH = math.ceil(CLH * 10)
            repeat
                Res = SV660CGetPostion()
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    SV660CRun(RLH)
                end
                if (os.time() - StartTime > Timeout) then
                    Alarm("Lifting motion timeout!", ErrorMessage.Type.LiftingStateErr)
                end
                LogInfo("Lifting motion position is %s mm! ", 0.1 * Res[1])
                Wait(100)
            until ((Res[1] <= RLH + 10) and (Res[1] >= RLH - 10))
        end,
        [LiftingType.ZT3ILC] = function()
            repeat
                Res = math.ceil(ZC01GetPostion())
                if Communication.Lifting.StopFlag == true then
                    Communication.Lifting.StopFlag = false
                    ZC01Init()
                    ZC01Run(math.ceil(CLH))
                end
                if (os.time() - StartTime > Timeout) then
                    Alarm("Lifting motion timeout!", ErrorMessage.Type.LiftingStateErr)
                end
                LogInfo("Lifting motion position is %s mm! ", Res)
                Wait(100)
            until ((Res <= math.ceil(CLH + 1)) and (Res >= math.ceil(CLH - 1)))
        end,
        [LiftingType.LINAK] = function()
            local RLH = math.ceil(CLH * 10)
            repeat
                Res = LINAKGetPostion()
                if Communication.Lifting.StopLiftingFlag == true then
                    Communication.Lifting.StopLiftingFlag = false
                    LINAKInit()
                    LINAKRun(RLH)
                end
                Wait(100)
            until ((Res <= RLH + 30) and (Res >= RLH - 30))
        end
    }
    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
        LogInfo("Lifting motion completed!")
    else
        Alarm("CommMode is error, please check it!", ErrorMessage.Type.LiftingStateErr)
    end
end
---------------------------------------------------------------
--调整升降柱高度
local function AdjustLiftingHeight(CLH)
    if (PalletLiftingFunction == true) and (math.abs(CLH - LiftingHeight) > 1) then
        LogInfo("Lifting relative motion distance is %s mm!", math.abs(CLH - LiftingHeight))
        SyncSignal = true
        if (math.abs(CLH - LiftingHeight) == Communication.Lifting.CMaxDis) then
            SyncMotionVel = 2
        else
            SyncMotionVel = math.ceil(10 * (1 - math.abs(CLH - LiftingHeight) / Communication.Lifting.CMaxDis))
        end
        LogInfo("Lifting-Robot motion velocity ratio is %s!", SyncMotionVel)
        LiftingHeight = CLH
        Communication.Lifting.TimesPerHour = Communication.Lifting.TimesPerHour + 1
        LogInfo("Lifting motion target position is %s mm!", CLH)
        if (SimulateMode == 1) then
            SimulateLiftingColumnMove(CLH)
            LogInfo("Simulate mode: moveTo_absolutePosition, %s", CLH)
        else
            local SwitchCommMode =
            {
                [LiftingType.EWELLIX] = function()
                    EWLRun(CLH)
                    EWLGetPosition()
                end,
                [LiftingType.GeMinG] = function()
                    SV660CRun(math.ceil(CLH * 10))
                end,
                [LiftingType.ZT3ILC] = function()
                    ZC01Run(CLH)
                end,
                [LiftingType.LINAK] = function()
                    LINAKRun(math.ceil(CLH * 10))
                end
            }
            local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
            if switch_mode then
                switch_mode()
            else
                Alarm("SwitchCommMode is error, please check it!", ErrorMessage.Type.LiftingStateErr)
            end
        end
    else
        SyncSignal = false
        SyncMotionVel = NLDVel
    end
end
---------------------------------------------------------------
--运动命令
---------------------------------------------------------------
--运动到安全原点
local function RobotGoHome()
    local CPose = GetPose()
    local CJoint = GetAngle()
    if (ResetPathFunc == true) then
        if (CPose.pose[1] > 400) then
            HomeTransPointL.joint[6] = 0.5 * CJoint.joint[6]
            MovL(HomeTransPointL, { a = NLDAcc * 0.25, v = NLDVel * 0.25, cp = 100 })
        elseif (CPose.pose[1] < -400) then
            HomeTransPointR.joint[6] = 0.5 * CJoint.joint[6]
            MovL(HomeTransPointR, { a = NLDAcc * 0.25, v = NLDVel * 0.25, cp = 100 })
        end
    end
    MovJ(HomePoint, { a = NLDAcc * 0.25, v = NLDVel * 0.25, cp = 100 })
    LogInfo("Robot go home success!")
	local value1 = GetHoldRegs(1, 5007, 1, "U16")
	print(value1)
	local value2 = GetHoldRegs(1, 5009, 1, "U16")
	print(value2)
end
---------------------------------------------------------------
--获取点位模式
local function GetPointMode(CMode, CType)
    if CMode == MotionType.Part then
        ErrorMessage.PointInfo.Type = CType.Part
    else
        ErrorMessage.PointInfo.Type = CType.Norm
    end
end
---------------------------------------------------------------
--获取点位类型
local function GetPointType(CPoint)
    if CPoint.Paras.ErrIndex <= PointType.Trans.Index.E then
        GetPointMode(CPoint.Paras.Mode, PointType.Trans.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex == PointType.Pick.Index.A then
        GetPointMode(CPoint.Paras.Mode, PointType.Pick.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex == PointType.PickOffset.Index.A then
        GetPointMode(CPoint.Paras.Mode, PointType.PickOffset.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex >= PointType.Place.Index.A
        and CPoint.Paras.ErrIndex <= PointType.Place.Index.D then
        GetPointMode(CPoint.Paras.Mode, PointType.Place.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex >= PointType.PlaceOffset.Index.A
        and CPoint.Paras.ErrIndex <= PointType.PlaceOffset.Index.D then
        GetPointMode(CPoint.Paras.Mode, PointType.PlaceOffset.Cfg)
        return
    end

    if CPoint.Paras.ErrIndex >= PointType.Insert.Index.A then
        GetPointMode(CPoint.Paras.Mode, PointType.Insert.Cfg)
        return
    end
end
---------------------------------------------------------------
--获取点位信息
local function GetPointInfo(PalletNumber, CPoint)
    local LayerNum = 0
    GetPointType(CPoint)
    if PalletNumber.Mode == WorkType.Pallet then
        if (PalletNumber.ProcessNum.BoxCount >= PalletNumber.PalletNum.LayerBoxNum)
            and (PalletNumber.PalletNum.LayerBoxNum > 0) and (CPoint.Paras.Mode == MotionType.Norm) then
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount + 1
        else
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
        end
    else
        local LocalLayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
        local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
        if (PalletNumber.ProcessNum.BoxCount <= TempBoxNum)
            and (TempBoxNum > 0) then
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount - 1
        else
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
        end
    end
    if ErrorMessage.PointInfo.Type == 5 or ErrorMessage.PointInfo.Type == 6 then
        ErrorMessage.PointInfo.Index = PalletNumber.PalletNum.NextBoxCount
    else
        for i = 1, (ErrorMessage.PointInfo.Layer - 1) do
            LayerNum = LayerNum + GetOddBoxCnt(PalletName, PalletNumber.Pallet, i)
        end
        ErrorMessage.PointInfo.Index = PalletNumber.PalletNum.NextBoxCount - LayerNum
    end
    ErrorMessage.PointInfo.PalletNum = PalletNumber.Pallet
    LogError("Point unreachable - Pallet: %d, Type: %d, Layer: %d, Index: %d",
        ErrorMessage.PointInfo.PalletNum, ErrorMessage.PointInfo.Type,
        ErrorMessage.PointInfo.Layer, ErrorMessage.PointInfo.Index)
    Alarm("CPoint Unreachable!", ErrorMessage.Type.PointErr)
end
---------------------------------------------------------------
--计算码垛数量
local function GetPalletIndex(PalletNumber)
    if PalletNumber.ProcessNum.BoxCount > PalletNumber.PalletNum.LayerBoxNum then
        if PalletNumber.PalletNum.LayerBoxNum > 0 then
            PalletNumber.PalletNum.LayerCount = PalletNumber.PalletNum.LayerCount + 1
        end
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.PalletNum.LayerBoxNum +
            GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
        if SimulateMode == 1 then
            SimulateProcess.LayerNum = SimulateProcess.LayerNum + 1
            StatisticLayerRate()
        end    
    end

    PalletNumber.PalletNum.RemainBoxNum = PalletNumber.PalletNum.LayerBoxNum - PalletNumber.ProcessNum.BoxCount
end
---------------------------------------------------------------
--计算放置箱子数量
local function CalPlaceBoxNum(PalletNumber, CPoint)
    if (PalletNumber.PalletNum.NextBoxCount <= PalletNumber.ProcessNum.TotalBoxNum) then
        PalletNumber.ProcessNum.BoxCount = PalletNumber.PalletNum.NextBoxCount        --托盘已放置箱体的数量
        PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount + 1 --托盘下一个放置箱体的数量
        PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(PalletName, PalletNumber.Pallet)
        if PalletNumber.ProcessNum.BoxCount > PalletNumber.ProcessNum.TotalBoxNum then
            LogWarn("BoxCount is wrong!")
            PalletNumber.ProcessNum.BoxCount = PalletNumber.ProcessNum.TotalBoxNum
            PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.TotalBoxNum + 1
        end
        GetPalletIndex(PalletNumber)
        if (CPoint.Paras.Sucker > 0) then
            PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount +
                math.ceil(CPoint.Paras.Sucker * 0.5)
        end

        CommitPalletNum(PalletNumber)  --上传已有料箱层数、剩余料箱数
        PlaceCountPallet(PalletNumber) --调用放置计数程序
    end
    --判断托盘是否已满载。当托盘计数大于单侧箱体的总数视为满载
    if (PalletNumber.PalletNum.NextBoxCount > PalletNumber.ProcessNum.TotalBoxNum) then
        if (PalletNumber.Partition.Enable == true) then
            if (PalletNumber.Partition.Last == false)
                and (PalletNumber.Partition.Layer[PalletNumber.Layer + 1] == 1) then
                PalletNumber.Partition.Last = true
                LogInfo("Enter last layer partition motion!")
                return
            else
                PalletNumber.Partition.Last = false
            end
        end
        PalletNumber.State.Done = true --将满载布尔变量置为true
        if (StateMachine ~= FSMType.DLR)
            or ((StateMachine == FSMType.DLR)
                and (FirstPallet.State.Done == true)
                and (SecondPallet.State.Done == true)) then
            PalletNumber.State.StateReady = false
        end
        if SimulateMode == 1 then
            LogInfo(" %s pallet is full!", (Pallet == Left) and 'Left' or 'Right')
            if FirstPallet.State.Done then
                StatisticPalletRate(SimulateProcess.LeftPallet)
            end
            if SecondPallet.State.Done then
                StatisticPalletRate(SimulateProcess.RightPallet)
            end
            if PalletNumber.State.StateReady == false then
                LogInfo("NotReady!")
                SimulateProcess.LayerNum = 1      --当前操作层数
                SimulateProcess.LayerBoxIndex = 0 --当前层的箱子索引
                SimulateProcess.LayerBoxNum = 0   --首层到当前层搬运的箱子数
                SimulateProcess.PickIndex = 1     --吸取索引
            end
        end
        LogInfo("%s pallet is completed!", (PalletNumber.Pallet == Left) and "Left" or "Right")
    end
end
---------------------------------------------------------------
--计算拆垛数量
local function GetDePalletIndex(PalletNumber)
    local LocalLayerBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet, PalletNumber.PalletNum.LayerCount)
    local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
    PalletNumber.PalletNum.RemainBoxNum = PalletNumber.ProcessNum.BoxCount - TempBoxNum
    if PalletNumber.ProcessNum.BoxCount <= TempBoxNum then
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
        if PalletNumber.PalletNum.LayerBoxNum > 0 then
            PalletNumber.PalletNum.LayerCount = PalletNumber.PalletNum.LayerCount - 1
            PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(PalletName, PalletNumber.Pallet,
                PalletNumber.PalletNum.LayerCount)
            if SimulateMode == 1 then
                StatisticLayerRate()
            end
        end
    end
end
---------------------------------------------------------------
--计算拆垛箱子数量
local function CalDePalletPlaceBoxNum(PalletNumber, CPoint)
    if (PalletNumber.PalletNum.NextBoxCount > 0) then
        PalletNumber.ProcessNum.BoxCount = PalletNumber.PalletNum.NextBoxCount - 1 --托盘已放置箱体的数量
        PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount     --托盘下一个放置箱体的数量
        if (PalletNumber.ProcessNum.BoxCount < 0) then
            LogWarn("BoxCount is wrong!")
            PalletNumber.ProcessNum.BoxCount = 0
            PalletNumber.PalletNum.NextBoxCount = 0
        end
        GetDePalletIndex(PalletNumber)
        if (CPoint.Paras.Sucker > 0) then
            PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount -
                math.ceil(CPoint.Paras.Sucker * 0.5)
        end

        CommitPalletNum(PalletNumber)                  --上传已有料箱层数、剩余料箱数
        PlaceCountPallet(PalletNumber)                 --调用放置计数程序
    end
    if (PalletNumber.PalletNum.NextBoxCount <= 0) then --判断托盘是否已满载。当托盘计数大于单侧箱体的总数视为满载
        if (PalletNumber.Partition.Enable == true) then
            if (PalletNumber.Partition.Last == false) and (PalletNumber.Partition.Layer[1] == 1) then
                PalletNumber.Partition.Last = true
                LogInfo("Enter last layer partition motion!")
                return
            else
                PalletNumber.Partition.Last = false
            end
        end
        PalletNumber.State.Done = true --将满载布尔变量置为true
        if (StateMachine ~= FSMType.DLR)
            or ((StateMachine == FSMType.DLR)
                and (FirstPallet.State.Done == true)
                and (SecondPallet.State.Done == true))
        then
            PalletNumber.State.StateReady = false
        end
        if SimulateMode == 1 then
            LogInfo(" %s pallet is empty!", (Pallet == Left) and 'Left' or 'Right')
            if FirstPallet.State.Done == true then
                StatisticPalletRate(SimulateProcess.LeftPallet)
            end

            if SecondPallet.State.Done == true then
                StatisticPalletRate(SimulateProcess.RightPallet)
            end
        end
        LogInfo("%s pallet is completed!", (PalletNumber.Pallet == Left) and "Left" or "Right")
    end
end
---------------------------------------------------------------
--吸盘控制
---------------------------------------------------------------
--吸盘控制
local function SuckerControll(PortCfg, State, Num)
    local DIPorts = {
        PortCfg.A,
        PortCfg.B,
        PortCfg.C,
        PortCfg.D
    }
    for i = 1, Num do
        IORes(PortCfg.Mode, DIPorts[i], State)
    end
end
---------------------------------------------------------------
--吸盘安全信号
local function SuckerSafeIO(State)
    if (SPortCfg.Enable == true or Communication.Lifting.Mode == LiftingType.EWELLIX) then
        IORes(SPortCfg.Port.Mode, SPortCfg.Port.A, State)
    end
end
---------------------------------------------------------------
--检测吸盘状态
local function VerifySuckerDO(PortCfg, DOIndex, ExpectedState)
    local ActualState = CheckDORes(PortCfg.Mode, DOIndex)
    if (ActualState ~= ExpectedState) then
        Alarm("Sucker DO" .. tostring(DOIndex) .. " state mismatch!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--初始化吸盘
local function InitSucker()
    DropDete(FirstPallet, DropType.Prep)
    DropDete(SecondPallet, DropType.Prep)

    if (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
        local ErrA = 0
        local ErrB = 0
        SetTool485(Communication.Sucker.Tcp.BaudRate, Communication.Sucker.Tcp.Parity,
            Communication.Sucker.Tcp.StopBit)
        ErrA, Communication.Sucker.Tcp.Socket = TCPCreate(false,
            Communication.Sucker.Tcp.Ip, Communication.Sucker.Tcp.Port) --创建TCP客户端
        ErrB = TCPStart(Communication.Sucker.Tcp.Socket, 5)             --建立TCP连接
        if ErrA ~= 0 or ErrB ~= 0 then
            Alarm("Initialized sucker failed!", ErrorMessage.Type.IPErr)
        else
            LogInfo("Create sucker tcp client success!")
        end
    else
        SuckerControll(SuckerCfg.Port, OFF, math.abs(PalletSuckerFunction))
        if (PalletSuckerFunction ~= SuckerCfg.Type.SSingle) then
            SuckerSafeIO(OFF)
        end
        if PartCfg.Enable then
            IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF)
        end

        if SuckerCfg.Dete.VacuumBreak.Enable == 1 then
            SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.abs(PalletSuckerFunction))
        end
    end
	DO(15,OFF)
	DO(17,OFF)
    LogInfo("Initialized sucker success!")
end
---------------------------------------------------------------
--计算偏心工具
local function CalcEccTool(PalletNumber, Sucker, BoxNum)
    local CTool = {}
    local PlaceNum = math.abs(PalletSuckerFunction)
    if (PlaceNum == BoxNum) then
        CTool = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    else
        local Ecc = {}
        local EccTool = {}
        local EccData = {}
        Ecc, EccTool, EccData = GetPalletTool(PalletName, ToolType.Ecc)
        local EccLength = {}

        if (Sucker ~= -1) then
            EccLength = (PlaceNum - 1) * EccTool[2][1]
        else
            EccLength = (PlaceNum - 1) * EccTool[3][1]
        end

        local SwitchSucker =
        {
            [SuckerCfg.Type.Double] = function()
                EccTool[2][1] = EccTool[1][1] + EccLength * math.cos(EccTool[1][6] / 180 * math.pi)
                EccTool[2][2] = EccTool[1][2] + EccLength * math.sin(EccTool[1][6] / 180 * math.pi)
                CTool = DeepCopy(EccTool[2])
            end,
            [SuckerCfg.Type.Triple] = function()
                CTool = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
            end,
            [SuckerCfg.Type.Quadruple] = function()
                CTool = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
            end
        }

        local switch_mode = SwitchSucker[PlaceNum]
        if switch_mode then
            switch_mode()
        else
            Alarm("Sucker type is wrong!", ErrorMessage.Type.WorkingDataErr)
        end
    end

    LogInfoTable("CTool:", CTool)
    return CTool
end
---------------------------------------------------------------
--打开吸盘
local function OpenSucker(PalletNumber, CPoint, CIndex)
    local BoxNum = 0
    local CTool = {}
    local SwitchOpenSucker =
    {
        [MotionType.Norm] = function()
            if (CPoint.Paras.Sucker == -1) then
                if (PalletNumber.Mode == WorkType.Pallet) then
                    BoxNum = math.abs(PalletSuckerFunction)
                    SuckerControll(SuckerCfg.Port, ON, BoxNum)
                    DO(15, ON)
                    Wait(1000)
                    local DOs = { SuckerCfg.Port.A, SuckerCfg.Port.B, SuckerCfg.Port.C, SuckerCfg.Port.D }
                    for i = 1, BoxNum do
                        VerifySuckerDO(SuckerCfg.Port, DOs[i], ON)
                    end
                    DO(15, ON)
                  
                else
                    BoxNum = CIndex
                    if (CIndex == 1) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A, ON)
                        DO(15, ON)
                       
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.A, ON)
                        DO(15, ON)
                        
                    elseif (CIndex == 2) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B, ON)
                        DO(15, ON)
                        
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.B, ON)
                        DO(15, ON)
                       
                    elseif (CIndex == 3) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.C, ON)
                        DO(15, ON)
                        
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.C, ON)
                        DO(15, ON)
                       
                    elseif (CIndex == 4) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.D, ON)
                        DO(15, ON)
                        
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.D, ON)
                        DO(15, ON)
                       
                    end
                end
                SuckerSafeIO(OFF)
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle and CPoint.Paras.Sucker == 0) then
                BoxNum = 1
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOn)
            else
                BoxNum = math.ceil(0.5 * CPoint.Paras.Sucker) + 1
                SuckerControll(SuckerCfg.Port, ON, BoxNum)
                DO(15, ON)
               
                Wait(1000)
                local DOs = { SuckerCfg.Port.A, SuckerCfg.Port.B, SuckerCfg.Port.C, SuckerCfg.Port.D }
                for i = 1, BoxNum do
                    VerifySuckerDO(SuckerCfg.Port, DOs[i], ON)
                end
                DO(15, ON)
                
                SuckerSafeIO(OFF)
            end
            Wait(Time.Pick.In)
            CTool = CalcEccTool(PalletNumber, CPoint.Paras.Sucker, BoxNum)
            
            SetPayload(BoxNum * PalletNumber.BoxProperty.BoxWeight + ToolWeight,
                { CTool[1], CTool[2], 0.5 * (CTool[3] + PalletNumber.BoxProperty.BoxHigh) }) --commande de réglage de la charge, ajouter le poids de la boîte
        end,
        [MotionType.Part] = function()
            if (PartCfg.Enable == true) then
                IORes(PartCfg.Port.Mode, PartCfg.Port.A, ON)
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOn)
            else
                SuckerControll(SuckerCfg.Port, ON, math.abs(PalletSuckerFunction))
                DO(15, ON)
                
                SuckerSafeIO(OFF)
            end
            Wait(Time.Pick.In)
            CTool = CalcEccTool(PalletNumber, CPoint.Paras.Sucker, PalletSuckerFunction)
            
            SetPayload(PalletNumber.ProcessNum.PartitionWeight + ToolWeight,
                { CTool[1], CTool[2], 0.5 * CTool[3] }) --设置负载指令，加上箱子重量
        end
    }

    local switch_mode = SwitchOpenSucker[CPoint.Paras.Mode]
    if switch_mode then
        switch_mode()
        LogInfo("OpenSucker success!")
    else
        Alarm("OpenSucker is error, please check it!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--关闭吸盘
local function CloseSucker(PalletNumber, CPoint, CIndex)
    local CTool = {}
    if ((CPoint.Paras.Sucker ~= -1) or (CPoint.Paras.Sucker == -1 and CIndex == PalletSuckerFunction)) then
        CTool = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    else
        CTool = CalcEccTool(PalletNumber, CPoint.Paras.Sucker, CIndex)
    end
    local Weight = (PalletSuckerFunction - CIndex) * PalletNumber.BoxProperty.BoxWeight + ToolWeight
       SetPayload(Weight, { CTool[1], CTool[2], 0.5 * CTool[3] }) ---définir la charge utile comme la charge correspondant à la prise (aspiration) de la boîte
    LogInfo("BoxWeight: %s", Weight)
    local SwitchCloseSucker =
    {
        [MotionType.Norm] = function()
            if (CPoint.Paras.Sucker == -1) then
                if (PalletNumber.Mode == WorkType.Pallet) then
                    if (CIndex == 1) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A, OFF)
                    elseif (CIndex == 2) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B, OFF)
                    elseif (CIndex == 3) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.C, OFF)
                    elseif (CIndex == 4) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.D, OFF)
                    end
                    DO(15, OFF)
                    SuckerSafeIO(ON)
                    if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                        if (CIndex == 1) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.A, ON)
                        elseif (CIndex == 2) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.B, ON)
                        elseif (CIndex == 3) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.C, ON)
                        elseif (CIndex == 4) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.D, ON)
                        end
                        DO(17, ON)
                        Wait(Time.Place.In)
                        if (CIndex == 1) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.A, OFF)
                        elseif (CIndex == 2) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.B, OFF)
                        elseif (CIndex == 3) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.C, OFF)
                        elseif (CIndex == 4) then
                            IORes(SuckerCfg.Dete.VacuumBreak.Mode, SuckerCfg.Dete.VacuumBreak.D, OFF)
                        end
                        DO(17, OFF)
                        return
                    end
                else
                    SuckerControll(SuckerCfg.Port, OFF, math.abs(PalletSuckerFunction))
                    DO(15, OFF)
                    SuckerSafeIO(ON)
                    if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                        SuckerControll(SuckerCfg.Dete.VacuumBreak, ON, math.abs(PalletSuckerFunction))
                        DO(17, ON)
                        Wait(Time.Place.In)
                        SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.abs(PalletSuckerFunction))
                        DO(17, OFF)
                        return
                    end
                end
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle and CPoint.Paras.Sucker == 0) then
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOff)
            else
                SuckerControll(SuckerCfg.Port, OFF, math.ceil(0.5 * CPoint.Paras.Sucker) + 1)
                DO(15, OFF)
                SuckerSafeIO(ON)
                if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, ON, math.ceil(0.5 * CPoint.Paras.Sucker) + 1)
                    DO(17, ON)
                    Wait(Time.Place.In)
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.ceil(0.5 * CPoint.Paras.Sucker) + 1)
                    DO(17, OFF)
                    return
                end
            end
            DO(17, ON)
            Wait(Time.Place.In)
            DO(17, OFF)
        end,
        [MotionType.Part] = function()
            if (PartCfg.Enable == true) then
                IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF)
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOff)
            else
                SuckerControll(SuckerCfg.Port, OFF, math.abs(PalletSuckerFunction))
                DO(15, OFF)
                SuckerSafeIO(ON)
                if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, ON, math.abs(PalletSuckerFunction))
                    DO(17, ON)
                    Wait(Time.Place.In)
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.abs(PalletSuckerFunction))
                    DO(17, OFF)
                    return
                end
            end
            DO(17, ON)
            Wait(Time.Place.In)
            DO(17, OFF)
        end
    }

    local switch_mode = SwitchCloseSucker[CPoint.Paras.Mode]
    if switch_mode then
        switch_mode()
        LogInfo("CloseSucker success!")
    else
        Alarm("CloseSucker is error, please check it!", ErrorMessage.Type.WorkingDataErr)
    end
end
---------------------------------------------------------------
--初始化三色灯状态
local function InitLight()
    if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
        TriLightStatus(FirstPallet, Light.Green.On)
        TriLightStatus(SecondPallet, Light.Green.On)
    elseif (StateMachine == FSMType.SL) then
        TriLightStatus(FirstPallet, Light.Green.On)
        TriLightStatus(SecondPallet, Light.Init)
    else
        TriLightStatus(FirstPallet, Light.Init)
        TriLightStatus(SecondPallet, Light.Green.On)
    end
    LogInfo("Initialized tri-color light success!")
end
---------------------------------------------------------------
--初始化，复位信号、复位程序数据
local function InitPallet()
    if BuzzerFunction == true then
        DO(BuzzerIO, OFF) --关闭蜂鸣器
        LogInfo("Initialized buzzer success!")
    end
    InitSucker()      --吸盘初始化
    InitLight()       --三色灯初始化
    if (PalletLiftingFunction == true) then
        InitLifting() --与升降轴建立TCP通讯
    end
    RobotGoHome()
end
---------------------------------------------------------------
--缠膜功能
local function FilmMotion()
    local DestPose = {}
    local JointAngle = {}
    if FilmFunction == true then
        if (DI(FilmDI) == ON)
            and (FilmDone == true)
            and (CheckDORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A) == OFF)
            and (CheckDORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B) == OFF) then
            FilmDone = false
            JointAngle = DeepCopy(LiftingPoint)
            MovJ(JointAngle, { a = NLDAcc, v = NLDVel, cp = 100 })
            DestPose = GetPose()
            if PrePoseHeight > DestPose.pose[3] then
                AdjustLiftingHeight(math.floor(PrePoseHeight - DestPose.pose[3]))
            end

            if PrePallet == 1 then
                JointAngle.joint[1] = 180
            elseif PrePallet == 2 then
                JointAngle.joint[1] = 0
            else
                Alarm("Pallet is wrong!", ErrorMessage.Type.WorkingDataErr)
            end
            MovJ(JointAngle, { a = NLDAcc, v = NLDVel, cp = 100 })
            LogInfo("Enter FilmMotion!")
        end
        if (DI(FilmDI) == OFF) and (FilmDone == false) then
            MovJ(LiftingPoint, { a = NLDAcc, v = NLDVel, cp = 100 })
            DestPose = GetPose()
            if PrePoseHeight > DestPose.pose[3] then
                AdjustLiftingHeight(math.floor(PrePoseHeight - DestPose.pose[3]))
            end
            FilmDone = true
            LogInfo("Exit FilmMotion!")
        end
    end
end
---------------------------------------------------------------
--J1安全分支归一化：本项目禁止J1继续向负方向绕到操作员侧
--现场安全分支：当前隔板放置后约-50°，安全点90°，取货点约150°
--因此目标J1如果被逆解成-210°/-270°，需要转换成等效的150°/90°
local J1SafeMin = -60
local J1SafeMax = 200

local function NormalizeJ1ToSafeBranch(j1)
    if j1 == nil then
        return j1
    end

    while j1 < J1SafeMin do
        j1 = j1 + 360
    end

    while j1 > J1SafeMax do
        j1 = j1 - 360
    end

    if (j1 < J1SafeMin) or (j1 > J1SafeMax) then
        LogError("J1 target out of safe branch: %s", tostring(j1))
        Alarm("J1 target out of safe branch!", ErrorMessage.Type.PointErr)
    end

    return j1
end

-- J6 soft limit is narrower than an unlimited equivalent-angle normalization.
-- The controller accepts equivalent wrist angles only inside the joint software limit.
-- In the latest fault, current J6 was about -329°, and the previous "nearest angle" logic
-- converted the next target to -443°, which is mathematically equivalent but outside J6 limit.
local J6SoftMin = -360
local J6SoftMax = 360

local function NormalizeJ6ToValidRange(j6, UseCurrentNearest)
    if j6 == nil then
        return j6
    end

    local RefJ6 = j6
    if UseCurrentNearest == true then
        local CurrentJoint = GetAngle().joint
        if (CurrentJoint ~= nil) and (CurrentJoint[6] ~= nil) then
            RefJ6 = CurrentJoint[6]
        end
    end

    local BestJ6 = nil
    local BestDiff = nil

    -- Try all nearby equivalent angles and choose the one inside the soft limit.
    -- If UseCurrentNearest=true, choose the valid one closest to current J6.
    -- If UseCurrentNearest=false, normally the original taught/calculated value is kept.
    for k = -3, 3 do
        local Candidate = j6 + 360 * k
        if (Candidate >= J6SoftMin) and (Candidate <= J6SoftMax) then
            local Diff = math.abs(Candidate - RefJ6)
            if (BestJ6 == nil) or (Diff < BestDiff) then
                BestJ6 = Candidate
                BestDiff = Diff
            end
        end
    end

    if BestJ6 ~= nil then
        return BestJ6
    end

    LogError("J6 target out of software limit after normalization: %s", tostring(j6))
    Alarm("J6 target out of software limit!", ErrorMessage.Type.PointErr)
    return j6
end

local function NormalizeJointForSafeBranch(Point, NormalizeJ6)
    local P = DeepCopy(Point)

    if (P ~= nil) and (P.joint ~= nil) then
        P.joint[1] = NormalizeJ1ToSafeBranch(P.joint[1])
        -- Always keep J6 inside the software limit.
        -- NormalizeJ6=true only means "prefer the equivalent angle closest to current J6".
        P.joint[6] = NormalizeJ6ToValidRange(P.joint[6], NormalizeJ6 == true)
    end

    return P
end

local function SafeMovJ(Point, Option, NormalizeJ6)
    local P = NormalizeJointForSafeBranch(Point, NormalizeJ6)
    MovJ(P, Option)
end

local function SafeMovL(Point, Option, NormalizeJ6)
    local P = NormalizeJointForSafeBranch(Point, NormalizeJ6)
    MovL(P, Option)
end

---------------------------------------------------------------
--过渡点运动
local function TransMotion(CPoint, CDir, Acc, Vel)
    local SD = 1
    local ED = CPoint.Paras.TransNum
    if (CDir == Dir.Backward) then
        SD = CPoint.Paras.TransNum
        ED = 1
    end
    for i = SD, ED, CDir do
        local TPoint = CPoint.MotionPoint[i]
        if (CDir == Dir.Backward)
            and (CPoint.BackwardMotionPoint ~= nil)
            and (type(CPoint.BackwardMotionPoint[i]) == "table") then
            -- backward使用src3提供的回程过渡点：J6已经改为终点standby的J6
            TPoint = CPoint.BackwardMotionPoint[i]
        end

        if (type(TPoint) == "table") then
            -- 普通箱子过渡点/回程过渡点主要用于安全换姿态，不是工艺直线路径。
            -- 使用 MovL 走普通 joint transition 时，J5 接近 ±90° 或 J6 跨分支会增加预处理失败风险。
            -- 但隔板 forward 是实际取隔板后的贴近/放置路径，需要保留 MovL。
            local TAcc = Acc
            local TVel = Vel
            if (TAcc == nil) or (TAcc > 30) then
                TAcc = 30
            end
            if (TVel == nil) or (TVel > 30) then
                TVel = 30
            end

            if (CDir == Dir.Backward) then
                if (CPoint.Paras.Mode == MotionType.Part) then
                    -- 隔板 backward：从隔板/支架区域退出时保留 MovL，避免 MovJ 走非直线路径扫到隔板支架
                    -- cp=0：尽量按 backward transition 点精确退出，底层更安全
                    -- J1归一到安全分支，J6选择当前最近且在软限位内的等效角
                    SafeMovL(TPoint, { a = TAcc, v = TVel, cp = 0 }, true)
                else
                    -- 普通箱子 backward：不是工艺直线路径，继续用 MovJ，降低奇异区/软限位风险
                    -- J1归一到安全分支，J6选择当前最近且在软限位内的等效角
                    SafeMovJ(TPoint, { a = TAcc, v = TVel, cp = 0 }, true)
                end
            else
                if (CPoint.Paras.Mode == MotionType.Part) then
                    -- 隔板 forward：取隔板后到放隔板区域必须用 MovL，保持现场示教的贴近/放置效果
                    -- 这里只做J1安全分支和J6软限位检查，不再把J6强行贴近当前角度
                    SafeMovL(TPoint, { a = TAcc, v = TVel, cp = 100 }, false)
                else
                    -- 普通箱子 forward：不是工艺直线贴合路径，继续用 MovJ，避免J5≈±90°时MovL预处理失败
                    -- J6选择当前最近且在软限位内的等效角，防止再次生成-443°这类非法角度
                    SafeMovJ(TPoint, { a = TAcc, v = TVel, cp = 0 }, true)
                end
            end
        end
    end
end
---------------------------------------------------------------
--升降柱运动
local function SyncMotion(CLH)
    if (SimulateMode == 1) then
        SyncSignal = false
        if SimulateProcess.LiftingColumn.UsedTime ~= 0 then
            -- if (CLH < 1) then
            Wait(math.ceil(SimulateProcess.LiftingColumn.UsedTime))
            SimulateProcess.LiftingColumn.UsedTime = 0
            -- else
            --     Wait(100)
            -- end
        end
        return
    end
    if (SyncSignal == true) then
        SyncSignal = false
        LiftingMotion(CLH)
    end
end
---------------------------------------------------------------
--获取隔板standby关节，供backward过渡点和standby共用同一个J6
local function GetPartitionStandbyJoint(CPoint)
    local Standy = { pose = {} }
    Standy.pose = DeepCopy(CPoint.Paras.Standy.pose)
    Standy.pose[3] = Standy.pose[3] - CPoint.Paras.LH

    local ErrId, StandyJoint = InverseKin(Standy)
    if (ErrId ~= 0) or (StandyJoint == nil) or (StandyJoint.joint == nil) then
        Alarm("InverseKin for partition standby failed!", ErrorMessage.Type.PointErr)
    end

    return StandyJoint
end

---------------------------------------------------------------

---
--待机位置运动
local function StandyMotion(PalletNumber, CPoint)
    if (PalletNumber.State.StateReady == false) and (LiftingHeight > 1) then
        SafeMovL(CPoint.Paras.Standy, { a = NLDAcc, v = NLDVel, cp = 100 }, false)
        AdjustLiftingHeight(Home)
        SyncMotion(Home)
    elseif (CPoint.Paras.Mode == MotionType.Part) then
        -- 隔板回standby：优先使用src3提供的standby joint，保证与backward transition的终点J6一致
        if (CPoint.StandyMotionPoint ~= nil) and (CPoint.StandyMotionPoint.joint ~= nil) then
            SafeMovJ(CPoint.StandyMotionPoint, { a = NLDAcc, v = NLDVel, cp = 100 }, true)
        else
            SafeMovJ(GetPartitionStandbyJoint(CPoint), { a = NLDAcc, v = NLDVel, cp = 100 }, true)
        end
    else
        SafeMovL(CPoint.MotionPoint[7], { a = NLDAcc, v = NLDVel, cp = 100 }, false)
    end
end
---------------------------------------------------------------
--隔板放置后先回安全点，避免直接回standby时J1转到操作员侧危险区域
local function PartitionGoSafePoint(CPoint, UseGlobalPartSafePoint, KeepCurrentJ6)
    local SafePoint = nil

    if (UseGlobalPartSafePoint ~= true)
        and (CPoint.MotionPoint[7] ~= nil)
        and (CPoint.MotionPoint[7].joint ~= nil) then
        --隔板运动自身/下一笔隔板动作：优先使用src3计算出来的MotionPoint[7]隔板安全点
        SafePoint = DeepCopy(CPoint.MotionPoint[7])
    else
        --兜底才使用全局隔板安全点PartSafePoint
        SafePoint = DeepCopy(PartSafePoint)
    end

    --默认保持当前J6，避免刚离开放置点就发生腕部旋转。
    --但普通箱子最后一箱后准备进入隔板时，需要直接去“下一笔隔板安全点”的完整joint，
    --这样下一笔隔板动作不会在安全点再额外转一次J6。
    if KeepCurrentJ6 ~= false then
        local CurrentJoint = GetAngle().joint
        if (SafePoint.joint ~= nil) and (CurrentJoint ~= nil) then
            SafePoint.joint[6] = CurrentJoint[6]
        end
    end

    SafeMovJ(SafePoint, { a = NLDAcc, v = NLDVel, cp = 100 }, true)
end

--获取队列里的下一笔隔板动作；用于普通箱子最后一箱后直接去下一笔隔板安全点
local function GetNextPartitionMotion(CQueue)
    if (CQueue == nil) or (CQueue:IsEmpty() == true) then
        return nil
    end

    local NextPoint = CQueue:Peek()
    if (NextPoint ~= nil)
        and (NextPoint.Paras ~= nil)
        and (NextPoint.Paras.Mode == MotionType.Part) then
        return NextPoint
    end

    return nil
end
---------------------------------------------------------------
--隔板余量传感器检测：放置隔板后检测料仓是否还有隔板
--DI = ON/1：认为料仓有隔板，恢复默认隔板数量，并写入Modbus/SetVal
--DI = OFF/0：认为料仓无隔板，将剩余隔板数量置为0，并写入Modbus/SetVal
local function CheckPartitionRemainSensor(PalletNumber, CPoint)
    if (CPoint == nil) or (CPoint.Paras == nil) then
        return
    end

    if (CPoint.Paras.Mode ~= MotionType.Part) or (PalletNumber.Mode ~= WorkType.Pallet) then
        return
    end

    if (PartSensorCfg == nil) or (PartSensorCfg.Enable ~= true) then
        return
    end

    if (PartSensorCfg.Port == nil) or (PartSensorCfg.Port.A == nil) then
        LogWarn("Partition remain sensor DI is not configured!")
        return
    end

    if SimulateMode == 1 then
        return
    end

    local DelayTime = PartSensorCfg.DelayTime or 0
    local SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)

    if DelayTime > 0 then
        Wait(DelayTime)
        SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)
    end

    if SensorState == ON then
        PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
        WritePartNum(PalletNumber)
        LogInfo("Partition remain sensor DI%s is ON. Restore remaining partition number to default and write Modbus: %s.",
            tostring(PartSensorCfg.Port.A), tostring(PalletNumber.Partition.RePartNum))
    else
        PalletNumber.Partition.RePartNum = 0
        WritePartNum(PalletNumber)
        LogWarn("Partition remain sensor DI%s is OFF. Set remaining partition number to 0 and write Modbus.",
            tostring(PartSensorCfg.Port.A))
    end
end
---------------------------------------------------------------
--隔板动作开始前检测：如果传感器已经确认无隔板，则不再继续执行取隔板动作
local function CheckPartitionRemainBeforeMotion(PalletNumber, CPoint)
    if (CPoint == nil) or (CPoint.Paras == nil) then
        return true
    end

    if (CPoint.Paras.Mode ~= MotionType.Part) or (PalletNumber.Mode ~= WorkType.Pallet) then
        return true
    end

    if (PartSensorCfg == nil) or (PartSensorCfg.Enable ~= true) then
        return true
    end

    if (PartSensorCfg.Port == nil) or (PartSensorCfg.Port.A == nil) then
        LogWarn("Partition remain sensor DI is not configured!")
        return true
    end

    if SimulateMode == 1 then
        return true
    end

    local DelayTime = PartSensorCfg.DelayTime or 0
    local SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)

    if DelayTime > 0 then
        Wait(DelayTime)
        SensorState = CheckDIRes(PartSensorCfg.Port.Mode, PartSensorCfg.Port.A)
    end

    if SensorState == OFF then
        PalletNumber.Partition.RePartNum = 0
        WritePartNum(PalletNumber)
        LogWarn("Partition remain sensor DI%s is OFF before partition motion. Set remaining partition number to 0.",
            tostring(PartSensorCfg.Port.A))
        Alarm("Partition is empty!", ErrorMessage.Type.PartErr)
        return false
    end

    -- 当前传感器检测到有隔板时，强制恢复默认数量，并写入Modbus/SetVal。
    -- 这样即使之前被写成0，补充隔板后也能恢复显示值。
    if PalletNumber.Partition.RePartNum ~= PalletNumber.ProcessNum.PartitionNum then
        PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
        WritePartNum(PalletNumber)
        LogInfo("Partition remain sensor DI%s is ON before partition motion. Restore remaining partition number to default and write Modbus: %s.",
            tostring(PartSensorCfg.Port.A), tostring(PalletNumber.Partition.RePartNum))
    end

    return true
end
---------------------------------------------------------------
--更新隔板数据
local function UpdatePartData(PalletNumber, CPoint)
    if (CPoint.Paras.Mode == MotionType.Part) then
        -- 使用隔板余量传感器时，隔板数量不再由动作次数维护。
        -- 放置后的数量更新只由 CheckPartitionRemainSensor() 负责：
        -- DI=ON 恢复默认数量，DI=OFF 将 RePartNum 写为0。
        if (PalletNumber.Mode == WorkType.Pallet)
            and (PartSensorCfg ~= nil)
            and (PartSensorCfg.Enable == true) then
            return
        end

        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.Partition.RePartNum <= 0) then
                -- 仿真模式，不需要隔板数量报警
                if SimulateMode == 1 then
                    PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
                    return
                end
                Alarm("Partition is empty!", ErrorMessage.Type.PartErr)
                PalletNumber.Partition.RePartNum = PalletNumber.ProcessNum.PartitionNum
                WritePartNum(PalletNumber)
            end
        else
            if (PalletNumber.Partition.RePartNum >= PalletNumber.ProcessNum.PartitionNum) then
                -- 仿真模式，不需要隔板数量报警
                if SimulateMode == 1 then
                    PalletNumber.Partition.RePartNum = 0
                    return
                end
                Alarm("Partition is full!", ErrorMessage.Type.PartErr)
                PalletNumber.Partition.RePartNum = 0
                WritePartNum(PalletNumber)
            end
        end
    end
end
---------------------------------------------------------------
--更新工作数据
local function UpdateData(PalletNumber, CPoint)
    if (PalletNumber.Partition.Enable == true) then
        if (PalletNumber.Pallet == Left) then
            SetVal("PalletPartPlaceA", CPoint.Paras.Mode)
        else
            SetVal("PalletPartPlaceB", CPoint.Paras.Mode)
        end
    end
    if (CPoint.Paras.Mode == MotionType.Norm) or (PalletNumber.Partition.Last == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CalPlaceBoxNum(PalletNumber, CPoint)         --执行托盘码垛计数
        else
            CalDePalletPlaceBoxNum(PalletNumber, CPoint) --执行托盘拆垛计数
        end

    end
    if (CPoint.Paras.Mode == MotionType.Part) then
        -- 使用隔板余量传感器时，放置隔板后不再按动作次数修改 RePartNum。
        -- RePartNum 只由传感器决定：DI=ON恢复默认值，DI=OFF写0。
        if (PartSensorCfg ~= nil) and (PartSensorCfg.Enable == true)
            and (PalletNumber.Mode == WorkType.Pallet) then
            return
        end

        -- 非传感器模式保留原有计数逻辑，避免影响未启用隔板传感器的项目。
        if (PalletNumber.Mode == WorkType.Pallet) then
            PalletNumber.Partition.RePartNum = PalletNumber.Partition.RePartNum - 1
        else
            PalletNumber.Partition.RePartNum = PalletNumber.Partition.RePartNum + 1
        end
        WritePartNum(PalletNumber)
    end
end
---------------------------------------------------------------
--根据栈板类型调整隔板点位（右栈板需要在0用户坐标系下向X方向平移1000mm）
local function GetAdjustedPartitionPoint(PalletNumber, BasePoint)
    local AdjustedPoint = DeepCopy(BasePoint)
    if PalletNumber.Pallet == 1 then
        AdjustedPoint.pose[1] = AdjustedPoint.pose[1] - 1000
    end
    return AdjustedPoint
end
---------------------------------------------------------------
--MotionPoint[index]:
--1~5:过渡点（示教），6:取料（示教），7：取料上方点（自动生成），8~11：放置点（自动生成）
--12~15：放料上方点（自动生成），16~19：放料偏移点（自动生成）
---------------------------------------------------------------
--执行点位运动
local function PTPMotion(PalletNumber, CPoint, CQueue)
    local CPose = { pose = {} }
    -- 仅用于隔板功能的慢抬升参数
    local PartSlowLiftHeight = 200
    local PartSlowLiftAcc = 10
    local PartSlowLiftVel = 10
    -- 隔板放置完成后，先垂直抬升100mm，再走回程过渡点
    local PartPlaceLiftHeight = 100

    if (PalletNumber.Mode == WorkType.Pallet) then
        Wait(Time.Pick.Pre)
        if (CPoint.Paras.Mode == MotionType.Part) then
            if CheckPartitionRemainBeforeMotion(PalletNumber, CPoint) == false then
                return
            end

            local CPartPick = DeepCopy(PartPick)
            CPartPick.pose[3] = CPartPick.pose[3] - CPoint.Paras.LH +
                PalletNumber.ProcessNum.PartitionHeight * PalletNumber.Partition.RePartNum
            SafeMovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = SyncMotionVel, cp = 100 }, true)
            SyncMotion(CPoint.Paras.LH)

            local CPartPickLift = DeepCopy(CPartPick)
            CPartPickLift.pose[3] = CPartPickLift.pose[3] + PartSlowLiftHeight
            MovL(CPartPickLift, { a = NLDAcc, v = NLDVel, cp = 0 })

            MovL(CPartPick, {a = 53, v = 20, stopcond = "AI(1) <= 1.5"}) --运动到抓取点

            --MovL(CPartPick, { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到抓取点

            OpenSucker(PalletNumber, CPoint)

            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end

            -- 取到隔板后：先慢速抬升 200 mm，再恢复原来的速度回上方点
            local CPartPickLift = DeepCopy(CPartPick)
            CPartPickLift.pose[3] = CPartPickLift.pose[3] + PartSlowLiftHeight
            MovL(CPartPickLift, { a = PartSlowLiftAcc, v = PartSlowLiftVel, cp = 0 })

        else
            if ((SingleMotion == false) or (SyncSignal == true)
                    or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet)) then
                SingleMotion = true
                SafeMovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = SyncMotionVel, cp = 100 }, true)
                SyncMotion(CPoint.Paras.LH)
            end
            MovL(CPoint.MotionPoint[6], { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到抓取点
            OpenSucker(PalletNumber, CPoint)
            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end
            MovL(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 }) --运动到抓取点上方
        end
        Wait(Time.Pick.Post)
        TransMotion(CPoint, Dir.Forward, LDAcc, LDVel)
        for i = 1, CPoint.Paras.Times do
            if CPoint.Paras.Mode == MotionType.Part then
                -- 隔板：执行完最后一个过渡点后，直接MovL滑到放置点，不再经过[12]/[16]上方点
                MovL(CPoint.MotionPoint[7 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 0 })
                CloseSucker(PalletNumber, CPoint, i)
                if SimulateMode == 1 then
                    UpdatePlaceBoxState(PalletNumber, CPoint)
                end

                -- 隔板放好后，先从当前放置点垂直抬升100mm，再进入回程过渡点
                local PartPlaceLift = GetPose()
                if (PartPlaceLift ~= nil) and (PartPlaceLift.pose ~= nil) then
                    PartPlaceLift.pose[3] = PartPlaceLift.pose[3] + PartPlaceLiftHeight
                    MovL(PartPlaceLift, { a = NLDAcc, v = NLDVel, cp = 0 })
                end

                UpdateData(PalletNumber, CPoint)
                CheckPartitionRemainSensor(PalletNumber, CPoint)
            else
                if CPoint.Paras.OffSet[i] == 1 then
                    MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 })         --运动到放置过渡点
                    MovL(CPoint.MotionPoint[11 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 100 }) --运动到放置点正上方
                else
                    MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })         --运动到放置点正上方
                end
                MovL(CPoint.MotionPoint[7 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 100 })
                CloseSucker(PalletNumber, CPoint, i)
                if SimulateMode == 1 then
                    UpdatePlaceBoxState(PalletNumber, CPoint)
                end

                UpdateData(PalletNumber, CPoint)

                MovL(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })

                local DepositLiftHeight = 250

                if i < CPoint.Paras.Times then
                    -- 还有下一个 box
                    -- 在当前 arrival point 基础上再抬高 80 mm

                    local currentJoint = { joint = GetAngle().joint }

                    local liftPoint = PositiveKin(currentJoint,
                        { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })

                    liftPoint.pose[3] = liftPoint.pose[3] + DepositLiftHeight

                    local errId, liftJointPoint = InverseKin(liftPoint,
                        { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })

                    if (errId ~= 0) or (liftJointPoint == nil) then
                        Alarm("InverseKin for deposit lift failed!", ErrorMessage.Type.PointErr)
                    end

                    MovL(liftJointPoint, { a = NLDAcc, v = NLDVel, cp = 0 })
                end

                if CPoint.Paras.OffSet[i] == 1 then
                    MovL(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
                end
            end

        end
        local SkipStandby = false
        if CPoint.Paras.Mode == MotionType.Part then
            --隔板：放置后先走backward transition离开放置区域，再去安全点，最后回standby
            TransMotion(CPoint, Dir.Backward, NLDAcc, NLDVel)
            PartitionGoSafePoint(CPoint)
        else
            TransMotion(CPoint, Dir.Backward, NLDAcc, NLDVel)

            --普通箱子：如果当前是每层最后一个box，下一笔队列就是隔板动作，
            --则不要再回取货standby，直接去下一笔隔板动作的安全点，随后进入隔板逻辑
            local NextPartPoint = GetNextPartitionMotion(CQueue)
            if NextPartPoint ~= nil then
                PartitionGoSafePoint(NextPartPoint, false, false)
                SkipStandby = true
            end
        end
        CPose = GetPose()
        if SkipStandby == false then
            StandyMotion(PalletNumber, CPoint)
        end
    else
        if (SingleMotion == false) or (SyncSignal == true)
            or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet) then
            if SingleMotion == false then
                SingleMotion = true
            else
                local Standy = { pose = {} }
                Standy.pose = DeepCopy(CPoint.Paras.Standy.pose)
                Standy.pose[3] = Standy.pose[3] - CPoint.Paras.LH
                SafeMovJ(Standy, { a = NLDAcc, v = SyncMotionVel, cp = 100 }, true)
            end
            SyncMotion(CPoint.Paras.LH)
        end
        TransMotion(CPoint, Dir.Forward, NLDAcc, NLDVel)
        for i = CPoint.Paras.Times, 1, -1 do
            if (CPoint.Paras.OffSet[i] == 1) then
                MovJ(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到放置过渡点
            end
            MovJ(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })     --运动到放置点正上方
            MovL(CPoint.MotionPoint[7 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
            OpenSucker(PalletNumber, CPoint, i)
            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end
            UpdateData(PalletNumber, CPoint)
            MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })     --运动到放置点正上方
            if (CPoint.Paras.OffSet[i] == 1) then
                MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 }) --运动到放置过渡点
            end
        end
        TransMotion(CPoint, Dir.Backward, LDAcc, LDVel)
        CPose = GetPose()
        SafeMovJ(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 }, true)
        if (CPoint.Paras.Mode == MotionType.Part) then
            local CPartPick = GetAdjustedPartitionPoint(PalletNumber, PartPick)
            CPartPick.pose[3] = CPartPick.pose[3] - CPoint.Paras.LH +
                PalletNumber.ProcessNum.PartitionHeight * PalletNumber.Partition.RePartNum
            MovL(CPartPick, { a = NLDAcc, v = NLDVel, cp = 100 })           --运动到抓取点
        else
            MovL(CPoint.MotionPoint[6], { a = LDAcc, v = LDVel, cp = 100 }) --运动到抓取点
        end
        CloseSucker(PalletNumber, CPoint)
        if SimulateMode == 1 then
            UpdatePlaceBoxState(PalletNumber, CPoint)
        end
        if (CPoint.Paras.Mode == MotionType.Part) then
            SafeMovJ(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 }, true)
        end
        StandyMotion(PalletNumber, CPoint)
    end
    UpdatePartData(PalletNumber, CPoint)
    PrePallet = PalletNumber.Pallet
    PrePoseHeight = CPose.pose[3] + CPoint.Paras.LH
end
---------------------------------------------------------------
--运动主流程
local function PreMotion(PalletNumber, CQueue)
    local CPoint = CQueue:Pop()
    if (CPoint == nil) then
        Alarm("PreMotion Point Error!", ErrorMessage.Type.PointErr)
    end
    if (CPoint.Paras ~= nil) and (CPoint.Paras.Mode == MotionType.Part) then
        -- 进入隔板动作前再次同步，保证在隔板不足ACK/报警前已经刷新Modbus数量。
        SyncPartitionRemainBySensor(PalletNumber, true)
    end
    if (CPoint.Paras.ErrIndex > 0) then
        GetPointInfo(PalletNumber, CPoint)
    end
    if (PalletNumber.Partition.Enable == true) then
        PalletNumber.Partition.Mode = CPoint.Paras.Mode
    end
    AdjustLiftingHeight(CPoint.Paras.LH)
    return CPoint
end
---------------------------------------------------------------
--执行运动流程
local function ExecuteMotion(PalletNumber, CQueue)
    while true do
        Wait(Time.Thread.s0)
        if (PalletNumber.State.Done == true or PalletNumber.Pallet ~= Pallet or Pallet == Idle) then
            break
        end
        if (CQueue:IsEmpty() == false) then
            local CPoint = PreMotion(PalletNumber, CQueue)
            while true do
                FilmMotion()
                GetLiftingHeight(CPoint.Paras.LH)
                if (CPoint.Paras.Mode == MotionType.Part)
                    or ((PalletNumber.State.StateReady == true) and (SignalReady == true) and (FilmDone == true)) then
                    LogInfo("%s pallet is working!", (Pallet == Left) and "Left" or "Right")
                    SignalReady = false
                    PTPMotion(PalletNumber, CPoint, CQueue)
                    if (SignalReady == false) then
                        MotionDone = true
                    end
                    if (StateMachine == FSMType.DLR) then
                        return
                    else
                        break
                    end
                end
            end
        end
    end
end
---------------------------------------------------------------
--获取运动状态
local function GetMotionFSM(PalletNumber, CQueue)
    if (PalletNumber.State.Init == true) then
        ExecuteMotion(PalletNumber, CQueue)
        if (SimulateMode == 1) or (AgingMode == 1) then
            if (StateMachine == FSMType.SLR or StateMachine == FSMType.DLR) then
                if FirstPallet.State.Done == true and SecondPallet.State.Done == true then
                    FirstPallet.State.SReset = true
                end
            else
                PalletNumber.State.SReset = true
            end
        end
    end
end
---------------------------------------------------------------
--获取工作状态
local function MotionFSM()
    local SwitchFSM =
    {
        [Idle] = function()
        end,
        [Left] = function()
            GetMotionFSM(FirstPallet, FQueue)
        end,
        [Right] = function()
            GetMotionFSM(SecondPallet, SQueue)
        end
    }

    if (StateMachine ~= FSMType.DLR)
        or (StateMachine == FSMType.DLR and SignalReady == true) then
        local switch_mode = SwitchFSM[Pallet]
        if switch_mode then
            switch_mode()
        else
            Alarm("SwitchFSM is wrong!", ErrorMessage.Type.WorkingDataErr)
        end
    end
end
---------------------------------------------------------------
---------------------------------------------------------------
--主程序
InitStorageMode()
InitModbus()
-- 必须在InitFSM/ACK/隔板不足判断前同步，否则界面和报警逻辑仍可能读取到旧的0。
SyncAllPartitionRemainBySensor(true)
InitFSM()
InitPallet()
while true do
    Wait(Time.Thread.s0)
    MotionFSM()
end

