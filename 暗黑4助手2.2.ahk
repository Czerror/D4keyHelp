#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

; ========== 全局变量定义 ==========
; 核心状态变量
global DEBUG := false ; 是否启用调试模式
global debugLogFile := A_ScriptDir "\debugd4.log"
global isRunning := false
global isPaused := false
global previouslyPaused := false
global counter := 0
global currentHotkey := "F1"

; GUI相关变量
global myGui := ""
global statusText := ""
global statusBar := ""
global skillControls := Map()
global skillBuffControls := Map()
global mouseControls := {}
global utilityControls := {}

; 功能状态变量
global shiftEnabled := false
global skillActiveState := false
global mouseAutoMoveEnabled := false
global mouseAutoMoveCurrentPoint := 1
global imagePauseMode := 2 ; Default value, assuming "2" corresponds to "Disabled"
; 技能模式常量
global SKILL_MODE_CLICK := 1    ; 连点模式
global SKILL_MODE_BUFF := 2     ; BUFF模式
global SKILL_MODE_HOLD := 3     ; 按住模式
global skillModeNames := ["连点", "BUFF", "按住"]

; 技能位置映射
global skillPositions := Map()


; 定时器相关变量
global boundSkillTimers := Map()  ; 存储绑定的技能定时器函数
global timerStates := Map()       ; 用于跟踪定时器状态

; 控件变量
global forceMove := {}            ; 强制移动控件
global mouseAutoMove := {}        ; 鼠标自动移动控件
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
; ========== 辅助函数 ==========
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

; ========== GUI创建 ==========
/**
 * 创建主GUI界面
 */
CreateMainGUI() {
    global myGui, statusText, statusBar, hotkeyControl, imagePauseMode

    ; 创建主窗口
    myGui := Gui("", "暗黑4助手 v2.2")
    myGui.BackColor := "FFFFFF"
    myGui.SetFont("s10", "Microsoft YaHei UI")

    ; 添加主要内容区域
    myGui.AddGroupBox("x10 y10 w460 h120", "F3: 卡快照  F4: 卡移速")
    statusText := myGui.AddText("x30 y35 w200 h20", "状态: 未运行")
    myGui.AddButton("x30 y65 w80 h30", "开始/停止").OnEvent("Click", ToggleMacro)
    myGui.AddText("x30 y100 w300 h20", "提示：仅在暗黑破坏神4窗口活动时生效")
    ; 添加识图暂停下拉框
    myGui.AddText("x300 y70 w70 h20", "自动启停：")
    imagePauseMode := myGui.AddDropDownList("x360 y65 w50", ["启用", "禁用"])
    ; 添加技能设置区域
    myGui.AddGroupBox("x10 y140 w460 h410", "键设置")

    ; 添加Shift键勾选框
    myGui.AddCheckbox("x30 y165 w100 h20", "按住Shift").OnEvent("Click", ToggleShift)

    ; 添加列标题
    myGui.AddText("x30 y195 w60 h20", "按键")
    myGui.AddText("x130 y195 w60 h20", "启用")
    myGui.AddText("x200 y195 w120 h20", "间隔(毫秒)")

    hotkeyControl := myGui.AddHotkey("x120 y70 w80 h20", currentHotkey)
    hotkeyControl.OnEvent("Change", (ctrl, *) => LoadGlobalHotkey())

    myGui.AddText("x130 y165", "BUFF检测阈值:")
    global buffThreshold := myGui.AddSlider("x260 y165 w100 Range50-200", 100)
    global buffThresholdValue := myGui.AddText("x360 y165 w30 h20", buffThreshold.Value)
    buffThreshold.OnEvent("Change", UpdateBuffThresholdDisplay)

    ; 添加 Sleep 延迟数字输入框
    myGui.AddText("x180 y600 w200 h20", "卡快照延迟(毫秒):")
    global sleepInput := myGui.AddEdit("x290 y595 w40", 2700)
    sleepInput.OnEvent("Change", UpdateSleepD)
}

