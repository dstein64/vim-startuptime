" *************************************************
" * Globals
" *************************************************

let s:event_types = {
      \   'sourcing': 0,
      \   'other': 1,
      \ }

let s:nvim_lua = has('nvim-0.4')
let s:vim9script = has('vim9script') && has('patch-8.2.4053')

" 's:tfields' contains the time fields.
let s:tfields = ['start', 'elapsed', 'self', 'self+sourced', 'finish']
" Expose tfields through a function for use in the test script.
function! s:TFields() abort
  return s:tfields
endfunction

let s:col_names = ['event', 'time', 'percent', 'plot']

" The number of lines prior to the event data (e.g., startup line, header
" line).
let s:preamble_line_count = 2

let s:startuptime_startup_key = 'startup:'

" *************************************************
" * Utils
" *************************************************

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
endfunction

function! s:Sum(numbers) abort
  let l:result = 0
  for l:number in a:numbers
    let l:result += l:number
  endfor
  return l:result
endfunction

" The built-in max() does not work with floats.
function! s:Max(numbers) abort
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

" The built-in min() does not work with floats.
function! s:Min(numbers) abort
  if len(a:numbers) ==# 0
    throw 'vim-startuptime: cannot take min of empty list'
  endif
  let l:result = a:numbers[0]
  for l:number in a:numbers
    if l:number <# l:result
      let l:result = l:number
    endif
  endfor
  return l:result
endfunction

function! s:Mean(numbers) abort
  if len(a:numbers) ==# 0
    throw 'vim-startuptime: cannot take mean of empty list'
  endif
  let l:result = 0.0
  for l:number in a:numbers
    let l:result += l:number
  endfor
  let l:result = l:result / len(a:numbers)
  return l:result
endfunction

" Calculate standard deviation using `ddof` delta degrees of freedom,
" optionally taking the mean to avoid redundant computation.
function! s:StandardDeviation(numbers, ddof, ...) abort
  let l:mean = a:0 ># 0 ? a:1 : s:Mean(a:numbers)
  let l:result = 0.0
  for l:number in a:numbers
    let l:diff = l:mean - l:number
    let l:result += l:diff * l:diff
  endfor
  let l:result = l:result / (len(a:numbers) - a:ddof)
  let l:result = sqrt(l:result)
  return l:result
endfunction

function! s:GetChar() abort
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
function! s:Echo(echo_list) abort
  redraw
  for [l:hlgroup, l:string] in a:echo_list
    execute 'echohl ' . l:hlgroup | echon l:string
  endfor
  echohl None
endfunction

function! s:Surround(inner, outer) abort
  return a:outer . a:inner . a:outer
endfunction

function! s:ClearCurrentBuffer() abort
  " Use silent to prevent --No lines in buffer-- message.
  silent %delete _
endfunction

function! s:SetBufLine(bufnr, line, text) abort
  let l:modifiable = getbufvar(a:bufnr, '&modifiable')
  call setbufvar(a:bufnr, '&modifiable', 1)
  " setbufline was added to Neovim in commit 9485061. Use nvim_buf_set_lines
  " to support older versions.
  if has('nvim')
    call nvim_buf_set_lines(a:bufnr, a:line - 1, a:line, 0, [a:text])
  else
    call setbufline(a:bufnr, a:line, a:text)
  endif
  call setbufvar(a:bufnr, '&modifiable', l:modifiable)
endfunction

" Return plus/minus character for supported environments, or '+/-' otherwise.
function! s:PlusMinus() abort
  let l:plus_minus = '+/-'
  if has('multi_byte') && &encoding ==# 'utf-8'
    let l:plus_minus = nr2char(177)
  endif
  return l:plus_minus
endfunction

function! s:NumberToFloat(number) abort
  return a:number + 0.0
endfunction

" *************************************************
" * Core
" *************************************************

