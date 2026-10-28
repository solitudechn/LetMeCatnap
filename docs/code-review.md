# 代码审查：汉化版 iCanHazRepose 还能改什么

基线：`55b88bb`（= 上游最新）+ `iCanHazRepose-zh-localization.patch`
审查范围：`src/` 全部源码、`build.sh`、`Info.plist`、`README.md`
（后续轮次已扩展到 `core/`、`Tests/`、`scripts/`、`.github/`）

> **阅读提示**：本文是按轮次追加的审查日志，记录的是「当时」的结论。
> 前几轮判定的若干问题已被后续轮次修复或推翻（已在正文用删除线标出），
> 判断项目当前状态请看文末最新的「第十轮」与 [`docs/audit-2026-10-28.md`](audit-2026-10-28.md)。

---

## 一、汉化补丁本身的质量

结论：**质量不错，可以合并。** 检查过的地方：

- 补丁能干净应用到上游最新提交（`git apply --check` 全通过），没有冲突。
- 字符串覆盖完整：所有 UI 文本构造点（`NSMenuItem`、`NSTextField(labelWithString:)`、`NSAlert`、SwiftUI `Text()`、`errorDescription`）都已换成 `L10n.*`，没有漏掉的英文硬编码（剩下的都是 `deseven` / `Fikri Karim` / `boxicons` 这类专有名词，本来就不该翻）。
- `UpdateError.errorDescription` 也做了本地化，这点很多人会漏。
- `L10n` 用「代码里内联字符串表」而不是 `.lproj`，对 `build.sh` 这种手工拼 `.app` 的构建方式是合理取舍（`.lproj` 要改打包逻辑），注释里也解释了原因。

需要注意的两处（已在本分支修掉，见下一节）：菜单在语言切换时的重建时序、`System` 那一项在英文下中英混排。

---

## 二、这次已经改掉的问题

| # | 问题 | 影响 | 改动 |
|---|------|------|------|
| 1 | 自动更新读取的是**上游**仓库（`UpdateManager` 里写死 `owner = "deseven"`） | 最严重的一条：用户点「更新」会把汉化版整个替换成英文版；而且上游产物是 deseven 的 Developer ID 签名，本地版本是 ad-hoc 签名，签名身份校验必然失败 → 只会得到「更新失败」 | `owner/repo` 改为从 `AppConstants.githubOwner/githubRepo`（= 你的 fork）读，新增 `upstreamRepoURL` 仅用于署名链接 |
| 2 | 版本号只在 `Info.plist` 里写死，CI 发版无法注入 | 发版后 `CFBundleVersion` 和 tag 不一致，更新器比较版本会错乱 | `build.sh` 支持 `ICHR_VERSION`，打包时用 `PlistBuddy` 写进 `CFBundleVersion` 和新增的 `CFBundleShortVersionString` |
| 3 | `build.sh` 无法在 CI 运行 | 进度/错误输出写死 `> /dev/tty`，GitHub Actions 没有控制终端；`release` 模式还依赖 `create-dmg` 和自建上传脚本 `share` | 新增 `ci` 模式（release 配置 + 通用二进制 + zip/dmg，不上传不启动）；tty 探测并回退到 stderr；`create-dmg` 缺失或失败（无头环境里 Finder 脚本常失败）时回退 `hdiutil`，不再让发版死在窗口样式上 |
| 4 | 没有自动编译 / 自动发布 | — | 新增 `.github/workflows/ci.yml` 与 `release.yml`（见第三节） |
| 5 | 切语言时在菜单项回调里直接替换 `statusItem.menu` | AppKit 正在跟踪这个菜单，替换/释放它属于未定义行为，偶发崩溃或菜单卡住 | 改成 `DispatchQueue.main.async` 延后到下一轮 runloop 再重建 |
| 6 | `System` 菜单项文案是 `跟随系统 / System` | 英文界面下也显示中文，很怪 | 改成 `L10n.t("System", "跟随系统")`，跟着当前语言走 |
| 7 | 更新窗口标题被统一成「发现更新」 | 语义变了（原来是「软件更新」） | 新增 `L10n.softwareUpdate` 单独使用 |
| 8 | `GitHubRelease.parsedVersion` 只认 release 标题 | 标题不合约定时永远检测不到更新 | 标题解析失败时回退解析 `tag_name`（`v1.0.4`） |
| 9 | README 首页下载按钮、issue 链接、源码 clone 地址都指向上游 | 用户点下载拿到的是英文版 | 指向 fork，保留上游署名与 upstream 说明；补充 Gatekeeper 去隔离命令、发版流程说明 |

