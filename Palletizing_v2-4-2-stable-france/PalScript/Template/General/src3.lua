--------------------------------------------------------------
-- 点位计算文件
-- point calculation file
-- 本文件根据插件配方、箱型、层数、吸盘模式和隔板配置生成CPoint。
---------------------------------------------------------------
-- 点位计算文件双语注释说明
-- 本文件根据配方、箱型、层数、吸盘模式和隔板配置生成CPoint，供src0执行运动。
-- MotionPoint索引很重要：1~5为过渡点，6为取料点，7为取料上方点，8~11为放置点，12~15为放置上方点，16~19为插入/偏移点。
-- 隔板逻辑额外保护J6：示教J6和回程J6不能被普通逆解逻辑随意改写，否则可能产生腕部奇异或关节限位问题。
-- Point calculation file bilingual comment guide
-- This file generates CPoint from recipe data, box dimensions, layer index, sucker mode, and partition configuration. src0 uses CPoint to execute motion.
-- MotionPoint indexes are critical: 1~5 transition points, 6 pick point, 7 pick-offset point, 8~11 place points, 12~15 place-offset points, and 16~19 insert/offset points.
-- Partition motion adds extra J6 protection: taught J6 and return-path J6 should not be overwritten by normal inverse-kinematics logic, otherwise wrist singularity or joint-limit issues may occur.
---------------------------------------------------------------
-- CPoint是src0执行运动的输入，包含：
-- 1. Paras：动作类型、吸盘模式、动作次数、过渡点数量等；
-- 2. MotionPoint：取料点、放料点、上方点、过渡点；
-- 3. BackwardMotionPoint：回程专用过渡点，主要用于控制隔板回程的J6分支。
--------------------------------------------------------------
-- 局部常量
-- local constants
local BufLen = 10
--------------------------------------------------------------
-- 局部变量
-- local variables
local OffSet =
{
    {}
}
local Point =
{
    Pose = {}
}

-- 单笔运动结果模板。
-- template for one calculated motion result
-- 每次计算点位时都会把当前动作需要的参数写入Res，再压入运动队列。
local Res =
{
    Standy = {},  --待机位置
    OffSet = {},  --偏移标志位
    LH = 0,       --升降高度
    Mode = 0,     --点位类型，0：常规点位，1：隔板运动点位
    Sucker = 0,   --吸盘信号，-1：n吸n单放，0：n吸单放，1：长边对齐双放，2：短边对齐双放，3：长边对齐三放，4：短边对齐三放，5：长边对齐四放，:6：短边对齐四放
    Times = 1,    --运动次数
    TransNum = 1, --过渡点数量
    ErrIndex = 0  --不可达点位序号，0：可达，1~10：对应不可达点位
}


-- 普通箱取料点J1接近±180°时视为侧面取料。
-- 只能使用客户示教关节判断，不能使用GetInvK结果判断。
local SidePickJ1Threshold = 135
local PathJ1SafeMin = -60
local PathJ1SafeMax = 200
local PathJ6SoftMin = -360
local PathJ6SoftMax = 360
local PathJ1MaxSegment = 150

local function WrapAngle180(Angle)
    if type(Angle) ~= "number" then
        return nil
    end
    while Angle > 180 do
        Angle = Angle - 360
    end
    while Angle <= -180 do
        Angle = Angle + 360
    end
    return Angle
end

local function IsSidePickJoint(Joint)
    if (type(Joint) ~= "table") or (type(Joint[1]) ~= "number") then
        return false
    end
    local WrappedJ1 = WrapAngle180(Joint[1])
    return (WrappedJ1 ~= nil) and (math.abs(WrappedJ1) >= SidePickJ1Threshold)
end

local function SelectEquivalentAngle(Value, ReferenceValue, MinValue, MaxValue)
    if type(Value) ~= "number" then
        return nil
    end
    if type(ReferenceValue) ~= "number" then
        ReferenceValue = Value
    end
    local BestValue = nil
    local BestDiff = nil
    for K = -3, 3 do
        local Candidate = Value + 360 * K
        if (Candidate >= MinValue) and (Candidate <= MaxValue) then
            local Diff = math.abs(Candidate - ReferenceValue)
            if (BestValue == nil) or (Diff < BestDiff) then
                BestValue = Candidate
                BestDiff = Diff
            end
        end
    end
    return BestValue
end

local function GetPointJoint(PointData)
    if (type(PointData) == "table") and (type(PointData.joint) == "table") then
        return PointData.joint
    end
    return nil
end

local function LogSidePointDebug(Label, PointData)
    if type(PointData) ~= "table" then
        LogWarn("%s is not a table: %s", tostring(Label), tostring(PointData))
        return
    end
    if PointData.joint ~= nil then
        LogInfoTable(tostring(Label) .. ".joint:", PointData.joint)
    else
        LogWarn("%s.joint is nil", tostring(Label))
    end
    if PointData.pose ~= nil then
        LogInfoTable(tostring(Label) .. ".pose:", PointData.pose)
    else
        LogWarn("%s.pose is nil", tostring(Label))
    end
end

