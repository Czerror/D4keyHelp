#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

; ========== 全局变量定义 ==========
; 核心状态变量
global DEBUG := false               ; 启用调试模式
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
    myGui := Gui("", "暗黑4助手 v5.3")
    myGui.BackColor := "FFFFFF"                    ; 背景色设为白色
    myGui.SetFont("s10", "Microsoft YaHei UI")    ; 设置默认字体

    ;# ==================== 系统托盘菜单 ==================== #
    A_TrayMenu.Delete()  ; 清空默认菜单
    A_TrayMenu.Add("显示主界面", (*) => myGui.Show())
    A_TrayMenu.Add()  ; 分隔线
    A_TrayMenu.Add("开始/停止宏", ToggleMacro)
    A_TrayMenu.Add()  ; 分隔线
    A_TrayMenu.Add("退出", (*) => 
    ConfigManager.SaveProfileFromUI()
    ExitApp())
    A_TrayMenu.Default := "显示主界面"  ; 设置默认菜单项

    ;|------------------- 窗口事件绑定 -------------------|
    myGui.OnEvent("Escape", (*) => myGui.Minimize())  ; ESC键最小化
    myGui.OnEvent("Close", (*) => 
    ConfigManager.SaveProfileFromUI()
    ExitApp())          ; 关闭按钮退出

    ;# ==================== 界面构建 ==================== #
    CreateMainGUI()     ; 创建主界面框架
    CreateAllControls() ; 初始化所有功能控件

    ;# ==================== 状态栏 ==================== #
    statusBar := myGui.AddStatusBar(, "就绪")  ; 底部状态栏初始化

    ;# ==================== 窗口显示 ==================== #
    myGui.Show("w485 h535")

    ;# ==================== 配置初始化 ==================== #
    ConfigManager.Initialize()
}

;|===============================================================|
;| 函数: CreateMainGUI
;| 功能: 创建主程序界面及所有控件
;|===============================================================|
CreateMainGUI() {
    global myGui, startkey, ProfileName, hotkeyText , tabControl

    ;# ==================== 热键控制区域 ==================== #
    hotkeyText := myGui.AddGroupBox("x10 y10 w280 h120", "启动热键: 自定义 - F1")
    startkey := Map(
        "mode", myGui.AddDropDownList("x310 y65 w65 h90 Choose1", ["自定义", "侧键1", "侧键2"]),
        "userkey", [
            {key: "F1", input : true},       ; 自定义按键
            {key: "XButton1", input: false}, ; 鼠标侧键1
            {key: "XButton2", input: false}  ; 鼠标侧键2
        ],
        "guiHotkey", myGui.AddHotkey("x380 y65 w90 h22")
    )

    startkey["mode"].OnEvent("Change", (*) => (
        LoadStartHotkey(startkey)
    ))

    startkey["guiHotkey"].OnEvent("Change", (*) => (
        (startkey["guiHotkey"].Value = "") && (startkey["guiHotkey"].Value := "F1"),
        startkey["userkey"][1].key := startkey["guiHotkey"].Value,
        LoadStartHotkey(startkey)
    ))

    ;# ==================== 配置管理区域 ==================== #
    myGui.AddGroupBox("x300 y10 w175 h120", "配置管理")
    profileName := myGui.AddComboBox("x310 y30 w160 h120 Choose1", ["默认"])
    profileName.OnEvent("Change", (ctrl, *) => (
        ConfigManager.LoadSelectedProfile(ctrl)
    ))
    myGui.AddButton("x310 y100 w60 h25", "保存").OnEvent("Click", (*) => (
        ConfigManager.SaveProfileFromUI()
    ))
    myGui.AddButton("x410 y100 w60 h25", "删除").OnEvent("Click", (*) => (
        ConfigManager.DeleteProfileFromUI()
    ))
    ;# ==================== Tab 控件 ==================== #
    tabControl := myGui.AddTab("x10 y135 w465 h360 Choose1", ["战斗模式", "工具模式"])
    ; 创建 Tab1 (按键设置) 的控件
    tabControl.UseTab(2)
}

