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
