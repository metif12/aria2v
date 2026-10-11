module session

import os

fn scratch(name string) string {
	dir := os.join_path(os.temp_dir(), 'aria2v-session-test')
	os.mkdir_all(dir) or { panic('cannot make the scratch directory: ' + err.msg()) }
	p := os.join_path(dir, name)
	os.rm(p) or {}
	os.rm(p + '.tmp') or {}
	return p
}

fn one(uri string, opts map[string]string) Entry {
	return Entry{
		uri:     uri
		options: opts
	}
}

// ---- the round trip -----------------------------------------------------

// The whole point of the file: what you saved is what you got back.
fn test_entries_survive_a_round_trip() {
	p := scratch('roundtrip.session')
	original := [
		one('https://example.com/a.iso', {
			'dir': 'D:/Downloads/a'
			'out': 'renamed.iso'
		}),
		one('https://example.com/b.iso', {
			'dir': 'D:/Downloads/b'
		}),
	]
	save(p, original) or {
		assert false, err.msg()
		return
	}

	got, skipped := load(p)
	assert skipped == 0, 'a clean file must not report skips: ${skipped}'
	assert got.len == 2, '${got.len}'
	assert got[0].uri == 'https://example.com/a.iso', got[0].uri
	assert got[0].options['out'] == 'renamed.iso', got[0].options['out']
	assert got[1].uri == 'https://example.com/b.iso', got[1].uri
	assert got[1].options['dir'] == 'D:/Downloads/b', got[1].options['dir']
}

// The blank line is the separator. Without it, one download's options become the
// next download's URL, and the queue loads the wrong files.
fn test_the_blank_line_separates_entries() {
	text := 'https://a/f.bin\n dir=D:/x\n\nhttps://b/f.bin\n dir=D:/y\n'
	got, skipped := decode(text)
	assert skipped == 0, '${skipped}'
	assert got.len == 2, '${got.len}'
	assert got[0].uri == 'https://a/f.bin', got[0].uri
	assert got[0].options['dir'] == 'D:/x', got[0].options['dir']
	assert got[1].uri == 'https://b/f.bin', got[1].uri
}

// A file that does not end with a blank line is legal in every version of the
// format, so the last entry is flushed rather than dropped.
fn test_a_last_entry_with_no_trailing_blank_line_is_kept() {
	got, _ := decode('https://a/f.bin\n dir=D:/x\nhttps://b/f.bin')
	assert got.len == 2, '${got.len}'
	assert got[1].uri == 'https://b/f.bin', got[1].uri
}

// ---- corruption, and the one rule that matters ---------------------------

// THE rule: a corrupt line loses one download, not the queue.
//
// A power cut half-writing the file is the normal case. A loader that gave up at
// the first bad line would take every other row with it, which is the opposite of
// what the file is for.
fn test_a_corrupt_line_loses_one_entry_not_the_queue() {
	text := 'https://a/f.bin\n dir=D:/x\n\nnot a url with\n\nhttps://b/f.bin\n dir=D:/y\n'
	got, _ := decode(text)
	// The middle line is treated as a URL, because it is not blank and has no `=`.
	assert got.len == 3, '${got.len}'
	assert got[0].uri == 'https://a/f.bin', got[0].uri
	assert got[2].uri == 'https://b/f.bin', got[2].uri
}

fn test_a_malformed_option_line_is_skipped_and_its_entry_survives() {
	// A key with a space in it cannot be an aria2 option. The entry it belongs to
	// must still load - losing a whole download over one bad option would be a
	// much larger loss than the option is.
	text := 'https://a/f.bin\n not an option=whatever\n dir=D:/x\n'
	got, skipped := decode(text)
	assert got.len == 1, '${got.len}'
	assert got[0].options['dir'] == 'D:/x', got[0].options['dir']
	assert skipped == 1, 'the bad line is still reported: ${skipped}'
}

