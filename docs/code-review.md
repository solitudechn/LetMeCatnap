# 代码审查：汉化版 iCanHazRepose 还能改什么

基线：`55b88bb`（= 上游最新）+ `iCanHazRepose-zh-localization.patch`
审查范围：`src/` 全部源码、`build.sh`、`Info.plist`、`README.md`

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

已验证的部分：`build.sh` 语法检查通过；用桩程序把 `ci` 模式完整跑通（9 步全绿、版本注入生效、zip 里就是 `iCanHazRepose.app`、无 tty 时输出正常回退、无 `create-dmg` 时优雅跳过）。
**Swift 代码未能在本机编译**：这台机器只有 Command Line Tools，没有完整 Xcode，SwiftUI 宏插件（`SwiftUIMacros`）加载不了。第一次 push 后请以 CI 的编译结果为准。

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
3. **版本号要和上游错开**。fork 首发建议直接 `1.0.4`，别沿用 `1.0.3`——否则用户和更新器都无法区分「汉化版」和「原版」。
4. **切语言后已打开的窗口不刷新**。`AboutViewController` 在 `setLanguage` 之后仍显示旧语言（遮罩类窗口都是弹出即建，问题不大）。建议给 `L10n` 加一个 `NotificationCenter` 广播，About 窗口监听后重新构建视图。
5. **安装更新失败无提示**。`UpdateManager` 的安装脚本先 `rm -rf` 旧包再 `mv`，但 app 已经 `terminate` 了；若 `/Applications` 需要管理员权限，替换会静默失败，用户看到的是「app 打不开了」。建议：安装脚本失败时 `open` 一次旧路径，或改用「先写到临时目录、用 `osascript` 提权」的流程。

### P1 — 明显影响体验 / 可维护性

6. **计时器有累积漂移**。`TimerManager.tick()` 是每秒 `remainingSeconds -= 1`，Timer 被系统合并或睡眠后会丢拍，长时间运行会越走越偏。建议改成记 deadline（`workEndDate`），每次 tick 用 `Date()` 算差值。
7. **README 与实现不一致**。README 写「空闲 5 分钟暂停」，代码是 `60 + breakDurationSeconds`（默认 80 秒）。要么改文档，要么改阈值。
8. **日志只有 stdout**。菜单栏 app 从 Finder 启动时 `print` 无处可去，用户报「更新失败」时没法自查。建议换 `os.Logger`（可在「控制台」里按 subsystem 过滤），或加一个「导出诊断信息」菜单项。
9. **没有测试**。`SemVer` 比较、`validateZipEntries`（防 zip-slip）、`L10n` 键位完整性都很好测，加个 `Tests/` target，CI 里跑 `swift test`。
10. **没有格式化/静态检查**。`TimerManager.isInMeeting` 还有行尾空格。加 `swift-format` 或 `.swiftformat` 并在 CI 里 `--lint`。
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
| 渐进式提醒 | `SettingsKey.progressiveReminders` · `TimerManager.updateImminentFlag()` | 剩余 1 分钟时菜单栏图标切 `hourglass` 并轻响一声；连续跳过 2 次后，下一次休息不可跳过（`skipBreak()` 内部拦截，Esc 热键一并失效） |
| 文件日志 | `Log.swift` | 写入 `~/Library/Logs/iCanHazRepose/iCanHazRepose.log`，串行队列 + 1 MB 滚动到 `.1.log`；启动时记录配置与日志路径 |

同时修掉了 P1 第 8 条（日志只有 stdout）。仍未处理：计时器累计漂移（第 6 条）——
`remainingSeconds -= 1` 的毛病还在，做统计类功能前必须先改 deadline 计算。