已验证的部分：`build.sh` 语法检查通过；用桩程序把 `ci` 模式完整跑通（9 步全绿、版本注入生效、zip 里就是 `iCanHazRepose.app`、无 tty 时输出正常回退、无 `create-dmg` 时跳过 DMG（第八轮改为回退 `hdiutil`，保证 DMG 一定产出））。
**Swift 代码未能在本机编译**：这台机器只有 Command Line Tools，没有完整 Xcode，SwiftUI 宏插件（`SwiftUIMacros`）加载不了，第一次 push 时以 CI 结果为准。~~（第八轮装上 Xcode 后已在本机全量编译并通过测试，见文末。）~~

---

## 三、CI / Release 怎么用

- `ci.yml`：push 到 `main` 或发 PR 时，跑 `./build.sh ci`，校验产物（版本号、架构、签名、zip 内容），把 `iCHR.zip` / `iCHR.dmg` 作为 artifact 上传（保留 14 天）。
- `release.yml`：推 `v1.0.4` 这样的 tag（或手动触发），编译 → 打 zip/dmg → 校验版本与 tag 一致 → 自动生成中文更新说明 → 创建 Release。

发布时有两条硬约束，改了自动更新就废：

1. Release 标题必须形如 `iCanHazRepose 1.0.4`（或 `iCHR 1.0.4`）；
2. 资产名必须**正好是** `iCHR.zip`（更新器按名字找）。

加这 5 个仓库 secret 就能签名 + 公证，不加就是 ad-hoc 签名（用户首次打开要清隔离）：

`MACOS_CERT_P12`（base64 的 .p12）、`MACOS_CERT_PASSWORD`、`NOTARY_APPLE_ID`、`NOTARY_TEAM_ID`、`NOTARY_APP_PASSWORD`

---

## 四、建议继续改的（按优先级，本次未动）

### P0 — 影响用户能不能用 / 会不会数据错乱

1. **正式签名 + 公证**。没有 Developer ID，下载用户看到的是「已损坏，无法打开」。workflow 已经预留好，拿到证书填 secret 即可。
2. **换签名证书会让老用户断更**。更新器用 `SecStaticCodeCopyDesignatedRequirement` 比对当前包与下载包的设计要求：ad-hoc（`identifier "wtf.d7.icanhazrepose"`）切到 Developer ID 后，旧包校验新包会失败，老用户必须手动装一次新包。建议在切换的那一版 Release 说明里写清楚。
3. ~~**版本号要和上游错开**~~。已按 `1.0.4` 首发，源码版本随发版推进（`Info.plist`）。
4. ~~**切语言后已打开的窗口不刷新**~~（第四轮已修：`AboutViewController.reloadForLanguageChange()`，`setLanguage` 时同步刷新可见窗口）。
5. **安装更新失败无提示**。`UpdateManager` 的安装脚本先 `rm -rf` 旧包再 `mv`，但 app 已经 `terminate` 了；若 `/Applications` 需要管理员权限，替换会静默失败，用户看到的是「app 打不开了」。建议：安装脚本失败时 `open` 一次旧路径，或改用「先写到临时目录、用 `osascript` 提权」的流程。

### P1 — 明显影响体验 / 可维护性

