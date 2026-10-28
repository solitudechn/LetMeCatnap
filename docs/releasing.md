# 发布流程 / Releasing

这份文档接手了原先写在 README 里的「发布」小节。README 面向使用者，这里面向维护者。

## 一、一次发布要做的事

```sh
# 1. 改版本号（两处必须一致）
#    Info.plist: CFBundleVersion / CFBundleShortVersionString
# 2. 跑一遍检查
./scripts/verify.sh
# 3. 打包自检（不发布、不上传）
./build.sh ci
# 4. 打标签并推送，Release 工作流接管
git tag v1.1.0 && git push origin v1.1.0
```

`Release` 工作流会：编译 arm64 + x86_64 → 合成通用二进制 → 组装 `.app` →
嵌入 `Sparkle.framework` → 签名 → 打包 `LetMeCatnap.zip` → 生成 `LetMeCatnap.dmg` →
**生成并签名 `appcast.xml`** → 创建 GitHub Release（标题 `LetMeCatnap <版本>`，
资产含 `LetMeCatnap.zip`、`LetMeCatnap.dmg`、`appcast.xml`）。

## 二、更新链路（Sparkle 2）

| 东西 | 位置 | 说明 |
|---|---|---|
| 订阅源 | `Info.plist` 的 `SUFeedURL` | `releases/latest/download/appcast.xml`，永远指向最新一次发布 |
| 公钥 | `Info.plist` 的 `SUPublicEDKey` | 校验每个更新包的 Ed25519 签名 |
| 私钥 | 仓库 secret `SPARKLE_ED_PRIVATE_KEY` | 只存在于 CI 与本机 `~/.config/letmecatnap/` |
| 检查频率 | `SUScheduledCheckInterval` | 86400 秒；用户也可手动「检查更新…」 |

**发布缺少 `appcast.xml` 等于这一版没人能自动更新到**，所以工作流在密钥缺失时
直接失败，而不是发一个悄悄坏掉的版本。

### 生成密钥（只需一次）

Sparkle 自带 `generate_keys`，也可以用任意 Ed25519 实现生成一对 32 字节密钥：

- 私钥：base64 编码的 32 字节种子，写入 `~/.config/letmecatnap/sparkle_ed25519_private.key`（权限 600），
  再整体粘进 GitHub 仓库 secret `SPARKLE_ED_PRIVATE_KEY`；
- 公钥：base64 编码的 32 字节公钥，写进 `Info.plist` 的 `SUPublicEDKey`。

两者必须成对。**换了公钥就等于换了更新身份**：旧版本校验不过新包，用户只能手动重装。

### 首次配置仓库 secret（只需一次）

```sh
cat ~/.config/letmecatnap/sparkle_ed25519_private.key | pbcopy
```

然后打开 `Settings → Secrets and variables → Actions → New repository secret`，
名称填 `SPARKLE_ED_PRIVATE_KEY`，粘贴、保存。配好之后每次发版都不再需要人工介入。

**不要**把私钥提交进仓库：能读到它的人可以签一个恶意更新包，所有装了本应用的机器
都会静默接受并运行（等于远程代码执行）。secret 是只写不可读的，CI 能用、谁取不回来。

本机自检（换密钥或改签名逻辑后跑一次，至少确认能生成带 `sparkle:edSignature` 的 feed）：

```sh
mkdir -p /tmp/feedtest && cp dist/LetMeCatnap.zip /tmp/feedtest/
cat ~/.config/letmecatnap/sparkle_ed25519_private.key \
  | .build/artifacts/sparkle/Sparkle/bin/generate_appcast --ed-key-file - /tmp/feedtest
grep edSignature /tmp/feedtest/appcast.xml
```

公私钥是否配对，最终由客户端说了算：签名不匹配时 Sparkle 会拒绝安装并提示
「无法验证更新」——出现这个提示，先查 secret 里的私钥和 `SUPublicEDKey` 是不是同一对。

### appcast 为什么能只放一版

每次发布在空目录里用当次的 `LetMeCatnap.zip` 重新生成 appcast，只含最新一版。
Sparkle 会拿自己当前的 `CFBundleVersion` 和 feed 里的最新版比较，比它新就提示，
所以「只列最新一版」既省事又不会漏更新。代价是旧版本不会出现在 feed 里，
需要回滚时得手动改 appcast。

## 三、签名与公证（可选）

配上这五个 secret 就得到签名 + 公证的包：

```
MACOS_CERT_P12 / MACOS_CERT_PASSWORD          Developer ID Application 证书
NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_APP_PASSWORD
```

没配也能发，是 ad-hoc 签名，用户首次启动要清隔离标记：

```sh
xattr -dr com.apple.quarantine /Applications/LetMeCatnap.app
```

### 已知的顺序问题

`build.sh` 现在是「打包 → 公证 DMG → staple `.app`」，包内 `.app` 没有嵌入票据，
离线首启动仍可能被拦。正确顺序是「公证 ZIP → staple `.app` → 重新打包」。
当前未配证书，这条不生效；**启用签名时要一起改**，否则公证等于白做。

## 四、bundle id 不能随便改

