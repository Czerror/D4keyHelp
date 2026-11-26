# 运行与按键

| 类名 | 职责 | 关键方法 |
| --- | --- | --- |
| `HotkeyManager` | 注册和更新全局启动热键 | `LoadStartHotkey()`、`UpdateHotkeyText()` |
| `MacroController` | 宏启停、暂停原因与停止清理 | `ToggleMacro()`、`TogglePause()`、`StopMacro()` |
| `KeyHandler` | 按运行模式注册动作，执行按键策略，记录并释放持有的键 | `PressKeyCallback()`、`HandleKeyMode()`、`ResetHoldStates()` |
| `KeyQueueManager` | 调度单线程队列，按优先级执行到期动作 | `EnqueueKey()`、`ProcessCycle()` |

开始按钮和全局热键都调用 `MacroController.ToggleMacro()`。多线程模式为每个启用的键预约独立定时器；单线程模式从队列中取出到期动作。两条路径都进入 `KeyHandler.HandleKeyMode()`，在那里决定连点、按住、补 BUFF 或检查资源。

任一暂停原因生效时，控制器取消按键调度并释放已持有的键。最后一个暂停原因解除后，控制器重新启动调度。窗口失焦、血条和对话框等信号来自[窗口与取色](detection.md)。
