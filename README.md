# vim-startuptime

`vim-startuptime` is a Vim plugin for viewing `vim` and `nvim` startup event
timing information. The plugin is customizable (see *Configuration* below).

<img src="https://github.com/dstein64/vim-startuptime/blob/master/screenshot.png?raw=true" width="800"/>

## Requirements

* `vim>=8.0.1453` or `nvim>=0.2.2`
  - The plugin may work on earlier versions, but has not been tested.
  - The plugin depends on compile-time features for `vim` (not applicable for `nvim`).
    * `+startuptime` is required.
    * `+timers` is recommended, to capture *all* startup events.
    * `+terminal` is required.

## Installation

Use one of the following package managers:

* [Vim8 packages][vim8pack]:
  - `git clone https://github.com/dstein64/vim-startuptime ~/.vim/pack/plugins/start/vim-startuptime`
* [Vundle][vundle]:
  - Add `Plugin 'dstein64/vim-startuptime'` to `~/.vimrc`
  - `:PluginInstall` or `$ vim +PluginInstall +qall`
* [Pathogen][pathogen]:
  - `git clone --depth=1 https://github.com/dstein64/vim-startuptime ~/.vim/bundle/vim-startuptime`
* [vim-plug][vimplug]:
  - Add `Plug 'dstein64/vim-startuptime'` to `~/.vimrc`
  - `:PlugInstall` or `$ vim +PlugInstall +qall`
* [dein.vim][dein]:
  - Add `call dein#add('dstein64/vim-startuptime')` to `~/.vimrc`
  - `:call dein#install()`
* [NeoBundle][neobundle]:
  - Add `NeoBundle 'dstein64/vim-startuptime'` to `~/.vimrc`
  - Re-open vim or execute `:source ~/.vimrc`

## Usage

Launch `vim-startuptime` with `:StartupTime`. Press `<space>` on events to get
additional information. The key sequence for additional information can be customized
(see *Configuration* below). Times are in milliseconds.

### Arguments

`:StartupTime` takes the following optional arguments.

* `--sort` and `--no-sort` specify whether events are sorted.
* `--sourced-events` and `--no-sourced-events` specify whether *sourced script*
events are included.
* `--other-events` and `--no-other-events` specify whether *other lines* events
are included.
* `--self` and `--no-self` specify whether to use *self* timings for *sourced
script* events (otherwise, *self+sourced* timings are used).
* `--tries` specifies how many startup times are averaged.
* `--help` shows the plugin's documentation.

```vim
:StartupTime
       \ [--sort] [--no-sort]
       \ [--sourced-events] [--no-sourced-events]
       \ [--other-events] [--no-other-events]
       \ [--self] [--no-self]
       \ [--tries INT]
       \ [--help]
```

### Modifiers

`:StartupTime` accepts the following modifiers.

* `:tab`
* `:aboveleft` or `:leftabove`
* `:belowright` or `:rightbelow`
* `:vertical`

### Vim Options

`:StartupTime` observes the following options, but these are overruled by
modifiers above.

* `'splitbelow'`
* `'splitright'`

## Configuration

The following variables can be used to customize the behavior of `vim-startuptime`.
The `:StartupTime` optional arguments have higher precedence than these options.

| Variable                          | Default            | Description                                                       |
|-----------------------------------|--------------------|-------------------------------------------------------------------|
| `g:startuptime_more_info_key_seq` | `<space>`          | Key sequence for getting more information                         |
| `g:startuptime_exe_path`          | *running vim* path | Path to `vim` for startup timing                                  |
| `g:startuptime_exe_args`          | `[]`               | Optional arguments to pass to `vim`                               |
| `g:startuptime_sort`              | `1`                | Specifies whether events are sorted                               |
| `g:startuptime_tries`             | `1`                | Specifies how many startup times are averaged                     |
| `g:startuptime_sourced_events`    | `1`                | Specifies whether *sourced script* events are included            |
| `g:startuptime_other_events`      | `1`                | Specifies whether *other lines* events are included               |
| `g:startuptime_self`              | `0`                | Specify whether to use *self* timings for *sourced script* events |
| `g:startuptime_event_width`       | `20`               | Event column width                                                |
| `g:startuptime_time_width`        | `6`                | Time column width                                                 |
| `g:startuptime_percent_width`     | `7`                | Percent column width                                              |
| `g:startuptime_plot_width`        | `26`               | Plot column width                                                 |
| `g:startuptime_colorize`          | `1`                | Specifies whether table data is colorized                         |

The variables can be customized in your `.vimrc`, as shown in the following
example.

```vim
let g:startuptime_sort = 0
let g:startuptime_tries = 5
let g:startuptime_exe_args = ['-u', '~/.vim/vimrc']
```

### Color Customization

The following highlight groups can be configured to change `vim-startuptime`'s
colors.

| Name                       | Default      | Description                    |
|----------------------------|--------------|--------------------------------|
| `StartupTimeHeader`        | `ModeMsg`    | Color for the header row text  |
| `StartupTimeSourcingEvent` | `Type`       | Color for sourcing event names |
| `StartupTimeOtherEvent`    | `Identifier` | Color for other event names    |
| `StartupTimeTime`          | `Directory`  | Color for the time column      |
| `StartupTimePercent`       | `Special`    | Color for the percent column   |
| `StartupTimePlot`          | `Normal`     | Color for the plot column      |

The highlight groups can be customized in your `.vimrc`, as shown in the
following example.

```vim
" Link StartupTimeSourcingEvent highlight to Title highlight
highlight link StartupTimeSourcingEvent Title

" Specify custom highlighting for StartupTimeTime
highlight StartupTimeTime
       \ term=bold ctermfg=12 ctermbg=159 guifg=Blue guibg=LightCyan
```

License
-------

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](https://github.com/dstein64/vim-startuptime/blob/master/LICENSE).

[dein]: https://github.com/Shougo/dein.vim
[neobundle]: https://github.com/Shougo/neobundle.vim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