`Info.plist` 的 `CFBundleIdentifier` 是**唯一来源**：`build.sh` 读它来生成 ad-hoc
签名的 designated requirement，`core/BundleIdentity.swift` 里的
`BundleIdentity.identifier` 只是它的镜像，由 `BundleIdentityTests` 保证一致
（改了 Info.plist 忘了改代码，测试会红）。

改了 id 的后果：`UserDefaults` 就是另一个命名空间——`Settings` 会在首次启动时按
`BundleIdentity.legacyIdentifiers` 逐个尝试迁移（见 `Settings.migratePreferences`），
但「开机启动」是系统按 bundle id 记的，需要用户在菜单里重新打开一次。

### 这个应用用过三个 id

| 顺序 | identifier | 说明 |
|---|---|---|
| 1 | `wtf.d7.icanhazrepose` | 上游原版，fork 早期直接沿用它（会和原版抢偏好设置） |
| 2 | `io.github.solitudechn.icanhazrepose` | 独立出来后的一版，**从未发布过** |
| 3 | `io.github.solitudechn.letmecatnap` | 改名为 LetMeCatnap 后的当前 id |

`legacyIdentifiers` 是**只增不减**的列表：每换一次 id 就把上一个加进去，否则老用户的
设置会在升级后静默丢失。`BundleIdentityTests` 会检查前两个 id 都还在列表里。

### 仓库名与 bundle id 是两件事

仓库目前仍叫 `solitudechn/iCanHazRepose`，而应用叫 `LetMeCatnap`——GitHub 仓库名
不影响用户看到的东西，所以没有强行改。如果以后把仓库也改名，需要同步两处
（`BundleIdentityTests` 会因为它俩不一致而报错）：

- `core/BundleIdentity.swift` 的 `repository`
- `Info.plist` 的 `SUFeedURL`

GitHub 会为旧仓库地址保留跳转，已经装了的用户不会因为改名而收不到更新。

### v1.1.0 是一次性手动升级

v1.0.x 里的自研更新器会校验「新包的代码签名要求必须和当前一致」。1.1.0 换了
identifier（`wtf.d7.icanhazrepose` → `io.github.solitudechn.letmecatnap`）也换了名字，
所以老用户点「更新」会收到「下载的应用由不同的签名身份签发」并中止——
这是设计如此，不是 bug。

发布 v1.1.0 时请在 release 正文最前面加一句：

> **从 1.0.x 升级需要手动安装一次**（bundle id 已更改，旧版更新器会拒绝替换）。
> 下载 `LetMeCatnap.dmg` 覆盖安装即可，设置会自动迁移；此后恢复自动更新。

从 1.1.0 起更新由 Sparkle 负责，不再有这个问题。

## 五、排错

| 现象 | 原因 |
|---|---|
| 更新提示「无法验证更新」 | `appcast.xml` 没签名，或私钥与 `SUPublicEDKey` 不配对 |
| 从 ad-hoc 版升到 Developer ID 版时更新被拒 | 签名身份变了，Sparkle 不接受换了身份的包。这一版必须在发布说明里写「请手动安装一次」，装完即恢复自动更新 |
| `releases/latest/download/appcast.xml` 404 | 最新 release 没上传 `appcast.xml`（检查 Release 工作流是否跳过） |
| 装完新版本又提示更新 | `CFBundleVersion` 没随 tag 变化（工作流会用 tag 覆盖，本地包则看 Info.plist） |
| 启动即崩、报 dyld 找不到 Sparkle | `build.sh` 的嵌入步骤被跳过，或 rpath 丢了 |
| CI 里 `generate_appcast` 找不到 | `swift build` 没跑过，Sparkle 的二进制产物还没下载 |

## 六、已知问题（不影响发版，但会咬人）

| 事项 | 说明 |
|---|---|
| Sparkle 的更新窗口在 `LSUIElement` 应用里的前台行为未验证 | 应用平时是 `.accessory`（不进 Dock），Sparkle 弹窗时会自己激活；若窗口被压在其他应用后面，用户点「检查更新…」会觉得没反应。**只有第一次真实更新能验证**，第一版发出去后请留意 |
| `Publish` 只 `--clobber` 资产，不更新 release 正文 | 想改发布说明只能去网页改，或删了重发 |
| 公证顺序仍是「先打包后公证」 | 见第三节的「已知的顺序问题」。无证书时不生效 |
| 从 ad-hoc 切到 Developer ID 的那一版要手动安装 | 签名身份变了，Sparkle 会拒绝替换；那一版发布说明里必须写明 |

## 七、图标

`res/main.icns`、`assets/icon.png`、`res/dmg/bg.png` 都是从**同一张画**生成的：

```sh
swift scripts/make-icon.swift
```

- 画稿是 `res/icon-source.jpg`（1024×1024，白底）。脚本量出猫的包围盒，把它重新
  居中、缩放到安全区（824/1024）里，所以画稿留白多少都不影响成品比例；
- 白底不是抠掉的，而是用 `.multiply` 把整张画压到米色底上——白像素自动变成底色，
  也就不存在抠图残留的白边；
- 换图标只需要换 `res/icon-source.jpg`，再跑一次脚本。**不要手改 `main.icns`**。

16 / 32 px 那一档会明显变糊：画稿里的眼睛、爪缝、`zzz` 在这个尺寸下只剩几个像素。
菜单栏用的是 SF Symbol，不读这个文件，所以实际影响只有 Finder 列表视图。