local function LogSidePickFailure(Context, PointData, RefPoint, FixedJ1, FixedJ6, Reason)
    LogError("[SidePickDebug] %s failed: %s", tostring(Context), tostring(Reason))
    LogSidePointDebug("[SidePickDebug] target", PointData)
    LogSidePointDebug("[SidePickDebug] reference", RefPoint)

    local CurrentAngle = GetAngle()
    if CurrentAngle ~= nil then
        LogSidePointDebug("[SidePickDebug] current angle", CurrentAngle)
    else
        LogWarn("[SidePickDebug] current angle is nil")
    end

    local CurrentPose = GetPose()
    if CurrentPose ~= nil then
        LogSidePointDebug("[SidePickDebug] current pose", CurrentPose)
    else
        LogWarn("[SidePickDebug] current pose is nil")
    end

    if FixedJ1 ~= nil then
        LogInfo("[SidePickDebug] fixed J1 candidate: %s", tostring(FixedJ1))
    end
    if FixedJ6 ~= nil then
        LogInfo("[SidePickDebug] fixed J6 candidate: %s", tostring(FixedJ6))
    end
end

local function NormalizeSidePoint(PointData, RefPoint)
    local P = DeepCopy(PointData)
    local Joint = GetPointJoint(P)
    local RefJoint = GetPointJoint(RefPoint)
    if Joint == nil then
        LogSidePickFailure("NormalizeSidePoint", PointData, RefPoint, nil, nil, "target joint is nil")
        return nil
    end
    local RefJ1 = RefJoint and RefJoint[1] or Joint[1]
    local RefJ6 = RefJoint and RefJoint[6] or Joint[6]
    local FixedJ1 = SelectEquivalentAngle(Joint[1], RefJ1, PathJ1SafeMin, PathJ1SafeMax)
    local FixedJ6 = SelectEquivalentAngle(Joint[6], RefJ6, PathJ6SoftMin, PathJ6SoftMax)
    if (FixedJ1 == nil) or (FixedJ6 == nil) then
        LogSidePickFailure("NormalizeSidePoint", PointData, RefPoint, FixedJ1, FixedJ6,
            "J1 or J6 cannot be normalized into safe range")
        return nil
    end
    if (RefJoint ~= nil) and (math.abs(FixedJ1 - RefJ1) > PathJ1MaxSegment) then
        LogSidePickFailure("NormalizeSidePoint", PointData, RefPoint, FixedJ1, FixedJ6,
            "J1 segment delta exceeds limit")
        LogError("[SidePickDebug] J1 delta: %s, limit: %s", tostring(math.abs(FixedJ1 - RefJ1)),
            tostring(PathJ1MaxSegment))
        return nil
    end
    Joint[1] = FixedJ1
    Joint[6] = FixedJ6
    return P
end

local function SetSidePickPointErrorInfo(CData, PalletNumber, PointCfg, PointIndex)
    if (CData ~= nil) and (CData.Pallet ~= nil) then
        ErrorMessage.PointInfo.PalletNum = CData.Pallet
    end
    if (PalletNumber ~= nil) and (PalletNumber.PalletNum ~= nil) then
        ErrorMessage.PointInfo.Layer = PalletNumber.PalletNum.LayerCount
    end
    if PointCfg ~= nil then
        ErrorMessage.PointInfo.Type = PointCfg
    end
    if PointIndex ~= nil then
        ErrorMessage.PointInfo.Index = PointIndex
    end
    LogInfo("Side Pick point error info - pallet: %s, type: %s, layer: %s, index: %s",
        tostring(ErrorMessage.PointInfo.PalletNum), tostring(ErrorMessage.PointInfo.Type),
        tostring(ErrorMessage.PointInfo.Layer), tostring(ErrorMessage.PointInfo.Index))
end

local function CreatePalletData(PalletType)
    return {
        Num = 0,
        Index = 0,
        Init = false,
        FMotion = false,
        CompNum = 0,
        PartNum = {},
        PartIndex = 0,
        TPartIndex = 0,
        Pick = { pose = {} },
        Standy = { pose = {} },
        PartPick = { pose = {} },
        PartPlace = { pose = {} },
        PickTeachJoint = nil,
        SidePick = false,
        PartPickTeachJ6 = nil, --隔板取料示教点J6，用于保持MotionPoint[6]的第6轴不被逆解改写
        PartTransTeachJ6 = {}, --隔板示教过渡点J6，用于保持MotionPoint[1~5]的第6轴不被改写
        Pallet = PalletType,
        User = 0,
        Tool = {
            Conc = 0,    --同心工具号
            Ecc = {},    --偏心工具号
            EccData = {} --偏心数据
        }
    }
end

local FData = CreatePalletData(Left)
local SData = CreatePalletData(Right)

