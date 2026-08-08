#Requires AutoHotkey v2.0.26
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
    static SKILL_MODES := ["连点", "BUFF", "按住", "资源"]   ; 技能模式
    static profileName := ""    ; 配置文件
    
    /**
     * 初始化GUI界面
     * 创建主窗口、托盘菜单和所有控件
     */
    static Initialize() {
        this.myGui := Gui("", "D4 HELP v7.1 by Archenemy")
        this.myGui.BackColor := "FFFFFF"
        this.myGui.SetFont("s10", "Microsoft YaHei UI")
        this.InitializeTrayMenu()
        this.myGui.OnEvent("Escape", (*) => this.myGui.Minimize())
        this.myGui.OnEvent("Close", (*) => GUIManager.ExitApp())
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
        A_TrayMenu.Add("调试日志", (*) => GUIManager.ToggleDebug())
        A_TrayMenu.Add()
        A_TrayMenu.Add("退出", (*) => GUIManager.ExitApp())
        A_TrayMenu.Default := "显示主界面"
    }

    /**
     * 切换调试日志开关（托盘菜单）
     */
    static ToggleDebug() {
        global DEBUG
        DEBUG := !DEBUG
        if (DEBUG) {
            A_TrayMenu.Check("调试日志")
            this.statusBar.Text := "调试日志已开启"
            UtilityHelper.DebugLog("调试日志已开启")
        } else {
            A_TrayMenu.Uncheck("调试日志")
            this.statusBar.Text := "调试日志已关闭"
        }
    }

    /**
     * 统一退出流程：先停止宏并释放按键，再保存配置并退出
     */
    static ExitApp() {
        try {
            MacroController.StopAllTimers()
        } catch as err {
            UtilityHelper.ReportError("退出清理失败: " . err.Message)
        }
        ConfigManager.SaveProfileFromUI()
        ExitApp()
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
        
        this.tabControl.UseTab(1)
        
        ; 运行模式选择
        this.CreateRunningControls()
        ; 技能控件
        this.CreateSkillControls()
        ; 自动启停区域
        this.CreateAutoStopControls()
        ; 工具模式
        this.tabControl.UseTab(2)
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
            MacroController.ToggleMacro()
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
                "mode", this.myGui.AddDropDownList("x250 y" yPos-2 " w60 h120 Choose1", this.SKILL_MODES)
            )
        }
        
        ; 左键配置
        this.mSkill["left"] := Map(
            "text", this.myGui.AddText("x30 y340 w40 h20", "左键:"),
            "key", "LButton",  ; 固定键值
            "enable", this.myGui.AddCheckbox("x125 y340 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y340 w50 h20", "80"),
            "mode", this.myGui.AddDropDownList("x250 y338 w60 h120 Choose1", this.SKILL_MODES)
        )
        
        this.mSkill["right"] := Map(
            "text", this.myGui.AddText("x30 y370 w40 h20", "右键:"),
            "key", "RButton",  ; 固定键值
            "enable", this.myGui.AddCheckbox("x125 y370 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y370 w50 h20", "300"),
            "mode", this.myGui.AddDropDownList("x250 y368 w60 h120 Choose1", this.SKILL_MODES)
        )
        
        ; 药水功能
        this.uCtrl["potion"] := Map(
            "text", this.myGui.AddText("x30 y400 w35 h20", "药水:"),
            "key", this.myGui.AddHotkey("x65 y400 w45 h20", "q"),
            "enable", this.myGui.AddCheckbox("x125 y400 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y400 w50 h20", "3000"),
            "mode", this.myGui.AddDropDownList("x250 y398 w60 h120 Choose1", this.SKILL_MODES)
        )
        this.uCtrl["potion"]["mode"].Enabled := false
        
        ; 强移功能
        this.uCtrl["forceMove"] := Map(
            "text", this.myGui.AddText("x30 y430 w35 h20", "强移:"),
            "key", this.myGui.AddHotkey("x65 y430 w45 h20", "e"),
            "enable", this.myGui.AddCheckbox("x125 y430 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y430 w50 h20", "50"),
            "mode", this.myGui.AddDropDownList("x250 y428 w60 h120 Choose1", this.SKILL_MODES)
        )
        this.uCtrl["forceMove"]["mode"].Enabled := false
        
        ; 闪避功能
        this.uCtrl["dodge"] := Map(
            "text", this.myGui.AddText("x30 y460 w35 h20", "闪避:"),
            "key", this.myGui.AddHotkey("x65 y460 w45 h20", "Space"),
            "enable", this.myGui.AddCheckbox("x125 y460 w45 h20", "启用"),
            "interval", this.myGui.AddEdit("x185 y460 w50 h20", "20"),
            "mode", this.myGui.AddDropDownList("x250 y458 w60 h120 Choose1", this.SKILL_MODES)
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
            UtilityHelper.LimitEditValue(
                this.uCtrl["random"]["max"],
                UtilityHelper.RANDOM_DELAY_MIN,
                UtilityHelper.RANDOM_DELAY_MAX)))
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
    static currentHotkey := ""          ; 当前生效的启动热键

    /**
     * 加载全局热键
     */
    static LoadStartHotkey() {
        mode := GUIManager.startkey["mode"].Value
        GUIManager.startkey["guiHotkey"].Enabled := GUIManager.startkey["userkey"][mode].input
        newHotkey := this._ResolveHotkey(mode)
        
        try {
            if (this.currentHotkey != "" && this.currentHotkey != newHotkey) {
                try {
                    Hotkey(this.currentHotkey, "Off")
                } catch as err {
                    UtilityHelper.ReportError("关闭旧热键失败: " . this.currentHotkey . " - " . err.Message)
                }
            }
            if (newHotkey != this.currentHotkey) {
                Hotkey(newHotkey, (*) => MacroController.ToggleMacro(), "On")
                this.currentHotkey := newHotkey
                if (GUIManager.statusBar != "") {
                    GUIManager.statusBar.Text := "热键已更新: " newHotkey
                }
                this.UpdateHotkeyText()
            }
        } catch as err {
            UtilityHelper.ReportError("加载启动热键失败: " . err.Message)
            if (GUIManager.statusBar != "") {
                GUIManager.statusBar.Text := "热键注册失败，已回退 F1: " err.Message
            }
            this._FallbackToF1()
        }
    }

    /**
     * 按模式解析启动热键
     * @param {Integer} mode - 1=自定义, 2=侧键1, 3=侧键2
     * @returns {String} 热键名
     */
    static _ResolveHotkey(mode) {
        switch mode {
            case 2: return "XButton1"
            case 3: return "XButton2"
            default: return GUIManager.startkey["userkey"][1].key
        }
    }

    /**
     * 热键注册失败时回退到默认 F1
     */
    static _FallbackToF1() {
        GUIManager.startkey["mode"].Value := 1
        GUIManager.startkey["guiHotkey"].Value := "F1"
        GUIManager.startkey["guiHotkey"].Enabled := true
        GUIManager.startkey["userkey"][1].key := "F1"
        try {
            Hotkey("F1", (*) => MacroController.ToggleMacro(), "On")
            this.currentHotkey := "F1"
        } catch as err {
            UtilityHelper.ReportError("回退热键 F1 注册失败: " . err.Message)
        }
        this.UpdateHotkeyText()
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
            
            currentKey := this._ResolveHotkey(mode)
            
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
    ; 随机延迟范围常量
    static RANDOM_DELAY_MIN := 1
    static RANDOM_DELAY_MAX := 10

    /**
     * 生成随机延迟毫秒数（1 ~ max）
     * @param {Number|String} max - 随机延迟上限（毫秒），非法值回退到默认上限
     * @returns {Integer} 随机延迟毫秒数
     */
    static RandomDelay(max) {
        maxRandom := this.RANDOM_DELAY_MAX
        try {
            maxRandom := Integer(max)
        }
        if (maxRandom < this.RANDOM_DELAY_MIN || maxRandom > this.RANDOM_DELAY_MAX) {
            maxRandom := this.RANDOM_DELAY_MAX
        }
        return Random(this.RANDOM_DELAY_MIN, maxRandom)
    }

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
            this.ReportError("切换窗口置顶状态失败: " . err.Message)
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

                fileObj := FileOpen(logFile, "a")
                if (fileObj.Length > maxSize) {
                    fileObj.Length := 0
                }
                timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
                fileObj.Write(timestamp . " - " . message . "`n")
                fileObj.Close()
            } catch as err {
                OutputDebug "日志写入失败: " err.Message
            }
        }
    }

    /**
     * 报告错误：DEBUG 开启时写入日志，并在可用时显示到状态栏
     * @param {String} message - 错误信息
     */
    static ReportError(message) {
        this.DebugLog(message)
        if (DEBUG && GUIManager.statusBar != "") {
            GUIManager.statusBar.Text := "错误: " message
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
            WindowManager.ResetCache()
            GUIManager.UpdateStatus("已停止", "宏已停止")
        }
    }
    
    /**
     * 核心启停函数 - 根据指定原因切换暂停状态
     * @param {String} reason - 暂停原因
     * @param {Boolean} state - 暂停状态
     * @param {String} reasonName - 原因显示名（可选，覆盖 pauseConfig 中的默认名）
     */
    static TogglePause(reason := "", state := unset, reasonName := "") {
        if (!this.isRunning) {
            return
        }
        if (reasonName != "") {
            this.pauseConfig[reason].name := reasonName
        }
        if (this.pauseConfig[reason].state == state) {
            return
        }
        wasAnyPaused := this._HasAnyPausedReason()
        this.pauseConfig[reason].state := state
        isAnyPaused := this._HasAnyPausedReason()
        if (isAnyPaused != wasAnyPaused) {
            if (isAnyPaused) {
                this.StopAllTimers()
            } else {
                this.StartAllTimers()
            }
        }
        if (isAnyPaused) {
            reasonsText := this._BuildPauseReasonText()
            GUIManager.UpdateStatus("已暂停", reasonsText)
        } else {
            GUIManager.UpdateStatus("运行中", "宏已启动")
        }
    }
    
    /**
     * 检查是否有任何暂停原因处于活跃状态
     * @returns {Boolean} - 存在至少一个暂停原因时返回 true
     */
    static _HasAnyPausedReason() {
        for , config in this.pauseConfig {
            if (config.state) {
                return true
            }
        }
        return false
    }
    
    /**
     * 构建暂停原因显示文本
     * @returns {String} - 以 " + " 连接的暂停原因名称
     */
    static _BuildPauseReasonText() {
        reasons := []
        for , config in this.pauseConfig {
            if (config.state) {
                reasons.Push(config.name)
            }
        }
        return UtilityHelper.Join(reasons, " + ")
    }
    
    /**
     * 查询暂停状态
     * @param {String} reason - 可选，指定暂停原因；省略时查询整体暂停状态
     * @returns {Boolean} - 指定原因或整体是否处于暂停状态
     */
    static IsPaused(reason := "") {
        if (reason == "") {
            return this._HasAnyPausedReason()
        }
        return this.pauseConfig.Has(reason) && this.pauseConfig[reason].state
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
                try {
                    KeyHandler.PressKeyCallback("skill", A_Index)
                } catch as err {
                    UtilityHelper.ReportError("技能" A_Index " 启动失败: " . err.Message)
                }
            }
        }
        
        for mouseBtn in ["left", "right"] {
            if (GUIManager.mSkill[mouseBtn]["enable"].Value) {
                try {
                    KeyHandler.PressKeyCallback("mouse", mouseBtn)
                } catch as err {
                    UtilityHelper.ReportError("鼠标键 " mouseBtn " 启动失败: " . err.Message)
                }
            }
        }
        
        for uSkillId in ["dodge", "potion", "forceMove"] {
            if (GUIManager.uCtrl[uSkillId]["enable"].Value) {
                try {
                    KeyHandler.PressKeyCallback("uSkill", uSkillId)
                } catch as err {
                    UtilityHelper.ReportError("功能键 " uSkillId " 启动失败: " . err.Message)
                }
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
    ; 检测与坐标常量
    static PIXEL_READ_RETRY := 2        ; 像素读取重试次数
    static PIXEL_READ_RETRY_SLEEP := 5  ; 像素读取重试间隔(ms)
    static RESOURCE_SAMPLE_COUNT := 5   ; 资源条采样点数
    static SKILL_COORD_BASE_X := 1550   ; 技能栏参考起点X
    static SKILL_COORD_STEP_X := 127    ; 技能栏格距X
    static SKILL_COORD_Y := 1940        ; 技能栏参考Y

    /**
     * 检查是否为鼠标按键
     * @param {Object} keyData - 按键数据
     * @returns {Boolean} - 是否为鼠标按键
     */
    static IsMouse(keyData) {
        return keyData.isMouse
    }

    /**
     * 通用按键处理
     * @param {Object} keyData - 按键数据
     */
    static HandleKeyMode(keyData) {
        uniqueKey := keyData.uniqueKey
        shiftEnabled := GUIManager.uCtrl["shift"]["enable"].Value

        switch keyData.mode {
            case 2: ; BUFF模式（队列模式复用预检结果，多线程模式回退到实时检测）
                isActive := keyData.HasProp("stateUrgent") ? !keyData.stateUrgent : this.IsSkillActive(keyData.id, keyData.coord)
                if (isActive) {
                    return
                }
                this._ExecuteKey(keyData, shiftEnabled)
            case 3: ; 按住模式
                if (!this.holdStates.Has(uniqueKey) || !this.holdStates[uniqueKey]) {
                    this.holdStates[uniqueKey] := {isMouse: this.IsMouse(keyData), key: keyData.key}
                    this._PressDown(keyData, shiftEnabled)
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
        if (shiftEnabled) {
            Send "{Blind}{Shift down}"
            this._Press(keyData)
            Send "{Blind}{Shift up}"
        } else {
            this._Press(keyData)
        }
    }

    /**
     * 单击按键（鼠标/键盘统一发送路径）
     * @param {Object} keyData - 按键数据
     */
    static _Press(keyData) {
        if (this.IsMouse(keyData))
            Click(keyData.key)
        else
            Send("{" keyData.key "}")
    }

    /**
     * 按住按键（Shift 修饰持续保持，由停止流程统一释放）
     * @param {Object} keyData - 按键数据
     * @param {Boolean} shiftEnabled - 是否启用Shift
     */
    static _PressDown(keyData, shiftEnabled) {
        if (shiftEnabled) {
            Send "{Blind}{Shift down}"
        }
        if (this.IsMouse(keyData))
            Click("down " keyData.key)
        else
            Send("{" keyData.key " down}")
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
            } catch as err {
                UtilityHelper.ReportError("停止技能定时器失败: " . keyData.uniqueKey . " - " . err.Message)
            }
            this.skillTimers.Delete(keyData.uniqueKey)
        }

        if (GUIManager.RunMod.Value == 1) {
            ; 先按新随机间隔重新武装一次性定时器，再执行按键，避免执行异常中断后续触发
            timerFunc := () => (
                SetTimer(timerFunc, -this._NextInterval(keyData)),
                this.HandleKeyMode(keyData)
            )
            this.skillTimers[keyData.uniqueKey] := timerFunc
            SetTimer(timerFunc, -this._NextInterval(keyData))
        } else if (GUIManager.RunMod.Value == 2) {
            KeyQueueManager.EnqueueKey(keyData)
        }
    }

    /**
     * 计算技能下一次触发间隔（基础间隔 + 随机延迟）
     * 随机开关与上限在启动时快照进 keyData，运行期间改动界面不生效
     * @param {Object} keyData - 按键数据
     * @returns {Integer} 下一次触发间隔（毫秒）
     */
    static _NextInterval(keyData) {
        if (keyData.randomEnabled) {
            return keyData.interval + UtilityHelper.RandomDelay(keyData.randomMax)
        }
        return keyData.interval
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
        defaults := ConfigManager.GetCtrlDefaults(
            category = "skill" ? "cSkill" : category = "mouse" ? "mSkill" : "uCtrl",
            id)

        key := isMouse ? id : Trim(config["key"].Value)
        if (key = "") {
            key := defaults.key
            config["key"].Value := key
            UtilityHelper.ReportError("技能键为空，已回退默认键: " . key)
        }
        mode := config.Has("mode") ? config["mode"].Value : 1
        interval := 0
        try {
            interval := Integer(config["interval"].Value)
        } catch {
        }
        if (interval < 1) {
            interval := defaults.interval
            config["interval"].Value := interval
            UtilityHelper.ReportError("技能间隔无效，已回退默认值: " . interval)
        }
        coord := this.GetSkillCoords(id)

        uniqueKey := category . ":" . id

        keyData := {
            key: key,                         ; 目标键/按钮
            mode: mode,                       ; 操作模式
            interval: interval,               ; 间隔时间（毫秒）
            uniqueKey: uniqueKey,             ; 唯一键（兼定时器键）
            isMouse: isMouse,                 ; 是否为鼠标按键
            id: id,                           ; 标识符（BUFF模式需要）
            coord: coord,
            randomEnabled: GUIManager.uCtrl["random"]["enable"].Value,  ; 随机延迟开关快照
            randomMax: GUIManager.uCtrl["random"]["max"].Value          ; 随机延迟上限快照
        }
     
        ; 模式调整
        keyData.mode := (!GUIManager.uCtrl["D4only"]["enable"].Value && (keyData.mode == 2 || keyData.mode == 4)) 
            ? 1 
            : keyData.mode

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
            if (!IsSet(coord) || !coord) {
                coord := this.GetSkillCoords(skillId)
            }
            if (!coord)
                return true

            hasValidRead := false
            loop this.PIXEL_READ_RETRY {
                try {
                    color := ColorDetector.GetPixelRGB(coord.x, coord.y)
                    hasValidRead := true
                    if (ColorDetector.IsGreen(color))
                        return true
                } catch as err {
                    UtilityHelper.ReportError("IsSkillActive 像素检测失败: " . err.Message)
                    Sleep this.PIXEL_READ_RETRY_SLEEP
                }
            }
            if (!hasValidRead)
                return true
            return false
        } catch as err {
            UtilityHelper.ReportError("IsSkillActive 异常: " . err.Message)
            return true
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
                
            coord := false
            
            if (Type(skillId) = "Integer" && skillId >= 1 && skillId <= 6) {
                windowInfo := WindowManager.GetWindowInfo()
                coord := WindowManager.ConvertCoord({
                    x: this.SKILL_COORD_BASE_X + this.SKILL_COORD_STEP_X * (skillId - 1), 
                    y: this.SKILL_COORD_Y
                }, windowInfo)
            }
            else if (skillId = "left") {
                windowInfo := WindowManager.GetWindowInfo()
                coord := WindowManager.ConvertCoord({
                    x: this.SKILL_COORD_BASE_X + this.SKILL_COORD_STEP_X * 4,  ; skillId 5
                    y: this.SKILL_COORD_Y
                }, windowInfo)
            }
            else if (skillId = "right") {
                windowInfo := WindowManager.GetWindowInfo()
                coord := WindowManager.ConvertCoord({
                    x: this.SKILL_COORD_BASE_X + this.SKILL_COORD_STEP_X * 5,  ; skillId 6
                    y: this.SKILL_COORD_Y
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

        loop this.RESOURCE_SAMPLE_COUNT {
            try {
                color := ColorDetector.GetPixelRGB(coord.x, coord.y + (A_Index - 1))
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
            } catch as err {
                UtilityHelper.ReportError("清理定时器失败: " . timerKey . " - " . err.Message)
            }
        }
        this.skillTimers.Clear()
    }

    /**
     * 重置按住状态
     */
    static ResetHoldStates() {
        if (this.holdStates.Count > 0) {
            for uniqueKey, state in this.holdStates {
                try {
                    if (state.isMouse)
                        Click("up " state.key)
                    else
                        Send("{" state.key " up}")
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
 * 负责管理按键队列，处理按键事件的入队、出队和执行逻辑
 * @version 2.0.0
 * @author Archenemy
 */
class KeyQueueManager {
    static keyConfigCache := Map()      ; 按键配置缓存 {uniqueKey: config}
    static expectedNext := Map()        ; 预计下次执行时刻 {uniqueKey: timestamp}
    static isRunning := false           ; 队列运行状态
    static QueueWorkerFunc := 0         ; 工作函数引用
    static MIN_WAKE_INTERVAL := 1       ; 最小唤醒间隔(ms)
    static MIN_INTERVAL := 5            ; 最短调度间隔(ms)
    static MAX_OVERSHOOT_RATIO := 0.5   ; 最大过冲矫正比例
    
    /**
     * 启动队列
     */
    static StartQueue() {
        this.StopQueue()
        this.isRunning := true
        if (this.QueueWorkerFunc == 0) {
            this.QueueWorkerFunc := () => this.ProcessCycle()
        }
        ; 不固定轮询：由 EnqueueKey / ProcessCycle 按最近执行时刻按需武装一次性定时器
    }
    
    /**
     * 停止队列
     */
    static StopQueue() {
        this.isRunning := false
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
        ; 直接复用启动时构建的 keyData 快照，避免第二套配置结构漂移
        keyData.priority := this.GetPriority(keyData.mode, keyData.id)
        this.keyConfigCache[uniqueKey] := keyData
        if (!this.expectedNext.Has(uniqueKey)) {
            this.expectedNext[uniqueKey] := A_TickCount - keyData.interval
        }
        this._ScheduleNext()
    }
    
    /**
     * 优先级计算函数
     * @param {Integer} mode - 按键模式
     * @param {String} id - 按键标识符
     * @param {Object} coord - 技能坐标（mode 2 需要，用于检测 BUFF 状态）
     * @returns {Integer} 优先级数值（mode 2 不活跃时返回 BOOST 值 10）
     */
    static GetPriority(mode, id := "", coord := false) {
        switch mode {
            case 4: return 4
            case 2:
                if (coord && !KeyHandler.IsSkillActive(id, coord))
                    return 10
                return 3
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
     * @description 快照收集到期按键，按优先级排序后批量执行，消除原逆序变异导致的索引混乱
     */
    static ProcessCycle() {
        if (!this.isRunning) {
            return
        }
        ; 批次执行期间不可被热键/其他线程中断，避免停止后回写队列造成残留
        Critical
        try {
            now := A_TickCount
            dueEntries := []
            for uniqueKey, config in this.keyConfigCache {
                nextExec := this.expectedNext.Get(uniqueKey, 0)
                if (now >= nextExec) {
                    dueEntries.Push({config: config, overshoot: now - nextExec})
                }
            }
            if (dueEntries.Length == 0) {
                return
            }
            ; BUFF 键每周期只做一次激活检测，同时写 stateUrgent 与 priority
            for entry in dueEntries {
                if (entry.config.mode == 2) {
                    isActive := KeyHandler.IsSkillActive(entry.config.id, entry.config.coord)
                    entry.config.stateUrgent := !isActive
                    entry.config.priority := (entry.config.coord && !isActive) ? 10 : 3
                }
            }
            this.SortDueEntries(dueEntries)
            for entry in dueEntries {
                try {
                    this.ExecuteKeyWithCorrection(entry.config, entry.overshoot, now)
                } catch as err {
                    UtilityHelper.ReportError("队列按键执行失败: " . entry.config.uniqueKey . " - " . err.Message)
                    ; 失败后按间隔推后调度，避免因 expectedNext 停留在过去而形成紧循环
                    if (this.expectedNext.Has(entry.config.uniqueKey)) {
                        this.expectedNext[entry.config.uniqueKey] := A_TickCount + Max(entry.config.interval, this.MIN_INTERVAL)
                    }
                }
            }
        } finally {
            ; 无论成功/失败/停止都重新武装调度，异常不会让队列停摆
            this._ScheduleNext()
        }
    }

    /**
     * 按最近执行时刻武装一次性定时器；队列为空时停用定时器
     */
    static _ScheduleNext() {
        if (!this.isRunning || this.QueueWorkerFunc == 0) {
            return
        }
        nextWake := 0
        for uniqueKey, nextExec in this.expectedNext {
            if (nextWake == 0 || nextExec < nextWake) {
                nextWake := nextExec
            }
        }
        if (nextWake == 0) {
            SetTimer(this.QueueWorkerFunc, 0)
            return
        }
        SetTimer(this.QueueWorkerFunc, -Max(nextWake - A_TickCount, this.MIN_WAKE_INTERVAL))
    }
    
    /**
     * 排序到期按键（priority > overshoot）
     * @param {Array} entries - 到期按键数组
     */
    static SortDueEntries(entries) {
        loop entries.Length - 1 {
            loop entries.Length - A_Index {
                left := entries[A_Index]
                right := entries[A_Index + 1]
                if (left.config.priority < right.config.priority
                    || (left.config.priority == right.config.priority && left.overshoot < right.overshoot)) {
                    entries[A_Index] := right
                    entries[A_Index + 1] := left
                }
            }
        }
    }
    
    /**
     * 执行按键并应用时间比率矫正
     * @param {Object} config - 按键配置
     * @param {Integer} overshoot - 过冲量(ms)
     * @param {Integer} now - 当前时刻
     */
    static ExecuteKeyWithCorrection(config, overshoot, now) {
        uniqueKey := config.uniqueKey
        if (config.mode == 3) {
            if (KeyHandler.holdStates.Has(uniqueKey) && KeyHandler.holdStates[uniqueKey]) {
                return
            }
            KeyHandler.HandleKeyMode(config)
            if (this.expectedNext.Has(uniqueKey)) {
                this.expectedNext.Delete(uniqueKey)
            }
            if (this.keyConfigCache.Has(uniqueKey)) {
                this.keyConfigCache.Delete(uniqueKey)
            }
            return
        }
        KeyHandler.HandleKeyMode(config)
        ; 停止后不再回写调度表，避免队列被重新填充
        if (!this.isRunning) {
            return
        }
        correction := 0
        if (overshoot > 0 && overshoot < config.interval) {
            correction := Min(overshoot, Floor(config.interval * this.MAX_OVERSHOOT_RATIO))
        }
        correctedInterval := Max(config.interval - correction, this.MIN_INTERVAL)
        randomOffset := config.randomEnabled ? UtilityHelper.RandomDelay(config.randomMax) : 0
        this.expectedNext[uniqueKey] := now + correctedInterval + randomOffset
    }
    
    /**
     * 清空队列
     */
    static ClearQueue() {
        this.keyConfigCache.Clear()
        this.expectedNext.Clear()
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
    static coordCache := Map()
    static lastWindowInfo := Map()
    
    ; 常量定义
    static D4_WINDOW_CLASS := "Diablo IV Main Window Class"
    static REFERENCE_WIDTH := 3840
    static REFERENCE_HEIGHT := 2160
    static REFERENCE_CENTER_X := 1920
    static REFERENCE_CENTER_Y := 1080
    static DIALOG_BTN_BASE_X := 50      ; 对话框红色按钮参考起点X
    static DIALOG_BTN_STEP_X := 90      ; 对话框红色按钮格距X
    static DIALOG_BTN_Y := 1440         ; 对话框红色按钮参考Y

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
        } catch as err {
            UtilityHelper.ReportError("获取窗口信息失败: " . err.Message)
        }

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
     * @param {Number|String} userX - X偏移（可选，不传则读取界面控件）
     * @param {Number|String} userY - Y偏移（可选，不传则读取界面控件）
     * @returns {Object} 转换后的坐标 {x, y}
     */
    static ConvertCoord(coord, windowInfo := unset, userX := unset, userY := unset) {

        if (!IsSet(windowInfo)) {
            windowInfo := this.GetWindowInfo()
        }
        if (!IsSet(userX) || !IsSet(userY)) {
            userX := GUIManager.uCtrl["xy"]["x"].Value
            userY := GUIManager.uCtrl["xy"]["y"].Value
        }

        x := Round(windowInfo["CD4W"] + (coord.x - windowInfo["D44KWC"]) * windowInfo["D4SW"])
        y := Round(windowInfo["CD4H"] + (coord.y - windowInfo["D44KHC"]) * windowInfo["D4SH"])

        ; 始终应用用户偏移（独立双轴缩放后无需条件判断）
        x += userX
        y += userY

        return {x: x, y: y}
    }

    /**
     * 获取所有预定义坐标
     * @returns {Map} 所有坐标的映射
     */
    static GetAllCoord() {
        currentWindowInfo := this.GetWindowInfo()
        if (this.lastWindowInfo.Has("D4W") && this.coordCache.Count > 0) {
            if (this.lastWindowInfo["D4W"] == currentWindowInfo["D4W"] &&
                this.lastWindowInfo["D4H"] == currentWindowInfo["D4H"]) {
                return this.coordCache
            }
        }
        this.lastWindowInfo := currentWindowInfo.Clone()
        this.coordCache := Map()
        KeyHandler.ClearCoordCache()
        ; 偏移量每轮只读一次，避免每个坐标转换重复读取控件
        userX := GUIManager.uCtrl["xy"]["x"].Value
        userY := GUIManager.uCtrl["xy"]["y"].Value

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
            this.coordCache[name] := this.ConvertCoord(coord, currentWindowInfo, userX, userY)
        }

        loop 6 {
            this.coordCache["dialog_red_btn_" . A_Index] := this.ConvertCoord({
                x: this.DIALOG_BTN_BASE_X + this.DIALOG_BTN_STEP_X * (A_Index - 1), 
                y: this.DIALOG_BTN_Y
            }, currentWindowInfo, userX, userY)
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
            }, currentWindowInfo, userX, userY)
        }

        return this.coordCache
    }

    /**
     * 重置所有缓存
     */
    static ResetCache() {
        this.coordCache.Clear()
        this.lastWindowInfo := Map()
        KeyHandler.ClearCoordCache()
    }
}

/**
 * 迟滞检测器类
 * 对单个暂停源的检测状态做阈值计数，避免单帧抖动触发切换
 * @version 1.0.0
 */
class HysteresisTracker {
    static PAUSE_THRESHOLD := 2   ; 连续触发暂停条件达到该次数才切换
    static RESUME_THRESHOLD := 2  ; 连续触发恢复条件达到该次数才切换
    missCount := 0                ; 连续触发暂停条件的帧数
    hitCount := 0                 ; 连续触发恢复条件的帧数

    /**
     * 更新迟滞计数并返回应执行的暂停动作
     * @param {Boolean} pauseSignal - 本帧触发暂停的条件是否满足
     * @param {Boolean} resumeSignal - 本帧触发恢复的条件是否满足
     * @param {Boolean} isPaused - 当前是否处于暂停状态
     * @returns {Integer} - 0=无动作, 1=触发暂停, -1=触发恢复
     */
    Update(pauseSignal, resumeSignal, isPaused) {
        if (isPaused) {
            if (resumeSignal) {
                this.hitCount++
                this.missCount := 0
                if (this.hitCount >= HysteresisTracker.RESUME_THRESHOLD) {
                    this.hitCount := 0
                    return -1
                }
            } else {
                this.hitCount := 0
            }
        } else {
            if (pauseSignal) {
                this.missCount++
                this.hitCount := 0
                if (this.missCount >= HysteresisTracker.PAUSE_THRESHOLD) {
                    this.missCount := 0
                    return 1
                }
            } else {
                this.missCount := 0
            }
        }
        return 0
    }

    /**
     * 重置计数
     */
    Reset() {
        this.missCount := 0
        this.hitCount := 0
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
    static bloodTracker := HysteresisTracker()
    static tabTracker := HysteresisTracker()
    static enterTracker := HysteresisTracker()
    static DIALOG_GRAY_POINT := "dialog_gray_bg"
    static DIALOG_RED_POINTS := ["dialog_red_btn_1", "dialog_red_btn_2", "dialog_red_btn_3", "dialog_red_btn_4", "dialog_red_btn_5", "dialog_red_btn_6"]
    static CheckTimer := Map()

    /**
     * 管理所有检测定时器的启动和停止
     * @param {Boolean} enable - true: 启动定时器, false: 停止定时器
     */
    static ManageTimers(enable) {
        if (enable) {
            this.UpdateTimerConfig()
            for timerName, timerConfig in this.CheckTimer {
                if (timerConfig.enabled) {
                    SetTimer(timerConfig.func, timerConfig.interval)
                } else {
                    SetTimer(timerConfig.func, 0)
                }
            }
        } else {
            this.InitializeTimerConfig()
            for timerName, timerConfig in this.CheckTimer {
                try {
                    SetTimer(timerConfig.func, 0)
                } catch as err {
                    UtilityHelper.ReportError("停止检测定时器失败: " . timerName . " - " . err.Message)
                }
            }
            this.ResetCounters()
        }
    }

    /**
     * 初始化定时器配置（仅首次调用时创建闭包）
     */
    static InitializeTimerConfig() {
        if (this.CheckTimer.Count > 0) {
            return
        }
        this.CheckTimer["CheckWindow"] := {
            func: ObjBindMethod(this, "CheckWindow"),
            enabled: true,
            interval: 100
        }
        this.CheckTimer["AutoPauseByBlood"] := {
            func: ObjBindMethod(this, "AutoPauseByBlood"),
            enabled: false,
            interval: 50
        }
        this.CheckTimer["AutoPauseByTAB"] := {
            func: ObjBindMethod(this, "AutoPauseByTAB"),
            enabled: false,
            interval: 100
        }
    }

    /**
     * 更新定时器配置的启用状态和检测间隔
     * 闭包复用，仅更新动态参数
     */
    static UpdateTimerConfig() {
        this.InitializeTimerConfig()
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
        this.CheckTimer["AutoPauseByBlood"].enabled := d4Only && blood
        this.CheckTimer["AutoPauseByBlood"].interval := bloodInterval
        this.CheckTimer["AutoPauseByTAB"].enabled := d4Only && tab
        this.CheckTimer["AutoPauseByTAB"].interval := tabInterval
    }

    /**
     * 重置所有检测计数器
     */
    static ResetCounters() {
        this.bloodTracker.Reset()
        this.tabTracker.Reset()
        this.enterTracker.Reset()
        this.CheckTimer.Clear()
    }

    /**
     * 窗口切换检查函数
     */
    static CheckWindow() {
        d4only := GUIManager.uCtrl["D4only"]["enable"].Value
        pause := false
        reasonName := "窗口切换"
        if (d4only) {
            d4Exists := WindowManager.IsD4WindowExists()
            d4Active := WinActive("ahk_class Diablo IV Main Window Class")
            pause := !d4Active
            if (pause) {
                reasonName := d4Exists ? "D4 未激活" : "未检测到 D4 窗口"
            }
        } else {
            pause := WinActive("ahk_id " GUIManager.myGui.Hwnd)
        }
        MacroController.TogglePause("window", pause, reasonName)
    }

    /**
     * 检测关键界面点（TAB界面和技能栏）
     * @param {Map} allcoords - 坐标映射
     * @returns {Object} - 包含isBlueColor和isRedColor的检测结果
     */
    static CheckKeyPoints(allcoords) {
        dfxCoord := allcoords["skill_bar_blue"]
        tabCoord := allcoords["tab_interface_red"]

        colorDFX := ColorDetector.GetPixelRGB(dfxCoord.x, dfxCoord.y)
        colorTAB := ColorDetector.GetPixelRGB(tabCoord.x, tabCoord.y)

        return {
            isBlueColor: ColorDetector.IsBlue(colorDFX), 
            isRedColor: ColorDetector.IsRed(colorTAB)
        }
    }

    /**
     * 检测输入框和对话框
     * @param {Map} allcoords - 坐标映射
     * @returns {Boolean} - 是否检测到对话框
     */
    static CheckPauseByEnter(allcoords) {
        try {
            coord := allcoords[this.DIALOG_GRAY_POINT]
            grayColor := ColorDetector.GetPixelRGB(coord.x, coord.y)

            if (!ColorDetector.IsGray(grayColor))
                return false

            for , point in this.DIALOG_RED_POINTS {
                coord := allcoords[point]
                colorObj := ColorDetector.GetPixelRGB(coord.x, coord.y)

                if (ColorDetector.IsRed(colorObj)) {
                    return true
                }
            }
            
            return false
            
        } catch as err {
            UtilityHelper.ReportError("对话框检测失败: " . err.Message)
            return false
        }
    }

    /**
     * 检测血条（通用实现）
     * 对指定坐标进行8次随机偏移采样，命中≥4次即判定为检测到血条
     * @param {String} baseCoordName - allcoords中的坐标键名
     * @param {Map} allcoords - 坐标映射
     * @returns {Boolean} - 是否检测到血条
     */
    static _CheckBloodBar(baseCoordName, allcoords) {
        try {
            baseCoord := allcoords[baseCoordName]
            hitCount := 0

            loop 8 {
                offsetX := Random(-2, 2)
                offsetY := Random(-2, 2)

                sampleX := baseCoord.x + offsetX
                sampleY := baseCoord.y + offsetY

                color := ColorDetector.GetPixelRGB(sampleX, sampleY)

                if (ColorDetector.IsRed(color)) {
                    hitCount++
                    if (hitCount >= 4) {
                        return true
                    }
                }
            }
            return false
        } catch as err {
            UtilityHelper.ReportError("血条检测失败: " . err.Message)
            return false
        }
    }

    /**
     * 血条检测暂停逻辑
     * 采用迟滞（hysteresis）计数机制：连续N帧满足条件才触发状态切换，
     * 避免像素级单帧误检导致的频繁启停抖动。
     * 直接调用 _CheckBloodBar，优先检测怪物血条（高频场景），
     * 未命中时短路检测Boss血条。
     * @returns {void}
     */
    static AutoPauseByBlood() {
        allcoords := WindowManager.GetAllCoord()
        bloodDetected := false
        try {
            bloodDetected := this._CheckBloodBar("monster_blood", allcoords)
                          || this._CheckBloodBar("boss_blood", allcoords)
        } catch {
            ; 像素检测异常时保持 bloodDetected = false
        }
        action := this.bloodTracker.Update(
            !bloodDetected, bloodDetected, MacroController.IsPaused("blood"))
        if (action > 0) {
            MacroController.TogglePause("blood", true)
        } else if (action < 0) {
            MacroController.TogglePause("blood", false)
        }
    }

    /**
     * TAB界面和对话框检测暂停逻辑
     * 定时检测界面状态并自动暂停/启动宏
     */
    static AutoPauseByTAB() {
        allcoords := WindowManager.GetAllCoord()

        try {
            keyPoints := this.CheckKeyPoints(allcoords)

            action := this.tabTracker.Update(
                !keyPoints.isBlueColor && keyPoints.isRedColor,
                keyPoints.isBlueColor,
                MacroController.IsPaused("tab"))
            if (action > 0) {
                MacroController.TogglePause("tab", true)
            } else if (action < 0) {
                MacroController.TogglePause("tab", false)
            }

            dialogDetected := this.CheckPauseByEnter(allcoords)
            action := this.enterTracker.Update(
                dialogDetected, !dialogDetected, MacroController.IsPaused("enter"))
            if (action > 0) {
                MacroController.TogglePause("enter", true)
            } else if (action < 0) {
                MacroController.TogglePause("enter", false)
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
    ; 蓝色判定阈值
    static BLUE_MIN_B := 60
    static BLUE_RATIO_R := 1.2
    static BLUE_RATIO_G := 1.2
    static BLUE_MIN_DOMINANCE := 30
    ; 红色判定阈值
    static RED_MIN_R := 60
    static RED_RATIO_G := 2
    static RED_RATIO_B := 3
    static RED_MIN_DOMINANCE := 40
    ; 绿色判定阈值
    static GREEN_MIN_G := 70
    static GREEN_RATIO_R := 1.3
    static GREEN_RATIO_B := 3
    static GREEN_MIN_DOMINANCE := 40
    ; 灰色判定阈值
    static GRAY_MAX_RANGE := 40
    static GRAY_MIN_AVG := 10
    static GRAY_MAX_BRIGHT := 80

    /**
     * 获取指定坐标像素的RGB颜色值
     * 每次调用执行单次屏幕像素读取，不做缓存。
     * @param {Integer} x - X坐标
     * @param {Integer} y - Y坐标
     * @returns {Integer} - 0xRRGGBB 格式的整数颜色值
     */
    static GetPixelRGB(x, y) {
        return PixelGetColor(x, y, "RGB")
    }
    
    ; 蓝色检测
    static IsBlue(color) {
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF
        return (b > this.BLUE_MIN_B &&
                b > r * this.BLUE_RATIO_R && 
                b > g * this.BLUE_RATIO_G &&
                b - Max(r, g) > this.BLUE_MIN_DOMINANCE)
    }
    ; 红色检测
    static IsRed(color) {
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF
        return (r > this.RED_MIN_R &&
                r > g * this.RED_RATIO_G &&
                r > b * this.RED_RATIO_B &&
                r - Max(g, b) > this.RED_MIN_DOMINANCE)
    }
    ; 绿色检测
    static IsGreen(color) {
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF
        return (g > this.GREEN_MIN_G &&
                g > r * this.GREEN_RATIO_R && 
                g > b * this.GREEN_RATIO_B &&
                g - Max(r, b) > this.GREEN_MIN_DOMINANCE)
    }
    ; 灰色检测
    static IsGray(color) {
        r := (color >> 16) & 0xFF
        g := (color >> 8) & 0xFF
        b := color & 0xFF
        mixcolor := Max(r, g, b)
        mincolor := Min(r, g, b)
        range := mixcolor - mincolor
        avgColor := (r + g + b) / 3
        return (range < this.GRAY_MAX_RANGE &&
                avgColor > this.GRAY_MIN_AVG && 
                mixcolor < this.GRAY_MAX_BRIGHT)
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
    static configSchema := ""          ; 配置 schema 缓存（_BuildConfigSchema 结果）
    /**
     * 写入INI键值，自动转换为字符串
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
     * 读取INI键值，失败时返回默认值
     */
    static Read(section, key, defaultValue := "") {
        try {
            return IniRead(this.settingsFile, section, key, String(defaultValue))
        } catch {
            return String(defaultValue)
        }
    }
    /**
     * 删除整个INI节
     */
    static DeleteSection(section) {
        try {
            IniDelete(this.settingsFile, section)
            return true
        } catch {
            return false
        }
    }
    /** 从控件Map提取字段值并序列化写入INI */
    static _SaveCtrl(section, key, ctrlMap, fieldDefs) {
        values := []
        for fieldDef in fieldDefs {
            values.Push(ctrlMap[fieldDef.name].Value)
        }
        this.Write(section, key, UtilityHelper.Join(values, ","))
    }
    /** 从INI读取CSV并按字段定义回填控件Map */
    static _LoadCtrl(section, key, ctrlMap, fieldDefs, defaultCSV) {
        parts := StrSplit(this.Read(section, key, defaultCSV), ",")
        if (parts.Length < fieldDefs.Length) {
            return
        }
        for i, fieldDef in fieldDefs {
            ctrlMap[fieldDef.name].Value := (fieldDef.isInt ? Integer(parts[i]) : parts[i])
        }
    }
    /**
     * 构建配置项 schema（保存与加载共用，字段定义唯一化）
     * @returns {Array} schema 条目数组
     */
    static _BuildConfigSchema() {
        if (this.configSchema != "") {
            return this.configSchema
        }

        fieldKeyEnableIntervalMode := [
            {name: "key", isInt: false}, {name: "enable", isInt: true},
            {name: "interval", isInt: true}, {name: "mode", isInt: true}
        ]
        fieldEnableIntervalMode := [
            {name: "enable", isInt: true}, {name: "interval", isInt: true}, {name: "mode", isInt: true}
        ]
        fieldKeyEnableInterval := [
            {name: "key", isInt: false}, {name: "enable", isInt: true}, {name: "interval", isInt: true}
        ]
        fieldEnableInterval := [
            {name: "enable", isInt: true}, {name: "interval", isInt: true}
        ]
        fieldEnableMax := [
            {name: "enable", isInt: true}, {name: "max", isInt: true}
        ]

        schema := []
        loop 5 {
            schema.Push({
                key: "skill" . A_Index,
                ctrlType: "cSkill",
                ctrlId: A_Index,
                fields: fieldKeyEnableIntervalMode,
                default: A_Index . ",1,20,1"
            })
        }
        schema.Push({key: "left", ctrlType: "mSkill", ctrlId: "left", fields: fieldEnableIntervalMode, default: "0,80,1"})
        schema.Push({key: "right", ctrlType: "mSkill", ctrlId: "right", fields: fieldEnableIntervalMode, default: "1,300,1"})
        schema.Push({key: "dodge", ctrlType: "uCtrl", ctrlId: "dodge", fields: fieldKeyEnableInterval, default: "Space,0,20"})
        schema.Push({key: "potion", ctrlType: "uCtrl", ctrlId: "potion", fields: fieldKeyEnableInterval, default: "q,0,3000"})
        schema.Push({key: "forceMove", ctrlType: "uCtrl", ctrlId: "forceMove", fields: fieldKeyEnableInterval, default: "e,0,50"})
        schema.Push({key: "ipPause", ctrlType: "uCtrl", ctrlId: "ipPause", fields: fieldEnableInterval, default: "0,50"})
        schema.Push({key: "tabPause", ctrlType: "uCtrl", ctrlId: "tabPause", fields: fieldEnableInterval, default: "0,100"})
        schema.Push({key: "dcPause", ctrlType: "uCtrl", ctrlId: "dcPause", fields: fieldEnableInterval, default: "1,2"})
        schema.Push({key: "mouseAutoMove", ctrlType: "uCtrl", ctrlId: "mouseAutoMove", fields: fieldEnableInterval, default: "0,1000"})
        schema.Push({key: "random", ctrlType: "uCtrl", ctrlId: "random", fields: fieldEnableMax, default: "0,10"})
        this.configSchema := schema
        return schema
    }
    /**
     * 按 schema 中的控件类型解析控件 Map
     * @param {String} ctrlType - 控件类型（cSkill/mSkill/uCtrl）
     * @param {String|Integer} ctrlId - 控件标识
     * @returns {Map|Boolean} 控件 Map 或 false
     */
    static _GetCtrl(ctrlType, ctrlId) {
        switch ctrlType {
            case "cSkill": return GUIManager.cSkill[ctrlId]
            case "mSkill": return GUIManager.mSkill[ctrlId]
            case "uCtrl": return GUIManager.uCtrl[ctrlId]
        }
        return false
    }
    /**
     * 按控件类型与标识获取默认键位和间隔（数据源：配置 schema 默认值，避免两处默认值漂移）
     * @param {String} ctrlType - 控件类型（cSkill/mSkill/uCtrl）
     * @param {String|Integer} ctrlId - 控件标识
     * @returns {Object} 默认值 {key, interval}
     */
    static GetCtrlDefaults(ctrlType, ctrlId) {
        for entry in this._BuildConfigSchema() {
            if (entry.ctrlType = ctrlType && entry.ctrlId = ctrlId) {
                parts := StrSplit(entry.default, ",")
                key := ""
                interval := 20
                for i, fieldDef in entry.fields {
                    if (fieldDef.name = "key")
                        key := parts[i]
                    else if (fieldDef.name = "interval")
                        interval := Integer(parts[i])
                }
                return {key: key, interval: interval}
            }
        }
        return {key: "", interval: 20}
    }
    /**
     * 将当前UI配置序列化写入INI
     */
    static SaveProfile(profileName) {
        try {
            this.DeleteSection(profileName)
            section := profileName
            for item in this._BuildConfigSchema() {
                this._SaveCtrl(section, item.key, this._GetCtrl(item.ctrlType, item.ctrlId), item.fields)
            }
            this.Write(section, "runMode", GUIManager.RunMod.Value)
            this.Write(section, "shift", GUIManager.uCtrl["shift"]["enable"].Value)
            this.Write(section, "D4only", GUIManager.uCtrl["D4only"]["enable"].Value)
            this.Write(section, "xyX", GUIManager.uCtrl["xy"]["x"].Value)
            this.Write(section, "xyY", GUIManager.uCtrl["xy"]["y"].Value)
            this.Write(section, "hotkeyMode", GUIManager.startkey["mode"].Value)
            this.Write(section, "useHotKey", GUIManager.startkey["userkey"][1].key)
            return true
        } catch as err {
            UtilityHelper.ReportError("保存配置失败: " . err.Message)
            return false
        }
    }
    /**
     * 从INI反序列化配置到UI控件
     */
    static LoadProfile(profileName) {
        try {
            section := profileName
            for item in this._BuildConfigSchema() {
                this._LoadCtrl(section, item.key, this._GetCtrl(item.ctrlType, item.ctrlId), item.fields, item.default)
            }
            GUIManager.RunMod.Value := this.Read(section, "runMode", "1")
            GUIManager.uCtrl["shift"]["enable"].Value := this.Read(section, "shift", "0")
            GUIManager.uCtrl["D4only"]["enable"].Value := this.Read(section, "D4only", "1")
            GUIManager.uCtrl["xy"]["x"].Value := this.Read(section, "xyX", "0")
            GUIManager.uCtrl["xy"]["y"].Value := this.Read(section, "xyY", "0")
            GUIManager.startkey["mode"].Value := this.Read(section, "hotkeyMode", "1")
            GUIManager.startkey["userkey"][1].key := this.Read(section, "useHotKey", "F1")
            GUIManager.startkey["guiHotkey"].Value := GUIManager.startkey["userkey"][1].key
            HotkeyManager.LoadStartHotkey()
            return true
        } catch as err {
            UtilityHelper.ReportError("加载配置失败: " . err.Message)
            return false
        }
    }
    /**
     * 获取配置方案列表，确保默认方案存在
     */
    static GetProfileList() {
        profilesString := this.Read("Profiles", "List", this.defaultProfile)
        profileList := StrSplit(profilesString, "|")
        found := false
        for name in profileList {
            if (name = this.defaultProfile) {
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
    /**
     * 删除指定配置方案（默认方案受保护）
     */
    static DeleteProfile(profileName) {
        if (profileName = this.defaultProfile) {
            return false
        }
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
            if (profile = profileName) {
                return true
            }
        }
        return false
    }
    /**
     * 确保配置文件存在，不存在则创建默认内容
     */
    static EnsureConfigFile() {
        if (FileExist(this.settingsFile)) {
            return true
        }
        try {
            ; 由 IniWrite 创建：新文件自动使用 UTF-16 LE（带 BOM），
            ; 与后续读写保持同一机制，避免手工拼写 INI 文本格式
            IniWrite(this.defaultProfile, this.settingsFile, "Profiles", "List")
            IniWrite(this.defaultProfile, this.settingsFile, "Global", "LastUsedProfile")
            return true
        } catch {
            return false
        }
    }
    /**
     * 更新下拉框选项列表并恢复选中状态
     */
    static UpdateDropDown(ctrl, selectProfile := "") {
        try {
            profileList := this.GetProfileList()
            currentText := (selectProfile != "") ? selectProfile : ctrl.Text
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
     * 从UI保存当前配置方案
     */
    static SaveProfileFromUI() {
        profileNameInput := Trim(GUIManager.profileName.Text)
        if (!this.SaveProfile(profileNameInput)) {
            GUIManager.statusBar.Text := "保存配置失败"
            return
        }
        if (!this.ProfileExists(profileNameInput)) {
            profileList := this.GetProfileList()
            profileList.Push(profileNameInput)
            this.SaveProfileList(profileList)
        }
        this.UpdateDropDown(GUIManager.profileName, profileNameInput)
        this.SetLastUsedProfile(profileNameInput)
        GUIManager.statusBar.Text := "配置方案「" profileNameInput "」已保存"
    }
    /**
     * 加载选中的配置方案（兼容字符串和控件两种入参）
     */
    static LoadSelectedProfile(ctrl, *) {
        selectedProfile := (Type(ctrl) = "String") ? ctrl : Trim(ctrl.Text)
        if (selectedProfile = "" || !this.ProfileExists(selectedProfile)) {
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
     * 从UI删除配置方案（默认方案则重置内容）
     */
    static DeleteProfileFromUI() {
        currentProfileName := Trim(GUIManager.profileName.Text)
        if (currentProfileName = "") {
            GUIManager.statusBar.Text := "请先选择要删除的配置方案"
            return
        }
        if (!this.ProfileExists(currentProfileName)) {
            GUIManager.statusBar.Text := "未找到配置方案: " currentProfileName
            return
        }
        if (currentProfileName = this.defaultProfile) {
            this.DeleteSection(this.defaultProfile)
            this.LoadSelectedProfile(this.defaultProfile)
            GUIManager.statusBar.Text := "默认配置已重置"
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
     * 初始化配置管理器：创建文件、加载上次方案
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
    static doubleClickResumeTimer := ObjBindMethod(MacroController, "TogglePause", "doubleClick", false)

    if (!GUIManager.uCtrl["dcPause"]["enable"].Value)
        return

    currentTime := A_TickCount

    if (currentTime - lastClickTime < 400) {
        MacroController.TogglePause("doubleClick", true)
        confirmTime := Integer(GUIManager.uCtrl["dcPause"]["interval"].Value) || 2
        SetTimer(doubleClickResumeTimer, -confirmTime * 1000)
        lastClickTime := 0
    } else {
        lastClickTime := currentTime
    }
}

GUIManager.Initialize()
