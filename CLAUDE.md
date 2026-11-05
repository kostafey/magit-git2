# CLAUDE.md

Guidance for coding agents in this repository. `README.md` explains what the
package does and how it works, so read it first. This file holds what it
takes to change the code safely.

## Commands

```sh
zig build                                  # zig-out/lib/magit-git2-core.so
zig build test                             # src/emacs.zig, walk.zig, git.zig
zig fmt --check build.zig build src
test/run-tests.sh                          # ERT, needs a built module
test/run-tests.sh magit-git2-test-ahead    # one test
test/run-tests.sh '"download\\|platform"'  # tests by regexp
MAGIT_GIT2_TEST_REPOS=~/src/a:~/src/b test/run-tests.sh
```

ERT's output of a mismatch is huge: set `MAGIT_GIT2_TEST_REPORT=<file>` and
read that instead. The repositories of Magit and Org are good stress cases,
with 100+ tags and 29k commits with date ties.

`src/path.zig` has Windows-only code, which `zig build test` does not reach:

```sh
zig test src/path.zig -target x86_64-windows-gnu -lc \
    --test-cmd wine --test-cmd-bin
```

Wine's `GetFinalPathNameByHandleW` returns the path as given, so the case of
a path and its drive letter can only be checked on real Windows.

## The emulation

Real git's output is the spec. A formatter that cannot be sure to match it
refuses, and the call falls through to git, which is always correct. Every
shape carries `:examples`, and the differential test runs them against git.

Only read-only queries are emulated. The one exception is the skipped
`update-index --refresh`, explained in the README.

The licence is GPL-2.0-or-later and git's is GPL-2.0-only, so never translate
git's code. Reimplement the behaviour from a description and verify it with
differential tests.

## Traps

- The refresh memo is keyed by `magit--refresh-start-time`. It must not follow
  `magit--refresh-cache`: `magit-run-git` binds that around commands that
  write, so refs would go stale.
- Commands started ahead run to their end, as killed git can leave
  `index.lock` behind. A process that has exited still needs
  `accept-process-output` to hand over its stdout.
- `delete-process` always redisplays. Mid-refresh that shows a half-built
  buffer, so finished processes are freed from a zero timer.
- On Windows `directory-file-name` lowers the drive letter. Never pass text
  meant to equal git's output through file-name primitives.
- Emacs never unloads a module, and Windows cannot replace or delete a loaded
  `.dll`. Hence the hash in a downloaded module's name and the temporary copy
  in `magit-git2-core-reload`.
- A module crash is an Emacs crash. Keep the `safe` optimization mode.
- The module may arrive after this package has loaded. What needs it goes on
  `magit-git2-core-loaded-hook`, not at the top level of a file.

Zig 0.17 has no `@cImport` (use `b.addTranslateC`) and no `**` on arrays (use
`@splat`). Optimization modes are `debug`, `safe`, `fast` and `small`, and
`dupeZ` is `dupeSentinel`.

## Measuring

`batch` Emacs has no redisplay: count redisplays in a tty Emacs under `script`
with `pre-redisplay-functions`. File operations per call are counted with an
`LD_PRELOAD` shim.

Measurement reports name real repositories, branches and paths. They stay
local (`measure/report-*.org` and `measure/*/` are ignored), and nothing from
them goes into code, tests, comments or commit messages.

## Releases

`lisp/magit-git2-release.el` is written by `build/publish-release.sh`; do not
edit it. When a push to master changes `build.zig`, `build.zig.zon`, `build/`,
`src/`, `vendor/` or the workflow, CI publishes a release and commits that
file. So after such a push run `git pull --rebase` before the next one.

In CI the Nix Emacs of `purcell/setup-emacs` cannot find Ubuntu's libgit2, so
the system-libgit2 build is tested with apt's Emacs.

## Style

- Keep Elisp lines within 80 columns.
- Comments and the README describe the present state, not its history.
- Commit messages say what changed and why, with no attribution lines.
- A test Emacs gets a temporary `--init-directory`, as `test/run-tests.sh`
  does, and never touches the user's own config.
