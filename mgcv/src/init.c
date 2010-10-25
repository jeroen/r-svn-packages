/* Symbol registration initialization: original provided by Brian Ripley.
   Anything called from R should be registered here (and declared in mgcv.h).
   (See also NAMESPACE:1)
 */ 
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include "mgcv.h"


R_CMethodDef CEntries[] = {
    {"RMonoCon", (DL_FUNC) &RMonoCon, 7},
    {"RuniqueCombs", (DL_FUNC) &RuniqueCombs, 4},
    {"RPCLS", (DL_FUNC) &RPCLS, 14},
    {"mgcv", (DL_FUNC) &mgcv, 27},
    {"construct_tprs", (DL_FUNC) &construct_tprs, 13},
    {"construct_cr", (DL_FUNC) &construct_cr, 8},
    {"predict_tprs", (DL_FUNC) &predict_tprs, 12},
    {"MinimumSeparation", (DL_FUNC) &MinimumSeparation, 7},
    {"magic", (DL_FUNC) &magic, 18},
    {"mgcv_mmult", (DL_FUNC) &mgcv_mmult,8},
    {"gdi1",(DL_FUNC) &gdi1,45},
    {"R_cond",(DL_FUNC) &R_cond,5} ,
    {"pls_fit",(DL_FUNC)&pls_fit,10},
    {"pls_fit1",(DL_FUNC)&pls_fit1,11},
    {"tweedious",(DL_FUNC)&tweedious,8},
    {"psum",(DL_FUNC)&psum,4},
    {"get_detS2",(DL_FUNC)&get_detS2,12},
    {"get_stableS",(DL_FUNC)&get_stableS,14},
    {"mgcv_tri_diag",(DL_FUNC)&mgcv_tri_diag,3},
    {"mgcv_td_qy",(DL_FUNC)&mgcv_td_qy,7},
    {"rwMatrix",(DL_FUNC)&rwMatrix,6},
    {"in_out",(DL_FUNC)&in_out,8},
    {NULL, NULL, 0}
};

void R_init_mgcv(DllInfo *dll)
{
    R_registerRoutines(dll, CEntries, NULL, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
