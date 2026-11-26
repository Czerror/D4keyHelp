#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

; ========== 全局变量定义 ==========
; 核心状态变量
global DEBUG := false              ; 是否启用调试模式
global debugLogFile := A_ScriptDir "\debugd4.log"
global isRunning := false          ; 宏是否运行中
global isPaused := Map(
    "window", false,  ; 窗口检测
    "enter", false,  ; Enter键检测
    "tab", false,  ; 界面检测
    "blood", false      ; 血条检测
)                                   ; 暂停状态映射  
global counter := 0
global currentHotkey := "F1"       ; 当前热键

; GUI相关变量
global myGui := ""                 ; 主GUI对象
global statusText := ""            ; 状态文本控件
global statusBar := ""             ; 状态栏控件
global hotkeyControl := ""         ; 热键控件
global buffThreshold := ""         ; BUFF检测阈值滑块
global buffThresholdValue := ""    ; 显示BUFF阈值的文本控件
global sleepInput := ""            ; 卡快照延迟输入控件
global currentProfileName := "默认" ; 当前配置名称
global profileList := []           ; 配置列表

; 控件映射
global cSkill := Map()      ; 技能控件映射
global bSkill := Map()  ; 技能BUFF控件映射
global mSkill := {}         ; 鼠标控件
global uCtrl := Map()                 ; 功能键控件
global mouseAutoMove := {}         ; 鼠标自动移动控件
global forceMove := {}             ; 强制移动控件

; 技能模式常量
global SKILL_MODE_CLICK := 1       ; 连点模式
global SKILL_MODE_BUFF := 2        ; BUFF模式
global SKILL_MODE_HOLD := 3        ; 按住模式
global skillMod := ["连点", "BUFF", "按住"]

; 功能状态变量
global shiftEnabled := false       ; 是否按住Shift
global skillActiveState := false   ; 技能是否激活
global mouseAutoMoveEnabled := false ; 是否启用鼠标自动移动
global mouseAutoMoveCurrentPoint := 1 ; 当前鼠标移动点

; 技能位置映射
global skillPositions := Map()     ; 存储技能位置坐标

; 定时器相关变量
global boundSkillTimers := Map()   ; 存储绑定的技能定时器函数
global timerStates := Map()        ; 用于跟踪定时器状态
global holdStates := Map()         ; 跟踪按键按住状态
global keyQueue := []         ; 按键队列
global keyQueueLock := false  ; 队列锁
global keyQueueTimer := ""    ; 队列调度定时器

; ==================== 工具类函数 ====================
/**
 * 调试日志记录函数
 * @param {String} message - 要记录的消息
 */
DebugLog(message) {
    if DEBUG {
        try {
            logFile := debugLogFile
            maxSize := 1024 * 1024  ; 1MB

            ; 检查日志文件大小，超出则清空
            if FileExist(logFile) {
                fileObj := FileOpen(logFile, "r")
                if (fileObj.Length > maxSize) {
                    fileObj.Close()
                    FileDelete logFile
                } else {
                    fileObj.Close()
                }
            }

            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            FileAppend timestamp " - " message "`n", logFile
        } catch as err {
            OutputDebug "日志写入失败: " err.Message
        }
    }
}

; ==================== GUI界面管理 ====================
/**
 * 创建主GUI界面
 */
CreateMainGUI() {
    global myGui, statusText, statusBar, hotkeyControl, currentProfileName
    global profileDropDown, profileNameInput

    ; 创建主窗口
    myGui := Gui("", "暗黑4助手 v3.1")
    myGui.BackColor := "FFFFFF"
    myGui.SetFont("s10", "Microsoft YaHei UI")

    ; 添加主要内容区域
    myGui.AddGroupBox("x10 y10 w460 h120", "F3: 卡快照")
    statusText := myGui.AddText("x30 y35 w400 h20", "状态: 未运行")
    myGui.AddButton("x30 y65 w80 h30", "开始/停止").OnEvent("Click", ToggleMacro)
    myGui.AddText("x30 y100 w300 h20", "提示：仅在暗黑破坏神4窗口活动时生效")
 
    ; 添加配置方案管理区
    myGui.AddGroupBox("x10 y135 w460 h65", "配置方案")
    myGui.AddText("x30 y160 w70 h20", "当前方案：")
    profileDropDown := myGui.AddDropDownList("x100 y155 w150 h120 Choose1", ["默认"])
    profileDropDown.OnEvent("Change", LoadSelectedProfile)
    
    profileNameInput := myGui.AddEdit("x270 y155 w100 h25", currentProfileName)
    myGui.AddButton("x375 y155 w40 h25", "保存").OnEvent("Click", SaveProfile)
    myGui.AddButton("x420 y155 w40 h25", "删除").OnEvent("Click", DeleteProfile)
    
    ; 添加技能设置区域
    myGui.AddGroupBox("x10 y210 w460 h455", "键设置")

    ; 添加Shift键勾选框
    myGui.AddCheckbox("x30 y245 w100 h20", "按住Shift").OnEvent("Click", ToggleShift)

    ; 添加列标题
    myGui.AddText("x30 y275 w60 h20", "按键")
    myGui.AddText("x130 y275 w60 h20", "启用")
    myGui.AddText("x200 y275 w120 h20", "间隔(毫秒)")

    hotkeyControl := myGui.AddHotkey("x120 y70 w80 h20", currentHotkey)
    hotkeyControl.OnEvent("Change", (ctrl, *) => LoadGlobalHotkey())

    myGui.AddText("x130 y245", "BUFF检测阈值:")
    global buffThreshold := myGui.AddSlider("x260 y245 w100 Range50-200", 100)
    global buffThresholdValue := myGui.AddText("x360 y245 w30 h20", buffThreshold.Value)
    buffThreshold.OnEvent("Change", UpdateBuffThresholdDisplay)

    ; 添加 Sleep 延迟数字输入框
    myGui.AddText("x30 y680 w200 h20", "卡快照延迟(毫秒):")
    global sleepInput := myGui.AddEdit("x140 y675 w40", 2700)
    sleepInput.OnEvent("LoseFocus", ValidateSleepInput)
}

/**
 * 创建所有控件
 */
CreateAllControls() {
    global myGui, cSkill, mSkill, uCtrl
    global mouseAutoMove, skillMod, SKILL_MODE_CLICK

    ; === 创建技能控件 ===
    cSkill := Map()
    Loop 5 {
        yPos := 305 + (A_Index-1) * 30
        myGui.AddText("x30 y" yPos " w40 h20", "技能" A_Index ":")
        cSkill[A_Index] := {
            key: myGui.AddHotkey("x90 y" yPos " w30 h20", A_Index),
            enable: myGui.AddCheckbox("x130 y" yPos " w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y" yPos " w40 h20", "20"),
            mode: myGui.AddDropDownList("x270 y" yPos " w60 h120 Choose1", skillMod)
        }
    }

    ; === 创建鼠标控件 ===
    mSkill := {
        left: {
            enable: myGui.AddCheckbox("x130 y455 w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y455 w40 h20", "80"),
            mode: myGui.AddDropDownList("x270 y455 w60 h120 Choose1", skillMod)
        },
        right: {
            enable: myGui.AddCheckbox("x130 y485 w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y485 w40 h20", "300"),
            mode: myGui.AddDropDownList("x270 y485 w60 h120 Choose1", skillMod)
        }
    }
    myGui.AddText("x30 y455 w40 h20", "左键:")
    myGui.AddText("x30 y485 w40 h20", "右键:")

    ; === 创建控件 ===
    uCtrl := Map()
    uCtrl["dodge"] := Map(
        "text", myGui.AddText("x30 y575 w30 h20", "空格:"),
        "key", { Value: "Space" },
        "enable", myGui.AddCheckbox("x130 y575 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y575 w40 h20", "20")
    )
    uCtrl["potion"] := Map(
        "text", myGui.AddText("x30 y515 w30 h20", "喝药:"),
        "key", myGui.AddHotkey("x90 y515 w35 h20", "q"),
        "enable", myGui.AddCheckbox("x130 y515 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y515 w40 h20", "3000")
    )
    uCtrl["forceMove"] := Map(
        "text", myGui.AddText("x30 y545 w30 h20", "强移:"),
        "key", myGui.AddHotkey("x90 y545 w35 h20", "f"),
        "enable", myGui.AddCheckbox("x130 y545 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y545 w40 h20", "50")
    )
    uCtrl["ipPause"] := Map(
        "text", myGui.AddText("x300 y70 w60 h20", "血条启停:"),
        "enable", myGui.AddCheckbox("x360 y70 w50 h20")
    )
    uCtrl["dcPause"] := Map(
        "text", myGui.AddText("x300 y100 w60 h20", "双击暂停:"),
        "enable", myGui.AddCheckbox("x360 y100 w30 h20")
    )
    uCtrl["huoDun"] := Map(
        "text", myGui.AddText("x30 y640 w60 h20", "火盾:"),
        "key", myGui.AddHotkey("x70 y635 w35 h20", "2")
    )
    uCtrl["dianMao"] := Map(
        "text", myGui.AddText("x110 y640 w60 h20", "电矛:"),
        "key", myGui.AddHotkey("x150 y635 w35 h20", "1")
    )
    uCtrl["dianQiu"] := Map(
        "text", myGui.AddText("x190 y640 w60 h20", "电球:"),
        "key", myGui.AddHotkey("x230 y635 w35 h20", "e")
    )
    uCtrl["binDun"] := Map(
        "text", myGui.AddText("x280 y640 w60 h20", "冰盾:"),
        "key", myGui.AddHotkey("x320 y635 w35 h20", "3")
    )
    ; 添加鼠标自动移动控件
    mouseAutoMove := {
        enable: myGui.AddCheckbox("x30 y605 w100 h20", "鼠标自动移动"),
        interval: myGui.AddEdit("x160 y605 w40 h20", "1000")
    }
    mouseAutoMove.enable.OnEvent("Click", ToggleMouseAutoMove)
}

