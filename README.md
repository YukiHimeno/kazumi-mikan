<div align="center">

# Kazumi Mikan · kazumi-mikan

<img src="assets/images/logo/logo_rounded.png" alt="Kazumi Mikan 蜜柑播放图标" width="180">

**以安卓为优先的 [Kazumi](https://github.com/Predidit/Kazumi) 改版：从蜜柑计划查找 BT 发布版本，在 Kazumi 自带播放器中边下边播。**

</div>

## 安卓使用

1. 在番剧详情页点击「开始观看」，按作品名搜索蜜柑计划 RSS；可以修改关键词。
2. 手动确认字幕组、集数、清晰度，选择一个 BT 发布版本。
3. 应用获取种子元数据，连接 BT 对等节点，通过仅供本机访问的 HTTP 流交给 Kazumi 播放器；播放与进度拖动都留在应用内。

安卓播放**不需要安装规则**。包名为 `io.github.yukihimeno.kazumimikan`，与原版 Kazumi 分开安装。引擎当前只提供 arm64-v8a 和 x86_64 原生库，无法在 32 位安卓上运行。

> 这是实验版。RSS 搜索结果可能不完整；无可用对等节点时无法播放。MKV、字幕、拖动进度和后台播放仍需真机验证。请仅获取有权使用的内容。

## 构建与 CI

- Flutter 版本见 `pubspec.yaml`（目前 3.47.7），Android 构建需要 JDK 17、Android SDK，以及 `clang`/CMake/Ninja 等原生工具。
- 本地执行：`flutter pub get && flutter test && flutter analyze --no-fatal-infos --fatal-warnings && flutter build apk --release --target-platform android-arm64 --split-per-abi`。
- 推送到 `main`、提交 PR 或手动运行 **Android CI** 会检查代码并上传 arm64 APK 构建产物；该 APK 暂用 Flutter 模板中的**调试签名**，不应用于正式发布。Tag/手动的 **Android release build** 仅上传构建产物，不会自动发布 Release。

更多设计、范围与已知限制见 [MIKAN_ANDROID.md](MIKAN_ANDROID.md)。非安卓平台仍保留上游的规则播放代码，尚未完成独立迁移；Dart 内部包名仍为 `kazumi`，避免大范围导入路径改写。

## 来源与许可

本项目 fork 自 [Predidit/Kazumi](https://github.com/Predidit/Kazumi)，感谢原作者与贡献者。代码继续遵循仓库内的 [GPL-3.0 许可](LICENSE)；第三方依赖的许可见 `licenses/`。
