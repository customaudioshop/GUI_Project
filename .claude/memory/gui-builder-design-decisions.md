---
name: gui-builder-design-decisions
description: "Accepted GUI Builder design (2026-10-04): base resolution + fit, value-per-widget, receive rules, echo prevention, motion = fader/encoder behavior"
metadata:
  type: project
---

User accepted all of these on 2026-10-04; spec is docs/Package-format.md.

- Workflow: set target (base) resolution first → drag/drop widgets → adjust layout → motion settings → trigger scripts → receive rules.
- Base resolution + `fit` (keep/expand) rather than one fixed resolution; tablets differ in aspect ratio. Changing base resolution rescales widgets.
- Every widget holds one value; sending = event → GuiScript with `$value`; receiving = declarative rules (pattern → widget value), not scripts.
- Echo prevention is mandatory: received values never fire `change`; values arriving while the user touches a widget are deferred.
- Devices are defined once in a device panel; widgets refer to them by name.
- "Moving function" in the user's plan means fader/encoder motion behavior (touch mode, sensitivity, endless, acceleration), not editor drag.
- Undo/redo built in from the start; Builder preview uses the shared Player renderer.

**Why:** Agreed design direction; later work should not re-litigate it.
**How to apply:** Build in the order: package format → shared renderer → builder canvas → send → devices + receive. See [[gui-builder-project-overview]].

Added 2026-10-04: hierarchy via `group` widgets (children relative to group, `params` like {"ch":1} readable as $ch in child scripts); Duplicate renumbers ids (ch1→ch2) and bumps numeric params, so channel strips share scripts. Work style the user asked for: rough frame first across the whole app, details second.

Added 2026-10-04: phones and foldables supported via multiple `layouts` per package (each with its own screen + pages, devices shared). Same widget id = same control across layouts; Player picks the layout closest in aspect ratio and re-picks on resize (fold/unfold, rotation), keeping values and page.

Added 2026-10-04: LEGO-style cell grid. Widgets/components sized in cells (1x1, 1x2, 2x2…), no overlap. "Tetris" is only a metaphor: user places blocks where they want, snugly (option B), no gravity/auto-fall. Target look = client-customized AV control panels (titled panels, button grids, exclusive source-select groups, level meters, header with title/clock), so per-client styling/skins matter.
The AV panel images were only samples: the user wants a comprehensive, domain-neutral GUI Builder (any device UI, not just screen/projector/volume). Keep widgets generic; device meaning lives in scripts/receive rules; make widget types easy to add and let users build/save reusable components.
Correction (2026-10-04): in this field, domain controls like projector, volume fader and rotary encoder ARE generic widgets to the user. Ship them as built-in standard widgets (alongside primitives like button/label), not as things users must assemble.
Decided (2026-10-04): option B — standard widgets bind to built-in device profiles (e.g. PJLink, vendor RS-232 tables). The user picks a device and commands + feedback fill in automatically; devices without a profile fall back to hand-written GuiScript. Profiles are developer-authored data shipped in the player.
Added 2026-10-04: multi-part widgets. The user needs a dual concentric encoder/pot (outer ring + inner knob, e.g. outer = frequency, inner = gain), so "one value per widget" became "one value per part": parts (outer/inner) each keep value/motion/on/receive, and events go out as "<id>.<part>". Buttons are offered at 1x1 and 2x1 in the palette.
