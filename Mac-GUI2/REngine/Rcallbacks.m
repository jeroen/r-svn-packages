/*
 *  R.app : a Cocoa front end to: "R A Computer Language for Statistical Data Analysis"
 *  
 *  R.app Copyright notes:
 *                     Copyright (C) 2005  The R Foundation
 *                     written by Stefano M. Iacus and Simon Urbanek
 *
 *                  
 *  R Copyright notes:
 *                     Copyright (C) 1995-1996   Robert Gentleman and Ross Ihaka
 *                     Copyright (C) 1998-2001   The R Development Core Team
 *                     Copyright (C) 2002-2005   The R Foundation
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
 *  Created by Simon Urbanek on Tue Jul 13 2004.
 *
 */

#include <R.h>
#include <Rdefines.h>
#include <Rinternals.h>
#include <Rversion.h>

#include <sys/select.h>
#include <unistd.h>
#include <stdio.h>

#include <R_ext/Boolean.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Parse.h>
#include <R_ext/eventloop.h>

#import "REngine.h"

/* any subsequent calls of ProcessEvents within the following time slice are ignored (in ms) */
#define MIN_DELAY_BETWEEN_EVENTS_MS   150

/* localization - we don't want to include GUI specific includes, so we define it manually */
#ifdef NLS
#undef NLS
#endif
#ifdef NLSC
#undef NLSC
#endif
#define NLS(S) NSLocalizedString(S,@"")
#define NLSC(S,C) NSLocalizedString(S,C)

#ifndef SLog
#if defined DEBUG_RGUI && defined PLAIN_STDERR
#define SLog(X,...) NSLog(X, ## __VA_ARGS__)
#else
#define SLog(X,...)
#endif
#endif

/* we have no access to config.h, so for the moment, let's disable i18n on C level - our files aren't even precessed by R anyway. */
#ifdef _
#undef _
#endif
#define _(A) (A)

int insideR = 0;

/* from Defn.h */
extern Rboolean R_Interactive;   /* TRUE during interactive use*/

extern FILE*    R_Consolefile;   /* Console output file */
extern FILE*    R_Outputfile;   /* Output file */

/* from src/unix/devUI.h */

extern void (*ptr_R_Suicide)(char *);
extern void (*ptr_R_ShowMessage)();
extern int  (*ptr_R_ReadConsole)(char *, unsigned char *, int, int);
extern void (*ptr_R_WriteConsole)(char *, int);
extern void (*ptr_R_ResetConsole)();
extern void (*ptr_do_flushconsole)();
extern void (*ptr_R_ClearerrConsole)();
extern void (*ptr_R_Busy)(int);
/* extern void (*ptr_R_CleanUp)(SA_TYPE, int, int); */
//extern int  (*ptr_R_ShowFiles)(int, char **, char **, char *, Rboolean, char *);
//extern int  (*ptr_R_EditFiles)(int, char **, char **, char *);
extern int  (*ptr_R_ChooseFile)(int, char *, int);
extern void (*ptr_R_loadhistory)(SEXP, SEXP, SEXP, SEXP);
extern void (*ptr_R_savehistory)(SEXP, SEXP, SEXP, SEXP);

//extern void (*ptr_R_StartCocoaRL)();

void Re_WritePrompt(char *prompt)
{
	NSString *s = [[NSString alloc] initWithUTF8String: prompt];
	insideR--;
    [[REngine mainHandler] handleWritePrompt:s];
	[s release];
	insideR++;
}

static long lastProcessEvents=0;

void Re_ProcessEvents(void){
	struct timeval rv;
	if (!gettimeofday(&rv,0)) {
		long curTime = (rv.tv_usec/1000)+(rv.tv_sec&0x1fffff)*1000;
		if (curTime - lastProcessEvents < MIN_DELAY_BETWEEN_EVENTS_MS) return;
	}
	if ([[REngine mainEngine] allowEvents]) // if events are masked, we won't call the handler. we may re-think what we do about the timer, though ...
		[[REngine mainHandler] handleProcessEvents];
	if (!gettimeofday(&rv,0)) // use the exit time for the measurement of next events - handleProcessEvents may take long
		lastProcessEvents = (rv.tv_usec/1000)+(rv.tv_sec&0x1fffff)*1000;
}

