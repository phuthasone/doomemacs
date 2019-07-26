;;; core/cli/env.el -*- lexical-binding: t; -*-

(def-command! env (&rest args)
  "Regenerates your envvars file.

  doom env [-c|--clear]

If -c or --clear is present

Available switches:

  refresh  Create or regenerate your envvar file
  auto     enable auto-reloading of your envvars file (on `doom refresh`)
  clear    deletes your envvar file (if it exists) and disables auto-reloading

An envvars file (its location is controlled by the `doom-env-file' variable)
will contain a list of environment variables scraped from your shell environment
and loaded when Doom starts (if it exists). This is necessary when Emacs can't
be launched from your shell environment (e.g. on MacOS or certain app launchers
on Linux).

To generate a file, run `doom env refresh`. If you'd like this file to be
auto-reloaded when running `doom refresh`, run `doom env enable` instead (only
needs to be run once)."
  (let ((default-directory doom-emacs-dir))
    (when (member "clear" args)  ; DEPRECATED
      (message "'doom env clear' is deprecated. Use 'doom env -c' or 'doom env --clear' instead")
      (push "-c" args))

    (cond ((or (member "-c" args)
               (member "--clear" args))
           (unless (file-exists-p doom-env-file)
             (user-error! "%S does not exist to be cleared"
                          (relpath doom-env-file)))
           (delete-file doom-env-file)
           (print! (success "Successfully deleted %S")
                   (relpath doom-env-file)))

          ((null args)
           (doom-reload-env-file 'force))

          ((user-error "I don't understand 'doom env %s'"
                       (string-join args " "))))))


;;
;; Helpers

(defvar doom-env-ignored-vars
  '("^PWD$"
    "^PS1$"
    "^R?PROMPT$"
    "^DBUS_SESSION_BUS_ADDRESS$"
    "^GPG_AGENT_INFO$"
    "^SSH_AGENT_PID$"
    "^SSH_AUTH_SOCK$"
    ;; Doom envvars
    "^INSECURE$"
    "^DEBUG$"
    "^YES$")
  "Environment variables to not save in `doom-env-file'.

Each string is a regexp, matched against variable names to omit from
`doom-env-file'.")

(defvar doom-env-executable
  (if IS-WINDOWS
      "set"
    (executable-find "env"))
  "The program to use to scrape your shell environment with.
It is rare that you'll need to change this.")

(defvar doom-env-switches
  (if IS-WINDOWS
      "-c"
    "-ic") ; Execute in an interactive shell
  "The `shell-command-switch'es to use on `doom-env-executable'.
This is a list of strings. Each entry is run separately and in sequence with
`doom-env-executable' to scrape envvars from your shell environment.")

;; Borrows heavily from Spacemacs' `spacemacs//init-spacemacs-env'.
(defun doom-reload-env-file (&optional force-p)
  "Generates `doom-env-file', if it doesn't exist (or if FORCE-P).

This scrapes the variables from your shell environment by running
`doom-env-executable' through `shell-file-name' with `doom-env-switches'. By
default, on Linux, this is '$SHELL -ic /usr/bin/env'. Variables in
`doom-env-ignored-vars' are removed."
  (when (or force-p (not (file-exists-p doom-env-file)))
    (with-temp-file doom-env-file
      (print! (start "%s envvars file at %S")
               (if (file-exists-p doom-env-file)
                   "Regenerating"
                 "Generating")
               (relpath doom-env-file doom-emacs-dir))
      (let ((process-environment doom--initial-process-environment))
        (let ((shell-command-switch doom-env-switches)
              (error-buffer (get-buffer-create "*env errors*")))
          (print! (info "Scraping shell environment with '%s %s %s'")
                  (filename shell-file-name)
                  shell-command-switch
                  (filename doom-env-executable))
          (save-excursion
            (shell-command doom-env-executable (current-buffer) error-buffer))
          (print-group!
           (let ((errors (with-current-buffer error-buffer (buffer-string))))
             (unless (string-empty-p errors)
               (print! (info "Error output:\n\n%s") (indent 4 errors))))
           ;; Remove undesireable variables
           (while (re-search-forward "\n\\([^= \n]+\\)=" nil t)
             (save-excursion
               (let* ((valend (or (save-match-data
                                    (when (re-search-forward "^\\([^= ]+\\)=" nil t)
                                      (line-beginning-position)))
                                  (point-max)))
                      (var (match-string 1)))
                 (when (cl-loop for regexp in doom-env-ignored-vars
                                if (string-match-p regexp var)
                                return t)
                   (print! (info "Ignoring %s") var)
                   (delete-region (match-beginning 0) (1- valend)))))))
          (goto-char (point-min))
          (insert
           (concat
            "# -*- mode: dotenv -*-\n"
            (format "# Generated with: %s %s %s\n"
                    shell-file-name
                    doom-env-switches
                    doom-env-executable)
            "# ---------------------------------------------------------------------------\n"
            "# This file was auto-generated by `doom env refresh'. It contains a list of\n"
            "# environment variables scraped from your default shell (excluding variables\n"
            "# blacklisted in doom-env-ignored-vars).\n"
            "#\n"
            "# It is NOT safe to edit this file. Changes will be overwritten next time that\n"
            "# `doom env refresh` is executed. Alternatively, create your own env file and\n"
            "# load it with `(doom-load-envvars-file FILE)`.\n"
            "#\n"
            "# To auto-regenerate this file when `doom reload` is run, use `doom env auto' or\n"
            "# set DOOMENV=1 in your shell environment/config.\n"
            "# ---------------------------------------------------------------------------\n\n"))
          (print! (success "Successfully generated %S")
                  (relpath doom-env-file doom-emacs-dir))
          t)))))