6. ~~**计时器有累积漂移**~~（第二轮已改为 wall-clock deadline：`workDeadline` / `breakDeadline`）。
7. ~~**README 与实现不一致**~~（已统一：空闲阈值固定 5 分钟，且改为可选的暂停时机）。
8. ~~**日志只有 stdout**~~（已加 `Log.swift` 文件日志：`~/Library/Logs/iCanHazRepose/`，1 MB 滚动）。
9. ~~**没有测试**~~（已加 `Tests/ICHRCoreTests` 与 `scripts/check-l10n.py`，两者都接进 CI）。
10. **没有格式化/静态检查**（行尾空格已清理；CI 仍无 lint，见第八轮待办）。
11. **bundle id 和上游相同**（`wtf.d7.icanhazrepose`）。同时装原版和汉化版会共用 `UserDefaults`、冲突「开机启动」注册（`SMAppService.mainApp` 按路径注册，容易残留）。如果希望两个版本共存，改成 `wtf.d7.icanhazrepose.zh`——代价是现有用户要重装一次。
12. **本地化方案的天花板**。现在是 `L10n.swift` 里硬编码两种语言，加第三种语言要改代码、且不能交给社区翻译。中期建议迁到 `Resources/<lang>.lproj/Localizable.strings` + `NSLocalizedString`，`build.sh` 里补一句 `cp -R res/lproj/*.lproj` 即可。

### P2 — 锦上添花

13. 用 Homebrew Cask 分发（`brew install --cask`），要开一个 tap。
14. 长期看建议换 **Sparkle 2**：签名校验、增量更新、进度条、beta 渠道都是现成的，比自研这套（约 490 行 + 安装脚本）更省心。自研的好处是零依赖、体积小。
15. 下载更新时加进度提示（现在只有「正在更新」和最终的失败弹窗）。
16. 关于窗口加一行「简体中文汉化：solitudechn」，符合 MIT 的署名习惯，也方便用户反馈到你的仓库。
17. `.roorules` 是上游给 AI 编码助手看的项目说明，保留没问题，建议在文件头注明来自上游。

---

## 已实现（本次迭代）

| 功能 | 落点 | 说明 |
|---|---|---|
| 休息引导语 | `L10n.breakTips` · `BreakOverlayView` · `CompactBreakOverlayView` | 每次休息随机一条（中英各 10 条），长休息期间每 20 秒换一条，取词时排除上一条避免重复 |
| 番茄节奏 | `SettingsKey.longBreakEvery` / `longBreakSeconds` · `TimerManager.startBreak()` | 每完成 N 个工作轮次进入长休息；菜单「番茄节奏」提供 关闭 / 2·10 / 3·15 / 4·15 / 4·25 / 5·30 六档，两个值编码进菜单项 tag 一起匹配 |
| 渐进式提醒 | `Settings.Key.progressiveReminders` · `TimerManager.updateImminentFlag()` | 剩余 1 分钟时菜单栏图标切 `hourglass` 并轻响一声；连续跳过 2 次后显示一句提示（**第六轮起不再阻止跳过**，Esc 始终有效） |
| 文件日志 | `Log.swift` | 写入 `~/Library/Logs/iCanHazRepose/iCanHazRepose.log`，串行队列 + 1 MB 滚动到 `.1.log`；启动时记录配置与日志路径 |

同时修掉了 P1 第 8 条（日志只有 stdout）。

---

## 第二轮代码级校验与修复（2026-10-27）

### 新增入口

- 菜单顶部新增 **立即休息 / Take a Break Now**（快捷键 `B`）：随时进入短休息；
  不消耗番茄工作轮次、不影响下一次长休息的位置；休息中禁用，重复调用无副作用。
- ~~主动手动休息会清除连续跳过计数~~（第三轮已推翻：只在真正完成休息时清零，否则「立即休息 + 跳过」可绕过提示）；会议中仍会延后弹出，保持“不打断会议”的原则。

### 本轮修复

