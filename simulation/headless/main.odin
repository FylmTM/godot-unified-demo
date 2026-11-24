package main

import "unified:headless/modes"

import g "../crypt_crew"

main :: proc() {
	// No standard benchmark yet (`uni bench` runs only the game's sessions): the bench row (four heroes, a held surge,
	// the floor's props) comes with the skeletons (docs/plan.md, Milestone 2: the design).
	modes.run(&g.GAME)
}
