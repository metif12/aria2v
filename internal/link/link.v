// link.v - what an address means, and what to call the file it produces.
//
// This is pure text work, which is why it is here rather than beside the socket:
// every function in this file is testable against a string, and the two bugs it
// prevents are both classic.
//
// The "suggest a folder from the URL" logic Fluxget's add dialog does is lifted
// from here, so the engine and the UI agree on what a URL implies. Two
// implementations of "the second-to-last segment" is two answers.
module link

// Kind is what an address IS, and it decides how it is added: a magnet is its own
// protocol, a .torrent path is bytes handed to the engine, a URL is HTTP.
pub enum Kind {
	url
	magnet
	file
}

// Link is a normalised address and what we could derive from it.
pub struct Link {
pub mut:
	raw  string
	kind Kind
	host string
	path string
	// name is the file name, derived from the last path segment. It is the
	// `--out` aria2 would use, and it is what a queue row shows.
	name string
	// folder is the second-to-last segment, offered as a suggestion and never
	// applied on its own.
	folder string
}

// parse turns an address into a Link.
//
// A magnet has no path, and a file path has no host, and both are legitimate -
// they just cannot have a name derived the way a URL's is. The magnet case is
// where this earns its keep: `magnet:?xt=urn:btih:<hash>` has the download's name
// embedded in the `dn=` parameter, and a client that ignores it names the
// download by its hash, which is what every badly-behaved magnet link looks like.
pub fn parse(raw string) !Link {
	trimmed := raw.trim_space()
	if trimmed == '' {
		return error('link: empty')
	}
	if trimmed.to_lower().starts_with('magnet:') {
		return Link{
			raw:    trimmed
			kind:   .magnet
			host:   ''
			path:   ''
			name:   magnet_name(trimmed)
			folder: ''
		}
	}
	if trimmed.to_lower().ends_with('.torrent') {
		return Link{
			raw:    trimmed
			kind:   .file
			host:   ''
			path:   trimmed.replace('\\', '/')
			name:   base_name(trimmed)
			folder: ''
		}
	}
	if !trimmed.to_lower().starts_with('http://') && !trimmed.to_lower().starts_with('https://') {
		return error('link: not a scheme Fluxget can fetch: ${trimmed}')
	}

	// Everything between the scheme and the first slash is the host.
	after_scheme := trimmed.index('://') or {
		return error('link: no scheme separator in ${trimmed}')
	}
	rest := trimmed[after_scheme + 3..]
	mut host := rest
	mut path := '/'
	slash := rest.index('/') or { -1 }
	if slash >= 0 {
		host = rest[..slash]
		path = rest[slash..]
	}
	// A query string is not part of the file name. `https://x/file.bin?token=abc`
	// downloads as `file.bin`, and a client that keeps the query names the file
	// `file.bin?token=abc` and puts a question mark in a filename on Windows.
	q := path.index('?') or { -1 }
	if q >= 0 {
		path = path[..q]
	}
	// A fragment is likewise not part of the name.
	h := path.index('#') or { -1 }
	if h >= 0 {
		path = path[..h]
	}

	mut folder := ''
	mut name := ''
	clean := path.trim_string_left('/')
	segs := clean.split('/')
	if segs.len >= 2 {
		folder = segs[segs.len - 2]
		name = segs[segs.len - 1]
	} else if segs.len == 1 {
		name = segs[0]
	}
	// A trailing slash is a directory listing, and a file name cannot be empty.
	if name == '' {
		name = host
	}

	return Link{
		raw:    trimmed
		kind:   .url
		host:   host
		path:   path
		name:   name
		folder: folder
	}
}

// magnet_name pulls the display name out of `dn=`.
//
// Percent-decoded, because a magnet's `dn` value is URL-encoded by necessity -
// it lives in a query string. A client that skips this shows `Arch%20Linux` with
// a percent sign in the middle of the word.
pub fn magnet_name(raw string) string {
	q := raw.index('?') or { -1 }
	if q < 0 {
		return ''
	}
	for pair in raw[q + 1..].split('&') {
		parts := pair.split('=')
		if parts.len != 2 {
			continue
		}
		if parts[0] != 'dn' {
			continue
		}
		return percent_decode(parts[1])
	}
	return ''
}

