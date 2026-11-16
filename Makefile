# Adamachines 3D: tiny cars racing round the house, in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
#   make         build the game
#   make run     build and start it
#   make test    the checks without a window: races on every track, replays
#   make clean

all: game

game:
	gprbuild -p -P adamachines3d.gpr -j0

run: game
	./bin/adamachines3d

test:
	gprbuild -p -P racetest.gpr -j0
	./bin/racetest

clean:
	gprclean -q -P adamachines3d.gpr
	gprclean -q -P racetest.gpr

.PHONY: all game run test clean
