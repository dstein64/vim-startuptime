" *************************************************
" * Globals
" *************************************************

let s:sourcing_event_type = 0
let s:other_event_type = 1

" 's:tfields' contains the time fields.
let s:tfields = ['elapsed', 'self+sourced', 'self']

let s:col_names = ['event', 'time', 'percent', 'plot']
let s:widths = {
      \   'event': g:startuptime_event_width,
      \   'time': g:startuptime_time_width,
      \   'percent': g:startuptime_percent_width,
      \   'plot': g:startuptime_plot_width
      \ }
function! s:ColBoundsLookup()
  let l:result = {}
  let l:position = 1
  for l:col_name in s:col_names
    let l:start = l:position
    let l:end = l:start + s:widths[l:col_name] - 1
    let l:result[l:col_name] = [l:start, l:end]
    let l:position = l:end + 2
  endfor
  return l:result
endfunction
let s:col_bounds_lookup = s:ColBoundsLookup()

" Maps property type names to the corresponding highlight groups.
let s:prop_type_highlight_lookup = {
      \   'startuptime_header': 'StartupTimeHeader',
      \   'startuptime_sourcing_event': 'StartupTimeSourcingEvent',
      \   'startuptime_other_event': 'StartupTimeOtherEvent',
      \   'startuptime_time': 'StartupTimeTime',
      \   'startuptime_percent': 'StartupTimePercent',
      \   'startuptime_plot': 'StartupTimePlot',
      \ }

" *************************************************
" * Utils
" *************************************************

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

" The built-in min() does not work with floats.
function! s:Min(numbers)
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

function! s:Surround(inner, outer)
  return a:outer . a:inner . a:outer
endfunction

" *************************************************
" * Core
" *************************************************

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

function! s:Profile(callback, tries, file)
  if a:tries ==# 0
    call a:callback()
    return
  endif
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
        \ 'if exists(''*timer_start'') | %s | else |  %s | endif',
        \ l:quit_cmd_timer,
        \ l:quit_cmd_autocmd)
  let l:command = [
        \   g:startuptime_exe_path,
        \   '--startuptime', a:file,
        \   '-c', l:quit_cmd
        \ ]
  call extend(l:command, g:startuptime_exe_args)
  let l:env = {
        \   'callback': a:callback,
        \   'tries': a:tries,
        \   'file': a:file
        \ }
  " The 'tmp' dicts below are used only so local functions can be created.
  if has('nvim')
    let l:tmp = {}
    function l:tmp.exit(job, status, type) dict
      call s:Profile(self.callback, self.tries - 1, self.file)
    endfunction
    let l:options = {
          \   'pty': 1,
          \   'on_exit': function(l:tmp.exit, l:env)
          \ }
    let l:env.jobnr = jobstart(l:command, l:options)
  else
    let l:tmp = {}
    function l:tmp.exit(job, status) dict
      execute self.bufnr . 'bdelete'
      call s:Profile(self.callback, self.tries - 1, self.file)
    endfunction
    let l:options = {
          \   'exit_cb': function(l:tmp.exit, l:env),
          \   'hidden': 1
          \ }
    " XXX: A new buffer is created each time this is run. Running many times
    " will result in large buffer numbers.
    let l:env.bufnr = term_start(l:command, l:options)
  endif
endfunction

" Returns a nested list. The top-level list entries correspond to different
" profiling sessions. The next level lists contain the parsed lines for each
" profiling session. Each line is represented with a dict.
function! s:Extract(file, options)
  let l:result = []
  let l:lines = readfile(a:file)
  for l:line in l:lines
    if strchars(l:line) ==# 0 || l:line[0] !~# '^\d$'
      continue
    endif
    if l:line =~# ': --- N\=VIM STARTING ---$'
      call add(l:result, [])
    endif
    let l:idx = stridx(l:line, ':')
    let l:times = split(l:line[:l:idx - 1], '\s\+')
    let l:item = {
          \   'event': l:line[l:idx + 2:],
          \   'clock': str2float(l:times[0]),
          \   'type': s:other_event_type
          \ }
    if len(l:times) ==# 3
      let l:item.type = s:sourcing_event_type
      let l:item['self+sourced'] = str2float(l:times[1])
      let l:item.self = str2float(l:times[2])
    else
      let l:item.elapsed = str2float(l:times[1])
    endif
    let l:types = []
    if a:options.sourcing_events
      call add(l:types, s:sourcing_event_type)
    endif
    if a:options.other_events
      call add(l:types, s:other_event_type)
    endif
    if s:Contains(l:types, l:item.type)
      call add(l:result[-1], l:item)
    endif
  endfor
  return l:result
endfunction

