" Test that startuptime functions are consistent across VimScript and Lua.

let s:sid = startuptime#Sid()
let s:Options = funcref(s:sid . 'Options')
let s:ExtractLua = funcref(s:sid . 'ExtractLua')
let s:ExtractVimScript = funcref(s:sid . 'ExtractVimScript')
let s:ConsolidateLua = funcref(s:sid . 'ConsolidateLua')
let s:ConsolidateVimScript = funcref(s:sid . 'ConsolidateVimScript')
let s:TFields = funcref(s:sid . 'TFields')

let s:file = tempname()
try
  let s:exepath = exepath(v:progpath)
  " XXX: A more thorough approach for using --startuptime is used in s:Profile
  " in autoload/startuptime.vim, to retain all events.
  silent execute '!' . s:exepath . ' --startuptime ' . s:file

  let s:optionss = []
  for s:other in ['--other-events', '--no-other-events']
    for s:sourced in ['--sourced', '--no-sourced']
      for s:sort in ['--sort', '--no-sort']
        for s:sourcing in ['--sourcing-events', '--no-sourcing-events']
          if s:other ==# '--other-events' || s:sourcing ==# '--sourcing-events'
            let s:options = s:Options([s:other, s:sourced, s:sort, s:sourcing])
            call add(s:optionss, s:options)
          endif
        endfor
      endfor
    endfor
  endfor
  call assert_equal(12, len(s:optionss))

  for s:options in s:optionss
    " Test Lua/VimScript consistency with default options.
    let s:extracted_vimscript = s:ExtractVimScript(s:file, s:options)
    call assert_equal(1, len(s:extracted_vimscript))
    call assert_true(!empty(s:extracted_vimscript[0]))
    let s:extracted_lua = s:ExtractLua(s:file, s:options)
    call assert_equal(s:extracted_vimscript, s:extracted_lua)
    let s:consolidated_vimscript =
          \ s:ConsolidateVimScript(s:extracted_vimscript)
    let s:consolidated_lua = s:ConsolidateLua(s:extracted_lua)
    call assert_equal(
          \ len(s:consolidated_vimscript), len(s:consolidated_lua))
    " Compare each item individually for improved output when test fails.
    for s:idx in range(len(s:consolidated_vimscript))
      let s:item_vimscript = s:consolidated_vimscript[s:idx]
      let s:item_lua = s:consolidated_lua[s:idx]
      " Convert NaN standard deviation to -1 since NaN !=# NaN.
      for s:item in [s:item_vimscript, s:item_lua]
        for s:tfield in s:TFields()
          if has_key(s:item, s:tfield) && isnan(s:item[s:tfield].std)
            let s:item[s:tfield].std = -1
          endif
        endfor
      endfor
      call assert_equal(s:item_vimscript, s:item_lua)
    endfor
  endfor

  " Add more profiling data and test again.
  for _ in range(5)
    silent execute '!' . s:exepath . ' --startuptime ' . s:file
  endfor
  for s:options in s:optionss
    let s:extracted_vimscript = s:ExtractVimScript(s:file, s:options)
    call assert_equal(6, len(s:extracted_vimscript))
    call assert_true(!empty(s:extracted_vimscript[0]))
    let s:extracted_lua = s:ExtractLua(s:file, s:options)
    call assert_equal(s:extracted_vimscript, s:extracted_lua)
    let s:consolidated_vimscript =
          \ s:ConsolidateVimScript(s:extracted_vimscript)
    let s:consolidated_lua = s:ConsolidateLua(s:extracted_lua)
    call assert_equal(len(s:consolidated_vimscript), len(s:consolidated_lua))
    " Compare each item individually for improved output when test fails.
    for s:idx in range(len(s:consolidated_vimscript))
      call assert_equal(
            \ s:consolidated_vimscript[s:idx], s:consolidated_lua[s:idx])
    endfor
  endfor
finally
  call delete(s:file)
endtry
