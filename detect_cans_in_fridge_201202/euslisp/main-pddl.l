;; open fridge and pick a can (and close the door)

(load "package://jsk_2011_07_pr2_semantic/euslisp/actions.l")
(load "package://jsk_maps/src/eng2-scene.l")
(load "package://pr2eus/pr2-interface.l")

;;(load "package://pr2eus_openrave/pr2eus-openrave.l")
;;(load "package://pr2eus_armnavigation/pr2eus-arm-navigation.l")

(ros::roseus "demo_main")
(setq *use-arm-navigation* nil)

(defun init-for-perception ()
  (unless (boundp '*scene*) (setq *scene* (make-eng2-scene)))
  (unless (boundp '*tfb*)
    (setq *tfb* (instance ros::transform-broadcaster :init)))
  (if (and x::*display* (/= x::*display* 0)) (make-irtviewer))
  (setq *obj* (make-sphere 100)) ;; dummy object
  (setq *target-name* nil)
  (ros::spin-once)
  )

(defun init-for-robot ()
  (unless (boundp '*pr2*) (pr2))
  (unless (boundp '*ri*) (setq *ri* (instance pr2-interface :init)))
  (send *ri* :spin-once)
  (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
  (when *use-arm-navigation*
    (setq *plan-env* (instance arm_planning_environment :init :robot *pr2*)))
  ;; added for pddl
  (send *pr2* :head :angle-vector (float-vector 0 0))
  (send *pr2* :torso :angle-vector (float-vector 50))
  (send *ri* :angle-vector (send *pr2* :angle-vector))
  (send *ri* :wait-interpolation)
  (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
  )

(defun init ()
  (init-for-perception)
  (init-for-robot)
  (load "package://jsk_perception/euslisp/detection_interface.l")

  ;; Setting global variables for pddl
  (setq *fridge-front* (send *scene* :spot "/eng2/7f/room73B2-fridge-front"))
  (send *fridge-front* :translate (float-vector 0 0 0) :world)

  (setq *type* "georgia")
  (speak-jp (format nil "~a を もってきます  しょうしょう おまち ください"
		    *type*))

  (pr2-tuckarm-pose :rarm)
  (setq *opose* (send *ri* :state :worldcoords))
  )

(defun grasp-can-single (obj &key (rotation 0))
  (let (via1 via2 tar orig-av)
    (send *ri* :stop-grasp :rarm)
    (send *tfb* :send-transform
          obj "/base_footprint" "/objecta_pose_frame")
    (setq orig-av (send *ri* :state :potentio-vector))

    (when *use-arm-navigation*
      (dotimes (i 5)
	(send *plan-env* :get-planning-scene)
	;; (unix::usleep (* 400 1000))
	))

    (setq tar (send obj :copy-worldcoords))
    (send tar :orient 0 :z :world)

    (setq via1 (send tar :copy-worldcoords))
    (send via1 :translate (float-vector (* (cos (deg2rad rotation)) -100)
					(* (sin (deg2rad rotation))  100) 0) :world)

    ;; via2 
    (setq via2 (send tar :copy-worldcoords))
    (send via2 :translate (float-vector 30 0 0) :world)

    ;; publish tf
    (send *tfb* :send-transform
          via1 "/base_footprint" "/objecta_pose_frame_via1")
    ;;(send *tfb* :send-transform
    ;;via2 "/base_footprint" "/objecta_pose_frame_via2")
    (send *tfb* :send-transform
          via2 "/base_footprint" "/objecta_pose_frame_via2")

    ;; move to via1
    (send *pr2* :rarm :inverse-kinematics via1 :rotation-axis t)
    (send *tfb* :send-transform
          (send *pr2* :rarm :end-coords)  "/base_footprint" "/objecta_pose_end_coords")

    ;;(send *ri* :angle-vector (send *pr2* :angle-vector))
    ;;(send *ri* :wait-interpolation))
    ;; check IK

    (cond
     ((null *use-arm-navigation*)
      (send *ri* :angle-vector (send *pr2* :angle-vector))
      (send *ri* :wait-interpolation))
     ((send *plan-env* :get-ik-for-pose (send *plan-env* :get-robot-coords :rarm) :rarm)
      (ros::ros-warn ";; can not solve collision free IK")
      (send *ri* :angle-vector (send *pr2* :angle-vector))
      (send *ri* :wait-interpolation))
     (t
      (when (send *plan-env* :planning-move-arm :rarm :planning-time 4.0)
	(ros::ros-warn ";; can not solve collision free Plan")
        (send *ri* :angle-vector (send *pr2* :angle-vector))
        (send *ri* :wait-interpolation))
      ))

    ;; move to via2 (grasping pose)
    (send *pr2* :rarm :inverse-kinematics via2 :rotation-axis t)
    ;; check IK
    #|(cond
    ((send *plan-env* :get-ik-for-pose (send *plan-env* :get-robot-coords :rarm) :rarm)
    (ros::ros-warn ";; can not solve collision free IK")
    ;; move to via1
    (send *ri* :angle-vector (send *pr2* :angle-vector))
    (send *ri* :wait-interpolation))
    (t
    (when (send *plan-env* :planning-move-arm :rarm :planning-time 4.0)
    (ros::ros-warn ";; can not solve collision free Plan")
    (send *ri* :angle-vector (send *pr2* :angle-vector))
    (send *ri* :wait-interpolation))
    ))|#
    (send *ri* :angle-vector (send *pr2* :angle-vector))
    (send *ri* :wait-interpolation)

    ;; grasp
    (send *ri* :start-grasp :rarm)

    ;; move to via1
    (send *pr2* :rarm :inverse-kinematics via1 :rotation-axis t)
    ;; check IK
    (cond
     ((null *use-arm-navigation*)
      (send *ri* :angle-vector (send *pr2* :angle-vector))
      (send *ri* :wait-interpolation))
     ((send *plan-env* :get-ik-for-pose (send *plan-env* :get-robot-coords :rarm) :rarm)
      (ros::ros-warn ";; can not solve collision free IK")
      ;; move to via1
      (send *ri* :angle-vector (send *pr2* :angle-vector))
      (send *ri* :wait-interpolation))
     (t
      (when (send *plan-env* :planning-move-arm :rarm :planning-time 4.0)
	(ros::ros-warn ";; can not solve collision free Plan")
        (send *ri* :angle-vector (send *pr2* :angle-vector))
        (send *ri* :wait-interpolation))
      ))
    ;;(send *ri* :angle-vector (send *pr2* :angle-vector))
    ;;(send *ri* :wait-interpolation)

    ;; move to original pose
    (send *ri* :angle-vector orig-av)
    (send *ri* :wait-interpolation)
    )
  )

(defun goto-front-of-fridge ()
  (let ((co (send *scene* :spot "/eng2/7f/room73B2-fridge-front")))
    (send co :translate (float-vector 0 0 0) :world) ;; for opening door
    (send *ri* :move-to co)
    (send *ri* :go-pos 0 -0.04 0) ;; ???
    ;;
    (send *pr2* :head :angle-vector (float-vector 0 0))
    (send *pr2* :torso :angle-vector (float-vector 50))
    (send *ri* :angle-vector (send *pr2* :angle-vector))
    (send *ri* :wait-interpolation)
    (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
    ;;(send *pr2* :move-to (send *ri* :state :worldcoords) :world)
    t
    ))

(defun open-fridge-door ()
  (let (ret
	;;(idealcds (make-coords :pos (float-vector 733.757 135.013 1092.946)
	;;:rpy (float-vector 0.002 0.059 -0.019)))
	(idealcds (make-coords :pos (float-vector 735 115 0)
			       :rpy (float-vector 0.05 0 0)))
	(diffcds (make-coords :pos (float-vector 10000 10000 10000)))
	cds)

    (dotimes (i 10 nil)

      ;; finding handle position
      (setq cds (check-detection :type "fridge")) ;; need detection fail check

      (when cds
	(send *obj* :reset-coords)
	(send *obj* :transform cds)
	(dump-structure *standard-output*
			(list (send *pr2* :copy-worldcoords)
			      (send cds :copy-worldcoords)))
	(setq cds
	      (make-coords :pos
			   (float-vector (elt (send cds :worldpos) 0)
					 (elt (send cds :worldpos) 1) 0)
			   :rpy (list (elt (car (rpy-angle (send cds :worldrot))) 0)
				      0 0)))

	(setq diffcds (send (send idealcds :inverse-transformation)
                            :transform (send cds :worldcoords) :world))

	(warn "~A -> ~A / ~A~%" diffcds cds idealcds)
	(ros::ros-info "DIFF: ~A" diffcds)

	(cond
	 ((and (< (norm (float-vector (elt (send diffcds :worldpos) 0)
				      (elt (send diffcds :worldpos) 1)))
		  40.0)
	       (< (elt (car (rpy-angle (send diffcds :worldrot))) 0) 0.07))
	  (setq cds (check-detection :type "fridge"))
	  (ros::spin-once)
	  (send *ri* :spin-once)
	  (when cds
	    (when (setq ret (open-fridge :rarm cds (/ pi 2)))
	      (return)))
	  (speak-jp "こまった")
	  (send *pr2* :head :angle-vector (float-vector 0 0))
	  (send *pr2* :torso :angle-vector (float-vector 50))
	  (send *ri* :angle-vector (send *pr2* :angle-vector))
	  (send *ri* :go-pos-unsafe -0.1 0 0)
	  (send *ri* :wait-interpolation)
	  )
	 (t ;;  there is much difference
	  (send *ri* :go-pos-unsafe
		(/ (elt (send diffcds :worldpos) 0) 1000.0)
		(/ (elt (send diffcds :worldpos) 1) 1000.0)
		(rad2deg (elt (car (rpy-angle (send diffcds :worldrot))) 0)))
	  (unix::usleep (* 500 1000))
	  ;; (send *ri* :wait-interpolation)
	  ))
	))

    (when (not ret)
      (ros::ros-info "TIMEOUT: open-fridge-door");;
      (return-from open-fridge-door nil))

    ;; free door handle
    (ros::spin-once)
    (send *ri* :spin-once)
    (send *ri* :stop-grasp :rarm)
    (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
    (setq rend (send *pr2* :rarm :end-coords :copy-worldcoords))
    (send rend :translate (float-vector -100 -50 0) *pr2*)
    (send *pr2* :rarm :inverse-kinematics rend)
    (send *ri* :angle-vector (send *pr2* :angle-vector) 1000)

    ;; ?? open door ()
    (send *ri* :angle-vector-sequence
	  (list (float-vector 50 5 74 100 -90 -70 -6 20 -70 50 -59 -43 118 0 0 -2 31)
		(float-vector 50 5 74 100 -90 -70 -6 20 -0 60 -20 -90 118 -90 0 -2 31)
		(float-vector 50 5 74 100 -90 -70 -6 20 -7 45 -34 -110 12 -38 74 -2 31)
		(float-vector 50 5 74 100 -90 -70 -6 20 -45 26 -31 -62 22 -76 121 -2 31)
		(float-vector 150 5 74 100 -90 -70 -6 20 -7 45 -34 -110 12 -38 74 -2 31))
	  (list 1500 1000 1000 3000 3000))
    (send *ri* :wait-interpolation)

    ;; (send *pr2* :angle-vector (float-vector 200 5.00529 74.2038 105.001 -90.0035 -70.0071 -5.73378 19.9988 9.96029 39.7801 -45.0972 -121.542 94.4262 -111.922 63.0666 -0.0316 21.024))
    (send *pr2* :angle-vector (float-vector 199.971 5.30455 72.1244 105.231 -88.5188 -69.9972 -5.72958 19.9717 24.6812 36.1934 10.6903 -121.497 159.113 -79.5111 -2.92658 -1.35562 26.862))
    (send *ri* :angle-vector (send *pr2* :angle-vector))
    t
    ))

(defun grasp-can (&key (move t) (rotation))
  ;; move-to spot for grasping
  (ros::spin-once)
  (send *ri* :spin-once)
  (when move
    (ros::ros-info "GO POS UNSAFE for grasping can")
    (send *ri* :go-pos-unsafe 0 0 (rad2deg 0.40))
    ;;(send *ri* :go-pos-unsafe 0.15 -0.30 0)
    (send *ri* :go-pos-unsafe 0.18 -0.31 0)
    (send *ri* :wait-interpolation))

  (ros::spin-once)
  (send *ri* :spin-once)
  (send *pr2* :angle-vector (send *ri* :state :potentio-vector))

  (let (isgrasp cds)
    (dotimes (trial 10)
      ;; detect cans which was indicated by ( type )
      (when (not (setq cds (check-detection :type *type* :single t)))
        (setq cds (check-detection :type *type* :tf-force t :timeout 30 :single t)))
      (when cds
	(send *obj* :reset-coords)
	(send *obj* :transform cds)
	(warn ";; print check cans~%")
	(dump-structure *standard-output*
			(list (send *pr2* :copy-worldcoords)
			      (send cds :copy-worldcoords)))
	(unless (boundp '*tfb*)
	  (setq *tfb* (instance ros::transform-broadcaster :init)))
	(send *tfb* :send-transform
	      cds "/base_footprint" "/object_pose_frame")
	(ros::spin-once)
	(send *ri* :spin-once)
	(send *pr2* :angle-vector (send *ri* :state :potentio-vector))
	(unless rotation
	  ;; FIXME: calc rotation from /map and /base_footprint
	  (setq rotation 0))
	(grasp-can-single cds :rotation rotation)
	(setq isgrasp (< 10 (send *ri* :start-grasp :rarm)))
	(when isgrasp
	  (return-from grasp-can t))
	)))
  nil)

(defun close-fridge ()
  ;; close the door of fridge
  (send *ri* :go-pos-unsafe -0.3 0.05 -20)
  (unix::sleep 1)
  (send *ri* :angle-vector-sequence
	(list (float-vector 250 5 74 100 -90 -70 -6 20 -13 50 -59 -43 118 -90 62 -2 31)
	      (float-vector 200 5 74 100 -90 -70 -6 20 -50 36 -29 -43 118 -90 62 -2 31)
	      (float-vector 150 5 74 100 -90 -70 -6 20 -63 10 -39 -33 -49 -32 89 -2 32)
	      (float-vector 100 5 74 100 -90 -70 -6 20 -61 6 -74 -64 -35 -6 102 -2 33)
	      (float-vector 50 5 74 100 -90 -70 -6 20 3 -2 -64 -80 -24 -55 10 -2 33))
	(list 2000 1000 3000 2000 2000))
  (send *ri* :wait-interpolation)
  (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
  (pr2-tuckarm-pose :rarm)
  t
  )

(defun goto-initial-position (&key (return-to-initial-position t))
  (send *ri* :go-pos-unsafe 0 0 -90)
  (send *ri* :wait-interpolation)
  (when return-to-initial-position
    (send *ri* :move-to *opose*))

  (speak-jp (format nil "~a を どうぞ" (send *obj* :name)))
  (hand-over :rarm :wait-shock t)
  t
  )

(defun demo (&key (type "georgia"))
  ;;(init)
  (setq *type* type)
  (speak-jp (format nil "~a を もってきます  しょうしょう おまち ください"
		    *type*))

  (pr2-tuckarm-pose :rarm)
  (setq *opose* (send *ri* :state :worldcoords))

  (unless (goto-front-of-fridge)
    (return-from demo))

  (unless (open-fridge-door)
    (return-from demo))

  (unless (grasp-can)
    (return-from demo))

  (unless (close-fridge)
    (return-from demo))

  (unless (goto-initial-position)
    (return-from demo))
  )

(defun wait-query ()
  (setq *type* nil)
  (ros::subscribe "/query" std_msgs::String
          #'(lambda(m) (setq *type* (send m :data))))
  #|(ros::subscribe "/query" std_msgs::String
          #'(lambda(m)(setq *type* (send m :data))))|#
  (do-until-key
   (ros::spin-once)
   (send *ri* :spin-once)
   (when *type*
     (ros::unsubscribe "/query")
     (demo *type*)
     (return-from wait-query t))
   (ros::sleep))
  )

;; this is just an another sample
(defun wait-android-query-test ()
  (ros::ros-info "Begin Waiting ....")
  (let (type)
    (ros::subscribe "/Tablet/StartDemo" roseus::StringStamped
		    #'(lambda(m)
			(print (send m :data))
			(cond
			 ((equal (send m :data) "/Tablet/other/MainDemo")
			  (setq type "georgia"))
			 (t ))))
    (do-until-key
     (ros::spin-once)
     (send *ri* :spin-once)
     (when type
       (ros::unsubscribe "/Tablet/StartDemo")
       (ros::ros-info "detect_cans: starting demo")
       (demo :type type)
       (setq type nil))
     (ros::sleep))
    ))

(warn ";; (init)~%")
(warn ";; (demo)~%")
(warn ";; (demo :type \"georgia\")~%")
(warn ";; (demo :type \"iemon\")~%")
(warn ";; (demo :type \"wonda\")~%")
(warn ";; ~%")
(warn ";; (check :type \"fridge\")~%")

;;(progn (check :type "wonda")(grasp-can *obj*))
;;(setq *type* "georgia")
;;(check :type *type* :tf-force t :timeout 30)
;;(grasp-can :move nil)


;; pddl function start


;; (move-to *fridge-front*)
;; (move-to *opose* t)
(defun move-to (co &optional (return-to-initial nil))
  (when return-to-initial
    (send *ri* :go-pos-unsafe 0 0 -90)
    (send *ri* :wait-interpolation))
  (send *ri* :move-to co)
  (send *ri* :go-pos 0 -0.04 0) ;;
  ;; (send *pr2* :head :angle-vector (float-vector 0 0))
  ;; (send *pr2* :torso :angle-vector (float-vector 50))
  ;; (send *ri* :angle-vector (send *pr2* :angle-vector))
  ;; (send *ri* :wait-interpolation)
  ;; (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
  t)

;;(open-fridge "fridge")
(defun open-fridge (fridge)
  (let (ret
	;;(idealcds (make-coords :pos (float-vector 733.757 135.013 1092.946)
	;;:rpy (float-vector 0.002 0.059 -0.019)))
	(idealcds (make-coords :pos (float-vector 735 115 0)
			       :rpy (float-vector 0.05 0 0)))
	(diffcds (make-coords :pos (float-vector 10000 10000 10000)))
	cds)

    (dotimes (i 10 nil)

      ;; finding handle position
      (setq cds (check-detection :type fridge)) ;; need detection fail check

      (when cds
	(send *obj* :reset-coords)
	(send *obj* :transform cds)
	(dump-structure *standard-output*
			(list (send *pr2* :copy-worldcoords)
			      (send cds :copy-worldcoords)))
	(setq cds
	      (make-coords :pos
			   (float-vector (elt (send cds :worldpos) 0)
					 (elt (send cds :worldpos) 1) 0)
			   :rpy (list (elt (car (rpy-angle (send cds :worldrot))) 0)
				      0 0)))

	(setq diffcds (send (send idealcds :inverse-transformation)
                            :transform (send cds :worldcoords) :world))

	(warn "~A -> ~A / ~A~%" diffcds cds idealcds)
	(ros::ros-info "DIFF: ~A" diffcds)

	(cond
	 ((and (< (norm (float-vector (elt (send diffcds :worldpos) 0)
				      (elt (send diffcds :worldpos) 1)))
		  40.0)
	       (< (elt (car (rpy-angle (send diffcds :worldrot))) 0) 0.07))
	  (setq cds (check-detection :type fridge))
	  (ros::spin-once)
	  (send *ri* :spin-once)
	  (when cds
	    (when (setq ret (open-fridge :rarm cds (/ pi 2)))
	      (return)))
	  (speak-jp "こまった")
	  (send *pr2* :head :angle-vector (float-vector 0 0))
	  (send *pr2* :torso :angle-vector (float-vector 50))
	  (send *ri* :angle-vector (send *pr2* :angle-vector))
	  (send *ri* :go-pos-unsafe -0.1 0 0)
	  (send *ri* :wait-interpolation)
	  )
	 (t ;;  there is much difference
	  (send *ri* :go-pos-unsafe
		(/ (elt (send diffcds :worldpos) 0) 1000.0)
		(/ (elt (send diffcds :worldpos) 1) 1000.0)
		(rad2deg (elt (car (rpy-angle (send diffcds :worldrot))) 0)))
	  (unix::usleep (* 500 1000))
	  ;; (send *ri* :wait-interpolation)
	  ))
	))

    (when (not ret)
      (ros::ros-info "TIMEOUT: open-fridge-door");;
      (return-from open-fridge nil))

    ;; free door handle
    (ros::spin-once)
    (send *ri* :spin-once)
    (send *ri* :stop-grasp :rarm)
    (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
    (setq rend (send *pr2* :rarm :end-coords :copy-worldcoords))
    (send rend :translate (float-vector -100 -50 0) *pr2*)
    (send *pr2* :rarm :inverse-kinematics rend)
    (send *ri* :angle-vector (send *pr2* :angle-vector) 1000)

    ;; ?? open door ()
    (send *ri* :angle-vector-sequence
	  (list (float-vector 50 5 74 100 -90 -70 -6 20 -70 50 -59 -43 118 0 0 -2 31)
		(float-vector 50 5 74 100 -90 -70 -6 20 -0 60 -20 -90 118 -90 0 -2 31)
		(float-vector 50 5 74 100 -90 -70 -6 20 -7 45 -34 -110 12 -38 74 -2 31)
		(float-vector 50 5 74 100 -90 -70 -6 20 -45 26 -31 -62 22 -76 121 -2 31)
		(float-vector 150 5 74 100 -90 -70 -6 20 -7 45 -34 -110 12 -38 74 -2 31))
	  (list 1500 1000 1000 3000 3000))
    (send *ri* :wait-interpolation)

    ;; (send *pr2* :angle-vector (float-vector 200 5.00529 74.2038 105.001 -90.0035 -70.0071 -5.73378 19.9988 9.96029 39.7801 -45.0972 -121.542 94.4262 -111.922 63.0666 -0.0316 21.024))
    (send *pr2* :angle-vector (float-vector 199.971 5.30455 72.1244 105.231 -88.5188 -69.9972 -5.72958 19.9717 24.6812 36.1934 10.6903 -121.497 159.113 -79.5111 -2.92658 -1.35562 26.862))
    (send *ri* :angle-vector (send *pr2* :angle-vector))
    t
    ))

(defun query-ipad ()
  ;;copy from
  )

;; variable fridge not used
;;(detect-can *type* nil)
(defun detect-can (type fridge (&key (move t) (rotation)))
  (ros::spin-once)
  (send *ri* :spin-once)
  (when move
    (ros::ros-info "GO POS UNSAFE for grasping can")
    (send *ri* :go-pos-unsafe 0 0 (rad2deg 0.40))
    ;;(send *ri* :go-pos-unsafe 0.15 -0.30 0)
    (send *ri* :go-pos-unsafe 0.18 -0.31 0)
    (send *ri* :wait-interpolation))

  (ros::spin-once)
  (send *ri* :spin-once)
  (send *pr2* :angle-vector (send *ri* :state :potentio-vector))

  (let (isgrasp cds)
    (dotimes (trial 10)
      ;; detect cans which was indicated by ( type )
      (when (not (setq cds (check-detection :type type :single t)))
        (setq cds (check-detection :type type :tf-force t :timeout 30 :single t)))
      (when cds
	(send *obj* :reset-coords)
	(send *obj* :transform cds)
	(warn ";; print check cans~%")
	(dump-structure *standard-output*
			(list (send *pr2* :copy-worldcoords)
			      (send cds :copy-worldcoords)))
	(unless (boundp '*tfb*)
	  (setq *tfb* (instance ros::transform-broadcaster :init)))
	(send *tfb* :send-transform
	      cds "/base_footprint" "/object_pose_frame")
	(ros::spin-once)
	(send *ri* :spin-once)
	(send *pr2* :angle-vector (send *ri* :state :potentio-vector))
	(unless rotation
	  ;; FIXME: calc rotation from /map and /base_footprint
	  (setq rotation 0))

	(setq *can-cds* cds)
	;;(grasp-can-single cds :rotation rotation)
	;;(setq isgrasp (< 10 (send *ri* :start-grasp :rarm)))
	;;(when isgrasp
	;;  (return-from grasp-can t))
	(when t
	  (return-from detect-can t))
	)))
  nil)

;; (grasp-can *can-cds* :rarm)
(defun grasp-can (can-cds arm)
  (dotimes (trial 10)
    (grasp-can-single can-cds :rotation 0)
    (setq isgrasp (< 10 (send *ri* :start-grasp arm)))
    (when isgrasp
      (return-from grasp-can t)))
  nil)

;; variable fridge not used
(defun close-fridge (fridge)
  (send *ri* :go-pos-unsafe -0.3 0.05 -20)
  (unix::sleep 1)
  (send *ri* :angle-vector-sequence
	(list (float-vector 250 5 74 100 -90 -70 -6 20 -13 50 -59 -43 118 -90 62 -2 31)
	      (float-vector 200 5 74 100 -90 -70 -6 20 -50 36 -29 -43 118 -90 62 -2 31)
	      (float-vector 150 5 74 100 -90 -70 -6 20 -63 10 -39 -33 -49 -32 89 -2 32)
	      (float-vector 100 5 74 100 -90 -70 -6 20 -61 6 -74 -64 -35 -6 102 -2 33)
	      (float-vector 50 5 74 100 -90 -70 -6 20 3 -2 -64 -80 -24 -55 10 -2 33))
	(list 2000 1000 3000 2000 2000))
  (send *ri* :wait-interpolation)
  (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
  (pr2-tuckarm-pose :rarm)
  t
  )

;; variable start-spot not used
;; (hand-over :rarm nil)
(defun hand-over (arm start-spot &key (wait-shock t))
  (ros::spin-once)
  (let* ((av (send *ri* :state :potentio-vector))
	(tuckarm (check-tuckarm-pose))
	(isfreearm (eq arm tuckarm))
	;; this is for :larm
	(avs (list #f(12 0 64 70 -122 50 -115 160 -4 74 -105 -90 70 -5 20 2 15)
		   #f(12 6 9 106 -77 35 -124 -128 -4 75 -104 -89 70 0 20 3 30)
		   #f(12 13 21 62 -105 -117 -66 -71 -4 74 -104 -89 70 -5 20 4 40)
		   #f(12 9 24 50 -94 -158 -70 39 -4 74 -104 -89 70 -5 20 5 30)))
	(tms (make-list (length avs) :initial-element 1000))
	(l-r-reverse #f(1  -1 1 -1 1 -1 1 -1  -1 1 -1 1 -1 1 -1  -1 1)))
    ;;
    (if (eq arm :rarm)
	(setq avs
	      (mapcar #'(lambda(av)
			  (map float-vector #'*
			       (concatenate float-vector
					    (subseq av 0 1) (subseq av 8 15)
					    (subseq av 1 8) (subseq av 15 17))
			       l-r-reverse))
			  avs)))
    ;;
    (unless isfreearm
      (pr2-reset-pose)
      (setq avs (subseq avs (- (length avs) 2))
	    tms (subseq tms (- (length avs) 2))
	    av (send *ri* :state :potentio-vector))
      (setq tuckarm arm))
    ;;
    (send *ri* :angle-vector-sequence avs tms)
    (send *ri* :wait-interpolation)
    ;;
    (if (and wait-shock (not (numberp wait-shock))) ;; if wait-shock = t
	(setq wait-shock 10))
    (if wait-shock
	(progn (wait-for-hand-impact arm :timeout wait-shock)
	       (ros::ros-info "return from gripper sensor event")
	       (send *ri* :move-gripper arm 0.08 :wait t))
      (progn
	(send *ri* :move-gripper arm 0.08 :wait t)
	(unix::sleep 3)))
    ;;
    (send *ri* :angle-vector-sequence (append (cdr (reverse avs)) (list av)) tms)
    (send *ri* :move-gripper arm 0.00 :wait nil)
    (send *ri* :wait-interpolation)
    ;;
    (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
    (pr2-tuckarm-pose tuckarm)
    ))