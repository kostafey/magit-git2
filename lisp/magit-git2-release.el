;;; magit-git2-release.el --- The released module builds  -*- lexical-binding: t -*-

;; This file is written by build/publish-release.sh.  Do not edit it.

;;; Code:

(defconst magit-git2-release-sources nil
  "The key of the sources the released builds were made from.")

(defconst magit-git2-release-tag nil
  "The GitHub release holding the builds.")

(defconst magit-git2-release-sha256
  nil
  "The SHA-256 of the build for each platform.")

(provide 'magit-git2-release)

;;; magit-git2-release.el ends here
