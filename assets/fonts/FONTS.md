## Fonts

backd8 bundles **no font files**. The window uses the faces that Windows itself shipped in the Windows 98 / 2000 era, so the look is authentic and nothing has to be licensed or redistributed:

| Where | Font | Size / weight |
|---|---|---|
| Body text, buttons, labels, lists, tooltips, menus | **Tahoma** (falls back to Microsoft Sans Serif, MS UI Gothic, Segoe UI) | 11 px (= 8 pt), regular and bold |
| Page titles, title bars, "backd8 Setup" banner | **Arial** | bold, 11 / 18 / 27 px |
| Commit message box, commit ids, activity log, technical details | **Lucida Console** (falls back to Consolas, Courier New) | 12 px |
| Window buttons and check marks | **Marlett** (Windows' own symbol font) | - |

All of them are part of Windows and are used under the Windows licence. Text is drawn with `TextFormattingMode=Display`, `TextRenderingMode=Aliased`, `TextHintingMode=Fixed`: the hinted, bi-level, black-on-grey rendering of the original wizard. Chinese, Japanese, Korean, Hebrew, Arabic and emoji fall back to the system fonts glyph by glyph.

Why not a pixel font? An earlier version shipped DotGothic16, VT323 and Silkscreen (all SIL OFL 1.1). Pixel fonts are drawn with one-pixel strokes and only look right at exact whole-number scales; at the 125 % / 150 % display scaling most laptops use they smear, and at 100 % they look thin and spindly next to hinted Tahoma. The hinted system faces stay crisp, darker and narrower from 100 % to 200 %. Body text is kept at 11 px because Tahoma/Microsoft Sans Serif at 12 or 13 px show uneven letter gaps under WPF's hinting.

If you want to bundle a font again, keep it OFL / CC0 / MIT, put the file and its licence text in this folder, and list it here.
