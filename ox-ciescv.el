;;; ox-ciescv.el --- Org export backend for Cies Resume/CV LaTeX template -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 George Kallitsounakis
;;
;; Author: George Kallitsounakis <mgkallits@gmail.com>
;; Maintainer: George Kallitsounakis <mgkallits@gmail.com>
;; Created: February 17, 2026
;; Modified: February 17, 2026
;; Version: 0.1.0
;; Keywords: org wp tex
;; Homepage: https://github.com/mgkallits/ox-ciescv
;; Package-Requires: ((emacs "27.1") (org "9.5"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; This library implements a LaTeX export backend for Org mode derived
;; from the standard LaTeX backend.  It produces resumes and CVs
;; following the structure of the Cies Resume/CV template.
;;
;; The backend is invoked automatically when you set #+LATEX_CLASS: ciescv
;; in your Org buffer and export via C-c C-e l p (Export to LaTeX PDF).
;; No additional keybindings or menu entries are required.
;;
;; USAGE:
;;
;; 1. Add to your init file:
;;      (require 'ox-ciescv)
;;    or with use-package:
;;      (use-package ox-ciescv)
;;
;; 2. In your CV buffer, add:
;;      #+LATEX_CLASS: ciescv
;;      #+FIRSTNAME: Your
;;      #+LASTNAME: Name
;;      #+EMAIL: you@example.com
;;      #+PHONE: +1 234 567 8900
;;      (and other metadata fields)
;;
;; 3. Export with C-c C-e l p
;;
;; HEADLINE STRUCTURE:
;;
;;   CV_ENV: summary  → two-column summary block
;;   CV_ENV: cventry  → position/degree entry with date range
;;   CV_ENV: skills   → skills section with inline subsections
;;   Level 1 (no CV_ENV) → top-level section wrapper (Experience, Education)
;;   Level 2 (no CV_ENV) → employer/institution block
;;
;; See README.org for detailed documentation and examples.
;;
;;; Code:

(require 'ox-latex)
(require 'org)
(require 'ox)
(require 'org-element)

;;; LaTeX Preamble

(defconst org-ciescv--preamble
  "\\documentclass[10pt,a4paper]{article}
[NO-DEFAULT-PACKAGES]
[NO-PACKAGES]
[EXTRA]

%%% LOAD AND SETUP PACKAGES

\\usepackage[margin=0.75in]{geometry}
\\usepackage{multicol}
\\usepackage{mdwlist}
\\usepackage{relsize}
\\usepackage{hyperref}
\\usepackage{xcolor}

\\definecolor{dark-blue}{rgb}{0.15,0.15,0.4}
\\hypersetup{colorlinks, linkcolor={dark-blue}, citecolor={dark-blue}, urlcolor={dark-blue}}

\\usepackage[T1]{fontenc}
\\usepackage{microtype}

\\pagestyle{empty}

%----------------------------------------------------------------------------------------
%\tLENGTHS
%----------------------------------------------------------------------------------------

\\newlength{\\newparindent}
\\addtolength{\\newparindent}{\\parindent}

\\newlength{\\doubleparindent}
\\addtolength{\\doubleparindent}{\\parindent}

%----------------------------------------------------------------------------------------
%\tSTRUCTURAL COMMANDS
%----------------------------------------------------------------------------------------

% Indented list environment used by all section commands.
\\newenvironment{indentsection}
  {\\begin{list}{}
    {\\setlength{\\leftmargin}{\\newparindent}
     \\setlength{\\parsep}{3pt}
     \\setlength{\\parskip}{0pt}
     \\setlength{\\itemsep}{0pt}
     \\setlength{\\topsep}{0pt}}}
  {\\end{list}}

% Main title (name) with date of birth or subtitle
\\newcommand*\\maintitle[2]{
  \\noindent{\\LARGE \\textbf{#1}}\\ \\ \\ \\emph{#2}\\vspace{0.3em}}

% Top level section title
\\newcommand*\\roottitle[1]{
  \\subsection*{#1}\\vspace{-0.3em}\\nopagebreak[4]}

% Section title used for a new employer.
\\newcommand{\\headedsection}[3]{
  \\nopagebreak[4]
  \\begin{indentsection}
    \\item[]\\textscale{1.1}{#1}\\hfill#2\\par#3
  \\end{indentsection}
  \\nopagebreak[4]}

% Section title used for a new position.
\\newcommand{\\headedsubsection}[3]{
  \\nopagebreak[4]
  \\begin{indentsection}
    \\item[]\\textbf{#1}\\hfill\\emph{#2}\\par#3
  \\end{indentsection}
  \\nopagebreak[4]}

% Body text (indented)
\\newcommand{\\bodytext}[1]{
  \\nopagebreak[4]
  \\begin{indentsection}
    \\item[]\\setlength{\\parskip}{0.4em}#1
  \\end{indentsection}
  \\pagebreak[2]}

% Section title where body text starts immediately after (used for skills)
\\newcommand{\\inlineheadsection}[2]{
  \\begin{basedescript}{\\setlength{\\leftmargin}{\\doubleparindent}}
    \\item[\\hspace{\\newparindent}\\textbf{#1}]#2
  \\end{basedescript}
  \\vspace{-1.6em}}

% Custom acronyms command
\\newcommand*\\acr[1]{\\textscale{.85}{#1}}

% Custom bullet point for separating contact info items
\\newcommand*\\bull{\\ \\ \\raisebox{-0.365em}[-1em][-1em]{\\textscale{4}{$\\cdot$}} \\ }

% Vspace variants that interact with page breaking
\\newcommand{\\breakvspace}[1]{\\pagebreak[2]\\vspace{#1}\\pagebreak[2]}
\\newcommand{\\nobreakvspace}[1]{\\nopagebreak[4]\\vspace{#1}\\nopagebreak[4]}

% Horizontal rule with configurable space before (#1) and after (#2)
\\newcommand{\\spacedhrule}[2]{\\breakvspace{#1}\\hrule\\nobreakvspace{#2}}"
  "Self-contained LaTeX preamble for the ciescv class.
Embedded directly into `org-latex-classes' so no external
structure.tex file is needed.")

;;; LaTeX Class Registration

(assoc-delete-all "ciescv" org-latex-classes)
(add-to-list 'org-latex-classes
             `("ciescv"
               ,org-ciescv--preamble
               ("\\roottitle{%s}" . "\\roottitle*{%s}")
               ("\\headedsection{%s}{}{}" . "\\headedsection*{%s}{}{}")))

;;; Export Backend Definition

(org-export-define-derived-backend 'ciescv 'latex
  :options-alist
  '((:latex-class "LATEX_CLASS" nil "ciescv" t)
    (:firstname "FIRSTNAME" nil nil t)
    (:lastname  "LASTNAME"  nil nil t)
    (:birthdate "BIRTHDATE" nil nil t)
    (:email     "EMAIL"     nil nil t)
    (:phone     "PHONE"     nil nil parse)
    (:mobile    "MOBILE"    nil nil parse)
    (:website   "WEBSITE"   nil nil parse)
    (:address   "ADDRESS"   nil nil parse)
    (:city      "CITY"      nil nil parse)
    (:state     "STATE"     nil nil parse)
    (:country   "COUNTRY"   nil nil parse)
    (:github    "GITHUB"    nil nil parse)
    (:linkedin  "LINKEDIN"  nil nil parse)
    (:with-email nil "email" t t))
  :translate-alist
  '((template   . org-ciescv-template)
    (headline   . org-ciescv-headline)
    (paragraph  . org-ciescv-paragraph)
    (plain-list . org-ciescv-plain-list)
    (section    . org-ciescv-section)))

;;; Utility: structure.tex Generator

(defconst org-ciescv--structure-tex-content
  (concat
   "% Structure file for Cies CV LaTeX class.\n"
   "% Generated by M-x org-ciescv-write-structure-file\n"
   "% Based on the Cies Resume/CV template (MIT License, Cies Breijs 2012).\n\n"
   (replace-regexp-in-string
    "\\\\documentclass[^\n]*\n\\(\\[NO-DEFAULT-PACKAGES\\]\n\\[NO-PACKAGES\\]\n\\[EXTRA\\]\n\n\\)?"
    ""
    org-ciescv--preamble))
  "Standalone structure.tex content for manual use.")

;;;###autoload
(defun org-ciescv-write-structure-file (&optional dir)
  "Write (or overwrite) structure.tex into DIR.
This file is no longer required for export (the preamble is embedded
in the class definition), but may be useful for manual LaTeX workflows.
Interactively, prompts for the target directory."
  (interactive
   (list (read-directory-name "Write structure.tex to: "
                              (or (and (buffer-file-name)
                                       (file-name-directory (buffer-file-name)))
                                  default-directory))))
  (let ((dest (expand-file-name "structure.tex" (or dir default-directory))))
    (with-temp-file dest
      (insert org-ciescv--structure-tex-content))
    (message "ox-ciescv: wrote %s" dest)))

;;; Template

(defun org-ciescv-template (contents info)
  "Return complete document string after LaTeX conversion.
CONTENTS is the transcoded contents string.  INFO is a plist
holding export options."
  (concat
   (and (plist-get info :time-stamp-file)
        (format-time-string "%% Created %Y-%m-%d %a %H:%M\n"))
   (org-latex--insert-compiler info)
   (org-latex-make-preamble info)
   "\\begin{document}\n"
   (org-ciescv--header info)
   "\\spacedhrule{0.9em}{-0.4em}\n"
   contents
   "\n\\end{document}"))

;;; Phone Formatting

(defun org-ciescv--format-phone (raw)
  "Format RAW phone string for Cies CV output.
Wraps leading + in \\textsmaller and uses lining figures."
  (cond
   ((string-match "^(\\+\\([^)]+\\))\\s-*\\(.*\\)$" raw)
    (format "(\\textsmaller{+}{\\addfontfeatures{Numbers=Lining}%s}) {\\addfontfeatures{Numbers=Lining}%s}"
            (match-string 1 raw)
            (string-trim (match-string 2 raw))))
   ((string-match "^\\+\\(.*\\)$" raw)
    (format "\\textsmaller{+}{\\addfontfeatures{Numbers=Lining}%s}"
            (match-string 1 raw)))
   (t (format "{\\addfontfeatures{Numbers=Lining}%s}" raw))))

;;; Header Generation

(defun org-ciescv--header (info)
  "Generate Cies CV header from INFO plist.
Name is built from FIRSTNAME + LASTNAME when either is set,
falling back to the #+AUTHOR keyword if both are absent."
  (let* ((first    (org-export-data (plist-get info :firstname) info))
         (last     (org-export-data (plist-get info :lastname)  info))
         (author   (org-export-data (plist-get info :author)    info))
         (name     (let ((fn-ln (string-join
                                 (delq nil
                                       (list (and (org-string-nw-p first) first)
                                             (and (org-string-nw-p last)  last)))
                                 " ")))
                     (if (org-string-nw-p fn-ln) fn-ln (or author ""))))
         (birthdate (org-export-data (plist-get info :birthdate) info))
         (mail     (and (plist-get info :with-email)
                        (org-export-data (plist-get info :email) info)))
         (phone-raw (let ((p (org-export-data (plist-get info :phone)  info))
                          (m (org-export-data (plist-get info :mobile) info)))
                      (cond ((org-string-nw-p p) p)
                            ((org-string-nw-p m) m)
                            (t nil))))
         (phone    (when phone-raw (org-ciescv--format-phone phone-raw)))
         (website  (org-export-data (plist-get info :website)  info))
         (address  (org-export-data (plist-get info :address)  info))
         (city     (org-export-data (plist-get info :city)     info))
         (state    (org-export-data (plist-get info :state)    info))
         (country  (org-export-data (plist-get info :country)  info))
         (github   (org-export-data (plist-get info :github)   info))
         (linkedin (org-export-data (plist-get info :linkedin) info))
         (contact-items '())
         (address-parts '()))

    (when (org-string-nw-p mail)
      (push (format "\\href{mailto:%s}{%s}" mail mail) contact-items))
    (when (org-string-nw-p phone)
      (push phone contact-items))
    (when (org-string-nw-p website)
      (push (format "\\href{%s}{%s}" website website) contact-items))
    (when (org-string-nw-p github)
      (push (format "\\href{https://github.com/%s}{github.com/%s}" github github) contact-items))
    (when (org-string-nw-p linkedin)
      (push (format "\\href{https://linkedin.com/in/%s}{linkedin.com/in/%s}" linkedin linkedin) contact-items))
    (setq contact-items (reverse contact-items))

    (when (org-string-nw-p address) (push address address-parts))
    (when (org-string-nw-p city)    (push city    address-parts))
    (when (org-string-nw-p state)   (push state   address-parts))
    (when (org-string-nw-p country) (push country address-parts))
    (setq address-parts (reverse address-parts))

    (concat
     (format "\\maintitle{%s}{%s}\n\n" name (or birthdate ""))
     "\\noindent"
     (if contact-items (mapconcat #'identity contact-items "\\bull ") "")
     "\\\\\n"
     (if address-parts (concat (mapconcat #'identity address-parts "\\bull ") "\n") "\n"))))

;;; Language Detection

(defun org-ciescv--detect-language (info)
  "Detect language from LaTeX headers in INFO plist.
Returns \\='el for Greek or \\='en for English (default)."
  (let* ((latex-header (or (plist-get info :latex-header) ""))
         (all-latex (concat latex-header "\n" (org-latex-make-preamble info))))
    (cond
     ((string-match "\\\\setdefaultlanguage\\s-*{\\s-*greek\\s-*}" all-latex) 'el)
     ((string-match "\\\\setdefaultlanguage\\s-*{\\s-*english\\s-*}" all-latex) 'en)
     ((string-match "\\\\usepackage\\[greek\\]" all-latex) 'el)
     ((string-match "\\\\usepackage\\[english\\]" all-latex) 'en)
     (t 'en))))

;;; Date Formatting

(defconst org-ciescv--greek-months
  '((1 . "Ιαν") (2 . "Φεβ") (3 . "Μαρ") (4 . "Απρ")
    (5 . "Μαϊ") (6 . "Ιουν") (7 . "Ιουλ") (8 . "Αυγ")
    (9 . "Σεπτ") (10 . "Οκτ") (11 . "Νοε") (12 . "Δεκ"))
  "Greek month abbreviations.")

(defconst org-ciescv--english-months
  '((1 . "Jan") (2 . "Feb") (3 . "Mar") (4 . "Apr")
    (5 . "May") (6 . "Jun") (7 . "Jul") (8 . "Aug")
    (9 . "Sep") (10 . "Oct") (11 . "Nov") (12 . "Dec"))
  "English month abbreviations.")

(defun org-ciescv--get-present-string (info)
  "Return localised string for \\='present\\='."
  (if (eq (org-ciescv--detect-language info) 'el) "Σήμερα" "present"))

(defun org-ciescv--format-date (date-str info)
  "Convert DATE-STR to Mon \\='YY format using the document language."
  (cond
   ((member date-str '("Σήμερα" "Today" "present" "now" "Present" "Now"))
    (org-ciescv--get-present-string info))
   ((string-match "<\\([0-9]+\\)-\\([0-9]+\\)-[0-9]+>" date-str)
    (let* ((year      (match-string 1 date-str))
           (month-num (string-to-number (match-string 2 date-str)))
           (lang      (org-ciescv--detect-language info))
           (abbr      (if (eq lang 'el)
                          (alist-get month-num org-ciescv--greek-months)
                        (alist-get month-num org-ciescv--english-months))))
      (format "%s '%s" abbr (substring year 2))))
   ((string-match "<\\([0-9]+\\)>" date-str)
    (match-string 1 date-str))
   (t date-str)))

(defun org-ciescv--format-education-date (date-str info)
  "Format date for education (year only)."
  (cond
   ((member date-str '("Σήμερα" "Today" "present" "now" "Present" "Now"))
    (org-ciescv--get-present-string info))
   ((string-match "<\\([0-9]+\\)-[0-9]+-[0-9]+>" date-str)
    (match-string 1 date-str))
   ((string-match "<\\([0-9]+\\)>" date-str)
    (match-string 1 date-str))
   (t date-str)))

;;; CV Entry Formatting

(defun org-ciescv--format-cventry (headline contents info)
  "Format HEADLINE as a \\headedsubsection CV entry."
  (let* ((title   (org-export-data (org-element-property :title headline) info))
         (from    (org-element-property :FROM     headline))
         (to      (org-element-property :TO       headline))
         (employer (org-element-property :EMPLOYER headline))
         (parent      (org-export-get-parent headline))
         (grandparent (when parent (org-export-get-parent parent)))
         (gp-title    (when grandparent
                        (org-export-data
                         (org-element-property :title grandparent) info)))
         (education-p (and gp-title
                           (string-match-p "Education\\|Εκπαίδευση" gp-title)))
         (fmt-fn  (if education-p
                      #'org-ciescv--format-education-date
                    #'org-ciescv--format-date))
         (from-s  (when from (funcall fmt-fn from info)))
         (to-s    (when to   (funcall fmt-fn to   info)))
         (date-str (cond
                    ((and from-s to-s) (format "%s -- %s" from-s to-s))
                    (from-s (format "%s -- %s" from-s
                                    (org-ciescv--get-present-string info)))
                    (t "")))
         (body (if education-p
                   (if (org-string-nw-p employer)
                       (format "\\emph{%s}\\bodytext{%s}"
                               (org-export-data employer info)
                               (string-trim contents))
                     (format "\\bodytext{%s}" (string-trim contents)))
                 (format "\\bodytext{%s}" (string-trim contents)))))
    (format "\\headedsubsection\n{%s}\n{%s}\n{%s}\n" title date-str body)))

;;; Summary Section Formatting

(defun org-ciescv--format-summary (headline contents info)
  "Format HEADLINE as a two-column \\begin{multicols} summary block."
  (let* ((paras (split-string (string-trim contents) "\n\n+" t))
         (body  (if (null paras)
                    (concat "\\noindent " (string-trim contents))
                  (concat
                   "\\noindent " (string-trim (car paras)) "\\\\\n\n"
                   (when (cadr paras)
                     (concat "\\noindent " (string-trim (cadr paras)) "\n\n"))
                   (when (cddr paras)
                     (mapconcat (lambda (p) (string-trim p))
                                (cddr paras)
                                "\n\n"))))))
    (format "\\roottitle{%s}\n\\vspace{-1.3em}\n\\begin{multicols}{2}\n%s\n\\end{multicols}\n\\spacedhrule{0.5em}{-0.4em}\n"
            (org-export-data (org-element-property :title headline) info)
            body)))

;;; Skills Section Formatting

(defun org-ciescv--format-skills (headline contents info)
  "Format HEADLINE as a skills block."
  (let* ((title   (org-element-property :title headline))
         (level   (org-export-get-relative-level headline info))
         (is-last (org-ciescv--last-section-p headline info)))
    (if (= level 1)
        (let ((hrule-space (if (string-match-p "\\\\inlineheadsection"
                                               (or contents ""))
                               "1.6em" "0.5em")))
          (concat
           (format "\\roottitle{%s}\n" (org-export-data title info))
           contents
           (unless is-last
             (format "\\spacedhrule{%s}{-0.4em}\n" hrule-space))))
      (format "\\inlineheadsection\n{%s:}\n{%s}\n"
              (org-export-data title info)
              (string-trim (or contents ""))))))

;;; Utility: Last Section Predicate

(defun org-ciescv--last-section-p (headline info)
  "Return non-nil if HEADLINE is the last top-level section."
  (when (= (org-export-get-relative-level headline info) 1)
    (let ((next (org-export-get-next-element headline info)))
      (or (null next)
          (not (and (eq (org-element-type next) 'headline)
                    (= (org-export-get-relative-level next info) 1)))))))

;;; Transcoders

(defun org-ciescv-paragraph (paragraph contents info)
  "Transcode PARAGRAPH into Cies CV LaTeX."
  (when (org-string-nw-p contents)
    (let* ((grand (org-export-get-parent (org-export-get-parent paragraph)))
           (tags  (and grand
                       (eq (org-element-type grand) 'headline)
                       (org-export-get-tags grand info)))
           (latex (org-export-with-backend 'latex paragraph contents info))
           (fixed (replace-regexp-in-string
                   "\\\\textbf{\\\\textbf{\\([^}]+\\)}}"
                   "\\\\textbf{\\1}"
                   latex)))
      (if (member "cventry" tags)
          (replace-regexp-in-string "\\\\par\\s-*$" "" fixed)
        fixed))))

(defun org-ciescv-section (section contents info)
  "Pass section CONTENTS through unchanged."
  contents)

(defun org-ciescv-plain-list (plain-list contents info)
  "Transcode PLAIN-LIST into a LaTeX list environment."
  (let ((env  (pcase (org-element-property :type plain-list)
                ('ordered     "enumerate")
                ('descriptive "description")
                (_            "itemize")))
        (body (replace-regexp-in-string "\n\n+" "\n" (or contents ""))))
    (format "\\begin{%s}\n%s\\end{%s}" env body env)))

(defun org-ciescv-headline (headline contents info)
  "Transcode HEADLINE element into Cies CV LaTeX."
  (unless (org-element-property :footnote-section-p headline)
    (let ((level  (org-export-get-relative-level headline info))
          (tags   (org-export-get-tags headline info))
          (title  (org-element-property :title headline))
          (cv-env (org-element-property :CV_ENV headline))
          (parent (org-export-get-parent headline))
          (is-last (org-ciescv--last-section-p headline info)))
      (cond
       ((or (member "summary" tags) (string= cv-env "summary"))
        (org-ciescv--format-summary headline contents info))

       ((or (member "cventry" tags) (string= cv-env "cventry"))
        (org-ciescv--format-cventry headline contents info))

       ((or (member "skills" tags) (string= cv-env "skills"))
        (org-ciescv--format-skills headline contents info))

       ((and parent
             (eq (org-element-type parent) 'headline)
             (or (member "skills" (org-export-get-tags parent info))
                 (string= (org-element-property :CV_ENV parent) "skills")))
        (org-ciescv--format-skills headline contents info))

       ((= level 1)
        (concat
         (format "\\roottitle{%s}\n" (org-export-data title info))
         contents
         (unless is-last "\\spacedhrule{0.5em}{-0.4em}\n")))

       ((= level 2)
        (let ((employer-name (org-export-data title info))
              (location (org-element-property :LOCATION headline))
              (url      (org-element-property :URL      headline)))
          (format "\\headedsection\n{%s}\n{%s} {\n%s}\n"
                  (if url (format "\\href{%s}{%s}" url employer-name) employer-name)
                  (if location
                      (format "\\textsc{%s}" (org-export-data location info))
                    "")
                  contents)))

       (t (org-export-with-backend 'latex headline contents info))))))

;;; Export Command

;;;###autoload
(defun org-ciescv-export-to-pdf
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to Cies CV LaTeX then process through to PDF."
  (interactive)
  (let ((outfile (org-export-output-file-name ".tex" subtreep)))
    (org-export-to-file 'ciescv outfile
      async subtreep visible-only body-only ext-plist
      (lambda (file) (org-latex-compile file)))))

;;; Automatic Backend Selection

(defun org-ciescv--buffer-latex-class ()
  "Return the #+LATEX_CLASS value for the current buffer, or nil.
Checks the file-level keyword first; falls back to the subtree
property at point to support per-subtree export."
  (or
   (save-excursion
     (goto-char (point-min))
     (when (re-search-forward "^#\\+LATEX_CLASS:\\s-*\\(\\S-+\\)" nil t)
       (match-string-no-properties 1)))
   (org-entry-get (point) "LATEX_CLASS" t)))

(defun org-ciescv--maybe-export-to-pdf (orig-fn &rest args)
  "Redirect to `org-ciescv-export-to-pdf' when #+LATEX_CLASS is ciescv.
ORIG-FN is `org-latex-export-to-pdf'; ARGS are forwarded unchanged."
  (if (string= (org-ciescv--buffer-latex-class) "ciescv")
      (apply #'org-ciescv-export-to-pdf args)
    (apply orig-fn args)))

(advice-add 'org-latex-export-to-pdf :around
            #'org-ciescv--maybe-export-to-pdf
            '((name . org-ciescv--lp-redirect)))

(provide 'ox-ciescv)

;;; Automatic Loading

;;;###autoload
(with-eval-after-load 'org
  (require 'ox-ciescv))

(provide 'ox-ciescv)

;;; ox-ciescv.el ends here
