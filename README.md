# 3D Multiplayer RPG

Godot 4.4 foundation for a co-op RPG: host/join over LAN or internet, pick a
character, and run around a shared world in first or third person.

> **New here?** Open [`reference/godot-rpg-field-guide.html`](reference/godot-rpg-field-guide.html)
> in a browser. It walks through every scene and script in the project, then
> covers importing your own character models, fixing facing direction, testing
> multiplayer locally, and designing your own maps.

## Running

Open the project in Godot 4.4 and press F5, or from a terminal:

```
Godot_v4.4.1-stable_win64.exe --path .
```

To test multiplayer you need two instances. The quickest way is the
quick-connect flags (everything after `--` is passed to the game):

```
# window 1 - the host
Godot_v4.4.1-stable_win64.exe --path . -- --host --name Host --character knight

# window 2 - a second player
Godot_v4.4.1-stable_win64.exe --path . -- --join 127.0.0.1 --name Friend --character mage
```

Flags: `--host`, `--join <address>`, `--port <n>`, `--name <text>`,
`--character <id>`. Leave `--character` out to stop at the character-select
screen. Add `--headless` to `--host` to run a dedicated server with no window.

Other players on your network join with your LAN IP. Over the internet you need
port **7777/UDP** forwarded to the host machine.

## Controls

| Input | Action |
| --- | --- |
| W A S D / arrows | Move (relative to the camera) |
| Mouse | Look |
| Shift | Sprint |
| Space | Jump |
| **V** | Switch first person / third person |
| Mouse wheel | Zoom the third-person camera |
| Esc | Pause menu, releases the mouse |
| Click | Re-capture the mouse |

In third person the character turns to face the direction it is moving. In first
person it turns with the camera, and the model is hidden from your own view but
still casts its shadow.

## Importing your own characters

Each playable character is a `CharacterData` resource in
`res://resources/characters/`. Anything in that folder is picked up
automatically, so you never have to edit code to add one.

1. Drop your model (`.glb`, `.gltf`, `.fbx`, or a `.tscn`) anywhere under
   `res://models/` and let Godot import it.
2. Duplicate one of the existing `.tres` files, e.g. `01_knight.tres`.
3. Open it in the inspector and set:
   - **Model / model_scene** - your imported scene.
   - **model_scale**, **model_offset** - the character's feet must sit at local
     y = 0 inside the collision capsule (which is 1.8 m tall, 0.4 m radius).
   - **model_yaw_offset_deg** - set to `180` if your model was authored facing
     +Z; Godot's forward is -Z.
   - **head_height** - eye level, used by the first-person camera.
   - **Animation Names** - the clip names exactly as they appear in the model's
     `AnimationPlayer` (idle / walk / run / jump / fall). Leave one blank to skip
     it. Wrong or missing names are ignored rather than erroring.
   - **id** - unique, and don't change it later: it is what travels over the
     network.
4. Restart the game (or just reopen the character-select screen, which rescans
   the folder).

Characters with no `model_scene` fall back to a coloured capsule using
`accent_color`, which is what the three shipped characters do right now.

## Layout

```
scenes/
  main.tscn              root: screen flow + the multiplayer spawner
  player/player.tscn     CharacterBody3D, camera rig, MultiplayerSynchronizer
  maps/arena.tscn        test map
  ui/                    main menu, character select, HUD
scripts/
  main.gd                screen flow, spawning, quick-connect flags
  character_data.gd      the CharacterData resource type
  autoload/game_state.gd character roster + local player's choices
  autoload/network_manager.gd  ENet peer, player roster, handshake
  player/player.gd       movement, camera modes, animation
  maps/arena.gd          procedural test-map geometry
resources/characters/    one .tres per playable character
```

## How the networking fits together

- `NetworkManager` owns the ENet peer and the authoritative roster
  (`peer_id -> {name, character}`). Clients send their name and character id
  once, and the server validates the id against the known roster before
  accepting it.
- `main.gd` reacts to `player_registered` and calls `MultiplayerSpawner.spawn()`.
  The spawn function runs on every peer with the same data, so late joiners get
  every existing player automatically.
- Each `Player` is authoritative on its owning peer: that peer simulates
  movement and publishes `sync_position` / `sync_yaw` / `sync_anim` through its
  `MultiplayerSynchronizer`. Everyone else smooths towards those values instead
  of snapping, and only the owning peer keeps a camera.

## Not built yet

Monsters, bosses, combat, health, multiple maps and portals between them. The
hooks are in place: `CharacterData` already carries `max_health` and
`attack_damage`, the `attack` action is bound to left mouse, physics layer 3 is
reserved for enemies, and any map that implements `get_spawn_point(index)` can
replace the arena.