// percent_decode reverses the encoding a query parameter applies to a display
// name.
//
// A V `String.split('=')` will happily give a value that was never encoded, so
// this is defensive rather than assuming well-formed input.
// percent_decode reverses the encoding a query parameter applies to a display
// name.
//
// It handles BOTH encodings a magnet's `dn=` can use, because magnet links are
// written by hand by humans who learned the convention from forms:
//
//   * `%20` — the percent-escape every spec means;
//   * `+`    — the form-encoding for a space, which appears in a great many
//              magnet links and which a client that ignores it renders as
//              "Arch+Linux".
//
// A `+` inside a filename is not invalid, so the bug is silent: the download
// works, it is just named wrong, and nobody files it.
pub fn percent_decode(s string) string {
	mut out := []u8{}
	mut i := 0
	for i < s.len {
		c := s[i]
		if c == `+` {
			out << ` `
			i++
			continue
		}
		if c == `%` && i + 2 < s.len {
			hex := s[i + 1..i + 3]
			val := hex_to_int(hex) or {
				// Not a valid escape, so the percent sign is literal. Replacing it
				// with a space, or dropping the pair, would both be a guess.
				out << c
				i++
				continue
			}
			out << u8(val)
			i += 3
			continue
		}
		out << c
		i++
	}
	return out.bytestr()
}

// hex_to_int parses two hex digits, and returns none if it was given anything
// else. A V `?int` and not an error, because a malformed escape is not a failure
// of the download - it is a name that keeps its percent sign.
fn hex_to_int(s string) ?int {
	if s.len != 2 {
		return none
	}
	mut nail := 0
	for c in s {
		d := match c {
			`0`...`9` { int(c - `0`) }
			`a`...`f` { int(c - `a` + 10) }
			`A`...`F` { int(c - `A` + 10) }
			else { return none }
		}
		nail = nail * 16 + d
	}
	return nail
}

// base_name is the last segment of a path, on either separator.
//
// `replace(a, b)` in V replaces EVERY occurrence, which is what this wants; the
// `_all` suffix that most languages use does not exist in 0.5.2.
pub fn base_name(path string) string {
	trimmed := trim_trailing_slashes(path.replace('\\', '/'))
	segs := trimmed.split('/')
	if segs.len == 0 {
		return trimmed
	}
	return segs[segs.len - 1]
}

// trim_trailing_slashes removes trailing separators, so a path ending in `/`
// still has a last segment. V 0.5.2 has no trim_string_right on a cutset.
fn trim_trailing_slashes(s string) string {
	mut end := s.len
	for end > 0 && s[end - 1] == `/` {
		end--
	}
	return s[..end]
}

// safe_name removes what a filesystem refuses.
//
// Windows has the largest set of characters to remove and also the reserved
// device names, which is why this is here and not left to the OS: a filename
// containing `:` is a rejected download on Windows and needs no work on Linux,
// and a download manager that names a file `aux` gets a file it cannot open.
pub fn safe_name(raw string) string {
	mut out := []string{}
	for c in raw {
		if c == `:` || c == `*` || c == `?` || c == `"` || c == `<` || c == `>` || c == `|`
			|| c == `/` || c == `\\` {
			continue
		}
		if c < 0x20 {
			continue
		}
		out << c.ascii_str()
	}
	name := out.join('').trim_space()
	// A name that is entirely separators would become empty; keep the download
	// rather than dropping it.
	if name == '' {
		return 'download'
	}
	return reserved_name(name)
}

fn reserved_name(name string) string {
	lower := name.to_lower()
	dot := lower.index('.') or { -1 }
	stem := if dot >= 0 { lower[..dot] } else { lower }
	for reserved in ['con', 'prn', 'aux', 'nul', 'com1', 'com2', 'com3', 'com4', 'lpt1', 'lpt2',
		'lpt3'] {
		if stem == reserved {
			return '_' + name
		}
	}
	return name
}

// suggest is the folder a URL implies, as a suggestion.
//
// It is the one Fluxget's add dialog shows, and it is deliberately shallow: the
// last segment is the file, the one before it is what the file came from, and a
// guess that reaches further than that is a guess the user has to undo.
pub fn suggest(raw string) string {
	l := parse(raw) or { return '' }
	return l.folder
}
