#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

; ========== 全局变量定义 ==========
; 核心状态变量
global DEBUG := false              ; 是否启用调试模式
global debugLogFile := A_ScriptDir "\debugd4.log"
global isRunning := false          ; 宏是否运行中
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

;|===============================================================|
;| 函数: InitializeGUI
;| 功能: 初始化主程序GUI界面
;|===============================================================|
InitializeGUI() {
    global myGui, statusBar

    ;# ==================== GUI基础设置 ==================== #
    myGui := Gui("", "暗黑4助手 v5.1")
    myGui.BackColor := "FFFFFF"                    ; 背景色设为白色
    myGui.SetFont("s10", "Microsoft YaHei UI")    ; 设置默认字体

    ;# ==================== 系统托盘菜单 ==================== #
    A_TrayMenu.Delete()  ; 清空默认菜单
    A_TrayMenu.Add("显示主界面", (*) => myGui.Show())
    A_TrayMenu.Add()  ; 分隔线
    A_TrayMenu.Add("开始/停止宏", ToggleMacro)
    A_TrayMenu.Add()  ; 分隔线
    A_TrayMenu.Add("退出", (*) => ExitApp())
    A_TrayMenu.Default := "显示主界面"  ; 设置默认菜单项

    ;|------------------- 窗口事件绑定 -------------------|
    myGui.OnEvent("Escape", (*) => myGui.Minimize())  ; ESC键最小化
    myGui.OnEvent("Close", (*) => ExitApp())          ; 关闭按钮退出

    ;# ==================== 界面构建 ==================== #
    CreateMainGUI()     ; 创建主界面框架
    CreateAllControls() ; 初始化所有功能控件

    ;# ==================== 状态栏 ==================== #
    statusBar := myGui.AddStatusBar(, "就绪")  ; 底部状态栏初始化

    ;# ==================== 窗口显示 ==================== #
    myGui.Show("w480 h620")

    ;# ==================== 配置初始化 ==================== #
    InitializeProfiles()
}

;|===============================================================|
;| 函数: CreateMainGUI
;| 功能: 创建主程序界面及所有控件
;|===============================================================|
CreateMainGUI() {
    global myGui, statusText, hotkeyControl, ProfileName, RunMod
    global profileDropDown, hotkeyModeDropDown

    ;# ==================== 主控制区域 ==================== #
    myGui.AddGroupBox("x10 y10 w280 h120", "运行模式: ")
    statusText := myGui.AddText("x30 y35 w140 h20", "状态: 未运行")  ; 状态指示器
    myGui.AddButton("x30 y65 w80 h30", "开始/停止").OnEvent("Click", ToggleMacro)
    ;# ==================== 热键控制区域 ==================== #
    hotkeyModeDropDown := myGui.AddDropDownList("x205 y70 w65 h90 Choose1", ["自定义", "侧键1", "侧键2"])
    hotkeyModeDropDown.OnEvent("Change", OnHotkeyModeChange)
    hotkeyControl := myGui.AddHotkey("x120 y70 w80 h20", "F1")
    hotkeyControl.OnEvent("Change", (ctrl, *) => LoadGlobalHotkey())

    ;# ==================== 运行模式选择 ==================== #
    RunMod := myGui.AddDropDownList("x90 y8 w65 h60 Choose1", ["多线程", "单线程"])
    RunMod.OnEvent("Change", (*) => (TogglePause()))

    ;# ==================== 配置管理区域 ==================== #
    myGui.AddGroupBox("x300 y10 w170 h120", "配置方案")
    profileDropDown := myGui.AddDropDownList("x320 y35 w60 h120 Choose1", ["默认"])
    profileDropDown.OnEvent("Change", LoadSelectedProfile)
    profileName := myGui.AddEdit("x390 y35 w50 h20", "默认")
    myGui.AddButton("x320 y75 w40 h25", "保存").OnEvent("Click", SaveProfile)
    myGui.AddButton("x370 y75 w40 h25", "删除").OnEvent("Click", DeleteProfile)

    ;# ==================== 按键设置主区域 ==================== #
    myGui.AddGroupBox("x10 y210 w460 h370", "按键设置")

    ;|----------------------- 自动启停 -----------------------|
    myGui.AddGroupBox("x10 y130 w460 h80", "启停管理")
    myGui.AddText("x30 y185 w50 h20", "灵敏度:")
    myGui.AddButton("x350 y150 w80 h25", "刷新检测").OnEvent("Click", RefreshDetection)
}

;|===============================================================|
;| 函数: CreateAllControls
;| 功能: 创建主界面所有GUI控件并初始化配置
;|===============================================================|
CreateAllControls() {
    global myGui, cSkill, mSkill, uCtrl, skillMod

    cSkill := Map()
    mSkill := Map()
    uCtrl := Map()
    skillMod := ["连点", "BUFF", "按住", "资源"]

    ;|----------------------- 技能配置 -----------------------|
    loop 5 {
        yPos := 280 + (A_Index - 1) * 30

        ; 技能标签
        myGui.AddText("x30 y" yPos " w40 h20", "技能" A_Index ":")

        ; 技能配置Map
        cSkill[A_Index] := Map(
            "key", myGui.AddHotkey("x90 y" yPos " w30 h20", A_Index),
            "enable", myGui.AddCheckbox("x130 y" yPos " w45 h20", "启用"),
            "interval", myGui.AddEdit("x200 y" yPos " w40 h20", "20"),
            "mode", myGui.AddDropDownList("x270 y" yPos " w60 h120 Choose1", skillMod)
        )

        ; 间隔时间单位标签
        myGui.AddText("x240 y" yPos + 5 " w20 h15", "ms")
    }

    ;|----------------------- 左键配置 -----------------------|
    mSkill["left"] := Map(
        "text", myGui.AddText("x30 y430 w40 h20", "左键:"),
        "key", "LButton",  ; 固定键值
        "enable", myGui.AddCheckbox("x130 y430 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y430 w40 h20", "80"),
        "mode", myGui.AddDropDownList("x270 y430 w60 h120 Choose1", skillMod)
    )

    ;|----------------------- 右键配置 -----------------------|
    mSkill["right"] := Map(
        "text", myGui.AddText("x30 y460 w40 h20", "右键:"),
        "key", "RButton",  ; 固定键值
        "enable", myGui.AddCheckbox("x130 y460 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y460 w40 h20", "300"),
        "mode", myGui.AddDropDownList("x270 y460 w60 h120 Choose1", skillMod)
    )

    ; 为鼠标控件添加ms单位标签
    loop 5 {
        yPos := 435 + (A_Index - 1) * 30
        myGui.AddText("x240 y" yPos " w20 h15", "ms")
    }

    ;|---------------------- 基础功能 ------------------------|
    uCtrl["potion"] := Map(
        "text", myGui.AddText("x30 y490 w30 h20", "喝药:"),
        "key", myGui.AddHotkey("x90 y488 w30 h20", "q"),
        "enable", myGui.AddCheckbox("x130 y490 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y490 w40 h20", "3000")
    )

    uCtrl["forceMove"] := Map(
        "text", myGui.AddText("x30 y520 w30 h20", "强移:"),
        "key", myGui.AddHotkey("x90 y518 w30 h20", "f"),
        "enable", myGui.AddCheckbox("x130 y520 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y520 w40 h20", "50")
    )

    ;|---------------------- 闪避功能 ------------------------|
    uCtrl["dodge"] := Map(
        "text", myGui.AddText("x30 y555 w30 h20", "闪避:"),
        "key", myGui.AddHotkey("x90 y553 w30 h20", "Space"),
        "enable", myGui.AddCheckbox("x130 y550 w45 h20", "启用"),
        "interval", myGui.AddEdit("x200 y550 w40 h20", "20")
    )
    ; 闪避键空值保护
    uCtrl["dodge"]["key"].OnEvent("Change", (*) => (
        (uCtrl["dodge"]["key"].Value = "") && (uCtrl["dodge"]["key"].Value := "Space")
    ))

    ;|---------------------- 辅助功能 ------------------------|
    uCtrl["shift"] := Map(   ; Shift键辅助
        "text", myGui.AddText("x30 y240 w40 h20", "Shift:"),
        "enable", myGui.AddCheckbox("x65 y240 w15 h15")
    )

    uCtrl["ranDom"] := Map(  ; 随机延迟
        "text", myGui.AddText("x240 y240 w60 h20", "随机延迟:"),
        "enable", myGui.AddCheckbox("x300 y240 w15 h15"),
        "max", myGui.AddEdit("x320 y238 w30 h20", "10")
    )

    uCtrl["ranDom"]["max"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["ranDom"]["max"], 1, 10)))

    uCtrl["D4only"] := Map(  ; D4only
        "text", myGui.AddText("x30 y100 w240 h20", "仅在暗黑破坏神4中使用:"),
        "enable", myGui.AddCheckbox("x180 y100 w15 h15", "1")
    )

    ;|---------------------- 血条检测 ------------------------|
    uCtrl["ipPause"] := Map(
        "text", myGui.AddText("x30 y155 w60 h20", "血条检测:"),
        "stopText", myGui.AddText("x80 y185 w15 h20", "停"),
        "startText", myGui.AddText("x120 y185 w15 h20", "启"),
        "enable", myGui.AddCheckbox("x90 y155 w20 h20"),
        "interval", myGui.AddEdit("x115 y155 w40 h20", "50"),
        "pauseConfirm", myGui.AddEdit("x95 y183 w20 h20", "2"),
        "resumeConfirm", myGui.AddEdit("x135 y183 w20 h20", "2")
    )
    ; 输入验证
    uCtrl["ipPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["ipPause"]["interval"], 10, 1000)))
    uCtrl["ipPause"]["pauseConfirm"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["ipPause"]["pauseConfirm"], 1, 9)))
    uCtrl["ipPause"]["resumeConfirm"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["ipPause"]["resumeConfirm"], 1, 9)))

    ;|---------------------- 界面检测 ------------------------|
    uCtrl["tabPause"] := Map(
        "text", myGui.AddText("x200 y155 w60 h20", "界面检测:"),
        "stopText", myGui.AddText("x250 y185 w15 h20", "停"),
        "startText", myGui.AddText("x290 y185 w15 h20", "启"),
        "enable", myGui.AddCheckbox("x260 y155 w20 h20"),
        "interval", myGui.AddEdit("x285 y155 w40 h20", "50"),
        "pauseConfirm", myGui.AddEdit("x265 y183 w20 h20", "2"),
        "resumeConfirm", myGui.AddEdit("x305 y183 w20 h20", "2")
    )
    ; 输入验证
    uCtrl["tabPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["interval"], 10, 1000)))
    uCtrl["tabPause"]["pauseConfirm"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["pauseConfirm"], 1, 9)))
    uCtrl["tabPause"]["resumeConfirm"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["resumeConfirm"], 1, 9)))

    uCtrl["dcPause"] := Map(
        "text", myGui.AddText("x350 y185 w80 h20", "双击暂停:"),
        "enable", myGui.AddCheckbox("x410 y185 w15 h15"),
        "interval", myGui.AddEdit("x430 y183 w20 h20", "2"),
        "text2", myGui.AddText("x451 y185 w15 h20", "秒")
    )

    uCtrl["dcPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["dcPause"]["interval"], 1, 3)))

    ;|----------------------- 鼠标自动移动 -----------------------|
    uCtrl["mouseAutoMove"] := Map(
        "text", myGui.AddText("x100 y240 w60 h20", "鼠标自移:"),
        "enable", myGui.AddCheckbox("x160 y240 w15 h15"),
        "interval", myGui.AddEdit("x180 y238 w40 h20", "1000"),
        "currentPoint", 1  ; 移动点位标记
    )
}

