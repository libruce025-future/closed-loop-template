# closed-loop-template

需求 → 改码 → 验证 → PR → 合并后自动部署到阿里云 ECS 的闭环模板。

## 命令

- `make install` 安装依赖（`npm ci`）
- `make check` 必过闸门（lint + test；有 Docker 时附加 compose 校验）
- `make run` 本地运行（:3000）
- `make docker-build` / `make smoke` 构建镜像并做容器冒烟
- `deploy/` 与 `scripts/` 为服务器侧内容，不要手工改线上文件

## 交付流程（强制）

1. **先开分支**：`feat/<slug>`，禁止在 `main` 上直接提交或推送。
2. **实现需求**，保持最小改动；换技术栈时只替换 `app/`、`Dockerfile` 与 `package.json`，保持 `Makefile` 接口不变。
3. **验证**：`make check` 必须通过；涉及容器/路由改动时再跑 `make smoke`。不通过不得提交。
4. **提交**：Conventional Commits（`feat: …` / `fix: …` / `chore: …`），一次提交聚焦一件事。
5. **推送并发起 PR**：`git push -u origin HEAD`，然后 `gh pr create`，正文包含变更摘要与测试方式。
6. **停在这里**：把 PR 链接交回用户。合并是唯一的人工闸门。

## 硬性禁止

- 不合并 PR，不推送 `main`/`master`，不强推，不 `reset --hard`
- 不读写 `.env` / 密钥文件；真实密钥只存在于 ECS 的 `/opt/closed-loop/*.env`
- 不改 `.github/workflows/` 中的部署触发条件来绕过 PR 闸门
- 部署失败时不要绕过健康检查；回滚走 `deploy-ctl rollback`

## 部署拓扑

PR 合并 → Actions 构建 `linux/amd64` 镜像并推送 ACR → `ssh deploy@ecs sudo deploy-ctl deploy <40-hex-sha>` → 服务器快照 `releases/<sha>/` → 容器内 `/version` 比对 SHA → 失败自动恢复上一份快照。
