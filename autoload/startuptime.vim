
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

"TODO: neovim support
function! s:ProfileVim(callback, tries, file)
  if a:tries ==# 0
    call a:callback()
    return
  endif
  let l:command = [
        \   exepath(v:progpath),
        \   '--startuptime', a:file,
        \   '-c', 'qall!'
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
endfunction

" Load timing results from the specified, and show the results in the
" specified window. The file is deleted and the active window is retained.
function! startuptime#Main(file, winid, bufnr)
  let l:eventignore = &eventignore
  set eventignore=all
  try
    if winbufnr(a:winid) !=# a:bufnr | return | endif
    let l:winid = win_getid()
    call win_gotoid(a:winid)
    " Don't read. Parse.
    execute 'silent read ' . a:file
    call append(0, a:file)

    call delete(a:file)
    set nomodifiable
    call win_gotoid(l:winid)
  finally
    let &eventignore = l:eventignore
  endtry
endfunction

" Usage:
"   :StartupTime [--sort] [--all] [--self] [--tries INT]
function! startuptime#StartupTime(...)
  " TODO: implement this with a loop
  let l:sort = 0
  let l:all = 0
  let l:self = 0
  let l:tries = 1
  let l:sort = s:Contains(a:000, '--sort')
  let l:all = s:Contains(a:000, '--all')
  let l:self = s:Contains(a:000, '--self')
  let l:tries = 1
  try
    let l:_tries = str2nr(a:000[index(a:000, '--tries') + 1])
    let l:tries = max([l:tries, l:_tries])
  catch
  endtry
  " TODO: account for vertical, and which side (i.e., bottomright instead of
  " topleft.
  silent topleft split enew
  " TODO: set syntax rules... Or maybe do that later...
  set buftype=nofile noswapfile nofoldenable foldcolumn=0
  set bufhidden=hide
  set modifiable
  call s:SetFile()
  call append(0, 'vim-startuptime: Loading...')
  let l:file = tempname()
  let l:args = [l:file, win_getid(), bufnr()]
  let l:Callback = function('startuptime#Main', l:args)
  call s:ProfileVim(l:Callback, l:tries, l:file)
endfunction