fn test_a_truncated_file_keeps_what_it_can() {
	// Cut off mid-way through the second entry's options.
	text := 'https://a/f.bin\n dir=D:/x\n dir=D:/y\n out=half'
	got, _ := decode(text)
	assert got.len == 1, '${got.len}'
	assert got[0].uri == 'https://a/f.bin', got[0].uri
	assert got[0].options['out'] == 'half', got[0].options['out']
}

fn test_an_empty_file_is_an_empty_queue() {
	got, skipped := decode('')
	assert got.len == 0, '${got.len}'
	assert skipped == 0, '${skipped}'
}

fn test_blank_lines_everywhere_do_not_create_empty_entries() {
	got, _ := decode('\n\n\nhttps://a/f.bin\n\n\n\n')
	assert got.len == 1, '${got.len}'
}

fn test_a_url_may_not_be_overwritten_by_a_second_one() {
	// Two URLs with no blank line: the second is malformed, and silently dropping
	// the first would lose a download the user had queued.
	got, skipped := decode('https://a/f.bin\nhttps://b/f.bin')
	assert got.len == 2, '${got.len}'
	assert got[0].uri == 'https://a/f.bin', got[0].uri
	assert got[1].uri == 'https://b/f.bin', got[1].uri
	assert skipped == 0, '${skipped}'
}

// ---- keys ---------------------------------------------------------------

fn test_aria2_option_names_are_accepted() {
	// The three that matter are the long and the short and the one with a dot.
	got, _ := decode('https://a/f.bin\n max-connection-per-server=8\n split=4\n bt-max-peers=55\n')
	assert got.len == 1, '${got.len}'
	assert got[0].options['max-connection-per-server'] == '8', got[0].options['max-connection-per-server']
	assert got[0].options['split'] == '4', got[0].options['split']
	assert got[0].options['bt-max-peers'] == '55', got[0].options['bt-max-peers']
}

// ---- the atomic write ----------------------------------------------------

// A rename over the target, so a power cut leaves the file valid or absent. A
// half-written session file loses the queue the file existed to protect.
fn test_saving_leaves_no_temporary_file_behind() {
	p := scratch('atomic.session')
	save(p, [one('https://a/f.bin', {})]) or { assert false, err.msg() }
	assert os.exists(p), 'the document was not written'
	assert !os.exists(p + '.tmp'), 'a temporary file was left behind'
}

// Saving twice replaces rather than appends, and the second save's content is the
// whole content.
fn test_saving_twice_replaces_rather_than_appends() {
	p := scratch('twice.session')
	save(p, [one('https://a/f.bin', {
		'dir': 'D:/first'
	})]) or { assert false, err.msg() }
	save(p, [one('https://b/f.bin', {
		'dir': 'D:/second'
	})]) or { assert false, err.msg() }
	got, _ := load(p)
	assert got.len == 1, 'a second save must replace the first, got ${got.len}'
	assert got[0].uri == 'https://b/f.bin', got[0].uri
	assert got[0].options['dir'] == 'D:/second', got[0].options['dir']
}

// Saving into a directory that does not exist is the first-run case.
fn test_saving_creates_the_directory_it_needs() {
	p := os.join_path(os.temp_dir(), 'aria2v-session-test', 'nested', 'deeper', 'x.session')
	os.rm(os.dir(p)) or {}
	save(p, [one('https://a/f.bin', {})]) or { assert false, err.msg() }
	assert os.exists(p), 'the directory was not created'
}

fn test_a_missing_file_is_an_empty_queue_not_an_error() {
	got, skipped := load(os.join_path(os.temp_dir(), 'aria2v-session-test', 'absent.session'))
	assert got.len == 0, '${got.len}'
	assert skipped == 0, '${skipped}'
}

// The order of options is stable, so two saves of the same entry produce the same
// bytes. A map iteration order that changed per run would make every diff of the
// file noise.
fn test_the_encoding_is_stable() {
	a := encode([one('https://a/f.bin', {
		'dir':   'D:/x'
		'out':   'f.bin'
		'split': '4'
	})])
	b := encode([one('https://a/f.bin', {
		'dir':   'D:/x'
		'out':   'f.bin'
		'split': '4'
	})])
	assert a == b, 'the encoding differs between two identical entries:'
}
