# 双音源真机验证 — 2026-10-27

维护与新增功能：**tiancaiProgramer**。

验证环境为连接的小米折叠手机、Android 16，手机端构建 2.0.8（2081—2092）。账号由用户在 QQ音乐官方页面登录；记录不包含账号标识、Cookie、签名播放地址或凭据。

| 项目 | 真实验证结果 |
| --- | --- |
| 官方登录与持久化 | 官方页面完成登录，应用校验成功；多次保留数据覆盖升级与重启后仍可读取 QQ 歌单 |
| 双源搜索 | 搜索《我好像在哪见过你》同时显示网易云和 QQ音乐版本，保留来源标签 |
| QQ 播放 | 曲目总长 4:39，拖至约 3:36 后保持播放并继续缓冲；封面、歌词与当前曲目一致 |
| 音频文件头 | 极高档取得 MP3 320 kbps / 44.1 kHz；无损档取得 FLAC 24 bit / 44.1 kHz；测试后恢复极高设置 |
| 横屏播放页 | 显示封面、歌词、控制按钮与歌曲时长；测试后恢复系统自动旋转 |
| 本地混合收藏 | 同时保存两个平台版本，覆盖升级和重启后仍保留；播放页心形与列表操作同步刷新 |
| 网易云云端收藏 | 只在本次指定的 BuYu收藏 歌单内创建、写入并读回 1 首测试曲目 |
| QQ 云端收藏 | 只在本次指定的 BuYu收藏 歌单内测试；加入、取消、重新加入后，云端歌曲列表分别读回 1、0、1 首 |

QQ 云端写入前采用官方歌曲详情确认歌曲编号与类型。该曲搜索结果的类型为 1，详情中的实际歌曲类型为 0；直接沿用搜索类型会出现返回成功、歌单有数量却无可读歌曲的问题。修复后清理本测试曲旧类型记录，并用云端读回验证真实增删结果。歌单详情中的 `disstid` 与内部 `dissid` 也分别处理。

本次结果不代表所有版权、地区、会员、账号或曲目均可取得完整音源。自动回归使用模拟网络，不会修改真实云端收藏。当前仅实现本机收藏向各自指定云端歌单推送，尚未实现其他设备改动拉取或已有收藏导入；QQ 下载、评论和歌单／专辑／歌手搜索尚未接入。

上述 2092 范围记录保留为历史；当前能力与新增实测见下方 2103 记录。APK 哈希、版本号和回归结果见随包 `verification.json`；未上传 GitHub Release。

## 2099 共存版登录复验

2026-10-27 本人完成独立共存包的手机 QQ 扫码授权，应用成功校验音乐会话并显示单账号三项动作；继续登录网易云后，当前页只剩跳转主页和对应平台退出。2099 保留数据覆盖升级、结束进程并冷启动后，网易云个人资料与歌单、QQ歌单均保留。未执行退出真实账号，以保留用户的试用状态；两个平台独立退出和状态清理由自动回归验证。完整回归为167项通过、3项默认跳过。

扫码故障主要原因是返回多个同名 Cookie 时忽略域名，父域旧Cookie删除覆盖了 graph.qq.com 的有效票据。已按域名、有效期和目标地址解析，并补充相同返回形态的回归。凭据和授权链接没有写入验证记录。

## 2103 聚合收藏、歌单管理与下载复验

2026-10-27，连接手机保留数据升级至 2.0.8（2103）共存版。原包保持 2092，不覆盖或清理原包数据。

- 聚合收藏从真实账号读到网易云 BuYu收藏 1 首、QQ 的 BuYu收藏 2 首，共 3 首，按来源标记；读取本身未创建或修改云端歌单。
- 网易云创建专用空测试歌单，改名后重新读取确认新名称，删除后重新读取确认移除。原 eapi 名称接口返回 403；修正为网页会话接口及单字段网页批量兼容，未提交描述或标签。测试结束已删除本轮创建的空歌单，未修改用户已有歌单。
- QQ《稻香》极高实际下载成功并显示完成提醒：MP3 320 kbps、44.1 kHz、双声道，8,941,053 字节，独立解码时长约 223.45 秒。手机原有同曲无损文件为 FLAC 16 bit、44.1 kHz、双声道，26,012,257 字节。
- 设置新增下载管理入口已真机打开；极高记录显示请求档位、实际档位、规格、大小、时间、次数和保存位置。保留数据升级及结束共存版进程并冷启动后，记录及字段仍保留。
- 下载管理横屏按现有三列卡片显示；详情可查看完整规格。测试后恢复原系统自动旋转设置。
- 177 项自动回归通过、3 项联网测试默认跳过；静态检查无错误。新增回归包含双平台只读收藏导入、账号切换、待同步删除保护、旧 QQ 下载记录恢复、单字段改名与安全编码，以及下载详情在 390×844、844×390、640×300 下可达。

