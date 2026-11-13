// SPDX-License-Identifier: GPL-2.0-only
import Foundation

enum ConsoleStatusText {
    static func chinese(for reason: UInt32) -> (head: String, detail: String) {
        switch reason {
        case 1: return ("已连接：没有正在运行的游戏", "启动游戏后画面会出现在这里；想看 HOME 菜单需在 Switch 端开启 Stream the HOME menu 并重启。")
        case 2: return ("已连接：游戏不在前台", "回到游戏，或开启 HOME 菜单串流。")
        case 3: return ("已暂停：说明书、eShop 或其他小程序已打开", "关闭后几秒恢复。")
        case 4: return ("串流已关闭", "在 Switch Frame Tap 浮层或设置应用中打开。")
        case 5: return ("这个游戏被排除在串流之外", "在设置应用中移除排除项。")
        case 6: return ("当前系统版本未经测试", "可在 config.ini 设置 allow_untested_firmware = 1。")
        case 7: return ("视频引擎无响应", "重启 Switch 后再串流。")
        case 8: return ("内存不足，暂时无法串流", "每隔几秒会自动重试。")
        case 9: return ("没有找到游戏画面", "重启游戏；反复出现请收集日志。")
        case 10: return ("正在启动串流…", "")
        case 11: return ("已暂停：键盘已打开", "关闭键盘后恢复。")
        case 12: return ("游戏画面高于 1080p", "最高支持 1920×1080。")
        case 13: return ("USB 连接太慢", "请改用网络模式。")
        default: return ("主机状态（代码 \(reason)）", "")
        }
    }
}
