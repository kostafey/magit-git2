#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Publish the modules CI built as a GitHub release, and pin their SHA-256
# in lisp/magit-git2-release.el, which the download checks them against.
#
#   build/publish-release.sh ARTIFACTS-DIRECTORY
#
# ARTIFACTS-DIRECTORY holds the run's artifacts, a directory for each.
# The checkout is master's tip, with GITHUB_SHA, the commit built, in its
# history.  This does nothing when the pinned builds were made from the
# same sources, or when newer sources are on master: the run of those
# publishes them.

set -eu
artifacts=$(cd "$1" && pwd)
cd "$(git rev-parse --show-toplevel)"
pins=lisp/magit-git2-release.el

# The key of what makes up a build at commit $1, the workflow included:
# it names the Zig version and the targets.
sources() {
    git ls-tree "$1" .github/workflows/ci.yml build.zig build.zig.zon \
        build src vendor | git hash-object --stdin
}

key=$(sources "$GITHUB_SHA")
pinned=$(sed -n 's/^(defconst magit-git2-release-sources "\(.*\)"$/\1/p' "$pins")
if [ "$key" = "$pinned" ] || [ "$key" != "$(sources HEAD)" ]; then
    exit 0
fi

tag=magit-git2-core-$(git rev-parse --short=12 "$GITHUB_SHA")
dist=$(mktemp -d)
cp "$artifacts/magit-git2-core-windows-x86_64/magit-git2-core.dll" \
   "$dist/magit-git2-core-windows-x86_64.dll"
cp "$artifacts/magit-git2-core-linux-x86_64/magit-git2-core.so" \
   "$dist/magit-git2-core-linux-x86_64.so"

gh release view "$tag" >/dev/null 2>&1 ||
    gh release create "$tag" --target "$GITHUB_SHA" --title "$tag" \
       --notes "The magit-git2-core modules built from $GITHUB_SHA."
gh release upload "$tag" "$dist"/* --clobber

sha256() {
    sha256sum "$dist/$1" | cut -d' ' -f1
}

write_pins() {
    cat > "$pins" <<PINS
;;; magit-git2-release.el --- The released module builds  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kostafey <kostafey@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 2 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; This file is written by build/publish-release.sh.  Do not edit it.
;; magit-git2-core.el checks a download against these hashes.

;;; Code:

(defconst magit-git2-release-sources "$key"
  "The key of the sources the released builds were made from.")

(defconst magit-git2-release-tag "$tag"
  "The GitHub release holding the builds.")

(defconst magit-git2-release-sha256
  '(("windows-x86_64"
     . "$(sha256 magit-git2-core-windows-x86_64.dll)")
    ("linux-x86_64"
     . "$(sha256 magit-git2-core-linux-x86_64.so)"))
  "The SHA-256 of the build for each platform.")

(provide 'magit-git2-release)

;;; magit-git2-release.el ends here
PINS
}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
# A push of the user's may land first; the pins file is ours alone.
for attempt in 1 2 3 4 5; do
    write_pins
    git commit -qm "Pin the magit-git2 module builds of $tag" -- "$pins"
    git push -q origin HEAD:master && exit 0
    sleep "$attempt"
    git fetch -q origin master
    git reset -q --hard origin/master
done
exit 1
