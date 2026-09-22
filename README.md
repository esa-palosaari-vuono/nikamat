# Nikamat

A macOS menu bar app that reminds you to open up your neck, shoulders and
shoulder blades — and guides the movements, rather than just nudging you.
A drawn figure animates each exercise while the same clock drives both the
animation and the hold/release countdown.

Documentation is in Finnish, under [`docs/`](docs/).

## What it does

Two-tier rhythm: a short seated micro break every 30 minutes (~60 s, two
exercises) and a longer one every hour (~3 min, four to five exercises,
some standing). When both fall due at once, the long one wins.

- **16 exercises** across neck, upper trapezius, shoulders, scapulae, chest
  and thoracic spine. Each break picks one exercise per body region,
  preferring whatever has gone longest unused.
- **Animated vector figure**, drawn from the front, the side or from behind
  depending on which angle actually shows the movement.
- **Per-exercise timing**: hold and release phases, repetition counts, and a
  countdown ring driven by the same clock as the animation.
- **Knows when not to interrupt**: quiet hours, idle detection, a settling
  period after you return to the desk, and deferral while an audio input
  device is running — the cheapest proxy for "in a meeting".
- **SQLite log** you can read from Emacs, `sqlite3`, or anything else.

## Install

Requires Xcode command line tools (Swift 6.2) and macOS 15 or later.

```bash
make install                        # build and install to ~/Applications
open ~/Applications/Nikamat.app
make autostart                      # optional: start at login
```

See [`docs/kayttoonotto.org`](docs/kayttoonotto.org) for the rest.

## Diagnostics

```bash
APP=~/Applications/Nikamat.app/Contents/MacOS/Nikamat

open -n ~/Applications/Nikamat.app --args --break-now   # break right now
"$APP" --exercises                                      # library as an Org table
"$APP" --render-poses /tmp/poses                        # every pose to PNG
"$APP" --render-break /tmp/break.png long 9             # window to PNG
"$APP" --selftest                                       # planner + log, scratch DB
```

## Tests

```bash
make test        # or: swift test
```

Swift Testing, run against the executable with `@testable import`. The
scheduling rules are tested in simulated time (idle, sleep, microphone,
snooze, quiet hours), the break lifecycle against a fake window, and the
log against temporary SQLite files. Nothing touches your real defaults or
history.

`--render-poses` is how the poses were reviewed: pose data cannot be judged
by reading it, because a plausible-looking 30° head tilt can still draw a
figure dislocating its own shoulder.

## Layout

| Path                          | Contents                                    |
|-------------------------------|---------------------------------------------|
| `Sources/Nikamat/Model`       | poses, exercises, break planning, the clock |
| `Sources/Nikamat/Scheduling`  | when a break opens, and when it does not    |
| `Sources/Nikamat/Views`       | drawing engine and user interface           |
| `Sources/Nikamat/Support`     | system sensors, diagnostic modes            |
| `Sources/Nikamat/Persistence` | SQLite wrapper and the break log            |
| `Tests/NikamatTests`          | unit and lifecycle tests                    |
| `docs`                        | documentation (Finnish, Org mode)           |

No third-party dependencies. SwiftPM builds the binary; the `Makefile`
wraps it into a `.app` bundle, because the `LSUIElement` key in
`Info.plist` is what keeps the app out of the Dock.

## Caveat

Ordinary desk mobility exercises, not a treatment programme. A stretch
should be felt, never hurt. If stiffness is constant or radiates into your
arms, see a physiotherapist instead.
