" Vim syntax file
" Language:     tforge Text::Forge, HTML with embedded Perl
" Maintainer:   Adam Monsen <adamm@wazamatta.com>
" URL:          http://text-forge.sourceforge.net
" Remark:       based on aasp.vim, syntax file for Apache::ASP code
" $Id: tforge.vim,v 1.3 2002/12/05 18:52:31 meonkeys Exp $

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

runtime! syntax/html.vim
unlet b:current_syntax
syn include @Perl syntax/perl.vim
syn cluster htmlPreproc add=tforgePerlInsideTags

syntax region tforgePerlInsideTags keepend matchgroup=Delimiter start=+<%[=$?]\=+ skip=+[^\\]".{-}[^\\]"+ end=+%>+ contains=@Perl

let b:current_syntax = "tforge"

" vim: ts=8 sw=8
