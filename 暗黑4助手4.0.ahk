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
global bSkill := Map()      ; 技能BUFF控件映射
global mSkill := Map()      ; 鼠标控件
global uCtrl := Map()       ; 功能键控件

; 技能模式常量
global skillMod := ["连点", "BUFF", "按住"]
global skillTimers := Map()   ; 用于存储各个技能的定时器ID
; 定时器相关变量
global holdStates := Map()         ; 跟踪按键按住状态
global keyQueue := []              ; 队列模式的操作队列
global keyQueueLastExec := Map()   ; 队列模式下每个操作的上次执行时间
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
 * 初始化GUI
 */
InitializeGUI() {
    global myGui, statusBar
    
    ; 创建主GUI窗口
    myGui := Gui("", "暗黑4助手 v4.0")
    myGui.BackColor := "FFFFFF"
    myGui.SetFont("s10", "Microsoft YaHei UI")
    
    ; 关闭窗口时保存设置并退出
    myGui.OnEvent("Close", (*) => (
        SaveSettings(),   ; 关闭窗口时自动保存设置
        ExitApp()
    ))  
    ; 按下Escape键时最小化窗口而不是退出
    myGui.OnEvent("Escape", (*) => myGui.Minimize())
    ; 创建所有控件 - 主界面、配置管理、按键设置等
    CreateMainGUI()
    CreateAllControls()
    
    ; 添加状态栏
    statusBar := myGui.AddStatusBar(, "就绪")
    
    ; 显示GUI
    myGui.Show("w480 h740")
    
    ; 初始化配置方案列表
    InitializeProfiles()
}


/**
 * 创建主GUI界面
 */
CreateMainGUI() {
    global myGui, statusText, hotkeyControl, currentProfileName, RunMod
    global profileDropDown, profileNameInput, buffThreshold, buffThresholdValue, sleepInput
    
    ; ----- 主区域 -----
    myGui.AddGroupBox("x10 y10 w460 h120", "F3: 卡快照")
    statusText := myGui.AddText("x30 y35 w400 h20", "状态: 未运行")
    myGui.AddButton("x30 y65 w80 h30", "开始/停止").OnEvent("Click", ToggleMacro)
    hotkeyControl := myGui.AddHotkey("x120 y70 w80 h20", currentHotkey)
    hotkeyControl.OnEvent("Change", (ctrl, *) => LoadGlobalHotkey())
    myGui.AddText("x30 y100 w300 h20", "提示：仅在暗黑破坏神4窗口活动时生效")

    ; ----- 运行模式 -----
    myGui.AddText("x230 y70 w70 h20", "运行模式：")
    RunMod := myGui.AddDropDownList("x300 y70 w65 h60 Choose1", ["多线程", "单线程"])
    RunMod.OnEvent("Change", (*) => (
        ; 如果宏正在运行，切换模式时重启定时器
        (isRunning && (StopAllTimers(), StartAllTimers()))
        (RunMod.Value = 2 && FillKeyQueue()), ; 切换到单线程时刷新队列
        UpdateStatus("", "宏已切换模式")
    ))
    ; ----- 配置管理区 -----
    myGui.AddGroupBox("x10 y135 w460 h65", "配置方案")
    myGui.AddText("x30 y160 w70 h20", "当前方案：")
    profileDropDown := myGui.AddDropDownList("x100 y155 w150 h120 Choose1", ["默认"])
    profileDropDown.OnEvent("Change", LoadSelectedProfile)
    profileNameInput := myGui.AddEdit("x270 y155 w100 h25", currentProfileName)
    myGui.AddButton("x375 y155 w40 h25", "保存").OnEvent("Click", SaveProfile)
    myGui.AddButton("x420 y155 w40 h25", "删除").OnEvent("Click", DeleteProfile)
    
    ; ----- BUFF检测区 -----
    myGui.AddText("x30 y245", "BUFF检测阈值:")
    buffThreshold := myGui.AddSlider("x120 y245 w100 Range50-200", 100)
    buffThresholdValue := myGui.AddText("x220 y245 w30 h20", buffThreshold.Value)
    buffThreshold.OnEvent("Change", (ctrl, *) => buffThresholdValue.Text := ctrl.Value)
    
    ; ----- 按键设置区域 -----
    myGui.AddGroupBox("x10 y210 w460 h370", "按键设置")
    
    ; ----- 快照设置区域 -----
    myGui.AddGroupBox("x10 y590 w460 h55", "快照设置")
    myGui.AddText("x300 y620 w60 h20", "快照延迟:")
    sleepInput := myGui.AddEdit("x360 y615 w40 h20", "2700")
    sleepInput.OnEvent("LoseFocus", ValidateSleepInput)
    
    ; ----- 自动启停区域 -----
    myGui.AddGroupBox("x10 y655 w460 h55", "自动启停管理")
    myGui.AddButton("x320 y680 w80 h25", "刷新检测").OnEvent("Click", RefreshDetection)
}
/**
 * 创建所有控件
 */
