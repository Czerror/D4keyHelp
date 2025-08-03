#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority "High"

global DEBUG := false
global debugLogFile := A_ScriptDir "\debugd4.log"

/**
 * GUI管理类
 * 负责创建和管理暗黑4助手的所有GUI元素
 * @version 1.0.0
 * @author Archenemy
 */
class GUIManager {
    static myGui := ""          ; 主GUI窗口
    static statusBar := ""      ; 状态栏
    static tabControl := ""     ; 标签页控件
    static hotkeyText := ""     ; 启动热键文本
    static statusText := ""     ; 状态文本
    static startkey := Map()    ; 启动热键配置
    static cSkill := Map()      ; 技能控件
    static mSkill := Map()      ; 鼠标控件
    static uCtrl := Map()       ; 用户控件
    static RunMod := ""         ; 运行模式
    static skillMod := []       ; 技能模式
    static profileName := ""    ; 配置文件
    
    /**
     * 初始化GUI界面
     * 创建主窗口、托盘菜单和所有控件
     */
    static Initialize() {
        this.myGui := Gui("", "暗黑4助手 v6.0")
        this.myGui.BackColor := "FFFFFF"
        this.myGui.SetFont("s10", "Microsoft YaHei UI")
        this.InitializeTrayMenu()
        this.myGui.OnEvent("Escape", (*) => this.myGui.Minimize())
        this.myGui.OnEvent("Close", (*) => (
            ConfigManager.SaveProfileFromUI(),
            ExitApp()
        ))
        this.CreateMainFrame()
        this.CreateAllControls()
        this.statusBar := this.myGui.AddStatusBar(, "就绪")
        this.myGui.Show("w485 h535")
        ConfigManager.Initialize()
    }
    
    /**
     * 初始化系统托盘菜单
     */
    static InitializeTrayMenu() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("显示主界面", (*) => this.myGui.Show())
        A_TrayMenu.Add()
        A_TrayMenu.Add("开始/停止宏", (*) => MacroController.ToggleMacro())
        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => (
            ConfigManager.SaveProfileFromUI(),
            ExitApp()
        ))
        A_TrayMenu.Default := "显示主界面"
    }
    
    /**
     * 创建主界面框架
     */
    static CreateMainFrame() {
        this.hotkeyText := this.myGui.AddGroupBox("x10 y10 w280 h120", "启动热键: 自定义 - F1")
        this.startkey := Map(
            "mode", this.myGui.AddDropDownList("x310 y65 w65 h90 Choose1", ["自定义", "侧键1", "侧键2"]),
            "userkey", [
                {key: "F1", input: true},
                {key: "XButton1", input: false},
                {key: "XButton2", input: false}
            ],
            "guiHotkey", this.myGui.AddHotkey("x380 y65 w90 h22")
        )
        this.startkey["mode"].OnEvent("Change", (*) => (
            HotkeyManager.LoadStartHotkey()
        ))
        this.startkey["guiHotkey"].OnEvent("Change", (*) => (
            (this.startkey["guiHotkey"].Value = "") && (this.startkey["guiHotkey"].Value := "F1"),
            this.startkey["userkey"][1].key := this.startkey["guiHotkey"].Value,
            HotkeyManager.LoadStartHotkey()
        ))
        this.myGui.AddGroupBox("x300 y10 w175 h120", "配置管理")
        this.profileName := this.myGui.AddComboBox("x310 y30 w160 h120 Choose1", ["默认"])
        this.profileName.OnEvent("Change", (ctrl, *) => (
            ConfigManager.LoadSelectedProfile(ctrl)
        ))
        this.myGui.AddButton("x310 y100 w60 h25", "保存").OnEvent("Click", (*) => (
            ConfigManager.SaveProfileFromUI()
        ))
        this.myGui.AddButton("x410 y100 w60 h25", "删除").OnEvent("Click", (*) => (
            ConfigManager.DeleteProfileFromUI()
        ))
        this.tabControl := this.myGui.AddTab("x10 y135 w465 h360 Choose1", ["战斗模式", "工具模式"])
        this.tabControl.UseTab(2)
    }
    
    /**
     * 创建所有控件
     */
    static CreateAllControls() {
        this.cSkill := Map()
        this.mSkill := Map()
        this.uCtrl := Map()
        this.skillMod := ["连点", "BUFF", "按住", "资源"]
        
        this.tabControl.UseTab(1)
        
        ; 运行模式选择
        this.CreateRunningControls()
        ; 技能控件
        this.CreateSkillControls()
        ; 自动启停区域
        this.CreateAutoStopControls()
        ; 工具模式
        this.tabControl.UseTab(2)
        ; 精造模式控件
        this.CreatePerfectModeControls()
        ; 窗口置顶控件
        this.CreateWindowTopControls()
        
        this.tabControl.UseTab()
    }
    
    /**
     * 创建运行模式控件
     */
    static CreateRunningControls() {
        this.statusText := this.myGui.AddText("x30 y35 w80 h20", "状态: 未运行")
        this.myGui.AddButton("x30 y63 w85 h30", "开始/停止").OnEvent("Click", (*) => (
            MacroController.ToggleMacro(),
            MacroController.TogglePause("window", true)
        ))
        this.myGui.AddText("x180 y103 w30 h20", "模式: ")
        this.RunMod := this.myGui.AddDropDownList("x215 y100 w65 h60 Choose1", ["多线程", "单线程"])
        
        ; D4only选项
        this.uCtrl["D4only"] := Map(
            "text", this.myGui.AddText("x30 y103 w110 h20", "仅在暗黑4中使用:"),
            "enable", this.myGui.AddCheckbox("x145 y104 w18 h18", "1")
        )
    }
    
    /**
     * 创建技能控件
     */
    static CreateSkillControls() {

        this.myGui.AddText("x35 y160 w100 h20", "技能与按键")
        this.myGui.AddText("x133 y160 w60 h20", "启用")
        this.myGui.AddText("x180 y160 w80 h20", "间隔(毫秒)")
        this.myGui.AddText("x252 y160 w80 h20", "运行策略")
        
        loop 5 {
            yPos := 190 + (A_Index - 1) * 30
            
            ; 技能标签
            this.myGui.AddText("x30 y" yPos " w40 h20", "技能" A_Index ":")
            
            this.cSkill[A_Index] := Map(
                "key", this.myGui.AddHotkey("x80 y" yPos " w30 h20", A_Index),
                "enable", this.myGui.AddCheckbox("x125 y" yPos " w45 h20", "启用"),
                "interval", this.myGui.AddEdit("x185 y" yPos " w50 h20", "20"),
                "mode", this.myGui.AddDropDownList("x250 y" yPos-2 " w60 h120 Choose1", this.skillMod)
            )
        }
        
        ; 左键配置
        this.mSkill["left"] := Map(
            "text", this.myGui.AddText("x30 y340 w40 h20", "左键:"),
            "key", "LButton",  ; 固定键值
            "enable", this.myGui.AddCheckbox("x125 y340 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y340 w50 h20", "80"),
            "mode", this.myGui.AddDropDownList("x250 y338 w60 h120 Choose1", this.skillMod)
        )
        
        this.mSkill["right"] := Map(
            "text", this.myGui.AddText("x30 y370 w40 h20", "右键:"),
            "key", "RButton",  ; 固定键值
            "enable", this.myGui.AddCheckbox("x125 y370 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y370 w50 h20", "300"),
            "mode", this.myGui.AddDropDownList("x250 y368 w60 h120 Choose1", this.skillMod)
        )
        
        ; 药水功能
        this.uCtrl["potion"] := Map(
            "text", this.myGui.AddText("x30 y400 w35 h20", "药水:"),
            "key", this.myGui.AddHotkey("x65 y400 w45 h20", "q"),
            "enable", this.myGui.AddCheckbox("x125 y400 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y400 w50 h20", "3000"),
            "mode", this.myGui.AddDropDownList("x250 y398 w60 h120 Choose1", this.skillMod)
        )
        this.uCtrl["potion"]["mode"].Enabled := false
        
        ; 强移功能
        this.uCtrl["forceMove"] := Map(
            "text", this.myGui.AddText("x30 y430 w35 h20", "强移:"),
            "key", this.myGui.AddHotkey("x65 y430 w45 h20", "e"),
            "enable", this.myGui.AddCheckbox("x125 y430 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y430 w50 h20", "50"),
            "mode", this.myGui.AddDropDownList("x250 y428 w60 h120 Choose1", this.skillMod)
        )
        this.uCtrl["forceMove"]["mode"].Enabled := false
        
        ; 闪避功能
        this.uCtrl["dodge"] := Map(
            "text", this.myGui.AddText("x30 y460 w35 h20", "闪避:"),
            "key", this.myGui.AddHotkey("x65 y460 w45 h20", "Space"),
            "enable", this.myGui.AddCheckbox("x125 y460 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y460 w50 h20", "20"),
            "mode", this.myGui.AddDropDownList("x250 y458 w60 h120 Choose1", this.skillMod)
        )
        ; 闪避键空值保护
        this.uCtrl["dodge"]["key"].OnEvent("Change", (*) => (
            (this.uCtrl["dodge"]["key"].Value = "") && (this.uCtrl["dodge"]["key"].Value := "Space")
        ))
        this.uCtrl["dodge"]["mode"].Enabled := false
        
        ; 辅助功能
        this.uCtrl["shift"] := Map(   ; Shift键辅助
            "text", this.myGui.AddText("x325 y400 w60 h20", "按住Shift:"),
            "enable", this.myGui.AddCheckbox("x395 y400 w20 h20")
        )
        
        this.uCtrl["random"] := Map(  ; 随机延迟
            "text", this.myGui.AddText("x325 y430 w60 h20", "随机延迟:"),
            "enable", this.myGui.AddCheckbox("x395 y430 w20 h20"),
            "max", this.myGui.AddEdit("x420 y430 w45 h20", "10")
        )
        
        this.uCtrl["random"]["max"].OnEvent("LoseFocus", (*) => (
            UtilityHelper.LimitEditValue(this.uCtrl["random"]["max"], 1, 10)))
    }
    
    /**
     * 创建自动启停控件
     */
    static CreateAutoStopControls() {
        this.myGui.AddGroupBox("x325 y160 w140 h230", "启停管理")
        
        ; 双击暂停
        this.uCtrl["dcPause"] := Map(
            "text", this.myGui.AddText("x335 y190 w60 h20", "双击暂停:"),
            "enable", this.myGui.AddCheckbox("x400 y190 w20 h20"),
            "interval", this.myGui.AddEdit("x420 y190 w20 h20", "2"),
            "text2", this.myGui.AddText("x443 y190 w18 h20", "秒")
        )
        
        this.uCtrl["dcPause"]["interval"].OnEvent("LoseFocus", (*) => (
            UtilityHelper.LimitEditValue(this.uCtrl["dcPause"]["interval"], 1, 3)))
        
        ; 血条检测
        this.uCtrl["ipPause"] := Map(
            "text", this.myGui.AddText("x335 y220 w60 h20", "血条检测:"),
            "enable", this.myGui.AddCheckbox("x400 y220 w20 h20"),
            "interval", this.myGui.AddEdit("x420 y220 w40 h20", "50")
        )
        ; 输入验证
        this.uCtrl["ipPause"]["interval"].OnEvent("LoseFocus", (*) => (
            UtilityHelper.LimitEditValue(this.uCtrl["ipPause"]["interval"], 10, 1000)))
        
        this.uCtrl["tabPause"] := Map(
            "text", this.myGui.AddText("x335 y250 w60 h20", "界面检测:"),
            "enable", this.myGui.AddCheckbox("x400 y250 w20 h20"),
            "interval", this.myGui.AddEdit("x420 y250 w40 h20", "50")
        )
        ; 输入验证
        this.uCtrl["tabPause"]["interval"].OnEvent("LoseFocus", (*) => (
            UtilityHelper.LimitEditValue(this.uCtrl["tabPause"]["interval"], 10, 1000)))
        
        this.uCtrl["xy"] := Map(
            "text", this.myGui.AddText("x335 y280 w60 h20", "偏移:"),
            "text2", this.myGui.AddText("x375 y280 w15 h20", "X"),
            "x", this.myGui.AddEdit("x390 y278 w25 h20", "0"),
            "text3", this.myGui.AddText("x420 y280 w15 h20", "Y"),
            "y", this.myGui.AddEdit("x435 y278 w25 h20", "0")
        )
        ; 输入验证
        this.uCtrl["xy"]["x"].OnEvent("LoseFocus", (*) => (
            this.uCtrl["xy"]["x"].Value := Integer(this.uCtrl["xy"]["x"].Value),
            UtilityHelper.LimitEditValue(this.uCtrl["xy"]["x"], -3, 3)))
        this.uCtrl["xy"]["y"].OnEvent("LoseFocus", (*) => (
            this.uCtrl["xy"]["y"].Value := Integer(this.uCtrl["xy"]["y"].Value),
            UtilityHelper.LimitEditValue(this.uCtrl["xy"]["y"], -3, 3)))
        
        this.uCtrl["mouseAutoMove"] := Map(
            "text", this.myGui.AddText("x325 y460 w60 h20", "鼠标自移:"),
            "enable", this.myGui.AddCheckbox("x395 y460 w20 h20"),
            "interval", this.myGui.AddEdit("x420 y460 w45 h20", "1000"),
            "currentPoint", 1  ; 移动点位标记
        )
    }
    
    /**
     * 创建精造模式控件
     */
    static CreatePerfectModeControls() {
        this.uCtrl["PM"] := Map(
            "mod", this.myGui.AddDropDownList("x90 y178 w60 h60 Choose1", ["暗金", "传奇"]),
            "trueTime", this.myGui.AddEdit("x270 y178 w40 h20", "120"),
            "modtime", this.myGui.AddEdit("x390 y178 w40 h20", "0"),
            "time", 0,
            "time1", this.myGui.AddEdit("x90 y210 w300 h20", "0"),
            "timeX", this.myGui.AddEdit("x90 y240 w300 h20", "0"),
            "correct", this.myGui.AddEdit("x120 y270 w20 h20", "1"),
            "xiuValue", this.myGui.AddEdit("x120 y300 w20 h20", "1")
        )
        
        this.uCtrl["PM"]["time1"].Enabled := false
        this.uCtrl["PM"]["timeX"].Enabled := false
        this.uCtrl["PM"]["correct"].OnEvent("LoseFocus", (*) => (
            UtilityHelper.LimitEditValue(this.uCtrl["PM"]["correct"], 1, 5)
        ))
        this.uCtrl["PM"]["xiuValue"].OnEvent("LoseFocus", (*) => (
            UtilityHelper.LimitEditValue(this.uCtrl["PM"]["xiuValue"], 1, 5)
        ))
        
        this.myGui.AddText("x30 y180 w60 h20", "精造模式:")
        this.myGui.AddText("x180 y180 w90 h20", "窗口周期(ms):")
        this.myGui.AddText("x330 y180 w60 h20", "偏差修正:")
        this.myGui.AddText("x30 y210 w60 h20", "记录时间:")
        this.myGui.AddText("x30 y240 w60 h20", "时间偏差:")
        this.myGui.AddText("x30 y270 w90 h20", "实际命中词条:")
        this.myGui.AddText("x30 y300 w90 h20", "期望命中词条:")
        this.myGui.AddButton("x30 y330 w60 h40", "开始").OnEvent("Click", (*) => PerfectCraftingManager.ExecuteStart())
        this.myGui.AddButton("x110 y330 w60 h40", "继续").OnEvent("Click", (*) => PerfectCraftingManager.ExecuteNext())
        this.myGui.AddButton("x200 y330 w60 h40", "重置").OnEvent("Click", (*) => PerfectCraftingManager.ExecuteReset())
    }
    
    /**
     * 创建窗口置顶控件
     */
    static CreateWindowTopControls() {
        this.uCtrl["alwaysOnTop"] := Map(
            "text", this.myGui.AddText("x30 y98 w60 h20", "窗口置顶:"),
            "enable", this.myGui.AddCheckbox("x90 y100 w15 h15")
        )

        this.uCtrl["alwaysOnTop"]["enable"].OnEvent("Click", (*) => UtilityHelper.ToggleAlwaysOnTop())
    }

    /**
     * 更新状态显示
     * @param {String} status - 主状态文本
     * @param {String} barText - 状态栏文本
     */
    static UpdateStatus(status, barText) {
        if (status = "已暂停") {
            this.statusText.Value := "状态: 已暂停"
            this.statusBar.Text := "宏已暂停 - " barText
        } else {
            this.statusText.Value := status ? ("状态: " status) : "状态: 运行中"
            this.statusBar.Text := barText
        }
    }
}

