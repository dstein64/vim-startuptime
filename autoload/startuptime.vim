
function! s:Contains(list, element)
  return index(a:list, a:element) !=# -1
endfunction

function! s:SetFile()
  try
    silent file [startuptime]
    return
  catch
  endtry
  let n = 1
  while 1
    try
      execute 'silent file [startuptime.' . n . ']'
    catch
      let n += 1
      continue
    endtry
    break
  endwhile
endfunction

"TODO: keep a buffer for reuse (so buffer list doesn't grow large)

"TODO: neovim support
function! s:ProfileVim(callback, tries, file)
  if a:tries ==# 0
    call a:callback()
    return
  endif
  let l:command = [
        \   exepath(v:progpath),
        \   '--startuptime', a:file,
        \ ]
  let l:exit_cb_env = {
        \   'callback': a:callback,
        \   'tries': a:tries,
        \   'file': a:file,
        \   'bufnr': 0
        \ }
  function l:exit_cb_env.exit_cb(job, status) dict
    execute self.bufnr . 'bdelete'
    call s:ProfileVim(self.callback, self.tries - 1, self.file)
  endfunction
  let l:options = {
        \   'exit_cb': l:exit_cb_env.exit_cb,
        \   'hidden': 1
        \ }
  let l:exit_cb_env.bufnr = term_start(l:command, l:options)
  " Send keys to exit instead of calling vim with '-c quit', as that approach
  " results in missing lines in the output.
  call term_sendkeys(l:exit_cb_env.bufnr, ":qall!\<cr>")
endfunction

" Returns a list of lists. The top-level lists correspond to different
" profiling sessions. The inner lists contain the parsed lines for each
" profiling session.
function! s:Parse(file)
  let l:result = []
  let l:lines = readfile(a:file)
  for l:line in l:lines
    if len(l:line) ==# 0 || l:line[0] !~# '^\d$'
      continue
    endif
    if l:line =~# ': --- VIM STARTING ---$'
      call add(l:result, [])
    endif
    let l:idx = stridx(l:line, ':')
    let l:times = split(l:line[:l:idx - 1], '\W\+')
    let l:text = l:line[l:idx + 2:]
    call add(l:result[-1], l:times + [l:text])
  endfor
  return l:result
endfunction

" Filters the parsed results from s:Parse(). Clock times from column 1 are
" dropped. For the sourced script entries, the 'self' argument specifies
" which time will be retained (self==1 retains the 'self' time and self==0
" retains the 'self+sourced' time.
function! s:Filter(parsed, self)
  let l:result = deepcopy(a:parsed)
  for l:list in l:result
    call remove(l:list, 0)
    if len(l:list) ==# 3
      " The boolean 'self' negated, as an int, coincidentally corresponds to
      " the column to remove.
      call remove(l:list, !self)
    endif
  endfor
  return l:result
endfunction

" Average the results of s:Filter().
function! s:Average(filtered)
  " TODO: make sure this is working properly

endfunction

" Load timing results from the specified file and show the results in the
" specified window. The file is deleted. The active window is retained.
function! startuptime#Main(file, winid, bufnr, options)
  let l:winid = win_getid()
  let l:eventignore = &eventignore
  set eventignore=all
  try
    if winbufnr(a:winid) !=# a:bufnr | return | endif
    call win_gotoid(a:winid)
    let l:parsed = s:Parse(a:file)
    let l:filtered = s:Filter(l:parsed, a:options.self)
    for l:item in l:filtered
      for l:item2 in l:item
        call append(line('$'), l:item2[-1])
      endfor
    endfor
    "call append(line('$') - 1, a:file)
    execute 'silent read ' . a:file

    "TODO: DELETE
    "call delete(a:file)
    setlocal nomodifiable
  finally
    call win_gotoid(l:winid)
    let &eventignore = l:eventignore
  endtry
endfunction

" Usage:
"   :StartupTime [--sort] [--all] [--self] [--tries INT]
function! startuptime#StartupTime(...)
  " TODO: implement this with a loop
  let l:options = {
        \   'sort': 0,
        \   'all': 0,
        \   'self': 0,
        \   'tries': 1
        \ }
  let l:options.sort = s:Contains(a:000, '--sort')
  let l:options.all = s:Contains(a:000, '--all')
  let l:options.self = s:Contains(a:000, '--self')
  try
    let l:_tries = str2nr(a:000[index(a:000, '--tries') + 1])
    if l:_tries ># l:options.tries
      l:options.tries = l:_tries
    endif
  catch
  endtry
  " TODO: account for vertical, and which side (i.e., bottomright instead of
  " topleft.
  silent topleft split enew
  " TODO: set syntax rules... Or maybe do that later...
  setlocal buftype=nofile noswapfile nofoldenable foldcolumn=0
  setlocal bufhidden=hide nobuflisted
  setlocal modifiable
  call s:SetFile()
  call append(line('$') - 1, 'vim-startuptime: Loading...')
  let l:file = tempname()
  let l:args = [l:file, win_getid(), bufnr(), l:options]
  let l:Callback = function('startuptime#Main', l:args)
  call s:ProfileVim(l:Callback, l:options.tries, l:file)
endfunction
