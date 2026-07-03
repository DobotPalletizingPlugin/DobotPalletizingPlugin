-- Version: Lua 5.4.0
-- 此线程为主线程，可调用任何指令
----------------------------------------------------------------
----------------------------------------------------------------
--常量
LayerSheetNum = 0       --隔板计数
BoxHigh = 0             --料箱高度
PrePallet = 0           --缠膜栈板号
PrePoseHeight = 0       --缠膜高度
LastHeight = 0          --前一次升降柱高度
ExAxisLiftingHeight = 0 --升降轴抬升高度后的位置(相对于0位置)。升降轴根据箱体的位置移动的高度
ExAxisMaxDistance = 0   --升降柱参数，处于0位置时对应的机器人末端TCP最远距离
LastDestPose = { pose = { 0, 0, 0, 0, 0, 0 } }
LiftingPoint = { joint = { 90, 0, 90, 0, -90, 0 } }
PartCoordinateFlag = 0 --隔板坐标系点位标志位
StandyPoint = {}       --待机点位
local LDVel = MotionParas.Forward.Pick.NormVel
local NLDVel = MotionParas.Backward.Pick.NormVel
local LDPlaceVel = MotionParas.Forward.Place.NormVel
--------------------------------------------------------------
--------------------------------------------------------------
--获取全局用户坐标和工具坐标
if MultPalletFunction == true then
    local CTool = {}
    FirstPallet.Layer = GetLayerCnt(PalletName, 0)
    FirstPallet.Coordinate.UserNum = GetPalletUser(PalletName, 0)
    CTool = GetPalletTool(PalletName, 0)
    FirstPallet.Coordinate.ToolNum = CTool[1]
    FirstPallet.BoxProperty.BoxWeight = GetBoxLoad(PalletName, 0)
    SecondPallet.Layer = GetLayerCnt(PalletName, 1)
    SecondPallet.Coordinate.UserNum = GetPalletUser(PalletName, 1)
    CTool = GetPalletTool(PalletName, 0)
    SecondPallet.Coordinate.ToolNum = CTool[1]
    SecondPallet.BoxProperty.BoxWeight = GetBoxLoad(PalletName, 1)
    local FirstPalletUser = CalcUser(FirstPallet.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
    FirstPalletUser[3] = FirstPalletUser[3] + FirstPallet.ProcessNum.PalletHeight
    SetUser(FirstPallet.Coordinate.UserNum, FirstPalletUser)

    local SecondPalletUser = CalcUser(SecondPallet.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
    SecondPalletUser[3] = SecondPalletUser[3] + SecondPallet.ProcessNum.PalletHeight
    SetUser(SecondPallet.Coordinate.UserNum, SecondPalletUser)
    if FirstPallet.BoxProperty.BoxHigh > SecondPallet.BoxProperty.BoxHigh then
        BoxHigh = FirstPallet.BoxProperty.BoxHigh
    else
        BoxHigh = SecondPallet.BoxProperty.BoxHigh
    end
    HomePointPose = PositiveKin(HomePoint,
        { user = FirstPallet.Coordinate.UserNum, tool = FirstPallet.Coordinate.ToolNum })
else
    if Pallet == 0 then
        FirstPallet.Layer = GetLayerCnt(PalletName, 0)
        FirstPallet.Coordinate.UserNum = GetPalletUser(PalletName, 0)
        local CTool = GetPalletTool(PalletName, 0)
        FirstPallet.Coordinate.ToolNum = CTool[1]
        FirstPallet.BoxProperty.BoxWeight = GetBoxLoad(PalletName, 0)
        local FirstPalletUser = CalcUser(FirstPallet.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
        FirstPalletUser[3] = FirstPalletUser[3] + FirstPallet.ProcessNum.PalletHeight
        SetUser(FirstPallet.Coordinate.UserNum, FirstPalletUser)
        BoxHigh = FirstPallet.BoxProperty.BoxHigh
        HomePointPose = PositiveKin(HomePoint,
            { user = FirstPallet.Coordinate.UserNum, tool = FirstPallet.Coordinate.ToolNum })
    else
        SecondPallet.Layer = GetLayerCnt(PalletName, 1)
        SecondPallet.Coordinate.UserNum = GetPalletUser(PalletName, 1)
        local CTool = GetPalletTool(PalletName, 0)
        SecondPallet.Coordinate.ToolNum = CTool[1]
        SecondPallet.BoxProperty.BoxWeight = GetBoxLoad(PalletName, 1)
        local SecondPalletUser = CalcUser(SecondPallet.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
        SecondPalletUser[3] = SecondPalletUser[3] + SecondPallet.ProcessNum.PalletHeight
        SetUser(SecondPallet.Coordinate.UserNum, SecondPalletUser)
        BoxHigh = SecondPallet.BoxProperty.BoxHigh
        HomePointPose = PositiveKin(HomePoint,
            { user = SecondPallet.Coordinate.UserNum, tool = SecondPallet.Coordinate.ToolNum })
    end
end

if HighLoadFunc == true then
    LiftingPoint = DeepCopy(LiftingSafetyPoint_HL)
else
    LiftingPoint = DeepCopy(LiftingSafetyPoint)
end
-----------------------------------------------------------------------------------
--点位类型转换
function PalletGetPose(PalletNumber, PalletPoint, PalletType)
    local ErrorID = 0
    local JointFlag = 0
    local CurrentPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    local CurrentJoint = { joint = {} }
    CurrentPose.pose = DeepCopy(PalletPoint.pose)
    CurrentJoint.joint = DeepCopy(PalletPoint.joint)
    JointFlag = CheckTableData(CurrentJoint.joint)
    if (PalletType == 2) then
        PalletUserNum = PalletNumber.Coordinate.LayerSheetUserNum
    else
        PalletUserNum = PalletNumber.Coordinate.UserNum
    end
    PalletToolNum = PalletNumber.Coordinate.ToolNum
    if (PalletType == 0) or (PalletType == 2) then
        if JointFlag > 0 then
            CurrentPose = PositiveKin(CurrentJoint,
                {
                    user = PalletUserNum,
                    tool = PalletToolNum
                })
        else
            CurrentPose.pose[3] = CurrentPose.pose[3] - PalletNumber.ProcessNum.PalletHeight
        end

        return CurrentPose
    elseif (PalletType == 1) then
        local CNear = { joint = {} }
        if PalletNumber.NearFlag == true then
            CNear = DeepCopy(PalletNumber.Near)
        else
            CNear = GetAngle()
        end
        if JointFlag <= 0 then
            ErrorID, CurrentJoint = InverseKin(CurrentPose,
                {
                    jointNear = CNear,
                    useJointNear = true,
                    user = PalletUserNum,
                    tool = PalletToolNum
                })
            if (ErrorID ~= 0)
                or ((CurrentJoint.joint[3] < Joint3Angle) and (CurrentJoint.joint[3] > -Joint3Angle)) then
                ErrorMessage.Code = 2
                Alarm("放置/抓取点位不可达！")
                print("DestPose", CurrentPose)
                Pause()
            end
        end

        if CNear.joint[6] * CurrentJoint.joint[6] > 0 then
            if CurrentJoint.joint[6] > 270 then
                CurrentJoint.joint[6] = CurrentJoint.joint[6] - 360
            end
            if CurrentJoint.joint[6] < -270 then
                CurrentJoint.joint[6] = CurrentJoint.joint[6] + 360
            end
        end
        if CurrentJoint.joint[4] > 90 then
            CurrentJoint.joint[4] = CurrentJoint.joint[4] - 360
        elseif CurrentJoint.joint[4] < -270 then
            CurrentJoint.joint[4] = CurrentJoint.joint[4] + 360
        end
        if CurrentJoint.joint[1] < -90 then
            CurrentJoint.joint[1] = CurrentJoint.joint[1] + 360
        elseif CurrentJoint.joint[1] > 270 then
            CurrentJoint.joint[1] = CurrentJoint.joint[1] - 360
        end
        return CurrentJoint
    end
end
--------------------------------------------------------------
--获取点位
FirstPickPose = PalletGetPose(FirstPallet, FirstPallet.TeachPoint.TeachPickPoint, 0)
PartPickPoseFP = PalletGetPose(FirstPallet, FirstPallet.TeachPoint.TeachLayerSheetPickPoint, 2)
PartPlacePoseFP = PalletGetPose(FirstPallet, FirstPallet.TeachPoint.TeachLayerSheetPlacePoint, 0)
PickPoseFP =
{
    pose = { 0, 0, 0, 0, 0, 0 }
}
BoxPoseFP =
{
    pose = { 0, 0, 0, 0, 0, 0 }
}

--------------------------------------------------------------
SecondPickPose = PalletGetPose(SecondPallet, SecondPallet.TeachPoint.TeachPickPoint, 0)
PartPickPoseSP = PalletGetPose(SecondPallet, SecondPallet.TeachPoint.TeachLayerSheetPickPoint, 2)
PartPlacePoseSP = PalletGetPose(SecondPallet, SecondPallet.TeachPoint.TeachLayerSheetPlacePoint, 0)
PickPoseSP =
{
    pose = { 0, 0, 0, 0, 0, 0 }
}
BoxPoseSP =
{
    pose = { 0, 0, 0, 0, 0, 0 }
}

---------------------------------------------------------------
---------------------------------------------------------------
--将收到的目标字符串szFullString，进行szSeparator形式进行分割处理后以数组的形式存在nSplitArray数组里
local function Split(szFullString, szSeparator)
    local nFindStartIndex = 1
    local nSplitIndex = 1
    local nSplitArray = {}
    while true do
        if Communication.Lifting.StopLiftingFlag == true then
            break
        end
        local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)
        if not nFindLastIndex then
            nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))
            break
        end
        nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)
        nFindStartIndex = nFindLastIndex + string.len(szSeparator)
        nSplitIndex = nSplitIndex + 1
    end
    return nSplitArray
end