| 问题 | 修复 |
|---|---|
| 每秒 `-1` 造成累计漂移，长休息误差更明显 | 工作与休息均改用 wall-clock deadline，延迟 tick 会补齐而不是永久延长 |
| 强制休息可被“重新开始计时”或会议检测绕过 | 统一状态转换；休息中禁止 restart，会议只中断非强制休息，且不计为用户跳过（*强制休息的概念已在第六轮整体移除*） |
| 最后 1 分钟提醒在暂停恢复后失效 | 按剩余区间计算提醒状态，恢复时可重新进入提醒 |
| 休息中修改“允许跳过”时按钮与 Esc 行为不一致 | 新增 `canSkipBreak` 作为视图、热键、状态机的唯一判断 |
| 长/短休息设置在当前休息中变化会改变进度环总量 | 开始休息时快照 `activeBreakTotalSeconds` |
| 结束动画期间可能重复调用 `endBreak()` | 增加 `isEndingBreak` 防重入 |
| 关闭会议暂停后会议图标可能残留 | 同时重置 `MeetingDetector` 和 `wasInMeeting` |
| 独立更新窗口点 Later/Skip 不关闭 | 非 sheet 情况改为 `window.close()` |
| 检查更新期间关闭关于窗口可能强制解包崩溃 | alert 展示前检查 window；缺失图标不再 force unwrap |
| Carbon Esc 回调 context 每次休息泄漏 | `OverlayManager` 保存并在注销 handler 后 release context |
| 异步日志在退出时可能丢最后一条 | 增加 `Log.flush()`，退出前等待队列完成 |
| Swift 6 主线程隔离前向兼容警告 | 更新完成后通过 `await MainActor.run` 终止应用 |

### 验证结果

- 13 个 Swift 源文件逐个 `swiftc -parse`：通过。
- 两个 SwiftUI 视图以桩替换后，其余 11 个源码文件 `swiftc -typecheck`：**0 error / 0 warning**。
- L10n 引用 70 个、菜单 selector 引用 11 个：无缺失。
- 25 项状态行为断言全部通过：立即休息、轮次计数、长休息、强制休息、会议延后/中断、deadline 到期、暂停恢复、跳过开关等。
- `build.sh` Bash 语法、两个 workflow YAML、Info.plist、`git diff --check`：通过。
- 本机仍无完整 Xcode，两个 SwiftUI 视图只能做语法检查；最终完整编译仍以推送后的 CI 为准。

### 复查（第二轮，推送前）

逐文件重审全部改动后又发现并修复 1 处竞态：

**`endBreak()` 的收尾动画可覆盖会议暂停（已修）** — `dismissWithAnimation` 的 0.45s 回调
无条件 `beginWorking`。若会议恰在该窗口内开始并暂停计时器，回调会把暂停冲掉，
计时器在会议中继续倒数。修复：回调先 `guard state == .onBreak`，被会议中断 /
用户跳过 / 系统唤醒接管时不再恢复工作。回归测试覆盖该竞态（32 项行为测试全过）。

其余复查结论：`L10n` 70 处引用零缺失；11 个菜单 selector 全部解析；视图引用的 8 个
`TimerManager` 成员全部存在（视图本身仍待 CI 编译）；`build.sh`/YAML/plist 校验通过；
无临时文件入库。已知留待观察的小项：会议中点「立即休息」会在会议结束后走 5 秒
倒计时再休息，且该次休息按自然到期计数（是否算轮次属设计选择，暂保持现状）。

### 复查（第三轮：视图已能真正类型检查）

**新增验证能力**：本机只有 Command Line Tools，`@State` 宏无法展开，此前两个视图只能做
`-parse` 语法检查。本轮用一个语义等价的 `ViewState` 属性包装器替换 `@State` 后，
**14 个文件全部通过 `-typecheck`（0 error / 0 warning）**，视图层的类型、成员引用、
修饰符与 macOS 13 可用性都得到了编译器验证。

**修复：强制休息可被「立即休息」绕过** — `startBreak()` 在手动休息开始时执行
`skipStreak = 0`。于是连跳两次后按 ⌘B 再跳过，计数被清零，强制休息永远触发不了。
改为只在 `endBreak()`（休息真正完成）时清零；跳过手动休息同样计为一次跳过。
新增 5 项回归测试（手动休息不重置计数 / 手动休息在 streak 2 时也强制 / 重开计时
无法绕过 / 完成休息才清零），行为测试增至 37 项，全部通过。

