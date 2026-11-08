;;; magit-git2-core.el --- Load the magit-git2 dynamic module  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kostafey <kostafey@gmail.com>

;; Author: Kostafey <kostafey@gmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 2 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Loads the module from `magit-git2-core-directory', whatever installed
;; this Lisp: magit-git2-core.so (.dll on Windows) put there by hand,
;; else the release build, which `magit-git2-core-ensure' downloads.
;; Requiring this feature never fails: when the module cannot be loaded,
;; `magit-git2-core-error' says why and `magit-git2-core-available-p' is
;; nil.
;;
;; A download is checked against the SHA-256 in magit-git2-release.el,
;; which CI commits with every release.  So a Lisp commit names exact
;; builds; the hash in the file's name also lets a new build land beside
;; a loaded one, which Windows would not let it replace.

;;; Code:

(require 'subr-x)
(require 'magit-git2-release)

(declare-function magit-git2--release "magit-git2-core")

(defgroup magit-git2 nil
  "Answer Magit's read-only git queries in-process."
  :group 'magit-extensions)

(defcustom magit-git2-core-directory (locate-user-emacs-file "magit-git2/")
  "Where the module lives.
A magit-git2-core.so (.dll on Windows) put here by hand has precedence
over the release build, which goes here too."
  :type 'directory)

(defcustom magit-git2-core-download t
  "Whether to download the release build when no module is at hand."
  :type 'boolean)

(defcustom magit-git2-core-release-url
  "https://github.com/kostafey/magit-git2/releases/download"
  "The URL the releases are under."
  :type 'string)

(defvar magit-git2-core-loaded-hook nil
  "Run once the module is loaded, which a download can delay.
See `magit-git2-core-ensure'.")

(defvar magit-git2-core-error nil
  "Why the module did not load, or nil.")

(defvar magit-git2-core--loaded-file nil
  "The file the module was last loaded from.")

(defvar magit-git2-core--download nil
  "The process of the last download.")

(defun magit-git2-core-available-p ()
  "Return non-nil when the module is loaded."
  (featurep 'magit-git2-core-module))

(defun magit-git2-core--platform ()
  "This system's name among the release builds, or nil if it has none."
  (when (string-prefix-p "x86_64-" system-configuration)
    (pcase system-type
      ('windows-nt "windows-x86_64")
      ('gnu/linux (unless (string-search "musl" system-configuration)
                    "linux-x86_64")))))

(defun magit-git2-core--sha256 ()
  "The pinned SHA-256 of the release build for this system, or nil."
  (cdr (assoc (magit-git2-core--platform) magit-git2-release-sha256)))

(defun magit-git2-core--released-file ()
  "The file of the release build for this system, or nil if it has none."
  (when-let* ((sha256 (magit-git2-core--sha256)))
    (expand-file-name
     (concat "magit-git2-core-" (substring sha256 0 12) module-file-suffix)
     magit-git2-core-directory)))

(defun magit-git2-core--own-file ()
  "The file of a module put in place by hand."
  (expand-file-name (concat "magit-git2-core" module-file-suffix)
                    magit-git2-core-directory))

(defun magit-git2-core--file ()
  "The file to load the module from."
  (let ((own (magit-git2-core--own-file)))
    (or (and (file-exists-p own) own)
        (magit-git2-core--released-file)
        own)))

(defun magit-git2-core-load (&optional file)
  "Load the module from FILE (default `magit-git2-core--file').
Return non-nil on success; on failure set `magit-git2-core-error'."
  (let ((file (or file (magit-git2-core--file))))
    (setq magit-git2-core-error
          (cond ((not (and (fboundp 'module-load) module-file-suffix))
                 "this Emacs has no dynamic module support")
                ((not (file-exists-p file))
                 (format "%s does not exist; see the README" file))
                ((condition-case err
                     (progn (module-load file)
                            (setq magit-git2-core--loaded-file file)
                            nil)
                   (error (error-message-string err))))))
    (null magit-git2-core-error)))

(defun magit-git2-core-reload ()
  "Load a fresh copy of the module, replacing the loaded functions.
Emacs never unloads a module, and loading the same file again does
nothing, so this loads a temporary copy of `magit-git2-core--file'."
  (let ((copy (make-temp-file "magit-git2-core" nil module-file-suffix)))
    (copy-file (magit-git2-core--file) copy t)
    (when (featurep 'magit-git2-core-module)
      (magit-git2--release))
    (prog1 (magit-git2-core-load copy)
      ;; The loaded copy stays mapped; on Windows it cannot be deleted.
      (ignore-errors (delete-file copy)))))

(defun magit-git2-core--url ()
  "The URL of the release build for this system."
  (format "%s/%s/magit-git2-core-%s%s" magit-git2-core-release-url
          magit-git2-release-tag (magit-git2-core--platform)
          module-file-suffix))

(defun magit-git2-core--fail (reason)
  "Report that the module stays out of use because of REASON."
  (setq magit-git2-core-error reason)
  (message "magit-git2: %s; Magit runs git as usual" reason))

(defun magit-git2-core--file-sha256 (file)
  "The SHA-256 of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun magit-git2-core--install (process part file)
  "Make PART, downloaded by PROCESS, the module FILE, and load it."
  (unless (zerop (process-exit-status process))
    (error "%s" (with-current-buffer (process-buffer process)
                  (string-trim (buffer-string)))))
  (unless (equal (magit-git2-core--file-sha256 part)
                 (magit-git2-core--sha256))
    (error "It is not the build with the pinned SHA-256"))
  (rename-file part file t)
  (unless (magit-git2-core-load file)
    (error "%s" magit-git2-core-error))
  ;; On Windows a build some Emacs has loaded stays until a later try.
  (dolist (old (directory-files (file-name-directory file) t
                                "\\`magit-git2-core-"))
    (unless (equal old file)
      (ignore-errors (delete-file old)))))

(defun magit-git2-core--fetch ()
  "Download the release build in the background, then load it."
  (unless (process-live-p magit-git2-core--download)
    (let* ((file (magit-git2-core--released-file))
           (url (magit-git2-core--url))
           (default-directory (file-name-directory file)))
      (make-directory default-directory t)
      (let ((part (make-temp-file (concat file "."))))
        (message "magit-git2: downloading the module for %s; Magit runs \
git until it is ready" (magit-git2-core--platform))
        (setq magit-git2-core--download
              (make-process
               :name "magit-git2-download"
               :buffer (generate-new-buffer " *magit-git2-download*")
               :connection-type 'pipe
               :noquery t
               :command (list "curl" "--fail" "--silent" "--show-error"
                              "--location" "--connect-timeout" "30"
                              "--max-time" "300"
                              "--output" (file-name-nondirectory part) url)
               :sentinel
               (lambda (process _event)
                 (unless (process-live-p process)
                   (condition-case err
                       (progn
                         (magit-git2-core--install process part file)
                         (message "magit-git2: the module is ready")
                         (run-hooks 'magit-git2-core-loaded-hook))
                     (error
                      (ignore-errors (delete-file part))
                      (magit-git2-core--fail
                       (format "%s: %s" url (error-message-string err)))))
                   (kill-buffer (process-buffer process))))))))))

(defun magit-git2-core-ensure ()
  "Run `magit-git2-core-loaded-hook' once the module is loaded.
With no module file at all, download the release build for this system
first.  That happens in the background, so Magit never waits for it:
it runs git until the module is there, and if the download fails."
  (cond ((magit-git2-core-available-p)
         (run-hooks 'magit-git2-core-loaded-hook))
        ((or (not magit-git2-core-download)
             (not module-file-suffix)
             (not (magit-git2-core--sha256))
             (file-exists-p (magit-git2-core--file)))
         (message "magit-git2: %s" magit-git2-core-error))
        ((not (executable-find "curl"))
         (magit-git2-core--fail
          (format "no curl to download %s" (magit-git2-core--url))))
        (t (condition-case err
               (magit-git2-core--fetch)
             (error (magit-git2-core--fail (error-message-string err)))))))

(unless (magit-git2-core-available-p)
  (magit-git2-core-load))

(provide 'magit-git2-core)

;;; magit-git2-core.el ends here