static char *readconsBuffer=0;
static char *readconsPos=0;

int Re_ReadConsole(char *prompt, unsigned char *buf, int len, int addtohistory)
{
	insideR--;
	Re_WritePrompt(prompt);

	if (!readconsBuffer) {
	    char *newc = [[REngine mainHandler] handleReadConsole: addtohistory];
	    if (!newc) {
			insideR++;
			return 0;
		}
		readconsPos=readconsBuffer=newc;
	}
		
	if (readconsBuffer) {
		int skipPC=0;
		char *c = readconsPos;
		while (*c && *c!='\n' && *c!='\r') c++;
		if (*c=='\r') { /* convert PC and Mac endings to unix */
			*c='\n';
			if (c[1]=='\n') skipPC=1;
		}
        if (*c) c++; /* if not at the end, point past the content to use */
        if (c-readconsPos>=len) c=readconsPos+(len-1);
        memcpy(buf, readconsPos, c-readconsPos);
		buf[c-readconsPos]=0;
        if (skipPC) c++;
		if (*c)
			readconsPos=c;
		else
			readconsPos=readconsBuffer=0;
		[[REngine mainHandler] handleProcessingInput: (char*) buf];
insideR=YES;
		return 1;
	}

    return 0;
}

void Re_RBusy(int which)
{
	insideR--;
    [[REngine mainHandler] handleBusy: (which==0)?NO:YES];
	insideR++;
}


void Re_WriteConsole(char *buf, int len)
{
	NSString *s = nil;
	if (buf[len]) { /* well, this is an ultima ratio, we are assuming null-terminated string, but one never knows ... */
		char *c = (char*) malloc(len+1);
		memcpy(c, buf, len);
		c[len]=0;
		s = [[NSString alloc] initWithUTF8String:c];
		free(c);
	} else s = [[NSString alloc] initWithUTF8String:buf];
    if (!s) {
		SLog(@"Rcallbacks:Re_WriteConsole: suspicious string of length %d doesn't parse as UTF8. Will use raw cString.", len);
		s = [[NSString alloc] initWithCString:buf length:len];
		SLog(@"Rcallbacks:Re_WriteConsole: string parsed as \"%@\"", s);
	}
    if (s) {
		[[REngine mainHandler] handleWriteConsole: s];
		[s release];
	}
}

/* Indicate that input is coming from the console */
void Re_ResetConsole()
{
}

/* Stdio support to ensure the console file buffer is flushed */
void Re_FlushConsole()
{
	insideR--;
	[[REngine mainHandler] handleFlushConsole];	
	insideR++;
}

/* Reset stdin if the user types EOF on the console. */
void Re_ClearerrConsole()
{
}

int Re_ChooseFile(int new, char *buf, int len)
{
	int r;
	insideR--;
	r=[[REngine mainHandler] handleChooseFile: buf len:len isNew:new];
	insideR++;
	return r;
}

void Re_ShowMessage(char *buf)
{
	insideR--;
	[[REngine mainHandler] handleShowMessage: buf];
	insideR++;
}

int  Re_Edit(char *file){
	int r;
	insideR--;
	r=[[REngine mainHandler] handleEdit: file];
	insideR++;
	return r;
}

int  Re_EditFiles(int nfile, char **file, char **wtitle, char *pager){
	int r;
	insideR--;
	r = [[REngine mainHandler] handleEditFiles: nfile withNames: file titles: wtitle pager: pager];
	insideR++;
	return r;
}

int Re_ShowFiles(int nfile, char **file, char **headers, char *wtitle, Rboolean del, char *pager)
{
	int r;
	insideR--;
	r = [[REngine mainHandler] handleShowFiles: nfile withNames: file headers: headers windowTitle: wtitle pager: pager andDelete: del];
	insideR++;
	return r;
}

//==================================================== the following callbacks are Cocoa-specific callbacks (see CocoaHandler)

#define checkArity(X,Y) /* is was removed from the API */