-----------------------------------------------------------------
--与升降轴建立通讯
local function CreateCommConnection()
    local Err = 0
    local CurrentHeight
    local SwitchCommMode =
    {
        [0] = function()
            ExAxisMaxDistance = Communication.Lifting.Brand.EWELLIX.MaxDistance
            Err, Communication.Lifting.Brand.EWELLIX.Tcp.Socket = TCPCreate(false,
                Communication.Lifting.Brand.EWELLIX.Tcp.Ip, Communication.Lifting.Brand.EWELLIX.Tcp.Port) --创建TCP客户端
        end,
        [1] = function()
            ExAxisMaxDistance = Communication.Lifting.Brand.GeMinG.MaxDistance
            Err, Communication.Lifting.Brand.GeMinG.ModbusRTU.Id = ModbusRTUCreate(
                Communication.Lifting.Brand.GeMinG.ModbusRTU.SlaveId,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.BaudRate,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.Parity,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.DataBit,
                Communication.Lifting.Brand.GeMinG.ModbusRTU.StopBit)
        end,
        [2] = function()
            ExAxisMaxDistance = Communication.Lifting.Brand.ZT3ILC.MaxDistance
            Err, Communication.Lifting.Brand.ZT3ILC.Modbus.Id = ModbusCreate(
                Communication.Lifting.Brand.ZT3ILC.Modbus.Ip,
                Communication.Lifting.Brand.ZT3ILC.Modbus.Port)
        end,
    }

    local SwitchCommInitMode =
    {
        [0] = function()
            local EHeight = {}
            local EHeightResult = {}
            print("Create TCP Client Success!")
            Err = TCPStart(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 5) --建立TCP连接
            TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                Communication.Lifting.Brand.EWELLIX.Command.GetPosition)
            Err, EHeight = TCPRead(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 5, "string")
            EHeightResult = Split(EHeight, ",")
            CurrentHeight = tonumber(EHeightResult[3])
        end,
        [1] = function()
            print("Create RTUModbus Client Success!")
            SV660CInit()
            SV660CEnable(1)
            CurrentHeight = SV660CGetPostion()[1]
            if CurrentHeight == nil then
                Err = 1
                CurrentHeight = 0
            else
                CurrentHeight = 0.1 * CurrentHeight
            end
        end,
        [2] = function()
            print("Create Modbus Client Success!")
            ZC01Init()
            ZC01Enable(1)
            CurrentHeight = ZC01GetPostion()[1]
            if CurrentHeight == nil then
                Err = 1
            else
                CurrentHeight = ConvertFloat(CurrentHeight)
            end
        end,
    }

    local switch_init_mode = SwitchCommInitMode[Communication.Lifting.Mode]
    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
    else
        print("The SwitchCommMode is error, please check it!")
    end
    if Err == 0 then
        if switch_init_mode then
            switch_init_mode()
        else
            print("The SwitchCommInitMode is error, please check it!")
        end
        if Err == 0 then
            print("Communication Connection Success!")
        else
            while true do
                print("Communication Connection failed, code:", Err)
                Wait(1000)
                --报警1："与升降轴通信失败"
                ErrorMessage.Code = 1
                Alarm("与升降轴通信失败")
            end
        end
    else
        while true do
            print("Create TCP Client failed, code:", Err)
            Wait(1000)
            --报警1："与升降轴通信失败"
            ErrorMessage.Code = 1
            Alarm("与升降轴通信失败")
        end
    end
    ExAxisLiftingHeight = math.ceil(CurrentHeight)
end

---------------------------------------------------------------
--检查机器人是否在HomePoint点位置
local function RobotGoHome()
    MovJ(HomePoint, { a = 100, v = NLDVel, cp = 100 })
end

---------------------------------------------------------------
--栈板三色灯初始化:初始时、脚本退出前栈板状态指示灯熄灭
local function InitTriLight()
    DO(FirstPallet.TriLight.Yellow, OFF) --栈板三色灯
    DO(FirstPallet.TriLight.Green, OFF)
    DO(FirstPallet.TriLight.Red, OFF)

    DO(SecondPallet.TriLight.Yellow, OFF) --栈板三色灯
    DO(SecondPallet.TriLight.Green, OFF)
    DO(SecondPallet.TriLight.Red, OFF)
end

---------------------------------------------------------------
--获取隔板高度
local function GetLayerSheetHeight(PalletNumber, LayerSheetPickPose)
    LayerSheetNum = ReadRobotModbus(FirstPallet.RegisterID.LayerSheetNum) --隔板计数
    if PalletNumber.PalletMode == 1 then
        if LayerSheetNum <= 0 then
            ErrorMessage.Code = 7
            Alarm("隔板已空")
            LayerSheetNum = PalletNumber.ProcessNum.LayerSheetNum
        end
    else
        if PalletNumber.ProcessNum.LayerSheetNum + 1 <= LayerSheetNum then
            ErrorMessage.Code = 7
            Alarm("隔板已满")
            LayerSheetNum = 1
        end
    end

    local PickPoseOffset = RelPointUser(LayerSheetPickPose,
        { 0, 0, PalletNumber.ProcessNum.LayerSheetHeight * LayerSheetNum, 0, 0, 0 })

    return PickPoseOffset
end
---------------------------------------------------------------
--Z轴向高度补偿
local function ZAxisCompensate(PalletNumber, DestPose)
    if PalletNumber.PalletMode == 1 then
        if (PalletNumber.PalletNum.LayerCount >= PalletNumber.CompensateLayer)
            or ((PalletNumber.PalletNum.LayerCount == PalletNumber.CompensateLayer - 1)
                and (PalletNumber.PalletNum.NextBoxCount > PalletNumber.PalletNum.LayerBoxNum)
                and (PalletNumber.LayerSheet.Enable == false)) then
            DestPose.pose[3] = DestPose.pose[3] - PalletNumber.CompensateZData
        end
    else
        if (PalletNumber.PalletNum.LayerCount >= PalletNumber.CompensateLayer) then
            DestPose.pose[3] = DestPose.pose[3] - PalletNumber.CompensateZData
        end
    end

    return DestPose
end

---------------------------------------------------------------
--Rz旋转补偿
local function RzCompensate(PalletNumber, DestPose, NameStr)
    local OffSet = {}
    OffSet, PalletNumber.BoxProperty.VacuumCup =
        GetBoxProPerty(NameStr, Pallet, PalletNumber.PalletNum.NextBoxCount)
    if PalletNumber.BoxProperty.VacuumCup > 0 then
        PalletNumber.BoxProperty.VacuumCup = 1
    end
    PalletNumber.BoxProperty.OffsetX = OffSet[1]
    PalletNumber.BoxProperty.OffsetY = OffSet[2]
    PalletNumber.BoxProperty.OffsetZ = OffSet[3]

    return DestPose
end
---------------------------------------------------------------
--获取点位信息
local function GetPointInfo(PalletNumber, CurrentPointType, CurrentIndex)
    local LayerNum = 0
    if PalletNumber.LayerSheet.Enable == true then
        ErrorMessage.PointInfo.Type = CurrentPointType.WithLayerSheet
    else
        ErrorMessage.PointInfo.Type = CurrentPointType.NoLayerSheet
    end

    if PalletNumber.PalletMode == 1 then
        if (PalletNumber.ProcessNum.BoxCount >= PalletNumber.PalletNum.LayerBoxNum)
            and (PalletNumber.PalletNum.LayerBoxNum > 0) and (PalletNumber.LayerSheet.Enable == false) then
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount + 1
        else
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
        end
    else
        local LocalLayerBoxNum = GetOddBoxCnt(PalletName, Pallet, PalletNumber.PalletNum.LayerCount)
        local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
        if (PalletNumber.ProcessNum.BoxCount <= TempBoxNum)
            and (TempBoxNum > 0) then
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount - 1
        else
            ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
        end
    end
    if ErrorMessage.PointInfo.Type == 5 or ErrorMessage.PointInfo.Type == 6 then
        ErrorMessage.PointInfo.Index = CurrentIndex
    else
        for i = 1, (ErrorMessage.PointInfo.Layer - 1) do
            LayerNum = LayerNum + GetOddBoxCnt(PalletName, Pallet, i)
        end
        ErrorMessage.PointInfo.Index = CurrentIndex - LayerNum
    end
    ErrorMessage.PointInfo.PalletNum = Pallet
end
---------------------------------------------------------------
--调整升降柱高度
local function AdjustLiftingHeight(FallingHeight, RelativeHeight)
    if (RelativeHeight > 0) then
        MovJ(LiftingPoint, { a = 100, v = NLDVel, cp = 100 })
        Communication.Lifting.TimesPerHour = Communication.Lifting.TimesPerHour + 1
    else
        return
    end

    local HeightIncrease = FallingHeight + 1
    local HeightReduce = FallingHeight - 1

    local SwitchCommMode =
    {
        [0] = function()
            local Err = 0
            local ReturnResult = {}
            local ReturnValue = {}

            print("LiftingHeight", FallingHeight)
            local HeightResult = tostring(FallingHeight)
            TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                Communication.Lifting.Brand.EWELLIX.Command.MovePosition .. HeightResult .. "\n")
            repeat
                TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                    Communication.Lifting.Brand.EWELLIX.Command.GetPosition)
                Err, ReturnValue = TCPRead(Communication.Lifting.Brand.EWELLIX.Tcp.Socket, 0, "string")
                ReturnResult = Split(ReturnValue, ",")
                if Err ~= 0 then
                    ErrorMessage.Code = 12
                    Alarm("升降柱状态异常！")
                end
                if Communication.Lifting.StopLiftingFlag == true then
                    Communication.Lifting.StopLiftingFlag = false
                    TCPWrite(Communication.Lifting.Brand.EWELLIX.Tcp.Socket,
                        Communication.Lifting.Brand.EWELLIX.Command.MovePosition .. HeightResult .. "\n")
                end

                
            until (
                    (tonumber(ReturnResult[3]) == FallingHeight)
                    or (tonumber(ReturnResult[3]) == HeightIncrease)
                    or (tonumber(ReturnResult[3]) == HeightReduce)
                )
        end,
        [1] = function()
            local HeightResult = math.ceil(FallingHeight * 10)
            local HeightIncreaseResult = math.ceil((HeightIncrease - 1) * 10 + 1)
            local HeightReduceResult = math.ceil((HeightReduce + 1) * 10 - 1)
            local ReturnResult = 0
            print("LiftingHeight", FallingHeight)
            SV660CRun(HeightResult)
            repeat
                ReturnResult = SV660CGetPostion()
                if Communication.Lifting.StopLiftingFlag == true then
                    Communication.Lifting.StopLiftingFlag = false
                    SV660CRun(HeightResult)
                end
            until (
                    (ReturnResult[1] == HeightResult)
                    or (ReturnResult[1] == HeightIncreaseResult)
                    or (ReturnResult[1] == HeightReduceResult)
                )
        end,
        [2] = function()
            local HeightResult = FallingHeight
            local HeightIncreaseResult = HeightIncrease
            local HeightReduceResult = HeightReduce
            local ReturnResult = 0
            print("LiftingHeight", FallingHeight)
            ZC01Run(HeightResult)
            repeat
                ReturnResult = math.ceil(ZC01GetPostion())
                if Communication.Lifting.StopLiftingFlag == true then
                    Communication.Lifting.StopLiftingFlag = false
                    ZC01Init()
                    ZC01Run(HeightResult)
                end
            until (
                    (ReturnResult == math.ceil(HeightResult))
                    or (ReturnResult == math.ceil(HeightIncreaseResult))
                    or (ReturnResult == math.ceil(HeightReduceResult))
                )
        end
    }

    local switch_mode = SwitchCommMode[Communication.Lifting.Mode]
    if switch_mode then
        switch_mode()
    else
        print("The SwitchCommMode is error, please check it!")
    end
