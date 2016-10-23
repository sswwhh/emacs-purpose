;;; window-purpose-core.el --- Core functions for Purpose -*- lexical-binding: t -*-

;; Copyright (C) 2015, 2016 Bar Magal

;; Author: Bar Magal
;; Package: purpose

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; This file contains core functions to be used by other parts of
;; package Purpose.

;;; Code:

(require 'window-purpose-configuration)

(defgroup purpose nil
  "purpose-mode configuration"
  :group 'windows
  :prefix "purpose-"
  :package-version "1.2")

(defcustom purpose-preferred-prompt 'auto
  "Which interface should Purpose use when prompting the user.
Available options are: 'auto - use IDO when `ido-mode' is enabled,
otherwise Helm when `helm-mode' is enabled, otherwise use default Emacs
prompts; 'ido - use IDO; 'helm - use Helm; 'vanilla - use default Emacs
prompts."
  :group 'purpose
  :type '(choice (const auto)
                 (const ido)
                 (const helm)
                 (const vanilla))
  :package-version "1.4")



;;; utilities

(defun purpose--buffer-major-mode (buffer-or-name)
  "Return the major mode of BUFFER-OR-NAME."
  (with-current-buffer buffer-or-name
    major-mode))

(defun purpose--dummy-buffer-name (purpose)
  "Create the name for a dummy buffer with purpose PURPOSE.
The name created is \"*pu-dummy-PURPOSE-*\".  e.g. for purpose 'edit,
the name is \"*pu-dummy-edit-*\"."
  (concat "*pu-dummy-" (symbol-name purpose) "*"))

(defun purpose--dummy-buffer-purpose (buffer-or-name)
  "Get buffer's purpose for dummy buffers.
A dummy buffer is a buffer with a name that starts with \"*pu-dummy-\"
and ends with \"*\".  For example, the buffer \"*pu-dummy-edit*\" is a
dummy buffer with the purpose 'edit."
  (let ((name (if (stringp buffer-or-name)
                  buffer-or-name
                (buffer-name buffer-or-name))))
    (when (and (string-prefix-p "*pu-dummy-" name)
               (string= "*" (substring name -1)))
      ;; 10 = (length "*pu-dummy-")
      (intern (substring name 10 -1)))))

(defun purpose-get-read-function (ido-method helm-method vanilla-method)
  "Get function to read something from the user.
Return value depends on `purpose-preferred-prompt', `ido-mode' and
`helm-mode'.
| `purpose-preferred-prompt' | `ido-mode' | `helm-mode' | method  |
|----------------------------+------------+-------------+---------|
| auto                       | t          | any         | ido     |
| auto                       | nil        | t           | helm    |
| auto                       | nil        | nil         | vanilla |
| ido                        | any        | any         | ido     |
| helm                       | any        | any         | helm    |
| vanilla                    | any        | any         | vanilla |"
  (cl-case purpose-preferred-prompt
    ('auto (cond ((bound-and-true-p ido-mode) ido-method)
                 ((bound-and-true-p helm-mode) helm-method)
                 (t vanilla-method)))
    ('ido ido-method)
    ('helm helm-method)
    (t vanilla-method)))

(defun purpose-get-completing-read-function ()
  "Intelligently choose a function to perform completing read.
The returned function is chosen according to the rules of
`purpose-get-read-function'.
ido method: `ido-completing-read'
helm method: `completing-read' (this is on purpose)
vanilla method: `completing-read'"
  (purpose-get-read-function #'ido-completing-read
                             #'completing-read
                             #'completing-read))

(defun purpose-get-read-file-name-function ()
  "Intelligently choose a function to read a file name.
The returned function is chosen according to the rules of
`purpose-get-read-function'.
ido method: `ido-read-file-name'
helm method: `read-file-name'
vanilla method: `read-file-name'"
  (purpose-get-read-function #'ido-read-file-name
                             #'read-file-name
                             #'read-file-name))



;;; simple purpose-finding operations for `purpose-buffer-purpose'
(defun purpose--buffer-purpose-mode (buffer-or-name mode-conf)
  "Return the purpose of buffer BUFFER-OR-NAME, as determined by its
mode and MODE-CONF.
MODE-CONF is a hash table mapping modes to purposes."
  (when (get-buffer buffer-or-name)     ; check if buffer exists
    (let* ((major-mode (purpose--buffer-major-mode buffer-or-name))
           (derived-modes (purpose--iter-hash #'(lambda (mode _purpose) mode)
                                              mode-conf))
           (derived-mode (apply #'derived-mode-p derived-modes)))
      (when derived-mode
        (gethash derived-mode mode-conf)))))

(defun purpose--buffer-purpose-name (buffer-or-name name-conf)
  "Return the purpose of buffer BUFFER-OR-NAME, as determined by its
exact name and NAME-CONF.
NAME-CONF is a hash table mapping names to purposes."
  (gethash (if (stringp buffer-or-name)
               buffer-or-name
             (buffer-name buffer-or-name))
           name-conf))

(defun purpose--buffer-purpose-name-regexp-1 (buffer-or-name regexp purpose)
  "Return purpose PURPOSE if buffer BUFFER-OR-NAME's name matches
regexp REGEXP."
  (when (string-match-p regexp (or (and (bufferp buffer-or-name)
                                        (buffer-name buffer-or-name))
                                   buffer-or-name))
    purpose))

(defun purpose--buffer-purpose-name-regexp (buffer-or-name regexp-conf)
  "Return the purpose of buffer BUFFER-OR-NAME, as determined by the
regexps matched by its name.
REGEXP-CONF is a hash table mapping name regexps to purposes."
  (car (remove nil
               (purpose--iter-hash
                #'(lambda (regexp purpose)
                    (purpose--buffer-purpose-name-regexp-1 buffer-or-name
                                                           regexp
                                                           purpose))
                regexp-conf))))

(defun purpose-buffer-purpose (buffer-or-name)
  "Get the purpose of buffer BUFFER-OR-NAME.
The purpose is determined by consulting these functions in this order:
1. `purpose--dummy-buffer-purpose'
2. `purpose-get-purpose'
If no purpose was determined, return `default-purpose'."
  (let ((buffer (get-buffer buffer-or-name)))
    (unless buffer
      (error "No such buffer: %S" buffer-or-name))
    (or (purpose--dummy-buffer-purpose buffer)
        (purpose-get-purpose buffer)
        default-purpose)))

(defun purpose-buffers-with-purpose (purpose)
  "Return a list of all existing buffers with purpose PURPOSE."
  (cl-remove-if-not #'(lambda (buffer)
                        (and (eql purpose (purpose-buffer-purpose buffer))
                             (not (minibufferp buffer))))
                    (buffer-list)))

(defun purpose-window-purpose (&optional window)
  "Get the purpose of window WINDOW.
The window's purpose is determined by its buffer's purpose.
WINDOW defaults to the selected window."
  (purpose-buffer-purpose (window-buffer window)))

(defun purpose-windows-with-purpose (purpose &optional frame)
  "Return a list of all live windows with purpose PURPOSE in FRAME.
FRAME defaults to the selected frame."
  (cl-remove-if-not #'(lambda (window)
                        (eql purpose (purpose-window-purpose window)))
                    (window-list frame)))

(defun purpose-get-all-purposes ()
  "Return a list of all known purposes."
  (delete-dups
   (append (list default-purpose)
           (mapcar (apply-partially #'nth 2) purpose--compiled-names)
           (mapcar (apply-partially #'nth 2) purpose--compiled-regexps)
           (mapcar (apply-partially #'nth 2) purpose--compiled-modes))))

(defun purpose-read-purpose (prompt &optional purposes require-match initial-output)
  "Read a purpose from the user.
PROMPT is the prompt to show the user.
PURPOSES is the available purposes the user can choose from, and
defaults to all defined purposes.
REQUIRE-MATCH and INITIAL-OUTPUT have the same meaning as in
`completing-read'."
  (let ((purpose-strings (mapcar #'symbol-name
                                 (or purposes (purpose-get-all-purposes))))
        (reader-function (purpose-get-completing-read-function)))
    (intern (funcall reader-function
                     prompt
                     purpose-strings
                     nil
                     require-match
                     initial-output))))


;;; purpose-aware buffer low-level functions
(defun purpose--get-buffer-create (purpose)
  "Get the first buffer with purpose PURPOSE.
If there is no such buffer, create a dummy buffer with purpose
PURPOSE."
  (or (car (purpose-buffers-with-purpose purpose))
      (get-buffer-create (purpose--dummy-buffer-name purpose))))

(defun purpose--set-window-buffer (purpose &optional window)
  "Make WINDOW display first buffer with purpose PURPOSE.
WINDOW must be a live window and defaults to the selected one.
If there is no buffer with purpose PURPOSE, create a dummy buffer with
purpose PURPOSE."
  (set-window-buffer window (purpose--get-buffer-create purpose)))



;;; window purpose dedication
(defun purpose-set-window-purpose-dedicated-p (window flag)
  "Set window parameter 'purpose-dedicated of window WINDOW to value
FLAG.
WINDOW defaults to the selected window."
  (set-window-parameter window 'purpose-dedicated flag))

(defun purpose-window-purpose-dedicated-p (&optional window)
  "Return non-nil if window WINDOW is dedicated to its purpose.
The result is determined by window parameter 'purpose-dedicated.
WINDOW defaults to the selected window."
  (window-parameter window 'purpose-dedicated))

(defun purpose-toggle-window-purpose-dedicated (&optional window)
  "Toggle window WINDOW's dedication to its purpose on or off.
WINDOW defaults to the selected window."
  (interactive)
  (let ((flag (not (purpose-window-purpose-dedicated-p window))))
    (purpose-set-window-purpose-dedicated-p window flag)
    (if flag
        (message "Window purpose is now dedicated")
      (message "Window purpose is not dedicated anymore"))
    (force-mode-line-update)
    flag))

;; not really purpose-related, but helpful for the user
;;;###autoload
(defun purpose-toggle-window-buffer-dedicated (&optional window)
  "Toggle window WINDOW's dedication to its current buffer on or off.
WINDOW defaults to the selected window."
  (interactive)
  (let* ((flag (not (window-dedicated-p window))))
    (set-window-dedicated-p window flag)
    (if flag
        (message "Window buffer is now dedicated")
      (message "Window buffer is not dedicated anymore"))
    (force-mode-line-update)
    flag))



;;; special window locations
(defun purpose-get-top-window (&optional frame)
  "Get FRAME's top window.
The top window is a window that takes up all the of the frame's width
and has no window above it.  If there is no top window, return nil."
  (let (top-window)
    (walk-window-tree #'(lambda (window)
                          (unless (or (window-in-direction 'left window)
                                      (window-in-direction 'right window)
                                      (window-in-direction 'above window)
                                      (not (window-in-direction 'below window)))
                            (setq top-window window)))
                      frame)
    top-window))

(defun purpose-get-bottom-window (&optional frame)
  "Get FRAME's bottom window.
The bottom window is a window that takes up all the of the frame's width
and has no window below it.  If there is no bottom window, return nil."
  (let (bottom-window)
    (walk-window-tree #'(lambda (window)
                          (unless (or (window-in-direction 'left window)
                                      (window-in-direction 'right window)
                                      (window-in-direction 'below window)
                                      (not (window-in-direction 'above window)))
                            (setq bottom-window window)))
                      frame)
    bottom-window))

(defun purpose-get-left-window (&optional frame)
  "Get FRAME's left window.
The left window is a window that takes up all the of the frame's
height and has no window to its left.  If there is no left window,
return nil."
  (let (left-window)
    (walk-window-tree #'(lambda (window)
                          (unless (or (window-in-direction 'above window)
                                      (window-in-direction 'below window)
                                      (window-in-direction 'left window)
                                      (not (window-in-direction 'right window)))
                            (setq left-window window)))
                      frame)
    left-window))

(defun purpose-get-right-window (&optional frame)
  "Get FRAME's right window.
The right window is a window that takes up all the of the frame's
height and has no window to its right.  If there is no right window,
return nil."
  (let (right-window)
    (walk-window-tree #'(lambda (window)
                          (unless (or (window-in-direction 'above window)
                                      (window-in-direction 'below window)
                                      (window-in-direction 'right window)
                                      (not (window-in-direction 'left window)))
                            (setq right-window window)))
                      frame)
    right-window))

(provide 'window-purpose-core)
;;; window-purpose-core.el ends here
