" Test various functionality of vim-startuptime.

" Test --hidden, --save, and --tries.
StartupTime --tries 3 --save save1 --hidden
augroup test
  autocmd!
  autocmd User StartupTimeSaved let autocmd = 1
augroup END
sleep 3
call assert_true(has_key(g:, 'save1'))
call assert_equal(['items', 'startup', 'types'], sort(copy(keys(g:save1))))
call assert_equal(v:t_float, type(g:save1.startup.mean))
call assert_equal({'sourcing': 0, 'other': 1}, g:save1.types)
call assert_true(len(g:save1.items) ># 1)
" TODO: TEST CONTENTS OF save1.items
call assert_true(has_key(g:, 'autocmd'))
call assert_equal(1, g:autocmd)
unlet autocmd
call assert_false(has_key(g:, 'autocmd'))
" When using --hidden, there should be no new window.
call assert_equal(1, winnr('$'))

" Test --save without --hidden.
StartupTime --save save2
augroup test
  autocmd!
  autocmd User StartupTimeSaved let autocmd = 1
augroup END
sleep 3
call assert_true(has_key(g:, 'save2'))
call assert_equal(['items', 'startup', 'types'], sort(copy(keys(g:save2))))
call assert_equal(v:t_float, type(g:save2.startup.mean))
call assert_equal({'sourcing': 0, 'other': 1}, g:save2.types)
call assert_true(len(g:save2.items) ># 1)
call assert_true(has_key(g:, 'autocmd'))
call assert_equal(1, g:autocmd)
unlet autocmd
call assert_false(has_key(g:, 'autocmd'))
" Without hidden there should be a new window.
call assert_equal(2, winnr('$'))
close
call assert_equal(1, winnr('$'))

" Test default call.
StartupTime
augroup test
  autocmd!
  autocmd User StartupTimeSaved let autocmd = 1
augroup END
sleep 3
" Without --save, no autocmd should execute.
call assert_false(has_key(g:, 'autocmd'))
" Without hidden there should be a new window.
call assert_equal(2, winnr('$'))
close
call assert_equal(1, winnr('$'))