### 国际化专项核查（第四轮）

审计结果：69 组中英字符串对全部有中文、英文侧无中文泄漏；本轮新增 10 个文案键
（立即休息 / 番茄节奏 / 长休息 / 渐进式提醒 / 强制休息提示等）全部中英齐备；
中英引导语各 10 条；界面字面量除空占位与数字前缀外均走 `L10n`。

修复一处真实缺口：**关于窗口切语言后不刷新** —— 它的所有标签在 `viewDidLoad`
里一次性用 `L10n` 生成，菜单切语言只重建菜单。新增
`AboutViewController.reloadForLanguageChange()`（移除子视图后重建，保留窗口尺寸与位置），
`setLanguage` 时若窗口可见则同时更新窗口标题与内容。菜单、状态栏、休息遮罩本来就
每秒重绘，切语言即时生效。

### 复查（第五轮：发布链路与资源）

逐行审完 `build.sh`、`ci.yml`、`release.yml`，并结合仓库文件清单核对：

- 资源完整：`res/main.icns`、`res/ui/*.png`（4 个图标）、`res/dmg/bg*.png`、`assets/*`（README 引用）全部存在；`build.sh` 复制的文件与实际文件一一对应。
- 步骤计数正确：`ci`/`release` 基础 9 步，签名 +1、公证 +3、验签 +1，与实际执行顺序一致（`set -euo pipefail` 下无漏步）。
- 发版硬约束成立：Release 标题 `iCanHazRepose x.y.z`、资产 `iCHR.zip`（+`iCHR.dmg` 可选），`Verify artifacts` 会比对 `CFBundleVersion` 与 tag，`Publish` 对已存在的 tag 走 `--clobber` 上传。
- `.gitignore` 覆盖 `dist/`、`.build/`、`*.log`、`.env`、`.workbuddy/`；工作区无残留产物。
- 统一了更新弹窗标题：关于窗口改用 `L10n.softwareUpdate`（原为「发现更新」，与菜单侧「软件更新」不一致），删除随之不再使用的 `updateAvailable` 键。

**已知限制（本次未改，需签名后才涉及）**：`build.sh` 先打 ZIP/DMG 再公证与 staple，
因此包内的 `.app` 没有嵌入式公证票据，未联网的首启动可能被 Gatekeeper 拦。
正确顺序应是「公证 ZIP → staple .app → 重新打包 ZIP/DMG」。当前未配证书，
发布的是 ad-hoc 包，此问题不生效；将来启用公证时应一并调整。

另一个设计说明（非遗漏）：`UpdateManager` 的签名校验依赖 `build.sh` 里
`codesign -r="designated => identifier ..."` 写入的显式 designated requirement。
ad-hoc 包若不写这个 DR，DR 会退化成 cdhash，新旧版本必然不匹配、自动更新永远失败。
这条命令因此不是可选项。

---

## 设计改造（第六轮）

按「离开就锁屏」的使用习惯，把整套交互从"猜你是否离开"改为"等你明确的信号"。

### 1. 锁屏检测取代空闲检测
- 新监听 `com.apple.screenIsLocked` / `Unlocked`（DistributedNotificationCenter）与
  `screensDidSleep/Wake`，启动时用 `CGSessionCopyCurrentDictionary` 兜底判断。
- 删除 `CGEventSource` 空闲轮询：读文档两分钟不动鼠标不再等于"人走了"，
  而锁屏/显示器休眠一定意味着离开。
- 解锁后开始一个完整工作轮次（锁屏本身就是休息）。
- 旧设置 `pauseWhenIdle` / `pauseWhenLocked` 只作为一次性迁移来源读取；
  之后统一用 `pauseTrigger`（见第七轮，已改为可选项）。

### 2. 休息不再强制，Esc 永远可退出
- 删除 `isBreakMandatory` 与 `skipBreak` 的拦截；`canSkipBreak` 只看
  「是否在休息中 + 用户是否允许跳过」。
