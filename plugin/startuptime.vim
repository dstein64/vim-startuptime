if get(g:, 'loaded_startuptime', 0)
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

let g:startuptime_more_info_key_seq = 
      \ get(g:, 'startuptime_more_info_key_seq', '<space>')

" The default highlight groups (for colors) are specified below.
" Change these default colors by defining or linking the corresponding
" highlight group.
" E.g., the following will use the Title highlight for sourcing event text.
" :highlight link StartupTimeSourcingEvent Title
" E.g., the following will use custom highlight colors for event times.
" :highlight StartupTimeTime term=bold ctermfg=12 ctermbg=159 guifg=Blue guibg=LightCyan
highlight default link StartupTimeHeader VisualNOS
highlight default link StartupTimeSourcingEvent Type
highlight default link StartupTimeOtherEvent Type
highlight default link StartupTimeTime Comment
highlight default link StartupTimePercent Special
highlight default StartupTimePlot ctermfg=7 guifg=Grey

let &cpo = s:save_cpo
unlet s:save_cpo
