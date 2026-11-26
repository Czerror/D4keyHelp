# 窗口与取色

| 类名 | 职责 | 关键方法 |
| --- | --- | --- |
| `WindowManager` | 获取游戏客户区尺寸，将参考坐标换算成取样点 | `GetWindowInfo()`、`ConvertCoord()`、`GetAllCoord()` |
| `ColorDetector` | 单点取色，判断红、绿、蓝、灰 | `GetPixelRGB()`、`IsRed()`、`IsGreen()`、`IsBlue()`、`IsGray()` |
| `PauseDetector` | 检查窗口、敌方血条、地图和对话框，更新对应暂停原因 | `CheckWindow()`、`AutoPauseByBlood()`、`AutoPauseByTAB()` |
| `HysteresisTracker` | 累计连续命中次数，避免单次取色波动触发暂停或恢复 | `Update()`、`Reset()` |

血条、地图和对话框各有独立的 `HysteresisTracker` 实例。检测器向[宏控制器](runtime.md)报告暂停原因，启停按键由宏控制器统一处理。
