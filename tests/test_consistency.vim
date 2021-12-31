" Test that startuptime functions are consistent across VimScript/Lua in
" Neovim and VimScript/Vim9 in Vim.

let s:sid = startuptime#Sid()
let s:Options = function(s:sid . 'Options')
let s:ExtractVimScript = function(s:sid . 'ExtractVimScript')
let s:ConsolidateVimScript = function(s:sid . 'ConsolidateVimScript')
let s:tfields = function(s:sid . 'TFields')()
if has('nvim')
  let s:ExtractOpt = function(s:sid . 'ExtractLua')
  let s:ConsolidateOpt = function(s:sid . 'ConsolidateLua')
else
  let s:ExtractOpt = function(s:sid . 'ExtractVim9')
  let s:ConsolidateOpt = function(s:sid . 'ConsolidateVim9')
endif

function! s:Execute(file) abort
  " XXX: A more thorough approach for using --startuptime is used in s:Profile
  " in autoload/startuptime.vim, to retain all events.
  let l:exepath = exepath(v:progpath)
  silent execute '!' . l:exepath . ' --startuptime ' . a:file . ' +qall\!'
endfunction

let s:file = tempname()
try
  call s:Execute(s:file)
  let s:optionss = []
  for s:other in ['--other-events', '--no-other-events']
    for s:sourced in ['--sourced', '--no-sourced']
      for s:sort in ['--sort', '--no-sort']
        for s:sourcing in ['--sourcing-events', '--no-sourcing-events']
          try
            let s:options = s:Options([s:other, s:sourced, s:sort, s:sourcing])
            call add(s:optionss, s:options)
          catch
          endtry
        endfor
      endfor
    endfor
  endfor
  " 4 of the 16 option configurations should error.
  call assert_equal(12, len(s:optionss))

  for s:options in s:optionss
    " Test Lua/VimScript consistency with default options.
    let s:extracted_vimscript = s:ExtractVimScript(s:file, s:options)
    call assert_equal(1, len(s:extracted_vimscript))
    call assert_true(!empty(s:extracted_vimscript[0]))
    let s:extracted_opt = s:ExtractOpt(s:file, s:options)
    call assert_equal(s:extracted_vimscript, s:extracted_opt)
    let s:consolidated_vimscript =
          \ s:ConsolidateVimScript(s:extracted_vimscript)
    let s:consolidated_opt = s:ConsolidateOpt(s:extracted_opt)
    call assert_equal(
          \ len(s:consolidated_vimscript), len(s:consolidated_opt))
    " Compare each item individually for improved output when test fails.
    for s:idx in range(len(s:consolidated_vimscript))
      let s:item_vimscript = s:consolidated_vimscript[s:idx]
      let s:item_opt = s:consolidated_opt[s:idx]
      " Convert NaN standard deviation to -1 since NaN !=# NaN.
      for s:item in [s:item_vimscript, s:item_opt]
        for s:tfield in s:tfields
          if has_key(s:item, s:tfield) && isnan(s:item[s:tfield].std)
            let s:item[s:tfield].std = -1
          endif
        endfor
      endfor
      call assert_equal(s:item_vimscript, s:item_opt)
    endfor
  endfor

  " Add more profiling data and test again.
  for _ in range(5)
    call s:Execute(s:file)
  endfor
  for s:options in s:optionss
    let s:extracted_vimscript = s:ExtractVimScript(s:file, s:options)
    call assert_equal(6, len(s:extracted_vimscript))
    call assert_true(!empty(s:extracted_vimscript[0]))
    let s:extracted_opt = s:ExtractOpt(s:file, s:options)
    call assert_equal(s:extracted_vimscript, s:extracted_opt)
    let s:consolidated_vimscript =
          \ s:ConsolidateVimScript(s:extracted_vimscript)
    let s:consolidated_opt = s:ConsolidateOpt(s:extracted_opt)
    call assert_equal(len(s:consolidated_vimscript), len(s:consolidated_opt))
    " Compare each item individually for improved output when test fails.
    for s:idx in range(len(s:consolidated_vimscript))
      call assert_equal(
            \ s:consolidated_vimscript[s:idx], s:consolidated_opt[s:idx])
    endfor
  endfor
finally
  call delete(s:file)
endtry
