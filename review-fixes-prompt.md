You are applying fixes from a code review.

## Review Document

Read the review at: `{{REVIEW_DOC_PATH}}`

## Your Task

1. Read the review document
2. If the verdict is **PASS**, respond with "No fixes needed" and stop
3. For each **Blocking Issue** (B1, B2, ...):
   - Understand the problem described
   - Implement the fix
   - Verify the fix addresses the described problem
4. Run quality checks (typecheck, lint, test — whatever the project uses)
5. If you made changes, commit with message: `fix: {{STORY_ID}} review fixes`
6. If quality checks fail, fix those too before committing

## Rules

- ONLY fix Blocking Issues — ignore Suggestions
- Keep fixes minimal and focused — do not refactor surrounding code
- Do not change behavior beyond what the blocking issue requires
- If a blocking issue is unclear or you disagree with it, skip it and note why in the commit message
