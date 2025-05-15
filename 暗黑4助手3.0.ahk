#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

; ========== 全局变量定义 ==========
; 核心状态变量
global DEBUG := false              ; 是否启用调试模式
global debugLogFile := A_ScriptDir "\debugd4.log"
global isRunning := false          ; 宏是否运行中
global isPaused := false           ; 宏是否暂停
global previouslyPaused := false   ; 记录之前的暂停状态
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
global skillControls := Map()      ; 技能控件映射
global skillBuffControls := Map()  ; 技能BUFF控件映射
global mouseControls := {}         ; 鼠标控件
global uCtrl := {}       ; 功能键控件
global mouseAutoMove := {}         ; 鼠标自动移动控件
global forceMove := {}             ; 强制移动控件

; 技能模式常量
global SKILL_MODE_CLICK := 1       ; 连点模式
global SKILL_MODE_BUFF := 2        ; BUFF模式
global SKILL_MODE_HOLD := 3        ; 按住模式
global skillModeNames := ["连点", "BUFF", "按住"]

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
    myGui := Gui("", "暗黑4助手 v3.0")
    myGui.BackColor := "FFFFFF"
    myGui.SetFont("s10", "Microsoft YaHei UI")

    ; 添加主要内容区域
    myGui.AddGroupBox("x10 y10 w460 h120", "F3: 卡快照")
    statusText := myGui.AddText("x30 y35 w200 h20", "状态: 未运行")
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
    global myGui, skillControls, mouseControls, uCtrl
    global mouseAutoMove, skillModeNames, SKILL_MODE_CLICK

    ; === 创建技能控件 ===
    skillControls := Map()
    Loop 5 {
        yPos := 305 + (A_Index-1) * 30
        myGui.AddText("x30 y" yPos " w40 h20", "技能" A_Index ":")
        skillControls[A_Index] := {
            key: myGui.AddHotkey("x90 y" yPos " w30 h20", A_Index),
            enable: myGui.AddCheckbox("x130 y" yPos " w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y" yPos " w40 h20", "20"),
            mode: myGui.AddDropDownList("x270 y" yPos " w60 h120 Choose1", skillModeNames)
        }
    }

    ; === 创建鼠标控件 ===
    mouseControls := {
        left: {
            enable: myGui.AddCheckbox("x130 y455 w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y455 w40 h20", "80"),
            mode: myGui.AddDropDownList("x270 y455 w60 h120 Choose1", skillModeNames)
        },
        right: {
            enable: myGui.AddCheckbox("x130 y485 w45 h20", "启用"),
            interval: myGui.AddEdit("x200 y485 w40 h20", "300"),
            mode: myGui.AddDropDownList("x270 y485 w60 h120 Choose1", skillModeNames)
        }
    }
    myGui.AddText("x30 y455 w40 h20", "左键:")
    myGui.AddText("x30 y485 w40 h20", "右键:")

    ; === 创建控件 ===
    myGui.AddText("x30 y515 w30 h20", "喝药:")
    myGui.AddText("x30 y545 w30 h20", "强移:")
    myGui.AddText("x300 y100 w70 h20", "双击暂停:")
    myGui.AddText("x300 y70 w70 h20", "自动启停：")
    uCtrl := {}

    uCtrl.dodge := {
        key: myGui.AddText("x30 y575 w30 h20", "空格:"),
        enable: myGui.AddCheckbox("x130 y575 w45 h20", "启用"),
        interval: myGui.AddEdit("x200 y575 w40 h20", "20")
    }
    uCtrl.potion := {
        key: myGui.AddHotkey("x90 y515 w35 h20", "q"),
        enable: myGui.AddCheckbox("x130 y515 w45 h20", "启用"),
        interval: myGui.AddEdit("x200 y515 w40 h20", "3000")
    }
    uCtrl.forceMove := {
        key: myGui.AddHotkey("x90 y545 w35 h20", "f"),
        enable: myGui.AddCheckbox("x130 y545 w45 h20", "启用"),
        interval: myGui.AddEdit("x200 y545 w40 h20", "50")
    }

    uCtrl.ipMode := {
        enable: myGui.AddCheckbox("x360 y70 w50")
    }

    uCtrl.dcPause := {
        enable: myGui.AddCheckbox("x360 y100 w30 h20")
    }

    ; 添加鼠标自动移动控件
    mouseAutoMove := {
        enable: myGui.AddCheckbox("x30 y605 w100 h20", "鼠标自动移动"),
        interval: myGui.AddEdit("x160 y605 w40 h20", "1000")
    }
    mouseAutoMove.enable.OnEvent("Click", ToggleMouseAutoMove)
    
    ; 定义法师技能及其属性名映射
    mageSkills := [
        {name: "火盾", key: "2", x: 70, prop: "huoDun"},
        {name: "电矛", key: "1", x: 150, prop: "dianMao"},
        {name: "电球", key: "e", x: 230, prop: "dianQiu"},
        {name: "冰盾", key: "3", x: 320, prop: "binDun"}
    ]
    for skill in mageSkills {
    myGui.AddText("x" (skill.x-40) " y640 w30 h20", skill.name ":")
    propName := skill.prop
    uCtrl.%propName% := { key: myGui.AddHotkey("x" skill.x " y635 w35 h20", skill.key) }
}
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
    myGui.OnEvent("Close", (*) => ExitApp())
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
    statusText.Value := "状态: " status
    statusBar.Text := barText
    DebugLog("状态更新: " status " | " barText)
}

