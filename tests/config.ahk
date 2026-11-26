TestSave() {
    ConfigManager.settingsFile := A_ScriptDir "\legacy.ini"
    FileAppend("[Profiles]`r`nList=测试|另一个`r`n[Global]`r`nLastUsedProfile=测试`r`n"
        . "[测试]`r`nskill1=2,0,73,3`r`nrunMode=2`r`n[另一个]`r`n备注=中文`r`n",
        ConfigManager.settingsFile, "UTF-16")
    for item in ConfigManager._BuildConfigSchema() {
        fields := Map()
        for field in item.fields
            fields[field.name] := {Value: ""}
        kind := item.ctrlType
        GUIManager.%kind%[item.ctrlId] := fields
    }
    GUIManager.uCtrl["shift"] := Map("enable", {Value: 0})
    GUIManager.uCtrl["D4only"] := Map("enable", {Value: 1})
    GUIManager.uCtrl["xy"] := Map("x", {Value: 0}, "y", {Value: 0})
    GUIManager.RunMod := {Value: 0}
    GUIManager.startkey := Map("mode", {Value: 1}, "userkey", [{key: "F1"}], "guiHotkey", {Value: ""})
    GUIManager.profileName := {Text: "测试"}
    GUIManager.statusBar := {Text: ""}
    GUIManager.statusText := {Value: ""}
    HotkeyManager.DefineProp("LoadStartHotkey", {Call: (*) => 0})

    Assert(ConfigManager.LoadProfile("测试") && GUIManager.RunMod.Value == 2, "加载旧格式中文方案")
    GUIManager.cSkill[1]["interval"].Value := 91
    Assert(ConfigManager.SaveProfile("测试"), "写入方案")
    GUIManager.cSkill[1]["interval"].Value := 0
    Assert(ConfigManager.LoadProfile("测试") && GUIManager.cSkill[1]["interval"].Value == 91, "保存后重载")
    Assert(IniRead(ConfigManager.settingsFile, "另一个", "备注") == "中文", "其他方案保留")

    old := IniRead(ConfigManager.settingsFile, "测试")
    GUIManager.cSkill[1].Delete("interval")
    Assert(!ConfigManager.SaveProfileFromUI() && IniRead(ConfigManager.settingsFile, "测试") == old,
        "序列化失败须保留原方案")
    GUIManager.cSkill[1]["interval"] := {Value: 73}
    FileSetAttrib("+R", ConfigManager.settingsFile)
    try {
        Assert(!ConfigManager.SaveProfileFromUI() && GUIManager.statusBar.Text == "保存配置失败",
            "只读 INI 须报告写入失败")
        Assert(GUIManager.ExitApp(), "取消退出须保留主窗口")
        Assert(InStr(GUIManager.statusText.Value, "已停止") && GUIManager.statusBar.Text == "保存配置失败",
            "取消退出后能看到停止状态及保存错误")
    } finally {
        FileSetAttrib("-R", ConfigManager.settingsFile)
    }
}

MsgBox(text, title, options) {
    Assert(InStr(text, "保存失败") && InStr(options, "YesNo"), "退出前提示保存失败")
    return "No"
}

TestSave()