/**
 * 热键管理类
 * 负责热键的加载、更新和文本显示管理
 * @version 1.0.0
 * @author Archenemy
 */
class HotkeyManager {
    /**
     * 加载全局热键
     */
    static LoadStartHotkey() {
        static currentHotkey := ""
        
        mode := GUIManager.startkey["mode"].Value
        GUIManager.startkey["guiHotkey"].Enabled := GUIManager.startkey["userkey"][mode].input
        newHotkey := ""
        
        switch mode {
            case 1:
                newHotkey := GUIManager.startkey["userkey"][1].key
            case 2:
                newHotkey := GUIManager.startkey["userkey"][2].key
            case 3:
                newHotkey := GUIManager.startkey["userkey"][3].key
        }
        
        try {
            if (currentHotkey != "" && currentHotkey != newHotkey) {
                try {
                    Hotkey(currentHotkey, "Off")
                } catch {
                }
            }
            
            if (newHotkey != currentHotkey) {
                Hotkey(newHotkey, (*) => MacroController.ToggleMacro(), "On")
                currentHotkey := newHotkey
                if (GUIManager.statusBar != "") {
                    GUIManager.statusBar.Text := "热键已更新: " newHotkey
                }
                this.UpdateHotkeyText()
            }
        } catch {
        }
    }
    
    /**
     * 更新热键文本显示
     */
    static UpdateHotkeyText() {
        if (GUIManager.startkey == "" || GUIManager.hotkeyText == "")
            return
            
        try {
            mode := GUIManager.startkey["mode"].Value
            modeNames := ["自定义", "鼠标侧键1", "鼠标侧键2"]
            modeName := modeNames[mode]
            
            currentKey := ""
            switch mode {
                case 1:
                    currentKey := GUIManager.startkey["userkey"][1].key
                case 2:
                    currentKey := "XButton1"
                case 3:
                    currentKey := "XButton2"
            }
            
            displayText := "启动热键: " . modeName . " - " . currentKey
            GUIManager.hotkeyText.Text := displayText
            
        } catch {
            GUIManager.hotkeyText.Text := "启动热键: 自定义 - F1"
        }
    }
}

