/*
 *  R.app : a Cocoa front end to: "R A Computer Language for Statistical Data Analysis"
 *  
 *  R.app Copyright notes:
 *                     Copyright (C) 2004-5  The R Foundation
 *                     written by Stefano M. Iacus and Simon Urbanek
 *
 *                  
 *  R Copyright notes:
 *                     Copyright (C) 1995-1996   Robert Gentleman and Ross Ihaka
 *                     Copyright (C) 1998-2001   The R Development Core Team
 *                     Copyright (C) 2002-2004   The R Foundation
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  A copy of the GNU General Public License is available via WWW at
 *  http://www.gnu.org/copyleft/gpl.html.  You can also obtain it by
 *  writing to the Free Software Foundation, Inc., 59 Temple Place,
 *  Suite 330, Boston, MA  02111-1307  USA.
 *
 *  Created by Simon Urbanek on 12/5/04.
 */

#define backgColorKey @"Background Color"
#define inputColorKey @"Input Color"
#define outputColorKey @"Output Color"
#define stdoutColorKey @"Stdout Color"
#define stderrColorKey @"Stderr Color"
#define promptColorKey @"Prompt Color"
#define rootColorKey   @"Root Color"

#define normalRdSyntaxColorKey @"Normal RdSyntax Color"
#define sectionRdSyntaxColorKey @"Section RdSyntax Color"
#define macroArgRdSyntaxColorKey @"MacroArg RdSyntax Color"
#define macroGenRdSyntaxColorKey @"MacroGen RdSyntax Color"
#define commentRdSyntaxColorKey @"Comment RdSyntax Color"
#define directiveRdSyntaxColorKey @"Directive RdSyntax Color"

#define normalSyntaxColorKey @"Normal Syntax Color"
#define stringSyntaxColorKey @"String Syntax Color"
#define numberSyntaxColorKey @"Number Syntax Color"
#define keywordSyntaxColorKey @"Keyword Syntax Color"
#define commentSyntaxColorKey @"Comment Syntax Color"
#define identifierSyntaxColorKey @"Identifier Syntax Color"
#define editorCursorColorKey @"RScriptEditorCursorColor"
#define editorBackgroundColorKey @"RScriptEditorBackgroundColor"
#define editorCurrentLineBackgroundColorKey @"RScriptEditorHighlightCurrentLineColor"

#define initialWorkingDirectoryKey @"Working directory"
#define lastUsedFileEncoding @"LastUsedFileEncoding"
#define usedFileEncodings @"UsedFileEncodings"

#define FontSizeKey    @"Console Font Size"
#define RScriptEditorTabWidth    @"R Script Editor tab width"
#define RScriptEditorDefaultFont    @"R Script Editor default font"
#define RConsoleDefaultFont    @"R Console default font"
#define internalOrExternalKey  @"Use Internal Editor"
#define indentNewLines  @"RScriptEditorIndentNewLines"
#define highlightCurrentLine  @"RScriptEditorHighlightCurrentLine"
#define showSyntaxColoringKey  @"Show syntax coloring"
#define showBraceHighlightingKey  @"Show brace highlighting"
#define highlightIntervalKey  @"Highlight interval"
#define HighlightIntervalKey  @"RScriptBraceHighlightInterval"
#define showLineNumbersKey  @"Show line numbers"
#define externalEditorNameKey  @"External Editor Name"
#define appOrCommandKey  @"Is it a .app or a command"
#define editOrSourceKey  @"Edit or source in file"
#define miscRAquaLibPathKey @"Append RAqua libs to R_LIBS"
#define enableLineWrappingKey @"Enable line wrapping if TRUE"
#define lineFragmentPaddingWidthKey @"Line fragment padding in editor"
#define lineNumberGutterWidthKey @"Line number gutter width"
#define importOnStartupKey @"Import history file on startup if TRUE"
#define enforceInitialWorkingDirectoryKey @"Enforce initial wd on startup"
#define historyFileNamePathKey @"History file path used for R type history files"
#define maxHistoryEntriesKey @"Max number of history entries"
#define removeDuplicateHistoryEntriesKey @"Remove duplicate history entries"
#define cleanupHistoryEntriesKey @"Cleanup history entries"
#define stripCommentsFromHistoryEntriesKey @"Strip comment history entries"
#define defaultCRANmirrorURLKey @"default.CRAN.mirror.URL"
#define stopAskingAboutDefaultMirrorSavingKey @"default.CRAN.mirror.save.dontask"

#define useQuartzPrefPaneSettingsKey @"Use QuartzPrefPane values"
#define quartzPrefPaneWidthKey @"QuartzPrefPane width"
#define quartzPrefPaneHeightKey @"QuartzPrefPane height"
#define quartzPrefPaneDPIKey @"QuartzPrefPane DPI"
#define quartzPrefPaneLocationKey @"QuartzPrefPane location"
#define quartzPrefPaneLocationIntKey @"QuartzPrefPane location as an integer"
#define quartzPrefPaneFontKey @"QuartzPrefPane font"
#define quartzPrefPaneFontSizeKey @"QuartzPrefPane fontsize"

#define kEditorAutosaveKey @"autosave.scripts"

#define prefShowArgsHints @"Show function args hints"

#define saveOnExitKey @"save.on.exit"

#define kAutoCloseBrackets @"auto.close.parens"

#define kExternalHelp @"use.external.help"

// defaults

#define kDefaultHistoryFile @".Rapp.history"

// other constants

#define iBackgroundColor 0
#define iInputColor      1
#define iOutputColor     2
#define iPromptColor     3
#define iStderrColor     4
#define iStdoutColor     5
#define iRootColor       6
#define iErrorColor      iStderrColor
