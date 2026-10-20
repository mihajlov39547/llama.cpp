# start-codex.ps1
# Starts Codex with approval prompts disabled and unrestricted sandbox access.
# Resumes the most recent Codex session.

codex `
    --ask-for-approval never `
    --sandbox danger-full-access `
    --disable apps `
    resume