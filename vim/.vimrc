" Portable, pluginless Vim profile.
" No plugin manager, curl download or first-start network action is performed.

set nocompatible
syntax enable
filetype plugin indent on
set encoding=utf-8
set hidden
set autoread
set confirm
set history=1000
set updatetime=300
set timeoutlen=500

" Recovery-friendly state under user state/cache paths.
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

" Interface: absolute line numbers only. Relative numbers are intentionally off.
set number
set norelativenumber
set cursorline
if exists('+cursorlineopt')
    set cursorlineopt=line
endif
set showcmd
set showmode
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

" Project navigation without plugins.
set path+=**
set wildignore+=*/.git/*,*/node_modules/*,*/.venv/*,*/venv/*,*/dist/*,*/build/*

" Prefer ripgrep for :grep when available; Vim's grep fallback still works otherwise.
if executable('rg')
    set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ --glob\ !.git
    set grepformat=%f:%l:%c:%m
endif

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

" High-contrast visual layer. CursorLine uses a neutral background so syntax
" colours (yellow/green/red) keep their contrast instead of being washed out.
function! s:ApplyDotfilesHighlights() abort
    highlight CursorLine   guibg=#262626 ctermbg=235 gui=NONE cterm=NONE
    highlight CursorLineNr guifg=#fbf1c7 guibg=#3c3836 ctermfg=230 ctermbg=237 gui=bold cterm=bold
    highlight Visual       guifg=NONE guibg=#3b5368 ctermfg=NONE ctermbg=24 gui=NONE cterm=NONE
    highlight Search       guifg=#1d2021 guibg=#fabd2f ctermfg=234 ctermbg=214 gui=bold cterm=bold
    highlight IncSearch    guifg=#1d2021 guibg=#fe8019 ctermfg=234 ctermbg=208 gui=bold cterm=bold
    highlight MatchParen   guifg=#1d2021 guibg=#83a598 ctermfg=234 ctermbg=109 gui=bold cterm=bold
    highlight Pmenu        guifg=#ebdbb2 guibg=#32302f ctermfg=223 ctermbg=236
    highlight PmenuSel     guifg=#1d2021 guibg=#83a598 ctermfg=234 ctermbg=109 gui=bold cterm=bold
    highlight DiffAdd      guifg=#d5c4a1 guibg=#213321 ctermfg=187 ctermbg=22
    highlight DiffChange   guifg=#d5c4a1 guibg=#3a321f ctermfg=187 ctermbg=58
    highlight DiffDelete   guifg=#d5c4a1 guibg=#3a2020 ctermfg=187 ctermbg=52
    highlight DiffText     guifg=#fbf1c7 guibg=#50461f ctermfg=230 ctermbg=94 gui=bold cterm=bold
endfunction

augroup DotfilesVisuals
    autocmd!
    autocmd ColorScheme * call <SID>ApplyDotfilesHighlights()
    autocmd WinEnter,BufEnter * setlocal cursorline
    autocmd WinLeave * setlocal nocursorline
augroup END
call s:ApplyDotfilesHighlights()

augroup DotfilesIndent
    autocmd!
    autocmd FileType html,css,scss,javascript,typescript,json,yaml,xml setlocal tabstop=2 shiftwidth=2 softtabstop=2
    autocmd FileType python,sh,bash,zsh,c,cpp,rust,go setlocal tabstop=4 shiftwidth=4 softtabstop=4
augroup END

let mapleader = " "

" Save / quit / UI.
nnoremap <Leader>w :write<CR>
nnoremap <Leader>q :quit<CR>
nnoremap <silent> <Leader>h :nohlsearch<CR>

" Built-in file/project navigation.
nnoremap <Leader>e :Lexplore<CR>
nnoremap <Leader>f :find<Space>
nnoremap <Leader>g :grep!<Space>

" Buffers.
nnoremap <Leader>b :buffers<CR>:buffer<Space>
nnoremap <Leader>bn :bnext<CR>
nnoremap <Leader>bp :bprevious<CR>
nnoremap <Leader>bd :bdelete<CR>

" Splits.
nnoremap <Leader>sv :vsplit<CR>
nnoremap <Leader>sh :split<CR>
nnoremap <Leader>sc :close<CR>
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Quickfix navigation (:grep, :vimgrep, compiler output).
nnoremap <Leader>co :copen<CR>
nnoremap <Leader>cc :cclose<CR>
nnoremap <Leader>cn :cnext<CR>zz
nnoremap <Leader>cp :cprevious<CR>zz

" Editing ergonomics.
nnoremap Y y$
xnoremap <Leader>p "_dP
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz
nnoremap n nzzzv
nnoremap N Nzzzv

" Built-in statusline: file, modified/read-only state, filetype, position.
set statusline=%f\ %m%r%h%w
set statusline+=%=
set statusline+=%y\ %l:%c\ %p%%
