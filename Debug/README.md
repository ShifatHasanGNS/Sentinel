# Debug/

Home for SENTINEL's self-verification tooling (CLAUDE.md §1.2): since Claude
Code cannot see the rendered window, `Source/Main.odin`'s `--capture <frames>
<path>` flag renders N frames and saves a screenshot via `glReadPixels` here
(or to a path the flag specifies) so Claude can inspect its own output.

Contents (implemented in Session 0):

- `Capture.odin` (package `Debug`, theme-agnostic): `Save_Screenshot(path,
  width, height)` reads the framebuffer with `gl.ReadPixels`, flips it
  top-down (glReadPixels' row 0 is the bottom of the image; encoders expect
  row 0 to be the top), and writes it as BMP via `core:image/bmp` — the only
  format in this Odin build's `core:image` that can both encode and decode
  (`core:image/png` only decodes here).
- `ToPng.sh`: the conversion helper BMP needed. Claude Code's file-reading
  tool cannot render BMP visually (confirmed empirically: it reads PNG
  directly but errors on BMP as an unreadable binary file), so this script
  converts a capture to PNG with macOS's built-in `sips`. Development
  convenience only; never invoked by the SENTINEL program itself.
- `Captures/`: default place to point `--capture <frames> <path>` at
  (gitignored; nothing here is meant to be committed).

Usage: `odin run Source -out:Sentinel -- --capture 5 Debug/Captures/x.bmp`,
then `Debug/ToPng.sh Debug/Captures/x.bmp` to get a viewable PNG.
