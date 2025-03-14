#lang racket

(require rackunit/text-ui racket/splicing)
(require rackunit rosette/base/core/store rosette/base/core/result rosette/lib/roseunit)
(require rosette/base/struct/struct rosette/base/adt/vector rosette/base/adt/box)
(require (only-in rosette/base/form/define define-symbolic)
         (only-in rosette/base/core/bool @boolean? && !)
         (only-in rosette/base/core/real @integer? @=)
         (only-in rosette/base/core/merge merge merge*))

(provide check-store)

(define (check-store s lvs)
  (check-equal? (length s) (length lvs))
  (for ([slv s][lv lvs])
    (match* (slv lv)
      [((cons sl sv) (list base offset v))
       (check-eq? sv v)
       (check-eq? (location-base sl) base)
       (check-eq? (location-offset sl) offset)])))

(define (store-loc s idx) (car (list-ref s idx)))

(struct exn:test exn:fail ())

(define (raise-exn:test [msg ""])
  (raise (exn:test msg (current-continuation-marks))))

(define (check-box-0)
  (define x (@box 1))
  (define y (@box 2))
  (check-match (with-store 1) (normal 1 '()))
  (check-match (with-store (+ (@unbox x) (@unbox y))) (normal 3 '()))
  (check-exn exn:test? (thunk (with-store (begin (raise-exn:test) 1)))))

(define (check-box-1)
  (define z (@box 10))
  (define r (with-store (begin (@set-box! z 2) (@unbox z))))
  (check-pred normal? r)
  (match-define (normal v s) r)
  (check-equal? v 2)
  (check-equal? (@unbox z) 10)
  (check-store s `((,z 0 2)))
  (location-set! (store-loc s 0) 20)
  (check-equal? (location-ref (store-loc s 0)) 20)
  (check-equal? (@unbox z) 20)
  (check-exn exn:test? (thunk (with-store (begin (@set-box! z 2) (raise-exn:test) 2))))
  (check-equal? (@unbox z) 20))

(define (check-box-2)
  (define z (@box 10))
  (define x z)
  (define r (with-store (begin (@set-box! z 3) (@set-box! x 2) (@unbox z))))
  (check-pred normal? r)
  (match-define (normal v s) r)
  (check-equal? v 2)
  (check-equal? (@unbox z) 10)
  (check-store s `((,z 0 2)))
  (location-set! (store-loc s 0) 20)
  (check-equal? (location-ref (store-loc s 0)) 20)
  (check-equal? (@unbox z) 20)
  (check-exn exn:test? (thunk (with-store (begin (@set-box! z 2) (raise-exn:test) 2))))
  (check-equal? (@unbox z) 20))

(define (check-box-3)
  (define x (@box 1))
  (define y (@box 2))
  (define r
    (with-store
        (let ([tmp (@unbox x)])
          (@set-box! x (@unbox y))
          (@set-box! y tmp))))
  (check-pred normal? r)
  (match-define (normal v s) r)
  (check-equal? v (void))
  (check-equal? (@unbox x) 1)
  (check-equal? (@unbox y) 2)
  (check-store s `((,y 0 1) (,x 0 2)))
  (match-define (cons yl yv) (list-ref s 0))
  (match-define (cons xl xv) (list-ref s 1))
  (location-set! xl (+ (location-ref xl) xv))
  (location-set! yl (+ (location-ref yl) yv))
  (check-equal? (@unbox x) 3)
  (check-equal? (@unbox y) 3)
  (check-exn exn:test? (thunk (with-store (begin (@set-box! x 4) (@set-box! y 4) (raise-exn:test)))))
  (check-equal? (@unbox x) 3)
  (check-equal? (@unbox y) 3)
  (check-exn exn:test? (thunk (with-store (begin (@set-box! y 4) (raise-exn:test) (@set-box! x 4)))))
  (check-equal? (@unbox x) 3)
  (check-equal? (@unbox y) 3))

(define (check-box-4)
  (define x (@box 1))
  (define y (@box 2))
  (define z (@box 3))
  (define r
    (with-store
        (let ([tmp (@unbox x)])
          (with-store
              (begin (@set-box! x (@unbox y))
                     (@set-box! y (@unbox z))
                     (@set-box! y -1)
                     (@set-box! y (@unbox z))
                     (@set-box! z tmp))))))
  (check-match r (normal (normal (? void?) (? list?)) (list)))
  (match-define (normal (normal _ s) _) r)
  (check-equal? (@unbox x) 1)
  (check-equal? (@unbox y) 2)
  (check-equal? (@unbox z) 3)
  (check-store s `((,z 0 1) (,y 0 3) (,x 0 2)))
  (match-define (list (cons zl zv) (cons yl yv) (cons xl xv)) s)
  (location-set! xl (+ xv (location-ref xl)))
  (location-set! yl (+ yv (location-ref yl)))
  (location-set! zl (+ zv (location-ref zl)))
  (check-equal? (@unbox x) 3)
  (check-equal? (@unbox y) 5)
  (check-equal? (@unbox z) 4)
  (check-exn
   exn:test?
   (thunk (with-store (with-store (begin (@set-box! y 6) (@set-box! z 7) (@set-box! x 8) (raise-exn:test))))))
  (check-equal? (@unbox x) 3)
  (check-equal? (@unbox y) 5)
  (check-equal? (@unbox z) 4))

(define (check-box-5)
  (define x (@box 1))
  (define y (@box 2))
  (define z (@box 3))
  (define r
    (with-store
        (begin                                               ; x,y,z = 1,2,3
          (@set-box! z (@unbox x))                           ; x,y,z = 1,2,1
          (begin0 
            (with-store
                (begin (@set-box! x (+ (@unbox z) (@unbox y)))   ; x,y,z = 3,2,1
                       (@set-box! y (+ 1 (@unbox x)))            ; x,y,z = 3,4,1
                       (@set-box! z (+ (@unbox y) (@unbox z))))) ; x,y,z = 3,4,5
            (@set-box! x (* (@unbox y) (@unbox z)))))))      ; x,y,z = 2,2,1                 
  (check-match r (normal (normal (? void?) (? list?)) (? list ?)))
  (match-define (normal (normal _ s1) s2) r)
  (check-equal? (@unbox x) 1)
  (check-equal? (@unbox y) 2)
  (check-equal? (@unbox z) 3)
  (check-store s1 `((,z 0 5) (,y 0 4) (,x 0 3)))
  (check-store s2 `((,x 0 2) (,z 0 1))))

(define (check-vector-0)
  (define v (@vector 1 2 3))
  (define r1 (with-store (@vector-set! v 1 4)))
  (check-match r1 (normal (? void?) (? list?)))
  (match-define (normal _ s1) r1)
  (check-equal? v (@vector 1 2 3))
  (check-store s1 `((,v 1 4)))
  (location-set! (store-loc s1 0) 5)
  (check-equal? v (@vector 1 5 3))
  (define r2 (with-store (@vector-fill! v 6)))
  (check-match r2 (normal (? void?) (? list?)))
  (match-define (normal _ s2) r2)
  (check-equal? v (@vector 1 5 3))
  (check-store s2 `((,v 2 6) (,v 1 6) (,v 0 6)))
  (check-equal? (store-loc s1 0) (store-loc s2 1))
  (location-set! (store-loc s2 0) 4)
  (location-set! (store-loc s2 2) 5)
  (check-equal? v (@vector 5 5 4))
  (define w (@vector 7 8))
  (define r3 (with-store (begin (@vector-copy! v 1 w 0) (@vector-copy! w 0 v 0 1))))
  (check-match r3 (normal (? void?) (? list?)))
  (match-define (normal _ s3) r3)
  (check-equal? v (@vector 5 5 4))
  (check-equal? w (@vector 7 8))
  (check-store s3 `((,w 0 5) (,v 2 8) (,v 1 7))))

(define (check-vector-1)
  (define v (@vector 1 2 3))
  (define w (@vector 4 5))
  (define-symbolic b @boolean?)
  (define-symbolic i @integer?)
  (define r1 (with-store (@vector-set! w i 6)))
  (match-define (normal (? void?) s1) r1)
  (check-equal? w (@vector 4 5))
  (check-store s1 `((,w 1 ,(merge (@= i 1) 6 5)) (,w 0 ,(merge (@= i 0) 6 4))))
  (define r2 (with-store (@vector-set! (merge b w v) 1 6)))
  (match-define (normal (? void?) s2) r2)
  (check-equal? v (@vector 1 2 3))
  (check-equal? w (@vector 4 5))
  (check-store s2 `((,v 1 ,(merge (! b) 6 2))
                    (,w 1 ,(merge b 6 5))))
  (define r3 (with-store (@vector-set! (merge b w v) i 6)))
  (match-define (normal (? void?) s3) r3)
  (check-equal? v (@vector 1 2 3))
  (check-equal? w (@vector 4 5))
  (check-store s3 `((,v 2 ,(merge (&& (! b) (@= i 2)) 6 3))
                    (,v 1 ,(merge (&& (! b) (@= i 1)) 6 2))
                    (,v 0 ,(merge (&& (! b) (@= i 0)) 6 1))
                    (,w 1 ,(merge (&& b (@= i 1)) 6 5))
                    (,w 0 ,(merge (&& b (@= i 0)) 6 4))))
  (define r4 (with-store (@vector-fill! (merge b w v) 6)))
  (match-define (normal (? void?) s4) r4)
  (check-equal? v (@vector 1 2 3))
  (check-equal? w (@vector 4 5))
  (check-store s4 `((,v 2 ,(merge (! b) 6 3))
                    (,v 1 ,(merge (! b) 6 2))
                    (,v 0 ,(merge (! b) 6 1))
                    (,w 1 ,(merge b 6 5))
                    (,w 0 ,(merge b 6 4)))))

(define (check-vector-2)
  (define v (@vector 1 2 3))
  (define w (@vector 4 5))
  (define z (@box v))
  (define r1
    (with-store
        (begin (@vector-set! w 0 6)
               (@vector-set! (@unbox z) 2 7)
               (@set-box! z w))))
  (match-define (normal (? void?) s1) r1)
  (check-eq? (@unbox z) v)
  (check-equal? v (@vector 1 2 3))
  (check-equal? w (@vector 4 5))
  (check-store s1 `((,z 0 ,w) (,v 2 7) (,w 0 6)))
  (define r2
    (with-store
        (begin
          (@set-box! z w)
          (begin0
            (with-store
                (begin (@vector-set! (@unbox z) 0 6)
                       (@set-box! z v)))
            (@vector-set! (@unbox z) 1 7)))))
  (match-define (normal (normal (? void?) s2i) s2o) r2)
  (check-eq? (@unbox z) v)
  (check-equal? v (@vector 1 2 3))
  (check-equal? w (@vector 4 5))
  (check-store s2i `((,z 0 ,v) (,w 0 6)))
  (check-store s2o `((,w 1 7) (,z 0 ,w))))

(struct triple ([x #:mutable] y [z #:mutable]) #:transparent)

(define (check-struct-0)
  (define p (triple 1 2 3))
  (define r1 (with-store (set-triple-z! p 4)))
  (match-define (normal (? void?) s1) r1)
  (check-equal? p (triple 1 2 3))
  (check-store s1 `((,p 2 4)))
  (define r2 (with-store (begin (set-triple-z! p (triple-x p)) (set-triple-x! p (triple-y p)))))
  (match-define (normal (? void?) s2) r2)
  (check-equal? p (triple 1 2 3))
  (check-store s2 `((,p 0 2) (,p 2 1)))
  (check-equal? (store-loc s1 0) (store-loc s2 1)))

(define (check-struct-1)
  (define p (triple 1 2 3))
  (define q (triple 4 5 6))
  (define-symbolic b @boolean?)
  (define r1 (with-store (set-triple-z! (merge b p q) 7)))
  (match-define (normal (? void?) s1) r1)
  (check-equal? p (triple 1 2 3))
  (check-equal? q (triple 4 5 6))
  (check-store s1 `((,q 2 ,(merge (! b) 7 6)) (,p 2 ,(merge b 7 3))))
  (define r2 (with-store (begin (set-triple-z! (merge b p q) (triple-x (merge b p q)))
                                (set-triple-x! (merge b p q) (triple-y (merge b p q))))))
  (match-define (normal (? void?) s2) r2)
  (check-equal? p (triple 1 2 3))
  (check-equal? q (triple 4 5 6))
  (check-store s2 `((,q 0 ,(merge (! b) (merge b 2 5) 4))
                    (,p 0 ,(merge b (merge b 2 5) 1))
                    (,q 2 ,(merge (! b) (merge b 1 4) 6))
                    (,p 2 ,(merge b (merge b 1 4) 3))))
  (define r3 (with-store (begin (set-triple-z! (merge b p 1) (triple-x (merge b p 1)))
                                (set-triple-x! (merge b p 1) (triple-y (merge b p 1))))))
  (match-define (normal (? void?) s3) r3)
  (check-equal? p (triple 1 2 3))
  (check-equal? q (triple 4 5 6))
  (check-store s3 `((,p 0 2) (,p 2 1))))

(define (check-merge-0)
  (define v (@vector 1 2 3))
  (match-define (normal 5 s1) (with-store (+ (@vector-ref v 1) (@vector-ref v 2))))
  (match-define (normal 1 s2) (with-store (@vector-ref v 0)))
  (check-equal? s1 null)
  (check-equal? s2 null)
  (check-equal? v (@vector 1 2 3))
  (define-symbolic b @boolean?)
  (merge-stores! (list b (! b)) (list s1 s2))
  (check-equal? v (@vector 1 2 3)))
  
  
(define (check-merge-1)
  (define z (@box 1))
  (define v (@vector 2 3 4 5 6 7 8 9 10))
  (define p (triple 11 12 13))
  (define r1 (with-store (begin (@set-box! z -1) (@vector-set! v 5 -7) (set-triple-z! p -13))))
  (match-define (normal (? void?) s1) r1)
  (check-equal? z (@box 1))
  (check-equal? v (@vector 2 3 4 5 6 7 8 9 10))
  (check-equal? p (triple 11 12 13))
  (check-store s1 `((,p 2 -13) (,v 5 -7) (,z 0 -1)))
  (merge-stores! (list #t) (list s1))
  (check-equal? z (@box -1))
  (check-equal? v (@vector 2 3 4 5 6 -7 8 9 10))
  (check-equal? p (triple 11 12 -13))
  (location-set! (store-loc s1 0) 13)
  (location-set! (store-loc s1 1) 7)
  (location-set! (store-loc s1 2) 1)
  (check-equal? z (@box 1))
  (check-equal? v (@vector 2 3 4 5 6 7 8 9 10))
  (check-equal? p (triple 11 12 13))
  (define-symbolic b @boolean?)
  (merge-stores! (list b) (list s1))
  (check-equal? z (@box -1))
  (check-equal? v (@vector 2 3 4 5 6 -7 8 9 10))
  (check-equal? p (triple 11 12 -13)))

(define (check-merge-2)
  (define v (@vector 1 2 3))
  (define-symbolic b @boolean?)
  (match-define (normal (? void?) s1t) (with-store (begin (@vector-set! v 0 4) (@vector-set! v 1 5) (@vector-set! v 2 6))))
  (match-define (normal (? void?) s1f) (with-store (begin (@vector-set! v 0 -4) (@vector-set! v 1 -5) (@vector-set! v 2 -6))))
  (merge-stores! (list b (! b)) (list s1t s1f))
  (check-equal? v (@vector (merge b 4 -4) (merge b 5 -5) (merge b 6 -6)))
  (@vector-copy! v 0 (vector 1 2 3))
  (match-define (normal (? void?) s2t) (with-store (begin (@vector-set! v 0 4) (@vector-set! v 2 6))))
  (match-define (normal (? void?) s2f) (with-store (begin (@vector-set! v 1 -5))))
  (merge-stores! (list b (! b)) (list s2t s2f))
  (check-equal? v (@vector (merge b 4 1) (merge b 2 -5) (merge b 6 3)))
  (@vector-copy! v 0 (vector 1 2 3))
  (match-define (normal (? void?) s3t) (with-store (begin (@vector-set! v 0 4) (@vector-set! v 1 5))))
  (match-define (normal (? void?) s3f) (with-store (begin (@vector-set! v 1 -5) (@vector-set! v 2 -6))))
  (merge-stores! (list b (! b)) (list s3t s3f))
  (check-equal? v (@vector (merge b 4 1) (merge b 5 -5) (merge b 3 -6))))

(define (check-merge-3)
  (define v (@vector 1 2 3 4 5 6 7)) 
  (define-symbolic a b c @boolean?)
  (match-define (normal (? void?) s1)
    (with-store
        (begin (@vector-set! v 0 11)
               (@vector-set! v 1 12)
               (@vector-set! v 2 13)
               (@vector-set! v 3 14))))
  (match-define (normal (? void?) s2)
    (with-store
        (begin (@vector-set! v 1 22)
               (@vector-set! v 3 24)
               (@vector-set! v 4 25)
               (@vector-set! v 5 26))))
 (match-define (normal (? void?) s3)
    (with-store
        (begin (@vector-set! v 2 33)
               (@vector-set! v 3 34)
               (@vector-set! v 4 35)
               (@vector-set! v 6 37))))
  (check-equal? v (@vector 1 2 3 4 5 6 7))
  (merge-stores! (list a b c) (list s1 s2 s3))
  (check-equal? (@vector-ref v 0) (merge* (cons a 11) (cons b 01) (cons c 01)))
  (check-equal? (@vector-ref v 1) (merge* (cons a 12) (cons b 22) (cons c 02)))
  (check-equal? (@vector-ref v 2) (merge* (cons a 13) (cons b 03) (cons c 33)))
  (check-equal? (@vector-ref v 3) (merge* (cons a 14) (cons b 24) (cons c 34)))
  (check-equal? (@vector-ref v 4) (merge* (cons a 05) (cons b 25) (cons c 35)))
  (check-equal? (@vector-ref v 5) (merge* (cons a 06) (cons b 26) (cons c 06)))
  (check-equal? (@vector-ref v 6) (merge* (cons a 07) (cons b 07) (cons c 37))))

(define box-tests
  (test-suite+
   "Box tests for rosette/base/core/store.rkt"
   (check-box-0)
   (check-box-1)
   (check-box-2)
   (check-box-3)
   (check-box-4)
   (check-box-5)))

(define vector-tests
  (test-suite+
   "Vector tests for rosette/base/core/store.rkt"
   (check-vector-0)
   (check-vector-1)
   (check-vector-2)))

(define struct-tests
  (test-suite+
   "Struct tests for rosette/base/core/store.rkt"
   (check-struct-0)
   (check-struct-1)))

(define merge-tests
  (test-suite+
   "Merge tests for rosette/base/core/store.rkt"
   (check-merge-0)
   (check-merge-1)
   (check-merge-2)
   (check-merge-3)))

(module+ test
  (time (run-tests box-tests))
  (time (run-tests vector-tests))
  (time (run-tests struct-tests))
  (time (run-tests merge-tests)))


