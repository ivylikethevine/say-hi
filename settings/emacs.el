;; hi's emacs override, kept to the minimum that earns the `-q -l`: emacs's own
;; defaults, minus what litters a target you are only visiting. Nothing to
;; taste lives here - your own $_HI_CONFIG_DIR/emacs.el replaces this file
;; wholesale. Loaded with `-q`, so ~/.emacs.d/init.el on the target stays out
;; of it, and `-l` does not read a lockfile-free init directory either.

;; straight to the file: the splash screen and the *scratch* blurb are for a
;; first run on your own machine, not a `hi box file.txt`
(setq inhibit-startup-screen t
      initial-scratch-message nil)

;; leave no droppings in a remote tree: no file~ backups, no #file# autosaves,
;; no .#file lock symlinks that confuse rsync, git status, and make
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil)

;; a terminal editor: the menu bar is a wasted line without a mouse to click
;; it, and xterm-mouse-mode makes the mouse that is there work anyway
(menu-bar-mode -1)
(xterm-mouse-mode 1)

;; the small things every modern editor has on: matching parens, the column
;; in the mode line, and y/n where yes/no would be asked
(show-paren-mode 1)
(column-number-mode 1)
(defalias 'yes-or-no-p 'y-or-n-p)
