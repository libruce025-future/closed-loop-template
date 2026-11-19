# closed-loop-template

需求 → 改码 → 验证 → PR → 合并后自动部署到阿里云 ECS。

```
Claude Code: 改码 → make check → commit → push → gh pr create → 停
GitHub PR:   CI 绿 + 人工 review → 合并（唯一闸门）
Actions:     构建镜像 → 推 ACR → ssh → deploy-ctl deploy <sha>
ECS:         快照 releases/<sha> → pull → up -d → 校验 /version → 失败回滚
```

## 0. 前置

```bash
brew install gh               # macOS
gh auth login                 # 必须本人交互完成
```

## 1. 本地

```bash
cd closed-loop-template
git init -b main
git config user.name  "your-name"      # 仓库级，不影响全局
git config user.email "you@example.com"
git config core.hooksPath .githooks    # pre-commit 跑 check，pre-push 拦 main
git add .
git commit -m "chore: bootstrap closed-loop template"
make install
make check
make run          # http://127.0.0.1:3000/health
```

有 Docker 时再跑 `make smoke`。

## 2. GitHub

创建仓库并推送：

```bash
gh repo create closed-loop-template --private --source=. --push
```

配置变量与密钥（`vars` 走 Environment/仓库变量，`secrets` 走加密密钥）：

```bash
gh variable set IMAGE_REGISTRY --body "registry.cn-hangzhou.aliyuncs.com"
gh variable set IMAGE_REPO     --body "your-namespace/closed-loop-template"
gh variable set DOMAIN         --body "app.example.com"

gh secret set REGISTRY_USERNAME
gh secret set REGISTRY_PASSWORD
gh secret set ECS_HOST
gh secret set ECS_USER --body "deploy"
gh secret set ECS_SSH_KEY  < ~/.ssh/closed-loop_deploy
gh secret set ECS_KNOWN_HOSTS < deploy/known_hosts
```

`ECS_KNOWN_HOSTS` 用 `ssh-keyscan -p 22 <ECS_HOST> > deploy/known_hosts` 生成后提交到 secret（不要提交到仓库）。

分支保护（要求 CI + 1 次 review，禁止直推/强推）：

```bash
OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh api -X PUT "repos/$OWNER_REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["check"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 1 },
  "restrictions": null
}
JSON
```

## 3. ECS 一次性初始化

安全组放行 22/80/443。把仓库落到服务器后执行：

```bash
scp -r closed-loop-template root@<ECS_HOST>:/root/
ssh root@<ECS_HOST> "sudo bash /root/closed-loop-template/deploy/bootstrap-ecs.sh"
```

然后按脚本末尾提示完成：放公钥、关密码登录、填 `deploy.env` / `app.env`、`docker login <ACR>`。

## 4. 首次发布

先手工验证一次部署链路（在服务器上）：

```bash
sudo deploy-ctl deploy <40-hex-sha>
sudo deploy-ctl status
curl -fsS https://<DOMAIN>/version
```

通过后，后续合并 PR 即自动发布。

## 5. 日常闭环

在 Claude Code 里直接描述需求，或输入 `/ship`：

1. 建 `feat/*` 分支并改码
2. `make check` 必须通过
3. Conventional Commit
4. 推送并 `gh pr create`
5. Claude 停在 PR，由你 review 合并

## 6. 回滚

```bash
sudo deploy-ctl rollback        # 恢复上一份发布快照
ls /opt/closed-loop/releases/   # 每份快照含 compose/Caddyfile/app.env/meta
```

自动回滚：部署后容器内 `/version` 不等于目标 SHA 时，脚本会恢复上一份快照；首次部署失败则保留现场供排查。

## 7. 安全边界

- `deploy` 用户不在 `docker` 组；只能通过 `sudo deploy-ctl` 执行三个动词
- SSH 仅密钥登录、固定 known_hosts、禁用 root 登录
- 镜像由 Actions 构建，ECS 只拉取
- 真实密钥只存在于 `/opt/closed-loop/{deploy,app}.env`（600，root）
- Claude 侧：`.claude/settings.json` 白名单 + 危险命令/密钥写入钩子

## 8. 换成你的技术栈

只替换 `app/`、`Dockerfile`、`package.json`，保持 `Makefile` 的 `install/lint/test/check/build/run` 接口不变，CI 与部署脚本无需改动。
