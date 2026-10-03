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