三点菜单、弹窗按钮及其他主题不一致项按用户要求只记录，尚未修改样式。结果仅覆盖上述真实账号与曲目，不表示所有会员曲目和音质档位均已验证。

## 2104 空播放区域复验

保留数据升级共存包至 2104，冷启动首页未出现空播放条和额外底部预留空白。点击本次已下载的《稻香》极高文件后，播放条出现，打开完整播放页正常；暂停后仍保留已选择歌曲控制，测试音频已暂停。自动回归验证无有效歌曲时横竖屏均只保留系统安全区、即使旧播放状态未清也不显示空面板、已展开面板清空后不占屏幕且不拦截返回，页面状态保持。

179 项自动回归通过、3 项默认联网检查跳过，静态检查无错误。现有主题和操作面板样式未修改；面板与标签入口仅提供对照说明。

## 2105 主题统一复验

保留数据升级共存包至 2105，双账号、歌单和聚合收藏仍可读取。真机查看 QQ 歌单三点菜单，背景变为当前主题面板色，文字清晰；打开原歌单的重命名弹窗，输入框和取消／保存按钮均清晰，随后点击取消，没有提交云端改名。账号页横屏按两项一行展示，使用主题卡片与同一套轮廓图标。

实际切换系统深色模式，核对横屏账号页的白色文字、卡片及主题红色操作；测试后恢复原浅色模式和系统自动旋转（原 user_rotation=1、accelerometer_rotation=1）。未修改原正式包。

183 项回归通过、3 项默认联网测试跳过，静态检查无错误。新增检查实际打开菜单、选择改名、输入并保存模拟名称、选择音质，并在深浅色和横竖屏下核对菜单、弹窗动作及选中标签文字至少 4.5:1 的对比度。自动回归不会执行真实云端修改。

## 2026-10-27：2106 / 2107 补验

2106 已覆盖安装共存版。用户确认“横版页面没有问题”，QQ 退出成功、网易云退出失败。代码追踪发现侧栏使用 replaceNamed 替换个人页，页面控制器可能已销毁，账号管理仍通过该控制器的静态查找执行网易云退出；2107 将账号刷新 / 退出与页面生命周期解耦。

2107 的自动测试覆盖：个人页控制器存在 / 已销毁时账号页退出、网易云会话与缓存清理、QQ 授权保持、退出后延迟账号响应不能恢复持久化登录、无个人页时重新登录、横竖屏的隐藏开关与来源过滤，以及本地分类 / 聚合收藏保留。新开关默认关闭，追加在 UI 设置末尾以保持原有设置项的横屏配对。

手机测试期间系统自动旋转已经恢复；没有操作其他应用的 Shizuku 授权或系统权限。

2107 最终自动回归 209 项通过、3 项联网检查跳过；两个 ABI 包核对原版证书和随包许可通过。已覆盖安装共存版 2107，正式版保持 2092。手机在其他应用中使用，未强行打开 BuYu，网易云真机退出仍待用户复验。

## 2026-10-27：2108 双平台发现功能

用户重新登录 QQ 后，临时只读核验确认返回一个每日推荐卡片和五首猜你喜欢；没有打印会话或签名音频 URL，也没有修改歌单。后续手机 USB 断开，最终完整新增页面尚待真机复验。

QQ 官方原生节目专辑读回 277 期节目；样例时长 2651 秒。独立只读音频解析与 Range 文件头核验成功：HTTP 206、audio/mpeg，读取 1024 字节后关闭连接，确认 MP3。默认播客主播的原生目录返回三张人声音频专辑。

最终完整回归 229 项通过，3 项联网检查默认跳过。原版签名、随包版权许可、两个 ABI 包验证通过；最终 libapp.so 不含开发核验日志标记，默认不执行自动核验。共存包已保存于 outputs/BuYu-2.0.8-2108-coexist-preview，尚未通过 USB 覆盖安装。