/**
 * 数值限制函数
 * @param {Object} ctrl - 控件对象
 * @param {Number} min - 最小值
 * @param {Number} max - 最大值
 */
LimitEditValue(ctrl, min, max) {
    value := ctrl.Value + 0
    ctrl.Value := value < min ? min : (value > max ? max : value)
    return
}

/**
 * 热键模式切换事件处理
 * @param {Object} ctrl - 下拉框控件
 */
OnHotkeyModeChange(ctrl, *) {
    global statusBar, hotkeyControl, hotkeyModeDropDown, profileName

    ; 模式配置映射
    static modeConfig := Map(
        1, {
            enabled: true,
            configKey: "useHotKey", 
            defaultValue: "F1",
            modeName: "自定义热键",
            errorMsg: "已切换到自定义热键模式"
        },
        2, {
            enabled: false,
            configKey: "HotKey", 
            defaultValue: "XButton1",
            modeName: "侧键1",
            errorMsg: "热键已设置为侧键1"
        },
        3, {
            enabled: false,
            configKey: "HotKey", 
            defaultValue: "XButton2",
            modeName: "侧键2", 
            errorMsg: "热键已设置为侧键2"
        }
    )

    mode := hotkeyModeDropDown.Value
    config := modeConfig[mode]
    hotkeyControl.Enabled := config.enabled

    ; 统一的配置读取逻辑
    try {
        settingsFile := A_ScriptDir "\settings.ini"
        section := profileName.Value "_uSkill"
        savedHotkey := IniRead(settingsFile, section, config.configKey, config.defaultValue)
        
        hotkeyControl.Value := savedHotkey
        LoadGlobalHotkey()
        statusBar.Text := "已切换到" config.modeName " - 热键: " savedHotkey
        
    } catch {
        ; 统一的错误处理
        if (mode == 1 && hotkeyControl.Value == "") {
            hotkeyControl.Value := config.defaultValue
        } else if (mode != 1) {
            hotkeyControl.Value := config.defaultValue
        }
        LoadGlobalHotkey()
        statusBar.Text := config.errorMsg
    }
}

/**
 * 加载全局热键
 */
LoadGlobalHotkey() {
    global hotkeyControl, statusBar
    static currentHotkey := ""

    if (hotkeyControl.Value = "") {
        hotkeyControl.Value := "F1"
        statusBar.Text := "热键不能为空，已恢复为: F1"
        return
    }

    try {
        if (currentHotkey != "") {
            Hotkey(currentHotkey, ToggleMacro, "Off")
        }

        newHotkey := hotkeyControl.Value
        Hotkey(newHotkey, ToggleMacro, "On")
        currentHotkey := newHotkey
        statusBar.Text := "热键已更新: " newHotkey
    } catch as err {
        hotkeyControl.Value := currentHotkey ? currentHotkey : "F1"
        statusBar.Text := "热键设置失败: " err.Message
    }
}

; ==================== 核心控制函数 ====================
/**
 * 切换宏运行状态
 */
ToggleMacro(*) {
    global isRunning

    isRunning := !isRunning
    TogglePause()
    if isRunning {
        if (uCtrl["D4only"]["enable"].Value == 1) {

            if WinActive("ahk_class Diablo IV Main Window Class") {
                StartAllTimers()
                ManageTimers("all", true)
                UpdateStatus("运行中", "宏已启动")
            } else {
                StartAllTimers()
                ManageTimers("all", true)
                TogglePause("window", true)
            }
        } else {
            StartAllTimers()
            UpdateStatus("运行中", "宏已启动")
        }
    } else {
        StopAllTimers()
        ManageTimers("none", false)
        UpdateStatus("已停止", "宏已停止")
    }
}

/**
 * 核心暂停函数
 * @param {String} reason - 暂停原因
 * @param {Boolean} state - 状态
 */
TogglePause(reason := "", state := unset) {
    global pauseConfig, isRunning

    if !IsSet(pauseConfig) {
        pauseConfig := Map(
            "window", {state: false, name: "窗口切换"},
            "blood", {state: false, name: "血条检测"},
            "tab", {state: false, name: "TAB界面"},
            "enter", {state: false, name: "对话框"},
            "doubleClick", {state: false, name: "双击暂停"}
        )
    }

    if (!reason)
        return
    
    prevPausedReasons := []
    if (isRunning) {
        for pauseReason, config in pauseConfig {
            if (config.state) {
                prevPausedReasons.Push(config.name)
            }
        }
    }
    prev := (prevPausedReasons.Length > 0)

    pauseConfig[reason].state := state
    
    currentPausedReasons := []
    if (isRunning) {
        for pauseReason, config in pauseConfig {
            if (config.state) {
                currentPausedReasons.Push(config.name)
            }
        }
    }
    now := (currentPausedReasons.Length > 0)
    
    if (now != prev) {
        if (now) {
            StopAllTimers()
        } else {
            StartAllTimers()
        }
    }

    if (now) {
        reasonsText := Join(currentPausedReasons, " + ")
        UpdateStatus("已暂停", reasonsText)
    } else {
        UpdateStatus("运行中", "宏已启动")
    }
}