; ==================== 核心控制函数 ====================
/**
 * 切换宏运行状态
 */
ToggleMacro(*) {
    global isRunning, isPaused, previouslyPaused, mouseAutoMoveEnabled, mouseAutoMove

    ; 确保完全停止所有定时器
    StopAllTimers()
    StopImagePauseTimer() ; 停止识图定时器
    StopWindowCheckTimer() ; 停止窗口检测定时器
    ; 切换运行状态
    isRunning := !isRunning

    if isRunning {
        ; 初始化窗口分辨率和技能位置
        GetDynamicSkillPositions()
        ; 重置暂停状态
        isPaused := false
        previouslyPaused := false

        ; 确保鼠标自动移动状态与GUI勾选框一致
        mouseAutoMoveEnabled := (mouseAutoMove.enable.Value = 1)

        ; 只有在暗黑4窗口激活时才启动定时器
        if WinActive("ahk_class Diablo IV Main Window Class") {
            StartAllTimers()
            StartImagePauseTimer() ; 启动识图定时器
            StartWindowCheckTimer() ; 启动窗口检测定时器
            UpdateStatus("运行中", "宏已启动")
        } else {
            isPaused := true
            UpdateStatus("已暂停(窗口切换)", "宏已暂停 - 窗口未激活")
        }
    } else {
        ; 确保重置所有状态
        isPaused := false
        previouslyPaused := false
        UpdateStatus("已停止", "宏已停止")

        ; 确保释放所有按键
        ReleaseAllKeys()
    }

    DebugLog("宏状态切换: " . (isRunning ? "运行" : "停止"))
}

/**
 * 释放所有可能被按住的按键
 */
ReleaseAllKeys() {
    global skillControls, holdStates

    ; 释放修饰键
    Send "{Shift up}"
    Send "{Ctrl up}"
    Send "{Alt up}"

    ; 释放技能键
    Loop 5 {
        key := skillControls[A_Index].key.Value
        if key != "" {
            Send "{" key " up}"
            DebugLog("释放技能" A_Index " 键: " key)
        }
    }

    ; 释放鼠标按键
    SetMouseDelay -1
    Click "up left"
    Click "up right"

    holdStates.Clear() ; 清空所有按住状态

    ; 重置鼠标按键状态
    ResetMouseButtonStates()

    DebugLog("已释放所有按键")
}

