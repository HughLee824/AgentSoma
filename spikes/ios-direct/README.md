# 无 WDA 真机验证 · 2026-09-04

**当前环境已验证截图、部分 AX 信息和应用启动/退出；尚未验证可用的点击、滑动和输入。因此还不能把这条纯协议路线定为 AgentSoma v0.1 的完整后端。**

本轮尝试的约束比“不使用 WDA”更严格：没有安装或启动任何自动化 Runner，也没有发起 XCTest 会话。这是验证路径，用户尚未确认产品是否必须排除所有 XCTest Runner。

## 实测环境

| 项目 | 值 |
| --- | --- |
| Mac | macOS 15.0.1 |
| Xcode | 16.0，未升级 |
| iPhone | iPhone13,3；iOS 26.6，23G71 |
| Developer Mode | 已开启 |
| 已挂载 DDI | Personalized；CoreDevice 518.31；ProductBuildVersion 17F42 |
| 探针依赖 | pymobiledevice3 11.3.1；Python 3.13 |
| 连接 | macOS 原生 CoreDevice 隧道，再通过 RSD 连接开发者服务 |

DDI 在验证开始前已挂载。本轮没有更换它，也没有安装 WDA、DeviceKit 或其他测试 App。Python 依赖通过临时 uv 缓存准备；pymobiledevice3 创建了自己的本机配置目录。

## 结果与证据

原始截图和响应保存在 `evidence/`，已加入 Git 忽略规则。表中的耗时是单次观测，不是基准测试。

| 能力 | 结果 | 证据与限制 |
| --- | --- | --- |
| 配对、原生隧道、RSD | 通过 | 当前 Mac/Xcode 环境可连接；RSD 建连约 70–85 ms |
| DVT 截图 | 通过 | `calculator-dvt.json/png`：1170×2532；抓图 440 ms，整个探针 605 ms；已目视确认计算器界面 |
| 锁屏状态下截图 | 有限制 | 初次 DVT 请求返回全黑图片；同时屏幕状态为 off。不能把“返回 PNG”当作“可用画面” |
| AX 元素列表 | 通过，范围有限 | `calculator-ax.json`：24 个元素，整个探针 1358 ms；有标签、朗读描述和部分 accessibilityIdentifier |
| AX 属性读取 | 部分通过 | `calculator-ax-details.json`：实际读到 Label、Identifier；层级查询返回一个 AXAuditNode，包含角色、描述、ignored 状态和元素引用 |
| 完整 AX 树、元素 bounds | 未验证 | 上述节点不构成完整树；本轮没有取得节点坐标。不能从字段名或能力清单推断完整支持 |
| 计算器 AX 激活 | 没有生效 | `calculator-activation.json`、`ax-press-before.png`、`ax-press-after.png`：请求激活数字 2 后，前后 RGB 像素完全相同；未证明具体失败原因 |
| 计算器退出、重新启动 | 通过 | `calculator-lifecycle.json`：SIGTERM 后进程消失，随后启动得到新 PID；`calculator-relaunched.png` 确认应用重新显示 |
| 独立获取前台 App | 未验证 | `deviceCurrentState` 返回 0；`deviceRunningApplications` 返回空数组。已知启动目标不等于通用前台识别 |
| CoreDevice 截图服务 | 当前环境缺失 | `initial-coredevice.json`：InvalidServiceError；DVT 截图路径可用 |
| CoreDevice 触控、键盘、屏幕流 | 当前环境缺失 | `inventory.json`、`unlocked-inventory.json`：锁屏与解锁时均未声明对应服务，无法开始该路径的输入验证 |
| CoreDevice lock state | 当前调用失败 | 虽然声明了 getlockstate feature，单独调用仍返回“Action ... is not implemented”；不是整个连接失败 |
| 断连恢复 | 部分通过 | 一次旧 RSD 地址报 No route to host；释放并重新建立原生隧道后获得新地址，截图与 AX 读取恢复。尚未实现自动恢复，也没有可重复的完整操作流程 |

本轮实际调用的是 DVT screenshot、AccessibilityAudit 和 CoreDevice app/device-info 服务。没有通过 WDA HTTP 接口或启动 XCTest Runner 来实现上述结果；这不等于审计了 Apple 服务内部的所有框架依赖。