/**
 * 更新状态显示
 * @param {String} status - 主状态文本
 * @param {String} barText - 状态栏文本
 */
UpdateStatus(status, barText) {
    global statusText, statusBar
    
    if (status = "已暂停") {
        statusText.Value := "状态: 已暂停"
        statusBar.Text := "宏已暂停 - " barText
    } else {
        statusText.Value := status ? ("状态: " status) : "状态: 运行中"
        statusBar.Text := barText
    }
}

; ==================== 定时器管理 ====================
/**
 * 启动定时器
 */
StartAllTimers() {
    global cSkill, mSkill, uCtrl, RunMod, keyQueue, skillTimers

    if (uCtrl["D4only"]["enable"].Value == 1) {
        CoordManager()
        if (uCtrl["mouseAutoMove"]["enable"].Value) {
            interval := Integer(uCtrl["mouseAutoMove"]["interval"].Value)
            if (interval > 0) {
                MoveMouse()
                SetTimer(MoveMouse, interval)
            }
        } else {
            SetTimer(MoveMouse, 0)
        }
    }

    if (!IsSet(skillTimers))
        skillTimers := Map()

    if (RunMod.Value = 2) {
        keyQueue := []
        SetTimer(KeyQueueWorker, 50)
    }

    ; ===== 技能按键 =====
    loop 5 {
        if (cSkill[A_Index]["enable"].Value) {
            PressKeyCallback("skill", A_Index)
        }
    }

    ; ===== 鼠标按键 =====
    for mouseBtn in ["left", "right"] {
         if (mSkill[mouseBtn]["enable"].Value) {
            PressKeyCallback("mouse", mouseBtn)
        }
    }

    ; ===== 功能键 =====
    for uSkillId in ["dodge", "potion", "forceMove"] {
        if (uCtrl[uSkillId]["enable"].Value) {
            PressKeyCallback("uSkill", uSkillId)
        }
    }
}

/**
 * 停止所有定时器
 */
StopAllTimers() {
    global skillTimers, RunMod

    if (RunMod.Value = 2) {
        SetTimer(KeyQueueWorker, 0)
    }

    if (IsSet(skillTimers)) {
        for timerName, boundFunc in skillTimers.Clone() {
            SetTimer(boundFunc, 0)
            skillTimers.Delete(timerName)
        }
        skillTimers.Clear()
    }

    SetTimer(MoveMouse, 0)

    ReleaseAllKeys()
}

/**
 * 重置所有变量
 */
ReleaseAllKeys() {
    global holdStates

    if IsSet(holdStates){
        for uniqueKey, _ in holdStates {
            try {
                arr := StrSplit(uniqueKey, ":")
                if (arr.Length < 2)
                    continue

                type := arr[1]
                keyName := arr[2]

                if (type = "mouse") {
                    Click("up " keyName)
                }
                else if (type = "key") {
                    Send("{" keyName " up}")
                }
            }
        }
        holdStates.Clear()
    }

    if IsSet(keyQueue) {
        keyQueue := []
    }

    Send "{Shift up}"
    Send "{Ctrl up}"
    Send "{Alt up}"
}

/**
 * 管理全局定时器
 * @param {String} timerType - 定时器类型
 * @param {Boolean} enable - 是否启用定时器
 * @param {Integer} interval - 定时器间隔(毫秒)
 * @returns {Boolean} - 操作是否成功
 */
ManageTimers(timerType, enable, interval := unset) {

    global uCtrl

    success := true

    if (timerType = "window") {
        actualInterval := IsSet(interval) ? interval : 100
        SetTimer(CheckWindow, enable ? actualInterval : 0)
    }
    else if (timerType = "blood") {
        actualInterval := IsSet(interval) ? interval : (
            uCtrl.Has("ipPause") && uCtrl["ipPause"].Has("interval")
                ? Integer(uCtrl["ipPause"]["interval"].Value)
                : 50
        )
        SetTimer(AutoPauseByBlood, enable ? actualInterval : 0)
    }
    else if (timerType = "tab") {
        actualInterval := IsSet(interval) ? interval : (
            uCtrl.Has("tabPause") && uCtrl["tabPause"].Has("interval")
                ? Integer(uCtrl["tabPause"]["interval"].Value)
                : 100
        )
        SetTimer(AutoPauseByTAB, enable ? actualInterval : 0)
    }
    else if (timerType = "all") {
        windowInterval := 100
        bloodInterval := (uCtrl.Has("ipPause") && uCtrl["ipPause"].Has("interval"))
            ? Integer(uCtrl["ipPause"]["interval"].Value) : 50
        tabInterval := (uCtrl.Has("tabPause") && uCtrl["tabPause"].Has("interval"))
            ? Integer(uCtrl["tabPause"]["interval"].Value) : 100
        if (uCtrl["D4only"]["enable"].Value) {
            ManageTimers("window", enable, windowInterval)
        }

        if (uCtrl["ipPause"]["enable"].Value) {
            ManageTimers("blood", enable, bloodInterval)
        }

        if (uCtrl["tabPause"]["enable"].Value) {
            ManageTimers("tab", enable, tabInterval)
        }
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
 * 立即刷新所有检测
 * 清理缓存，立即执行检测，支持强制恢复运行
 * @param {*} - 事件参数（来自按钮点击事件）
 */
RefreshDetection(*) {
    global isRunning, statusBar, uCtrl, pauseConfig

    if !isRunning || !(uCtrl["D4only"]["enable"].Value) {
        statusBar.Text := "无需刷新检测"
        return
    }

    ManageTimers("none", false)

    bloodInterval := Integer(uCtrl["ipPause"]["interval"].Value)
    tabInterval := Integer(uCtrl["tabPause"]["interval"].Value)

    for reason, config in pauseConfig {
        config.state := false
    }
    UpdateStatus("运行中", "已强制重置")

    try {
        CheckWindow()
        if (uCtrl["ipPause"]["enable"].Value)
            AutoPauseByBlood()

        if (uCtrl["tabPause"]["enable"].Value)
            AutoPauseByTAB()
    } catch {
    }


    if (uCtrl["D4only"]["enable"].Value) {
        ManageTimers("window", true, 100)
    }

    if (uCtrl["ipPause"]["enable"].Value) {
        ManageTimers("blood", true, bloodInterval)
    }
    
    if (uCtrl["tabPause"]["enable"].Value) {
        ManageTimers("tab", true, tabInterval)
    }
}

; ==================== 按键与技能处理 ====================
/**
 * 通用按键处理
 * @param {Object} keyData - 按键数据
 */
HandleKeyMode(keyData) {
    global uCtrl, holdStates

    uniqueKey := keyData.uniqueKey
    shiftEnabled := uCtrl["shift"]["enable"].Value

    switch keyData.mode {
        case 2: ; BUFF模式
            if (keyData.HasProp("Coord")) {
                if (IsSkillActive(keyData.id, keyData.Coord))
                    return
            } else {
                if (IsSkillActive(keyData.id))
                    return
            }

            if (keyData.isMouse) {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Click(keyData.key)
                    Send "{Blind} {Shift up}"
                } else {
                    Click(keyData.key)
                }
            } else {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Send "{" keyData.key "}"
                    Send "{Blind} {Shift up}"
                } else {
                    Send "{" keyData.key "}"
                }
            }

        case 3: ; 按住模式
            if (!IsSet(holdStates))
                holdStates := Map()
            
            if (!holdStates.Has(uniqueKey) || !holdStates[uniqueKey]) {
                holdStates[uniqueKey] := true
                
                if (keyData.isMouse) {
                    if (shiftEnabled)
                        Send "{Blind}{Shift down}"
                    Click("down " keyData.key)
                } else {
                    if (shiftEnabled)
                        Send "{Blind}{Shift down}"
                    Send("{" keyData.key " down}")
                }
            }

        case 4: ; 资源模式
            if (IsResourceSufficient()) {
                if (keyData.isMouse) {
                    if (shiftEnabled) {
                        Send "{Blind} {Shift down}"
                        Click(keyData.key)
                        Send "{Blind} {Shift up}"
                    } else {
                        Click(keyData.key)
                    }
                } else {
                    if (shiftEnabled) {
                        Send "{Blind} {Shift down}"
                        Send "{" keyData.key "}"
                        Send "{Blind} {Shift up}"
                    } else {
                        Send "{" keyData.key "}"
                    }
                }
            }

        default: ; 连点模式
            if (keyData.isMouse) {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Click(keyData.key)
                    Send "{Blind} {Shift up}"
                } else {
                    Click(keyData.key)
                }
            } else {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Send "{" keyData.key "}"
                    Send "{Blind} {Shift up}"
                } else {
                    Send "{" keyData.key "}"
                }
            }
    }
}