end
---------------------------------------------------------------
--传送带用户坐标切换
local function ConveyorUserSwitch(PalletNumber, UserFlag, UserNum, NameStr)
    if (WorkingMode == 1) and (PalletNumber.LayerSheet.Enable == false) then
        local SwitchUser =
        {
            [0] = function()
                PalletNumber.Coordinate.UserNum = GetPalletUser(NameStr, UserNum)
            end,
            [1] = function()
                if Pallet ~= BoxBeInpPlaceFlag then
                    if BoxBeInpPlaceFlag == 0 then
                        PalletNumber.Coordinate.UserNum = FirstPallet.Coordinate.UserNum
                    elseif BoxBeInpPlaceFlag == 1 then
                        PalletNumber.Coordinate.UserNum = SecondPallet.Coordinate.UserNum
                    else
                        print("用户坐标错误！")
                        Pause()
                    end
                end
            end
        }

        local switch_func = SwitchUser[UserFlag]

        if switch_func then
            switch_func()
        else
            print("The SwitchTool is error, please check it!")
            Pause()
        end
    end
end

---------------------------------------------------------------
--切换工具
local function ToolSwitch(PalletNumber, ToolFlag, NameStr)
    local CurrentTool = {}
    if (PalletNumber.LayerSheet.Enable == false)
        and (PalletVacuumCupFunc == 2)
        and (PalletNumber.BoxProperty.VacuumCup == 0) then
        local SwitchTool =
        {
            [0] = function()
                CurrentTool = GetPalletTool(NameStr, 1)
                PalletNumber.Coordinate.ToolNum = CurrentTool[2]
            end,
            [1] = function()
                local CTool = GetPalletTool(NameStr, 0)
                PalletNumber.Coordinate.ToolNum = CTool[1]
            end
        }

        local switch_func = SwitchTool[ToolFlag]

        if switch_func then
            switch_func()
        else
            print("The SwitchTool is error, please check it!")
            Pause()
        end
    end
end
---------------------------------------------------------------
--***码垛子函数***--
---------------------------------------------------------------
--计算位置：放置位置
local function GetPlacePositon(PalletNumber, LayerSheetPickPose, LayerSheetPlacePose, NameStr)
    local PickPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    local DestPose = { pose = { 0, 0, 0, 0, 0, 0 } }

    if WorkingMode == 0 then
        if Pallet == 0 then
            PickPose = DeepCopy(FirstPickPose)
        else
            PickPose = DeepCopy(SecondPickPose)
        end
    else
        if BoxBeInpPlaceFlag == 0 then
            PickPose = DeepCopy(FirstPickPose)
        elseif BoxBeInpPlaceFlag == 1 then
            PickPose = DeepCopy(SecondPickPose)
        else
            print("异常 BoxBeInpPlaceFlag = ", BoxBeInpPlaceFlag)
            Pause()
        end
    end

    DestPose = GetBoxPos(NameStr, Pallet, PalletNumber.PalletNum.NextBoxCount)
    print("放置/抓取 ", PalletNumber.PalletNum.NextBoxCount)
    
    DestPose = ZAxisCompensate(PalletNumber, DestPose)
    DestPose = RzCompensate(PalletNumber, DestPose, NameStr)
    return DestPose, PickPose
end

---------------------------------------------------------------
--计算升降轴抬升高度
local function GetExAxisHeight(PalletNumber, ExAxisHeight, AxisOffsetHeight, DestPose, ModeSwitch)
	local ErrorID = 0
    local JointAngle = 0
    local LiftingHeight = 0
    local CheckResult = false
    local LiftingFlag = false
    local CopyDestPose = {}
    local LocalNearJoint = {}
	local switch_func = SwitchJoint[Pallet]
    if switch_func then
        switch_func()
        LocalNearJoint = NearJoint
    else
        print("The GetExAxisHeight is error, please check it!")
        Pause()
    end

    CopyDestPose.pose = DeepCopy(DestPose.pose)
    if ModeSwitch == 0 then
        CopyDestPose.pose[3] = CopyDestPose.pose[3] - ExAxisHeight + AxisOffsetHeight
    elseif ModeSwitch == 1 then
        CopyDestPose.pose[3] = CopyDestPose.pose[3] - ExAxisHeight
    end
	repeat
		ErrorID, JointAngle = InverseKin(
			{
                pose =
                {
                    CopyDestPose.pose[1], CopyDestPose.pose[2],
                    CopyDestPose.pose[3] - LiftingHeight,
                    CopyDestPose.pose[4], CopyDestPose.pose[5], CopyDestPose.pose[6]
                }
			},
			{
				jointNear =
				{
					joint = LocalNearJoint
				},
				useJointNear = true,
				user = PalletNumber.Coordinate.UserNum,
				tool = PalletNumber.Coordinate.ToolNum,
			}
        )
        if PalletLiftingFunction == true then
            if (ErrorID == 0)
                and ((JointAngle.joint[3] >= Joint3Angle) or (JointAngle.joint[3] <= -Joint3Angle))
                and ((JointAngle.joint[4] >= PalletNumber.J4UpperLimit) or (JointAngle.joint[4] <= PalletNumber.J4LowerLimit)) then
                CheckResult = true
                print("\rExAxisHeight 可达:", ExAxisHeight + LiftingHeight) --升降轴抓取料箱需要抬升的高度
            else
                CheckResult = false
                local CurrentUser = CalcUser(PalletNumber.Coordinate.UserNum, 0, { 0, 0, 0, 0, 0, 0 })
                if CopyDestPose.pose[3] + CurrentUser[3] < 0 then
                    LiftingHeight = LiftingHeight - BoxHigh
                else
                    LiftingHeight = LiftingHeight + BoxHigh
                end
                print("\rExAxisHeight 不可达:", ExAxisHeight + LiftingHeight) --升降轴抓取料箱需要抬升的高度
                if ExAxisHeight + LiftingHeight < 0 then
                    ErrorMessage.Code = 2
                    Alarm("升降轴移动高度超出最大行程")
                    Pause()
                    break
                end
                if (ExAxisHeight + LiftingHeight > ExAxisMaxDistance) then
                    if LiftingFlag == false then
                        LiftingFlag = true
                        LiftingHeight = ExAxisMaxDistance - ExAxisHeight
                    else
                        ErrorMessage.Code = 2
                        Alarm("升降轴移动高度超出最大行程")
                        Pause()
                        break
                    end
                end
            end
        else
            CheckResult = true
            if (ErrorID ~= 0)
                or ((JointAngle.joint[3] < Joint3Angle) and (JointAngle.joint[3] > -Joint3Angle)) then
                ErrorMessage.Code = 2
                Alarm("放置/抓取点位不可达！")
                print("DestPose", DestPose)
                Pause()
                break
            end
        end
    until (CheckResult == true)

    return (ExAxisHeight + LiftingHeight)

end

---------------------------------------------------------------
--放置箱体过渡点
local function PlacePalletTransPoint(PalletNumber, DestPose, TransitionPoint, LiftingHeight,
                                     OffHeight, ModeSwitch, PointMode, ToolAcc, ToolSpeed)
    print("\rPlacePos.pose[6]:", DestPose.pose[6])
    local DestPoint = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }
    DestPoint.pose = DeepCopy(TransitionPoint.pose)
    DestPoint.pose[6] = DestPose.pose[6] --过渡点与放置姿态一致
    if (DestPoint.pose[6] > 180) then
        DestPoint.pose[6] = DestPoint.pose[6] - 360
    end

    DestPoint.pose[3] = DestPoint.pose[3] - LiftingHeight --更新过渡点位置

    if PointMode == 0 then
        if DestPoint.pose[3] <= (DestPose.pose[3] + OffHeight + PalletNumber.BoxProperty.OffsetZ - LiftingHeight) then
            DestPoint.pose[3] = DestPose.pose[3] + OffHeight + PalletNumber.BoxProperty.OffsetZ - LiftingHeight
        end

        local PickTransPoint = 0
        if Pallet == 0 then
            PickTransPoint = PickPoseFP.pose[3]
        else
            PickTransPoint = PickPoseSP.pose[3]
        end
        if DestPoint.pose[3] <= (PickTransPoint + TeachPointOffHeight - LiftingHeight) then
            DestPoint.pose[3] = PickTransPoint + TeachPointOffHeight - LiftingHeight
        end
    end
    if ModeSwitch == 0 then
        local tempDestJoint = PalletGetPose(PalletNumber, DestPoint, 1)
        if PalletObstacleFunc == 1 and PalletNumber.TransPointMode == 1 then
            MovL(tempDestJoint, { a = ToolAcc, v = ToolSpeed, cp = 100 }) --运动到层过渡点
        else
            MovJ(tempDestJoint, { a = ToolAcc, v = ToolSpeed, cp = 100 }) --运动到层过渡点
        end
    elseif ModeSwitch == 1 then
        LiftingHeight = GetExAxisHeight(PalletNumber, LiftingHeight, OffHeight, DestPoint, 2)
    end

    return LiftingHeight
end

