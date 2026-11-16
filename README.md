# Adamachines 3D

Tiny cars, boats, planes, bikes, tanks and more racing round the house, now in 3D. A 3D
version of [Adamachines](../adamachines), in Ada with GtkAda and OpenGL 3.3. The races run
on the same game logic as the 2D game, so the tracks, the cars and the network play are the same.

## Getting started

    make run

That needs GNAT, gprbuild, GtkAda, libepoxy and PulseAudio. On Debian, Ubuntu and Mint:

    sudo apt install gnat gprbuild libgtkada20-dev libgtk-3-dev libepoxy-dev libpulse-dev

## Ways to play

- **Race**: one player against up to five AI drivers, or two players on a split screen.
- **Championship**: the eight cups of the 2D game, points for every place, standings after each race.
- **Time trial**: alone against the clock and a ghost of your best lap.
- **Duel**: two players on one shared screen. Leave the other off it and take one of their lights.
- **Network game**: up to eight players over the network, with AI drivers in the empty places.
  It plays together with the 2D game.
- **Track editor**: build a track from above and drive it in 3D. The tracks are shared with the 2D game.

## Controls

| | Player 1 | Player 2 |
|---|---|---|
| Drive, brake, steer | arrows | W A S D |
| Use the pick-up | right Ctrl, right Shift, Enter | left Ctrl, left Shift, Space, Q |
| Camera (behind, bumper, cockpit, high) | C | V |

Esc or P pauses, M mutes, F3 shows the frame rate, F11 goes full screen.

Game controllers work too: an Xbox-style pad, a racing wheel (Logitech G29 and the like) or a
joystick. Press a button on one to take it. Pads rumble, and a wheel pulls back to the middle
harder the faster you go.

Lap records and ghosts are kept in `~/.adamachines3d`. The choices made in the menus are
kept in `~/.adamachines3drc`.

> **Built with AI.** Written by [Claude](https://www.anthropic.com/claude) Opus 5.5 in Claude
> Code from the author's prompts.
