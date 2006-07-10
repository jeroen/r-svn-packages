#include <stdio.h>
#include <string.h>

#define __SQLITE_WORKSPACE__
#include "sqlite_dataframe.h"

/* global variables */
sqlite3 *g_workspace = NULL;
char *g_sql_buf[NBUFS];
int g_sql_buf_sz[NBUFS];

/****************************************************************************
 * UTILITY FUNCTIONS
 ****************************************************************************/

/* test if a file is a sqlite database file */
sqlite3* _is_sqlitedb(char *filename) {
    sqlite3 *db;
    int res;
    res = sqlite3_open(filename, &db);
    if (res != SQLITE_OK) { goto is_sqlitedb_FAIL; }

    sqlite3_stmt *stmt; char *sql = "select * from sqlite_master";
    res = sqlite3_prepare(db, sql, -1, &stmt, 0);
    if (stmt != NULL) sqlite3_finalize(stmt);
    /*char **result_set;
    char nrow, ncol;
    res = sqlite3_get_table(db, "select * from sqlite_master limit 0", 
            &result_set, &nrow, &ncol, NULL);
    sqlite3_free_table(result_set);*/
    if (res != SQLITE_OK) goto is_sqlitedb_FAIL;

    return db;

is_sqlitedb_FAIL:
    sqlite3_close(db);
    return NULL;
}

/* test if a file is a SQLiteDF workspace */
sqlite3* _is_workspace(char *filename) {
    sqlite3* db = _is_sqlitedb(filename); 

    if (db != NULL) {
        sqlite3_stmt *stmt;
        char *sql = "select * from workspace";
        int res = sqlite3_prepare(db, sql, -1, &stmt, 0), ncols;
        if ((res != SQLITE_OK) || /* no workspace table */
              ((ncols = sqlite3_column_count(stmt)) != WORKSPACE_COLUMNS) ||
              /* below also checks the ordering of the columns */
              (strcmp(sqlite3_column_name(stmt, 0), "rel_filename") != 0) ||
              (strcmp(sqlite3_column_decltype(stmt, 0), "text") != 0) ||
              (strcmp(sqlite3_column_name(stmt, 1), "full_filename") != 0) ||
              (strcmp(sqlite3_column_decltype(stmt, 1), "text") != 0) ||
              (strcmp(sqlite3_column_name(stmt, 2), "internal_name") != 0) ||
              (strcmp(sqlite3_column_decltype(stmt, 2), "text") != 0)) {
            sqlite3_finalize(stmt); sqlite3_close(db); db = NULL;
        } else {
            sqlite3_finalize(stmt);
        }
    }

    return db;
}

/* test if a file is a sqlite.data.frame. returns the internal name of the
 * sdf if file is an sdf or NULL otherwise */
char * _is_sdf2(char *filename) {
    sqlite3* db = _is_sqlitedb(filename); 
    char *ret = (db == NULL) ? NULL : filename;

    if (ret) {
        sqlite3_stmt *stmt;
        char *sql = "select * from sdf_attributes where attr='name'";
        int res, ncols;
        res = sqlite3_prepare(db, sql, -1, &stmt, NULL);
        ret = (((res == SQLITE_OK) && /* no attribute table */
               ((ncols = sqlite3_column_count(stmt)) == 2) &&
               (strcmp(sqlite3_column_name(stmt, 0), "attr") == 0) &&
               (strcmp(sqlite3_column_decltype(stmt, 0), "text") == 0) &&
               (strcmp(sqlite3_column_name(stmt, 1), "value") == 0) &&
               (strcmp(sqlite3_column_decltype(stmt, 1), "text") == 0))) ? ret : NULL ;
        
        if (ret == NULL) goto _is_sdf_cleanup;

        /* get internal name */
        res = sqlite3_step(stmt);
        ret = (res == SQLITE_ROW) ? ret : NULL;
        if (ret == NULL) goto _is_sdf_cleanup;

        /* copy to buf2, because when we finalize stmt, we won't be sure
         * if sqlite3_column_text()'s ret value will still be there */
        strcpy(g_sql_buf[2], (char *)sqlite3_column_text(stmt, 1));
        ret = g_sql_buf[2];
        sqlite3_finalize(stmt);
        
        sql = "select * from sdf_data";
        res = sqlite3_prepare(db, sql, -1, &stmt, NULL);
        ret = (res == SQLITE_OK) ? ret : NULL;  /* if not, missing data table */

_is_sdf_cleanup:
        sqlite3_finalize(stmt);
        sqlite3_close(db);
    }

    return ret;
}