int Re_system(char *cmd) {
	int r;
	insideR--;
	if ([REngine cocoaHandler])
		r = [[REngine cocoaHandler] handleSystemCommand: cmd];
	else { // fallback in case there's no handler
		   // reset signal handlers
		signal(SIGINT, SIG_DFL);
		signal(SIGTERM, SIG_DFL);
		signal(SIGQUIT, SIG_DFL);
		signal(SIGALRM, SIG_DFL);
		signal(SIGCHLD, SIG_DFL);
		r = system(cmd);
	}
	insideR++;
	return r;
}

int  Re_CustomPrint(char *type, SEXP obj)
{
	insideR--;
	if ([REngine cocoaHandler]) {
		RSEXP *par = [[RSEXP alloc] initWithSEXP: obj];
		int res = [[REngine cocoaHandler] handleCustomPrint: type withObject: par];
		[par release];
		insideR++;
		return res;
	}
	insideR++;
	return -1;
}

SEXP Re_packagemanger(SEXP call, SEXP op, SEXP args, SEXP env)
{
	SEXP pkgname, pkgstatus, pkgdesc, pkgurl;
	char *vm;
	SEXP ans; 
	int i, len;
	
	const char **sName, **sDesc, **sURL;
	BOOL *bStat;
	
	checkArity(op, args);

	if (![REngine cocoaHandler]) return R_NilValue;
	
	vm = vmaxget();
	pkgstatus = CAR(args); args = CDR(args);
	pkgname = CAR(args); args = CDR(args);
	pkgdesc = CAR(args); args = CDR(args);
	pkgurl = CAR(args); args = CDR(args);
  
	if(!isString(pkgname) || !isLogical(pkgstatus) || !isString(pkgdesc) || !isString(pkgurl))
		errorcall(call, "invalid arguments");
   
	len = LENGTH(pkgname);
	if (len!=LENGTH(pkgstatus) || len!=LENGTH(pkgdesc) || len!=LENGTH(pkgurl))
		errorcall(call, "invalid arguments (length mismatch)");

	if (len==0) {
		insideR--;
		[[REngine cocoaHandler] handlePackages: 0 withNames: 0 descriptions: 0 URLs: 0 status: 0];
		insideR++;
		vmaxset(vm);
		return pkgstatus;
	}

	sName = (const char**) malloc(sizeof(char*)*len);
	sDesc = (const char**) malloc(sizeof(char*)*len);
	sURL  = (const char**) malloc(sizeof(char*)*len);
	bStat = (BOOL*) malloc(sizeof(BOOL)*len);

	i = 0; // we don't copy since the Obj-C side is responsible for making copies if necessary
	while (i<len) {
		sName[i] = CHAR(STRING_ELT(pkgname, i));
		sDesc[i] = CHAR(STRING_ELT(pkgdesc, i));
		sURL [i] = CHAR(STRING_ELT(pkgurl, i));
		bStat[i] = (BOOL)LOGICAL(pkgstatus)[i];
		i++;
	}
	insideR--;
	[[REngine cocoaHandler] handlePackages: len withNames: sName descriptions: sDesc URLs: sURL status: bStat];
	insideR++;
	free(sName); free(sDesc); free(sURL);
	
	PROTECT(ans = NEW_LOGICAL(len));
	for(i=0;i<len;i++)
		LOGICAL(ans)[i] = bStat[i];
	UNPROTECT(1);
	free(bStat);
	
	vmaxset(vm);
  	return ans;
}