/**
 * 初始化GUI
 */
InitializeGUI() {
    global myGui, statusBar

    ; 创建主GUI
    CreateMainGUI()

    ; 创建所有控件
    CreateAllControls()

    ; 添加状态栏
    statusBar := myGui.AddStatusBar(, "就绪")

    ; 显示GUI
    myGui.Show("w480 h740")  ; 增加高度以适应新控件

    ; 初始化配置方案列表
    InitializeProfiles()  ; 添加这一行来初始化配置

    ; 设置窗口事件处理
    myGui.OnEvent("Close", (*) => (
        SaveSettings(),   ; 关闭窗口时自动保存设置
        ExitApp()
    ))

    ; 设置窗口事件处理
    myGui.OnEvent("Escape", (*) => ExitApp())
}

/**
 * 更新BUFF阈值显示
 */
UpdateBuffThresholdDisplay(ctrl, *) {
    buffThresholdValue.Text := buffThreshold.Value
    ; 如果需要实时获取值也可以在此处更新阈值
}

/**
 * 更新卡快照延迟
 */
ValidateSleepInput(ctrl, *) {
    try {
        val := Integer(ctrl.Value)
        if (val < 2400 || val > 5000) {
            ctrl.Value := 2700
            statusBar.Text := "延迟必须在2400-5000毫秒范围内"
        } else {
            statusBar.Text := "卡快照延迟已更新: " val "毫秒"
        }
    } catch {
        ctrl.Value := 2700
        statusBar.Text := "请输入有效数字"
    }
}

/**
 * 更新状态显示
 * @param {String} status - 主状态文本
 * @param {String} barText - 状态栏文本
 */
UpdateStatus(status, barText) {
    global statusText, statusBar
    if (IsAnyPaused()) {
        statusText.Value := "状态: 已暂停"
        statusBar.Text := "宏已暂停 - " barText
        DebugLog("状态更新: 已暂停 | " barText)
    } else {
        statusText.Value := "状态: " status
        statusBar.Text := barText
        DebugLog("状态更新: " status " | " barText)
    }
}

; ==================== 核心控制函数 ====================
/**
 * 切换宏运行状态
 */
/**
 * 切换宏运行状态
 */
ToggleMacro(*) {
    global isRunning, mouseAutoMoveEnabled, mouseAutoMove, isPaused

    ; 确保完全停止所有定时器
    StopAllTimers()
    StopWindowCheckTimer()
    StopAutoPauseTimer()
    StopImagePauseTimer()
    
    ; 切换运行状态
    isRunning := !isRunning
    
    if isRunning {
        ; 初始化暂停状态
        for key, _ in isPaused {
            isPaused[key] := false
        }
        
        ; 初始化窗口分辨率和技能位置
        GetDynamicSkillPositions()
        
        ; 确保鼠标自动移动状态与GUI勾选框一致
        mouseAutoMoveEnabled := (mouseAutoMove.enable.Value = 1)
        
        ; 启动监控定时器
        StartWindowCheckTimer()
        StartAutoPauseTimer()
        StartImagePauseTimer()
        
        ; 只有在暗黑4窗口激活时才启动定时器
        if WinActive("ahk_class Diablo IV Main Window Class") {
            StartAllTimers()
            UpdateStatus("运行中", "宏已启动")
        } else {
            ; 如果窗口未激活，设置窗口暂停状态
            isPaused["window"] := true
            UpdateStatus("已暂停(窗口切换)", "宏已暂停 - 窗口未激活")
        }
    } else {
        ; 停止所有定时器
        StopAllTimers()
        StopWindowCheckTimer()
        StopAutoPauseTimer()
        StopImagePauseTimer()
        
        ; 重置所有暂停状态
        for key, _ in isPaused {
            isPaused[key] := false
        }
        
        ; 确保释放所有按键
        ReleaseAllKeys()
        
        UpdateStatus("已停止", "宏已停止")
    }

    DebugLog("宏状态切换: " . (isRunning ? "运行" : "停止"))
}

/**
 * 释放所有可能被按住的按键
 */
ReleaseAllKeys() {
    global holdStates    
    for uniqueKey, _ in holdStates {
        ; 解析 uniqueKey 得到实际按键
        arr := StrSplit(uniqueKey, ":")
        type := arr[1]
        key := arr[2]
        if (type = "mouse") {
            Click "up " key
        } else {
            Send "{" key " up}"
        }
    }
    holdStates.Clear()
    ; 释放修饰键
    Send "{Shift up}"
    Send "{Ctrl up}"
    Send "{Alt up}"

    ; 清空所有按住状态跟踪
    holdStates.Clear()

    DebugLog("已释放所有技能键、功能键、法师技能、鼠标键和修饰键")
}

; ==================== 暂停管理 ====================

IsAnyPaused() {
    global isPaused, isRunning
    if (!isRunning)
        return false
    for _, v in isPaused {
        if v
            return true
    }
    return false
}

/**
 * 切换暂停状态
 */
/**
 * 切换暂停状态，增加恢复条件检查
 */
TogglePause(reason, state) {
    global isPaused, isRunning
    if (!isRunning)
        return
    ; 确保原因存在
    if (!isPaused.Has(reason)) {
        isPaused[reason] := false
    }
    
    ; 如果是尝试恢复操作(state=false)且原因是color或special，先检查条件
    if !state {
        res := GetWindowResolutionAndScale()
        colors := CheckKeyPoints(res)
        enterDetected := CheckPauseByEnter()
        
        ; 只有同时满足"检测到蓝色"和"没有检测到Enter提示"才允许恢复
        if (!colors.isBlueColor || enterDetected || colors.isRedColor) {
            DebugLog("恢复条件未满足: 没有退出界面=" colors.isBlueColor ", 输入框未关闭=" enterDetected ", 地图未关闭=" colors.isRedColor)
            DebugLog("保持暂停状态")
            return
        } else {
            DebugLog("恢复条件已满足: 重新启动宏")
        }
    }
    
    prev := IsAnyPaused()
    isPaused[reason] := state
    now := IsAnyPaused()
    
    DebugLog("暂停状态变更: 原因=" reason ", 状态=" state ", 之前全局=" prev ", 现在全局=" now)
    
    if (now != prev) {
        if (now) {
            StopAllTimers()
            UpdateStatus("已暂停", "宏已暂停 - 原因: " reason)
        } else {
            StartAllTimers()
            UpdateStatus("运行中", "宏已恢复 - 原因: " reason)
        }
    }
}

