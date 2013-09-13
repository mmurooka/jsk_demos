(load "package://pr2eus/pr2-interface.l")

(defvar *attention-flag* "/attention_observation/flag")
(defvar *attention-id* "/attention_observation/id")

(ros::set-param *attention-flag* nil)

#|
(defun call-retry-all ()
  (ros::set-param *attention-flag* "retry-all"))

(defun call-retry-plus ()
  (ros::set-param *attention-flag* "retry-plus"))

(defun call-retry ()
  (ros::set-param *attention-flag* "retry"))
|#

;;
(defclass pr2-attention-interface
  :super pr2-interface
  :slots ())
(defmethod pr2-attention-interface
  (:wait-interpolation (&rest args)
   (let ((ret (send-super* :wait-interpolation args)))
     (unless (or (not (memq :attention-barrier (sys::list-all-catchers)))
                 (some #'identity ret))
       (throw :attention-barrier (ros::get-param *attention-flag*)))
     ;;(send self :try-check-cancel-flag)
     ret))
  (:move-to (&rest args)
   (let ((ret (send-super* :move-to args)))
     (unless (or (not (memq :attention-barrier (sys::list-all-catchers)))
                 ret)
       (throw :attention-barrier (ros::get-param *attention-flag*)))
     ;;(send self :try-check-cancel-flag)
     ret))
  (:go-pos (&rest args)
   (let ((ret (send-super* :go-pos args)))
     (unless (or (not (memq :attention-barrier (sys::list-all-catchers)))
                 ret)
       (throw :attention-barrier (ros::get-param *attention-flag*)))
     ;;(send self :try-check-cancel-flag)
     ret))
  (:go-pos-unsafe (&rest args)
   (let ((ret (send-super* :go-pos-unsafe args)))
     (unless (or (not (memq :attention-barrier (sys::list-all-catchers)))
                 ret)
       (throw :attention-barrier (ros::get-param *attention-flag*)))
     ;;(send self :try-check-cancel-flag)
     ret))
  (:move-gripper
   (arm pos &rest args)
   (let ((ret (send-super* :move-gripper arm pos args)))
     (send self :try-check-cancel-flag)
     ret))
  ;;
  (:wait-interpolation-org (&rest args)
   (send-super* :wait-interpolation args))
  (:move-to-org (&rest args)
   (send-super* :move-to args))
  (:go-pos-org (&rest args)
   (send-super* :go-pos args))
  (:go-pos-unsafe-org (&rest args)
   (send-super* :go-pos-unsafe args))
  (:move-gripper-org (&rest args)
   (send-super* :move-gripper args))
  ;;
  (:try-check-cancel-flag (&optional (func-before-throw))
   (when (memq :attention-barrier (sys::list-all-catchers))
     (let ((ret (ros::get-param *attention-flag*)))
       (when ret
         (if func-before-throw (funcall func-before-throw self))
         (throw :attention-barrier ret)))))
  (:get-cancel-flag ()
   (ros::get-param *attention-flag*))
  (:clear-cancel-flag ()
   (ros::set-param *attention-flag* nil))
  (:cancel-all-motion (&optional (flag t))
   (ros::set-param *attention-flag* flag)
   (send r-gripper-action :cancel-all-gols)
   (send l-gripper-action :cancel-all-gols)
   (send self :cancel-angle-vector)
   (send self :go-stop nil))
  (:ros-wait
   (tm &key (spin) (spin-self) (func-before-throw))
   (send-super self :ros-wait tm :spin spin :spin-self spin-self
               :finish-check
               #'(lambda (sl) (send sl :try-check-cancel-flag func-before-throw) nil))
   )
  ) ;;

(unless (fboundp 'pr2-init-org)
  (setf (symbol-function 'pr2-init-org) (symbol-function 'pr2-init)))

(defun pr2-init (&rest args)
  (setq *ri* (setq *ri* (instance pr2-attention-interface :init)))
  (apply #'pr2-init-org args)
  )

(defun do-command-sequence (seq &rest args)
  (let ((ptr 0) com abr)
    (while (< ptr (lenth com))
      (setq abr
            (catch :attention-barrier
              (setq com (elt seq ptr))
              (let (ret)
                (setq ret (apply com args))
                (unless ret (throw :attention-barrier :fail))
                :success
                )))
      (cond
       ((stringp abr)
        (let ((str (send *ri* :get-cancel-flag)))
          (send *ri* :clear-cancel-flag)
          (setq abr (intern (string-upcase abr) *keyword-package*))
          ))
       ((null abr)
        (warn "abr = nil~%");;
        (setq abr :fail))
       ((eq t abr) ;; normal cancel
        (setq abr :fail))
       )
      (case abr
        ((:retry :fail) )
        (:retry-plus
         (decf ptr 1)
         (if (< ptr 0) (setq ptr 0)))
        (:retry-all
         (setq ptr 0))
        (t (incf ptr))
       ))
    ))

(defun wait-android-query ()
  (ros::ros-info "Begin Waiting")
  (let (type from (cntr 0))
    (ros::subscribe "/Tablet/StartDemo" roseus::StringStamped
                    #'(lambda(m)
                        ;;(print (list :subscribe (send m :data)))
                        (cond
                         ((string= (send m :data)
                                   "/Tablet/other/GetGeorgia")
                          (setq from :tablet)
                          (setq type "georgia"))
                         ((string= (send m :data)
                                   "/Tablet/other/DoNothing")
                          (setq from :tablet)
                          (setq type "nothing"))
                         (t ))))
    (ros::rate 100)
    (do-until-key
     (incf cntr)
     (when (> cntr 200)
       (ros::ros-info " Waiting ....")
       (setq cntr 0))
     (ros::spin-once)
     (send *ri* :spin-once)
     (when type
       (case from
         (:tablet
          (cond
           ((string= type "nothing")
            (ros::ros-info "Cancel all motion")
            (send *ri* :cancel-all-motion "tablet")
            )
           (t )
           )
          ))
       (setq type nil from nil)
       )
     (ros::sleep))
    (ros::unsubscribe "/Tablet/StartDemo")
    ))

#| ;; sample actions for detect_cans
(load "package://jsk_demo_common/euslisp/attention-observation.l")
(defun action-0 (&rest args
                   &key type demo-type finish-type
                   &allow-other-keys)
  (setq *type* type)
  ;;
  (if (and (boundp '*use-voicetext*) *use-voicetext*)
      (cond
       ((and (boundp '*use-english*) *use-english*)
        (speak-jp (format nil "I will look for ~a and bring it. Please wait a minute." *type*)))
       (t (speak-jp (format nil "~aを持って行きます。少々、お待ちください。" *type*))))
    (speak-jp (format nil "~a を もってきます  しょうしょう おまち ください" *type*)))
  (pr2-tuckarm-pose :rarm)
  (setq *opose* (send *ri* :state :worldcoords))
  t
  )

(defun action-1 (&rest args
                   &key type demo-type finish-type
                   &allow-other-keys)
  (case demo-type
    (:map
     (goto-front-of-fridge))
    (t
     ;; do nothing
     t))
  )

(defun action-2 (&rest args
                       &key type demo-type finish-type
                       &allow-other-keys)
  (open-fridge-door :torso-lift 25 :head-pitch 14)
  )

(defun action-3 (&rest args
                       &key type demo-type finish-type
                       &allow-other-keys)
  (grasp-can)
  )

(defun action-4 (&rest args
                       &key type demo-type finish-type
                       &allow-other-keys)
  (close-fridge)
  )

(defun action-5 (&rest args
                       &key type demo-type finish-type
                       &allow-other-keys)
  (case demo-type
    (:map
     (goto-initial-position :finish-type finish-type))
    (t
     (goto-initial-position
      :return-to-initial-position nil :turnp t
      :finish-type finish-type)))
  )
|#