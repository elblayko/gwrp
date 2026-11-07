---
trigger: always_on
description: Language settings
---

# Output Rules: Strict ASCII Only

Rules:
You must strictly restrict all outputs, code, comments, documentation, and edits to 7-bit ASCII characters (code points 0x00 to 0x7F).

NEVER output any character matching regex: [^\x00-\x7F]
NO smart/curly quotes (' ', " ") -> use standard straight quotes (', ")
NO em/en dashes (—, –) -> use standard hyphens (-, --)
NO bullet glyphs (•, ▪) -> use - or \*
NO emojis (🚀, ✅), degree symbols (°), or unicode arrows (→) -> use text equivalents ([OK], deg, C, F, ->)
If non-ASCII values are required in code, use escape sequences (\xNN, \uNNNN) instead of literal characters.
