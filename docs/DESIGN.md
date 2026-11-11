# backd8 design principles

How the window and its pictures are designed. The look is a Windows 98 Setup wizard; the discipline comes from product-illustration craft,
in particular Benji Taylor's [Stageshow skill](https://github.com/benjitaylor/skills/tree/main/stageshow) (restraint, hierarchy, framing and
a ruthless final review). These are our own condensed notes, not a copy of that material - read the original for the full reasoning.

## 1. One idea

**A page reads as a real product, simplified to what the user needs, with one clear thing for the eye to land on, and every state has a
way forward.** The result of the task (the commit, the Publish button, the "GitHub is up to date" message) is the heaviest thing on the page.

Failure modes to look for on every page:

| Failure | What it looks like in backd8 |
|---|---|
| Too much | every row, label and hint spelled out; three paragraphs of help; a toolbar of rarely used buttons |
| Flat | every control in the same bevelled box, nothing leads |
| Dead space | an empty band in the middle of the dialog, a void under a list, a corner nothing lives in |
| Bland | grey rectangles with no recognisable content (a commit list of "Commit 1, Commit 2") |
| Boxed | a whole page shrunk into an even frame instead of using the space for the content that matters |

## 2. Restraint

- Count the real words a page needs (title, what you act on, what you type, the result). Everything else is quiet or gone.
- One number or status is allowed to be big (for example "3 changes waiting"). The rest is plain text.
- Say it once. The same status must not appear in the sidebar, the banner, the status bar and a dialog. Pick the place.
- Placeholder text and sample data must look like real data (real file names, real commit subjects, varied lengths).
- Quiet is not faint: secondary text still meets 4.5:1 on its background (Win98 disabled grey needs the white emboss and a darker ink).
- No invented marks. We use our own pixel icons from one set at one size; never an emoji as an icon, never a lookalike of another logo.

## 3. Hierarchy and density

- Ask of every page: what does the eye land on first, and is it the result/next step? If not, that is the first fix.
- Density follows the story: a first-run page is sparse; the commit editor may be dense. No element quota, but no filler either.
- Heaviest marks on what the story is about: the default button, the selected commit, the sentence that says what will happen.
- Group by whitespace: a title sits closer to its own help text than to the next group. Never spread lines evenly to fill a frame.
- Check at thumbnail size: the sidebar, the dialog and the illustration should still form one picture.

## 4. Spacing and alignment (applies to every page)

- Buttons sit 8-12 px away from the field or edge above; text keeps a 12 px inset from the edge of a panel, group box or list.
- Title over subtitle: 4-6 px of ink between lines; list rows 12 px padding (8 px dense).
- Text never touches a neighbouring box: fixed gaps of 8-12 px, never leftover space-between.
- Edges that are 1-3 px apart read as an accident: align exactly, or separate by at least 8 px.
- Columns share one grid (fixed tracks); a badge or dot lives in its own gutter, 6 px clear of text.
- Nested shapes pad evenly; a control hugs its content (no stretched button with a label at one end).
- A control's text must fit before its box is widened (the clipped "Browse..." button is the cautionary tale).
- Align the reading edge first, then the visible ink; centre labels on their letters, not their line box.

## 5. Icons and imagery

- One family, one pixel grid, one outline weight, one light direction (top-left). Small icons are filled.
- Illustrations earn their place: they depict the page's job (a folder, a notepad, a key, a cloud). Empty states may be grey/neutral art.
- Check imagery at its smallest size and over every surface it sits on.

## 6. Colour and material (Windows 98 palette)

- One neutral family (face #C0C0C0) for the dialog, a different material (black sidebar, teal art panel, blue desktop) only on purpose.
- Status colours mean status (green on GitHub, yellow warning, red error); never decorative.
- Depth comes from bevels (raised / sunken), not translucency; nothing translucent overlaps.
- A control that has keyboard focus gets the dotted focus rectangle; nothing else gets an accent ring "to point at it".

## 7. Framing for pictures (README, store page, docs)

Product shots are composed, not pasted:

1. One hero object and at most one or two satellites (a dialog, a card, a receipt).
2. Crop only filler. Words, buttons and what the story is about stay whole; a list may run off a bled bottom edge.
3. The hero fills at least two thirds of the stage and runs 10-40% off one edge. On a coloured stage (our blue desktop) inset it 8-20% from the sides and let it run off the bottom, so the ground frames it on three sides.
4. A satellite straddles the hero's edge, about half outside, over chrome or margin - never over the content it explains.
5. One gutter, measured in the final crop; every other edge distance matches it. No dead corners.
6. Different objects get different jobs and weights; two satellites differ in size and kind.

## 8. The review (do this before calling a page done)

Look at the page the way the most exacting designer you know would - the one who screenshots the single wrong thing and sends it back with
"what is this?". Typical catches: a dot off its avatar, a unit on its own line, text touching a box, an empty band, a clipped label.
Write findings as a ranked list: framing first, then hierarchy and density, then polish. The bar for a finding is a screenshot.

## 9. Workflow rules that protect the design

- Every page is a state of the workflow model (`workflow.ps1`); a design that needs a screen outside the model is a design bug.
- Every disabled control says why. Every error offers a way forward. No page without Back/Cancel.
- Text comes from `assets/strings.en.psd1`; layout from the page model; the look from the Win98 theme - change them in those places only.
- After changing a page: render it at 100/125/150/200% DPI, in the minimum window size, and with a long path/commit subject.