; ==================== 定时器管理 ====================
/**
 * 启动所有定时器（队列模式）
 */
StartAllTimers() {
    StopAllTimers()
    StartKeyQueueTimers()
    StartWindowCheckTimer()
    StartAutoPauseTimer()
    StartImagePauseTimer()
    DebugLog("所有定时器已启动(队列模式)")
}

/**
 * 启动所有按键队列定时器
 */
StartKeyQueueTimers() {
    global keyQueue, keyQueueTimer, cSkill, mSkill, uCtrl

    keyQueue := []

    ; 技能
    for i in [1,2,3,4,5] {
        if (cSkill[i].enable.Value = 1) {
            interval := Integer(cSkill[i].interval.Value)
                if (interval > 0) {
                    EnqueueKey({
                        id: "skill" i,
                        func: (qItem) => PressSkill(qItem.skillIndex),
                        skillIndex: i,
                        interval: interval,
                        nextFire: A_TickCount + interval
                    })
                }
            }
    }
    ; 鼠标
    if (mSkill.left.enable.Value = 1) {
        interval := Integer(mSkill.left.interval.Value)
        if (interval > 0) {
            EnqueueKey({
                id: "mouseLeft",
                func: PressLeftClickQueue,
                interval: interval,
                nextFire: A_TickCount + interval
            })
        }
    }
    if (mSkill.right.enable.Value = 1) {
        interval := Integer(mSkill.right.interval.Value)
        if (interval > 0) {
            EnqueueKey({
                id: "mouseRight",
                func: PressRightClickQueue,
                interval: interval,
                nextFire: A_TickCount + interval
            })
        }
    }
    for id, config in uCtrl {
        if (config.Has("enable") && config.Has("interval") && config["enable"].Value = 1) {
            interval := Integer(config["interval"].Value)
            if (interval > 0) {
                EnqueueKey({
                    id: id,
                    func: (qItem) => PressuSkillKey(qItem.uSkillId),
                    uSkillId: id,
                    interval: interval,
                    nextFire: A_TickCount + interval
                })
            }
        }
    }   
    ; 启动统一调度定时器（建议10ms轮询）
    keyQueueTimer := SetTimer(KeyQueueDispatcher, 10)
}

/**
 * 停止所有定时器
 */
StopAllTimers() {
    global keyQueue, keyQueueTimer
    SetTimer(KeyQueueDispatcher, 0)
    keyQueue := []
    ; 释放所有按键
    ReleaseAllKeys()
    DebugLog("已停止所有定时器并释放按键")
}

/**
 * 启动窗口检测定时器
 */
StartWindowCheckTimer() {
    SetTimer CheckWindow, 100
}

/**
 * 停止窗口检测定时器
 */
StopWindowCheckTimer() {
    SetTimer CheckWindow, 0
}

/**
 * 启动自动战斗定时器
 */
StartImagePauseTimer() {
    SetTimer AutoPauseByColor, 50
}

/**
 * 停止自动战斗定时器
 */
StopImagePauseTimer() {
    SetTimer AutoPauseByColor, 0
}

/**
 * 启动特殊点检测定时器
 */
StartAutoPauseTimer() {
    SetTimer(AutoPause, 100)
    DebugLog("特殊点检测定时器已启动")
}

/**
 * 停止特殊点检测定时器
 */
StopAutoPauseTimer() {
    SetTimer(AutoPause, 0)
    DebugLog("特殊点检测定时器已停止")
}

; ==================== 队列调度核心 ====================
/**
 * 按键队列调度器
 */
QuickSortByNextFire(arr, left := 1, right := unset) {
    if !IsSet(right)
        right := arr.Length
    if (left >= right)
        return
    pivotObj := arr[left]
    pivot := pivotObj.nextFire
    i := left
    j := right
    while (i < j) {
        while (i < j && arr[j].nextFire >= pivot)
            j--
        if (i < j)
            arr[i] := arr[j]
        while (i < j && arr[i].nextFire <= pivot)
            i++
        if (i < j)
            arr[j] := arr[i]
    }
    arr[i] := pivotObj
    QuickSortByNextFire(arr, left, i - 1)
    QuickSortByNextFire(arr, i + 1, right)
}

KeyQueueDispatcher() {
    global keyQueue, keyQueueLock, isRunning

    if (!isRunning || keyQueue.Length = 0)
        return

    if (keyQueueLock)
        return

    keyQueueLock := true

    now := A_TickCount

    ; 快速排序 keyQueue
    QuickSortByNextFire(keyQueue)

    ; 遍历所有到时间的按键
    for i, item in keyQueue {
        if (item.nextFire <= now) {
            try {
                item.func.Call(item)
            } catch as err {
                DebugLog("队列调度器异常: " err.Message)
            }
            item.nextFire := now + item.interval
        }
    }

    keyQueueLock := false
}

/**
 * 添加/更新按键到队列
 * @param {Object} item - {id, func, interval, nextFire, ...}
 */
EnqueueKey(item) {
    global keyQueue
    ; 检查是否已存在（用id唯一标识）
    for i, v in keyQueue {
        if (v.id = item.id) {
            keyQueue[i] := item
            return
        }
    }
    keyQueue.Push(item)
}

/**
 * 队列适配的按键处理函数
 */
PressLeftClickQueue(item) {
    PressLeftClick()
}
PressRightClickQueue(item) {
    PressRightClick()
}

; ==================== 按键与技能处理 ====================
/**
 * 通用按键处理
 * @param {String} keyOrBtn - 键名或鼠标按钮名
 * @param {Integer} mode - 模式编号
 * @param {Object} pos - BUFF检测坐标对象（可选）
 * @param {String} type - "key"、"mouse" 或 "uSkill"
 * @param {String} mouseBtn - 鼠标按钮名（如"left"/"right"，仅type为mouse时用）
 * @param {String} description - 按键描述（用于日志）
 */
HandleKeyMode(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "", description := "") {
    global shiftEnabled, buffThreshold, holdStates
    static lastReholdTime := Map()     ; 存储每个按键上次重新按住的时间
    static REHOLD_MIN_INTERVAL := 2000 ; 重新按住的最小间隔(毫秒)
    if (IsAnyPaused())
    return
    ; 生成唯一键标识符
    uniqueKey := type . ":" . (type="mouse" ? mouseBtn : keyOrBtn)
    currentTime := A_TickCount
    
    ; 按键描述（用于日志）
    keyDesc := description ? description : (type="mouse" ? "鼠标" . mouseBtn : "按键" . keyOrBtn)

    if (mode == SKILL_MODE_BUFF) {
        ; BUFF模式
        if (pos && IsSkillActive(pos.x, pos.y)) {
            DebugLog(keyDesc . " BUFF已激活，跳过")
            return
        }
        if (type = "mouse") {
            shiftEnabled ? SendWithShift(mouseBtn) : Click(mouseBtn)
        } else {
            shiftEnabled ? SendWithShift(keyOrBtn) : Send("{" keyOrBtn "}")
        }
        DebugLog("按下" . keyDesc . "(BUFF模式)")
    }
    else if (mode == SKILL_MODE_HOLD) {
        ; 按住模式
        ; 检查是否是首次按下或需要重新按住
        if (!holdStates.Has(uniqueKey) || !holdStates[uniqueKey]) {
            if (shiftEnabled)
                Send "{Shift down}"
            if (type = "mouse") {
                Click "down " mouseBtn
            } else {
                Send "{" keyOrBtn " down}"
            }
            holdStates[uniqueKey] := true
            lastReholdTime[uniqueKey] := currentTime
            DebugLog("按住" . keyDesc)
        } 
        else {
            ; 检查是否需要重新按住(已经过了足够的时间)
            if (!lastReholdTime.Has(uniqueKey) || (currentTime - lastReholdTime[uniqueKey] > REHOLD_MIN_INTERVAL)) {
                ; 重新按住
                if (type = "mouse") {
                    Click "up " mouseBtn
                    Click "down " mouseBtn
                    DebugLog("重新按住" . keyDesc . "，间隔: " (currentTime - lastReholdTime[uniqueKey]) "ms")
                } else {
                    Send "{" keyOrBtn " up}"
                    Send "{" keyOrBtn " down}"
                    DebugLog("重新按住" . keyDesc . "，间隔: " (currentTime - lastReholdTime[uniqueKey]) "ms")
                }
                lastReholdTime[uniqueKey] := currentTime
            }
        }
    }
    else {
        ; 连点模式
        if (type = "mouse") {
            shiftEnabled ? SendWithShift(mouseBtn) : Click(mouseBtn)
        } else {
            shiftEnabled ? SendWithShift(keyOrBtn) : Send("{" keyOrBtn "}")
        }
        DebugLog("按下" . keyDesc . "(连点模式)")
    }
}

