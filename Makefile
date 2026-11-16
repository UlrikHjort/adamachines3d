# Adamachines 3D: tiny cars racing round the house, in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
#   make         build the game
#   make run     build and start it
#   make clean

all: game

game:
	gprbuild -p -P adamachines3d.gpr -j0

run: game
	./bin/adamachines3d

clean:
	gprclean -q -P adamachines3d.gpr

.PHONY: all game run clean
