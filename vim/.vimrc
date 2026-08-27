"" ============================================================================
"" STANDALONE ENHANCED VIM CONFIGURATION
"" Theme: Gruvbox (Warm Yellow/Green palette for long sessions)
"" Includes: Auto-installing Plugin Manager (vim-plug), Navigation & Dev/Audit Tools
"" ============================================================================

"" --- Automatic Plugin Manager Setup (vim-plug) ---
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

"" --- Plugin Specifications ---
call plug#begin('~/.vim/plugged')

Plug 'morhetz/gruvbox'                  " Warm yellow/green/amber retro palette
Plug 'preservim/nerdtree'               " Tree file explorer
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } } " Fuzzy finder core binary
Plug 'junegunn/fzf.vim'                 " Fuzzy finder Vim bindings
Plug 'tpope/vim-commentary'             " Fast code commenting (gcc / gc)
Plug 'tpope/vim-surround'               " Parentheses, quotes & HTML tag wrapper
Plug 'airblade/vim-gitgutter'           " Real-time git status diff signs in gutter
Plug 'vim-airline/vim-airline'          " Custom statusline interface
Plug 'vim-airline/vim-airline-themes'   " Statusline themes matching Gruvbox

call plug#end()

"" --- General Settings ---
set nocompatible              " Disable legacy vi compatibility
syntax on                     " Enable syntax highlighting
filetype plugin indent on     " Enable filetype detection, plugins, and indent rules
set encoding=utf-8            " Standard internal encoding
set fileencodings=utf-8,latin1 " Fallback file encodings
set fileformats=unix,dos,mac  " Standard line endings
set hidden                    " Hide buffers when abandoned instead of unloading
set history=1000              " Increase undo/command history
set autoread                  " Reload files modified outside Vim automatically
set nobackup                  " Disable creation of backup files
set noswapfile                " Disable swap file creation (.swp)
set updatetime=300            " Faster redraws for gitgutter & diagnostics

"" --- UI & Visuals (Gruvbox Palette) ---
set number                    " Show line numbers
set relativenumber            " Show relative line numbers for quick jumping
set cursorline                " Highlight current line
set showcmd                   " Display incomplete commands in status bar
set showmode                  " Display current mode (INSERT, VISUAL, etc.)
set wildmenu                  " Enhanced command-line completion menu
set wildmode=list:longest,full " Tab completion settings for command line
set scrolloff=8               " Keep 8 lines visible above/below cursor when scrolling
set sidescrolloff=8           " Keep 8 columns visible left/right of cursor
set termguicolors             " Enable 24-bit RGB colors in terminal

" Gruvbox Configuration (Cálido, alto contraste, legible día y noche)
let g:gruvbox_contrast_dark = 'hard' " Hard contrast background
let g:gruvbox_termcolors = 256
" Gruvbox Configuration (Cálido, alto contraste, legible día y noche)
let g:gruvbox_contrast_dark = 'hard' " Hard contrast background
let g:gruvbox_termcolors = 256 

try
    colorscheme gruvbox
catch /^Vim\%((\a\+)\)\=:E185/
    colorscheme desert "Setting fallback theme while plugins are installing..."
endtry

set background=dark           " Set to 'light' if you prefer light mode during daylight

"" --- Search Settings ---
set ignorecase                " Ignore case in search patterns
set smartcase                 " Override ignorecase if search pattern contains uppercase
set hlsearch                  " Highlight search matches
set incsearch                 " Show search matches dynamically while typing

"" --- Indentation & Formatting ---
set expandtab                 " Convert tabs to spaces
set tabstop=4                 " Number of spaces a tab counts for
set shiftwidth=4              " Number of spaces used for autoindentation
set softtabstop=4             " Number of spaces inserted/deleted with Tab/Backspace
set autoindent                " Copy indent from current line when starting a new line
set smartindent               " Smart autoindenting for new lines
set wrap                      " Line wrap visually (without breaking actual lines)

"" --- Filetype Specific Indentation ---
augroup FileTypeOverrides
    autocmd!
    " Web Development & Configs: 2 spaces
    autocmd FileType html,css,scss,javascript,typescript,json,yaml,xml setlocal tabstop=2 shiftwidth=2 softtabstop=2
    " Scripting & Security Tools: 4 spaces
    autocmd FileType python,sh,bash,zsh,c,cpp setlocal tabstop=4 shiftwidth=4 softtabstop=4
augroup END

"" --- Security & Cleanup Helpers ---
augroup AutoStripWhitespace
    autocmd!
    " Automatically strip trailing whitespace on file save
    autocmd BufWritePre * %s/\s\+$//e
augroup END

"" --- Plugin Configurations ---
" Status Bar (Airline)
let g:airline_theme = 'gruvbox'
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'unique_tail'

" File Explorer (NERDTree)
let NERDTreeShowHidden = 1
let NERDTreeMinimalUI = 1

"" --- Keybindings & Improved Movement ---
let mapleader = " "           " Set Leader key to Space

" Fast save and quit
nnoremap <Leader>w :w<CR>
nnoremap <Leader>q :q<CR>

" Clear search highlights quickly with Space + h
nnoremap <Leader>h :noh<CR>

" File Explorer shortcuts
nnoremap <Leader>e :NERDTreeToggle<CR>
nnoremap <Leader>nf :NERDTreeFind<CR>

" Fuzzy Search shortcuts (FZF)
nnoremap <Leader>f :Files<CR>
nnoremap <Leader>b :Buffers<CR>
nnoremap <Leader>rg :Rg<CR>

" Centered Navigation (Keeps cursor in the middle when jumping half-pages or searching)
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv

" Split navigation using Ctrl + hjkl
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Resize split windows with arrow keys
nnoremap <Up> :resize +2<CR>
nnoremap <Down> :resize -2<CR>
nnoremap <Left> :vertical resize -2<CR>
nnoremap <Right> :vertical resize +2<CR>

" Buffer navigation
nnoremap <Leader>bn :bnext<CR>
nnoremap <Leader>bp :bprevious<CR>
nnoremap <Leader>bd :bdelete<CR>

" Move selected lines up/down in Visual mode with J / K
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Keep selection active when indenting visual blocks
vnoremap < <gv
vnoremap > >gv