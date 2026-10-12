---
name: start
description: Start work on a roadmap item. Use when asked to begin a feature or bug by its id, e.g. "/start OP-412".
---
1. Find /roadmap/**/<id>-*.md and read it fully, plus the linked spec in /docs/specs.
2. Create branch `<id>-<slug>` from main.
3. Set front matter `status: in-progress`. Set `owner: claude` only if empty.
4. Commit `<id>: start` and open a draft PR whose body links the file and lists the tasks.
