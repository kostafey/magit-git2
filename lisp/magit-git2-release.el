;;; magit-git2-release.el --- The released module builds  -*- lexical-binding: t -*-

;; This file is written by build/publish-release.sh.  Do not edit it.

;;; Code:

(defconst magit-git2-release-sources "765a59d23694328a44b774ce95a5ee10d2b992e7"
  "The key of the sources the released builds were made from.")

(defconst magit-git2-release-tag "magit-git2-core-f4ab584164b1"
  "The GitHub release holding the builds.")

(defconst magit-git2-release-sha256
  '(("windows-x86_64"
     . "6c9a4e453d7fae4ad4196e63b72eda14a7824e50acdfffa4014542c2f2ddc73c")
    ("linux-x86_64"
     . "6317ecb8cd6c28cf4c0940887c94524786887d30d93578f6b5a2ab897c465690"))
  "The SHA-256 of the build for each platform.")

(provide 'magit-git2-release)

;;; magit-git2-release.el ends here