- 连续跳过 2 次仍会提示（`showsSkipHint` + 一句建议文案），但**不阻止**跳过。
- 长休息因此也不会再出现"锁屏 15 分钟无法退出"。

### 3. 休息遮罩：先给信息，再让位给引导
- 倒计时与进度环在 3 秒后淡出到 16% 透明度并缩小；引导语始终保留，
  点一下圆环可再显示 3 秒（`TimerRules.countdownVisibleSeconds`）。
- 全屏模式下显示一行极淡的「点一下圆环可查看剩余时间」。
- 紧凑面板是点击穿透的，那里不倒计时淡出（否则无法唤回）。

### 4. 菜单分层
- 动作（暂停 / 立即休息 / 重新开始）→ 计时（工作、休息、番茄三个子菜单）→
  提醒（六个开关）→ 开机启动、语言、关于、退出。
- 布尔开关统一用 `BoolSetting` 枚举 + tag，取代原先散落的 `SettingsKey` 字符串。

### 5. 首次启动引导
- 不再需要额外窗口：首次启动自动展开一次菜单，顶部状态行显示一句欢迎语，
  菜单关闭后写入 `hasCompletedWelcome`，此后不再出现。

### 6. 代码分层与测试
- 新增 `ICHRCore` 库（纯 Foundation，无 AppKit/SwiftUI）：
  - `TimerRules`：时长换算、长休息判定、剩余时间、提醒阈值、跳过提示、时间格式化；
  - `Settings`：所有偏好唯一来源，setter 内 clamp + 持久化 + `@Published`。
- `TimerManager` 退化为协调者：状态机 + 定时器 + 系统通知 + 遮罩调度。
- `Tests/ICHRCoreTests`：规则与设置测试（当时 34 项，重构后 24 项）；`scripts/check-l10n.py`：文案完整性审计。
  两者都接进 CI（`swift test` 需完整 Xcode，本地仅有 CLT 时跳过）。

### 已知限制
- `swift test` 依赖 XCTest，只能在完整 Xcode 下运行；本地用 `swiftc -typecheck`
  与等价的行为脚本验证（46 项状态行为断言 + 24 项 XCTest）。
- 公证顺序问题（见上一节）仍未处理，需在启用签名时一并调整。

---

## 设计改造（第七轮）：暂停时机可选

第六轮把空闲检测换成了锁屏检测，但那是**替用户做的决定**。本轮把它变成设置项，
默认值仍是锁屏——对「离开就锁屏」的人是最少误判的选择，其他人可以改。

### 实现
- `ICHRCore.PauseTrigger`（`core/PauseTrigger.swift`）：`lockScreen` / `idle` /
  `lockScreenOrIdle` / `never`，附 `pausesOnLock` / `pausesOnIdle` 谓词。
  显示文案留在 App 的 `L10n`，枚举本身不持有 UI 字符串。
- `Settings`：新键 `pauseTrigger`（存 rawValue）。旧的两个布尔键降级为一次性迁移：
  显式关过暂停 → `.never`；其余 → `.lockScreen`。**空闲模式不会被自动恢复**，
  因为它正是让「读文档」被误判为离开的元凶。
- `TimerManager`：
  - 新增 `PauseReason.idle`，菜单栏显示「空闲 m:ss」、图标 `moon.zzz`；
  - `checkIdleStatus()` 每 5 秒随会议检测一起跑，仅在 `pausesOnIdle` 时生效；
  - 阈值常量化：`TimerRules.idleThresholdSeconds = 300`（5 分钟）、
    `idleReturnSeconds = 5`（回到键鼠即恢复），不再沿用「60 + 休息时长」；
  - 锁屏/空闲暂停恢复时都开始完整工作轮次（离开过 = 已经休息过）；
  - 切换设置时若正因该信号暂停，会立即恢复（`pauseTriggerSettingChanged`）。
- 菜单：提醒子菜单第一项为「暂停时机 ▸」单选组（4 个勾选项），取代原来的
  「锁屏时自动暂停」开关。
