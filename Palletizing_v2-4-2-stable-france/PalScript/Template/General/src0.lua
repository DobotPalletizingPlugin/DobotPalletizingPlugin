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
--坐标系重定义
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
                    Wait(1000)
                    local DOs = { SuckerCfg.Port.A, SuckerCfg.Port.B, SuckerCfg.Port.C, SuckerCfg.Port.D }
                    for i = 1, BoxNum do
                        VerifySuckerDO(SuckerCfg.Port, DOs[i], ON)
                    end
                else
                    BoxNum = CIndex
                    if (CIndex == 1) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.A, ON)
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.A, ON)
                    elseif (CIndex == 2) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.B, ON)
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.B, ON)
                    elseif (CIndex == 3) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.C, ON)
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.C, ON)
                    elseif (CIndex == 4) then
                        IORes(SuckerCfg.Port.Mode, SuckerCfg.Port.D, ON)
                        Wait(1000)
                        VerifySuckerDO(SuckerCfg.Port, SuckerCfg.Port.D, ON)
                    end
                end
                SuckerSafeIO(OFF)
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle and CPoint.Paras.Sucker == 0) then
                BoxNum = 1
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOn)
            else
                BoxNum = math.ceil(0.5 * CPoint.Paras.Sucker) + 1
                SuckerControll(SuckerCfg.Port, ON, BoxNum)
                Wait(1000)
                local DOs = { SuckerCfg.Port.A, SuckerCfg.Port.B, SuckerCfg.Port.C, SuckerCfg.Port.D }
                for i = 1, BoxNum do
                    VerifySuckerDO(SuckerCfg.Port, DOs[i], ON)
                end
                SuckerSafeIO(OFF)
            end
            Wait(Time.Pick.In)
            CTool = CalcEccTool(PalletNumber, CPoint.Paras.Sucker, BoxNum)
            SetPayload(BoxNum * PalletNumber.BoxProperty.BoxWeight + ToolWeight,
                { CTool[1], CTool[2], 0.5 * (CTool[3] + PalletNumber.BoxProperty.BoxHigh) }) --设置负载指令，加上箱子重量
        end,
        [MotionType.Part] = function()
            if (PartCfg.Enable == true) then
                IORes(PartCfg.Port.Mode, PartCfg.Port.A, ON)
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOn)
            else
                SuckerControll(SuckerCfg.Port, ON, math.abs(PalletSuckerFunction))
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
    SetPayload(Weight, { CTool[1], CTool[2], 0.5 * CTool[3] }) ---设置负载为吸取箱子的负载
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
                        return
                    end
                else
                    SuckerControll(SuckerCfg.Port, OFF, math.abs(PalletSuckerFunction))
                    SuckerSafeIO(ON)
                    if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                        SuckerControll(SuckerCfg.Dete.VacuumBreak, ON, math.abs(PalletSuckerFunction))
                        Wait(Time.Place.In)
                        SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.abs(PalletSuckerFunction))
                        return
                    end
                end
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle and CPoint.Paras.Sucker == 0) then
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOff)
            else
                SuckerControll(SuckerCfg.Port, OFF, math.ceil(0.5 * CPoint.Paras.Sucker) + 1)
                SuckerSafeIO(ON)
                if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, ON, math.ceil(0.5 * CPoint.Paras.Sucker) + 1)
                    Wait(Time.Place.In)
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.ceil(0.5 * CPoint.Paras.Sucker) + 1)
                    return
                end
            end
            Wait(Time.Place.In)
        end,
        [MotionType.Part] = function()
            if (PartCfg.Enable == true) then
                IORes(PartCfg.Port.Mode, PartCfg.Port.A, OFF)
            elseif (PalletSuckerFunction == SuckerCfg.Type.SSingle) then
                TCPWrite(Communication.Sucker.Tcp.Socket, Communication.Sucker.Command.VacuumOff)
            else
                SuckerControll(SuckerCfg.Port, OFF, math.abs(PalletSuckerFunction))
                SuckerSafeIO(ON)
                if (SuckerCfg.Dete.VacuumBreak.Enable == 1) then
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, ON, math.abs(PalletSuckerFunction))
                    Wait(Time.Place.In)
                    SuckerControll(SuckerCfg.Dete.VacuumBreak, OFF, math.abs(PalletSuckerFunction))
                    return
                end
            end
            Wait(Time.Place.In)
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
--过渡点运动
local function TransMotion(CPoint, CDir, Acc, Vel)
    local SD = 1
    local ED = CPoint.Paras.TransNum

    if (CDir == Dir.Backward) then
        SD = CPoint.Paras.TransNum
        ED = 1
    end
    for i = SD, ED, CDir do
        if (type(CPoint.MotionPoint[i]) == "table") then
            if (PalletObstacleFunc == 1) then
                MovL(CPoint.MotionPoint[i], { a = Acc, v = Vel, cp = 100 }) --运动到层过渡点
            else
                if (CDir == Dir.Backward) then
                    local P = DeepCopy(CPoint.MotionPoint[i])
                    local CurrentJoint = GetAngle().joint
                
                    if P.joint ~= nil then
                        P.joint[6] = CurrentJoint[6]
                    end
                
                    MovJ(P, { a = Acc, v = Vel, cp = 100 }) -- backward 回程保持当前 J6
                else
                    MovL(CPoint.MotionPoint[i], { a = Acc, v = Vel, cp = 100 }) -- forward 保持原逻辑
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
---
---standby move from movJ to movL to avoid hit the stock of interlayer
---
--待机位置运动
local function StandyMotion(PalletNumber, CPoint)
    if (PalletNumber.State.StateReady == false) and (LiftingHeight > 1) then
        MovL(CPoint.Paras.Standy, { a = NLDAcc, v = NLDVel, cp = 100 })
        AdjustLiftingHeight(Home)
        SyncMotion(Home)
    elseif (CPoint.Paras.Mode == MotionType.Part) then
        local Standy = { pose = {} }
        Standy.pose = DeepCopy(CPoint.Paras.Standy.pose)
        Standy.pose[3] = Standy.pose[3] - CPoint.Paras.LH
        MovL(Standy, { a = NLDAcc, v = NLDVel, cp = 100 })
    else
        local CurrentJoint = GetAngle().joint
        MovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = NLDVel, cp = 100 })
    end
