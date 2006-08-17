#include "R.h"
#include "Rdefines.h"
#include "Rinternals.h"
#include "sqlite3.h"

#ifndef __SQLITE_DATAFRAME__
#define __SQLITE_DATAFRAME__

#define WORKSPACE_COLUMNS 6
#ifndef WIN32
#define MAX_ATTACHED 30     /* 31 including workspace.db */
#else
#define MAX_ATTACHED 10     /* set to 10 until I have recompiled it to 30 */
#endif

/* utilities for checking characteristics of arg */
int _is_r_sym(char *sym);
int _file_exists(char *filename);
int _sdf_exists2(char *iname);

/* sdf utilities */
int USE_SDF1(const char *iname, int exists, int protect);  /* call this before doing anything on an SDF */
int UNUSE_SDF2(const char *iname); /* somewhat like UNPROTECT */
SEXP _create_sdf_sexp(const char *iname);  /* create a SEXP for an SDF */
int _add_sdf1(char *filename, char *internal_name); /* add SDF to workspace */
void _delete_sdf2(const char *iname); /* remove SDF from workspace */
int _get_factor_levels1(const char *iname, const char *varname, SEXP var);
int _get_row_count2(const char *table, int quote);
SEXP _get_rownames(const char *sdf_iname);
char *_get_full_pathname2(char *relpath); /* get full path given relpath, used in workspace mgmt */
int _is_factor2(const char *iname, const char *factor_type, const char *colname);
SEXP _get_rownames2(const char *sdf_iname);

/* utilities for creating SDF's */
char *_create_sdf_skeleton1(SEXP name, int *o_namelen, int protect);
int _copy_factor_levels2(const char *factor_type, const char *iname_src,
        const char *colname_src, const char *iname_dst, const char *colname_dst);
int _create_factor_table2(const char *iname, const char *factor_type, 
        const char *colname);
char *_create_svector1(SEXP name, const char *type, int * _namelen, int protect);

/* R utilities */
SEXP _getListElement(SEXP list, char *varname);
SEXP _shrink_vector(SEXP vec, int len); /* shrink vector size */

/* sqlite utilities */
int _empty_callback(void *data, int ncols, char **row, char **cols);
int _sqlite_error_check(int res, const char *file, int line);
const char *_get_column_type(const char *class, int type); /* get sqlite type corresponding to R class & type */
sqlite3* _is_sqlitedb(char *filename);

/* global buffer (g_sql_buf) utilities */
int _expand_buf(int i, int size);  /* expand ith buf if size > buf[i].size */


/* sqlite.vector utilities */
SEXP sdf_get_variable(SEXP sdf, SEXP name);
SEXP sdf_detach_sdf(SEXP internal_name);

/* workspace utilities */
int _prepare_attach2();  /* prepare workspace before attaching a sqlite db */

/* misc utilities */
char *_r2iname(char *internal_name, char *filename);
char *_fixname(char *rname);
char *_str_tolower(char *out, const char *ref);

/* register functions to sqlite */
void __register_vector_math();

#define _sqlite_exec(sql) sqlite3_exec(g_workspace, sql, _empty_callback, NULL, NULL)
#define _sqlite_error(res) _sqlite_error_check((res), __FILE__, __LINE__)

#ifdef __SQLITE_DEBUG__
#define _sqlite_begin  { _sqlite_error(_sqlite_exec("begin")); Rprintf("begin at "  __FILE__  " line %d\n",  __LINE__); }
#define _sqlite_commit  { _sqlite_error(_sqlite_exec("commit")); Rprintf("commit at "  __FILE__  " line %d\n",  __LINE__); }
#else
#define _sqlite_begin  _sqlite_error(_sqlite_exec("begin")) 
#define _sqlite_commit _sqlite_error(_sqlite_exec("commit"))
#endif

#ifndef SET_ROWNAMES
#define SET_ROWNAMES(x,n) setAttrib(x, R_RowNamesSymbol, n)
#endif

/* override R's, which does a GetRowNames which is different I believe */
#undef GET_ROWNAMES
#define GET_ROWNAMES(x) getAttrib(x, R_RowNamesSymbol)

/* R object accessors shortcuts */
#define CHAR_ELT(str, i) CHAR(STRING_ELT(str,i))

/* SDF object accessors shortcuts */
#define SDF_INAME(sdf) CHAR(STRING_ELT(_getListElement(sdf, "iname"),0))
#define SVEC_VARNAME(sdf) CHAR(STRING_ELT(_getListElement(sdf, "varname"),0))

/* # of sql buffers */
#define NBUFS 4

/* possible var types when stored in sqlite as integer */
#define VAR_INTEGER 0
#define VAR_FACTOR  1
#define VAR_ORDERED 2

/* detail constants (see _get_sdf_detail2 in sqlite_workspace.c) */
#define SDF_DETAIL_EXISTS 0
#define SDF_DETAIL_FULLFILENAME 1

/* R SXP type constants */
#define FACTORSXP 11
#define ORDEREDSXP 12

#ifndef __SQLITE_WORKSPACE__
extern sqlite3 *g_workspace;
extern char *g_sql_buf[NBUFS];
extern int g_sql_buf_sz[NBUFS];
#endif

#endif
