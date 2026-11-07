syntax on                  " цвета для кода
set number                 " номера строк: функция по Норме максимум 25 строк
set noexpandtab            " Tab остаётся настоящим символом Tab (так требует Норма)
set tabstop=4              " Tab выглядит шириной в 4 пробела
set shiftwidth=4           " автоотступ тоже 4
set autoindent             " новая строка начинается с того же отступа
set cindent                " отступы по правилам C
set list listchars=tab:-->,trail:·   " Tab виден как --->, пробелы в конце строки как ·
set colorcolumn=81         " линия на 81-й колонке: строка по Норме не длиннее 80
set cursorline             " подсвечивает строку, где курсор
set background=dark        " тёмный фон
colorscheme wildcharm        " спокойная тёмная тема

let g:user42 = 'boharuty'
let g:mail42 = 'boharuty@student.42yerevan.am'

" F5 — следующая тема
let s:themes = getcompletion('', 'color')
let s:i = 0
function! NextTheme()
	let s:i = (s:i + 1) % len(s:themes)
	execute 'colorscheme ' . s:themes[s:i]
	echo s:themes[s:i]
endfunction
nnoremap <F5> :call NextTheme()<CR>

autocmd FileType c syntax match cUserFunction "\<\h\w*\ze\s*("
autocmd FileType c highlight link cUserFunction Function

nnoremap <F2> :Stdheader<CR>
" F2 — вставить 42 header
"autocmd BufNewFile *.c,*.h Stdheader
" новый .c или .h файл сразу получает header

" свои цвета для скобок и точки с запятой
function! MyColors()
	highlight cBraces    ctermfg=214 guifg=#ffaf00
	highlight cParens    ctermfg=203 guifg=#5fd7ff
	highlight cSemicolon ctermfg=85 guifg=#ff5f5f
	highlight cInclude   ctermfg=12  guifg=#0000ff
	highlight cIncluded  ctermfg=20  guifg=#0000d7
	highlight SpecialKey ctermfg=6 guifg=#585858
	silent! source ~/.vim/mycolors.vim
	endfunction
call MyColors()
autocmd ColorScheme * call MyColors()

autocmd FileType c syntax match cBraces "[{}]"
autocmd FileType c syntax match cParens "[()]"
autocmd FileType c syntax match cSemicolon ";"
autocmd FileType c syntax match cComma ","

" отдельные группы для типов, чтобы красить каждый по-своему
autocmd FileType c syntax keyword cVoid void
autocmd FileType c syntax keyword cInt  int
autocmd FileType c syntax keyword cChar char

" F6 — перекрасить то, что под курсором, и запомнить
function! RecolorHere()
	let l:group = synIDattr(synID(line('.'), col('.'), 1), 'name')
	if l:group == ''
		echo 'Здесь нет подсветки'
		return
	endif
	let l:num = input(l:group . ' — номер цвета (0-255): ')
	if l:num == ''
		return
	endif
	let l:line = 'highlight ' . l:group . ' ctermfg=' . l:num
	execute l:line
	call writefile([l:line], expand('~/.vim/mycolors.vim'), 'a')
	redraw
	echo l:group . ' = ' . l:num
endfunction
nnoremap <F6> :call RecolorHere()<CR>
