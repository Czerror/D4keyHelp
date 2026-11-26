CheckHeldAndReleased(mode) {
    enabled := {Value: 1}, off := {Value: 0}
    GUIManager.myGui := {Hwnd: 1}
    GUIManager.statusText := {Value: ""}
    GUIManager.statusBar := {Text: ""}
    GUIManager.RunMod := {Value: mode}
    GUIManager.uCtrl := Map(
        "D4only", Map("enable", enabled), "shift", Map("enable", {Value: 1}),
        "mouseAutoMove", Map("enable", {Value: 1}, "interval", {Value: 20}),
        "random", Map("enable", off, "max", {Value: 5}), "xy", Map("x", off, "y", off),
        "ipPause", Map("enable", off), "tabPause", Map("enable", off)
    )
    for id in ["dodge", "potion", "forceMove"]
        GUIManager.uCtrl[id] := Map("enable", off)
    loop 5
        GUIManager.cSkill[A_Index] := Map("enable", off)
    GUIManager.cSkill[1] := Map("enable", enabled, "mode", {Value: 3}, "key", {Value: "1"}, "interval", {Value: 20})
    GUIManager.mSkill["left"] := Map("enable", enabled, "mode", {Value: 3}, "interval", {Value: 20})
    GUIManager.mSkill["right"] := Map("enable", enabled, "mode", {Value: 1}, "interval", {Value: 40})

    TestIO.events.Length := 0
    TestIO.active := false
    MacroController.ToggleMacro()
    Assert(MacroController.IsPaused("window") && !TestIO.events.Length, "失焦启动必须先暂停")
    TestIO.active := true
    PauseDetector.CheckWindow()
    oldAction := mode == 1 ? KeyHandler.skillTimers["skill:1"].callback : KeyQueueManager.QueueWorkerFunc
    Critical "Off"
    Sleep(150)
    Assert(Sent("{1 down}") && Sent("down left") && Sent("{Blind}{Shift down}"), "确实按住了键盘、鼠标和 Shift")
    Assert(Sent("right") && !Sent("{Blind}{Shift up}"), "连点期间保持脚本的 Shift")

    GUIManager.RunMod.Value := 3 - mode
    GUIManager.cSkill[1]["key"].Value := "2"
    GUIManager.uCtrl["shift"]["enable"].Value := 0
    GUIManager.uCtrl["mouseAutoMove"]["enable"].Value := 0
    MacroController.ToggleMacro()
    Assert(Sent("{1 up}") && Sent("up left") && Sent("{Blind}{Shift up}"), "按实际持有的键释放")
    TestIO.events.Length := 0
    oldAction()
    Critical "Off"
    Sleep(150)
    Assert(!TestIO.events.Length, "切模式后停止仍有旧按键或鼠标移动")
}

Sent(value) {
    for event in TestIO.events
        if (event.value == value)
            return true
    return false
}

for mode in [1, 2]
    CheckHeldAndReleased(mode)