- 可测性：锁屏状态与空闲秒数改为可注入的闭包（`screenLockedProvider` /
  `secondsSinceInputProvider`），无图形会话的机器也能验证这两条路径。

### 验证
- `swiftc -typecheck`：14 个文件 **0 error / 0 warning**（含两个 SwiftUI 视图）。
- 状态行为测试 **46 项**全过（新增：空闲阈值前后、恢复、组合触发、
  非锁屏触发时锁屏不暂停、屏亮但仍锁屏不恢复、切设置解除滞留暂停）。
- Core 规则/设置断言 + `scripts/check-l10n.py`（78 组双语，79 处引用）通过。

---

## 本机 Xcode 真机验证（第八轮）

装上完整 Xcode（27.1 / Swift 6.4）后，此前只能靠 CI 的三件事终于在本机跑通，
并顺带查出两个发布链路的真实缺陷。

### 已验证
- `swift build -c release`：整个包编译通过（12 秒），**包含两个 SwiftUI 视图的真实宏展开**——
  之前用 `ViewState` 桩做的类型检查不再是唯一依据。
- `swift test`：**23 项 XCTest 全部通过**（此前本机无 XCTest，只能交给 CI）。
- `./build.sh ci`：9 步全绿，产出 2.1 MB 的 universal `.app`、716 KB 的 `iCHR.zip`、
  1.0 MB 的 `iCHR.dmg`。
- 产物校验：`lipo` 双架构（x86_64 + arm64）；ad-hoc 签名带**显式 designated requirement**
  `identifier "wtf.d7.icanhazrepose"`（自动更新依赖它，见第五轮）；DMG 挂载后含
  `iCanHazRepose.app` + `Applications` 软链，`codesign --deep --strict` 通过。
- 冒烟运行 6 秒：无崩溃、stdout 干净、日志正常落到 `~/Library/Logs/iCanHazRepose/`，
  且真实用户数据上完成了 `pauseTrigger` 迁移（日志显示 `pauseTrigger=lockScreen`）。

### 修复 1：通用二进制在 Swift 6 工具链上必然失败
`build.sh` 原本从 `.build/arm64-apple-macosx/<config>/` 取二进制。新的 SwiftPM 把产物
放到 `.build/out/Products/<Config>`，而且**两个 `--arch` 构建写同一个路径**，后跑的
x86_64 会覆盖先跑的 arm64——`lipo` 直接报 "no eligible inputs"。
改为 `swift build --show-bin-path` 询问真实路径，并在每次编译后暂存到
`.build/stage/<arch>/`；取不到时回退旧布局。GitHub 的 macOS runner 迟早升级工具链，
这个坑不修会以「发布流水线突然全线失败」的形式出现。

### 修复 2：缺 create-dmg 时 DMG 被静默跳过
原来 `command -v create-dmg` 失败就 `return 0`，但 Release 页面链接的是 `iCHR.dmg`。
现在缺失或失败都回退 `hdiutil`，并在镜像里补一个 `Applications` 软链，使回退产物
仍然可以拖拽安装。

### 修复 3：Xcode 装了但 xcode-select 还在 CLT
这正是本次本机踩到的：`swift --version` 能用，一编译就报
`external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`。
`build.sh` 现在若发现 `DEVELOPER_DIR` 未设置且 `xcode-select` 指向 CLT，会自动选用
最新的 `/Applications/Xcode*.app`（并打印所选路径）；一个 Xcode 都没有时给出明确警告。

---

## 第九轮：全项目审计（2026-10-28）

完整报告见 [`docs/audit-2026-10-28.md`](audit-2026-10-28.md)。摘要：

### 修复
1. **自动检查更新从未真正触发**：定时器首次回调在启动 24 小时后，菜单栏应用很少连续运行那么久。
   改为持久化 `lastUpdateCheck`，启动时若已过期则 5 秒后补检，随后按每日节奏。
2. **`dev-release` 最后一步必然失败**：它调用仓库外的 `share` 脚本。改为探测后跳过，
   步骤计数随之从 9 变 8。
