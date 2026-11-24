package main

import "unified:headless/modes"

import g "../crypt_crew"

main :: proc() {
	// No standard benchmark yet (`uni bench` runs only the game's sessions): once the game has a population worth
	// timing, give GAME its `benches = {{...}}`, with a Game.bench_prepare that builds it (unified/src/headless/README.md).
	modes.run(&g.GAME)
}
