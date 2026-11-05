# 词隙 · WordGap

**在 Mac 菜单栏里，利用碎片时间记单词。**

一个原生 Swift / SwiftUI 背词工具：看词、回忆、揭晓、评分，随后按间隔复习。内置离线词库，不需要应用账号；AI 加词与易混词辨析按需使用自己的 DeepSeek API Key。

[译隙：配套的单句翻译练习](https://github.com/dagongzhanshi1/translategap) · [详细使用说明](docs/USER_GUIDE.md) · [MIT 许可证](LICENSE)

## 界面预览

| 单词卡片 | 中文选词 |
| :---: | :---: |
| ![词隙单词卡片](docs/images/word-card.png) | ![词隙中文选词](docs/images/chinese-quick-add.png) |

截图由程序使用模拟数据离屏渲染，不包含个人学习记录；系统玻璃的实际效果随桌面背景和系统设置变化。

## 能做什么

| 功能 | 说明 |
| --- | --- |
| 菜单栏随时学 | 全局 `⌘K` 显示或收起；244 × 190 点迷你卡片，也可展开到普通模式。 |
| 内置离线词库 | 7,758 个进阶词，含音标与中文释义，来自 MIT 授权的 ECDICT。可随机或按字母出词。 |
| 分开新学与复习 | 设置每日新学目标；显示今日待新学与待复习。未到期的词不会提前进入复习。 |
| 简单间隔复习 | 不认识：10 分钟；模糊：30 分钟；连续认识：按 1、3、7、14、30、60、120 天延长。 |
| 自建词库 | 导入 UTF-8 CSV / TSV，支持释义、音标、例句及例句翻译；已有词可标记掌握或恢复。 |
| 快捷加词 | `⌘⇧K` 从剪贴板或已获权限的选中文字加词；已有词复用本地释义，新词可手动填写或 AI 补全。 |
| 中文选英文 | 输入简短中文意思与语境，主动生成一个英文词或短语，检查后再加入学习。 |
| 按需易混词辨析 | 揭晓后按 `⌘B`，生成至多三个候选，显示具体区别；可保留或排除，结果在本机缓存。 |
| 发音与外观 | 使用 macOS 已安装的英语系统语音，支持美音 / 英音、自动朗读和可选评分提示音；浅色、深色、系统外观与玻璃材质。 |
| 学习统计 | 日 / 周 / 月统计、CSV 导出、学习进度 JSON 导出，以及评分撤回。 |

内置词库未附带现成例句；自建词库和 AI 新增词可保存例句。复习算法是项目自己的简单间隔规则，没有实现 FSRS。统计中的评分是自评，专注时长是应用内估算。

## 快速开始

当前开源版本 **2.7.6**。仓库提供源码与内置资源，自行编译后运行。

需要 **Apple Silicon Mac**、macOS 13 或更高版本，以及带 **macOS 26 SDK** 的 Apple Command Line Tools。编译脚本默认使用 `/Library/Developer/CommandLineTools` 中的 Swift 编译器；当前目标是 `arm64`。无需 Python 或第三方包管理器即可编译应用。

```sh
git clone https://github.com/dagongzhanshi1/wordgap.git
cd wordgap
bash scripts/build.sh
open dist/词隙.app
```

产物在 `dist/词隙.app`，编译缓存位于 `.build/`。可通过 `WORDGAP_APP_PATH`、`WORDGAP_BUILD_PATH` 指定其他绝对路径。构建采用本机 ad-hoc 签名，未做 Developer ID 公证；仓库没有提供经过苹果公证的安装包。macOS 26 使用原生玻璃，较旧系统使用替代材质。

第一次使用：点击菜单栏单词 → 空格揭晓释义 → 按 `1 / 2 / 3` 评分。普通离线背词无需配置 API。

## 常用快捷键

| 按键 | 作用 |
| --- | --- |
| `⌘K` | 全局显示 / 收起背词卡片 |
| `⌘⇧K` | 全局快捷加词 |
| `空格` | 揭晓 / 隐藏释义 |
| `1 / 2 / 3` | 不认识 / 模糊 / 认识，先揭晓再评分 |
| `4` | 标记掌握 |
| `5` 或 `⌘P` | 朗读当前词 |
| `⌘B` | 按需生成 / 筛选易混词 |
| `⌘Z` | 撤回上一次评分 |
| `⌘1 / ⌘2` | 切换新学 / 复习 |
| `⌘M` | 切换迷你 / 普通卡片 |
| `Esc` | 收起卡片 |

除全局唤出快捷键外，操作只在相应应用界面获得焦点时生效；快捷键冲突时仍可点击菜单栏使用。

## 数据、备份与 AI

- 学习进度、设置和自建词库保存在 `~/Library/Application Support/WordGap/`，不提供云同步。
- `progress.json` 保存学习状态；`progress.backup.json` 保留上一份备份。易混词缓存单独保存在 `confusables.json` 与 `confusables.backup.json`。
- 设置中可导出学习进度 JSON，但当前没有备份恢复界面；**完整迁移请先退出应用，再备份整个 WordGap 文件夹**，因为学习进度导出不包含单独的易混词缓存。具体恢复步骤见[使用说明](docs/USER_GUIDE.md#备份与恢复)。
- 不配置 DeepSeek 也能使用内置词库、导入、复习、发音和统计。新词可手动填释义。
- 可选 AI 功能需要自己的 DeepSeek API Key，存入 macOS 钥匙串；调用费用由服务商按账户规则计算。
- 释义补全发送当前词，中文选词发送当前中文意思与语境；易混词辨析发送目标词、释义和少量本地拼写候选，不上传整本词库或学习历史。新词从选词 / 剪贴板带入时，若已配置 Key 且本地未收录，可能自动请求释义；中文选词与易混词需主动触发。
- AI 生成内容可检查、编辑或排除。离线学习不依赖 AI 服务可用性。

## 开发与验证

```sh
# 编译后运行；使用临时目录和模拟接口，不修改日常学习记录
./dist/词隙.app/Contents/MacOS/WordGap --self-test
./dist/词隙.app/Contents/MacOS/WordGap --quick-add-test
./dist/词隙.app/Contents/MacOS/WordGap --confusion-test
```

`--self-test` 同时覆盖新学 / 复习计数、撤回、跨日、迁移、导入、统计与布局等检查。快捷加词检查包含中文选词；易混词检查覆盖缓存、解析和异步旧回复。离屏截图可使用 `--quick-add-test --previews /tmp/wordgap-previews`。真实 API 测试入口另见源码，不属于上述离线检查。

| 目录 | 内容 |
| --- | --- |
| `Sources/` | AppKit 菜单栏、SwiftUI 卡片、学习状态、发音、AI 与内置测试 |
| `Resources/` | 离线词库、授权文本和程序合成的提示音 |
| `scripts/` | 编译、图标生成、词库筛选和提示音生成脚本 |
| `docs/` | 使用说明、模拟截图与第三方材料说明 |

## 开源与授权

程序源码采用 [MIT License](LICENSE)。内置词库另保留 [ECDICT 原 MIT 许可证](Resources/ECDICT-LICENSE.txt)，来源及筛选方式见[词库说明](词库说明.md)和[第三方说明](THIRD_PARTY_NOTICES.md)。仓库包含词库资源，不包含个人学习记录或 API Key。

欢迎提交 Issue 或 Pull Request，参见 [CONTRIBUTING.md](CONTRIBUTING.md)。