end
---------------------------------------------------------------
--更新隔板数据
local function UpdatePartData(PalletNumber, CPoint)
    if (CPoint.Paras.Mode == MotionType.Part) then
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
        if (PalletNumber.Mode == WorkType.Pallet) then
            PalletNumber.Partition.RePartNum = PalletNumber.Partition.RePartNum - 1
        else
            PalletNumber.Partition.RePartNum = PalletNumber.Partition.RePartNum + 1
        end
        WritePartNum(PalletNumber)
    end
end
---------------------------------------------------------------
--MotionPoint[index]:
--1~5:过渡点（示教），6:取料（示教），7：取料上方点（自动生成），8~11：放置点（自动生成）
--12~15：放料上方点（自动生成），16~19：放料偏移点（自动生成）
---------------------------------------------------------------
--执行点位运动

local function PTPMotion(PalletNumber, CPoint)
    local CPose = { pose = {} }

    ----------------------------------------------------------------
    -- 隔板取料慢速抬升参数
    ----------------------------------------------------------------
    -- PartSlowLiftHeight:
    --   隔板吸取后先慢速垂直抬升的高度，单位 mm。
    --   目的：避免刚吸起隔板时，把相邻隔板一起带起来。
    local PartSlowLiftHeight = 20
    local PartSlowLiftAcc = 5
    local PartSlowLiftVel = 5

    ----------------------------------------------------------------
    -- 双吸单放 / 多吸单放：放完一个箱子后的额外抬升高度
    ----------------------------------------------------------------
    -- DepositLiftHeight:
    --   当 i < CPoint.Paras.Times 时，说明当前箱子不是最后一个箱子，
    --   机器人上还带着后续箱子。
    --
    --   放完当前箱子后，先回到当前放置上方点，
    --   再从当前位置沿当前用户坐标系 Z 方向额外抬高 250 mm。
    --
    --   目的：
    --     避免机器人横向移动到下一个箱子放置点时，
    --     夹具或剩余箱子刮碰已经放好的箱子。
    local DepositLiftHeight = 250

    if (PalletNumber.Mode == WorkType.Pallet) then
        ----------------------------------------------------------------
        -- WorkType.Pallet:
        --   当前流程是码垛流程：
        --   从输送线 / 取料点抓箱子，然后放到托盘上。
        ----------------------------------------------------------------

        Wait(Time.Pick.Pre)

        if (CPoint.Paras.Mode == MotionType.Part) then
            ----------------------------------------------------------------
            -- MotionType.Part:
            --   当前 CPoint 是隔板动作，不是普通箱子动作。
            --
            -- 点位说明：
            --   MotionPoint[7]：隔板取料上方点 / standby 上方点
            --   CPartPick：实际隔板取料点，根据剩余隔板数量动态计算高度
            --
            -- 速度说明：
            --   到隔板取料上方点：NLDAcc / SyncMotionVel
            --     因为此时未吸隔板，属于空载或同步升降运动。
            --
            --   下去取隔板：NLDAcc / NLDVel
            --     因为还未吸到隔板，仍然为空载。
            --
            --   吸到隔板后慢速抬升：PartSlowLiftAcc / PartSlowLiftVel
            --     目的是避免带起相邻隔板。
            --
            --   吸到隔板后回上方点：LDAcc / LDVel
            --     因为此时已经带着隔板，按带料速度运行。
            ----------------------------------------------------------------

            local CPartPick = DeepCopy(PartPick)
            CPartPick.pose[3] = CPartPick.pose[3] - CPoint.Paras.LH +
                PalletNumber.ProcessNum.PartitionHeight * PalletNumber.Partition.RePartNum

            MovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = SyncMotionVel, cp = 100 })
            SyncMotion(CPoint.Paras.LH)

            MovL(CPartPick, { a = NLDAcc, v = NLDVel, cp = 100 })
            OpenSucker(PalletNumber, CPoint)

            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end

            local CPartPickLift = DeepCopy(CPartPick)
            CPartPickLift.pose[3] = CPartPickLift.pose[3] + PartSlowLiftHeight
            MovL(CPartPickLift, { a = PartSlowLiftAcc, v = PartSlowLiftVel, cp = 0 })

            MovL(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 })

        else
            ----------------------------------------------------------------
            -- MotionType.Norm:
            --   当前 CPoint 是普通箱子动作。
            --
            -- 点位说明：
            --   MotionPoint[6]：箱子取料点
            --   MotionPoint[7]：箱子取料上方点
            --
            -- if 条件说明：
            --   SingleMotion == false:
            --     当前循环第一次进入取料侧，需要先移动到取料上方点。
            --
            --   SyncSignal == true:
            --     升降柱高度发生变化，需要同步等待升降柱动作。
            --
            --   StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet:
            --     双输送线双托盘模式下，当前托盘和上一次托盘不同，
            --     说明左右托盘切换了，需要重新移动到当前托盘对应的取料上方点。
            --
            -- 速度说明：
            --   到取料上方点：NLDAcc / SyncMotionVel
            --     因为此时还没有抓箱子，同时可能要配合升降柱。
            --
            --   下去取箱子：NLDAcc / NLDVel
            --     因为下去之前还是空载。
            --
            --   抓箱后回取料上方点：LDAcc / LDVel
            --     因为此时已经带着箱子。
            ----------------------------------------------------------------

            if ((SingleMotion == false) or (SyncSignal == true)
                    or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet)) then
                SingleMotion = true
                MovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = SyncMotionVel, cp = 100 })
                SyncMotion(CPoint.Paras.LH)
            end

            MovL(CPoint.MotionPoint[6], { a = NLDAcc, v = NLDVel, cp = 100 })
            OpenSucker(PalletNumber, CPoint)

            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end

            MovL(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 })
        end

        Wait(Time.Pick.Post)

        ----------------------------------------------------------------
        -- TransMotion Forward:
        --   从取料侧移动到放料侧的过渡点运动。
        --
        -- 点位说明：
        --   MotionPoint[1] ~ MotionPoint[5]：
        --     用户示教的过渡点。
        --
        -- 方向说明：
        --   Dir.Forward:
        --     从取料侧到放料侧，按照 1 -> 5 顺序走过渡点。
        --
        -- 速度说明：
        --   此时机器人已经抓到箱子 / 隔板，
        --   所以使用 LDAcc / LDVel。
        ----------------------------------------------------------------
        TransMotion(CPoint, Dir.Forward, LDAcc, LDVel)

        for i = 1, CPoint.Paras.Times do
            ----------------------------------------------------------------
            -- CPoint.Paras.Times:
            --   本次动作需要放置的次数。
            --
            -- 例如：
            --   单吸单放：Times = 1
            --   双吸单放：Times = 2
            --   三吸单放：Times = 3
            --
            -- i:
            --   当前正在放第几个箱子。
            ----------------------------------------------------------------

            if CPoint.Paras.OffSet[i] == 1 then
                ----------------------------------------------------------------
                -- OffSet[i] == 1:
                --   当前第 i 个箱子需要使用放置 offset 过渡点。
                --
                -- 点位说明：
                --   MotionPoint[15 + i]：
                --     第 i 个箱子的放置 offset 过渡点。
                --     例如：
                --       i = 1 -> MotionPoint[16]
                --       i = 2 -> MotionPoint[17]
                --       i = 3 -> MotionPoint[18]
                --       i = 4 -> MotionPoint[19]
                --
                --   MotionPoint[11 + i]：
                --     第 i 个箱子的放置上方点。
                --     例如：
                --       i = 1 -> MotionPoint[12]
                --       i = 2 -> MotionPoint[13]
                --       i = 3 -> MotionPoint[14]
                --       i = 4 -> MotionPoint[15]
                --
                -- 速度说明：
                --   到 offset 过渡点：LDAcc / LDVel
                --     因为此时机器人还带着箱子。
                --
                --   从 offset 过渡点到放置上方点：PlaceAcc / PlaceSpeed
                --     因为已经接近码垛放置区域，需要使用放置速度。
                ----------------------------------------------------------------

                MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 })
                MovL(CPoint.MotionPoint[11 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 100 })

            else
                ----------------------------------------------------------------
                -- OffSet[i] ~= 1:
                --   当前第 i 个箱子不需要 offset 过渡点，
                --   直接移动到第 i 个箱子的放置上方点。
                --
                -- 点位说明：
                --   MotionPoint[11 + i]：
                --     第 i 个箱子的放置上方点。
                --
                -- 速度说明：
                --   此时机器人仍然带着箱子，
                --   所以使用 LDAcc / LDVel。
                ----------------------------------------------------------------

                MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })
            end

            ----------------------------------------------------------------
            -- 下放到实际放置点
            --
            -- 点位说明：
            --   MotionPoint[7 + i]：
            --     第 i 个箱子的实际放置点。
            --     例如：
            --       i = 1 -> MotionPoint[8]
            --       i = 2 -> MotionPoint[9]
            --       i = 3 -> MotionPoint[10]
            --       i = 4 -> MotionPoint[11]
            --
            -- 速度说明：
            --   放置动作使用 PlaceAcc / PlaceSpeed。
            ----------------------------------------------------------------
            MovL(CPoint.MotionPoint[7 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 100 })

            ----------------------------------------------------------------
            -- 放下当前第 i 个箱子
            --
            -- 对于双吸单放：
            --   i = 1 时，只关闭第一个吸盘，机器人上还带着第二个箱子。
            --   i = 2 时，关闭第二个吸盘，机器人空载。
            --
            -- CloseSucker 内部会根据 i 控制对应吸盘。
            ----------------------------------------------------------------
            CloseSucker(PalletNumber, CPoint, i)

            if SimulateMode == 1 then
                UpdatePlaceBoxState(PalletNumber, CPoint)
            end

            UpdateData(PalletNumber, CPoint)

            if i < CPoint.Paras.Times then
                ----------------------------------------------------------------
                -- i < CPoint.Paras.Times:
                --   当前箱子不是最后一个箱子。
                --
                -- 具体含义：
                --   机器人刚放完第 i 个箱子，
                --   但是后面还有第 i+1 个箱子没有放。
                --
                -- 例如双吸单放：
                --   Times = 2
                --   i = 1 时满足 i < Times
                --   说明第一个箱子已经放下，
                --   但机器人仍然带着第二个箱子。
                --
                -- 速度原则：
                --   只要机器人上还带着箱子，
                --   后续返回、抬升、offset 运动都必须使用 LDAcc / LDVel。
                ----------------------------------------------------------------

                ----------------------------------------------------------------
                -- 第一步：从实际放置点回到当前箱子的放置上方点
                --
                -- 点位说明：
                --   MotionPoint[11 + i]：
                --     当前第 i 个箱子的放置上方点。
                --
                -- 速度说明：
                --   机器人仍然带着后续箱子，
                --   所以使用 LDAcc / LDVel。
                ----------------------------------------------------------------
                MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })

                ----------------------------------------------------------------
                -- 第二步：基于当前位置额外抬高 250 mm
                --
                -- 逻辑说明：
                --   先读取当前关节角 GetAngle().joint；
                --   再用 PositiveKin 转换成当前 TCP 位姿；
                --   然后把 pose[3]，也就是 Z 高度，加上 DepositLiftHeight；
                --   最后用 InverseKin 转回关节点，并用 MovL 直线运动过去。
                --
                -- 坐标系说明：
                --   这里使用 PalletNumber.Coordinate.UserNum，
                --   也就是当前托盘用户坐标系。
                --
                -- 目的：
                --   放完第 i 个箱子后，机器人还带着第 i+1 个箱子。
                --   直接横移到下一个放置点可能刮碰已经放好的箱子。
                --   所以先抬高 250 mm，再进入后续路径。
                --
                -- 速度说明：
                --   仍然带箱，所以使用 LDAcc / LDVel。
                ----------------------------------------------------------------
                local currentJoint = { joint = GetAngle().joint }

                local liftPoint = PositiveKin(currentJoint,
                    { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })

                liftPoint.pose[3] = liftPoint.pose[3] + DepositLiftHeight

                local errId, liftJointPoint = InverseKin(liftPoint,
                    { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })

                if (errId ~= 0) or (liftJointPoint == nil) then
                    Alarm("InverseKin for deposit lift failed!", ErrorMessage.Type.PointErr)
                end

                MovL(liftJointPoint, { a = LDAcc, v = LDVel, cp = 0 })

                if CPoint.Paras.OffSet[i] == 1 then
                    ----------------------------------------------------------------
                    -- 如果当前第 i 个箱子使用了 offset 过渡点，
                    -- 那么抬高后再返回当前箱子的 offset 过渡点。
                    --
                    -- 点位说明：
                    --   MotionPoint[15 + i]：
                    --     当前第 i 个箱子的放置 offset 过渡点。
                    --
                    -- 速度说明：
                    --   虽然第 i 个箱子已经放下，
                    --   但机器人还带着第 i+1 个箱子，
                    --   所以这里仍然使用 LDAcc / LDVel。
                    ----------------------------------------------------------------
                    MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 })
                end

            else
                ----------------------------------------------------------------
                -- i >= CPoint.Paras.Times:
                --   当前箱子是最后一个箱子。
                --
                -- 具体含义：
                --   当前第 i 个箱子放完以后，
                --   本次抓取到的所有箱子都已经放完，
                --   机器人已经空载。
                --
                -- 速度原则：
                --   机器人空载后，返回路径使用 NLDAcc / NLDVel。
                ----------------------------------------------------------------

                ----------------------------------------------------------------
                -- 从最后一个箱子的实际放置点回到放置上方点
                --
                -- 点位说明：
                --   MotionPoint[11 + i]：
                --     最后一个箱子的放置上方点。
                --
                -- 速度说明：
                --   已经空载，所以使用 NLDAcc / NLDVel。
                ----------------------------------------------------------------
                MovL(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })

                if CPoint.Paras.OffSet[i] == 1 then
                    ----------------------------------------------------------------
                    -- 最后一个箱子如果使用了 offset 过渡点，
                    -- 返回 offset 过渡点时机器人已经空载。
                    --
                    -- 点位说明：
                    --   MotionPoint[15 + i]：
                    --     最后一个箱子的放置 offset 过渡点。
                    --
                    -- 速度说明：
                    --   已经空载，所以使用 NLDAcc / NLDVel。
                    ----------------------------------------------------------------
                    MovL(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
                end
            end
        end

        ----------------------------------------------------------------
        -- TransMotion Backward:
        --   从放料侧返回取料侧的过渡点运动。
        --
        -- 点位说明：
        --   MotionPoint[1] ~ MotionPoint[5]：
        --     用户示教的过渡点。
        --
        -- 方向说明：
        --   Dir.Backward:
        --     从放料侧返回取料侧，按照 5 -> 1 顺序走过渡点。
        --
        -- 速度说明：
        --   正常情况下箱子已经全部放完，
        --   所以使用 NLDAcc / NLDVel。
        ----------------------------------------------------------------
        TransMotion(CPoint, Dir.Backward, NLDAcc, NLDVel)

        CPose = GetPose()
        StandyMotion(PalletNumber, CPoint)

    else
        ----------------------------------------------------------------
        -- 非 WorkType.Pallet:
        --   这里是拆垛 / 反向流程。
        --   原逻辑基本保持不变。
        ----------------------------------------------------------------

        if (SingleMotion == false) or (SyncSignal == true)
            or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet) then

            if SingleMotion == false then
                SingleMotion = true
            else
                local Standy = { pose = {} }
                Standy.pose = DeepCopy(CPoint.Paras.Standy.pose)
                Standy.pose[3] = Standy.pose[3] - CPoint.Paras.LH
                MovJ(Standy, { a = NLDAcc, v = SyncMotionVel, cp = 100 })
            end

            SyncMotion(CPoint.Paras.LH)
        end

        TransMotion(CPoint, Dir.Forward, NLDAcc, NLDVel)

        for i = CPoint.Paras.Times, 1, -1 do
            if (CPoint.Paras.OffSet[i] == 1) then
                MovJ(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
            end

            MovJ(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
            MovL(CPoint.MotionPoint[7 + i], { a = NLDAcc, v = NLDVel, cp = 100 })

            OpenSucker(PalletNumber, CPoint, i)

            if SimulateMode == 1 then
                UpdatePickBoxState(PalletNumber, CPoint)
            end

            UpdateData(PalletNumber, CPoint)

            MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })

            if (CPoint.Paras.OffSet[i] == 1) then
                MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 })
            end
        end

        TransMotion(CPoint, Dir.Backward, LDAcc, LDVel)

        CPose = GetPose()
        MovJ(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 })

        if (CPoint.Paras.Mode == MotionType.Part) then
            local CPartPick = DeepCopy(PartPick)
            CPartPick.pose[3] = CPartPick.pose[3] - CPoint.Paras.LH +
                PalletNumber.ProcessNum.PartitionHeight * PalletNumber.Partition.RePartNum

            MovL(CPartPick, { a = NLDAcc, v = NLDVel, cp = 100 })
        else
            MovL(CPoint.MotionPoint[6], { a = LDAcc, v = LDVel, cp = 100 })
        end

        CloseSucker(PalletNumber, CPoint)

        if SimulateMode == 1 then
            UpdatePlaceBoxState(PalletNumber, CPoint)
        end

        if (CPoint.Paras.Mode == MotionType.Part) then
            MovJ(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 })
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
                    PTPMotion(PalletNumber, CPoint)
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
InitFSM()
InitPallet()
while true do
    Wait(Time.Thread.s0)
    MotionFSM()