/**
 * 技能按键处理
 */
PressSkill(skillNum) {
    global isRunning, cSkill, skillPositions
    if (!isRunning || IsAnyPaused() || !cSkill[skillNum].enable.Value)
        return
    key := cSkill[skillNum].key.Value
    if (key = "")
        return
    mode := cSkill[skillNum].mode.Value
    pos := skillPositions.Has(skillNum) ? skillPositions[skillNum] : ""
    HandleKeyMode(key, mode, pos, "key")
}

/**
 * 鼠标左键处理
 */
PressLeftClick() {
    global isRunning, mSkill, skillPositions
    if (!isRunning || IsAnyPaused() || !mSkill.left.enable.Value)
        return
    mode := mSkill.left.mode.Value
    pos := skillPositions.Has("left") ? skillPositions["left"] : ""
    HandleKeyMode("left", mode, pos, "mouse", "left")
}

/**
 * 鼠标右键处理
 */
PressRightClick() {
    global isRunning, mSkill, skillPositions
    if (!isRunning || IsAnyPaused() || !mSkill.right.enable.Value)
        return
    mode := mSkill.right.mode.Value
    pos := skillPositions.Has("right") ? skillPositions["right"] : ""
    HandleKeyMode("right", mode, pos, "mouse", "right")
}

/**
 * 功能键队列处理函数
 * @param {String} uSkillId - 功能键ID
 */
PressuSkillKey(uSkillId) {
    global isRunning, uCtrl
    
    if (!isRunning || IsAnyPaused())
        return

    ; 检查功能键是否存在于 uCtrl 中
    if (!uCtrl.Has(uSkillId)) {
        DebugLog("功能键未定义: " uSkillId)
        return
    }

    ; 获取功能键配置
    config := uCtrl[uSkillId]

    ; 检查功能键是否启用
    if (config.Has("enable") && config["enable"].Value = 1) {
        key := config.Has("key") ? config["key"].Value : ""
        if (key != "") {
            HandleKeyMode(key, SKILL_MODE_CLICK, "", "key", "", uSkillId)
        }
    }
}
/**
 * shift按键发送函数
 * @param {String} key - 要发送的按键
 */
SendWithShift(key) {
    Send "{Blind} {Shift down}"
    Sleep 10
    Send "{" key "}"
    Sleep 10
    Send "{Blind} {Shift up}"
}

/**
 * 切换Shift键状态
 */
ToggleShift(*) {
    global shiftEnabled
    shiftEnabled := !shiftEnabled
    DebugLog("Shift键状态: " . (shiftEnabled ? "启用" : "禁用"))
}

/**
 * 鼠标自动移动函数
 */
MoveMouseToNextPoint() {
    global mouseAutoMoveCurrentPoint, isRunning, mouseAutoMoveEnabled, isPaused

    if (!isRunning || isPaused || !mouseAutoMoveEnabled)
        return

    try {
        ; 获取分辨率和缩放比例
        res := GetWindowResolutionAndScale()

        ; 计算六个点的位置
        points := [
            {x: Round(0.15 * res.D4W), y: Round(0.15 * res.D4H)},  ; 左上角
            {x: Round(0.5 * res.D4W), y: Round(0.15 * res.D4H)},   ; 中上角
            {x: Round(0.85 * res.D4W), y: Round(0.15 * res.D4H)},  ; 右上角
            {x: Round(0.85 * res.D4W), y: Round(0.85 * res.D4H)},  ; 右下角
            {x: Round(0.5 * res.D4W), y: Round(0.85 * res.D4H)},   ; 中下角
            {x: Round(0.15 * res.D4W), y: Round(0.85 * res.D4H)}   ; 左下角
        ]

        ; 移动鼠标到当前点
        currentPoint := points[mouseAutoMoveCurrentPoint]
        MouseMove(currentPoint.x, currentPoint.y, 0)

        ; 更新到下一个点
        mouseAutoMoveCurrentPoint := Mod(mouseAutoMoveCurrentPoint, 6) + 1

        DebugLog("鼠标自动移动到点" mouseAutoMoveCurrentPoint ": x=" currentPoint.x ", y=" currentPoint.y)
    } catch as err {
        DebugLog("鼠标自动移动失败: " err.Message)
    }
}

/**
 * 切换鼠标自动移动功能
 */
ToggleMouseAutoMove(*) {
    global mouseAutoMoveEnabled, mouseAutoMove, isRunning, timerStates, isPaused

    mouseAutoMoveEnabled := !mouseAutoMoveEnabled

    ; 更新GUI勾选框状态以匹配当前状态
    mouseAutoMove.enable.Value := mouseAutoMoveEnabled ? 1 : 0

    ; 如果宏已经在运行且未暂停，则更新定时器状态
    if (isRunning && !isPaused) {
        if (mouseAutoMoveEnabled) {
            interval := Integer(mouseAutoMove.interval.Value)
            if (interval > 0) {
                SetTimer(MoveMouseToNextPoint, interval)
                timerStates["mouseAutoMove"] := true
                DebugLog("启动鼠标自动移动定时器 - 间隔: " interval)
            }
        } else {
            SetTimer(MoveMouseToNextPoint, 0)
            timerStates["mouseAutoMove"] := false
            DebugLog("停止鼠标自动移动定时器")
        }
    }

    DebugLog("鼠标自动移动状态切换: " . (mouseAutoMoveEnabled ? "启用" : "禁用"))
}

; ==================== 图像和窗口检测 ====================
/**
 * 窗口切换检查函数
 * 检测暗黑4窗口是否激活，并在状态变化时触发相应事件
 */
CheckWindow() {
    static lastState := false
    currentState := WinActive("ahk_class Diablo IV Main Window Class")
    if (currentState != lastState) {
        OnWindowChange(currentState)
        lastState := currentState
    }
}

/**
 * 窗口切换事件处理
 * @param {Boolean} isActive - 暗黑4窗口是否激活
 */
OnWindowChange(isActive) {
    global isRunning
    if (!isActive) {
        ; 暗黑4窗口失去激活时，推送“窗口切换”暂停
        if (isRunning) {
            TogglePause("window", true)
        }
    } else if (isRunning) {
        ; 暗黑4窗口激活时，弹出“窗口切换”暂停
        TogglePause("window", false)
    }
}

/**
 * 获取窗口分辨率并计算缩放比例
 * @returns {Object} - 包含分辨率和缩放比例的对象 {width, height, scaleW, scaleH, scale}
 */
GetWindowResolutionAndScale() {
    BASE_WIDTH := 3840
    BASE_HEIGHT := 2160
    D4W := 0, D4H := 0

    ; 获取窗口分辨率
    if WinExist("ahk_class Diablo IV Main Window Class") {
        WinGetPos(, , &D4W, &D4H, "ahk_class Diablo IV Main Window Class")
    }

    ; 计算缩放比例
    scaleW := D4W / BASE_WIDTH
    scaleH := D4H / BASE_HEIGHT
    scale := Min(scaleW, scaleH)

    return {
        D4W: D4W,       ; 窗口宽度
        D4H: D4H,      ; 窗口高度
        scaleW: scaleW,   ; 宽度缩放比例
        scaleH: scaleH,   ; 高度缩放比例
        scale: scale      ; 最终缩放比例（取宽高比例的最小值）
    }
}

/**
 * 动态计算技能位置
 * 基于窗口分辨率和缩放比例
 */