CreateAllControls() {
    global myGui, cSkill, mSkill, uCtrl, skillMod
    ; === 创建技能控件 ===
    cSkill := Map()
    Loop 5 {
        yPos := 280 + (A_Index-1) * 30
        myGui.AddText("x30 y" yPos " w40 h20", "技能" A_Index ":")
        cSkill[A_Index] := {
            key: myGui.AddHotkey("x90 y" yPos " w30 h20", A_Index),
            enable: myGui.AddCheckbox("x130 y" yPos " w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y" yPos " w40 h20", "20"),
            mode: myGui.AddDropDownList("x270 y" yPos " w60 h120 Choose1", skillMod)
        }
        ; 添加ms文本标签
    myGui.AddText("x240 y" yPos+5 " w20 h15", "ms")
    }

    ; === 创建鼠标控件 ===
    mSkill["left"] := Map(
        "enable", myGui.AddCheckbox("x130 y430 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y430 w40 h20", "80"),
        "mode", myGui.AddDropDownList("x270 y430 w60 h120 Choose1", skillMod)
    )
    mSkill["right"] := Map(
        "enable", myGui.AddCheckbox("x130 y460 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y460 w40 h20", "300"),
        "mode", myGui.AddDropDownList("x270 y460 w60 h120 Choose1", skillMod)
    )
    myGui.AddText("x30 y430 w40 h20", "左键:")
    myGui.AddText("x30 y460 w40 h20", "右键:")
    ; 添加ms标签
    Loop 5 {
        yPos := 435 + (A_Index-1) * 30
        myGui.AddText("x240 y" yPos " w20 h15", "ms")
    }
    ; === 创建控件 ===
    uCtrl["potion"] := Map(
        "text", myGui.AddText("x30 y490 w30 h20", "喝药:"),
        "key", myGui.AddHotkey("x90 y490 w30 h20", "q"),
        "enable", myGui.AddCheckbox("x130 y490 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y490 w40 h20", "3000")
    )
    uCtrl["forceMove"] := Map(
        "text", myGui.AddText("x30 y520 w30 h20", "强移:"),
        "key", myGui.AddHotkey("x90 y520 w30 h20", "f"),
        "enable", myGui.AddCheckbox("x130 y520 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y520 w40 h20", "50")
    )
    uCtrl["dodge"] := Map(
        "text", myGui.AddText("x30 y550 w30 h20", "空格:"),
        "key", { Value: "Space" },
        "enable", myGui.AddCheckbox("x130 y550 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y550 w40 h20", "20")
    )
    uCtrl["shift"] := Map(
        "text", myGui.AddText("x300 y505 w60 h20", "按住Shift:"),
        "enable", myGui.AddCheckbox("x360 y505 w20 h20")
    )
    uCtrl["huoDun"] := Map(
        "text", myGui.AddText("x30 y620 w30 h20", "火盾:"),
        "key", myGui.AddHotkey("x65 y615 w20 h20", "2")
    )
    uCtrl["dianMao"] := Map(
        "text", myGui.AddText("x95 y620 w30 h20", "电矛:"),
        "key", myGui.AddHotkey("x130 y615 w20 h20", "1")
    )
    uCtrl["dianQiu"] := Map(
        "text", myGui.AddText("x160 y620 w30 h20", "电球:"),
        "key", myGui.AddHotkey("x195 y615 w20 h20", "e")
    )
    uCtrl["binDun"] := Map(
        "text", myGui.AddText("x225 y620 w30 h20", "冰盾:"),
        "key", myGui.AddHotkey("x260 y615 w20 h20", "3")
    )
    uCtrl["dcPause"] := Map(
        "text", myGui.AddText("x300 y100 w60 h20", "双击暂停:"),
        "enable", myGui.AddCheckbox("x360 y100 w30 h20")
    )
    uCtrl["ipPause"] := Map(
        "text", myGui.AddText("x30 y680 w60 h20", "血条启停:"),
        "enable", myGui.AddCheckbox("x90 y680 w20 h20"),
        "interval", myGui.AddEdit("x110 y680 w40 h20", "50")
    )
    bloodInterval := uCtrl["ipPause"]["interval"]
    bloodInterval.OnEvent("LoseFocus", (ctrl, *) => ValidateTimerInterval(ctrl, "blood"))
    uCtrl["tabPause"] := Map(
        "text", myGui.AddText("x160 y680 w60 h20", "界面检测:"),
        "enable", myGui.AddCheckbox("x220 y680 w20 h20"),
        "interval", myGui.AddEdit("x240 y680 w40 h20", "50")
    )
    tabInterval := uCtrl["tabPause"]["interval"]
    tabInterval.OnEvent("LoseFocus", (ctrl, *) => ValidateTimerInterval(ctrl, "tab"))

    ; 添加鼠标自动移动控件
    uCtrl["mouseAutoMove"] := Map(
        "text", myGui.AddText("x300 y550 w60 h20", "鼠标移动:"),
        "enable", myGui.AddCheckbox("x360 y550 w15 h15"),
        "interval", myGui.AddEdit("x380 y545 w40 h20", "1000"),
        "currentPoint", 1
    )
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
    } else {
        statusText.Value := "状态: " status
        statusBar.Text := barText
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
    global isRunning, isPaused

    ; 确保完全停止所有定时器
    StopAllTimers()
    ManageTimers("none", false) ; 停止所有检测定时器
    
    ; 切换运行状态
    isRunning := !isRunning
    
    if isRunning {
        ; 初始化暂停状态
        for key, _ in isPaused {
            isPaused[key] := false
        }
        
        ; 初始化窗口分辨率和技能位置
        GetDynamicbSkill()
        
        ; 启动监控定时器
        ManageTimers("all", true)

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
        ManageTimers("none", false) ; 停止所有检测定时器
        
        ; 重置所有暂停状态
        for key, _ in isPaused {
            isPaused[key] := false
        }
        
        ; 确保释放所有按键
        ReleaseAllKeys()
        
        UpdateStatus("已停止", "宏已停止")
    }
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
    ; 释放修饰键
    Send "{Shift up}"
    Send "{Ctrl up}"
    Send "{Alt up}"

    ; 清空所有按住状态跟踪
    holdStates.Clear()
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
TogglePause(reason, state) {
    global isPaused, isRunning
    if (!isRunning)
        return
    if (!isPaused.Has(reason)) {
        isPaused[reason] := false
    }

    ; 恢复时只检测对应原因的条件
    if !state {
        res := GetWindowResolutionAndScale()
        pixelCache := Map()
        if (reason = "window") {
            if !WinActive("ahk_class Diablo IV Main Window Class")
                return
        } else if (reason = "tab") {
            colors := CheckKeyPoints(res, pixelCache)
            if (colors.isRedColor)
                return
        } else if (reason = "enter") {
            if (CheckPauseByEnter(res, pixelCache))
                return
        } else if (reason = "blood") {
            if (!CheckPauseByBlood(res, pixelCache))
                return
        } else if (reason = "doubleClick") {
            ; 双击暂停一般定时恢复，这里不做额外判断
        }
    }

    prev := IsAnyPaused()
    isPaused[reason] := state
    now := IsAnyPaused()
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
 * 启动定时器
 */
StartAllTimers() {
    global cSkill, mSkill, uCtrl, skillTimers, RunMod
    ; 清空之前的定时器
    StopAllTimers()
    if (RunMod.Value = 1) {
        Loop 5 {
            skillIndex := A_Index
            if (cSkill[skillIndex].enable.Value) {
                PressSkillCallback(skillIndex)
            }
        }
        if (mSkill["left"]["enable"].Value) {
            PressMouseCallback("left")
        }
        if (mSkill["right"]["enable"].Value) {
            PressMouseCallback("right")
        }
        if (uCtrl["dodge"]["enable"].Value) {
            PressuSkillKey("dodge")
        }
        if (uCtrl["potion"]["enable"].Value) {
            PressuSkillKey("potion")
        }
        if (uCtrl["forceMove"]["enable"].Value) {
            PressuSkillKey("forceMove")
        }
        StartAutoMove()
    } else if (RunMod.Value = 2) {
        keyQueue := []
        keyQueueLastExec := Map()
        FillKeyQueue()
        SetTimer(KeyQueueWorker, 5)
    }
}
/**
 * 停止所有定时器
 */
StopAllTimers() {
    global skillTimers
    ; 停止所有定时器
    for timerName, boundFunc in skillTimers {
        SetTimer(boundFunc, 0)
    }
    if (RunMod.Value = 2) {
        SetTimer(KeyQueueWorker, 0)
        keyQueue := []
        keyQueueLastExec := Map()
    }           
    ; 释放所有按键
    ReleaseAllKeys()
}
/**
 * 管理全局定时器
 * @param {String} timerType - 定时器类型，"window"(窗口检测)、"blood"(血条检测)、"tab"(界面检测)、"all"(所有)或"none"(无)
 * @param {Boolean} enable - 是否启用定时器
 * @param {Integer} interval - 定时器间隔(毫秒)，可选，默认值取决于定时器类型
 * @returns {Boolean} - 操作是否成功
 */
ManageTimers(timerType, enable, interval := unset) {
    static DEFAULT_INTERVALS := Map(
        "window", 100, 
        "blood", 50, 
        "tab", 100
    )
    global uCtrl

    success := true

    if (timerType = "window") {
        actualInterval := IsSet(interval) ? interval : DEFAULT_INTERVALS["window"]
        SetTimer(CheckWindow, enable ? actualInterval : 0)
    }
    else if (timerType = "blood") {
        actualInterval := IsSet(interval) ? interval : (
            uCtrl.Has("ipPause") && uCtrl["ipPause"].Has("interval") 
                ? Integer(uCtrl["ipPause"]["interval"].Value) 
                : DEFAULT_INTERVALS["blood"]
        )
        SetTimer(AutoPauseByBlood, enable ? actualInterval : 0)
    }
    else if (timerType = "tab") {
        actualInterval := IsSet(interval) ? interval : (
            uCtrl.Has("tabPause") && uCtrl["tabPause"].Has("interval") 
                ? Integer(uCtrl["tabPause"]["interval"].Value) 
                : DEFAULT_INTERVALS["tab"]
        )
        SetTimer(AutoPauseByTAB, enable ? actualInterval : 0)
    }
    else if (timerType = "all") {
        ; 分别读取各自的 interval 控件值，保证每个检测项独立
        windowInterval := DEFAULT_INTERVALS["window"]
        bloodInterval := (uCtrl.Has("ipPause") && uCtrl["ipPause"].Has("interval")) 
            ? Integer(uCtrl["ipPause"]["interval"].Value) : DEFAULT_INTERVALS["blood"]
        tabInterval := (uCtrl.Has("tabPause") && uCtrl["tabPause"].Has("interval")) 
            ? Integer(uCtrl["tabPause"]["interval"].Value) : DEFAULT_INTERVALS["tab"]
        ManageTimers("window", enable, windowInterval)
        ManageTimers("blood", enable, bloodInterval)
        ManageTimers("tab", enable, tabInterval)
    }
    else if (timerType = "none") {
        SetTimer(CheckWindow, 0)
        SetTimer(AutoPauseByBlood, 0)
        SetTimer(AutoPauseByTAB, 0)
    }
    else {
        success := false
    }
    return success
}

/**
 * 验证定时器间隔输入并提供反馈
 * @param {Object} ctrl - 控件对象
 * @param {String} timerType - 定时器类型
 */
ValidateTimerInterval(ctrl, timerType) {
    global statusBar, isRunning
    
    ; 默认值设置
    defaultValue := timerType == "blood" ? 50 : 100
    typeText := timerType == "blood" ? "血条检测" : "界面检测"
    
    try {
        val := Integer(ctrl.Value)
        
        ; 范围检查 (10-1000ms)
        if (val < 10 || val > 1000) {
            ctrl.Value := defaultValue
            statusBar.Text := "定时器间隔必须在10-1000毫秒范围内，已重置为" defaultValue "ms"
            return defaultValue
        }
        
        ; 构建状态消息
        statusMsg := typeText "间隔已更新: " val "ms"
        
        ; 添加提示
        if (isRunning)
            statusMsg .= " (点击'刷新检测'按钮使更改生效)"
            
        if (val < 30)
            statusMsg .= " - 注意：过低的间隔可能会影响性能"
            
        statusBar.Text := statusMsg
    } catch {
        ctrl.Value := defaultValue
        statusBar.Text := "请输入有效数字，已重置为" defaultValue "ms"
    }
    
    return Integer(ctrl.Value)
}

/**
 * 立即刷新所有检测
 */
RefreshDetection(*) {
    global isRunning, statusBar, uCtrl
    
    if (!isRunning) {
        statusBar.Text := "宏未运行，无需刷新检测"
        return
    }
    
    ; 停止然后重启所有定时器
    ManageTimers("none", false)
    
    ; 使用当前设置的间隔重新启动定时器
    ; 窗口检测使用固定100ms间隔
    ; 血条和界面检测使用用户设置的间隔
    bloodInterval := Integer(uCtrl["ipPause"]["interval"].Value)
    tabInterval := Integer(uCtrl["tabPause"]["interval"].Value)
    
    ManageTimers("window", true, 100)
    ManageTimers("blood", true, bloodInterval)
    ManageTimers("tab", true, tabInterval)
    
    statusBar.Text := "已刷新所有检测定时器"
}

/**
 * 获取模式枚举值
 * @param {Object} modeControl - 模式控件对象
 * @returns {Integer} - 模式枚举值
 */
StartAutoMove() {
    global uCtrl, isRunning

    ; 检查鼠标自动移动是否启用
    if (uCtrl["mouseAutoMove"]["enable"].Value) {
        interval := Integer(uCtrl["mouseAutoMove"]["interval"].Value)
        if (interval > 0) {
            ; 立即移动一次鼠标，然后设置定时器
            MoveMouseToNextPoint()
            SetTimer(MoveMouseToNextPoint, interval)
        }
    } else {
        SetTimer(MoveMouseToNextPoint, 0)
    }
}

; ==================== 按键与技能处理 ====================
/**
 * 通用按键处理
 * @param {String} keyOrBtn - 键名或鼠标按钮名
 * @param {Integer} mode - 模式编号 (1: 连点, 2: BUFF, 3: 按住)
 * @param {Object} pos - BUFF检测坐标对象（可选）
 * @param {String} type - "key"、"mouse" 或 "uSkill"
 * @param {String} mouseBtn - 鼠标按钮名（如"left"/"right"，仅type为mouse时用）
 * @param {String} description - 按键描述（用于日志）
 */
HandleKeyMode(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "", description := "") {
    global uCtrl, buffThreshold, holdStates
    static lastReholdTime := Map()     ; 存储每个按键上次重新按住的时间
    static REHOLD_MIN_INTERVAL := 2000 ; 重新按住的最小间隔(毫秒)
    
    ; 快速返回检查
    if (IsAnyPaused())
        return
    ; 生成唯一键标识符
    uniqueKey := type ":" (type="mouse" ? mouseBtn : keyOrBtn)
    
    ; 预先确定是否为鼠标操作
    isMouse := (type = "mouse")
    ; 获取当前Shift状态
    shiftEnabled := uCtrl["shift"]["enable"].Value
    ; 确定按键
    currentTime := A_TickCount

    ; 按照模式分类处理
    switch mode {
        case 2: ; BUFF模式
            ; 只在技能未激活时执行
            if (pos && IsSkillActive(pos.x, pos.y))
                return
                
            ; 执行按键操作
            if (isMouse) {
                shiftEnabled ? SendWithShift(mouseBtn) : Click(mouseBtn)
            } else {
                shiftEnabled ? SendWithShift(keyOrBtn) : Send("{" keyOrBtn "}")
            }
            
        case 3: ; 按住模式
            needPress := false
            isHeld := holdStates.Has(uniqueKey) && holdStates[uniqueKey]
            
            if (!isHeld) {
                ; 首次按下
                needPress := true
                holdStates[uniqueKey] := true
                lastReholdTime[uniqueKey] := currentTime
            } 
            else if (!lastReholdTime.Has(uniqueKey) || 
                    (currentTime - lastReholdTime[uniqueKey] > REHOLD_MIN_INTERVAL)) {
                ; 需要重新按住
                needPress := true
                lastReholdTime[uniqueKey] := currentTime
            }
            
            ; 执行按键动作（只在需要时执行）
            if (needPress) {
                if (shiftEnabled && !isHeld)
                    Send "{Shift down}"
                    
                if (isMouse) {
                    if (isHeld)
                        Click("up " mouseBtn)
                    Click("down " mouseBtn)
                } else {
                    if (isHeld)
                        Send("{" keyOrBtn " up}")
                    Send("{" keyOrBtn " down}")
                }
            }
            
        default: ; 连点模式(1)
            ; 执行简单点击
            if (isMouse) {
                shiftEnabled ? SendWithShift(mouseBtn) : Click(mouseBtn)
            } else {
                shiftEnabled ? SendWithShift(keyOrBtn) : Send("{" keyOrBtn "}")
            }
    }
}

; ==================== 队列模式实现 ====================
/**
 * 队列填充函数：将所有启用的技能、鼠标、功能键操作入队
 */
FillKeyQueue() {
    global cSkill, mSkill, uCtrl, bSkill
    ; 技能
    Loop 5 {
        idx := A_Index
        if (cSkill[idx].enable.Value) {
            EnqueueKey(
                cSkill[idx].key.Value,
                cSkill[idx].mode.Value,
                bSkill.Has(idx) ? bSkill[idx] : "",
                "key", "", "技能" idx,
                Integer(cSkill[idx].interval.Value)
            )
        }
    }
    ; 鼠标
    for btn in ["left", "right"] {
        if (mSkill[btn]["enable"].Value) {
            EnqueueKey(
                btn,
                mSkill[btn]["mode"].Value,
                bSkill.Has(btn) ? bSkill[btn] : "",
                "mouse", btn, "鼠标" btn,
                Integer(mSkill[btn]["interval"].Value)
            )
        }
    }
    ; 功能键
    for u in ["dodge", "potion", "forceMove"] {
        if (uCtrl.Has(u) && uCtrl[u]["enable"].Value) {
            EnqueueKey(
                uCtrl[u]["key"].Value,
                1,
                bSkill.Has(u) ? bSkill[u] : "",
                "key", "", u,
                Integer(uCtrl[u]["interval"].Value)
            )
        }
    }
}

/**
 * 添加到队列的通用函数
 * 避免添加重复操作类型，保证按照设定的间隔执行
 */
EnqueueKey(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "", description := "", interval := 1000) {
    global keyQueue
    ; 生成唯一ID
    uniqueId := type ":" (type="mouse" ? mouseBtn : keyOrBtn)
    ; 优先级计算
    getPriority := (mode) => (
        mode = 2 ? 3
        : mode = 3 ? 2
        : mode = 1 ? 1
        : 0
    )
    ; 检查队列中是否已有相同唯一ID的操作
    for i, existingItem in keyQueue {
        existingId := existingItem.type ":" (existingItem.type="mouse" ? existingItem.mouseBtn : existingItem.keyOrBtn)
        if (existingId = uniqueId) {
            ; 只更新优先级、模式、描述、interval，不刷新time，保证interval生效
            existingItem.priority := getPriority(mode)
            existingItem.mode := mode
            existingItem.pos := pos
            existingItem.description := description
            existingItem.interval := interval
            return
        }
    }
    ; 如果队列中没有相同类型的操作，添加新操作
    item := {
        keyOrBtn: keyOrBtn, mode: mode, pos: pos, type: type,
        mouseBtn: mouseBtn, description: description,
        time: A_TickCount, interval: interval,
        priority: getPriority(mode)
    }
    ; 队列最大长度限制
    maxLen := 20
    if (keyQueue.Length >= maxLen) {
        keyQueue.Pop()
    }
    ; 优先级插入（二分查找法）
    left := 1
    right := keyQueue.Length
    while (left <= right) {
        mid := Floor((left + right) / 2)
        if (item.priority > keyQueue[mid].priority) {
            right := mid - 1
        } else {
            left := mid + 1
        }
    }
    keyQueue.InsertAt(left, item)
}
/**
 * 队列处理定时器（精准间隔支持）
 * 每个队列项被执行后，立即补充自身，保证interval大于50ms时也能正常触发
 */
KeyQueueWorker() {
    global keyQueue, keyQueueLastExec
    if (keyQueue.Length = 0)
        return
    now := A_TickCount
    for i, item in keyQueue {
        uniqueId := item.type ":" (item.type="mouse" ? item.mouseBtn : item.keyOrBtn)
        interval := item.interval
        last := keyQueueLastExec.Has(uniqueId) ? keyQueueLastExec[uniqueId] : 0
        if (now - last >= interval) {
            HandleKeyMode(item.keyOrBtn, item.mode, item.pos, item.type, item.mouseBtn, item.description)
            keyQueueLastExec[uniqueId] := now
            keyQueue.RemoveAt(i)
            ; 重新入队，保证持续性
            EnqueueKey(item.keyOrBtn, item.mode, item.pos, item.type, item.mouseBtn, item.description, interval)
            break
        }
    }
}
; ==================== 按键回调函数 ====================

/**
 * 按下技能按键的回调函数
 * @param {Integer} skillNum - 技能索引 (1-5)
 */
PressSkillCallback(skillNum) {
    global cSkill, skillTimers, skillMod, RunMod
    timerKey := "skill" skillNum
    ; 先停止并移除旧定时器
    if (skillTimers.Has(timerKey)) {
        SetTimer(skillTimers[timerKey], 0)
        skillTimers.Delete(timerKey)
    }
    if (!cSkill[skillNum].enable.Value)
        return
    key := cSkill[skillNum].key.Value
    mode := cSkill[skillNum].mode.Value
    pos := bSkill.Has(skillNum) ? bSkill[skillNum] : ""
    interval := Integer(cSkill[skillNum].interval.Value)
    boundFunc := (RunMod.Value = 1)
        ? HandleKeyMode.Bind(key, mode, pos, "key", "", "技能" skillNum)
        : EnqueueKey.Bind(key, mode, pos, "key", "", "技能" skillNum, interval)
    skillTimers[timerKey] := boundFunc
    SetTimer(boundFunc, interval)
}

/**
 * 按下鼠标按键的回调函数
 * @param {String} mouseBtn - 鼠标按钮名 (left/right)
 */
PressMouseCallback(mouseBtn) {
    global mSkill, skillTimers, skillMod, RunMod
    timerKey := "mouse" mouseBtn
    if (skillTimers.Has(timerKey)) {
        SetTimer(skillTimers[timerKey], 0)
        skillTimers.Delete(timerKey)
    }
    if (mSkill[mouseBtn]["enable"].Value) {
        mode := mSkill[mouseBtn]["mode"].Value
        pos := bSkill.Has(mouseBtn) ? bSkill[mouseBtn] : ""
        interval := Integer(mSkill[mouseBtn]["interval"].Value)
        boundFunc := (RunMod.Value = 1)
            ? HandleKeyMode.Bind(mouseBtn, mode, pos, "mouse", mouseBtn, "鼠标" mouseBtn)
            : EnqueueKey.Bind(mouseBtn, mode, pos, "mouse", mouseBtn, "鼠标" mouseBtn, interval)
        skillTimers[timerKey] := boundFunc
        SetTimer(boundFunc, interval)
    }
}

/**
 * 按下功能键的回调函数
 * @param {String} uSkillId - 功能键ID
 */
PressuSkillKey(uSkillId) {
    global uCtrl, skillTimers, RunMod
    timerKey := "uSkill" uSkillId
    if (skillTimers.Has(timerKey)) {
        SetTimer(skillTimers[timerKey], 0)
        skillTimers.Delete(timerKey)
    }
    if (uCtrl[uSkillId]["enable"].Value) {
        mode := 1
        pos := bSkill.Has(uSkillId) ? bSkill[uSkillId] : ""
        interval := Integer(uCtrl[uSkillId]["interval"].Value)
        boundFunc := (RunMod.Value = 1)
            ? HandleKeyMode.Bind(uCtrl[uSkillId]["key"].Value, mode, pos, "key", "", uSkillId)
            : EnqueueKey.Bind(uCtrl[uSkillId]["key"].Value, mode, pos, "key", "", uSkillId, interval)
        skillTimers[timerKey] := boundFunc
        SetTimer(boundFunc, interval)
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
 * 鼠标自动移动函数
 */
MoveMouseToNextPoint() {
    global isRunning, uCtrl, isPaused

    ; 检查各种条件
    if (!isRunning || IsAnyPaused() || !uCtrl["mouseAutoMove"]["enable"].Value)
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

        ; 确保currentPoint字段存在
        if (!uCtrl["mouseAutoMove"].Has("currentPoint"))
            uCtrl["mouseAutoMove"]["currentPoint"] := 1

        ; 获取当前点索引
        currentIndex := uCtrl["mouseAutoMove"]["currentPoint"]
        
        ; 验证索引范围
        if (currentIndex < 1 || currentIndex > points.Length)
            currentIndex := 1
            
        ; 移动鼠标到当前点
        currentPoint := points[currentIndex]
        MouseMove(currentPoint.x, currentPoint.y, 0)

        ; 更新到下一个点
        uCtrl["mouseAutoMove"]["currentPoint"] := Mod(currentIndex, 6) + 1

    }
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
GetDynamicbSkill() {
    global bSkill
    res := GetWindowResolutionAndScale()
    baseX := 1550, baseY := 1940, offset := 127

    ; 清空并填充技能位置
    bSkill.Clear()
    Loop 5 {
        idx := A_Index
        bSkill[idx] := {
            x: Round((baseX + offset * (idx - 1)) * res.scale),
            y: Round(baseY * res.scale)
        }
    }
    bSkill["left"] := {
        x: Round((baseX + offset * 4) * res.scale),
        y: Round(baseY * res.scale)
    }
    bSkill["right"] := {
        x: Round((baseX + offset * 5) * res.scale),
        y: Round(baseY * res.scale)
    }
}


; ==================== 像素检测与暂停机制 ====================
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
    Loop 6 {
        x := Round(baseX + offset * (A_Index - 1))
        y := baseY
        key := "enter" A_Index
        colorObj := (IsSet(pixelCache) && pixelCache.Has(key)) ? pixelCache[key] : GetPixelRGB(x, y)
        if (colorObj.r > 100 && colorObj.g < 60 && colorObj.b < 60) {
            return true
        }
    }
    return false
}

/**
 * 专用的血条检测函数
 * 支持像素缓存，避免重复采样
 */
CheckPauseByBlood(res := unset, pixelCache := unset) {
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
AutoPauseByBlood() {
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

    if (CheckPauseByBlood(res, pixelCache)) {
        TogglePause("blood", false)
        UpdateStatus("运行中", "检测到血条，自动启动")
    } else { 
        TogglePause("blood", true)
        UpdateStatus("已暂停", "血条消失，自动暂停")
    }
}

/**
 * 定时检测界面状态并自动暂停/启动宏
 * 检测TAB键打开的界面和对话框
 */
AutoPauseByTAB() {
    global isRunning, isPaused, uCtrl
    
    ; 如果宏未运行或界面检测未启用，则直接返回
    if (!isRunning || uCtrl["tabPause"]["enable"].Value != 1)
        return 
        
    try {
        res := GetWindowResolutionAndScale()
        
        ; 统一采样所有关键点
        pixelCache := Map()
        
        ; 界面检测
        dfx := Round(1535 * res.scaleW), dty := Round(1880 * res.scaleH)
        tabx := Round(3795 * res.scaleW), tab := Round(90 * res.scaleH)
        pixelCache["dfx"] := GetPixelRGB(dfx, dty)
        pixelCache["tab"] := GetPixelRGB(tabx, tab)
        
        ; 对话框检测
        baseX := Round(30 * res.scaleW)
        baseY := Round(1440 * res.scaleH)
        offset := Round(90 * res.scaleW)
        Loop 6 {
            x := Round(baseX + offset * (A_Index - 1))
            y := baseY
            pixelCache["enter" A_Index] := GetPixelRGB(x, y)
        }

        ; 检查界面状态
        colors := CheckKeyPoints(res, pixelCache)
        enterDetected := CheckPauseByEnter(res, pixelCache)

        ; 根据检测结果设置暂停状态
        if (colors.isRedColor) {
            TogglePause("tab", true)
            UpdateStatus("已暂停", "检测到地图界面，自动暂停")
        } 
        else if (enterDetected) {
            TogglePause("enter", true)
            UpdateStatus("已暂停", "检测到确认对话框，自动暂停")
        }
        else if (isPaused["tab"] || isPaused["enter"]) {
            ; 恢复操作
            if (isPaused["tab"]) {
                TogglePause("tab", false)
                UpdateStatus("运行中", "界面关闭，自动恢复")
            }
            if (isPaused["enter"]) {
                TogglePause("enter", false)
                UpdateStatus("运行中", "确认对话框消失，自动恢复")
            }
        }
    } catch as err {
        UpdateStatus("错误", "检测出错")
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
        return {r: 0, g: 0, b: 0}  ; 失败时返回黑色
    }
}

; ==================== 设置管理 ====================
/**
 * 初始化配置方案列表
 */
InitializeProfiles() {
    global profileList, profileDropDown, currentProfileName
    
    ; 主配置文件路径
    settingsFile := A_ScriptDir "\settings.ini"
    
    ; 确保配置文件所在目录存在
    settingsDir := RegExReplace(settingsFile, "[^\\]+$", "")
    if (!DirExist(settingsDir) && settingsDir != "") {
        try {
            DirCreate(settingsDir)
        } catch {
            ; 创建目录失败时继续尝试
        }
    }
    
    ; 确保配置文件存在
    if (!FileExist(settingsFile)) {
        ; 创建默认配置文件
        try {
            FileAppend("[Profiles]`nList=默认`n`n[Global]`nLastUsedProfile=默认`n`n", settingsFile)
        } catch {
            ; 文件创建失败时继续使用内存中的默认值
        }
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
        ; 如果读取失败，尝试重写Profiles段
        try {
            IniWrite("默认", settingsFile, "Profiles", "List")
        } catch {
            ; 写入失败时继续使用内存中的默认值
        }
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
        ; 尝试写入Global段
        try {
            IniWrite("默认", settingsFile, "Global", "LastUsedProfile")
        } catch {
            ; 写入失败时继续
        }
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
    ; 快速检查空数组
    if (arr.Length == 0)
        return false
        
    for i, v in arr {
        if (v == val)  ; 使用严格相等比较
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
    ; 快速处理空数组
    if (arr.Length == 0)
        return ""
        
    ; 单元素数组无需分隔符处理
    if (arr.Length == 1)
        return arr[1]
        
    result := ""
    arrLen := arr.Length
    
    for i, v in arr {
        result .= v
        ; 只在非最后一个元素后添加分隔符
        if (i < arrLen)
            result .= delimiter
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

    ; 检查文件所在目录是否存在，如果不存在则创建
    settingsDir := RegExReplace(settingsFile, "[^\\]+$", "")
    if (!DirExist(settingsDir) && settingsDir != "") {
        try {
            DirCreate(settingsDir)
        } catch as err {
            statusBar.Text := "创建目录失败: " err.Message
            return
        }
    }
    
    ; 如果文件不存在，创建一个基本结构
    if (!FileExist(settingsFile)) {
        try {
            FileAppend("[Profiles]`nList=默认`n`n[Global]`nLastUsedProfile=" profileName "`n`n", settingsFile)
            statusBar.Text := "已创建新的设置文件"
        } catch as err {
            statusBar.Text := "创建设置文件失败: " err.Message
            return
        }
    }

    ; 确认已有设置节不存在
    DeleteProfileSettings(settingsFile, profileName)

    if (hotkeyControl.Value = "") {
        hotkeyControl.Value := "F1"
    }
    
    try {
        ; 保存各类设置
        SaveSkillSettings(settingsFile, profileName)
        SaveMouseSettings(settingsFile, profileName)
        SaveuSkillSettings(settingsFile, profileName)
        LoadGlobalHotkey()

        statusBar.Text := "设置已保存"
    } catch as err {
        statusBar.Text := "保存设置失败: " err.Message
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
    global mSkill, uCtrl
    section := profileName "_Mouse"

    ; 保存左键设置
    IniWrite(mSkill["left"]["enable"].Value, file, section, "LeftClickEnable")
    IniWrite(mSkill["left"]["interval"].Value, file, section, "LeftClickInterval")
    leftModeIndex := mSkill["left"]["mode"].Value
    IniWrite(leftModeIndex, file, section, "LeftClickMode")

    ; 保存右键设置
    IniWrite(mSkill["right"]["enable"].Value, file, section, "RightClickEnable")
    IniWrite(mSkill["right"]["interval"].Value, file, section, "RightClickInterval")
    rightModeIndex := mSkill["right"]["mode"].Value
    IniWrite(rightModeIndex, file, section, "RightClickMode")

    ; 保存自动移动设置
    IniWrite(uCtrl["mouseAutoMove"]["enable"].Value, file, section, "MouseAutoMoveEnable")
    IniWrite(uCtrl["mouseAutoMove"]["interval"].Value, file, section, "MouseAutoMoveInterval")
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
    IniWrite(uCtrl["ipPause"]["interval"].Value, file, section, "IpPauseInterval")
    IniWrite(uCtrl["tabPause"]["enable"].Value, file, section, "TabPauseEnable") 
    IniWrite(uCtrl["tabPause"]["interval"].Value, file, section, "TabPauseInterval")
    IniWrite(uCtrl["dcPause"]["enable"].Value, file, section, "DcPauseEnable")
    IniWrite(uCtrl["shift"]["enable"].Value, file, section, "ShiftEnabled")
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
    ; 保存运行模式
    IniWrite(RunMod.Value, file, section, "RunMod")
}

/**
 * 加载设置
 * @param {String} settingsFile - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadSettings(settingsFile := "", profileName := "默认") {
    global statusBar
    
    if (settingsFile = "")
        settingsFile := A_ScriptDir "\settings.ini"

    if (!FileExist(settingsFile)) {
        ; 文件不存在时创建空文件
        try {
            settingsDir := RegExReplace(settingsFile, "[^\\]+$", "")
            if (!DirExist(settingsDir) && settingsDir != "") {
                DirCreate(settingsDir)
            }
            
            FileAppend("[Profiles]`nList=默认`n`n[Global]`nLastUsedProfile=" profileName "`n`n", settingsFile)
            statusBar.Text := "已创建新的设置文件"
            
            ; 保存当前设置以初始化文件
            SaveSettings(settingsFile, profileName)
            return
        } catch as err {
            statusBar.Text := "创建设置文件失败"
            return
        }
    }

    try {
        ; 加载各类设置
        LoadSkillSettings(settingsFile, profileName)
        LoadMouseSettings(settingsFile, profileName)
        LoaduSkillSettings(settingsFile, profileName)
        
        ; 每个配置都应用自己的热键和自动启停
        LoadGlobalHotkey()
        statusBar.Text := "设置已加载"
    } catch as err {
        statusBar.Text := "加载设置出错"
    }
}
/**
 * 加载技能设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadSkillSettings(file, profileName) {
    global cSkill
    section := profileName "_Skills"

    Loop 5 {
        try {
            key := IniRead(file, section, "Skill" A_Index "Key", A_Index)
            enabled := IniRead(file, section, "Skill" A_Index "Enable", 1)
            interval := IniRead(file, section, "Skill" A_Index "Interval", 20)
            mode := Integer(IniRead(file, section, "Skill" A_Index "Mode", 1))

            cSkill[A_Index].key.Value := key
            cSkill[A_Index].enable.Value := enabled
            cSkill[A_Index].interval.Value := interval

            ; 设置模式下拉框
            try {
                if (mode >= 1 && mode <= 3) {
                    cSkill[A_Index].mode.Value := mode
                }
            } catch as err {
                cSkill[A_Index].mode.Value := 1
            }
        } catch as err {
            ; 如果读取失败，使用默认值
            cSkill[A_Index].key.Value := A_Index
            cSkill[A_Index].enable.Value := 1
            cSkill[A_Index].interval.Value := 20
            cSkill[A_Index].mode.Value := 1
        }
    }
}

/**
 * 加载鼠标设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadMouseSettings(file, profileName) {
    global mSkill, uCtrl
    section := profileName "_Mouse"

    try {
        ; 加载左键设置
        mSkill["left"]["enable"].Value := IniRead(file, section, "LeftClickEnable", 0)
        mSkill["left"]["interval"].Value := IniRead(file, section, "LeftClickInterval", 80)
        leftMode := Integer(IniRead(file, section, "LeftClickMode", 1))

        ; 加载右键设置
        mSkill["right"]["enable"].Value := IniRead(file, section, "RightClickEnable", 1)
        mSkill["right"]["interval"].Value := IniRead(file, section, "RightClickInterval", 300)
        rightMode := Integer(IniRead(file, section, "RightClickMode", 1))

        ; 加载自动移动设置
        uCtrl["mouseAutoMove"]["enable"].Value := IniRead(file, section, "MouseAutoMoveEnable", 0)
        uCtrl["mouseAutoMove"]["interval"].Value := IniRead(file, section, "MouseAutoMoveInterval", 1000)
        if (!uCtrl["mouseAutoMove"].Has("currentPoint"))
            uCtrl["mouseAutoMove"]["currentPoint"] := 1
        ; 设置左键模式下拉框
        try {
            if (leftMode >= 1 && leftMode <= 3) {
                mSkill["left"]["mode"].Value := leftMode
            }
        } catch as err {
            mSkill["left"]["mode"].Value := 1
        }

        ; 设置右键模式下拉框
        try {
            if (rightMode >= 1 && rightMode <= 3) {
                mSkill["right"]["mode"].Value := rightMode
            }
        } catch as err {
            mSkill["right"]["mode"].Value := 1
        }
    } catch as err {
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
        uCtrl["ipPause"]["interval"].Value := IniRead(file, section, "IpPauseInterval", "50")
        uCtrl["tabPause"]["enable"].Value := IniRead(file, section, "TabPauseEnable", "1")
        uCtrl["tabPause"]["interval"].Value := IniRead(file, section, "TabPauseInterval", "100")
        uCtrl["dcPause"]["enable"].Value := IniRead(file, section, "DcPauseEnable", "1")
        uCtrl["shift"]["enable"].Value := IniRead(file, section, "ShiftEnabled", "0")

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
        modeValue := Integer(IniRead(file, section, "RunMod", 1))
            if (modeValue = 1 || modeValue = 2) {
            RunMod.Value := modeValue  ; 使用正确的控件变量
        }       
    } catch as err {
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
        return
    }
    
    try {
        ; 移除旧热键绑定
        if (currentHotkey != "") {
            Hotkey(currentHotkey, ToggleMacro, "Off")
        }
        
        ; 获取并验证新热键
        newHotkey := hotkeyControl.Value
      
        ; 注册新热键
        Hotkey(newHotkey, ToggleMacro, "On")
        currentHotkey := newHotkey 
        ; 更新状态栏
        statusBar.Text := "热键已更新: " newHotkey
    } catch as err {
        ; 处理热键注册失败的情况
        hotkeyControl.Value := currentHotkey ? currentHotkey : "F1"
        statusBar.Text := "热键设置失败: " err.Message
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
        TogglePause("doubleClick", true)
        SetTimer(() => TogglePause("doubleClick", false), -2000)
        lastClickTime := 0
    } else {
        lastClickTime := currentTime
    }
}

; 初始化GUI
InitializeGUI()