UpdateBuffThresholdDisplay(ctrl, *) {
    buffThresholdValue.Text := buffThreshold.Value
    ; 如果需要实时获取值也可以在此处更新阈值
}

UpdateSleepD(ctrl, sleepD) {
    try {
        newValue := Integer(ctrl.Value)
        if (newValue >= 2400 && newValue <= 5000) {
            sleepD := newValue
            DebugLog("Sleep 延迟更新为: " sleepD)
        } else {
            ctrl.Value := sleepD
            DebugLog("输入值超出范围，恢复为: " sleepD)
        }
    } catch {
        ctrl.Value := sleepD
        DebugLog("输入值无效，恢复为: " sleepD)
    }
    return sleepD
}
/**
 * 创建技能控件
 */
CreateSkillControls() {
    global myGui, skillControls, skillModeNames, SKILL_MODE_CLICK

    skillControls := Map()
    Loop 5 {
        yPos := 225 + (A_Index-1) * 30
        myGui.AddText("x30 y" yPos " w60 h20", "技能" A_Index ":")
        skillControls[A_Index] := {
            key: myGui.AddHotkey("x90 y" yPos " w35 h20", A_Index),
            enable: myGui.AddCheckbox("x130 y" yPos " w60 h20", "启用"),
            interval: myGui.AddEdit("x200 y" yPos " w60 h20", "20"),
            mode: myGui.AddDropDownList("x270 y" yPos " w100 h120 Choose1", skillModeNames)
        }
    }
}

/**
 * 创建鼠标控件
 */
CreateMouseControls() {
    global myGui, mouseControls, skillModeNames, SKILL_MODE_CLICK

    mouseControls := {
        left: {
            enable: myGui.AddCheckbox("x130 y375 w60 h20", "启用"),
            interval: myGui.AddEdit("x200 y375 w60 h20", "80"),
            mode: myGui.AddDropDownList("x270 y375 w100 h120 Choose1", skillModeNames)
        },
        right: {
            enable: myGui.AddCheckbox("x130 y405 w60 h20", "启用"),
            interval: myGui.AddEdit("x200 y405 w60 h20", "300"),
            mode: myGui.AddDropDownList("x270 y405 w100 h120 Choose1", skillModeNames)
        }
    }
    myGui.AddText("x30 y375 w60 h20", "左键:")
    myGui.AddText("x30 y405 w60 h20", "右键:")
}

/**
 * 创建功能键控件
 */
