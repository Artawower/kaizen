if exists('current_compiler')
  finish
endif
let current_compiler = 'npm'

CompilerSet makeprg=npm
let &l:errorformat = join([
      \ '%EError: %f:%l:%c - error %m',
      \ '%WWarning: %f:%l:%c - warning %m',
      \ '%E%f(%l\,%c): error %m',
      \ '%E%f:%l:%c - error %m',
      \ '%E%.%#[ERROR] %m',
      \ '%W%.%#[WARNING] %m',
      \ '%Z%\s%#%f:%l:%c:',
      \ '%-C%.%#',
      \ '%-G%.%#',
      \ ], ',')
