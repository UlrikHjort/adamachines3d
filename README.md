# Adamachines 3D

[![Build and test](https://github.com/UlrikHjort/adamachines3d/actions/workflows/ci.yml/badge.svg)](https://github.com/UlrikHjort/adamachines3d/actions/workflows/ci.yml)

Tiny cars, boats, planes, bikes, tanks and more racing round the house, now in 3D. A 3D
version of [Adamachines](https://github.com/UlrikHjort/adamachines), in Ada with GtkAda and
OpenGL 3.3. The races run on the same game logic as the 2D game, so the 29 tracks, the
vehicles, the pick-ups and the network play are the same. You see them from behind the car,
from its bumper, from the driver's seat, or from high above as in the 2D game.

![Backyard Motocross, over the hills and into the tunnel](docs/gifs/motocross.gif)

| | |
|---|---|
| ![Workbench Run](docs/gifs/workbench.gif) | ![Cloud Nine](docs/gifs/sky.gif) |
| Workbench Run: round the bench, the room behind | Cloud Nine: biplanes banking over the clouds |

![The title](docs/screenshots/title.jpg)

| | |
|---|---|
| ![Workbench Run](docs/screenshots/workbench.jpg) | ![Kitchen GP](docs/screenshots/kitchen.jpg) |
| Workbench Run: racer, beetle, van and sports car | Kitchen GP from the saddle, under the table |
| ![Backyard Motocross](docs/screenshots/motocross.jpg) | ![Chess Board](docs/screenshots/chess.jpg) |
| Backyard Motocross: hills, banked bends, a tunnel | Chess Board from high above |
| ![Garden Path at sunset](docs/screenshots/garden-sunset.jpg) | ![Garden Path in the rain](docs/screenshots/garden-rain.jpg) |
| Garden Path at sunset | Garden Path in the rain |
| ![Arctic Safari in the snow](docs/screenshots/arctic-snow.jpg) | ![Toy Train Town at night](docs/screenshots/toytown-night.jpg) |
| Arctic Safari in the snow | Toy Train Town at night: only the headlights |
| ![Cloud Nine](docs/screenshots/sky.jpg) | ![Attic at Night](docs/screenshots/attic.jpg) |
| Cloud Nine | Attic at Night |
| ![Fish Tank](docs/screenshots/fishtank.jpg) | ![Moon Base](docs/screenshots/moon.jpg) |
| Fish Tank: submarines behind the glass | Moon Base: stars, and a tunnel through the dust |
| ![Bubble Bath](docs/screenshots/bath.jpg) | ![Birthday Party](docs/screenshots/party.jpg) |
| Bubble Bath: boats in the tub | Birthday Party: the cake and its candles |
| ![Two players](docs/screenshots/split.jpg) | ![A duel](docs/screenshots/duel.jpg) |
| Two players, a screen each | A duel on one screen |
| ![A replay](docs/screenshots/replay.jpg) | ![The standings](docs/screenshots/standings.jpg) |
| The replay, from beside the track | A championship's standings |
| ![The track editor](docs/screenshots/editor.jpg) | ![The options](docs/screenshots/options.jpg) |
| The track editor | The options |

> **Built with AI.** Written by [Claude](https://www.anthropic.com/claude) Opus 5.5 in Claude
> Code from the author's prompts.

## Getting started

    make run

That needs GNAT, gprbuild, GtkAda, libepoxy and PulseAudio. On Debian, Ubuntu and Mint:

    sudo apt install gnat gprbuild libgtkada20-dev libgtk-3-dev libepoxy-dev libpulse-dev

For the announcer, install `espeak-ng` too. `make test` races the AI round every track
without a window, and checks that a race run again from what was pressed ends exactly as
it did (the replays depend on it).

## Ways to play

- **Race**: one player against up to five AI drivers, or two players on a split screen.
- **Championship**: the eight cups of the 2D game, points for every place, standings after each race.
- **Time trial**: alone against the clock and a ghost of your best lap.
- **Duel**: two players on one shared screen. Leave the other off it and take one of their lights.
- **Network game**: up to eight players over the network (UDP port 27272), with AI drivers in
  the empty places. It plays together with the 2D game.
- **Track editor**: build a track from above and drive it in 3D. The tracks are shared with the
  2D game.

Every race can be watched again: **W** on the results shows the replay, from cameras beside the
track or any other, following any car.

Choose the **time of day** (day, sunset, night) and the **weather** (clear, rain, snow) on the
title. Out of doors the land rolls in hills, the road is banked in its tight bends, and some
tracks run through a tunnel.

In the **options**: each player's car (racer, beetle, van or sports car) and colour, the
volumes, the announcer, the shadows, and which controller each player uses.

## Controls

| | Player 1 | Player 2 |
|---|---|---|
| Drive, brake, steer | arrows | W A S D |
| Use the pick-up | right Ctrl, right Shift, Enter | left Ctrl, left Shift, Space, Q |
| Camera (behind, bumper, cockpit, high) | C | V |

Esc or P pauses, M mutes, F3 shows the frame rate, F11 goes full screen.

Game controllers work too: an Xbox-style pad, a racing wheel (Logitech G29 and the like) or a
joystick. Press a button on one to take it, or choose it in the options. Pads rumble, and a
wheel pulls back to the middle harder the faster you go.

Lap records and ghosts are kept in `~/.adamachines3d`. The choices made in the menus are
kept in `~/.adamachines3drc`.
