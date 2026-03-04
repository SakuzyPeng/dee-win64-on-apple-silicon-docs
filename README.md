# DEE 在 macOS（Apple Silicon）上运行 Win x64 的实践笔记

本仓库用于记录并复现实验：在 Apple Silicon macOS 上通过 `gcenx/wine` 运行 Dolby Encoding Engine（Windows x64）。

English README: [README.en.md](./README.en.md)
免责声明 / Disclaimer: [DISCLAIMER.md](./DISCLAIMER.md)

## 文档入口

- 中文（主文档）：[DEE_Encoding_on_macOS_with_gcenx_wine.md](./DEE_Encoding_on_macOS_with_gcenx_wine.md)
- English: [DEE_Encoding_on_macOS_with_gcenx_wine.en.md](./DEE_Encoding_on_macOS_with_gcenx_wine.en.md)

## 仓库包含内容

- Markdown 文档
- 轻量文本说明

## 仓库不包含内容

- Dolby 工具二进制/安装包（`.exe`、`.dll`、`.zip`）
- 授权文件（`.lic`）
- 媒体测试资产（`.wav`、`.ec3`）
- 运行日志（`.log`）
- 解压后的引擎目录

## 若公开仓库，建议再确认

1. `git ls-files` 仅包含文档与说明文件（不含二进制/许可证/媒体）。
2. 提交历史中没有误提交敏感信息（token、私钥、本地绝对路径等）。
3. 已阅读并接受 [DISCLAIMER.md](./DISCLAIMER.md) 的边界说明。
4. 补充合适的开源许可证（如仅分享文档，可选择文档许可证）。
