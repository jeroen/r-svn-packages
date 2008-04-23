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
 *  Created by Stefano Iacus on 7/26/04.
 *  $Id$
 */

#import <Cocoa/Cocoa.h>
#import "RGUI.h"
#import "REngine/REngine.h"
#import "Preferences.h"
#import "PreferenceKeys.h"
#import "Quartz/QuartzDevice.h"
#import "RController.h"
#import "Rversion.h"

#import <ExceptionHandling/NSExceptionHandler.h>
#import "Tools/GlobalExHandler.h"

NSString *Rapp_R_version_short;
NSString *Rapp_R_version;

int main(int argc, const char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	if ([Preferences flagForKey:@"Debug all exceptions"] == YES) {
		// add an independent exception handler
		[[GlobalExHandler alloc] init]; // the init method also registers the handler
		[[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask: 1023]; // hang+log+handle all
	}

	Rapp_R_version_short = [[NSString alloc] initWithFormat:@"%d.%d", (R_VERSION >> 16), (R_VERSION >> 8)&255];
	Rapp_R_version = [[NSString alloc] initWithFormat:@"%s.%s", R_MAJOR, R_MINOR];
	
	[NSApplication sharedApplication];
	[NSBundle loadNibNamed:@"MainMenu" owner:NSApp];
	
	 SLog(@" - initalizing R");
	 if (![[REngine mainEngine] activate]) {
		 NSRunAlertPanel(NLS(@"Cannot start R"),[NSString stringWithFormat:NLS(@"Unable to start R: %@"), [[REngine mainEngine] lastError]],NLS(@"OK"),nil,nil);
		 exit(-1);
	 }
	 
#if R_VERSION < R_Version(2,7,0)
	 /* register Quartz symbols */
	 QuartzRegisterSymbols();
	 /* create quartz.save function in tools:quartz */
	 [[REngine mainEngine] executeString:@"try(local({e<-attach(NULL,name=\"tools:RGUI\"); assign(\"quartz.save\",function(file, type=\"png\", device=dev.cur(), ...) invisible(.Call(\"QuartzSaveContents\",device,file,type,list(...))),e)}))"];
#else
	/* in R 2.7.0 we use dev.copy to implement quartz.save */
	[[REngine mainEngine] executeString:@"try(local({e<-attach(NULL,name=\"tools:RGUI\"); assign(\"quartz.save\", function(file, type='png', device=dev.cur(), dpi=100, ...) {\n # modified version of dev.copy2pdf\n dev.set(device)\n current.device <- dev.cur()\n nm <- names(current.device)[1]\n if (nm == 'null device') stop('no device to print from')\n oc <- match.call()\n oc[[1]] <- as.name('dev.copy')\n oc$file <- NULL\n oc$device <- quartz\n oc$type <- type\n oc$file <- file\n oc$dpi <- dpi\n din <- dev.size('in')\n w <- din[1]\n h <- din[2]\n if (is.null(oc$width))\n oc$width <- if (!is.null(oc$height)) w/h * eval.parent(oc$height) else w\n if (is.null(oc$height))\n oc$height <- if (!is.null(oc$width)) h/w * eval.parent(oc$width) else h\n dev.off(eval.parent(oc))\n dev.set(current.device)\n},e); environment(e$quartz.save) <- e}))"];
#endif
	
	 SLog(@" - set R options");
	 // force html-help, because that's the only format we can handle ATM
	 [[REngine mainEngine] executeString: @"options(htmlhelp=TRUE)"];
	 
	 SLog(@" - set default CRAN mirror");
	 {
		 NSString *url = [Preferences stringForKey:defaultCRANmirrorURLKey withDefault:@""];
		 if (![url isEqualToString:@""])
			 [[REngine mainEngine] executeString:[NSString stringWithFormat:@"try(local({ r <- getOption('repos'); r['CRAN']<-gsub('/$', '', \"%@\"); options(repos = r) }),silent=TRUE)", url]];
	 }
	 
	 SLog(@" - set BioC repositories");
#if (R_VERSION < R_Version(2,3,0))
	 [[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=c('http://www.bioconductor.org/packages/bioc/stable','http://www.bioconductor.org/packages/data/annotation/stable','http://www.bioconductor.org/packages/data/experiment/stable'))"];
#elif (R_VERSION < R_Version(2,4,0))
	 [[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=paste('http://www.bioconductor.org/packages/',c('1.8/bioc','1.8/data/annotation','1.8/data/experiment','1.8/omegahat','1.8/lindsey'),sep=''))"];
#elif (R_VERSION < R_Version(2,5,0))
	 [[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=paste('http://www.bioconductor.org/packages/',c('1.9/bioc','1.9/data/annotation','1.9/data/experiment','1.9/omegahat'),sep=''))"];
#elif (R_VERSION < R_Version(2,6,0))
	 [[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=paste('http://www.bioconductor.org/packages/',c('2.0/bioc','2.0/data/annotation','2.0/data/experiment','2.0/extra'),sep=''))"];
#elif (R_VERSION < R_Version(2,7,0))
	 [[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=paste('http://www.bioconductor.org/packages/',c('2.1/bioc','2.1/data/annotation','2.1/data/experiment','2.1/extra'),sep=''))"];
#elif (R_VERSION < R_Version(2,8,0))
	 [[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=paste('http://www.bioconductor.org/packages/',c('2.2/bioc','2.2/data/annotation','2.2/data/experiment','2.2/extra'),sep=''))"];
#elif (R_VERSION < R_Version(2,9,0))
	[[REngine mainEngine] executeString:@"if (is.null(getOption('BioC.Repos'))) options('BioC.Repos'=paste('http://www.bioconductor.org/packages/',c('2.3/bioc','2.3/data/annotation','2.3/data/experiment','2.3/extra'),sep=''))"];
#else
#error "BioC repository is unknown, please add it to main.m or get more recent GUI sources"
#endif
	 SLog(@" - loading secondary NIBs");
	 if (![NSBundle loadNibNamed:@"Vignettes" owner:NSApp]) {
		 SLog(@" * unable to load Vignettes.nib!");
	 }

	 SLog(@"main: finish launching");
	 [NSApp finishLaunching];
 
	// torture
	[pool release];
	pool = [[NSAutoreleasePool alloc] init];

	 // ready to rock
	 SLog(@"main: entering REPL");
	 [[REngine mainEngine] runREPL];
	 
	 SLog(@"main: returned from REPL");
	 [pool release];
	 
	 SLog(@"main: exiting with status 0");
	 return 0;
}