SEXP Re_datamanger(SEXP call, SEXP op, SEXP args, SEXP env)
{
  SEXP  dsets, dpkg, ddesc, durl, ans;
  char *vm;
  int i, len;
  
  char **sName, **sDesc, **sURL, **sPkg;
  BOOL *res;

  checkArity(op, args);

  vm = vmaxget();
  dsets = CAR(args); args = CDR(args);
  dpkg = CAR(args); args = CDR(args);
  ddesc = CAR(args); args = CDR(args);
  durl = CAR(args);
  
  if (!isString(dsets) || !isString(dpkg) || !isString(ddesc)  || !isString(durl) )
	errorcall(call, "invalid arguments");

  len = LENGTH(dsets);
  if (LENGTH(dpkg)!=len || LENGTH(ddesc)!=len || LENGTH(durl)!=len)
	  errorcall(call, "invalid arguments (length mismatch)");
	  
  if (len==0) {
	  insideR--;
	  [[REngine cocoaHandler] handleDatasets: 0 withNames: 0 descriptions: 0 packages: 0 URLs: 0];
	  insideR++;
	  vmaxset(vm);
	  return R_NilValue;
  }

  sName = (char**) malloc(sizeof(char*)*len);
  sDesc = (char**) malloc(sizeof(char*)*len);
  sURL  = (char**) malloc(sizeof(char*)*len);
  sPkg  = (char**) malloc(sizeof(char*)*len);
  
  i = 0; // we don't copy since the Obj-C side is responsible for making copies if necessary
  while (i<len) {
	  sName[i] = CHAR(STRING_ELT(dsets, i));
	  sDesc[i] = CHAR(STRING_ELT(ddesc, i));
	  sURL [i] = CHAR(STRING_ELT(durl, i));
	  sPkg [i] = CHAR(STRING_ELT(dpkg, i));
	  i++;
  }

  insideR--;
  res = [[REngine cocoaHandler] handleDatasets: len withNames: sName descriptions: sDesc packages: sPkg URLs: sURL];
  insideR++;
  
  free(sName); free(sDesc); free(sPkg); free(sURL);
  
  if (res) {
	  PROTECT(ans=allocVector(LGLSXP, len));
	  i=0;
	  while (i<len) {
		  LOGICAL(ans)[i]=res[i];
		  i++;
	  }
	  UNPROTECT(1);
  } else {
	  // this should be the default:	  ans=R_NilValue;
	  // but until the R code is fixed to accept this, we have to fake a result
	  ans=allocVector(LGLSXP, 0);
  }
  
  vmaxset(vm);
  
  return ans;
}

SEXP Re_browsepkgs(SEXP call, SEXP op, SEXP args, SEXP env)
{
  char *vm;
  int i, len;
  SEXP rpkgs, rvers, ivers, wwwhere, install_dflt;

  char **sName, **sIVer, **sRVer;
  BOOL *bStat;

  checkArity(op, args);

  vm = vmaxget();
  rpkgs = CAR(args); args = CDR(args);
  rvers = CAR(args); args = CDR(args);
  ivers = CAR(args); args = CDR(args);
  wwwhere = CAR(args); args=CDR(args);
  install_dflt = CAR(args); 
  
  if(!isString(rpkgs) || !isString(rvers) || !isString(ivers) || !isString(wwwhere) || !isLogical(install_dflt))
	  errorcall(call, "invalid arguments");

  len = LENGTH(rpkgs);
  if (LENGTH(rvers)!=len || LENGTH(ivers)!=len || LENGTH(wwwhere)<1 || LENGTH(install_dflt)!=len)
	  errorcall(call, "invalid arguments (length mismatch)");
	  
  if (len==0) {
	  insideR--;
	  [[REngine cocoaHandler] handleInstalledPackages: 0 withNames: 0 installedVersions: 0 repositoryVersions: 0 update: 0 label: 0];
	  insideR++;
	  vmaxset(vm);
	  return R_NilValue;
  }
  
  sName = (char**) malloc(sizeof(char*)*len);
  sIVer = (char**) malloc(sizeof(char*)*len);
  sRVer = (char**) malloc(sizeof(char*)*len);
  bStat = (BOOL*) malloc(sizeof(BOOL)*len);
  
  i = 0; // we don't copy since the Obj-C side is responsible for making copies if necessary
  while (i<len) {
	  sName[i] = CHAR(STRING_ELT(rpkgs, i));
	  sIVer[i] = CHAR(STRING_ELT(ivers, i));
	  sRVer[i] = CHAR(STRING_ELT(rvers, i));
	  bStat[i] = (BOOL)LOGICAL(install_dflt)[i];
	  i++;
  }
  
  insideR--;
  [[REngine cocoaHandler] handleInstalledPackages: len withNames: sName installedVersions: sIVer repositoryVersions: sRVer update: bStat label:CHAR(STRING_ELT(wwwhere,0))];
  insideR++;
  free(sName); free(sIVer); free(sRVer); free(bStat);
    
  vmaxset(vm);
  return allocVector(LGLSXP, 0);
}

