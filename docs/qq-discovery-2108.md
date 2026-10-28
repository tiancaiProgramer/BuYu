# QQ 发现功能接入（2108）

维护与新增功能：tiancaiProgramer。

## 使用方式

- 每日：沿用原按钮，页内切换网易云 / QQ 音乐，只登录 QQ 时自动选中 QQ。未登录的平台显示登录入口。
- FM：单账号直接播放；双账号弹出主题一致的平台选择面板。曲目和后续推荐始终绑定所选平台和当前账号，退出或切换账号后不借用另一平台续播。
- 播客：页内选择平台；QQ 部分提供原生有声专辑目录、搜索、节目列表、播放与分页。QQ 账号播客订阅同步尚未接入，不标为已同步订阅。
- 云盘：始终可见，只使用网易云账号；不接入 QQ 云盘，不参与隐藏规则。
- 设置 → UI设置 → 未登录隐藏：开启后，未登录平台的歌单来源和云端歌单隐藏；每日 / FM / 播客在任意一个平台已登录时保留。两个平台都未登录时这三个入口隐藏，云盘、头像登录、搜索、聚合收藏及本地分类保留。

## 协议与数据边界

| 能力 | 数据来源 |
| --- | --- |
| QQ 每日 | `music.recommend.RecommendFeed/get_recommend_feed` 唯一 subtype 510 卡片，携带卡片目录读取 `CgiGetDiss`；按账号与上海日期隔离缓存，空结果不替换成其他推荐 |
| QQ FM | `music.radioProxy.MbTrackRadioSvr/get_radio_track`；使用服务支持的空历史参数，近期歌曲在本地去重（2109 修正），保留原 MID / file / songType，末尾补歌 |
| QQ 播客目录 | QQ 网页搜索的原生播客主播身份 14，再通过 `music.musichallAlbum.AlbumListServer/GetAlbumList` 读取明确标记为人声音频的节目专辑；不把音乐搜索结果直接改名为播客 |
| QQ 节目 | `music.musichallAlbum.AlbumSongList/GetAlbumSongList` 的 `songInfo`，走既有 QQ 音频、收藏、评论和下载菜单流程，保持平台原有权限 |

连续 FM 保留近期曲目记录，每批补歌最多尝试两次；服务无新歌或失败时显示错误，避免无限循环旧批次。手动切歌、换队列、切换平台、退出账号及暂停均有迟到请求保护；暂停期间到达的新队列也持久化保存。

协议事实参考 [L-1124/QQMusicApi](https://github.com/L-1124/QQMusicApi)、[jsososo/QQMusicApi](https://github.com/jsososo/QQMusicApi) 与 [simple-music 接口记录](https://github.com/Yyyangshenghao/simple-music/blob/master/docs/qq-music-api.md)。未复制或分发这些项目的代码，客户端实现由本维护分支编写，原 BuJuan 版权和 MIT 全文保留。

## 实际核验记录

- 用户重新登录 QQ 后，手机只读核验得到一个真正的每日推荐卡片，猜你喜欢返回五首歌曲；没有导出登录票据或请求修改歌单。
- QQ 官方返回的原生节目专辑“随机波动StochasticVolatility”共有 277 期；已读取原生节目列表与 `songInfo`，样例单期长度 2651 秒。
- 默认“播客”查询的主播对应三张原生人声音频专辑。
- 样例 QQ 节目音频解析成功，读取 1024 字节后即关闭连接：HTTP 206、audio/mpeg、MP3 文件头；没有保存完整节目音频。
- 2026-10-28 手机恢复 USB 连接，已安装最终 2108 共存包，正式版仍为 2092。用户已手动打开 QQ 每日页面，真机确认歌曲、原生封面及平台信息正常，横屏为三列且无文字裁切；自动旋转已恢复。QQ 播客“啊！是猫咪呀”的原生节目页、封面、横屏三列与加载更多入口也已真机确认；播客实际出声及 FM 最终播放继续核验。最终共存包默认不执行开发核验，不自动播放、下载或操作歌单。
