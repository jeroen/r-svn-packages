/*
 *  R.app : a Cocoa front end to: "R A Computer Language for Statistical Data Analysis"
 *  
 *  R.app Copyright notes:
 *                     Copyright (C) 2004  The R Foundation
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
 */

#define R_GUI_VERSION_STR "1.01" /* it must be a string, but should parse to a valid real number */

#include <R.h>
#include <Rinternals.h>
#include "Rinit.h"
#include "Rcallbacks.h"
#include "IOStuff.h"
//#include <R_ext/Parse.h>
//#include <Parse.h>
#include <R_ext/eventloop.h>
#import <sys/types.h>

#import <Cocoa/Cocoa.h>
#import "History.h"
#import "ConnectionCache.h"

#define RToolbarIdentifier                       @"R Toolbar Identifier"
#define FontSizeToolbarItemIdentifier            @"Font Size Item Identifier"
#define NewEditWinToolbarItemIdentifier          @"New Edit Window Item Identifier"
#define SaveDocToolbarItemIdentifier             @"Save R ConsoleWindow Item Identifier"
#define	SourceRCodeToolbarIdentifier             @"Source/Load R Code Identifier"
#define	InterruptToolbarItemIdentifier 	         @"Interrupt Computation Item Identifier"
#define	NewQuartzToolbarItemIdentifier 	         @"New Quartz Device Item Identifier"
#define	LoadFileInEditorToolbarItemIdentifier 	 @"Load File in Editor Item Identifier"
#define	AuthenticationToolbarItemIdentifier 	 @"Authentication Item Identifier"
#define	ShowHistoryToolbarItemIdentifier 	     @"Show History Item Identifier"
#define	QuitRToolbarItemIdentifier 	             @"Quit R Item Identifier"
#define	X11ToolbarItemIdentifier 	             @"X11 Item Identifier"
#define	SetColorsToolbarItemIdentifier 	         @"SetColors Item Identifier"

#define backgColorKey @"Background Color"
#define inputColorKey @"Input Color"
#define outputColorKey @"Output Color"
#define stdoutColorKey @"Stdout Color"
#define stderrColorKey @"Stderr Color"
#define promptColorKey @"Prompt Color"
#define alphaValueKey  @"Alpha Value"
#define FontSizeKey    @"Console Font Size"
#define internalOrExternalKey  @"Use Internal Editor"
#define showSyntaxColoringKey  @"Show syntax coloring"
#define showBraceHighlightingKey  @"Show brace highlighting"
#define highlightIntervalKey  @"Highlight interval"
#define showLineNumbersKey  @"Show line numbers"
#define externalEditorNameKey  @"External Editor Name"
#define appOrCommandKey  @"Is it a .app or a command"
#define editOrSourceKey  @"Edit or source in file"
#define miscRAquaLibPathKey @"Append RAqua libs to R_LIBS"

#import "AMPreferenceWindowController.h"

/* Preference keys */

@interface RController : NSObject <REPLHandler, CocoaHandler>
{
	IBOutlet NSTextView *RTextView;
	IBOutlet NSProgressIndicator *progressWheel;
	IBOutlet NSTableView *historyView;			/* TableView for the package manager */ 
	IBOutlet NSTextField *WDirView;				/* Mini-TextField for the working directory */
	IBOutlet NSSearchField *helpSearch;			/* help search  field */
	IBOutlet NSButton *clearHistory;
	IBOutlet NSButton *loadHistory;
	IBOutlet NSButton *saveHistory;
    IBOutlet NSDrawer *HistoryDrawer;	
	IBOutlet NSWindow *RConsoleWindow;
	NSTimer *timer;
	NSTimer *RLtimer;
	NSTimer *Flushtimer;
	NSTimer *WDirtimer;
	History *hist;
	NSToolbar *toolbar;
	NSToolbarItem *toolbarStopItem;
	
    IBOutlet NSStepper *fontSizeStepper;
    IBOutlet NSTextField *fontSizeField;
    IBOutlet NSView *fontSizeView;
	
	unsigned committedLength; // any text before this position cannot be edited by the user
    unsigned promptPosition;  // the last prompt is positioned at this position
	unsigned outputPosition;  // any output (stdxx or consWrite) is to be place here, if -1 then the text can be appended
	
