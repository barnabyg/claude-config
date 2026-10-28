---
name: pr-screenshots
description: Show screenshots or other images in a GitHub PR, issue or comment. Uploads them to the repo's pr-assets branch and returns Markdown to embed.
---

# PR screenshots

GitHub has no API for real attachments: drag-and-drop uploads need a signed-in browser, and `gh` cannot do them. So images go to an orphan `pr-assets` branch in the repo itself, through the GitHub API, and are embedded with links pinned to the upload commit. `~/.claude/scripts/pr-asset.sh` does the upload; it never touches the working tree, index or local branches, and creates the branch on first use.

## Steps

1. **Prepare the images.** PNG, JPEG, GIF or WebP, each under 10 MB, cropped to what the reader needs. SVG is served as text through this route, so render it to PNG first. Check every image for secrets, tokens and personal data before uploading: anyone who can read the repo can read the branch.
2. **Upload.** From inside the repo, run `bash ~/.claude/scripts/pr-asset.sh [-d folder] <file>...`. Files land in a folder named after the current branch unless `-d` names one (for example `-d pr-123`). It prints one `![name](url)` line per file, in argument order.
3. **Embed.** Rewrite each alt text to say what the image shows, then put the lines into the body or comment (`gh pr create --body-file`, `gh pr edit --body-file`, `gh pr comment --body-file`, or the issue equivalents). Done when `gh pr view` (or `gh issue view`) shows the image links in place.

## Reference

- **Who can see them:** only signed-in users with read access, in a private repo; everyone, in a public one. In a private repo the images show as broken in email notifications and in signed-out views.
- **Permanence:** each upload is a new commit, and old links keep working because they are pinned to their commit. The images stay in the branch history; the `pr-assets` branch is shared by every PR and is never merged or deleted.
- **Failures:** a ruleset or branch protection that blocks creating `pr-assets` makes the upload fail; report the error to the user. The script retries three times when another upload moves the branch at the same moment.
- **Native attachment:** when the user wants a true GitHub attachment, Claude in Chrome's `upload_image` can drop the file into the comment box in their signed-in Chrome. That posts content, so ask first.
