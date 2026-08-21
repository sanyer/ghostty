//! Kitty drag and drop protocol (OSC 72).
//!
//! Specification: https://sw.kovidgoyal.net/kitty/dnd-protocol/
//! Reference implementation: kitty/dnd.c and kitty/screen.c in
//! https://github.com/kovidgoyal/kitty (introduced in kitty 0.47).
//!
//! The protocol lets a program running in the terminal participate in
//! native OS drag and drop. A client registers to accept drops (t=a);
//! the terminal then forwards native drag movement (t=m) and drops
//! (t=M) to it and serves the dropped data on request (t=r), instead
//! of the traditional behavior of pasting dropped paths or text.
//!
//! The implementation is split into:
//!
//!   * dnd_command.zig: metadata grammar and typed command decoding,
//!     including chunk reassembly. The grammar mirrors kitty's
//!     generated parser exactly.
//!   * dnd_response.zig: wire encoding for everything the terminal
//!     sends, mirroring kitty's send_payload_to_child chunking.
//!   * dnd_drop.zig: the per-terminal protocol state machine, driven
//!     by client OSCs on one side and native drag events from the
//!     embedder on the other.
//!
//! The wire behavior was validated against kitty's implementation
//! (kitty_tests/dnd.py is the oracle), including its deviations from
//! the published spec: the MIME list payload is sent on every move
//! event with a trailing space after each entry, a missing `t` key
//! ignores the command rather than defaulting to `a`, empty payloads
//! omit the `;` and `m=` entirely, and registration survives a
//! terminal reset (RIS clears only the chunk-reassembly flag).
//!
//! ## Divergences from kitty
//!
//! All are bounded-scope decisions, not accidents:
//!
//!   * Dropped data is captured eagerly at drop time from a curated
//!     set of representations the embedder can serve (typically
//!     text/uri-list and text/plain), rather than fetched from the OS
//!     on demand. Consequently the native drag session concludes at
//!     drop time and the client's concluding operation (t=r with
//!     x=y=Y=0) only frees the held data, and kitty's 128-entry
//!     request queue and EMFILE overflow handling are unnecessary
//!     because requests are served synchronously in order.
//!   * The MIME list a client registers with (the t=a payload) is
//!     accepted but not forwarded to the OS, so exotic pasteboard
//!     types on macOS are not offered to clients.
//!   * Every client is treated as local: machine IDs (t=a:x=1) are
//!     accepted and ignored, responses never carry the X=1 remote
//!     marker, and remote file transfer requests (t=r with y or Y
//!     keys) are answered with EINVAL. A remote client (e.g. over
//!     ssh) can still receive text drops; only file-content transfer
//!     is unavailable.
//!   * The terminal never initiates drags (drag out): enabling offers
//!     (t=o:x=1) is tracked so the state is queryable, but the
//!     terminal never sends a drag start request, so a conforming
//!     client never offers a drag. Direct offers (t=o:x=0) and drag
//!     data/start commands (t=p, t=P) are refused with EPERM.
//!   * Responses echo the requesting command's terminator (ST or BEL)
//!     per ghostty convention; kitty always uses ST. Terminal-
//!     initiated events always use ST.

const dnd_command = @import("dnd_command.zig");
const dnd_response = @import("dnd_response.zig");

pub const EventType = dnd_command.EventType;
pub const Metadata = dnd_command.Metadata;
pub const Operation = dnd_command.Operation;
pub const Operations = dnd_command.Operations;
pub const Request = dnd_command.Request;
pub const Chunking = dnd_command.Chunking;

pub const Errno = dnd_response.Errno;
pub const RequestKeys = dnd_response.RequestKeys;
pub const encode = dnd_response.encode;
pub const encodeError = dnd_response.encodeError;

test {
    _ = dnd_command;
    _ = dnd_response;
}
