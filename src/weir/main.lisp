
(in-package :weir)


(deftype single-array () `(simple-array veq:ff))
(deftype pos-int (&optional (bits 31)) `(unsigned-byte ,bits))


(defstruct (weir (:constructor -make-weir))
  (adj-size 100 :type pos-int :read-only t)
  (alt-res (make-hash-table :test #'eq :size 20 :rehash-size 2f0))
  (dim 2 :type pos-int :read-only t)
  (grps (make-hash-table :test #'equal :size 20 :rehash-size 2f0))
  (kdtree nil :read-only nil)
  (max-verts 5000 :type pos-int :read-only t)
  (name :main :type symbol :read-only t)
  (num-verts 0 :type pos-int)
  (props (make-hash-table :test #'equal :size 500 :rehash-size 2f0))
  (set-size 5 :type pos-int :read-only t)
  (verts nil :type veq:fvec))


(defstruct (grp (:constructor -make-grp))
  (name nil :type symbol :read-only t)
  (grph nil :type graph::graph))


(declaim (inline -make-hash-table))
(defun -make-hash-table (&key init (test #'equal))
  (declare #.*opt* (list init) (function test))
  (loop with res = (make-hash-table :test test)
        for (k v) in init
        do (setf (gethash k res) v)
        finally (return res)))

(declaim (inline -init-grps))
(defun -init-grps (adj-size set-size)
  (declare #.*opt* (number adj-size set-size))
  (-make-hash-table
    :init `((nil ,(-make-grp :name :main
                             :grph (graph:make :adj-size adj-size
                                               :set-size set-size))))))

(defun make (&key (max-verts 5000) (adj-size 4) (set-size 10) name (dim 2))
  "
  make weir instances

  - max-verts is the maximum number of verts in weir (across all grps).
  - set-size is the initial size of edge adjacency sets.
      ie. the expected number of vertices in the graph
  - adj-size is the initial size of the adjacency map.
      ie. the expected number of incident vertices
  - dim is the vector dimension of vertices
  "
  (declare #.*opt* (pos-int max-verts adj-size set-size dim) (symbol name))
  (when (not (> 4 dim 1)) (error "dim must be 2 or 3."))
  (-make-weir :name name :set-size set-size :adj-size adj-size :dim dim
    :max-verts max-verts
    :verts (veq:f$make :dim dim :n max-verts)
    :grps (-init-grps adj-size set-size)))

(defun clear! (wer &key keep-props keep-verts keep-grps)
  (declare #.*opt* (weir wer) (boolean keep-props keep-grps keep-verts))
  "clear values of weir instance. unless keep is set for a given property"
  ; TODO: hard reset verts to 0?

  (setf (weir-kdtree wer) nil
        (weir-alt-res wer) (make-hash-table :test #'eq :size 20 :rehash-size 2f0))

  (unless keep-verts (setf (weir-num-verts wer) 0))
  (unless keep-props
          (setf (weir-props wer)
                (make-hash-table :test #'equal :size 500 :rehash-size 2f0)))
  (unless keep-grps
          (setf (weir-grps wer)
                (-init-grps (weir-adj-size wer) (weir-set-size wer))))
  wer)


(defun add-grp! (wer &key name &aux (name* (if name name (gensym "grp"))))
  (declare #.*opt* (weir wer))
  "
  constructor for grp instances.

  grps are edge graphs.

  nil is the default grp. as such, nil is not an allowed grp name (there is
  always a default grp named nil). if name is nil, the name will be a gensym.

  edges can be associated with multiple grps.

  verts are global. that is, they do not belong to any grp on their own.
  however, if a vert is associated with an edge, that vert is also associated
  with whatever grp that edge belongs to.

    - to get verts in a grp: (get-grp-verts wer :g g).
    - to get indices of verts (in a grp): (get-vert-inds wer :g g)
    - ...

  the grp functionality is somewhat experimental.
  "
  (with-struct (weir- grps adj-size set-size) wer
    (multiple-value-bind (v exists) (gethash name* grps)
      (declare (ignore v) (boolean exists))
      (when exists (error "grp name already exists: ~a" name*)))
    (setf (gethash name* grps) (-make-grp
                                 :name name*
                                 :grph (graph:make :adj-size adj-size
                                                   :set-size set-size))))
  name*)

(defun reset-grp! (wer &key g)
  (declare #.*opt* (weir wer))
  (setf (gethash g (weir-grps wer))
          (-make-grp :name (if g g :main)
                     :grph (graph:make :adj-size (weir-adj-size wer)
                                       :set-size (weir-set-size wer)))))

(defun del-grp! (wer &key g)
  (declare #.*opt* (symbol g))
  (remhash g (weir-grps wer)))


(defmacro with-grp ((wer g* g) &body body)
  (declare (symbol wer))
  "select grp g from weir instance. g will be available in this context as g*"
  (alexandria:with-gensyms (grps exists gname wname)
    `(let ((,wname ,wer)
           (,gname ,g))
      (let ((,grps (weir-grps ,wname)))
        (multiple-value-bind (,g* ,exists)
          (gethash ,gname ,grps)
            (unless ,exists
                    (error "attempted to access invalid group: ~a" ,gname))
            (progn ,@body))))))


(defun get-all-grps (wer &key main)
  (declare #.*opt* (weir wer) (boolean main))
  "returns all grps. use :main t to include main/nil grp"
  (loop for g being the hash-keys of (weir-grps wer)
        ; ignores nil (main) grp, unless overridden with :main t
        if (or g main) collect g))

(defun get-grp (wer &key g)
  (declare #.*opt* (weir wer))
  "returns the grp g. if g is not provided, the main/nil grp will be returned"
  (gethash g (weir-grps wer)))

(defun grp-exists (wer &key g)
  (declare #.*opt* (weir wer))
  (mvb (g exists) (get-grp wer :g g)
       (declare (ignore g))
       exists))


(defun get-num-edges (wer &key g)
  (declare #.*opt* (weir wer))
  (with-grp (wer g* g)
    (graph:get-num-edges (grp-grph g*))))

(defun get-num-grps (wer)
  (declare #.*opt* (weir wer))
  "number of grps excluding main/nil grp"
  (1- (hash-table-count (weir-grps wer))))


(defun get-edges (wer &key g)
  (declare #.*opt* (weir wer))
  (with-grp (wer g* g)
    (graph:get-edges (grp-grph g*))))

(defun get-connected-verts (wer &key g)
  (declare #.*opt* (weir wer))
  "get verts in g with at least one connected edge"
  (with-grp (wer g* g)
    (graph:get-verts (grp-grph g*))))

(defun get-grp-as-path (wer &key g)
  (declare #.*opt* (weir wer))
  "returns (values path cycle?)"
  (graph:edge-set->path (weir:get-edges wer :g g)))


; TODO: get-all-incident-edges (not just in grp g)?
(defun get-incident-edges (wer v &key g)
  (declare #.*opt* (weir wer) (pos-int v))
  "incident edges of v"
  (with-grp (wer g* g)
    (graph:get-incident-edges (grp-grph g*) v)))

(defun get-incident-verts (wer v &key g)
  (declare #.*opt* (weir wer) (pos-int v))
  "incident verts of v"
  (with-grp (wer g* g) (graph:get-incident-verts (grp-grph g*) v)))


(defun get-vert-inds (wer &key g order)
  "
  returns all vertex indices that belongs to a grp.
  note: verts only belong to a grp if they are part of an edge in grp.
  "
  (declare #.*opt* (weir wer) (boolean order))
  (with-struct (weir- grps) wer
    (multiple-value-bind (g* exists) (gethash g grps)
      (if exists (if order (sort (the list (graph:get-verts (grp-grph g*))) #'<)
                           (graph:get-verts (grp-grph g*)))
                 (error "grp does not exist: ~a" g)))))


(defun edge-exists (wer ee &key g)
  (declare #.*opt* (weir wer) (list ee))
  "t if edge exists"
  (with-grp (wer g* g) (apply #'graph:mem (grp-grph g*) ee)))


(defun add-edge! (wer a b &key g)
  "
  adds a new edge to weir. provided the edge is valid.
  otherwise it returns nil.

  returns nil if the edge exists already.
  "
  (declare #.*opt* (weir wer) (pos-int a b))
  (when (= a b) (return-from add-edge! nil))
  (with-grp (wer g* g)
    (with-struct (weir- num-verts) wer
      (declare (pos-int num-verts))
      (with-struct (grp- grph) g*
        (when (and (< a num-verts) (< b num-verts))
              (when (graph:add grph a b)
                    (sort (list a b) #'<)))))))


(defun ladd-edge! (wer ee &key g)
  (declare #.*opt* (weir wer) (list ee))
  (destructuring-bind (a b) ee
    (declare (pos-int a b))
    (add-edge! wer a b :g g)))


(defun add-edges! (wer ee &key g)
  "adds multiple edges (see above). returns a list of the results"
  (declare #.*opt* (weir wer) (list ee))
  (loop for e of-type list in ee collect (ladd-edge! wer e :g g)))


(defun del-edge! (wer a b &key g)
  (declare #.*opt* (weir wer) (pos-int a b))
  (with-grp (wer g* g)
    (with-struct (grp- grph) g*
      (graph:del grph a b))))


(defun ldel-edge! (wer ee &key g)
  (declare #.*opt* (weir wer) (list ee))
  (with-grp (wer g* g)
    (with-struct (grp- grph) g*
      (apply #'graph:del grph ee))))


(defun swap-edge! (wer a b &key g from)
  (declare #.*opt* (weir wer) (pos-int a b))
  "move edge from grp from to g"
  (when (del-edge! wer a b :g from)
        (add-edge! wer a b :g g)))

(defun lswap-edge! (wer ee &key g from)
  (declare #.*opt* (weir wer) (list ee))
  "move edge from grp from to g"
  ; (when (eq g from) (error "nothing to do"))
  (when (ldel-edge! wer ee :g from)
        (ladd-edge! wer ee :g g)))


(defun del-path! (wer path &key g closed)
  (declare #.*opt* (weir wer) (list path) (boolean closed))
  "del all edges in path"
  (when closed (setf path (cons (last* path) path)))
  (with-grp (wer g* g)
    (with-struct (grp- grph) g*
      (loop for a of-type pos-int in path and b of-type pos-int in (cdr path)
            collect (graph:del grph a b)))))


(defun split-edge-ind! (wer a b &key via g force)
  (declare #.*opt* (weir wer) (pos-int a b via) (boolean force))
  "add delete edge (a b) and add edges (a via b)"
  (when (or (del-edge! wer a b :g g) force)
        (list (add-edge! wer a via :g g)
              (add-edge! wer via b :g g))))

(defun lsplit-edge-ind! (wer ee &key via g force)
  (declare #.*opt* (weir wer) (list ee) (pos-int via) (boolean force))
  (destructuring-bind (a b) ee
    (declare (pos-int a b))
    (split-edge-ind! wer a b :via via :g g :force force)))


(defun collapse-verts! (wer u v &key g)
  (declare #.*opt* (weir wer) (pos-int u v))
  "move all incident verts of v to u. returns the moved verts."
  (loop with incident = (get-incident-verts wer v :g g)
        for w in incident
        do (del-edge! wer v w :g g)
           (add-edge! wer w u :g g)
        finally (return incident)))

(defun lcollapse-verts! (wer uv &key g)
  (declare #.*opt* (weir wer) (list uv))
  "move all incident verts of v1, v2, ... to u. assuming uv = (u v1 v2 ...)"
  (loop with u of-type pos-int = (car uv)
        with res of-type list = (list)
        for v of-type pos-int in (cdr uv)
        do (loop with incident of-type list = (get-incident-verts wer v :g g)
                 for w in incident
                 do (del-edge! wer v w :g g)
                    (add-edge! wer w u :g g))
        finally (return res)))


(defun add-path-ind! (wer path &key g closed)
  (declare #.*opt* (weir wer) (list path) (boolean closed))
  "create edges of path"
  (loop for a of-type pos-int in path
        and b of-type pos-int in
          (if closed (butlast (cons (math:last* path) path) 1) (cdr path))
        collect (add-edge! wer a b :g g)))

(weird:abbrev ae! add-edge!)
(weird:abbrev de! del-edge!)

