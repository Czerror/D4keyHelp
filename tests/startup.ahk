; /Include places this observer ahead of the unmodified application entry point.
OnError((err, *) => (FileAppend(err.Message "`n", "**", "UTF-8"), ExitApp(1)))
SetTimer(WaitForStartup, 50)

WaitForStartup() {
    if (!IsObject(GUIManager.myGui) || !IsObject(GUIManager.statusBar))
        return
    if (!DllCall("IsWindowVisible", "Ptr", GUIManager.myGui.Hwnd))
        return
    if (MacroController.isRunning)
        throw Error("Startup unexpectedly armed the macro")
    if (!InStr(GUIManager.statusBar.Text, "配置已加载") || !FileExist(ConfigManager.settingsFile))
        return
    FileAppend("D4_TEST_COMPLETE`n", "*", "UTF-8-RAW")
    ExitApp(0)
}
