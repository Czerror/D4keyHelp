class ConfigTestComboBox {
    Text := ""
    Value := 0
    Delete() {
    }
    Add(items) {
    }
}

TestConfig() {
    configDir := A_WorkingDir
    ConfigManager.settingsFile := configDir "\legacy.ini"
    FileAppend(
        "[Profiles]`r`nList=测试方案|另一个方案`r`n"
        . "[Global]`r`nLastUsedProfile=测试方案`r`n"
        . "[测试方案]`r`nskill1=2,0,73,3`r`nrunMode=2`r`nxyX=-21`r`nuseHotKey=F5`r`n"
        . "[另一个方案]`r`nrunMode=1`r`n保留=中文`r`n",
        ConfigManager.settingsFile, "UTF-16"
    )
    for entry in ConfigManager._BuildConfigSchema() {
        fields := Map()
        for field in entry.fields
            fields[field.name] := {Value: ""}
        ctrlType := entry.ctrlType
        GUIManager.%ctrlType%[entry.ctrlId] := fields
    }
    GUIManager.RunMod := {Value: ""}
    GUIManager.uCtrl["shift"] := Map("enable", {Value: ""})
    GUIManager.uCtrl["D4only"] := Map("enable", {Value: ""})
    GUIManager.uCtrl["xy"] := Map("x", {Value: ""}, "y", {Value: ""})
    GUIManager.startkey := Map("mode", {Value: ""}, "userkey", [{key: "", input: true}], "guiHotkey", {Value: ""})
    GUIManager.profileName := ConfigTestComboBox()
    GUIManager.statusBar := {Text: ""}
    HotkeyManager.DefineProp("LoadStartHotkey", {Call: (*) => 0})

    Assert(ConfigManager.LoadProfile("测试方案"), "旧中文方案加载")
    Assert(GUIManager.RunMod.Value = 2 && GUIManager.cSkill[1]["interval"].Value = 73, "旧方案自定义字段")
    Assert(GUIManager.cSkill[2]["interval"].Value = 20 && GUIManager.uCtrl["D4only"]["enable"].Value = 1, "缺失字段加载缺省值")
    Assert(GUIManager.uCtrl["xy"]["x"].Value = -21 && GUIManager.startkey["userkey"][1].key = "F5", "坐标与启动热键")

    oldSection := IniRead(ConfigManager.settingsFile, "测试方案")
    GUIManager.profileName.Text := "测试方案"
    GUIManager.cSkill[1].Delete("interval")
    ConfigManager.SaveProfileFromUI()
    Assert(GUIManager.statusBar.Text = "保存配置失败", "正文序列化失败应报告失败")
    Assert(IniRead(ConfigManager.settingsFile, "测试方案", "skill1", "") = "2,0,73,3", "序列化失败保留旧正文")
    GUIManager.cSkill[1]["interval"] := {Value: 73}

    FileSetAttrib("+R", ConfigManager.settingsFile)
    try {
        ConfigManager.SaveProfileFromUI()
        Assert(GUIManager.statusBar.Text = "保存配置失败", "正文写入失败应报告失败")
    } finally {
        FileSetAttrib("-R", ConfigManager.settingsFile)
    }
    Assert(IniRead(ConfigManager.settingsFile, "测试方案") = oldSection, "正文写入失败保留旧节")

    GUIManager.RunMod.Value := 1
    ConfigManager.SaveProfileFromUI()
    Assert(InStr(GUIManager.statusBar.Text, "已保存"), "保存旧方案应报告成功")
    Assert(ConfigManager.LoadProfile("测试方案") && GUIManager.RunMod.Value = 1, "多线程模式重载")
    GUIManager.RunMod.Value := 2
    ConfigManager.SaveProfileFromUI()
    Assert(ConfigManager.LoadProfile("测试方案") && GUIManager.RunMod.Value = 2, "单线程模式重载")
    Assert(GUIManager.cSkill[1]["interval"].Value = 73 && GUIManager.startkey["userkey"][1].key = "F5", "重载保留受支持的旧字段")
    Assert(IniRead(ConfigManager.settingsFile, "Profiles", "List") = "默认|测试方案|另一个方案", "保存补齐默认方案并保留列表")
    Assert(IniRead(ConfigManager.settingsFile, "另一个方案", "保留") = "中文", "保留其他方案")

    beforeInvalidName := FileRead(ConfigManager.settingsFile)
    for name in ["", "profiles", "GLOBAL", "无效|方案", "无效]方案", "无效`n方案", "无效`r方案"] {
        GUIManager.profileName.Text := name
        ConfigManager.SaveProfileFromUI()
        Assert(GUIManager.statusBar.Text = "保存配置失败", "拒绝无法保存的方案名")
        Assert(FileRead(ConfigManager.settingsFile) = beforeInvalidName, "拒绝方案名时保留原 INI")
    }

    originalWrite := ConfigManager.GetOwnPropDesc("Write")
    for failureSection in ["Profiles", "Global"] {
        name := failureSection = "Profiles" ? "列表重试" : "上次使用重试"
        previous := ConfigManager.GetLastUsedProfile()
        ConfigManager.DefineProp("Write", {Call: FailConfigMetadata.Bind(originalWrite.Call, failureSection)})
        GUIManager.profileName.Text := name
        try {
            ConfigManager.SaveProfileFromUI()
            Assert(GUIManager.statusBar.Text = "保存配置失败", failureSection " 写入失败应报告失败")
            Assert(ConfigManager.GetLastUsedProfile() = previous, "写入失败保留之前的最后使用方案")
        } finally {
            ConfigManager.DefineProp("Write", originalWrite)
        }
        ConfigManager.SaveProfileFromUI()
        Assert(InStr(GUIManager.statusBar.Text, "已保存"), "修复写入权限后修改可重试")
        Assert(ConfigManager.ProfileExists(name) && ConfigManager.GetLastUsedProfile() = name, "重试恢复元数据")
    }

    ConfigManager.settingsFile := configDir "\new.ini"
    GUIManager.profileName.Text := ConfigManager.defaultProfile
    ConfigManager.SaveProfileFromUI()
    Assert(InStr(GUIManager.statusBar.Text, "已保存"), "首次保存默认方案")
    file := FileOpen(ConfigManager.settingsFile, "r", "UTF-16-RAW")
    try {
        file.Pos := 0
        Assert(file.ReadUShort() = 0xFEFF, "新文件含 UTF-16 LE BOM")
    } finally {
        file.Close()
    }
    FileSetAttrib("+R", ConfigManager.settingsFile)
    try {
        ConfigManager.DeleteProfileFromUI()
        Assert(GUIManager.statusBar.Text = "删除配置失败", "默认方案重置失败应报告失败")
        Assert(GUIManager.cSkill[1]["interval"].Value = 73, "默认方案重置失败保留当前配置")
    } finally {
        FileSetAttrib("-R", ConfigManager.settingsFile)
    }
    ConfigManager.DeleteProfileFromUI()
    Assert(GUIManager.statusBar.Text = "默认配置已重置", "默认方案仍可通过删除入口重置")
    Assert(GUIManager.cSkill[1]["interval"].Value = 20, "重置恢复缺省值")
}

FailConfigMetadata(write, failureSection, self, section, key, value) {
    if (section = failureSection)
        return false
    return write(self, section, key, value)
}

TestConfig()