SEXP Re_do_hsbrowser(SEXP call, SEXP op, SEXP args, SEXP env)
{
	char *vm;
	SEXP ans; 
	int i, len;
	SEXP h_topic, h_pkg, h_desc, h_wtitle, h_url;
	char **sTopic, **sDesc, **sPkg, **sURL;
	
	checkArity(op, args);
	
	vm = vmaxget();
	h_topic = CAR(args); args = CDR(args);
	h_pkg = CAR(args); args = CDR(args);
	h_desc = CAR(args); args = CDR(args);
	h_wtitle = CAR(args); args = CDR(args);
	h_url = CAR(args); 
	
	if(!isString(h_topic) | !isString(h_pkg) | !isString(h_desc) )
		errorcall(call, "invalid arguments");
	
	len = LENGTH(h_topic);
	if (LENGTH(h_pkg)!=len || LENGTH(h_desc)!=len || LENGTH(h_wtitle)<1 || LENGTH(h_url)!=len)
		errorcall(call, "invalid arguments (length mismatch)");
	
	if (len==0) {
		insideR--;
		[[REngine cocoaHandler] handleHelpSearch: 0 withTopics: 0 packages: 0 descriptions: 0 urls: 0 title: 0];
		insideR++;
		vmaxset(vm);
		return R_NilValue;
	}
	
	sTopic = (char**) malloc(sizeof(char*)*len);
	sDesc = (char**) malloc(sizeof(char*)*len);
	sPkg = (char**) malloc(sizeof(char*)*len);
	sURL = (char**) malloc(sizeof(char*)*len);
	
	i = 0; // we don't copy since the Obj-C side is responsible for making copies if necessary
	while (i<len) {
		sTopic[i] = CHAR(STRING_ELT(h_topic, i));
		sDesc[i]  = CHAR(STRING_ELT(h_desc, i));
		sPkg[i]   = CHAR(STRING_ELT(h_pkg, i));
		sURL[i]   = CHAR(STRING_ELT(h_url, i));
		i++;
	}
	
	insideR--;
	[[REngine cocoaHandler] handleHelpSearch: len withTopics: sTopic packages: sPkg descriptions: sDesc urls: sURL title:CHAR(STRING_ELT(h_wtitle,0))];
	insideR++;
	free(sTopic); free(sDesc); free(sPkg); free(sURL);
	
	PROTECT(ans = NEW_LOGICAL(len));
	for(i=0;i<len;i++)
		LOGICAL(ans)[i] = 0;
	
	vmaxset(vm);  
	UNPROTECT(1);
	
	return ans;
}

SEXP Re_do_selectlist(SEXP call, SEXP op, SEXP args, SEXP rho)
{
    SEXP list, preselect, ans = R_NilValue;
    char **clist;
    int i, j = -1, n,  multiple, nsel = 0;
	Rboolean haveTitle;
	BOOL *itemStatus = 0;
	int selectListDone = 0;
	
    checkArity(op, args);
    list = CAR(args);
    if(!isString(list)) Rf_error(_("invalid 'list' argument"));
    preselect = CADR(args);
    if(!isNull(preselect) && !isString(preselect))
		Rf_error(_("invalid 'preselect' argument"));
    multiple = asLogical(CADDR(args));
    if(multiple == NA_LOGICAL) multiple = 0;
    haveTitle = isString(CADDDR(args));
    if(!multiple && isString(preselect) && LENGTH(preselect) != 1)
		Rf_error(_("invalid 'preselect' argument"));
	
    n = LENGTH(list);
    clist = (char **) R_alloc(n + 1, sizeof(char *));
    itemStatus = (BOOL *) R_alloc(n + 1, sizeof(BOOL));
    for(i = 0; i < n; i++) {
		clist[i] = CHAR(STRING_ELT(list, i));
		itemStatus[i] = NO;
    }
    clist[n] = NULL;
	
    if(!isNull(preselect) && LENGTH(preselect)) {
		for(i = 0; i < n; i++)
			for(j = 0; j < LENGTH(preselect); j++)
				if(strcmp(clist[i], CHAR(STRING_ELT(preselect, j))) == 0) {
					itemStatus[i] = YES;
					break;
				};
    }
	
	insideR--;
	if (n==0)
		selectListDone = [[REngine cocoaHandler] handleListItems: 0 withNames: 0 status: 0 multiple: 0 title: @""];
	else
		selectListDone = [[REngine cocoaHandler] handleListItems: n withNames: clist status: itemStatus multiple: multiple
														   title: haveTitle
			?[NSString stringWithUTF8String: CHAR(STRING_ELT(CADDDR(args), 0))]
			:(multiple ? NLS(@"Select one or more") : NLS(@"Select one")) ];
	insideR++;
	
	if (selectListDone == 1) { /* Finish */
		for(i = 0; i < n; i++)  if(itemStatus[i]) nsel++;
		PROTECT(ans = allocVector(STRSXP, nsel));
		for(i = 0, j = 0; i < n; i++)
			if(itemStatus[i])
				SET_STRING_ELT(ans, j++, mkChar(clist[i]));
	} else { /* cancel */
		PROTECT(ans = allocVector(STRSXP, 0));
	}

    UNPROTECT(1);
    return ans;
}