---------------------------------------------------------------
--选择过渡点
local function ChooseTransPoint(PalletNumber, DestPose, LiftingHeight, OffHeight, TransFlag, ModeSwitch, ToolAcc,
                                ToolSpeed)
    local PointMode = 0
    local PointNum = 0
    local TransPoint = {}
    local TransitionPoint = { pose = {} }
    local CPoint = { pose = {}, joint = {} }

    if PartCoordinateFlag == 0 then
        if PalletNumber.TransPointMode == 0 then
            PointNum = PalletNumber.TransPlacePointNum
            TransPoint = DeepCopy(PalletNumber.TeachPoint.TransPlacePoint)
        else
            TransitionPoint.pose =
                DeepCopy(PalletNumber.AutoGenPoint.TransPoint[PalletNumber.PalletNum.NextBoxCount])
        end
    else
        print("PartCoordinateFlag Is Wrong", PartCoordinateFlag)
        Pause()
    end
    if PalletNumber.TransPointMode == 1 then
        PointNum = CheckTableData(TransitionPoint.pose)
        if PointNum > 0 then
            TransitionPoint = GetAddUserPos(0, PalletNumber.Coordinate.UserNum, TransitionPoint)
            TransitionPoint.pose = CalcTool(PalletNumber.Coordinate.ToolNum, 0, TransitionPoint.pose)
            PointMode = 0
        end
    end
    local switchTransPoint =
    {
        [0] = function()
            print("无过渡点！")
            Pause()
        end,
        [1] = function()
            if PalletNumber.TransPointMode == 0 then
                CPoint.pose = DeepCopy(TransPoint.pose[1])
                CPoint.joint = DeepCopy(TransPoint.joint[1])
                TransitionPoint = PalletGetPose(PalletNumber, CPoint, 0)
                PointMode = TransPoint.mode[1]
            end
            GetPointInfo(PalletNumber, PointType.TransPoint, 1)
            LiftingHeight = PlacePalletTransPoint(PalletNumber, DestPose, TransitionPoint, LiftingHeight,
                OffHeight, ModeSwitch, PointMode, ToolAcc, ToolSpeed)
        end,
        [2] = function()
            CPoint.pose = DeepCopy(TransPoint.pose[2])
            CPoint.joint = DeepCopy(TransPoint.joint[2])
            TransitionPoint = PalletGetPose(PalletNumber, CPoint, 0)
            PointMode = TransPoint.mode[2]
            GetPointInfo(PalletNumber, PointType.TransPoint, 2)
            LiftingHeight = PlacePalletTransPoint(PalletNumber, DestPose, TransitionPoint, LiftingHeight,
                OffHeight, ModeSwitch, PointMode, ToolAcc, ToolSpeed)
        end,
        [3] = function()
            CPoint.pose = DeepCopy(TransPoint.pose[3])
            CPoint.joint = DeepCopy(TransPoint.joint[3])
            TransitionPoint = PalletGetPose(PalletNumber, CPoint, 0)
            PointMode = TransPoint.mode[3]
            GetPointInfo(PalletNumber, PointType.TransPoint, 3)
            LiftingHeight = PlacePalletTransPoint(PalletNumber, DestPose, TransitionPoint, LiftingHeight,
                OffHeight, ModeSwitch, PointMode, ToolAcc, ToolSpeed)
        end,
        [4] = function()
            CPoint.pose = DeepCopy(TransPoint.pose[4])
            CPoint.joint = DeepCopy(TransPoint.joint[4])
            TransitionPoint = PalletGetPose(PalletNumber, CPoint, 0)
            PointMode = TransPoint.mode[4]
            GetPointInfo(PalletNumber, PointType.TransPoint, 4)
            LiftingHeight = PlacePalletTransPoint(PalletNumber, DestPose, TransitionPoint, LiftingHeight,
                OffHeight, ModeSwitch, PointMode, ToolAcc, ToolSpeed)
        end,
        [5] = function()
            CPoint.pose = DeepCopy(TransPoint.pose[5])
            CPoint.joint = DeepCopy(TransPoint.joint[5])
            TransitionPoint = PalletGetPose(PalletNumber, CPoint, 0)
            PointMode = TransPoint.mode[5]
            GetPointInfo(PalletNumber, PointType.TransPoint, 5)
            LiftingHeight = PlacePalletTransPoint(PalletNumber, DestPose, TransitionPoint, LiftingHeight,
                OffHeight, ModeSwitch, PointMode, ToolAcc, ToolSpeed)
        end
    }

    local switch_mode

    for i = 1, PointNum do
        if TransFlag == 0 then
            switch_mode = switchTransPoint[i]
        else
            switch_mode = switchTransPoint[PointNum - i + 1]
        end

        if switch_mode then
            switch_mode()
        else
            print("The switchTransPoint is error, please check it!")
            Pause()
        end
        print("\rTransitionPoint.pose[6]:", TransitionPoint.pose[6])
    end

    return LiftingHeight
end
---------------------------------------------------------------
--获取升降轴高度
local function GetAxisHeight(PalletNumber, DestPose, NameStr)
    local Index = 0
    local VacuumCup = 0
    local OffSet = {}
    local BoxPoint = {}
    local ExAxisHeight = ExAxisLiftingHeight
    local AxisOffsetHeight = PalletNumber.OffsetHeight

    --[[if PalletNumber.LayerSheet.Enable == false then
        local LayerCount = 0
        if PalletNumber.PalletMode == 1 then
            if (PalletNumber.ProcessNum.BoxCount >= PalletNumber.PalletNum.LayerBoxNum)
                and (PalletNumber.PalletNum.LayerBoxNum > 0) then
                LayerCount = PalletNumber.PalletNum.LayerCount + 1
            else
                LayerCount = PalletNumber.PalletNum.LayerCount
            end
        else
            local LocalLayerBoxNum = GetOddBoxCnt(PalletName, Pallet, PalletNumber.PalletNum.LayerCount)
            local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
            if (PalletNumber.ProcessNum.BoxCount <= TempBoxNum)
                and (TempBoxNum > 0) then
                LayerCount = PalletNumber.PalletNum.LayerCount - 1
            else
                LayerCount = PalletNumber.PalletNum.LayerCount
            end
        end

        BoxPoint, Index = GetFarthestPoint(NameStr, Pallet, LayerCount) --每一层最远距离点
        OffSet, VacuumCup = GetBoxProPerty(NameStr, Pallet, Index)
        ToolSwitch(PalletNumber, VacuumCup, NameStr)
        GetPointInfo(PalletNumber, PointType.PlacePoint, Index)
        ExAxisHeight = GetExAxisHeight(PalletNumber, ExAxisHeight, AxisOffsetHeight, BoxPoint, 1)
        ToolSwitch(PalletNumber, 1, NameStr)
    end]]

    PartCoordinateFlag = 0
    ExAxisHeight = ChooseTransPoint(PalletNumber, DestPose, ExAxisHeight,
        PalletNumber.OffsetHeight, 0, 1, 100, LDVel)
    ToolSwitch(PalletNumber, PalletNumber.BoxProperty.VacuumCup, NameStr)
    GetPointInfo(PalletNumber, PointType.PlacePoint, PalletNumber.PalletNum.NextBoxCount)
    ExAxisHeight = GetExAxisHeight(PalletNumber, ExAxisHeight, AxisOffsetHeight, DestPose, 1)
    GetPointInfo(PalletNumber, PointType.PlaceOffsetPoint, PalletNumber.PalletNum.NextBoxCount)
    ExAxisHeight = GetExAxisHeight(PalletNumber, ExAxisHeight, AxisOffsetHeight, DestPose, 0)
    local PlacePosOffset = DeepCopy(DestPose)
    PlacePosOffset.pose[1] = PlacePosOffset.pose[1] + PalletNumber.BoxProperty.OffsetX
    PlacePosOffset.pose[2] = PlacePosOffset.pose[2] + PalletNumber.BoxProperty.OffsetY
    PlacePosOffset.pose[3] = PlacePosOffset.pose[3] + PalletNumber.BoxProperty.OffsetZ
    GetPointInfo(PalletNumber, PointType.InsertPoint, PalletNumber.PalletNum.NextBoxCount)
    ExAxisHeight = GetExAxisHeight(PalletNumber, ExAxisHeight, AxisOffsetHeight, PlacePosOffset, 0)
    print("\rExAxisHeight:", ExAxisHeight)
    ToolSwitch(PalletNumber, 1, NameStr)

    return ExAxisHeight
end
---------------------------------------------------------------
---------------------------------------------------------------
--计算码垛数量
local function GetPalletIndex(PalletNumber, NameStr)
    if PalletNumber.ProcessNum.BoxCount > PalletNumber.PalletNum.LayerBoxNum then
        if PalletNumber.PalletNum.LayerBoxNum > 0 then
            PalletNumber.PalletNum.LayerCount = PalletNumber.PalletNum.LayerCount + 1
        end
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.PalletNum.LayerBoxNum +
            GetOddBoxCnt(NameStr, Pallet, PalletNumber.PalletNum.LayerCount)
    end

    PalletNumber.PalletNum.RemainBoxNum = PalletNumber.PalletNum.LayerBoxNum - PalletNumber.ProcessNum.BoxCount
end

---------------------------------------------------------------
--计算拆垛数量
local function GetDePalletIndex(PalletNumber, NameStr)
    local LocalLayerBoxNum = GetOddBoxCnt(NameStr, Pallet, PalletNumber.PalletNum.LayerCount)
    local TempBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
    PalletNumber.PalletNum.RemainBoxNum = PalletNumber.ProcessNum.BoxCount - TempBoxNum
    if PalletNumber.ProcessNum.BoxCount <= TempBoxNum then
        PalletNumber.PalletNum.LayerBoxNum = PalletNumber.PalletNum.LayerBoxNum - LocalLayerBoxNum
        if PalletNumber.PalletNum.LayerBoxNum > 0 then
            PalletNumber.PalletNum.LayerCount = PalletNumber.PalletNum.LayerCount - 1
            PalletNumber.PalletNum.RemainBoxNum = GetOddBoxCnt(NameStr, Pallet, PalletNumber.PalletNum.LayerCount)
        end
    end
end