/**
 * 工具类
 * 提供各种实用工具函数
 * @version 1.0.0
 * @author Archenemy
 */
class UtilityHelper {
    /**
     * 限制编辑框数值范围
     * @param {Object} ctrl - 编辑框控件
     * @param {Number} min - 最小值
     * @param {Number} max - 最大值
     */
    static LimitEditValue(ctrl, min, max) {
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
    static ToggleAlwaysOnTop() {
        try {
            if (GUIManager.uCtrl["alwaysOnTop"]["enable"].Value = 1) {
                WinSetAlwaysOnTop(true, GUIManager.myGui.Hwnd)
            } else {
                WinSetAlwaysOnTop(false, GUIManager.myGui.Hwnd)
            }
        } catch as err {
            OutputDebug "切换窗口置顶状态失败: " err.Message
        }
    }

    static MoveMouseFunc := 0 ; 鼠标移动定时器

    /**
     * 启动鼠标自动移动
     */
    static StartMove(){
        this.StopMove()
        if(this.MoveMouseFunc == 0) {
            this.MoveMouseFunc := () => this.MoveMouse()
        }
        interval := Integer(GUIManager.uCtrl["mouseAutoMove"]["interval"].Value)
        if (interval > 0) {
            UtilityHelper.MoveMouse()
            SetTimer(this.MoveMouseFunc, interval)
        }
    }

    /**
     * 停止鼠标自动移动
     */
    static StopMove(){
        if (this.MoveMouseFunc != 0) {
            SetTimer(this.MoveMouseFunc, 0)
            this.MoveMouseFunc := 0
        }
    }

    /**
     * 鼠标自动移动函数
     */
    static MoveMouse() {
        allcoords := WindowManager.GetAllCoord()

        try {
            if (!GUIManager.uCtrl["mouseAutoMove"].Has("currentPoint"))
                GUIManager.uCtrl["mouseAutoMove"]["currentPoint"] := 1

            currentIndex := GUIManager.uCtrl["mouseAutoMove"]["currentPoint"]

            if (currentIndex < 1 || currentIndex > 6)
                currentIndex := 1

            currentPoint := allcoords["mouse_move_" currentIndex]
            MouseMove(currentPoint.x, currentPoint.y, 0)

            GUIManager.uCtrl["mouseAutoMove"]["currentPoint"] := Mod(currentIndex, 6) + 1

        }
    }
    
    /**
     * 将数组元素用指定分隔符连接
     * @param {Array} arr - 要连接的数组
     * @param {String} delimiter - 分隔符
     * @returns {String} - 连接后的字符串
     */
    static Join(arr, delimiter := ",") {
        result := ""
        for i, v in arr {
            result .= (i > 1 ? delimiter : "") . v
        }
        return result
    }
    
    /**
     * 调试日志记录函数
     * @param {String} message - 要记录的消息
     */
    static DebugLog(message) {
        if DEBUG {
            try {
                logFile := debugLogFile
                maxSize := 1024 * 1024

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
                FileAppend(timestamp . " - " . message . "`n", logFile)
            } catch as err {
                OutputDebug "日志写入失败: " err.Message
            }
        }
    }
}

/**
 * 宏控制类
 * 负责管理暗黑4助手的宏控制逻辑
 * @version 1.0.0
 * @author Archenemy
 */
class MacroController {
    ; 静态属性
    static isRunning := false          ; 宏是否运行中
    static pauseConfig := Map(         ; 暂停配置
        "window", {state: false, name: "窗口切换"},
        "blood", {state: false, name: "血条检测"},
        "tab", {state: false, name: "TAB界面"},
        "enter", {state: false, name: "对话框"},
        "doubleClick", {state: false, name: "双击暂停"}
    )
    
    /**
     * 核心控制函数 - 切换宏的启动/停止状态
     */
    static ToggleMacro(*) {
        this.isRunning := !this.isRunning
        
        if (this.isRunning) {
            PauseDetector.ManageTimers(true)
            this.StartAllTimers()
            GUIManager.UpdateStatus("已启动", "宏已启动")
        } else {
            PauseDetector.ManageTimers(false)
            this.StopAllTimers()
            for reason, config in this.pauseConfig {
                config.state := false
            }
            GUIManager.UpdateStatus("已停止", "宏已停止")
        }
    }
    
    /**
     * 核心启停函数 - 根据指定原因切换暂停状态
     * @param {String} reason - 暂停原因
     * @param {Boolean} state - 暂停状态
     */
    static TogglePause(reason := "", state := unset) {
        if (!this.isRunning) {
            return
        }
        
        prevPausedReasons := []
        if (this.isRunning) {
            for pauseReason, config in this.pauseConfig {
                if (config.state) {
                    prevPausedReasons.Push(config.name)
                }
            }
        }
        prev := (prevPausedReasons.Length > 0)
        
        this.pauseConfig[reason].state := state
        
        currentPausedReasons := []
        if (this.isRunning) {
            for pauseReason, config in this.pauseConfig {
                if (config.state) {
                    currentPausedReasons.Push(config.name)
                }
            }
        }
        now := (currentPausedReasons.Length > 0)
        
        if (now != prev) {
            if (now) {
                this.StopAllTimers()
            } else {
                this.StartAllTimers()
            }
        }
        
        if (now) {
            reasonsText := UtilityHelper.Join(currentPausedReasons, " + ")
            GUIManager.UpdateStatus("已暂停", reasonsText)
        } else {
            if (this.isRunning) {
                GUIManager.UpdateStatus("运行中", "宏已启动")
            } else {
                GUIManager.UpdateStatus("已停止", "宏已停止")
            }
        }
    }
    
    /**
     * 启动所有定时器
     */
    static StartAllTimers() {

        for reason, config in this.pauseConfig {
            config.state := false
        }
        
        if (GUIManager.uCtrl["D4only"]["enable"].Value) {
            WindowManager.GetAllCoord()
            if (GUIManager.uCtrl["mouseAutoMove"]["enable"].Value) {
                UtilityHelper.StartMove()
            }
        }
        
        if (GUIManager.RunMod.Value = 2) {
            KeyQueueManager.StartQueue()
        }
        
        loop 5 {
            if (GUIManager.cSkill[A_Index]["enable"].Value) {
                KeyHandler.PressKeyCallback("skill", A_Index)
            }
        }
        
        for mouseBtn in ["left", "right"] {
            if (GUIManager.mSkill[mouseBtn]["enable"].Value) {
                KeyHandler.PressKeyCallback("mouse", mouseBtn)
            }
        }
        
        for uSkillId in ["dodge", "potion", "forceMove"] {
            if (GUIManager.uCtrl[uSkillId]["enable"].Value) {
                KeyHandler.PressKeyCallback("uSkill", uSkillId)
            }
        }
    }
    
    /**
     * 停止所有定时器
     */
    static StopAllTimers() {
        if (GUIManager.RunMod.Value = 2) {
            KeyQueueManager.StopQueue()
        }
        KeyHandler.ClearAllTimers()
        if (GUIManager.uCtrl["mouseAutoMove"]["enable"].Value) {
            UtilityHelper.StopMove()
        }
        this.ReleaseAllKeys()
    }
    
    /**
     * 释放所有按键
     */
    static ReleaseAllKeys() {
        KeyHandler.ResetHoldStates()

        if (GUIManager.uCtrl["shift"]["enable"].Value) {
            Send "{Blind}{Shift up}"
        }
    }
}

/**
 * 按键处理类
 * 统一管理所有按键相关的处理逻辑
 * @version 1.0.0
 * @author Archenemy
 */
class KeyHandler {
    ; 静态属性 - 存储按键状态
    static holdStates := Map()          ; 按住状态缓存
    static skillTimers := Map()         ; 技能定时器
    static coordCache := Map()          ; 技能坐标缓存

    /**
     * 检查是否为鼠标按键
     * @param {Object} keyData - 按键数据
     * @returns {Boolean} - 是否为鼠标按键
     */
    static IsMouse(keyData) {
        return InStr(keyData.uniqueKey, "mouse:") == 1
    }

