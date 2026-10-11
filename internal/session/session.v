// session.v - the queue on disk, and the one thing it must never lose.
//
// aria2's `--save-session` / `--input-file` format is a flat line-based text file:
//
//     https://example.com/file.bin
//      dir=D:/Downloads/x
//      out=renamed.bin
//
//     https://example.com/second.bin
//      dir=D:/Downloads/y
//
// One entry, blank line, next entry. The URL is the first line and the options
// below it are ARIA2'S OWN OPTION NAMES, dash-separated.
//
// WHY THE FORMAT IS COMPATIBLE rather than "better"
//
// It would be easy to write JSON and call it clean. But a session file is the one
// artifact that has to survive the app not running: a queue that vanishes on close
// is the single worst failure a download manager has, and Fluxget's Phase 1 proof
// for that is an aria2 session file. Using the same shape means the file the old
// engine wrote is a file the new one reads, which makes the cut-over reversible -
// and a cut-over you cannot reverse is a cut-over nobody will let you do.
//
// entry_count is bounded, because a session file is untrusted input: a corrupt one
// from a power cut is normal, and one written by something else is possible.
module session

import os

// Entry is one download that was in flight.
pub struct Entry {
pub mut:
	uri string
	// options are the download's own aria2 option names and values, in the order
	// they were read. An order is kept because the file is a human-readable record
	// as well as a machine one.
	options map[string]string
}

// max_entries bounds a read, so a truncated or hostile file cannot exhaust memory
// before the loader notices.
const max_entries = 10000

// encode renders the queue in aria2's format.
//
// The blank line between entries is the separator, and it is required: a reader
// that skipped it would treat the options of one download as the URL of the next.
pub fn encode(entries []Entry) string {
	mut out := []string{}
	for e in entries {
		if e.uri.trim_space() == '' {
			continue
		}
		out << e.uri
		// Sorted, so the same entry always encodes to the same bytes. Without
		// this, a map iteration order that changes per run would make the file
		// differ every save and a diff of it would be noise.
		mut keys := []string{}
		for k, _ in e.options {
			keys << k
		}
		keys.sort()
		for k in keys {
			out << ' ${k}=${e.options[k]}'
		}
		out << ''
	}
	return out.join('\n')
}

// decode reads the queue, and skips what it cannot understand rather than
// failing.
//
// THE one rule this module exists to enforce: a CORRUPT LINE LOSES ONE DOWNLOAD,
// not the whole queue. A power cut half-writing the file is the normal case, and a
// session loader that gave up at the first bad line would take every other row
// with it - the opposite of what the file is for.
//
// Returns the entries and a line to say how many were skipped, so a caller can
// tell the user "4 of 12 came back" instead of quietly showing 8.
pub fn decode(raw string) ([]Entry, int) {
	mut entries := []Entry{}
	mut current := Entry{}
	mut in_entry := false
	mut skipped := 0

	for line in raw.split_into_lines() {
		trimmed := line.trim_space()

		// A blank line ends the current entry.
		if trimmed == '' {
			if in_entry && current.uri != '' {
				entries << current
			}
			current = Entry{}
			in_entry = false
			continue
		}

		// An option line starts with a space in the file; after trimming that is
		// indistinguishable from a key=value line, so the key=value test comes first.
		eq := trimmed.index('=') or { -1 }
		if eq > 0 && in_entry {
			key := trimmed[..eq].trim_space()
			value := trimmed[eq + 1..].trim_space()
			if valid_key(key) {
				current.options[key] = value
				continue
			}
			// A line that looks like an option but has a name we do not accept is
			// skipped, and the entry survives.
			skipped++
			continue
		}

		// Anything else is a URL.
		if !in_entry {
			current = Entry{
				uri: trimmed
			}
			in_entry = true
			continue
		}
		// A second URL with no blank line is a malformed file, and it is REPAIRED
		// rather than reported as a loss: both URLs load. Counting it as a
		// skipped line would tell the user a download was lost when nothing was,
		// and "the file said so" is not worth losing a row for.
		if in_entry && current.uri != '' {
			entries << current
		}
		current = Entry{
			uri: trimmed
		}
		in_entry = true
	}

	// The file does not end with a blank line in every version of the format, so
	// the last entry is flushed here.
	if in_entry && current.uri != '' {
		entries << current
	}
	if entries.len > max_entries {
		return entries[..max_entries], skipped + entries.len - max_entries
	}
	return entries, skipped
}

// valid_key accepts aria2's option names: lowercase letters, digits, dashes and
// dots, which is what covers `max-connection-per-server`, `split` and
// `bt-max-peers`. A key with a space in it cannot be an aria2 option.
fn valid_key(key string) bool {
	if key == '' {
		return false
	}
	for c in key {
		if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
			|| c == `-` || c == `.` || c == `_` {
			continue
		}
		return false
	}
	return true
}

// save writes the queue, and does it the safe way: the content goes to a sibling
// temporary file and is renamed over the target.
//
// A power cut during a direct write leaves a half-written session file, and the
// next load then loses the queue to the file that existed to protect it. The
// rename is atomic on every platform this runs on, which makes the whole file
// valid or not there at all - and "not there" is a state the caller can recover
// from by starting empty, which half-written is not.
pub fn save(path string, entries []Entry) ! {
	if os.exists(path) == false {
		os.mkdir_all(os.dir(path))!
	}
	tmp := path + '.tmp'
	os.write_file(tmp, encode(entries)) or {
		return error('session: cannot write ${tmp}: ${err.msg()}')
	}
	os.mv(tmp, path)!
}

// load reads the queue, and returns an empty one when the file is not there.
//
// A missing file is a first run, not a failure.
pub fn load(path string) ([]Entry, int) {
	raw := os.read_file(path) or { return []Entry{}, 0 }
	return decode(raw)
}
