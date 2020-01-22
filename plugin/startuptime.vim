if exists('g:loaded_startuptime')
  finish
endif
let g:loaded_startuptime = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists(':StartupTime')
  command -nargs=* StartupTime :call startuptime#StartupTime(<f-args>)
endif

" ************************************************************
" * User Configuration
" ************************************************************

" TODO: rename columns to indicate what they are
" The default highlight groups (for colors) are specified below.
" Change these default colors by defining or linking the corresponding
" highlight group.
" E.g., the following will use the Title highlight for column 1.
" :highlight link StartupTimeColumn1 Title
" E.g., the following will use custom highlight colors for column 2.
" :highlight StartupTimeColumn2 term=bold ctermfg=12 ctermbg=159 guifg=Blue guibg=LightCyan
highlight default link StartupTimeColumn1 Type
highlight default link StartupTimeColumn2 Comment
highlight default link StartupTimeColumn3 Special
highlight default StartupTimeColumn4 ctermfg=7 guifg=Grey

let &cpo = s:save_cpo
unlet s:save_cpo
