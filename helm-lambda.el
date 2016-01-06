(require 'helm)
(require 'cl-lib)
;; TODO delete this when I move elisp config out to its own package/
(require 'helm-elisp)
(require 'helm-lambda-context)
(require 'helm-lambda-context-elisp)

(defvar helm-lambda-eval-context nil)
(defvar helm-lambda-history '())
(defvar helm-lambda-history-index -1)
(defvar helm-lambda-eval-context nil)
(defvar helm-lambda-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-i") 'helm-lambda-lookup)
    (define-key map (kbd "C-u") 'helm-lambda-confirm-application)
    (define-key map (kbd "C-j") 'helm-lambda-history-next)
    (define-key map (kbd "C-l") 'helm-lambda-history-previous)
    map))

;; TODO delete this when i separate elisp stuff
(setq helm-lambda-emacs-commands-and-functions
      (let ((sources `(,(helm-def-source--emacs-functions)
                       ,(helm-def-source--emacs-commands)))
            (partial (lambda (name f index)
                       `(lambda (src)
                          (helm-add-action-to-source ,name (quote ,f) src ,index)
                          src))))
        (mapcar (funcall partial "Identity" 'identity 0) sources)))

(cl-defun helm-lambda-marked-candidates (&key with-wildcard)
  "Same as 'helm-marked-candidates' except it returns nil 
if no candidates were marked."
  (with-current-buffer helm-buffer
    (let ((candidates
           (cl-loop with current-src = (helm-get-current-source)
                    for (source . real) in (reverse helm-marked-candidates)
                    when (equal (assq 'name source) (assq 'name current-src))
                    append (helm--compute-marked real source with-wildcard) 
                    into cands
                    finally return cands)))
      candidates)))

(defun helm-lambda-history-push! (data)
  (setq helm-lambda-history (cons data (subseq helm-lambda-history helm-lambda-history-index)))
  (setq helm-lambda-history-index 0))

(defun helm-lambda-history-pop! ()
  (setq helm-lambda-history (cdr helm-lambda-history))
  (let ((index (if (equal nil helm-lambda-history nil)
                   -1
                 (- 1 helm-lambda-history-index))))
    (setq helm-lambda-history-index index)))

(defun helm-lambda-history-clear! ()
  (setq helm-lambda-history '())
  (setq helm-lambda-history-index -1))

(defun helm-lambda-history-current ()
  (nth helm-lambda-history-index helm-lambda-history))

;; TODO There's currently a weird bug happening where spamming the history next
;; and previous actions will cause the helm session to shut down. Has to do with
;; let bindings being nested too deep.
(defun helm-lambda-history-next ()
  (interactive)
  (when (not (equal 0 helm-lambda-history-index))
    (setq helm-lambda-history-index (+ -1 helm-lambda-history-index))
    (helm-lambda-history-load)))

(defun helm-lambda-history-previous ()
  (interactive)
  (when (not (equal (+ -1 (length helm-lambda-history)) helm-lambda-history-index))
    (setq helm-lambda-history-index (+ 1 helm-lambda-history-index))
    (helm-lambda-history-load)))

(defun helm-lambda-lookup ()
  (interactive)
  (let ((item (helm :sources helm-lambda-emacs-commands-and-functions
                    :allow-nest t)))
    ;; TODO need to find a way that this opens with the same size as previous helm session.
    (insert item)))

(defun helm-lambda-history-load ()
  (let* ((source (helm-lambda-history-current))
         (candidates (helm-get-candidates source))
         (f (lambda (candidates _) (helm-lambda candidates nil))))
    (helm-exit-and-execute-action (apply-partially f candidates))))

(defun helm-lambda-confirm-application ()
  "Accepts results and starts a new helm-lambda for further
transformation."
  (interactive)
  (let ((source (helm-lambda-history-current))
        (candidates (helm-lambda-transform-candidates nil))
        (f (lambda (candidates _) (helm-lambda candidates t))))
    (helm-exit-and-execute-action (apply-partially f candidates))))

(defun helm-lambda-transform-candidates (should-try)
  (let* ((keyword (if should-try :transform-candidates-try :transform-candidates))
         (transform-func (slot-value helm-lambda-eval-context keyword)))
    (funcall
     transform-func
     helm-lambda-eval-context
     (helm-get-candidates (helm-lambda-history-current))
     (helm-lambda-marked-candidates)
     helm-pattern)))

(defun helm-lambda-build-source (candidates)
  (helm-build-sync-source "Evaluation Result"
    :volatile t
    :candidates candidates
    :filtered-candidate-transformer (lambda (_candidates _source)
                                      ;; TODO might be possible to move condition-case to this level
                                      (with-helm-current-buffer
                                        (helm-lambda-transform-candidates t)))
    :keymap helm-lambda-map
    :nohighlight t))

(defun helm-lambda (data &optional update-history)
  "Starts a helm session for interactive evaluation and transformation
of input data."
  (funcall (slot-value helm-lambda-eval-context :init))
  (let* ((candidates (funcall (slot-value helm-lambda-eval-context :make-candidates) data))
         (source (helm-lambda-build-source candidates)))
    (when update-history (helm-lambda-history-push! source))
    (helm :sources source
          :buffer "*helm-lambda*"
          :prompt "Expression: ")))

;; ;; Delete when development done
;; (setq helm-lambda-history '())
;; (setq helm-lambda-history-index -1)
;; (helm-lambda '(1 2 3 4))
;; helm-lambda-eval-context
;; helm-lambda-history
;; helm-lambda-history-index
;; (helm-lambda-history-current)

(provide 'helm-lambda)
