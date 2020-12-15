(in-package :xml-parser)

#|
 <DOCUMENTATION>
 <DESCRIPTION>
 compile models into predicates which can be applied to element forests.

 the control structure uses continuation passing to iterate through the
 element list to compare it to the specified model and to recurse through
 the individual element trees.
 the comparison happens in distinct levels - that is, each element model is
 associated with a predicate compiled distinctly for itself to test the content
 and content of  one element.
 the respective content elements are then tested against the respective
 element's model.
 </DESCRIPTION>
 <CHRONOLOGY>
 <DATE>19971201</DATE>
  <DELTA>jaa: compiles to predicates with a 3-continuation control-structure.
   two functions are specified by the caller: one for success and one
   for failure. the other function is generated by the compiler to perform the
   iteration through the model elements or groups. for model members which
   repeat a fourth function is used internal to the respecitve iterative
   function to iterate through the element members.
   <P>
   the continuations follow the respective protocols:
   <DL>
   <DT>succeed: (data fail) -> continue</DT>
   <DD>the data is the element member list which remains to be tested;
   <BR>fail as expected.
   </DD>
   <DT>fail: (data succeed model) -> continue</DT>
   <DD>the data is the element member list which failed to match;
   <BR>succeed as expected;
   <BR>the model is the model member which did was required.
   </DD>
   <DT>rest: (data succeed fail) -> continue</DT>
   <DD>the data is the element member list which remains to be tested;
   <BR>succeed and fail as expected.
   </DT>iterate: (data) -> continue</DT>
   <DD>the data is the element member list which remains to be tested;
   </DD>
   </DL>
   </DELTA>
  <DATE>19971202</DATE>
  <DELTA>jaa: move the constraint on complete processing to the outermost
   <CODE>MODEL-PREDICATE</CODE> which simplified the terminal predicates.
   <BR>changed <CODE>PCDATA-P</CODE> and teh respective model predicate to
   allow null content.
   <BR>changed the tag comparison in the element predicate from checking
   element type to checking literal element name. a) this is not the xsl
   matcher, and b) using type would prevent validating elements (including
   xsl elements) used as patterns.
 <DATE>19971210</DATE>
 <DELTA>jaa: fixed CONTENT-LIST -> INNER-CONTENT-LIST binding on the
  +, model content predicate generator.
   </DELTA>
 <DATE>19971229</DATE>
  <DELTA>jaa: added NULL-MODEL-PREDICATE as the compiled predicate for
   null (or (NOT MODEL)) 'models'</DELTA>
 <DELTA><DATE>19980102</DATE>
  XML-CHARACTER-DATA instead of XML-TEXT</DELTA>
 </CHRONOLOGY>
 </DOCUMENTATION>
|#


(defParameter *model-predicate-level* 0)
(defparameter *XML-COMPILER-TRACE* nil)
;(defparameter *XML-COMPILER-TRACE* t)
;(setf *xml-verbose* t) (setf *xml-verbose* nil)

;; there are functional hooks for the continuation control points.
;; they are invoked or ignored as a compiler option...

(defMethod %model-succeed
           ((content-list t)
            (succeed-continuation function)
            (fail-continuation t))
  (funcall succeed-continuation content-list fail-continuation))
(defMacro model-succeed (content succeed fail)
  (if *xml-compiler-trace*
    `(%model-succeed ,content ,succeed ,fail)
    `(funcall ,succeed ,content ,fail)))

(defMethod %model-continue
           ((model-continue function)
            (content-list t)
            (succeed-continuation function)
            (fail-continuation function))
  (funcall model-continue content-list succeed-continuation fail-continuation))
(defMacro model-continue (continue content succeed fail)
  (if *xml-compiler-trace*
    `(%model-continue ,continue ,content ,succeed ,fail)
    `(funcall ,continue ,content ,succeed ,fail)))

(defMethod %model-fail
           ((content-list t)
            (succeed-continuation t)
            (fail-continuation function)
            (model t))
  (funcall fail-continuation content-list succeed-continuation model))
(defMacro model-fail (content succeed fail model)
  (if *xml-compiler-trace*
    `(%model-fail ,content ,succeed ,fail ,model)
    `(funcall ,fail ,content ,succeed ,model)))

(defMethod %model-iterate
           ((iteration-function t)
            (content-list t))
  (funcall iteration-function content-list))
(defMacro model-iterate (iterate content)
  (if *xml-compiler-trace*
    `(%model-iterate ,iterate ,content)
    `(funcall ,iterate ,content)))

