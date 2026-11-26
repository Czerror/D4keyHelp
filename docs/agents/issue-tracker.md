# GitHub Issues

议题和规格保存在 `Czerror/D4keyHelp`。在仓库内运行 `gh`，首次写入前用 `gh repo view --json nameWithOwner` 核对目标。在其他目录运行时显式指定 `-R Czerror/D4keyHelp`。

- 发布规格或工单用 `gh issue create --title "标题" --body-file <文件>`。
- 读取工单用 `gh issue view <编号> --json number,title,body,labels,comments`。查队列用 `gh issue list --state open`，按需加 `--label`。
- 添加或移除标签用 `gh issue edit <编号> --add-label <标签>` 或 `--remove-label <标签>`。
- 需要说明关闭原因时，先用 `gh issue comment <编号> --body-file <文件>` 留言，再用 `gh issue close <编号>` 关闭。
- 关联父子议题用 `gh issue edit <父编号> --add-sub-issue <子编号>`。无法使用子议题时，在子议题正文首行写 `Part of #<父编号>`，并在父议题任务清单里链接子项。
- 登记阻塞关系用 `gh issue edit <被阻塞编号> --add-blocked-by <前置编号>`。无法使用原生依赖时，在正文首行写 `Blocked by: #<前置编号>`。所有前置议题关闭后才算解除阻塞。

**PRs as a request surface: no.**

## Wayfinder

地图使用带 `wayfinder:map` 标签的议题，正文记录笔记、已作决定和待查问题。子议题按任务类型使用 `wayfinder:research`、`wayfinder:prototype`、`wayfinder:grilling` 或 `wayfinder:task`。按地图顺序选择首个开放、无人认领且无未关闭前置项的子议题，用 `gh issue edit <编号> --add-assignee @me` 认领。完成时评论并关闭子议题，把结论摘要和链接补回地图。