    int stdoutFD;
    int stderrFD;
	int rootFD;
	
	pid_t childPID;
	
    BOOL runSystemAsRoot;
	BOOL busyRFlag;
	
	float currentSize;
	float currentFontSize;
	float currentConsoleWidth;
	
	char *readConsTransBuffer; // transfer buffer returned by handeReadConsole
	int readConsTransBufferSize; // size of the above buffer
	
	id quartzPrefPane;
	id miscPrefPane;
	id colorsPrefPane;
	id editorPrefPane;
	
	NSColor *inputColor;
	NSColor *outputColor;
	NSColor *promptColor;
	NSColor *backgColor;
	NSColor *stderrColor;
	NSColor *stdoutColor;
	float alphaValue;
	
	BOOL doSyntaxColoring;
	BOOL doLineNumbers;
	BOOL doBraceHighlighting;
	double currentHighlightInterval;
	NSString *externalEditor;
	BOOL editorIsApp;
	BOOL useInternalEditor;
	BOOL openInEditor;
	
	NSMutableArray *consoleInputQueue;
	NSString *currentConsoleInput;
	
	BOOL forceStdFlush;
	
	char *writeBuffer;
	char *writeBufferPos;
	int  writeBufferLen;	
	
	AMPreferenceWindowController *prefsWindow;
	NSMutableDictionary *preferences;
	
}

- (IBAction)showPrefsWindow:(id)sender;

- (AMPreferenceWindowController *)prefsWindow;
- (void)setPrefsWindow:(AMPreferenceWindowController *)newPrefsWindow;

- (BOOL)shouldLoadPreferencePane:(NSString *)identifier;

- (void)willSelectPreferencePane:(NSString *)identifier;
- (void)didUnselectPreferencePane:(NSString *)identifier;

- (IBAction)sortByAlphabet:(id)sender;
- (IBAction)sortByCategory:(id)sender;

- (void) showWindow;

	/* process pending events. if blocking is set to YES then the method waits indefinitely for one event. otherwise only pending events are processed. */
- (void) doProcessEvents: (BOOL) blocking;

- (void) addChildProcess: (pid_t) pid;
- (void) rmChildProcess: (pid_t) pid;

- (void) setRootFlag: (BOOL) flag;
- (BOOL) getRootFlag;
- (void) setRootFD: (int) fd;

- (BOOL) textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
- (BOOL) textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString;

	/* write to the console bypassing any cache buffers - for internal use only! */
- (void) writeConsoleDirectly: (NSString*) text withColor: (NSColor*) color;

/* sendInput is an alias for "consoleInput: text interactive: YES" */
- (void) sendInput: (NSString*) text;

	/* replace the current console input with the "cmd" string. if "inter" is set to YES, then the input is immediatelly committed, otherwise it is only written to the input area, but not committed. Int tje interactive mode an optimization is made to not display the content before commit, because the lines are displayed as they are processed anyway. */
- (void) consoleInput: (NSString*) cmd interactive: (BOOL) inter;

- (IBAction)otherEventLoops:(id)sender;
- (IBAction)runRELP:(id)sender;
- (IBAction)flushconsole:(id)sender;

-(IBAction) fontSizeBigger:(id)sender;
-(IBAction) fontSizeSmaller:(id)sender;
-(IBAction) changeFontSize:(id)sender;

-(IBAction) getWorkingDir:(id)sender;
-(IBAction) resetWorkingDir:(id)sender;
-(IBAction) setWorkingDir:(id)sender;
-(IBAction) showWorkingDir:(id)sender;
-(IBAction) runX11:(id)sender;
-(IBAction) openColors:(id)sender;
-(IBAction) checkForUpdates:(id)sender;

- (int) numberOfRowsInTableView: (NSTableView *)tableView;
- (id) tableView: (NSTableView *)tableView
		objectValueForTableColumn: (NSTableColumn *)tableColumn
			 row: (int)row;

- (IBAction)doClearHistory:(id)sender;
- (IBAction)doLoadHistory:(id)sender;
- (IBAction)doSaveHistory:(id)sender;
- (IBAction)historyDoubleClick:(id)sender;

