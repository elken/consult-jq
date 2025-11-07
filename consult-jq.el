;;; consult-jq.el --- Interactive JSON filtering with jq -*- lexical-binding: t -*-

;; Copyright (C) 2025 Your Name

;; Author: Ellis Kenyő <emacs@lkn.mozmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (consult "0.35"))
;; Keywords: convenience, tools, json, jq
;; URL: https://github.com/elken/consult-jq

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a Consult interface to filter JSON data using jq
;; with live preview as you type.  The results are syntax highlighted and
;; copying the result to the kill ring is as simple as pressing RET.

;; Usage:
;;
;; M-x consult-jq
;;
;; Shortcuts:
;; - `keys` - Show all object keys
;; - `items` - Show keys as separate items
;; - `values` - Show all values
;; - `types` - Show types of all values
;;
;; Requirements:
;; - The `jq` command-line tool must be installed

;;; Code:
(require 'consult)

(defgroup consult-jq nil
  "Interactive JSON filtering with jq."
  :group 'convenience)

(defcustom consult-jq-filter-alist
  '(("items" . "keys[]")
    ("types" . "map_values(type)"))
  "Alist mapping shorthand jq filters to their actual implementations.
Keys are the shorthand names, values are the actual jq filter expressions."
  :type '(alist :key-type string :value-type string)
  :group 'consult-jq)

(defcustom consult-jq-executable (executable-find "jq")
  "The path to jq, if it doesn't exist in variable `exec-path'."
  :type '(file :must-match t)
  :group 'consult-jq)

(defun consult-jq--process-filter (filter)
  "Process jq FILTER string, applying shorthand expansions if needed.
If FILTER matches a key in `consult-jq--filter-alist', use the corresponding value.
If FILTER starts with '.', use it as-is.
Otherwise, prepend '.' to FILTER."
  (or (cdr (assoc filter consult-jq--filter-alist))
      (if (string-prefix-p "." filter)
          filter
        (concat "." filter))))

(defun consult-jq--get-result (json filter)
  "Run jq with FILTER on JSON content and return the result.
Returns nil if FILTER is empty or if jq execution fails."
  (when (and filter (not (string-empty-p filter)))
    (with-temp-buffer
      (insert json)
      (condition-case nil
          (progn
            (call-process-region (point-min) (point-max)
                                consult-jq-executable t t nil (consult-jq--process-filter filter))
            (buffer-string))
        (error nil)))))

(defun consult-jq--highlight-json (json-string)
  "Apply syntax highlighting to JSON-STRING and return the highlighted text."
  (when json-string
    (with-temp-buffer
      (insert json-string)
      (if (featurep 'treesit)
        (json-ts-mode)
        (js-json-mode))
      (font-lock-ensure)
      (concat "\n" (buffer-string)))))

(defun consult-jq--buffer-is-json-p ()
  "Check if the current buffer contains valid JSON.
Returns nil if the buffer is empty."
  (and (not (zerop (buffer-size)))
       (condition-case nil
           (save-excursion
             (goto-char (point-min))
             (with-temp-buffer
               (insert-buffer-substring (current-buffer))
               (call-process-region (point-min) (point-max) consult-jq-executable t t nil ".")
               t))
         (error nil))))

;;;###autoload
(defun consult-jq ()
  "Filter JSON in current buffer using jq with live preview.
As you type a jq filter expression in the minibuffer, the filtered JSON
is shown with syntax highlighting.  Press RET to copy the result to the
kill ring.

Supports shorthand filters defined in `consult-jq-filter-alist'."
  (interactive)
  ;; Check if jq is installed
  (unless (file-exists-p consult-jq-executable)
    (user-error "Cannot find jq executable.  Please install jq"))

  (unless (consult-jq--buffer-is-json-p)
    (user-error "Buffer doesn't contain valid JSON"))

  (let* ((json (buffer-substring-no-properties (point-min) (point-max)))
         (latest-result nil))
    (let ((filter (consult--read
                   (consult--dynamic-collection
                    (lambda (input)
                      (unless (string-empty-p input)
                        (when-let* ((result (consult-jq--get-result json input)))
                          (setq latest-result result)
                          (list (propertize " " 'jq-result result))))))
                   :prompt "Enter jq query: "
                   :initial ""
                   :require-match nil
                   :sort nil
                   :annotate (lambda (cand)
                               (when-let ((result (get-text-property 0 'jq-result cand)))
                                 (consult-jq--highlight-json result))))))
      (when latest-result
        (kill-new latest-result)
        (message "jq result copied to kill ring")))))

;;;###autoload
(put 'consult-jq 'function-documentation '(consult-jq--function-docstring))

;; Add execute-extended-command-for-buffer support
(put 'consult-jq 'command-modes '(json-mode json-ts-mode js-json-mode))

;; Docstring function that includes any additional info
(defun consult-jq--function-docstring ()
  "Return the complete docstring for the `consult-jq' function."
  (concat
   "Filter JSON in current buffer using jq with live preview.
As you type a jq filter expression in the minibuffer, the filtered JSON
is shown with syntax highlighting. Press RET to copy the result to the
kill ring.

Supports shorthand filters defined in `consult-jq-filter-alist':
"
   (mapconcat
    (lambda (entry)
      (format "- '%s': %s" (car entry) (cdr entry)))
    consult-jq-filter-alist
    "\n")))

(provide 'consult-jq)

(provide 'consult-jq)
;;; consult-jq.el ends here