GetDynamicSkillPositions() {
    global skillPositions
    res := GetWindowResolutionAndScale()
    baseX := 1550, baseY := 1940, offset := 127

    ; 清空并填充技能位置
    skillPositions.Clear()
    Loop 5 {
        idx := A_Index
        skillPositions[idx] := {
            x: Round((baseX + offset * (idx - 1)) * res.scale),
            y: Round(baseY * res.scale)
        }
    }
    skillPositions["left"] := {
        x: Round((baseX + offset * 4) * res.scale),
        y: Round(baseY * res.scale)
    }
    skillPositions["right"] := {
        x: Round((baseX + offset * 5) * res.scale),
        y: Round(baseY * res.scale)
    }
}


/**
 * 专用的自动暂停函数
 * 检测特定坐标的颜色，并根据结果控制宏的暂停状态
 * 支持像素缓存，避免重复采样
 */
CheckKeyPoints(res, pixelCache := unset) {
    try {
        ; 定义关键点的坐标
        dfx := Round(1535 * res.scaleW), dty := Round(1880 * res.scaleH)
        tabx := Round(3795 * res.scaleW), tab := Round(90 * res.scaleH)
        
        ; 优先使用缓存
        color1 := (IsSet(pixelCache) && pixelCache.Has("dfx")) ? pixelCache["dfx"] : GetPixelRGB(dfx, dty)
        color2 := (IsSet(pixelCache) && pixelCache.Has("tab")) ? pixelCache["tab"] : GetPixelRGB(tabx, tab)

        ; 进行颜色判断
        isBlueColor := (color1.r + 50 < color1.b && color1.b >= 100)
        isRedColor := (color2.r > 100 && color2.g < 60 && color2.b < 60)
        
        ; 返回颜色信息和判断结果
        return {
            dfxcolor: color1,
            tabcolor: color2,
            isBlueColor: isBlueColor,
            isRedColor: isRedColor,
            positions: {
                dfx: dfx, dty: dty,
                tabx: tabx, tab: tab
            }
        }
    } catch as err {
        DebugLog("关键点颜色检测失败: " err.Message)
        return {
            dfxcolor: {}, 
            tabcolor: {}, 
            isBlueColor: false,
            isRedColor: false,
            positions: {}
        }
    }
}

/**
 * 检测屏幕底部是否有红色确认提示，如对话框、警告等
 * 支持像素缓存，避免重复采样
 * @returns {Boolean} - 是否检测到红色提示
 */
CheckPauseByEnter(res := unset, pixelCache := unset) {
    if !IsSet(res)
        res := GetWindowResolutionAndScale()
    
    baseX := Round(30 * res.scaleW)
    baseY := Round(1440 * res.scaleH)
    offset := Round(90 * res.scaleW)
    DebugLog("Enter检测点基准坐标: x=" baseX ", y=" baseY ", 偏移=" offset)
    Loop 6 {
        x := Round(baseX + offset * (A_Index - 1))
        y := baseY
        key := "enter" A_Index
        colorObj := (IsSet(pixelCache) && pixelCache.Has(key)) ? pixelCache[key] : GetPixelRGB(x, y)
        if (colorObj.r > 100 && colorObj.g < 60 && colorObj.b < 60) {
            DebugLog("检测到红色提示点: (" x "," y ") R=" colorObj.r ",G=" colorObj.g ",B=" colorObj.b)
            return true
        }
    }
    DebugLog("未检测到红色提示点")
    return false
}

/**
 * 专用的血条检测函数
 * 支持像素缓存，避免重复采样
 */
CheckPauseByColor(res := unset, pixelCache := unset) {
    if !IsSet(res)
        res := GetWindowResolutionAndScale()
    try {
        x1 := Round(1605 * res.scaleW), x2 := Round(1435 * res.scaleW)
        y1 := Round(85 * res.scaleH), y2 := Round(95 * res.scaleH)
        keys := ["blood1", "blood2", "blood3", "blood4"]
        coords := [[x1, y1], [x1, y2], [x2, y1], [x2, y2]]
        colors := []
        Loop 4 {
            key := keys[A_Index]
            xy := coords[A_Index]
            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? pixelCache[key] : GetPixelRGB(xy[1], xy[2])
            colors.Push(color)
        }
        hitCount := 0
        for color in colors {
            if (color.r > 100 && color.g < 60 && color.b < 60)
                hitCount++
        }
        return hitCount >= 2
    } catch as err {
        DebugLog("颜色检测失败: " err.Message)
    }
    return false
}

/**
 * 定时检测颜色并自动暂停/启动宏
 */
AutoPauseByColor() {
    global isRunning, isPaused, uCtrl
    if (!isRunning || uCtrl["ipPause"]["enable"].Value != 1)
        return

    ; 统一采样血条检测点
    res := GetWindowResolutionAndScale()
    pixelCache := Map()
    x1 := Round(1605 * res.scaleW), x2 := Round(1435 * res.scaleW)
    y1 := Round(85 * res.scaleH), y2 := Round(95 * res.scaleH)
    pixelCache["blood1"] := GetPixelRGB(x1, y1)
    pixelCache["blood2"] := GetPixelRGB(x1, y2)
    pixelCache["blood3"] := GetPixelRGB(x2, y1)
    pixelCache["blood4"] := GetPixelRGB(x2, y2)

    if (CheckPauseByColor(res, pixelCache)) {
        TogglePause("blood", false)
        UpdateStatus("运行中", "检测到血条，自动启动")
        DebugLog("识图触发自动启动")
    } else { 
        TogglePause("blood", true)
        UpdateStatus("已暂停", "血条消失，自动暂停")
        DebugLog("识图触发自动暂停")
    }
}

/**
 * 定时检测颜色并自动暂停/启动宏
 */
AutoPause() {
    global isRunning, isPaused
    if (isRunning) {  
        res := GetWindowResolutionAndScale()
        ; 统一采样所有关键点
        pixelCache := Map()
        ; CheckKeyPoints
        dfx := Round(1535 * res.scaleW), dty := Round(1880 * res.scaleH)
        tabx := Round(3795 * res.scaleW), tab := Round(90 * res.scaleH)
        pixelCache["dfx"] := GetPixelRGB(dfx, dty)
        pixelCache["tab"] := GetPixelRGB(tabx, tab)
        ; CheckPauseByEnter
        baseX := Round(30 * res.scaleW)
        baseY := Round(1440 * res.scaleH)
        offset := Round(90 * res.scaleW)
        Loop 6 {
            x := Round(baseX + offset * (A_Index - 1))
            y := baseY
            pixelCache["enter" A_Index] := GetPixelRGB(x, y)
        }

        colors := CheckKeyPoints(res, pixelCache)
        enterDetected := CheckPauseByEnter(res, pixelCache)

        if (colors.isRedColor) {
            TogglePause("tab", true)
            UpdateStatus("已暂停", "检测到地图界面，自动暂停")
            DebugLog("识图检测到地图界面，触发自动暂停")
        } 
        else if (enterDetected) {
            TogglePause("enter", true)
            UpdateStatus("已暂停", "检测到确认对话框，自动暂停")
            DebugLog("检测到Enter提示，触发自动暂停")
        }
        else if (isPaused["tab"] || isPaused["enter"]) {
            if (isPaused["tab"]) {
                TogglePause("tab", false)
                UpdateStatus("运行中", "界面关闭，自动恢复")
                DebugLog("识图检测界面关闭，触发自动恢复")
            }
            if (isPaused["enter"]) {
                TogglePause("enter", false)
                UpdateStatus("运行中", "确认对话框消失，自动恢复")
                DebugLog("Enter提示消失，触发自动恢复")
            }
        }
    }
}

/**
 * 检测技能激活状态
 * @param {Integer} x - 检测点X坐标
 * @param {Integer} y - 检测点Y坐标
 * @returns {Boolean} - 技能是否激活
 */
IsSkillActive(x, y) {
    tryCount := 2
    Loop tryCount {
        try {
            color := GetPixelRGB(x, y)
            return (color.g > color.b + buffThreshold.Value)
        } catch {
            Sleep 5
        }
    }
    DebugLog("检测技能状态失败: 多次尝试无效")
    return false
}

/**
 * 获取指定坐标像素的RGB颜色值
 * @param {Integer} x - X坐标
 * @param {Integer} y - Y坐标
 * @returns {Object} - 包含r, g, b三个颜色分量的对象
 */
