// crypt_crew's CLI (unified/src/cli/README.md): unified's public commands, plus this game's own (none yet). Run it
// through the shims, ./uni or uni.cmd; it rebuilds itself when this file changes.
package main

import "unified:cli"

main :: proc() {
	cli.run(cli.public_commands())
}
