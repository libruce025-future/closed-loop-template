# closed-loop-template

静态 SPA → nginx on ECS 的需求到上线闭环。

```
Claude Code: 改码 → make check → commit → push → gh pr create → 停
GitHub PR:   CI 绿 → 合并（唯一闸门）
Actions:     make check → rsync dist/ → releases/<sha>/ → deploy-ctl deploy <sha>
ECS:         原子切换 current → nginx -t + reload → 校验 /version.json → 失败回滚
```

## 0. 前置

```bash
brew install gh
gh auth login
gh auth setup-git
```

## 1. 本地

```bash
git init -b main
git config user.name  "your-name"      # 仓库级，不影响全局
git config user.email "you@example.com"
git config core.hooksPath .githooks    # pre-commit 跑 check，pre-push 拦 main
make install
make check
make run          # http://127.0.0.1:3000
```

## 2. GitHub

```bash
gh repo create closed-loop-template --public --source=. --push
```

变量（不配置则部署工作流整体跳过）：

```bash
gh variable set DEPLOY_ENABLED --body "true"
gh variable set SITE_URL       --body "https://app.example.com"
```

密钥：

```bash
ssh-keygen -t ed25519 -N "" -C closed-loop-deploy -f ~/.ssh/closed-loop_deploy
ssh-keyscan -p 22 <ECS_HOST> > /tmp/known_hosts

gh secret set ECS_HOST         --body "<ECS_HOST>"
gh secret set ECS_USER         --body "deploy"
gh secret set ECS_SSH_KEY      < ~/.ssh/closed-loop_deploy
gh secret set ECS_KNOWN_HOSTS  < /tmp/known_hosts
```

分支保护（要求 PR + CI，禁止直推/强推）：

```bash
OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api -X PUT "repos/$OWNER_REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["check"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 0, "dismiss_stale_reviews": true },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

单人仓库无法给自己的 PR 批准，所以 review 数设为 0；强制项是“必须走 PR + check 通过”。

## 3. ECS 一次性初始化

安全组放行 22/80（HTTPS 另加 443）。把仓库传到服务器后：

```bash
scp -r closed-loop-template root@<ECS_HOST>:/root/
ssh root@<ECS_HOST> "sudo bash /root/closed-loop-template/deploy/bootstrap-ecs.sh"
```

按脚本末尾提示完成：放公钥、关密码登录、可选 certbot 上 HTTPS。

## 4. 首次发布

在服务器上手工验证一次，确认链路与权限：

```bash
sudo deploy-ctl status
# 合并一个 PR 后：
curl -fsS http://127.0.0.1:8080/version.json
```

## 5. 日常闭环

在 Claude Code 里直接描述需求，或输入 `/ship`：建分支 → 改码 → `make check` → 提交 → 推送 → 开 PR → 停。你合并后自动发布。

## 6. 回滚

```bash
sudo deploy-ctl rollback     # 切回上一份发布
sudo deploy-ctl status
ls /opt/closed-loop/releases/
```

自动回滚：`nginx -t` 失败或 `/version.json` 的 sha 不匹配时，脚本切回上一份发布并 reload；首次部署失败则保留现场供排查。

## 7. 换成你自己的构建

业务代码放 `app/`。如果用了 Vite/Webpack，把 `scripts/build.mjs` 的复制逻辑换成你的构建命令，并保证产物里写出 `version.json`：

```json
{ "sha": "<提交 SHA>", "builtAt": "<ISO 时间>" }
```

`Makefile` 的 `install/lint/build/test/check/run` 接口保持不变，CI 与部署脚本无需改动。

## 8. 安全与缓存

- `deploy` 用户不在 sudo 全权列表，只能执行 `deploy-ctl` 的三个动词
- 只允许密钥登录，固定 known_hosts，禁用 root 登录
- 静态站点无需 `.env`；仓库内不放任何密钥
- `index.html` 与 `version.json` 不缓存；如果将来给文件名加哈希，可在 `deploy/nginx.conf` 里对该类资源启用长缓存