" Consolidates the data returned by s:Extract(), by averaging times across
" tries.
function! s:Consolidate(items)
  if len(a:items) ==# 0 | return [] | endif
  let l:items = deepcopy(a:items)
  let l:tries = len(a:items)
  let l:result = deepcopy(l:items[0])
  let l:keys = map(copy(l:result), 'v:val.event')
  for l:try in l:items[1:]
    let l:_keys = map(copy(l:try), 'v:val.event')
    if l:keys !=# l:_keys
      throw 'vim-startuptime: inconsistent tries'
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

" Adds a time field to the data returned by s:Consolidate.
function! s:Augment(items, options)
  let l:result = deepcopy(a:items)
  for l:item in l:result
    let l:event = l:item.event
    if l:item.type ==# s:sourcing_event_type
      let l:time = l:item[a:options.self ? 'self' : 'self+sourced']
    elseif l:item.type ==# s:other_event_type
      let l:time = l:item.elapsed
    else
      throw 'vim-startuptime: unknown type'
    endif
    let l:item.time = l:time
  endfor
  return l:result
endfunction

function! startuptime#ShowMoreInfo()
  let l:line = line('.')
  let l:info_lines = []
  if l:line ==# 1
    call extend(l:info_lines, [
          \   '- You''ve queried for additional information.',
          \   '- sum(time) is ' . printf('%.2f', b:startuptime_total),
          \   '- More specific information is available for event lines.',
          \ ])
  elseif !has_key(b:startuptime_item_map, l:line)
    throw 'vim-startuptime: error getting more info'
  else
    let l:item = b:startuptime_item_map[l:line]
    call add(l:info_lines, 'event: ' . l:item.event)
    for l:tfield in s:tfields
      if has_key(l:item, l:tfield)
        call add(l:info_lines, l:tfield . ': ' . string(l:item[l:tfield]))
      endif
    endfor
    call add(l:info_lines, 'clock: ' . string(l:item.clock))
  endif
  call add(l:info_lines, '* times are in milliseconds')
  let l:echo_list = []
  call add(l:echo_list, ['Title', "vim-startuptime\n"])
  call add(l:echo_list, ['None', join(l:info_lines, "\n")])
  call add(l:echo_list, ['Question', "\n[press any key to continue]"])
  call s:Echo(l:echo_list)
  call s:GetChar()
  redraw | echo ''
endfunction

function! startuptime#GotoFile()
  let l:line = line('.')
  let l:nofile = 'header'
  if has_key(b:startuptime_item_map, l:line)
    let l:item = b:startuptime_item_map[l:line]
    if l:item.type ==# s:sourcing_event_type
      let l:file = substitute(l:item.event, '^sourcing ', '', '')
      execute 'aboveleft split ' . l:file
      return
    endif
    let l:nofile = s:Surround(l:item.event, "'")
  endif
  let l:message = 'vim-startuptime: no file for ' . l:nofile
  call s:Echo([['WarningMsg', l:message]])
endfunction

function! s:RegisterMaps(items)
  " 'b:startuptime_item_map' maps line numbers to corresponding items.
  let b:startuptime_item_map = {}
  let b:startuptime_total = s:Sum(map(copy(a:items), 'v:val.time'))
  for l:idx in range(len(a:items))
    " 'l:idx' is incremented by 2 since lines start at 1 and the first line is
    " a header.
    let b:startuptime_item_map[l:idx + 2] = a:items[l:idx]
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
function! s:ConstrainPattern(pattern, lines, columns)
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

function! s:CreatePlotLine(size, max, width)
  if has('multi_byte') && &encoding ==# 'utf-8'
    let l:block_chars = {
          \   1: nr2char(0x258F), 2: nr2char(0x258E),
          \   3: nr2char(0x258D), 4: nr2char(0x258C),
          \   5: nr2char(0x258B), 6: nr2char(0x258A),
          \   7: nr2char(0x2589), 8: nr2char(0x2588)
          \ }
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

