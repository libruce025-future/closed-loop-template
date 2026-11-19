# closed-loop-template

静态 SPA（nginx on ECS）的需求 → 改码 → 验证 → PR → 合并后自动部署闭环。

## 命令

- `make install` 安装依赖（`npm ci`）
- `make check` 必过闸门（lint + build + dist 校验）
- `make run` 本地预览（http://127.0.0.1:3000，含 SPA 回退）
- 产物在 `dist/`，由 `scripts/build.mjs` 生成；`version.json` 内含提交 SHA

## 交付流程（强制）

1. **先开分支**：`feat/<slug>`，禁止在 `main` 上直接提交或推送。
2. **实现需求**：业务代码放 `app/`；需要打包时改 `scripts/build.mjs`，保持 `make check` 语义不变。
3. **验证**：`make check` 必须通过；涉及路由/交互时再 `make run` 手动看一遍。不通过不得提交。
4. **提交**：Conventional Commits（`feat:` / `fix:` / `chore:`），一次提交聚焦一件事。
5. **推送并发起 PR**：`git push -u origin HEAD`，然后 `gh pr create`，正文包含变更摘要与验证方式。
6. **停在这里**：把 PR 链接交回用户。合并是唯一的人工闸门。

## 硬性禁止

- 不合并 PR，不推送 `main`/`master`，不强推，不 `reset --hard`
- 不改 `.github/workflows/` 的触发条件来绕过 PR 闸门
- 不在仓库内放任何密钥；部署私钥只进 GitHub Secrets，服务器公钥只进 `authorized_keys`
- 部署失败时不要绕过校验；回滚走 `sudo deploy-ctl rollback`

## 部署拓扑

PR 合并 → Actions 构建 `dist/` → `rsync` 到 `/opt/closed-loop/releases/<sha>/` → `sudo deploy-ctl deploy <sha>` → 原子切换 `current` 符号链接 → `nginx -t` + reload → 校验 `/version.json` 的 sha → 任一步失败自动切回上一份发布。静态站点没有服务端逻辑，也没有 `.env`。