---------------------------------------------------------------
--计算放置箱子数量
local function CalPlaceBoxNum(PalletNumber, NameStr)
    local OffSet = {}
    local VacuumCup = 0
    local DestPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    PalletNumber.ProcessNum.BoxCount = PalletNumber.PalletNum.NextBoxCount        --托盘已放置箱体的数量
    PalletNumber.PalletNum.NextBoxCount = PalletNumber.PalletNum.NextBoxCount + 1 --托盘下一个放置箱体的数量
    if PalletNumber.ProcessNum.BoxCount > PalletNumber.ProcessNum.TotalBoxNum then
        print("BoxCount is Wrong!")
        PalletNumber.ProcessNum.BoxCount = PalletNumber.ProcessNum.TotalBoxNum
        PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.TotalBoxNum + 1
    end
    GetPalletIndex(PalletNumber, NameStr)

    if PalletNumber.PalletNum.NextBoxCount <= 1 then
        OffSet, VacuumCup = GetBoxProPerty(NameStr, Pallet, 1)
    else
        OffSet, VacuumCup = GetBoxProPerty(NameStr, Pallet, PalletNumber.PalletNum.NextBoxCount - 1)
    end
    if VacuumCup > 0 then
        PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount + 1
    end

    CommitPalletNum(PalletNumber)  --上传已有料箱层数、剩余料箱数
    PlaceCountPallet(PalletNumber) --调用放置计数程序
    WriteRobotModbus(Pallet + 1, 5037)
    --判断托盘是否已满载。当托盘计数大于单侧箱体的总数视为满载
    if (PalletNumber.PalletNum.NextBoxCount > PalletNumber.ProcessNum.TotalBoxNum) then
        FinishFlag = true
        FirstPallet.State.Full = true  --将满载布尔变量置为true
        SecondPallet.State.Full = true --将满载布尔变量置为true
        if (WorkingMode ~= 2)
            or ((WorkingMode == 2) and (FirstPallet.State.Full == true)
                and (SecondPallet.State.Full == true))
        then
            IsReady = false
            if (PalletLiftingFunction == true) and (ExAxisLiftingHeight ~= 0) then
                ExAxisLiftingHeight = 0
                AdjustLiftingHeight(0, 1)
            end
            if (WorkingMode == 2) then
                if FirstPallet.PalletMode == 1 then
                    FirstPallet.PalletMode = 2
                    SecondPallet.PalletMode = 1
                    SwitchConveyorFlag = 1
                    WriteRobotModbus(SwitchConveyorFlag, 5028)
                    FirstPickPose = PalletGetPose(FirstPallet, FirstPallet.TeachPoint.TeachPickPoint, 0)
                    SecondPickPose = PalletGetPose(SecondPallet, SecondPallet.TeachPoint.TeachPickPoint, 0)
                elseif FirstPallet.PalletMode == 2 then
                    FirstPallet.PalletMode = 1
                    SecondPallet.PalletMode = 2
                    SwitchConveyorFlag = -1
                    WriteRobotModbus(2, 5028)
                    local SrcPose = { pose = {} }
                    local CurrentPose = { pose = {} }
                    local CurrentPoint = { pose = {}, joint = {} }
                    SrcPose.pose = DeepCopy(SecondPallet.TeachPoint.TeachPickPoint.pose)
                    CurrentPose = GetAddUserPos(SecondPallet.Coordinate.UserNum, FirstPallet.Coordinate.UserNum, SrcPose)
                    CurrentPoint.pose = DeepCopy(CurrentPose.pose)
                    CurrentPoint.joint = DeepCopy(SecondPallet.TeachPoint.TeachPickPoint.joint)
                    FirstPickPose = PalletGetPose(FirstPallet, CurrentPoint, 0)

                    SrcPose.pose = DeepCopy(FirstPallet.TeachPoint.TeachPickPoint.pose)
                    CurrentPose = GetAddUserPos(FirstPallet.Coordinate.UserNum, SecondPallet.Coordinate.UserNum, SrcPose)
                    CurrentPoint.pose = DeepCopy(CurrentPose.pose)
                    CurrentPoint.joint = DeepCopy(FirstPallet.TeachPoint.TeachPickPoint.joint)
                    SecondPickPose = PalletGetPose(SecondPallet, CurrentPoint, 0)
                end
                FirstPallet.State.SecondResetFlag = true
                SecondPallet.State.SecondResetFlag = true
                WriteRobotModbus(FirstPallet.PalletMode, FirstPallet.RegisterID.PalletMode)
                WriteRobotModbus(SecondPallet.PalletMode, SecondPallet.RegisterID.PalletMode)
                WorkFinishFlag = true
            end
        else
            if PalletLiftingFunction then
                if FirstPallet.State.Full == true then
                    if SecondPallet.PalletNum.NextBoxCount > SecondPallet.ProcessNum.TotalBoxNum then
                        SecondPallet.PalletNum.NextBoxCount = SecondPallet.ProcessNum.TotalBoxNum
                    end
                    if SecondPallet.PalletNum.NextBoxCount < 1 then
                        SecondPallet.PalletNum.NextBoxCount = 1
                    end
                    DestPose = GetBoxPos(NameStr, 1, SecondPallet.PalletNum.NextBoxCount)
                elseif SecondPallet.State.Full == true then
                    if FirstPallet.PalletNum.NextBoxCount > FirstPallet.ProcessNum.TotalBoxNum then
                        FirstPallet.PalletNum.NextBoxCount = FirstPallet.ProcessNum.TotalBoxNum
                    end
                    if FirstPallet.PalletNum.NextBoxCount < 1 then
                        FirstPallet.PalletNum.NextBoxCount = 1
                    end
                    DestPose = GetBoxPos(NameStr, 0, FirstPallet.PalletNum.NextBoxCount)
                end

                if (DestPose.pose[3] < HomePointPose.pose[3]) and (ExAxisLiftingHeight ~= 0) then
                    ExAxisLiftingHeight = 0
                    AdjustLiftingHeight(0, 1)
                end
            end
        end
    end
end

--------------------------------------------------------------
--启动带料箱动作
local function GetInitVacuumCupAction()
    DO(FirstPallet.TriLight.Yellow, OFF) --栈板三色灯
    DO(FirstPallet.TriLight.Green, OFF)
    DO(FirstPallet.TriLight.Red, ON)

    DO(SecondPallet.TriLight.Yellow, OFF) --栈板三色灯
    DO(SecondPallet.TriLight.Green, OFF)
    DO(SecondPallet.TriLight.Red, ON)

    ErrorMessage.Code = 6
    Alarm("启动带料")
end

--------------------------------------------------------------
--启动带料箱状态
local function GetInitVacuumCupState()
    local SwitchTerminalTool =
    {
        [-1] = function()

        end,
        [1] = function()
            if VacuumCupCfg.Dete.Mode == 1 then
                if (ToolDI(VacuumCupCfg.Dete.PE.A) == ON) and (CheckIORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A) == ON) then
                    GetInitVacuumCupAction()
                end
            elseif VacuumCupCfg.Dete.Mode == 2 then
                if (DI(VacuumCupCfg.Dete.Vacuum.A) == ON) and (CheckIORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A) == ON) then
                    GetInitVacuumCupAction()
                end
            else
                print("启动带料箱功能关闭！")
            end
        end,

        [2] = function()
            if VacuumCupCfg.Dete.Mode == 1 then
                if ((ToolDI(VacuumCupCfg.Dete.PE.A) == ON) or (ToolDI(VacuumCupCfg.Dete.PE.B) == ON))
                    and (CheckIORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A) == ON or CheckIORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B) == ON) then
                    GetInitVacuumCupAction()
                end
            elseif VacuumCupCfg.Dete.Mode == 2 then
                if ((DI(VacuumCupCfg.Dete.Vacuum.A) == ON) or (DI(VacuumCupCfg.Dete.Vacuum.B) == ON))
                    and (CheckIORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A) == ON or CheckIORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B) == ON) then
                    GetInitVacuumCupAction()
                end
            else
                print("启动带料箱功能关闭！")
            end
        end
    }

    local switch_mode = SwitchTerminalTool[PalletVacuumCupFunc]
    if switch_mode then
        switch_mode()
    else
        print("The SwitchTerminalTool is error, please check it!")
        Pause()
    end
end

---------------------------------------------------------------
--初始化吸盘
local function InitVacuumCup()
    GetInitVacuumCupState()
    local SwitchVacuumCup =
    {
        [-1] = function()
            local Err = 0
            SetTool485(Communication.VacuumCup.Tcp.BaudRate, Communication.VacuumCup.Tcp.Parity,
                Communication.VacuumCup.Tcp.StopBit)
            Err, Communication.VacuumCup.Tcp.Socket = TCPCreate(false,
                Communication.VacuumCup.Tcp.Ip, Communication.VacuumCup.Tcp.Port) --创建TCP客户端
            print("Create TCP Client Success!")
            Err = TCPStart(Communication.VacuumCup.Tcp.Socket, 5)                 --建立TCP连接
            if Err ~= 0 then
                ErrorMessage.Code = 8
                Alarm("吸盘初始化失败！")
            end
        end,
        [1] = function()
            IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, OFF)
            if LayerSheetSignalFunction then
                IORes(PartSignalMode, LayerSheetSignal, OFF)
            end

            if VacuumCupCfg.Dete.VacuumBreak.Enable == 1 then
                IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.A, OFF)
            end
            
        end,
        [2] = function()
            IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, OFF) --数字输出控制吸盘关闭
            IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B, OFF)
            if LayerSheetSignalFunction then
                IORes(PartSignalMode, LayerSheetSignal, OFF)
            end
            if VacuumCupCfg.Dete.VacuumBreak.Enable == 1 then
                IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.A, OFF)
                IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.B, OFF)
            end
        end
    }

    local switch_mode = SwitchVacuumCup[PalletVacuumCupFunc]

    if switch_mode then
        switch_mode()
    else
        print("The SwitchVacuumCup is error, please check it!")
        Pause()
    end

end

---------------------------------------------------------------
--打开吸盘
local function OpenVacuumCup(PalletNumber)
    local CurrentTool = {}
    local CurrentToolNum = 0
    if (PalletVacuumCupFunc == 2)
        and (PalletNumber.BoxProperty.VacuumCup == 0)
        and (PalletNumber.LayerSheet.Enable == false) then
        CurrentToolNum, CurrentTool = GetPalletTool(PalletName, 1)
    else
        CurrentTool = CalcTool(PalletNumber.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    end
    local SwitchOpenVacuumCup =
    {
        [0] = function()
            if PalletVacuumCupFunc == -1 then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOn)
            else
                IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, ON)                                         --数字输出控制吸盘吸气
            end
            Wait(Time.Pick.In)                                                                                 --预留吸盘动作时间，以保证吸盘将箱体吸稳。等待时间根据实际情况来调整其大小
            SetPayload(PalletNumber.BoxProperty.BoxWeight + ToolWeight,
                { CurrentTool[1], CurrentTool[2], 0.5 * (CurrentTool[3] + PalletNumber.BoxProperty.BoxHigh) }) --设置负载指令，加上箱子重量
        end,
        [1] = function()
            if PalletVacuumCupFunc == -1 then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOn)
            else
                IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, ON) --数字输出控制吸盘吸气
                IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B, ON)
            end
            Wait(Time.Pick.In)                                                                                 --预留吸盘动作时间，以保证吸盘将箱体吸稳。等待时间根据实际情况来调整其大小
            SetPayload(2 * PalletNumber.BoxProperty.BoxWeight + ToolWeight,
                { CurrentTool[1], CurrentTool[2], 0.5 * (CurrentTool[3] + PalletNumber.BoxProperty.BoxHigh) }) --设置负载指令，加上箱子重量
        end,
        [2] = function()
            if PalletVacuumCupFunc == -1 then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOn)
            else
                if LayerSheetSignalFunction then
                    IORes(PartSignalMode, LayerSheetSignal, ON)
                else
                    if PalletVacuumCupFunc == 2 then
                        IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, ON) --数字输出控制吸盘吸气
                        IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B, ON)
                    else
                        IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, ON) --数字输出控制吸盘吸气
                    end
                end
            end
            Wait(Time.Pick.In) --预留吸盘动作时间，以保证吸盘将箱体吸稳。等待时间根据实际情况来调整其大小

            SetPayload(PalletNumber.ProcessNum.LayerSheetWeight + ToolWeight,
                { CurrentTool[1], CurrentTool[2], 0.5 * CurrentTool[3] }) --设置负载指令，加上箱子重量
        end
    }

    local ModeFlag = 0
    if PalletNumber.LayerSheet.Enable == true then
        ModeFlag = 2
    else
        ModeFlag = PalletNumber.BoxProperty.VacuumCup
    end
    local switch_mode = SwitchOpenVacuumCup[ModeFlag]

    if switch_mode then
        switch_mode()
    else
        print("The SwitchOpenVacuumCup is error, please check it!")
        Pause()
    end
end

