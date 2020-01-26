let s:sourced_script_type = 0
let s:other_lines_type = 1
" 's:tfields' contains the time fields.
let s:tfields = ['elapsed', 'self+sourced', 'self']
let s:col_widths = {
      \   'event': 22,
      \   'time': 7,
      \   'percent': 7,
      \   'plot': 26
      \ }
function! s:ColBounds()
  let l:result = {}
  let l:position = 1
  for l:col_name in ['event', 'time', 'percent', 'plot']
    let l:start = l:position
    let l:end = l:start + s:col_widths[l:col_name] - 1
    let l:result[l:col_name] = [l:start, l:end]
    let l:position = l:end + 2
  endfor
  return l:result
endfunction
let s:col_bounds = s:ColBounds()

function! s:Contains(list, element)
  return index(a:list, a:element) !=# -1
endfunction

function! s:Sum(numbers)
  let l:result = 0
  for l:number in a:numbers
    let l:result += l:number
  endfor
  return l:result
endfunction

" The built-in max() does not work with floats.
function! s:Max(numbers)
  if len(a:numbers) ==# 0
    throw 'vim-startuptime: cannot take max of empty list'
  endif
  let l:result = a:numbers[0]
  for l:number in a:numbers
    if l:number ># l:result
      let l:result = l:number
    endif
  endfor
  return l:result
endfunction

function! s:GetChar()
  try
    while 1
      let l:char = getchar()
      if v:mouse_win ># 0 | continue | endif
      if l:char ==# "\<CursorHold>" | continue | endif
      break
    endwhile
  catch
    " E.g., <c-c>
    let l:char = char2nr("\<esc>")
  endtry
  if type(l:char) ==# v:t_number
    let l:char = nr2char(l:char)
  endif
  return l:char
endfunction

" Takes a list of lists. Each sublist is comprised of a highlight group name
" and a corresponding string to echo.
function! s:Echo(echo_list)
  redraw
  for [l:hlgroup, l:string] in a:echo_list
    execute 'echohl ' . l:hlgroup | echon l:string
  endfor
  echohl None
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
          \   'event': l:line[l:idx + 2:],
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

" Consolidates the data returned by s:Extract(), by averaging times across
" tries.
function! s:Consolidate(extracted)
  if len(a:extracted) ==# 0 | return [] | endif
  let l:extracted = deepcopy(a:extracted)
  let l:tries = len(a:extracted)
  let l:result = deepcopy(l:extracted[0])
  let l:keys = map(copy(l:result), 'v:val.event')
  for l:try in l:extracted[1:]
    let l:_keys = map(copy(l:try), 'v:val.event')
    if l:keys !=# l:_keys
      throw 'vim-startuptime: inconistent tries'
    endif
    for l:idx in range(len(l:try))
      for l:tfield in s:tfields
        if has_key(l:result[l:idx], l:tfield)
          let l:result[l:idx][l:tfield] += l:try[l:idx][l:tfield]
        endif
      endfor
    endfor
  endfor
  for l:item in l:result
    for l:tfield in s:tfields
      if has_key(l:item, l:tfield)
        let l:item[l:tfield] = l:item[l:tfield] / l:tries
      endif
    endfor
  endfor
  return l:result
endfunction

function! startuptime#ShowMoreInfo()
  if line('.') ==# 1 | return | endif
  let l:item = b:item_map[line('.')]
  let l:info_lines = [
        \   'event: ' . l:item.event,
        \   'clock: ' . string(l:item.clock)
        \ ]
  for l:tfield in s:tfields
    if has_key(l:item, l:tfield)
      call add(l:info_lines, l:tfield . ': ' . string(l:item[l:tfield]))
    endif
  endfor
  let l:echo_list = []
  call add(l:echo_list, ['Title', "vim-startuptime\n"])
  call add(l:echo_list, ['None', join(l:info_lines, "\n")])
  call add(l:echo_list, ['Question', "\n[press any key to continue]"])
  call s:Echo(l:echo_list)
  call s:GetChar()
  redraw | echo ''
endfunction

function! s:RegisterMoreInfo(items)
  " 'b:item_map' maps line numbers to corresponding items.
  let b:item_map = {}
  for l:idx in range(len(a:items))
    " 'l:idx' is incremented by 2 since lines start at 1 and the first line is
    " a header.
    let b:item_map[l:idx + 2] = a:items[l:idx]
  endfor
  if g:startuptime_more_info_key_seq !=# ''
    execute 'nnoremap <buffer> <silent> ' . g:startuptime_more_info_key_seq
          \ ' :call startuptime#ShowMoreInfo()<cr>'
  endif
endfunction