;|===============================================================|
;| 函数: CreateAllControls
;| 功能: 创建主界面所有GUI控件并初始化配置
;|===============================================================|
CreateAllControls() {
    global myGui, cSkill, mSkill, uCtrl, skillMod, tabControl, statusText, RunMod

    cSkill := Map()
    mSkill := Map()
    uCtrl := Map()
    skillMod := ["连点", "BUFF", "按住", "资源"]
    tabControl.UseTab(1)
    ;# ==================== 运行模式选择 ==================== #
    statusText := myGui.AddText("x30 y35 w80 h20", "状态: 未运行")
    myGui.AddButton("x30 y63 w85 h30", "开始/停止").OnEvent("Click", (*) => 
    ToggleMacro()
    TogglePause("window", true)
    )
    myGui.AddText("x180 y103 w30 h20", "模式: ")
    RunMod := myGui.AddDropDownList("x215 y100 w65 h60 Choose1", ["多线程", "单线程"])

    ;# ==================== 按键设置主区域 ==================== #
   ; 添加列标题
    myGui.AddText("x35 y160 w100 h20", "技能与按键")
    myGui.AddText("x133 y160 w60 h20", "启用")
    myGui.AddText("x180 y160 w80 h20", "间隔(毫秒)")
    myGui.AddText("x252 y160 w80 h20", "运行策略")

    ;|----------------------- 自动启停 -----------------------|
    myGui.AddGroupBox("x325 y160 w140 h230", "启停管理")
    myGui.AddButton("x335 y340 w120 h25", "刷新检测").OnEvent("Click", RefreshDetection)

    ;|----------------------- 技能配置 -----------------------|
    loop 5 {
        yPos := 190 + (A_Index - 1) * 30

        ; 技能标签
        myGui.AddText("x30 y" yPos " w40 h20", "技能" A_Index ":")

        ; 技能配置Map
        cSkill[A_Index] := Map(
            "key", myGui.AddHotkey("x80 y" yPos " w30 h20", A_Index),
            "enable", myGui.AddCheckbox("x125 y" yPos " w45 h20", "启用"),
            "interval", myGui.AddEdit("x185 y" yPos " w50 h20", "20"),
            "mode", myGui.AddDropDownList("x250 y" yPos-2 " w60 h120 Choose1", skillMod)
        )
    }

    ;|----------------------- 左键配置 -----------------------|
    mSkill["left"] := Map(
        "text", myGui.AddText("x30 y340 w40 h20", "左键:"),
        "key", "LButton",  ; 固定键值
        "enable", myGui.AddCheckbox("x125 y340 w45 h20", "启用"),
        "interval", myGui.AddEdit("x185 y340 w50 h20", "80"),
        "mode", myGui.AddDropDownList("x250 y338 w60 h120 Choose1", skillMod)
    )

    ;|----------------------- 右键配置 -----------------------|
    mSkill["right"] := Map(
        "text", myGui.AddText("x30 y370 w40 h20", "右键:"),
        "key", "RButton",  ; 固定键值
        "enable", myGui.AddCheckbox("x125 y370 w45 h20", "启用"),
        "interval", myGui.AddEdit("x185 y370 w50 h20", "300"),
        "mode", myGui.AddDropDownList("x250 y368 w60 h120 Choose1", skillMod)
    )

    ;|---------------------- 基础功能 ------------------------|
    uCtrl["potion"] := Map(
        "text", myGui.AddText("x30 y400 w35 h20", "药水:"),
        "key", myGui.AddHotkey("x65 y400 w45 h20", "q"),
        "enable", myGui.AddCheckbox("x125 y400 w45 h20", "启用"),
        "interval", myGui.AddEdit("x185 y400 w50 h20", "3000"),
        "mode", myGui.AddDropDownList("x250 y398 w60 h120 Choose1", skillMod)
    )
    uCtrl["potion"]["mode"].Enabled := false
    ;|---------------------- 强移功能 ------------------------|
    uCtrl["forceMove"] := Map(
        "text", myGui.AddText("x30 y430 w35 h20", "强移:"),
        "key", myGui.AddHotkey("x65 y430 w45 h20", "e"),
        "enable", myGui.AddCheckbox("x125 y430 w45 h20", "启用"),
        "interval", myGui.AddEdit("x185 y430 w50 h20", "50"),
        "mode", myGui.AddDropDownList("x250 y428 w60 h120 Choose1", skillMod)
    )
    uCtrl["forceMove"]["mode"].Enabled := false
    ;|---------------------- 闪避功能 ------------------------|
    uCtrl["dodge"] := Map(
        "text", myGui.AddText("x30 y460 w35 h20", "闪避:"),
        "key", myGui.AddHotkey("x65 y460 w45 h20", "Space"),
        "enable", myGui.AddCheckbox("x125 y460 w45 h20", "启用"),
        "interval", myGui.AddEdit("x185 y460 w50 h20", "20"),
        "mode", myGui.AddDropDownList("x250 y458 w60 h120 Choose1", skillMod)
    )
    ; 闪避键空值保护
    uCtrl["dodge"]["key"].OnEvent("Change", (*) => (
        (uCtrl["dodge"]["key"].Value = "") && (uCtrl["dodge"]["key"].Value := "Space")
    ))
    uCtrl["dodge"]["mode"].Enabled := false
    ;|---------------------- 辅助功能 ------------------------|
    uCtrl["shift"] := Map(   ; Shift键辅助
        "text", myGui.AddText("x325 y400 w60 h20", "按住Shift:"),
        "enable", myGui.AddCheckbox("x395 y400 w20 h20")
    )

    uCtrl["random"] := Map(  ; 随机延迟
        "text", myGui.AddText("x325 y430 w60 h20", "随机延迟:"),
        "enable", myGui.AddCheckbox("x395 y430 w20 h20"),
        "max", myGui.AddEdit("x420 y430 w45 h20", "10")
    )

    uCtrl["random"]["max"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["random"]["max"], 1, 10)))

    uCtrl["D4only"] := Map(  ; D4only
        "text", myGui.AddText("x30 y103 w110 h20", "仅在暗黑4中使用:"),
        "enable", myGui.AddCheckbox("x145 y104 w18 h18", "1")
    )

    ;|---------------------- 血条检测 ------------------------|
    uCtrl["ipPause"] := Map(
        "text", myGui.AddText("x335 y220 w60 h20", "血条检测:"),
        "enable", myGui.AddCheckbox("x400 y220 w20 h20"),
        "interval", myGui.AddEdit("x420 y220 w40 h20", "50")
    )
    ; 输入验证
    uCtrl["ipPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["ipPause"]["interval"], 10, 1000)))

    ;|---------------------- 界面检测 ------------------------|
    uCtrl["tabPause"] := Map(
        "text", myGui.AddText("x335 y250 w60 h20", "界面检测:"),
        "enable", myGui.AddCheckbox("x400 y250 w20 h20"),
        "interval", myGui.AddEdit("x420 y250 w40 h20", "50")
    )
    ; 输入验证
    uCtrl["tabPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["interval"], 10, 1000)))
    ;|---------------------- 坐标偏移量 ------------------------|
    uCtrl["xy"] := Map(
        "text", myGui.AddText("x335 y280 w60 h20", "偏移:"),
        "text2", myGui.AddText("x375 y280 w15 h20", "X"),
        "x", myGui.AddEdit("x390 y278 w25 h20", "0"),
        "text3", myGui.AddText("x420 y280 w15 h20", "Y"),
        "y", myGui.AddEdit("x435 y278 w25 h20", "0")
    )
    ; 输入验证
    uCtrl["xy"]["x"].OnEvent("LoseFocus", (*) => (
        uCtrl["xy"]["x"].Value := Integer(uCtrl["xy"]["x"].Value)
        LimitEditValue(uCtrl["xy"]["x"], -3, 3)))
    uCtrl["xy"]["y"].OnEvent("LoseFocus", (*) => (
        uCtrl["xy"]["y"].Value := Integer(uCtrl["xy"]["y"].Value)
        LimitEditValue(uCtrl["xy"]["y"], -3, 3)))
    ;|---------------------- 双击暂停 ------------------------|
    uCtrl["dcPause"] := Map(
        "text", myGui.AddText("x335 y190 w60 h20", "双击暂停:"),
        "enable", myGui.AddCheckbox("x400 y190 w20 h20"),
        "interval", myGui.AddEdit("x420 y190 w20 h20", "2"),
        "text2", myGui.AddText("x443 y190 w18 h20", "秒")
    )

    uCtrl["dcPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["dcPause"]["interval"], 1, 3)))

    ;|----------------------- 鼠标自动移动 -----------------------|
    uCtrl["mouseAutoMove"] := Map(
        "text", myGui.AddText("x325 y460 w60 h20", "鼠标自移:"),
        "enable", myGui.AddCheckbox("x395 y460 w20 h20"),
        "interval", myGui.AddEdit("x420 y460 w45 h20", "1000"),
        "currentPoint", 1  ; 移动点位标记
    )
    ; 切换到工具模式
    tabControl.UseTab(2)
    uCtrl["PM"] := Map(
        "mod", myGui.AddDropDownList("x90 y178 w60 h60 Choose1", ["暗金", "传奇"]),
        "trueTime", myGui.AddEdit("x270 y178 w40 h20", "120"),
        "modtime", myGui.AddEdit("x390 y178 w40 h20", "0"),
        "time", 0,
        "time1", myGui.AddEdit("x90 y210 w300 h20", "0"),
        "timeX", myGui.AddEdit("x90 y240 w300 h20", "0"),
        "correct", myGui.AddEdit("x120 y270 w20 h20", "1"),
        "xiuValue", myGui.AddEdit("x120 y300 w20 h20", "1")
    )
    
    uCtrl["PM"]["time1"].Enabled := false
    uCtrl["PM"]["timeX"].Enabled := false
    uCtrl["PM"]["correct"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["PM"]["correct"], 1, 5)
    ))
    uCtrl["PM"]["xiuValue"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["PM"]["xiuValue"], 1, 5)
    ))
    myGui.AddText("x30 y180 w60 h20", "精造模式:")
    myGui.AddText("x180 y180 w90 h20", "窗口周期(ms):")
    myGui.AddText("x330 y180 w60 h20", "偏差修正:")
    myGui.AddText("x30 y210 w60 h20", "记录时间:")
    myGui.AddText("x30 y240 w60 h20", "时间偏差:")
    myGui.AddText("x30 y270 w90 h20", "实际命中词条:")
    myGui.AddText("x30 y300 w90 h20", "期望命中词条:")
    myGui.AddButton("x30 y330 w60 h40", "开始").OnEvent("Click", (*) => PmMod("start"))
    myGui.AddButton("x110 y330 w60 h40", "继续").OnEvent("Click", (*) => PmMod("next"))
    myGui.AddButton("x200 y330 w60 h40", "重置").OnEvent("Click", (*) => PmMod("reset"))
    ;|---------------------- 窗口置顶选项 ------------------------|
    uCtrl["alwaysOnTop"] := Map(
        "text", myGui.AddText("x30 y98 w60 h20", "窗口置顶:"),
        "enable", myGui.AddCheckbox("x90 y100 w15 h15")
    )
    ; 绑定事件，当勾选状态改变时切换窗口置顶属性
    uCtrl["alwaysOnTop"]["enable"].OnEvent("Click", (*) => ToggleAlwaysOnTop())
    tabControl.UseTab()
}

