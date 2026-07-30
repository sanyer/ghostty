//! Terminal snapshot binary representation and codecs.
//!
//! This is NOT a full transport-ready format to implement generic replay
//! software such as multiplexers, recorders (e.g. asciinema), etc. The goal
//! of this package is to provide a documented, binary-compatible representation
//! for a terminal state.
//!
//! We call this a "snapshot." The snapshot is purposely laid out in a way
//! that prioritizes making a terminal functional as quickly as possible.
//! To do that, it sends the active terminal state followed by a READY record,
//! then complete history.
//!
//! READY denotes that enough of the terminal state is down that it can
//! be fully rendered at that point. This is also the point where live
//! terminals can also start accepting pty bytes, typically. But the current
//! snapshot format lacks some of the information necessary to synchronize
//! pty byte state with an authoritative server.
//!
//! After READY, we send history pages (scrollback).
//!
//! ## Snapshot Format
//!
//! This documents snapshot format 1. Version 1 is the work-in-progress
//! format that we intended to continue to break until we can promise
//! binary compatibility.
//!
//! A snapshot is one envelope followed by a sequence of records. The envelope
//! occurs once at byte zero. Every record is independently framed as a fixed
//! header followed by the number of payload bytes declared by that header.
//!
//! ```text
//! +------------------+
//! | Envelope         |
//! +------------------+
//! | Record 1 header  |
//! +------------------+
//! | Record 1 payload |
//! +------------------+
//! | Record 2 header  |
//! +------------------+
//! | Record 2 payload |
//! +------------------+
//! | ...              |
//! +------------------+
//! ```
//!
//! Records have a strict order:
//!
//! ```text
//! +----------------------------------------+
//! | TERMINAL                               |
//! +----------------------------------------+
//! | SCREEN (primary)                       |
//! | PAGE * screen.page_count               |
//! +----------------------------------------+
//! | SCREEN (alternate, when present)       |
//! | PAGE * screen.page_count               |
//! +----------------------------------------+
//! | READY                                  |
//! +----------------------------------------+
//! | HISTORY (primary)                      |
//! | PAGE * history.page_count              |
//! +----------------------------------------+
//! | HISTORY (alternate, when present)      |
//! | PAGE * history.page_count              |
//! +----------------------------------------+
//! | FINISH                                 |
//! +----------------------------------------+
//! ```
//!
//! The SCREEN sequences contain the complete pages needed to restore each
//! active area. A HISTORY sequence contains the older complete pages for its
//! screen in newest-to-oldest order so they can be prepended as they arrive.
//! Every SCREEN has one corresponding HISTORY, even when its history page count
//! is zero. FINISH is followed by end-of-file.
//!
//! READY and FINISH contain BLAKE3-256 digests of all preceding snapshot bytes.
//! READY therefore validates the renderable active-state prefix. FINISH covers
//! READY and all history as well, validating the complete snapshot and its
//! record ordering.
//!
//! ## Encoding
//!
//! Encode the envelope once, then append records in the required order:
//!
//! ```zig
//! var output: std.Io.Writer.Allocating = .init(alloc);
//! defer output.deinit();
//!
//! try envelope.encode(&output.writer);
//! try screen.encode(&terminal_screen, .primary, &output);
//!
//! const snapshot = output.written();
//! ```
//!
//! We have to use an allocating writer because record formats require
//! encoding the length and CRC in the header, so we need a seekable
//! format.
//!
//! Each record type usually exposes an `encode` function that encodes
//! a complete record, such as `screen.encode`.

pub const checkpoint = @import("checkpoint.zig");
pub const envelope = @import("envelope.zig");
pub const grid = @import("grid.zig");
pub const history = @import("history.zig");
pub const hyperlink = @import("hyperlink.zig");
pub const page = @import("page.zig");
pub const record = @import("record.zig");
pub const screen = @import("screen.zig");
pub const style = @import("style.zig");
pub const terminal = @import("terminal.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
