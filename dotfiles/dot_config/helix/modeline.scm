(require "moka/moka.scm")
(require "scopeline/scopeline.scm")

;; Nord
(moka-configure!
  #:sections
  (list
    (moka-section (list (moka-segment 'mode #:bg "#88c0d0" #:fg "#2e3440" #:bubble? #f #:gap 0)
                   (moka-segment 'file #:bg "#4c566a" #:fg "#d8dee9" #:bubble? #f #:gap 0)
                   (moka-segment 'git-branch #:bg "#3b4252" #:fg "#d8dee9" #:bubble? #f))
      #:align
      'left)
    (moka-section (list (moka-segment 'lsp #:bg "#3b4252" #:fg "#d8dee9" #:bubble? #f #:gap 0)
                   (moka-segment 'position #:bg "#5e81ac" #:fg "#eceff4" #:bubble? #f))
      #:align
      'right)))
(moka-enable!)

(moka-enable!)