function! s:SetFile() abort
  let l:isfname = &isfname
  " On Windows, to escape '[' with a backslash below, the character has to be
  " removed from 'isfname' (:help wildcard).
  set isfname-=[
  " Prepend backslash to the prefix to avoid the special wildcard meaning
  " (:help wildcard). Two backslashes are necessary on Windows, since Vim
  " removes backslashes before special characters (:help dos-backslash).
  " Issue #9.
  let l:prefix = has('win32') ? '\\[' : '\['
  let l:suffix = ']'
  let l:n = 0
  while 1
    try
      let l:text = 'startuptime'
      if l:n ># 0
        let l:text .= '.' . l:n
      endif
      execute 'silent file ' . l:prefix . l:text . l:suffix
    catch
      let l:n += 1
      continue
    endtry
    break
  endwhile
  let &isfname = l:isfname
endfunction

function! s:IsRequireEvent(event) abort
  return a:event =~# "require('.*')"
endfunction

" E.g., convert "require('vim.filetype')" to "vim.filetype"
function! s:ExtractRequireArg(event) abort
  return a:event[9:-3]
endfunction

function! s:SimplifiedEvent(item) abort
  let l:event = a:item.event
  if a:item.type ==# s:event_types['sourcing']
    if s:IsRequireEvent(l:event)
      let l:event = s:ExtractRequireArg(l:event)
    else
      let l:event = substitute(l:event, '^sourcing ', '', '')
      let l:event = fnamemodify(l:event, ':t')
    endif
  endif
  return l:event
endfunction

function! s:ProfileCmd(file) abort
  " * If timer_start() is available, vim is quit with a timer. This retains
  "   all events up to the last event, '--- VIM STARTED ---'.
  " * XXX: If timer_start() is not available, an autocmd is used. This retains
  "   all events up to 'executing command arguments', which excludes:
  "   - 'VimEnter autocommands'
  "   - 'before starting main loop'
  "   - 'first screen update'
  "   - '--- VIM STARTED ---'
  "   This approach works because the 'executing command arguments' event is
  "   before the 'VimEnter autocommands' event.
  " * These are used in place of 'qall!' alone, which excludes the same events
  "   as the autocmd approach, in addition to the 'executing command
  "   arguments' event. 'qall!' alone can also seemingly trigger additional
  "   autoload sourcing events (possibly from autocmds registered to Vim's
  "   exit events (i.e., QuitPre, ExitPre, VimLeavePre, VimLeave).
  " * A -c command is used for quitting, as opposed to sending keys. The
  "   latter approach would retain all events, but does not work for some
  "   environments (e.g., gVim on Windows).
  let l:quit_cmd_timer = 'call timer_start(0, {-> execute(''qall!'')})'
  let l:quit_cmd_autocmd = 'autocmd VimEnter * qall!'
  let l:quit_cmd = printf(
        \ 'if exists(''*timer_start'') | %s | else | %s | endif',
        \ l:quit_cmd_timer,
        \ l:quit_cmd_autocmd)
  let l:command = [
        \   g:startuptime_exe_path,
        \   '--startuptime', a:file,
        \   '-c', l:quit_cmd
        \ ]
  call extend(l:command, g:startuptime_exe_args)
  return l:command
endfunction

function! s:Profile(onfinish, onprogress, options, tries, file, items) abort
  if !a:onprogress(a:tries)
    return
  endif
  " Extract data when it's available (i.e., after the first call to Profile).
  if a:tries <# a:options.tries
    while 1
      try
        let l:items = s:Extract(a:file, a:options)
        break
      catch /^Vim:Interrupt$/
        " Ignore interrupts. The loop will result in re-attempting to extract.
        " The plugin can be interrupted by closing the window.
      endtry
    endwhile
    call extend(a:items, l:items)
    call delete(a:file)
  endif
  if a:tries ==# 0
    call a:onfinish()
    return
  endif
  let l:command = s:ProfileCmd(a:file)
  " The 'tmp' dict is used so a local function can be created.
  let l:tmp = {}
  let l:args = [a:onfinish, a:onprogress, a:options, a:tries - 1, a:file, a:items]
  let l:env = {'args': args}
  if has('nvim')
    function l:tmp.exit(job, status, type) dict
      call function('s:Profile', self.args)()
    endfunction
    let l:jobstart_options = {
          \   'pty': 1,
          \   'on_exit': function(l:tmp.exit, l:env)
          \ }
    let l:env.jobnr = jobstart(l:command, l:jobstart_options)
  else
    function l:tmp.exit(job, status) dict
      execute self.bufnr . 'bdelete'
      call function('s:Profile', self.args)()
    endfunction
    let l:term_start_options = {
          \   'exit_cb': function(l:tmp.exit, l:env),
          \   'hidden': 1
          \ }
    " XXX: A new buffer is created each time this is run. Running many times
    " will result in large buffer numbers.
    let l:env.bufnr = term_start(l:command, l:term_start_options)
  endif
endfunction

function! s:ExtractLua(file, options) abort
  let l:args = [
        \   a:file,
        \   a:options,
        \   s:event_types,
        \ ]
  let l:result = luaeval('require("startuptime").extract(unpack(_A))', l:args)
  " Convert numbers to floats where applicable.
  for l:session in l:result
    for l:item in l:session
      for l:tfield in s:tfields
        if has_key(l:item, l:tfield)
          let l:item[l:tfield] = s:NumberToFloat(l:item[l:tfield])
        endif
      endfor
    endfor
  endfor
  return l:result
endfunction

function! s:ExtractVim9(file, options) abort
  return startuptime9#Extract(a:file, a:options, s:event_types)
endfunction

function! s:ExtractVimScript(file, options) abort
  let l:result = []
  let l:lines = readfile(a:file)
  for l:line in l:lines
    if strchars(l:line) ==# 0 || l:line[0] !~# '^\d$'
      continue
    endif
    if l:line =~# ': --- N\=VIM STARTING ---$'
      call add(l:result, [])
      let l:occurrences = {}
    endif
    let l:idx = stridx(l:line, ':')
    let l:times = split(l:line[:l:idx - 1], '\s\+')
    let l:event = l:line[l:idx + 2:]
    let l:type = s:event_types['other']
    if len(l:times) ==# 3
      let l:type = s:event_types['sourcing']
    endif
    let l:key = l:type . '-' . l:event
    if has_key(l:occurrences, l:key)
      let l:occurrences[l:key] += 1
    else
      let l:occurrences[l:key] = 1
    endif
    " 'finish' time is reported as 'clock' in --startuptime output.
    let l:item = {
          \   'event': l:event,
          \   'occurrence': l:occurrences[l:key],
          \   'finish': str2float(l:times[0]),
          \   'type': l:type
          \ }
    if l:type ==# s:event_types['sourcing']
      let l:item['self+sourced'] = str2float(l:times[1])
      let l:item.self = str2float(l:times[2])
      let l:item.start = l:item.finish - l:item['self+sourced']
    else
      let l:item.elapsed = str2float(l:times[1])
      let l:item.start = l:item.finish - l:item.elapsed
    endif
    let l:types = []
    if a:options.sourcing_events
      call add(l:types, s:event_types['sourcing'])
    endif
    if a:options.other_events
      call add(l:types, s:event_types['other'])
    endif
    if s:Contains(l:types, l:item.type)
      call add(l:result[-1], l:item)
    endif
  endfor
  return l:result
endfunction

" Returns a nested list. The top-level list entries correspond to different
" profiling sessions. The next level lists contain the parsed lines for each
" profiling session. Each line is represented with a dict.
function! s:Extract(file, options) abort
  " For improved speed, a Lua function is used for Neovim and a Vim9 function
  " for Vim, when available.
  if s:nvim_lua
    return s:ExtractLua(a:file, a:options)
  elseif s:vim9script
    return s:ExtractVim9(a:file, a:options)
  else
    return s:ExtractVimScript(a:file, a:options)
  endif
endfunction

" Returns the average startup time of the data returned by s:Extract().
function! s:Startup(items) abort
  let l:times = []
  for l:item in a:items
    let l:last = l:item[-1]
    let l:lookup = {
          \   s:event_types['sourcing']: 'self+sourced',
          \   s:event_types['other']: 'elapsed'
          \ }
    let l:key = l:lookup[l:last.type]
    call add(l:times, l:last.finish)
  endfor
  let l:mean = s:Mean(l:times)
  let l:std = s:StandardDeviation(l:times, 1, l:mean)
  let l:output = {'mean': l:mean, 'std': l:std}
  return l:output
endfunction

function! s:ConsolidateLua(items) abort
  let l:args = [a:items, s:tfields]
  let l:result = luaeval(
        \ 'require("startuptime").consolidate(unpack(_A))', l:args)
  " Convert numbers to floats where applicable.
  for l:item in l:result
    for l:metric in ['std', 'mean']
      for l:tfield in s:tfields
        if has_key(l:item, l:tfield)
          let l:item[l:tfield][l:metric] =
                \ s:NumberToFloat(l:item[l:tfield][l:metric])
        endif
      endfor
    endfor
  endfor
  return l:result
endfunction

function! s:ConsolidateVim9(items) abort
  return startuptime9#Consolidate(a:items, s:tfields)
endfunction

function! s:ConsolidateVimScript(items) abort
  let l:lookup = {}
  for l:try in a:items
    for l:item in l:try
      let l:key = l:item.type . '-' . l:item.occurrence . '-' . l:item.event
      if has_key(l:lookup, l:key)
        for l:tfield in s:tfields
          if has_key(l:item, l:tfield)
            call add(l:lookup[l:key][l:tfield], l:item[l:tfield])
          endif
        endfor
        let l:lookup[l:key].tries += 1
      else
        let l:lookup[l:key] = deepcopy(l:item)
        for l:tfield in s:tfields
          if has_key(l:lookup[l:key], l:tfield)
            " Put item in a list.
            let l:lookup[l:key][l:tfield] = [l:lookup[l:key][l:tfield]]
          endif
        endfor
        let l:lookup[l:key].tries = 1
      endif
    endfor
  endfor
  let l:result = values(l:lookup)
  for l:item in l:result
    for l:tfield in s:tfields
      if has_key(l:item, l:tfield)
        let l:mean = s:Mean(l:item[l:tfield])
        " Use 1 for ddof, for sample standard deviation.
        let l:std = s:StandardDeviation(l:item[l:tfield], 1, l:mean)
        let l:item[l:tfield] = {'mean': l:mean, 'std': l:std}
      endif
    endfor
  endfor
  " Sort on mean start time, event name, then occurrence.
  let l:Compare = {i1, i2 ->
        \ i1.start.mean !=# i2.start.mean
        \ ? (i1.start.mean <# i2.start.mean ? -1 : 1)
        \ : (i1.event !=# i2.event
        \    ? (i1.event <# i2.event ? -1 : 1)
        \    : (i1.occurrence !=# i2.occurrence
        \       ? (i1.occurrence <# i2.occurrence ? -1 : 1)
        \       : 0))}
  call sort(l:result, l:Compare)
  return l:result
endfunction

" Consolidates the data returned by s:Extract(), by averaging times across
" tries. Adds a new field, 'tries', indicating how many tries were conducted
" for each event (this can be smaller than specified by --tries).
function! s:Consolidate(items) abort
  " For improved speed, a Lua function is used for Neovim and a Vim9 function
  " for Vim, when available.
  if s:nvim_lua
    return s:ConsolidateLua(a:items)
  elseif s:vim9script
    return s:ConsolidateVim9(a:items)
  else
    return s:ConsolidateVimScript(a:items)
  endif
endfunction

" Adds a time field to the data returned by s:Consolidate.
function! s:Augment(items, options) abort
  let l:result = deepcopy(a:items)
  for l:item in l:result
    if l:item.type ==# s:event_types['sourcing']
      let l:key = a:options.sourced ? 'self+sourced' : 'self'
    elseif l:item.type ==# s:event_types['other']
      let l:key = 'elapsed'
    else
      throw 'vim-startuptime: unknown type'
    endif
    let l:item.time = l:item[l:key].mean
  endfor
  return l:result
endfunction

function! startuptime#ShowMoreInfo() abort
  let l:cmdheight = &cmdheight
  let l:laststatus = &laststatus
  if l:cmdheight ==# 0
    " Neovim supports cmdheight=0. When used, temporarily change to 1 to avoid
    " 'Press ENTER or type command to continue' after showing more info.
    set cmdheight=1
  endif
  " Make sure the last window has a status line, to serve as a divider between
  " the info message and the last window.
  if has('nvim') && l:laststatus ==# 3
    " Keep the existing value
  else
    set laststatus=2
  endif
  try
    let l:line = line('.')
    let l:info_lines = []
    if l:line <=# s:preamble_line_count
      call add(l:info_lines,
            \ '- You''ve queried for additional information.')
      let l:startup = printf('%.2f', b:startuptime_startup.mean)
      if b:startuptime_options.tries ># 1
        let l:startup .= printf(
              \ ' %s %.2f', s:PlusMinus(), b:startuptime_startup.std)
        call extend(l:info_lines, [
              \   '- The startup time is ' . l:startup . ' milliseconds, an',
              \   '  average plus/minus sample standard deviation.'
              \ ])
      else
        call add(l:info_lines,
              \ '- The startup time is ' . l:startup . ' milliseconds.')
      endif
      call add(l:info_lines,
            \ '- More specific information is available for event lines.')
    elseif !has_key(b:startuptime_item_map, l:line)
      throw 'vim-startuptime: error getting more info'
    else
      let l:item = b:startuptime_item_map[l:line]
      call add(l:info_lines, 'event: ' . l:item.event)
      let l:occurrences = b:startuptime_occurrences[l:item.event]
      if l:occurrences ># 1
        call add(
              \ l:info_lines,
              \ 'occurrence: ' . l:item.occurrence . ' of ' . l:occurrences)
      endif
      for l:tfield in s:tfields
        if has_key(l:item, l:tfield)
          let l:info = printf('%s: %.3f', l:tfield, l:item[l:tfield].mean)
          if l:item.tries ># 1
            let l:plus_minus = s:PlusMinus()
            let l:info .= printf(' %s %.3f', l:plus_minus, l:item[l:tfield].std)
          endif
          call add(l:info_lines, l:info)
        endif
      endfor
      if b:startuptime_options.tries ># 1
        call add(l:info_lines, 'tries: ' . l:item.tries)
      endif
      call add(l:info_lines, '* times are in milliseconds')
      if l:item.tries ># 1
        call add(
              \ l:info_lines,
              \ '* times are averages plus/minus sample standard deviation')
      endif
    endif
    let l:echo_list = []
    call add(l:echo_list, ['Title', "vim-startuptime\n"])
    call add(l:echo_list, ['None', join(l:info_lines, "\n")])
    call add(l:echo_list, ['Question', "\n[press any key to continue]"])
    call s:Echo(l:echo_list)
    call s:GetChar()
    redraw | echo ''
  finally
    let &laststatus = l:laststatus
    let &cmdheight = l:cmdheight
  endtry
endfunction

function! startuptime#GotoFile() abort
  let l:line = line('.')
  let l:nofile = 'line'
  if l:line ==# 1
    let l:nofile = 'startup line'
  elseif l:line ==# 2
    let l:nofile = 'header'
  elseif has_key(b:startuptime_item_map, l:line)
    let l:item = b:startuptime_item_map[l:line]
    if l:item.type ==# s:event_types['sourcing']
      let l:file = ''
      if s:IsRequireEvent(l:item.event)
        " Attempt to deduce the file path.
        let l:arg = s:ExtractRequireArg(l:item.event)
        let l:part = substitute(l:arg, '\.', '/', 'g')
        for l:base in globpath(&runtimepath, '', 1, 1)
          let l:candidates = [
                \   l:base .. 'lua/' .. l:part .. '.lua',
                \   l:base .. 'lua/' .. l:part .. '/init.lua'
                \ ]
          for l:candidate in l:candidates
            if filereadable(l:candidate)
              let l:file = l:candidate
              break
            endif
          endfor
          if !empty(l:file) | break | endif
        endfor
      elseif l:item.event =~# '^sourcing '
        let l:file = substitute(l:item.event, '^sourcing ', '', '')
      endif
      if !empty(l:file)
        execute 'aboveleft split ' . l:file
        return
      endif
    endif
    let l:nofile = l:item.event
    let l:surround = ''
    if stridx(l:nofile, "'") ==# -1
      let l:surround = "'"
    elseif stridx(l:nofile, '"') ==# -1
      let l:surround = '"'
    endif
    if !empty(l:surround)
      let l:nofile = s:Surround(l:item.event, l:surround)
    endif
  endif
  let l:message = 'vim-startuptime: no file for ' . l:nofile
  call s:Echo([['WarningMsg', l:message]])
endfunction

function! s:RegisterMaps(items, options, startup) abort
  " 'b:startuptime_item_map' maps line numbers to corresponding items.
  let b:startuptime_item_map = {}
  " 'b:startuptime_occurrences' maps events to the number of times it
  " occurred.
  let b:startuptime_occurrences = {}
  let b:startuptime_startup = deepcopy(a:startup)
  let b:startuptime_options = deepcopy(a:options)
  for l:idx in range(len(a:items))
    let l:item = a:items[l:idx]
    " 'l:idx' is incremented to accommodate lines starting at 1 and the
    " preamble lines prior to the table's data.
    let b:startuptime_item_map[l:idx + 1 + s:preamble_line_count] = l:item
    if l:item.occurrence ># get(b:startuptime_occurrences, l:item.event, 0)
      let b:startuptime_occurrences[l:item.event] = l:item.occurrence
    endif
  endfor
  if g:startuptime_more_info_key_seq !=# ''
    execute 'nnoremap <buffer> <nowait> <silent> '
          \ . g:startuptime_more_info_key_seq
          \ . ' :call startuptime#ShowMoreInfo()<cr>'
  endif
  if g:startuptime_split_edit_key_seq !=# ''
    execute 'nnoremap <buffer> <nowait> <silent> '
          \ . g:startuptime_split_edit_key_seq
          \ . ' :call startuptime#GotoFile()<cr>'
  endif
endfunction

" Constrains the specified pattern to the specified lines and columns. 'lines'
" and 'columns' are lists, comprised of either numbers, or lists representing
" boundaries. '$' can be used as the second element in a boundary list to
" represent the last line or column (this is not needed for the first element,
" since 1 can be used for the first line). Use ['*'] for 'lines' or 'columns'
" to represent all lines or columns. An empty list for 'lines' or 'columns'
" will return a pattern that never matches.
function! s:ConstrainPattern(pattern, lines, columns) abort
  " The 0th line will never match (when no lines specified)
  let l:line_parts = len(a:lines) ># 0 ? [] : ['\%0l']
  for l:line in a:lines
    if type(l:line) ==# v:t_list
      let l:gt = l:line[0] - 1
      let l:line_pattern = '\%>' . l:gt . 'l'
      if l:line[1] !=# '$'
        let l:lt = l:line[1] + 1
        let l:line_pattern = '\%(' . l:line_pattern . '\%<' . l:lt . 'l' . '\)'
      endif
      call add(l:line_parts, l:line_pattern)
    elseif type(l:line) ==# v:t_number
      call add(l:line_parts, '\%' . l:line . 'l')
    elseif type(l:line) ==# v:t_string && l:line ==# '*'
      continue
    else
      throw 'vim-startuptime: unsupported line type'
    endif
  endfor
  " The 0th column will never match (when no lines specified)
  let l:col_parts = len(a:columns) ># 0 ? [] : ['\%0v']
  for l:col in a:columns
    if type(l:col) ==# v:t_list
      let l:gt = l:col[0] - 1
      let l:col_pattern = '\%>' . l:gt . 'v'
      if l:col[1] !=# '$'
        let l:lt = l:col[1] + 1
        let l:col_pattern = '\%(' . l:col_pattern . '\%<' . l:lt . 'v' . '\)'
      endif
      call add(l:col_parts, l:col_pattern)
    elseif type(l:col) ==# v:t_number
      call add(l:col_parts, '\%'. l:col . 'v')
    elseif type(l:col) ==# v:t_string && l:col ==# '*'
      continue
    else
      throw 'vim-startuptime: unsupported column type'
    endif
  endfor
  let l:line_qualifier = join(l:line_parts, '\|')
  if len(l:line_parts) > 1
    let l:line_qualifier = '\%(' . l:line_qualifier . '\)'
  endif
  let l:col_qualifier = join(l:col_parts, '\|')
  if len(l:col_parts) > 1
    let l:col_qualifier = '\%(' . l:col_qualifier . '\)'
  endif
  let l:result = l:line_qualifier . l:col_qualifier . a:pattern
  return l:result
endfunction

function! s:CreatePlotLine(size, max, width) abort
  if g:startuptime_use_blocks
    let l:block_chars = {
          \   1: nr2char(0x258F), 2: nr2char(0x258E),
          \   3: nr2char(0x258D), 4: nr2char(0x258C),
          \   5: nr2char(0x258B), 6: nr2char(0x258A),
          \   7: nr2char(0x2589), 8: nr2char(0x2588)
          \ }
    if !g:startuptime_fine_blocks
      let l:block_chars[1] = ''
      let l:block_chars[2] = ''
      let l:block_chars[3] = l:block_chars[4]
      let l:block_chars[5] = l:block_chars[4]
      let l:block_chars[6] = l:block_chars[8]
      let l:block_chars[7] = l:block_chars[8]
    endif
    let l:width = 0.0 + a:width * a:size / a:max
    let l:plot = repeat(l:block_chars[8], float2nr(l:width))
    let l:remainder = s:Max([0.0, l:width - float2nr(l:width)])
    let l:eigths = s:Min([8, float2nr(round(l:remainder * 8.0))])
    if l:eigths ># 0
      let l:plot .= l:block_chars[l:eigths]
    endif
  else
    let l:plot = repeat('*', float2nr(round(a:width * a:size / a:max)))
  endif
  return l:plot
endfunction

function! s:ColBoundsLookup() abort
  let l:result = {}
  let l:position = 1
  for l:col_name in s:col_names
    let l:start = l:position
    let l:width = g:['startuptime_' . l:col_name . '_width']
    let l:end = l:start + l:width - 1
    let l:result[l:col_name] = [l:start, l:end]
    let l:position = l:end + 2
  endfor
  return l:result
endfunction

" Given a field (string), col_name, and alignment (1 for left, 0 for right),
" return the column boundaries of the field.
function! s:FieldBounds(field, col_name, left) abort
  let l:col_bounds_lookup = s:ColBoundsLookup()
  let l:col_bounds = l:col_bounds_lookup[a:col_name]
  if a:left
    let l:start = l:col_bounds[0]
    let l:field_bounds = [
          \   l:start,
          \   l:start + strchars(a:field) - 1
          \ ]
  else
    let l:end = l:col_bounds[1]
    let l:field_bounds = [
          \   l:end - strchars(a:field) + 1,
          \   l:end
          \ ]
  endif
  return l:field_bounds
endfunction

" Tabulate items and return each line's field boundaries in a
" multi-dimensional array.
function! s:Tabulate(items, startup) abort
  let l:output = []
  let l:startup_line = repeat(' ', g:startuptime_startup_indent)
  let l:startup_line .= s:startuptime_startup_key
  let l:startup_line .= printf(' %.1f', a:startup.mean)
  call setline(1, l:startup_line)
  let l:key_start = g:startuptime_startup_indent + 1
  let l:key_end = l:key_start + strdisplaywidth(s:startuptime_startup_key) - 1
  let l:value_start = l:key_end + 2
  let l:value_end = strdisplaywidth(l:startup_line)
  call add(l:output, [[l:key_start, l:key_end], [l:value_start, l:value_end]])
  let l:event = strcharpart('event', 0, g:startuptime_event_width)
  let l:line = printf('%-*S', g:startuptime_event_width, l:event)
  let l:time = strcharpart('time', 0, g:startuptime_time_width)
  let l:line .= printf(' %*S', g:startuptime_time_width, l:time)
  let l:percent = strcharpart('percent', 0, g:startuptime_percent_width)
  let l:line .= printf(' %*S', g:startuptime_percent_width, l:percent)
  let l:plot = strcharpart('plot', 0, g:startuptime_plot_width)
  let l:line .= ' ' . l:plot
  let l:field_bounds_list = [
        \   s:FieldBounds('event', 'event', 1),
        \   s:FieldBounds('time', 'time', 0),
        \   s:FieldBounds('percent', 'percent', 0),
        \   s:FieldBounds('plot', 'plot', 1),
        \ ]
  call add(l:output, l:field_bounds_list)
  call setline(2, l:line)
  if len(a:items) ==# 0 | return l:output | endif
  let l:max = s:Max(map(copy(a:items), 'v:val.time'))
  " WARN: Times won't necessarily sum to the reported startup time. This could
  " be due to some time being double counted. E.g., if --no-self is used,
  " self+sourced timings are used. These timings include time spent sourcing
  " other files, files which will have their own events and timings.
  for l:item in a:items
    let l:event = s:SimplifiedEvent(l:item)
    let l:event = strcharpart(l:event, 0, g:startuptime_event_width)
    let l:line = printf('%-*S', g:startuptime_event_width, l:event)
    let l:time = printf('%.2f', l:item.time)
    let l:time = strcharpart(l:time, 0, g:startuptime_time_width)
    let l:line .= printf(' %*S', g:startuptime_time_width, l:time)
    let l:percent = printf('%.2f', 100 * l:item.time / a:startup.mean)
    let l:percent = strcharpart(l:percent, 0, g:startuptime_percent_width)
    let l:line .= printf(' %*S', g:startuptime_percent_width, l:percent)
    let l:field_bounds_list = [
          \   s:FieldBounds(l:event, 'event', 1),
          \   s:FieldBounds(l:time, 'time', 0),
          \   s:FieldBounds(l:percent, 'percent', 0),
          \ ]
    let l:plot = s:CreatePlotLine(l:item.time, l:max, g:startuptime_plot_width)
    if strchars(l:plot) ># 0
      let l:line .= printf(' %s', l:plot)
      call add(l:field_bounds_list, s:FieldBounds(l:plot, 'plot', 1))
    endif
    call add(l:output, l:field_bounds_list)
    call setline(line('$') + 1, l:line)
  endfor
  normal! gg0
  return l:output
endfunction

" Converts a list of numbers into a list of numbers *and* ranges.
" For example:
"   > echo s:Rangify([1, 3, 4, 5, 9, 10, 12, 14, 15])
"     [1, [3, 5], [9, 10], 12, [14, 15]]
function! s:Rangify(list) abort
  if len(a:list) ==# 0 | return [] | endif
  let l:result = [[a:list[0], a:list[0]]]
  for l:x in a:list[1:]
    if l:x ==# l:result[-1][1] + 1
      let l:result[-1][1] = l:x
    else
      call add(l:result, [l:x, l:x])
    endif
  endfor
  for l:idx in range(len(l:result))
    if l:result[l:idx][0] ==# l:result[l:idx][1]
      let l:result[l:idx] = l:result[l:idx][0]
    endif
  endfor
  return l:result
endfunction

" Use syntax patterns to highlight text. Spaces within fields are not
" highlighted.
function! s:SyntaxColorize(event_types) abort
  let l:key_start = g:startuptime_startup_indent + 1
  let l:key_end = l:key_start + strdisplaywidth(s:startuptime_startup_key) - 1
  let l:startup_key_pattern = s:ConstrainPattern(
        \ '\S', [1], [[l:key_start, l:key_end]])
  execute 'syntax match StartupTimeStartupKey '
        \ . s:Surround(l:startup_key_pattern, "'")
  let l:startup_value_pattern = s:ConstrainPattern(
        \ '\S', [1], [[l:key_end + 2, '$']])
  execute 'syntax match StartupTimeStartupValue '
        \ . s:Surround(l:startup_value_pattern, "'")
  let l:header_pattern = s:ConstrainPattern('\S', [2], ['*'])
  execute 'syntax match StartupTimeHeader ' . s:Surround(l:header_pattern, "'")
  let l:line_lookup = {s:event_types['sourcing']: [], s:event_types['other']: []}
  for l:idx in range(len(a:event_types))
    let l:event_type = a:event_types[l:idx]
    " 'l:idx' is incremented to accommodate lines starting at 1 and the
    " preamble lines prior to the table's data.
    let l:line = l:idx + 1 + s:preamble_line_count
    call add(l:line_lookup[l:event_type], l:line)
  endfor
  let l:col_bounds_lookup = s:ColBoundsLookup()
  let l:sourcing_event_pattern = s:ConstrainPattern(
        \ '\S',
        \ s:Rangify(l:line_lookup[s:event_types['sourcing']]),
        \ [l:col_bounds_lookup.event])
  execute 'syntax match StartupTimeSourcingEvent '
        \ . s:Surround(l:sourcing_event_pattern, "'")
  let l:other_event_pattern = s:ConstrainPattern(
        \ '\S',
        \ s:Rangify(l:line_lookup[s:event_types['other']]),
        \ [l:col_bounds_lookup.event])
  execute 'syntax match StartupTimeOtherEvent '
        \ . s:Surround(l:other_event_pattern, "'")
  let l:first_event_line = s:preamble_line_count + 1
  let l:time_pattern = s:ConstrainPattern(
        \ '\S',
        \ [[l:first_event_line, '$']],
        \ [l:col_bounds_lookup.time])
  execute 'syntax match StartupTimeTime ' . s:Surround(l:time_pattern, "'")
  let l:percent_pattern = s:ConstrainPattern(
        \ '\S', [[l:first_event_line, '$']], [l:col_bounds_lookup.percent])
  execute 'syntax match StartupTimePercent ' . s:Surround(l:percent_pattern, "'")
  let l:plot_pattern = s:ConstrainPattern(
        \ '\S',
        \ [[l:first_event_line, '$']],
        \ [l:col_bounds_lookup.plot])
  execute 'syntax match StartupTimePlot ' . s:Surround(l:plot_pattern, "'")
endfunction

" Use Vim's text properties or Neovim's 'nvim_buf_add_highlight' to highlight
" text based on location. Spaces within fields are highlighted.
function! s:LocationColorize(event_types, field_bounds_table) abort
  for l:linenr in range(1, line('$'))
    let line = getline(l:linenr)
    let l:field_bounds_list = a:field_bounds_table[l:linenr - 1]
    for l:idx in range(len(l:field_bounds_list))
      let l:field_bounds = field_bounds_list[l:idx]
      " byteidx() returns the end byte of the corresponding character, which
      " requires adjustment for l:start (to include all bytes in the char),
      " but is usable as-is for l:end.
      let l:start = byteidx(l:line, l:field_bounds[0])
            \ - strlen(nr2char(strgetchar(l:line, l:field_bounds[0] - 1)))
            \ + 1
      let l:end = byteidx(l:line, l:field_bounds[1])
      let l:hlgroup = 'StartupTime'
      if l:linenr ==# 1
        let l:hlgroup .= ['StartupKey', 'StartupValue'][l:idx]
      elseif l:linenr ==# 2
        let l:hlgroup .= 'Header'
      else
        let l:col_name = s:col_names[l:idx]
        if l:col_name ==# 'event'
          " 'l:linenr' is decremented to accommodate lines starting at 1 and the
          " preamble lines prior to the table's data.
          let l:event_type = a:event_types[l:linenr - 1 - s:preamble_line_count]
          if l:event_type ==# s:event_types['sourcing']
            let l:hlgroup .= 'SourcingEvent'
          elseif l:event_type ==# s:event_types['other']
            let l:hlgroup .= 'OtherEvent'
          else
            throw 'vim-startuptime: unknown type'
          endif
        else
          let l:hlgroup .= toupper(l:col_name[0]) . tolower(l:col_name[1:])
        endif
      endif
      let l:bufnr = bufnr('%')
      if has('textprop')
        if empty(prop_type_get(l:hlgroup, {'bufnr': l:bufnr}))
          let l:props = {
                \   'highlight': l:hlgroup,
                \   'bufnr': l:bufnr,
                \ }
          call prop_type_add(l:hlgroup, l:props)
        endif
        let l:props = {
              \   'type': l:hlgroup,
              \   'end_col': l:end + 1,
              \ }
        call prop_add(l:linenr, l:start, l:props)
      elseif exists('*nvim_buf_add_highlight')
        call nvim_buf_add_highlight(
              \ l:bufnr,
              \ -1,
              \ l:hlgroup,
              \ l:linenr - 1,
              \ l:start - 1,
              \ l:end)
      else
        throw 'vim-startuptime: unable to highlight'
      endif
    endfor
  endfor
endfunction

function! s:Colorize(event_types, field_bounds_table) abort
  " Use text properties (introduced in Vim 8.2) or Neovim's similar
  " functionality (nvim_buf_add_highlight), where applicable. This can be
  " faster than pattern-based syntax matching, as processing is only done once
  " (as opposed to processing on each screen redrawing) and doesn't require
  " pattern matching. Use pattern-based syntax matching as a fall-back when
  " the other approaches are not available. If the application of
  " matchaddpos() was per-buffer, as opposed to per-window, it could be used
  " in-place of the various approaches here. Per-window application is
  " problematic, because subsequent changes to the file in the window will
  " result in mis-applied highlighting.
  if has('textprop') || exists('*nvim_buf_add_highlight')
    call s:LocationColorize(a:event_types, a:field_bounds_table)
  else
    call s:SyntaxColorize(a:event_types)
  endif
endfunction

function! s:SaveCallback(varname, items, startup, timer_id) abort
  " A mapping of types is returned since the internal integers are referenced
  " by the array of items.
  let g:[a:varname] = {
        \   'items': deepcopy(a:items),
        \   'startup': deepcopy(a:startup),
        \   'types': deepcopy(s:event_types),
        \ }
  doautocmd <nomodeline> User StartupTimeSaved
endfunction

function! s:Process(options, items) abort
  let l:items = a:items
  let l:startup = s:Startup(l:items)
  let l:items = s:Consolidate(l:items)
  let l:items = s:Augment(l:items, a:options)
  if a:options.sort
    let l:Compare = {i1, i2 ->
          \ i1.time ==# i2.time ? 0 : (i1.time <# i2.time ? 1 : -1)}
    call sort(l:items, l:Compare)
  endif
  if !empty(a:options.save)
    " Saving the data is executed asynchronously with a callback. Otherwise,
    " when s:Process is called through startuptime#Main, 'eventignore' would
    " be set to all and have to be handled.
    call timer_start(0, function('s:SaveCallback',
          \ [a:options.save, l:items, l:startup]))
  endif
  return [l:items, l:startup]
endfunction

" Load timing results from the specified file and show the results in the
" specified window. The file is deleted. The active window is retained.
function! startuptime#Main(file, winid, bufnr, options, items) abort
  let l:winid = win_getid()
  let l:eventignore = &eventignore
  set eventignore=all
  try
    if winbufnr(a:winid) !=# a:bufnr | return | endif
    call win_gotoid(a:winid)
    call s:SetBufLine(a:bufnr, 3, 'Processing...')
    " Redraw so that "[100%]" and "Processing..." show. Don't do this if the
    " tab changed, since it would result in flickering.
    if getwininfo(l:winid)[0].tabnr ==# getwininfo(a:winid)[0].tabnr
      redraw!
    endif
    let l:processing_finished = 0
    " Save event width for possible restoring.
    let l:event_width = g:startuptime_event_width
    try
      let [l:items, l:startup] = s:Process(a:options, a:items)
      let l:processing_finished = 1
      " Set 'modifiable' after :redraw so that e.g., if modifiable shows in
      " the status line, it's display is not changed for the duration of
      " running/processing.
      setlocal modifiable
      call s:ClearCurrentBuffer()
      call s:RegisterMaps(l:items, a:options, l:startup)
      if g:startuptime_event_width ==# 0
        for l:item in l:items
          let l:event = s:SimplifiedEvent(l:item)
          let g:startuptime_event_width =
                \ max([strchars(l:event), g:startuptime_event_width])
        endfor
      endif
      let l:field_bounds_table = s:Tabulate(l:items, l:startup)
      let l:event_types = map(copy(l:items), 'v:val.type')
      if g:startuptime_colorize && (has('gui_running') || &t_Co > 1)
        call s:Colorize(l:event_types, l:field_bounds_table)
      endif
      setlocal nowrap
      setlocal list
      setlocal listchars=precedes:<,extends:>
    catch /^Vim:Interrupt$/
      if !l:processing_finished
        call s:SetBufLine(a:bufnr, 3, 'Processing cancelled')
      endif
    endtry
    setlocal nomodifiable
  finally
    let g:startuptime_event_width = l:event_width
    call win_gotoid(l:winid)
    let &eventignore = l:eventignore
  endtry
endfunction

function! s:ShowZeroProgressMsg(winid, bufnr)
  if !bufexists(a:bufnr)
    return
  endif
  let l:winid = win_getid()
  let l:eventignore = &eventignore
  set eventignore=all
  try
    if winbufnr(a:winid) !=# a:bufnr | return | endif
    call win_gotoid(a:winid)
    setlocal modifiable
    if g:startuptime_zero_progress_msg && b:startuptime_zero_progress
      let l:lines = [
            \   '',
            \   'Is vim-startuptime stuck on 0% progress?',
            \   '',
            \   '  The plugin measures startuptime by asynchronously running (n)vim',
            \   '  with the --startuptime argument. If there is a request for user',
            \   '  input (e.g., "Press ENTER"), then processing will get stuck at 0%.',
            \   '',
            \   '  To investigate further, try starting a terminal with :terminal, and',
            \   '  launching a nested instance of (n)vim. If you see "Press ENTER or',
            \   '  type command to continue" or some other message interfering with',
            \   '  ordinary startup, this could be problematic for vim-startuptime.',
            \   '  Running :messages within the nested (n)vim may help identify the',
            \   '  issue.',
            \   '',
            \   '  It may help to run a nested instance of (n)vim in a manner similar',
            \   '  to vim-startuptime. The following lines show the shell-escaped',
            \   '  program and arguments used by vim-startuptime. <OUTPUT> should be',
            \   '  replaced with an output file.',
            \   '',
            \ ]
      let l:command = s:ProfileCmd('<OUTPUT>')
      call add(l:lines, '    ' . shellescape(l:command[0]))
      for l:line in l:command[1:]
        call add(l:lines, '      ' . shellescape(l:line))
      endfor
      call extend(l:lines, [
            \   '',
            \   '  Try running vim-startuptime again once the problem is avoided via a',
            \   '  configuration update.',
            \ ])
      for l:line in l:lines
        call s:SetBufLine(a:bufnr, line('$') + 1, l:line)
      endfor
    endif
    setlocal nomodifiable
  finally
    call win_gotoid(l:winid)
    let &eventignore = l:eventignore
  endtry
endfunction

function! s:True(...) abort
  return 1
endfunction

" Updates progress bar. Returns a status indicating whether the startuptime
" buffer and window still exists.
function! s:OnProgress(winid, bufnr, total, pending) abort
  if !bufexists(a:bufnr)
    return 0
  endif
  let l:winid = win_getid()
  let l:eventignore = &eventignore
  set eventignore=all
  try
    if winbufnr(a:winid) !=# a:bufnr | return 0 | endif
    call win_gotoid(a:winid)
    setlocal modifiable
    let b:startuptime_zero_progress = a:pending ==# a:total
    " Delete the zero-progress message.
    if line('$') ># 2
      " 'deletebufline' works better than 'delete' since it retains the
      " position of the cursor, but is not available on earlier versions.
      if exists('*deletebufline')
        call deletebufline(a:bufnr, 3, '$')
      else
        3,$delete _
      endif
    endif
    let l:percent = 100.0 * (a:total - a:pending) / a:total
    call s:SetBufLine(a:bufnr, 2, printf("Running: [%.0f%%]", l:percent))
    if a:pending ==# a:total
      let l:cmd = 'call s:ShowZeroProgressMsg(' . a:winid . ', ' . a:bufnr. ')'
      call timer_start(g:startuptime_zero_progress_time, {-> execute(l:cmd)})
    endif
    setlocal nomodifiable
  finally
    call win_gotoid(l:winid)
    let &eventignore = l:eventignore
  endtry
  return 1
endfunction

" Create a new window or tab with a buffer for startuptime.
function! s:New(mods) abort
  try
    let l:vert = s:Contains(a:mods, 'vertical')
    let l:parts = ['split', '+enew']
    if s:Contains(a:mods, 'tab')
      let l:parts = ['tabnew', '+enew']
    elseif s:Contains(a:mods, 'aboveleft') || s:Contains(a:mods, 'leftabove')
      let l:parts = ['topleft'] + l:parts
    elseif s:Contains(a:mods, 'belowright') || s:Contains(a:mods, 'rightbelow')
      let l:parts = ['botright'] + l:parts
    elseif &splitbelow && !l:vert
      let l:parts = ['botright'] + l:parts
    elseif &splitright && l:vert
      let l:parts = ['botright'] + l:parts
    else
      let l:parts = ['topleft'] + l:parts
    endif
    if l:vert
      let l:parts = ['vertical'] + l:parts
    endif
    let l:parts = ['silent'] + l:parts
    execute join(l:parts)
  catch
    return 0
  endtry
  return 1
endfunction

function! s:Options(args) abort
  let l:options = {
        \   'help': 0,
        \   'hidden': 0,
        \   'other_events': g:startuptime_other_events,
        \   'save': '',
        \   'sourced': g:startuptime_sourced,
        \   'sort': g:startuptime_sort,
        \   'sourcing_events': g:startuptime_sourcing_events,
        \   'tries': g:startuptime_tries,
        \ }
  let l:idx = 0
  " WARN: Any new/removed/changed arguments below should have corresponding
  " updates below in the startuptime#CompleteOptions function and the
  " startuptime#StartupTime usage documentation.
  while l:idx <# len(a:args)
    let l:arg = a:args[l:idx]
    if l:arg ==# '--help'
      let l:options.help = 1
      break
    elseif l:arg ==# '--hidden'
      let l:options.hidden = 1
    elseif l:arg ==# '--other-events' || l:arg ==# '--no-other-events'
      let l:options.other_events = l:arg ==# '--other-events'
    elseif l:arg ==# '--save'
      let l:idx += 1
      let l:options.save = a:args[l:idx]
    elseif l:arg ==# '--sourced' || l:arg ==# '--no-sourced'
      let l:options.sourced = l:arg ==# '--sourced'
    elseif l:arg ==# '--sort' || l:arg ==# '--no-sort'
      let l:options.sort = l:arg ==# '--sort'
    elseif l:arg ==# '--sourcing-events' || l:arg ==# '--no-sourcing-events'
      let l:options.sourcing_events = l:arg ==# '--sourcing-events'
    elseif l:arg ==# '--tries'
      let l:idx += 1
      let l:arg = a:args[l:idx]
      let l:options.tries = str2nr(l:arg)
    else
      throw 'vim-startuptime: unknown argument (' . l:arg . ')'
    endif
    if type(l:options.tries) ==# v:t_float
      let l:options.tries = float2nr(l:options.tries)
    endif
    if type(l:options.tries) !=# v:t_number || l:options.tries <# 1
      throw 'vim-startuptime: invalid argument (tries)'
    endif
    let l:idx += 1
  endwhile
  if !l:options.other_events && !l:options.sourcing_events
    throw 'vim-startuptime: '
          \ . '--no-other-events and --no-sourcing-events cannot be combined'
  endif
  return l:options
endfunction

" Returns the script ID, for testing functions with internal visibility.
function! startuptime#Sid() abort
  let l:sid = expand('<SID>')
  if !empty(l:sid)
    return l:sid
  endif
  " Older versions of Vim cannot expand "<SID>".
  if !exists('*s:Sid')
    function s:Sid() abort
      return matchstr(expand('<sfile>'), '\zs<SNR>\d\+_\zeSid$')
    endfunction
  endif
  return s:Sid()
endfunction

" A 'custom' completion function for :StartupTime. A 'custom' function is used
" instead of a 'customlist' function, for the automatic filtering that is
" conducted for the former, but not the latter.
function! startuptime#CompleteOptions(...) abort
  let l:args = [
        \   '--help',
        \   '--hidden',
        \   '--other-events', '--no-other-events',
        \   '--save',
        \   '--sourced', '--no-sourced',
        \   '--sort', '--no-sort',
        \   '--sourcing-events', '--no-sourcing-events',
        \   '--tries',
        \ ]
  return join(l:args, "\n")
endfunction

" Usage:
"   :StartupTime
"          \ [--hidden]
"          \ [--sort] [--no-sort]
"          \ [--sourcing-events] [--no-sourcing-events]
"          \ [--other-events] [--no-other-events]
"          \ [--save STRING]
"          \ [--sourced] [--no-sourced]
"          \ [--tries INT]
"          \ [--help]
function! startuptime#StartupTime(mods, ...) abort
  if !has('nvim') && !has('terminal')
    throw 'vim-startuptime: +terminal feature required'
  endif
  if !has('nvim') && !has('startuptime')
    throw 'vim-startuptime: +startuptime feature required'
  endif
  let l:mods = split(a:mods)
  let l:options = s:Options(a:000)
  if l:options.help
    execute a:mods . ' help startuptime.txt'
    return
  endif
  let l:items = []
  let l:file = tempname()
  if l:options.hidden
    let l:OnProgress = function('s:True')
    let l:OnFinish = function('s:Process', [l:options, l:items])
  else
    if !s:New(l:mods)
      throw 'vim-startuptime: couldn''t create new buffer'
    endif
    setlocal buftype=nofile
    setlocal noswapfile
    setlocal nofoldenable
    setlocal foldcolumn=0
    setlocal bufhidden=wipe
    setlocal nobuflisted
    setlocal filetype=startuptime
    setlocal nospell
    setlocal wrap
    " Prevent the built-in matchparen plugin from highlighting matching brackets
    " (on the vim-startuptime loading screen). The plugin can't be disabled at
    " the buffer level.
    setlocal matchpairs=
    call s:SetFile()
    call setline(1, '# vim-startuptime')
    setlocal nomodifiable
    let l:bufnr = bufnr('%')
    let l:winid = win_getid()
    let l:OnProgress = function(
          \ 's:OnProgress', [l:winid, l:bufnr, l:options.tries])
    let l:OnFinish = function(
          \ 'startuptime#Main', [l:file, l:winid, l:bufnr, l:options, l:items])
  endif
  call s:Profile(
        \ l:OnFinish, l:OnProgress, l:options, l:options.tries, l:file, l:items)
endfunction
