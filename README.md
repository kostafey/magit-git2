# magit-git2

Magit asks git a few dozen cheap, read-only questions on every status
refresh, each in its own process. On Windows a git process costs about
190 ms. magit-git2 answers these questions in-process: an Emacs dynamic
module written in Zig over libgit2 (`magit-git2-core`) reads the
repository, and Elisp formats the data exactly as git prints it.

Every synchronous git call of Magit goes through `magit-process-git`. An
`:around` advice on that function (the only change to Magit's behaviour)
looks at the local arguments. If they have a registered *shape*, the
shape's formatter answers. Every other call, and every call a formatter is
not sure about, goes to git exactly as before. Asynchronous git (commit,
push, fetch, rebase) is untouched.

On Windows this took a status refresh from 4.28 s to 0.37 s on one real
repository. On Linux, where a process is cheap, the gain is small.

## Install

```elisp
(straight-use-package
 '(magit-git2 :type git :host github :repo "kostafey/magit-git2"))
```

That is all: it loads with Magit, and the first time downloads the module
for your system. See [Release builds](#release-builds). Without a package
manager, add `lisp/` to `load-path` and call `(require 'magit-git2)` after
Magit has loaded. It is not on MELPA yet.

## Layout

```
build.zig, build.zig.zon     the module; libgit2 is a pinned dependency
build/libgit2.zig            static libgit2 without network support
build/libgit2-sources.zon    its source list
build/publish-release.sh     CI: the release, and the pins of its builds
src/main.zig                 module functions (data in, data out)
src/git.zig                  repository cache, libgit2 errors, object ids
src/path.zig                 directory paths as git prints them
src/walk.zig                 git log's commit order
src/emacs.zig                helpers over emacs_env
vendor/emacs-module.h        from Emacs 31.1, unchanged
lisp/magit-git2-core.el      loads the module, downloads the release build
lisp/magit-git2-release.el   the pinned release, written by CI
lisp/magit-git2.el           advice, dispatcher, formatters, modes
test/                        fixture builder, differential ERT suite
measure/                     the refresh cost measurement
LICENSE                      GNU General Public License, version 2
```

## Build

Requires Zig 0.17.0 (`zig version`). No C is written: the C headers go
through `translate-c`, because Zig 0.17 has no `@cImport`.

```sh
zig build                              # zig-out/lib/magit-git2-core.so
zig build -Dtarget=x86_64-windows-gnu  # zig-out/lib/magit-git2-core.dll
zig build -Dsystem-libgit2=true        # link libgit2 found by pkg-config
zig build -Dstrip=true                 # without debug info
zig build test                         # unit tests of the Zig parts
```

The optimization mode defaults to `safe` (Zig 0.17's name for
ReleaseSafe): bounds checks stay in, as a module crash is an Emacs crash.

libgit2 1.9.7 is fetched by `zig build` and pinned by hash in
`build.zig.zon`. It is built without HTTPS, SSH or NTLM, with libgit2's
bundled zlib, PCRE2 regex and SHA-256. The only libgit2 symbols the module
exports are `emacs_module_init` and `plugin_is_GPL_compatible` (a version
script on ELF). The Windows `.dll` depends only on system DLLs: KERNEL32,
ADVAPI32, WS2_32, Secur32, ntdll and the Universal CRT.

`build/libgit2.zig` is adapted from the `build.zig` of
[allyourcodebase/libgit2](https://github.com/allyourcodebase/libgit2)
(MIT, commit 71b31da, already ported to Zig 0.17). The TLS backends,
libssh2 and ntlmclient are removed, together with every dependency except
the libgit2 tarball. zlib and pcre2 are compiled as libraries of their own,
because on Windows zlib's `#include <process.h>` would otherwise find
libgit2's `src/util/process.h`.

## Release builds

Building is optional. `magit-git2-core-ensure`, called when Magit loads,
downloads the build for this system when there is no module file, and
loads it. Which build is told from `system-type` and
`system-configuration`: x86-64 Windows, or x86-64 Linux with glibc 2.28 or
newer. Other systems stay with git unless they build the module.

The download runs in the background with messages at its start and end, so
Magit does not wait: it runs git until the module is there, and then
`magit-git2-core-loaded-hook` runs. It takes `curl`, as a process blocks Emacs neither on DNS nor
on TLS; Windows has one since version 10, and it reads the Windows certificate
store. If it fails, the message says why and Magit goes on with git. Then
`M-x magit-git2-download-module` tries again. Where the network blocks it, get
the file from the release page and set `magit-git2-core-file` to it.

A build lands in `magit-git2-core-directory` (`~/.emacs.d/magit-git2/`) only
if its SHA-256 is the one pinned in `lisp/magit-git2-release.el`, under a name
with that hash: a new build goes beside a loaded one, which Windows would not
let it replace. A module built here (`magit-git2-core-file`) has precedence
and nothing is downloaded. `magit-git2-core-download` nil turns the download
off.

On master, when the sources of the module changed and the tests pass, CI
publishes both builds as a GitHub release (artifacts of a run need a GitHub
login) and commits the new `lisp/magit-git2-release.el`. So a Lisp commit
names exact builds, and that commit is CI's: pull before the next push.

## Use

`magit-git2-mode` is one of:

- `off`: always run git.
- `verify`: run git and also the emulation, compare the exit code and the
  output byte for byte, and record every difference in
  `*magit-git2-mismatches*`. The first difference of each shape in a session
  also shows as a warning, once the refresh is over. Magit always gets git's
  result.
- `on`: answer what the emulation understands, run git for the rest.

The default is `on`; until the module is loaded, every call goes to git. An
unexpected Lisp error in the emulation sets the mode to `off` for the session
and is logged to `*magit-git2-log*`. A libgit2 error (signalled as
`magit-git2-error`) only sends that one call to git.

Commands:

- `magit-git2-mode` cycles the mode.
- `magit-git2-show-mismatches` shows what verify mode found.
- `magit-git2-stats` shows per-command counters (emulated, fell through,
  mismatched, libgit2 errors, skipped, started ahead) and the number of
  auto-disables.
- `magit-git2-reload-module` loads a rebuilt module, from a temporary copy,
  since Emacs never unloads a module.
- `magit-git2-download-module` tries a failed download again.

On Windows, `magit-git2-set-system-config-from-git` runs once the module is
loaded and points libgit2 at the system config of Git for Windows
(`<root>/etc/gitconfig`, or `<root>/mingw64/etc/gitconfig`), which libgit2
does not search by default.

Repository handles are cached per git directory during a Magit refresh
and freed when it ends (`magit-unwind-refresh-hook`), or right after a
call made outside a refresh. On Windows no pack file stays open to block
`git gc`.

While Magit refreshes a buffer the emulation also keeps what it has read
(refs, config, resolved revisions) from one call to the next, per directory
and global arguments, since only reading happens there. Magit's own refresh
cache has a wider scope: `magit-run-git` binds it around a command that
writes.

In mode `on` a status refresh also does without its first command,
`update-index --refresh`. Magit ignores the exit code, and the `git diff` of
the same refresh looks past stale stat data and writes the index back. Git
does run it with `--no-optional-locks` or with `diff.autoRefreshIndex` off.

What such a refresh still needs of git is `status` and two `diff` commands,
nearly all of it process start-up, and Magit waits for one after the other.
So the refresh starts the `status` and `diff` commands of the previous one
all at once, with the same arguments, and takes their output when Magit asks
for it. A command Magit does not ask for runs to its end, since killed git
could leave `index.lock` behind. One that was not started runs as usual and
starts ahead next time.

## What is emulated

`M-x describe-variable magit-git2--shapes` lists the shapes. In short:

| command | shapes |
|---|---|
| rev-parse | `--show-toplevel`, `--show-cdup`, `--git-dir`, `--is-bare-repository`, `--is-inside-work-tree`, `--verify [--quiet] REV`, `--short REV`, `--verify --abbrev-ref X@{upstream}`, `@{upstream}` |
| symbolic-ref | `[--short] NAME` |
| config | `--list [-z]`; `[--local\|--global\|--system] [-z] --get\|--get-all [--include] KEY`; `--bool [--default V] KEY` |
| for-each-ref | `--format=` of `%(refname[:short])`, `%(symref[:short])`, `%(objectname[:short])`, `%(upstream[:short])`, `%(HEAD)`; `--sort=[-]refname`; prefix patterns |
| describe | `--long --tags [REV]`; `--contains REV` when no tag, or exactly one tag at REV itself, contains it |
| log | an explicit `--format=`/`--pretty=tformat:` of `%H %h %P %p %s %b %d %D %an %ae %aN %aE %at %cn %ce %cN %cE %ct %n %% %xNN`, revisions (`A`, `^A`, `A..B`), `--no-walk`, `-nN`, `--decorate=full\|short\|no`, `--[no-]use-mailmap`, `--no-prefix`, a final `--` |
| reflog | `--format=` with the above and `%gd %gD %gs %gn %ge`, of a full ref name |
| merge-base | `--is-ancestor A B`, `A B` |
| rev-list | `--count --left-right A...B` |
| remote | (no arguments) |

Never emulated: `diff`, `status`, `ls-files`, `update-index` and
everything else that writes, `log` without an explicit format or with
`--graph`/`-p`/paths, `blame`. On a Windows work tree libgit2's status took
twice as long as a whole git process, so `status` and `ls-files` stay with
git. A formatter refuses rather than approximates. Cases it refuses:

- revisions outside `NAME[@{upstream}][~N|^N|^{commit}|^{tree}|^{}]...`,
  abbreviated hashes, and names that more than one ref could mean;
- placeholders and fields outside the lists above, glob patterns,
  version sort;
- shallow repositories, grafts and replace refs (libgit2 ignores them),
  alternates, incremental multi-pack-index chains;
- commit messages git would re-encode;
- `log.excludeDecoration`/`log.initialDecorationSet` for decorations;
- `describe --contains` when HEAD is in a commit-graph (git then cuts off
  by generation number, not by date);
- global arguments other than `--no-pager`, `--literal-pathspecs`,
  `--no-optional-locks` and `-c KEY=VALUE`;
- an environment that changes what git reads: `GIT_DIR` and the like, or
  `HOME`, `XDG_CONFIG_HOME`, `GIT_CONFIG_SYSTEM`, ... other than at Emacs
  start-up;
- remote directories, and call destinations other than `nil`, `t`,
  `(t nil)` and `(t FILE)`.

### Where git's behaviour is replicated, not taken from libgit2

- **Commit order of `log`.** `src/walk.zig` lists commits in git's default
  order: a queue newest committer date first, equal dates in the order
  they were queued, and for ranges git's way of telling that the walk is
  done (five excluded commits in a row with nothing newer queued), clock
  skew included. libgit2's `GIT_SORT_TIME` queue does not keep equal dates
  in queue order.
- **Abbreviation length.** git 2.55 sizes `%h`, `--short` and `describe`
  hashes from the objects in packs only (`.idx` headers and the
  multi-pack-index, loose objects excluded): `max(7, ceil((msb(n)+1)/2))`.
  `core.abbrev` overrides this. Uniqueness is then extended through
  libgit2.
- **Decorations (`%d`, `%D`).** git's default decoration filter, its order
  (HEAD first, then refs in reverse name order, `HEAD -> branch` merged)
  and `tag:` for peeled annotated tags.
- **Mailmap.** It applies to `%aN`/`%aE`/`%cN`/`%cE` only. `%an` and `%ae`
  stay raw in `--format` output, with or without `--use-mailmap`.
- **Ref shortening** (`--abbrev-ref`, `:short`, `symbolic-ref --short`,
  `%gd`): git's `shorten_unambiguous_ref`, strict where git is strict
  (`core.warnAmbiguousRefs`).
- **`describe --contains`.** `name-rev` walks down from the tags but not
  into commits more than a day older than the commit described. The module
  walks the same way: libgit2's exact reachability check walks the whole
  history below the tags.
- **Paths.** `--show-toplevel` and an absolute `--git-dir` print the real
  name of the directory. On Windows that takes `GetFinalPathNameByHandle`:
  a capital drive letter and the case on disk, where libgit2 repeats the
  path it was given. Without a module that can tell, git answers.
- **Config.** The `-c` pairs of `magit-git-global-arguments` come last in
  `config --list` and take precedence in lookups. `config --bool` reports
  the first invalid value in file order, as git does.
- **Error messages** for the cases Magit inspects, copied from git 2.55.
- `magit-git-string-ng` passes the global arguments again as local ones.
  The dispatcher strips them.

## Tests

```sh
test/run-tests.sh                    # whole suite
test/run-tests.sh magit-git2-test-differential
MAGIT_GIT2_TEST_REPOS=~/src/a:~/src/b test/run-tests.sh
```

`test/fixture.el` builds the fixture with real git in a temporary directory:

- a branch with an upstream two commits ahead and one behind, and a branch
  with a push remote;
- lightweight and annotated tags, two stashes;
- staged, unstaged, renamed, untracked and ignored files, with UTF-8 names
  and messages;
- a commit message in windows-1251 (`i18n.commitEncoding`), which the
  module cannot read, so that the error path is exercised;
- a mailmap, an included config file, a key without a value, and system,
  global and local config;
- a linked worktree, a detached clone, an unborn repository and a bare one.

`HOME`, `XDG_CONFIG_HOME` and `GIT_CONFIG_SYSTEM` point into that directory.

For every example argument list of every registered shape, in every
fixture state and in every repository of `MAGIT_GIT2_TEST_REPOS` (by
default the one containing this directory), the emulation's exit code,
stdout and stderr must equal git's. The examples belong to the shape
definitions (`:examples`, which `magit-git2-define-shape` requires), and a
test fails for any shape that never answers. Two more tests compare
Magit's own helpers with the emulation on and off, and refresh status
buffers in verify mode. Mismatches go to `MAGIT_GIT2_TEST_REPORT`.

The download tests fetch a release from a `file://` URL with real `curl`.

## Measuring

```sh
emacs -l measure/magit-git2-measure.el    # then, in a repository:
M-x magit-git2-measure
```

This records `magit-status` and two refreshes
(`magit-process-record-invocations`, `magit-refresh-verbose`) and times
three more. It writes `measure/report-<host>-<date>-<setup>.org`, where
`<setup>` is `git` when the module is not loaded and `magit-git2-mode`
otherwise: invocations per command and per argument list, the calls through
`magit-process-git` with the time of each and whether it started git,
section timings, wall time per refresh and, when magit-git2 is loaded, its
mode and statistics. Emacs has no `dynamic-modules` feature to test. Module
support shows as `module-load` together with a non-nil
`module-file-suffix`.

A report names the measured repository, its branches and local paths, so
git ignores `measure/report-*.org` and the directories under `measure/`.

## License

magit-git2 is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 2 of the License, or (at your
option) any later version. See `LICENSE`.

The module also contains code under other licenses:

- libgit2 and the libraries it bundles, under the terms in libgit2's
  `COPYING`: GPL version 2 with a linking exception for libgit2 itself,
  permissive licenses for the rest;
- `vendor/emacs-module.h`, part of GNU Emacs: GPL version 3 or later.

`build/libgit2.zig` is adapted from allyourcodebase/libgit2 and stays
under its MIT license, quoted in the file.