/**
 * 自动恢复暂停的功能
 */
ResumeAfterPause() {
    global isRunning, isPaused  ; 这个函数中也需要声明全局变量
    
    if (isRunning && isPaused) {
        isPaused := false
        StartAllTimers()
        UpdateStatus("运行中", "宏已自动恢复 - 双击暂停结束")
        DebugLog("双击暂停2秒后自动恢复")
    }
}

; ==================== 定时器管理 ====================
/**
 * 启动所有定时器
 */
StartAllTimers() {
    ; 先停止所有定时器，确保清理
    StopAllTimers()

    ; 启动技能定时器
    StartSkillTimers()

    ; 启动鼠标和功能键定时器
    StartUtilityTimers()

    ; 启动鼠标自动移动定时器
    StartMouseAutoMoveTimer()
    
    DebugLog("所有定时器已启动")
}

/**
 * 启动技能定时器
 */
StartSkillTimers() {
    global skillControls, boundSkillTimers, timerStates

    for i in [1, 2, 3, 4, 5] {
        if (skillControls[i].enable.Value = 1) {
            interval := Integer(skillControls[i].interval.Value)
            if (interval > 0) {
                boundSkillTimers[i] := PressSkill.Bind(i)
                SetTimer(boundSkillTimers[i], interval)
                timerStates[i] := true
                DebugLog("启动技能" i "定时器，间隔: " interval)
            }
        }
    }
}

/**
 * 启动鼠标和功能键定时器
 */
StartUtilityTimers() {
    StartSingleTimer("leftClick", mouseControls.left, PressLeftClick)
    StartSingleTimer("rightClick", mouseControls.right, PressRightClick)
    StartSingleTimer("dodge", uCtrl.dodge, PressDodge)
    StartSingleTimer("potion", uCtrl.potion, PressPotion)
    StartSingleTimer("forceMove", uCtrl.forceMove, PressForceMove)
}

/**
 * 启动鼠标自动移动定时器
 */
StartMouseAutoMoveTimer() {
    global mouseAutoMoveEnabled, mouseAutoMove, timerStates

    DebugLog("鼠标自动移动状态: " . (mouseAutoMoveEnabled ? "启用" : "禁用") . ", GUI勾选状态: " . mouseAutoMove.enable.Value)

    if (mouseAutoMoveEnabled) {
        interval := Integer(mouseAutoMove.interval.Value)
        if (interval > 0) {
            SetTimer(MoveMouseToNextPoint, interval)
            timerStates["mouseAutoMove"] := true
            DebugLog("启动鼠标自动移动定时器 - 间隔: " interval)
        }
    }
}

/**
 * 启动单个定时器
 * @param {String} name - 定时器名称
 * @param {Object} control - 控件对象
 * @param {Function} timerFunc - 定时器函数
 */
StartSingleTimer(name, control, timerFunc) {
    global timerStates

    if (control.enable.Value = 1) {
        interval := Integer(control.interval.Value)
        if (interval > 0) {
            SetTimer(timerFunc, interval)
            timerStates[name] := true
            DebugLog("启动" name "定时器 - 间隔: " interval)
        }
    }
}

/**
 * 停止所有定时器
 */
StopAllTimers() {
    global boundSkillTimers, skillControls

    ; 停止技能定时器
    Loop 5 {
        if boundSkillTimers.Has(A_Index) {
            SetTimer(boundSkillTimers[A_Index], 0)
            boundSkillTimers.Delete(A_Index)
            DebugLog("停止技能" A_Index "定时器")
        }

        ; 如果是按住模式，确保释放按键
        key := skillControls[A_Index].key.Value
        if (key != "") {
            Send "{" key " up}"
        }
    }

    ; 停止所有其他定时器
    SetTimer PressLeftClick, 0
    SetTimer PressRightClick, 0
    SetTimer PressDodge, 0
    SetTimer PressPotion, 0
    SetTimer PressForceMove, 0
    SetTimer MoveMouseToNextPoint, 0
    
    ; 重置鼠标按键状态
    ResetMouseButtonStates()

    DebugLog("已停止所有定时器并释放按键")
}