### 2026-10-28 最终 2108 共存包安装

- USB 恢复连接，已从 outputs 最终交付目录覆盖安装 ARM64 APK，adb 返回 Success。
- 已核对共存包版本代码 2108、正式版仍为 2092。
- 手机前台为游戏，已请求用户方便时切回 BuYu；新增每日、FM、播客的最终页面核验待继续。

- 用户允许继续后已打开共存版：首页正常显示 QQ 歌单、聚合收藏及云盘入口，未显示空白播放条。
- 两种 adb 触控注入均未触发每日页面跳转；未将此情况记为每日功能失败。已请求用户手动打开“每日 → QQ音乐”后继续核对。

- 用户手动打开 QQ 每日后，实际页面显示《自由的你》《天外来物》《搁浅》等 QQ 歌曲及正确封面；当前可见列表不是空态或登录提示。未据首屏条目推断列表总数。
- 临时关闭自动旋转并设置横屏，确认三列卡片、歌曲封面及文字完整，随后恢复 accelerometer_rotation=1，user_rotation 保持原值 1。
- 证据位于 work/device-check2108/qq-daily-portrait.png、qq-daily-landscape.png（仅本地留存）。
- 已请求用户进入 QQ 播客的节目列表，待继续验证。

- 用户已进入 QQ 原生播客“啊！是猫咪呀”节目列表：首屏显示引导节目及 S1.E01–S1.E08，封面正常，横屏三列卡片与加载更多入口可见。未将入口可见记为分页已实际点击成功。
- 证据：work/device-check2108/qq-podcast-episodes-landscape.png。
- 请求用户试听播客后进入 QQ FM，以继续核对实际出声与系统播放进度。

### 2026-10-28 / 2109 verification

- User confirmed QQ podcast audio; FM session PLAYING, five tracks, progress 29603 ms to 55656 ms.
- System next controls advanced indices 1 through 4 with PLAYING and error=null. Refill at batch end failed; continuous playback was not marked passed.
- Landscape mini-player camera-left regression reproduced right edge 887 > viewport 844 before fix. Header width now constrained before safe insets; full Material covers the safe area to prevent album-gradient leakage.
- Official anonymous parameter comparison: two numeric song_ids returned request code 22006. 2109 uses the supported empty history and local recent-track filtering. Authenticated refill remains pending device verification.

- Final 2109 installed successfully. Both landscape camera sides verified: control visible and safe-area surface uniform, no gradient leakage. Automatic rotation restored.
- Authenticated QQ FM refill verified on device: old queue index 4 of 5 -> new queue index 1 of 6, no error; paused state preserved, then system play starts the new track. Progress 3320 ms -> 81997 ms, PLAYING, error=null.
- Final full tests: 230 passed, 3 skipped. Original certificate and bundled MIT verified on both ABI packages. No GitHub or TV release.

### 2026-10-28 / 2110 landscape alignment

- Fold control moved into playlist area; right edge follows last playlist card. Mini-player control shares the same trailing inset.
- 11 related layout tests passed, including actual control/card bounds and both camera sides. Previous complete regression: 230 passed, 3 skipped.
- Original-signed final 2110 preview installed. Homepage screenshot confirms fold/playback vertical alignment, original shortcut rail retained and no background leakage. Evidence: work/device-check2110/aligned-landscape.png.
- No GitHub, stable or TV release.

### 2026-10-28 / 2111 landscape shortcut spacing

- Four existing shortcuts now share the full available body height, including space beside the source filter. Icon size, font size, horizontal position, playlist cards, fold and playback control positions unchanged.
- 5 related layout tests passed; targeted static analysis: no issues. Both ABI artifacts verified with original certificate, bundled MIT and development probe disabled.
- Final 2111 preview installed and version confirmed; screenshot while playing confirms more vertical spacing, retained alignment and cloud clear of mini player. Evidence: work/device-check2111/spaced-landscape.png. No GitHub or TV release.

### 2026-10-28 / 2113 combined layout changes

- Includes uninstalled 2112 change: shortcut groups bounded by playlist top and mini-player top, equal gaps.
- Portrait collapsed player removes synthetic bottom inset; body reserves matching height. Content height includes the 48 logical pixel button minimum, so title/control centers match the actual bar.
- 6 related tests passed; targeted static check: no errors or warnings. Original certificate, bundled MIT and disabled development probe verified for both ABI packages.
- Final 2113 preview installed and version confirmed. Other app remains foreground; user was asked to open BuYu portrait, visual check remains pending. No GitHub or TV release.