CreateUtilityControls() {
    global myGui, utilityControls, mouseAutoMove

    myGui.AddText("x30 y435 w60 h20", "翻滚:")
    myGui.AddText("x30 y465 w60 h20", "喝药:")
    myGui.AddText("x30 y495 w60 h20", "强移:")
    myGui.AddText("x30 y560 w60 h20", "火盾:")
    myGui.AddText("x110 y560 w60 h20", "电矛:")
    myGui.AddText("x190 y560 w60 h20", "电球:")
    myGui.AddText("x280 y560 w60 h20", "冰盾:")

    utilityControls := {
        dodge: {
            key: myGui.AddText("x90 y435 w35 h20", "空格"),
            enable: myGui.AddCheckbox("x130 y435 w60 h20", "启用"),
            interval: myGui.AddEdit("x200 y435 w60 h20", "20")
        },
        potion: {
            key: myGui.AddHotkey("x90 y465 w35 h20", "q"),
            enable: myGui.AddCheckbox("x130 y465 w60 h20", "启用"),
            interval: myGui.AddEdit("x200 y465 w60 h20", "3000")
        },
        forceMove: {
            key: myGui.AddHotkey("x90 y495 w35 h20", "``"),
            enable: myGui.AddCheckbox("x130 y495 w60 h20", "启用"),
            interval: myGui.AddEdit("x200 y495 w60 h20", "50")
        },
        huoDun: {  ; 火盾
            key: myGui.AddHotkey("x70 y555 w35 h20", "2"),
        },    
        dianMao: {  ; 电矛
            key: myGui.AddHotkey("x150 y555 w35 h20", "1"),
        },
        dianQiu: {  ; 电球
            key: myGui.AddHotkey("x230 y555 w35 h20", "e"),
        },
        binDun: {  ; 冰盾
            key: myGui.AddHotkey("x320 y555 w35 h20", "3"),
        }
    }

    ; 添加鼠标自动移动控件
    mouseAutoMove := {
        enable: myGui.AddCheckbox("x30 y525 w100 h20", "鼠标自动移动"),
        interval: myGui.AddEdit("x160 y525 w40 h20", "1000")
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

    ; 创建各种控件
    CreateSkillControls()
    CreateMouseControls()
    CreateUtilityControls()
    ; 添加保存按钮
    myGui.AddButton("x30 y590 w100 h30", "保存设置").OnEvent("Click", SaveSettings)

    ; 添加状态栏
    statusBar := myGui.AddStatusBar(, "就绪")

    ; 显示GUI
    myGui.Show("w480 h660")

    ; 加载设置
    LoadSettings()

    ; 设置窗口事件处理
    myGui.OnEvent("Close", (*) => ExitApp())
    myGui.OnEvent("Escape", (*) => ExitApp())
}

; 初始化GUI
InitializeGUI()

; ========== 窗口管理 ==========
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


LoadGlobalHotkey() {
    global currentHotkey, hotkeyControl, myGui
    
    ; 跳过初始化时的空值
    if (hotkeyControl.Value = "")
        return
    
    try {
        ; 移除旧热键绑定
        if (currentHotkey != "") {
            if Hotkey(currentHotkey, ToggleMacro, "Off")
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

; ========== 定时器管理 ==========
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
    StartSingleTimer("dodge", utilityControls.dodge, PressDodge)
    StartSingleTimer("potion", utilityControls.potion, PressPotion)
    StartSingleTimer("forceMove", utilityControls.forceMove, PressForceMove)
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

    ; 重置所有按住模式的按键状态
    ResetAllHoldKeyStates()

    ; 重置鼠标按键状态
    ResetMouseButtonStates()

    DebugLog("已停止所有定时器并释放按键")
}

; ========== 按键功能实现 ==========
/**
 * 通用按键模式处理
 * @param {String} keyOrBtn - 键名或鼠标按钮名
 * @param {Integer} mode - 模式编号
 * @param {Object} pos - BUFF检测坐标对象（可选）
 * @param {String} type - "key" 或 "mouse"
 * @param {String} mouseBtn - 鼠标按钮名（如"left"/"right"，仅type为mouse时用）
 */
HandleKeyMode(keyOrBtn, mode, pos := "", type := "key", mouseBtn := "") {
    global shiftEnabled, buffThreshold

    static holdStates := Map()

    if (mode == SKILL_MODE_BUFF) {
        ; BUFF模式
        if (pos && IsSkillActive(pos.x, pos.y)) {
            DebugLog((type="mouse"?"鼠标":"技能") (mouseBtn?mouseBtn:"") "BUFF已激活，跳过")
            return
        }
        if (type = "mouse") {
            shiftEnabled ? SendWithShift(mouseBtn) : Click(mouseBtn)
        } else {
            shiftEnabled ? SendWithShift(keyOrBtn) : Send("{" keyOrBtn "}")
        }
        DebugLog("按下" (type="mouse"?"鼠标":"技能") (mouseBtn?mouseBtn:"") "(BUFF模式)")
    }
    else if (mode == SKILL_MODE_HOLD) {
        ; 按住模式
        if (!holdStates.Has(keyOrBtn) || !holdStates[keyOrBtn]) {
            if (shiftEnabled)
                Send "{Shift down}"
            if (type = "mouse") {
                Click "down " mouseBtn
            } else {
                Send "{" keyOrBtn " down}"
            }
            holdStates[keyOrBtn] := true
            DebugLog("按住" (type="mouse"?"鼠标":"技能") (mouseBtn?mouseBtn:""))
        }
    }
    else {
        ; 连点模式
        if (type = "mouse") {
            shiftEnabled ? SendWithShift(mouseBtn) : Click(mouseBtn)
        } else {
            shiftEnabled ? SendWithShift(keyOrBtn) : Send("{" keyOrBtn "}")
        }
        DebugLog("按下" (type="mouse"?"鼠标":"技能") (mouseBtn?mouseBtn:"") "(连点模式)")
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
 * 统一的按键发送函数
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
 * 卡移速功能
 * 按下r键、空格键，然后再按r键
 */
SendKeys() {
    Send "r"
    Sleep 10
    Send "{Space}"
    Sleep 500
    Send "r"
    DebugLog("执行卡移速")
}

; ========== 设置管理 ==========
/**
 * 保存设置到INI文件
 */
SaveSettings(*) {
    global statusBar
    settingsFile := A_ScriptDir "\settings.ini"

    try {
        ; 保存各类设置
        SaveSkillSettings(settingsFile)
        SaveMouseSettings(settingsFile)
        SaveUtilitySettings(settingsFile)
        LoadGlobalHotkey()

        statusBar.Text := "设置已保存"
        DebugLog("所有设置已保存到: " settingsFile)
    } catch as err {
        statusBar.Text := "保存设置失败: " err.Message
        DebugLog("保存设置失败: " err.Message)
    }
}

/**
 * 保存技能设置
 * @param {String} file - 设置文件路径
 */
SaveSkillSettings(file) {
    global skillControls
    section := "Skills"

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
 */
SaveMouseSettings(file) {
    global mouseControls, mouseAutoMove
    section := "Mouse"

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
 */
SaveUtilitySettings(file) {
    global utilityControls
    section := "Utility"

    IniWrite(utilityControls.dodge.enable.Value, file, section, "DodgeEnable")
    IniWrite(utilityControls.dodge.interval.Value, file, section, "DodgeInterval")
    IniWrite(utilityControls.potion.key.Value, file, section, "PotionKey")
    IniWrite(utilityControls.potion.enable.Value, file, section, "PotionEnable")
    IniWrite(utilityControls.potion.interval.Value, file, section, "PotionInterval")
    IniWrite(utilityControls.forceMove.key.Value, file, section, "ForceMoveKey")
    IniWrite(utilityControls.forceMove.enable.Value, file, section, "ForceMoveEnable")
    IniWrite(utilityControls.forceMove.interval.Value, file, section, "ForceMoveInterval")
    IniWrite(utilityControls.huoDun.key.Value, file, section, "HuoDunKey")
    IniWrite(utilityControls.dianMao.key.Value, file, section, "DianMaoKey")
    IniWrite(utilityControls.dianQiu.key.Value, file, section, "DianQiuKey")
    IniWrite(utilityControls.binDun.key.Value, file, section, "BinDunKey")
    IniWrite(hotkeyControl.Value, file, "Global", "StartStopKey")
    IniWrite(imagePauseMode.Value, file, "Global", "ImagePauseMode")
}

/**
 * 加载设置函数
 */

LoadSettings() {
    settingsFile := A_ScriptDir "\settings.ini"

    if !FileExist(settingsFile) {
        DebugLog("设置文件不存在，使用默认设置")
        return
    }

    try {
        ; 加载各类设置
        LoadSkillSettings(settingsFile)
        LoadMouseSettings(settingsFile)
        LoadUtilitySettings(settingsFile)
        LoadGlobalHotkey()

        DebugLog("所有设置已从文件加载: " settingsFile)
    } catch as err {
        DebugLog("加载设置出错: " err.Message)
    }
}

/**
 * 加载技能设置
 * @param {String} file - 设置文件路径
 */
LoadSkillSettings(file) {
    global skillControls, SKILL_MODE_CLICK

    Loop 5 {
        try {
            key := IniRead(file, "Skills", "Skill" A_Index "Key", A_Index)
            enabled := IniRead(file, "Skills", "Skill" A_Index "Enable", 1)
            interval := IniRead(file, "Skills", "Skill" A_Index "Interval", 20)
            mode := Integer(IniRead(file, "Skills", "Skill" A_Index "Mode", SKILL_MODE_CLICK))

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
 */
LoadMouseSettings(file) {
    global mouseControls, mouseAutoMove, mouseAutoMoveEnabled, SKILL_MODE_CLICK

    try {
        ; 加载左键设置
        mouseControls.left.enable.Value := IniRead(file, "Mouse", "LeftClickEnable", 1)
        mouseControls.left.interval.Value := IniRead(file, "Mouse", "LeftClickInterval", 80)
        leftMode := Integer(IniRead(file, "Mouse", "LeftClickMode", SKILL_MODE_CLICK))

        ; 加载右键设置
        mouseControls.right.enable.Value := IniRead(file, "Mouse", "RightClickEnable", 0)
        mouseControls.right.interval.Value := IniRead(file, "Mouse", "RightClickInterval", 300)
        rightMode := Integer(IniRead(file, "Mouse", "RightClickMode", SKILL_MODE_CLICK))

        ; 加载自动移动设置
        mouseAutoMove.enable.Value := IniRead(file, "Mouse", "MouseAutoMoveEnable", 0)
        mouseAutoMove.interval.Value := IniRead(file, "Mouse", "MouseAutoMoveInterval", 1000)
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
 */
LoadUtilitySettings(file) {
    global utilityControls

    try {
        utilityControls.dodge.enable.Value := IniRead(file, "Utility", "DodgeEnable", 0)
        utilityControls.dodge.interval.Value := IniRead(file, "Utility", "DodgeInterval", 20)

        utilityControls.potion.key.Value := IniRead(file, "Utility", "PotionKey", "q")
        utilityControls.potion.enable.Value := IniRead(file, "Utility", "PotionEnable", 0)
        utilityControls.potion.interval.Value := IniRead(file, "Utility", "PotionInterval", 3000)

        utilityControls.forceMove.key.Value := IniRead(file, "Utility", "ForceMoveKey", "``")
        utilityControls.forceMove.enable.Value := IniRead(file, "Utility", "ForceMoveEnable", 0)
        utilityControls.forceMove.interval.Value := IniRead(file, "Utility", "ForceMoveInterval", 50)
        utilityControls.huoDun.key.Value := IniRead(file, "Utility", "HuoDunKey", "2")
        utilityControls.dianMao.key.Value := IniRead(file, "Utility", "DianMaoKey", "1")
        utilityControls.dianQiu.key.Value := IniRead(file, "Utility", "DianQiuKey", "e")
        utilityControls.binDun.key.Value := IniRead(file, "Utility", "BinDunKey", "3")
        imagePauseMode.Value := IniRead(file, "Global", "ImagePauseMode", 2)
        savedHotkey := IniRead(file, "Global", "StartStopKey", "F1")
        hotkeyControl.Value := savedHotkey
    } catch as err {
        DebugLog("加载功能键设置出错: " err.Message)
    }
}

; ========== 宏控制功能 ==========
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
    global skillControls

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

    ; 重置所有按住模式的按键状态
    ResetAllHoldKeyStates()

    ; 重置鼠标按键状态
    ResetMouseButtonStates()

    DebugLog("已释放所有按键")
}

/**
 * 重置所有按住模式的按键状态
 */
ResetAllHoldKeyStates() {
    ; 使用全局静态变量来跟踪按键状态
    static keyStates := Map()

    ; 清空按键状态映射
    keyStates := Map()
    DebugLog("重置所有按住模式的按键状态")
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

; ========== 热键设置 ==========
#HotIf WinActive("ahk_class Diablo IV Main Window Class")



F3::{
    ; 确保从配置对象获取最新值
    dianQiuKey := utilityControls.dianQiu.key.Value
    huoDunKey := utilityControls.huoDun.key.Value
    dianMaoKey := utilityControls.dianMao.key.Value
    binDunKey := utilityControls.binDun.key.Value
    static sleepD := 2700
    sleepD := UpdateSleepD(sleepInput, sleepD)

    ; 添加错误处理
    try {
        ; 执行连招
        Send "{Blind}{" binDunKey "}"  ; 使用Blind模式保持Shift状态
        Sleep 75
        Loop 4 {
            Send "{Blind}{" dianQiuKey "}"
            Sleep 750
        }
        Send "{Blind}{" huoDunKey "}"
        Sleep sleepD  ; 使用滑块控制的值
        Send "{Blind}{" dianMaoKey "}"
        Sleep 550
        ToggleMacro()
    } catch as err {
        DebugLog("F3连招出错: " err.Message)
        TrayTip "连招错误", "请检查技能键配置", 3
    }
}

F4::SendKeys()

Tab::{
    global isRunning, isPaused

    ; 发送原始Tab键
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

    ; 发送原始Tab键
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

; ========== 定时器控制 ==========
StartWindowCheckTimer() {
    SetTimer CheckWindow, 100
}
StopWindowCheckTimer() {
    SetTimer CheckWindow, 0
}

; ========== 识图自动暂停/启动功能 ==========
/**
 * 检查指定坐标的红色分量是否大于绿色100
 * @returns {Boolean} - 是否触发
 */ 

StartImagePauseTimer() {
    SetTimer AutoPauseByColor, 50
}
StopImagePauseTimer() {
    SetTimer AutoPauseByColor, 0
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
            PixelGetColor(x1, y1, "RGB"),
            PixelGetColor(x1, y2, "RGB"),
            PixelGetColor(x2, y1, "RGB"),
            PixelGetColor(x2, y2, "RGB")
        ]

        ; 统计满足红色条件的点数
        hitCount := 0
        for color in colors {
            r := (color >> 16) & 0xFF, g := (color >> 8) & 0xFF, b := color & 0xFF
            if (r > 100 && g < 60 && b < 60)
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
    global isRunning, isPaused, imagePauseMode
    ; 仅在启用时才执行
    if (!isRunning || imagePauseMode.Value != 1)
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

; ========== 功能键实现 ==========
/**
 * 按下翻滚键(空格)
 */
PressDodge() {
    global isRunning, isPaused, utilityControls, shiftEnabled

    if (isRunning && !isPaused && utilityControls.dodge.enable.Value = 1) {
        if (shiftEnabled) {
            SendWithShift("Space")
        } else {
            Send "{Space}"
        }
        DebugLog("按下翻滚键")
    }
}

/**
 * 按下喝药键
 */
PressPotion() {
    global isRunning, isPaused, utilityControls, shiftEnabled

    if (isRunning && !isPaused && utilityControls.potion.enable.Value = 1) {
        key := utilityControls.potion.key.Value
        if key != "" {
            if (shiftEnabled) {
                SendWithShift(key)
            } else {
                Send "{" key "}"
            }
            DebugLog("按下喝药键: " key)
        }
    }
}

/**
 * 按下强制移动键
 */
PressForceMove() {
    global isRunning, isPaused, utilityControls, shiftEnabled

    if (isRunning && !isPaused && utilityControls.forceMove.enable.Value = 1) {
        key := utilityControls.forceMove.key.Value
        if key != "" {
            if (shiftEnabled) {
                SendWithShift(key)
            } else {
                Send "{" key "}"
            }
            DebugLog("按下强制移动键: " key)
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
            color := PixelGetColor(x, y, "RGB")
            r := (color >> 16) & 0xFF
            g := (color >> 8) & 0xFF
            b := color & 0xFF
            return (g > b + buffThreshold.Value)
        } catch
            Sleep 5
    }
    DebugLog("检测技能状态失败: 多次尝试无效")
    return false
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