    /**
     * 通用按键处理
     * @param {Object} keyData - 按键数据
     */
    static HandleKeyMode(keyData) {
        uniqueKey := keyData.uniqueKey
        shiftEnabled := GUIManager.uCtrl["shift"]["enable"].Value

        switch keyData.mode {
            case 2: ; BUFF模式
                if (this.IsSkillActive(keyData.id)) {
                    return
                } else {
                    this._ExecuteKey(keyData, shiftEnabled)
                }
            case 3: ; 按住模式
                if (!this.holdStates.Has(uniqueKey) || !this.holdStates[uniqueKey]) {
                    this.holdStates[uniqueKey] := true
                    
                    if (this.IsMouse(keyData)) {
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
                if (this.IsResourceSufficient()) {
                    this._ExecuteKey(keyData, shiftEnabled)
                }

            default: ; 连点模式
                this._ExecuteKey(keyData, shiftEnabled)
        }
    }

    /**
     * 执行按键操作的内部方法
     * @param {Object} keyData - 按键数据
     * @param {Boolean} shiftEnabled - 是否启用Shift
     */
    static _ExecuteKey(keyData, shiftEnabled) {
        if (this.IsMouse(keyData)) {

            if (shiftEnabled) {
                Send "{Blind}{Shift down}"
                Click(keyData.key)
                Send "{Blind}{Shift up}"
            } else {
                Click(keyData.key)
            }
        } else {
            ; 键盘按键处理
            if (shiftEnabled) {
                Send "{Blind}{Shift down}"
                Send("{" keyData.key "}")
                Send "{Blind}{Shift up}"
            } else {
                Send("{" keyData.key "}")
            }
        }
    }

    /**
     * 通用按键回调函数
     * @param {String} category - 类别 ("skill", "mouse", "uSkill")
     * @param {String|Integer} id - 标识符
     */
    static PressKeyCallback(category, id) {

        config := this._GetConfig(category, id)
        if (!config)
            return

        keyData := this._BuildKeyData(category, id, config)
        if (!keyData)
            return

        if (this.skillTimers.Has(keyData.uniqueKey)) {
            try {
                SetTimer(this.skillTimers[keyData.uniqueKey], 0)
            } catch {
            }
            this.skillTimers.Delete(keyData.uniqueKey)
        }

        if (GUIManager.RunMod.Value == 1) {
            timerFunc := () => this.HandleKeyMode(keyData)
            this.skillTimers[keyData.uniqueKey] := timerFunc
            SetTimer(timerFunc, keyData.interval)
        } else if (GUIManager.RunMod.Value == 2) {
            KeyQueueManager.EnqueueKey(keyData)
        }
    }

    /**
     * 获取配置信息
     * @param {String} category - 类别
     * @param {String|Integer} id - 标识符
     * @returns {Object|Boolean} - 配置对象或false
     */
    static _GetConfig(category, id) {
        switch category {
            case "skill":
                return (GUIManager.cSkill.Has(id) && GUIManager.cSkill[id]["enable"].Value) 
                    ? GUIManager.cSkill[id] 
                    : false
            case "mouse":
                return (GUIManager.mSkill.Has(id) && GUIManager.mSkill[id]["enable"].Value) 
                    ? GUIManager.mSkill[id] 
                    : false
            case "uSkill":
                return (GUIManager.uCtrl.Has(id) && GUIManager.uCtrl[id]["enable"].Value) 
                    ? GUIManager.uCtrl[id] 
                    : false
            default:
                return false
        }
    }

    /**
     * 构建按键数据对象
     * @param {String} category - 类别
     * @param {String|Integer} id - 标识符
     * @param {Object} config - 配置对象
     * @returns {Object|Boolean} - 按键数据对象或false
     */
    static _BuildKeyData(category, id, config) {
        isMouse := (category = "mouse")
        key := isMouse ? id : config["key"].Value
        mode := config.Has("mode") ? config["mode"].Value : 1
        interval := Integer(config["interval"].Value)
        coord := this.GetSkillCoords(id)

        uniqueKey := (isMouse ? "mouse:" : "key:") . key

        keyData := {
            key: key,                         ; 目标键/按钮
            mode: mode,                       ; 操作模式
            interval: interval,               ; 间隔时间（毫秒）
            uniqueKey: uniqueKey,             ; 唯一键（兼定时器键）
            id: id,                           ; 标识符（BUFF模式需要）
            coord: coord
        }
     
        ; 模式调整
        keyData.mode := (!GUIManager.uCtrl["D4only"]["enable"].Value && (keyData.mode == 2 || keyData.mode == 4)) 
            ? 1 
            : keyData.mode

        ; 随机间隔调整
        keyData.interval += GUIManager.uCtrl["random"]["enable"].Value 
            ? Random(1, GUIManager.uCtrl["random"]["max"].Value) 
            : 0

        return keyData
    }

    /**
     * 检测技能激活状态
     * @param {String|Integer} skillId - 技能标识符
     * @param {Object} coord - 预计算的坐标对象
     * @returns {Boolean} - 技能是否激活
     */
    static IsSkillActive(skillId, coord := unset) {
        try {
            ; 如果没有传入坐标，则计算坐标
            if (!IsSet(coord) || !coord) {
                coord := this.GetSkillCoords(skillId)
            }

            loop 2 {
                try {
                    color := ColorDetector.GetPixelRGB(coord.x, coord.y, false)
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
    static GetSkillCoords(skillId) {
        try {
            cacheKey := String(skillId)
            if (this.coordCache.Has(cacheKey))
                return this.coordCache[cacheKey]
                
            windowInfo := WindowManager.GetWindowInfo()
            coord := false
            
            if (Type(skillId) = "Integer" && skillId >= 1 && skillId <= 6) {
                coord := WindowManager.ConvertCoord({
                    x: 1550 + 127 * (skillId - 1), 
                    y: 1940
                }, windowInfo)
            }
            else if (skillId = "left") {
                coord := WindowManager.ConvertCoord({
                    x: 1550 + 127 * 4,  ; skillId 5
                    y: 1940
                }, windowInfo)
            }
            else if (skillId = "right") {
                coord := WindowManager.ConvertCoord({
                    x: 1550 + 127 * 5,  ; skillId 6
                    y: 1940
                }, windowInfo)
            }
            
            if (coord) {
                this.coordCache[cacheKey] := coord
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
    static IsResourceSufficient() {
        allcoords := WindowManager.GetAllCoord()
        coord := allcoords["resource_bar"]

        loop 5 {
            try {
                color := ColorDetector.GetPixelRGB(coord.x, coord.y + (A_Index - 1), false)
                if (!ColorDetector.IsGray(color))  ; 如果不是灰色，认为资源充足
                    return true
            } catch {
                Sleep 5
            }
        }
        return false
    }

    /**
     * 清理所有定时器
     */
    static ClearAllTimers() {
        for timerKey, timerFunc in this.skillTimers {
            try {
                SetTimer(timerFunc, 0)
            } catch {
            }
        }
        this.skillTimers.Clear()
    }

    /**
     * 重置按住状态
     */
    static ResetHoldStates() {
        if (this.holdStates.Count > 0) {
            for uniqueKey, _ in this.holdStates {
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
                } catch {
                    ; 忽略释放错误
                }
            }
        }
        this.holdStates.Clear()
    }

    /**
     * 清理坐标缓存
     */
    static ClearCoordCache() {
        this.coordCache.Clear()
    }
}

/**
 * 按键队列管理器类
 * @param {Object} keyData
 * @description 管理按键队列，处理按键事件的入队、出队和执行逻辑
 * @version 1.0.0
 * @author Archenemy
 */
class KeyQueueManager {
    static keyQueue := []
    static lastExec := Map()
    static maxLen := 15
    static QueueTimer := 0
    static QueueWorkerFunc := 0
    
    static StartQueue() {
        this.StopQueue()
        if (this.QueueWorkerFunc == 0) {
            this.QueueWorkerFunc := () => this.KeyQueueWorker()
        }
        SetTimer(this.QueueWorkerFunc, 10)
        this.QueueTimer := 1
    }
    
    static StopQueue() {
        this.QueueTimer := 0
        if (this.QueueWorkerFunc != 0) {
            SetTimer(this.QueueWorkerFunc, 0)
        }
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
            uniqueKey: keyData.uniqueKey,
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
     * @param {String} id - 按键标识符
     * @returns {Integer} 优先级数值
     */
    static GetPriority(mode, id := "") {
        switch mode {
            case 4: return 4
            case 2: return 3
            case 3: return 2
            case 1: 
                if (id = "dodge" || id = "potion" || id = "forceMove") {
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
        if (this.QueueTimer = 0) {
            return
        }
        
        now := A_TickCount
        i := this.keyQueue.Length
        while (i >= 1) {
            if (this.keyQueue.Length == 0 || i > this.keyQueue.Length) {
                break
            }
            
            item := this.keyQueue[i]
            uniqueKey := item.uniqueKey
            lastExecTime := this.lastExec.Get(uniqueKey, 0)

            if (item.mode == 3) {
                if (KeyHandler.holdStates.Has(uniqueKey) && KeyHandler.holdStates[uniqueKey]) {
                    i--
                    continue
                }
                KeyHandler.HandleKeyMode(item)
                this.lastExec[uniqueKey] := now

                if (i <= this.keyQueue.Length) {
                    this.keyQueue.RemoveAt(i)
                }
                i--
                continue
            }

            if ((now - lastExecTime) >= item.interval) {
                KeyHandler.HandleKeyMode(item)
                this.lastExec[uniqueKey] := now
                if (item.mode != 3) {
                    if (i <= this.keyQueue.Length) {
                        this.keyQueue.RemoveAt(i)
                        this.EnqueueKey(item)
                    }
                }
            }
            i--
        }
    }

    /**
     * 清空队列
     */
    static ClearQueue() {
        this.keyQueue := []
        this.lastExec.Clear()
    }
}

/**
 * 统一窗口管理类
 * 负责窗口检测、坐标转换、分辨率适配等所有窗口相关功能
 * @version 1.0.0
 * @author Archenemy
 */
class WindowManager {
    ; 静态属性 - 窗口信息缓存
    static windowInfo := Map()
    static coordCache := Map()
    static lastWindowInfo := unset
    
    ; 常量定义
    static D4_WINDOW_CLASS := "Diablo IV Main Window Class"
    static REFERENCE_WIDTH := 3840
    static REFERENCE_HEIGHT := 2160
    static REFERENCE_CENTER_X := 1920
    static REFERENCE_CENTER_Y := 1080

    /**
     * 获取暗黑4窗口信息并计算缩放比例
     * @returns {Map} 包含窗口尺寸和缩放比例信息的Map对象
     */
    static GetWindowInfo() {

        windowInfo := Map(
            "D4W", 0.0,                     ; 客户区实际宽度
            "D4H", 0.0,                     ; 客户区实际高度
            "CD4W", 0.0,                    ; 客户区中心X坐标（浮点）
            "CD4H", 0.0,                    ; 客户区中心Y坐标（浮点）
            "D4S", 1.0,                     ; 统一缩放比例
            "D4SW", 1.0,
            "D4SH", 1.0,
            "D44KW", this.REFERENCE_WIDTH,  ; 参考分辨率宽度
            "D44KH", this.REFERENCE_HEIGHT, ; 参考分辨率高度
            "D44KWC", this.REFERENCE_CENTER_X, ; 参考中心X坐标
            "D44KHC", this.REFERENCE_CENTER_Y  ; 参考中心Y坐标
        )

        try {
            if (this.IsD4WindowExists()) {
                hWnd := WinGetID("ahk_class " . this.D4_WINDOW_CLASS)
                rect := Buffer(16)

                if (DllCall("GetClientRect", "Ptr", hWnd, "Ptr", rect)) {

                    windowInfo["D4W"] := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
                    windowInfo["D4H"] := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")

                    windowInfo["CD4W"] := windowInfo["D4W"] / 2
                    windowInfo["CD4H"] := windowInfo["D4H"] / 2

                    windowInfo["D4SW"] := windowInfo["D4W"] / windowInfo["D44KW"]
                    windowInfo["D4SH"] := windowInfo["D4H"] / windowInfo["D44KH"]
                    windowInfo["D4S"] := Min(windowInfo["D4SW"], windowInfo["D4SH"])
                }
            }
        } catch as err {
            UtilityHelper.DebugLog("获取窗口信息失败: " . err.Message)
        }

        this.windowInfo := windowInfo
        return windowInfo
    }

    /**
     * 检查暗黑4窗口是否存在
     * @returns {Boolean} 窗口是否存在
     */
    static IsD4WindowExists() {
        return WinExist("ahk_class " . this.D4_WINDOW_CLASS)
    }

    /**
     * 坐标转换函数
     * @param {Object} coord - 原始坐标 {x, y}
     * @param {Map} windowInfo - 窗口信息（可选，不传则自动获取）
     * @returns {Object} 转换后的坐标 {x, y}
     */
    static ConvertCoord(coord, windowInfo := unset) {

        if (!IsSet(windowInfo)) {
            windowInfo := this.GetWindowInfo()
        }

        userX := GUIManager.uCtrl["xy"]["x"].Value
        userY := GUIManager.uCtrl["xy"]["y"].Value

        x := Round(windowInfo["CD4W"] + (coord.x - windowInfo["D44KWC"]) * windowInfo["D4S"])
        y := Round(windowInfo["CD4H"] + (coord.y - windowInfo["D44KHC"]) * windowInfo["D4S"])

        ; 如果缩放比例小于1，应用用户偏移
        if (windowInfo["D4S"] < 1) {
            x += userX
            y += userY
        }

        return {x: x, y: y}
    }

    /**
     * 获取所有预定义坐标
     * @returns {Map} 所有坐标的映射
     */
    static GetAllCoord() {
        currentWindowInfo := this.GetWindowInfo()

        try {
            if (this.lastWindowInfo.Has("D4W") && this.coordCache.Count > 0) {
                if (this.lastWindowInfo["D4W"] == currentWindowInfo["D4W"] && 
                    this.lastWindowInfo["D4H"] == currentWindowInfo["D4H"]) {
                    return this.coordCache
                }
            }
        } catch {
            ; 如果访问属性出错，说明还未初始化，继续执行初始化逻辑
        }

        this.lastWindowInfo := currentWindowInfo.Clone()
        this.coordCache := Map()

        ; 预定义的坐标配置
        static coordConfig := Map(
            "monster_blood", {x: 1605, y: 90},
            "boss_blood", {x: 1435, y: 95},
            "skill_bar_blue", {x: 1540, y: 1885},
            "tab_interface_red", {x: 3790, y: 95},
            "dialog_gray_bg", {x: 150, y: 2070},
            "resource_bar", {x: 2620, y: 1875}
        )

        for name, coord in coordConfig {
            this.coordCache[name] := this.ConvertCoord(coord, currentWindowInfo)
        }

        loop 6 {
            this.coordCache["dialog_red_btn_" . A_Index] := this.ConvertCoord({
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
            this.coordCache["mouse_move_" . A_Index] := this.ConvertCoord({
                x: Round(ratio.x * currentWindowInfo["D44KW"]), 
                y: Round(ratio.y * currentWindowInfo["D44KH"])
            }, currentWindowInfo)
        }

        return this.coordCache
    }

    /**
     * 重置所有缓存
     */
    static ResetCache() {
        this.coordCache.Clear()
        this.windowInfo.Clear()
        this.lastWindowInfo := unset
        this.D4State := false
    }
}

/**
 * 精造模式管理类
 * 负责精造时机计算、界面坐标管理和执行流程控制
 * @version 1.0.0
 * @author Archenemy
 */
class PerfectCraftingManager {
    ; 精造模式坐标配置
    static coordConfig := Map(
        "Up", {x: 970, y: 1835},        ; 升级按钮
        "res", {x: 865, y: 725},        ; 结果区域
        "fix", {x: 540, y: 1900},       ; 修复按钮
        "skip", {x: 690, y: 1650}       ; 跳过按钮
    )
    
    ; 相位时机常量
    static LEGENDARY := 5        ; 传奇总阶段数
    static RARE := 4            ; 暗金总阶段数
    static CLICK_DELAY := 130          ; 点击间隔(ms)
    static PREP_DELAY := 150           ; 准备延迟(ms)

    /**
     * 获取转换后的坐标映射
     * @returns {Map} 转换后的坐标映射
     */
    static GetCoordinates() {
        coordMap := Map()
        for key, coord in this.coordConfig {
            coordMap[key] := WindowManager.ConvertCoord(coord)
        }
        return coordMap
    }

    /**
     * 获取高精度时间戳（微秒）
     * @returns {Integer} 高精度时间戳
     */
    static GetPreciseTime() {
        static freq := 0
        if (freq = 0) {
            DllCall("QueryPerformanceFrequency", "Int64*", &freq)
        }
        counter := 0
        DllCall("QueryPerformanceCounter", "Int64*", &counter)
        return (counter * 1000000) // freq
    }

    /**
     * 激活暗黑4窗口
     */
    static ActivateD4Window() {
        if (WindowManager.IsD4WindowExists()) {
            WinActivate("ahk_class " . WindowManager.D4_WINDOW_CLASS)
        }
    }

    /**
     * 获取精造配置参数
     * @returns {Object} 配置参数对象
     */
    static GetCraftingConfig() {
        return {
            modTime: GUIManager.uCtrl["PM"]["modtime"].Value * 1000,
            mode: GUIManager.uCtrl["PM"]["mod"].Value,
            trueTime: GUIManager.uCtrl["PM"]["trueTime"].Value * 1000,
            correct: GUIManager.uCtrl["PM"]["correct"].Value,
            xiuValue: GUIManager.uCtrl["PM"]["xiuValue"].Value
        }
    }

    /**
     * 计算精造时机参数
     * @param {Object} config - 配置参数
     * @returns {Object} 时机计算结果
     */
    static CalculateTiming(config) {
        totalPhases := (config.mode = 1) ? this.RARE : this.LEGENDARY
        needTime := config.trueTime * totalPhases
        
        return {
            totalPhases: totalPhases,
            needTime: needTime,
            targetCenter: Mod((config.xiuValue - config.correct) * config.trueTime + (config.trueTime / 5), needTime)
        }
    }

    /**
     * 执行开始流程
     */
    static ExecuteStart() {
        this.ActivateD4Window()
        coord := this.GetCoordinates()
        
        Sleep(this.PREP_DELAY)
        MouseMove(coord["Up"].x, coord["Up"].y)
        Sleep(this.PREP_DELAY)
        
        ; 前3次准备点击
        Loop 3 {
            Click
            Sleep(this.PREP_DELAY)
        }
        
        ; 记录开始时间并执行第4次点击
        startTime := this.GetPreciseTime()
        Click
        
        GUIManager.uCtrl["PM"]["time1"].Value := FormatTime(, "HH:mm:ss") . "." . Format("{:03}", Mod(Round(startTime/1000), 1000))
        GUIManager.uCtrl["PM"]["time"] := startTime
        
        UtilityHelper.DebugLog("精造开始 - 时间: " . startTime)
    }

    /**
     * 执行继续流程
     */
    static ExecuteNext() {
        this.ActivateD4Window()
        config := this.GetCraftingConfig()
        timing := this.CalculateTiming(config)
        coord := this.GetCoordinates()
        startTime := GUIManager.uCtrl["PM"]["time"]
        
        ; 前3次点击
        MouseMove(coord["Up"].x, coord["Up"].y)
        Loop 3 {
            Click
            Sleep(this.CLICK_DELAY)
        }
        
        currentTime := this.GetPreciseTime()
        elapsedTime := currentTime - startTime
        currentPhase := Mod(elapsedTime, timing.needTime)
        waitTime := Mod(timing.targetCenter - currentPhase + timing.needTime, timing.needTime)
        
        ; 确保等待时间合理
        if (waitTime < config.trueTime / 2) {
            waitTime += timing.needTime
        }
        
        ; 精确等待到目标时间
        targetTime := currentTime + waitTime - config.modTime
        while (targetTime > this.GetPreciseTime()) {
            Sleep(0)
        }
        
        Click
        endTime := this.GetPreciseTime()
        
        this.CalculateAndDisplayResult(startTime, endTime, config, timing)
        
        UtilityHelper.DebugLog("精造继续 - 开始: " . startTime . " 结束: " . endTime)
    }

    /**
     * 计算并显示精造结果
     * @param {Integer} startTime - 开始时间
     * @param {Integer} endTime - 结束时间
     * @param {Object} config - 配置参数
     * @param {Object} timing - 时机参数
     */
    static CalculateAndDisplayResult(startTime, endTime, config, timing) {
        totalElapsed := endTime - startTime
        finalPhase := Mod(totalElapsed, timing.needTime)
        
        phaseIndex := Floor(finalPhase / config.trueTime)
        actualFixedPhase := Mod(config.correct + phaseIndex - 1, timing.totalPhases) + 1
        
        phaseDeviation := finalPhase - timing.targetCenter + config.modTime
        
        resultText := "总耗时:" . Floor(totalElapsed/1000) . "ms 实际窗口:" . actualFixedPhase . "/" . config.xiuValue . " 偏差: " . Round(phaseDeviation/1000) . "ms"
        GUIManager.uCtrl["PM"]["timeX"].Value := resultText
        
        UtilityHelper.DebugLog("精造结果 - " . resultText)
    }

    /**
     * 重置精造数据
     */
    static ExecuteReset() {

        GUIManager.uCtrl["PM"]["time"] := 0
        
        GUIManager.uCtrl["PM"]["time1"].Value := ""
        GUIManager.uCtrl["PM"]["timeX"].Value := ""
        GUIManager.uCtrl["PM"]["correct"].Value := 1
        GUIManager.uCtrl["PM"]["xiuValue"].Value := 1
        
        UtilityHelper.DebugLog("精造数据已重置")
    }
}

/**
 * 暂停检测管理类
 * 负责管理所有的暂停检测逻辑，包括血条检测、界面检测、对话框检测等
 * @version 1.0.0
 * @author Archenemy
 */
class PauseDetector {
    ; 静态属性 - 检测状态缓存
    static bloodPauseMissCount := 0
    static bloodResumeHitCount := 0
    static tabPauseMissCount := 0
    static tabResumeHitCount := 0
    static enterPauseMissCount := 0
    static enterResumeHitCount := 0
    static PAUSE_THRESHOLD := 2
    static RESUME_THRESHOLD := 2
    static CheckTimer := Map()

    /**
     * 管理所有检测定时器的启动和停止
     * @param {Boolean} enable - true: 启动定时器, false: 停止定时器
     */
    static ManageTimers(enable) {
        if (enable) {
            this.GetTimerConfig()
            for timerName, timerConfig in this.CheckTimer {
                if (timerConfig.enabled) {
                    SetTimer(timerConfig.func, timerConfig.interval)
                } else {
                    SetTimer(timerConfig.func, 0)
                }
            }
        } else {
            if (this.CheckTimer.Count == 0) {
                this.GetTimerConfig()
            }
            
            for timerName, timerConfig in this.CheckTimer {
                try {
                    SetTimer(timerConfig.func, 0)
                } catch {
                }
            }
            this.ResetCounters()
        }
    }

    /**
     * 获取定时器配置
     * 包括箭头函数、启用状态和检测间隔
     */
    static GetTimerConfig() {

        d4Only := GUIManager.uCtrl["D4only"]["enable"].Value
        blood := GUIManager.uCtrl["ipPause"]["enable"].Value
        tab := GUIManager.uCtrl["tabPause"]["enable"].Value
        
        bloodInterval := (
            GUIManager.uCtrl.Has("ipPause") && GUIManager.uCtrl["ipPause"].Has("interval")
                ? Integer(GUIManager.uCtrl["ipPause"]["interval"].Value)
                : 50
        )
        
        tabInterval := (
            GUIManager.uCtrl.Has("tabPause") && GUIManager.uCtrl["tabPause"].Has("interval")
                ? Integer(GUIManager.uCtrl["tabPause"]["interval"].Value)
                : 100
        )

        this.CheckTimer["CheckWindow"] := {
            func: () => this.CheckWindow(),
            enabled: true,
            interval: 100
        }
        
        this.CheckTimer["AutoPauseByBlood"] := {
            func: () => this.AutoPauseByBlood(),
            enabled: d4Only && blood,  ; 血条检测依赖d4only模式
            interval: bloodInterval
        }
        
        this.CheckTimer["AutoPauseByTAB"] := {
            func: () => this.AutoPauseByTAB(),
            enabled: d4Only && tab,    ; TAB检测依赖d4only模式
            interval: tabInterval
        }
    }

    /**
     * 重置所有检测计数器
     */
    static ResetCounters() {
        this.bloodPauseMissCount := 0
        this.bloodResumeHitCount := 0
        this.tabPauseMissCount := 0
        this.tabResumeHitCount := 0
        this.enterPauseMissCount := 0
        this.enterResumeHitCount := 0
        this.CheckTimer.Clear()
    }

    /**
     * 窗口切换检查函数
     */
    static CheckWindow() {
        d4only := GUIManager.uCtrl["D4only"]["enable"].Value
        pause := false
        if (d4only) {
            pause := !WinActive("ahk_class Diablo IV Main Window Class")
        } else {
            pause := WinActive("ahk_class AutoHotkeyGUI") || InStr(WinGetTitle("A"), "暗黑4助手")
        }
        MacroController.TogglePause("window", pause)
    }

    /**
     * 检测关键界面点（TAB界面和技能栏）
     * @param {Map} allcoords - 坐标映射
     * @param {Map} pixelCache - 像素缓存（可选）
     * @returns {Object} - 包含isBlueColor和isRedColor的检测结果
     */
    static CheckKeyPoints(allcoords, pixelCache := unset) {
        dfxCoord := allcoords["skill_bar_blue"]
        tabCoord := allcoords["tab_interface_red"]

        colorDFX := IsSet(pixelCache) && pixelCache.Has(dfxCoord.x . "," . dfxCoord.y)
            ? pixelCache[dfxCoord.x . "," . dfxCoord.y]
            : ColorDetector.GetPixelRGB(dfxCoord.x, dfxCoord.y)
        colorTAB := IsSet(pixelCache) && pixelCache.Has(tabCoord.x . "," . tabCoord.y)
            ? pixelCache[tabCoord.x . "," . tabCoord.y]
            : ColorDetector.GetPixelRGB(tabCoord.x, tabCoord.y)

        return {
            isBlueColor: ColorDetector.IsBlue(colorDFX), 
            isRedColor: ColorDetector.IsRed(colorTAB)
        }
    }

    /**
     * 检测输入框和对话框
     * @param {Map} allcoords - 坐标映射
     * @param {Map} pixelCache - 像素缓存（可选）
     * @returns {Boolean} - 是否检测到对话框
     */
    static CheckPauseByEnter(allcoords, pixelCache := unset) {
        try {
            grayPoint := "dialog_gray_bg"
            redPoints := ["dialog_red_btn_1", "dialog_red_btn_2", "dialog_red_btn_3", 
                         "dialog_red_btn_4", "dialog_red_btn_5", "dialog_red_btn_6"]

            coord := allcoords[grayPoint]
            key := coord.x . "," . coord.y
            
            grayColor := (IsSet(pixelCache) && pixelCache.Has(key))
                ? pixelCache[key]
                : ColorDetector.GetPixelRGB(coord.x, coord.y)

            if (!ColorDetector.IsGray(grayColor))
                return false

            for , point in redPoints {
                coord := allcoords[point]
                key := coord.x . "," . coord.y
                
                colorObj := (IsSet(pixelCache) && pixelCache.Has(key))
                    ? pixelCache[key]
                    : ColorDetector.GetPixelRGB(coord.x, coord.y)

                if (ColorDetector.IsRed(colorObj)) {
                    return true
                }
            }
            
            return false
            
        } catch as err {
            return false
        }
    }

    /**
     * 检测Boss血条
     * @param {Map} allcoords - 坐标映射
     * @param {Map} pixelCache - 像素缓存（可选）
     * @returns {Boolean} - 是否检测到Boss血条
     */
    static CheckBoss(allcoords, pixelCache := unset) {
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
                    pixelCache[key] : ColorDetector.GetPixelRGB(sampleX, sampleY)

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
     * 检测怪物血条
     * @param {Map} allcoords - 坐标映射
     * @param {Map} pixelCache - 像素缓存（可选）
     * @returns {Boolean} - 是否检测到怪物血条
     */
    static CheckMonster(allcoords, pixelCache := unset) {
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
                    pixelCache[key] : ColorDetector.GetPixelRGB(sampleX, sampleY)

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
     * 血条检测暂停逻辑
     * 定时检测血条并自动暂停/启动宏
     */
    static AutoPauseByBlood() {
        allcoords := WindowManager.GetAllCoord()
        bloodDetected := false
        
        try {
            pixelCache := Map()
            if (this.CheckMonster(allcoords, pixelCache)) {
                bloodDetected := true
            }
            else if (this.CheckBoss(allcoords, pixelCache)) {
                bloodDetected := true
            }
        } catch as err {
            bloodDetected := false
        }

        if (MacroController.pauseConfig["blood"].state) {
            if (bloodDetected) {
                this.bloodResumeHitCount++
                this.bloodPauseMissCount := 0
                if (this.bloodResumeHitCount >= this.RESUME_THRESHOLD) {
                    MacroController.TogglePause("blood", false)
                    this.bloodResumeHitCount := 0
                }
            } else {
                this.bloodResumeHitCount := 0
            }
        } else {
            if (!bloodDetected) {
                this.bloodPauseMissCount++
                this.bloodResumeHitCount := 0
                if (this.bloodPauseMissCount >= this.PAUSE_THRESHOLD) {
                    MacroController.TogglePause("blood", true)
                    this.bloodPauseMissCount := 0
                }
            } else {
                this.bloodPauseMissCount := 0
            }
        }
    }

    /**
     * TAB界面和对话框检测暂停逻辑
     * 定时检测界面状态并自动暂停/启动宏
     */
    static AutoPauseByTAB() {
        allcoords := WindowManager.GetAllCoord()

        try {
            pixelCache := Map()
            keyPoints := this.CheckKeyPoints(allcoords, pixelCache)

            if (MacroController.pauseConfig["tab"].state) {
                if (keyPoints.isBlueColor) {
                    this.tabResumeHitCount++
                    this.tabPauseMissCount := 0
                    if (this.tabResumeHitCount >= this.RESUME_THRESHOLD) {
                        MacroController.TogglePause("tab", false)
                        this.tabResumeHitCount := 0
                    }
                } else {
                    this.tabResumeHitCount := 0
                }
            } else {
                if (!keyPoints.isBlueColor && keyPoints.isRedColor) {
                    this.tabPauseMissCount++
                    this.tabResumeHitCount := 0
                    if (this.tabPauseMissCount >= this.PAUSE_THRESHOLD) {
                        MacroController.TogglePause("tab", true)
                        this.tabPauseMissCount := 0
                    }
                } else {
                    this.tabPauseMissCount := 0
                }
            }

            if (MacroController.pauseConfig["enter"].state) {
                if (!this.CheckPauseByEnter(allcoords, pixelCache)) {
                    this.enterResumeHitCount++
                    this.enterPauseMissCount := 0
                    if (this.enterResumeHitCount >= this.RESUME_THRESHOLD) {
                        MacroController.TogglePause("enter", false)
                        this.enterResumeHitCount := 0
                    }
                } else {
                    this.enterResumeHitCount := 0
                }
            } else {
                if (this.CheckPauseByEnter(allcoords, pixelCache)) {
                    this.enterPauseMissCount++
                    this.enterResumeHitCount := 0
                    if (this.enterPauseMissCount >= this.PAUSE_THRESHOLD) {
                        MacroController.TogglePause("enter", true)
                        this.enterPauseMissCount := 0
                    }
                } else {
                    this.enterPauseMissCount := 0
                }
            }
        }
    } 

}

/**
 * 颜色检测器类
 * 负责像素颜色获取和颜色类型判断
 * @version 1.0.0
 * @author Archenemy
 */
class ColorDetector {
    ; 静态缓存配置
    static pixelCache := Map()
    static cacheLifetime := 50
    static lastCacheClear := 0
    static maxCacheEntries := 100
    
    /**
     * 获取指定坐标像素的RGB颜色值
     * @param {Integer} x - X坐标
     * @param {Integer} y - Y坐标
     * @param {Boolean} useCache - 是否使用缓存，默认为true
     * @returns {Object} - 包含r, g, b三个颜色分量的对象
     */
    static GetPixelRGB(x, y, useCache := true) {
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
        timeSlot := currentTime // this.cacheLifetime
        cacheKey := (x << 20) | (y << 8) | (timeSlot & 0xFF)
        
        if (currentTime - this.lastCacheClear > 150) {
            if (this.pixelCache.Count > this.maxCacheEntries) {
                this.pixelCache.Clear()
            }
            this.lastCacheClear := currentTime
        }
        
        if (this.pixelCache.Has(cacheKey)) {
            return this.pixelCache[cacheKey]
        }
        
        try {
            color := PixelGetColor(x, y, "RGB")
            result := {
                r: (color >> 16) & 0xFF,
                g: (color >> 8) & 0xFF,
                b: color & 0xFF
            }
            this.pixelCache[cacheKey] := result
            return result
        } catch {
            result := {r: 0, g: 0, b: 0}
            this.pixelCache[cacheKey] := result
            return result
        }
    }
    
    /**
     * 清理像素缓存
     */
    static ClearCache() {
        this.pixelCache.Clear()
        this.lastCacheClear := A_TickCount
    }
    
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
                color.r > color.g * 2 &&
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
        mixcolor := Max(color.r, color.g, color.b)
        mincolor := Min(color.r, color.g, color.b)
        range := mixcolor - mincolor
        avgColor := (color.r + color.g + color.b) / 3
        return (range < 40 &&
                avgColor > 10 && 
                mixcolor < 80)
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
        try {
            this.DeleteSection(profileName)
            
            section := profileName
            
            for i in [1, 2, 3, 4, 5] {
                skillData := GUIManager.cSkill[i]["key"].Value . "," . 
                            GUIManager.cSkill[i]["enable"].Value . "," . 
                            GUIManager.cSkill[i]["interval"].Value . "," . 
                            GUIManager.cSkill[i]["mode"].Value
                IniWrite(skillData, this.settingsFile, section, "skill" i)
            }
            
            leftData := GUIManager.mSkill["left"]["enable"].Value . "," . 
                        GUIManager.mSkill["left"]["interval"].Value . "," . 
                        GUIManager.mSkill["left"]["mode"].Value
            IniWrite(leftData, this.settingsFile, section, "left")
            
            rightData := GUIManager.mSkill["right"]["enable"].Value . "," . 
                         GUIManager.mSkill["right"]["interval"].Value . "," . 
                         GUIManager.mSkill["right"]["mode"].Value
            IniWrite(rightData, this.settingsFile, section, "right")
            
            dodgeData := GUIManager.uCtrl["dodge"]["key"].Value . "," . 
                         GUIManager.uCtrl["dodge"]["enable"].Value . "," . 
                         GUIManager.uCtrl["dodge"]["interval"].Value
            IniWrite(dodgeData, this.settingsFile, section, "dodge")

            potionData := GUIManager.uCtrl["potion"]["key"].Value . "," . 
                          GUIManager.uCtrl["potion"]["enable"].Value . "," . 
                          GUIManager.uCtrl["potion"]["interval"].Value
            IniWrite(potionData, this.settingsFile, section, "potion")

            forceMoveData := GUIManager.uCtrl["forceMove"]["key"].Value . "," . 
                             GUIManager.uCtrl["forceMove"]["enable"].Value . "," . 
                             GUIManager.uCtrl["forceMove"]["interval"].Value
            IniWrite(forceMoveData, this.settingsFile, section, "forceMove")

            ipPauseData := GUIManager.uCtrl["ipPause"]["enable"].Value . "," . 
                           GUIManager.uCtrl["ipPause"]["interval"].Value
            IniWrite(ipPauseData, this.settingsFile, section, "ipPause")

            tabPauseData := GUIManager.uCtrl["tabPause"]["enable"].Value . "," . 
                            GUIManager.uCtrl["tabPause"]["interval"].Value
            IniWrite(tabPauseData, this.settingsFile, section, "tabPause")

            dcPauseData := GUIManager.uCtrl["dcPause"]["enable"].Value . "," . 
                           GUIManager.uCtrl["dcPause"]["interval"].Value
            IniWrite(dcPauseData, this.settingsFile, section, "dcPause")

            mouseAutoMoveData := GUIManager.uCtrl["mouseAutoMove"]["enable"].Value . "," . 
                                 GUIManager.uCtrl["mouseAutoMove"]["interval"].Value
            IniWrite(mouseAutoMoveData, this.settingsFile, section, "mouseAutoMove")
            RandomData := GUIManager.uCtrl["random"]["enable"].Value . "," . 
                          GUIManager.uCtrl["random"]["max"].Value
            IniWrite(RandomData, this.settingsFile, section, "random")

            IniWrite(GUIManager.RunMod.Value, this.settingsFile, section, "runMode")
            IniWrite(GUIManager.uCtrl["shift"]["enable"].Value, this.settingsFile, section, "shift")
            IniWrite(GUIManager.uCtrl["D4only"]["enable"].Value, this.settingsFile, section, "D4only")
            IniWrite(GUIManager.uCtrl["xy"]["x"].Value, this.settingsFile, section, "xyX")
            IniWrite(GUIManager.uCtrl["xy"]["y"].Value, this.settingsFile, section, "xyY")
            IniWrite(GUIManager.startkey["mode"].Value, this.settingsFile, section, "hotkeyMode")
            IniWrite(GUIManager.startkey["userkey"][1].key, this.settingsFile, section, "useHotKey")
            
            return true
            
        } catch {
            return false
        }
    }
    
    /**
     * 加载
     */
    static LoadProfile(profileName) {
        try {
            section := profileName

            for Index in [1, 2, 3, 4, 5]  {
                skillData := IniRead(this.settingsFile, section, "skill" Index, Index . ",1,20,1")
                parts := StrSplit(skillData, ",")
                
                if (parts.Length >= 4) {
                    GUIManager.cSkill[Index]["key"].Value := parts[1]
                    GUIManager.cSkill[Index]["enable"].Value := Integer(parts[2])
                    GUIManager.cSkill[Index]["interval"].Value := Integer(parts[3])
                    GUIManager.cSkill[Index]["mode"].Value := Integer(parts[4])
                }
            }

            leftData := IniRead(this.settingsFile, section, "left", "0,80,1")
            leftParts := StrSplit(leftData, ",")
            if (leftParts.Length >= 3) {
                GUIManager.mSkill["left"]["enable"].Value := Integer(leftParts[1])
                GUIManager.mSkill["left"]["interval"].Value := Integer(leftParts[2])
                GUIManager.mSkill["left"]["mode"].Value := Integer(leftParts[3])
            }
            
            rightData := IniRead(this.settingsFile, section, "right", "1,300,1")
            rightParts := StrSplit(rightData, ",")
            if (rightParts.Length >= 3) {
                GUIManager.mSkill["right"]["enable"].Value := Integer(rightParts[1])
                GUIManager.mSkill["right"]["interval"].Value := Integer(rightParts[2])
                GUIManager.mSkill["right"]["mode"].Value := Integer(rightParts[3])
            }

            dodgeData := IniRead(this.settingsFile, section, "dodge", "Space,0,20")
            dodgeParts := StrSplit(dodgeData, ",")
            if (dodgeParts.Length >= 3) {
                GUIManager.uCtrl["dodge"]["key"].Value := dodgeParts[1]
                GUIManager.uCtrl["dodge"]["enable"].Value := Integer(dodgeParts[2])
                GUIManager.uCtrl["dodge"]["interval"].Value := Integer(dodgeParts[3])
            }

            potionData := IniRead(this.settingsFile, section, "potion", "q,0,3000")
            potionParts := StrSplit(potionData, ",")
            if (potionParts.Length >= 3) {
                GUIManager.uCtrl["potion"]["key"].Value := potionParts[1]
                GUIManager.uCtrl["potion"]["enable"].Value := Integer(potionParts[2])
                GUIManager.uCtrl["potion"]["interval"].Value := Integer(potionParts[3])
            }

            forceMoveData := IniRead(this.settingsFile, section, "forceMove", "e,0,50")
            forceMoveParts := StrSplit(forceMoveData, ",")
            if (forceMoveParts.Length >= 3) {
                GUIManager.uCtrl["forceMove"]["key"].Value := forceMoveParts[1]
                GUIManager.uCtrl["forceMove"]["enable"].Value := Integer(forceMoveParts[2])
                GUIManager.uCtrl["forceMove"]["interval"].Value := Integer(forceMoveParts[3])
            }

            ipPauseData := IniRead(this.settingsFile, section, "ipPause", "0,50")
            ipPauseParts := StrSplit(ipPauseData, ",")
            if (ipPauseParts.Length >= 2) {
                GUIManager.uCtrl["ipPause"]["enable"].Value := Integer(ipPauseParts[1])
                GUIManager.uCtrl["ipPause"]["interval"].Value := Integer(ipPauseParts[2])
            }

            tabPauseData := IniRead(this.settingsFile, section, "tabPause", "0,100")
            tabPauseParts := StrSplit(tabPauseData, ",")
            if (tabPauseParts.Length >= 2) {
                GUIManager.uCtrl["tabPause"]["enable"].Value := Integer(tabPauseParts[1])
                GUIManager.uCtrl["tabPause"]["interval"].Value := Integer(tabPauseParts[2])
            }

            dcPauseData := IniRead(this.settingsFile, section, "dcPause", "1,2")
            dcPauseParts := StrSplit(dcPauseData, ",")
            if (dcPauseParts.Length >= 2) {
                GUIManager.uCtrl["dcPause"]["enable"].Value := Integer(dcPauseParts[1])
                GUIManager.uCtrl["dcPause"]["interval"].Value := Integer(dcPauseParts[2])
            }

            mouseAutoMoveData := IniRead(this.settingsFile, section, "mouseAutoMove", "0,1000")
            mouseAutoMoveParts := StrSplit(mouseAutoMoveData, ",")
            if (mouseAutoMoveParts.Length >= 2) {
                GUIManager.uCtrl["mouseAutoMove"]["enable"].Value := Integer(mouseAutoMoveParts[1])
                GUIManager.uCtrl["mouseAutoMove"]["interval"].Value := Integer(mouseAutoMoveParts[2])
            }

            RandomData := IniRead(this.settingsFile, section, "random", "0,10")
            RandomParts := StrSplit(RandomData, ",")
            if (RandomParts.Length >= 2) {
                GUIManager.uCtrl["random"]["enable"].Value := Integer(RandomParts[1])
                GUIManager.uCtrl["random"]["max"].Value := Integer(RandomParts[2])
            }
  
            GUIManager.RunMod.Value := IniRead(this.settingsFile, section, "runMode", "1")
            GUIManager.uCtrl["shift"]["enable"].Value := IniRead(this.settingsFile, section, "shift", "0")
            GUIManager.uCtrl["D4only"]["enable"].Value := IniRead(this.settingsFile, section, "D4only", "1")
            GUIManager.uCtrl["xy"]["x"].Value := IniRead(this.settingsFile, section, "xyX", "0")
            GUIManager.uCtrl["xy"]["y"].Value := IniRead(this.settingsFile, section, "xyY", "0")
            GUIManager.startkey["mode"].Value := IniRead(this.settingsFile, section, "hotkeyMode", "1")
            GUIManager.startkey["userkey"][1].key := IniRead(this.settingsFile, section, "useHotKey", "F1")
            GUIManager.startkey["guiHotkey"].Value := GUIManager.startkey["userkey"][1].key
            HotkeyManager.LoadStartHotkey()

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
            this.Write("Profiles", "List", UtilityHelper.Join(profileList, "|"))
        }
        return profileList
    }
    
    static SaveProfileList(profileList) {
        return this.Write("Profiles", "List", UtilityHelper.Join(profileList, "|"))
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
                defaultContent := "[Profiles]`nList=" . this.defaultProfile . "`n`n[Global]`nLastUsedProfile=" . this.defaultProfile . "`n`n"
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
        profileNameInput := Trim(GUIManager.profileName.Text)
        if (this.SaveProfile(profileNameInput)) {
            if (!this.ProfileExists(profileNameInput)) {
                profileList := this.GetProfileList()
                profileList.Push(profileNameInput)
                this.SaveProfileList(profileList)
            }

            this.UpdateDropDown(GUIManager.profileName, profileNameInput)
            this.SetLastUsedProfile(profileNameInput)
            
            GUIManager.statusBar.Text := "配置方案「" profileNameInput "」已保存"
        } else {
            GUIManager.statusBar.Text := "保存配置失败"
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
            GUIManager.statusBar.Text := "配置已加载: " selectedProfile
        } else {
            GUIManager.statusBar.Text := "加载配置失败"
        }
    }
    
    /**
     * 删除
     */
    static DeleteProfileFromUI() {
        profileList := this.GetProfileList()
        currentProfileName := profileList[GUIManager.profileName.Value]
        if (currentProfileName = this.defaultProfile) {
            this.DeleteSection(this.defaultProfile)
            this.LoadSelectedProfile(this.defaultProfile)
            GUIManager.statusBar.Text := "默认配置以重置"
            return
        }

        if (this.DeleteProfile(currentProfileName)) {
            this.UpdateDropDown(GUIManager.profileName, this.defaultProfile)
            this.LoadSelectedProfile(this.defaultProfile)
            GUIManager.statusBar.Text := "配置方案已删除，已加载默认配置"
        } else {
            GUIManager.statusBar.Text := "删除配置失败"
        }
    }
    
    /**
     * 初始化
     */
    static Initialize() {
        if (!this.EnsureConfigFile()) {
            GUIManager.statusBar.Text := "配置文件初始化失败"
            return
        }

        lastProfile := this.GetLastUsedProfile()
        this.UpdateDropDown(GUIManager.profileName, lastProfile)

        this.LoadSelectedProfile(lastProfile)
        GUIManager.statusBar.Text := "配置已加载: " lastProfile
    }
}

#HotIf WinActive("ahk_class Diablo IV Main Window Class")

~LButton::
{
    static lastClickTime := 0

    if (!GUIManager.uCtrl["dcPause"]["enable"].Value)
        return

    currentTime := A_TickCount

    if (currentTime - lastClickTime < 400) {
        MacroController.TogglePause("doubleClick", true)
        confirmTime := GUIManager.uCtrl["dcPause"]["interval"] ? GUIManager.uCtrl["dcPause"]["interval"].Value : 2
        SetTimer(ObjBindMethod(MacroController, "TogglePause", "doubleClick", false), -confirmTime * 1000)
        lastClickTime := 0
    } else {
        lastClickTime := currentTime
    }
}

GUIManager.Initialize()