- User opened BuYu portrait. Final 2113 screenshot on aggregate-favorites page confirms collapsed player has no synthetic bottom gap; artwork, title and playback button visually centered. Evidence: work/device-check2113/portrait-mini-player.png. No playback or account state was changed during this visual check. Landscape shortcut bounds remain covered by the related widget tests.

### 2026-10-28 / 2114 QQ-only navigation and settings

- User confirmed NetEase logout and current landscape shortcut bounds. Required policy clarified: either platform logged in permits drawer navigation; both signed out still enters login.
- Added shared account predicate for discovery/local/settings avatars. Drawer navigation waits for the real closed state and coalesces repeated taps. Settings paints its own opaque base and adaptive wallpaper.
- Device run 2 (QQ signed in, NetEase signed out): drawer navigation across settings/discovery/local/home passed; hide-unlogged retained QQ discovery and cloud; native podcast search paging reached 100 episodes; FM natural completion reached a new batch. Controlled single QQ connection failure followed by a real successful retry passed.
- Run 2 seek/progress checks used the deliberately UI-gated Home.duration field and did not pass; final engine-position/rotation checks must be rerun after QQ login. Run 3 found both accounts signed out, so account-dependent checks were not counted as passed. Sanitized per-run reports are in work/device-check2114.
- Final regression: 237 passed, 3 skipped. Production dependencies restored, temporary profile signing and test harness removed; final small original-signed 2114 preview installed. No GitHub or TV release. QQ re-login requested once for pending audio checks.

### 2026-10-28 / 2115 QQ public profile and final discovery checks

- Official QQ profile avatar decoded at 140 x 140 on the signed-in phone. Shared identity and saved source selector verified; dual-account switching covered by portrait/landscape automated fixtures, current phone QQ-only.
- Attached real-device smoke test passed: QQ-only drawer routes, hide preference, 100 podcast episodes, actual decoder seek to 30 seconds, portrait/landscape state retention, FM natural completion refill and new-track decoded progress, and controlled connection-failure recovery. Sanitized result: work/device-check2115/device-smoke-results.json.
- Background playback progressed 4055 ms over a 4-second sample; native pause/resume passed, no session error. No claim of physical Super Island touch verification.
- Previous default Flutter drive teardown uninstalled the preview app and reset local data. User informed; no pre-reset local-data backup found. New manual install/attach workflow keeps the app installed with keep-app-running; both 2115 runs retained QQ login.
- Complete regression: 241 passed, 3 skipped; last selected-radio dismissal fix: 4 focused tests passed. Static analysis has no errors/warnings, existing info-level suggestions remain.

- Final release 2115 installed using adb install -r. Version, original signing certificate, bundled MIT and absence of test markers verified for both ABIs. ARM64 13,797,762 bytes. Home screenshot shows official QQ avatar/nickname and QQ playlists after install; current account remained signed in. No GitHub or TV publication.
- Final release force-stop/reopen check: QQ avatar, nickname and populated playlists still displayed. Evidence: work/device-check2115/final-restart-profile.png.

## 2026-10-28：2115 共存包补测（当前源码 2116）

维护与新增功能：**tiancaiProgramer**。

本轮连接手机只有 `com.sixbugs.bujuan.preview` 2.0.8（2115），未检测到正式包，不将下列实机结果归为 2116 正式包验收。未卸载、清除数据、退出账号或修改云端歌单。

