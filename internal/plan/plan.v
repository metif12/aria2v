// plan.v - how one download is split across connections.
//
// This is the whole reason aria2 is faster than curl on a big file, and it is
// arithmetic, so it is testable: given a length, a connection count, a minimum
// segment size and what is already on disk, which byte ranges should be fetched
// next?
//
// The rules, in the order they are applied, and each one was a real mistake
// somewhere:
//
//  1. A download SHORTER than the minimum segment is one connection. Splitting a
//     1 MiB file eight ways gives eight 128 KiB pieces that each cost a round trip
//     and finish no sooner.
//
//  2. Never plan a range that reaches past the end. aria2 answers that with a 416
//     and a caller that trusts the plan will happily loop forever requesting a
//     byte that does not exist.
//
//  3. Never plan a range that starts past the end, either - that is the same bug
//     on the other side and it is how a download appears "finished" at 300% of
//     its length.
//
//  4. What is already on disk is subtracted, not ignored. A resume that
//     re-fetches from zero is not a resume, and a resume that assumes the file is
//     intact would skip a truncated tail.
module plan

// Segment is one range to fetch, and the reason it is `first`/`last` rather than
// `start`/`end` is that aria2's JSON-RPC spells its own ranges
// `bytes=<first>-<last>` inclusive. Naming ours the same way keeps the mapping
// between this plan and the wire one line rather than an off-by-one.
pub struct Segment {
pub mut:
	index int
	first i64
	last  i64
}

// len is how many bytes this segment covers, and it is a method because a
// segment whose `last` is before its `first` is a bug and this is where it
// should be visible.
pub fn (s Segment) len() i64 {
	if s.last < s.first {
		return 0
	}
	return s.last - s.first + 1
}

// plan splits `length` bytes into at most `connections` segments.
//
// The split is EVEN and the remainder goes to the FIRST segment rather than the
// last. That is deliberate: aria2 hands the extra bytes to segment zero, and a
// caller that puts them at the end cannot tell which segment is the "long" one
// without comparing lengths, which is how a progress bar ends up finishing 1%
// early and then sitting there.
pub fn plan(length i64, connections int, min_segment i64) []Segment {
	mut out := []Segment{}
	if length <= 0 {
		return out
	}

	// One connection when the file is too small to be worth splitting - and also
	// when the caller asked for one, including when they asked for zero or fewer,
	// which is a caller that means "I do not know" rather than "no connections".
	mut n := connections
	if n <= 0 {
		n = 1
	}
	if min_segment > 0 && length / i64(n) < min_segment {
		n = 1
	}
	if n <= 1 {
		out << Segment{
			index: 0
			first: 0
			last:  length - 1
		}
		return out
	}

	base := length / i64(n)
	leftover := length % i64(n)
	// If the arithmetic cannot give every connection at least one byte, fall back
	// to a single connection rather than emitting empty segments.
	if base == 0 {
		out << Segment{
			index: 0
			first: 0
			last:  length - 1
		}
		return out
	}

	mut first := i64(0)
	for i in 0 .. n {
		mut size := base
		if i == 0 {
			size += leftover
		}
		if size <= 0 {
			break
		}
		out << Segment{
			index: i
			first: first
			last:  first + size - 1
		}
		first += size
	}
	return out
}

// resume_plan is plan() with what is already on disk subtracted.
//
// `done` is how many bytes at the START of the file are already complete. The
// already-fetched prefix is dropped from segment zero and the file keeps growing
// from where it stopped, which is what a `Range: bytes=<done>-<length-1>` request
// asks the server for.
//
// `done` may overshoot - a stale control file and a re-downloaded file are two
// ways to end up there - and an overshoot yields an empty plan rather than a
// panic or a bogus request.
pub fn resume_plan(length i64, connections int, min_segment i64, done i64) []Segment {
	if done <= 0 {
		return plan(length, connections, min_segment)
	}
	remaining := length - done
	if remaining <= 0 {
		return []Segment{}
	}
	mut out := []Segment{}
	for s in plan(remaining, connections, min_segment) {
		out << Segment{
			index: s.index
			first: s.first + done
			last:  s.last + done
		}
	}
	return out
}

// range_header is the value of the HTTP `Range` header for one segment.
//
// `bytes=<first>-<last>`, inclusive on both ends. An open-ended form is allowed
// by HTTP but not used here: a segment that does not know its end is a segment
// whose length cannot be checked, and an unchecked length is how a truncated file
// gets reported as complete.
pub fn (s Segment) range_header() string {
	return 'bytes=${s.first}-${s.last}'
}

// covers answers whether `pos` is inside this segment.
//
// Inclusive at both ends, like the header. A half-open check here is the classic
// off-by-one that makes the last byte of a segment be requested twice.
pub fn (s Segment) covers(pos i64) bool {
	return pos >= s.first && pos <= s.last
}

// total_len is how many bytes a plan will fetch. A plan whose total is not the
// file's length is a plan that will produce a short or long file, and this is the
// single assertion every test below leans on.
pub fn total_len(segs []Segment) i64 {
	mut sum := i64(0)
	for s in segs {
		sum += s.len()
	}
	return sum
}