/* remove an sdf from the workspace */
void _delete_sdf2(char *iname) {
    sprintf(g_sql_buf[2], "delete from workspace where internal_name='%s';", iname);
    _sqlite_exec(g_sql_buf[2]);
}

/* add a sdf to the workspace */
int _add_sdf1(char *filename, char *internal_name) {
    sprintf(g_sql_buf[1], "insert into workspace(rel_filename, full_filename, internal_name) values('%s', '%s', '%s')",
            filename, _get_full_pathname2(filename), internal_name);
    return _sqlite_exec(g_sql_buf[1]);
}


static char* _get_sdf_detail2(char *iname, int what) {
    sqlite3_stmt *stmt;
    char * ret; int res;

    sprintf(g_sql_buf[2], "select full_filename from workspace where "
            "internal_name='%s'", iname);
    sqlite3_prepare(g_workspace, g_sql_buf[2], -1, &stmt, NULL);
    res = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (res == SQLITE_DONE) {
        ret = NULL;
    } else {
        ret = g_sql_buf[2];
        switch (what) {
            case SDF_DETAIL_EXISTS: 
                break; /* doesn't matter */
            case SDF_DETAIL_FULLFILENAME:
                strcpy(g_sql_buf[2], (char *)sqlite3_column_text(stmt, 0));
                break;
        }
    }

    return ret;
}

/* returns TRUE if sdf exists in the workspace */
int _sdf_exists2(char *iname) {
    return _get_sdf_detail2(iname, SDF_DETAIL_EXISTS) != NULL;
}

/****************************************************************************
 * WORKSPACE FUNCTIONS
 ****************************************************************************/

SEXP sdf_init_workspace() {
    int file_idx = 0, i;
    char *basename = "workspace", *filename;
    SEXP ret;

    /* initialize sql_buf */
    for (i = 0; i < NBUFS; i++) {
        if (g_sql_buf[i] == NULL) {
            g_sql_buf_sz[i] = 1024;
            g_sql_buf[i] = Calloc(g_sql_buf_sz[i], char);
        }
    }

    /*
     * check for workspace.db, workspace1.db, ..., workspace9999.db if they
     * are valid workspace file. if one is found, use that as the workspace.
     */
    filename = R_alloc(18, sizeof(char)); /* workspace10000.db\0 */
    sprintf(filename, "%s.db", basename);
    while(_file_exists(filename) && file_idx < 10000) {
        if ((g_workspace = _is_workspace(filename)) != NULL) break;
        /* warn("%s is not a workspace", filename) */
        sprintf(filename, "%s%d.db", basename, ++file_idx);
    }

    PROTECT(ret = NEW_LOGICAL(1));
    if ((g_workspace == NULL) && (file_idx < 10000)) {
        /* no workspace found but there are still "available" file name */
        /* if (file_idx) warn("workspace will be stored at #{filename}") */
        sqlite3_open(filename, &g_workspace);
        _sqlite_exec("create table workspace(rel_filename text, full_filename text, internal_name text)");
        LOGICAL(ret)[0] = TRUE;
    } else if (g_workspace != NULL) {
        /* a valid workspace has been found, load each of the tables */
        int res, nrows, ncols; 
        char **result_set, *fname, *iname;
        
        res = sqlite3_get_table(g_workspace, "select * from workspace", 
                &result_set, &nrows, &ncols, NULL);
        
        if (res == SQLITE_OK && nrows >= 1 && ncols == WORKSPACE_COLUMNS) {
            for (i = 1; i <= nrows; i++) {
                /* we will use rel_filename in opening the file, so that
                 * if the user is "sensible", files will be dir agnostic */
                fname = result_set[i*ncols]; iname = result_set[i*ncols+2];
                
                if (!_file_exists(fname)) {
                    Rprintf("Warning: SDF %s does not exist.\n", iname);
                    _delete_sdf2(iname);
                    continue;
                }

                if (_is_sdf2(fname) == NULL) {
                    Rprintf("Warning: %s is not a valid SDF.\n", fname);
                    _delete_sdf2(iname);
                    continue;
                }

                /* attach db */
                sprintf(g_sql_buf[0], "attach '%s' as %s", fname, iname);
                _sqlite_exec(g_sql_buf[0]);

                /* update full_filename */
                sprintf(g_sql_buf[0], "update workspace set full_filename='%s' where iname='%s'", _get_full_pathname2(fname), iname);
                _sqlite_exec(g_sql_buf[0]);
            }
        }
        sqlite3_free_table(result_set);

        LOGICAL(ret)[0] = TRUE;
    } else { /* can't find nor create workspace */
        LOGICAL(ret)[0] = FALSE;
    }

    UNPROTECT(1);

    /* register sqlite math functions */
    __register_vector_math();
    return ret;
}
        

    
SEXP sdf_finalize_workspace() {
    SEXP ret;
    PROTECT(ret = NEW_LOGICAL(1)); 
    LOGICAL(ret)[0] = (sqlite3_close(g_workspace) == SQLITE_OK);
    for (int i = 0; i < NBUFS; i++) Free(g_sql_buf[i]);
    UNPROTECT(1);
    return ret;
} 