- QQ 单账号的账号页、侧栏、主页与每日推荐正常；结束进程再打开后，QQ 资料与歌单仍能读取。
- 真实熄屏观察三分钟，回到前台后的原生播放位置已推进至 221883 ms。熄屏期间系统会话位置快照停止刷新，未将快照中的 PLAYING 单独作为连续解码证据。设备 USB 充电中，不等同于断电省电或长时间深度休眠测试。
- 系统媒体暂停后，四秒间隔的位置均为 266929 ms；恢复播放约五秒再暂停，位置为 272030 ms，增加 5101 ms。横屏完整播放器与返回竖屏的页面可见；本轮进度条坐标操作未改变原生位置，不将拖动复验计为通过。
- 移动数据原本关闭。真实关闭 Wi-Fi 后，另一首 QQ 曲目请求进入系统媒体 ERROR；恢复 Wi-Fi 并手动重试，同一选中曲目进入 PLAYING。测试后 Wi-Fi 已连接，移动数据、自动旋转及旋转方向均恢复原值。
- 首次下载触发通知权限弹窗；关闭弹窗后权限仍未授予，下载仍成功。标准档《天外来物》显示 MP3、128 kbps、44.1 kHz、双声道，4,116,678 字节，保存到 `Music/BuYuPreview`。
- Wi-Fi 与移动数据均关闭时，从下载管理播放该本地文件，暂停后的原生位置达到 7834 ms。重开应用后，下载记录、规格与播放入口保留。本次测试文件保留供用户复核。
- 首次离线下载提交被通知弹窗阻断，恢复 Wi-Fi 后才真正开始；因此不将它计为真机下载失败重试通过。新增三项隔离回归覆盖保存权限失败、磁盘满以及 HTTP 503 后重复重试，确认失败不会误报完成、暂存文件清理、重开服务后可重试且不重复建任务。这些测试使用临时文件和本机 HTTP 服务，不是手机磁盘耗尽实测。
- 发现提示问题：保存阶段的 `FileSystemException` 也被统一显示为“下载失败，请检查网络后重试”，不能准确区分保存权限或磁盘问题；本轮仅记录，未修改运行实现。
- 本地完整回归 **244 项通过、3 项默认联网检查跳过**；另单独启用只读 QQ 搜索/热评/最新评论及网易云二维码等待扫码检查，均通过。新增测试静态检查无问题。

用户本人完成网易云登录后，本轮继续实测双账号：

- 账号页同时显示网易云和 QQ 已登录；网易云登录未清除原 QQ 会话。
- 头像来源从 QQ 切换为网易云，结束进程并重开后，网易云头像、昵称与选择保留，两个平台的歌单均可读取。
- 竖屏 QQ / 网易云来源筛选正确显示各平台歌单，网易云喜欢入口随筛选隐藏或显示，聚合收藏保持可见；恢复合并显示后横屏三列布局与快捷入口正常。测试结束恢复原 QQ 头像来源并再次重开确认，两个平台登录均保留。
- 已有聚合收藏同时显示同名歌曲的两个平台版本。点击网易云版本，原生队列项为 2、暂停位置 6477 ms；再点击 QQ 版本，队列项为 1、暂停位置 6585 ms。两次均经过 PLAYING，按真实进度确认音源可播放，并未修改收藏。

本轮未发现上述播放、网络恢复、双账号显示与状态保留场景的新功能故障。已记录的保存失败提示不准确问题尚未修正。仍待验证正式包升级、账号独立退出与重新登录、物理折叠/分屏、蓝牙与来电打断、断电长时间后台，以及手机真实下载中断恢复。脱敏记录和本地截图在 `G:\Data\bujuan-tools\device-audit-20261028`；不上传含个人界面的截图或认证二维码。

## 2026-10-28：2117 缓存文件权限修复

维护与新增功能：**tiancaiProgramer**。

- 横竖屏“网易云缓存歌曲”共用权限流程，先说明用途；取消不跳转系统设置，返回后未开启权限会明确提示并提供“重新授权”。连续点击只发起一个流程，授权状态重新检查后才进入缓存页；旧 Android 使用存储读取权限。
- 修正共享缓存根目录按正式包名写死的问题，正式包和共存包均能定位共享存储，不再将共存应用私有目录当成缓存根目录。
- 新增 11 项自动回归，覆盖取消、未授权重试、状态返回、旋转、页面销毁、已有权限、旧系统、设置异常及两种包名目录。含上一轮 3 项下载异常补测，完整回归 **255 项通过、3 项默认联网检查跳过**；本次修改静态检查无问题。
- ARM64 共存修复包已使用原正式证书签名，ZIP 对齐校验通过；`adb install -r` 成功，设备版本为 2.0.8（2117），原双账号和歌单保留。未发布 GitHub。
- 手机实测授权说明显示、暂不开启后返回、系统所有文件访问页跳转，以及不开启权限直接返回时的提示和重试按钮。系统所有文件权限保持未开启；开启后自动进入由状态返回自动回归验证，不将它声称为手机已授权实测。旋转配置恢复原值。

