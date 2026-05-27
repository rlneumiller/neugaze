# Best-practice way to do "first-success wins" in Linux/PAM/Rust

## Use custom conversation wrapper + `pipe()` cancellation

The cleanest race pattern uses a **cancellable conversation function** built on `poll()` + a `pipe()` pair for cancellation signalling. We take ownership of the password read so that we can cancel it cleanly.

A `pipe()` pair is preferred over `eventfd` here:
- `eventfd` is Linux-only; `pipe()` works on Linux, macOS, and all BSDs
- the pipe's byte payload can carry typed signal values, making the channel self-describing without a separate atomic
- when the write end closes (e.g. the biometric thread panics), the read end receives `POLLHUP` automatically — a free implicit error signal that `eventfd` does not provide

#### Dependencies

Use the [`rustix`](https://crates.io/crates/rustix) crate for all fd operations. It calls syscalls directly (bypassing libc), provides fully safe typed wrappers, and returns `Result<_, Errno>` throughout. Use the [`pam`](https://crates.io/crates/pam) crate's safe `PamHandle` wrapper rather than raw FFI to avoid the send-across-thread problem.

```toml
# Cargo.toml
[dependencies]
rustix = { version = "0.38", features = ["pipe", "event", "io"] }
pam   = "1"
```

#### Signal constants

```rust
const SIG_BIO_SUCCESS: u8 = 1;
const SIG_BIO_FAILURE: u8 = 2;
const SIG_TIMEOUT:     u8 = 3;
```

#### Create the pipe

```rust
use rustix::pipe::{pipe_with, PipeFlags};

// O_CLOEXEC set atomically — critical in a PAM module to avoid fd leaks into child processes
let (cancel_read, cancel_write) = pipe_with(PipeFlags::CLOEXEC)?;
```

Both ends are returned as `OwnedFd` directly so no risk of leaking fds into child processes (which causes subtle and hard-to-debug auth failures in PAM contexts).

#### Password thread: safe poll() with rustix

```rust
use rustix::event::{poll, PollFd, PollFlags};

let pw_thread = thread::spawn(move || {
    let mut fds = [
        PollFd::new(&stdin_fd,    PollFlags::IN),
        PollFd::new(&cancel_read, PollFlags::IN),
    ];

    poll(&mut fds, -1)?; // blocks; returns Result<_, Errno>

    // Biometric side died unexpectedly — fall through to password auth normally
    if fds[1].revents().contains(PollFlags::HUP) {
        return read_password_via_pam_conv(pamh);
    }

    // Explicit cancellation signal received
    if fds[1].revents().contains(PollFlags::IN) {
        let mut sig = [0u8; 1];
        rustix::io::read(&cancel_read, &mut sig)?;
        match sig[0] {
            SIG_BIO_SUCCESS => return None,       // yield; biometric won
            SIG_BIO_FAILURE => { /* continue prompting */ }
            SIG_TIMEOUT     => return None,       // hard abort
            _               => {}
        }
    }

    read_password_via_pam_conv(pamh)
});
```

`PollFd::new` borrows `OwnedFd` directly (via `AsFd`), so the borrow checker enforces that the fds stay alive for the duration of the call.

#### Biometric path: signal and clean up

```rust
use rustix::io::write;

let bio_result = rt.block_on(authenticate_biometric(&username));

if bio_result == Ok(Some(true)) {
    // Signal the password thread to yield
    write(&cancel_write, &[SIG_BIO_SUCCESS])?;

    // Wait for the password thread to exit, then restore terminal/UI state
    let _ = pw_thread.join();

    // IMPORTANT: restore terminal state here (tcsetattr) or send a PAM
    // conversation dismiss message — do not return PAM_SUCCESS with the
    // prompt still active, as this leaves the terminal or GDM widget dirty.

    return PAM_SUCCESS;
}

// Biometric lost — wait for password, stash it, let pam_unix.so verify
// (see note in Idea One, point 5, about downstream module coupling)
// From idea one, point 5:
// 5. If password entry wins first:
//    - store the entered password into `PAM_AUTHTOK` via `pam_set_item`
//    - return `PAM_AUTHINFO_UNAVAIL`
//    - let the next stack module (typically `pam_unix.so`) verify it
//    - **Note:** this is an implicit contract with the downstream module. 
//      If the stack uses LDAP, SSSD, or systemd-homed instead of `pam_unix.so`,
//      this silently breaks. Document the assumption explicitly, or perform 
//      password verification inside the module itself to avoid the dependency entirely.
```
#### Why `POLLHUP` matters here

When `cancel_write` drops (because the biometric thread exited normally or panicked), the OS closes the write end of the pipe. The read end then receives `POLLHUP` in its `revents`. This gives the password thread implicit error propagation for free:

```rust
if fds[1].revents().contains(PollFlags::HUP) {
    // Biometric side died — proceed with password auth as normal fallback
    return read_password_via_pam_conv(pamh);
}
```

#### Timeout on the biometric path

Always impose a deadline on the biometric side. If the face-auth daemon hangs or crashes silently, the race must not block indefinitely:

```rust
let bio_result = tokio::time::timeout(
    Duration::from_secs(5),
    authenticate_biometric(&username),
).await;

if bio_result.is_err() {
    // Timeout — signal password thread to continue, fall through
    write(&cancel_write, &[SIG_TIMEOUT])?;
}
```

#### Multi-producer note

With `eventfd`'s atomic increment, concurrent writes from multiple threads are self-consolidating — a single read drains the counter regardless of how many writes occurred. With a pipe, two concurrent writes produce two bytes. For a single-producer cancel signal (one biometric thread, one write) this is not a concern. If the design later grows multiple signal sources, either drain the pipe in a loop or reach for `crossbeam_channel` rather than raw fd signalling.

#### Additional best practices

- Keep the PAM conversation call on the **main thread** — only signal via the pipe write end from other threads.
- Prefer `PAM_AUTHINFO_UNAVAIL` + `PAM_AUTHTOK` only when the next stack module is known; otherwise perform verification inside the module to remove the downstream dependency.
- Always add a timeout to the biometric path so a dead face-auth daemon cannot stall the entire auth flow indefinitely.
