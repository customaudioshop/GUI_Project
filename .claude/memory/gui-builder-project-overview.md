---
name: gui-builder-project-overview
description: "GUI Builder/Player project goals, platforms, device-control use case, and who writes which code"
metadata:
  node_type: memory
  type: project
  originSessionId: 2931ff71-569e-44f4-b64b-eb72c54213d5
  modified: 2026-10-03T13:39:25.580Z
---

Two Godot 4.7 projects under /Volumes/WD/develope/GUI_Project:
- gui-builder: GUI authoring tool, PC + Mac only.
- gui-player: loads packages (layout, functions, images) made by the builder and runs them; PC, Mac, Android, iOS.

Use case: control UIs for devices (DMX lighting, audio mixers) over UART, TCP/IP, DMX, MIDI, GPIO, IR receive/blast.

Code ownership (decided 2026-10-03):
- The developer (user) writes in C# and GDScript; C# is for the developer's own code only.
- End users of the builder never write C#. They only add simple commands, so plan a small command language (DSL) interpreted by the player.
- Most functions are built into the player by the developer.

Open: how packages are delivered to the player (local file / server / bundled) is undecided.

**Why:** These decisions shape the package format and the iOS-safe design (no downloaded executable code).
**How to apply:** Never expose C# scripting to end users; route user logic through the DSL. See [[always-answer-korean]].
