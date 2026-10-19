# 蜜柑计划安卓播放（实验版）

安卓番剧详情页的「开始观看」不再要求规则：按番剧名查询蜜柑计划的 RSS，用户自行核对字幕组、集数和清晰度并选择发布版本。支持修改搜索词；一次只打开所选版本，不会自动跳到另一条搜索结果。选中的 `.torrent` 元数据直接交给原生 BT 引擎（保留 private 标记和 tracker 层级；magnet 链接仍走原路径），并选择最大的常见视频文件，通过仅监听 `127.0.0.1` 的 HTTP Range 流交给现有播放器，实现边下载边播放和拖动；起播时从 Range 请求的 0 偏移尝试预缓冲最多 2 MiB（最多等待 5 秒），并优先调度后续 8 MiB；seek 不会额外等待预缓冲。读取等待完整、哈希校验过的 piece，并在 HTTP 请求取消时中断读取；piece 窗口按 Range/seek 位置由 Anacrolix reader 调度，参考 [WebTorrent 的 file iterator](https://github.com/webtorrent/webtorrent/blob/master/lib/file-iterator.js) 和 [Anacrolix Reader API](https://pkg.go.dev/github.com/anacrolix/torrent#Reader)。弱网下仍受 peer/带宽影响。退出/换片会停止会话并清理对应 infohash 的下载数据；历史版本残留的全局缓存可通过系统的应用数据管理清理。

**范围与限制**

- 优先实现安卓（原生引擎仅提供 arm64-v8a、x86_64；CI 只产出 arm64 APK，不提供 32 位版本）；其他平台暂保留原规则播放流程。安卓已跳过规则初始化/引导并隐藏规则管理、规则更新入口，但仓库中的旧规则代码、既有下载与同步模块尚未彻底删除。
- 蜜柑搜索 RSS 的结果可能不完整、混入其他作品，且发布标题不保证与 Bangumi 集数一致；不要依据自动识别的集数盲选。当前会提取季、单集/集数范围、分辨率、片源、视频编码、位深、音频编码、字幕提示与封装格式；字幕组不依赖组名白名单，仅根据前缀标签和通用结构谨慎识别，含糊时显示“未标注来源”；样本覆盖和歧义处理参考 Anitomy 的回归语料实践（[Anitomy](https://github.com/erengy/anitomy)）。发布列表可按单集（集数范围也会命中）和字幕组/标题筛选；字幕组过滤为自由文本，会搜索原始标题，不限于已识别或样本中出现过的组名。历史记录能重新打开同一发布版本，但目前不恢复播放位置。
- `flutter_go_torrent_streamer` 0.0.8 已以源码放在 `third_party/flutter_go_torrent_streamer`。构建 APK 前必须安装 Go 1.23.6 和 Android NDK 27.2.12479018，并运行 `third_party/flutter_go_torrent_streamer/go/build_android.sh`（使用 `ANDROID_HOME`，或设置 `ANDROID_NDK_HOME`）；脚本生成 arm64-v8a 和 x86_64 原生库及各 ABI 所需的 `libc++_shared.so`；后者是 Go/cgo 引擎的运行时依赖，缺失时 Android 无法加载 BT 引擎。仓库不包含旧版预编译 `.so`，缺少库时 Gradle 会报错，而不是打包未经修复的 BT 引擎。CI 在 `flutter build` 前生成库并检查 APK 是否同时包含 arm64 引擎和 C++ 运行时。仍需在真实安卓设备测试下载、seek、熄屏后台与 MKV/字幕兼容性。无做种/Tracker/DHT 连通性时可能卡住；需遵守当地法律，仅播放有权获取的内容。
- 投屏和同步观看不能直接访问手机的 `127.0.0.1`，蜜柑播放时隐藏了相关入口；下载记录页仍属于旧规则下载系统。

验证：可在 `third_party/flutter_go_torrent_streamer/go` 运行 `go test metainfo_spec.go metainfo_spec_test.go` 检查 private 标记、tracker 层级及非法元数据，运行 `go test stream_buffer.go stream_buffer_test.go` 检查 Range 偏移和预缓冲定位；Flutter 侧使用 `flutter analyze --no-fatal-infos --fatal-warnings` 与 `flutter test`。还需 CI 的 NDK 构建和真机播放验证。
