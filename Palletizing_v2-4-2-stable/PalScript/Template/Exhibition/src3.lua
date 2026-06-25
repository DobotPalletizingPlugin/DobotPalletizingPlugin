
-- 子线程，随主线程一起运行的并行程序，可设置I/O、通讯、变量等，不能调用运动指令。
---------------------------------------------------------------
TotalTime = 0     --产能数据：时间
TotalTimeStart = 0

Hour = 0
Minute = 0
Second = 0
RemainingHour = 0
RemainingMinute = 0
RemainingSecond = 0

---------------------------------------------------------------
--读取产能数据已有时间	
local function ReadProductionTime()
	RemainingHour = ReadRobotModbus(5014)
	RemainingMinute = ReadRobotModbus(5015)
	RemainingSecond = ReadRobotModbus(5016)
end
---------------------------------------------------------------
--计算产能数据：时间
local function CalProductionTime(Time)
	Hour = math.floor(Time/3600) 
	Minute = math.floor((Time%3600)/60) 
	Second = math.floor((Time%3600)%60)
end
---------------------------------------------------------------
--上传产能数据：时间
local function CommitProductionTime()	
	WriteRobotModbus(Hour, 5014)
	WriteRobotModbus(Minute, 5015)
	WriteRobotModbus(Second, 5016)
end
---------------------------------------------------------------
while true do
    if Communication.Controller.Modbus.SuccessFlag == true then
        ReadProductionTime() --读取产能数据已有时间

        if RemainingHour == nil then
            RemainingHour = 0
        end
        if RemainingMinute == nil then
            RemainingMinute = 0
        end
        if RemainingSecond == nil then
            RemainingSecond = 0
        end
        print("\rRemainingHour:", RemainingHour)
        print("\rRemainingMinute:", RemainingMinute)
        print("\rRemainingSecond:", RemainingSecond)
        TotalTime = RemainingHour * 3600 + RemainingMinute * 60 + RemainingSecond
        TotalTimeStart = TotalTime
        while true do
            if (FirstPallet.StateValue.Status == 2 and FirstPallet.State.EnableResult == true)
                or (SecondPallet.StateValue.Status == 2 and SecondPallet.State.EnableResult == true) then
                Wait(Time.Thread.s3)
                TotalTime = TotalTime + 1 --单位s
                if Communication.Lifting.TimesPerHour > Communication.Lifting.MaxtimesPerHour then
                    Communication.Lifting.TimesPerHour = 0
                    if (TotalTime - TotalTimeStart) < 3600 then
                        TotalTimeStart = TotalTime
                        ErrorMessage.Code = 9
                        Alarm("升降柱运动次数过多！")
                    end
                end
                CalProductionTime(TotalTime) --计算产能数据：时间
                CommitProductionTime()       --上传产能数据：时间
            end
        end
    end
end