(defMacro succeed-with (args &rest body)
  (assert (= (length args) 2))
  `(function (lambda ,args ,@body)))

(defMacro fail-with (args &rest body)
  (assert (= (length args) 3))
  `(function (lambda ,args ,@body)))

(defMacro compiler-trace (string &rest args)
  (if *xml-compiler-trace*
    `(when *xml-verbose*
       (format *trace-output* ,(concatenate 'string "~%~*t" string)
               *model-predicate-level* ,@args))
    (values)))

;; the generic predicate generation methods support an element model with
;; an element or a model group with a list of elements. to simplify the
;; interface, they also recognize element declarations and distinguish
;; models which contain reserved type designators.

(defMethod %xml-element.valid?
           ((datum string) (succeed function) fail)
  (funcall succeed datum fail))

(defMethod %xml-element.valid?
           ((datum t) (succeed t) (fail function))
  (call-next-method)
  (funcall fail datum succeed nil))
    


(defMethod model-predicate-name
           ((name symbol) &optional (suffix "?"))
  (when name
    (intern (format nil "~a~a" name suffix) (symbol-package name))))

(defMethod model-predicate-name
           ((model dtd-model) &optional (suffix "?"))
  (model-predicate-name (dtd-model.name model) suffix))


(defMethod compile-model-predicate
           ((model dtd-model) &aux (name (model-predicate-name model)))
  (declare (ignorable name))
  (when (xml-verbose 'compile-model-predicate)
    (format *trace-output* "~%;;compiling model predicate: ~s..."
            (dtd-model.name model)))
  (prog1 #-:ccl (compile nil (model-predicate model))
         #+:ccl (eval `(nfunction ,name ,(model-predicate model)))
    (when (xml-verbose 'compile-model-predicate)
      (format *trace-output* " done."))))

(defMethod compile-model-predicate
           ((model dtd-element-declaration))
  (compile-model-predicate (dtd-element-declaration.model model)))

(defMethod null-model-predicate
           ((content t) (succeed t) (fail t))
  t)

