#!/bin/bash

set -e
sbcl --quit \
     --eval '(load "~/quicklisp/setup.lisp")'\
     --eval '(load "weird.asd")'\
     --eval '(progn
                (handler-case (ql:quickload :weird :verbose t)
                  (error (c) (print c) (sb-ext:quit :unix-status 2)))
                (handler-case (progn (ql:quickload :prove)
                                     (asdf:test-system :weird))
                  (error (c) (print c) (sb-ext:quit :unix-status 3))))'