GetPixelRGB(x, y) {
    try {
        color := PixelGetColor(x, y, "RGB")
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF
        return {r: r, g: g, b: b}
    } catch as err {
        DebugLog("获取像素颜色失败: " err.Message)
        return {r: 0, g: 0, b: 0}  ; 失败时返回黑色
    }
}

; ==================== 设置管理 ====================
/**
 * 初始化配置方案列表
 */
/**
 * 初始化配置方案列表
 */
InitializeProfiles() {
    global profileList, profileDropDown, currentProfileName
    
    ; 主配置文件路径
    settingsFile := A_ScriptDir "\settings.ini"
    
    ; 确保配置文件存在
    if !FileExist(settingsFile) {
        ; 创建默认配置文件
        IniWrite("默认", settingsFile, "Profiles", "List")
    }
    
    ; 从主配置文件读取配置方案列表
    try {
        profilesString := IniRead(settingsFile, "Profiles", "List", "默认")
        profileList := StrSplit(profilesString, "|")
        
        ; 确保默认配置总是存在
        if (!InArray(profileList, "默认")) {
            profileList.InsertAt(1, "默认")
            IniWrite(Join(profileList, "|"), settingsFile, "Profiles", "List")
        }
    } catch {
        profileList := ["默认"]
    }
    
    ; 更新下拉框
    UpdateProfileDropDown()
    
    ; 如果存在上次使用的配置记录，则加载它
    try {
        lastProfile := IniRead(settingsFile, "Global", "LastUsedProfile", "默认")
        found := false
        for i, name in profileList {
            if (name = lastProfile) {
                profileDropDown.Value := i
                LoadSelectedProfile(profileDropDown)
                found := true
                break
            }
        }
        ; 如果没找到或就是默认，则主动加载默认配置
        if (!found) {
            profileDropDown.Value := 1
            LoadSelectedProfile(profileDropDown)
        }
    } catch {
        ; 如果读取失败，主动加载默认配置
        profileDropDown.Value := 1
        LoadSelectedProfile(profileDropDown)
    }
}

/**
 * 更新配置列表下拉框
 */
UpdateProfileDropDown() {
    global profileList, profileDropDown, currentProfileName
    
    ; 保存当前选择
    currentSelection := currentProfileName
    ; 清空并重新填充下拉框
    profileDropDown.Delete()
    for i, name in profileList {
        profileDropDown.Add([name])
    }
    
    ; 尝试恢复选择
    found := false
    for i, name in profileList {
        if (name = currentSelection) {
            profileDropDown.Choose(i)
            found := true
            break
        }
    }
    
    ; 如果未找到，选择第一个
    if (!found && profileList.Length > 0)
        profileDropDown.Choose(1)
}

/**
 * 加载选定的配置方案
 * @param {Object} ctrl - 控件对象
 */
LoadSelectedProfile(ctrl, *) {
    global profileList, currentProfileName
    
    if (ctrl.Value <= 0 || ctrl.Value > profileList.Length)
        return
    
    ; 获取选定的配置名
    selectedProfile := profileList[ctrl.Value]
    currentProfileName := selectedProfile
    
    ; 更新输入框
    profileNameInput.Value := selectedProfile
    
    ; 加载配置
    LoadSettings(A_ScriptDir "\settings.ini", selectedProfile)
    
    DebugLog("已加载配置方案: " selectedProfile)
}

/**
 * 保存当前配置为方案
 */
SaveProfile(*) {
    global currentProfileName, profileNameInput, profileList
    
    ; 获取输入的配置名
    profileName := profileNameInput.Value
    
    ; 验证配置名
    if (profileName = "") {
        MsgBox("请输入配置方案名称", "提示", 48)
        return
    }
    
    ; 确认保存操作
    if (currentProfileName != profileName && InArray(profileList, profileName)) {
        if (MsgBox("配置方案「" profileName "」已存在，是否覆盖？", "确认", 4) != "Yes")
            return
    }
    
    ; 保存配置
    SaveSettings(A_ScriptDir "\settings.ini", profileName)
    
    ; 如果是新配置，添加到列表
    if (!InArray(profileList, profileName)) {
        profileList.Push(profileName)
        ; 保存更新后的配置方案列表
        IniWrite(Join(profileList, "|"), A_ScriptDir "\settings.ini", "Profiles", "List")
        UpdateProfileDropDown()
    }
    
    ; 更新当前配置名
    currentProfileName := profileName
    
    ; 记住这个配置作为最后使用的配置
    IniWrite(profileName, A_ScriptDir "\settings.ini", "Global", "LastUsedProfile")
    
    for i, name in profileList {
        if (name = profileName) {
            profileDropDown.Choose(i)
            LoadSelectedProfile(profileDropDown)
            break
        }
    }

    DebugLog("已保存配置方案: " profileName)
    statusBar.Text := "配置方案「" profileName "」已保存"
}

/**
 * 删除当前配置方案
 */
DeleteProfile(*) {
    global currentProfileName, profileList
    
    settingsFile := A_ScriptDir "\settings.ini"
    
    ; 不能删除默认配置
    if (currentProfileName = "默认") {
        MsgBox("无法删除默认配置方案", "提示", 48)
        return
    }
    
    ; 确认删除
    if (MsgBox("确定要删除配置方案「" currentProfileName "」吗？", "确认", 4) != "Yes")
        return
    
    ; 从列表中移除
    for i, name in profileList {
        if (name = currentProfileName) {
            profileList.RemoveAt(i)
            break
        }
    }
    
    ; 保存更新后的配置方案列表
    IniWrite(Join(profileList, "|"), settingsFile, "Profiles", "List")
    
    ; 从设置文件中删除此配置方案的所有设置
    DeleteProfileSettings(settingsFile, currentProfileName)
    
    ; 更新下拉框并选择默认配置
    UpdateProfileDropDown()
    profileDropDown.Choose(1)  ; 选择默认配置
    currentProfileName := "默认"
    profileNameInput.Value := "默认"
    
    ; 加载默认配置
    LoadSettings(settingsFile, "默认")
    
    DebugLog("已删除配置方案: " currentProfileName)
    statusBar.Text := "配置方案已删除，已加载默认配置"
}

/**
 * 从配置文件中删除指定配置方案的所有设置
 * @param {String} file - 配置文件路径
 * @param {String} profileName - 要删除的配置方案名称
 */
DeleteProfileSettings(file, profileName) {
    ; 删除此配置方案的所有部分
    sectionPrefix := profileName "_"
    
    ; 读取文件内容
    fileContent := FileRead(file)
    lines := StrSplit(fileContent, "`n", "`r")
    newContent := []
    
    ; 过滤掉属于此配置方案的行
    inProfileSection := false
    for i, line in lines {
        if (line ~= "^\[" sectionPrefix ".*\]") {
            inProfileSection := true
            continue
        } else if (line ~= "^\[.*\]") {
            inProfileSection := false
        }
        
        if (!inProfileSection) {
            newContent.Push(line)
        }
    }
    
    ; 写回文件
    FileDelete(file)
    FileAppend(Join(newContent, "`n"), file)
    
    DebugLog("已从配置文件删除配置方案设置: " profileName)
}

/**
 * 检查值是否在数组中
 * @param {Array} arr - 要搜索的数组
 * @param {Any} val - 要查找的值
 * @returns {Boolean} - 如果值在数组中则返回true，否则返回false
 */
InArray(arr, val) {
    for i, v in arr {
        if (v = val)
            return true
    }
    return false
}

/**
 * 将数组元素用指定分隔符连接
 * @param {Array} arr - 要连接的数组
 * @param {String} delimiter - 分隔符
 * @returns {String} - 连接后的字符串
 */
Join(arr, delimiter := ",") {
    result := ""
    for i, v in arr {
        if (i > 1)
            result .= delimiter
        result .= v
    }
    return result
}