---------------------------------------------------------------
--关闭吸盘
local function CloseVacuumCup(VacuumCup)
    local CurrentTool = {}

    if Pallet == 0 then
        CurrentTool = CalcTool(FirstPallet.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    else
        CurrentTool = CalcTool(SecondPallet.Coordinate.ToolNum, 0, { 0, 0, 0, 0, 0, 0 })
    end
    Wait(500)
    SetPayload(ToolWeight, { CurrentTool[1], CurrentTool[2], 0.5 * CurrentTool[3] }) ---设置负载为吸取箱子的负载
    local SwitchCloseVacuumCup =
    {
        [0] = function()
            if PalletVacuumCupFunc == -1 then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOff)
                Wait(Time.Place.In)                                --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
            else
                IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, OFF) --数字输出控制吸盘关闭
                if VacuumCupCfg.Dete.VacuumBreak.Enable == 1 then
                    IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.A, ON)
                    Wait(Time.Place.In) --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
                    IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.A, OFF)
                else
                    Wait(Time.Place.In) --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
                end
            end
        end,
        [1] = function()
            if PalletVacuumCupFunc == -1 then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOff)
                Wait(Time.Place.In)                                --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
            else
                IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.A, OFF) --数字输出控制吸盘关闭
                IORes(VacuumCupCfg.Port.Mode, VacuumCupCfg.Port.B, OFF)
                if VacuumCupCfg.Dete.VacuumBreak.Enable == 1 then
                    IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.A, ON)
                    IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.B, ON)
                    Wait(Time.Place.In) --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
                    IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.A, OFF)
                    IORes(VacuumCupCfg.Dete.VacuumBreak.Mode, VacuumCupCfg.Dete.VacuumBreak.B, OFF)
                else
                    Wait(Time.Place.In) --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
                end
            end
        end,
        [2] = function()
            if PalletVacuumCupFunc == -1 then
                TCPWrite(Communication.VacuumCup.Tcp.Socket, Communication.VacuumCup.Command.VacuumOff)
            else
                IORes(PartSignalMode, LayerSheetSignal, OFF)
            end
            Wait(Time.Place.In) --预留吸盘动作时间，以保证吸盘已将箱体完全放下。等待时间根据实际情况来调整其大小
        end
    }

    if (LayerSheetSignalFunction == true)
        and (FirstPallet.LayerSheet.Enable == true or SecondPallet.LayerSheet.Enable == true) then
        VacuumCup = 2
    end
    local switch_mode = SwitchCloseVacuumCup[VacuumCup]

    if switch_mode then
        switch_mode()
    else
        print("The SwitchCloseVacuumCup is error, please check it!")
        Pause()
    end
end

---------------------------------------------------------------
--初始化隔板数量
local function InitLayerSheet()
    if Pallet == 0 then
        LayerSheetNum = ReadRobotModbus(FirstPallet.RegisterID.LayerSheetNum) --隔板计数
        if (LayerSheetNum > FirstPallet.ProcessNum.LayerSheetNum) or (LayerSheetNum <= 0) then
            if (FirstPallet.PalletMode == 1) then
                WriteRobotModbus(FirstPallet.ProcessNum.LayerSheetNum, FirstPallet.RegisterID.LayerSheetNum)
            else
                WriteRobotModbus(1, FirstPallet.RegisterID.LayerSheetNum)
            end
        end
    else
        LayerSheetNum = ReadRobotModbus(FirstPallet.RegisterID.LayerSheetNum) --隔板计数
        if (LayerSheetNum > FirstPallet.ProcessNum.LayerSheetNum) or (LayerSheetNum <= 0) then
            if (SecondPallet.PalletMode == 1) then
                WriteRobotModbus(FirstPallet.ProcessNum.LayerSheetNum, FirstPallet.RegisterID.LayerSheetNum)
            else
                WriteRobotModbus(1, FirstPallet.RegisterID.LayerSheetNum)
            end
        end
    end
end
---------------------------------------------------------------
--初始化，复位信号、复位程序数据
local function InitPallet()
    InitVacuumCup()            --吸盘初始化
    InitTriLight()            --栈板三色灯初始化
    InitLayerSheet()           --隔板数量初始化
    if (PalletLiftingFunction == true) then
        CreateCommConnection() --与升降轴建立TCP通讯
        if (math.abs(ExAxisLiftingHeight) > 0) then
            ExAxisLiftingHeight = 0
            AdjustLiftingHeight(0, 1)
        end
    end
    RobotGoHome()
end

---------------------------------------------------------------
--“升降轴”移动到指定位置
local function LiftingPickPallet(PalletNumber, DestPose, RelativeHeight, ModeSwitch)
    local JointAngle = {}     --逆解关节角度
    local ErrorID = 0         --逆解错误码
    local CheckResult = false --检查结果
    local LiftingHeight = 0   --升降轴抓取料箱需要下移的高度，重置
    local LocalNearJoint = {}
    local switch_func = SwitchJoint[Pallet]
    if switch_func then
        switch_func()
        LocalNearJoint = NearJoint
    else
        print("The SwitchJoint is error, please check it!")
        Pause()
    end
    
    local CopyDestPose = DeepCopy(DestPose)
    if ModeSwitch == 0 then
        CopyDestPose.pose[3] = CopyDestPose.pose[3] - ExAxisLiftingHeight
    elseif ModeSwitch == 1 then
        CopyDestPose.pose[3] = CopyDestPose.pose[3] - ExAxisLiftingHeight + TeachPointOffHeight
    end
    repeat
        ErrorID, JointAngle = InverseKin(
            {
                pose =
                {
                    CopyDestPose.pose[1], CopyDestPose.pose[2],
                    CopyDestPose.pose[3] + LiftingHeight,
                    CopyDestPose.pose[4], CopyDestPose.pose[5], CopyDestPose.pose[6]
                }
            },
            {
                jointNear =
                {
                    joint = LocalNearJoint
                },
                useJointNear = true,
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            }
        )
        if PalletLiftingFunction == true then
            if (ErrorID == 0)
                and ((JointAngle.joint[3] >= Joint3Angle) or (JointAngle.joint[3] <= -Joint3Angle)) then
                CheckResult = true
            else
                CheckResult = false
                if CopyDestPose.pose[3] < 0 then
                    LiftingHeight = LiftingHeight - BoxHigh
                else
                    LiftingHeight = LiftingHeight + BoxHigh
                end
                --升降轴抓取料箱需要下移的高度
                print("\rExAxisFallingHeight NotFirst:", LiftingHeight)
                --报警2：“升降轴抬升高度超过最大行程”
                if (ExAxisLiftingHeight + LiftingHeight > ExAxisMaxDistance)
                    or (ExAxisLiftingHeight + LiftingHeight < 0) then
                    ErrorMessage.Code = 2
                    Alarm("升降轴移动高度超出最大行程! ")
                    print("DestPose", DestPose)
                    print("CopyDestPose", CopyDestPose)
                    Pause()
                    break
                end
            end
        else
            CheckResult = true
            if (ErrorID ~= 0)
                or ((JointAngle.joint[3] < Joint3Angle) and (JointAngle.joint[3] > -Joint3Angle)) then
                ErrorMessage.Code = 2
                Alarm("放置/抓取点位不可达！")
                print("DestPose", DestPose)
                print("CopyDestPose", CopyDestPose)
                Pause()
            end
        end
    until (CheckResult == true)

    if PalletLiftingFunction == true then
        ExAxisLiftingHeight = ExAxisLiftingHeight + LiftingHeight --升降轴抓取料箱下移后的位置
        print("\rExAxisFallingHeight Final:", LiftingHeight) --升降轴抓取料箱需要下移的高度
        print("\rExAxisFallingHeight 位置:", ExAxisLiftingHeight) --升降轴抓取料箱需要下移的高度
        AdjustLiftingHeight(ExAxisLiftingHeight, math.abs(RelativeHeight + LiftingHeight))
    end
end

----------------------------------------------------------------
--预处理获取点位关节
local function GetPrePointJoint(DestPose, LiftingHeight)
    local PreDestPoint = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }
    local PreDestPointOffset = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }

    PreDestPoint.pose = DeepCopy(DestPose.pose)
    PreDestPoint.pose[3] = PreDestPoint.pose[3] - LiftingHeight

    PreDestPointOffset.pose = DeepCopy(PreDestPoint.pose)
    PreDestPointOffset.pose[3] = PreDestPointOffset.pose[3] + TeachPointOffHeight

    return PreDestPoint, PreDestPointOffset
end

---------------------------------------------------------------
--抓取箱体
local function PickPallet(PalletNumber, DestPose, LiftingHeight)
    --根据“升降轴”相对于基准零位抬升高度更新抓取位置
    local PartPoint = { pose = { 0, 0, 0, 0, 0, 0 } }
    local PickJoint = { Joint = { 0, 0, 0, 0, 0, 0 } }
    local DestJointOffset = { Joint = { 0, 0, 0, 0, 0, 0 } }
    local PalletPickPoint = { pose = { 0, 0, 0, 0, 0, 0 }, joint = { 0, 0, 0, 0, 0, 0 } }
    local DestPickPointOffset = { pose = { 0, 0, 0, 0, 0, 0 }, joint = { 0, 0, 0, 0, 0, 0 } }

    PalletPickPoint, DestPickPointOffset = GetPrePointJoint(DestPose, LiftingHeight)
    PalletNumber.NearFlag = true
    PickJoint = PalletGetPose(PalletNumber, PalletPickPoint, 1)

    if PalletNumber.LayerSheet.Enable == true then
        local CLSPoint = { joint = {} }
        CLSPoint = DeepCopy(PalletNumber.LayerSheet.SafePoint.Forward.joint[1])
        PartPoint = PositiveKin(CLSPoint,
            {
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            })
        PartPoint.pose[3] = PartPoint.pose[3] - LiftingHeight
        DestPickPointOffset.pose = DeepCopy(PartPoint.pose)
    end
    DestJointOffset = PalletGetPose(PalletNumber, DestPickPointOffset, 1)
    PalletNumber.NearFlag = false
    Wait(Time.Pick.Pre)
    MovJ(DestJointOffset, { a = 100, v = NLDVel, cp = 100 })
    MovL(PickJoint, { a = 100, v = NLDVel, cp = 100 }) --运动到抓取点
    OpenVacuumCup(PalletNumber)
    Wait(Time.Pick.Post)
    StandyPoint = DeepCopy(DestJointOffset)
end

---------------------------------------------------------------
--“升降轴”移动到指定位置
local function LiftingPlacePallet(PalletNumber, DestPose, NameStr)
    ExAxisLiftingHeight = GetAxisHeight(PalletNumber, DestPose, NameStr)
    --通过TCP下发“升降轴”相对于零位的绝对位置
    print("ExAxisLiftingHeight Final位置:", ExAxisLiftingHeight)