--------------------------------------------------------------
--初始化隔板数量。
-- 根据配方中每层是否需要隔板，计算本托盘理论需要的隔板总数。
-- 码垛和拆垛方向相反，所以首尾隔板的计算方式不同。
local function InitPartition(PalletNumber, CData)
    if (PalletNumber.Partition.Enable == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            if (PalletNumber.ProcessNum.BoxCount ~= 0) then
                for i = 1, PalletNumber.PalletNum.LayerCount do
                    CData.PartIndex = CData.PartIndex + PalletNumber.Partition.Layer[i]
                end
            end
        else
            for i = 1, PalletNumber.PalletNum.LayerCount + 1 do
                CData.PartIndex = CData.PartIndex + PalletNumber.Partition.Layer[i]
            end
        end
        if (PalletNumber.Partition.Place == 1) then
            if (PalletNumber.Mode == WorkType.Pallet) then
                CData.PartIndex = CData.PartIndex + 1
            else
                CData.PartIndex = CData.PartIndex - 1
            end
        end
        LogInfo("Données des intercalaires : index = %s", CData.PartIndex)
        LogDebugTable("Données des intercalaires : couches :", CData.PartNum)
    end
end
--------------------------------------------------------------
--获取当前动作对应的数据序号。
-- 普通箱子使用箱体序号；隔板动作使用隔板序号。
-- 这个序号会决定从插件配方中读取哪一个自动生成点位。
local function GetDataIndex(PalletNumber, CData)
    local LNum = 0
    for i = 1, PalletNumber.Layer + 1 do
        if (PalletNumber.Partition.Enable == true) then
            if (PalletNumber.Partition.Layer[i] == 1) then
                CData.TPartIndex = CData.TPartIndex + 1
                CData.PartNum[CData.TPartIndex] = LNum + CData.TPartIndex
            end
        end
        if (i <= PalletNumber.Layer) then
            LNum = LNum + GetOddBoxCnt(PalletName, CData.Pallet, i)
            if (i == PalletNumber.CompensateLayer) then
                if (i == 1) then
                    CData.CompNum = 0
                else
                    CData.CompNum = LNum
                end
            end
        end
    end
    InitPartition(PalletNumber, CData)

    CData.Num = GetBoxCnt(PalletName, CData.Pallet)
    if PalletNumber.Partition.Last == true then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.Index = CData.Num
        else
            CData.Index = 1
        end
        PalletNumber.Partition.LastPlan = true
    else
        CData.Index = PalletNumber.PalletNum.NextBoxCount
    end
end
---------------------------------------------------------------
-- 获取点位数据
-- read point data
local function GetTeachPoint(PalletNumber, CData)
    if (CData.Init == false) then
        GetDataIndex(PalletNumber, CData)

        CData.User = PalletNumber.Coordinate.UserNum
        CData.Tool.Conc = PalletNumber.Coordinate.ToolNum
        --local EccTool = {}
        --if (PalletSuckerFunction > 1) then
        --    CData.Tool.Ecc, EccTool, CData.Tool.EccData = GetPalletTool(PalletName, ToolType.Ecc)
        --end

        local ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPickPoint.joint)
        if (ProjectType == 1) then
            local PickJoint = { joint = {} }
            PickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPickPoint.joint)
            CData.PickTeachJoint = DeepCopy(PickJoint.joint)
            CData.SidePick = IsSidePickJoint(CData.PickTeachJoint)
            CData.Pick = PositiveKin(PickJoint, { user = CData.User, tool = CData.Tool.Conc })
            CData.Standy = PositiveKin(PickJoint)
            CData.Standy.pose[3] = CData.Standy.pose[3] + TeachPointOffHeight
        else
            CData.PickTeachJoint = nil
            CData.SidePick = false
            CData.Pick.pose = DeepCopy(PalletNumber.TeachPoint.TeachPickPoint.pose)
            CData.Pick.pose[3] = CData.Pick.pose[3] - PalletNumber.ProcessNum.PalletHeight
            CData.Standy = GetAddUserPos(PalletNumber.Coordinate.UserNum, 0, CData.Pick)
            CData.Standy.pose[3] = CData.Standy.pose[3] + TeachPointOffHeight
        end
        if (PalletNumber.Partition.Enable == true) then
            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
            if (ProjectType == 1) then
                local PartPickJoint = { joint = {} }
                PartPickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
                CData.PartPickTeachJ6 = PartPickJoint.joint[6]
                CData.PartPick = PositiveKin(PartPickJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.PartPickTeachJ6 = nil
                CData.PartPick.pose = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.pose)
                CData.PartPick.pose[3] = CData.PartPick.pose[3] - PalletNumber.ProcessNum.PalletHeight
            end

            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPartitionPlacePoint.joint)
            if (ProjectType == 1) then
                local PartPlaceJoint = { joint = {} }
                PartPlaceJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPlacePoint.joint)
                CData.PartPlace = PositiveKin(PartPlaceJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.PartPlace.pose = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPlacePoint.pose)
                CData.PartPlace.pose[3] = CData.PartPlace.pose[3] - PalletNumber.ProcessNum.PalletHeight
            end

            --保存隔板示教过渡点J6，避免后续统一改成放置点J6
            CData.PartTransTeachJ6 = {}
            for i = 1, PalletNumber.TransPartitionPointNum do
                if (PalletNumber.TeachPoint.TransPartitionPoint.joint[i] ~= nil)
                    and (CheckTableData(PalletNumber.TeachPoint.TransPartitionPoint.joint[i]) == 1) then
                    CData.PartTransTeachJ6[i] = PalletNumber.TeachPoint.TransPartitionPoint.joint[i][6]
                else
                    CData.PartTransTeachJ6[i] = nil
                end
            end
        end
        CData.Init = true
        LogInfo("Initialisation de la file %s terminée !", (CData.Pallet == Left) and "gauche" or "droite")
    end
end
-----------------------------------------------------------------
-- 获取点位模式
-- get point mode
local function GetPointMode(PalletNumber, CData)
    if (PalletNumber.Partition.Enable == true) then
        Res.Mode = MotionType.Norm
        local CPartIndex = 0
        LogDebug("CData.Index = %s, CData.PartIndex = %s", CData.Index, CData.PartIndex)
        if (PalletNumber.Mode == WorkType.Pallet) then
            CPartIndex = CData.PartIndex + 1
        else
            CPartIndex = CData.PartIndex
        end
        if (CData.Index + CData.PartIndex == CData.PartNum[CPartIndex]) or (PalletNumber.Partition.LastPlan == true) then
            Res.Mode = MotionType.Part
        end
    end