/**
 * 保存设置到INI文件
 * @param {String} settingsFile - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
SaveSettings(settingsFile := "", profileName := "默认") {
    global statusBar
    
    if (settingsFile = "")
        settingsFile := A_ScriptDir "\settings.ini"
    
    if (hotkeyControl.Value = "") {
    hotkeyControl.Value := "F1"
    DebugLog("全局热键未设置，已自动保存为默认F1")
}
    
    try {
        ; 保存各类设置
        SaveSkillSettings(settingsFile, profileName)
        SaveMouseSettings(settingsFile, profileName)
        SaveuSkillSettings(settingsFile, profileName)
        LoadGlobalHotkey()

        statusBar.Text := "设置已保存"
        DebugLog("所有设置已保存到: " settingsFile " 配置方案: " profileName)
    } catch as err {
        statusBar.Text := "保存设置失败: " err.Message
        DebugLog("保存设置失败: " err.Message)
    }
}

/**
 * 保存技能设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
SaveSkillSettings(file, profileName) {
    global cSkill
    section := profileName "_Skills"

    for i in [1, 2, 3, 4, 5] {
        IniWrite(cSkill[i].key.Value, file, section, "Skill" i "Key")
        IniWrite(cSkill[i].enable.Value, file, section, "Skill" i "Enable")
        IniWrite(cSkill[i].interval.Value, file, section, "Skill" i "Interval")

        ; 获取下拉框选择的索引并保存
        modeIndex := cSkill[i].mode.Value
        IniWrite(modeIndex, file, section, "Skill" i "Mode")
        DebugLog("保存技能" i "模式: " modeIndex)
    }
}

/**
 * 保存鼠标设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
SaveMouseSettings(file, profileName) {
    global mSkill, mouseAutoMove
    section := profileName "_Mouse"

    ; 保存左键设置
    IniWrite(mSkill.left.enable.Value, file, section, "LeftClickEnable")
    IniWrite(mSkill.left.interval.Value, file, section, "LeftClickInterval")
    leftModeIndex := mSkill.left.mode.Value
    IniWrite(leftModeIndex, file, section, "LeftClickMode")
    DebugLog("保存左键模式: " leftModeIndex)

    ; 保存右键设置
    IniWrite(mSkill.right.enable.Value, file, section, "RightClickEnable")
    IniWrite(mSkill.right.interval.Value, file, section, "RightClickInterval")
    rightModeIndex := mSkill.right.mode.Value
    IniWrite(rightModeIndex, file, section, "RightClickMode")
    DebugLog("保存右键模式: " rightModeIndex)

    ; 保存自动移动设置
    IniWrite(mouseAutoMove.enable.Value, file, section, "MouseAutoMoveEnable")
    IniWrite(mouseAutoMove.interval.Value, file, section, "MouseAutoMoveInterval")
}

/**
 * 保存功能键设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
SaveuSkillSettings(file, profileName) {
    global uCtrl, hotkeyControl, sleepInput
    section := profileName "_uSkill"

    ; 保存功能键（喝药、强移、闪避）
    if (uCtrl.Has("dodge")) {
        IniWrite(uCtrl["dodge"]["key"].Value, file, section, "DodgeKey")
        IniWrite(uCtrl["dodge"]["enable"].Value, file, section, "DodgeEnable")
        IniWrite(uCtrl["dodge"]["interval"].Value, file, section, "DodgeInterval")
    }
    
    if (uCtrl.Has("potion")) {
        IniWrite(uCtrl["potion"]["key"].Value, file, section, "PotionKey")
        IniWrite(uCtrl["potion"]["enable"].Value, file, section, "PotionEnable")
        IniWrite(uCtrl["potion"]["interval"].Value, file, section, "PotionInterval")
    }
    
    if (uCtrl.Has("forceMove")) {
        IniWrite(uCtrl["forceMove"]["key"].Value, file, section, "ForceMoveKey")
        IniWrite(uCtrl["forceMove"]["enable"].Value, file, section, "ForceMoveEnable")
        IniWrite(uCtrl["forceMove"]["interval"].Value, file, section, "ForceMoveInterval")
    }
    
    ; 保存其他设置
    IniWrite(uCtrl["ipPause"]["enable"].Value, file, section, "IpPauseEnable")
    IniWrite(uCtrl["dcPause"]["enable"].Value, file, section, "DcPauseEnable")
    
    ; 保存法师技能设置
    IniWrite(uCtrl["huoDun"]["key"].Value, file, section, "HuoDunKey")
    IniWrite(uCtrl["dianMao"]["key"].Value, file, section, "DianMaoKey")
    IniWrite(uCtrl["dianQiu"]["key"].Value, file, section, "DianQiuKey")
    IniWrite(uCtrl["binDun"]["key"].Value, file, section, "BinDunKey")

    ; 保存BUFF阈值和卡快照延迟
    IniWrite(buffThreshold.Value, file, section, "BuffThreshold")
    IniWrite(sleepInput.Value, file, section, "SnapSleepDelay")
    
    ; 保存全局热键
    IniWrite(hotkeyControl.Value, file, section, "StartStopKey")
    
}

/**
 * 加载设置
 * @param {String} settingsFile - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadSettings(settingsFile := "", profileName := "默认") {
    if (settingsFile = "")
        settingsFile := A_ScriptDir "\settings.ini"

    if !FileExist(settingsFile) {
        DebugLog("设置文件不存在，使用默认设置: " settingsFile)
        return
    }
    try {
        ; 加载各类设置
        LoadSkillSettings(settingsFile, profileName)
        LoadMouseSettings(settingsFile, profileName)
        LoaduSkillSettings(settingsFile, profileName)
        
        ; 每个配置都应用自己的热键和自动启停
        LoadGlobalHotkey()
        DebugLog("所有设置已从文件加载: " settingsFile " 配置方案: " profileName)
    } catch as err {
        DebugLog("加载设置出错: " err.Message)
    }

    DebugLog("自动启停模式已同步: " uCtrl["dcPause"]["enable"].Value)
}
/**
 * 加载技能设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadSkillSettings(file, profileName) {
    global cSkill, SKILL_MODE_CLICK
    section := profileName "_Skills"

    Loop 5 {
        try {
            key := IniRead(file, section, "Skill" A_Index "Key", A_Index)
            enabled := IniRead(file, section, "Skill" A_Index "Enable", 1)
            interval := IniRead(file, section, "Skill" A_Index "Interval", 20)
            mode := Integer(IniRead(file, section, "Skill" A_Index "Mode", SKILL_MODE_CLICK))

            cSkill[A_Index].key.Value := key
            cSkill[A_Index].enable.Value := enabled
            cSkill[A_Index].interval.Value := interval

            ; 设置模式下拉框
            try {
                DebugLog("尝试设置技能" A_Index "模式为: " mode)
                if (mode >= 1 && mode <= 3) {
                    ; 直接设置Text属性而不是使用Choose方法
                    if (mode == 1)
                        cSkill[A_Index].mode.Text := "连点"
                    else if (mode == 2)
                        cSkill[A_Index].mode.Text := "BUFF"
                    else if (mode == 3)
                        cSkill[A_Index].mode.Text := "按住"

                    DebugLog("成功设置技能" A_Index "模式为: " mode)
                } else {
                    cSkill[A_Index].mode.Text := "连点"
                    DebugLog("技能" A_Index "模式值无效: " mode "，使用默认连点模式")
                }
            } catch as err {
                cSkill[A_Index].mode.Text := "连点"
                DebugLog("设置技能" A_Index "模式出错: " err.Message "，使用默认连点模式")
            }
        } catch as err {
            DebugLog("加载技能" A_Index "设置出错: " err.Message)
        }
    }
}

/**
 * 加载鼠标设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadMouseSettings(file, profileName) {
    global mSkill, mouseAutoMove, mouseAutoMoveEnabled, SKILL_MODE_CLICK
    section := profileName "_Mouse"

    try {
        ; 加载左键设置
        mSkill.left.enable.Value := IniRead(file, section, "LeftClickEnable", 0)
        mSkill.left.interval.Value := IniRead(file, section, "LeftClickInterval", 80)
        leftMode := Integer(IniRead(file, section, "LeftClickMode", SKILL_MODE_CLICK))

        ; 加载右键设置
        mSkill.right.enable.Value := IniRead(file, section, "RightClickEnable", 1)
        mSkill.right.interval.Value := IniRead(file, section, "RightClickInterval", 300)
        rightMode := Integer(IniRead(file, section, "RightClickMode", SKILL_MODE_CLICK))

        ; 加载自动移动设置
        mouseAutoMove.enable.Value := IniRead(file, section, "MouseAutoMoveEnable", 0)
        mouseAutoMove.interval.Value := IniRead(file, section, "MouseAutoMoveInterval", 1000)
        mouseAutoMoveEnabled := (mouseAutoMove.enable.Value = 1)

        ; 设置左键模式下拉框
        try {
            DebugLog("尝试设置左键模式为: " leftMode)
            if (leftMode >= 1 && leftMode <= 3) {
                ; 直接设置Text属性而不是使用Choose方法
                if (leftMode == 1)
                    mSkill.left.mode.Text := "连点"
                else if (leftMode == 2)
                    mSkill.left.mode.Text := "BUFF"
                else if (leftMode == 3)
                    mSkill.left.mode.Text := "按住"

                DebugLog("成功设置左键模式为: " leftMode)
            } else {
                mSkill.left.mode.Text := "连点"
                DebugLog("左键模式值无效: " leftMode "，使用默认连点模式")
            }
        } catch as err {
            mSkill.left.mode.Text := "连点"
            DebugLog("设置左键模式出错: " err.Message "，使用默认连点模式")
        }

        ; 设置右键模式下拉框
        try {
            DebugLog("尝试设置右键模式为: " rightMode)
            if (rightMode >= 1 && rightMode <= 3) {
                ; 直接设置Text属性而不是使用Choose方法
                if (rightMode == 1)
                    mSkill.right.mode.Text := "连点"
                else if (rightMode == 2)
                    mSkill.right.mode.Text := "BUFF"
                else if (rightMode == 3)
                    mSkill.right.mode.Text := "按住"

                DebugLog("成功设置右键模式为: " rightMode)
            } else {
                mSkill.right.mode.Text := "连点"
                DebugLog("右键模式值无效: " rightMode "，使用默认连点模式")
            }
        } catch as err {
            mSkill.right.mode.Text := "连点"
            DebugLog("设置右键模式出错: " err.Message "，使用默认连点模式")
        }

        DebugLog("加载鼠标设置 - 自动移动状态: " . (mouseAutoMoveEnabled ? "启用" : "禁用"))
    } catch as err {
        DebugLog("加载鼠标设置出错: " err.Message)
    }
}

/**
 * 加载功能键设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoaduSkillSettings(file, profileName) {
    global uCtrl, hotkeyControl, sleepInput
    section := profileName "_uSkill"

    try {
        ; 加载闪避设置
        if (uCtrl.Has("dodge")) {
            uCtrl["dodge"]["key"].Value := IniRead(file, section, "DodgeKey", "Space")
            uCtrl["dodge"]["enable"].Value := IniRead(file, section, "DodgeEnable", "0")
            uCtrl["dodge"]["interval"].Value := IniRead(file, section, "DodgeInterval", "20")
        }
        
        ; 加载喝药设置
        if (uCtrl.Has("potion")) {
            uCtrl["potion"]["key"].Value := IniRead(file, section, "PotionKey", "q")
            uCtrl["potion"]["enable"].Value := IniRead(file, section, "PotionEnable", "0")
            uCtrl["potion"]["interval"].Value := IniRead(file, section, "PotionInterval", "3000")
        }
        
        ; 加载强移设置
        if (uCtrl.Has("forceMove")) {
            uCtrl["forceMove"]["key"].Value := IniRead(file, section, "ForceMoveKey", "f")
            uCtrl["forceMove"]["enable"].Value := IniRead(file, section, "ForceMoveEnable", "0")
            uCtrl["forceMove"]["interval"].Value := IniRead(file, section, "ForceMoveInterval", "50")
        }
        
        ; 加载其他设置
        uCtrl["ipPause"]["enable"].Value := IniRead(file, section, "IpPauseEnable", "1")
        uCtrl["dcPause"]["enable"].Value := IniRead(file, section, "DcPauseEnable", "1")
        
        ; 加载法师技能设置
        uCtrl["huoDun"]["key"].Value := IniRead(file, section, "HuoDunKey", "2")
        uCtrl["dianMao"]["key"].Value := IniRead(file, section, "DianMaoKey", "1")
        uCtrl["dianQiu"]["key"].Value := IniRead(file, section, "DianQiuKey", "e")
        uCtrl["binDun"]["key"].Value := IniRead(file, section, "BinDunKey", "3")

        ; 加载BUFF阈值和卡快照延迟
        thresholdValue := IniRead(file, section, "BuffThreshold", "100")
        buffThreshold.Value := thresholdValue
        buffThresholdValue.Text := thresholdValue
        
        sleepInput.Value := IniRead(file, section, "SnapSleepDelay", "2700")
        
        ; 加载全局热键
        hotkeyControl.Value := IniRead(file, section, "StartStopKey", "F1")
        
        DebugLog("成功加载功能键设置")
    } catch as err {
        DebugLog("加载功能键设置出错: " err.Message)
    }
}

/**
 * 加载全局热键
 */