(defMethod compile-model-predicate
           ((model null))
  (when (xml-verbose 'compile-model-predicate)
    (warn "asserting a null model in context: ~s." *parent-node*))
  #'null-model-predicate)

#|
;; this definition does not distinguish the outermost group from
;; the inner groups. that which follows does.
(defMethod model-predicate
           ((model dtd-model-group))
  (model-content-predicate nil nil
                           (dtd-model.connector model)
                           (dtd-model.content model)))
 |#

(defMethod model-predicate
           ((model dtd-model-group))
  `(lambda (content-list succeed fail
            &aux (*model* ,model))
     (declare (special *model*))
     (compiler-trace "~%??> ~s"
                     (list ',(dtd-model.name model) content-list))
     (,(model-content-predicate model (dtd-model.occurrence model)
                           *seq-marker* nil)
      content-list
      (succeed-with (remaining-content _fail)
       (if remaining-content
         (model-fail remaining-content succeed _fail ,model)
         (model-succeed remaining-content succeed _fail)))
      fail)))


#|
 model predicates can be generated for three kinds of model.
 each predicate expects as content-list an element. it performs its test and
 invokes a sucess or a failure continuation appropriately

 the supported models are:

 reserved models: #PCDATA, CDATA, ANY, EMPTY
  requires that the content-list be a string or a text element
 element models: any unary element - neglecting the occurrence
  requires that the content-list be an element of the respective type and that the
  content matches the declaration
 model groups: any element group
  distinguishes an element from a list. if the former, then the type identity
  is constrained and the content is checked as for a list. if a list, then
  the model sequence is checked against the element sequence.
 |#


(defMethod model-element-predicate
           ((model dtd-element-model) &aux (name (dtd-model.name model)))
  `(lambda (content-list succeed fail &aux (element (first content-list)))
     (if (and (typep element 'xml-element)
               ,@(if name
                   `((eq ',name (xml-element.name element)))))
        (%xml-element.valid? element
                            (succeed-with (element _fail)
                             (declare (ignore element _fail))
                             (compiler-trace "~%<-- ~s: ~s . ~s"
                                             ',name
                                             (first content-list)
                                             (rest content-list))
                             (model-succeed (rest content-list) succeed fail))
                            fail)
        ;; fail with all of the remaining content, NOT just the element
        (model-fail content-list succeed fail ,model))))


(defMethod model-element-predicate
           ((model dtd-model-group)
            &aux (content (dtd-model.content model))
                 (first (first content)))
  (model-content-predicate first (dtd-model.occurrence first)
                           (dtd-model.connector  model) (rest content)))


#|
(defMethod model-seq-predicate
           (model occurrence connector rest succeed fail)
  (list :seq-predicate model occurrence connector rest succeed fail))

(model-predicate #!m#pcdata t nil)
(inspect (mapcar #'(lambda (model) (list model (model-predicate model t nil)))
                 *test-models*))
(pprint (elt (top-inspect-form) 0))
 |#

;; one of four effects:
;; advance model, advance data, succeed, fail

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql *opt-marker*)) ; 0...1,
            (connector (eql *seq-marker*)) (rest t))
  `(lambda (content-list succeed fail)
      (flet ((rest-cont ,@(rest
                          (model-content-predicate nil nil connector rest))))
        (,(model-element-predicate model)
         content-list
         (succeed-with (_content-list _fail)
          (model-continue #'rest-cont _content-list succeed _fail))
         (fail-with (_content-list _succeed _model)
          (declare (ignore _content-list _succeed _model))
          (model-continue #'rest-cont content-list succeed fail))))))

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql *opt-marker*))
            (connector (eql *or-marker*)) (rest t))
  `(lambda (content-list succeed fail)
     (flet ((rest-cont ,@(rest
                         (model-content-predicate nil nil connector rest))))
       (let ((rest-fail nil))
         (setf rest-fail
               (fail-with (_content-list _succeed _model)
                          (declare (ignore _content-list _succeed _model))
                          (model-continue #'rest-cont content-list succeed fail)))
         (,(model-element-predicate model)
          content-list
          (succeed-with (_content-list _fail)
                        (model-succeed _content-list succeed _fail))
          rest-fail)))))

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql *rep-marker*))
            (connector (eql *seq-marker*)) (rest t))
  `(lambda (content-list succeed fail)
     (flet ((rest-cont ,@(rest
                         (model-content-predicate nil nil connector rest))))
       (let ((iterate nil))
         (setf iterate
               (function
                (lambda (inner-content-list)
                  (if (null inner-content-list)
                    ;; keep testing the model - only further *'s will succeed
                    (model-continue #'rest-cont nil succeed fail)
                    (,(model-element-predicate model)
                     inner-content-list
                     (succeed-with (_content-list fail)
                                   (declare (ignore fail))
                                   (model-iterate iterate _content-list))
                     (fail-with (_content-list _succeed _model)
                      (declare (ignore _content-list _succeed _model))
                      (model-continue #'rest-cont inner-content-list succeed fail)))))))
         (model-iterate iterate content-list)))))

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql *rep-marker*))
            (connector (eql *or-marker*)) (rest t))
  ;; treat it as if it had an optional marker (?)
  (model-content-predicate  model *plus-marker* connector rest))


(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql *plus-marker*))
            (connector (eql *seq-marker*)) (rest t))
  `(lambda (content-list succeed fail)
     (flet ((rest-cont ,@(rest
                         (model-content-predicate nil nil connector rest))))
       (let ((occurrence 0)
             (iterate nil))
        (setf iterate
              (function
               (lambda (inner-content-list)
                 (if (null inner-content-list)
                   (if (plusp occurrence)
                     (model-succeed nil succeed fail)
                     (model-fail content-list succeed fail ,model))
                   (,(model-element-predicate model)
                    inner-content-list
                    (succeed-with (_content-list _fail)
                     (declare (ignore _fail))
                     (incf occurrence)
                     (model-iterate iterate _content-list))
                    (if (plusp occurrence)
                      (fail-with (_content-list _succeed _model)
                       (declare (ignore _content-list _succeed _model))
                       (model-continue #'rest-cont inner-content-list
                                       succeed fail))
                      fail))))))
      (model-iterate iterate content-list)))))

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql *plus-marker*))
            (connector (eql *or-marker*)) (rest t))
  `(lambda (content-list succeed fail)
     (flet ((rest-cont ,@(rest
                         (model-content-predicate nil nil connector rest))))
      (let ((occurrence 0)
            (iterate nil)
            (rest-fail nil))
        (setf rest-fail
             (fail-with (_content-list _succeed _model)
              (declare (ignore _content-list _succeed _model))
              (model-continue #'rest-cont content-list succeed fail)))
        (setf iterate
             (function
              (lambda (inner-content-list)
                (if (null inner-content-list)
                  (if (plusp occurrence)
                    (model-succeed nil succeed rest-fail)
                    (model-fail content-list succeed fail ,model))
                  (,(model-element-predicate model)
                   inner-content-list
                   (succeed-with (_content-list _fail)
                    (declare (ignore _fail))
                    (incf occurrence)
                    (model-iterate iterate _content-list))
                   (fail-with (_content-list _succeed _model)
                    (declare (ignore _content-list _succeed _model))
                    (if (plusp occurrence)
                      (model-succeed succeed inner-content-list rest-fail)
                      (model-continue #'rest-cont inner-content-list
                                      succeed fail))))))))
       (model-iterate iterate content-list)))))

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql 1))
            (connector (eql *seq-marker*)) (rest t))
  `(lambda (content-list succeed fail)
     (flet ((rest-cont ,@(rest
                         (model-content-predicate nil nil connector rest))))
       (if (null content-list)
         (model-fail content-list succeed fail ,model)
         (,(model-element-predicate model)
          content-list
          (succeed-with (_content-list _fail)
           (model-continue #'rest-cont _content-list succeed _fail))
          fail)))))

(defMethod model-content-predicate
           ((model dtd-model) (occurrence (eql 1))
            (connector (eql *or-marker*)) (rest t))
  `(lambda (content-list succeed fail)
      (flet ((rest-cont ,@(rest
                          (model-content-predicate nil nil connector rest))))
        (if (null content-list)
          (model-fail content-list succeed fail ,model)
          (,(model-element-predicate model)
           content-list
           succeed
           (fail-with (_content-list _succeed _model)
            (declare (ignore _content-list _succeed _model))
            (model-continue #'rest-cont content-list succeed fail)))))))


;;; base method as a convenience for starting the model sequence

(defMethod model-content-predicate
           ((model null) (occurrence null) (connector t) (content cons))
  (setf model (first content))
  (model-content-predicate model (dtd-model.occurrence model)
                           connector (rest content)))

#|
 special methods for reserved models: CDATA, ANY, EMPTY, PCDATA
 |#

(defun pcdata-p
       (datum)
  ;; note that this does not accept a null list: it is intended to  be
  ;; applied to individual content members of an element - none of which
  ;; may be nil
  (typecase datum
    ((or string xml-character-data symbol number) t)
    (t nil)))


(defMethod model-content-predicate
           ((model dtd-reserved-model) (occurrence t)
            (connector t) (rest t))
  (model-content-predicate (dtd-model.name model) occurrence connector rest))


(defMethod model-content-predicate
           ((model (eql 'xml::\#PCDATA)) (occurrence t)
            (connector t) (rest t))
  `(lambda (content-list succeed fail)
     (loop (when (or (null content-list) (not (pcdata-p (first content-list))))
             (return))
           (pop content-list))
     (if (null content-list)
       (model-succeed nil succeed fail)
       (model-fail content-list succeed fail ',model))))

(defMethod model-content-predicate
           ((model (eql 'xml::CDATA)) (occurrence t)
            (connector t) (rest t))
  `(lambda (content-list succeed fail)
        (if (pcdata-p (first content-list))
            (model-succeed (rest content-list) succeed fail)
            (model-fail content-list succeed fail ',model))))

(defMethod model-content-predicate
           ((model (eql 'xml::ANY)) (occurrence t)
            (connector t) (rest t))
  `(lambda (content-list succeed fail)
     (declare (ignore content-list))
     ;; null content allowed?
     (model-succeed nil succeed fail)))

(defMethod model-content-predicate
           ((model (eql 'xml::EMPTY)) (occurrence t)
            (connector t) (rest t))
  `(lambda (content-list succeed fail)
     (if content-list
       (model-fail content-list succeed fail ',model)
       (model-succeed nil succeed fail))))

#|
(mapcar #'(lambda (m) (list m (model-content-predicate m t nil)))
        '(#!M#PCDATA #!MCDATA #!MANY #!MEMPTY
          #!M(#PCDATA)))
  (model-content-predicate #!M#PCDATA t nil)
|#



#|
 base methods to generate the terminal predicates.
 there are two cases - one each for sequences and or-groups
 the difference is, an or group should alread have succeed and should get to
 invoke this as the continuation to process the rest of the element list.
 a sequence group, on the other hand, must get here and be allowed to use
 the succeed continuation to process the remainder of the element list.

 if that is the outermost continuations (see <CODE>MODEL-PREDICATE</CODE>,
 then the succeed continuation requires that no content remain in order to
 finally succeed...
 |#


(defMethod model-content-predicate
           ((model null) (occurrence null)
            (connector (eql *seq-marker*)) (rest null))
  `(lambda (content-list succeed fail)
     (model-succeed content-list succeed fail)))

(defMethod model-content-predicate
           ((model null) (occurrence null)
            (connector (eql *or-marker*)) (rest null))
  `(lambda (content-list succeed fail)
     (declare (special *model*))
     (model-fail content-list succeed fail *model*)))


(defMethod model-content-predicate
           ((element t) (occurrence t)
            (connector t) (rest t))
  (error "unknown model state: (~s ~s ~s ~s)."
         element occurrence connector rest))


#|
 an extra method to generate trace information.
 if tracing is enabled, then each predicate is wrapped for tracing on entry
 and on invocation of its continuations.
 the first arg is specialized to avoid the various other helper methods
 which specialize on symbols, null, etc
 |#

(defun wrap-model-predicate
       (model tag lambda)
  `(lambda (%content-list %succeed %fail
            &aux (*model-predicate-level* (1+ *model-predicate-level*))
                 (*model* ,model))
     (declare (special *model* *model-predicate-level*))
     (compiler-trace "~a: (~s ~s ~s)" ,tag %content-list %succeed %fail)
     (,lambda
      %content-list
      (succeed-with (%%content-list %%fail)
       (compiler-trace "~a: succeeded ~s -> (~s ~s ~s)"
                 ,tag %content-list %succeed %%content-list %%fail)
       (funcall %succeed %%content-list %%fail))
      (fail-with (%%content-list %%succeed %%model)
       (compiler-trace "~a: failed ~s -> (~s ~s ~s)"
                 ,tag %content-list %fail %%content-list %%model)
       (funcall %fail %%content-list %%succeed %%model)))))

(defMethod model-content-predicate :around
           ((model dtd-model) (occurrence t) (connector t) (rest t)
            &aux (tag (format nil "(~s ~s ~s)"
                              (dtd-model.name model) occurrence connector)))
  (let ((primary (call-next-method)))
    (if *xml-compiler-trace*
      (wrap-model-predicate model tag primary)
      primary)))

(defMethod model-content-predicate :around
           ((model null) (occurrence null) (connector t) (rest null)
            &aux (tag (format nil "(~s ~s ~s)" model occurrence connector)))
  (let ((primary (call-next-method)))
    (if *xml-compiler-trace*
      (wrap-model-predicate model tag primary)
      primary)))
             
           
#|
 hooks to invoke the compiler as a side-effect of operations on model elements.
 |#

(defMethod dtd-add-element :before
           ((dtd dtd) (element dtd-element-declaration))
  (setf (dtd-element-declaration.predicate element)
        (when (dtd.validate? dtd)
          (let ((model (dtd-element-declaration.model element)))
            (handler-case (compile-model-predicate model)
              (error (condition)
                     (warn "error occurred while compiling model: ~a: ~a."
                           model condition)
                     nil))))))

(defMethod (setf dtd-element-declaration.model) :before
           ((model dtd-model) (decl dtd-element-declaration))
  ;; the check here serves two purposes -
  ;; while the element is being constructed, it has no parent and thus the
  ;; compilation is defered until it is placed in a dtd
  ;; if changes happen to an existing dtd, the compilation occurrs
  ;; appropriately
  (setf (dtd-element-declaration.predicate decl)
        (when (dtd.validate? (dtd-element-declaration.dtd decl))
          (handler-case (compile-model-predicate model)
            (error (condition)
                   (warn "error occurred while compiling model: ~a: ~a."
                         model condition)
                   nil)))))

(defMethod (setf dtd.validate?) :before
           ((mode null) (dtd dtd))
  (dolist (element-decl (dtd.elements dtd))
    (when (typep element-decl 'dtd-element-declaration)
      (setf (dtd-element-declaration.predicate element-decl) nil))))

(defMethod (setf dtd.validate?) :before
           ((mode t) (dtd dtd))
  (dolist (decl (dtd.elements dtd))
    (when (typep decl 'dtd-element-declaration)
      (setf (dtd-element-declaration.predicate decl)
            (let ((model (dtd-element-declaration.model decl)))
              (when model
                (handler-case (compile-model-predicate model)
                  (error (condition)
                         (warn "error occurred while compiling model: ~a: ~a."
                               model condition)
                         nil))))))))

:EOF
