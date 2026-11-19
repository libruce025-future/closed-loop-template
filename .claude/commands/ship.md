---
description: 校验 → 提交 → 推送 → 发起 PR（不合并）
allowed-tools: Bash(make:*), Bash(npm:*), Bash(git:*), Bash(gh:*)
---

执行以下步骤，任何一步失败就停下并报告，不要跳过。

1. `git rev-parse --abbrev-ref HEAD`。如果在 `main`/`master`，创建 `feat/<short-slug>`（slug 由本次改动概括）。
2. `git status --short` 与 `git diff --stat`，确认改动范围与用户需求一致；无关文件不要提交。
3. `make check`。失败则修复后重跑，不得带病提交。
4. 按文件逐个 `git add <path>`（不要 `git add -A`），用 Conventional Commits 提交。
5. `git push -u origin HEAD`。
6. `gh pr create`，标题 ≤70 字符，正文用以下结构：

```
## Summary
- …

## Test plan
- [ ] make check
- [ ] …
```

7. 输出 PR URL，然后停止。**不要合并 PR，不要推送 main。**