SEXP sdf_list_sdfs(SEXP pattern) {
    SEXP ret;
    char **result;
    int nrow, ncol, res, i;

    if (TYPEOF(pattern) != STRSXP) {
        res = sqlite3_get_table(g_workspace, "select internal_name from workspace",
                &result, &nrow, &ncol, NULL);
    } else {
        /* since internal_names must be a valid r symbol, 
           did not check for "'" */
        sprintf(g_sql_buf[0], "select internal_name from workspace where "
                "internal_name like '%s%%'", CHAR(STRING_ELT(pattern, 0)));
        res = sqlite3_get_table(g_workspace, g_sql_buf[0], &result, &nrow,
                &ncol, NULL);
    }

    if (_sqlite_error(res)) return R_NilValue;
    PROTECT(ret = NEW_CHARACTER(nrow));
    
    for (i = 0; i < nrow; i++) SET_STRING_ELT(ret, i, mkChar(result[i+1]));

    sqlite3_free_table(result);
    UNPROTECT(1);
    return ret;
}

SEXP sdf_get_sdf(SEXP name) {    
    if (TYPEOF(name) != STRSXP) {
        Rprintf("Error: Argument must be a string containing the SDF name.\n");
        return R_NilValue;
    }

    char *iname = CHAR(STRING_ELT(name, 0));
    SEXP ret;
    sqlite3_stmt *stmt;
    int res;

    res = sqlite3_prepare(g_workspace, "select * from workspace where internal_name=?",
            -1, &stmt, NULL);
    if (_sqlite_error(res)) return R_NilValue;

    sqlite3_bind_text(stmt, 1, iname, strlen(iname), SQLITE_STATIC);
    res = sqlite3_step(stmt);

    if (res == SQLITE_ROW) ret = _create_sdf_sexp(iname);
    else { Rprintf("Error: SDF %s not found.\n", iname); ret = R_NilValue; }
    
    sqlite3_finalize(stmt);

    return ret;
}

SEXP sdf_attach_sdf(SEXP filename, SEXP internal_name) {
    /* when studying this, please be mindful of the global buffers used.
     * you have been warned */
    char *fname, *iname, *iname_orig;;
    int fnamelen, res;
    sqlite3_stmt *stmt;

    if (IS_CHARACTER(filename)) {
        fname = CHAR_ELT(filename, 0);
        fnamelen = strlen(fname);
    } else {
        Rprintf("Error: filename argument must be a string.\n");
        return R_NilValue;
    }

    if (strcmp(fname+(fnamelen-3),".db") != 0) {
        Rprintf("Error: Cannot attach because extension is not .db, which may cause problems [%s].\n");
        return R_NilValue;
    }

    /* check if it is a valid sdf file */
    if (_is_sdf2(fname) == NULL) {
        Rprintf("Error: %s is not a valid SDF.\n", fname);
        return R_NilValue;
    } else {
        /* _is_sdf2 puts the orig iname in buf2. transfer data to buf0 since
         * functions called below will use buf2 */
        strcpy(g_sql_buf[0], g_sql_buf[2]);
        iname_orig = g_sql_buf[0];
    }

    /* check if file to be attached exists in the workspace already */
    _get_full_pathname2(fname);
    res = sqlite3_prepare(g_workspace, "select internal_name from workspace where full_filename=?",
            -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, g_sql_buf[2], -1, SQLITE_STATIC);
    res = sqlite3_step(stmt);
    if (res == SQLITE_ROW) {
        Rprintf("Warning: That sdf is already attached as '%s'\n",
                sqlite3_column_text(stmt, 0));
        sqlite3_finalize(stmt);
        return R_NilValue;
    } else sqlite3_finalize(stmt);


    /* internal_name checking and processing. */
    if (IS_CHARACTER(internal_name)) {
        /* if name is specified, rename the sdf. original internal name is the
         * one stored at sdf_attribute */
        iname = CHAR_ELT(internal_name, 0);
        if (!_is_r_sym(iname)) {
            Rprintf("Error: %s is not a valid R symbol.\n", iname);
            return R_NilValue;
        }
    } else {
        /* if no name is specified, use original internal name */
        iname = (char *)iname_orig;  /* g_sql_buf[0]! */
    }

    /* check if internal name is already used in the workspace */
    res = sqlite3_prepare(g_workspace, "select full_filename from workspace "
           " where internal_name=?", -1, &stmt, NULL);
    sqlite3_bind_text(stmt, 1, iname, -1, SQLITE_STATIC);
    res = sqlite3_step(stmt);
    if (res == SQLITE_ROW) {
        Rprintf("Error: The sdf internal name '%s' is already used by file %s.\n",
                iname, sqlite3_column_text(stmt, 1));
        sqlite3_finalize(stmt);
        return R_NilValue;
    } 
    sqlite3_finalize(stmt);
    
    /* finally, attach it. */
    sprintf(g_sql_buf[1], "attach '%s' as [%s]", fname, iname);
    res = _sqlite_exec(g_sql_buf[1]);
    if (_sqlite_error(res)) return R_NilValue;

    /* if internal name found in newly-attached-SDF is the same as the
     * name wanted by the user, do nothing. otherwise, update sdf_attribute
     * on attached-SDF. this is like attachSdf then renameSdf */
    if (iname != iname_orig && strcmp(iname, iname_orig) != 0) {
        sprintf(g_sql_buf[1], "update [%s].sdf_attributes set value=? where attr='name'",
                iname);
        res = sqlite3_prepare(g_workspace, g_sql_buf[0], -1, &stmt, NULL);
        if (_sqlite_error(res)) { 
            sqlite3_finalize(stmt); 
            sprintf(g_sql_buf[1], "detach [%s]", iname);
            _sqlite_exec(g_sql_buf[1]);
            return R_NilValue;
        }
        res = sqlite3_bind_text(stmt, 1, iname, -1, SQLITE_STATIC);
        res = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    } 

    /* .. and update workspace */
    res = _add_sdf1(fname, iname);
    if (_sqlite_error(res)) return R_NilValue;

    return _create_sdf_sexp(iname);
}