本地修复包：`G:\Data\BuYu-apk\BuYu-2.0.8-2117-coexist-preview-arm64.apk`。签名材料现位于 `F:\apk\BuYu`，原 `Tianlai` 目录已改名；本轮未将私钥或密码写入源码与日志。

## 2026-10-28：2118 正式包本地交付

按用户要求，将相同功能生成原签名正式包 ARM64 / ARM32，未上传 GitHub。两个包的包名、版本、原证书、ZIP 对齐和随包 MIT 许可核对通过，开发核验标记未包含在 AOT 中，正式包使用正式保存目录配置。

连接手机安装 ARM64 成功，正式包版本为 2.0.8（2118），桌面入口恢复，首页启动正常。由于此前正式包不存在，本次为新安装，首页未登录，未声称自动恢复旧正式包或共存包的账号与本地数据。共存包仍为 2117，原 QQ 头像和本地音乐可见；未卸载共存包，未改写其数据。正式包当前进程无崩溃标记。

本次仅提升正式交付构建号，运行实现与已完成 255 项自动回归的版本相同；未重新将未测的蓝牙、来电、折叠/分屏或长时间省电场景计为通过。详情见 [2118 正式包交付说明](releases/2.0.8-2118.md)。

## 2026-10-29：MIX Fold 3 正式包 2119 / 2120

维护与新增功能：**tiancaiProgramer**。

- 在 MIX Fold 3 正式包保留数据升级，登录后自动读取两平台原有聚合收藏；2120 再次升级和冷启动保留双账号与收藏。
- QQ 推荐歌单封面、内屏多列布局、歌单详情和真实播放通过。QQ 测试收藏断网时先在本地保存，恢复 Wi-Fi 后不手动刷新即可重试完成；取消后云端成员回读确认删除。
- 网易云每日歌曲读取、测试歌曲添加与取消同步通过；待同步状态只有在回读云端歌单确认变更后才清除。两平台新增测试收藏均已清理，原有三首完整保留。
- 发现并修复网易云断网资料请求失败被误判未登录的问题；2120 再次真实断网冷启动，账号与登录入口保留。
- 内屏横竖向聚合收藏布局核对通过。使用者确认手动打开歌曲菜单正常，实际合屏后菜单保留；外屏截图显示菜单完整。后续 ADB 注入点击未响应，原因未定位，不据此认定应用触控故障。
- 完整自动回归 **290 项通过，4 项默认联网检查跳过**；QQ 官方只读联网检查另行启用后 **2 项通过**。ARM64 / ARM32 原证书、包名、版本与 ZIP 对齐校验通过。
- 测试后网络和旋转设置恢复；截屏、账号相关记录及设备标识仅保存在本地，不作为发布附件。

本次没有完整验证蓝牙与来电打断、分屏、断电长时间后台，以及手机真实下载中断恢复。已记录的保存失败提示不准确问题仍保留。用户确认本轮测试后，按 **2.0.8（2120）** 发布 GitHub，详情见 [当前发布说明](releases/2.0.8-2120.md)。

## 2026-10-29：2120 更新检查提示修复补测

- 将检测更新反馈移到设置页原版本号位置，检查结果不弹窗；发现新版本的链接指向当前 BuYu 仓库。
- 新增 7 项回归覆盖最新状态位置、发现更高构建号后打开对应发布链接、网络失败及重试、无适用安装包、20 秒超时、重复点击与页面销毁，以及浏览器打开失败。完整回归 **297 项通过，4 项默认联网检查跳过**；本次静态检查无错误或警告，设置页保留两项既有样式提示。
- MIX Fold 3 使用原签名覆盖安装成功，原账号与三首聚合收藏保留。设备 APK 哈希与本地待发布包一致；使用者手动确认联网显示“已是最新版本”、真实关闭 Wi-Fi 后显示失败、恢复 Wi-Fi 后重新检查成功，均位于原版本号位置且无弹窗。恢复后的外屏截图核对通过，当前日志无崩溃标记。
- Wi-Fi 开启、移动数据关闭、自动旋转和旋转方向保持原值。只有 MIX Fold 3 安装修复包，未操作另一台手机。
- 在完成上述实机验证后，按用户要求替换现有 2.0.8（2120）发布附件；同版本已安装用户需手动下载覆盖安装。