end
----------------------------------------------------------------
-- 计算偏心位置坐标
-- calculate eccentric position coordinates
local function GetEccPoint(CData, CPose)
    if (Res.Mode == MotionType.Norm
            and (PalletSuckerFunction == SuckerCfg.Type.Double
                or PalletSuckerFunction == SuckerCfg.Type.Triple
                or PalletSuckerFunction == SuckerCfg.Type.Quadruple)) then
        local SwitchFSM =
        {
            [SuckerCfg.Type.Double] = function()
                if Res.Sucker == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
            end,
            [SuckerCfg.Type.Triple] = function()
                if Res.Sucker == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
                if Res.Sucker == 1 or Res.Sucker == 2 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[3][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[3][2]
                end
            end,
            [SuckerCfg.Type.Quadruple] = function()
                if Res.Sucker == 0 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[2][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[2][2]
                end
                if Res.Sucker == 1 or Res.Sucker == 2 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[3][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[3][2]
                end
                if Res.Sucker == 3 or Res.Sucker == 4 then
                    CPose[1] = CPose[1] + CData.Tool.EccData[4][1]
                    CPose[2] = CPose[2] + CData.Tool.EccData[4][2]
                end
            end
        }

        local switch_mode = SwitchFSM[PalletSuckerFunction]
        if switch_mode then
            switch_mode()
        else
            Alarm("Le type de ventouse est incorrect !", ErrorMessage.Type.WorkingDataErr)
        end
    end

    return CPose
end
----------------------------------------------------------------
-- 计算取放位置
-- calculate pick/place positions
local function GetPickPlacePoint(PalletNumber, CData)
    local PickPose = { pose = { 0, 0, 0, 0, 0, 0 } }
    local PlacePose = { pose = { 0, 0, 0, 0, 0, 0 } }
    local TempPose = { pose = { 0, 0, 0, 0, 0, 0 } }

    GetPointMode(PalletNumber, CData)
    OffSet[1], Res.Sucker = GetBoxProPerty(PalletName, CData.Pallet, CData.Index)
    if (Res.Mode == MotionType.Part) or (Res.Sucker >= 0) then
        Res.Times = 1
    else
        Res.Times = math.abs(PalletSuckerFunction)
    end
    for i = 1, Res.Times do
        if (Res.Mode == MotionType.Part) then
            PickPose = DeepCopy(CData.PartPick)
            PlacePose = DeepCopy(CData.PartPlace)
            TempPose = GetBoxPos(PalletName, CData.Pallet, CData.Index)
            if (PalletNumber.Partition.LastPlan == false and PalletNumber.Mode == WorkType.Pallet)
                or (PalletNumber.Partition.LastPlan == true and PalletNumber.Mode == WorkType.Depallet) then
                PlacePose.pose[3] = TempPose.pose[3] - PalletNumber.BoxProperty.BoxHigh
            else
                PlacePose.pose[3] = TempPose.pose[3] + PalletNumber.ProcessNum.PartitionHeight
            end
        else
            PickPose = DeepCopy(CData.Pick)
            if (PalletNumber.Mode == WorkType.Pallet) then
                PlacePose = GetBoxPos(PalletName, CData.Pallet, CData.Index + i - 1)
            else
                PlacePose = GetBoxPos(PalletName, CData.Pallet, CData.Index - i + 1)
            end
        end
        if (CData.Index > CData.CompNum) then
            PlacePose.pose[3] = PlacePose.pose[3] - PalletNumber.CompensateZData
        end
        --隔板放置点比原始计算点抬高30mm。隔板较软，在高于理论位置处释放后自然飘落。
        if (Res.Mode == MotionType.Part) then
            PlacePose.pose[3] = PlacePose.pose[3] + 30
        end
        if (PalletNumber.Mode == WorkType.Pallet) then
            OffSet[i], Res.Sucker = GetBoxProPerty(PalletName, CData.Pallet, CData.Index + i - 1)
            if (OffSet[i][1] == 0) and (OffSet[i][2] == 0) then
                Res.OffSet[i] = 0
            else
                Res.OffSet[i] = 1
            end
            Point.Pose[7 + i] = DeepCopy(PlacePose.pose)
        else
            local CIndex = Res.Times - i + 1
            OffSet[CIndex], Res.Sucker = GetBoxProPerty(PalletName, CData.Pallet, CData.Index - i + 1)
            if (OffSet[CIndex][1] == 0) and (OffSet[CIndex][2] == 0) then
                Res.OffSet[CIndex] = 0
            else
                Res.OffSet[CIndex] = 1
            end
            Point.Pose[7 + CIndex] = DeepCopy(PlacePose.pose)
        end
        --PickPose.pose = GetEccPoint(CData, PickPose.pose)
    end

    Point.Pose[6] = DeepCopy(PickPose.pose)
    Res.Standy = DeepCopy(CData.Standy)
end
---------------------------------------------------------------
-- 选择自动过渡点
-- select automatically generated transition point
local function GetAutoGenPoint(PalletNumber, CData)
    local TPoint = { pose = {} }

    if Res.Mode == MotionType.Part then
        if (PalletNumber.Mode == WorkType.Pallet) then
            TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.PartTransPoint[CData.PartIndex + 1])
        else
            TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.PartTransPoint[CData.PartIndex])
        end
    else
        TPoint.pose = DeepCopy(PalletNumber.AutoGenPoint.TransPoint[CData.Index])
    end

    Res.TransNum = CheckTableData(TPoint.pose)
    if Res.TransNum > 0 then
        TPoint = GetAddUserPos(0, PalletNumber.Coordinate.UserNum, TPoint)
        if Res.Mode == MotionType.Part then
            --隔板自动过渡点固定为放置点上方100mm，避免沿用过高的示教/自动点Z
            TPoint.pose[3] = Point.Pose[8][3] + 100
        else
            TPoint.pose[6] = Point.Pose[8][6] --常规过渡点与放置姿态一致
        end
        Point.Pose[1] = DeepCopy(TPoint.pose)
    else
        Point.Pose[1] = { 0, 0, 0, 0, 0, 0 }
    end
end
---------------------------------------------------------------
-- 选择示教过渡点
-- select taught transition point
local function GetTransPoint(PalletNumber)
    local CopyPoint = {}
    if Res.Mode == MotionType.Part then
        Res.TransNum = PalletNumber.TransPartitionPointNum
        CopyPoint = DeepCopy(PalletNumber.TeachPoint.TransPartitionPoint)
    else
        Res.TransNum = PalletNumber.TransPlacePointNum
        CopyPoint = DeepCopy(PalletNumber.TeachPoint.TransPlacePoint)
    end
    local PHeight = Point.Pose[6][3] + TeachPointOffHeight
    local THeight = 0
    if Res.Mode == MotionType.Part then
        --隔板示教过渡点参考放置点：最后一个过渡点固定为放置点上方200mm
        THeight = Point.Pose[8][3] + 200
    else
        --常规箱子过渡点保持原逻辑
        THeight = Point.Pose[8][3] + PalletNumber.OffsetHeight + OffSet[1][3]
    end

    for i = 1, Res.TransNum do
        if Res.Mode ~= MotionType.Part then
            CopyPoint.pose[i][6] = Point.Pose[8][6] --常规过渡点与放置姿态一致
        end

        if Res.Mode == MotionType.Part then
            --隔板最后一个示教过渡点必须贴近放置点，固定为放置点上方200mm
            --这里不再受CopyPoint.mode[i]限制，也不再用PHeight抬高
            if i == Res.TransNum then
                CopyPoint.pose[i][3] = THeight
            elseif (CopyPoint.mode[i] == 0) and (CopyPoint.pose[i][3] <= THeight) then
                CopyPoint.pose[i][3] = THeight
            end
        else
            if CopyPoint.mode[i] == 0 then
                if CopyPoint.pose[i][3] <= THeight then
                    CopyPoint.pose[i][3] = THeight
                end

                if CopyPoint.pose[i][3] <= PHeight then
                    CopyPoint.pose[i][3] = PHeight
                end
            end
        end

        Point.Pose[i] = DeepCopy(CopyPoint.pose[i])
    end
end

---------------------------------------------------------------
-- 计算放料位置
-- calculate place position
local function GetInterPoint(PalletNumber)
    local PreTrans = { pose = {} }
    local PreOffset = { pose = {} }
    local PrePoint = { pose = {} }

    if Res.Mode == MotionType.Part then
        PrePoint = PositiveKin(PartSafePoint,
            {
                user = PalletNumber.Coordinate.UserNum,
                tool = PalletNumber.Coordinate.ToolNum
            })
    else
        PrePoint.pose = DeepCopy(Point.Pose[6])
        PrePoint.pose[3] = PrePoint.pose[3] + TeachPointOffHeight -- 取料上方点
        -- pick-offset point above pick position
    end
    Point.Pose[7] = DeepCopy(PrePoint.pose)

    for i = 1, Res.Times do
        PreTrans.pose = DeepCopy(Point.Pose[7 + i])
        PreTrans.pose[1] = PreTrans.pose[1] + OffSet[i][1]
        PreTrans.pose[2] = PreTrans.pose[2] + OffSet[i][2]
        PreTrans.pose[3] = PreTrans.pose[3] + OffSet[i][3] + PalletNumber.OffsetHeight

        PreOffset.pose = DeepCopy(Point.Pose[7 + i])
        if (Res.OffSet[i] == 0) then
            PreOffset.pose[3] = PreOffset.pose[3] + OffSet[i][3] + PalletNumber.OffsetHeight
        else
            PreOffset.pose[3] = PreOffset.pose[3] + PalletNumber.OffsetHeight
        end
        Point.Pose[15 + i] = DeepCopy(PreTrans.pose)
        Point.Pose[11 + i] = DeepCopy(PreOffset.pose)
    end
end

-----------------------------------------------------------------
--MotionPoint索引说明：
--1~5:过渡点（示教），6:取料（示教），7：取料上方点（自动生成），8~11：放置点（自动生成）
--12~15：放料上方点（自动生成），16~19：放料偏移点（自动生成）
-----------------------------------------------------------------
-- 获取点位结果
-- get point calculation result
local function GetResult(CData, PalletNumber)
    local Ret = { MotionPoint = {}, ForwardMotionPoint = {}, BackwardMotionPoint = {}, Paras = {} }
    local ToolNum = 0
    local CJoint = {}
    local BackwardTransJ6 = nil
    local StandyJoint = nil
    if (Res.Mode == MotionType.Part) then
        ToolNum = math.abs(PalletSuckerFunction) - 1
    else
        if (Res.Sucker >= 0) then
            ToolNum = math.ceil(Res.Sucker * 0.5)
        else
            ToolNum = Res.Sucker
        end
    end
    CJoint, Res.LH, Res.ErrIndex = GetInvK(PalletName, CData.Pallet, Point.Pose, ToolNum)

    --隔板回程过渡点使用终点待机点的J6；去程过渡点仍保持示教J6
    if (Res.Mode == MotionType.Part) and (Res.Standy ~= nil) and (Res.Standy.pose ~= nil) then
        local Standy = { pose = {} }
        Standy.pose = DeepCopy(Res.Standy.pose)
        Standy.pose[3] = Standy.pose[3] - Res.LH
        local ErrId = 0
        ErrId, StandyJoint = InverseKin(Standy)
        if (ErrId == 0) and (StandyJoint ~= nil) and (StandyJoint.joint ~= nil) then
            BackwardTransJ6 = StandyJoint.joint[6]
            Ret.StandyMotionPoint = DeepCopy(StandyJoint)
        else
            LogWarn("Échec de la cinématique inverse pour l’attente de l’intercalaire ; le J6 du retour conservera la valeur du trajet aller !")
        end
    end

    for i = 1, 19 do
        Ret.MotionPoint[i] = { joint = CJoint[i] }
        if (i < 6) then
            if (Res.Mode == MotionType.Part) then
                if (CData.PartTransTeachJ6 ~= nil) and (CData.PartTransTeachJ6[i] ~= nil) then
                    Ret.MotionPoint[i].joint[6] = CData.PartTransTeachJ6[i]
                end
            elseif CData.SidePick ~= true then
                -- 正面取料严格保持原始不卡版：所有普通箱过渡点统一使用放置A点J6。
                Ret.MotionPoint[i].joint[6] = CJoint[8][6]
            end
        end
        if (i == 12 or i == 16) then
            Ret.MotionPoint[i].joint[6] = CJoint[8][6]
        end
        if (i == 13 or i == 17) then
            Ret.MotionPoint[i].joint[6] = CJoint[9][6]
        end
        if (i == 14 or i == 18) then
            Ret.MotionPoint[i].joint[6] = CJoint[10][6]
        end
        if (i == 15 or i == 19) then
            Ret.MotionPoint[i].joint[6] = CJoint[11][6]
        end
    end

    --隔板回程过渡点副本：J1~J5保持逆解，J6统一改为待机点终点J6
    if (Res.Mode == MotionType.Part) then
        for i = 1, Res.TransNum do
            if (type(Ret.MotionPoint[i]) == "table") then
                Ret.BackwardMotionPoint[i] = DeepCopy(Ret.MotionPoint[i])
                if (BackwardTransJ6 ~= nil) and (Ret.BackwardMotionPoint[i].joint ~= nil) then
                    Ret.BackwardMotionPoint[i].joint[6] = BackwardTransJ6
                end
            end
        end
    end

    --隔板取料点[6]保持示教时的J6，避免逆解重新选择第6轴角度
    if (Res.Mode == MotionType.Part) and (CData.PartPickTeachJ6 ~= nil) then
        Ret.MotionPoint[6].joint[6] = CData.PartPickTeachJ6
    end

    if (Res.Mode == MotionType.Norm) and (CData.SidePick == true) then
        -- Side Pick使用客户示教取料关节作为整条路径的起始分支。
        -- 所有实际运动点均按执行顺序连续化J1/J6：
        -- 6取料 -> 7取料上方 -> 1~N去程 -> 16~19偏移 -> 12~15放置上方
        -- -> 8~11放置 -> 放置上方/偏移返回 -> N~1回程 -> 7取料上方。
        if type(CData.PickTeachJoint) ~= "table" then
            SetSidePickPointErrorInfo(CData, PalletNumber, PointType.Pick.Cfg.Norm, PointType.Pick.Index.A)
            Alarm("Point de prise latérale invalide !", ErrorMessage.Type.PointErr)
            return nil
        end

        Ret.MotionPoint[6].joint = DeepCopy(CData.PickTeachJoint)
        local RefPoint = Ret.MotionPoint[6]

        local PickOffset = NormalizeSidePoint(Ret.MotionPoint[7], RefPoint)
        if PickOffset == nil then
            LogError("Trajectoire Side Pick invalide entre la prise et le point supérieur !")
            SetSidePickPointErrorInfo(CData, PalletNumber, PointType.PickOffset.Cfg.Norm, PointType.PickOffset.Index.A)
            Alarm("Trajectoire de prise latérale invalide !", ErrorMessage.Type.PointErr)
            return nil
        end
        Ret.MotionPoint[7] = PickOffset
        RefPoint = PickOffset

        -- 去程过渡点1~N。
        for i = 1, Res.TransNum do
            local P = NormalizeSidePoint(Ret.MotionPoint[i], RefPoint)
            if P == nil then
                LogError("Transition aller Side Pick invalide : index %d", i)
                LogInfo("[SidePickDebug] PalletName=%s, Pallet=%s, Index=%s, TransNum=%s, Times=%s",
                    tostring(PalletName), tostring(CData.Pallet), tostring(CData.Index), tostring(Res.TransNum),
                    tostring(Res.Times))
                LogSidePointDebug("[SidePickDebug] failed forward transition point", Ret.MotionPoint[i])
                LogSidePointDebug("[SidePickDebug] failed forward transition reference", RefPoint)
                SetSidePickPointErrorInfo(CData, PalletNumber, PointType.Trans.Cfg.Norm, i)
                Alarm("Trajectoire de transition latérale invalide !", ErrorMessage.Type.PointErr)
                return nil
            end
            Ret.ForwardMotionPoint[i] = P
            RefPoint = P
        end

        -- 放置区域的全部实际运动点。
        for i = 1, Res.Times do
            local InsertIndex = 15 + i
            local AboveIndex = 11 + i
            local PlaceIndex = 7 + i

            if Res.OffSet[i] == 1 then
                local InsertPoint = NormalizeSidePoint(Ret.MotionPoint[InsertIndex], RefPoint)
                if InsertPoint == nil then
                    LogError("Point de décalage Side Pick invalide : index %d", InsertIndex)
                    SetSidePickPointErrorInfo(CData, PalletNumber, PointType.Insert.Cfg.Norm, InsertIndex)
                    Alarm("Point de décalage Side Pick invalide !", ErrorMessage.Type.PointErr)
                    return nil
                end
                Ret.MotionPoint[InsertIndex] = InsertPoint
                RefPoint = InsertPoint
            end

            local AbovePoint = NormalizeSidePoint(Ret.MotionPoint[AboveIndex], RefPoint)
            if AbovePoint == nil then
                LogError("Point supérieur de dépose Side Pick invalide : index %d", AboveIndex)
                SetSidePickPointErrorInfo(CData, PalletNumber, PointType.PlaceOffset.Cfg.Norm, AboveIndex)
                Alarm("Point supérieur de dépose Side Pick invalide !", ErrorMessage.Type.PointErr)
                return nil
            end
            Ret.MotionPoint[AboveIndex] = AbovePoint

            local PlacePoint = NormalizeSidePoint(Ret.MotionPoint[PlaceIndex], AbovePoint)
            if PlacePoint == nil then
                LogError("Point de dépose Side Pick invalide : index %d", PlaceIndex)
                SetSidePickPointErrorInfo(CData, PalletNumber, PointType.Place.Cfg.Norm, PlaceIndex)
                Alarm("Point de dépose Side Pick invalide !", ErrorMessage.Type.PointErr)
                return nil
            end
            Ret.MotionPoint[PlaceIndex] = PlacePoint

            -- 放置后src0先回AbovePoint。
            RefPoint = AbovePoint

            -- 多吸流程才会从AbovePoint返回偏移点。
            -- 当前单吸项目Times==1时不会执行此段，但仍预先验证以保留feature。
            if (Res.Times ~= 1) and (Res.OffSet[i] == 1) then
                local ReturnInsert = NormalizeSidePoint(Ret.MotionPoint[InsertIndex], RefPoint)
                if ReturnInsert == nil then
                    LogError("Retour au point de décalage Side Pick invalide : index %d", InsertIndex)
                    SetSidePickPointErrorInfo(CData, PalletNumber, PointType.Insert.Cfg.Norm, InsertIndex)
                    Alarm("Retour Side Pick invalide !", ErrorMessage.Type.PointErr)
                    return nil
                end
                Ret.MotionPoint[InsertIndex] = ReturnInsert
                RefPoint = ReturnInsert
            end
        end

        -- 回程过渡点按放置端当前分支重新连续化，不能简单复制去程角度。
        for i = Res.TransNum, 1, -1 do
            local P = NormalizeSidePoint(Ret.ForwardMotionPoint[i], RefPoint)
            if P == nil then
                LogError("Transition retour Side Pick invalide : index %d", i)
                SetSidePickPointErrorInfo(CData, PalletNumber, PointType.Trans.Cfg.Norm, i)
                Alarm("Trajectoire retour Side Pick invalide !", ErrorMessage.Type.PointErr)
                return nil
            end
            Ret.BackwardMotionPoint[i] = P
            RefPoint = P
        end

        -- 最后一个回程点到取料上方点也必须连续。
        local FinalPickOffset = NormalizeSidePoint(Ret.MotionPoint[7], RefPoint)
        if FinalPickOffset == nil then
            LogError("Retour Side Pick vers le point supérieur de prise invalide !")
            SetSidePickPointErrorInfo(CData, PalletNumber, PointType.PickOffset.Cfg.Norm, PointType.PickOffset.Index.A)
            Alarm("Retour Side Pick invalide !", ErrorMessage.Type.PointErr)
            return nil
        end
        Ret.MotionPoint[7] = FinalPickOffset
    elseif Res.Mode == MotionType.Norm then
        -- 正面取料不做任何J1/J6安全分支搜索，完全复用原始MotionPoint。
        for i = 1, Res.TransNum do
            Ret.ForwardMotionPoint[i] = DeepCopy(Ret.MotionPoint[i])
            Ret.BackwardMotionPoint[i] = DeepCopy(Ret.MotionPoint[i])
        end
    end

    Ret.Paras = DeepCopy(Res)
    Ret.Paras.BackwardTransJ6 = BackwardTransJ6
    Ret.Paras.SidePick = CData.SidePick
    return Ret
end

-----------------------------------------------------------------
--获取点位
local function GetPoint(PalletNumber, CData)
    local CPoint = {}
    GetPickPlacePoint(PalletNumber, CData)
    LogDebug("Calcul des points de prise et de dépose terminé à %f", os.clock())
    if (Res.Mode == MotionType.Norm) then
        if (PalletNumber.TransPointMode == 0) then
            GetTransPoint(PalletNumber)
        else
            GetAutoGenPoint(PalletNumber, CData)
        end
    else
        if (PalletNumber.TransPartPointMode == 0) then
            GetTransPoint(PalletNumber)
        else
            GetAutoGenPoint(PalletNumber, CData)
        end
    end
    LogDebug("Calcul des points de transition terminé à %f", os.clock())
    GetInterPoint(PalletNumber)
    LogDebug("Calcul des points intermédiaires terminé à %f", os.clock())
    CPoint = GetResult(CData, PalletNumber)
    return CPoint
end
----------------------------------------------------------------
--更新目录
local function UpdateIndex(PalletNumber, CData)
    if (Res.Mode == MotionType.Part) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.PartIndex = CData.PartIndex + 1
        else
            CData.PartIndex = CData.PartIndex - 1
        end
    end
    if (Res.Mode == MotionType.Norm) or (PalletNumber.Partition.LastPlan == true) then
        if (PalletNumber.Mode == WorkType.Pallet) then
            CData.Index = CData.Index + Res.Times
            if (CData.Index > CData.Num) then
                if (PalletNumber.Partition.Enable == true) then
                    if (PalletNumber.Partition.LastPlan == false)
                        and (PalletNumber.Partition.Layer[PalletNumber.Layer + 1] == 1) then
                        CData.Index = CData.Num
                        PalletNumber.Partition.LastPlan = true
                        return
                    else
                        PalletNumber.Partition.LastPlan = false
                    end
                end
                CData.Index = 1
                CData.PartIndex = 0
            end
        else
            CData.Index = CData.Index - Res.Times
            if (CData.Index <= 0) then
                if (PalletNumber.Partition.Enable == true) then
                    if (PalletNumber.Partition.LastPlan == false) and (PalletNumber.Partition.Layer[1] == 1) then
                        CData.Index = 1
                        PalletNumber.Partition.LastPlan = true
                        return
                    else
                        PalletNumber.Partition.LastPlan = false
                    end
                end
                CData.Index = CData.Num
                CData.PartIndex = CData.TPartIndex
            end
        end
    end
end
----------------------------------------------------------------
--更新点位
local function UpdatePoint(PalletNumber, CQueue, CData)
    local CPoint = {}
    local QueueL = math.min(BufLen, CData.Num)
    if (CQueue:Size() < QueueL) then
        for i = 1, 19 do
            Point.Pose[i] = { 0, 0, 0, 0, 0, 0 }
        end
        CPoint = GetPoint(PalletNumber, CData)
        LogDebug("Calcul de tous les points terminé à %f", os.clock())
        UpdateIndex(PalletNumber, CData)
        LogDebug("Mise à jour de l’index terminée à %f", os.clock())
        CQueue:Push(CPoint)
        LogDebug("Ajout du point à la file terminé à %f", os.clock())
        local Dir = (CData.Pallet == Left) and "gauche" or "droite"
        LogInfo("File %s — index : %d, taille : %d", Dir, CData.Index, CQueue:Size())
        LogDebugTable(Dir .. " queue data is: ", CPoint)
    end
end
----------------------------------------------------------------
--执行动作
local function ExecuteFSM(PalletNumber, CQueue, CData)
    if (PalletNumber.State.Init == false) then
        return
    end
    LogDebug("Début du calcul de la file à : %f", os.clock())
    while (PalletNumber.Pallet == Pallet) or (CData.FMotion == false) do
        CData.FMotion = true
        if (PalletNumber.State.Done == true) then
            break
        end
        GetTeachPoint(PalletNumber, CData)
        UpdatePoint(PalletNumber, CQueue, CData)
        if (StateMachine == FSMType.DLR)
            or (StateMachine == FSMType.SLR
                and (CQueue:Size() > 2)
                and (FData.FMotion == false or SData.FMotion == false)) then
            break
        end
    end
end
-----------------------------------------------------------------
--获取点位状态
local function PointFSM()
    local SwitchFSM =
    {
        [FSMType.IDLE] = function()
            LogWarn("La machine d’état des points est inactive !")
        end,
        [FSMType.SL] = function()
            ExecuteFSM(FirstPallet, FQueue, FData)
        end,
        [FSMType.SR] = function()
            ExecuteFSM(SecondPallet, SQueue, SData)
        end,
        [FSMType.DP] = function()
            ExecuteFSM(FirstPallet, FQueue, FData)
            ExecuteFSM(SecondPallet, SQueue, SData)
        end
    }
    local CFSM = StateMachine
    if (StateMachine == FSMType.SLR) or (StateMachine == FSMType.DLR) then
        CFSM = FSMType.DP
    end
    local switch_mode = SwitchFSM[CFSM]
    if switch_mode then
        switch_mode()
    else
        Alarm("PointFSM est incorrect !", ErrorMessage.Type.WorkingDataErr)
    end
end
-----------------------------------------------------------------
-----------------------------------------------------------------
while true do
    Wait(Time.Thread.s3)
    if (Communication.Controller.Modbus.LinkState == true) then
        PointFSM()
    end
end