end




-- local function PTPMotion(PalletNumber, CPoint)
--     local CPose = { pose = {} }
--     -- 仅用于隔板功能的慢抬升参数
--     local PartSlowLiftHeight = 20
--     local PartSlowLiftAcc = 5
--     local PartSlowLiftVel = 5

--     if (PalletNumber.Mode == WorkType.Pallet) then
--         Wait(Time.Pick.Pre)
--         if (CPoint.Paras.Mode == MotionType.Part) then
--             local CPartPick = DeepCopy(PartPick)
--             CPartPick.pose[3] = CPartPick.pose[3] - CPoint.Paras.LH +
--                 PalletNumber.ProcessNum.PartitionHeight * PalletNumber.Partition.RePartNum
--             MovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = SyncMotionVel, cp = 100 })
--             SyncMotion(CPoint.Paras.LH)
--             MovL(CPartPick, { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到抓取点
--             OpenSucker(PalletNumber, CPoint)
--             if SimulateMode == 1 then
--                 UpdatePickBoxState(PalletNumber, CPoint)
--             end

--             -- 取到隔板后：先慢速抬升 12 mm，再恢复原来的速度回上方点
--             local CPartPickLift = DeepCopy(CPartPick)
--             CPartPickLift.pose[3] = CPartPickLift.pose[3] + PartSlowLiftHeight
--             MovL(CPartPickLift, { a = PartSlowLiftAcc, v = PartSlowLiftVel, cp = 0 })

            
--             RelMovJUser({0, 0, PartSlowLiftHeight, 0, 0, 0}, {user =  PalletNumber.Coordinate.PartitionUserNum, tool = PalletNumber.Coordinate.ToolNum , a = PartSlowLiftAcc, v = PartSlowLiftVel})



--             -- local currentJoint = { joint = GetAngle().joint }

--             -- local liftPoint = PositiveKin(currentJoint,
--             --     { user = PalletNumber.Coordinate.PartitionUserNum, tool = PalletNumber.Coordinate.ToolNum })
        
--             -- liftPoint.pose[3] = liftPoint.pose[3] + PartSlowLiftHeight
        
--             -- local errId, liftJointPoint = InverseKin(liftPoint,
--             --     { user = PalletNumber.Coordinate.PartitionUserNum, tool = PalletNumber.Coordinate.ToolNum })
        
--             -- if (errId ~= 0) or (liftJointPoint == nil) then
--             --     Alarm("InverseKin for partition lift failed!", ErrorMessage.Type.PointErr)
--             -- end
        
--             -- MovL(liftJointPoint, { a = PartSlowLiftAcc, v = PartSlowLiftVel, cp = 0 })
--             -- MovL(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 }) --运动到抓取点上方

--         else
--             if ((SingleMotion == false) or (SyncSignal == true)
--                     or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet)) then
--                 SingleMotion = true
--                 MovJ(CPoint.MotionPoint[7], { a = NLDAcc, v = SyncMotionVel, cp = 100 })
--                 SyncMotion(CPoint.Paras.LH)
--             end
--             MovL(CPoint.MotionPoint[6], { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到抓取点
--             OpenSucker(PalletNumber, CPoint)
--             if SimulateMode == 1 then
--                 UpdatePickBoxState(PalletNumber, CPoint)
--             end
--             MovL(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 }) --运动到抓取点上方
--         end
--         Wait(Time.Pick.Post)
--         TransMotion(CPoint, Dir.Forward, LDAcc, LDVel)
--         for i = 1, CPoint.Paras.Times do
--             if CPoint.Paras.OffSet[i] == 1 then
--                 MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 })         --运动到放置过渡点
--                 MovL(CPoint.MotionPoint[11 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 100 }) --运动到放置点正上方
--             else
--                 MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })         --运动到放置点正上方
--             end
--             MovL(CPoint.MotionPoint[7 + i], { a = PlaceAcc, v = PlaceSpeed, cp = 100 })
--             CloseSucker(PalletNumber, CPoint, i)
--             if SimulateMode == 1 then
--                 UpdatePlaceBoxState(PalletNumber, CPoint)
--             end
--             -- if (CPoint.Paras.Mode == MotionType.Part) then
--             --     -- 放下隔板后：基于当前位置慢速抬升 12 mm，再恢复原来的返回逻辑
--             --     local liftPoint = GetPose()
--             --     liftPoint.pose[3] = liftPoint.pose[3] + PartSlowLiftHeight
--             --     MovL(liftPoint, { a = PartSlowLiftAcc, v = PartSlowLiftVel, cp = 0 })
--             -- end