end
---------------------------------------------------------------
---------------------------------------------------------------
--获取待机位置
local function GetStandbyPose()
    local WorkingModeFlag = 0
    local SpPickPoint = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }
    local DestJointOffset = { Joint = {} }
    local DestPointOffset = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }
    local SwitchWorkingMode =
    {
        [0] = function()
            if Pallet == 0 then
                SpPickPoint, DestPointOffset = GetPrePointJoint(FirstPickPose, ExAxisLiftingHeight)
                FirstPallet.NearFlag = true
                DestJointOffset = PalletGetPose(FirstPallet, DestPointOffset, 1)
                FirstPallet.NearFlag = false
            elseif Pallet == 1 then
                SpPickPoint, DestPointOffset = GetPrePointJoint(SecondPickPose, ExAxisLiftingHeight)
                SecondPallet.NearFlag = true
                DestJointOffset = PalletGetPose(SecondPallet, DestPointOffset, 1)
                SecondPallet.NearFlag = false
            else
                print("Pallet Is Wrong In GetStandbyPose()!")
                print("Pallet = ", Pallet)
                Pause()
            end
        end,
        [1] = function()
            if BoxBeInpPlaceFlag == 1 then
                SpPickPoint, DestPointOffset = GetPrePointJoint(FirstPickPose, ExAxisLiftingHeight)
                FirstPallet.NearFlag = true
                DestJointOffset = PalletGetPose(FirstPallet, DestPointOffset, 1)
                FirstPallet.NearFlag = false
            elseif BoxBeInpPlaceFlag == 2 then
                SpPickPoint, DestPointOffset = GetPrePointJoint(SecondPickPose, ExAxisLiftingHeight)
                SecondPallet.NearFlag = true
                DestJointOffset = PalletGetPose(SecondPallet, DestPointOffset, 1)
                SecondPallet.NearFlag = false
            else
                print("BoxBeInpPlaceFlag Is Wrong In GetStandbyPose()!")
                print("BoxBeInpPlaceFlag = ", BoxBeInpPlaceFlag)
                Pause()
            end
        end,
        [2] = function()

        end
    }

    WorkingModeFlag = WorkingMode
    if WorkingMode == 2 then
        WorkingModeFlag = 1
    end

    local switch_mode = SwitchWorkingMode[WorkingModeFlag]

    if switch_mode then
        switch_mode()
        if PalletObstacleFunc == 1 and (FirstPallet.TransPointMode == 1 or SecondPallet.TransPointMode == 1) then
            MovL(DestJointOffset, { a = 100, v = NLDVel, cp = 100 }) --运动到层过渡点
        else
            MovJ(DestJointOffset, { a = 100, v = NLDVel, cp = 100 })
        end
    else
        print("The Get Standby Pose is error, please check it!")
        Pause()
    end
end
---------------------------------------------------------------
--点位切换
local function SwitchPointMode(PalletNumber, DestPose)
    local tempPoint = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }
    tempPoint.pose = DeepCopy(DestPose.pose)
    local tempDestJoint = PalletGetPose(PalletNumber, tempPoint, 1)

    return tempDestJoint
end
---------------------------------------------------------------
--放置箱子
local function PlacePallet(PalletNumber, DestPose, LiftingHeight, NameStr)
    local OffHeight = 0 --放置前先移动到指定距离

    OffHeight = PalletNumber.OffsetHeight
    local CopyPlacePos = { 0, 0, 0, 0, 0, 0 }
    CopyPlacePos = DeepCopy(DestPose)
    CopyPlacePos.pose[3] = CopyPlacePos.pose[3] - LiftingHeight --根据“升降轴”相对于基准零位抬升高度更新抓取位置
    print("\rCopyPlacePos.pose[3]:", CopyPlacePos.pose[3])
    local PlacePosOffset = DeepCopy(CopyPlacePos)
    PlacePosOffset.pose[1] = PlacePosOffset.pose[1] + PalletNumber.BoxProperty.OffsetX
    PlacePosOffset.pose[2] = PlacePosOffset.pose[2] + PalletNumber.BoxProperty.OffsetY
    PlacePosOffset.pose[3] = PlacePosOffset.pose[3] + PalletNumber.BoxProperty.OffsetZ + OffHeight
    local CopyPlacePosOffset = DeepCopy(CopyPlacePos)
    CopyPlacePosOffset.pose[3] = CopyPlacePosOffset.pose[3] + OffHeight
    if PalletNumber.LayerSheet.Enable == false then
        PartCoordinateFlag = 0
    else
        PartCoordinateFlag = 2
    end
    ToolSwitch(PalletNumber, PalletNumber.BoxProperty.VacuumCup, NameStr)
    local tempDestJoint = SwitchPointMode(PalletNumber, PlacePosOffset)
    local tempPlaceOffsetJoint = SwitchPointMode(PalletNumber, CopyPlacePosOffset)
    local tempPlaceJoint = SwitchPointMode(PalletNumber, CopyPlacePos)
    MovL(StandyPoint, { a = 100, v = NLDVel, cp = 100 })
    ChooseTransPoint(PalletNumber, DestPose, LiftingHeight,
        OffHeight, 0, 0, 100, LDVel)
    MovL(tempDestJoint, { a = 100, v = LDVel, cp = 100 })                    --运动到放置过渡点
    MovL(tempPlaceOffsetJoint, { a = LDPlaceVel, v = PlaceSpeed, cp = 100 }) --运动到放置点正上方
    MovL(tempPlaceJoint, { a = LDPlaceVel, v = PlaceSpeed, cp = 100 })
    if PalletNumber.LayerSheet.Enable == false then
        CalPlaceBoxNum(PalletNumber, NameStr) --执行托盘码垛计数
    else
        LayerSheetNum = LayerSheetNum - 1
        WriteRobotModbus(LayerSheetNum, FirstPallet.RegisterID.LayerSheetNum)
    end
    CloseVacuumCup(PalletNumber.BoxProperty.VacuumCup)
    
    MovL(tempPlaceOffsetJoint, { a = 100, v = NLDVel, cp = 100 }) --运动到放置点正上方
    MovL(tempDestJoint, { a = 100, v = NLDVel, cp = 100 })        --运动到放置过渡点
    PartCoordinateFlag = 0
    ChooseTransPoint(PalletNumber, DestPose, LiftingHeight,
        OffHeight, 1, 0, 100, NLDVel)
    MovJ(StandyPoint, { a = 100, v = NLDVel, cp = 100 })
    local CurrentPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    CurrentPose = GetPose()
    ToolSwitch(PalletNumber, 1, NameStr)
    --GetStandbyPose()
    PrePallet = Pallet
    PrePoseHeight = CurrentPose.pose[3] + ExAxisLiftingHeight
end

---------------------------------------------------------------
--***拆垛子函数***--
---------------------------------------------------------------
---------------------------------------------------------------
--计算拆垛箱子数量
local function CalDePalletPlaceBoxNum(PalletNumber, NameStr)
    local DestPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    PalletNumber.ProcessNum.BoxCount = PalletNumber.PalletNum.NextBoxCount - 1 --托盘已放置箱体的数量
    PalletNumber.PalletNum.NextBoxCount = PalletNumber.ProcessNum.BoxCount     --托盘下一个放置箱体的数量
    if PalletNumber.ProcessNum.BoxCount < 0 then
        print("BoxCount Is Wrong!")
        PalletNumber.ProcessNum.BoxCount = 0
        PalletNumber.PalletNum.NextBoxCount = 0
    end
    GetDePalletIndex(PalletNumber, NameStr)
    local OffSet = {}
    local VacuumCup = 0
    if PalletNumber.PalletNum.NextBoxCount <= 0 then
        OffSet, VacuumCup = GetBoxProPerty(NameStr, Pallet, 1)
    else
        OffSet, VacuumCup = GetBoxProPerty(NameStr, Pallet, PalletNumber.PalletNum.NextBoxCount + 1)
    end
    if VacuumCup > 0 then
        PalletNumber.PalletNum.AddBoxCount = PalletNumber.PalletNum.AddBoxCount - 1
    end
    
    CommitPalletNum(PalletNumber)                      --上传已有料箱层数、剩余料箱数
    PlaceCountPallet(PalletNumber)                     --调用放置计数程序
    WriteRobotModbus(Pallet + 1, 5037)
    if (PalletNumber.PalletNum.NextBoxCount <= 0) then --判断托盘是否已满载。当托盘计数大于单侧箱体的总数视为满载
        FinishFlag = true
        FirstPallet.State.Empty = true                 --将满载布尔变量置为true
        SecondPallet.State.Empty = true                --将满载布尔变量置为true

        if PalletLiftingFunction then
            if MultPalletFunction == true then
                if Pallet == 0 then
                    if SecondPallet.PalletNum.NextBoxCount < 1 then
                        SecondPallet.PalletNum.NextBoxCount = 1
                    end
                    DestPose = GetBoxPos(NameStr, 1, SecondPallet.PalletNum.NextBoxCount)
                elseif Pallet == 1 then
                    if FirstPallet.PalletNum.NextBoxCount < 1 then
                        FirstPallet.PalletNum.NextBoxCount = 1
                    end
                    DestPose = GetBoxPos(NameStr, 0, FirstPallet.PalletNum.NextBoxCount)
                end
            else
                DestPose.pose[3] = 0
            end

            if (DestPose.pose[3] < HomePointPose.pose[3]) and (ExAxisLiftingHeight ~= 0) then
                ExAxisLiftingHeight = 0
                AdjustLiftingHeight(0, 1)
            end
        end
    end
end

---------------------------------------------------------------
--“升降轴”移动到指定位置
local function LiftingPickDePallet(PalletNumber, DestPose, NameStr)
    ExAxisLiftingHeight = GetAxisHeight(PalletNumber, DestPose, NameStr)
    if PalletLiftingFunction == true then
        print("ExAxisLiftingHeight Final位置:", ExAxisLiftingHeight)
        AdjustLiftingHeight(ExAxisLiftingHeight, math.abs(ExAxisLiftingHeight - LastHeight))
    end
end

---------------------------------------------------------------
--取料运动
local function PickDePalletCal(PalletNumber, DestPose, LiftingHeight, NameStr)
    local OffHeight = 0 --放置前升降轴先移动到指定距离
    OffHeight = PalletNumber.OffsetHeight
    PartCoordinateFlag = 0
    local CopyPlacePos = { 0, 0, 0, 0, 0, 0 }
    CopyPlacePos = DeepCopy(DestPose)

    CopyPlacePos.pose[3] = CopyPlacePos.pose[3] - LiftingHeight --根据“升降轴”相对于基准零位抬升高度更新抓取位置
    print("\rCopyPlacePos.pose[3]:", CopyPlacePos.pose[3])

    local CopyPlacePoseOffset = DeepCopy(CopyPlacePos)
    CopyPlacePoseOffset.pose[3] = CopyPlacePoseOffset.pose[3] + OffHeight
    local PlacePosOffset = DeepCopy(CopyPlacePos)
    PlacePosOffset.pose[1] = PlacePosOffset.pose[1] + PalletNumber.BoxProperty.OffsetX
    PlacePosOffset.pose[2] = PlacePosOffset.pose[2] + PalletNumber.BoxProperty.OffsetY
    PlacePosOffset.pose[3] = PlacePosOffset.pose[3] + PalletNumber.BoxProperty.OffsetZ + OffHeight
    ToolSwitch(PalletNumber, PalletNumber.BoxProperty.VacuumCup, NameStr)
    local tempDestJoint = SwitchPointMode(PalletNumber, PlacePosOffset)
    local tempPlaceOffsetJoint = SwitchPointMode(PalletNumber, CopyPlacePoseOffset)
    local tempPlaceJoint = SwitchPointMode(PalletNumber, CopyPlacePos)
    ChooseTransPoint(PalletNumber, DestPose, LiftingHeight,
        OffHeight, 0, 0, 100, NLDVel)
    MovL(tempDestJoint, { a = 100, v = NLDVel, cp = 100 })        --运动到放置过渡点
    MovL(tempPlaceOffsetJoint, { a = 100, v = NLDVel, cp = 100 }) --运动到放置点正上方
    MovL(tempPlaceJoint, { a = 100, v = NLDVel, cp = 100 })
    OpenVacuumCup(PalletNumber)
    MovL(tempPlaceOffsetJoint, { a = 100, v = LDVel, cp = 100 }) --运动到放置点正上方
    MovL(tempDestJoint, { a = 100, v = LDVel, cp = 100 })        --运动到放置过渡点
    if PalletNumber.LayerSheet.Enable == true then
        PartCoordinateFlag = 2
    end
    ChooseTransPoint(PalletNumber, DestPose, LiftingHeight,
        OffHeight, 1, 0, 100, LDVel)
    ToolSwitch(PalletNumber, 1, NameStr)
