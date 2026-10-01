" Portable, pluginless Vim profile.
" No plugin manager, curl download or first-start network action is performed.

set nocompatible
syntax enable
filetype plugin indent on
set encoding=utf-8
set hidden
set autoread
set history=1000
set updatetime=300
set timeoutlen=500

" Recovery-friendly state under XDG-ish user cache/state paths.
let s:vim_state = expand('~/.local/state/vim')
let s:vim_cache = expand('~/.cache/vim')
call mkdir(s:vim_state . '/undo', 'p')
call mkdir(s:vim_cache . '/swap', 'p')
call mkdir(s:vim_cache . '/backup', 'p')
if has('persistent_undo')
    let &undodir = s:vim_state . '/undo//'
    set undofile
endif
let &directory = s:vim_cache . '/swap//'
let &backupdir = s:vim_cache . '/backup//'
set backup
set writebackup

set number
set relativenumber
set cursorline
set showcmd
set wildmenu
set wildmode=list:longest,full
set scrolloff=6
set sidescrolloff=6
set splitbelow
set splitright
set signcolumn=yes
set laststatus=2
set background=dark
if has('termguicolors')
    set termguicolors
endif
silent! colorscheme desert

set ignorecase
set smartcase
set incsearch
set hlsearch
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set autoindent
set smartindent
set nowrap

if has('clipboard')
    set clipboard^=unnamedplus
endif

augroup DotfilesIndent
    autocmd!
    autocmd FileType html,css,scss,javascript,typescript,json,yaml,xml setlocal tabstop=2 shiftwidth=2 softtabstop=2
    autocmd FileType python,sh,bash,zsh,c,cpp,rust,go setlocal tabstop=4 shiftwidth=4 softtabstop=4
augroup END

let mapleader = " "
nnoremap <Leader>w :write<CR>
nnoremap <Leader>q :quit<CR>
nnoremap <silent> <Leader>h :nohlsearch<CR>
nnoremap <Leader>e :Lexplore<CR>
nnoremap <Leader>b :buffers<CR>:buffer<Space>
nnoremap <Leader>f :find<Space>
nnoremap Y y$
xnoremap <Leader>p "_dP
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv

" Built-in statusline: file, modified/read-only state, filetype, position.
set statusline=%f\ %m%r%h%w
set statusline+=%=
set statusline+=%y\ %l:%c\ %p%%
