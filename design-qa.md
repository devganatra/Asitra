# Design QA — task matrix and board

- source visual truth: `/Users/devganatra/Documents/AppleMobileApp/design-qa/option3-today.png`
- implementation screenshot: `/Users/devganatra/Documents/AppleMobileApp/design-qa/tasks-desktop-final.png`
- responsive matrix screenshot: `/Users/devganatra/Documents/AppleMobileApp/design-qa/tasks-mobile-final.png`
- responsive board screenshot: `/Users/devganatra/Documents/AppleMobileApp/design-qa/tasks-board-mobile-final.png`
- source pixels: 1440 × 1024
- desktop implementation pixels and CSS viewport: 1440 × 1000 at device scale factor 1
- mobile implementation pixels and CSS viewport: 390 × 844 at device scale factor 1
- density normalization: source and implementation were both compared at 1×; no resampling was required
- state: authenticated account with one important and urgent Heidelberg task, a renamed custom column, and release 0.2.0-beta.3

## Full-view comparison evidence

The existing Today dashboard and the browser-rendered Tasks page were opened together in one comparison input. The Tasks page preserves the source visual system: the same evergreen navigation, warm canvas, restrained sage palette, Georgia display hierarchy, Geist UI type, thin borders, rounded surfaces, icon weight, sparse density, account toolbar, release trace and floating assistant. The new task inbox, matrix and board read as part of the same Asitra environment rather than a separate product.

The task screen is intentionally a different product state from the Today reference. Its content architecture changes to a capture strip and planning views, while the shell, typography, spacing rhythm, color tokens and control language remain aligned.

## Required fidelity surfaces

- fonts and typography: display headings use the same serif family and optical weight as the source; labels, counts and controls retain the existing compact sans hierarchy and readable wrapping on phone widths
- spacing and layout rhythm: desktop follows the source's fixed 248 px navigation and generous content margins; matrix gutters, card padding, radii and elevation match the established surface rhythm; phone layout stacks without document overflow
- colors and visual tokens: evergreen, moss, warm canvas, sage, blue and warm quadrant tones are muted and accessible; semantic important and urgent tags remain distinguishable without overpowering the screen
- image and asset quality: no source imagery was required; existing Lucide icons remain crisp vectors and no placeholder or handcrafted image approximations were introduced
- copy and content: language is personal and action-oriented (“Put everything down first”, “Do now”, “Plan”, “Simplify”, “Later”) without exposing implementation terminology to the user

## Focused region comparison evidence

The sidebar, top toolbar, task inbox and task-card controls were checked at native pixel dimensions. They retain the source's icon sizing, control heights, border treatment and typography. Separate mobile captures were required because the board intentionally scrolls inside its own container; the document itself remains fixed to 390 px.

## Primary interactions tested

- dumped a new task and tagged it Important and Urgent
- confirmed the task appeared in the “Do now” matrix quadrant
- switched to the board and moved the task from To do to In progress
- added a custom Waiting column and renamed it Awaiting
- completed the task and confirmed it moved automatically to Done; reopened it and confirmed it returned to To do
- confirmed the same record remained visible in Lists
- checked matrix and board at 1440 × 1000 and 390 × 844
- checked browser console warnings and errors: none

## Comparison history

1. First desktop comparison found a P1 semantic mismatch: horizontal and vertical axis labels were reversed relative to the quadrant positions. The label order was corrected. The revised capture shows Urgent above Do now/Simplify, Not urgent above Plan/Later, Important on the upper row and Not important on the lower row.
2. First phone-board pass found a P2 four-pixel document overflow caused by a negative board margin. The negative margin was removed. Post-fix evidence reports `documentScrollWidth: 390` at `innerWidth: 390`, while the board retains its intended internal horizontal scroll (`boardClientWidth: 362`, `boardScrollWidth: 1120`).
3. The browser's stitched full-page phone capture visually distorted fixed and sticky elements; native viewport screenshots and DOM geometry showed the rendered layout itself was correct. Viewport captures were used as the valid comparison evidence.

## Findings

No actionable P0, P1 or P2 findings remain. The persistent focus/active outline seen during automated interaction is an intentional accessible state and does not affect the neutral layout.

final result: passed
