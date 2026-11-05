# assets/

Art files the game loads at runtime. Almost everything you see in the game is built in code from simple meshes (the
world, the 3D figure, weapons, dummies, trees, fruit, worms, birds and all effects), so this folder is small.

| Folder | What is in it | Used by |
|---|---|---|
| [pip/](pip/README.md) | Pip's pixel-art sprite sheets (character and weapons), each a PNG with a JSON file describing the animations | `scripts/avatar.gd` |

There are no sound files yet. (`scripts/ecology.gd` already sends `sound` events, for example `fruitDrop`, but
nothing plays them.)

Back to the [project README](../README.md).

## Adding assets

- Put each group in its own subfolder with a README like [pip/README.md](pip/README.md).
- Godot creates a `.import` file next to every image or sound when the editor opens the project. Commit it with the
  file; it records how Godot converts the file and gives it a stable ID.
- Load assets by `res://` path (as `Avatar.SHEETS` does). Everything in the project except `tools/` is packed into the
  game and the update pack, so new assets reach players with the next release.
