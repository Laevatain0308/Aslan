# Aslan

Aslan 是基于 [Kazumi](https://github.com/Predidit/Kazumi) 的 fork / 修改版本。
上游 Kazumi 由 Predidit 及 Kazumi contributors 开发，并依据 GPL-3.0 发布。
Aslan 不是 Kazumi 官方版本；问题反馈、发布版本和维护策略请以本仓库为准。

Aslan 使用 Flutter 开发，是基于自定义规则的番剧采集与在线观看程序。使用最多五行基于 `Xpath` 语法的选择器构建规则，支持规则导入与规则分享，支持基于 `Anime4K` 的实时超分辨率。

## 支持平台

- Android 10 及以上
- Windows 10 及以上
- macOS 10.15 及以上
- Linux（实验性）
- iOS 13 及以上（需要自签名）

## 当前差异

Aslan 保留 Kazumi 的 GPL-3.0 授权和上游归属声明，并加入 Laevatain 维护的修改。当前版本暂时隐藏或禁用以下 Kazumi 上游功能入口：

- 弹幕功能及相关弹弹play入口
- 一起看功能及播放器入口
- 以图搜番功能及搜索页入口
- WebDAV 同步设置及后台同步

Kazumi 原图标未随 Aslan 使用。Aslan 使用独立占位图标资产，后续可替换为新的授权品牌图标。

## 功能

- [x] 规则编辑器
- [x] 番剧目录
- [x] 番剧搜索
- [x] 番剧时间表
- [x] 番剧字幕
- [x] 分集播放
- [x] 视频播放器
- [x] 多视频源支持
- [x] 规则分享
- [x] 硬件加速
- [x] 高刷适配
- [x] 追番列表
- [x] 在线更新
- [x] 历史记录
- [x] 倍速播放
- [x] 配色方案
- [x] 无线投屏（DLNA）
- [x] 外部播放器播放
- [x] 超分辨率
- [x] 番剧下载
- [ ] 自有同步功能
- [ ] 番剧更新提醒

## 构建

本项目编译需要良好的网络环境。除了由 Google 托管的 Flutter 相关依赖外，本项目同样依赖托管在 MavenCentral、GitHub、SourceForge 等平台上的资源。如果您位于中国大陆，可能需要设置恰当的镜像地址。

```bash
flutter pub get
flutter test
flutter build apk
```

## 美术资源

Aslan 不使用 Kazumi 上游 README 中提到的受单独授权保护的 Kazumi 图标。

本项目内嵌字体为 [Mi Sans](https://hyperos.mi.com/font/en/details/sc/) 字体，由 [Xiaomi](https://www.mi.com/) 开发和拥有版权。

## 许可证与归属

本项目基于 GNU 通用公共许可证第 3 版（GPL-3.0）授权。请参阅 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。

上游项目：

- Kazumi: <https://github.com/Predidit/Kazumi>
- Kazumi contributors: <https://github.com/Predidit/Kazumi/graphs/contributors>

## 免责声明

我们不对本项目的适用性、可靠性或准确性作出任何明示或暗示的保证。在法律允许的最大范围内，作者和贡献者不承担任何因使用本软件而产生的直接、间接、偶然、特殊或后果性的损害赔偿责任。

使用本项目需遵守所在地法律法规，不得进行任何侵犯第三方知识产权的行为。因使用本项目而产生的数据和缓存应在 24 小时内清除，超出 24 小时的使用需获得相关权利人的授权。

## 隐私政策

我们不收集任何用户数据，不使用任何遥测组件。

## 致谢

感谢 Kazumi、XpathSelector、Bangumi、Anime4K、media-kit、avbuild、hive 及其他开源项目为本项目提供基础能力。
