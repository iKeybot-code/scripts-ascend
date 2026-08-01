# Scripts Ascend Wiki

昇腾（Ascend）大模型推理开发脚本与工具集知识库 —— 使用指南、调测复盘、设计方案。

## Background

本仓库是昇腾推理开发过程中的**脚本与工具集**，同时配套 MkDocs Material Wiki 知识库，用于沉淀：

- **实践指南** —— PD/KV Pool 分离部署、编译安装、测试拉起
- **调测经验** —— 线上问题定位复盘、环境调试踩坑
- **设计方案** —— 关键模块的源码追踪与方案分析

## Structure

```
scripts-ascend/
├── example/                    # 样例工程（PD/KV Pool 脚本）
│   ├── common/                 # 公共脚本
│   ├── template/               # 模板配置
│   └── benchmark/              # 性能测试
├── backup/                     # 旧版备份脚本
├── prepare_aisbench.sh         # AISBench 环境准备
├── start_container.sh          # 容器启动脚本
│
├── docs/                       # Wiki 文档（MkDocs Material）
│   ├── index.md                # 首页
│   ├── debug/                  # 调测经验
│   ├── design/                 # 设计方案
│   ├── practice/               # 实践指南
│   ├── hooks/                  # MkDocs 自定义钩子
│   ├── javascripts/            # 自定义 JS
│   └── stylesheets/            # 自定义 CSS
│
├── overrides/                  # MkDocs 模板覆盖
│   └── partials/
│       ├── content.html        # 作者 + 最后修改人展示
│       └── comments.html       # Giscus 评论系统
│
├── draft/                      # 草稿区
├── mkdocs.yml                  # MkDocs 配置
├── requirements.txt            # Python 依赖
└── .readthedocs.yaml           # Read the Docs 构建配置
```

## How to Use

### 本地预览文档

```bash
# 安装依赖
pip install -r requirements.txt

# 启动本地服务
mkdocs serve
```

浏览器打开 `http://127.0.0.1:8000/` 即可预览。

### 构建静态站点

```bash
mkdocs build
```

### 文档贡献

- 使用 Markdown 编写，保持结构清晰
- 文档内可引用外部链接或关联其他文档
- `debug/`、`design/`、`practice/` 下的文档需在 `mkdocs.yml` 的 `nav` 配置中注册
- Giscus 评论功能需要先配置 GitHub Discussions（参考 [Giscus 配置指南](https://giscus.app/)）

## Documentation Site

本站由 [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) 构建，托管于 [Read the Docs](https://readthedocs.org/)。

- 文档站点: https://scripts-ascend.readthedocs.io/ （需配置 Read the Docs 后生效）

## Related Repos

- [vllm-ascend](https://github.com/vllm-project/vllm-ascend) — vLLM 推理框架在昇腾平台的移植与适配
- [Ascend-Inference-wiki](https://github.com/xuchi-0808/Ascend-Inference-wiki) — 昇腾推理开发经验参考 Wiki

## Remote

- GitHub: `git@github.com:iKeybot-code/scripts-ascend.git` (main)