/**
 * 数值限制函数
 * @param {Object} ctrl - 控件对象
 * @param {Number} min - 最小值
 * @param {Number} max - 最大值
 */
LimitEditValue(ctrl, min, max) {
    try {
        inputValue := Trim(ctrl.Value)
        if (inputValue = "" || inputValue = "-") {
            ctrl.Value := min
            return
        }

        value := Number(inputValue)

        if (!IsNumber(value)) {
            ctrl.Value := min
            return
        }
        if (value < min) {
            ctrl.Value := min
        } else if (value > max) {
            ctrl.Value := max
        } else {
            ctrl.Value := value
        }
        
    } catch {
        ctrl.Value := min
    }
    return
}

/**
 * 切换窗口置顶状态
 */
ToggleAlwaysOnTop(*) {
    global myGui, uCtrl
    try {
        if (uCtrl["alwaysOnTop"]["enable"].Value = 1) {
            ; 设置窗口置顶
            WinSetAlwaysOnTop(true, myGui.Hwnd)
        } else {
            ; 取消窗口置顶
            WinSetAlwaysOnTop(false, myGui.Hwnd)
        }
    } catch as err {
        OutputDebug "切换窗口置顶状态失败: " err.Message
    }
}

/**
 * 加载全局热键
 * @param {Object} startkey - 热键配置对象
 */
LoadStartHotkey(startkey) {
    global statusBar
    static currentHotkey := ""

    mode := startkey["mode"].Value
    startkey["guiHotkey"].Enabled := startkey["userkey"][mode].input
    newHotkey := ""

    switch mode {
        case 1:
            newHotkey := startkey["userkey"][1].key
        case 2:
            newHotkey := startkey["userkey"][2].key
        case 3:
            newHotkey := startkey["userkey"][3].key
    }

    try {
        if (currentHotkey != "" && currentHotkey != newHotkey) {
            try {
                Hotkey(currentHotkey, "Off")
            } catch {
            }
        }

        if (newHotkey != currentHotkey) {
            Hotkey(newHotkey, ToggleMacro, "On")
            currentHotkey := newHotkey
            if (IsSet(statusBar)) {
                statusBar.Text := "热键已更新: " newHotkey
            }
            UpdateHotkeyText()
        }
    } catch {
    }
}

UpdateHotkeyText() {
    global startkey, hotkeyText
    
    if (!IsSet(startkey) || !IsSet(hotkeyText))
        return
        
    try {
        mode := startkey["mode"].Value
        modeNames := ["自定义", "鼠标侧键1", "鼠标侧键2"]
        modeName := modeNames[mode]
        
        currentKey := ""
        switch mode {
            case 1:
                currentKey := startkey["userkey"][1].key
            case 2:
                currentKey := "XButton1"
            case 3:
                currentKey := "XButton2"
        }

        displayText := "启动热键: " . modeName . " - " . currentKey
        hotkeyText.Text := displayText
        
    } catch {
        hotkeyText.Text := "启动热键: 自定义 - F1"
    }
}

; ==================== 控制函数 ====================
/**
 * 核心控制函数
 */
ToggleMacro(*) {
    global isRunning, uCtrl, pauseConfig
    if !IsSet(pauseConfig) {
        pauseConfig := Map(
            "window", {state: false, name: "窗口切换"},
            "blood", {state: false, name: "血条检测"},
            "tab", {state: false, name: "TAB界面"},
            "enter", {state: false, name: "对话框"},
            "doubleClick", {state: false, name: "双击暂停"}
        )
    }

    isRunning := !isRunning
    
    if (isRunning) {
        ManageTimers(true)
        StartAllTimers()
        UpdateStatus("已启动", "宏已启动")
    } else {
        ManageTimers(false)
        StopAllTimers()
        pauseConfig.Clone()
        UpdateStatus("已停止", "宏已停止")
    }
}

/**
 * 核心启停函数
 * @param {String} reason - 原因
 * @param {Boolean} state - 状态
 */
TogglePause(reason := "", state := unset) {
    global pauseConfig, isRunning
    if !isRunning {
        return
    }
    
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
        if (isRunning) {
            UpdateStatus("运行中", "宏已启动")
        } else {
            UpdateStatus("已停止", "宏已停止")
        }
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
    global cSkill, mSkill, uCtrl, RunMod, skillTimers, pauseConfig

    for reason, config in pauseConfig {
        config.state := false
    }

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
        KeyQueueManager.StartQueue()
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
    global skillTimers, RunMod, uCtrl

    if (RunMod.Value = 2) {
        KeyQueueManager.StopQueue()
    }

    if (IsSet(skillTimers)) {
        for timerName, boundFunc in skillTimers.Clone() {
            SetTimer(boundFunc, 0)
            skillTimers.Delete(timerName)
        }
        skillTimers.Clear()
    }

    if (uCtrl["mouseAutoMove"]["enable"].Value) {
        SetTimer(MoveMouse, 0)
    }

    ReleaseAllKeys()
}

/**
 * 重置所有变量
 */
ReleaseAllKeys() {
    global holdStates, uCtrl, RunMod

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

    if uCtrl["shift"]["enable"].Value {
        Send "{Blind}{Shift up}"
    }
}

/**
 * 管理全局定时器
 * @param {String} timerType - 定时器类型
 * @param {Boolean} enable - 是否启用定时器
 * @param {Integer} interval - 定时器间隔(毫秒)
 * @returns {Boolean} - 操作是否成功
 */
