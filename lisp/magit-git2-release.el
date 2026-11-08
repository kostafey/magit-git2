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

(defconst magit-git2-release-sources "6a76b2f976a81d49321bb43ba76edb9b73d74864"
  "The key of the sources the released builds were made from.")

(defconst magit-git2-release-tag "magit-git2-core-b1ee52730a71"
  "The GitHub release holding the builds.")

(defconst magit-git2-release-sha256
  '(("windows-x86_64"
     . "6c9a4e453d7fae4ad4196e63b72eda14a7824e50acdfffa4014542c2f2ddc73c")
    ("linux-x86_64"
     . "6317ecb8cd6c28cf4c0940887c94524786887d30d93578f6b5a2ab897c465690"))
  "The SHA-256 of the build for each platform.")

(provide 'magit-git2-release)

;;; magit-git2-release.el ends here
