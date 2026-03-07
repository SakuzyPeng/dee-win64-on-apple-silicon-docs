# DEE 在 macOS（Apple Silicon）上运行 Win x64 的实践笔记

本仓库用于记录并复现实验：在 Apple Silicon macOS 上通过 `gcenx/wine` 运行 Dolby Encoding Engine（Windows x64）。

补充：`FEX` 容器路线用于降低对 `Rosetta 2` 的依赖，提前应对苹果未来可能弃用 `Rosetta 2` 的风险。

English README: [README.en.md](./README.en.md)
免责声明 / Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)
许可证 / Licenses: [LICENSE](./LICENSE), [LICENSE-docs](./LICENSE-docs)

## 文档入口

- 中文（主文档）：[DEE_Encoding_on_macOS_with_gcenx_wine.md](./DEE_Encoding_on_macOS_with_gcenx_wine.md)
- FEX 容器指南（中文）：[DEE_Docker_FEX_Experiment.md](./DEE_Docker_FEX_Experiment.md)
- 容器化方案（Docker + 自编译精简 Wine，非 FEX，依赖 Rosetta 2）：[DEE_Docker_Minimal_Wine.md](./DEE_Docker_Minimal_Wine.md)

## 仓库包含内容

- Markdown 文档
- 轻量文本说明

## 仓库不包含内容

- Dolby 工具二进制/安装包（`.exe`、`.dll`、`.zip`）
- 授权文件（`.lic`）
- 媒体测试资产（`.wav`、`.ec3`）
- 运行日志（`.log`）
- 解压后的引擎目录

## 开源许可证说明

1. 代码与脚本：`MIT`（见 [LICENSE](./LICENSE)）
2. 文档内容：`CC BY 4.0`（见 [LICENSE-docs](./LICENSE-docs)）
