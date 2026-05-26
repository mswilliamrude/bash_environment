syntax on
set background=dark
colorscheme desert
set tabstop=4 shiftwidth=4 expandtab
filetype plugin indent on
autocmd FileType json silent! %!python3 -m json.tool --indent 2 --no-ensure-ascii
autocmd FileType sh   setlocal shiftwidth=4 tabstop=4 expandtab
autocmd BufWritePre *.json %!python3 -m json.tool --compact  --no-ensure-ascii