3. **版本号落后**：`Info.plist` 从 1.0.3 提升到 1.0.5（线上已发布 1.0.4）。
4. **死代码**：删除 `L10n.breakSoon`、`L10n.longBreakStarted`、`PauseTrigger.isEnabled`。

### 文档
- 修正本文件前几轮已被推翻的结论（强制休息、`SettingsKey`、测试项数、无法本机编译等），
  并在文首加了「以最新轮次为准」的阅读提示。
- README 补上休息引导语与渐进式提醒，并把「Escape 永远可退出」修正为
  「除非关闭『允许跳过休息』」。
- 新增 `docs/audit-2026-10-28.md`：完整问题清单（含未修项与理由）。

### 仍未处理（详见审计报告）
- 安装更新失败无提示；公证顺序倒置；zip 符号链接未校验；
- 两张界面截图过期；`.roorules` / `.env.example` 未随项目演进更新；
- 无 CI lint、无辅助功能标签。

---

## 第十轮：更新器换代、bundle id、L10n 框架化（2026-10-28）

这一轮不是「再查一遍」，而是按用户决定做了三处架构变更，因此上面所有提到
`UpdateManager` / `UpdateDialogViewController` / `L10n.t("en", "zh")` 的段落都成了历史。

1. **更新器换成 Sparkle 2**（`src/Updater.swift`，约 100 行包装）。自研的下载 / 解压 /
   验签 / 替换 bundle 代码全部删除，顺带消掉了「安装失败无提示」「管道死锁」
   「zip 符号链接未校验」三条问题。发布的硬约束随之改变：不再是「标题含
   `iCanHazRepose x.y.z` + 资产名 `iCHR.zip`」，而是「`appcast.xml` 必须签名、
   且与 `Info.plist` 的 `SUPublicEDKey` 配对」，详见 `docs/releasing.md`。
2. **bundle id 改为 `io.github.solitudechn.icanhazrepose`**。可与原版共存；
   `Settings.migratePreferences` 负责从旧 domain 一次性搬迁偏好，有三处 id 需要同步
   （`Info.plist`、`core/BundleIdentity.swift`、`build.sh` 的 `ident`）。
3. **`L10n` 框架化**：字符串表迁进 `ICHRCore`，键是 `LocKey` 枚举（编译期校验），
   值是 `Translation`（中英成对），参数走 `%ld` / `%@` 格式串。新增
   `StringTableTests` 检查空串、漏翻、占位符数量；`check-l10n.py` 改为结构校验 +
   硬编码扫描。

同时补了 `.swift-format` + CI lint、辅助功能标签、`scripts/verify.sh`、`.roorules` 重写，
以及关于窗口里的汉化署名。界面截图仍未重截（本机进程无屏幕录制权限）。

---

## 第十一轮：发布前复查（2026-10-28 晚）

对全部 49 个受控文件重审一遍，发现并修掉 7 处问题，其中两处是真 bug：

1. **`TimerRules.showsSkipHint` 只被测试调用**，App 里另有一份拷贝——测的不是跑的那份；
   已让 `TimerManager` 直接调用它。
2. **`OverlayManager` 读全局 `Settings.shared`** 而不是 `timerManager.settings`，
   热键与按钮可能来自两份设置；已改。
3. `Log.error` 零调用（失败在日志里和成功长得一样）、`Settings.migratedLegacyPreferences`
   只写不读、`AppConstants.appShortName` 死代码、bundle id 三处重复——都已收拾干净，
   并新增 `BundleIdentityTests`（37 项测试）。
4. 文档与实现不符 4 处（审查日志、审计报告、`.roorules`、发布手册）已改。

留了一个需要你决定的问题：关掉「允许跳过休息」后，完整遮罩既没有 Esc 也没有按钮，
还会吞掉全屏幕的点击，屏幕最长被锁 10 分钟——与「Esc 随时可退出」的原则冲突。
详见 [`docs/audit-2026-10-28.md`](audit-2026-10-28.md) 第八节。
