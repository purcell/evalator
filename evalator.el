(require 'cl-lib)
(require 'evalator-context)
(require 'evalator-faces)
(require 'evalator-history)
(require 'evalator-key-map)
(require 'evalator-state)
(require 'helm)

(defvar evalator-candidates-initial '("Enter an expression below to generate initial data"))

;; TODO this approach doesn't work anymore
(defvar evalator-prompt-f
  (lambda (hist-ind hist-length)
    (let ((hist (format "%s of %s" (+ 1 hist-ind) hist-length))
          (sep "|")
          (expr-prompt "Expression:" ))
      (mapconcat 'identity `(,hist ,sep ,expr-prompt) " ")))
  "Points to a function that is called with the current history index
and length.  Will be used to generate the evalator prompt") 

(defun evalator-action-previous ()
  "Go to the next history state and update the evalator session."
  (interactive)
  (when (not (equal 0 (evalator-history-index)))
    (evalator-utils-put! evalator-state :history-index (+ -1 (evalator-history-index)))
    (helm-set-pattern "")
    (helm-update)))

(defun evalator-action-next ()
  "Go to the previous history state and update the evalator session."
  (interactive)
  (when (not (equal (+ -1 (length (evalator-history))) (evalator-history-index)))
    (evalator-utils-put! evalator-state :history-index (+ 1 (evalator-history-index)))
    (helm-set-pattern "")
    (helm-update)))

(defun evalator-action-confirm ()
  "Accepts results and starts a new evalator for further
transformation."
  (interactive)
  (let* ((err-handler (lambda ()
                        (message "Can't update, invalid expression")
                        nil))
         (candidates (evalator-transform-candidates
                      helm-pattern
                      (plist-get evalator-state :mode)
                      (slot-value (plist-get evalator-state :context) :make-candidates)
                      (slot-value (plist-get evalator-state :context) :transform-candidates)
                      err-handler)))
    (when candidates
      (evalator-history-push! candidates helm-pattern)
      (helm-set-pattern ""))))

(defun evalator-action-insert-special-arg ()
  "Inserts the special evalator arg into the expression prompt"
  (interactive)
  (insert (evalator-context-get-special-arg (plist-get evalator-state :context))))

(defun evalator-flash (status)
  "Changes the expression prompt face to 'evalator-(success | error)'
depending on the 'status' arg"
  (let ((f (if (equal :success status) 'evalator-success 'evalator-error)))
    (with-current-buffer (window-buffer (active-minibuffer-window))
      (face-remap-add-relative 'minibuffer-prompt f))))

(cl-defun evalator-marked-candidates (&key with-wildcard)
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

(defun evalator-persistent-help ()
  "Builds persistent help string"
  (cl-flet ((f (command)
               (key-description (where-is-internal command evalator-key-map t))))
    (concat "History forward, "
            (f 'evalator-action-previous)            ": History backward, "
            (f 'evalator-action-confirm)             ": Accept transformation, "
            (f 'evalator-action-insert-special-arg)  ": Insert special arg")))

(defun evalator-build-source (candidates mode)
  "Builds the source for a evalator session.  Accepts a list of
candidates."
  (helm-build-sync-source (concat "Evaluation Result" (when (equal :explicit mode) "(Explicit)"))
    :candidates candidates
    :filtered-candidate-transformer (lambda (_candidates _source)
                                      (with-helm-current-buffer
                                        (evalator-transform-candidates
                                         helm-pattern
                                         (plist-get evalator-state :mode)
                                         (slot-value (plist-get evalator-state :context) :make-candidates)
                                         (slot-value (plist-get evalator-state :context) :transform-candidates))))
    :keymap evalator-key-map
    :nohighlight t
    :nomark (equal :explicit mode)
    :persistent-help (evalator-persistent-help)
    :volatile t))

(defun evalator-transform-candidates (expr mode make-f transform-f &optional err-handler)
  ""
  (let ((cands-all (evalator-history-current :candidates))
        (cands-marked (evalator-marked-candidates)))
    (condition-case err
        (progn (evalator-flash :success)
               (if (equal 0 (evalator-history-index))
                   (progn (funcall make-f expr mode))
                 (funcall transform-f cands-all cands-marked expr mode)))
      (error
       (if err-handler
           (funcall err-handler)
         (progn
           (evalator-flash :error)
           cands-all))))))

(defun evalator-insert-equiv-expr (&optional exprs)
  "Inserts the equivalent expression of the previous evalator
session.  NOTE: Session must have been run with 'evalator-explicit'
for this to work."
  (interactive)
  (insert (funcall
           (slot-value (plist-get evalator-state :context) :make-equiv-expr)
           (or (evalator-history-expression-chain) exprs))))

(defun evalator-resume ()
  "Resumes last evalator session."
  (interactive)
  (helm-resume "*helm-evalator*"))

(defun evalator (&optional mode)
  "Starts a helm session for interactive evaluation and transformation
of input data"
  (interactive)
  (evalator-state-init mode)
  (evalator-history-push! evalator-candidates-initial "")

  (let* ((helm-mode-line-string "")
         (source (evalator-build-source evalator-candidates-initial mode)))
    (helm :sources source
          :buffer "*evalator*"
          :prompt "Enter Expression:")))

(defun evalator-explicit ()
  (interactive)
  (evalator :explicit))

(provide 'evalator)

;; Dev
;; TODO comment or remove these when development done
;; (defun evalator-dev-reload-elisp ()
;;   (interactive)
;;   (let ((contextel "evalator-context.el")
;;         (elispel "evalator-context-elisp.el")
;;         (evalatorel "evalator.el"))
;;     (with-current-buffer contextel
;;       (save-buffer)
;;       (eval-buffer))
;;     (with-current-buffer elispel
;;       (save-buffer)
;;       (eval-buffer))
;;     (with-current-buffer evalatorel
;;       (save-buffer)
;;       (eval-buffer))
;;     (setq evalator-state (plist-put evalator-state :context evalator-context-elisp))))

;; (defun evalator-dev-reload-cider ()
;;   (interactive)
;;   (let ((ciderclj "evalator-context-cider.clj")
;;         (ciderel "evalator-context-cider.el")
;;         (testclj "test.clj")
;;         (lambdael "evalator.el"))
;;     (with-current-buffer ciderclj
;;       (save-buffer)
;;       (cider-eval-buffer))
;;     (with-current-buffer testclj
;;       (save-buffer)
;;       (cider-eval-buffer))
;;     (with-current-buffer ciderel
;;       (save-buffer)
;;       (eval-buffer))
;;     (setq evalator-state (plist-put evalator-state :context evalator-context-cider))))

;; (defun evalator-dev ()
;;   (interactive)
;;   (evalator-dev-reload)
;;   (evalator :initp t :hist-pushp t))

