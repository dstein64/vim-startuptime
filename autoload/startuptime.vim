
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
  "TODO: maybe indicate progress in the buffer
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

let s:sourced_script_type = 0
let s:other_lines_type = 1

" Returns a nested list. The top-level list entries correspond to different
" profiling sessions. The next level lists contain the parsed lines for each
" profiling session. Each line is represented with a dict.
function! s:Extract(file)
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
    let l:times = split(l:line[:l:idx - 1], '\s\+')
    let l:item = {
          \   'text': l:line[l:idx + 2:],
          \   'clock': str2float(l:times[0]),
          \   'type': s:other_lines_type
          \ }
    if len(l:times) ==# 3
      let l:item.type = s:sourced_script_type
      let l:item['self+sourced'] = str2float(l:times[1])
      let l:item.self = str2float(l:times[2])
    else
      let l:item.elapsed = str2float(l:times[1])
    endif
    call add(l:result[-1], l:item)
  endfor
  return l:result
endfunction

" Consolidates the data returned by s:Extract().
" - Clock times are dropped.
" - 'self+sourced' and 'self' times are dropped, with the specified time to
"   retain moved to 'elapsed'.
" - Elapsed times are averaged.
" - 'other lines' are dropped (unless 'all' is specified).
function! s:Consolidate(extracted, self, all)
  if len(a:extracted) ==# 0 | return [] | endif
  let l:extracted = deepcopy(a:extracted)
  let l:tries = len(a:extracted)
  for l:try in l:extracted
    for l:line in l:try
      unlet l:line.clock
      if l:line.type ==# s:sourced_script_type
        let l:line.elapsed = l:line[a:self ? 'self' : 'self+sourced']
        unlet l:line.self
        unlet l:line['self+sourced']
      endif
    endfor
  endfor
  let l:result = deepcopy(l:extracted[0])
  let l:keys = map(copy(l:result), 'v:val.text')
  for l:try in l:extracted[1:]
    let l:_keys = map(copy(l:try), 'v:val.text')
    if l:keys !=# l:_keys
      throw 'vim-startuptime: inconistent tries'
    endif
    for l:idx in range(len(l:try))
      let l:result[l:idx].elapsed += l:try[l:idx].elapsed
    endfor
  endfor
  for l:item in l:result
    let l:item.elapsed /= l:tries
  endfor
  return l:result
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
    let l:extracted = s:Extract(a:file)
    let l:items = s:Consolidate(l:extracted, a:options.self, a:options.all)
    for l:item in l:items
      call append(line('$'), l:item.text . ': ' . string(l:item.elapsed))
    endfor
    "call append(line('$') - 1, a:file)
    execute 'silent read ' . a:file

    "TODO: remove comment
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
  " TODO: throw error for unknown options
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
      let l:options.tries = l:_tries
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
