" ~/.vim/ftplugin/json.vim  (or ~/.config/nvim/ftplugin/json.vim)

" buffer-local maps only for JSON buffers
"nnoremap <silent><buffer> <Leader>fj  <Cmd>%!python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin), indent=2))'<CR>
"nnoremap <silent><buffer> <Leader>fcj <Cmd>%!python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin), separators=(",",":")))'<CR>
nnoremap <silent><buffer> <Leader>fj  <Cmd>%!python3 -m json.tool --indent 2 --no-ensure-ascii<CR>
nnoremap <silent><buffer> <Leader>fcj <Cmd>%!python3 -m json.tool --compact --no-ensure-ascii<CR>
xnoremap <silent><buffer> <Leader>fj  :'<,'>!python3 -m json.tool --indent 2 --no-ensure-ascii<CR>
xnoremap <silent><buffer> <Leader>fcj :'<,'>!python3 -m json.tool --compact --no-ensure-ascii<CR>
