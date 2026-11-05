# 第三方材料与资源

## ECDICT

内置 `Resources/advanced.json` 从 [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT) 筛选而来，共 7,758 词，保留词目、音标与中文释义。

ECDICT 采用 MIT License，版权声明以随附的 [Resources/ECDICT-LICENSE.txt](Resources/ECDICT-LICENSE.txt) 为准。重新分发该词库或其重要部分时，请一并保留原许可证和版权声明。筛选流程与局限见[词库说明](词库说明.md)。

## 程序生成资源

应用图标由 `scripts/icon.swift` 生成；评分提示音由 `scripts/make-feedback-sounds.py` 合成。系统朗读使用 macOS 已安装的语音，仓库不分发苹果语音模型、SDK 或系统字体文件。

## 可选在线服务

AI 加词、中文选词与易混词通过用户自己的 DeepSeek 账户调用。MIT 许可证不授予该服务的额度、账号或商标权；服务可用性及计费以提供方为准。