## 对技术选型的影响

此前把“iOS 17+ 的 CoreDevice 连接能力”外推成“iOS 17+ 可直接注入触控”是不成立的。

上游对相同 HID 路径的实测报告指出，触控需要活动屏幕流来获得输入授权；iOS 26.3/26.5 上流启动被拒绝并提示需要 iOS 27。另一位贡献者声称私有实现能在更早版本工作，但没有公开可复现实现。因此只能说**本次候选实现的早期版本兼容性未成立**，不能说所有 iOS 26 无 Runner 方案都不可能。[go-ios #843](https://github.com/danielpaulus/go-ios/pull/843)、[go-ios #835](https://github.com/danielpaulus/go-ios/pull/835)

我们没有在这台 iOS 26.6 手机上换装新 DDI，所以“缺服务”是本机观测，“iOS 27 的流授权门槛”是上游证据。升级 Xcode 26 不能被视为已经验证的解法。

选型还需要对齐一个边界：

- **只排除 WDA 项目**：可以继续验证独立的 XCTest Runner，例如 DeviceKit。它公开提供点击、滑动、文本和 UI 树，但明确以 XCUITest 运行；本轮未安装或验证它。[DeviceKit README](https://github.com/mobile-next/devicekit-ios/blob/main/README.md)
- **同时排除所有 XCTest/Runner**：保留 DVT/AX/应用管理的已验证结果，继续研究原生输入及其 OS/DDI 前提。当前不能承诺 iOS 26 上的完整自动化，也不应为了延续假设而直接升级用户设备。

本轮 Python 工具仅用于验证，生产语言、接口形式和依赖策略尚未决定。

## 复现

在仓库根目录运行。先准备隔离环境：

```sh
uv venv /tmp/agentsoma-spike --python 3.13
uv pip install --python /tmp/agentsoma-spike/bin/python 'pymobiledevice3==11.3.1'
```

手机需要已信任此 Mac、开启 Developer Mode，并有兼容 DDI。本轮是在既有 DDI 上验证，以下命令不会自动更换它：

```sh
/tmp/agentsoma-spike/bin/pymobiledevice3 amfi developer-mode-status
/tmp/agentsoma-spike/bin/pymobiledevice3 mounter list
```

在第一个终端把 `IOS_UDID` 设为测试设备标识，然后启动隧道并保持终端打开。原生隧道需要 macOS 的本机服务访问权限；沙箱中可能无法完成设备发现。

```sh
/tmp/agentsoma-spike/bin/pymobiledevice3 remote start-tunnel --native --udid "$IOS_UDID" --script-mode
```

在第二个终端将 `RSD_HOST`、`RSD_PORT` 设为上述输出的地址和端口。地址可能在重连后改变。解锁手机并打开计算器：

```sh
/tmp/agentsoma-spike/bin/python spikes/ios-direct/probe.py inventory --host "$RSD_HOST" --port "$RSD_PORT" --name inventory
/tmp/agentsoma-spike/bin/python spikes/ios-direct/probe.py dvt-screenshot --host "$RSD_HOST" --port "$RSD_PORT" --name screen
/tmp/agentsoma-spike/bin/python spikes/ios-direct/probe.py ax --host "$RSD_HOST" --port "$RSD_PORT" --name elements
/tmp/agentsoma-spike/bin/python spikes/ios-direct/probe.py ax-details --host "$RSD_HOST" --port "$RSD_PORT" --name first-element-details
```

以下探针会启动计算器并尝试按数字 2，保存前后截图。`observed` 仅表示完成采集；`request_sent` 不代表操作成功。截图出现差异也需确认是否为预期结果，而非时钟或动画变化。

```sh
/tmp/agentsoma-spike/bin/python spikes/ios-direct/calculator.py --host "$RSD_HOST" --port "$RSD_PORT"
```

完成后在第一个终端按 Ctrl-C，释放本次隧道断言。AX 探针在结束时关闭自己开启的 App monitoring。

更多协议背景：[pymobiledevice3 隧道说明](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/)、[CLI 用法](https://doronz88.github.io/pymobiledevice3/guides/cli-recipes/)、[AX 源码](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/accessibilityaudit.py)。
