if get(g:, 'loaded_startuptime', 0)
  finish
endif
let g:loaded_startuptime = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists(':StartupTime')
  command -nargs=* -complete=custom,startuptime#CompleteOptions StartupTime
        \ :call startuptime#StartupTime(<q-mods>, <f-args>)
endif

" *************************************************
" * Utils
" *************************************************

" Returns true if Vim is running on Windows Subsystem for Linux.
function! s:OnWsl()
  " Recent versions of neovim provide a 'wsl' pseudo-feature.
  if has('wsl') | return 1 | endif
  if !has('unix') | return 0 | endif
  " Read /proc/version instead of using `uname` because 1) it's faster and 2)
  " so that this works in restricted mode.
  try
    if filereadable('/proc/version')
      let l:version = readfile('/proc/version', '', 1)
      if len(l:version) ># 0 && stridx(l:version[0], 'Microsoft') ># -1
        return 1
      endif
    endif
  catch
  endtry
  return 0
endfunction

" *************************************************
" * User Configuration
" *************************************************

let g:startuptime_more_info_key_seq = 
      \ get(g:, 'startuptime_more_info_key_seq', 'K')
let g:startuptime_split_edit_key_seq =
      \ get(g:, 'startuptime_split_edit_key_seq', 'gf')

let g:startuptime_exe_path =
      \ get(g:, 'startuptime_exe_path', exepath(v:progpath))
let g:startuptime_exe_args =
      \ get(g:, 'startuptime_exe_args', [])

let g:startuptime_sort = get(g:, 'startuptime_sort', 1)
let g:startuptime_tries = get(g:, 'startuptime_tries', 1)
let g:startuptime_sourcing_events = get(g:, 'startuptime_sourcing_events', 1)
let g:startuptime_other_events = get(g:, 'startuptime_other_events', 1)
" '--self' was removed, with '--sourced' being used now to control the same
" setting (but reversed). The following handling allows configurations to
" continue working if 'startuptime_self' was specified.
let g:startuptime_self = get(g:, 'startuptime_self', 0)
let g:startuptime_sourced = get(g:, 'startuptime_sourced', !g:startuptime_self)

let g:startuptime_startup_indent =
      \ get(g:, 'startuptime_startup_indent', 7)
let g:startuptime_event_width =
      \ get(g:, 'startuptime_event_width', 20)
let g:startuptime_time_width =
      \ get(g:, 'startuptime_time_width', 6)
let g:startuptime_percent_width =
      \ get(g:, 'startuptime_percent_width', 7)
let g:startuptime_plot_width =
      \ get(g:, 'startuptime_plot_width', 26)

let g:startuptime_colorize =
      \ get(g:, 'startuptime_colorize', 1)

let s:use_blocks = has('multi_byte') && &g:encoding ==# 'utf-8'
let g:startuptime_use_blocks =
      \ get(g:, 'startuptime_use_blocks', s:use_blocks)
" The built-in Windows terminal emulator (used for CMD, Powershell, and WSL)
" does not properly display some block characters (i.e., the 1/8 precision
" blocks) using the default font, Consolas. The characters display properly on
" Cygwin using its default font, Lucida Console, and also when using Consolas.
let s:win_term = has('win32') || s:OnWsl()
let g:startuptime_fine_blocks =
      \ get(g:, 'startuptime_fine_blocks', !s:win_term)

let g:startuptime_zero_progress_msg =
      \ get(g:, 'startuptime_zero_progress_msg', 1)
let g:startuptime_zero_progress_time =
      \ get(g:, 'startuptime_zero_progress_time', 2000)

" The default highlight groups (for colors) are specified below.
" Change these default colors by defining or linking the corresponding
" highlight groups.
" E.g., the following will use the Title highlight for sourcing event text.
" :highlight link StartupTimeSourcingEvent Title
" E.g., the following will use custom highlight colors for event times.
" :highlight StartupTimeTime
"         \ term=bold ctermfg=12 ctermbg=159 guifg=Blue guibg=LightCyan
highlight default link StartupTimeStartupKey Normal
highlight default link StartupTimeStartupValue Title
highlight default link StartupTimeHeader ModeMsg
highlight default link StartupTimeSourcingEvent Type
highlight default link StartupTimeOtherEvent Identifier
highlight default link StartupTimeTime Directory
highlight default link StartupTimePercent Special
highlight default link StartupTimePlot Normal

let &cpo = s:save_cpo
unlet s:save_cpo
