(require 'evalator-context)
(require 'eieio)

(defun evalator-context-elisp-substitute-special-args (expr c)
  "Walks through the expression and replaces any special args with
their proper value."
  (cl-labels ((rgx ()
                   (format "%s[0-9]*" evalator-context-special-arg-default))
              
              (quote-if-list (x)
                             (if (consp x) (quote x) x))
              
              (get-elt (sym)
                       (quote-if-list (elt c (string-to-number (subseq (symbol-name sym) 1)))))
              
              (subst (x)
                     (my-sp x)
                     (if (symbolp x)
                         (cond ((equal (symbol-name x) evalator-context-special-arg-default)
                                (quote-if-list c))
                               
                               ((string-match (make-regex) (symbol-name x))
                                (quote-if-list (get-elt x)))
                               
                               (t
                                x))
                       x))
              (rec (xs)
                   (cond ((equal nil (car xs)) nil)
                         ((consp (car xs)) (cons (rec (car xs)) (rec (cdr xs))))
                         (t (cons (subst (car xs)) (rec (cdr xs)))))))
    (rec expr)))

(defun evalator-context-elisp-make-candidates (input mode &optional not-initialp)
  (let* ((data (if not-initialp input (eval (read input))))
         (to-obj-string (lambda (x)
                          (prin1-to-string x))))
    (my-sp (funcall to-obj-string data))
    (cond
     ((equal :explicit mode) (if not-initialp
                                 (list (funcall to-obj-string (car data)))
                               (list (funcall to-obj-string data))))
     ((and (not (stringp data)) (sequencep data)) (mapcar to-obj-string data))
     (t (list (funcall to-obj-string data))))))

(defun evalator-context-elisp-transform-candidates-try (candidates-all candidates-marked expr-str mode)
  (condition-case err
      (evalator-context-elisp-transform-candidates candidates-all
                                                   candidates-marked
                                                   expr-str
                                                   mode)
    (error
     ;; TODO Would be useful to have a red/green flash for this
     candidates-all)))

(defun evalator-context-elisp-transform-candidates (candidates-all candidates-marked expr-str mode)
  (evalator-context-elisp-make-candidates
   (if (equal nil candidates-marked)
       (mapcar (lambda (candidate)
                 (evalator-context-elisp-apply-expression (read expr-str)
                                                          (read candidate)))
               candidates-all)
     (evalator-context-elisp-apply-expression (read expr-str)
                                              (mapcar 'read candidates-marked)))
   mode
   t))

(defun evalator-context-elisp-apply-expression (expr x)
  (let ((new-expr (evalator-context-elisp-substitute-special-args expr x)))
    (my-sp new-expr)
    (eval new-expr)))

;; TODO kinda confused on the difference between defvar and setq, figure this out.
(setq evalator-context-elisp
      (make-instance
       'evalator-context
       
       :name
       "ELisp"

       :init
       (lambda () nil)

       :make-candidates
       'evalator-context-elisp-make-candidates
       

       :transform-candidates-try
       'evalator-context-elisp-transform-candidates-try
       

       :transform-candidates
       'evalator-context-elisp-transform-candidates))

(provide 'evalator-context-elisp)