# AXAuditDaemon 元素 frame 验证 · 2026-09-05

**本次没有从 AXAuditDaemon 取得元素 frame，因此“它能向 Host 提供每个元素的准确 frame”仍未成立。已测试的属性查询路径返回空值；这不是对所有未公开 selector、属性映射和系统版本的不可能性证明。**

已阅读「agent-soma调研」最后三轮关于 AX 树、版本兼容性和元素坐标的对话。本次只验证坐标获取，不改变产品后端选择。

## 本地历史证据

- [原来的直接协议报告](README.md)明确写了“本轮没有取得节点坐标”。[calculator-ax.json](evidence/calculator-ax.json)保存的 24 个 focus 对象中，没有 frame / rect / bounds / position / size 字段。
- [calculator-ax-details.json](evidence/calculator-ax-details.json)证明 `deviceElement:valueForAttribute:` 可用，但只查询了 Label、Identifier、Hierarchy；不包含几何信息。
- [已有带 frame 的观察示例](../../docs/examples/observe/spike-observe.json)来自自写 XCTest Runner。它证明的是 XCTest 路径，不能用作 AXAuditDaemon 路径的成功证据。

## 本次真机结果

设备：iPhone13,3，iOS 26.6 / 23G71。Host：Xcode 16.0 / 16A242d；Python 3.13；pymobiledevice3 11.3.1。复用设备既有开发服务，通过原生 CoreDevice 隧道和 RSD 连接 `com.apple.accessibility.axAuditDaemon.remoteserver.shim.remote`。本次没有启动 XCTest 会话、安装 App 或注入点击。

最终有效样本采集于北京时间 10:53:47–10:53:52，遍历了计算器当前可聚焦的 24 个元素。逐个使用同一元素引用调用：

```text
deviceElement:valueForAttribute:
    AXAuditElement_v1
    AXAuditElementAttribute_v1
```

| 查询描述符 | 次数 | 实际响应 |
| --- | ---: | --- |
| Label，string 类型 | 24 | 全部返回非空字符串，含数字 2 的标签 `2` |
| Frame / AXFrame，rect 类型，各测试 IsInternal=false / true | 96 | 全部 `null` |
| ElementRect / ElementFrame，rect 类型 | 48 | 全部 `null` |
| Position / AXPosition，point 类型 | 48 | 全部 `null` |
| Size / AXSize，size 类型 | 48 | 全部 `null` |

共 240 次几何查询，零非空响应、零查询异常。Label 是请求编码、元素引用和服务连接的阳性对照。上述几何属性名是候选，并非设备自己声明支持的属性；这些 null 不能解释为“设备内部不知道元素位置”。

类型编号通过本机 AccessibilityAuditDeviceManager 二进制的 `-[XDMDeviceFakeGeneric sendFocusUpdate]` 中测试属性构造调用确认：string=2、rect=4、size=8、point=16。[二进制哈希和反汇编证据](evidence/frame-protocol-types.json)。这些是 Host 侧类型编码证据，不是 iOS 端支持这些属性名的证明。

两张 DVT 截图均为 1170×2532，目视确认都在计算器 `2+3=5` 页面：[查询前](evidence/calculator-frame-verification-before.png)、[查询后](evidence/calculator-frame-verification-after.png)。截图与查询不是原子快照；Inspector 高亮发生了变化，不能声称前后像素完全相同。因没有获得矩形，未能计算相对截图或 XCTest 基准的坐标误差。

## 补充路径与边界

- `deviceInspectorPreviewOnElement:` 对一个已枚举的计算器元素发出请求后，2 秒观察窗口内没有收到事件；不据此断言该 selector 无效。
- `testTypeHitRegion` 和 `testTypeContrast` 两项 audit 均收到完成事件和“No issues”日志，返回空 issue 数组。本次没有取得可核对的 `ElementRectValue_v1`。[原始 audit / preview 事件](evidence/frame-paths.json)。
- [上游源码](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/accessibilityaudit.py)中，`ElementRectValue_v1` 是 `AXAuditIssue_v1` 的字段，`list-items` 使用的 focus 对象便捷输出不包含 frame。模型中有矩形字段，不足以证明任意元素的几何查询已打通。
- 中间一次正确类型的试探遇到了手机自动锁屏，返回时间和 Locked 元素；保存在 [frame-typed.json](evidence/frame-typed.json)，**不计入计算器最终样本**。用户再次解锁后才采集上表结果。
- 完成后已关闭本轮 Inspector visuals 和 App monitoring；[清理后的截图](evidence/frame-cleanup.png)确认绿色高亮消失。

因此，应把前述 session 的“每个元素大概率可以取坐标”保留为待验证假设。当前可用的本地 frame 成功证据仍属于 XCTest。若继续研究 AXAuditDaemon，需要定位 iOS 端实际接受的属性映射或其他几何返回路径，并用同屏基准验证坐标；仅凭框架字符串、audit 模型字段或设备能画高亮，不能宣布成功。

## 证据与复现

- [最终原始响应](evidence/calculator-frame-verification.json)：保留 focus 字段、每次查询描述符及原始返回值。
- [结果汇总与原始文件 SHA-256](evidence/calculator-frame-summary.json)。
- [可复现探针](frame_probe.py)：50 秒总时限、每次查询 3 秒时限、最多 80 个 focus 元素；本次正常完成且未触发上限。

先按 [直接协议报告](README.md#复现)准备 pymobiledevice3 11.3.1 环境和 RSD 隧道。解锁手机，打开计算器并保持亮屏，然后运行；主机地址和端口必须使用当前隧道的输出：

```sh
/tmp/agentsoma-frame-venv/bin/python spikes/ios-direct/frame_probe.py \
  --host "$RSD_HOST" --port "$RSD_PORT" --name calculator-frame-verification
```

原始截图和 JSON 位于已忽略的 `evidence/` 中；探针和本报告可纳入版本控制。