//==================================================== the following callbacks need to be moved!!! (TODO)

SEXP Re_do_wsbrowser(SEXP call, SEXP op, SEXP args, SEXP env)
{
	int len;
	SEXP ids, isroot, iscont, numofit, parid;
	SEXP name, type, objsize;
	char *vm;
   
	/* checkArity(op, args); */

	vm = vmaxget();
	ids = CAR(args); args = CDR(args);
	isroot = CAR(args); args = CDR(args);
	iscont = CAR(args); args = CDR(args);
	numofit = CAR(args); args = CDR(args);
	parid = CAR(args); args = CDR(args);
	name = CAR(args); args = CDR(args);
	type = CAR(args); args = CDR(args);
	objsize = CAR(args); 

	if(!isInteger(ids)) 
		errorcall(call,"`id' must be integer");      
	if(!isString(name))
		errorcall(call, "invalid objects' name");
	if(!isString(type))
		errorcall(call, "invalid objects' type");
	if(!isString(objsize))
		errorcall(call, "invalid objects' size");
	if(!isLogical(isroot))
		errorcall(call, "invalid `isroot' definition");
	if(!isLogical(iscont))
		errorcall(call, "invalid `iscont' definition");
	if(!isInteger(numofit))
		errorcall(call,"`numofit' must be integer");
	if(!isInteger(parid))
		errorcall(call,"`parid' must be integer");
  
    len = LENGTH(ids);

	/*
	if(len>0){
		WeHaveWorkspace = YES;
		NumOfWSObjects = freeWorkspaceList(len);		
  
		for(i=0; i<NumOfWSObjects; i++){

		if (!isNull(STRING_ELT(name, i)))
			ws_name[i] = strdup(CHAR(STRING_ELT(name, i)));
		else
			ws_name[i] = strdup(CHAR(R_BlankString));

		if (!isNull(STRING_ELT(type, i)))
			ws_type[i] = strdup(CHAR(STRING_ELT(type, i)));
		else
			ws_type[i] = strdup(CHAR(R_BlankString));

		if (!isNull(STRING_ELT(objsize, i)))
			ws_size[i] = strdup(CHAR(STRING_ELT(objsize, i)));
		else
			ws_size[i] = strdup(CHAR(R_BlankString));  

		ws_IDNum[i] = INTEGER(ids)[i];
		ws_numOfItems[i] = INTEGER(numofit)[i];
		if(INTEGER(parid)[i] == -1)
			ws_parID[i] = -1;
		else 
			ws_parID[i] = INTEGER(parid)[i]; 
		ws_IsRoot[i] = LOGICAL(isroot)[i];
		ws_IsContainer[i] = LOGICAL(iscont)[i];
	 }
	 }

	insideR--;
	[WSBrowser toggleWorkspaceBrowser];
	insideR++;
	*/
	vmaxset(vm);

  return R_NilValue;
}

