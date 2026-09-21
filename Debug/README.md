# Debug/

Home for SENTINEL's self-verification tooling (CLAUDE.md §1.2): since Claude
Code cannot see the rendered window, `Source/Main.odin`'s `--capture <frames>
<path>` flag renders N frames and saves a screenshot via `glReadPixels` here
(or to a path the flag specifies) so Claude can inspect its own output.

Planned contents (Session 0, Prompts.md Session 0 item 4):

- A screenshot encoder Claude can both write and read back. Try Odin's
  `core:image` encoders first; if the format needs a helper Claude can't read
  natively, keep the conversion step in a small file in this directory and
  note it in PROGRESS.md.
- Nothing here is theme-specific; keep it generic capture/encode plumbing.

No implementation yet — this is the project skeleton stage.
