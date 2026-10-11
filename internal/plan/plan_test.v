module plan

// The plan's one property, asserted in every test: the segments cover the file
// exactly once, with no gap and no overlap.

fn assert_covers_exactly(segs []Segment, length i64) {
	sum := total_len(segs)
	assert sum == length, 'planned ${sum} bytes for a ${length}-byte file'
	for i, s in segs {
		assert s.len() > 0, 'segment ${i} is empty'
		// Overlap check against the previous segment: the end of one must be
		// strictly before the start of the next.
		if i > 0 {
			assert s.first > segs[i - 1].last, 'segment ${i} starts at ${s.first}, before the previous one ends at ${segs[i - 1].last}'
		}
	}
}

fn test_one_connection_covers_the_whole_file() {
	segs := plan(1000, 1, 0)
	assert segs.len == 1, '${segs.len}'
	assert segs[0].first == 0 && segs[0].last == 999, '${segs[0]}'
	assert segs[0].range_header() == 'bytes=0-999', segs[0].range_header()
}

fn test_a_short_file_is_not_split() {
	// 1 MiB is smaller than aria2's own 20 MiB minimum segment, so a five-connection
	// ask still yields one segment. Splitting it gives five pieces that each cost a
	// round trip and finish no sooner.
	segs := plan(1048576, 5, 20971520)
	assert segs.len == 1, '${segs.len}'
	assert_covers_exactly(segs, 1048576)
}

fn test_even_split_gives_the_remainder_to_the_first_segment() {
	// 10 bytes over 4 connections: 4,3,3,3 would put the odd byte at the start with
	// a naive `first + i*base`; the rule here is base for everyone plus the
	// remainder on segment zero, so 4,2,2,2.
	segs := plan(10, 4, 0)
	assert segs.len == 4, '${segs.len}'
	assert segs[0].first == 0 && segs[0].last == 3, 'segment 0 = ${segs[0]}'
	assert segs[1].first == 4 && segs[1].last == 5, 'segment 1 = ${segs[1]}'
	assert segs[2].first == 6 && segs[2].last == 7, 'segment 2 = ${segs[2]}'
	assert segs[3].first == 8 && segs[3].last == 9, 'segment 3 = ${segs[3]}'
	assert_covers_exactly(segs, 10)
}

fn test_a_plan_never_reaches_past_the_end() {
	// 7 bytes over 3 connections: base 2, remainder 1, so 3,2,2.
	segs := plan(7, 3, 0)
	assert_covers_exactly(segs, 7)
	for s in segs {
		assert s.last < 7, 'a segment reaches past byte 7: ${s}'
		assert s.first >= 0 && s.first <= 6, 'a segment starts past the end: ${s}'
	}
}

fn test_more_connections_than_bytes_collapses_to_one() {
	// 3 bytes with 8 connections: base 0, so there is no even split to make. Eight
	// connections would mean five empty segments, which the plan refuses to emit.
	segs := plan(3, 8, 0)
	assert segs.len == 1, '${segs.len}'
	assert segs[0].len() == 3, '${segs[0]}'
	assert_covers_exactly(segs, 3)
}

fn test_zero_length_is_an_empty_plan() {
	assert plan(0, 8, 0).len == 0, 'a zero-byte file has nothing to fetch'
	assert plan(-5, 8, 0).len == 0, 'a negative length is a caller error, not a panic'
}

fn test_a_caller_that_does_not_know_gets_one_connection() {
	segs := plan(1000, 0, 0)
	assert segs.len == 1, '${segs.len}'
	assert segs[0].len() == 1000, '${segs[0]}'
}

fn test_a_resume_skips_the_prefix_already_on_disk() {
	segs := resume_plan(1000, 4, 0, 400)
	// 600 bytes remain, split into four even 150s and every range shifted by the
	// 400 already on disk. The first byte requested is 400, not 0 - that is the
	// whole point of a resume, and it is the assertion that would catch a plan
	// which simply ignored the prefix.
	assert segs.len == 4, '${segs.len}'
	assert segs[0].first == 400, '${segs[0]}'
	assert segs[0].last == 549, '${segs[0]}'
	assert segs[3].last == 999, 'the last byte is still the last byte of the file: ${segs[3]}'
	assert_covers_exactly(segs, 600)
}

fn test_a_resume_that_is_already_done_fetches_nothing() {
	assert resume_plan(1000, 4, 0, 1000).len == 0, 'nothing left to fetch'
}

fn test_a_resume_that_overshot_fetches_nothing_rather_than_a_bogus_range() {
	// A stale control file says 1500 bytes are done on a 1000-byte file. Asking
	// for bytes=1500-999 is a request for a range that cannot exist, and a caller
	// that trusts it will report the download finished at 150% of its length.
	assert resume_plan(1000, 4, 0, 1500).len == 0, 'an overshoot must not plan a request'
}

fn test_a_resume_from_zero_is_a_full_plan() {
	segs := resume_plan(1000, 4, 0, 0)
	assert segs[0].first == 0, '${segs[0]}'
	assert_covers_exactly(segs, 1000)
}

fn test_range_headers_are_inclusive_and_correct() {
	s := Segment{
		index: 2
		first: 100
		last:  199
	}
	assert s.range_header() == 'bytes=100-199', s.range_header()
	assert s.len() == 100, 'a 100-byte segment should be 100 bytes, got ${s.len()}'
}

fn test_covers_is_inclusive_at_both_ends() {
	s := Segment{
		index: 0
		first: 100
		last:  199
	}
	assert s.covers(100), 'the first byte is inside'
	assert s.covers(199), 'the last byte is inside'
	assert !s.covers(99), 'the byte before is outside'
	assert !s.covers(200), 'the byte after is outside'
}

fn test_a_broken_segment_reports_zero_length_rather_than_a_negative_one() {
	// A segment built backwards is a caller bug; surfacing it as 0 makes the
	// coverage assertion fail loudly instead of quietly planning a negative range.
	s := Segment{
		index: 0
		first: 50
		last:  10
	}
	assert s.len() == 0, 'a broken segment must not plan a negative range, got ${s.len()}'
}