" Constrains the specified pattern to the specified lines and columns. 'lines'
" and 'columns' are lists, comprised of either numbers, or lists representing
" boundaries. '$' can be used as the second element in a boundary list to
" represent the last line or column (this is not needed for the first element,
" since 1 can be used for the first line). Empty lists represent all lines or
" columns, as no constraints would be applied.
function! s:ConstrainPattern(pattern, lines, columns)
  let l:line_parts = []
  for l:line in a:lines
    if type(l:line) ==# v:t_list
      let l:gt = l:line[0] - 1
      let l:line_pattern = '\%>' . l:gt . 'l'
      if l:line[1] !=# '$'
        let l:lt = l:line[1] + 1
        let l:line_pattern = '\(' . l:line_pattern . '\%<' . l:lt . 'l' . '\)'
      endif
      call add(l:line_parts, l:line_pattern)
    elseif type(l:line) ==# v:t_number
      call add(l:line_parts, '\%' . l:line . 'l')
    else
      throw 'vim-startuptime: unsupported line type'
    endif
  endfor
  let l:col_parts = []
  for l:col in a:columns
    if type(l:col) ==# v:t_list
      let l:gt = l:col[0] - 1
      let l:col_pattern = '\%>' . l:gt . 'v'
      if l:col[1] !=# '$'
        let l:lt = l:col[1] + 1
        let l:col_pattern = '\(' . l:col_pattern . '\%<' . l:lt . 'v' . '\)'
      endif
      call add(l:col_parts, l:col_pattern)
    elseif type(l:col) ==# v:t_number
      call add(l:col_parts, '\%'. l:col . 'v')
    else
      throw 'vim-startuptime: unsupported column type'
    endif
  endfor
  let l:line_qualifier = join(l:line_parts, '\|')
  if len(l:line_parts) > 1
    let l:line_qualifier = '\(' . l:line_qualifier . '\)'
  endif
  let l:col_qualifier = join(l:col_parts, '\|')
  if len(l:col_parts) > 1
    let l:col_qualifier = '\(' . l:col_qualifier . '\)'
  endif
  let l:result = l:line_qualifier . l:col_qualifier . a:pattern
  return l:result
endfunction

function! s:Tabulate(data)
  let l:total = s:Sum(map(copy(a:data), 'v:val.time'))
  let l:max = s:Max(map(copy(a:data), 'v:val.time'))
  let l:line = printf('%-*S', s:col_widths.event, 'event')
  let l:line .= printf(' %*S', s:col_widths.time, 'time')
  let l:line .= printf(' %*S', s:col_widths.percent, 'percent')
  let l:line .= ' plot'
  call append(line('$') - 1, l:line)
  for l:datum in a:data
    " XXX: Truncated numbers are not properly rounded (e.g., 1234.5678 would
    " be truncated to 1234.56, as opposed to 1234.57).
    let l:event = l:datum.event[:s:col_widths.event - 1]
    let l:line = printf('%-*S', s:col_widths.event, l:event)
    let l:time = printf('%.3f', l:datum.time)[:s:col_widths.time - 1]
    let l:line .= printf(' %*S', s:col_widths.time, l:time)
    let l:percent = printf('%.2f', 100 * l:datum.time / l:total)
    let l:percent = l:percent[:s:col_widths.percent - 1]
    let l:line .= printf(' %*S', s:col_widths.percent, l:percent)
    " TODO: real plot
    let l:plot = repeat('*', float2nr(s:col_widths.plot * l:datum.time / l:max))
    if len(l:plot) ># 0
      let l:line .= printf(' %s', l:plot)
    endif
    call append(line('$') - 1, l:line)
  endfor
endfunction

function! s:Colorize()
  let l:header_pattern = s:ConstrainPattern('\S', [1], [])
  execute 'syntax match StartupTimeHeader ''' . l:header_pattern . ''''
  let l:time_pattern = s:ConstrainPattern('\S', [[2, '$']], [s:col_bounds.time])
  execute 'syntax match StartupTimeTime ''' . l:time_pattern . ''''
  let l:percent_pattern = s:ConstrainPattern(
        \ '\S', [[2, '$']], [s:col_bounds.percent])
  execute 'syntax match StartupTimePercent ''' . l:percent_pattern . ''''
  let l:plot_pattern = s:ConstrainPattern('\S', [[2, '$']], [s:col_bounds.plot])
  execute 'syntax match StartupTimePlot ''' . l:plot_pattern . ''''
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
    normal! ggdG
    let l:extracted = s:Extract(a:file)
    let l:items = s:Consolidate(l:extracted)
    if !a:options.all
      call filter(l:items, 'v:val.type !=# s:other_lines_type')
    endif
    call s:RegisterMoreInfo(l:items)
    let l:table_data = []
    for l:item in l:items
      let l:event = l:item.event
      if l:item.type ==# s:sourced_script_type
        let l:time = l:item[a:options.self ? 'self' : 'self+sourced']
        let l:event = substitute(l:event, '^sourcing ', '', '')
        let l:event = fnamemodify(l:event, ':t')
      elseif l:item.type ==# s:other_lines_type
        let l:time = l:item.elapsed
      else
        throw 'vim-startuptime: unknown type'
      endif
      let l:datum = {'event': l:event, 'time': l:time}
      call add(l:table_data, l:datum)
    endfor
    call s:Tabulate(l:table_data)
    call s:Colorize()
    normal! Gddgg
    call delete(a:file)
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
  " TODO: require --tries=20 instead of '--tries 20'
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
  setlocal buftype=nofile noswapfile nofoldenable foldcolumn=0
  setlocal bufhidden=wipe nobuflisted
  setlocal nowrap
  setlocal modifiable
  call s:SetFile()
  call append(line('$') - 1, 'vim-startuptime: running... (please wait)')
  let l:file = tempname()
  let l:args = [l:file, win_getid(), bufnr('%'), l:options]
  let l:Callback = function('startuptime#Main', l:args)
  call s:ProfileVim(l:Callback, l:options.tries, l:file)
endfunction