ManageTimers(enable) {
    global uCtrl

    d4only := uCtrl["D4only"]["enable"].Value
    blood := uCtrl["ipPause"]["enable"].Value
    tab := uCtrl["tabPause"]["enable"].Value
    
    if (!d4only) {
        blood := false
        tab := false
    }

    SetTimer(CheckWindow, enable ? 100 : 0)
    if (!enable) {
        for fn in [CheckWindow, AutoPauseByBlood, AutoPauseByTAB] {
            SetTimer(fn, 0)
        }
    }

    if (blood) {
        actualInterval :=  (
            uCtrl.Has("ipPause") && uCtrl["ipPause"].Has("interval")
                ? Integer(uCtrl["ipPause"]["interval"].Value)
                : 50
        )
        SetTimer(AutoPauseByBlood, enable ? actualInterval : 0)
    }
    
    if (tab) {
        actualInterval := (
            uCtrl.Has("tabPause") && uCtrl["tabPause"].Has("interval")
                ? Integer(uCtrl["tabPause"]["interval"].Value)
                : 100
        )
        SetTimer(AutoPauseByTAB, enable ? actualInterval : 0)
    }
}

/**
 * 立即刷新所有检测
 * 清理缓存，立即执行检测，支持强制恢复运行
 * @param {*} - 事件参数（来自按钮点击事件）
 */
RefreshDetection(*) {
    global isRunning, statusBar, uCtrl, pauseConfig

    if !isRunning {
        statusBar.Text := "无需刷新检测"
        return
    }
    ManageTimers(false)
    Sleep 100  ; 确保定时器已停止
    ManageTimers(true)
    UpdateStatus("运行中", "已强制重置")
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
                    Send "{Blind}{Shift down}"
                    Click(keyData.key)
                    Send "{Blind}{Shift up}"
                } else {
                    Click(keyData.key)
                }
            } else {
                if (shiftEnabled) {
                    Send "{Blind}{Shift down}"
                    Send "{" keyData.key "}"
                    Send "{Blind}{Shift up}"
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
                        Send "{Blind}{Shift down}"
                        Click(keyData.key)
                        Send "{Blind}{Shift up}"
                    } else {
                        Click(keyData.key)
                    }
                } else {
                    if (shiftEnabled) {
                        Send "{Blind}{Shift down}"
                        Send "{" keyData.key "}"
                        Send "{Blind}{Shift up}"
                    } else {
                        Send "{" keyData.key "}"
                    }
                }
            }

        default: ; 连点模式
            if (keyData.isMouse) {
                if (shiftEnabled) {
                    Send "{Blind}{Shift down}"
                    Click(keyData.key)
                    Send "{Blind}{Shift up}"
                } else {
                    Click(keyData.key)
                }
            } else {
                if (shiftEnabled) {
                    Send "{Blind}{Shift down}"
                    Send "{" keyData.key "}"
                    Send "{Blind}{Shift up}"
                } else {
                    Send "{" keyData.key "}"
                }
            }
    }
}

; ==================== 队列模式实现 ====================
/**
 * 按键队列管理器类
 * @param {Object} keyData
 */
class KeyQueueManager {
    static keyQueue := []
    static lastExec := Map()
    static critSection := false
    static maxLen := 15
    static QueueTimer := ""
    ; 启动队列模式
    static StartQueue() {
        this.QueueTimer := (*) => this.KeyQueueWorker()
        SetTimer(this.QueueTimer, 10)
    }
    ; 停止队列模式
    static StopQueue() {
        SetTimer(this.QueueTimer, 0)
        this.QueueTimer := unset
        this.ClearQueue()
    }

