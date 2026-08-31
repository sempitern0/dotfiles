"" ============================================================================
"" STANDALONE ENHANCED VIM CONFIGURATION
"" Theme: Gruvbox (Warm Yellow/Green palette for long sessions)
"" Optimized for: Keyboard-driven workflow, clean visuals & ergonomic movement
"" ============================================================================

"" --- Automatic Plugin Manager Setup (vim-plug) ---
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

"" --- Plugin Specifications ---
call plug#begin('~/.vim/plugged')

Plug 'morhetz/gruvbox'                 " Warm retro palette (eye-comfort)
Plug 'preservim/nerdtree'               " Tree file explorer
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } } " Fuzzy finder core binary
Plug 'junegunn/fzf.vim'                 " Fuzzy finder Vim bindings
Plug 'tpope/vim-commentary'             " Fast code commenting (gcc / gc)
Plug 'tpope/vim-surround'               " Parentheses, quotes & HTML tag wrapper
Plug 'airblade/vim-gitgutter'           " Real-time git status diff signs
Plug 'vim-airline/vim-airline'          " Custom statusline interface
Plug 'vim-airline/vim-airline-themes'   " Statusline themes matching Gruvbox

call plug#end()

"" --- General & Ergonomic Settings ---
set nocompatible              " Disable legacy vi compatibility
syntax on                     " Enable syntax highlighting
filetype plugin indent on     " Enable filetype detection, plugins, and indent rules
set encoding=utf-8            " Standard internal encoding
set fileencodings=utf-8,latin1 " Fallback file encodings
set fileformats=unix,dos,mac  " Standard line endings
set hidden                    " Switch buffers without saving
set history=1000              " Command history limit
set autoread                  " Reload files modified outside Vim automatically
set nobackup                  " Disable backup files
set noswapfile                " Disable swap files (.swp)
set updatetime=300            " Faster statusline & gitgutter updates
set timeoutlen=500            " Faster response time for leader keys

"" --- Persistent Undo (Undo history survives restarting Vim) ---
if has('persistent_undo')
    let myUndoDir = expand('~/.vim/undodir')
    call mkdir(myUndoDir, 'p')
    let &undodir = myUndoDir
    set undofile
endif

"" --- Clipboard Integration ---
" Sync Vim default register with OS system clipboard
if has('clipboard')
    set clipboard^=unnamed,unnamedplus
endif

"" --- Window Management ---
set splitbelow                " New horizontal splits open below
set splitright                " New vertical splits open to the right

"" --- UI & Visuals (Gruvbox Palette) ---
set number                    " Absolute line numbers
set cursorline                " Highlight current line
set showcmd                   " Display incomplete commands
set showmode                  " Display current mode
set wildmenu                  " Command-line completion menu
set wildmode=list:longest,full
set scrolloff=8               " Keep vertical padding when scrolling
set sidescrolloff=8           " Keep horizontal padding when scrolling
set termguicolors             " Enable 24-bit RGB colors
set signcolumn=yes            " Always show signcolumn to prevent layout shifts

" Gruvbox Configuration
let g:gruvbox_contrast_dark = 'hard'
let g:gruvbox_termcolors = 256

try
    colorscheme gruvbox
catch /^Vim\%((\a\+)\)\=:E185/
    colorscheme desert
endtry

set background=dark

"" --- Search Settings ---
set ignorecase                " Case-insensitive searching
set smartcase                 " Case-sensitive if pattern has uppercase letters
set hlsearch                  " Highlight search matches
set incsearch                 " Dynamic search matching while typing

"" --- Indentation & Formatting ---
set expandtab                 " Convert tabs to spaces
set tabstop=4                 " Spaces per tab
set shiftwidth=4              " Spaces for auto-indent
set softtabstop=4             " Tab key behavior in insert mode
set autoindent                " Copy indent from current line
set smartindent               " Smart auto-indenting
set wrap                      " Soft line wrapping

"" --- Filetype Specific Indentation ---
augroup FileTypeOverrides
    autocmd!
    " 2 Spaces for Web & Config formats
    autocmd FileType html,css,scss,javascript,typescript,json,yaml,xml setlocal tabstop=2 shiftwidth=2 softtabstop=2
    " 4 Spaces for Systems & Scripting
    autocmd FileType python,sh,bash,zsh,c,cpp setlocal tabstop=4 shiftwidth=4 softtabstop=4
augroup END

"" --- Automatic Whitespace Cleanup ---
augroup AutoStripWhitespace
    autocmd!
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

"" --- Keybindings & Keyboard-Driven Navigation ---
let mapleader = " "           " Space bar as Leader key

" Quick save and quit
nnoremap <Leader>w :w<CR>
nnoremap <Leader>q :q<CR>

" Clear search highlight
nnoremap <silent> <Leader>h :nohlsearch<CR>

" File Explorer
nnoremap <Leader>e :NERDTreeToggle<CR>
nnoremap <Leader>nf :NERDTreeFind<CR>

" Fuzzy Finder (FZF)
nnoremap <Leader>f :Files<CR>
nnoremap <Leader>b :Buffers<CR>
nnoremap <Leader>rg :Rg<CR>

" Intuitive Y behavior (yank to end of line, consistent with D and C)
nnoremap Y y$

" Keep paste register intact when pasting over visual selection
xnoremap <Leader>p "_dP

" Keep cursor centered during half-page navigation and search skips
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv

" Split window navigation using Ctrl + hjkl
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Resize split windows with Arrow keys
nnoremap <Up> :resize +2<CR>
nnoremap <Down> :resize -2<CR>
nnoremap <Left> :vertical resize -2<CR>
nnoremap <Right> :vertical resize +2<CR>

" Buffer switching
nnoremap <Leader>bn :bnext<CR>
nnoremap <Leader>bp :bprevious<CR>
nnoremap <Leader>bd :bdelete<CR>

" Move visual lines up/down with J / K
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Retain selection after visual shift indent
vnoremap < <gv
vnoremap > >gv