; ==================== 队列模式实现 ====================
/**
 * 键位入队函数
 * @param {Object} keyData
 */
EnqueueKey(keyData) {
    global keyQueue
    static maxLen := 10

    uniqueKey := keyData.uniqueKey
    priority := GetPriority(keyData.mode, keyData.id)
    now := A_TickCount
    existingIndex := 0
    loop keyQueue.Length {
        if (keyQueue[A_Index].uniqueKey = uniqueKey) {
            existingIndex := A_Index
            break
        }
    }

    item := {
        key: keyData.key,
        mode: keyData.mode,
        interval: keyData.interval,
        id: keyData.id,
        isMouse: keyData.isMouse,
        uniqueKey: keyData.uniqueKey,
        category: keyData.category,
        timerKey: keyData.timerKey,
        time: now,
        priority: priority
    }

    if (keyData.HasProp("Coord")) {
        item.Coord := keyData.Coord
    }

    if (existingIndex > 0)
        keyQueue.RemoveAt(existingIndex)

    if (keyQueue.Length >= maxLen) {
        lowestPriority := priority
        lowestIndex := 0

        loop keyQueue.Length {
            idx := A_Index
            qItem := keyQueue[idx]
            if (qItem.priority < lowestPriority || 
               (qItem.priority == lowestPriority && qItem.time < (lowestIndex ? keyQueue[lowestIndex].time : 0))) {
                lowestPriority := qItem.priority
                lowestIndex := idx
            }
        }
        
        if (lowestIndex > 0 && priority >= lowestPriority)
            keyQueue.RemoveAt(lowestIndex)
        else if (existingIndex == 0)
            return
    }

    if (keyQueue.Length == 0) {
        keyQueue.Push(item)
        return
    }

    left := 1
    right := keyQueue.Length

    firstPriority := keyQueue[1].priority
    lastPriority := keyQueue[right].priority

    if (priority > firstPriority) {
        keyQueue.InsertAt(1, item)
        return
    }
    if (priority <= lastPriority) {
        keyQueue.Push(item)
        return
    }

    while (right - left > 1) {
        mid := (left + right) >> 1
        midItem := keyQueue[mid]
        if (priority > midItem.priority || 
           (priority == midItem.priority && now > midItem.time))
            right := mid
        else
            left := mid
    }

    keyQueue.InsertAt(right, item)
}

/**
; 优先级计算函数
* @param {Integer} mode - 按键模式
* @param {String} identifier - 按键标识符
*/
GetPriority(mode, identifier := "") {
    switch mode {
        case 4: return 4
        case 2: return 3
        case 3: return 2
        case 1: 
            if (identifier = "dodge" || identifier = "potion" || identifier = "forceMove") {
                return 5
            }
            return 1
        default: return 0
    }
}

/**
 * 队列处理器
 * @description 处理队列中的按键事件
 */
KeyQueueWorker() {
    global keyQueue, holdStates
    static lastExec := Map()
    static critSection := false
    
    if IsObject(keyQueue) && keyQueue.Length = 0
        return

    now := A_TickCount
    pendingItems := []
    remainingItems := []

    if (critSection)
        return
    critSection := true

    loop keyQueue.Length {
        item := keyQueue[A_Index]
        uniqueKey := item.uniqueKey
        lastExecTime := lastExec.Get(uniqueKey, 0)

        if (item.mode == 3) {
            if (IsSet(holdStates) && holdStates.Has(uniqueKey) && holdStates[uniqueKey]) {
                continue
            }
            
            HandleKeyMode(item)
            lastExec[uniqueKey] := now
            continue
        }

        if ((now - lastExecTime) >= item.interval) {
            HandleKeyMode(item)
            lastExec[uniqueKey] := now
            pendingItems.Push(item)
        } else {
            remainingItems.Push(item)
        }
    }

    keyQueue := remainingItems
    critSection := false

    for item in pendingItems {
        if (item.mode != 3) {
            EnqueueKey(item)
        }
    }
}

/**
 * 通用按键回调函数
 * @param {String} category - 按键类别 ("skill"|"mouse"|"uSkill")
 * @param {String|Integer} identifier - 按键标识符 (技能索引|鼠标按钮名|功能键ID)
 */
PressKeyCallback(category, identifier) {
    global cSkill, mSkill, uCtrl, skillTimers, RunMod

    timerKey := category . identifier

    if (IsSet(skillTimers) && skillTimers.Has(timerKey)) {
        try {
            SetTimer(skillTimers[timerKey], 0)
        } catch {
        }
        skillTimers.Delete(timerKey)
    }

    config := ""
    switch category {
        case "skill":
            if (!cSkill.Has(identifier) || cSkill[identifier]["enable"].Value != 1)
                return
            config := cSkill[identifier]
        case "mouse":
            if (!mSkill.Has(identifier) || mSkill[identifier]["enable"].Value != 1)
                return
            config := mSkill[identifier]
        case "uSkill":
            if (!uCtrl.Has(identifier) || uCtrl[identifier]["enable"].Value != 1)
                return
            config := uCtrl[identifier]
        default:
            return
    }

    isMouse := (category = "mouse")
    key := isMouse ? identifier : config["key"].Value
    mode := config.Has("mode") ? config["mode"].Value : 1
    interval := Integer(config["interval"].Value)
    skillCoord := GetSkillCoords(identifier)

    keyData := {
        key: key,                         ; 目标键/按钮key
        mode: mode,                       ; 操作模式
        interval: interval,               ; 执行间隔
        id: identifier,                   ; 标识符
        isMouse: isMouse,                 ; 鼠标标识
        uniqueKey: (isMouse ? "mouse:" : "key:") . key,  ; 唯一键
        category: category,               ; 类别信息
        timerKey: timerKey,               ; 定时器键
    }
 
    if (!uCtrl["D4only"]["enable"].Value) {
        if (keyData.mode == 2 || keyData.mode == 4) {
            keyData.mode := 1
        }
    }

    if (skillCoord) {
        keyData.Coord := skillCoord
    }

    if (uCtrl["ranDom"]["enable"].Value == 1) {
        keyData.interval += Random(1, uCtrl["ranDom"]["max"].Value)
    }

    if (RunMod.Value == 1) {
        boundFunc := HandleKeyMode.Bind(keyData)
        skillTimers[keyData.timerKey] := boundFunc
        SetTimer(boundFunc, keyData.interval)
    } else if (RunMod.Value == 2) {
        EnqueueKey(keyData)
    }
}

; ==================== 图像和窗口检测 ====================
/**
 * 窗口切换检查函数
 * 检测暗黑4窗口是否激活，并在状态变化时触发相应事件
 */
CheckWindow() {
    if WinActive("ahk_class Diablo IV Main Window Class") {
        TogglePause("window", false)
    } else {
        TogglePause("window", true)
    }
}

/**
 * 获取窗口分辨率并计算缩放比例
 * @param D44KW {Integer} 参考分辨率宽度(默认3840，即4K宽度)
 * @param D44KH {Integer} 参考分辨率高度(默认2160，即4K高度)
 * @param D44KWC {Integer} 参考分辨率中心X坐标(默认1920)
 * @param D44KHC {Integer} 参考分辨率中心Y坐标(默认1080)
 * @returns {Map} 包含窗口尺寸和缩放比例信息的Map对象
 */