/**
 * 启动自动暂停定时器
 */
StartImagePauseTimer() {
    SetTimer AutoPauseByColor, 50
}

/**
 * 停止自动暂停定时器
 */
StopImagePauseTimer() {
    SetTimer AutoPauseByColor, 0
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

; ==================== 按键与技能处理 ====================
/**
 * 通用按键处理
 * @param {String} keyOrBtn - 键名或鼠标按钮名
 * @param {Integer} mode - 模式编号
 * @param {Object} pos - BUFF检测坐标对象（可选）
 * @param {String} type - "key"、"mouse" 或 "utility"
 * @param {String} mouseBtn - 鼠标按钮名（如"left"/"right"，仅type为mouse时用）
 * @param {String} description - 按键描述（用于日志）
 */
HandleKeyMode(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "", description := "") {
    global shiftEnabled, buffThreshold, holdStates
    static lastReholdTime := Map()     ; 存储每个按键上次重新按住的时间
    static REHOLD_MIN_INTERVAL := 2000 ; 重新按住的最小间隔(毫秒)
    
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
            ; 首次按下
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
                    Click "down " mouseBtn
                    DebugLog("重新按住" . keyDesc . "，间隔: " (currentTime - lastReholdTime[uniqueKey]) "ms")
                } else {
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
    global isRunning, isPaused, skillControls, skillPositions
    if (!isRunning || isPaused || !skillControls[skillNum].enable.Value)
        return
    key := skillControls[skillNum].key.Value
    if (key = "")
        return
    mode := skillControls[skillNum].mode.Value
    pos := skillPositions.Has(skillNum) ? skillPositions[skillNum] : ""
    HandleKeyMode(key, mode, pos, "key")
}

/**
 * 鼠标左键处理
 */
PressLeftClick() {
    global isRunning, isPaused, mouseControls, skillPositions
    if (!isRunning || isPaused || !mouseControls.left.enable.Value)
        return
    mode := mouseControls.left.mode.Value
    pos := skillPositions.Has("left") ? skillPositions["left"] : ""
    HandleKeyMode("left", mode, pos, "mouse", "left")
}

/**
 * 鼠标右键处理
 */
PressRightClick() {
    global isRunning, isPaused, mouseControls, skillPositions
    if (!isRunning || isPaused || !mouseControls.right.enable.Value)
        return
    mode := mouseControls.right.mode.Value
    pos := skillPositions.Has("right") ? skillPositions["right"] : ""
    HandleKeyMode("right", mode, pos, "mouse", "right")
}

/**
 * 按下空格键(空格)
 */
PressDodge() {
    global isRunning, isPaused, uCtrl
    
    if (isRunning && !isPaused && uCtrl.dodge.enable.Value = 1) {
        ; 空格键总是使用连点模式
        HandleKeyMode("Space", SKILL_MODE_CLICK, "", "key", "", "空格键")
    }
}

/**
 * 按下喝药键
 */
PressPotion() {
    global isRunning, isPaused, uCtrl
    
    if (isRunning && !isPaused && uCtrl.potion.enable.Value = 1) {
        key := uCtrl.potion.key.Value
        if (key != "") {
            HandleKeyMode(key, SKILL_MODE_CLICK, "", "key", "", "喝药键")
        }
    }
}

/**
 * 按下强制移动键
 */
PressForceMove() {
    global isRunning, isPaused, uCtrl
    
    if (isRunning && !isPaused && uCtrl.forceMove.enable.Value = 1) {
        key := uCtrl.forceMove.key.Value
        if (key != "") {
            HandleKeyMode(key, SKILL_MODE_CLICK, "", "key", "", "强制移动键")
        }
    }
}

/**
 * 发送按键
 * @param {String} key - 要发送的按键
 */
SendKey(key) {
    global shiftEnabled

    if (shiftEnabled) {
        SendWithShift(key)
    } else {
        Send "{" key "}"
    }
}

/**
 * shift按键发送函数
 * @param {String} key - 要发送的按键
 */
SendWithShift(key) {
    Send "{Shift down}"
    Sleep 10
    Send "{" key "}"
    Sleep 10
    Send "{Shift up}"
}

/**
 * 重置鼠标按键状态
 */
ResetMouseButtonStates() {
    static leftMouseHeld := false
    static rightMouseHeld := false

    if (leftMouseHeld) {
        Click "up left"
        leftMouseHeld := false
        DebugLog("释放鼠标左键")
    }

    if (rightMouseHeld) {
        Click "up right"
        rightMouseHeld := false
        DebugLog("释放鼠标右键")
    }
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
    global mouseAutoMoveCurrentPoint, isRunning, isPaused, mouseAutoMoveEnabled

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
    global mouseAutoMoveEnabled, mouseAutoMove, isRunning, isPaused, timerStates

    mouseAutoMoveEnabled := !mouseAutoMoveEnabled

    ; 更新GUI勾选框状态以匹配当前状态
    mouseAutoMove.enable.Value := mouseAutoMoveEnabled ? 1 : 0

    ; 如果宏已经在运行，则更新定时器状态
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
    global isRunning, isPaused, previouslyPaused, statusText, statusBar

    if (!isActive) {  ; 窗口失去焦点
        if (isRunning) {
            previouslyPaused := isPaused
            if (!isPaused) {
                StopAllTimers()
                isPaused := true
                UpdateStatus("已暂停(窗口切换)", "宏已暂停 - 窗口未激活")
            }
        }
    } else if (isRunning && isPaused && !previouslyPaused) {  ; 窗口获得焦点且之前不是手动暂停
        StartAllTimers()
        isPaused := false
        UpdateStatus("运行中", "宏已恢复 - 窗口已激活")
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
 * 检查颜色时使用缩放比例
 */
CheckPauseByColor() {
    res := GetWindowResolutionAndScale()

    try {
        ; 定义检测点的坐标
        x1 := Round(1605 * res.scaleW), x2 := Round(1435 * res.scaleW)
        y1 := Round(85 * res.scaleH), y2 := Round(95 * res.scaleH)

        ; 检测颜色
        colors := [
            GetPixelRGB(x1, y1),
            GetPixelRGB(x1, y2),
            GetPixelRGB(x2, y1),
            GetPixelRGB(x2, y2)
        ]

        ; 统计满足红色条件的点数
        hitCount := 0
        for color in colors {
            if (color.r > 100 && color.g < 60 && color.b < 60)
                hitCount++
        }

        ; 至少命中2个点才返回 true
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
    ; 仅在启用时才执行
    if (!isRunning || uCtrl.ipMode.enable.Value != 1)
        return

    if (CheckPauseByColor()) {
        ; 检测到红色时启动
        if (isPaused) {
            isPaused := false
            StartAllTimers()
            UpdateStatus("运行中", "检测到红色，自动启动")
            DebugLog("识图触发自动启动")
        }
    } else {
        ; 红色消失时暂停
        if (!isPaused) {
            isPaused := true
            StopAllTimers()
            UpdateStatus("已暂停", "红色消失，自动暂停")
            DebugLog("识图触发自动暂停")
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
        SaveUtilitySettings(settingsFile, profileName)
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
    global skillControls
    section := profileName "_Skills"

    for i in [1, 2, 3, 4, 5] {
        IniWrite(skillControls[i].key.Value, file, section, "Skill" i "Key")
        IniWrite(skillControls[i].enable.Value, file, section, "Skill" i "Enable")
        IniWrite(skillControls[i].interval.Value, file, section, "Skill" i "Interval")

        ; 获取下拉框选择的索引并保存
        modeIndex := skillControls[i].mode.Value
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
    global mouseControls, mouseAutoMove
    section := profileName "_Mouse"

    ; 保存左键设置
    IniWrite(mouseControls.left.enable.Value, file, section, "LeftClickEnable")
    IniWrite(mouseControls.left.interval.Value, file, section, "LeftClickInterval")
    leftModeIndex := mouseControls.left.mode.Value
    IniWrite(leftModeIndex, file, section, "LeftClickMode")
    DebugLog("保存左键模式: " leftModeIndex)

    ; 保存右键设置
    IniWrite(mouseControls.right.enable.Value, file, section, "RightClickEnable")
    IniWrite(mouseControls.right.interval.Value, file, section, "RightClickInterval")
    rightModeIndex := mouseControls.right.mode.Value
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
SaveUtilitySettings(file, profileName) {
    global uCtrl, hotkeyControl, sleepInput
    section := profileName "_Utility"

    IniWrite(uCtrl.dodge.enable.Value, file, section, "DodgeEnable")
    IniWrite(uCtrl.dodge.interval.Value, file, section, "DodgeInterval")
    IniWrite(uCtrl.potion.key.Value, file, section, "PotionKey")
    IniWrite(uCtrl.potion.enable.Value, file, section, "PotionEnable")
    IniWrite(uCtrl.potion.interval.Value, file, section, "PotionInterval")
    IniWrite(uCtrl.forceMove.key.Value, file, section, "ForceMoveKey")
    IniWrite(uCtrl.forceMove.enable.Value, file, section, "ForceMoveEnable")
    IniWrite(uCtrl.forceMove.interval.Value, file, section, "ForceMoveInterval")
    IniWrite(uCtrl.huoDun.key.Value, file, section, "HuoDunKey")
    IniWrite(uCtrl.dianMao.key.Value, file, section, "DianMaoKey")
    IniWrite(uCtrl.dianQiu.key.Value, file, section, "DianQiuKey")
    IniWrite(uCtrl.binDun.key.Value, file, section, "BinDunKey")
    IniWrite(sleepInput.Value, file, section, "SnapSleepDelay")
    IniWrite(uCtrl.dcPause.enable.Value, file, section, "DcPauseEnable")
    IniWrite(uCtrl.ipMode.enable.Value, file, section, "IpModeEnable")
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
        LoadUtilitySettings(settingsFile, profileName)
        
        ; 每个配置都应用自己的热键和自动启停
        LoadGlobalHotkey()
        DebugLog("所有设置已从文件加载: " settingsFile " 配置方案: " profileName)
    } catch as err {
        DebugLog("加载设置出错: " err.Message)
    }

    DebugLog("自动启停模式已同步: " uCtrl.ipMode.enable.Value)
}
/**
 * 加载技能设置
 * @param {String} file - 设置文件路径
 * @param {String} profileName - 配置方案名称
 */
LoadSkillSettings(file, profileName) {
    global skillControls, SKILL_MODE_CLICK
    section := profileName "_Skills"

    Loop 5 {
        try {
            key := IniRead(file, section, "Skill" A_Index "Key", A_Index)
            enabled := IniRead(file, section, "Skill" A_Index "Enable", 1)
            interval := IniRead(file, section, "Skill" A_Index "Interval", 20)
            mode := Integer(IniRead(file, section, "Skill" A_Index "Mode", SKILL_MODE_CLICK))

            skillControls[A_Index].key.Value := key
            skillControls[A_Index].enable.Value := enabled
            skillControls[A_Index].interval.Value := interval

            ; 设置模式下拉框
            try {
                DebugLog("尝试设置技能" A_Index "模式为: " mode)
                if (mode >= 1 && mode <= 3) {
                    ; 直接设置Text属性而不是使用Choose方法
                    if (mode == 1)
                        skillControls[A_Index].mode.Text := "连点"
                    else if (mode == 2)
                        skillControls[A_Index].mode.Text := "BUFF"
                    else if (mode == 3)
                        skillControls[A_Index].mode.Text := "按住"

                    DebugLog("成功设置技能" A_Index "模式为: " mode)
                } else {
                    skillControls[A_Index].mode.Text := "连点"
                    DebugLog("技能" A_Index "模式值无效: " mode "，使用默认连点模式")
                }
            } catch as err {
                skillControls[A_Index].mode.Text := "连点"
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
    global mouseControls, mouseAutoMove, mouseAutoMoveEnabled, SKILL_MODE_CLICK
    section := profileName "_Mouse"

    try {
        ; 加载左键设置
        mouseControls.left.enable.Value := IniRead(file, section, "LeftClickEnable", 0)
        mouseControls.left.interval.Value := IniRead(file, section, "LeftClickInterval", 80)
        leftMode := Integer(IniRead(file, section, "LeftClickMode", SKILL_MODE_CLICK))

        ; 加载右键设置
        mouseControls.right.enable.Value := IniRead(file, section, "RightClickEnable", 1)
        mouseControls.right.interval.Value := IniRead(file, section, "RightClickInterval", 300)
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
                    mouseControls.left.mode.Text := "连点"
                else if (leftMode == 2)
                    mouseControls.left.mode.Text := "BUFF"
                else if (leftMode == 3)
                    mouseControls.left.mode.Text := "按住"

                DebugLog("成功设置左键模式为: " leftMode)
            } else {
                mouseControls.left.mode.Text := "连点"
                DebugLog("左键模式值无效: " leftMode "，使用默认连点模式")
            }
        } catch as err {
            mouseControls.left.mode.Text := "连点"
            DebugLog("设置左键模式出错: " err.Message "，使用默认连点模式")
        }

        ; 设置右键模式下拉框
        try {
            DebugLog("尝试设置右键模式为: " rightMode)
            if (rightMode >= 1 && rightMode <= 3) {
                ; 直接设置Text属性而不是使用Choose方法
                if (rightMode == 1)
                    mouseControls.right.mode.Text := "连点"
                else if (rightMode == 2)
                    mouseControls.right.mode.Text := "BUFF"
                else if (rightMode == 3)
                    mouseControls.right.mode.Text := "按住"

                DebugLog("成功设置右键模式为: " rightMode)
            } else {
                mouseControls.right.mode.Text := "连点"
                DebugLog("右键模式值无效: " rightMode "，使用默认连点模式")
            }
        } catch as err {
            mouseControls.right.mode.Text := "连点"
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
LoadUtilitySettings(file, profileName) {
    global uCtrl, hotkeyControl, sleepInput
    section := profileName "_Utility"

    try {
        uCtrl.dodge.enable.Value := IniRead(file, section, "DodgeEnable", 0)
        uCtrl.dodge.interval.Value := IniRead(file, section, "DodgeInterval", 20)
        uCtrl.potion.key.Value := IniRead(file, section, "PotionKey", "q")
        uCtrl.potion.enable.Value := IniRead(file, section, "PotionEnable", 0)
        uCtrl.potion.interval.Value := IniRead(file, section, "PotionInterval", 3000)
        uCtrl.forceMove.key.Value := IniRead(file, section, "ForceMoveKey", "f")
        uCtrl.forceMove.enable.Value := IniRead(file, section, "ForceMoveEnable", 0)
        uCtrl.forceMove.interval.Value := IniRead(file, section, "ForceMoveInterval", 50)
        uCtrl.huoDun.key.Value := IniRead(file, section, "HuoDunKey", "2")
        uCtrl.dianMao.key.Value := IniRead(file, section, "DianMaoKey", "1")
        uCtrl.dianQiu.key.Value := IniRead(file, section, "DianQiuKey", "e")
        uCtrl.binDun.key.Value := IniRead(file, section, "BinDunKey", "3")
        uCtrl.dcPause.enable.Value := IniRead(file, section, "DcPauseEnable", 1)
        uCtrl.ipMode.enable.Value := IniRead(file, section, "IpModeEnable", 1)
        sleepInput.Value := IniRead(file, section, "SnapSleepDelay", 2700)
        hotkeyControl.Value := IniRead(file, section, "StartStopKey", "F1")
    } catch as err {
        DebugLog("加载功能键设置出错: " err.Message)
    }
}

/**
 * 加载全局热键
 */
LoadGlobalHotkey() {
    global currentHotkey, hotkeyControl, myGui
    
    ; 跳过初始化时的空值
    if (hotkeyControl.Value = "")
        return
    
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
        myGui.statusBar.Text := "热键已更新: " newHotkey
    }
}


; ==================== 热键处理 ====================
#HotIf WinActive("ahk_class Diablo IV Main Window Class")

F3::{
    ; 确保从配置对象获取最新值
    dianQiuKey := uCtrl.dianQiu.key.Value
    huoDunKey := uCtrl.huoDun.key.Value
    dianMaoKey := uCtrl.dianMao.key.Value
    binDunKey := uCtrl.binDun.key.Value
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

Tab::{
    global isRunning, isPaused

    ; 发送原始键
    Send "{Tab}"

    ; 如果宏未运行，不做其他处理
    if !isRunning
        return

    ; 切换暂停状态
    isPaused := !isPaused

    if isPaused {
        StopAllTimers()
        UpdateStatus("已暂停", "宏已暂停")
    } else {
        StartAllTimers()
        UpdateStatus("运行中", "宏已继续")
    }
}

Enter::{
    global isRunning, isPaused

    ; 发送原始键
    Send "{Enter}"

    ; 如果宏未运行，不做其他处理
    if !isRunning
        return

    ; 切换暂停状态
    isPaused := !isPaused

    if isPaused {
        StopAllTimers()
        UpdateStatus("已暂停", "宏已暂停")
    } else {
        StartAllTimers()
        UpdateStatus("运行中", "宏已继续")
    }
}

NumpadEnter::{
    global isRunning, isPaused

    ; 发送原始NumpadEnter键
    Send "{NumpadEnter}"

    ; 如果宏未运行，不做其他处理
    if !isRunning
        return

    ; 切换暂停状态
    isPaused := !isPaused

    if isPaused {
        StopAllTimers()
        UpdateStatus("已暂停", "宏已暂停")
    } else {
        StartAllTimers()
        UpdateStatus("运行中", "宏已继续")
    }
}

; 鼠标左键双击检测
~LButton::{
    global isRunning, isPaused, previouslyPaused, uCtrl ; 声明这些是全局变量
    static lastClickTime := 0
    ; 如果未启用双击暂停，直接返回
    if (!isRunning || uCtrl.dcPause.enable.Value != 1)
        return
        
    currentTime := A_TickCount
    
    ; 检查是否在400ms内发生了双击
    if (currentTime - lastClickTime < 400) {
        ; 是双击，暂停宏
        if (!isPaused) {
            ; 记录之前的暂停状态
            previouslyPaused := isPaused
            
            ; 暂停宏
            StopAllTimers()
            isPaused := true
            UpdateStatus("已暂停(鼠标双击)", "宏已暂停 - 将在2秒后自动恢复")
            DebugLog("鼠标双击触发暂停，2秒后自动恢复")
            
            ; 设置2秒后自动恢复
            SetTimer(ResumeAfterPause, -2000)  ; 负号表示只运行一次
        }
        
        lastClickTime := 0  ; 重置以避免连续触发
    } else {
        ; 记录点击时间
        lastClickTime := currentTime
    }
}

; 初始化GUI
InitializeGUI()