SEXP sdf_detach_sdf(SEXP internal_name) {
    if (!IS_CHARACTER(internal_name)) {
        Rprintf("Error: iname argument is not a string.\n");
        return R_NilValue;
    }

    char *iname = CHAR_ELT(internal_name, 0);
    sprintf(g_sql_buf[0], "detach [%s]", iname);

    SEXP ret; int res;
    res = _sqlite_exec(g_sql_buf[0]);
    res = !_sqlite_error(res);

    if (res) _delete_sdf2(iname);

    PROTECT(ret = NEW_LOGICAL(1));
    LOGICAL(ret)[0] = res;
    UNPROTECT(1);

    return ret;
}

SEXP sdf_rename_sdf(SEXP sdf, SEXP name) {
    char *iname, *path, *newname;
    SEXP ret;
    int res, ret_tmp;

    iname = SDF_INAME(sdf);
    newname = CHAR_ELT(name, 0);
    
    /* check if valid r name */
    if (!_is_r_sym(newname)) {
        Rprintf("Error: %s is not a valid R symbol.", iname);
        return R_NilValue;
    }

    /* check if sdf already exists */
    if (_sdf_exists2(newname)) { /* name is already taken */
        Rprintf("Error: the name \"%s\" is already taken.\n", newname);
        return R_NilValue;
    }

    /* get path of the sdf file, because we're goint to detach it */
    path = _get_sdf_detail2(iname, SDF_DETAIL_FULLFILENAME);
    if (path == NULL) {
        Rprintf("Error: no sdf named \"%s\" exists.\n", iname);
        return R_NilValue;
    }

    /* change name in sdf_attribute */
    sprintf(g_sql_buf[0], "update [%s].sdf_attributes set value='%s' "
            "where attr='name'", iname, newname);
    res = _sqlite_exec(g_sql_buf[0]);
    Rprintf("result: %d\n", res);
    /* if (_sqlite_error(res)) return R_NilValue; */

    /* detach and remove sdf from workspace */
    sprintf(g_sql_buf[0], "detach '%s'", iname);
    res = _sqlite_exec(g_sql_buf[0]);
    ret_tmp = !_sqlite_error(res);

    /* remove from ws, attach and add again to ws using new name */
    if (ret_tmp) {
        _delete_sdf2(iname);
        sprintf(g_sql_buf[0], "attach '%s' as '%s'", path, newname);
        res = _sqlite_exec(g_sql_buf[0]);
        ret_tmp = !_sqlite_error(res);
        
        /* TODO: make path relative! */
        _add_sdf1(iname, path);
    }

    PROTECT(ret = NEW_LOGICAL(1));
    LOGICAL(ret)[0] = ret_tmp;
    UNPROTECT(1);

    return ret;
}

