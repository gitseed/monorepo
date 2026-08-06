;; Minimal emacs-nox config for terminal compatibility.
;; The main issue: fn+left/fn+right (Home/End) don't work in some terminal
;; emulators because the escape sequences they send aren't bound. This binds
;; all common variants so it works regardless of which terminal sends what.

;; Enable basic useful modes
(column-number-mode 1)
(show-paren-mode 1)
(global-display-line-numbers-mode 1)
(electric-pair-mode 1)
(delete-selection-mode 1)

;; Less clutter. GUI chrome modes can be absent from nox builds
;; (scroll-bar-mode is void on this one); an unguarded call aborts the
;; rest of this file — including the key bindings below.
(when (fboundp 'menu-bar-mode) (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))

;; Stop creating backup/~ files
(setq make-backup-files nil)
(setq auto-save-default nil)

;; Fix Home/End keys — bind all common terminal escape sequences
;; Normal mode: \e[1~ (Home), \e[4~ (End)
;; Application mode: \eOH (Home), \eOF (End)
;; Some terminals: \e[H (Home), \e[F (End)
(global-set-key (kbd "<home>") 'beginning-of-line)
(global-set-key (kbd "<end>") 'end-of-line)
(global-set-key (kbd "\e[1~") 'beginning-of-line)
(global-set-key (kbd "\e[4~") 'end-of-line)
(global-set-key (kbd "\eOH") 'beginning-of-line)
(global-set-key (kbd "\eOF") 'end-of-line)
(global-set-key (kbd "\e[H") 'beginning-of-line)
(global-set-key (kbd "\e[F") 'end-of-line)