--             -- 以下返回逻辑保持原版风格，不改普通功能
--             -- UpdateData(PalletNumber, CPoint)
--             -- if (CPoint.Paras.Times ~= 1) then
--             --     MovL(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })     --运动到放置点正上方
--             --     if CPoint.Paras.OffSet[i] == 1 then
--             --         MovL(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到放置过渡点
--             --     end
--             -- else
--             --     MovL(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到放置点正上方
--             -- end

--             UpdateData(PalletNumber, CPoint)

--             MovL(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })

--             local DepositLiftHeight = 250

--             if i < CPoint.Paras.Times then
--                 -- 还有下一个 box
--                 -- 在当前 arrival point 基础上再抬高 80 mm

--                 local currentJoint = { joint = GetAngle().joint }

--                 local liftPoint = PositiveKin(currentJoint,
--                     { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })

--                 liftPoint.pose[3] = liftPoint.pose[3] + DepositLiftHeight

--                 local errId, liftJointPoint = InverseKin(liftPoint,
--                     { user = PalletNumber.Coordinate.UserNum, tool = PalletNumber.Coordinate.ToolNum })

--                 if (errId ~= 0) or (liftJointPoint == nil) then
--                     Alarm("InverseKin for deposit lift failed!", ErrorMessage.Type.PointErr)
--                 end

--                 MovL(liftJointPoint, { a = NLDAcc, v = NLDVel, cp = 0 })
--             end

--             if CPoint.Paras.OffSet[i] == 1 then
--                 MovL(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
--             end

--             -- local DepositLiftHeight = 80 -- 第一个盒子放完后额外抬升高度 mm

--             -- if i < CPoint.Paras.Times then
--             --     -- 不是最后一个 box，说明后面还有第 2 / 第 3 个 box
--             --     -- 放完当前 box 后，先抬高，避免移动到下一个 box 时刮到其它箱子

--             --     local LiftPoint = DeepCopy(CPoint.MotionPoint[11 + i])
--             --     LiftPoint.pose[3] = LiftPoint.pose[3] + DepositLiftHeight
--             --     MovL(LiftPoint, { a = NLDAcc, v = NLDVel, cp = 100 })

--             --     if CPoint.Paras.OffSet[i] == 1 then
--             --         local OffsetLiftPoint = DeepCopy(CPoint.MotionPoint[15 + i])
--             --         OffsetLiftPoint.pose[3] = OffsetLiftPoint.pose[3] + DepositLiftHeight
--             --         MovL(OffsetLiftPoint, { a = NLDAcc, v = NLDVel, cp = 100 })
--             --     end
--             -- else
--             --     -- 最后一个 box，保持原来的返回逻辑即可
--             --     MovL(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })

--             --     if CPoint.Paras.OffSet[i] == 1 then
--             --         MovL(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
--             --     end
--             -- end
--         end
--         TransMotion(CPoint, Dir.Backward, NLDAcc, NLDVel)
--         CPose = GetPose()
--         StandyMotion(PalletNumber, CPoint)
--     else
--         if (SingleMotion == false) or (SyncSignal == true)
--             or (StateMachine == FSMType.DLR and PalletNumber.Pallet ~= PrePallet) then
--             if SingleMotion == false then
--                 SingleMotion = true
--             else
--                 local Standy = { pose = {} }
--                 Standy.pose = DeepCopy(CPoint.Paras.Standy.pose)
--                 Standy.pose[3] = Standy.pose[3] - CPoint.Paras.LH
--                 MovJ(Standy, { a = NLDAcc, v = SyncMotionVel, cp = 100 })
--             end
--             SyncMotion(CPoint.Paras.LH)
--         end
--         TransMotion(CPoint, Dir.Forward, NLDAcc, NLDVel)
--         for i = CPoint.Paras.Times, 1, -1 do
--             if (CPoint.Paras.OffSet[i] == 1) then
--                 MovJ(CPoint.MotionPoint[15 + i], { a = NLDAcc, v = NLDVel, cp = 100 }) --运动到放置过渡点
--             end
--             MovJ(CPoint.MotionPoint[11 + i], { a = NLDAcc, v = NLDVel, cp = 100 })     --运动到放置点正上方
--             MovL(CPoint.MotionPoint[7 + i], { a = NLDAcc, v = NLDVel, cp = 100 })
--             OpenSucker(PalletNumber, CPoint, i)
--             if SimulateMode == 1 then
--                 UpdatePickBoxState(PalletNumber, CPoint)
--             end
--             UpdateData(PalletNumber, CPoint)
--             MovL(CPoint.MotionPoint[11 + i], { a = LDAcc, v = LDVel, cp = 100 })     --运动到放置点正上方
--             if (CPoint.Paras.OffSet[i] == 1) then
--                 MovL(CPoint.MotionPoint[15 + i], { a = LDAcc, v = LDVel, cp = 100 }) --运动到放置过渡点
--             end
--         end
--         TransMotion(CPoint, Dir.Backward, LDAcc, LDVel)
--         CPose = GetPose()
--         MovJ(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 })
--         if (CPoint.Paras.Mode == MotionType.Part) then
--             local CPartPick = DeepCopy(PartPick)
--             CPartPick.pose[3] = CPartPick.pose[3] - CPoint.Paras.LH +
--                 PalletNumber.ProcessNum.PartitionHeight * PalletNumber.Partition.RePartNum
--             MovL(CPartPick, { a = NLDAcc, v = NLDVel, cp = 100 })           --运动到抓取点
--         else
--             MovL(CPoint.MotionPoint[6], { a = LDAcc, v = LDVel, cp = 100 }) --运动到抓取点
--         end
--         CloseSucker(PalletNumber, CPoint)
--         if SimulateMode == 1 then
--             UpdatePlaceBoxState(PalletNumber, CPoint)
--         end
--         if (CPoint.Paras.Mode == MotionType.Part) then
--             MovJ(CPoint.MotionPoint[7], { a = LDAcc, v = LDVel, cp = 100 })
--         end
--         StandyMotion(PalletNumber, CPoint)
--     end
--     UpdatePartData(PalletNumber, CPoint)
--     PrePallet = PalletNumber.Pallet
--     PrePoseHeight = CPose.pose[3] + CPoint.Paras.LH
-- end
