InitLifecycle(mode) {
    enabled := {Value: true}
    off := {Value: false}
    GUIManager.myGui := {Hwnd: 1}
    GUIManager.statusText := {Value: ""}
    GUIManager.statusBar := {Text: ""}
    GUIManager.RunMod := {Value: mode}
    GUIManager.uCtrl := Map(
        "D4only", Map("enable", {Value: true}),
        "mouseAutoMove", Map("enable", {Value: false}, "interval", {Value: 20}),
        "shift", Map("enable", {Value: false}),
        "random", Map("enable", off, "max", {Value: 10}),
        "xy", Map("x", {Value: 0}, "y", {Value: 0}),
        "ipPause", Map("enable", off), "tabPause", Map("enable", off),
        "dcPause", Map("enable", enabled, "interval", {Value: 1}),
        "dodge", Map("enable", off), "forceMove", Map("enable", off),
        "potion", Map("enable", off)
    )
    GUIManager.cSkill := Map(
        1, Map("enable", enabled, "mode", {Value: 1}, "key", {Value: "1"}, "interval", {Value: 20}),
        2, Map("enable", off), 3, Map("enable", off),
        4, Map("enable", off), 5, Map("enable", off)
    )
    GUIManager.mSkill := Map(
        "left", Map("enable", {Value: false}, "mode", {Value: 3}, "interval", {Value: 20}),
        "right", Map("enable", {Value: false}, "mode", {Value: 1}, "interval", {Value: 60})
    )
    TestIO.events.Length := 0
}

WaitLifecycle(ms) {
    Critical "Off"
    Sleep ms
}

CheckLifecycle(condition, label, failures) {
    if (!condition)
        failures.Push(label)
}

CountLifecycle(value) {
    count := 0
    for event in TestIO.events {
        if (event.value == value)
            count++
    }
    return count
}

IndexLifecycle(value) {
    for index, event in TestIO.events {
        if (event.value == value)
            return index
    }
    return 0
}

TestLifecycle() {
    failures := []
    for mode in [1, 2] {
        InitLifecycle(mode)
        TestIO.active := false
        MacroController.ToggleMacro()
        WaitLifecycle(70)
        CheckLifecycle(MacroController.IsPaused("window") && TestIO.events.Length == 0,
            "mode " mode ": startup outside D4 suppresses the first action", failures)
        MacroController.TogglePause("tab", true)
        TestIO.active := true
        PauseDetector.CheckWindow()
        WaitLifecycle(40)
        CheckLifecycle(TestIO.events.Length == 0,
            "mode " mode ": window resume preserves another pause reason", failures)
        MacroController.TogglePause("tab", false)
        WaitLifecycle(70)
        CheckLifecycle(TestIO.events.Length > 0,
            "mode " mode ": actions resume after the last pause reason clears", failures)
        GUIManager.RunMod.Value := 3 - mode
        MacroController.ToggleMacro()
        TestIO.events.Length := 0
        WaitLifecycle(70)
        CheckLifecycle(TestIO.events.Length == 0,
            "mode " mode ": changing mode then stopping cancels old actions", failures)
        KeyQueueManager.StopQueue()

        InitLifecycle(mode)
        GUIManager.cSkill[1]["mode"].Value := 3
        GUIManager.mSkill["left"]["enable"].Value := true
        GUIManager.mSkill["right"]["enable"].Value := true
        GUIManager.uCtrl["shift"]["enable"].Value := true
        GUIManager.uCtrl["mouseAutoMove"]["enable"].Value := true
        MacroController.ToggleMacro()
        if (mode == 1) {
            registration := KeyHandler.skillTimers["skill:1"]
            oldAction := registration.HasOwnProp("callback") ? registration.callback : registration
        } else {
            oldAction := KeyQueueManager.QueueWorkerFunc
        }
        oldMove := UtilityHelper.MoveMouseFunc
        oldWindow := PauseDetector.CheckTimer["CheckWindow"].func
        WaitLifecycle(100)
        CheckLifecycle(CountLifecycle("{Blind}{Shift down}") == 1
            && CountLifecycle("{Blind}{Shift up}") == 0
            && CountLifecycle("{Blind}{1 down}") == 1
            && CountLifecycle("down left") == 1 && CountLifecycle("right") > 0
            && IndexLifecycle("{Blind}{Shift down}") < IndexLifecycle("{Blind}{1 down}")
            && IndexLifecycle("{Blind}{Shift down}") < IndexLifecycle("down left"),
            "mode " mode ": repeated click keeps the Shift owned by held actions", failures)
        GUIManager.cSkill[1]["key"].Value := "2"
        GUIManager.uCtrl["shift"]["enable"].Value := false
        GUIManager.uCtrl["mouseAutoMove"]["enable"].Value := false
        GUIManager.RunMod.Value := 3 - mode
        MacroController.TogglePause("tab", true)
        CheckLifecycle(CountLifecycle("{Blind}{1 up}") == 1
            && CountLifecycle("up left") == 1 && CountLifecycle("{Blind}{Shift up}") == 1
            && IndexLifecycle("{Blind}{1 up}") < IndexLifecycle("{Blind}{Shift up}")
            && IndexLifecycle("up left") < IndexLifecycle("{Blind}{Shift up}"),
            "mode " mode ": pause releases held inputs after config changes", failures)
        TestIO.events.Length := 0
        WaitLifecycle(70)
        CheckLifecycle(TestIO.events.Length == 0,
            "mode " mode ": pause cancels old movement and key timers", failures)
        MacroController.ToggleMacro()
        if (!MacroController.HasMethod("HandleLeftClick")) {
            KeyQueueManager.StopQueue()
            UtilityHelper.StopMove()
            continue
        }
        oldAction()
        oldMove()
        CheckLifecycle(TestIO.events.Length == 0,
            "mode " mode ": cancelled callbacks do nothing after stopping", failures)

        GUIManager.RunMod.Value := mode
        MacroController.ToggleMacro()
        TestIO.active := false
        oldWindow()
        oldAction()
        oldMove()
        CheckLifecycle(!MacroController.IsPaused("window") && TestIO.events.Length == 0,
            "mode " mode ": old callbacks do nothing after restarting", failures)
        TestIO.active := true
        MacroController.HandleLeftClick()
        MacroController.HandleLeftClick()
        oldResume := MacroController.doubleClickResumeTimer
        MacroController.ToggleMacro()
        MacroController.ToggleMacro()
        MacroController.HandleLeftClick()
        MacroController.HandleLeftClick()
        oldResume()
        CheckLifecycle(MacroController.IsPaused("doubleClick"),
            "mode " mode ": old double-click callback cannot resume a later run", failures)
        MacroController.ToggleMacro()
    }
    for failure in failures
        FileAppend(failure "`n", "**")
    Assert(!failures.Length, failures.Length " lifecycle assertions failed")
}

AssertLifecycleExit(*) {
    if (CountLifecycle("{Blind}{1 up}") != 1
        || CountLifecycle("up left") != 1 || CountLifecycle("{Blind}{Shift up}") != 1)
        FileAppend("OnExit did not release held inputs`n", "**")
}

TestLifecycle()
InitLifecycle(2)
GUIManager.cSkill[1]["mode"].Value := 3
GUIManager.mSkill["left"]["enable"].Value := true
GUIManager.uCtrl["shift"]["enable"].Value := true
MacroController.ToggleMacro()
WaitLifecycle(80)
Assert(CountLifecycle("{Blind}{1 down}") == 1 && CountLifecycle("down left") == 1,
    "held inputs established before ExitApp")
OnExit(AssertLifecycleExit)