GetWindowInfo(D44KW := 3840, D44KH := 2160, D44KWC := 1920, D44KHC := 1080) {
    D4Windows := Map(
        "D4W", 0.0,       ; 客户区实际宽度
        "D4H", 0.0,       ; 客户区实际高度
        "CD4W", 0.0,      ; 客户区中心X坐标（浮点）
        "CD4H", 0.0,      ; 客户区中心Y坐标（浮点）
        "D4S", 1.0,       ; 统一缩放比例（Min(D4SW,D4SH)）
        "D4SW", 1.0,      ; 宽度独立缩放比例
        "D4SH", 1.0,       ; 高度独立缩放比例
        "D44KW", D44KW,    ; 添加参考分辨率宽度到返回Map
        "D44KH", D44KH,    ; 添加参考分辨率高度到返回Map
        "D44KWC", D44KWC,  ; 添加参考中心X坐标到返回Map
        "D44KHC", D44KHC   ; 添加参考中心Y坐标到返回Map
    )

    if WinExist("ahk_class Diablo IV Main Window Class") {
        hWnd := WinGetID("ahk_class Diablo IV Main Window Class")
        rect := Buffer(16)

        if DllCall("GetClientRect", "Ptr", hWnd, "Ptr", rect) {
            D4Windows["D4W"] := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
            D4Windows["D4H"] := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")

            ; 计算精确的中心点（浮点）
            D4Windows["CD4W"] := D4Windows["D4W"] / 2
            D4Windows["CD4H"] := D4Windows["D4H"] / 2

            ; 计算独立缩放比例
            D4Windows["D4SW"] := D4Windows["D4W"] / D44KW
            D4Windows["D4SH"] := D4Windows["D4H"] / D44KH
            ; 计算统一缩放比例
            D4Windows["D4S"] := Min(D4Windows["D4SW"], D4Windows["D4SH"])
        }
    }

    return D4Windows
}
/**
 * 坐标管理函数
 * @description 获取所有坐标并转换为实际屏幕坐标
 */
CoordManager() {
    global allcoords
    

    windowInfo := GetWindowInfo()

    allcoords := Map()

    ; 使用预定义的坐标配置
    static coordConfig := Map(
        "monster_blood_top", {x: 1605, y: 85},
        "monster_blood_bottom", {x: 1605, y: 95},
        "boss_blood_top", {x: 1435, y: 85},
        "boss_blood_bottom", {x: 1435, y: 95},
        "monster_ui_top", {x: 1590, y: 75},
        "monster_ui_bottom", {x: 1590, y: 100},
        "boss_ui_top", {x: 1425, y: 77},
        "boss_ui_bottom", {x: 1425, y: 117},
        "skill_bar_blue", {x: 1535, y: 1880},
        "tab_interface_red", {x: 3795, y: 90},
        "dialog_gray_bg", {x: 150, y: 2070},
        "resource_bar", {x: 2620, y: 1875}
    )

    for name, coord in coordConfig {
        allcoords[name] := Convert(coord, windowInfo)
    }

    loop 6 {
        allcoords["dialog_red_btn_" A_Index] := Convert({
            x: 50 + 90 * (A_Index - 1), 
            y: 1440
        }, windowInfo)
    }

    static mouseMoveRatios := [
        {x: 0.15, y: 0.15}, {x: 0.5, y: 0.15}, {x: 0.85, y: 0.15},
        {x: 0.85, y: 0.85}, {x: 0.5, y: 0.85}, {x: 0.15, y: 0.85}
    ]
    
    loop 6 {
        ratio := mouseMoveRatios[A_Index]
        allcoords["mouse_move_" A_Index] := Convert({
            x: Round(ratio.x * windowInfo["D44KW"]), 
            y: Round(ratio.y * windowInfo["D44KH"])
        }, windowInfo)
    }
    
    return allcoords
}

Convert(coord, windowInfo := unset) {
    static cacheInfo := unset
    if (!IsSet(cacheInfo)) {
        cacheInfo := GetWindowInfo()
    }
    if IsSet(windowInfo) {
        useInfo := windowInfo
    } else {
        useInfo := cacheInfo
    }
    x := Round(useInfo["CD4W"] + (coord.x - useInfo["D44KWC"]) * useInfo["D4SW"])
    y := Round(useInfo["CD4H"] + (coord.y - useInfo["D44KHC"]) * useInfo["D4SH"])

    return { x: x, y: y }
}


; ==================== 像素检测与暂停机制 ====================
/**
 * 专用的自动暂停函数
 * 支持像素缓存，避免重复采样
 */
