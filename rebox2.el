;;; rebox2.el --- Handling of comment boxes in various styles.

;; Filename: rebox2.el
;; Description:
;; Author: François Pinard
;;         Le Wang
;; Maintainer: Le Wang (lewang.emacs!!!gmayo.com remove exclamations, correct host, hint: google mail)

;; Copyright © 2011 Le Wang
;; Copyright © 1991,92,93,94,95,96,97,98,00 Progiciels Bourbeau-Pinard inc.
;; François Pinard <pinard@iro.umontreal.ca>, April 1991.

;; Created: Mon Jan 10 22:22:32 2011 (+0800)
;; Version: 0.2
;; Last-Updated: Fri Mar 11 13:50:11 2011 (+0800)
;;           By: Le Wang
;;     Update #: 212
;; URL: https://github.com/lewang/rebox2
;; Keywords:
;; Compatibility: GNU Emacs 23.2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:

                     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                     ;; Hi, I'm a box. My style is 525 ;;
                     ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Installation:
;;
;; 1. Add rebox2.el to a directory in your load-path.
;;
;; 2. Basic install - add to your ".emacs":
;;
;;     (require 'rebox2)
;;     (global-set-key [(meta q)] 'rebox-dwim-fill)
;;     (global-set-key [(shift meta q)] 'rebox-dwim-no-fill)
;;
;; 3. Full install - use `rebox-mode' in major-mode hooks:
;;
;;     ;; setup rebox for emacs-lisp
;;     (add-hook 'emacs-lisp-mode-hook (lambda ()
;;                                       (setq rebox-default-style 525)
;;                                       (setq rebox-no-box-comment-style 521)
;;                                       (rebox-mode 1)))
;;
;;    Default boxing styles should work for most programming modes, however,
;;    you may want to set the style you prefer for each major-mode like above
;;
;; ** minor-mode features
;;
;;   - auto-fill boxes
;;   - hype filladapt
;;   - motion (beginning-of-line, end-of-line) within box
;;   - S-return rebox-newline
;;   - kill/yank (within box) only text, not box borders
;;   - move box by using space, backspace / center with M-c
;;     - point has to be to the left of the border
;;
;;

;;; Ideas removed from François Pinard's original version
;;
;; * Building styles on top of each other.
;;

;;; Future improvement ideas:
;;
;; * allow mixed borders "-=-=-=-=-=-"
;; * optimize functions that modify the box contents so they don't unbuild and
;;   rebuild boxes all the time.
;; * style selection can use some kind of menu completion where all styles are
;;   presented and the user navigates
;; * space on the ww border moves whole box right, backspace moves box left
;;
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Change Log:
;;
;; * better error handling
;; * fixed a few boxing and unboxing corner cases where boxes were malformed
;; * changed how spaces are handled, rebox was very aggressive in removing
;;   white space in every direction, and even when it was keeping spaces, it
;;   would delete them and reinsert, which killed any markers.
;;
;;   now spaces are precious and never aggressively deleted.  Unboxing
;;   followed by boxing is idempotent.
;; * instead of parsing a current-prefix-arg in convoluted ways `rebox-engine'
;;   and most other functions now take key parameters
;; * increased the lengh of the box text in the box definition so that longer
;;   merged top and bottom borders can be specified.
;; * auto-filling
;; * minor-mode
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with this program; see the file COPYING.  If not, write to the Free
;; Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
;; 02110-1301, USA.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

;;,----
;;| François Pinard's original commentary (with non-relevant stuff removed)
;;`----


;; For comments held within boxes, it is painful to fill paragraphs, while
;; stretching or shrinking the surrounding box "by hand", as needed.  This
;; piece of GNU Emacs LISP code eases my life on this.  I find only fair,
;; while giving all sources for a package using such boxed comments, to also
;; give the means I use for nicely modifying comments.  So here they are!

;; The function `rebox-comment' automatically discovers the extent of the
;; boxed comments near the cursor, possibly refills the text, then adjusts the
;; comment box style.  When this command is executed, the cursor should be
;; within a comment, or else it should be between two comments, in which case
;; the command applies to the next comment.  The function `rebox-region' does
;; the same, except that it takes the current region as a boxed comment.  Both
;; commands obey numeric prefixes to add or remove a box, force a particular
;; box style, or to prevent refilling of text.  Without such prefixes, the
;; commands may deduce the current comment box style from the comment itself
;; so the style is preserved.  An unboxed comment is merely one of box styles.

;; A style is identified by three non-zero digits.  The _convention_ about
;; style numbering is such the the hundreds digit roughly represents the
;; programming language, the tens digit roughly represents a box quality (or
;; weight) and the units digit roughly a box type (or figure).  Language,
;; quality and types are collectively referred to as style attributes.

;;;; Convention:

;; A programming language is associated with comment delimiters.  Values are
;; 100 for none or unknown, 200 for `/*' and `*/' as in plain C, 300 for `//'
;; as in C++, 400 for `#' as in most scripting languages, 500 for `;' as in
;; LISP or assembler and 600 for `%' as in TeX or PostScript.

;; Box quality differs according to language. For unknown languages (100) or
;; for the C language (200), values are 10 for simple, 20 for rounded, and 30
;; or 40 for starred.  Simple quality boxes (10) use comment delimiters to
;; left and right of each comment line, and also for the top or bottom line
;; when applicable. Rounded quality boxes (20) try to suggest rounded corners
;; in boxes.  Starred quality boxes (40) mostly use a left margin of asterisks
;; or X'es, and use them also in box surroundings.  For all others languages,
;; box quality indicates the thickness in characters of the left and right
;; sides of the box: values are 10, 20, 30 or 40 for 1, 2, 3 or 4 characters
;; wide.  With C++, quality 10 is not useful, you should force 20 instead.

;; Box type values are 1 for fully opened boxes for which boxing is done
;; only for the left and right but not for top or bottom, 2 for half
;; single lined boxes for which boxing is done on all sides except top,
;; 3 for fully single lined boxes for which boxing is done on all sides,
;; 4 for half double lined boxes which is like type 2 but more bold,
;; or 5 for fully double lined boxes which is like type 3 but more bold.

;; The special style 221 is for C comments between a single opening `/*' and a
;; single closing `*/'.  The special style 111 deletes a box.

;;;; History:

;; I first observed rounded corners, as in style 223 boxes, in code from
;; Warren Tucker, a previous maintainer of the `shar' package.  Besides very
;; special files, I was carefully avoiding to use such boxes for real work,
;; as I found them much too hard to maintain.  My friend Paul Provost was
;; working at Taarna, a computer graphics place, which had boxes as part of
;; their coding standards.  He asked that we try something to get out of his
;; misery, and this how `rebox.el' was originally written.  I did not plan to
;; use it for myself, but Paul was so enthusiastic that I timidly started to
;; use boxes in my things, very little at first, but more and more as time
;; passed, yet not fully sure it was a good move.  Later, many friends
;; spontaneously started to use this tool for real, some being very serious
;; workers.  This finally convinced me that boxes are acceptable, after all.

(require 'newcomment)

(eval-when-compile
  (require 'filladapt nil t)
  (require 'cl))

;; Box templates.  First number is style, second is recognition weight.
(defconst rebox-templates

  ;; Generic programming language templates.  Adding 300 replaces
  ;; `?' by `/', for C++ style comments.  Adding 400 replaces `?' by
  ;; `#', for scripting languages.  Adding 500 replaces `?' by ';',
  ;; for LISP and assembler.  Adding 600 replaces `?' by `%', for
  ;; TeX and PostScript.

  '((10 114
        "?box123456")

    (11 115
        "? box123456")

    (12 215
        "? box123456 ?"
        "? --------- ?")

    (13 315
        "? --------- ?"
        "? box123456 ?"
        "? --------- ?")

    (14 415
        "? box123456 ?"
        "?????????????")

    (15 515
        "?????????????"
        "? box123456 ?"
        "?????????????")

    (20 124
        "??box123456")

    (21 125
        "?? box123456")

    (22 225
        "?? box123456 ??"
        "?? --------- ??")

    (23 325
        "?? --------- ??"
        "?? box123456 ??"
        "?? --------- ??")

    (24 425
        "?? box123456 ??"
        "???????????????")

    (25 525
        "???????????????"
        "?? box123456 ??"
        "???????????????")

    (30 134
        "???box123456")

    (31 135
        "??? box123456")

    (32 235
        "??? box123456 ???"
        "??? --------- ???")

    (33 335
        "??? --------- ???"
        "??? box123456 ???"
        "??? --------- ???")

    (34 435
        "??? box123456 ???"
        "?????????????????")

    (35 535
        "?????????????????"
        "??? box123456 ???"
        "?????????????????")

    (40 144
        "????box123456")

    (41 145
        "???? box123456")

    (42 245
        "???? box123456 ????"
        "???? --------- ????")

    (43 345
        "???? --------- ????"
        "???? box123456 ????"
        "???? --------- ????")

    (44 445
        "???? box123456 ????"
        "???????????????????")

    (45 545
        "???????????????????"
        "???? box123456 ????"
        "???????????????????")

    (50 154
        "?????box123456")

    (51 155
        "????? box123456")

    (60 164
        "??????box123456")

    (61 165
        "?????? box123456")

    ;;,----
    ;;| boxquote style for comments
    ;;`----

    (16 126
        "?,----"
        "?|box123456"
        "?`----")

    (17 226
        "?,----------"
        "?| box123456"
        "?`----------")

    (26 236
        "??,----"
        "??| box123456"
        "??`----")

    (27 136
        "??,----------"
        "??| box123456"
        "??`----------")


    ;;; Text mode (non programming) templates.

    (111 113
         "box123456")

    (112 213
         "| box123456 |"
         "+-----------+")

    (113 313
         "+-----------+"
         "| box123456 |"
         "+-----------+")

    (114 413
         "| box123456 |"
         "*===========*")

    (115 513
         "*===========*"
         "| box123456 |"
         "*===========*")

    (116 114
         "---------"
         "box123456"
         "---------")

    (121 123
         "| box123456 |")

    (122 223
         "| box123456 |"
         "`-----------'")

    (123 323
         ".-----------."
         "| box123456 |"
         "`-----------'")

    (124 423
         "| box123456 |"
         "\\===========/")

    (125 523
         "/===========\\"
         "| box123456 |"
         "\\===========/")

    ;; boxquote style

    (126 225
         ",----"
         "|box123456"
         "`----")

    (127 126
         ",----------"
         "| box123456"
         "`----------")

    (141 143
         "| box123456 ")

    (142 243
         "* box123456 *"
         "*************")

    (143 343
         "*************"
         "* box123456 *"
         "*************")

    (144 443
         "X box123456 X"
         "XXXXXXXXXXXXX")

    (145 543
         "XXXXXXXXXXXXX"
         "X box123456 X"
         "XXXXXXXXXXXXX")

    ;; C language templates.

    (211 118
         "/* box123456 */")

    (212 218
         "/* box123456 */"
         "/* --------- */")

    (213 318
         "/* --------- */"
         "/* box123456 */"
         "/* --------- */")

    (214 418
         "/* box123456 */"
         "/* ========= */")

    (215 518
         "/* ========= */"
         "/* box123456 */"
         "/* ========= */")

    (221 128
         "/*"
         "   box123456"
         " */")

    (222 228
         "/*          ."
         " | box123456 |"
         " `----------*/")

    (223 328
         "/*----------."
         "| box123456 |"
         "`----------*/")

    (224 428
         "/*          \\"
         "| box123456 |"
         "\\==========*/")

    (225 528
         "/*==========\\"
         "| box123456 |"
         "\\==========*/")

    (231 138
         "/*"
         " | box123456"
         " */")

    (232 238
         "/*             "
         " | box123456 | "
         " *-----------*/")

    (233 338
         "/*-----------* "
         " | box123456 | "
         " *-----------*/")

    (234 438
         "/* box123456 */"
         "/*-----------*/")

    (235 538
         "/*-----------*/"
         "/* box123456 */"
         "/*-----------*/")

    (241 148
         "/*"
         " * box123456"
         " */")

    (242 248
         "/*           * "
         " * box123456 * "
         " *************/")

    (243 348
         "/************* "
         " * box123456 * "
         " *************/")

    (244 448
         "/* box123456 */"
         "/*************/")

    (245 548
         "/*************/"
         "/* box123456 */"
         "/*************/")

    ))


(defvar rebox-default-style 15
  "*Preferred style for box comments.  The buffer's
`comment-start' is used with this style to arrive at the box
style.")
(make-variable-buffer-local 'rebox-default-style)

(defvar rebox-save-env-alist nil
  "backup value saved for here for mode deactivation")
(make-variable-buffer-local 'rebox-save-env-alist)

(defvar rebox-save-env-vars
  '(comment-auto-fill-only-comments
    auto-fill-function
    normal-auto-fill-function)
  "list of variables overwritten by `rebox-mode' to be saved.")

(defvar rebox-save-env-done nil
  "prevent rebox from overwriting saved values")
(make-variable-buffer-local 'rebox-save-env-done)

(defvar rebox-default-unbox-style 11
  "*Preferred style for unboxed comments.")
(make-variable-buffer-local 'rebox-default-unbox-style)

(defgroup rebox nil
  "rebox."
  :group 'convenience)

(defcustom rebox-keep-blank-lines t
  "Non-nil gives rebox permission to truncate blank lines at
beginning of box, end, and more than three consecutive blank
lines in the body of box."
  :type 'boolean
  :group 'rebox)

(defcustom rebox-mode-line-string " rebox"
  ""
  :type 'string
  :group 'rebox)

(defcustom rebox-newline-indent-function-default 'comment-indent-new-line
  "function called by `rebox-indent-new-line' when doesn't see a box."
  :group 'rebox)

(defvar rebox-newline-indent-function nil
  "cached function for this buffer.")
(make-variable-buffer-local 'rebox-newline-indent-function)

(defcustom rebox-backspace-function 'backward-delete-char-untabify
  "function called by `rebox-backpace' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-space-function 'self-insert-command
  "function called by `rebox-space' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-kill-line-function 'kill-line
  "function called by `rebox-kill-line' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-kill-ring-save-function 'kill-ring-save
  "function called by `rebox-kill-ring-save' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-beginning-of-line-function 'move-beginning-of-line
  "function called by `rebox-beginning-of-line' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-end-of-line-function 'move-end-of-line
  "function called by `rebox-end-of-line' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-yank-function 'yank
  "function called by `rebox-yank' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-yank-pop-function 'yank-pop
  "function called by `rebox-yank-pop' when no box is found."
  :type 'symbol
  :group 'rebox)

(defcustom rebox-newline-indent-function-alist
  '((c-mode   . c-indent-new-comment-line)
    (c++-mode . c-indent-new-comment-line)
    (org-mode . org-return-indent))
  "list of (major-mode . function) for making a newline.

The function should make and indent a new comment-line for the
mode.  `comment-indent-newline' is the default.
"
  :type '(alist :key-type 'symbol
                :value-type 'symbol)
  :group 'rebox)

(defcustom rebox-hybrid-major-modes
  '(org-mode)
  "Text based major modes that also have `comment-start' defined.

In these modes, auto-filling should be on for all text.  And
boxing should recognize paragraphs as well as comment blocks.
"
  :type 'list
  :group 'rebox)

;;;###autoload
(define-minor-mode rebox-mode
  "Toggle rebox mode for managing text and comment boxes.

1. Auto-filling is enabled, and comment boxes are auto-filled.  asd f asd f



With no argument, this command toggles the mode.
  Non-null prefix argument turns on the mode.
  Null prefix argument turns off the mode.

You don't need to enable the minor mode to use rebox2

"
  :init-value nil
  :lighter rebox-mode-line-string
  :keymap '(([(shift return)] . rebox-indent-new-line)
            ([(meta q)] . rebox-dwim-fill)
            ([(meta Q)] . rebox-dwim-no-fill)
            ([(control a)] . rebox-beginning-of-line)
            ([(control e)] . rebox-end-of-line)
            ([(control k)] . rebox-kill-line)
            ([(meta w)] . rebox-kill-ring-save)
            ([(control y)] . rebox-yank)
            ([(meta y)] . rebox-yank-pop)
            ([(meta c)] . rebox-center)
            (" " . rebox-space)
            ([(backspace)] . rebox-backspace)

            )
  :group 'rebox
  (if rebox-mode
      (progn
        (rebox-save-env)
        (set (make-local-variable 'comment-auto-fill-only-comments)
             (if (and (stringp comment-start)
                      (not (zerop (length comment-start)))
                      (not (memq major-mode rebox-hybrid-major-modes)))
                 t
               nil))
        (set (make-local-variable 'normal-auto-fill-function) 'rebox-do-auto-fill)
        (auto-fill-mode 1))
    (rebox-restore-env)))


(define-global-minor-mode rebox-global-mode rebox-mode
    rebox-mode
  :group 'rebox)

;; functions passed to rebox-engine inspect these variables
(eval-when-compile
  (defvar previous-nn)
  (defvar previous-ne)
  (defvar previous-sw)
  (defvar previous-ss)
  (defvar previous-se)
  (defvar previous-margin)
  (defvar previous-ee)
  (defvar previous-nw)
  (defvar unindent-count)
  (defvar orig-m)
  (defvar orig-col)
  (defvar max-n)
  (defvar marked-point)
  (defvar ww)
  (defvar previous-regexp1)
  (defvar regexp1)
)

(put 'rebox-error
     'error-conditions
     '(error rebox-error))

(put 'rebox-comment-not-found-error
     'error-message
     "rebox error")

(put 'rebox-comment-not-found-error
     'error-conditions
     '(error rebox-error rebox-comment-not-found-error))

(put 'rebox-comment-not-found-error
     'error-message
     "Comment not found")

(put 'rebox-mid-line-comment-found
     'error-conditions
     '(error rebox-error rebox-mid-line-comment-found))

(put 'rebox-mid-line-comment-found
     'error-message
     "Comment started mid-line.")

;; we don't use syntax table for whitespace definition here because we don't
;; trust major-modes to define them properly.
(defconst rebox-blank-line-regexp "^[ \t]*$")


;; Template numbering dependent code.

(defvar rebox-language-character-alist
  '((3 . "/") (4 . "#") (5 . ";") (6 . "%"))
  "Alist relating language to comment character, for generic languages.")

;;; Regexp to match the comment start, given a LANGUAGE value as index.

(defvar rebox-regexp-start
  ["^[ \t]*\\(/\\*\\|//+\\|#+\\|;+\\|%+\\)"
   "^"                                  ; 1
   "^[ \t]*/\\*"                        ; 2
   "^[ \t]*//+"                         ; 3
   "^[ \t]*#+"                          ; 4
   "^[ \t]*\;+"                         ; 5
   "^[ \t]*%+"                          ; 6
   ])

;;; Request the style interactively, using the minibuffer.

(defun rebox-ask-for-style ()
  (let (key language quality type)
    (while (not language)
      (message "\
Box language is 100-none, 200-/*, 300-//, 400-#, 500-;, 600-%%")
      (setq key (read-char))
      (when (and (>= key ?0) (<= key ?6))
        (setq language (- key ?0))))
    (while (not quality)
      (message "\
Box quality/width is 10-simple/1, 20-rounded/2, 30-starred/3 or 40-starred/4")
      (setq key (read-char))
      (when (and (>= key ?0) (<= key ?4))
        (setq quality (- key ?0))))
    (while (not type)
      (message "\
Box type is 1-opened, 2-half-single, 3-single, 4-half-double or 5-double")
      (setq key (read-char))
      (when (and (>= key ?0) (<= key ?5))
        (setq type (- key ?0))))
    (+ (* 100 language) (* 10 quality) type)))

;; Template ingestion.

;;; Information about registered templates.
(defvar rebox-style-data nil)

;;; Register all box templates.

(defun rebox-register-all-templates ()
  (setq rebox-style-data nil)
  (let ((templates rebox-templates))
    (while templates
      (let ((template (car templates)))
        (rebox-register-template (car template)
                                 (cadr template)
                                 (cddr template)))
      (setq templates (cdr templates)))))

;;; Register a single box template.

(defun rebox-register-template (style weight lines)
  "Digest and register a single template.
The template is numbered STYLE, and is described by one to three LINES.

If STYLE is below 100, it is generic for a few programming languages and
within lines, `?' is meant to represent the language comment character.
STYLE should be used only once through all `rebox-register-template' calls.

One of the lines should contain the substring `box' to represent the comment
to be boxed, and if three lines are given, `box' should appear in the middle
one.  Lines containing only spaces are implied as necessary before and after
the the `box' line, so we have three lines.

Normally, all three template lines should be of the same length.  If the first
line is shorter, it represents a start comment string to be bundled within the
first line of the comment text.  If the third line is shorter, it represents
an end comment string to be bundled at the end of the comment text, and
refilled with it."

  (cond ((< style 100)
         (let ((pairs rebox-language-character-alist)
               language character)
           (while pairs
             (setq language (caar pairs)
                   character (cdar pairs)
                   pairs (cdr pairs))
             (rebox-register-template
              (+ (* 100 language) style)
              weight
              (mapcar (lambda (line)
                        (while (string-match "\?" line)
                          (setq line (replace-match character t t line)))
                        line)
                      lines)))))
        ((assq style rebox-style-data)
         (error "Style %d defined more than once" style))
        (t
         (let (line1 line2 line3 regexp1 regexp2 regexp3
                     merge-nw merge-se nw nn ne ww ee sw ss se)
           (if (string-match "box123456" (car lines))
               (setq line1 nil
                     line2 (car lines)
                     lines (cdr lines))
             (setq line1 (car lines)
                   line2 (cadr lines)
                   lines (cddr lines))
             (unless (string-match "box123456" line2)
               (error "Erroneous template for %d style" style)))
           (setq line3 (and lines (car lines)))
           (setq merge-nw (and line1 (< (length line1) (length line2)))
                 merge-se (and line3 (< (length line3) (length line2)))
                 nw       (cond ((not line1) nil)
                                (merge-nw line1)
                                ((zerop (match-beginning 0)) nil)
                                (t (substring line1 0 (match-beginning 0))))
                 nn       (cond ((not line1) nil)
                                (merge-nw nil)
                                (t (let ((x (aref line1 (match-beginning 0))))
                                     (if (= x ? ) nil x))))
                 ne       (cond ((not line1) nil)
                                (merge-nw nil)
                                ((= (match-end 0) (length line1)) nil)
                                (t (rebox-rstrip (substring line1 (match-end 0)))))
                 ww       (cond ((zerop (match-beginning 0)) nil)
                                (t (substring line2 0 (match-beginning 0))))
                 ee       (cond ((= (match-end 0) (length line2)) nil)
                                (t (rebox-rstrip (substring line2 (match-end 0)))))
                 sw       (cond ((not line3) nil)
                                (merge-se nil)
                                ((zerop (match-beginning 0)) nil)
                                (t (substring line3 0 (match-beginning 0))))
                 ss       (cond ((not line3) nil)
                                (merge-se nil)
                                (t (let ((x (aref line3 (match-beginning 0))))
                                     (if (= x ? ) nil x))))
                 se       (cond ((not line3) nil)
                                (merge-se (rebox-rstrip line3))
                                ((= (match-end 0) (length line3)) nil)
                                (t (rebox-rstrip (substring line3 (match-end 0))))))
           (setq regexp1 (cond
                          (merge-nw
                           (concat "^[ \t]*" (rebox-regexp-quote nw :rstrip nil) "\n"))
                          ((and nw (not nn) (not ne))
                           (concat "^[ \t]*" (rebox-regexp-quote nw :rstrip nil) "\n"))
                          ((or nw nn ne)
                           (concat "^[ \t]*" (rebox-regexp-quote nw :rstrip nil)
                                   (rebox-regexp-ruler nn)
                                   (rebox-regexp-quote ne :lstrip nil) "\n")))
                 regexp2 (and (not (string-equal (rebox-rstrip (concat ww ee))
                                                 ""))
                              (concat "^[ \t]*"
                                      (rebox-regexp-quote ww :rstrip nil)
                                      ".*"
                                      (rebox-regexp-quote ee :lstrip nil)
                                      "\n"))
                 regexp3 (cond
                          (merge-se
                           (concat "^.*" (rebox-regexp-quote se :lstrip nil) "\n"))
                          ((and sw (not ss) (not se))
                           (concat "^[ \t]*" (rebox-regexp-quote sw :rstrip nil) "\n"))
                          ((or sw ss se)
                           (concat "^[ \t]*" (rebox-regexp-quote sw :rstrip nil)
                                   (rebox-regexp-ruler ss)
                                   (rebox-regexp-quote se :lstrip nil) "\n"))))
           (setq rebox-style-data
                 (cons (cons style
                             (vector weight regexp1 regexp2 regexp3
                                     merge-nw merge-se
                                     nw nn ne ww ee sw ss se))
                       rebox-style-data))))))

(defun* rebox-get-style-from-prefix-arg (arg &key (ask t) (use-default t))
  "analyze `arg' to get style"
  (cond ((numberp arg)
         (if (> arg 0)
             (rebox-get-style-for-major-mode arg)
           (rebox-get-style-for-major-mode (- arg))))
        ((eq '- arg)
         (if ask
             (rebox-ask-for-style)
           (rebox-get-style-for-major-mode rebox-default-unbox-style)))
        (t
         (when use-default
           (rebox-get-style-for-major-mode rebox-default-style)))))

(defun rebox-get-refill-from-prefix-arg (arg)
  "analyze `arg' to refill

returns t for refil nil for not.
"
  (if (and arg
           (listp arg))
      nil
    t))

(defun rebox-get-style-for-major-mode (style)
  (cond ((and (numberp style)
              (< style 100)
              (> style 0))
         (+ (* 100 (rebox-guess-language comment-start))
            style))
        ((numberp style)
         style)
        (t
         (error "unknown style: %s" style))))

(defun rebox-make-fill-prefix ()
  "generate fill prefix using adaptive filling methods"
  (beginning-of-line)
  (if (featurep 'filladapt)
      (filladapt-make-fill-prefix
       (filladapt-parse-prefixes))
    (fill-context-prefix
     (point-at-bol)
     (point-at-eol))))


;; User interaction.

;;;###autoload
(defun rebox-beginning-of-line (arg)
  "If point is in a box, go to beginning of text on first invocation.
On second invocation, go to beginning of physical line.  Subsequent invocation switches between the two.

If point is not in a box, call `rebox-beginning-of-line-function'

ARG argument is prefix argument, only used by 'rebox-beginning-of-line-function'

"

  (interactive "^P")
  (let ((orig-m (point-marker))
        previous-style
        boxed-line-start-col)
    (save-restriction
      (condition-case err
          (progn
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
            (setq previous-style (rebox-guess-style))
            (if (eq previous-style 111)
                (signal 'rebox-error '("style is 111"))
              (rebox-engine :style previous-style
                            :marked-point orig-m
                            :quiet t
                            :refill nil
                            :move-point nil
                            :previous-style previous-style
                            :before-insp-func
                            (lambda ()
                              (goto-char marked-point)
                              (if ;; top or bottom border
                                  (or (and previous-regexp1
                                           (eq (line-number-at-pos) 1))
                                      (and previous-regexp3
                                           (eq (line-number-at-pos) (1- (line-number-at-pos (point-max))))))
                                  (setq boxed-line-start-col previous-margin)
                                (save-restriction
                                  (narrow-to-region (+ (point-at-bol) unindent-count)
                                                    (point-at-eol))
                                  (beginning-of-line 1)
                                  (setq boxed-line-start-col
                                        (if (looking-at-p (concat "[ \t]*"
                                                                  (and previous-ee
                                                                       (regexp-quote previous-ee))
                                                                  "$"))
                                            unindent-count
                                          (+ (length (rebox-make-fill-prefix))
                                             unindent-count)))))
                              (throw 'rebox-engine-done t)))
	      (goto-char orig-m)
              (if (or (bolp)
                      (> (current-column) boxed-line-start-col))
                  (move-to-column boxed-line-start-col)
                (move-beginning-of-line 1))))
        ('rebox-error
         (goto-char orig-m)
         (call-interactively rebox-beginning-of-line-function))
        ('error
         (signal (car err) (cdr err)))))))

;;;###autoload
(defun rebox-end-of-line (arg)
  "If point is in a box, go to end of text on first invocation.
On second invocation, go to end of physical line.  Subsequent invocation switches between the two.

If point is not in a box, call `rebox-beginning-of-line-function'"
  (interactive "^P")
  (let ((orig-m (point-marker))
        previous-style
        boxed-line-end-col)
    (save-restriction
      (condition-case err
          (progn
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
            (setq previous-style (rebox-guess-style))
            (if (eq previous-style 111)
                (signal 'rebox-error '("style is 111"))
              (rebox-engine :style previous-style
                            :quiet t
                            :refill nil
                            :move-point nil
                            :previous-style previous-style
                            :before-insp-func
                            (lambda ()
                              (goto-char orig-m)
                              (beginning-of-line)
                              (if ;; top or bottom border
                                  (or (and previous-regexp1
                                           (eq (line-number-at-pos) 1))
                                      (and previous-regexp3
                                           (eq (line-number-at-pos) (1- (line-number-at-pos (point-max))))))
                                  (setq boxed-line-end-col (point-at-eol))
                                (setq boxed-line-end-col
                                      (if previous-ee
                                          (progn
                                            (search-forward-regexp (concat "[ \t]*"
                                                                           (rebox-regexp-quote previous-ee)
                                                                           "$")
                                                                   (point-at-eol))
                                            (goto-char (match-beginning 0))
                                            (current-column))
                                        (search-forward-regexp "[ \t]*$"
                                                               (point-at-eol))
                                        (goto-char (match-beginning 0))
                                        (current-column)))
                                ;; blank line
                                (when (<= boxed-line-end-col unindent-count)
                                  (setq boxed-line-end-col (progn (goto-char (point-at-eol))
                                                                  (current-column)))))
                              (throw 'rebox-engine-done t)))
              (goto-char orig-m)
              (if (or (eolp)
                      (< (current-column) boxed-line-end-col))
                  (move-to-column boxed-line-end-col)
                (move-end-of-line 1))))
        ('rebox-error
         (goto-char orig-m)
         (call-interactively rebox-end-of-line-function))
        ('error
         (signal (car err) (cdr err)))))))

;;;###autoload
(defun rebox-kill-line (arg)
  "If point is in a box, unbox first, and then run
`rebox-kill-line-function' as requested, unless region is
selected, in which case, the region is killed.

If point is not in a box, call `rebox-kill-line-function'.

With universal ARG, always call `rebox-kill-line-function'.
"
  (interactive "P*")
  (let (orig-col orig-line)
    (rebox-kill-yank-wrapper :before-insp-func
                             (lambda ()
                               (goto-char marked-point)
                               (setq orig-line (if previous-regexp1
                                                   (1- (line-number-at-pos))
                                                 (line-number-at-pos)))
                               (setq orig-col (- (current-column) unindent-count)))
                             :mod-func
                             (lambda ()
                               (goto-char marked-point)
                               (condition-case err
                                   (progn
                                     (if (use-region-p)
                                         (progn
                                           (kill-region (region-beginning) (region-end))
                                           (goto-char (point-max))
                                           ;; ensure narrowed region is still valid
                                           (unless (bolp)
                                             (insert "\n")))
                                       (call-interactively rebox-kill-line-function)))
                                 ('end-of-buffer
                                  (signal 'end-of-buffer `(,(format "end of box reached, aborting %s." this-command)
                                                           ,@(cdr err))))))
                             :after-insp-func
                             (lambda ()
                               ;; try to fix the point
                               (goto-char marked-point)
                               (let ((new-line-num (if regexp1
                                                       (1- (line-number-at-pos))
                                                     (line-number-at-pos)))
                                     (new-col (- (current-column) previous-margin (length ww))))
                                 (when (and (< new-line-num 1)
                                            (>= orig-line 1))
                                   ;; goto-line
                                   (goto-char (point-min))
                                   (forward-line (1- (+ orig-line (if regexp1 1 0)))))
                                 (when (and (< new-col 0)
                                            (>= orig-col 0))
                                   (move-beginning-of-line 1)
                                   (rebox-beginning-of-line 1))
                                 (set-marker marked-point (point))))
                             :orig-func
                             rebox-kill-line-function)))

(defun rebox-yank (arg)
  "If point is in a box, unbox first, and then run `rebox-yank-function' as requested.

If point is not in a box, call `rebox-yank-function'.

With universal ARG, always call `rebox-yank-function'.
"
  (interactive "P*")
  (rebox-kill-yank-wrapper :not-at-nw t
                           :mod-func
                           (lambda ()
                             (goto-char orig-m)
                             (call-interactively 'yank)
                             (set-marker orig-m (point)))
                           :orig-func
                           rebox-yank-function))

(defun rebox-yank-pop (arg)
  "If point is in a box, unbox first, and then run `reobx-yank-pop-function' as requested.

If point is not in a box, call `reobx-yank-pop-function'.

With universal ARG, always call `reobx-yank-pop-function'.
"
  (interactive "P*")
  (rebox-kill-yank-wrapper :not-at-nw t
                           :mod-func
                           (lambda ()
                             (goto-char orig-m)
                             (call-interactively 'yank-pop)
                             (set-marker orig-m (point)))
                           :orig-func
                           rebox-yank-pop-function))

(defun rebox-kill-ring-save (arg)
  (interactive "P")
  (let ((mod-p (buffer-modified-p)))
    (rebox-kill-yank-wrapper :try-whole-box t
                             :mod-func
                             (lambda ()
                               (goto-char orig-m)
                               (call-interactively rebox-kill-ring-save-function)
                               (set-marker orig-m (point-marker)))
                             :orig-func
                             rebox-kill-ring-save-function)
    ;; kill-ring-save shouldn't change buffer-modified status
    (set-buffer-modified-p mod-p)))

(defun rebox-center ()
  "If point is in the left border of a box, center the box,
else call the default binding of M-c.

with argument N, move n columns."
  (interactive "*")
  (let ((orig-func (cdr (assq 'meta-c-func rebox-save-env-alist))))
    (rebox-left-border-wrapper (lambda ()
                                 (if (< (current-column) unindent-count)
                                     (center-region (point-min) (point-max))
                                   (when orig-func
                                     (call-interactively orig-func)
                                     (set-marker orig-m (point))))
                                 (throw 'rebox-engine-done t))
                               orig-func
                               )))


(defun rebox-space (n)
  "If point is in the left border of a box, move box to the right,
else calls `rebox-space-function'.

with argument N, move n columns."
  (interactive "p*")
  (rebox-left-border-wrapper (lambda ()
                               (goto-char orig-m)
                               (if (< (current-column) unindent-count)
                                   (progn
                                     (set-marker-insertion-type orig-m t)
                                     (string-rectangle (point-min)
                                                       (progn (goto-char (point-max))
                                                              (point-at-bol 0))
                                                       (make-string n ? )))
                                 (call-interactively rebox-space-function)
                                 ;; we can't change insertion-type in case
                                 ;; this is the last column of the box
                                 (set-marker orig-m (point)))
                               (throw 'rebox-engine-done t))
                             rebox-space-function))

(defun rebox-backspace (n)
  "If point is in the left border of a box, move box to the left,
else call `rebox-backspace-function'.

with argument N, move n columns."
  (interactive "*p")
  (if (use-region-p)
      (call-interactively 'rebox-kill-line)
    (rebox-left-border-wrapper (lambda ()
                                 (if (< orig-col unindent-count)
                                     (delete-rectangle (point-min)
                                                       (progn (goto-char (point-max))
                                                              (beginning-of-line 0)
                                                              (setq max-n (min orig-col previous-margin))
                                                              (if (< n max-n)
                                                                  (move-to-column n)
                                                                (move-to-column max-n))
                                                              (point)))
                                   (goto-char orig-m)
                                   (call-interactively rebox-backspace-function))
                                 (throw 'rebox-engine-done t))
                               rebox-backspace-function)))

;;;###autoload
(defun* rebox-region (r-beg r-end &key style (refill t) previous-style (quiet nil))
  "Rebox the region.

Prefix arg is processed same as `rebox-comment'

Create newling before and after region as needed to ensure box
starts and ends on a newline.
"
  (interactive (progn
                 (unless (use-region-p)
                   (error "region not selected."))
                 (let ((style (rebox-get-style-from-prefix-arg
                               current-prefix-arg))
                       (refill (rebox-get-refill-from-prefix-arg
                                current-prefix-arg)))
                   (list (region-beginning) (region-end) :style style :refill
                         refill))))
  (let ((orig-m (point-marker))
        (r-end (progn
                 (goto-char r-end)
                 (point-marker)))
        (r-beg (progn
                 (goto-char r-beg)
                 (point-marker))))
    ;; we can't possible recognize any style when region was improperly
    ;; selected.
    (when (rebox-ensure-region-whole-lines r-beg r-end)
        (setq previous-style 111))
    (save-restriction
      (narrow-to-region r-beg r-end)
      (goto-char orig-m)
      (rebox-engine :style style
                    :previous-style previous-style
                    :refill refill
                    :quiet quiet))))

;;; Rebox the surrounding comment.
;;;###autoload
(defun* rebox-comment (&key style (refill t))
  "Make box around current comment.  If no comment is defined,
  build box around current consecutive non-blank lines.

prefix arg is processed thusly:

1) positive number - specifies 3 digit style or 2 digit base style.  WITH REFILL.
2) negative number - style, no refill.
3) \"-\"             - prompt for style interactively (legacy)
4) universal arg   - apply `rebox-default-style', no refill.
"
  (interactive (list :style (rebox-get-style-from-prefix-arg current-prefix-arg)
                     :refill (rebox-get-refill-from-prefix-arg current-prefix-arg)))
  (if (use-region-p)
      (error "rebox-comment doesn't understand regions."))
  (let ((orig-m (point-marker))
        previous-style)
    (save-restriction
      (condition-case err
          (progn
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
            (setq previous-style (rebox-guess-style))
            (rebox-engine :style style
                          :refill refill
                          :previous-style previous-style
                          :marked-point orig-m))
        ('rebox-error
         (signal (car err) (cdr err)))
        ('error
         (error "rebox-comment wrapper: %s" err))))
    (goto-char orig-m)))

;;;###autoload
(defun rebox-dwim-fill (arg)
  "On first invocation, fill region or comment, unless style requested through prefix arg.

If comment is not found, call `fill-paragraph'.

On second consecutive invocation, box region or comment using
prefix arg specified style or `rebox-default-style'.

If region is active, the region will stay active after this command.

This function processes prefix arg the same way as`rebox-comment' with the
  exception that:

            +----------------------------------------------------+
            | specifying `-' will unbox the region or comment to |
            | `rebox-default-unbox-style' with refill           |
            +----------------------------------------------------+
"
  (interactive "*P")
  (let ((orig-m (point-marker))
        ;;copy of mark, so we can possibly change the insertion type
        temp-mark
        (style (rebox-get-style-from-prefix-arg current-prefix-arg
                                                :use-default nil :ask nil))
        previous-style)
    (save-restriction
      (condition-case err
          (if (use-region-p)
              (let (deactivate-mark)
                (if (and (prog2
                             (goto-char (region-beginning))
                             (eq (point) (point-at-bol))
                           (goto-char orig-m))
                         (prog2
                             (goto-char (region-end))
                             (eq (point) (point-at-bol))
                           (goto-char orig-m)))
                    (progn
                      (setq temp-mark (set-marker (make-marker) (mark)))
                      (set-marker-insertion-type (if (< temp-mark orig-m)
                                                     orig-m
                                                   temp-mark)
                                                 t)
                      (narrow-to-region (region-beginning) (region-end))
                      (setq previous-style (rebox-guess-style))
                      (if (or (memq last-command '(rebox-dwim-fill))
                              style)
                          (progn
                            (setq style (or style
                                            (rebox-get-style-for-major-mode rebox-default-style)))
                            (message "Rebox changing style: %s -> %s"
                                     previous-style
                                     style)
                            (rebox-engine :style style
                                          :refill t
                                          :previous-style previous-style
                                          :quiet t))
                        (message "Refilling style: %s" previous-style)
                        (if (eq previous-style 111)
                            (progn
                              (goto-char orig-m)
                              (call-interactively 'fill-region))
                          (rebox-engine :style previous-style
                                        :refill t
                                        :previous-style previous-style
                                        :quiet t)))
                      (set-mark temp-mark))
                  (if (memq last-command '(rebox-dwim-fill))
                      (let ((r-beg (prog2
                                     (goto-char (region-beginning))
                                     (point-marker)
                                     (goto-char orig-m)))
                            (r-end (prog2
                                       (goto-char (region-end))
                                       (point-marker)
                                     (goto-char orig-m))))
                        (rebox-ensure-region-whole-lines r-beg r-end)
                        (if (< (point) (mark))
                            (progn
                              (set-mark r-end)
                              (goto-char r-beg))
                          (set-mark r-beg)
                          (goto-char r-end))
                        (rebox-dwim-fill arg)
                        (set-marker orig-m (point)))
                    (message "Refilling region")
                    (fill-region (region-beginning) (region-end)))))
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
            (setq previous-style (rebox-guess-style))
            (if (or (memq last-command '(rebox-dwim-fill))
                    style)
                (progn
                  (setq style (or style
                                  (rebox-get-style-for-major-mode rebox-default-style)))
                  (message "Rebox changing style: %s -> %s"
                           previous-style
                           style)
                  (rebox-engine :style style
                                :refill t
                                :previous-style previous-style
                                :marked-point orig-m
                                :quiet t))
              (if (eq previous-style 111)
                  (signal 'rebox-error nil)
                (message "Refilling style: %s" previous-style)
                (rebox-engine :refill t
                              :previous-style previous-style
                              :style previous-style
                              :marked-point orig-m
                              :quiet t))))
        ('rebox-error
         ;; (message "rebox returned: %s, calling `fill-paragraph'" err)
         (goto-char orig-m)
         (call-interactively 'fill-paragraph))
        ('error
         (error "rebox-dwim-fill wrapper: %s" err))))
    (goto-char orig-m)))

;;;###autoload
(defun rebox-dwim-no-fill (arg)
  "Rebox region or comment, never refilling.

This function processes prefix arg the same way as`rebox-comment'
with the
  exception that:

            +----------------------------------------------------+
            | specifying `-' will unbox the region or comment to |
            | `rebox-default-unbox-style'                       |
            +----------------------------------------------------+
"
  (interactive "*P")
  (let ((style (rebox-get-style-from-prefix-arg current-prefix-arg :ask nil))
        (refill (rebox-get-refill-from-prefix-arg current-prefix-arg)))
    (if (use-region-p)
        (rebox-region (region-beginning)
                      (region-end)
                      :style style
                      :refill nil)
      (rebox-comment :style style
                     :refill nil))))

(defun rebox-do-auto-fill ()
  "Try to fill as box first, if that fails use `do-auto-fill'
"
  (let ((orig-m (point-marker))
        style)
    (condition-case err
        (save-restriction
          (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
          (setq style (rebox-guess-style))
          (if (= style 111)
              (signal 'rebox-error nil)
            (goto-char orig-m)
            (rebox-engine :previous-style style
                          :marked-point orig-m
                          :refill 'auto-fill
                          :quiet t
                          :move-point nil
                          :before-insp-func
                          (lambda ()
                            (goto-char marked-point)
                            ;; top or bottom or left or right border
                            (when (or (and previous-regexp1
                                           (eq (line-number-at-pos) 1))
                                      (and previous-regexp3
                                           (eq (line-number-at-pos) (1- (line-number-at-pos (point-max)))))
                                      (< (current-column) unindent-count)
                                      (and previous-ee
                                           (looking-back (rebox-regexp-quote previous-ee :lstrip nil))
                                           (looking-at-p "[ \t]*$")))
                              (throw 'rebox-engine-done t)))
                          :after-insp-func
                          (lambda ()
                            ;; pressing space at boundary - changing style from 520 to 521
                            ;; moves point to bol, we need to move it back.
                            (when (and (eq this-command 'rebox-space)
                                       (bolp))
                              (rebox-beginning-of-line nil)
                              (setq marked-point (point)))))))
      ('rebox-error
       (goto-char orig-m)
       ;; prefer `normal-auto-fill-function' to `auto-fill-function'
       (let ((fill-func (or (cdr (assq 'normal-auto-fill-function rebox-save-env-alist))
                            (cdr (assq 'auto-fill-function rebox-save-env-alist)))))
         (if fill-func
             (funcall fill-func)
           (signal 'rebox-error '("appropriate auto-fill-function not found.")))))
       ('error
       (error "rebox-do-auto-fill wrapper: %s" err)))))

;;;###autoload
(defun rebox-indent-new-line (arg)
  "Create newline.

Prefix arg greater than zero inserts arg lines.  Other prefix arg
causes refilling without actually inserting a newline.

If point is within a box, keep comment boxed.  Elsif point is
in a comment, continue comment on the next line.  Else, newline
and indent.
"
  (interactive "*P")
  (save-restriction
    (let (orig-m
          style
          text-beg-col
          )
      (condition-case err
          (progn
            (setq orig-m (point-marker))
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
            (set-marker-insertion-type orig-m t)
            (setq style (rebox-guess-style))
            (if (not (eq style 111)) ; 111 is no-box
                (progn
                  (setq arg (cond ((not arg)
                                   1)
                                  ((and arg
                                        (numberp arg)
                                        (> arg 0))
                                   arg)
                                  (t
                                   nil)))
                  (rebox-engine :previous-style style
                                :refill nil
                                :mod-func
                                (lambda ()
                                  ;;-lw- just always goto beginning of line?
                                  (when arg
                                    (goto-char orig-m)
                                    (if (looking-at-p "[ \t]*$")
                                        ;; creating blank line
                                        (progn
                                          (beginning-of-line)
                                          (setq text-beg-col
                                                (if (looking-at-p "[ \t]*$")
                                                    (progn
                                                      (goto-char orig-m)
                                                      (+ previous-margin
                                                         (length ww)
                                                         (current-column)))
                                                  (skip-chars-forward " \t")
                                                  (+ previous-margin
                                                     (length ww)
                                                     (current-column)))))
                                      (setq text-beg-col (+ previous-margin (length ww))))
                                    (goto-char orig-m)
                                    (newline arg))))
                  (goto-char orig-m)
                  (move-to-column text-beg-col t))
              (goto-char orig-m)
              (call-interactively (rebox-get-newline-indent-function))))
        ('rebox-error
         (let ((err-marker (point-marker))
               (saved-func (rebox-get-newline-indent-function)))
           (goto-char orig-m)
           (cond ((eq (car err) 'rebox-comment-not-found-error)
                  (message "rebox-indent-new-line: unable to find comment, calling %s."
                           saved-func))
                 ((eq (car err) 'rebox-mid-line-comment-found)
                  (message "midline comment found at (%s), calling %s" err-marker saved-func)))
           (call-interactively saved-func)))
        ('rebox-comment-not-found-error
         (message "rebox-indent-new-line: unable to find comment, calling saved function.")
         (call-interactively (rebox-get-newline-indent-function)))
        ('error
         (error "rebox-indent-new-line wrapper: %s" err))))))



(defun* rebox-kill-yank-wrapper (&key try-whole-box not-at-nw mod-func orig-func before-insp-func after-insp-func)
  (let ((orig-m (point-marker))
        previous-style)
    (condition-case err
        (progn
          (when (and current-prefix-arg
                     (listp current-prefix-arg))
            ;; call orig-func
            (signal 'rebox-error nil))
          (save-restriction
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments
                                   :try-whole-box try-whole-box)
            (when (and (= orig-m (point-min))
                       not-at-nw)
              (signal 'rebox-error '("mark is out of box")))
            (when (and (use-region-p)
                       (or (< (mark) (point-min))
                           (> (mark) (point-max))))
              (signal 'rebox-error '("mark is out of box")))
            (setq previous-style (rebox-guess-style))
            (if (eq previous-style 111)
                (signal 'rebox-error '("style is 111"))
              (rebox-engine :style previous-style
                            :marked-point orig-m
                            :quiet t
                            :refill nil
                            :move-point nil
                            :previous-style previous-style
                            :before-insp-func
                            before-insp-func
                            :mod-func
                            mod-func
                            :after-insp-func
                            after-insp-func))))
      ('rebox-error
       (goto-char orig-m)
       (and orig-func
            (call-interactively orig-func)))
      ('error
       (signal (car err) (cdr err))))))

(defun rebox-left-border-wrapper (before-insp-func orig-func)
  (let ((orig-m (point-marker))
        (orig-col (current-column))
        previous-style)
    (condition-case err
        (progn
          (when (use-region-p)
            (signal 'rebox-error '("region used")))
          (save-restriction
            (rebox-find-and-narrow :comment-only comment-auto-fill-only-comments)
            (setq previous-style (rebox-guess-style))
            (if (eq previous-style 111)
                (signal 'rebox-error '("style is 111"))
              (goto-char orig-m)
              (rebox-engine :style previous-style
                            :marked-point orig-m
                            :quiet t
                            :refill nil
                            :move-point nil
                            :previous-style previous-style
                            :before-insp-func
                            before-insp-func))))
      ('rebox-error
       (goto-char orig-m)
       (and orig-func
            (call-interactively orig-func)))
      ('error
       (signal (car err) (cdr err))))))



(defun rebox-ensure-region-whole-lines (r-beg r-end)
  "Ensure region covered by r-beg and r-end are whole lines.

R-BEG and R-END are markers.  We assume R-BEG < R-END.

Returns t when changes were made to the markers."
  (let (col
        changes-made)
    (goto-char r-beg)
    (unless (bolp)
      (setq changes-made t)
      (setq col (current-column))
      (beginning-of-line 1)
      (unless (prog2
                  (skip-chars-forward " \t")
                  (>= (current-column) col))
        (goto-char r-beg)
        (insert "\n")
        (indent-to col))
      (set-marker r-beg (point-at-bol)))
    (goto-char r-end)
    (unless (bolp)
      (setq changes-made t)
      (if (and (looking-at-p "[ \t]*$")
               (not (eobp)))
          (set-marker r-end (point-at-bol 2))
        (insert "\n")
        (set-marker r-end (point))))
    changes-made))

(defun* rebox-engine (&key style
                           before-insp-func
                           mod-func
                           before-insp-func
                           after-insp-func
                           (refill t)
                           (previous-style nil)
                           (quiet nil)
                           (marked-point nil)
                           (move-point t))
  "Add, delete or adjust a comment box in the narrowed buffer.

The narrowed buffer should contain only whole lines, otherwise it will look strange once widened.

"
  (let* ((undo-list buffer-undo-list)
         clean-undo-list
         (marked-point (or marked-point
                           (point-marker)))
         (previous-margin (rebox-left-margin))
         (previous-style (or previous-style
                             (rebox-guess-style)))
         (previous-style-data (cdr (assq previous-style rebox-style-data)))
         (previous-regexp1 (aref previous-style-data 1))
         (previous-regexp2 (aref previous-style-data 2))
         (previous-regexp3 (aref previous-style-data 3))
         (previous-merge-nw (aref previous-style-data 4))
         (previous-merge-se (aref previous-style-data 5))
         (previous-nw (aref previous-style-data 6))
         (previous-nn (aref previous-style-data 7))
         (previous-ne (aref previous-style-data 8))
         (previous-ww (aref previous-style-data 9))
         (previous-ee (aref previous-style-data 10))
         (previous-sw (aref previous-style-data 11))
         (previous-ss (aref previous-style-data 12))
         (previous-se (aref previous-style-data 13))
         (style (or style previous-style))
         (style-data (or (cdr (assq style rebox-style-data))
                         (signal 'rebox-comment-not-found-error (list (format "style (%s) is unknown" style)))))
         (regexp1 (aref style-data 1))
         (regexp2 (aref style-data 2))
         (regexp3 (aref style-data 3))
         (merge-nw (aref style-data 4))
         (merge-se (aref style-data 5))
         (nw (aref style-data 6))
         (nn (aref style-data 7))
         (ne (aref style-data 8))
         (ww (aref style-data 9))
         (ee (aref style-data 10))
         (sw (aref style-data 11))
         (ss (aref style-data 12))
         (se (aref style-data 13))
         (unindent-count (+ previous-margin (length previous-ww)))
         ;; (marked-col-within-box (progn
         ;;                          (goto-char marked-point)
         ;;                          (- (current-column)
         ;;                             unindent-count)))
         )


    (unless quiet
      (if (= previous-style style)
          (message "Keeping style \"%s\"%s."
                   style
                   (concat (when refill
                             ", refilling")
                           (when before-insp-func
                             ", running before-insp-func")
                           (when mod-func
                             ", running mod-func")
                           (when after-insp-func
                             ", running after-insp-func")
                           ))
        (message "Style: %d -> %d" (or previous-style 0) style)))

    ;; attempt to box only spaces
    (goto-char (point-min))
    (skip-chars-forward " \t\n")
    (when (not (< (point) (point-max)))
      (signal 'rebox-error '("Cannot box region consisting of only spaces.")))

    ;; untabify, but preserve position of marked-point
    (let ((marked-col (progn
                        (goto-char marked-point)
                        (current-column))))
      (untabify (point-min) (point-max))
      (goto-char marked-point)
      (unless (= (current-column) marked-col)
        (move-to-column marked-col)
        (set-marker marked-point (point))))

    (catch 'rebox-engine-done
      ;; inspect the box
      (when before-insp-func
        (if (functionp before-insp-func)
            (funcall before-insp-func)
          (error "%s is not a function" before-insp-func)))

      ;; if we don't set the insertion type, and it gets pulled to the beginning
      ;; of line, it will get stuck there.
      (goto-char marked-point)
      (when (eolp)
        (set-marker-insertion-type marked-point t))

      ;; Remove all previous comment marks.
      (unless (eq previous-style 111)
        (rebox-unbuild previous-style))

      (unless rebox-keep-blank-lines
        ;; Remove all spurious whitespace.
        (goto-char (point-min))
        (while (re-search-forward " +$" nil t)
          (replace-match "" t t))
        (goto-char (point-min))
        (delete-char (- (skip-chars-forward "\n")))
        (goto-char (point-max))
        (when (= (preceding-char) ?\n)
          (forward-char -1))
        (delete-char (- (skip-chars-backward "\n")))
        (goto-char (point-min))
        (while (re-search-forward "\n\n\n+" nil t)
          (replace-match "\n\n" t t)))

      ;; Move all the text rigidly to the left for insuring that the left
      ;; margin stays at the same place.
      (unless (zerop unindent-count)
        (goto-char (point-min))
        (while (not (eobp))
          (backward-delete-char (skip-chars-forward " " (+ (point) unindent-count)))
          (forward-line 1)))

      ;; modify the box
      (when mod-func
        (if (functionp mod-func)
            (let (
                  ;; in case editing functions check major-mode for
                  ;; indentation, etc.
                  (major-mode 'fundamental-mode)
                  (fill-column (- fill-column (+ (length ww) (length ee) previous-margin))))
              (funcall mod-func))
          (error "%s is not a function" mod-func)))

      ;; empty boxes are allowed if we are just doing an autofill, otherwise
      ;; we can never start a comment, as the "space" after `comment-start'
      ;; will trigger auto-fill-function.
      (when (not (eq refill 'auto-fill))
        ;; if the narrowed box is all blanks now, delete it and quit
        (goto-char (point-min))
        (skip-chars-forward " \t\n")
        (when (eq (point) (point-max))
          (delete-region (point-min) (point-max))
          (throw 'rebox-engine-done t)))

      ;; Possibly refill, then build the comment box.
      (let ((indent-tabs-mode nil))
        (rebox-build refill previous-margin style marked-point move-point))
      (setq clean-undo-list t))

    ;; Retabify to the left only (adapted from tabify.el).
    (if indent-tabs-mode
        (let ((marked-col (progn
                            ;; bug # 7946 workaround
                            ;; should be fixed in next emacs23 release after 23.2.1
			    (set-buffer (current-buffer))
                             (format "%s" marked-point)
			    (goto-char marked-point)
                            (current-column))))
          (goto-char (point-min))
          (while (re-search-forward "^[ \t][ \t]+" nil t)
            (let ((column (current-column)))
              (delete-region (match-beginning 0) (point))
              (indent-to column)))
          (goto-char marked-point)
          (unless (= (current-column) marked-col)
            (move-to-column marked-col)
            (set-marker marked-point (point))))
      (goto-char marked-point))

    (when after-insp-func
      (if (functionp after-insp-func)
          (funcall after-insp-func)
        (error "%s is not a function" after-insp-func)))

    ;; Remove all intermediate boundaries from the undo list.
    (unless (or (not clean-undo-list)
                (eq buffer-undo-list undo-list))
      (let ((cursor buffer-undo-list))
        (while (not (eq (cdr cursor) undo-list))
          (if (car (cdr cursor))
              (setq cursor (cdr cursor))
            (rplacd cursor (cdr (cdr cursor)))))))))


(defun rebox-style-to-vector (number)
  "Transform a style number into a vector triplet."
  (vector (/ number 100) (% (/ number 10) 10) (% number 10)))

;; Classification of boxes (and also, construction data).

(defun rebox-find-box-beg-end (comment-only)
  (let ((orig-p (point))
        (has-comment-definition (and comment-start
                                     (not (zerop (length comment-start)))))
        comment-b comment-e)
    (if has-comment-definition
        ;; are we inside a comment?
        (when (progn
                (goto-char (point-at-eol))
                (rebox-line-has-comment :move-multiline nil))
          (setq comment-b (point-at-bol))
          (goto-char (point-at-eol 0))  ; previous line's eol
          (catch 'roo
            (while (rebox-line-has-comment :throw-label 'roo)
              (setq comment-b (point-at-bol))
              (if (eq (point-at-bol) (point-min))
                  (throw 'roo nil)
                (goto-char (point-at-eol 0)))))
          (goto-char orig-p)
          (end-of-line 2)
          (setq comment-e (point-at-bol))
          (catch 'roo
            (while (rebox-line-has-comment :throw-label 'roo
                                           :move-multiline nil)
              (goto-char (point-at-eol 2))
              (setq comment-e (point-at-bol))
              (when (and (eq (point) (point-max)) ; hit eob
                         (not (eq (point) (point-at-bol)))) ; eob is *not* newline
                ;; we need to end on a blank line for rebox to work properly,
                ;; we don't call `newline' to avoid refilling.
                (insert "\n")
                (setq comment-e (point))
                (throw 'roo nil))))))
    (goto-char orig-p)
    (when  (and (not comment-b)
                (not comment-e)
                (not comment-only))
      ;; no comment format defined
      (setq comment-b (if (search-backward-regexp rebox-blank-line-regexp nil t)
                          (prog1
                              (point-at-bol 2)
                            (goto-char orig-p))
                        (point-min)))
      (setq comment-e (if (search-forward-regexp rebox-blank-line-regexp nil t)
                          (prog1
                              (point-at-bol 1)
                            (goto-char orig-p))
                        ;; we need a blank line at the end of the narrow
                        (goto-char (point-max))
                        (insert "\n")
                        (point))))
    (list comment-b comment-e)))

(defun* rebox-find-and-narrow (&key (comment-only t) (try-whole-box nil))
  "Find the limits of the block of comments following or enclosing
the cursor, or return an error if the cursor is not within such a
block of comments.  Extend it as far as possible in both
directions, then narrow the buffer around it."
  (let ((orig-p (point))
        comment-b comment-e
        temp
        got-it)
    (setq temp (rebox-find-box-beg-end comment-only))
    (setq comment-b (car temp))
    (setq comment-e (cadr temp))
    (if (or (not comment-b)
            (not comment-e))
        (when try-whole-box
          (progn
            (goto-char orig-p)
            (when (and (bolp)
                       (not (bobp)))
              (progn
                (backward-char)
                (setq temp (rebox-find-box-beg-end comment-only))
                (setq comment-b (car temp))
                (setq comment-e (cadr temp))
                (when (and comment-b
                           comment-e
                           (= comment-e orig-p))
                  (setq got-it t))))))
      (setq got-it t))
    (if got-it
        (narrow-to-region comment-b comment-e)
      (signal 'rebox-comment-not-found-error nil))))

(defun rebox-guess-language (my-comment-start-str)
  "Guess the language in use based on the comment-start character.

returns guess as single digit."
  (setq my-comment-start-str
        (cond ((stringp my-comment-start-str)
               my-comment-start-str)
              ((not my-comment-start-str)
               "")
              (t
               (error "invalid my-comment-start-str: %s" my-comment-start-str))))
  (let ((language 1)
        (index (1- (length rebox-regexp-start))))
    (while (not (zerop index))
      (if (string-match (aref rebox-regexp-start index) my-comment-start-str)
          (setq language index
                index 0)
        (setq index (1- index))))
    language))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                                ;;
;; Some caching is possible here to remember the last found style ;;
;; and try that first, etc.                                       ;;
;;                                                                ;;
;; However, computing time is cheap, my time is not.              ;;
;;                                                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun rebox-guess-style ()
  "Guess the current box style from the text in the whole (narrowed) buffer."
  (let ((style-data rebox-style-data)
        best-style best-weight)
    ;; Let's try all styles in turn.  A style has to match exactly to be
    ;; eligible.  More heavy is a style, more prone it is to be retained.
    (while style-data
      (let* ((style (caar style-data))
             (data (cdar style-data))
             (weight (aref data 0))
             (regexp1 (aref data 1))
             (regexp2 (aref data 2))
             (regexp3 (aref data 3))
             (min-lines (length (remove nil (list regexp1 regexp2 regexp3))))
             (limit (cond
                     ((and best-weight (<= weight best-weight))
                      nil)
                     ((< (count-lines (point-min) (point-max)) min-lines)
                      nil)
                     ((not regexp3)
                      (point-max))
                     ((progn (goto-char (point-max))
                             (forward-line -1)
                             (looking-at regexp3))
                      (point)))))
        (when limit
          (goto-char (point-min))
          (cond ((not regexp1))
                ((looking-at regexp1) (goto-char (match-end 0)))
                (t (setq limit nil)))
          (when (and limit regexp2)
            (while (and (< (point) limit) (looking-at regexp2))
              (goto-char (match-end 0)))
            (unless (= (point) limit)
              (setq limit nil)))
          (when limit
            (setq best-style style
                  best-weight weight))))
      (setq style-data (cdr style-data)))
    best-style))

(defun* rebox-line-has-comment (&key (move-multiline t)
                                     (throw-label nil))
  (let ((bare-comment-end (and comment-end (rebox-rstrip (rebox-lstrip comment-end))))
        (bare-comment-start (and comment-start (rebox-rstrip (rebox-lstrip comment-start))))
        (starting-bol (point-at-bol))
        comment-start-pos
        )
    (end-of-line 1)
    (setq comment-start-pos (comment-beginning))
    (unless comment-start-pos
      ;; C-style comments, we could be in the white space past comment end
      (when (and (stringp comment-end)
                 (not (equal comment-end "")))
        (goto-char (point-at-eol))
        (search-backward-regexp (concat (regexp-quote bare-comment-end)
                                        "[ \t]*$")
                                (point-at-bol)
                                t)
        (setq comment-start-pos (comment-beginning))))
    ;; detect mid-line comments
    (when comment-start-pos
      (goto-char comment-start-pos)
      (skip-chars-backward " \t")
      (unless (= (point) (point-at-bol))
        (signal 'rebox-mid-line-comment-found nil)))
    (if (and (< (point) starting-bol)
             (not move-multiline))
        (goto-char starting-bol))
    comment-start-pos))


(defun* rebox-regexp-quote (string &key (rstrip t) (lstrip t) (match-trailing-spaces t))
"Return a regexp matching STRING without its surrounding space,
maybe followed by spaces or tabs.  If STRING is nil, return the
empty regexp.

With no-rstrip specified, don't strip spaces to the right."
  (cond ((not string) "")
        ((not (stringp string))
         (error "debug me, rebox-regexp-quote got non-string %s" string))
        (t
         (and rstrip
              (setq string (rebox-rstrip string)))
         (and lstrip
              (setq string (rebox-lstrip string)))
         (setq string (regexp-quote string))
         (if match-trailing-spaces
             (concat string "[ \t]*")
           string))))


;; -lw-
;; when the box is just one character wide:
          ;;;;;;;
          ;; a ;;
          ;;;;;;;
;; if we make the regex 2 characters wide, it won't match.

(defun rebox-regexp-ruler (character)
  "Return a regexp matching one or more repetitions of CHARACTER,
maybe followed by spaces or tabs.  Is CHARACTER is nil, return
the empty regexp."
  (if character
      (concat (regexp-quote (make-string 1 character)) "+[ \t]*")
    ""))


(defun rebox-rstrip (string)
  "Return string with trailing spaces removed."
  (while (and (> (length string) 0)
              (memq (aref string (1- (length string))) '(?  ?\t)))
    (setq string (substring string 0 (1- (length string)))))
  string)

(defun rebox-lstrip (string)
  "Return string with leading spaces removed."
  (while (and (> (length string) 0)
              (memq (aref string 0) '(?  ?\t)))
    (setq string (substring string 1)))
  string
  )


;; Reconstruction of boxes.

(defun rebox-unbuild (style)
  (let* ((data (cdr (assq style rebox-style-data)))
         (merge-nw (aref data 4))
         (merge-se (aref data 5))
         (nw (aref data 6))
         (nn (aref data 7))
         (ne (aref data 8))
         (ww (aref data 9))
         (ee (aref data 10))
         (sw (aref data 11))
         (ss (aref data 12))
         (se (aref data 13))
         (nw-regexp (and nw (regexp-quote nw)))
         (ww-regexp (and ww (regexp-quote ww)))
         (sw-regexp (and sw (regexp-quote sw)))

         limit-m
         )
    ;; Clean up first line.
    (goto-char (point-min))
    (end-of-line)
    (skip-chars-backward " \t")
    (when ne
      (let ((start (- (point) (length ne))))
        (when (and (>= start (point-min))
                   (string-equal ne (buffer-substring start (point))))
          (delete-backward-char (length ne)))))
    (beginning-of-line)
    (when (and nw-regexp (search-forward-regexp nw-regexp (point-at-eol)))
        (replace-match (make-string (- (match-end 0) (match-beginning 0))
                                    ? )))
    (when nn
      (let ((count (skip-chars-forward (char-to-string nn))))
        (delete-char (- count))
        (insert (make-string count ? ))))

    ;; Clear the top border line.
    ;;
    ;; If there was any top border, clear it.  I used to try to keep
    ;; text on the top border like the C-style comments:
    ;;
    ;; /* {Title}
    ;;  *  text
    ;;  */
    ;;
    ;; However, when you unbox and then rebox, it becomes unclear whether
    ;; {Title} should be in the top border or the box itself.

    (when (or nw-regexp nn ne)
      (goto-char (point-at-bol))
      (if (looking-at-p rebox-blank-line-regexp)
          (delete-region (point) (point-at-bol 2))
        (error "Top border should be clear now.  Debug me.")))
    ;; Clean up last line.
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (when se
      (let ((start (- (point) (length se))))
        (when (and (>= start (point-min))
                   (string-equal se (buffer-substring start (point))))
          (delete-backward-char (length se)))))
    (forward-line 0)
    (when (and sw-regexp (search-forward-regexp sw-regexp (point-at-eol)))
        (replace-match (make-string (- (match-end 0) (match-beginning 0))
                                    ? )))
    (when ss
      (let ((count (skip-chars-forward (char-to-string ss))))
        (delete-char (- count))
        (insert (make-string count ? ))))
    (setq limit-m (make-marker))
    ;; if there was any bottom border, and it's now just blanks, delete bottom line
    (if (or se sw-regexp ss)
        (progn
          (goto-char (point-at-bol))
          (if (looking-at-p rebox-blank-line-regexp)
              (delete-region (point) (point-at-bol 2))
            (error "Top border should be clear now.  Debug me."))
          (set-marker limit-m (point)))
      (set-marker limit-m (1+ (point))))
    ;; Clean up all lines.
    (goto-char (point-min))
    (while (< (point) limit-m)
      (end-of-line)
      (skip-chars-backward " \t")
      (when ee
        (let ((start (- (point) (length ee))))
          (when (and (>= start (point-min))
                     (string-equal ee (buffer-substring start (point))))
            (delete-backward-char (length ee)))))
      (beginning-of-line)
      (when (and ww-regexp (search-forward-regexp ww-regexp (point-at-eol)))
          (replace-match (make-string (- (match-end 0) (match-beginning 0))
                                      ? )))
      (forward-line 1))))


(defun rebox-build (refill margin style marked-point move-point)
"After refilling it if REFILL is not nil, while respecting a left MARGIN,
put the narrowed buffer back into a boxed comment according to
box STYLE."
  (let* ((data (cdr (assq style rebox-style-data)))
         (merge-nw (aref data 4))
         (merge-se (aref data 5))
         (nw (aref data 6))
         (nn (aref data 7))
         (ne (aref data 8))
         (ww (aref data 9))
         (ee (aref data 10))
         (sw (aref data 11))
         (ss (aref data 12))
         (se (aref data 13))
         right-margin
         count-trailing-spaces
         limit-m
         )

    ;; Merge a short end delimiter now, so it gets refilled with text.
    (if merge-se
        (progn
          (goto-char (point-max))
          (insert "\n")
          (goto-char (1- (point-max)))
          (setq limit-m (point-marker))
          (insert (make-string margin ? )
                  se)
          (setq se nil))
      (setq limit-m (point-max-marker)))
    ;; Possibly refill, and adjust margins to account for left inserts.
    (if refill
        (let (;;;; whatever adaptive filling should take care of this
              (fill-prefix nil)
              ;; In a box, we don't want mode-specific fill functions
              (fill-paragraph-function (if (or (not comment-start)
                                               (equal "" comment-start)
                                               (memq major-mode rebox-hybrid-major-modes))
                                           fill-paragraph-function
                                         nil))
              (fill-column (- fill-column (+ (length ww) (length ee) margin)))
              ;; some filling functions will consult major-mode for filling
              ;; advice, we don't want this since we've removed the
              ;; comment-starts.
              (major-mode 'fundamental-mode)
              (comment-auto-fill-only-comments nil)
              )
          (if (eq refill 'auto-fill)
              (progn
                (setq count-trailing-spaces marked-point)
                (goto-char marked-point)
                (do-auto-fill))
            (setq count-trailing-spaces nil)
            (fill-region (point-min) limit-m)))
      (setq count-trailing-spaces marked-point))
    (setq right-margin (max (+ (rebox-right-margin :count-trailing-spaces count-trailing-spaces)
                               (length ww)
                               margin)
                            ;; minimum box width is 1
                            (1+ (length ww))))
    ;; Construct the top line.
    (goto-char (point-min))
    (cond (merge-nw
           (insert (make-string (- margin (current-column)) ? )
                   nw)
           (insert "\n"))
          ((or nw nn ne)
           (indent-to margin)
           (when nw
             (insert nw))
           (if (not (or nn ne))
               (delete-char (- (skip-chars-backward " ")))
             (insert (make-string (- right-margin (current-column))
                                  (or nn ? )))
             (when ne
               (insert ne)))
           (insert "\n")))
    ;; Construct all middle lines.
    (while (< (point) limit-m)
      (when (or ww ee (/= (following-char) ?\n))
        (insert (make-string (- margin (current-column)) ? ))
        (when ww
          (insert ww))
        (when ee
          (end-of-line)
          (indent-to right-margin)
          (insert ee)
          (delete-char (- (skip-chars-backward " ")))))
      (forward-line 1))
    ;; Construct the bottom line.
    (when (or sw ss se)
      (indent-to margin)
      (when sw
        (insert sw))
      (if (not (or ss se))
          (delete-char (- (skip-chars-backward " ")))
        (insert (make-string (- right-margin (current-column))
                             (or ss ? )))
        (when se
          (insert se)))
      (insert "\n"))

    (goto-char marked-point)
    (when move-point
      ;; figure out if we've moved the marked-point to an unreasonable position
      (let* ((my-col (current-column))
             (my-line (line-number-at-pos))
             (point-max-line (line-number-at-pos (point-max)))
             (min-line (if (or merge-nw nw nn ne)
                           2
                         1))
             (max-line (if (or merge-se sw ss se)
                           (- point-max-line 2)
                         (- point-max-line 1)))
             (min-col (+ margin (length ww)))
             (max-col right-margin)
             temp
             )
        ;; move vertically
        (cond ((< my-line min-line)
               (forward-line 1))
              ((> my-line max-line)
               (goto-char (point-min))
               (forward-line (1- max-line))))
        ;; move horizontally
        (cond ((< my-col min-col)
               (beginning-of-line)
               (forward-char min-col)
               (setq temp (skip-chars-forward " \t"))
               ;; nothing but space on this line
               (when (looking-at-p (concat (regexp-quote (if ee
                                                             (rebox-lstrip ee)
                                                           ""))
                                           "[ \t]*$"))
                 (backward-char temp)))
              ((> my-col max-col)
               (goto-char (+ (point-at-bol) max-col))
               (setq temp (skip-chars-backward " \t"))
               (when (< (current-column) min-col)
                 (beginning-of-line)
                 (forward-char min-col)))))
      (unless (= (point) marked-point)
        (set-marker marked-point (point))))
    ))


(defun rebox-left-margin ()
"Return the minimum value of the left margin of all lines, or -1 if
all lines are empty."
  (let ((margin -1))
    (goto-char (point-min))
    (while (and (not (zerop margin)) (not (eobp)))
      (skip-chars-forward " \t")
      (let ((column (current-column)))
        (and (not (= (following-char) ?\n))
             (or (< margin 0) (< column margin))
             (setq margin column)))
      (forward-line 1))
    margin))


(defun* rebox-right-margin (&key (count-trailing-spaces t))
  "Return the maximum value of the right margin of all lines.

COUNT-TRAILING-SPACES may be a marker, in which case only spaces
on that line, up to that marker will be counted.  nil to never
count trailing spaces or t to always count.

"
  (let ((margin 0))
    (when (markerp count-trailing-spaces)
      (when (progn (goto-char count-trailing-spaces)
                   (looking-at "[ \t]*$"))
        (setq margin (current-column)))
      (setq count-trailing-spaces nil))
    (goto-char (point-min))
    (while (not (eobp))
      (end-of-line)
      (unless count-trailing-spaces
        (skip-chars-backward " \t"))
      (setq margin (max margin (current-column)))
      (forward-line 1))
    (unless count-trailing-spaces
      ;; we iterate through lines twice to avoid excess damage to markers
      (goto-char (point-min))
      (while (not (eobp))
        (end-of-line)
        (when (> (current-column) margin)
          (delete-char (- margin (current-column))))
        (forward-line 1)))
    margin))

(defun rebox-get-newline-indent-function ()
  "return preferred newline-and-indent function"
  (setq rebox-newline-indent-function
        (or rebox-newline-indent-function
            (cdr (assq major-mode rebox-newline-indent-function-alist))
            rebox-newline-indent-function-default)))

(defun rebox-save-env ()
  "save some settings"
  (unless rebox-save-env-done
    (setq rebox-save-env-alist nil)
    (mapc (lambda (var)
            (push (cons var (symbol-value var)) rebox-save-env-alist))
          rebox-save-env-vars)
    (push (cons 'meta-c-func (lookup-key global-map [(meta c)])) rebox-save-env-alist)
    (setq rebox-save-env-done t)))

(defun rebox-restore-env ()
  "load some settings"
  (mapc (lambda (var)
          (set var (cdr (assq var rebox-save-env-alist))))
        rebox-save-env-vars))

;;; Initialize the internal structures.

(rebox-register-all-templates)

(provide 'rebox2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; rebox2.el ends here
