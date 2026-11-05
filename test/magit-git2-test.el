;;; magit-git2-test.el --- Differential tests of magit-git2  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kostafey <kostafey@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 2 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Run with test/run-tests.sh.  For every registered shape, every
;; example argument list of it, and every repository state -- the
;; fixture states of test/fixture.el plus the repositories listed in
;; MAGIT_GIT2_TEST_REPOS -- the emulation's (EXIT STDOUT STDERR) must
;; equal real git's.  A shape that refuses falls through to git, which
;; is always correct; the registry test makes sure each shape answers
;; at least once.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'magit)
(require 'magit-git2)
(require 'fixture)

(declare-function magit-git2--release "magit-git2-core")

;; Without the module every call falls through to git, and the tests
;; would compare git with itself.
(unless (magit-git2-core-available-p)
  (error "magit-git2: %s" magit-git2-core-error))

(setq ert-batch-print-length 3
      ert-batch-print-level 3
      ert-batch-backtrace-right-margin 60)

(defvar magit-git2-test-report
  (or (getenv "MAGIT_GIT2_TEST_REPORT")
      (expand-file-name "mismatches.txt" (magit-git2-fixture-root)))
  "File the mismatches are written to.")

(defun magit-git2-test--check (what reports)
  "Fail when REPORTS (strings) is not empty, writing them to a file.
WHAT names the test in the file."
  (when reports
    (with-temp-buffer
      (insert "## " what "\n\n" (string-join reports "\n\n") "\n\n")
      (write-region nil nil magit-git2-test-report t 'silent))
    (ert-fail (format "%s: %d mismatches, see %s"
                      what (length reports) magit-git2-test-report))))

(defvar magit-git2-test--dirs nil
  "The repository states: ((NAME . DIRECTORY) ...).")

(defun magit-git2-test--dirs ()
  "The fixture states (built on first use) and the extra repositories."
  (or magit-git2-test--dirs
      (setq magit-git2-test--dirs
            (append (if (file-exists-p (expand-file-name
                                        "main" (magit-git2-fixture-root)))
                        (magit-git2-fixture-dirs)
                      (magit-git2-fixture-build))
                    (mapcar (lambda (dir)
                              (cons (abbreviate-file-name dir)
                                    (file-name-as-directory dir)))
                            (split-string
                             (or (getenv "MAGIT_GIT2_TEST_REPOS") "")
                             path-separator t))))))

(defun magit-git2-test--git (args)
  "Run git with local ARGS the way `magit-process-git' does."
  (let ((log (make-temp-file "magit-git2-test-stderr"))
        (magit-git2-mode 'off))
    (unwind-protect
        (with-temp-buffer
          (let* ((exit (magit-process-git (list t log) args))
                 (stdout (buffer-string)))
            (list exit stdout
                  (with-temp-buffer
                    (let ((coding-system-for-read 'utf-8-unix))
                      (insert-file-contents log))
                    (buffer-string)))))
      (delete-file log))))

(defun magit-git2-test--compare (args)
  "Compare the emulation with git for ARGS in `default-directory'.
Return nil when they agree or the emulation refused, else a report."
  (let ((mine (condition-case nil
                  (magit-git2--dispatch args)
                ;; In use such a call goes to git, as on a refusal.
                (magit-git2-error nil)))
        (shape magit-git2--shape))
    (magit-git2--release)
    (when mine
      (let* ((theirs (magit-git2-test--git args))
             (mine* (if (eq (nth 2 mine) 'unknown)
                        (list (nth 0 mine) (nth 1 mine) (nth 2 theirs))
                      mine)))
        (unless (equal mine* theirs)
          (format "%s $ git %s\n  shape:    %s\n  git:      %S\n  emulated: %S"
                  (abbreviate-file-name default-directory)
                  (mapconcat #'shell-quote-argument args " ")
                  shape theirs mine))))))

(defvar magit-git2-test--tally nil
  "Per shape: (NAME ANSWERED REFUSED), from the last run.")

(defun magit-git2-test--run (shapes)
  "Compare SHAPES (names) in every state.
Return (MISMATCHES . ANSWERED), ANSWERED the shapes that answered."
  (setq magit-git2-test--tally (mapcar (lambda (n) (list n 0 0)) shapes))
  (let (mismatches answered)
    (pcase-dolist (`(,state . ,dir) (magit-git2-test--dirs))
      (let ((default-directory dir))
        (dolist (name shapes)
          (pcase-let ((`(,_ ,_ ,examples) (alist-get name magit-git2--shapes)))
            (dolist (args (funcall examples state))
              (let ((report (magit-git2-test--compare args))
                    (tally (assq name magit-git2-test--tally)))
                (if magit-git2--shape (cl-incf (nth 1 tally))
                  (cl-incf (nth 2 tally)))
                (when (and magit-git2--shape (not report))
                  (cl-pushnew magit-git2--shape answered))
                (when report (push report mismatches))))))))
    (cons (nreverse mismatches) answered)))

(ert-deftest magit-git2-test-differential ()
  "The emulation agrees with git for every example of every shape."
  :tags '(git2)
  (let ((result (magit-git2-test--run (mapcar #'car magit-git2--shapes))))
    (message "%-32s %8s %8s" "shape" "answered" "refused")
    (pcase-dolist (`(,name ,yes ,no) magit-git2-test--tally)
      (message "%-32s %8d %8d" name yes no))
    (magit-git2-test--check "differential" (car result))))

(ert-deftest magit-git2-test-every-shape-answers ()
  "Every registered shape has examples and answers some of them."
  :tags '(git2)
  (let* ((names (mapcar #'car magit-git2--shapes))
         (answered (cdr (magit-git2-test--run names))))
    (magit-git2-test--check
     "every-shape-answers"
     (mapcar (lambda (n) (format "%s never answered" n))
             (cl-remove-if (lambda (n) (memq n answered)) names)))))

(ert-deftest magit-git2-test-delivery ()
  "Magit's own helpers return the same with the emulation on and off."
  :tags '(git2)
  (let (reports)
   (pcase-dolist (`(,_ . ,dir)
                  (append (magit-git2-test--dirs)
                          ;; Magit passes abbreviated directories too;
                          ;; HOME is the fixture's home, next to main.
                          (list (cons "~" "~/../main/"))))
    (let ((default-directory dir))
      (dolist (call '((magit-git-string "rev-parse" "--show-toplevel")
                      (magit-git-string "rev-parse" "--verify" "HEAD")
                      (magit-git-str "symbolic-ref" "--short" "HEAD")
                      (magit-git-lines "log" "--format=%h %s" "-n5" "--")
                      (magit-git-items "config" "--list" "-z")
                      (magit-git-success "rev-parse" "@{upstream}")
                      (magit-git-exit-code "merge-base" "--is-ancestor"
                                           "HEAD" "HEAD")
                      (magit-git-config-p "magitgit2.global")
                      (magit-git-string-ng "rev-parse" "--git-dir")))
        (let* ((magit--refresh-cache nil)
               (off (let ((magit-git2-mode 'off)) (eval call t)))
               (on (let ((magit-git2-mode 'on)) (eval call t))))
          (unless (equal on off)
            (push (format "%s %S\n  off: %S\n  on:  %S" dir call off on)
                  reports))))))
   (magit-git2-test--check "delivery" (nreverse reports))))

(ert-deftest magit-git2-test-status-verify ()
  "Refreshing a status buffer in verify mode records no mismatch."
  :tags '(git2)
  (when-let* ((buffer (get-buffer magit-git2-mismatches-buffer)))
    (kill-buffer buffer))
  (let ((magit-git2-mode 'verify))
    (pcase-dolist (`(,state . ,dir) (magit-git2-test--dirs))
      (unless (member state '("main/sub" "origin.git"))
        (let ((default-directory dir))
          (magit-status-setup-buffer dir)
          (magit-refresh)))))
  (magit-git2-test--check
   "status-verify"
   (when-let* ((b (get-buffer magit-git2-mismatches-buffer)))
     (with-current-buffer b (split-string (buffer-string) "^\\* " t)))))

(defmacro magit-git2-test--in-refresh (&rest body)
  "Run BODY the way a section runs in a buffer refresh."
  (declare (indent 0))
  `(let ((magit--refreshing-buffer-p t)
         (magit--refresh-start-time (current-time))
         (magit--refresh-cache (list (cons 0 0))))
     ,@body))

(ert-deftest magit-git2-test-refresh-memo ()
  "What a buffer refresh has read lasts for that refresh alone."
  :tags '(git2)
  (let* ((dirs (magit-git2-test--dirs))
         (main (cdr (assoc "main" dirs)))
         (sub (cdr (assoc "main/sub" dirs)))
         (ref "refs/heads/memo-test")
         (args (list "rev-parse" "--verify" "--quiet" ref))
         (default-directory main)
         (exit (lambda ()
                 (prog1 (car (magit-git2--dispatch args))
                   (magit-git2--release))))
         (cdup (lambda (dir)
                 (let ((default-directory dir))
                   (cadr (magit-git2--dispatch
                          '("rev-parse" "--show-cdup")))))))
    (unwind-protect
        (progn
          (magit-git2-test--in-refresh
            (should (equal (funcall exit) 1))
            (magit-git2-fixture--git main "update-ref" ref "HEAD")
            (should (equal (funcall exit) 1))
            ;; The memos are per directory.
            (should (equal (funcall cdup main) "\n"))
            (should (equal (funcall cdup sub) "../\n")))
          (magit-git2-test--in-refresh
            (should (equal (funcall exit) 0)))
          ;; `magit-run-git' binds the cache around a command that writes.
          (let ((magit--refresh-cache (list (cons 0 0))))
            (should (equal (funcall exit) 0))
            (magit-git2-fixture--git main "update-ref" "-d" ref)
            (should (equal (funcall exit) 1))))
      (magit-git2-fixture--git main "update-ref" "-d" ref))))

(defun magit-git2-test--clean-repo ()
  "A new repository with one committed file and no changes."
  (magit-git2-test--dirs)               ; the global config names the author
  (let ((dir (file-name-as-directory
              (make-temp-file (expand-file-name
                               "clean-" (magit-git2-fixture-root))
                              t))))
    (magit-git2-fixture--git dir "init" "-q")
    (magit-git2-fixture--write (expand-file-name "file" dir) "text\n")
    (magit-git2-fixture--git dir "add" "file")
    (magit-git2-fixture--commit dir "first")
    dir))

(ert-deftest magit-git2-test-update-index ()
  "A status refresh does without `update-index --refresh' where it can."
  :tags '(git2)
  (let* ((default-directory (magit-git2-test--clean-repo))
         (dir default-directory)
         (magit-git2-mode 'on)
         ;; Started ahead, they would refresh the index themselves.
         (magit-git2--ahead-commands nil)
         ;; git compares whole seconds of the modification time.
         (shift 0)
         (touch (lambda ()
                  (setq shift (+ shift 10))
                  (set-file-times "file" (time-add (current-time) shift))))
         (stale-p (lambda ()
                    (/= 0 (call-process "git" nil nil nil
                                        "diff-files" "--quiet"))))
         (run (lambda ()
                (magit-process-git nil '("update-index" "--refresh"))))
         (run-in-refresh (lambda ()
                           (let ((magit--refreshing-buffer-p t))
                             (funcall run)))))
    ;; Outside a refresh, git runs.
    (funcall touch)
    (should (funcall stale-p))
    (funcall run)
    (should-not (funcall stale-p))
    ;; In one it does not, and Magit gets a success.
    (funcall touch)
    (should (equal (funcall run-in-refresh) 0))
    (should (funcall stale-p))
    ;; Without a `git diff' that writes the index back, git runs.
    (let ((magit-git-global-arguments
           (cons "--no-optional-locks" magit-git-global-arguments)))
      (funcall run-in-refresh))
    (should-not (funcall stale-p))
    (funcall touch)
    (magit-git2-fixture--git dir "config" "diff.autoRefreshIndex" "false")
    (funcall run-in-refresh)
    (magit-git2-fixture--git dir "config" "--unset" "diff.autoRefreshIndex")
    (should-not (funcall stale-p))
    ;; Verify mode leaves all to git.
    (funcall touch)
    (let ((magit-git2-mode 'verify))
      (funcall run-in-refresh))
    (should-not (funcall stale-p))
    ;; A real refresh shows nothing false and leaves the index fresh.
    (funcall touch)
    (with-current-buffer (magit-status-setup-buffer dir)
      (should-not (magit-get-section '((unstaged) (status))))
      (should-not (funcall stale-p)))))

(defun magit-git2-test--ahead-count ()
  "How many calls git commands started ahead have answered."
  (cl-loop for (_ . counters) in (alist-get 'commands (magit-git2-stats-alist))
           sum (alist-get 'ahead counters)))

(defun magit-git2-test--leftovers ()
  "The processes and buffers of commands started ahead that remain."
  (append (cl-remove-if-not
           (lambda (p) (string-prefix-p "magit-git2" (process-name p)))
           (process-list))
          (cl-remove-if-not
           (lambda (b) (string-prefix-p " *magit-git2 " (buffer-name b)))
           (buffer-list))))

(defun magit-git2-test--settle ()
  "Wait until the commands started ahead have been freed."
  (with-timeout (10 (ert-fail "commands started ahead were not freed"))
    (while (magit-git2-test--leftovers)
      (accept-process-output nil 0.01))))

(ert-deftest magit-git2-test-ahead ()
  "Commands started ahead give what they give one after the other."
  :tags '(git2)
  (let* ((dir (magit-git2-test--clean-repo))
         (default-directory dir)
         (refresh (lambda ()
                    (with-current-buffer (magit-status-setup-buffer dir)
                      (magit-refresh)
                      (buffer-substring-no-properties
                       (point-min) (point-max)))))
         (coding-system-for-write 'latin-1-unix))
    ;; Staged, unstaged, not valid UTF-8, untracked.
    (write-region "staged\n" nil "staged" nil 'silent)
    (magit-git2-fixture--git dir "add" "staged")
    (write-region "caf\xe9\n" nil "file" nil 'silent)
    (write-region "new\n" nil "untracked" nil 'silent)
    (let* ((serial (let ((magit-git2-mode 'off)) (funcall refresh)))
           (magit-git2-mode 'on)
           (before (magit-git2-test--ahead-count))
           ;; It redisplays, showing the half built buffer.
           (deleted nil)
           (note (lambda (&rest _)
                   (when magit--refreshing-buffer-p
                     (setq deleted t))))
           (ahead (unwind-protect
                      (progn
                        (advice-add 'delete-process :before note)
                        (funcall refresh))
                    (advice-remove 'delete-process note))))
      (should (> (magit-git2-test--ahead-count) before))
      (should (equal ahead serial))
      (should-not deleted)
      (magit-git2-test--settle))))

(ert-deftest magit-git2-test-ahead-output ()
  "A command started ahead keeps its exit code, stdout and stderr apart."
  :tags '(git2)
  (let ((default-directory (magit-git2-test--clean-repo))
        (finish (lambda (&rest args)
                  (magit-git2--finish-process
                   (magit-git2--start-process
                    (cons magit-git-global-arguments args))))))
    (should (equal (funcall finish "rev-parse" "--is-bare-repository")
                   '(0 "false\n" "")))
    (should (equal (funcall finish "rev-parse" "--verify" "no-such-ref")
                   '(128 "" "fatal: Needed a single revision\n")))
    ;; Long over by the time Magit asks.
    (let ((process (magit-git2--start-process
                    (cons magit-git-global-arguments
                          '("rev-parse" "--is-bare-repository")))))
      (sleep-for 0.2)
      (should (equal (magit-git2--finish-process process)
                     '(0 "false\n" ""))))
    (magit-git2-test--settle)))

(ert-deftest magit-git2-test-ahead-unused ()
  "A command nothing asks for ends by itself and is not started again."
  :tags '(git2)
  (let* ((dir (magit-git2-test--clean-repo))
         (default-directory dir)
         (magit-git2-mode 'on)
         (command (cons magit-git-global-arguments '("diff" "--stat")))
         (magit-git2--ahead-commands (list command))
         (magit-git2--ahead-processes nil)
         (magit--refreshing-buffer-p t)
         (magit--refresh-start-time (current-time)))
    (should (equal (magit-process-git nil '("update-index" "--refresh")) 0))
    (should (= (length magit-git2--ahead-processes) 1))
    ;; Its output belongs to this refresh and no other.
    (let ((magit--refresh-start-time (current-time)))
      (should-not (magit-git2--take-ahead '("diff" "--stat"))))
    (magit-git2--drop-ahead)
    (should-not magit-git2--ahead-processes)
    (should-not magit-git2--ahead-commands)
    (magit-git2-test--settle)
    (should-not (file-exists-p ".git/index.lock"))))

(ert-deftest magit-git2-test-lisp-error ()
  "A Lisp error turns the emulation off and git answers."
  :tags '(git2)
  (let* ((default-directory (magit-git2-test--clean-repo))
         (check
          (lambda (mode function args)
            (let* ((magit-git2-mode mode)
                   (magit-git2--auto-disables 0)
                   (magit--refreshing-buffer-p t)
                   (magit--refresh-start-time (current-time))
                   (magit-git2--status-refresh magit--refresh-start-time)
                   (theirs (magit-git2-test--git args))
                   (mine (cl-letf (((symbol-function function)
                                    (lambda (&rest _) (error "Failure"))))
                           (with-temp-buffer
                             (let ((exit (magit-process-git '(t nil) args)))
                               (list exit (buffer-string)))))))
              (should (equal mine (list (car theirs) (cadr theirs))))
              (should (eq magit-git2-mode 'off))
              (should (= magit-git2--auto-disables 1))))))
    (dolist (function '(magit-git2--usable-p magit-git2--redundant-p
                        magit-git2--emulate))
      (funcall check 'on function '("rev-parse" "--show-cdup")))
    (funcall check 'on 'magit-git2--deliver '("rev-parse" "--show-cdup"))
    (funcall check 'on 'magit-git2--take-ahead '("status" "--porcelain"))
    (funcall check 'verify 'magit-git2--usable-p '("rev-parse" "--show-cdup"))
    (funcall check 'verify 'magit-git2--count '("rev-parse" "--show-cdup"))))

(ert-deftest magit-git2-test-printed-paths ()
  "Paths are printed as the module spells them, and only then."
  :tags '(git2)
  (let* ((default-directory (cdr (assoc "main/sub" (magit-git2-test--dirs))))
         (ask (lambda (option)
                (cadr (magit-git2--dispatch (list "rev-parse" option))))))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'magit-git2--final-path)
                     (lambda (path) (concat "C:/Real/" path)))
                    ;; On Windows it lowers the drive letter.
                    ((symbol-function 'directory-file-name) #'downcase))
            (dolist (option '("--show-toplevel" "--git-dir"))
              (should (string-prefix-p "C:/Real/" (funcall ask option)))))
          (pcase-dolist (`(,path . ,printed) '(("/repo/" . "/repo")
                                               ("/" . "/")
                                               ("C:/repo" . "C:/repo")
                                               ("C:/" . "C:/")))
            (cl-letf (((symbol-function 'magit-git2--final-path)
                       (lambda (_) path)))
              (should (equal (magit-git2--printed-path "any") printed))))
          ;; A module that cannot tell, or is too old to, leaves it to git.
          (cl-letf (((symbol-function 'magit-git2--final-path) #'ignore))
            (should-not (funcall ask "--show-toplevel")))
          (cl-letf (((symbol-function 'magit-git2--final-path) nil))
            (should-not (funcall ask "--git-dir"))))
      (magit-git2--release))))

;;; Mismatch warnings

(ert-deftest magit-git2-test-first-difference ()
  "The first difference of the output is found, if there is one."
  :tags '(git2)
  (pcase-dolist (`(,git ,emulated ,difference)
                 '(("a\nb\n" "a\nc\n" (2 "b" "c"))
                   ("a\n" "a\nb\n" (2 "" "b"))
                   ("a\nb" "a" (2 "b" nil))
                   ("a\n" "a\n" nil)))
    (should (equal (magit-git2--first-difference (list 0 git nil)
                                                 (list 1 emulated nil))
                   difference))))

(ert-deftest magit-git2-test-mismatch-warning ()
  "A mismatch warns once per shape, only after the refresh, and stays recorded."
  :tags '(git2)
  (let* ((dir (magit-git2-test--clean-repo))
         (default-directory dir)
         (magit-git2-mode 'verify)
         (magit-git2--warned-shapes nil)
         (magit-git2-mismatches-buffer " *magit-git2-test-mismatches*")
         (settle (lambda ()
                   (dotimes (_ 5) (accept-process-output nil 0.01))))
         warnings)
    (cl-letf (((symbol-function 'display-warning)
               (lambda (type text &rest _) (push (cons type text) warnings)))
              ((symbol-function 'magit-git2--emulate)
               (lambda (args _destination)
                 (setq magit-git2--shape (intern (car args)))
                 (list 0 (make-string 5000 ?x) nil))))
      (unwind-protect
          (progn
            (magit-status-setup-buffer dir)
            (magit-refresh)
            (should-not warnings)
            (funcall settle)
            (let ((shapes (length magit-git2--warned-shapes)))
              (should (> shapes 1))
              (should (= (length warnings) shapes))
              (magit-refresh)
              (funcall settle)
              (should (= (length warnings) shapes)))
            (pcase-dolist (`(,type . ,text) warnings)
              (should (eq type 'magit-git2))
              (should (string-search "magit-git2-show-mismatches" text))
              (should (< (length text) 300)))
            (with-current-buffer magit-git2-mismatches-buffer
              (should (string-search "first difference at line"
                                     (buffer-string))))
            (setq warnings nil magit-git2--warned-shapes nil)
            (magit-git2--warn-mismatch '("config" "x") nil)
            (funcall settle)
            (should (string-search "exit code or stderr" (cdar warnings))))
        (magit-git2--release)
        (kill-buffer magit-git2-mismatches-buffer)))))

;;; Setup

(ert-deftest magit-git2-test-no-module ()
  "Without the module the mode stands, and calls go to git and just work."
  :tags '(git2)
  (let* ((dir (magit-git2-test--clean-repo))
         (default-directory dir)
         (head (string-trim (shell-command-to-string "git rev-parse HEAD"))))
    (cl-letf (((symbol-function 'magit-git2-core-available-p) #'ignore))
      (dolist (mode '(on verify))
        (let ((magit-git2-mode mode))
          (should (equal (magit-git-string "rev-parse" "HEAD") head))
          (should (eq magit-git2-mode mode)))))))

(ert-deftest magit-git2-test-system-config ()
  "The system config is set up once the module is there, by the environment."
  :tags '(git2)
  (let ((magit-git2--system-config-ok nil)
        (magit-git2--initial-environment nil)
        (from-git 0)
        paths)
    (cl-letf (((symbol-function 'magit-git2-set-system-config-from-git)
               (lambda (&rest _) (cl-incf from-git)))
              ((symbol-function 'magit-git2--set-system-config-path)
               (lambda (dir) (push dir paths))))
      (pcase-dolist (`(,type ,file ,ok ,times ,dirs)
                     '((gnu/linux nil t 0 nil)
                       (windows-nt nil t 1 nil)
                       (windows-nt "/etc/gitconfig" t 0 ("/etc/"))
                       (gnu/linux "/etc/other" nil 0 nil)))
        (let ((system-type type)
              (magit-git2--initial-environment
               (list (cons "GIT_CONFIG_SYSTEM" file))))
          (setq from-git 0 paths nil)
          (magit-git2--init-system-config)
          (should (eq (and magit-git2--system-config-ok t) ok))
          (should (= from-git times))
          (should (equal paths dirs)))))))

(ert-deftest magit-git2-test-loaded-hook ()
  "A module that arrives late makes the emulation usable."
  :tags '(git2)
  (should (memq #'magit-git2--init-system-config magit-git2-core-loaded-hook))
  (let ((magit-git2--system-config-ok nil)
        (default-directory (magit-git2-test--clean-repo)))
    (should-not (magit-git2--usable-p nil))
    (run-hooks 'magit-git2-core-loaded-hook)
    (should (magit-git2--usable-p nil))))

;;; Download

(defmacro magit-git2-test--with-release (&rest body)
  "Run BODY with no module loaded or built, and a release to download.
BODY sees the release's ASSET, the FILE the module downloads to, the
files `module-load' got in LOADED and the hook's runs in RAN."
  (declare (indent 0))
  `(let* ((root (make-temp-file "magit-git2-release" t))
          (platform (magit-git2-core--platform))
          (asset (expand-file-name
                  (format "t1/magit-git2-core-%s%s" platform
                          module-file-suffix)
                  root))
          (magit-git2-core-directory (expand-file-name "modules/" root))
          (magit-git2-core-release-url (concat "file://" root))
          (magit-git2-release-tag "t1")
          (magit-git2-release-sha256
           (list (cons platform (secure-hash 'sha256 "build"))))
          (magit-git2-core-error "not loaded")
          (magit-git2-core--download nil)
          (file (magit-git2-core--released-file))
          (loaded nil)
          (ran 0)
          (magit-git2-core-loaded-hook (list (lambda () (cl-incf ran)))))
     (ignore file)
     (make-directory (file-name-directory asset))
     (write-region "build" nil asset nil 'silent)
     (cl-letf (((symbol-function 'magit-git2-core-available-p)
                (lambda () (and loaded t)))
               ((symbol-function 'module-load)
                (lambda (file) (push file loaded))))
       (unwind-protect (progn ,@body)
         (delete-directory root t)))))

(defun magit-git2-test--await-download ()
  "Wait until the download has been dealt with."
  (with-timeout (10 (ert-fail "the download does not end"))
    (while (buffer-live-p (process-buffer magit-git2-core--download))
      (accept-process-output nil 0.01))))

(defun magit-git2-test--downloaded ()
  "The names of the files in the directory of the downloads."
  (directory-files magit-git2-core-directory nil "\\`[^.]"))

(ert-deftest magit-git2-test-download ()
  "The release build lands beside no other, says so, and is put to use."
  :tags '(git2)
  (magit-git2-test--with-release
    (make-directory magit-git2-core-directory)
    (write-region "" nil (expand-file-name "magit-git2-core-0"
                                           magit-git2-core-directory)
                  nil 'silent)
    (ert-with-message-capture messages
      (magit-git2-core-ensure)
      ;; Magit goes on meanwhile.
      (should (= ran 0))
      (should (string-search "downloading the module" messages))
      (magit-git2-test--await-download)
      (should (string-search "the module is ready" messages)))
    (should (= ran 1))
    (should (equal loaded (list file)))
    (should-not magit-git2-core-error)
    (should (equal (magit-git2-core--file-sha256 file)
                   (secure-hash 'sha256 "build")))
    (should (equal (magit-git2-test--downloaded)
                   (list (file-name-nondirectory file))))))

(ert-deftest magit-git2-test-download-refused ()
  "A file with another hash is neither kept nor loaded."
  :tags '(git2)
  (magit-git2-test--with-release
    (write-region "tampered" nil asset nil 'silent)
    (ert-with-message-capture messages
      (magit-git2-core-ensure)
      (magit-git2-test--await-download)
      (should (string-search "Magit runs git as usual" messages)))
    (should (string-search "SHA-256" magit-git2-core-error))
    (should-not loaded)
    (should (= ran 0))
    (should-not (magit-git2-test--downloaded))))

(ert-deftest magit-git2-test-download-failed ()
  "A failed download tells why and leaves nothing; a later try works."
  :tags '(git2)
  (magit-git2-test--with-release
    (let ((build (expand-file-name "build" root)))
      (rename-file asset build)
      (magit-git2-core-ensure)
      (magit-git2-test--await-download)
      (should (string-search "curl:" magit-git2-core-error))
      (should (string-search (magit-git2-core--url) magit-git2-core-error))
      (should-not loaded)
      (should-not (magit-git2-test--downloaded))
      (rename-file build asset))
    (magit-git2-core-ensure)
    (magit-git2-test--await-download)
    (should (equal loaded (list file)))
    (should (= ran 1))))

(ert-deftest magit-git2-test-no-download ()
  "Nothing is downloaded with a module file at hand, or with no build."
  :tags '(git2)
  (magit-git2-test--with-release
    (cl-flet ((file-only (lambda ()
                           (magit-git2-core-load)
                           (magit-git2-core-ensure)
                           (should-not magit-git2-core--download)
                           (should (= (length loaded) 1))
                           (prog1 (car loaded) (setq loaded nil ran 0)))))
      (make-directory magit-git2-core-directory)
      (write-region "" nil file nil 'silent)
      (should (equal (file-only) file))
      ;; A module put in place by hand goes first.
      (write-region "" nil (magit-git2-core--own-file) nil 'silent)
      (should (equal (file-only) (magit-git2-core--own-file)))
      (delete-file (magit-git2-core--own-file))
      ;; Downloaded anew, a file that does not load would not load either.
      (cl-letf (((symbol-function 'module-load)
                 (lambda (_) (error "Too old a glibc"))))
        (magit-git2-core-load)
        (magit-git2-core-ensure)
        (should-not magit-git2-core--download)
        (should (string-search "glibc" magit-git2-core-error)))
      (delete-file file))
    (let ((magit-git2-core-download nil))
      (magit-git2-core-ensure)
      (should-not magit-git2-core--download))
    (let ((magit-git2-release-sha256 nil))
      (magit-git2-core-ensure)
      (should-not magit-git2-core--download))
    (cl-letf (((symbol-function 'executable-find) #'ignore))
      (magit-git2-core-ensure)
      (should-not magit-git2-core--download)
      (should (string-search "no curl" magit-git2-core-error)))))

(ert-deftest magit-git2-test-platform ()
  "The system picks the release build, and only a build that runs on it."
  :tags '(git2)
  (pcase-dolist (`(,type ,configuration ,platform)
                 '((windows-nt "x86_64-w64-mingw32" "windows-x86_64")
                   (gnu/linux "x86_64-pc-linux-gnu" "linux-x86_64")
                   (gnu/linux "x86_64-suse-linux" "linux-x86_64")
                   (gnu/linux "x86_64-alpine-linux-musl" nil)
                   (gnu/linux "aarch64-unknown-linux-gnu" nil)
                   (darwin "x86_64-apple-darwin23.6.0" nil)))
    (let ((system-type type)
          (system-configuration configuration))
      (should (equal (magit-git2-core--platform) platform)))))

(provide 'magit-git2-test)

;;; magit-git2-test.el ends here
