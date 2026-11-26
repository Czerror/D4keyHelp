#Requires AutoHotkey v2.0.31
#SingleInstance Off
global DEBUG := false
global debugLogFile := A_ScriptDir "\debugd4.log"
OnError(TestError)

TestError(err, *) {
    FileAppend(err.Message " (line " err.Line ")`n", "**", "UTF-8")
    ExitApp(1)
}

Assert(condition, message) {
    if !condition
        throw Error(message)
}

class TestIO {
    static active := true
    static events := []
    static Record(action, value) {
        this.events.Push({action: action, value: value})
    }
}

; Script-local functions shadow the input APIs in this isolated interpreter.
Send(keys) => TestIO.Record("Send", keys)
Click(button) => TestIO.Record("Click", button)
MouseMove(x, y, speed := 0) => TestIO.Record("MouseMove", x)
Hotkey(*) => 0
WinActive(criteria) => InStr(criteria, "Diablo IV") && TestIO.active
