# SFTap — Switch 串流 iPhone 版

用 iPhone 看 Switch 画面并用屏幕手柄操作。通过 Tailscale 在家里的 Mac 上做子网路由，iPhone 在外面也能直接连到 Switch 的局域网地址。

- 仅适配 iPhone，横屏，iOS 17 及以上；工程需要 Xcode 16 或更新版本
- Swift + SwiftUI/UIKit + VideoToolbox，无第三方依赖
- 走 Switch Frame Tap 的 SFTR/SFTI 协议，Switch 端不用改任何东西

## 1. Switch 端准备

在 Switch 的 Switch Frame Tap 应用里：

- `Connection` 设为 `Network`
- `Beta` 页开启 `Stream the HOME menu`（异地启动／切换游戏必须开）和 `Controls from the viewer`（触屏手柄必须开）
- 远程串流建议 `Quality = Medium`、`Max resolution = 720`
- 改完重启 Switch

同时在 Switch 系统设置里关闭自动睡眠；建议插底座并用有线网卡。
在家中路由器为 Switch 设置 DHCP 地址保留，保证重启后地址不变。HOME 采集仍是 Beta 功能，eShop、说明书等小程序可能暂停画面；先在家验证能从 HOME 启动游戏，再做异地测试。

## 2. Tailscale：让 iPhone 在外面也能连到 Switch

Switch 提供局域网 TCP 服务，手机在家用 Wi-Fi 就能直连；出门在外需要 Mac 把 Switch 的局域网 IP 路由进 Tailnet。**SFTR 本身没有鉴权或加密，不要把 TCP 9950 映射到公网。** 不需要申请公网 IP，Mac 只做网络转发，不需要运行桌面播放器。

1. Mac、iPhone 都登录同一个 Tailscale 账号。
2. 在 Mac 上宣告路由（把 `<Switch IP>` 换成 Switch 的局域网地址，例如 `192.168.1.50`）：

   ```sh
   sudo tailscale set --advertise-routes=192.168.1.50/32
   ```

   macOS 在宣告路由时会自动开启 IP 转发，不用单独设置。App Store / Standalone 版本需要先在 Tailscale 设置里启用 CLI 集成，或者直接调包内可执行文件：

   ```sh
   sudo /Applications/Tailscale.app/Contents/MacOS/Tailscale set --advertise-routes=192.168.1.50/32
   ```

3. 到 Tailscale 管理控制台批准路由：Machines → 找到这台 Mac → Edit route settings → 打开这条 `/32` 路由。
4. iPhone 默认接受 Tailnet 路由，不用设置。
5. 在 tailnet 策略中限制访问。下面仅允许示例账号 `you@example.com` 访问示例 Switch 的 TCP 9950；两个值都需要替换：

   ```json
   {
     "acls": [
       {
         "action": "accept",
         "src": ["you@example.com"],
         "proto": "tcp",
         "dst": ["192.168.1.50:9950"]
       }
     ]
   }
   ```

   ACL / grants 允许规则是叠加生效的。**只新增这条规则，不能收紧已有的全员放行规则**；需先核对并按需修改覆盖该地址的宽泛规则，同时保留其他设备所需访问权限。按账号授权会允许该账号的所有设备，不是绑定某一台 iPhone；多人 tailnet 需进一步设置设备标签或设备身份限制。在管理控制台用策略测试确认其他账号不能访问此地址。
   `--advertise-routes` 会替换这台 Mac 当前宣告的路由列表；如果它已有其他子网路由，需要在命令中一并保留。

6. 验证连通性：

   ```sh
   tailscale ping your-iphone
   tailscale status
   ```

   将 `your-iphone` 换成控制台里的 iPhone 名称或 Tailscale IP。测试时手机先关闭 Wi-Fi、改用蜂窝网络，避免误以为局域网直连就是异地连接成功。`tailscale ping` 输出公网 `IP:端口` 或 `direct ...` 表示直连；`via DERP(...)` 表示走中继，延迟可能明显增加。穿透效果取决于网络，不能保证所有网络下都适合低延迟游玩。

7. Mac 保持在线：系统设置 → 电池/能源 → 打开「防止自动睡眠」类选项，并勾选「断电后自动启动」。
   具体选项因 Mac 型号而异，MacBook 也不要合盖睡眠。iPhone 在 Tailscale App 中开启 VPN；iOS 默认接受已批准的子网路由。

