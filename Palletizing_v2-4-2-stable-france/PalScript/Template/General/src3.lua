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
-- 3. ForwardMotionPoint：去程专用过渡点，J1/J6已按取料端起始姿态连续化；
-- 4. BackwardMotionPoint：回程专用过渡点，J1/J6已按放置端起始姿态连续化。
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

-- 取料点J1接近±180°时视为侧面取料。
-- 这里只使用客户示教关节判断，不能使用GetInvK返回值，因为逆解本身可能选择错误分支。
local SidePickJ1Threshold = 135

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
        PickTeachJoint = nil, --普通箱取料示教关节；侧面取料时作为安全分支基准
        PartPickTeachJoint = nil, --隔板取料示教关节，保持客户示教分支
        PartPickTeachJ6 = nil, --兼容原有隔板J6保护逻辑
        TransTeachJoint = {}, --普通箱示教过渡点关节；侧面取料时用于识别错误IK分支
        UseTaughtTransition = false, --只有手动示教过渡点才启用锚点校验
        PartTransTeachJ6 = {}, --隔板示教过渡点J6，用于保持MotionPoint[1~5]的第6轴不被改写
        SidePick = false, --普通箱是否为侧面取料；只在初始化时根据示教J1判断一次
        IKWarningCache = {}, --避免同一类IK分支纠正每个箱子都重复刷日志
        PathBuildFailed = false, --安全路径生成失败后停止继续向队列填充
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

            if CData.SidePick == true then
                LogWarn("Prise latérale détectée sur la palette %s : J1 enseigné = %.4f° ; contrôle renforcé des branches IK activé.",
                    (CData.Pallet == Left) and "gauche" or "droite", CData.PickTeachJoint[1])
            end
        else
            CData.PickTeachJoint = nil
            CData.SidePick = false
            CData.Pick.pose = DeepCopy(PalletNumber.TeachPoint.TeachPickPoint.pose)
            CData.Pick.pose[3] = CData.Pick.pose[3] - PalletNumber.ProcessNum.PalletHeight
            CData.Standy = GetAddUserPos(PalletNumber.Coordinate.UserNum, 0, CData.Pick)
            CData.Standy.pose[3] = CData.Standy.pose[3] + TeachPointOffHeight
        end
        -- 保存普通箱示教过渡点关节。侧面取料时，除连续性外还要检查IK结果是否偏离客户示教分支。
        CData.TransTeachJoint = {}
        CData.UseTaughtTransition = (PalletNumber.TransPointMode == 0)
        if CData.UseTaughtTransition == true then
            for i = 1, PalletNumber.TransPlacePointNum do
                local TeachJoint = PalletNumber.TeachPoint.TransPlacePoint.joint[i]
                if (TeachJoint ~= nil) and (CheckTableData(TeachJoint) == 1) then
                    CData.TransTeachJoint[i] = DeepCopy(TeachJoint)
                end
            end
        end

        if (PalletNumber.Partition.Enable == true) then
            ProjectType = CheckTableData(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
            if (ProjectType == 1) then
                local PartPickJoint = { joint = {} }
                PartPickJoint.joint = DeepCopy(PalletNumber.TeachPoint.TeachPartitionPickPoint.joint)
                CData.PartPickTeachJoint = DeepCopy(PartPickJoint.joint)
                CData.PartPickTeachJ6 = PartPickJoint.joint[6]
                CData.PartPick = PositiveKin(PartPickJoint, { user = CData.User, tool = CData.Tool.Conc })
            else
                CData.PartPickTeachJoint = nil
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
-- 过渡路径在src3中提前完成安全分支计算。
-- 中间取料直接使用GetInvK结果；只有侧面取料才执行J1/J6等效分支纠正和连续性检查。
local PathJ1SafeMin = -60
local PathJ1SafeMax = 200
local PathJ6SoftMin = -360
local PathJ6SoftMax = 360
local PathJ1MaxSegment = 150
local PathJ1AnchorTolerance = 60
local DepositLiftHeight = 250

local function GetPointJoint(PointData)
    if (type(PointData) == "table") and (type(PointData.joint) == "table") then
        return PointData.joint
    end
    return nil
end

local function GetPointJ6(PointData, DefaultJ6)
    local Joint = GetPointJoint(PointData)
    if (Joint ~= nil) and (Joint[6] ~= nil) then
        return Joint[6]
    end
    return DefaultJ6
end

local function CaptureRawJointInfo(CJoint)
    local RawJointInfo = {}
    for i = 1, 19 do
        if type(CJoint[i]) == "table" then
            RawJointInfo[i] = {
                J1 = CJoint[i][1],
                J6 = CJoint[i][6]
            }
        end
    end
    return RawJointInfo
end

local function NormalizePathJ1(J1)
    if type(J1) ~= "number" then
        return nil
    end

    while J1 < PathJ1SafeMin do
        J1 = J1 + 360
    end
    while J1 > PathJ1SafeMax do
        J1 = J1 - 360
    end

    if (J1 < PathJ1SafeMin) or (J1 > PathJ1SafeMax) then
        return nil
    end
    return J1
end

local function NormalizePathJ6(J6, RefJ6)
    if type(J6) ~= "number" then
        return nil
    end
    if type(RefJ6) ~= "number" then
        RefJ6 = J6
    end

    local BestJ6 = nil
    local BestDiff = nil
    for K = -3, 3 do
        local Candidate = J6 + 360 * K
        if (Candidate >= PathJ6SoftMin) and (Candidate <= PathJ6SoftMax) then
            local Diff = math.abs(Candidate - RefJ6)
            if (BestJ6 == nil) or (Diff < BestDiff) then
                BestJ6 = Candidate
                BestDiff = Diff
            end
        end
    end
    return BestJ6
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

local function LogIKCorrectionOnce(CData, Context, PointIndex, RawJ1, RawJ6, FixedJ1, FixedJ6)
    if CData == nil then
        return
    end
    if type(CData.IKWarningCache) ~= "table" then
        CData.IKWarningCache = {}
    end

    local Key = string.format("%s:%d:%s:%s:%s:%s", tostring(Context), PointIndex,
        tostring(RawJ1), tostring(RawJ6), tostring(FixedJ1), tostring(FixedJ6))
    if CData.IKWarningCache[Key] == true then
        return
    end
    CData.IKWarningCache[Key] = true

    LogWarn("Branche IK corrigée (%s, point %d) : J1 IK brut=%s°, J6 IK brut=%s°, J1 corrigé=%s°, J6 corrigé=%s°.",
        tostring(Context), PointIndex, tostring(RawJ1), tostring(RawJ6), tostring(FixedJ1), tostring(FixedJ6))
end

local function ReportUnsafeIK(Context, PointIndex, J1, J6, RefJ1)
    LogError("Aucune branche IK sûre (%s, point %d) : J1=%s°, J6=%s°, référence J1=%s°.",
        tostring(Context), PointIndex, tostring(J1), tostring(J6), tostring(RefJ1))
    Alarm("Trajectoire articulaire dangereuse détectée !", ErrorMessage.Type.PointErr)
end

local function NormalizeLegacyPoint(PointData, RefJ6)
    local P = DeepCopy(PointData)
    local Joint = GetPointJoint(P)
    if Joint == nil then
        return nil
    end

    local FixedJ1 = NormalizePathJ1(Joint[1])
    local FixedJ6 = NormalizePathJ6(Joint[6], RefJ6)
    if (FixedJ1 == nil) or (FixedJ6 == nil) then
        return nil
    end

    Joint[1] = FixedJ1
    Joint[6] = FixedJ6
    return P
end

local function NormalizeSidePoint(PointData, RefPoint, CData, Context, PointIndex, RawInfo, CheckStep, AnchorJoint,
    ForcedJ6)
    local P = DeepCopy(PointData)
    local Joint = GetPointJoint(P)
    local RefJoint = GetPointJoint(RefPoint)
    if Joint == nil then
        ReportUnsafeIK(Context, PointIndex, nil, nil, RefJoint and RefJoint[1] or nil)
        return nil
    end

    local RefJ1 = RefJoint and RefJoint[1] or Joint[1]
    local RefJ6 = RefJoint and RefJoint[6] or Joint[6]
    local FixedJ1 = SelectEquivalentAngle(Joint[1], RefJ1, PathJ1SafeMin, PathJ1SafeMax)
    local FixedJ6 = nil
    if type(ForcedJ6) == "number" then
        -- 侧面取货的去程过渡点沿用旧版已验证平滑的策略：
        -- 所有过渡点使用同一个放置端J6等效分支，避免每个IK点的J6细小变化导致控制器逐点减速。
        FixedJ6 = SelectEquivalentAngle(ForcedJ6, RefJ6, PathJ6SoftMin, PathJ6SoftMax)
    else
        FixedJ6 = SelectEquivalentAngle(Joint[6], RefJ6, PathJ6SoftMin, PathJ6SoftMax)
    end

    if (FixedJ1 == nil) or (FixedJ6 == nil) then
        ReportUnsafeIK(Context, PointIndex, Joint[1], Joint[6], RefJ1)
        return nil
    end

    if (CheckStep == true) and (RefJoint ~= nil)
        and (math.abs(FixedJ1 - RefJ1) > PathJ1MaxSegment) then
        LogError("Saut J1 dangereux (%s, point %d) : %.4f° -> %.4f° (écart %.4f°).",
            tostring(Context), PointIndex, RefJ1, FixedJ1, math.abs(FixedJ1 - RefJ1))
        Alarm("Saut J1 dangereux détecté !", ErrorMessage.Type.PointErr)
        return nil
    end

    -- 手动示教过渡点提供第二道约束：IK结果必须靠近客户实际示教的J1分支。
    -- 这样可识别“数值连续但选到了另一套机械臂构型”的错误逆解。
    if (type(AnchorJoint) == "table") and (type(AnchorJoint[1]) == "number") then
        local AnchorJ1 = SelectEquivalentAngle(AnchorJoint[1], RefJ1, PathJ1SafeMin, PathJ1SafeMax)
        if (AnchorJ1 == nil) or (math.abs(FixedJ1 - AnchorJ1) > PathJ1AnchorTolerance) then
            LogError("Branche IK éloignée du point enseigné (%s, point %d) : J1 IK=%s°, J1 enseigné=%s°.",
                tostring(Context), PointIndex, tostring(FixedJ1), tostring(AnchorJ1 or AnchorJoint[1]))
            Alarm("Branche IK incompatible avec le point enseigné !", ErrorMessage.Type.PointErr)
            return nil
        end
    end

    local RawJ1 = (type(RawInfo) == "table" and RawInfo.J1 ~= nil) and RawInfo.J1 or Joint[1]
    local RawJ6 = (type(RawInfo) == "table" and RawInfo.J6 ~= nil) and RawInfo.J6 or Joint[6]
    if (math.abs(FixedJ1 - RawJ1) > 0.001) or (math.abs(FixedJ6 - RawJ6) > 0.001) then
        LogIKCorrectionOnce(CData, Context, PointIndex, RawJ1, RawJ6, FixedJ1, FixedJ6)
    end

    Joint[1] = FixedJ1
    Joint[6] = FixedJ6
    return P
end

local function ValidateJ1Segment(FromPoint, ToPoint, Context)
    local FromJoint = GetPointJoint(FromPoint)
    local ToJoint = GetPointJoint(ToPoint)
    if (FromJoint == nil) or (ToJoint == nil)
        or (type(FromJoint[1]) ~= "number") or (type(ToJoint[1]) ~= "number") then
        LogError("Impossible de vérifier le segment J1 : %s", tostring(Context))
        Alarm("Trajectoire J1 invalide !", ErrorMessage.Type.PointErr)
        return false
    end

    local Delta = math.abs(ToJoint[1] - FromJoint[1])
    if Delta > PathJ1MaxSegment then
        LogError("Saut J1 dangereux (%s) : %.4f° -> %.4f° (écart %.4f°).",
            tostring(Context), FromJoint[1], ToJoint[1], Delta)
        Alarm("Saut J1 dangereux détecté !", ErrorMessage.Type.PointErr)
        return false
    end
    return true
end

local function BuildOriginalTransitionPaths(Ret)
    for i = 1, Res.TransNum do
        local SourcePoint = Ret.MotionPoint[i]
        if GetPointJoint(SourcePoint) == nil then
            LogError("Point de transition central invalide : %d", i)
            Alarm("Point de transition invalide !", ErrorMessage.Type.PointErr)
            return false
        end
        Ret.ForwardMotionPoint[i] = DeepCopy(SourcePoint)
        Ret.BackwardMotionPoint[i] = DeepCopy(SourcePoint)
    end
    return true
end

local function NormalizePartitionExecutionPoints(Ret)
    for i = 1, 19 do
        local P = Ret.MotionPoint[i]
        if GetPointJoint(P) ~= nil then
            local FixedPoint = NormalizeLegacyPoint(P, P.joint[6])
            if FixedPoint == nil then
                ReportUnsafeIK("intercalaire", i, P.joint[1], P.joint[6], P.joint[1])
                return false
            end
            Ret.MotionPoint[i] = FixedPoint
        end
    end

    if GetPointJoint(Ret.StandyMotionPoint) ~= nil then
        local FixedStandy = NormalizeLegacyPoint(Ret.StandyMotionPoint, Ret.StandyMotionPoint.joint[6])
        if FixedStandy == nil then
            ReportUnsafeIK("attente intercalaire", 0, Ret.StandyMotionPoint.joint[1],
                Ret.StandyMotionPoint.joint[6], Ret.StandyMotionPoint.joint[1])
            return false
        end
        Ret.StandyMotionPoint = FixedStandy
    end

    -- 客户配置的隔板安全点保持原始关节值，不参与IK分支纠正。
    if (type(PartSafePoint) == "table") and (type(PartSafePoint.joint) == "table") then
        Ret.PartitionSafePoint = DeepCopy(PartSafePoint)
    else
        Ret.PartitionSafePoint = nil
        LogError("Le point de sécurité de l’intercalaire n’est pas configuré !")
        Alarm("Point de sécurité de l’intercalaire invalide !", ErrorMessage.Type.PointErr)
        return false
    end
    return true
end

local function BuildPartitionTransitionPaths(Ret)
    local ForwardRefJ6 = GetPointJ6(Ret.MotionPoint[6], nil)
    local BackwardRefJ6 = GetPointJ6(Ret.MotionPoint[8], ForwardRefJ6)

    for i = 1, Res.TransNum do
        local P = NormalizeLegacyPoint(Ret.MotionPoint[i], ForwardRefJ6)
        if P == nil then
            ReportUnsafeIK("aller intercalaire", i, nil, nil, nil)
            return false
        end
        Ret.ForwardMotionPoint[i] = P
        ForwardRefJ6 = GetPointJ6(P, ForwardRefJ6)
    end

    for i = Res.TransNum, 1, -1 do
        local SourcePoint = Ret.BackwardMotionPoint[i]
        if GetPointJoint(SourcePoint) == nil then
            SourcePoint = Ret.MotionPoint[i]
        end
        local P = NormalizeLegacyPoint(SourcePoint, BackwardRefJ6)
        if P == nil then
            ReportUnsafeIK("retour intercalaire", i, nil, nil, nil)
            return false
        end
        Ret.BackwardMotionPoint[i] = P
        BackwardRefJ6 = GetPointJ6(P, BackwardRefJ6)
    end
    return true
end

local function BuildDepositLiftPoints(Ret, CData)
    Ret.DepositLiftMotionPoint = {}
    if (Res.Mode ~= MotionType.Norm) or (Res.Times <= 1) then
        return true
    end

    for i = 1, Res.Times - 1 do
        local SourcePose = Point.Pose[11 + i]
        if type(SourcePose) ~= "table" then
            LogError("Pose de relèvement après dépose invalide : index %d", i)
            Alarm("Point de relèvement après dépose invalide !", ErrorMessage.Type.PointErr)
            return false
        end

        local LiftPose = { pose = DeepCopy(SourcePose) }
        LiftPose.pose[3] = LiftPose.pose[3] + DepositLiftHeight
        local ErrId, LiftJointPoint = InverseKin(LiftPose, {
            user = CData.User,
            tool = CData.Tool.Conc
        })

        if (ErrId ~= 0) or (GetPointJoint(LiftJointPoint) == nil) then
            LogError("Échec de la cinématique inverse du relèvement après dépose : index %d, erreur %s.",
                i, tostring(ErrId))
            Alarm("Échec de la cinématique inverse pour le relèvement après dépose !", ErrorMessage.Type.PointErr)
            return false
        end
        Ret.DepositLiftMotionPoint[i] = LiftJointPoint
    end
    return true
end

local function PrepareSidePickExecutionPoints(Ret, CData, RawJointInfo)
    if (type(CData.PickTeachJoint) ~= "table") or (type(CData.PickTeachJoint[1]) ~= "number") then
        LogError("Le joint enseigné du point de prise latérale est invalide !")
        Alarm("Point de prise latérale invalide !", ErrorMessage.Type.PointErr)
        return false
    end

    local RawPick = RawJointInfo[6]
    Ret.MotionPoint[6].joint = DeepCopy(CData.PickTeachJoint)
    if type(RawPick) == "table" then
        if (math.abs((RawPick.J1 or CData.PickTeachJoint[1]) - CData.PickTeachJoint[1]) > 0.001)
            or (math.abs((RawPick.J6 or CData.PickTeachJoint[6]) - CData.PickTeachJoint[6]) > 0.001) then
            LogIKCorrectionOnce(CData, "prise enseignée", 6, RawPick.J1, RawPick.J6,
                CData.PickTeachJoint[1], CData.PickTeachJoint[6])
        end
    end

    local PickOffset = NormalizeSidePoint(Ret.MotionPoint[7], Ret.MotionPoint[6], CData,
        "prise supérieure", 7, RawJointInfo[7], true)
    if PickOffset == nil then
        return false
    end
    Ret.MotionPoint[7] = PickOffset

    local RefPoint = Ret.MotionPoint[7]

    -- 旧版不卡的关键行为：普通箱去程的所有过渡点J6统一使用第一个放置点的J6。
    -- 这里只恢复J6连续策略；J1仍按当前安全逻辑逐点选择等效分支并检查跳变。
    local PlaceJoint = GetPointJoint(Ret.MotionPoint[8])
    local PickOffsetJoint = GetPointJoint(RefPoint)
    local ForwardTransitionJ6 = nil
    if (PlaceJoint ~= nil) and (PickOffsetJoint ~= nil) then
        ForwardTransitionJ6 = SelectEquivalentAngle(PlaceJoint[6], PickOffsetJoint[6],
            PathJ6SoftMin, PathJ6SoftMax)
    end
    if ForwardTransitionJ6 == nil then
        LogError("Impossible de déterminer le J6 commun du trajet aller !")
        Alarm("Trajectoire J6 invalide !", ErrorMessage.Type.PointErr)
        return false
    end

    for i = 1, Res.TransNum do
        local AnchorJoint = nil
        if CData.UseTaughtTransition == true then
            AnchorJoint = CData.TransTeachJoint[i]
        end
        local P = NormalizeSidePoint(Ret.MotionPoint[i], RefPoint, CData,
            "aller", i, RawJointInfo[i], true, AnchorJoint, ForwardTransitionJ6)
        if P == nil then
            return false
        end
        Ret.ForwardMotionPoint[i] = P
        RefPoint = P
    end

    -- 按src0真实执行顺序处理放置点，保证所有动态点与前一安全点连续。
    for i = 1, Res.Times do
        if Res.OffSet[i] == 1 then
            local InsertIndex = 15 + i
            local InsertPoint = NormalizeSidePoint(Ret.MotionPoint[InsertIndex], RefPoint, CData,
                "décalage dépose", InsertIndex, RawJointInfo[InsertIndex], true)
            if InsertPoint == nil then
                return false
            end
            Ret.MotionPoint[InsertIndex] = InsertPoint
            RefPoint = InsertPoint
        end

        local AboveIndex = 11 + i
        local AbovePoint = NormalizeSidePoint(Ret.MotionPoint[AboveIndex], RefPoint, CData,
            "au-dessus dépose", AboveIndex, RawJointInfo[AboveIndex], true)
        if AbovePoint == nil then
            return false
        end
        Ret.MotionPoint[AboveIndex] = AbovePoint

        local PlaceIndex = 7 + i
        local PlacePoint = NormalizeSidePoint(Ret.MotionPoint[PlaceIndex], AbovePoint, CData,
            "dépose", PlaceIndex, RawJointInfo[PlaceIndex], true)
        if PlacePoint == nil then
            return false
        end
        Ret.MotionPoint[PlaceIndex] = PlacePoint

        -- 放置后机器人先回到AbovePoint，因此后续参考从AbovePoint继续。
        RefPoint = AbovePoint
        if Ret.DepositLiftMotionPoint[i] ~= nil then
            local LiftPoint = NormalizeSidePoint(Ret.DepositLiftMotionPoint[i], RefPoint, CData,
                "relèvement après dépose", i, nil, true)
            if LiftPoint == nil then
                return false
            end
            Ret.DepositLiftMotionPoint[i] = LiftPoint
            RefPoint = LiftPoint
        end

        if Res.OffSet[i] == 1 then
            local InsertPoint = Ret.MotionPoint[15 + i]
            if ValidateJ1Segment(RefPoint, InsertPoint, "retour vers le point de décalage") ~= true then
                return false
            end
            RefPoint = InsertPoint
        end
    end

    -- 普通箱回程严格复用去程已确认的关节分支，只反向执行顺序。
    for i = 1, Res.TransNum do
        Ret.BackwardMotionPoint[i] = DeepCopy(Ret.ForwardMotionPoint[i])
    end

    local BackwardRef = RefPoint
    for i = Res.TransNum, 1, -1 do
        if ValidateJ1Segment(BackwardRef, Ret.BackwardMotionPoint[i], "retour transition " .. tostring(i)) ~= true then
            return false
        end
        BackwardRef = Ret.BackwardMotionPoint[i]
    end
    if ValidateJ1Segment(BackwardRef, Ret.MotionPoint[7], "retour vers la prise") ~= true then
        return false
    end
    return true
end


-- 获取点位结果
-- get point calculation result
local function GetResult(CData)
    local Ret = {
        MotionPoint = {},
        ForwardMotionPoint = {},
        BackwardMotionPoint = {},
        DepositLiftMotionPoint = {},
        Paras = {},
        MovS = {}
    }
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
    if type(CJoint) ~= "table" then
        LogError("GetInvK n’a retourné aucune donnée articulaire !")
        Alarm("Échec du calcul des points articulaires !", ErrorMessage.Type.PointErr)
        return nil
    end
    local RawJointInfo = CaptureRawJointInfo(CJoint)

    -- 隔板回程过渡点使用终点待机点的J6；去程过渡点仍保持示教J6。
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
        local JointData = {}
        if type(CJoint[i]) == "table" then
            JointData = DeepCopy(CJoint[i])
        end
        Ret.MotionPoint[i] = { joint = JointData }

        if (i < 6) then
            if (Res.Mode == MotionType.Part) then
                if (CData.PartTransTeachJ6 ~= nil) and (CData.PartTransTeachJ6[i] ~= nil) then
                    Ret.MotionPoint[i].joint[6] = CData.PartTransTeachJ6[i]
                end
            elseif CData.SidePick ~= true then
                -- 中间取料保持原有快速逻辑：普通示教过渡点J6与放置姿态一致。
                -- 侧面取料不在这里覆盖GetInvK原值，而是在安全路径处理中按前一点选择连续分支。
                if (Ret.MotionPoint[i].joint[5] ~= nil)
                    and (math.abs(math.abs(Ret.MotionPoint[i].joint[5]) - 90) < 3) then
                    -- 接近腕部奇异区时保留GetInvK给出的J6。
                elseif (type(CJoint[8]) == "table") then
                    Ret.MotionPoint[i].joint[6] = CJoint[8][6]
                end
            end
        end

        if (i == 12 or i == 16) and (type(CJoint[8]) == "table") then
            Ret.MotionPoint[i].joint[6] = CJoint[8][6]
        end
        if (i == 13 or i == 17) and (type(CJoint[9]) == "table") then
            Ret.MotionPoint[i].joint[6] = CJoint[9][6]
        end
        if (i == 14 or i == 18) and (type(CJoint[10]) == "table") then
            Ret.MotionPoint[i].joint[6] = CJoint[10][6]
        end
        if (i == 15 or i == 19) and (type(CJoint[11]) == "table") then
            Ret.MotionPoint[i].joint[6] = CJoint[11][6]
        end
    end

    -- 隔板回程过渡点副本：J1~J5保持逆解，J6统一改为待机点终点J6。
    if (Res.Mode == MotionType.Part) then
        for i = 1, Res.TransNum do
            if GetPointJoint(Ret.MotionPoint[i]) ~= nil then
                Ret.BackwardMotionPoint[i] = DeepCopy(Ret.MotionPoint[i])
                if (BackwardTransJ6 ~= nil) and (Ret.BackwardMotionPoint[i].joint ~= nil) then
                    Ret.BackwardMotionPoint[i].joint[6] = BackwardTransJ6
                end
            end
        end
    end

    -- 隔板取料点保持客户完整示教关节，不只保护J6。
    if (Res.Mode == MotionType.Part) and (type(CData.PartPickTeachJoint) == "table") then
        Ret.MotionPoint[6].joint = DeepCopy(CData.PartPickTeachJoint)
    elseif (Res.Mode == MotionType.Part) and (CData.PartPickTeachJ6 ~= nil) then
        Ret.MotionPoint[6].joint[6] = CData.PartPickTeachJ6
    end

    -- 多吸单放的放置后额外抬升点在src3中提前逆解，src0运行时不再GetAngle/InverseKin。
    if BuildDepositLiftPoints(Ret, CData) ~= true then
        return nil
    end

    if Res.Mode == MotionType.Part then
        if NormalizePartitionExecutionPoints(Ret) ~= true then
            return nil
        end
        if BuildPartitionTransitionPaths(Ret) ~= true then
            return nil
        end
    elseif CData.SidePick == true then
        if PrepareSidePickExecutionPoints(Ret, CData, RawJointInfo) ~= true then
            return nil
        end
    else
        -- 中间取料不做J1/J6等效分支搜索，只复制原始过渡路径，提高点位生成效率。
        if BuildOriginalTransitionPaths(Ret) ~= true then
            return nil
        end
    end

    Ret.Paras = DeepCopy(Res)
    Ret.Paras.BackwardTransJ6 = BackwardTransJ6
    Ret.Paras.SidePick = CData.SidePick

    -- MovS轨迹必须使用与本次CPoint计算完全相同的用户坐标系和工具号。
    -- ecoKey在本项目中固定为0，不用于IO事件。
    Ret.MovS.UserNum = CData.User
    Ret.MovS.ToolNum = CData.Tool.Conc
    Ret.MovS.EcoKey = 0
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
    CPoint = GetResult(CData)
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

    if CData.PathBuildFailed == true then
        return false
    end

    if (CQueue:Size() < QueueL) then
        for i = 1, 19 do
            Point.Pose[i] = { 0, 0, 0, 0, 0, 0 }
        end
        CPoint = GetPoint(PalletNumber, CData)
        LogDebug("Calcul de tous les points terminé à %f", os.clock())

        -- 安全路径生成失败时不更新箱号、不压入队列，原始错误关节绝不进入src0。
        if CPoint == nil then
            CData.PathBuildFailed = true
            LogError("Échec de la génération d’une trajectoire sûre pour la palette %s ; remplissage de la file arrêté.",
                (CData.Pallet == Left) and "gauche" or "droite")
            return false
        end

        UpdateIndex(PalletNumber, CData)
        LogDebug("Mise à jour de l’index terminée à %f", os.clock())
        CQueue:Push(CPoint)
        LogDebug("Ajout du point à la file terminé à %f", os.clock())
        local Dir = (CData.Pallet == Left) and "gauche" or "droite"
        LogInfo("File %s — index : %d, taille : %d", Dir, CData.Index, CQueue:Size())
        LogDebugTable(Dir .. " queue data is: ", CPoint)
    end
    return true
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
        if UpdatePoint(PalletNumber, CQueue, CData) ~= true then
            break
        end
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