    /**
     * 键位入队函数
     * @param {Object} keyData - 按键数据
     */
    static EnqueueKey(keyData) {
        uniqueKey := keyData.uniqueKey
        priority := this.GetPriority(keyData.mode, keyData.id)
        now := A_TickCount
        existingIndex := 0
        for index, item in this.keyQueue {
            if (item.uniqueKey = uniqueKey) {
                existingIndex := index
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
            this.keyQueue.RemoveAt(existingIndex)

        if (this.keyQueue.Length >= KeyQueueManager.maxLen) {
            this.keyQueue.RemoveAt(this.keyQueue.Length)
        }

        if (this.keyQueue.Length == 0) {
            this.keyQueue.Push(item)
            return
        }

        inserted := false
        loop this.keyQueue.Length {
            if (priority > this.keyQueue[A_Index].priority) {
                this.keyQueue.InsertAt(A_Index, item)
                inserted := true
                break
            }
        }

        if (!inserted) {
            this.keyQueue.Push(item)
        }
    }

    /**
     * 优先级计算函数
     * @param {Integer} mode - 按键模式
     * @param {String} identifier - 按键标识符
     * @returns {Integer} 优先级数值
     */
    static GetPriority(mode, identifier := "") {
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
    static KeyQueueWorker() {
        global holdStates
        if !(this.keyQueue is Array) || this.keyQueue.Length == 0
            return

        if this.critSection
            return

        this.critSection := true
        now := A_TickCount
        i := this.keyQueue.Length
        while (i >= 1) {
            item := this.keyQueue[i]
            uniqueKey := item.uniqueKey
            lastExecTime := this.lastExec.Get(uniqueKey, 0)

            if (item.mode == 3) {
                if (IsSet(holdStates) && holdStates.Has(uniqueKey) && holdStates[uniqueKey]) {
                    i--
                    continue
                }
                
                HandleKeyMode(item)
                this.lastExec[uniqueKey] := now
                i--
                continue
            }

            if ((now - lastExecTime) >= item.interval) {
                HandleKeyMode(item)
                this.lastExec[uniqueKey] := now
                ; 对于非按住模式的按键，重新入队
                if (item.mode != 3) {
                    this.keyQueue.RemoveAt(i)
                    this.EnqueueKey(item)
                }
            }
            i--
        }
        
        this.critSection := false
    }


    /**
     * 清空队列
     */
    static ClearQueue() {
        this.keyQueue := []
        this.lastExec.Clear()
        this.critSection := false
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

    if (uCtrl["random"]["enable"].Value == 1) {
        keyData.interval += Random(1, uCtrl["random"]["max"].Value)
    }

    if (RunMod.Value == 1) {
        boundFunc := HandleKeyMode.Bind(keyData)
        skillTimers[keyData.timerKey] := boundFunc
        SetTimer(boundFunc, keyData.interval)
    } else if (RunMod.Value == 2) {
        KeyQueueManager.EnqueueKey(keyData)
    }
}

; ==================== 图像和窗口检测 ====================
/**
 * 窗口切换检查函数
 */
CheckWindow() {
    global uCtrl
    
    try {
        if (uCtrl["D4only"]["enable"].Value == 1) {
            TogglePause("window", !WinActive("ahk_class Diablo IV Main Window Class"))
        } else {
            if (WinActive("ahk_class AutoHotkeyGUI") || InStr(WinGetTitle("A"), "暗黑4助手")) {
                TogglePause("window", true)
            } else {
                TogglePause("window", false)
            }
        }
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
GetWindowInfo() {
    D4Windows := Map(
        "D4W", 0.0,       ; 客户区实际宽度
        "D4H", 0.0,       ; 客户区实际高度
        "CD4W", 0.0,      ; 客户区中心X坐标（浮点）
        "CD4H", 0.0,      ; 客户区中心Y坐标（浮点）
        "D4S", 1.0,       ; 统一缩放比例（Min(D4SW,D4SH)）
        "D4SW", 1.0,      ; 宽度独立缩放比例
        "D4SH", 1.0,       ; 高度独立缩放比例
        "D44KW", 3840,    ; 添加参考分辨率宽度到返回Map
        "D44KH", 2160,    ; 添加参考分辨率高度到返回Map
        "D44KWC", 1920,  ; 添加参考中心X坐标到返回Map
        "D44KHC", 1080   ; 添加参考中心Y坐标到返回Map
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
            D4Windows["D4SW"] := D4Windows["D4W"] / D4Windows["D44KW"]
            D4Windows["D4SH"] := D4Windows["D4H"] / D4Windows["D44KH"]
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

    static lastWindowInfo := unset
    currentWindowInfo := GetWindowInfo()

    if (IsSet(lastWindowInfo) && IsSet(allcoords)) {
        if (lastWindowInfo["D4W"] == currentWindowInfo["D4W"] && 
            lastWindowInfo["D4H"] == currentWindowInfo["D4H"]) {
            return allcoords
        }
    }

    lastWindowInfo := currentWindowInfo.Clone()
    allcoords := Map()

    ; 使用预定义的坐标配置
    static coordConfig := Map(
        "monster_blood", {x: 1605, y: 90},
        "boss_blood", {x: 1435, y: 95},
        "skill_bar_blue", {x: 1540, y: 1885},
        "tab_interface_red", {x: 3790, y: 95},
        "dialog_gray_bg", {x: 150, y: 2070},
        "resource_bar", {x: 2620, y: 1875}
    )

    for name, coord in coordConfig {
        allcoords[name] := Convert(coord, currentWindowInfo)
    }

    loop 6 {
        allcoords["dialog_red_btn_" A_Index] := Convert({
            x: 50 + 90 * (A_Index - 1), 
            y: 1440
        }, currentWindowInfo)
    }

    static mouseMoveRatios := [
        {x: 0.15, y: 0.15}, {x: 0.5, y: 0.15}, {x: 0.85, y: 0.15},
        {x: 0.85, y: 0.85}, {x: 0.5, y: 0.85}, {x: 0.15, y: 0.85}
    ]
    
    loop 6 {
        ratio := mouseMoveRatios[A_Index]
        allcoords["mouse_move_" A_Index] := Convert({
            x: Round(ratio.x * currentWindowInfo["D44KW"]), 
            y: Round(ratio.y * currentWindowInfo["D44KH"])
        }, currentWindowInfo)
    }
    return allcoords
}

Convert(coord, windowInfo := unset) {
    global uCtrl
    static cacheInfo := unset
    if (!IsSet(cacheInfo)) {
        cacheInfo := GetWindowInfo()
    }
    if IsSet(windowInfo) {
        useInfo := windowInfo
    } else {
        useInfo := cacheInfo
    }
    UserX := uCtrl["xy"]["x"].Value
    UserY := uCtrl["xy"]["y"].Value

    x := Round(useInfo["CD4W"] + (coord.x - useInfo["D44KWC"]) * useInfo["D4S"])
    y := Round(useInfo["CD4H"] + (coord.y - useInfo["D44KHC"]) * useInfo["D4S"])

    if (useInfo["D4S"] < 1) {
        x += UserX
        y += UserY
    }
    return { x: x, y: y }
}

; 高精度计时器
GetPreciseTime() {
    static freq := 0
    static counter := 0
    if (freq = 0) {
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    }
    DllCall("QueryPerformanceCounter", "Int64*", &counter)
    return (counter * 1000000) // freq
}


PmCoord(){
    static Pm := Map(
        "Up", {x: 970, y: 1835},
        "res", {x: 865, y: 725},
        "fix", {x: 540, y: 1900},
        "skip", {x: 690, y: 1650}
    )
    PmCoord := Map()
    for key, coord in Pm {
        PmCoord[key] := Convert(coord)
    }
    return PmCoord
}

PmMod(ctrl){
    global uCtrl

    if WinExist("ahk_class Diablo IV Main Window Class") {
        WinActivate
    }

    coord := PmCoord()
    modtime := uCtrl["PM"]["modtime"].Value * 1000
    mode := uCtrl["PM"]["mod"].Value
    truetime := uCtrl["PM"]["trueTime"].Value * 1000  ; 窗口期:125ms
    totalPhases := (mode = 1) ? 4 : 5
    needtime := truetime * totalPhases ; 完整周期时间:暗金500ms，传奇625ms
    correct := uCtrl["PM"]["correct"].Value
    xiuValue := uCtrl["PM"]["xiuValue"].Value
    
    if (ctrl == "start") {
        if WinExist("ahk_class Diablo IV Main Window Class") {
            WinActivate
        }
        Sleep 150
        MouseMove(coord["Up"].x, coord["Up"].y, 0)
        Sleep 150
        Loop 3 {
            Click
            Sleep 150
        }
        startTime := GetPreciseTime()
        Click
        uCtrl["PM"]["time1"].Value := FormatTime(, "HH:mm:ss") . "." . Format("{:03}", Mod(Round(startTime/1000), 1000))
        uCtrl["PM"]["time"] := startTime
    } else if (ctrl == "next") {
        startTime := uCtrl["PM"]["time"]
        
        ; 前3次点击
        MouseMove(coord["Up"].x, coord["Up"].y, 0)
        Loop 3 {
            Click
            Sleep 130
        }
        currentTime := GetPreciseTime()
        elapsedTime := currentTime - startTime
        currentPhase := Mod(elapsedTime, needtime)
        targetCenter := Mod((xiuValue - correct) * truetime + (truetime / 5), needtime)
        waitTime := Mod(targetCenter - currentPhase + needtime, needtime)
        if (waitTime < truetime / 2) {
            waitTime += needtime
        }

        targetTime := currentTime + waitTime - modtime
        while (targetTime > GetPreciseTime()) {
            Sleep 0
        }
        Click
        endTime := GetPreciseTime()
        
        ; 验证结果
        totalElapsed := endTime - startTime
        finalPhase := Mod(totalElapsed, needtime)
    
        ; 计算实际命中的固定相位编号
        phaseIndex := Floor(finalPhase / truetime)
        actualFixedPhase := Mod(correct + phaseIndex - 1, totalPhases) + 1

        ; 计算目标相位中心点
        targetCenter := Mod((xiuValue - correct) * truetime + (truetime / 5), needtime)
    
        ; 计算偏差
        phaseDeviation := finalPhase - targetCenter + modtime
        uCtrl["PM"]["timeX"].Value := "总耗时:" . Floor(totalElapsed/1000) . "ms 实际窗口:" . actualFixedPhase . "/" . xiuValue " 偏差: " . Round(phaseDeviation/1000) . "ms"
    } else if (ctrl == "reset") {
        ; 重置所有时间记录
        uCtrl["PM"]["nettime"].Value := 0
        uCtrl["PM"]["time"] := 0
        uCtrl["PM"]["time1"].Value := 0
        uCtrl["PM"]["timeX"].Value := 0
        uCtrl["PM"]["correct"].Value := 1
        uCtrl["PM"]["xiuValue"].Value := 1
        return
    }    
}

; ==================== 像素检测与暂停机制 ====================
/**
 * 专用的自动暂停函数
 * 支持像素缓存，避免重复采样
 */
CheckKeyPoints(allcoords, pixelCache := unset) {  

    dfxCoord := allcoords["skill_bar_blue"]
    tabCoord := allcoords["tab_interface_red"]

    colorDFX := IsSet(pixelCache) && pixelCache.Has(dfxCoord.x . "," . dfxCoord.y) ? 
        pixelCache[dfxCoord.x . "," . dfxCoord.y] : GetPixelRGB(dfxCoord.x, dfxCoord.y)

    if (ColorDetector.IsBlue(colorDFX)) {
        return {isBlueColor: true, isRedColor: false}
    }

    colorTAB := IsSet(pixelCache) && pixelCache.Has(tabCoord.x . "," . tabCoord.y) ? 
        pixelCache[tabCoord.x . "," . tabCoord.y] : GetPixelRGB(tabCoord.x, tabCoord.y)

    if (ColorDetector.IsRed(colorTAB)) {
        return {isBlueColor: false, isRedColor: true}
    } else {
        return {isBlueColor: true, isRedColor: false}
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

        if (!colorDetector.IsGray(grayColor))
            return false

        ; 2. 检测红色按钮
        for , point in redPoints {
            coord := allcoords[point]
            key := coord.x . "," . coord.y
            
            colorObj := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(coord.x, coord.y)

            if (colorDetector.IsRed(colorObj)) {
                return true
            }
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
        baseCoord := allcoords["boss_blood"]

        hitCount := 0

        loop 8 {
            offsetX := Random(-2, 2)
            offsetY := Random(-2, 2)

            sampleX := baseCoord.x + offsetX
            sampleY := baseCoord.y + offsetY

            key := sampleX . "," . sampleY

            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(sampleX, sampleY)

            if (IsSet(pixelCache)) {
                pixelCache[key] := color
            }

            if (ColorDetector.IsRed(color)) {
                hitCount++
                if (hitCount >= 4) {
                    return true
                }
            }
        }
        return false
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
        baseCoord := allcoords["monster_blood"]

        hitCount := 0

        loop 8 {
            offsetX := Random(-2, 2)
            offsetY := Random(-2, 2)

            sampleX := baseCoord.x + offsetX
            sampleY := baseCoord.y + offsetY

            key := sampleX . "," . sampleY

            color := (IsSet(pixelCache) && pixelCache.Has(key)) ? 
                pixelCache[key] : GetPixelRGB(sampleX, sampleY)

            if (IsSet(pixelCache)) {
                pixelCache[key] := color
            }

            if (ColorDetector.IsRed(color)) {
                hitCount++
                if (hitCount >= 4) {
                    return true
                }
            }
        }
        return false
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

    PAUSE := 2
    RESUME := 2

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
    static tabPauseMissCount := 0
    static tabResumeHitCount := 0
    static enterPauseMissCount := 0
    static enterResumeHitCount := 0

    TAB_PAUSE := 2
    TAB_RESUME := 2

    try {
        pixelCache := Map()
        keyPoints := CheckKeyPoints(allcoords, pixelCache)

        ; 处理 TAB 界面检测
        if (pauseConfig["tab"].state) {
            if (keyPoints.isBlueColor) {
                tabResumeHitCount++
                tabPauseMissCount := 0
                if (tabResumeHitCount >= TAB_RESUME) {
                    TogglePause("tab", false)
                    tabResumeHitCount := 0
                }
            } else {
                tabResumeHitCount := 0
            }
        } else {
            if (!keyPoints.isBlueColor && keyPoints.isRedColor) {
                tabPauseMissCount++
                tabResumeHitCount := 0
                if (tabPauseMissCount >= TAB_PAUSE) {
                    TogglePause("tab", true)
                    tabPauseMissCount := 0
                }
            } else {
                tabPauseMissCount := 0
            }
        }

        ; 处理对话框检测
        if (pauseConfig["enter"].state) {
            if (!CheckPauseByEnter(allcoords, pixelCache)) {
                enterResumeHitCount++
                enterPauseMissCount := 0
                if (enterResumeHitCount >= TAB_RESUME) {
                    TogglePause("enter", false)
                    enterResumeHitCount := 0
                }
            } else {
                enterResumeHitCount := 0
            }
        } else {
            if (CheckPauseByEnter(allcoords, pixelCache)) {
                enterPauseMissCount++
                enterResumeHitCount := 0
                if (enterPauseMissCount >= TAB_PAUSE) {
                    TogglePause("enter", true)
                    enterPauseMissCount := 0
                }
            } else {
                enterPauseMissCount := 0
            }
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

        loop 2 {
            try {
                color := GetPixelRGB(coord.x, coord.y, false)
                if (ColorDetector.IsGreen(color))
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
            if (!ColorDetector.IsGray(color))  ; 如果不是灰色，认为资源充足
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
    static maxCacheEntries := 100
    
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
            pixelCache := Map()
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
 * 颜色判断类
 * @param {Integer} r - 红色分量 (0-255)
 * @param {Integer} g - 绿色分量 (0-255) 
 * @param {Integer} b - 蓝色分量 (0-255)
 */
class ColorDetector {
    ; 蓝色检测
    static IsBlue(color) {
        return (color.b > 60 &&
                color.b > color.r * 1.2 && 
                color.b > color.g * 1.2 &&
                color.b - Max(color.r, color.g) > 30)
    }
    ; 红色检测
    static IsRed(color) {
        return (color.r > 60 &&
                color.r > color.g * 1.2 &&
                color.r > color.b * 3 &&
                color.r - Max(color.g, color.b) > 40)
    }
    ; 绿色检测
    static IsGreen(color) {
        return (color.g > 70 &&
                color.g > color.r * 1.3 && 
                color.g > color.b * 3 &&
                color.g - Max(color.r, color.b) > 40)
    }
    ; 灰色检测
    static IsGray(color) {
        range := Max(color.r, color.g, color.b) - Min(color.r, color.g, color.b)
        avgColor := (color.r + color.g + color.b) / 3
        return (range < 35 &&
                avgColor > 10 && 
                avgColor < 80)
    }
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

/**
 * 配置管理类
 * @param {String} profileName - 配置方案名称，可选 <默认|自定义>
 * @returns {Object} - 包含技能设置、鼠标设置、功能键设置、启动热键、运行模式的对象
 * @returns {IniWrite/IniRead} - <编号>=<按键值,状态,间隔,模式>
 */
class ConfigManager {
    static settingsFile := A_ScriptDir "\settings.ini"
    static defaultProfile := "默认"
    
    /**
     * 写入
     */
    static Write(section, key, value) {
        try {
            IniWrite(String(value), this.settingsFile, section, key)
            return true
        } catch {
            return false
        }
    }
    
    /**
     * 读取
     */
    static Read(section, key, defaultValue := "") {
        try {
            return IniRead(this.settingsFile, section, key, String(defaultValue))
        } catch {
            return String(defaultValue)
        }
    }
    
    /**
     * 删除
     */
    static DeleteSection(section) {
        try {
            IniDelete(this.settingsFile, section)
            return true
        } catch {
            return false
        }
    }
    
    /**
     * 保存
     */
    static SaveProfile(profileName) {
        global cSkill, mSkill, uCtrl, startkey, RunMod
        
        try {
            ; 删除
            this.DeleteSection(profileName)
            
            section := profileName
            
            ; 保存技能设置
            for i in [1, 2, 3, 4, 5] {
                skillData := cSkill[i]["key"].Value . "," . 
                            cSkill[i]["enable"].Value . "," . 
                            cSkill[i]["interval"].Value . "," . 
                            cSkill[i]["mode"].Value
                IniWrite(skillData, this.settingsFile, section, "skill" i)
            }
            
            ; 保存鼠标设置
            leftData := mSkill["left"]["enable"].Value . "," . 
                        mSkill["left"]["interval"].Value . "," . 
                        mSkill["left"]["mode"].Value
            IniWrite(leftData, this.settingsFile, section, "left")
            
            rightData := mSkill["right"]["enable"].Value . "," . 
                         mSkill["right"]["interval"].Value . "," . 
                         mSkill["right"]["mode"].Value
            IniWrite(rightData, this.settingsFile, section, "right")
            
            ; 保存功能键设置
            dodgeData := uCtrl["dodge"]["key"].Value . "," . 
                         uCtrl["dodge"]["enable"].Value . "," . 
                         uCtrl["dodge"]["interval"].Value
            IniWrite(dodgeData, this.settingsFile, section, "dodge")

            potionData := uCtrl["potion"]["key"].Value . "," . 
                          uCtrl["potion"]["enable"].Value . "," . 
                          uCtrl["potion"]["interval"].Value
            IniWrite(potionData, this.settingsFile, section, "potion")

            forceMoveData := uCtrl["forceMove"]["key"].Value . "," . 
                             uCtrl["forceMove"]["enable"].Value . "," . 
                             uCtrl["forceMove"]["interval"].Value
            IniWrite(forceMoveData, this.settingsFile, section, "forceMove")

            ipPauseData := uCtrl["ipPause"]["enable"].Value . "," . 
                           uCtrl["ipPause"]["interval"].Value
            IniWrite(ipPauseData, this.settingsFile, section, "ipPause")

            tabPauseData := uCtrl["tabPause"]["enable"].Value . "," . 
                            uCtrl["tabPause"]["interval"].Value
            IniWrite(tabPauseData, this.settingsFile, section, "tabPause")

            dcPauseData := uCtrl["dcPause"]["enable"].Value . "," . 
                           uCtrl["dcPause"]["interval"].Value
            IniWrite(dcPauseData, this.settingsFile, section, "dcPause")

            mouseAutoMoveData := uCtrl["mouseAutoMove"]["enable"].Value . "," . 
                                 uCtrl["mouseAutoMove"]["interval"].Value
            IniWrite(mouseAutoMoveData, this.settingsFile, section, "mouseAutoMove")
            RandomData := uCtrl["random"]["enable"].Value . "," . 
                          uCtrl["random"]["max"].Value
            IniWrite(RandomData, this.settingsFile, section, "random")

            IniWrite(RunMod.Value, this.settingsFile, section, "runMode")
            IniWrite(uCtrl["shift"]["enable"].Value, this.settingsFile, section, "shift")
            IniWrite(uCtrl["D4only"]["enable"].Value, this.settingsFile, section, "D4only")
            IniWrite(uCtrl["xy"]["x"].Value, this.settingsFile, section, "xyX")
            IniWrite(uCtrl["xy"]["y"].Value, this.settingsFile, section, "xyY")
            ; 保存热键设置
            IniWrite(startkey["mode"].Value, this.settingsFile, section, "hotkeyMode")
            IniWrite(startkey["userkey"][1].key, this.settingsFile, section, "useHotKey")
            
            return true
            
        } catch {
            return false
        }
    }
    
    /**
     * 加载
     */
    static LoadProfile(profileName) {
        global cSkill, mSkill, uCtrl, startkey, RunMod

        try {
            ; 加载
            section := profileName

            for Index in [1, 2, 3, 4, 5]  {
                skillData := IniRead(this.settingsFile, section, "skill" Index, Index . ",1,20,1")
                parts := StrSplit(skillData, ",")
                
                if (parts.Length >= 4) {
                    cSkill[Index]["key"].Value := parts[1]
                    cSkill[Index]["enable"].Value := Integer(parts[2])
                    cSkill[Index]["interval"].Value := Integer(parts[3])
                    cSkill[Index]["mode"].Value := Integer(parts[4])
                }
            }

            leftData := IniRead(this.settingsFile, section, "left", "0,80,1")
            leftParts := StrSplit(leftData, ",")
            if (leftParts.Length >= 3) {
                mSkill["left"]["enable"].Value := Integer(leftParts[1])
                mSkill["left"]["interval"].Value := Integer(leftParts[2])
                mSkill["left"]["mode"].Value := Integer(leftParts[3])
            }
            
            rightData := IniRead(this.settingsFile, section, "right", "1,300,1")
            rightParts := StrSplit(rightData, ",")
            if (rightParts.Length >= 3) {
                mSkill["right"]["enable"].Value := Integer(rightParts[1])
                mSkill["right"]["interval"].Value := Integer(rightParts[2])
                mSkill["right"]["mode"].Value := Integer(rightParts[3])
            }

            
            dodgeData := IniRead(this.settingsFile, section, "dodge", "Space,0,20")
            dodgeParts := StrSplit(dodgeData, ",")
            if (dodgeParts.Length >= 3) {
                uCtrl["dodge"]["key"].Value := dodgeParts[1]
                uCtrl["dodge"]["enable"].Value := Integer(dodgeParts[2])
                uCtrl["dodge"]["interval"].Value := Integer(dodgeParts[3])
            }

            potionData := IniRead(this.settingsFile, section, "potion", "q,0,3000")
            potionParts := StrSplit(potionData, ",")
            if (potionParts.Length >= 3) {
                uCtrl["potion"]["key"].Value := potionParts[1]
                uCtrl["potion"]["enable"].Value := Integer(potionParts[2])
                uCtrl["potion"]["interval"].Value := Integer(potionParts[3])
            }

            forceMoveData := IniRead(this.settingsFile, section, "forceMove", "e,0,50")
            forceMoveParts := StrSplit(forceMoveData, ",")
            if (forceMoveParts.Length >= 3) {
                uCtrl["forceMove"]["key"].Value := forceMoveParts[1]
                uCtrl["forceMove"]["enable"].Value := Integer(forceMoveParts[2])
                uCtrl["forceMove"]["interval"].Value := Integer(forceMoveParts[3])
            }

            ipPauseData := IniRead(this.settingsFile, section, "ipPause", "0,50")
            ipPauseParts := StrSplit(ipPauseData, ",")
            if (ipPauseParts.Length >= 2) {
                uCtrl["ipPause"]["enable"].Value := Integer(ipPauseParts[1])
                uCtrl["ipPause"]["interval"].Value := Integer(ipPauseParts[2])
            }

            tabPauseData := IniRead(this.settingsFile, section, "tabPause", "0,100")
            tabPauseParts := StrSplit(tabPauseData, ",")
            if (tabPauseParts.Length >= 2) {
                uCtrl["tabPause"]["enable"].Value := Integer(tabPauseParts[1])
                uCtrl["tabPause"]["interval"].Value := Integer(tabPauseParts[2])
            }

            dcPauseData := IniRead(this.settingsFile, section, "dcPause", "1,2")
            dcPauseParts := StrSplit(dcPauseData, ",")
            if (dcPauseParts.Length >= 2) {
                uCtrl["dcPause"]["enable"].Value := Integer(dcPauseParts[1])
                uCtrl["dcPause"]["interval"].Value := Integer(dcPauseParts[2])
            }

            mouseAutoMoveData := IniRead(this.settingsFile, section, "mouseAutoMove", "0,1000")
            mouseAutoMoveParts := StrSplit(mouseAutoMoveData, ",")
            if (mouseAutoMoveParts.Length >= 2) {
                uCtrl["mouseAutoMove"]["enable"].Value := Integer(mouseAutoMoveParts[1])
                uCtrl["mouseAutoMove"]["interval"].Value := Integer(mouseAutoMoveParts[2])
            }

            RandomData := IniRead(this.settingsFile, section, "random", "0,10")
            RandomParts := StrSplit(RandomData, ",")
            if (RandomParts.Length >= 2) {
                uCtrl["random"]["enable"].Value := Integer(RandomParts[1])
                uCtrl["random"]["max"].Value := Integer(RandomParts[2])
            }
  
            RunMod.Value := IniRead(this.settingsFile, section, "runMode", "1")
            uCtrl["shift"]["enable"].Value := IniRead(this.settingsFile, section, "shift", "0")
            uCtrl["D4only"]["enable"].Value := IniRead(this.settingsFile, section, "D4only", "1")
            uCtrl["xy"]["x"].Value := IniRead(this.settingsFile, section, "xyX", "0")
            uCtrl["xy"]["y"].Value := IniRead(this.settingsFile, section, "xyY", "0")
            ; 加载全局热键
            startkey["mode"].Value := IniRead(this.settingsFile, section, "hotkeyMode", "1")
            startkey["userkey"][1].key := IniRead(this.settingsFile, section, "useHotKey", "F1")
            startkey["guiHotkey"].Value := startkey["userkey"][1].key
            LoadStartHotkey(startkey)

            return true
            
        } catch {
            return false
        }
    }
    
    /**
     * 配置列表管理
     */
    static GetProfileList() {
        profilesString := this.Read("Profiles", "List", this.defaultProfile)
        profileList := StrSplit(profilesString, "|")
        
        found := false
        for profile in profileList {
            if (profile = this.defaultProfile) {
                found := true
                break
            }
        
        }

        if (!found) {
            profileList.InsertAt(1, this.defaultProfile)
            this.Write("Profiles", "List", Join(profileList, "|"))
        }
        return profileList
    }
    
    static SaveProfileList(profileList) {
        return this.Write("Profiles", "List", Join(profileList, "|"))
    }
    
    static GetLastUsedProfile() {
        return this.Read("Global", "LastUsedProfile", this.defaultProfile)
    }
    
    static SetLastUsedProfile(profileName) {
        return this.Write("Global", "LastUsedProfile", profileName)
    }
    
    static DeleteProfile(profileName) {
        if (profileName = this.defaultProfile)
            return false
            
        try {
            profileList := this.GetProfileList()
            for i, name in profileList {
                if (name = profileName) {
                    profileList.RemoveAt(i)
                    break
                }
            }

            this.SaveProfileList(profileList)
            this.DeleteSection(profileName)
            return true
        } catch {
            return false
        }
    }
    
    static ProfileExists(profileName) {
        profileList := this.GetProfileList()
        for profile in profileList {
            if (profile = profileName)
                return true
        }
        return false
    }
    
    /**
     * 确保配置文件存在
     */
    static EnsureConfigFile() {
        if (!FileExist(this.settingsFile)) {
            try {
                defaultContent := "[Profiles]`nList=" this.defaultProfile "`n`n[Global]`nLastUsedProfile=" this.defaultProfile "`n`n"
                FileAppend(defaultContent, this.settingsFile)
                return true
            } catch {
                return false
            }
        }
        return true
    }
    
    /**
     * 更新
     */
    static UpdateDropDown(ctrl, selectProfile := "") {
        try {
            profileList := this.GetProfileList()
            currentText := selectProfile != "" ? selectProfile : ctrl.Text
            
            ctrl.Delete()
            for i, name in profileList {
                ctrl.Add([name])
            }

            if (currentText != "") {
                ctrl.Text := currentText
                for i, name in profileList {
                    if (name = currentText) {
                        ctrl.Value := i
                        break
                    }
                }
            }
            
            if (ctrl.Text = "" && profileList.Length > 0) {
                ctrl.Text := profileList[1]
                ctrl.Value := 1
            }
            
            return true
        } catch {
            return false
        }
    }
    
    /**
     * 保存
     */
    static SaveProfileFromUI() {
        global profileName

        profileNameInput := Trim(profileName.Text)
        if (this.SaveProfile(profileNameInput)) {
            if (!this.ProfileExists(profileNameInput)) {
                profileList := this.GetProfileList()
                profileList.Push(profileNameInput)
                this.SaveProfileList(profileList)
            }

            this.UpdateDropDown(profileName, profileNameInput)
            this.SetLastUsedProfile(profileNameInput)
            
            statusBar.Text := "配置方案「" profileNameInput "」已保存"
        } else {
            statusBar.Text := "保存配置失败"
        }
    }
    
    /**
     * 加载
     */
    static LoadSelectedProfile(ctrl, *) {
        
        if (Type(ctrl) = "String") {
            selectedProfile := ctrl
        } else {
            selectedProfile := Trim(ctrl.Text)
        }
        if (selectedProfile = "") {
            return
        }
        if (!this.ProfileExists(selectedProfile)) {
            return
        }
        if (this.LoadProfile(selectedProfile)) {
            this.SetLastUsedProfile(selectedProfile)
            statusBar.Text := "配置已加载: " selectedProfile
        } else {
            statusBar.Text := "加载配置失败"
        }
    }
    
    /**
     * 删除
     */
    static DeleteProfileFromUI() {
        global profileName
        
        profileList := this.GetProfileList()
        currentProfileName := profileList[profileName.Value]
        if (currentProfileName = this.defaultProfile) {
            this.DeleteSection(this.defaultProfile)
            this.LoadSelectedProfile(this.defaultProfile)
            statusBar.Text := "默认配置以重置"
            return
        }

        if (this.DeleteProfile(currentProfileName)) {
            this.UpdateDropDown(profileName, this.defaultProfile)
            this.LoadSelectedProfile(this.defaultProfile)
            statusBar.Text := "配置方案已删除，已加载默认配置"
        } else {
            statusBar.Text := "删除配置失败"
        }
    }
    
    /**
     * 初始化
     */
    static Initialize() {
        global profileName
        if (!this.EnsureConfigFile()) {
            statusBar.Text := "配置文件初始化失败"
            return
        }

        lastProfile := this.GetLastUsedProfile()
        this.UpdateDropDown(profileName, lastProfile)

        this.LoadSelectedProfile(lastProfile)
        statusBar.Text := "配置已加载: " lastProfile
    }
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
        result .= (i > 1 ? delimiter : "") . v
    }
    return result
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