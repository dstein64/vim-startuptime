" Test various functionality of vim-startuptime.

" ###############################################
" # Test --hidden, --save, and --tries.
" ###############################################

augroup test
  autocmd!
  autocmd User StartupTimeSaved let autocmd = 1
augroup END
StartupTime --tries 3 --save save1 --hidden
sleep 3
call assert_true(has_key(g:, 'save1'))
call assert_equal(['items', 'startup', 'types'], sort(copy(keys(g:save1))))
call assert_equal(v:t_float, type(g:save1.startup.mean))
call assert_equal({'sourcing': 0, 'other': 1}, g:save1.types)
call assert_true(len(g:save1.items) ># 1)
for s:item in g:save1.items
  if s:item.type ==# g:save1.types['sourcing']
    call assert_equal(
          \ [
          \   'event',
          \   'finish',
          \   'occurrence',
          \   'self',
          \   'self+sourced',
          \   'start',
          \   'time',
          \   'tries',
          \   'type'
          \ ],
          \ sort(copy(keys(s:item))))
    call assert_equal(v:t_float, type(s:item['self+sourced'].mean))
    call assert_equal(v:t_float, type(s:item['self'].mean))
    call assert_false(isnan(s:item['self+sourced'].std))
    call assert_false(isnan(s:item['self'].std))
    call assert_equal(s:item['self+sourced'].mean, s:item['time'])
  elseif s:item.type ==# g:save1.types['other']
    call assert_equal(
          \ [
          \   'elapsed',
          \   'event',
          \   'finish',
          \   'occurrence',
          \   'start',
          \   'time',
          \   'tries',
          \   'type'
          \ ],
          \ sort(copy(keys(s:item))))
    call assert_equal(v:t_float, type(s:item['elapsed'].mean))
    call assert_false(isnan(s:item['elapsed'].std))
    call assert_equal(s:item['elapsed'].mean, s:item['time'])
  else
    throw 'vim-startuptime: unknown type'
  endif
  call assert_equal(v:t_float, type(s:item['finish'].mean))
  call assert_equal(v:t_float, type(s:item['start'].mean))
  call assert_false(isnan(s:item['finish'].std))
  call assert_false(isnan(s:item['start'].std))
  call assert_equal(v:t_number, type(s:item['occurrence']))
  call assert_equal(v:t_string, type(s:item['event']))
  call assert_equal(3, s:item.tries)
endfor
unlet g:save1
call assert_true(has_key(g:, 'autocmd'))
call assert_equal(1, g:autocmd)
unlet autocmd
call assert_false(has_key(g:, 'autocmd'))
" When using --hidden, there should be no new window.
call assert_equal(1, winnr('$'))
" Test for failure with --tries 0.
let s:failed = v:false
try
  StartupTime --tries 0 --hidden
  sleep 3
catch
  let s:failed = v:true
endtry
call assert_true(s:failed)

" ###############################################
" # Test --save without --hidden.
" ###############################################

augroup test
  autocmd!
  autocmd User StartupTimeSaved let autocmd = 1
augroup END
StartupTime --save save2
sleep 3
call assert_true(has_key(g:, 'save2'))
call assert_equal(['items', 'startup', 'types'], sort(copy(keys(g:save2))))
call assert_equal(v:t_float, type(g:save2.startup.mean))
call assert_equal({'sourcing': 0, 'other': 1}, g:save2.types)
call assert_true(len(g:save2.items) ># 1)
for s:item in g:save2.items
  if s:item.type ==# g:save2.types['sourcing']
    call assert_equal(
          \ ['event', 'finish', 'occurrence', 'self', 'self+sourced', 'start', 'time', 'tries', 'type'],
          \ sort(copy(keys(s:item))))
    call assert_equal(v:t_float, type(s:item['self+sourced'].mean))
    call assert_equal(v:t_float, type(s:item['self'].mean))
    call assert_true(isnan(s:item['self+sourced'].std))
    call assert_true(isnan(s:item['self'].std))
    call assert_equal(s:item['self+sourced'].mean, s:item['time'])
  elseif s:item.type ==# g:save2.types['other']
    call assert_equal(
          \ ['elapsed', 'event', 'finish', 'occurrence', 'start', 'time', 'tries', 'type'],
          \ sort(copy(keys(s:item))))
    call assert_equal(v:t_float, type(s:item['elapsed'].mean))
    call assert_true(isnan(s:item['elapsed'].std))
    call assert_equal(s:item['elapsed'].mean, s:item['time'])
  else
    throw 'vim-startuptime: unknown type'
  endif
  call assert_equal(v:t_float, type(s:item['finish'].mean))
  call assert_equal(v:t_float, type(s:item['start'].mean))
  call assert_true(isnan(s:item['finish'].std))
  call assert_true(isnan(s:item['start'].std))
  call assert_equal(v:t_number, type(s:item['occurrence']))
  call assert_equal(v:t_string, type(s:item['event']))
  call assert_equal(1, s:item.tries)
endfor
unlet g:save2
call assert_true(has_key(g:, 'autocmd'))
call assert_equal(1, g:autocmd)
unlet autocmd
call assert_false(has_key(g:, 'autocmd'))
" Without hidden there should be a new window.
call assert_equal(2, winnr('$'))
close
call assert_equal(1, winnr('$'))

" ###############################################
" # Test default call.
" ###############################################

augroup test
  autocmd!
  autocmd User StartupTimeSaved let autocmd = 1
augroup END
StartupTime
sleep 3
" Without --save, no autocmd should execute.
call assert_false(has_key(g:, 'autocmd'))
" Without hidden there should be a new window.
call assert_equal(2, winnr('$'))
close
call assert_equal(1, winnr('$'))

" ###############################################
" # Ensure 'opening buffers' event.
" ###############################################

" We depend on the presence of 'opening buffers' in lua/startuptime.lua::remove_tui_sessions.

StartupTime --hidden --save save3
sleep 3
call assert_true(has_key(g:, 'save3'))
let s:has_opening_buffers = v:false
for s:item in g:save3.items
  if s:item.event ==# 'opening buffers'
    let s:has_opening_buffers = v:false
    break
  endif
endfor
call assert_false(s:has_opening_buffers)

" ###############################################
" # Test --input-file.
" ###############################################

" Convert all NaNs to the specified value.
function! s:ConvertNan(x, replacement) abort
  let l:type = type(a:x)
  if l:type ==# v:t_dict
    let l:dict = {}
    for l:key in keys(a:x)
      let l:dict[l:key] = s:ConvertNan(a:x[l:key], a:replacement)
    endfor
    return l:dict
  elseif l:type == v:t_list
    let l:list = []
    for l:item in a:x
      call add(l:list, s:ConvertNan(l:item, a:replacement))
    endfor
    return l:list
  elseif isnan(a:x)
    return a:replacement
  else
    return a:x
  endif
endfunction

" Generate a file to pass to --input-file.
" XXX: A more thorough approach for using --startuptime is used in s:Profile
" in autoload/startuptime.vim, to retain all events.
let s:file = tempname()
let s:exepath = exepath(v:progpath)
silent execute '!' . s:exepath . ' --startuptime ' . s:file . ' +qall\!'

try
  execute 'StartupTime --save save4 --input-file ' . s:file
  sleep 3
  execute 'StartupTime --save save5 --input-file ' . s:file
  sleep 3
  call assert_true(has_key(g:, 'save4'))
  call assert_true(has_key(g:, 'save5'))
  call assert_false(empty(g:save4.items))
  " NaN doesn't compare as equal to NaN, so convert to -1.
  call assert_equal(s:ConvertNan(g:save4, -1), s:ConvertNan(g:save5, -1))
finally
  call delete(s:file)
endtry