" Given a field (string), col_name, and alignment (1 for left, 0 for right),
" return the column boundaries of the field.
function! s:FieldBounds(field, col_name, left)
  let l:col_bounds = s:col_bounds_lookup[a:col_name]
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
function! s:Tabulate(items)
  let l:output = []
  let l:line = printf('%-*S', s:widths.event, 'event')
  let l:line .= printf(' %*S', s:widths.time, 'time')
  let l:line .= printf(' %*S', s:widths.percent, 'percent')
  let l:line .= ' plot'
  let l:field_bounds_list = [
        \   s:FieldBounds('event', 'event', 1),
        \   s:FieldBounds('time', 'time', 0),
        \   s:FieldBounds('percent', 'percent', 0),
        \   s:FieldBounds('plot', 'plot', 1),
        \ ]
  call add(l:output, l:field_bounds_list)
  call append(line('$') - 1, l:line)
  if len(a:items) ==# 0 | return | endif
  let l:total = s:Sum(map(copy(a:items), 'v:val.time'))
  let l:max = s:Max(map(copy(a:items), 'v:val.time'))
  for l:item in a:items
    " XXX: Truncated numbers are not properly rounded (e.g., 1234.5678 would
    " be truncated to 1234.56, as opposed to 1234.57).
    let l:event = l:item.event
    if l:item.type ==# s:sourcing_event_type
      let l:event = substitute(l:event, '^sourcing ', '', '')
      let l:event = fnamemodify(l:event, ':t')
    endif
    let l:event = strcharpart(l:event, 0, s:widths.event)
    let l:line = printf('%-*S', s:widths.event, l:event)
    let l:time = printf('%.2f', l:item.time)
    let l:time = strcharpart(l:time, 0, s:widths.time)
    let l:line .= printf(' %*S', s:widths.time, l:time)
    let l:percent = printf('%.2f', 100 * l:item.time / l:total)
    let l:percent = strcharpart(l:percent, 0, s:widths.percent)
    let l:line .= printf(' %*S', s:widths.percent, l:percent)
    let l:field_bounds_list = [
          \   s:FieldBounds(l:event, 'event', 1),
          \   s:FieldBounds(l:time, 'time', 0),
          \   s:FieldBounds(l:percent, 'percent', 0),
          \ ]
    let l:plot = s:CreatePlotLine(l:item.time, l:max, s:widths.plot)
    if strchars(l:plot) ># 0
      let l:line .= printf(' %s', l:plot)
      call add(l:field_bounds_list, s:FieldBounds(l:plot, 'plot', 1))
    endif
    call add(l:output, l:field_bounds_list)
    call append(line('$') - 1, l:line)
  endfor
  normal! Gddgg
  return l:output
endfunction

" Converts a list of numbers into a list of numbers *and* ranges.
" For example:
"   > echo s:Rangify([1, 3, 4, 5, 9, 10, 12, 14, 15])
"     [1, [3, 5], [9, 10], 12, [14, 15]]
function! s:Rangify(list)
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
function! s:SyntaxColorize(event_types)
  let l:header_pattern = s:ConstrainPattern('\S', [1], ['*'])
  execute 'syntax match StartupTimeHeader ' . s:Surround(l:header_pattern, "'")
  let l:line_lookup = {s:sourcing_event_type: [], s:other_event_type: []}
  for l:idx in range(len(a:event_types))
    let l:event_type = a:event_types[l:idx]
    " 'l:idx' is incremented by 2 since lines start at 1 and the first line is
    " a header.
    let l:line = l:idx + 2
    call add(l:line_lookup[l:event_type], l:line)
  endfor
  let l:sourcing_event_pattern = s:ConstrainPattern(
        \ '\S',
        \ s:Rangify(l:line_lookup[s:sourcing_event_type]),
        \ [s:col_bounds_lookup.event])
  execute 'syntax match StartupTimeSourcingEvent '
        \ . s:Surround(l:sourcing_event_pattern, "'")
  let l:other_event_pattern = s:ConstrainPattern(
        \ '\S',
        \ s:Rangify(l:line_lookup[s:other_event_type]),
        \ [s:col_bounds_lookup.event])
  execute 'syntax match StartupTimeOtherEvent '
        \ . s:Surround(l:other_event_pattern, "'")
  let l:time_pattern = s:ConstrainPattern(
        \ '\S',
        \ [[2, '$']],
        \ [s:col_bounds_lookup.time])
  execute 'syntax match StartupTimeTime ' . s:Surround(l:time_pattern, "'")
  let l:percent_pattern = s:ConstrainPattern(
        \ '\S', [[2, '$']], [s:col_bounds_lookup.percent])
  execute 'syntax match StartupTimePercent ' . s:Surround(l:percent_pattern, "'")
  let l:plot_pattern = s:ConstrainPattern(
        \ '\S',
        \ [[2, '$']],
        \ [s:col_bounds_lookup.plot])
  execute 'syntax match StartupTimePlot ' . s:Surround(l:plot_pattern, "'")
endfunction

function! s:CreatePropTypes(bufnr)
  for [l:prop_name, l:highlight] in items(s:prop_type_highlight_lookup)
    if len(prop_type_get(l:prop_name)) ==# 0
      let l:props = {
            \   'highlight': l:highlight,
            \   'bufnr': a:bufnr,
            \ }
      call prop_type_add(l:prop_name, l:props)
    endif
  endfor
endfunction