/**
 * 加载全局热键
 */
LoadGlobalHotkey() {
    global currentHotkey, hotkeyControl, statusBar
    
    ; 处理空热键值
    if (hotkeyControl.Value = "") {
        ; 将热键恢复为之前的值或默认值
        hotkeyControl.Value := currentHotkey ? currentHotkey : "F1"
        statusBar.Text := "热键不能为空，已恢复为: " hotkeyControl.Value
        DebugLog("热键为空，已恢复为: " hotkeyControl.Value)
        return
    }
    
    try {
        ; 移除旧热键绑定
        if (currentHotkey != "") {
            Hotkey(currentHotkey, ToggleMacro, "Off")
            DebugLog("已解除旧热键: " currentHotkey)
        }
        
        ; 获取并验证新热键
        newHotkey := hotkeyControl.Value
      
        ; 注册新热键
        Hotkey(newHotkey, ToggleMacro, "On")
        currentHotkey := newHotkey
        DebugLog("成功注册热键: " newHotkey)  
        ; 更新状态栏
        statusBar.Text := "热键已更新: " newHotkey
    } catch as err {
        ; 处理热键注册失败的情况
        hotkeyControl.Value := currentHotkey ? currentHotkey : "F1"
        statusBar.Text := "热键设置失败: " err.Message
        DebugLog("热键设置失败: " err.Message)
    }
}

; ==================== 热键处理 ====================
#HotIf WinActive("ahk_class Diablo IV Main Window Class")

F3::{
    ; 确保从配置对象获取最新值
    dianQiuKey := uCtrl["dianQiu"]["key"].Value
    huoDunKey := uCtrl["huoDun"]["key"].Value
    dianMaoKey := uCtrl["dianMao"]["key"].Value
    binDunKey := uCtrl["binDun"]["key"].Value
    ; 获取延迟值
    sleepD := Integer(sleepInput.Value)
    ; 验证范围
    if (sleepD < 2400 || sleepD > 5000)
        sleepD := 2700

    ; 添加错误处理
    try {
        ; 执行连招
        Send "{Blind}{" binDunKey "}"  ; 使用Blind模式保持Shift状态
        Sleep 75
        Loop 4 {
            Send "{Blind}{" dianQiuKey "}"
            Sleep 850
        }
        Send "{Blind}{" huoDunKey "}"
        Sleep sleepD 
        Send "{Blind}{" dianMaoKey "}"
        Sleep 550
        ToggleMacro()
    } catch as err {
        DebugLog("F3连招出错: " err.Message)
        TrayTip "连招错误", "请检查技能键配置", 3
    }
}

~LButton::
{
    global isRunning, uCtrl, isPaused
    static lastClickTime := 0

    if (!isRunning || !uCtrl.Has("dcPause") || !uCtrl["dcPause"].Has("enable") || uCtrl["dcPause"]["enable"].Value != 1)
        return
        
    currentTime := A_TickCount
    
    if (currentTime - lastClickTime < 400) {
        DebugLog("检测到双击，暂停宏2秒")
        TogglePause("doubleClick", true)
        SetTimer(() => TogglePause("doubleClick", false), -2000)
        lastClickTime := 0
    } else {
        lastClickTime := currentTime
    }
}

; 初始化GUI
InitializeGUI()
