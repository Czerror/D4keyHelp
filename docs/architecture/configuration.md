# 界面与配置

| 类名 | 职责 | 关键方法 |
| --- | --- | --- |
| `GUIManager` | 创建界面和托盘入口，展示运行状态 | `Initialize()`、`UpdateStatus()`、`ExitApp()` |
| `ConfigManager` | 按共享 schema 在控件和 INI 方案之间读写配置 | `SaveProfileFromUI()`、`SaveProfile()`、`LoadProfile()` |
| `UtilityHelper` | 随机延迟、输入值约束、日志和鼠标自动移动等公共操作 | `RandomDelay()`、`LimitEditValue()`、`DebugLog()`、`StartMove()` |

方案保存在脚本同目录的 `settings.ini`。保存完成后，界面显示保存结果；运行模式和按键设置如何进入调度，见[运行与按键](runtime.md)。