" Use Vim's text properties or Neovim's 'nvim_buf_add_highlight' to highlight
" text based on location. Spaces within fields are highlighted.
function! s:LocationColorize(event_types, field_bounds_table)
  if has('textprop') | call s:CreatePropTypes(bufnr('%')) | endif
  for l:linenr in range(1, line('$'))
    let line = getline(l:linenr)
    let l:field_bounds_list = a:field_bounds_table[l:linenr - 1]
    for l:idx in range(len(l:field_bounds_list))
      let l:col_name = s:col_names[l:idx]
      let l:field_bounds = field_bounds_list[l:idx]
      " byteidx() returns the end byte of the corresponding character, which
      " requires adjustment for l:start (to include all bytes in the char),
      " but is useable as-is for l:end.
      let l:start = byteidx(l:line, l:field_bounds[0])
            \ - strlen(nr2char(strgetchar(l:line, l:field_bounds[0] - 1)))
            \ + 1
      let l:end = byteidx(l:line, l:field_bounds[1])
      let l:prop_type = 'startuptime_'
      if l:linenr ==# 1
        let l:prop_type .= 'header'
      elseif l:col_name ==# 'event'
        " 'l:linenr' is decremented by 2 since lines start at 1 and the first
        " line is a header.
        let l:event_type = a:event_types[l:linenr - 2]
        if l:event_type ==# s:sourcing_event_type
          let l:prop_type .= 'sourcing_event'
        elseif l:event_type ==# s:other_event_type
          let l:prop_type .= 'other_event'
        else
          throw 'vim-startuptime: unknown type'
        endif
      else
        let l:prop_type .= l:col_name
      endif
      if has('textprop')
        let l:props = {
              \   'type': l:prop_type,
              \   'end_col': l:end + 1,
              \ }
        call prop_add(l:linenr, l:start, l:props)
      elseif exists('*nvim_buf_add_highlight')
        call nvim_buf_add_highlight(
              \ bufnr('%'),
              \ -1,
              \ s:prop_type_highlight_lookup[l:prop_type],
              \ l:linenr - 1,
              \ l:start - 1,
              \ l:end)
      else
        throw 'vim-startuptime: unable to highlight'
      endif
    endfor
  endfor
endfunction

function! s:Colorize(event_types, field_bounds_table)
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
    let l:items = s:Extract(a:file, a:options)
    let l:items = s:Consolidate(l:items)
    let l:items = s:Augment(l:items, a:options)
    let l:Compare = {i1, i2 ->
          \ i1.time ==# i2.time ? 0 : (i1.time <# i2.time ? 1 : -1)}
    if a:options.sort
      call sort(l:items, l:Compare)
    endif
    call s:RegisterMaps(l:items)
    let l:field_bounds_table = s:Tabulate(l:items)
    let l:event_types = map(copy(l:items), 'v:val.type')
    if g:startuptime_colorize && (has('gui_running') || &t_Co > 1)
      call s:Colorize(l:event_types, l:field_bounds_table)
    endif
    call delete(a:file)
    setlocal nomodifiable
  finally
    call win_gotoid(l:winid)
    let &eventignore = l:eventignore
  endtry
endfunction

" Create a new window or tab with a buffer for startuptime.
function! s:New(mods)
  try
    let l:vert = s:Contains(a:mods, 'vertical')
    let l:parts = ['split', 'enew']
    if s:Contains(a:mods, 'tab')
      let l:parts = ['tabnew', 'enew']
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

function! s:Options(args)
  let l:options = {
        \   'help': 0,
        \   'other_events': g:startuptime_other_events,
        \   'self': g:startuptime_self,
        \   'sort': g:startuptime_sort,
        \   'sourcing_events': g:startuptime_sourcing_events,
        \   'tries': g:startuptime_tries,
        \ }
  let l:idx = 0
  while l:idx <# len(a:args)
    let l:arg = a:args[l:idx]
    if l:arg ==# '--help'
      let l:options.help = 1
      break
    elseif l:arg ==# '--other-events' || l:arg ==# '--no-other-events'
      let l:options.other_events = l:arg ==# '--other-events'
    elseif l:arg ==# '--self' || l:arg ==# '--no-self'
      let l:options.self = l:arg ==# '--self'
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
    let l:idx += 1
  endwhile
  return l:options
endfunction

" Usage:
"   :StartupTime
"          \ [--sort] [--no-sort]
"          \ [--sourcing-events] [--no-sourcing-events]
"          \ [--other-events] [--no-other-events]
"          \ [--self] [--no-self]
"          \ [--tries INT]
function! startuptime#StartupTime(mods, ...)
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
  if !s:New(l:mods)
    throw 'vim-startuptime: couldn''t create new buffer'
  endif
  setlocal buftype=nofile noswapfile nofoldenable foldcolumn=0
  setlocal bufhidden=wipe nobuflisted
  setlocal nowrap
  setlocal modifiable
  call s:SetFile()
  call append(line('$') - 1, 'vim-startuptime: running... (please wait)')
  let l:file = tempname()
  let l:args = [l:file, win_getid(), bufnr('%'), l:options]
  let l:Callback = function('startuptime#Main', l:args)
  call s:Profile(l:Callback, l:options.tries, l:file)
endfunction
