#ifndef MATRIX_CHMFACTOR_H
#define MATRIX_CHMFACTOR_H

#include "Mutils.h"
#include "chm_common.h"

SEXP CHMfactor_to_sparse(SEXP x);
SEXP CHMfactor_solve(SEXP a, SEXP b, SEXP type);
SEXP CHMfactor_spsolve(SEXP a, SEXP b, SEXP type);
SEXP CHMfactor_ldetL2(SEXP x);
double chm_factor_ldetL2(CHM_FR f);

#endif