CheckKeyPoints(allcoords, pixelCache := unset) {  
    try {
        dfx := allcoords["skill_bar_blue"].x
        dty := allcoords["skill_bar_blue"].y
        
        ; 1. 检测巅峰栏蓝色
        colorDFX := (IsSet(pixelCache) && pixelCache.Has("dfx")) ? 
            pixelCache["dfx"] : GetPixelRGB(dfx, dty)

        try {
            dfxHSV := RGBToHSV(colorDFX.r, colorDFX.g, colorDFX.b)
            isBlueDFX := (dfxHSV.h >= 180 && dfxHSV.h <= 270 && dfxHSV.s > 0.3 && dfxHSV.v > 0.2)
            
            ; 如果检测到蓝色
            if (isBlueDFX) {
                return {
                    dfxcolor: colorDFX,
                    tabcolor: {},
                    isBlueColor: true,
                    isRedColor: false,
                    positions: { dfx: dfx, dty: dty, tabx: 0, taby: 0 }
                }
            }
        } catch {
        }
        
        ; 2. 检测TAB界面红色
        tabx := allcoords["tab_interface_red"].x
        taby := allcoords["tab_interface_red"].y
        
        colorTAB := (IsSet(pixelCache) && pixelCache.Has("tab")) ? 
            pixelCache["tab"] : GetPixelRGB(tabx, taby)
        
        ; 红色检测
        isRedTAB := false
        try {
            isRedTAB := (colorTAB.r > (colorTAB.g + colorTAB.b) * 1.5)
        } catch {
            isRedTAB := false
        }

        return {
            dfxcolor: colorDFX,
            tabcolor: colorTAB,
            isBlueColor: false,
            isRedColor: isRedTAB,
            positions: { dfx: dfx, dty: dty, tabx: tabx, taby: taby }
        }
        
    } catch {
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
 * 专用的输入框检测
 * 支持像素缓存，减少采样次数
 * @returns {Boolean} - 是否检测到红色提示
 */
CheckPauseByEnter(allcoords, pixelCache := unset) {
    try {
        grayPoint := "dialog_gray_bg"
        redPoints := ["dialog_red_btn_1", "dialog_red_btn_2", "dialog_red_btn_3", 
                     "dialog_red_btn_4", "dialog_red_btn_5", "dialog_red_btn_6"]

        ; 1. 检测灰色背景
        coord := allcoords[grayPoint]
        key := coord.x . "," . coord.y
        
        grayColor := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
            pixelCache[key] : GetPixelRGB(coord.x, coord.y)

        isGrayBackground := false
        try {
            grayHsv := RGBToHSV(grayColor.r, grayColor.g, grayColor.b)
            isGrayBackground := (grayHsv.s < 0.3 && grayHsv.v < 0.3)
        } catch {
            isGrayBackground := false
        }

        if (!isGrayBackground)
            return false

        ; 2. 检测红色按钮
        loop 6 {
            coord := allcoords[redPoints[A_Index]]
            key := coord.x . "," . coord.y
            
            colorObj := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(coord.x, coord.y)

            isRedButton := false
            try {
                hsv := RGBToHSV(colorObj.r, colorObj.g, colorObj.b)
                isRedHue := (hsv.h <= 30 || hsv.h >= 330)  ; 红色色相范围
                isSaturated := (hsv.s > 0.7)               ; 饱和度
                isBright := (hsv.v > 0.35)                 ; 亮度
                isRedButton := (isRedHue && isSaturated && isBright)
            } catch {
                isRedButton := false
            }

            if (isRedButton)
                return true
        }
        
        return false
        
    } catch as err {
        return false
    }
}

/**
 * 检测boss血条
 * @param pixelCache {Map} 像素缓存
 * @returns {Boolean} 是否检测到boss血条
 */
CheckBoss(allcoords, pixelCache := unset) {
    try {
        uiPoints := ["boss_ui_top", "boss_ui_bottom"]
        bloodPoints := ["boss_blood_top", "boss_blood_bottom"]
        
        ; 1. 检测UI是否为灰色
        loop 2 {
            coord := allcoords[uiPoints[A_Index]]
            key := coord.x . "," . coord.y
            
            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(coord.x, coord.y)
            
            try {
                rgbRange := Max(color.r, color.g, color.b) - Min(color.r, color.g, color.b)
                if (rgbRange > 35)
                    return false
            } catch {
                return false
            }
        }
        
        ; 2. UI为灰色时才检测血条红色
        loop 2 {
            coord := allcoords[bloodPoints[A_Index]]
            key := coord.x . "," . coord.y
            
            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(coord.x, coord.y)
            
            try {
                if (color.r <= (color.g + color.b) * 1.5)
                    return false
            } catch {
                return false
            }
        }
        
        return true

    } catch as err {
        return false
    }
}

/**
 * 检测monster血条
 * @param pixelCache {Map} 像素缓存
 * @returns {Boolean} 是否检测到monster血条
 */
CheckMonster(allcoords, pixelCache := unset) {
    try {
        uiPoints := ["monster_ui_top", "monster_ui_bottom"]
        bloodPoints := ["monster_blood_top", "monster_blood_bottom"]
        
        ; 1. 检测UI是否为灰色
        loop 2 {
            coord := allcoords[uiPoints[A_Index]]
            key := coord.x . "," . coord.y
            
            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(coord.x, coord.y)
            
            try {
                rgbRange := Max(color.r, color.g, color.b) - Min(color.r, color.g, color.b)
                if (rgbRange > 50)
                    return false
            } catch {
                return false
            }
        }
        
        ; 2. UI为灰色时才检测血条红色
        loop 2 {
            coord := allcoords[bloodPoints[A_Index]]
            key := coord.x . "," . coord.y
            
            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(coord.x, coord.y)
            
            try {
                if (color.r <= (color.g + color.b) * 1.5)
                    return false
            } catch {
                return false
            }
        }
        
        return true

    } catch as err {
        return false
    }
}

/**
 * 定时检测血条并自动暂停/启动宏
 */
AutoPauseByBlood() {
    global pauseConfig, uCtrl, allcoords
    static pauseMissCount := 0
    static resumeHitCount := 0

    PAUSE := uCtrl["ipPause"]["pauseConfirm"].Value
    RESUME := uCtrl["ipPause"]["resumeConfirm"].Value

    bloodDetected := false
    
    try {
        pixelCache := Map()
        if (CheckMonster(allcoords, pixelCache)) {
            bloodDetected := true
        }
        else if (CheckBoss(allcoords, pixelCache)) {
            bloodDetected := true
        }
    } catch as err {
        bloodDetected := false
    }

    if (pauseConfig["blood"].state) {
        if (bloodDetected) {
            resumeHitCount++
            pauseMissCount := 0
            if (resumeHitCount >= RESUME) {
                TogglePause("blood", false)
                resumeHitCount := 0
            }
        } else {
            resumeHitCount := 0
        }
    } else {
        if (!bloodDetected) {
            pauseMissCount++
            resumeHitCount := 0
            if (pauseMissCount >= PAUSE) {
                TogglePause("blood", true)
                pauseMissCount := 0
            }
        } else {
            pauseMissCount := 0
        }
    }
}

/**
 * 定时检测界面状态并自动暂停/启动宏
 * 检测TAB键打开的界面和对话框
 */
AutoPauseByTAB() {
    global pauseConfig, uCtrl, allcoords
    static pauseMissCount := 0
    static resumeHitCount := 0

    PAUSE := uCtrl["tabPause"]["pauseConfirm"].Value
    RESUME := uCtrl["tabPause"]["resumeConfirm"].Value

    try {
        res := GetWindowInfo()
        pixelCache := Map()
        keyPoints := CheckKeyPoints(allcoords, pixelCache)

        if (pauseConfig["tab"].state) {
            if (keyPoints.isBlueColor) {
                TogglePause("tab", false)
            }
            return
        }

        if (pauseConfig["enter"].state) {
            if (!CheckPauseByEnter(allcoords, pixelCache)) {
                resumeHitCount++
                pauseMissCount := 0
                if (resumeHitCount >= RESUME) {
                    TogglePause("enter", false)
                    resumeHitCount := 0
                }
            } else {
                resumeHitCount := 0
            }
        }

        if (keyPoints.isRedColor && !keyPoints.isBlueColor) {
            TogglePause("tab", true)
            return
        } else if (CheckPauseByEnter(allcoords, pixelCache)) {
            pauseMissCount++
            resumeHitCount := 0
            if (pauseMissCount >= PAUSE) {
                TogglePause("enter", true)
                pauseMissCount := 0
            }
        } else {
            pauseMissCount := 0
        }
    }
}

/**
 * 检测技能激活状态
 * @param {String|Integer} skillId - 技能标识符
 * @param {Object} coord - 预计算的坐标对象
 * @returns {Boolean} - 技能是否激活
 */
IsSkillActive(skillId, coord := unset) {
    try {
        ; 如果没有传入坐标，则计算坐标
        if (!IsSet(coord) || !coord) {
            coord := GetSkillCoords(skillId)
        }
        
        if (!coord)
            return false
            
        loop 2 {
            try {
                color := GetPixelRGB(coord.x, coord.y, false)
                hsv := RGBToHSV(color.r, color.g, color.b)
                isGreenHue := (hsv.h >= 60 && hsv.h <= 180)  ; 绿色色相范围
                isSaturated := (hsv.s > 0.3)  ; 饱和度大于30%
                isBright := (hsv.v > 0.2)  ; 亮度大于20%
                if (isGreenHue && isSaturated && isBright)
                    return true
            } catch {
                Sleep 5
            }
        }
        return false
    } catch {
        return false
    }
}

/**
 * 获取技能坐标
 * @param {String|Integer} skillId - 技能标识符
 * @returns {Object|Boolean} - 坐标对象或false
 */
GetSkillCoords(skillId) {
    static coordCache := Map()
    
    try {
        cacheKey := String(skillId)
        if (coordCache.Has(cacheKey))
            return coordCache[cacheKey]
            
        windowInfo := GetWindowInfo()
        coord := false
        
        if (Type(skillId) = "Integer" && skillId >= 1 && skillId <= 6) {
            coord := Convert({
                x: 1550 + 127 * (skillId - 1), 
                y: 1940
            }, windowInfo)
        }
        else if (skillId = "left") {
            coord := Convert({
                x: 1550 + 127 * 4,  ; skillId 5
                y: 1940
            }, windowInfo)
        }
        else if (skillId = "right") {
            coord := Convert({
                x: 1550 + 127 * 5,  ; skillId 6
                y: 1940
            }, windowInfo)
        }
        
        if (coord) {
            coordCache[cacheKey] := coord
        }
        
        return coord
        
    } catch {
        return false
    }
}

/**
 * 检测资源状态
 * @returns {Boolean} - 资源是否充足
 */
IsResourceSufficient() {
    global allcoords
    
    coord := allcoords["resource_bar"]

    loop 5 {
        try {
            color := GetPixelRGB(coord.x, coord.y + (A_Index - 1), false)
            Colorrange := Max(color.r, color.g, color.b) - Min(color.r, color.g, color.b)
            if (Colorrange > 30)  ; 如果颜色差大于30，认为资源充足
                return true
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
 * @param {Boolean} useCache - 是否使用缓存，默认为true
 * @returns {Object} - 包含r, g, b三个颜色分量的对象
 */
GetPixelRGB(x, y, useCache := true) {
    static pixelCache := Map()
    static cacheLifetime := 50
    static lastCacheClear := 0
    static maxCacheEntries := 80
    
    if (!useCache) {
        try {
            color := PixelGetColor(x, y, "RGB")
            return {
                r: (color >> 16) & 0xFF,
                g: (color >> 8) & 0xFF,
                b: color & 0xFF
            }
        } catch {
            return {r: 0, g: 0, b: 0}
        }
    }
    
    currentTime := A_TickCount
    timeSlot := currentTime // cacheLifetime
    cacheKey := (x << 20) | (y << 8) | (timeSlot & 0xFF)
    
    if (currentTime - lastCacheClear > 150) {
        if (pixelCache.Count > maxCacheEntries) {
            pixelCache.Clear()
        }
        lastCacheClear := currentTime
    }
    
    if (pixelCache.Has(cacheKey)) {
        return pixelCache[cacheKey]
    }
    
    try {
        color := PixelGetColor(x, y, "RGB")
        result := {
            r: (color >> 16) & 0xFF,
            g: (color >> 8) & 0xFF,
            b: color & 0xFF
        }
        pixelCache[cacheKey] := result
        return result
    } catch {
        result := {r: 0, g: 0, b: 0}
        pixelCache[cacheKey] := result
        return result
    }
}

/**
 * RGB转HSV
 * @param {Integer} r - 红色分量 (0-255)
 * @param {Integer} g - 绿色分量 (0-255) 
 * @param {Integer} b - 蓝色分量 (0-255)
 * @returns {Object} - 包含h,s,v的对象
 */
RGBToHSV(r, g, b) {
    r := r / 255.0
    g := g / 255.0
    b := b / 255.0

    max_val := Max(r, g, b)
    min_val := Min(r, g, b)
    diff := max_val - min_val

    v := max_val

    s := (max_val == 0) ? 0 : (diff / max_val)

    h := 0
    if (diff != 0) {
        if (max_val == r) {
            h := 60 * Mod((g - b) / diff, 6)
        } else if (max_val == g) {
            h := 60 * ((b - r) / diff + 2)
        } else {
            h := 60 * ((r - g) / diff + 4)
        }
    }

    return { h: h, s: s, v: v }
}

/**
 * 鼠标自动移动函数
 */
MoveMouse() {
    global uCtrl, allcoords

    try {
        if (!uCtrl["mouseAutoMove"].Has("currentPoint"))
            uCtrl["mouseAutoMove"]["currentPoint"] := 1

        currentIndex := uCtrl["mouseAutoMove"]["currentPoint"]

        if (currentIndex < 1 || currentIndex > 6)
            currentIndex := 1

        currentPoint := allcoords["mouse_move_" currentIndex]
        MouseMove(currentPoint.x, currentPoint.y, 0)

        uCtrl["mouseAutoMove"]["currentPoint"] := Mod(currentIndex, 6) + 1

    }
}


; ==================== 设置管理 ====================
/**
 * 初始化配置方案列表
 */
InitializeProfiles() {
    global profileDropDown, profileName, statusBar

    settingsFile := A_ScriptDir "\settings.ini"

    settingsDir := RegExReplace(settingsFile, "[^\\]+$", "")
    if (!DirExist(settingsDir) && settingsDir != "") {
        try {
            DirCreate(settingsDir)
        } catch {
        }
    }

    if (!FileExist(settingsFile)) {
        try {
            FileAppend("[Profiles]`nList=默认`n`n[Global]`nLastUsedProfile=默认`n`n", settingsFile)
        } catch {
        }
    }

    try {
        profilesString := IniRead(settingsFile, "Profiles", "List", "默认")
        profileList := StrSplit(profilesString, "|")

        if (!InArray(profileList, "默认")) {
            profileList.InsertAt(1, "默认")
            IniWrite(Join(profileList, "|"), settingsFile, "Profiles", "List")
        }
    } catch {
        profileList := ["默认"]
        try {
            IniWrite("默认", settingsFile, "Profiles", "List")
        } catch {
        }
    }

    profileDropDown.Delete()
    for i, name in profileList {
        profileDropDown.Add([name])
    }

    try {
        lastProfile := IniRead(settingsFile, "Global", "LastUsedProfile", "默认")
        found := false
        for i, name in profileList {
            if (name = lastProfile) {
                profileDropDown.Value := i
                profileName.Value := lastProfile
                LoadSelectedProfile(profileDropDown)
                found := true
                break
            }
        }
        if (!found) {
            profileDropDown.Value := 1
            profileName.Value := "默认"
            LoadSelectedProfile(profileDropDown)
        }
    } catch {
        profileDropDown.Value := 1
        profileName.Value := "默认"
        LoadSelectedProfile(profileDropDown)
        try {
            IniWrite("默认", settingsFile, "Global", "LastUsedProfile")
        } catch {
        }
    }
}

/**
 * 更新配置列表下拉框
 */
UpdateProfileDropDown() {
    global profileDropDown, profileName

    settingsFile := A_ScriptDir "\settings.ini"
    profilesString := IniRead(settingsFile, "Profiles", "List", "默认")
    profileList := StrSplit(profilesString, "|")

    currentSelection := profileName.Value
    profileDropDown.Delete()
    for i, name in profileList {
        profileDropDown.Add([name])
    }

    found := false
    for i, name in profileList {
        if (name = currentSelection) {
            profileDropDown.Value := i
            found := true
            break
        }
    }

    if (!found && profileList.Length > 0) {
        profileDropDown.Value := 1
        if (profileList.Length > 0)
            profileName.Value := profileList[1]
    }
}

/**
 * 加载选定的配置方案
 * @param {Object} ctrl - 控件对象
 */
LoadSelectedProfile(ctrl, *) {
    global profileDropDown, profileName

    settingsFile := A_ScriptDir "\settings.ini"
    profilesString := IniRead(settingsFile, "Profiles", "List", "默认")
    profileList := StrSplit(profilesString, "|")

    if (ctrl.Value <= 0 || ctrl.Value > profileList.Length)
        return

    selectedProfile := profileList[ctrl.Value]
    profileName.Value := selectedProfile

    LoadSettings(A_ScriptDir "\settings.ini", selectedProfile)
}

/**
 * 保存当前配置为方案
 */
SaveProfile(*) {
    global profileDropDown, profileName, statusBar
    
    profileNameInput := profileName.Value

    if (profileNameInput = "") {
        MsgBox("请输入配置方案名称", "提示", 48)
        return
    }

    settingsFile := A_ScriptDir "\settings.ini"
    profilesString := IniRead(settingsFile, "Profiles", "List", "默认")
    profileList := StrSplit(profilesString, "|")
    
    currentProfileName := ""
    if (profileDropDown.Value > 0 && profileDropDown.Value <= profileList.Length) {
        currentProfileName := profileList[profileDropDown.Value]
    }

    if (currentProfileName != profileNameInput && InArray(profileList, profileNameInput)) {
        if (MsgBox("配置方案「" profileNameInput "」已存在，是否覆盖？", "确认", 4) != "Yes")
            return
    }

    SaveSettings(settingsFile, profileNameInput)

    if (!InArray(profileList, profileNameInput)) {
        profileList.Push(profileNameInput)
        IniWrite(Join(profileList, "|"), settingsFile, "Profiles", "List")

        profileDropDown.Delete()
        for i, name in profileList {
            profileDropDown.Add([name])
        }
    }

    IniWrite(profileNameInput, settingsFile, "Global", "LastUsedProfile")

    for i, name in profileList {
        if (name = profileNameInput) {
            profileDropDown.Value := i
            break
        }
    }

    statusBar.Text := "配置方案「" profileNameInput "」已保存"
}


/**
 * 删除当前配置方案
 */
DeleteProfile(*) {
    global profileDropDown, profileName, statusBar

    settingsFile := A_ScriptDir "\settings.ini"
    profilesString := IniRead(settingsFile, "Profiles", "List", "默认")
    profileList := StrSplit(profilesString, "|")
    
    if (profileDropDown.Value <= 0 || profileDropDown.Value > profileList.Length)
        return
        
    currentProfileName := profileList[profileDropDown.Value]

    if (currentProfileName = "默认") {
        MsgBox("无法删除默认配置方案", "提示", 48)
        return
    }

    if (MsgBox("确定要删除配置方案「" currentProfileName "」吗？", "确认", 4) != "Yes")
        return

    for i, name in profileList {
        if (name = currentProfileName) {
            profileList.RemoveAt(i)
            break
        }
    }

    IniWrite(Join(profileList, "|"), settingsFile, "Profiles", "List")
    DeleteProfileSettings(settingsFile, currentProfileName)

    profileDropDown.Delete()
    for i, name in profileList {
        profileDropDown.Add([name])
    }
    
    profileDropDown.Value := 1
    profileName.Value := "默认"

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
    sectionPrefix := profileName "_"

    fileContent := FileRead(file)
    lines := StrSplit(fileContent, "`n", "`r")
    newContent := []

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
    if (arr.Length == 0)
        return false

    for i, v in arr {
        if (v == val)
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
    if (arr.Length == 0)
        return ""

    if (arr.Length == 1)
        return arr[1]

    result := ""
    arrLen := arr.Length

    for i, v in arr {
        result .= v
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

    settingsDir := RegExReplace(settingsFile, "[^\\]+$", "")
    if (!DirExist(settingsDir) && settingsDir != "") {
        try {
            DirCreate(settingsDir)
        } catch as err {
            statusBar.Text := "创建目录失败: " err.Message
            return
        }
    }

    if (!FileExist(settingsFile)) {
        try {
            FileAppend("[Profiles]`nList=默认`n`n[Global]`nLastUsedProfile=" profileName "`n`n", settingsFile)
            statusBar.Text := "已创建新的设置文件"
        } catch as err {
            statusBar.Text := "创建设置文件失败: " err.Message
            return
        }
    }

    DeleteProfileSettings(settingsFile, profileName)

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
        IniWrite(cSkill[i]["key"].Value, file, section, "Skill" i "Key")
        IniWrite(cSkill[i]["enable"].Value, file, section, "Skill" i "Enable")
        IniWrite(cSkill[i]["interval"].Value, file, section, "Skill" i "Interval")

        modeIndex := cSkill[i]["mode"].Value
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
 * 增加完整性检查
 * @param {String} file - 配置文件路径
 * @param {String} profileName - 配置名称
 */
SaveuSkillSettings(file, profileName) {
    global uCtrl

    section := profileName "_uSkill"

    ; 清除旧设置
    IniDelete(file, section)

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

    ; 确保保存所有暂停相关设置
    IniWrite(uCtrl["ipPause"]["enable"].Value, file, section, "IpPauseEnable")
    IniWrite(uCtrl["ipPause"]["interval"].Value, file, section, "IpPauseInterval")
    IniWrite(uCtrl["ipPause"]["pauseConfirm"].Value, file, section, "IpPausePauseConfirm")
    IniWrite(uCtrl["ipPause"]["resumeConfirm"].Value, file, section, "IpPauseResumeConfirm")

    IniWrite(uCtrl["tabPause"]["enable"].Value, file, section, "TabPauseEnable")
    IniWrite(uCtrl["tabPause"]["interval"].Value, file, section, "TabPauseInterval")
    IniWrite(uCtrl["tabPause"]["pauseConfirm"].Value, file, section, "TabPausePauseConfirm")
    IniWrite(uCtrl["tabPause"]["resumeConfirm"].Value, file, section, "TabPauseResumeConfirm")

    ; 确保保存所有其他功能设置
    IniWrite(uCtrl["dcPause"]["enable"].Value, file, section, "DcPauseEnable")
    IniWrite(uCtrl["dcPause"]["interval"].Value, file, section, "DcPauseInterval")
    IniWrite(uCtrl["shift"]["enable"].Value, file, section, "ShiftEnabled")
    IniWrite(uCtrl["ranDom"]["enable"].Value, file, section, "RandomEnabled")
    IniWrite(uCtrl["ranDom"]["max"].Value, file, section, "RandomMax")
    IniWrite(uCtrl["D4only"]["enable"].Value, file, section, "D4onlyEnable")

    ; 保存其他全局设置
    IniWrite(hotkeyModeDropDown.Value, file, section, "HotKeyMode")
    if (hotkeyModeDropDown.Value = 1) {
        IniWrite(hotkeyControl.Value, file, section, "useHotKey")
    }
    else {
        IniWrite(hotkeyControl.Value, file, section, "HotKey")
    }
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
        try {
            settingsDir := RegExReplace(settingsFile, "[^\\]+$", "")
            if (!DirExist(settingsDir) && settingsDir != "") {
                DirCreate(settingsDir)
            }

            FileAppend("[Profiles]`nList=默认`n`n[Global]`nLastUsedProfile=" profileName "`n`n", settingsFile)
            statusBar.Text := "已创建新的设置文件"

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

    loop 5 {
        try {
            key := IniRead(file, section, "Skill" A_Index "Key", A_Index)
            enabled := IniRead(file, section, "Skill" A_Index "Enable", 1)
            interval := IniRead(file, section, "Skill" A_Index "Interval", 20)
            mode := Integer(IniRead(file, section, "Skill" A_Index "Mode", 1))

            cSkill[A_Index]["key"].Value := key
            cSkill[A_Index]["enable"].Value := enabled
            cSkill[A_Index]["interval"].Value := interval

            try {
                cSkill[A_Index]["mode"].Value := mode
            } catch as err {
                cSkill[A_Index]["mode"].Value := 1
            }
        } catch as err {
            cSkill[A_Index]["key"].Value := A_Index
            cSkill[A_Index]["enable"].Value := 1
            cSkill[A_Index]["interval"].Value := 20
            cSkill[A_Index]["mode"].Value := 1
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
            mSkill["left"]["mode"].Value := leftMode
        } catch as err {
            mSkill["left"]["mode"].Value := 1
        }

        ; 设置右键模式下拉框
        try {
            mSkill["right"]["mode"].Value := rightMode
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
    global uCtrl
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
        ; 加载血条检测相关设置
        uCtrl["ipPause"]["enable"].Value := IniRead(file, section, "IpPauseEnable", "0")
        uCtrl["ipPause"]["interval"].Value := IniRead(file, section, "IpPauseInterval", "50")
        uCtrl["ipPause"]["pauseConfirm"].Value := IniRead(file, section, "IpPausePauseConfirm", "2")
        uCtrl["ipPause"]["resumeConfirm"].Value := IniRead(file, section, "IpPauseResumeConfirm", "2")

        ; 加载TAB检测相关设置
        uCtrl["tabPause"]["enable"].Value := IniRead(file, section, "TabPauseEnable", "0")
        uCtrl["tabPause"]["interval"].Value := IniRead(file, section, "TabPauseInterval", "100")
        uCtrl["tabPause"]["pauseConfirm"].Value := IniRead(file, section, "TabPausePauseConfirm", "2")
        uCtrl["tabPause"]["resumeConfirm"].Value := IniRead(file, section, "TabPauseResumeConfirm", "2")
        ; 加载其他设置
        uCtrl["dcPause"]["enable"].Value := IniRead(file, section, "DcPauseEnable", "1")
        uCtrl["dcPause"]["interval"].Value := IniRead(file, section, "DcPauseInterval", "2")
        uCtrl["shift"]["enable"].Value := IniRead(file, section, "ShiftEnabled", "0")
        uCtrl["ranDom"]["enable"].Value := IniRead(file, section, "RandomEnabled", "0")
        uCtrl["ranDom"]["max"].Value := IniRead(file, section, "RandomMax", "10")
        uCtrl["D4only"]["enable"].Value := IniRead(file, section, "D4onlyEnable", "1")

        ; 加载全局热键
        hotkeyModeDropDown.Value := IniRead(file, section, "HotkeyMode", "1")
        switch hotkeyModeDropDown.Value {
            case 1:
                hotkeyControl.Value := IniRead(file, section, "useHotKey", "F1")
            case 2:
                hotkeyControl.Value := IniRead(file, section, "HotKey", "XButton1")
            case 3:
                hotkeyControl.Value := IniRead(file, section, "HotKey", "XButton1")
        }

        OnHotkeyModeChange(hotkeyModeDropDown)
        ; 加载运行模式
        modeValue := Integer(IniRead(file, section, "RunMod", 1))
        if (modeValue = 1 || modeValue = 2) {
            RunMod.Value := modeValue
        }
    } catch as err {
    }
}

; ==================== 热键处理 ====================
#HotIf WinActive("ahk_class Diablo IV Main Window Class")

~LButton::
{
    global uCtrl
    static lastClickTime := 0

    if (uCtrl["dcPause"]["enable"].Value != 1)
        return

    currentTime := A_TickCount

    if (currentTime - lastClickTime < 400) {
        TogglePause("doubleClick", true)
        confirmTime := uCtrl["dcPause"]["interval"] ? uCtrl["dcPause"]["interval"].Value : 2
        SetTimer(() => TogglePause("doubleClick", false), -confirmTime * 1000)
        lastClickTime := 0
    } else {
        lastClickTime := currentTime
    }
}

; 初始化GUI
InitializeGUI()