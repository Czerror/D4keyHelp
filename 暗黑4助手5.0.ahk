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
)

global currentHotkey := "F1"       ; 当前热键
global hotkeyControl := ""         ; 热键控件
; GUI相关变量
global myGui := ""                 ; 主GUI对象
global statusText := ""            ; 状态文本控件
global statusBar := ""             ; 状态栏控件
global currentProfileName := "默认" ; 当前配置名称
global profileList := []           ; 配置列表

; 控件映射
global cSkill := Map()      ; 技能控件映射
global bSkill := Map()      ; 技能BUFF控件映射
global mSkill := Map()      ; 鼠标控件
global uCtrl := Map()       ; 功能键控件

; 技能模式常量
global skillMod := ["连点", "BUFF", "按住", "资源"]
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

;|===============================================================|
;| 函数: InitializeGUI
;| 功能: 初始化主程序GUI界面
;|===============================================================|
InitializeGUI() {
    global myGui, statusBar

    ;# ==================== GUI基础设置 ==================== #
    myGui := Gui("", "暗黑4助手 v5.0.1")
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
    global myGui, statusText, hotkeyControl, currentProfileName, RunMod
    global profileDropDown, profileNameInput

    ;# ==================== 主控制区域 ==================== #
    myGui.AddGroupBox("x10 y10 w280 h120", "运行模式: ")
    statusText := myGui.AddText("x30 y35 w140 h20", "状态: 未运行")  ; 状态指示器
    myGui.AddButton("x30 y65 w80 h30", "开始/停止").OnEvent("Click", ToggleMacro)
    hotkeyControl := myGui.AddHotkey("x120 y70 w80 h20", currentHotkey)
    hotkeyControl.OnEvent("Change", (ctrl, *) => LoadGlobalHotkey())
    myGui.AddText("x30 y100 w240 h20", "提示：仅在暗黑破坏神4窗口活动时生效")

    ;# ==================== 运行模式选择 ==================== #
    RunMod := myGui.AddDropDownList("x90 y8 w65 h60 Choose1", ["多线程", "单线程"])
    RunMod.OnEvent("Change", (*) => (
        ; 模式切换时重启定时器（如果正在运行）
        (isRunning && (StopAllTimers(), StartAllTimers())
        ),
        UpdateStatus("", "宏已切换模式")
    ))

    ;# ==================== 配置管理区域 ==================== #
    myGui.AddGroupBox("x300 y10 w170 h120", "配置方案")
    profileDropDown := myGui.AddDropDownList("x320 y35 w60 h120 Choose1", ["默认"])
    profileDropDown.OnEvent("Change", LoadSelectedProfile)
    profileNameInput := myGui.AddEdit("x390 y35 w50 h20", currentProfileName)
    myGui.AddButton("x320 y75 w40 h25", "保存").OnEvent("Click", SaveProfile)
    myGui.AddButton("x370 y75 w40 h25", "删除").OnEvent("Click", DeleteProfile)

    ;# ==================== 按键设置主区域 ==================== #
    myGui.AddGroupBox("x10 y210 w460 h370", "按键设置")

    ;|----------------------- 自动启停 -----------------------|
    myGui.AddGroupBox("x10 y130 w460 h80", "启停管理")
    myGui.AddText("x30 y185 w50 h20", "灵敏度:")
    myGui.AddButton("x380 y145 w80 h25", "刷新检测").OnEvent("Click", RefreshDetection)
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
        uCtrl["ranDom"]["max"].Value := Max(1, uCtrl["ranDom"]["max"].Value)))

    ;|---------------------- 血条检测 ------------------------|
    uCtrl["ipPause"] := Map(
        "text", myGui.AddText("x30 y155 w60 h20", "血条检测:"),
        "stopText", myGui.AddText("x80 y185 w15 h20", "停"),
        "startText", myGui.AddText("x120 y185 w15 h20", "启"),
        "enable", myGui.AddCheckbox("x90 y155 w20 h20"),
        "interval", myGui.AddEdit("x115 y155 w40 h20", "50"),
        "pauseConfirm", myGui.AddEdit("x95 y183 w20 h20", "5"),
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
        "pauseConfirm", myGui.AddEdit("x265 y180 w20 h20", "2"),
        "resumeConfirm", myGui.AddEdit("x305 y180 w20 h20", "2")
    )
    ; 输入验证
    uCtrl["tabPause"]["interval"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["interval"], 10, 1000)))
    uCtrl["tabPause"]["pauseConfirm"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["pauseConfirm"], 1, 9)))
    uCtrl["tabPause"]["resumeConfirm"].OnEvent("LoseFocus", (*) => (
        LimitEditValue(uCtrl["tabPause"]["resumeConfirm"], 1, 9)))

    uCtrl["dcPause"] := Map(
        "text", myGui.AddText("x380 y180 w60 h20", "双击暂停:"),
        "enable", myGui.AddCheckbox("x440 y180 w20 h20")
    )

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
ToggleMacro(*) {
    global isRunning, isPaused

    ; 确保完全停止所有定时器
    StopAllTimers()
    ManageTimers("none", false)

    ; 切换运行状态
    isRunning := !isRunning

    if isRunning {
        ; 初始化暂停状态
        for key, _ in isPaused {
            isPaused[key] := false
        }

        ; 启动监控定时器
        ManageTimers("all", true)

        if WinActive("ahk_class Diablo IV Main Window Class") {
            StartAllTimers()
            UpdateStatus("运行中", "宏已启动")
        } else {
            isPaused["window"] := true
            UpdateStatus("已暂停(窗口切换)", "宏已暂停 - 窗口未激活")
        }
    } else {
        ; 停止所有定时器
        StopAllTimers()
        ManageTimers("none", false)

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
    global holdStates, uCtrl

    ; 释放所有跟踪的按键
    for uniqueKey, _ in holdStates {
        try {
            ; 解析 uniqueKey 得到实际按键
            arr := StrSplit(uniqueKey, ":")
            if (arr.Length < 2)
                continue

            type := arr[1]
            fullKey := arr[2]

            ; 移除前缀
            if (type = "mouse") {
                btn := SubStr(fullKey, 7)  ; 移除"mouse_"前缀
                Click("up " btn)
            }
            else if (type = "key") {
                key := SubStr(fullKey, 5)   ; 移除"key_"前缀
                Send("{" key " up}")
            }
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
        res := GetWindowInfo()
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
    GetDynamicbSkill()

    if (RunMod.Value = 1) {
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
    } else if (RunMod.Value = 2) {
        keyQueue := []
        keyQueueLastExec := Map()
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

        SetTimer(KeyQueueWorker, 5)
    }
    StartAutoMove()
}

/**
 * 停止所有定时器
 */
StopAllTimers() {
    global skillTimers, RunMod, keyQueue, keyQueueLastExec, bSkill

    ; 停止所有技能定时器
    for timerName, boundFunc in skillTimers.Clone() {
        SetTimer(boundFunc, 0)
        skillTimers.Delete(timerName)
    }

    ; 处理单线程模式的队列定时器
    if (RunMod && RunMod.Value = 2) {
        SetTimer(KeyQueueWorker, 0)
        keyQueue := []
        keyQueueLastExec := Map()
    }

    ; 一次性清空映射
    skillTimers := Map()
    bSkill := Map()

    ; 停止可能的自动移动定时器
    SetTimer(MoveMouseToNextPoint, 0)

    ; 释放所有按键
    ReleaseAllKeys()
}
/**
 * 管理全局定时器
 * @param {String} timerType - 定时器类型
 * @param {Boolean} enable - 是否启用定时器
 * @param {Integer} interval - 定时器间隔(毫秒)
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
 * 立即刷新所有检测
 * 清理缓存，立即执行检测，支持强制恢复运行
 * @param {*} - 事件参数（来自按钮点击事件）
 */
RefreshDetection(*) {
    global isRunning, statusBar, uCtrl, isPaused

    if (!isRunning) {
        statusBar.Text := "宏未运行，无需刷新检测"
        return
    }

    ; 停止然后重启所有定时器
    ManageTimers("none", false)

    ; 验证并获取间隔设置
    bloodInterval := Integer(uCtrl["ipPause"]["interval"].Value)
    tabInterval := Integer(uCtrl["tabPause"]["interval"].Value)

    ; 清理像素缓存 - 强制触发GetPixelRGB的缓存清理
    CleanPixelCache()

    ; 直接重置所有暂停状态
    for key, _ in isPaused {
        isPaused[key] := false
    }
    UpdateStatus("运行中", "已强制恢复运行")

    ; 立即执行一次检测
    try {
        CheckWindow()

        ; 仅当相应检测启用时执行
        if (uCtrl["ipPause"]["enable"].Value)
            AutoPauseByBlood()

        if (uCtrl["tabPause"]["enable"].Value)
            AutoPauseByTAB()
    } catch {
        ; 忽略任何错误
    }

    ; 重新启动定时器
    ManageTimers("window", true, 100)
    ManageTimers("blood", true, bloodInterval)
    ManageTimers("tab", true, tabInterval)

    ; 获取更新后的状态
    paused := IsAnyPaused()
    statusBar.Text := "已刷新所有检测定时器" (paused ? " (宏仍在暂停状态)" : "")
}

/**
 * 强制清理像素缓存的辅助函数
 */
CleanPixelCache() {
    static lastCacheClear := 0
    static pixelCache := Map()

    ; 直接重置缓存Map和清理时间
    pixelCache := Map()
    lastCacheClear := A_TickCount
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
 * @param {String} type - - 输入类型 ("key"|"mouse"|"uSkill")
 * @param {String} mouseBtn - 鼠标按钮名（"left"/"right"）
 */
HandleKeyMode(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "") {
    global uCtrl, holdStates
    static lastReholdTime := Map()
    static REHOLD_MIN_INTERVAL := 2000

    ; 缓存 A_TickCount
    currentTime := A_TickCount

    ; 改进的唯一键生成
    uniqueKey := type ":" (type = "mouse" ? "mouse_" mouseBtn : "key_" keyOrBtn)

    ; 快速返回检查
    if (IsAnyPaused())
        return

    isMouse := (type = "mouse")

    shiftEnabled := uCtrl["shift"]["enable"].Value

    ; 模式处理
    switch mode {
        case 2: ; BUFF模式
            if (pos && IsSkillActive(pos.x, pos.y))
                return

            if (isMouse) {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Click(mouseBtn)
                    Send "{Blind} {Shift up}"
                } else {
                    Click(mouseBtn)
                }
            } else {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Send "{" keyOrBtn "}"
                    Send "{Blind} {Shift up}"
                } else {
                    Send "{" keyOrBtn "}"
                }
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
                for key in lastReholdTime.Clone() {
                    if (!holdStates.Has(key))
                        lastReholdTime.Delete(key)
                }
            }

            if (needPress) {
                if (isMouse) {
                    if (isHeld) {
                        if (shiftEnabled)
                            Send "{Blind}{Shift up}"
                        Click("up " mouseBtn)
                        Sleep 10
                    }
                    ; 重新按下
                    if (shiftEnabled)
                        Send "{Blind}{Shift down}"
                    Click("down " mouseBtn)
                } else {
                    if (isHeld) {
                        if (shiftEnabled)
                            Send "{Blind}{Shift up}"
                        Send("{" keyOrBtn " up}")
                        Sleep 10
                    }
                    ; 重新按下
                    if (shiftEnabled)
                        Send "{Blind}{Shift down}"
                    Send("{" keyOrBtn " down}")
                }
            }

        case 4: ; 资源模式
            if (IsResourceSufficient()) {
                if (isMouse) {
                    if (shiftEnabled) {
                        Send "{Blind} {Shift down}"
                        Click(mouseBtn)
                        Send "{Blind} {Shift up}"
                    } else {
                        Click(mouseBtn)
                    }
                } else {
                    if (shiftEnabled) {
                        Send "{Blind} {Shift down}"
                        Send "{" keyOrBtn "}"
                        Send "{Blind} {Shift up}"
                    } else {
                        Send "{" keyOrBtn "}"
                    }
                }
            }

        default: ; 连点模式
            if (isMouse) {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Click(mouseBtn)
                    Send "{Blind} {Shift up}"
                } else {
                    Click(mouseBtn)
                }
            } else {
                if (shiftEnabled) {
                    Send "{Blind} {Shift down}"
                    Send "{" keyOrBtn "}"
                    Send "{Blind} {Shift up}"
                } else {
                    Send "{" keyOrBtn "}"
                }
            }
    }
}

; ==================== 队列模式实现 ====================
/**
 * 键位入队函数
 */
EnqueueKey(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "", interval := 1000) {
    global keyQueue
    static maxLen := 20

    ; 快速生成唯一ID
    uniqueId := type ":" (type = "mouse" ? mouseBtn : keyOrBtn)
    priority := GetPriorityFromMode(mode)
    now := A_TickCount

    ; 快速查找现有项
    existingIndex := 0
    loop keyQueue.Length {
        if (keyQueue[A_Index].type ":"
            (keyQueue[A_Index].type = "mouse" ? keyQueue[A_Index].mouseBtn : keyQueue[A_Index].keyOrBtn) = uniqueId) {
            existingIndex := A_Index
            break
        }
    }

    ; 创建新项
    item := {
        keyOrBtn: keyOrBtn,
        mode: mode,
        pos: pos,
        type: type,
        mouseBtn: mouseBtn,
        time: now,
        interval: interval,
        priority: priority
    }

    ; 移除现有项
    if (existingIndex > 0)
        keyQueue.RemoveAt(existingIndex)

    ; 队列满处理
    if (keyQueue.Length >= maxLen) {
        lowestPriority := priority
        lowestIndex := 0

        ; 单次遍历查找最低优先级项
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

    ; 快速插入处理
    if (keyQueue.Length == 0) {
        keyQueue.Push(item)
        return
    }

    ; 优化二分查找
    left := 1
    right := keyQueue.Length

    ; 边界检查
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

    ; 核心二分逻辑
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

; 优先级计算函数
GetPriorityFromMode(mode) {
    switch mode {
        case 4: return 4
        case 2: return 3
        case 3: return 2
        case 1: return 1
        default: return 0
    }
}

/**
 * 队列处理器
 * @description 处理队列中的按键事件
 */
KeyQueueWorker() {
    global keyQueue, keyQueueLastExec

    ; 快速初始化检查
    if !IsObject(keyQueue)
        keyQueue := []
    if !IsObject(keyQueueLastExec)
        keyQueueLastExec := Map()

    static critSection := 0
    now := A_TickCount
    pendingItems := []
    remainingItems := []

    ; 轻量级临界区 (无超时设置)
    if (critSection)
        return
    critSection := 1

    ; 快速队列处理
    loop keyQueue.Length {
        item := keyQueue[A_Index]
        uniqueId := item.type ":" (item.type = "mouse" ? item.mouseBtn : item.keyOrBtn)
        lastExec := keyQueueLastExec.Get(uniqueId, 0)

        ; 优化时间差计算
        if ((now - lastExec) >= item.interval) {
            HandleKeyMode(item.keyOrBtn, item.mode, item.pos, item.type, item.mouseBtn)
            keyQueueLastExec[uniqueId] := now
            pendingItems.Push(item)
        } else {
            remainingItems.Push(item)
        }
    }

    ; 原子化队列更新
    keyQueue := remainingItems
    critSection := 0

    ; 高效重新入队
    for item in pendingItems {
        EnqueueKey(
            item.keyOrBtn,
            item.mode,
            item.pos,
            item.type,
            item.mouseBtn,
            item.interval
        )
    }
}

; ==================== 按键回调函数 ====================
/**
 * 通用按键回调函数
 * @param {String} category - 按键类别 ("skill"|"mouse"|"uSkill")
 * @param {String|Integer} identifier - 按键标识符 (技能索引|鼠标按钮名|功能键ID)
 */
PressKeyCallback(category, identifier) {
    global cSkill, mSkill, uCtrl, skillTimers, RunMod, bSkill

    timerKey := category . identifier

    if (skillTimers.Has(timerKey)) {
        SetTimer(skillTimers[timerKey], 0)
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

    key := (category = "mouse") ? identifier : config["key"].Value
    mode := config.Has("mode") ? config["mode"].Value : 1
    pos := bSkill.Has(identifier) ? bSkill[identifier] : ""
    interval := Integer(config["interval"].Value)

    if (uCtrl["ranDom"]["enable"].Value == 1) {
        interval += Random(1, uCtrl["ranDom"]["max"].Value)
    }

    if (RunMod.Value == 1) {
        boundFunc := (category = "mouse")
            ? HandleKeyMode.Bind(key, mode, pos, "mouse", identifier)
            : HandleKeyMode.Bind(key, mode, pos, "key", "")
        skillTimers[timerKey] := boundFunc
        SetTimer(boundFunc, interval)
    } else if (RunMod.Value = 2) {
        if (category = "mouse")
            EnqueueKey(key, mode, pos, "mouse", identifier, interval)
        else
            EnqueueKey(key, mode, pos, "key", "", interval)
    }
}

/**
 * 鼠标自动移动函数
 */
MoveMouseToNextPoint() {
    global isRunning, uCtrl

    ; 检查各种条件
    if (!isRunning || IsAnyPaused() || !uCtrl["mouseAutoMove"]["enable"].Value)
        return

    try {
        ; 获取分辨率和缩放比例
        res := GetWindowInfo()

        ; 计算六个点的位置
        points := [
        { x: Round(0.15 * res["D4W"]), y: Round(0.15 * res["D4H"]) },  ; 左上角
        { x: Round(0.5 * res["D4W"]), y: Round(0.15 * res["D4H"]) },   ; 中上角
        { x: Round(0.85 * res["D4W"]), y: Round(0.15 * res["D4H"]) },  ; 右上角
        { x: Round(0.85 * res["D4W"]), y: Round(0.85 * res["D4H"]) },  ; 右下角
        { x: Round(0.5 * res["D4W"]), y: Round(0.85 * res["D4H"]) },   ; 中下角
        { x: Round(0.15 * res["D4W"]), y: Round(0.85 * res["D4H"]) }   ; 左下角
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
            ; 获取实际客户区尺寸
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
 * 动态计算技能位置
 * 基于窗口分辨率和缩放比例
 */
GetDynamicbSkill() {
    global bSkill
    res := GetWindowInfo()

    bSkill.Clear()
    loop 6 {
        idx := A_Index
        bSkill[idx] := {
            x: Round(res["CD4W"] + (1550 - res["D44KWC"] + 127 * (idx - 1)) * res["D4SW"]),
            y: Round(res["CD4H"] + (1940 - res["D44KHC"]) * res["D4SH"])
        }
    }
    bSkill["left"] := bSkill[5]
    bSkill["right"] := bSkill[6]
}

; ==================== 像素检测与暂停机制 ====================
/**
 * 专用的自动暂停函数
 * 只返回必要的检测结果
 * 支持像素缓存，避免重复采样
 */
CheckKeyPoints(res, pixelCache := unset) {
    try {
        dfx := Round(res["CD4W"] + (1535 - res["D44KWC"]) * res["D4SW"])
        dty := Round(res["CD4H"] + (1880 - res["D44KHC"]) * res["D4SH"])
        tabx := Round(res["CD4W"] + (3795 - res["D44KWC"]) * res["D4SW"])
        taby := Round(res["CD4H"] + (90 - res["D44KHC"]) * res["D4SH"])

        colorDFX := (IsSet(pixelCache) && pixelCache.Has("dfx")) ? pixelCache["dfx"] : GetPixelRGB(dfx, dty)
        colorTAB := (IsSet(pixelCache) && pixelCache.Has("tab")) ? pixelCache["tab"] : GetPixelRGB(tabx, taby)

        dfxHSV := RGBToHSV(colorDFX.r, colorDFX.g, colorDFX.b)
        tabHSV := RGBToHSV(colorTAB.r, colorTAB.g, colorTAB.b)

        ; 蓝色检测
        isBlueDFX := (dfxHSV.h >= 180 && dfxHSV.h <= 270 && dfxHSV.s > 0.3 && dfxHSV.v > 0.2)

        ; 红色检测
        isRedTAB := ((tabHSV.h <= 30 || tabHSV.h >= 330) && tabHSV.s > 0.7 && tabHSV.v > 0.3)

        return {
            dfxcolor: colorDFX,
            tabcolor: colorTAB,
            isBlueColor: isBlueDFX,
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
CheckPauseByEnter(res := unset, pixelCache := unset) {
    if !IsSet(res)
        res := GetWindowInfo()

    ; 直接计算最终坐标
    grayColor := (IsSet(pixelCache) && pixelCache.Has("enterGray"))
        ? pixelCache["enterGray"]
        : GetPixelRGB(
            Round(res["CD4W"] + (150 - res["D44KWC"]) * res["D4SW"]),
            Round(res["CD4H"] + (2070 - res["D44KHC"]) * res["D4SH"])
        )

    loop 6 {
        x := Round(res["CD4W"] + (50 - res["D44KWC"] + 90 * (A_Index - 1)) * res["D4SW"])
        colorObj := (IsSet(pixelCache) && pixelCache.Has("enter" A_Index))
            ? pixelCache["enter" A_Index]
            : GetPixelRGB(x, Round(res["CD4H"] + (1440 - res["D44KHC"]) * res["D4SH"]))

        hsv := RGBToHSV(colorObj.r, colorObj.g, colorObj.b)

        isRedHue := (hsv.h <= 30 || hsv.h >= 330)  ; 红色色相范围
        isSaturated := (hsv.s > 0.7)               ; 饱和度
        isBright := (hsv.v > 0.35)                 ; 亮度

        if (isRedHue && isSaturated && isBright) {

            grayHsv := RGBToHSV(grayColor.r, grayColor.g, grayColor.b)

            isGrayBackground := (grayHsv.s < 0.3 && grayHsv.v < 0.3)

            return isGrayBackground
        }
    }
    return false
}

/**
 * 血条检测函数
 * @param res {Map} 窗口分辨率信息(可选)
 * @returns {Boolean} 是否检测到血条
 */
CheckPauseByBlood(res := unset, pixelCache := unset) {
    if !IsSet(res)
        res := GetWindowInfo()
    
    ; 定义血条检测坐标（怪物和Boss血条位置）
    bloodCoords := [
        {x: 1605, y: 85},   ; 怪物血条上边缘
        {x: 1605, y: 95},   ; 怪物血条下边缘
        {x: 1435, y: 85},   ; Boss血条上边缘
        {x: 1435, y: 95}    ; Boss血条下边缘
    ]

    try {
        ; 一次性获取所有血条坐标的颜色
        ; 检测血条红色像素
        hitCount := 0
        bloodColors := []
        for i, coord in bloodCoords {
            x := Round(res["CD4W"] + (coord.x - res["D44KWC"]) * res["D4SW"])
            y := Round(res["CD4H"] + (coord.y - res["D44KHC"]) * res["D4SH"])
            key := x . "," . y  ; 使用坐标组合作为缓存键
            bloodColors := (IsSet(pixelCache) && pixelCache.Has(key)) ? pixelCache[key] : GetPixelRGB(x, y)
            if (bloodColors.r > (bloodColors.g + bloodColors.b) * 2 && bloodColors.r > 100) {
                hitCount++
                return true
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
    global isRunning, isPaused, uCtrl
    static pauseMissCount := 0
    static resumeHitCount := 0

    ; 读取多次确认次数（带默认值和容错）
    PAUSE := uCtrl["ipPause"]["pauseConfirm"].Value
    RESUME := uCtrl["ipPause"]["resumeConfirm"].Value

    if (!isRunning || uCtrl["ipPause"]["enable"].Value != 1)
        return

    ; 像素缓存进行血条检测
    res := GetWindowInfo()
    pixelCache := Map()
    bloodDetected := CheckPauseByBlood(res, pixelCache)

    if (isPaused["blood"]) {
        if (bloodDetected) {
            resumeHitCount++
            pauseMissCount := 0
            if (resumeHitCount >= RESUME) {
                TogglePause("blood", false)
                UpdateStatus("运行中", "检测到血条，自动启动")
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
                UpdateStatus("已暂停", "血条消失，自动暂停")
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
    global isRunning, isPaused, uCtrl
    static pauseMissCount := 0
    static resumeHitCount := 0

    ; 读取多次确认次数（带默认值和容错）
    PAUSE_CONFIRM := uCtrl["tabPause"].Has("pauseConfirm") ? Max(1, Min(9, Integer(uCtrl["tabPause"]["pauseConfirm"].Value
    ))) : 2
    RESUME_CONFIRM := uCtrl["tabPause"].Has("resumeConfirm") ? Max(1, Min(9, Integer(uCtrl["tabPause"]["resumeConfirm"]
        .Value))) : 2

    ; 如果宏未运行或界面检测未启用，则直接返回
    if (!isRunning || uCtrl["tabPause"]["enable"].Value != 1)
        return

    try {
        res := GetWindowInfo()
        pixelCache := Map()
        keyPoints := CheckKeyPoints(res, pixelCache)

        ; TAB界面暂停时，检测是否关闭
        if (isPaused["tab"]) {
            if (keyPoints.isBlueColor) {
                TogglePause("tab", false)
                UpdateStatus("运行中", "界面关闭，自动恢复")
            }
            return
        }

        ; 对话框暂停时，检测是否关闭（多次确认）
        if (isPaused["enter"]) {
            if (!CheckPauseByEnter(res, pixelCache)) {
                resumeHitCount++
                pauseMissCount := 0
                if (resumeHitCount >= RESUME_CONFIRM) {
                    TogglePause("enter", false)
                    UpdateStatus("运行中", "确认对话框消失，自动恢复")
                    resumeHitCount := 0
                }
            } else {
                resumeHitCount := 0
            }
        }

        ; 检测TAB界面或对话框（多次确认）
        if (keyPoints.isRedColor && !keyPoints.isBlueColor) {
            TogglePause("tab", true)
            UpdateStatus("已暂停", "检测到地图界面，自动暂停")
            return
        } else if (CheckPauseByEnter(res, pixelCache)) {
            pauseMissCount++
            resumeHitCount := 0
            if (pauseMissCount >= PAUSE_CONFIRM) {
                TogglePause("enter", true)
                UpdateStatus("已暂停", "检测到确认对话框，自动暂停")
                pauseMissCount := 0
            }
        } else {
            pauseMissCount := 0
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
    global uCtrl
    loop 2 {
        try {
            color := GetPixelRGBNoCache(x, y)
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
}

/**
 * 检测资源状态
 * @returns {Boolean} - 资源是否充足
 */
IsResourceSufficient() {
    global uCtrl
    res := GetWindowInfo()
    x := Round(res["CD4W"] + (2620 - res["D44KWC"]) * res["D4SW"])
    y := Round(res["CD4H"] + (1875 - res["D44KHC"]) * res["D4SH"])

    loop 5 {
        try {
            color := GetPixelRGBNoCache(x, y + (A_Index - 1))

            hsv := RGBToHSV(color.r, color.g, color.b)

            if (hsv.s > 0.30 && hsv.v > 0.15)
                return true
        } catch {
            Sleep 5
        }
    }
    return false
}

/**
 * 获取指定坐标像素的RGB颜色值，支持缓存和无缓存两种模式
 * @param {Integer} x - X坐标
 * @param {Integer} y - Y坐标
 * @param {Boolean} useCache - 是否使用缓存，默认为true
 * @returns {Object} - 包含r, g, b三个颜色分量的对象
 */
GetPixelRGB(x, y, useCache := true) {
    static pixelCache := Map()           ; 缓存最近采样的像素
    static cacheLifetime := 200           ; 缓存有效期(毫秒)
    static lastCacheClear := 0           ; 最后一次缓存清理时间
    static cacheStats := { hits: 0, misses: 0, cleanups: 0 }  ; 缓存统计
    static maxCacheEntries := 100        ; 缓存最大条目数

    ; 获取当前时间
    currentTime := A_TickCount

    ; 如果不使用缓存，直接获取颜色值并返回
    if (!useCache) {
        try {
            color := PixelGetColor(x, y, "RGB")
            r := (color >> 16) & 0xFF
            g := (color >> 8) & 0xFF
            b := color & 0xFF
            return { r: r, g: g, b: b }
        } catch as err {
            return { r: 0, g: 0, b: 0 }  ; 失败时返回黑色
        }
    }

    ; 定期清理缓存(每100毫秒)或缓存项超过限制时
    if (currentTime - lastCacheClear > 100 || pixelCache.Count > maxCacheEntries) {
        pixelCache := Map()
        lastCacheClear := currentTime
        cacheStats.cleanups++
    }

    ; 计算缓存键，使用整数值避免浮点数精度问题
    cacheKey := Format("{:d},{:d},{:d}", x, y, currentTime // cacheLifetime)

    ; 如果缓存中已有该位置的最近结果，直接返回
    if (pixelCache.Has(cacheKey)) {
        cacheStats.hits++
        return pixelCache[cacheKey]
    }

    ; 否则获取新的颜色值
    try {
        color := PixelGetColor(x, y, "RGB")
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF

        result := { r: r, g: g, b: b }

        ; 缓存结果供后续使用 - 使用浅拷贝对象减少内存占用
        pixelCache[cacheKey] := result
        cacheStats.misses++
        return result
    } catch as err {
        return { r: 0, g: 0, b: 0 }  ; 失败时返回黑色
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
    ; 转换为0-1范围
    r := r / 255.0
    g := g / 255.0
    b := b / 255.0

    ; 找到最大最小值
    max_val := Max(r, g, b)
    min_val := Min(r, g, b)
    diff := max_val - min_val

    ; 计算亮度(Value)
    v := max_val

    ; 计算饱和度(Saturation)
    s := (max_val == 0) ? 0 : (diff / max_val)

    ; 计算色相(Hue)
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
 * 无缓存获取像素颜色的便捷函数
 */
GetPixelRGBNoCache(x, y) {
    return GetPixelRGB(x, y, false)
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
        IniWrite(cSkill[i]["key"].Value, file, section, "Skill" i "Key")
        IniWrite(cSkill[i]["enable"].Value, file, section, "Skill" i "Enable")
        IniWrite(cSkill[i]["interval"].Value, file, section, "Skill" i "Interval")

        ; 获取下拉框选择的索引并保存
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
    IniWrite(uCtrl["shift"]["enable"].Value, file, section, "ShiftEnabled")
    IniWrite(uCtrl["ranDom"]["enable"].Value, file, section, "RandomEnabled")
    IniWrite(uCtrl["ranDom"]["max"].Value, file, section, "RandomMax")

    ; 保存其他全局设置
    IniWrite(hotkeyControl.Value, file, section, "StartStopKey")
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

    loop 5 {
        try {
            key := IniRead(file, section, "Skill" A_Index "Key", A_Index)
            enabled := IniRead(file, section, "Skill" A_Index "Enable", 1)
            interval := IniRead(file, section, "Skill" A_Index "Interval", 20)
            mode := Integer(IniRead(file, section, "Skill" A_Index "Mode", 1))

            cSkill[A_Index]["key"].Value := key
            cSkill[A_Index]["enable"].Value := enabled
            cSkill[A_Index]["interval"].Value := interval

            ; 设置模式下拉框
            try {
                cSkill[A_Index]["mode"].Value := mode
            } catch as err {
                cSkill[A_Index]["mode"].Value := 1
            }
        } catch as err {
            ; 如果读取失败，使用默认值
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
    global uCtrl, hotkeyControl
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
        uCtrl["ipPause"]["pauseConfirm"].Value := IniRead(file, section, "IpPausePauseConfirm", "5")
        uCtrl["ipPause"]["resumeConfirm"].Value := IniRead(file, section, "IpPauseResumeConfirm", "2")

        ; 加载TAB检测相关设置
        uCtrl["tabPause"]["enable"].Value := IniRead(file, section, "TabPauseEnable", "0")
        uCtrl["tabPause"]["interval"].Value := IniRead(file, section, "TabPauseInterval", "100")
        uCtrl["tabPause"]["pauseConfirm"].Value := IniRead(file, section, "TabPausePauseConfirm", "2")
        uCtrl["tabPause"]["resumeConfirm"].Value := IniRead(file, section, "TabPauseResumeConfirm", "2")
        ; 加载其他设置
        uCtrl["dcPause"]["enable"].Value := IniRead(file, section, "DcPauseEnable", "1")
        uCtrl["shift"]["enable"].Value := IniRead(file, section, "ShiftEnabled", "0")
        uCtrl["ranDom"]["enable"].Value := IniRead(file, section, "RandomEnabled", "0")
        uCtrl["ranDom"]["max"].Value := IniRead(file, section, "RandomMax", "10")

        ; 加载全局热键
        hotkeyControl.Value := IniRead(file, section, "StartStopKey", "F1")
        ; 加载运行模式
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
LoadGlobalHotkey() {
    global currentHotkey, hotkeyControl, statusBar

    if (hotkeyControl.Value = "") {
        hotkeyControl.Value := currentHotkey ? currentHotkey : "F1"
        statusBar.Text := "热键不能为空，已恢复为: " hotkeyControl.Value
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

; ==================== 热键处理 ====================
#HotIf WinActive("ahk_class Diablo IV Main Window Class")

~LButton::
{
    global isRunning, uCtrl, isPaused
    static lastClickTime := 0

    if (!isRunning || !uCtrl.Has("dcPause") || !uCtrl["dcPause"].Has("enable") || uCtrl["dcPause"]["enable"].Value != 1
    )
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