end

---------------------------------------------------------------
--放置箱体
local function PlaceDePallet(PalletNumber, DestPose, LiftingHeight, NameStr)
    local PartPoint = { pose = {} }
    local PlaceJoint = { Joint = {} }
    local PlacePoint = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }
    local PlaceJointOffset = { Joint = {} }
    local PlacePointOffset = { pose = {}, joint = { 0, 0, 0, 0, 0, 0 } }

    PlacePoint, PlacePointOffset = GetPrePointJoint(DestPose, LiftingHeight)
    if PalletNumber.LayerSheet.Enable == true then
        local CLSPoint = { joint = {} }
        CLSPoint = DeepCopy(PalletNumber.LayerSheet.SafePoint.Forward.joint[1])
        PartPoint = PositiveKin(CLSPoint,
            {
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            })
        PartPoint.pose[3] = PartPoint.pose[3] - LiftingHeight
        PlacePointOffset.pose = DeepCopy(PartPoint.pose)
    end
    PalletNumber.NearFlag = true
    PlaceJointOffset = PalletGetPose(PalletNumber, PlacePointOffset, 1)
    PalletNumber.NearFlag = false
    if PalletObstacleFunc == 1 and PalletNumber.TransPointMode == 1 then
        MovL(PlaceJointOffset, { a = 100, v = LDVel, cp = 100 })
    else
        MovJ(PlaceJointOffset, { a = 100, v = LDVel, cp = 100 })
    end
    PalletNumber.NearFlag = true
    PlaceJoint = PalletGetPose(PalletNumber, PlacePoint, 1)
    PalletNumber.NearFlag = false
    MovL(PlaceJoint, { a = 100, v = LDVel, cp = 100 }) --运动到抓取点
    if PalletNumber.LayerSheet.Enable == false then
        CalDePalletPlaceBoxNum(PalletNumber, NameStr)                        --执行托盘码垛计数
    else
        LayerSheetNum = LayerSheetNum + 1
        WriteRobotModbus(LayerSheetNum, FirstPallet.RegisterID.LayerSheetNum)
    end
    CloseVacuumCup(PalletNumber.BoxProperty.VacuumCup)

    MovL(PlaceJointOffset, { a = 100, v = NLDVel, cp = 100 }) --运动到抓取点上方
    local CurrentPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    CurrentPose = GetPose()
    PrePallet = Pallet
    PrePoseHeight = CurrentPose.pose[3] + ExAxisLiftingHeight
end

---------------------------------------------------------------
---------------------------------------------------------------
--拆垛放置动作
local function PlaceDePalletBoxAction(PalletNumber, DestPose, NameStr)
    ConveyorUserSwitch(PalletNumber, 1, Pallet, NameStr)
    GetPointInfo(PalletNumber, PointType.PickPoint, PalletNumber.PalletNum.NextBoxCount)
    LiftingPickPallet(PalletNumber, DestPose, 0, 0) --“升降轴”移动到指定位置
    GetPointInfo(PalletNumber, PointType.PickOffsetPoint, PalletNumber.PalletNum.NextBoxCount)
    if PalletNumber.LayerSheet.Enable == true then
        local CLSPoint = { joint = {} }
        CLSPoint = DeepCopy(PalletNumber.LayerSheet.SafePoint.Forward.joint[1])
        local PartPoint = PositiveKin(CLSPoint,
            {
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            })
        LiftingPickPallet(PalletNumber, PartPoint, 0, 0) --“升降轴”移动到指定位置
    else
        LiftingPickPallet(PalletNumber, DestPose, 0, 1)  --“升降轴”移动到指定位置
    end
    PlaceDePallet(PalletNumber, DestPose, ExAxisLiftingHeight, NameStr)
    ConveyorUserSwitch(PalletNumber, 0, Pallet, NameStr)
end

---------------------------------------------------------------
--拆垛取料动作
local function PickDePalletBoxAction(PalletNumber, DestPose, NameStr)
    PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(NameStr, Pallet)
    LastHeight = ExAxisLiftingHeight --“升降轴”移动到指定位置
    if (DestPose.pose[3] < HomePointPose.pose[3]) and (LastDestPose.pose[3] < HomePointPose.pose[3]) then
        ExAxisLiftingHeight = 0
    end
    LastDestPose.pose[3] = DestPose.pose[3]
    LiftingPickDePallet(PalletNumber, DestPose, NameStr)
    PickDePalletCal(PalletNumber, DestPose, ExAxisLiftingHeight, NameStr)
end

---------------------------------------------------------------
--取料箱动作
local function PickPalletBoxAction(PalletNumber, DestPickPose, DesePlacePose, NameStr)
    local LiftingHeight = ExAxisLiftingHeight

    if PalletLiftingFunction then
        LiftingPlacePallet(PalletNumber, DesePlacePose, NameStr) --“升降轴”移动到指定位置
    end
    --ConveyorUserSwitch(PalletNumber, 1, Pallet, NameStr)
    GetPointInfo(PalletNumber, PointType.PickPoint, PalletNumber.PalletNum.NextBoxCount)
    LiftingPickPallet(PalletNumber, DestPickPose, LiftingHeight - ExAxisLiftingHeight, 0) --“升降轴”移动到指定位置
    GetPointInfo(PalletNumber, PointType.PickOffsetPoint, PalletNumber.PalletNum.NextBoxCount)
    if PalletNumber.LayerSheet.Enable == true then
        local CLSPoint = { joint = {} }
        CLSPoint = DeepCopy(PalletNumber.LayerSheet.SafePoint.Forward.joint[1])
        local PartPoint = PositiveKin(CLSPoint,
            {
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            })
        LiftingPickPallet(PalletNumber, PartPoint, 0, 0)    --“升降轴”移动到指定位置
    else
        LiftingPickPallet(PalletNumber, DestPickPose, 0, 1) --“升降轴”移动到指定位置
    end
    PickPallet(PalletNumber, DestPickPose, ExAxisLiftingHeight)
    --ConveyorUserSwitch(PalletNumber, 0, Pallet, NameStr)
end

---------------------------------------------------------------
--放置料箱动作
local function PlacePalletBoxAction(PalletNumber, DestPose, NameStr)
    local LiftingHeight = 0
    PalletNumber.ProcessNum.TotalBoxNum = GetBoxCnt(NameStr, Pallet)
    LiftingHeight = ExAxisLiftingHeight
    LiftingPlacePallet(PalletNumber, DestPose, NameStr)
    if PalletLiftingFunction == true then
        AdjustLiftingHeight(ExAxisLiftingHeight, math.abs(ExAxisLiftingHeight - LiftingHeight))
    end
    PlacePallet(PalletNumber, DestPose, ExAxisLiftingHeight, NameStr)
end

---------------------------------------------------------------
---------------------------------------------------------------
--码垛主流程
local function PalletProcess()
    local SwitchPallet =
	{
        [0] = function()
            BoxPoseFP, PickPoseFP =
                GetPlacePositon(FirstPallet, PartPickPoseFP, PartPlacePoseFP, PalletName)
            PickPalletBoxAction(FirstPallet, PickPoseFP, BoxPoseFP, PalletName)
            PlacePalletBoxAction(FirstPallet, BoxPoseFP, PalletName)
		end,
        [1] = function()
            BoxPoseSP, PickPoseSP =
                GetPlacePositon(SecondPallet, PartPickPoseSP, PartPlacePoseSP, PalletName)
            PickPalletBoxAction(SecondPallet, PickPoseSP, BoxPoseSP, PalletName)
            PlacePalletBoxAction(SecondPallet, BoxPoseSP, PalletName)
        end
	}

    local switch_pallet = SwitchPallet[Pallet]
    if switch_pallet then
        switch_pallet()
    else
        print("The Pallet Is Wrong !")
        Pause()
    end
end

---------------------------------------------------------------
--拆垛主流程
local function DePalletProcess()
    local SwitchDePallet =
	{
        [0] = function()
            BoxPoseFP, PickPoseFP =
                GetPlacePositon(FirstPallet, PartPickPoseFP, PartPlacePoseFP, PalletName)
            PickDePalletBoxAction(FirstPallet, BoxPoseFP, PalletName)
            PlaceDePalletBoxAction(FirstPallet, PickPoseFP, PalletName)
		end,
        [1] = function()
            BoxPoseSP, PickPoseSP =
                GetPlacePositon(SecondPallet, PartPickPoseSP, PartPlacePoseSP, PalletName)
            PickDePalletBoxAction(SecondPallet, BoxPoseSP, PalletName)
            PlaceDePalletBoxAction(SecondPallet, PickPoseSP, PalletName)
		end
	}

    local switch_pallet = SwitchDePallet[Pallet]
    if switch_pallet then
        switch_pallet()
    else
        print("The Pallet Is Wrong !")
        Pause()
    end
end

---------------------------------------------------------------
---------------------------------------------------------------
--主程序
CreateModbusConnection()      --创建Modbus连接
InitPallet()

local SwitchPalletMode =
{
	[1] = function()
		PalletProcess()
	end,
	[2] = function()
		DePalletProcess()
	end
}
local switch_mode
while true do
    Wait(Time.Thread.s0)
    if (PalletNumInitFlag == true)
        and (IsReady == true)
        and (PalletChosenFlag == true)
        and (FilmFlag == true) then
        PalletChosenFlag = false
        if Pallet == 0 then
            switch_mode = SwitchPalletMode[FirstPallet.PalletMode]
        else
            switch_mode = SwitchPalletMode[SecondPallet.PalletMode]
        end
        if switch_mode then
            switch_mode()
        else
            print("The SwitchPalletMode is error, please check it!")
            Pause()
        end
        PalletFinishFlag = true
    end
end
