# 实践指南
昇腾大模型推理脚本工具集的操作指南、编译安装与测试拉起方法。

---

## 文章列表

### PD / KV Pool 样例工程设计与操作指南

覆盖 Prefill-Decode 分离部署的完整脚本体系，包括单节点、多节点、KV 池化等场景的配置与操作。

[example/README.md →](https://github.com/iKeybot-code/scripts-ascend/blob/main/example/README.md)

主要内容：
- 统一配置入口与能力开关
- 单节点 / 多节点 PD 分离部署
- KV 池化开关与 Mooncake 传输层
- AISBench 精度验证
- 投机解码、编译配置、Pipeline Parallel

---

> 更多内容持续完善中，欢迎贡献。