- (IBAction)newQuartzDevice:(id)sender;
- (IBAction)breakR:(id)sender;
- (IBAction)quitR:(id)sender;
- (IBAction)toggleHistory:(id)sender;
- (IBAction)toggleAuthentication:(id)sender;

- (IBAction)installFromBinary:(id)sender;
- (IBAction)installFromDir:(id)sender;
- (IBAction)installFromSource:(id)sender;

- (IBAction)togglePackageInstaller:(id)sender;

- (IBAction)newDocument:(id)sender;
- (IBAction)openDocument:(id)sender;

- (IBAction)loadWorkSpace:(id)sender;
- (IBAction)loadWorkSpaceFile:(id)sender;
- (IBAction)saveWorkSpace:(id)sender;
- (IBAction)saveWorkSpaceFile:(id)sender;
- (IBAction)clearWorkSpace:(id)sender;
- (IBAction)showWorkSpace:(id)sender;

- (IBAction)togglePackageManager:(id)sender;
- (IBAction)toggleDataManager:(id)sender;
- (IBAction)toggleWSBrowser:(id)sender;
- (IBAction)performHelpSearch:(id)sender;

- (IBAction)sourceFile:(id)sender;
- (IBAction)sourceOrLoadFile:(id)sender;

- (IBAction)makeConsoleKey:(id)sender;

- (void) shouldClearWS:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;

- (void) addConnectionLog;

- (void) writeLogsWithBytes: (char*) buf length: (int) len type: (int) outputType;
- (void) openHelpFor: (char*) topic;

- (void)setupToolbar;

- (int) isImageData:(NSString *)fname;
- (void) loadFile:(NSString *)fname;

- (void) RConsoleDidResize: (NSNotification *)notification;
- (void) setOptionWidth:(BOOL)force;
- (void) setOpenInEditor:(BOOL)flag;
- (BOOL) openInEditor;

- (IBAction) changeInputColor:(id)sender;
- (IBAction) changeOutputColor:(id)sender;
- (IBAction) changePromptColor:(id)sender;
- (IBAction) changeStdoutColor:(id)sender;
- (IBAction) changeStderrColor:(id)sender;
- (IBAction) changeBackGColor:(id)sender;
- (IBAction) changeAlphaColor:(id)sender;
- (IBAction) setDefaultColors:(id)sender;

- (void) setInputColor:(NSColor *)newColor;
- (void) setOutputColor:(NSColor *)newColor;
- (void) setPromptColor:(NSColor *)newColor;
- (void) setBackGColor:(NSColor *)newColor;
- (void) setStderrColor:(NSColor *)newColor;
- (void) setStdoutColor:(NSColor *)newColor;
- (void) setAlphaValue:(float)f;

- (void) setUseInternalEditor:(BOOL)flag;
- (BOOL) useInternalEditor;
- (void) setDoSyntaxColoring:(BOOL)flag;
- (BOOL) doSyntaxColoring;
- (void) setDoBraceHighlighting:(BOOL)flag;
- (BOOL) doBraceHighlighting;
- (void) setCurrentHighlightInterval:(NSString *)aString;
- (double) currentHighlightInterval;
- (void) setDoLineNumbers:(BOOL)flag;
- (BOOL) doLineNumbers;
- (void) setExternalEditor:(NSString *)name;
- (NSString *) externalEditor;
- (void) setEditorIsApp:(BOOL)flag;
- (BOOL) editorIsApp;

- (void) readDefaults;

+ (RController*) getRController;

- (void) flushROutput;
- (void) flushTimerHook: (NSTimer*) source; // hook for flush timer

- (void) handleWriteConsole: (NSString *)txt;
- (void) handleWritePrompt: (NSString *)prompt;
- (void) handleProcessEvents;
- (void) handleFlushConsole;
- (void) handleBusy: (BOOL)i;
- (int)  handleChooseFile: (char *)buf len:(int)len isNew:(int)isNew;	

- (NSFont*) currentFont;

- (void)setupPrefWindow;

- (NSTextView *)getRTextView;
- (NSWindow *)getRConsoleWindow;
@end

