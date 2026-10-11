// main.v - the aria2v CLI.
//
// Phase 0 of this repo is a working tool for the parts that exist: plan a
// download, and round-trip the session file. The engine itself is the next
// commit, which is why this does not fetch anything.
//
//   aria2v plan <url> <bytes> [connections] [min-segment-bytes]
//   aria2v session <path>
//
// Every subcommand is a thin call into internal/, which is where the logic lives.
// The CLI's job is argument handling and printing, and nothing else - a CLI that
// also holds logic is a CLI that cannot be tested by vlib's test runner.
module main

import os
import aria2v.internal.link
import aria2v.internal.plan
import aria2v.internal.session

fn usage() {
	print('aria2v - a download engine in pure V

  aria2v plan <url> <bytes> [connections] [min-segment]
      Print the byte ranges a download of <bytes> would fetch. The point is the
      arithmetic: even segments, remainder on the first, nothing past the end.

  aria2v session <path>
      Read a session file and print what came back, and how many lines were lost
      to corruption. The loss count is the interesting half.

  aria2v suggest <url>
      Print the folder a URL implies.

')
}

fn main() {
	args := os.args
	if args.len < 2 {
		usage()
		exit(1)
	}
	match args[1] {
		'plan' { cmd_plan(args[2..]) }
		'session' { cmd_session(args[2..]) }
		'suggest' { cmd_suggest(args[2..]) }
		else { usage() }
	}
}

fn cmd_plan(args []string) {
	if args.len < 2 {
		eprintln('plan needs a url and a byte count')
		exit(1)
	}
	url := args[0]
	length := args[1].i64()
	connections := if args.len > 2 { args[2].int() } else { 4 }
	min_segment := if args.len > 3 { args[3].i64() } else { 0 }

	l := link.parse(url) or {
		eprintln('aria2v: ${err.msg()}')
		exit(1)
	}
	println('url:      ${l.raw}')
	println('name:     ${link.safe_name(l.name)}')
	if l.folder != '' {
		println('folder:   ${l.folder} (suggested)')
	}

	for done in [i64(0), length / 2] {
		segs := plan.resume_plan(length, connections, min_segment, done)
		if segs.len == 0 {
			continue
		}
		println('\n${if done == 0 { 'fresh' } else { 'resuming from ' + done.str() + ' bytes' }}: ' +
			'${plan.total_len(segs)} bytes in ${segs.len} segment(s)')
		for s in segs {
			println('  [${s.index}] rows ${s.first}-${s.last}  ${s.len()} bytes  ${s.range_header()}')
		}
	}
}

fn cmd_session(args []string) {
	if args.len < 1 {
		eprintln('session needs a path')
		exit(1)
	}
	entries, skipped := session.load(args[0])
	println('${entries.len} download(s) came back')
	if skipped > 0 {
		// The number that makes a corrupt file trustworthy instead of scary: a
		// report of what was lost, rather than silence that hides it.
		println('${skipped} line(s) were lost to corruption')
	}
	for e in entries {
		println('  ${e.uri}')
	}
}

fn cmd_suggest(args []string) {
	if args.len < 1 {
		eprintln('suggest needs a url')
		exit(1)
	}
	s := link.suggest(args[0])
	println(if s == '' { 'nothing to suggest from that address' } else { s })
}
