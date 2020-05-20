# vim-startuptime

`vim-startuptime` is a Vim plugin for viewing `vim` and `nvim` startup event
timing information. The plugin is customizable (see
`:help startuptime-configuration`).

<img src="screenshot.png?raw=true" width="800"/>

## Requirements

* `vim>=8.0.1453` or `nvim>=0.2.2`
  - The plugin may work on earlier versions, but has not been tested.
  - The plugin depends on compile-time features for `vim` (not applicable for
    `nvim`).
    * `+startuptime` is required.
    * `+timers` is recommended, to capture *all* startup events.
    * `+terminal` is required.

## Installation

A package manager can be used to install `vim-startuptime`.
<details><summary>Examples</summary><br>

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

</details>

## Usage

* Launch `vim-startuptime` with `:StartupTime`.
* Press `<space>` on events to get additional information.
* Press `<enter>` on sourcing events to load the corresponding file in a new
  split.
* The key sequences above can be customized (`:help startuptime-configuration`).
* Times are in milliseconds.

## Documentation

Documentation can be accessed with either:

```vim
:help vim-startuptime
```

or:

```vim
:StartupTime --help
```

The underlying markup is in [startuptime.txt](doc/startuptime.txt).

There is documentation on the following topics.

| Topic               | `:help` *{subject}*               |
|---------------------|-----------------------------------|
| Arguments           | `startuptime-arguments`           |
| Modifiers           | `startuptime-modifiers`           |
| Vim Options         | `startuptime-vim-options`         |
| Configuration       | `startuptime-configuration`       |
| Color Customization | `startuptime-color-customization` |

License
-------

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[dein]: https://github.com/Shougo/dein.vim
[neobundle]: https://github.com/Shougo/neobundle.vim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