SEXP Re_dataentry(SEXP call, SEXP op, SEXP args, SEXP rho)
{
    SEXP colmodes, tnames, tvec, tvec2, work2;
    SEXPTYPE type;
    int i, j, cnt, len;
    char clab[25];

#if 0	
    nprotect = 0;/* count the PROTECT()s */
    PROTECT_WITH_INDEX(work = duplicate(CAR(args)), &wpi); nprotect++;
    colmodes = CADR(args);
    tnames = getAttrib(work, R_NamesSymbol);

    if (TYPEOF(work) != VECSXP || TYPEOF(colmodes) != VECSXP)
	errorcall(call, "invalid argument");

    /* initialize the constants */

    ssNA_REAL = -NA_REAL;
    tvec = allocVector(REALSXP, 1);
    REAL(tvec)[0] = ssNA_REAL;
    PROTECT(ssNA_STRING = coerceVector(tvec, STRSXP)); nprotect++;
    
    /* setup work, names, lens  */
    xmaxused = length(work); ymaxused = 0;
    PROTECT_WITH_INDEX(lens = allocVector(INTSXP, xmaxused), &lpi);
    nprotect++;

    if (isNull(tnames)) {
		PROTECT_WITH_INDEX(names = allocVector(STRSXP, xmaxused), &npi);
		for(i = 0; i < xmaxused; i++) {
			sprintf(clab, "var%d", i);
			SET_STRING_ELT(names, i, mkChar(clab));
		}
    } else 
		PROTECT_WITH_INDEX(names = duplicate(tnames), &npi);
    nprotect++;

    for (i = 0; i < xmaxused; i++) {
	int len = LENGTH(VECTOR_ELT(work, i));
	INTEGER(lens)[i] = len;
	ymaxused = max(len, ymaxused);
        type = TYPEOF(VECTOR_ELT(work, i));
    if (LENGTH(colmodes) > 0 && !isNull(VECTOR_ELT(colmodes, i)))
	    type = str2type(CHAR(STRING_ELT(VECTOR_ELT(colmodes, i), 0)));
	if (type != STRSXP) type = REALSXP;
	if (isNull(VECTOR_ELT(work, i))) {
	    if (type == NILSXP) type = REALSXP;
	    SET_VECTOR_ELT(work, i, ssNewVector(type, 100));
	} else if (!isVector(VECTOR_ELT(work, i)))
	    errorcall(call, "invalid type for value");
	else {
	    if (TYPEOF(VECTOR_ELT(work, i)) != type)
		SET_VECTOR_ELT(work, i, 
			       coerceVector(VECTOR_ELT(work, i), type));
	}
    }


    /* start up the window, more initializing in here */

	IsDataEntry = YES;
	insideR--;
	[REditor startDataEntry];
	insideR++;
	IsDataEntry = NO;

	/* drop out unused columns */
    for(i = 0, cnt = 0; i < xmaxused; i++)
	if(!isNull(VECTOR_ELT(work, i))) cnt++;
    if (cnt < xmaxused) {
	PROTECT(work2 = allocVector(VECSXP, cnt)); nprotect++;
	for(i = 0, j = 0; i < xmaxused; i++) {
	    if(!isNull(VECTOR_ELT(work, i))) {
		SET_VECTOR_ELT(work2, j, VECTOR_ELT(work, i));
		INTEGER(lens)[j] = INTEGER(lens)[i];
		SET_STRING_ELT(names, j, STRING_ELT(names, i));
		j++;
	    }
	}
	REPROTECT(names = lengthgets(names, cnt), npi);
    } else work2 = work;

    for (i = 0; i < LENGTH(work2); i++) {
	len = INTEGER(lens)[i];
	tvec = VECTOR_ELT(work2, i);
	if (LENGTH(tvec) != len) {
	    tvec2 = ssNewVector(TYPEOF(tvec), len);
	    for (j = 0; j < len; j++) {
		if (TYPEOF(tvec) == REALSXP) {
		    if (REAL(tvec)[j] != ssNA_REAL)
			REAL(tvec2)[j] = REAL(tvec)[j];
		    else
			REAL(tvec2)[j] = NA_REAL;
		} else if (TYPEOF(tvec) == STRSXP) {
		    if (!streql(CHAR(STRING_ELT(tvec, j)),
				CHAR(STRING_ELT(ssNA_STRING, 0))))
			SET_STRING_ELT(tvec2, j, STRING_ELT(tvec, j));
		    else
			SET_STRING_ELT(tvec2, j, NA_STRING);
		} else
		    Rf_error("dataentry: internal memory problem");
	    }
	    SET_VECTOR_ELT(work2, i, tvec2);
	}
    }

    setAttrib(work2, R_NamesSymbol, names);    
    UNPROTECT(nprotect);

    return work2;
#endif
	return R_NilValue;
}
