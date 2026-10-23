# 拾读 Glean 素材包

视觉：青绿 `#0F766E`、薄荷 `#CCFBF1`、奶油白 `#FFFDF7`、暖金 `#FBBF24`。封面及品牌图为生成式插画；状态图为可编辑 SVG。

## 文件用途

- `brand/app-icon.png`：应用图标原图，方形全出血。`app-icon-1024.png`、`app-icon-512.png`、`app-icon-192.png`、`app-icon-48.png`：常用尺寸。
- `covers/tech.png`、`business.png`、`culture.png`、`daily.png`：科技、商业、文化、日常通用分类封面。用于分类或缺省封面，具体文章可继续按主题扩展。
- `illustrations/reading.png`：欢迎、关于或阅读引导插画。
- `illustrations/empty-vocabulary.svg`：生词本为空。
- `illustrations/empty-articles.svg`：暂无文章或无筛选结果。
- `illustrations/reading-complete.svg`：阅读完成。
- `illustrations/offline.svg`：离线内容可用。

## 给 Claude 的接入说明

本次仅交付素材，不修改正在开发中的 Dart、pubspec 或原生工程文件。

1. 在 pubspec.yaml 的 flutter/assets 中登记 `assets/brand/`、`assets/covers/`、`assets/illustrations/`。
2. PNG 使用 `Image.asset`；分类封面路径可由 category (`tech/business/culture/daily`) 映射，使用 `BoxFit.cover`。现有 ArticleCover 是程序绘制封面，替换时保留 Hero 和圆角行为。
3. SVG 需要 flutter_svg 依赖，使用 `SvgPicture.asset`。建议状态插画宽 160–220 逻辑像素，说明文字由 Flutter 渲染。
4. 应用图标需由原生平台或 flutter_launcher_icons 导出配置。此包提供方形图标，未生成 Android adaptive foreground/monochrome 分层；不要把完整背景图直接当透明前景。iOS 使用无透明的 1024 PNG。
5. 导航及操作图标继续使用工程现有 Material Icons，保持一致且不增加图片解码开销。加载动画、阅读进度等继续使用现有 Flutter 组件。

素材为本项目生成；未包含第三方照片、字体或品牌商标。上线前请在设备上检查小尺寸图标、封面裁切及深色模式对比度。
