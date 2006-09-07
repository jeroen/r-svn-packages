#include "HBMM.h"
#include "iohb.h"
#include "mmio.h"

SEXP Matrix_writeHarwellBoeing(SEXP obj, SEXP file, SEXP typep)
{
    char *type = CHAR(asChar(typep)), Type[4] = "RUA";
    int *dims = INTEGER(GET_SLOT(obj, Matrix_DimSym)),
	*ii = (int *) NULL, *pp = (int *) NULL;
    int M = dims[0], N = dims[1], nz = -1;
    double *xx = (double *) NULL;

    if (type[2] == 'C' || type[2] == 'T') {
	SEXP islot = GET_SLOT(obj, Matrix_iSym);
	nz = LENGTH(islot);
	ii = INTEGER(islot);
	if (type[2] == 'T') {	/* create column pointers */
	    int *i1 = Calloc(nz, int);
	    double *x1 = Calloc(nz, double);

	    pp = Calloc(N + 1, int);
	    triplet_to_col(M, N, nz, ii,
			   INTEGER(GET_SLOT(obj, Matrix_jSym)), xx,
			   pp, i1, x1);
	    nz = pp[N];
	    xx = x1;
	    ii = i1;
	} else pp = INTEGER(GET_SLOT(obj, Matrix_pSym));
    } else error("Only types 'C' and 'T' allowed");

    if (type[0] == 'D') {
	xx = REAL(GET_SLOT(obj, Matrix_xSym));
    } else error("Only real matrices allowed");

    if (!isString(file))
	error("non-string values for file not presently accepted");

    if (type[1] == 'S') {
	if (*uplo_P(obj) != 'L')
	    error("Symmetric matrices must be stored in lower triangle");
	Type[1] = 'S';
    }

    writeHB_mat_double(CHAR(asChar(file)), M, N, nz, pp, ii, xx, 0,
		       (double *)NULL, (double *)NULL, (double *)NULL,
		       "", "", Type, (char*)NULL, (char*)NULL,
		       (char*)NULL, (char*)NULL, "RUA");

    if (type[2] == 'T') {Free(ii); Free(pp); Free(xx);}
    return R_NilValue;
}

SEXP Matrix_writeMatrixMarket(SEXP obj, SEXP file, SEXP typep)
{
    char *type = CHAR(asChar(typep));
    int *dims = INTEGER(GET_SLOT(obj, Matrix_DimSym)),
	*ii = (int *) NULL, *jj = (int *) NULL;
    int M = dims[0], N = dims[1], nz = -1;
    MM_typecode matcode;
    double *xx = (double *) NULL;

    mm_set_matrix(&matcode);
    if (type[2] == 'C' || type[2] == 'T') {
	SEXP islot = GET_SLOT(obj, Matrix_iSym);
	nz = LENGTH(islot);
	ii = INTEGER(islot);
	mm_set_coordinate(&matcode);
    } else error("Only types 'C' and 'T' allowed");

    if (type[0] == 'D') {
	xx = REAL(GET_SLOT(obj, Matrix_xSym));
	mm_set_real(&matcode);
    } else error("Only real matrices allowed");

    if (!isString(file))
	error("non-string values for file not currently allowed");

    if (type[1] == 'S') {
	if (*uplo_P(obj) != 'L')
	    error("Symmetric matrices must be stored in lower triangle");
	mm_set_symmetric(&matcode);
    }
    if (type[1] == 'G') mm_set_general(&matcode);

    if (type[2] == 'C')
	jj = expand_cmprPt(N, INTEGER(GET_SLOT(obj, Matrix_pSym)),
			   Calloc(nz, int));
    if (type[2] == 'T')
	jj = INTEGER(GET_SLOT(obj, Matrix_jSym));
    if (!jj) error("storage mode must be T or C");

    mm_write_mtx_crd(CHAR(STRING_ELT(file, 0)), M, N, nz, ii, jj, xx,
		     matcode);

    if (type[2] == 'C') Free(jj);
    return R_NilValue;

}