以上配置依据 [Tailscale 子网路由文档](https://tailscale.com/docs/features/subnet-routers?tab=macos)。若中继延迟偏高，可检查家中 IPv6、路由器 UPnP / NAT-PMP；自建中继不在本项目第一阶段范围。

## 3. 构建安装

1. 复制签名配置并填上自己的开发者账号：

   ```sh
   cp ios/SFTap/Config/Signing.local.xcconfig.example ios/SFTap/Config/Signing.local.xcconfig
   ```

   把 `DEVELOPMENT_TEAM` 填成 Apple Developer Team ID，`PRODUCT_BUNDLE_IDENTIFIER` 改成自己唯一的 ID（文件已被 gitignore，不会提交）。

2. 打开 `ios/SFTap.xcodeproj`，选自己的 iPhone，Run。
3. 第一次安装到手机：设置 → 通用 → VPN 与设备管理 → 信任开发者证书；如果是 iOS 16+ 还需要在 设置 → 隐私与安全性 里开启「开发者模式」。

命令行构建（模拟器，免签名）：

```sh
xcodebuild -project ios/SFTap.xcodeproj -scheme SFTap -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

## 4. 使用

- 首页填 Switch 的局域网 IP（或主机名）和端口（默认 9950），点「连接」。
- 出画面后屏幕上就是虚拟手柄：左下浮动摇杆和十字键、右下 ABXY 加右摇杆、顶上 ZL/L、ZR/R，上中 −/+，下中 截图/HOME，摇杆附近的小圆点是 L3/R3。
- 顶部中央「⋯」是菜单：设置、断开连接。菜单几秒不用会变淡，点击即可打开。打开设置期间释放手柄，关闭后以中立状态重新接管。
- 设置里有：静音、音频缓冲（低延迟 40 ms / 标准 80 ms / 稳定 150 ms）、手柄透明度/大小、触感反馈、隐藏手柄、显示统计信息。
- 切到后台会自动松开手柄并断开，回到前台自动重连。
- 小屏幕会自动限制手柄最大尺寸，避免按键重叠。截图键发送的是 Switch 的截图按键，不会把画面保存到 iPhone。
- 统计中的「接收→显示」测量的是从收到 SFTR 包头到提交显示队列的本地耗时，不含画面在 Switch 上采集、网络传输前半段或屏幕实际扫描时间，不能等同于端到端延迟。

## 5. 本地测试（不用真 Switch）

仓库里的回放服务器能把录好的码流当 Switch 播：

```sh
python3 android-tv/tools/replay_server.py logs/m83-runI/stream-first10.sft --tone --input --bind 127.0.0.1 --no-beacon
```

- `--tone` 生成 48 kHz 立体声测试音
- `--input` 在视频包头标 128（接受输入），并打印收到的 SFTK/SFTI
- Debug 构建的模拟器启动参数加 `-autoConnectHost 127.0.0.1 -showStats YES` 可以直接连上测试

自检脚本（会跑两段：普通回放 + `--input` 日志校验）：

```sh
python3 android-tv/tools/test_replay_server.py
swift test --package-path ios/SFTCore
```

自检脚本使用临时 TCP 端口，不与正在运行的 9950 回放服务抢连接。回放服务也可用 `--port` 指定其他端口，默认仍为 9950。

本机已验证协议测试、模拟器／真机 SDK 免签名编译、回放显示、断线重连及前后台释放手柄。模拟器不等于真机：实际声音、触感、Switch HOME 切换、Tailscale 蜂窝链路和持续游玩发热仍需 iPhone + Switch 验证。建议依次验证局域网音视频与手柄、HOME 启动其他游戏、蜂窝网络串流，再测试 Wi-Fi／蜂窝切换恢复。
## 6. 常见问题

- **连接被拒（refused）**：Switch 没在跑网络串流。把 `Connection` 设为 `Network` 并重启 Switch。
- **连不上/超时**：同一时间只能一个播放器连 Switch —— 看看电脑或别的设备是不是还连着；再检查 Tailscale 是否在线、地址对不对。
- **手柄没反应**：在 Switch 端 Beta 页开启 `Controls from the viewer` 并重启；第一次接入时游戏可能要在「更改握法/顺序」界面确认一下手柄。
- **卡顿**：把 Switch 端 Quality 降到 Medium、Max resolution 降到 720；`tailscale status` 看看是不是走了 DERP 中继。
- **Switch 睡了**：串流叫不醒它，得有人在家按一下。

## 7. 代码结构

```
ios/
├── SFTCore/            纯协议库（Swift Package，跨平台可测）
│   └── Sources/SFTCore/  SFTR 解包、SFTI/手柄状态、H.264、视频策略、音频抖动缓冲
└── SFTap/              iOS App
    ├── SFTapApp.swift    入口、前后台生命周期、自动连接
    ├── Model/            设置（UserDefaults 持久化）
    ├── Stream/           NWConnection、会话/重连、VideoToolbox 解码、AVAudioEngine 播放、状态文本
    ├── Input/            虚拟手柄视图、SFTI 发送调度
    ├── UI/               首页、播放页、统计浮层、设置页
    └── Config/           Base.xcconfig + Signing.local.xcconfig（本地签名，不提交）
```
