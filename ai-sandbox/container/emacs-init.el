;; Minimal emacs-nox config for terminal compatibility.
;;
;; Root cause: xterm's terminfo maps \e[4~ (End in normal cursor mode) to
;; the [select] key event, not [end]. [select] is unbound, so fn+right does
;; nothing while fn+left (Home, \e[1~ → [home]) works fine. This overrides
;; the key at the input-decode layer so \e[4~ produces [end] like it should.
;;
;; NOTE: global-set-key with (kbd "\eOF") is WRONG — kbd treats \e as Meta,
;; so it binds M-O F, not the raw escape sequence ESC O F. We use
;; input-decode-map with strings instead, where \e is byte 27 (ESC).

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

;; ── Home/End key fix ──────────────────────────────────────────────
;;
;; The terminfo for xterm-256color defines:
;;   khome=\EOH (application mode)  kend=\EOF  (application mode)
;;   \e[1~  → [home]                \e[4~  → [select]  ← BUG: should be [end]
;;
;; Emacs already maps \eOH → [home] and \eOF → [end] via xterm-function-map.
;; The problem is \e[4~ → [select] (unbound) instead of [end]. We fix it
;; by adding the correct mapping in input-decode-map, which takes precedence.

(defun my/input-decode-remap (seq key)
  "Map escape sequence SEQ to key vector KEY in input-decode-map."
  (define-key input-decode-map seq key))

(my/input-decode-remap "\e[1~" [home])   ;; Home  (normal cursor mode)
(my/input-decode-remap "\e[4~" [end])     ;; End   (normal cursor mode) — THE FIX
(my/input-decode-remap "\e[7~" [home])    ;; Home  (rxvt variant)
(my/input-decode-remap "\e[8~" [end])     ;; End   (rxvt variant)
(my/input-decode-remap "\e[H"  [home])    ;; Home  (some terminals)
(my/input-decode-remap "\e[F"  [end])     ;; End   (some terminals)

;; Ensure the symbolic keys are bound to the right actions (redundant with
;; emacs defaults, but makes behavior consistent).
(global-set-key [home] 'move-beginning-of-line)
(global-set-key [end]  'move-end-of-line)
