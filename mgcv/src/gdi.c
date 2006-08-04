#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#define ANSI
#include "matrix.h"
#include "mgcv.h"

void getXtWX(double *XtWX, double *X,double *w,int *r,int *c,double *work)
/* forms X'WX as efficiently as possible, where W = diag(w)
   and X is an r by c matrix stored column wise. 
   work should be an r-vector (longer is no problem).
*/ 
{ int i,j;
  double *p,*p1,*p2,*pX0,*pX1,xx;
  pX0=X;
  for (i=0;i< *c;i++) { 
    p2 = work + *r;
    for (p=w,p1=work;p1<p2;p++,p1++,pX0++) *p1 = *pX0 * *p; 
    for (pX1=X,j=0;j<=i;j++) {
      for (xx=0.0,p=work;p<p2;p++,pX1++) xx += *p * *pX1;
      XtWX[i * *c + j] = XtWX[j * *c + i] = xx;
    }
  }
}

void getXtMX(double *XtMX,double *X,double *M,int *r,int *c,double *work)
/* forms X'MX as efficiently as possible, where M is a symmetric matrix
   and X is an r by c matrix. X and M are stored column wise. 
   work should be an r-vector (longer is no problem).
*/

{ int i,j;
  double *p,*p1,*p2,*pX0,*pX1,xx,*pM;
  pX0=X;
  for (i=0;i< *c;i++) { 
    /* first form MX[:,i] */
    p2 = work + *r;pM=M;
    for (p1=work;p1<p2;pM++,p1++) *p1 = *pX0 * *pM;pX0++;
    for (j=1;j< *r;j++,pX0++) 
    for (p1=work;p1<p2;pM++,p1++) *p1 += *pX0 * *pM;
    /* now form ith row and column of X'MX */
    for (pX1=X,j=0;j<=i;j++) {
      for (xx=0.0,p=work;p<p2;p++,pX1++) xx += *p * *pX1;
      XtMX[i * *c + j] = XtMX[j * *c + i] = xx;
    }
  }
}


void multSk(double *y,double *x,int *xcol,int k,double *rS,int *rSncol,int *q,double *work)
/* function to form y = Sk x, where a square root of Sk 
   is packed somewhere inside rS. x must be q by xcol. The 
   kth square root is q by rSncol[k]. The square roots are packed 
   one after another columnwise (R default).
   
   work and y must be the same dimension as x.
*/
{ int i,off,nc,bt,ct;
  double *rSk;
  off=0; /* the start of the kth square root */
  for (i=0;i<k;i++) off += *q * rSncol[i];
  rSk = rS + off; /* pointer to the kth square root */
  nc = rSncol[k];
  bt=1;ct=0;
  mgcv_mmult(work,rSk,x,&bt,&ct,&nc,xcol,q);
  bt=0;
  mgcv_mmult(y,rSk,work,&bt,&ct,q,xcol,&nc);
}

double diagABt(double *d,double *A,double *B,int *r,int *c)
/* obtain diag(AB') as efficiently as possible, and return tr(AB') A and B are
   r by c stored column-wise.
*/
{ int j;
  double tr,*pa,*pb,*p1,*pd;
  for (pa=A,pb=B,p1=pa + *r,pd=d;pa<p1;pa++,pb++,pd++) *pd = *pa * *pb;
  for (j=1;j < *c;j++)
  for (p1=d + *r,pd=d;pd<p1;pa++,pb++,pd++) *pd += *pa * *pb;
  /* d now contains diag(AB') */
  for (tr=0.0,pd=d,p1=d + *r;pd < p1;pd++) tr += *pd;
  return(tr);
}


void get_trA(double *trA,double *trA1,double *trA2,double *U1,double *KU1t,double *P,double *K,double *sp,
             double *rS,int *rSncol,double *Tk,double *Tkm,int *n,int *q,int *r,int *M)

/* obtains trA and its first two derivatives wrt the log smoothing parameters 
   * P is q by r
   * K is n by r
   * U1 is q by r
   * this routine assumes that sp contains smoothing parameters, rather than log smoothing parameters.
*/

{ double *diagA,*diagAA,xx,*KtTK,*U1KtTK,*work,*pTk,*pTm,*pdA,*pdAA,*p1,*pd,
         *PtrSm,*U1PtrSm,*U1PtSP,*KPtrSm,*KU1tU1PtrSm,*diagBtSB,*diagBtSBA;
  int i,m,k,bt,ct,j,one=1,km,mk,rSoff;
  /* set up work space */
  work =  (double *)calloc((size_t)*n,sizeof(double));
  /* obtain tr(A) and diag(A) */ 
  diagA = (double *)calloc((size_t)*n,sizeof(double));
  *trA = diagABt(diagA,K,K,n,r);
  /* obtain diag(AA) */
  diagAA = (double *)calloc((size_t)*n,sizeof(double));
  xx = diagABt(diagAA,KU1t,KU1t,n,q);
  /* now loop through the smoothing parameters to create K'TkK and U1K'TkK */
  KtTK = (double *)calloc((size_t)(*r * *r * *M),sizeof(double));
  U1KtTK = (double *)calloc((size_t)(*q * *r * *M),sizeof(double));
  for (k=0;k < *M;k++) {
    j = k * *r * *r;
    getXtWX(KtTK+ j,K,Tk + k * *n,n,r,work);
    bt=ct=0;mgcv_mmult(U1KtTK+ k * *q * *r ,U1,KtTK + j,&bt,&ct,q,r,r);
  }
  
  /* evaluate first term in first derivative of tr(A) */
  bt=1;ct=0;mgcv_mmult(trA1,Tk,diagA,&bt,&ct,M,&one,n); /* tr(TkA) */ 
  bt=1;ct=0;mgcv_mmult(work,Tk,diagAA,&bt,&ct,M,&one,n); /* tr(ATkA) */
  for (i=0;i<*M;i++) trA1[i] = 2*(trA1[i] - work[i]);
  
  /* now evaluate terms in Hessian of tr(A) which depend on what's available so far */

  for (m=0;m < *M;m++) for (k=m;k < *M;k++){
     km=k * *M + m;mk=m * *M + k;
     /* 2tr(Tkm A - ATkmA) */
     for (xx=0.0,pdA=diagA,pdAA=diagAA,p1=pdA + *n;pdA<p1;pdA++,pdAA++,Tkm++) xx += *Tkm * (*pdA - *pdAA);
     trA2[km] = 2*xx;

     /* 4tr(TkTmA - ATmTkA) */
     pTk = Tk + k * *n;pTm = Tk + m * *n;
     for (xx=0.0,pdA=diagA,pdAA=diagAA,p1=pdA + *n;pdA<p1;pdA++,pdAA++,pTk++,pTm++) xx += *pTk * *pTm  * (*pdA - *pdAA);
     trA2[km] += 4*xx; 

     /* -4 tr(TkATmA + TmATkA) */
     trA2[km] -= 8*diagABt(work,KtTK + k * *r * *r,KtTK+ m * *r * *r,r,r);

     /* 8 tr(ATkATmA) */
     trA2[km] += 8*diagABt(work,U1KtTK+k * *q * *r,U1KtTK+m * *q * *r,q,r);
 
     trA2[mk] = trA2[km];     
  }

  /* free up some memory */
  free(U1KtTK);free(KtTK);free(diagAA);free(diagA);

  /* create KP'rSm, KU1tU1P'rSm and U1P'SmP */
  PtrSm = (double *)calloc((size_t)(*r * *q ),sizeof(double)); /* transient storage for P' rSm */
  U1PtrSm = (double *)calloc((size_t)(*q * *q ),sizeof(double)); /* transient storage for U1 P' rSm */
  U1PtSP = (double *)calloc((size_t)(*M * *q * *r ),sizeof(double));
  
  KPtrSm = (double *)calloc((size_t)(*n * *q),sizeof(double)); /* transient storage for K P' rSm */
  KU1tU1PtrSm = (double *)calloc((size_t)(*n * *q),sizeof(double));/* transient storage for K U1'U1 P'rSm */ 
  diagBtSB = (double *)calloc((size_t)(*n * *M),sizeof(double));
  diagBtSBA = (double *)calloc((size_t)(*n * *M),sizeof(double));
  
  for (rSoff=0,m=0;m < *M;m++) {
    bt=1;ct=0;mgcv_mmult(PtrSm,P,rS+rSoff * *q,&bt,&ct,r,rSncol+m,q);
    bt=0;ct=0;mgcv_mmult(U1PtrSm,U1,PtrSm,&bt,&ct,q,rSncol+m,r);
    bt=0;ct=0;mgcv_mmult(KPtrSm,K,PtrSm,&bt,&ct,n,rSncol+m,r);  
    bt=0;ct=1;mgcv_mmult(U1PtSP+ m * *q * *r,U1PtrSm,PtrSm,&bt,&ct,q,r,rSncol+m);
    /* Now do KU1tU1P'rSm, recycling PtrSm as transient storage */
    bt=1;ct=0;mgcv_mmult(PtrSm,U1,U1PtrSm,&bt,&ct,r,rSncol+m,q);
    bt=0;ct=0;mgcv_mmult(KU1tU1PtrSm,K,PtrSm,&bt,&ct,n,rSncol+m,r);
    rSoff += rSncol[m];
    xx = diagABt(diagBtSBA+ m * *n,KPtrSm,KU1tU1PtrSm,n,rSncol+m);
    xx = sp[m] * diagABt(diagBtSB+ m * *n,KPtrSm,KPtrSm,n,rSncol+m);
    trA1[m] -= xx; /* finishing trA1 */
    trA2[m * *M + m] -=xx; /* the extra diagonal term of trA2 */
  }
  
  /* now use these terms to finish off the Hessian and gradient of tr(A) */ 
   for (m=0;m < *M;m++) for (k=m;k < *M;k++){
     km=k * *M + m;mk=m * *M + k;

     /* 4 sp[m] tr(ATkB'SmB) */
     pTk = Tk + k * *n;
     for (xx=0.0,pd = diagBtSBA + m * *n,p1=pd + *n;pd < p1;pd++,pTk++) xx += *pd * *pTk;
     trA2[km] += 4*sp[m] *xx;

     /* 4 sp[k] tr(ATmB'SkB) */
     pTm = Tk + m * *n;
     for (xx=0.0,pd = diagBtSBA + k * *n,p1=pd + *n;pd < p1;pd++,pTm++) xx += *pd * *pTm;
     trA2[km] += 4*sp[k] *xx;
     
     /* -2 sp[m] tr(TkB'SmB) */
     pTk = Tk + k * *n;
     for (xx=0.0,pd = diagBtSB + m * *n,p1=pd + *n;pd < p1;pd++,pTk++) xx += *pd * *pTk;
     trA2[km] -= 2*sp[m] *xx;
     
     /* -2 sp[k] tr(TmB'SkB) */
     pTm = Tk + m * *n;
     for (xx=0.0,pd = diagBtSB + k * *n,p1=pd + *n;pd < p1;pd++,pTm++) xx += *pd * *pTm;
     trA2[km] -= 2*sp[k] *xx;

     /* 2 sp[m] sp[k] tr(B'SmG^{-1}SkB) */
     trA2[km] += 2 * sp[k]*sp[m]*diagABt(work,U1PtSP + m * *q * *r,U1PtSP + k * *q * *r,q,r);
      
     trA2[mk] =trA2[km];
   } 
   /* clear up */
   free(PtrSm);free(U1PtrSm);free(U1PtSP);free(KPtrSm);free(KU1tU1PtrSm);free(diagBtSB);
   free(diagBtSBA);free(work);
   
}


void B1B2zBaseSetup(double *B2z,double *B1z,double *z,double *P,double *K,
           double *KKtz,double *PKtz,double *KPtSPKtz,double *rS,
           int *rSncol,int *n,int *q, int *r,int *M,double *sp,double *work)

/* Initializes B1z, B2z and creates
   KKtz, PKtz and KPSPKtz
   work must have dimension of at least 2*n+M*q
*/

{ double *PPtSPKtz,*v1,*v2,*dp,*dp0,*dp1,*pB2z,*pPPtSPKtz,xx;
  int i,k,one=1,m,bt,ct;
  /* A. portion out work */
  dp=work;
  v1 = dp;dp += *n;  
  v2 = dp;dp += *n;
  pPPtSPKtz=PPtSPKtz = dp; dp += *q * *M;
  /* B. create KKtz and PKtz */
  bt=1;ct=0;mgcv_mmult(v1,K,z,&bt,&ct,r,&one,n);
  bt=0;ct=0;mgcv_mmult(KKtz,K,v1,&bt,&ct,n,&one,r);
  bt=0;ct=0;mgcv_mmult(PKtz,P,v1,&bt,&ct,q,&one,r);
  /* C. loop through sp's creating PP'SkPK'z, KP'SkPK'z and intializing B1z */
  for (k=0;k < *M;k++) {
    multSk(v1,PKtz,&one,k,rS,rSncol,q,v2);
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(pPPtSPKtz,P,v2,&bt,&ct,q,&one,r);
    bt=0;ct=0;mgcv_mmult(KPtSPKtz,K,v2,&bt,&ct,n,&one,r);
    xx = -sp[k];
    for (i=0;i<*q;i++,B1z++,pPPtSPKtz++) *B1z = xx * *pPPtSPKtz;  
    KPtSPKtz += *n; /* move to next slot */
  }
  /* D. double loop through sps to set up B2z */
  pB2z=B2z;
  for (m=0;m < *M;m++)
  for (k=m;k < *M;k++)
  { /* 1. obtain PP'SmPP'SkPK'z */
    pPPtSPKtz = PPtSPKtz + k * *q;
    multSk(v1,pPPtSPKtz,&one,m,rS,rSncol,q,v2);    
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, put (sp[m]*sp[k])*v1 into the relevant part of B2z */
    dp1 = v1 + *q;xx=sp[m]*sp[k];
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 = xx * *dp;

    /* 2. obtain PP'SkPP'SmPK'z (simple k,m interchange of term 1)*/
    pPPtSPKtz = PPtSPKtz + m * *q;
    multSk(v1,pPPtSPKtz,&one,k,rS,rSncol,q,v2);    
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add (sp[m]*sp[k])*v1 to relevant part of B2z */
    dp1 = v1 + *q;xx=sp[m]*sp[k];
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += xx * *dp;
    
    /* 3. the final term PP'SkPK' */
    if (m==k) {
	dp = PPtSPKtz + k * *q;
        dp1 = dp + *q;xx=sp[k];
        for (dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= xx * *dp;
    }

    pB2z += *q;
  }
}



void B1B2z(double *B2z,double *B1z,double *B2zBase,double *B1zBase,double *z,
           double *Tk,double *Tkm,double *P,double *K,
           double *KKtz,double *PKtz,double *KPtSPKtz,double *rS,
           int *rSncol,int *n,int *q, int *r,int *M,double *sp,double *work)
/* Routine to apply first and second derivatives of B to z'.
   Some key dimensions:
   * M is the number of smoothing parameters
   * z is an n-vector
   * Tk is packed as a first derivative structure
   * TKM is packed as a second derivative structure.
   * P is q by r
   * K is n by r
   * KKtz is an n-vector
   * PKtz is a q-vector
   * KPSPKtz[i] is an n-vector
   * the rS are q by rSncol[i] matrices 

   B2zBase and B1zBase are the parts of the derivatives that do not change
   through iteration. 

   * work should contain a block of memory for (2*q+4*n)*M + 2*n doubles.
*/
{ int i,k,bt,ct,one=1,m;
  double *dp,*dp0,*dp1,*dp2,*TKKtz,*PKtTKKtz,*KKtTKKtz,*PKtTz,*Tz,*KKtTz,*v1,*v2,
         *pTk,*pTKKtz,*pPKtTKKtz,*pKKtTKKtz,*pPKtTz,*pTz,*pKKtTz,*pTkm,*pB2z,
         xx,*pKKtz,*pKPtSPKtz;
  /* A. Farm out workspace */
  dp = work;v1 = dp;dp += *n;v2 = dp; dp += *n;
  TKKtz = dp; dp += *M * *n;
  KKtTKKtz = dp; dp += *M * *n;
  PKtTKKtz = dp; dp += *M * *q;
  PKtTz = dp; dp += *M * *q;
  Tz = dp; dp += *M * *n;
  KKtTz = dp; dp += *M * *n;
  /* B. initialize B2z and B1z to base values */
  dp1 = B1z + *q * *M;
  for (dp=B1z,dp0=B1zBase;dp<dp1;dp++,dp0++) *dp = *dp0;
  dp1 = B2z + *q * *M * (1 + *M) /2;
  for (dp=B2z,dp0=B2zBase;dp<dp1;dp++,dp0++) *dp = *dp0;
  /* C. Initial loop through smoothing parameters, creating:
        * TKKtz[i], PKtTKKtz[i], KKtTKKtz[i], PKtTz[i],Tz[i],KKtTz[i]
        * B1z
  */
  pTk = Tk;
  pTKKtz=TKKtz;
  pPKtTKKtz = PKtTKKtz;
  pKKtTKKtz=KKtTKKtz;
  pTz = Tz;
  pKKtTz=KKtTz;
  pPKtTz=PKtTz;
  for (k=0;k<*M;k++) { /* loop through smoothing parameters */
    /* form TKKtz[i] */
    dp1 = pTk + *n;  
    for (dp = pTk,dp0=KKtz;dp<dp1;dp++,pTKKtz++,dp0++) *pTKKtz = *dp * *dp0; 
    /* Now form r-vector v1 = KtTKKtz */
    bt=1;ct=0;
    mgcv_mmult(v1,K,pTKKtz - *n,&bt,&ct,r,&one,n);
    /* ... which is the basis for PKtTKKtz */
    bt=0;ct=0;
    mgcv_mmult(pPKtTKKtz,P,v1,&bt,&ct,q,&one,r);
    /* ... and also for KKtTKKtz */
    mgcv_mmult(pKKtTKKtz,K,v1,&bt,&ct,n,&one,r);
    /* Form Tz... */
    dp1 = pTk + *n;
    for (dp0=z,dp=pTk;dp<dp1;dp++,pTz++,dp0++) *pTz = *dp0 * *dp;
    /* Form r-vector v1 = KtTz */
    bt=1;ct=0;
    mgcv_mmult(v1,K,pTz - *n,&bt,&ct,r,&one,n);
    /* and hence PKtTz */
    bt=0;ct=0;
    mgcv_mmult(pPKtTz,P,v1,&bt,&ct,q,&one,r);
    /* and also KKtTz */
    bt=0;ct=0;
    mgcv_mmult(pKKtTz,K,v1,&bt,&ct,n,&one,r);
    /* can now update B1z */
    for (i=0;i < *q;i++,B1z++,pPKtTz++,pPKtTKKtz++)
	*B1z += *pPKtTz - 2 * *pPKtTKKtz; 
    /* move pointers to next derivative */ 
    pKKtTKKtz += *n;
    pKKtTz += *n;
    pTk += *n;
  }

  /* D. double loop through smoothing parameters to obtain B2z
  */
  pTkm=Tkm;pB2z=B2z;
  for (m=0;m < *M;m++)
  for (k=m;k < *M;k++)
  { /* 1. obtain PK'TmKK'TkKK'z */
    pKKtTKKtz = KKtTKKtz + k * *n;
    dp = Tk + m * *n; /* pointer to Tm array*/
    dp1 = v1 + *n; /* end of v1 = TmKK'TkKK'z */
    for (dp0=v1;dp0<dp1;dp0++,dp++,pKKtTKKtz++) *dp0 = *dp * *pKKtTKKtz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add 4*v1 to relevant part of B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += 4 * *dp;
 
    /* 2. obtain PP'SmPK'TkKK'z */ 
    pPKtTKKtz = PKtTKKtz + k * *q;
    multSk(v1,pPKtTKKtz,&one,m,rS,rSncol,q,v2);
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1 - add to B2z */
    xx = 2 * sp[m];
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += xx * *dp;

    /* 3. obtain PK'TmTkKK'z */ 
    pTKKtz = TKKtz + k * *n;
    dp0 = Tk + m * *n;dp1 = dp0 + *n;
    for (dp=dp0,dp2=v1;dp < dp1;dp++,pTKKtz++,dp2++) *dp2 = *dp * *pTKKtz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1 - for addition to B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= 4 * *dp;

    /* 4. obtain PK'TkmKK'z */
    pKKtz = KKtz;
    dp1 = v1 + *n;
    for (dp0=pTkm,dp=v1;dp < dp1;dp++,dp0++,pKKtz++) *dp = *dp0 * *pKKtz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);    
    /* add result in v1 to B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= 2 * *dp;

    /* 5. obtain PK'TkKK'TmKK'z (code modified from m,k version of term) */
    pKKtTKKtz = KKtTKKtz + m * *n;
    dp = Tk + k * *n; /* pointer to Tk array*/
    dp1 = v1 + *n; /* end of v1 = TkKK'TmKK'z */
    for (dp0=v1;dp0<dp1;dp0++,dp++,pKKtTKKtz++) *dp0 = *dp * *pKKtTKKtz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add 4*v1 to relevant part of B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += 4 * *dp;

    /* 6. obtain PK'TkKP'SmPK'z */
    pKPtSPKtz = KPtSPKtz + m * *n;
    dp = Tk + k * *n;dp1 = dp + *n;
    for (dp0=v1;dp<dp1;dp++,dp0++,pKPtSPKtz++) *dp0 = *dp * *pKPtSPKtz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1 - add into B2z */
    xx = 2 * sp[m];
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += xx * *dp;

    /* 7. obtain PK'TkKK'Tmz  */
    pKKtTz = KKtTz + m * *n;
    dp = Tk + k * *n;dp1 = dp + *n;
    for (dp0=v1;dp < dp1;dp++,dp0++,pKKtTz++) *dp0 = *dp * *pKKtTz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add -2*v1 to relevant part of B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= 2 * *dp;

    /* 8. obtain PK'TmKK'Tkz  (code simple modification of term 7) */
    pKKtTz = KKtTz + k * *n;
    dp = Tk + m * *n;dp1 = dp + *n;
    for (dp0=v1;dp < dp1;dp++,dp0++,pKKtTz++) *dp0 = *dp * *pKKtTz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add -2*v1 to relevant part of B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= 2 * *dp;

    /* 9. obtain PP'SmPK'Tkz */ 
    pPKtTz = PKtTz + k * *q;
    multSk(v1,pPKtTz,&one,m,rS,rSncol,q,v2);    
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add -sp[m]*v1 to relevant part of B2z */
    dp1 = v1 + *q;xx=sp[m];
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= xx * *dp;

    /* 10. obtain PK'TmTkz */
    pTz = Tz + k * *n;
    dp = Tk + m * *n;dp1 = dp + *n;
    for (dp0 = v1;dp < dp1;dp++,dp0++,pTz++) *dp0 = *dp * *pTz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add v1 to relevant part of B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += *dp;
        
    /* 11. obtain PK'Tkmz */
    for (dp=pTkm,dp1=pTkm + *n,dp0=v1,dp2=z;dp < dp1;dp++,dp0++,dp2++) *dp0 = *dp * *dp2;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add v1 to relevant part of B2z */
    dp1 = v1 + *q;
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += *dp;

    /* 12. obtain PK'TmKP'SkPK'z */
    pKPtSPKtz = KPtSPKtz + k * *n;
    dp = Tk + m * *n;dp1 = dp + *n;
    for (dp0=v1;dp < dp1;dp++,dp0++,pKPtSPKtz++) *dp0 = *dp * *pKPtSPKtz;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,&one,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add 2*sp[k]*v1 to relevant part of B2z */
    dp1 = v1 + *q;xx=2*sp[k];
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += xx * *dp;

  

    /* 13. PP'SkPK'TmKK'z */ 
    pPKtTKKtz = PKtTKKtz + m * *q;
    multSk(v1,pPKtTKKtz,&one,k,rS,rSncol,q,v2);    
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add 2*sp[k]*v1 to relevant part of B2z */
    dp1 = v1 + *q;xx=2*sp[k];
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 += xx * *dp;

 
    /* 14. obtain PP'SkPK'Tmz */
    pPKtTz = PKtTz + m * *q;
    multSk(v1,pPKtTz,&one,k,rS,rSncol,q,v2);    
    bt=1;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,r,&one,q);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,&one,r);
    /* result now in v1, add -sp[k]*v1 to relevant part of B2z */
    dp1 = v1 + *q;xx=sp[k];
    for (dp=v1,dp0=pB2z;dp<dp1;dp++,dp0++) *dp0 -= xx * *dp;

  
    /* update complete, move pB2z and pTkm to next case */
    pB2z += *q;
    pTkm += *n;
  } 
}


void getB1z1(double *B1z1,double *z1,double *K,double *P,double *Tk,double *sp,
             double *rS,int *rSncol,int *n,int *r, int *q,int *M,double *work)
/* function to form dB/d \rho_k dz'/\rho_m for k,m=1..M and return the result in
   B1z1 which has dimension q*M^2. The storage order is:
   dB/d \rho_0 dz'/\rho_0, dB/d \rho_0 dz'/\rho_1, ...
   All matrices are stored column-wise, as in R. Conceptual dimensions are:
   * K is n by r
   * P is q by r
   * elements of z1 and Tk are n-vectors.
   * work must be of length 2*(n+q)*M, at least.
   
*/
{ double *v1,*v2,*PKtz1,*KKtz1,*dp,*dp0,*dp1,*dp2,*pz1,*pv1,xx;
  int bt,ct,k,j;
  /* A. allocate work*/
  dp=work;
  v1 = dp; dp += *n * *M;
  v2 = dp; dp += *q * *M; /* note limited size!*/
  PKtz1 = dp; dp += *q * *M;
  KKtz1 = dp; dp += *n * *M; 
  
  /* B. obtain PK'z1 and KK'z1  */ 
  bt=1;ct=0;mgcv_mmult(v2,K,z1,&bt,&ct,r,M,n);
  bt=0;ct=0;mgcv_mmult(KKtz1,K,v2,&bt,&ct,n,M,r);
  bt=0;ct=0;mgcv_mmult(PKtz1,P,v2,&bt,&ct,q,M,r);
  
  /* C. loop through the smoothing parameters updating B1z1 */
  for (k=0;k<*M;k++) {
    /* PP'SkPK'z1 */
    multSk(v2,PKtz1,M,k,rS,rSncol,q,v1);
    bt=1;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,r,M,q);
    bt=0;ct=0;mgcv_mmult(v2,P,v1,&bt,&ct,q,M,r);
    /* v2 now contains result - need to add (-sp[k] times) to appropriate block of B1z1 */
    dp1=B1z1 + *q * *M;xx = -sp[k];
    for (pv1=v2,dp=B1z1;dp < dp1;dp++,pv1++) *dp = xx * *pv1;  
    
    /* PK'Tkz1 */
    dp0 = Tk + k * *n;dp1 = dp0 + *n;
    for (pz1=z1,pv1=v1,j=0;j<*M;j++) 
     for (dp=dp0;dp<dp1;dp++,pz1++,pv1++) *pv1 = *dp * *pz1;  
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,M,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,M,r);
    /* v1 now contains result - need to add to appropriate block of B1z1 */
    dp1=B1z1 + *q * *M;
    for (pv1=v1,dp=B1z1;dp < dp1;dp++,pv1++) *dp += *pv1;

    /* PK'TkKK'z1 */
    dp0 = Tk + k * *n;dp1 = dp0 + *n;
    for (pv1=v1,dp2=KKtz1,j=0;j<*M;j++) 
     for (dp=dp0;dp<dp1;dp++,dp2++,pv1++) *pv1 = *dp * *dp2;
    bt=1;ct=0;mgcv_mmult(v2,K,v1,&bt,&ct,r,M,n);
    bt=0;ct=0;mgcv_mmult(v1,P,v2,&bt,&ct,q,M,r);
    /* v1 now contains result - need to add (-2 times) to appropriate block of B1z1 */
    dp1=B1z1 + *q * *M;
    for (pv1=v1,dp=B1z1;dp < dp1;dp++,pv1++) *dp += -2 * *pv1; 
        
    /* move B1z1 on to next block */
    B1z1 += *q * *M;
  }
}

void rc_prod(double *y,double *z,double *x,int *xcol,int *n)
/* obtains element-wise product of z and each of the  xcol columns of x,
   returning the result in y. z and the columns of x are n-vectors. 
   (equivalent to y = diag(z)%*%x)
*/ 
{ int i;
  double *pz,*pz1;
  pz1 = z + *n;
  for (i=0;i < *xcol;i++) 
      for (pz=z;pz<pz1;pz++,y++,x++) *y = *pz * *x;
}


void gdi(double *X,double *E,double *rS,
    double *sp,double *z,double *w,double *mu, double *y,
    double *p_weights,double *g1,double *g2,double *g3,double *V0,
    double *V1,double *V2,double *beta,double *D1,double *D2,double *trA,
    double *trA1,double *trA2,double *rV,double *rank_tol,double *conv_tol, int *rank_est,
    int *n,int *q, int *M,int *Encol,int *rSncol,double *debug1,double *debug2)     
/* Function to iterate for first and second derivatives of the deviance 
   of a GAM fit, and to evaluate the first and second derivatives of
   tr(A). Derivatives are w.r.t. log smoothing parameters.

   The function is to be called at convergence of a P-IRLS scheme so that 
   z, w, mu and functions of these can be treated as fixed, and only the 
   derivatives need to be updated.

   All matrices are packed into arrays in column order (i.e. col1, col2,...)
   as in R. 

   All names ending in 1,2 or 3 are derivatives of some sort, with the integer
   indicating the order of differentiation. 

   The arguments of this function point to the following:
   * X is and n by q model matrix.
   * E is a q by Encol square root of the total penalty matrix, so EE'=S
   * rS is a list of square roots of individual penalty matrices, packed
     in one array. The ith such matrix rSi, say, has dimension q by rSncol[i]
     and the ith penalty is [rSi][rSi]'.
   * sp is an M array of smoothing parameters (NOT log smoothing parameters)
   * z and w are n-vectors of the pseudodata and iterative weights
   * p_weights is an n-vector of prior weights (as opposed to the iterative weights in w)
   * mu and y are n-vectors of the fitted values and data.
   * g1,g2,g3 are the n-vectors of the link derivatives: 
     g'(mu), g''(mu) and g'''(mu)
   * V0, V1, V2 are n-vectors of the variance function and first two derivatives.
     V0(mu), V'(mu) and V''(mu) 
   * D1 and D2 are an M-vector and M by M matrix for returning the first 
     and second derivatives of the deviance wrt the log smoothing parameters.
   * trA1 and trA2 are an M-vector and M by M matrix for returning the first 
     and second derivatives of tr(A) wrt the log smoothing parameters.
   * rank_est is for returning the estimated rank of the problem.
   * the remaining arguments are the dimensions already refered to except for:
   * debug1 and debug2 which are for debugging use to pass out extra information.
   
   The method has 4 main parts:

   1. The initial QR- decomposition and SVD are performed, various quantities which 
      are independent of derivatives are created

   2. Iteration to obtain the derivatives of the coefficients wrt the log smoothing 
      parameters. 

   3. Evaluation of the derivatives of the deviance wrt the log smoothing parameters
      (i.e. calculation of D1 and D2)

   4. Evaluation of the derivatives of tr(A) (i.e. trA1 and trA2)

   The method involves first and second derivatives of a number of k-vectors wrt
   log smoothing parameters (\rho), where q is q or n. Consider such a vector, v. 
   
   * v1 will contain dv/d\rho_0, dv/d\rho_1 etc. So, for example, dv_i/d\rho_j
     (indices starting at zero) is located in v1[q*j+i].
   
   * v2 will contain d^2v/d\rho_0d\rho_0, d^2v/d\rho_1d\rho_0,... but rows will not be
     stored if they duplicate an existing row (e.g. d^2v/d\rho_0d\rho_1 would not be 
     stored as it already exists and can be accessed by interchanging the sp indices).
     So to get d^2v_k/d\rho_id\rho_j: 
     i)   if i<j interchange the indices
     ii)  off = (j*m-(j+1)*j/2+i)*q 
     iii) v2[off+k] is the required derivative.       

*/
{ double *zz,*WX,*tau,*work,*pd,*p0,*p1,*p2,*p3,*K,*R,*d,*Vt,*V,*U1,*KU1t,xx,*b1,*b2,*P,
         *c0,*c1,*c2,*a0,*a1,*a2,*B2z,*B2zBase,*B1z,*B1zBase,*eta1,*mu1,*eta2,*KKtz,
         *PKtz,*KPtSPKtz,*v1,*v2,*wi,*wis,*z1,*z2,*zz1,*zz2,*pz2,*w1,*w2,*pw2,*Tk,*Tkm,
         *pb2,*B1z1, *dev_grad,*dev_hess,diff,mag,*D1_old,*D2_old;
  int i,j,k,*pivot,ScS,*pi,rank,r,left,tp,bt,ct,iter,m,one=1,n_2dCols,n_b1,n_b2,
      n_eta1,n_eta2,n_work,ok;

  zz = (double *)calloc((size_t)*n,sizeof(double)); /* storage for z'=Wz */
  for (i=0;i< *n;i++) zz[i] = z[i]*w[i]; /* form z'=Wz itself*/
  WX = (double *) calloc((size_t) (*n * *q),sizeof(double));
  for (j=0;j<*q;j++) for (i=0;i<*n;i++) /* form WX */
  { k = i + *n * j;
    WX[k]=w[i]*X[k];
  } 
  /* get the QR decomposition of WX */
  tau=(double *)calloc((size_t)*q,sizeof(double)); /* part of reflector storage */
 
  pivot=(int *)calloc((size_t)*q,sizeof(int));
  /* Accuracy can be improved by pivoting on some occasions even though it's not going to be 
     `used' as such here - see Golub and Van Loan (1983) section 6.4. page 169 for reference. */
  mgcv_qr(WX,n,q,pivot,tau); /* WX and tau now contain the QR decomposition information */
  /* Apply pivoting to the parameter space - this simply means reordering the rows of Sr and the 
     rS_i, and then unscrambling the parameter vector at the end (along with any covariance matrix)
     pivot[i] gives the unpivoted position of the ith pivoted parameter.
  */
  ScS=0;for (pi=rSncol;pi<rSncol + *M;pi++) ScS+= *pi;  /* total columns of input rS */
  n_work = (4 * *n + 2 * *q) * *M + 2 * *n;
  work = (double *)calloc((size_t) n_work,sizeof(double)); /* work space for several routines*/
  p0 = work + *q;
  for (pd=rS,i=0;i<ScS;i++,pd += *q) /* work across columns */
  { for (pi=pivot,p2=work;p2<p0;pi++,p2++) *p2 = pd[*pi];  /* apply pivot into work */
    p3 = pd + *q;
    for (p1=pd,p2=work;p1<p3;p1++,p2++) *p1 = *p2;  /* copy back into rS */
  } /* rS pivoting complete, do E .... */
  p0 = work + *q;
  for (pd=E,i=0;i< *Encol;i++,pd += *q) /* work across columns */
  { for (pi=pivot,p2=work;p2<p0;pi++,p2++) *p2 = pd[*pi];  /* apply pivot into work */
    p3 = pd + *q;
    for (p1=pd,p2=work;p1<p3;p1++,p2++) *p1 = *p2;  /* copy back into E */
  }
  /* pivot columns of X - can't think of a smart arsed way of doing this*/
  for (i=0;i< *n;i++) {
      for (j=0;j<*q;j++) work[j]=X[pivot[j] * *n + i];
      for (j=0;j<*q;j++) X[j * *n + i] = work[j];
  }
  
  /* Now form the augmented R matrix [R',E']' */
  r = *Encol + *q;
  R=(double *)calloc((size_t)(r * *q),sizeof(double));  
  for (j=0;j< *q;j++) for (i=0;i<=j;i++) R[i+r*j] = WX[i + *n * j];
  for (j=0;j< *q;j++) for (i= *q;i<r;i++) R[i+r*j]=E[j+ (i - *q) * *q ];
  /* Get singular value decomposition, and hang the expense */

  d=(double *)calloc((size_t)*q,sizeof(double));
  Vt=(double *)calloc((size_t)(*q * *q),sizeof(double));
  mgcv_svd_full(R,Vt,d,&r,q);  
 
  /* now truncate the svd in order to deal with rank deficiency */
  rank= *q;xx=d[0] * *rank_tol;
  while(d[rank-1]<xx) rank--;
  *rank_est = rank;
  V = (double *) calloc((size_t)(*q * rank),sizeof(double));
  U1 = (double *) calloc((size_t)(*q * rank),sizeof(double));
  /* produce the truncated V (q by rank): columns dropped so V'V=I but VV'!=I   */
  for (i=0;i< *q;i++) for (j=0;j< rank;j++) V[i+ *q * j]=Vt[j+ *q * i];
  /* produce the truncated U1 (q by rank): rows and columns dropped - no-longer orthogonal */
  for (i=0;i< *q;i++) for (j=0;j< rank;j++) U1[i+ *q * j]=R[i+r*j];
  free(R);free(Vt);
  
  /* At this stage the parameter space is pivoted, and is of dimension `rank' <= *q.
     d=diag(D) and V and U1 are available. Q can be applied via calls to mgcv_qrqy.
     Now obtain P=VD^{-1},K=QU1, KU1' and the other quantities that can be obtained before 
     iteration.
  */
  K = (double *)calloc((size_t) *n * rank,sizeof(double));
  p0=U1;p1=K; /* first q rows of U0 should be U1 */
  for (j=0;j<rank;j++,p1+= *n) { p3=p1 + *q;for (p2=p1;p2<p3;p2++,p0++) *p2 = *p0;} 
  left=1;tp=0;mgcv_qrqy(K,WX,tau,n,&rank,q,&left,&tp); /* QU1 = Q%*%U1, now */

  KU1t = (double *)calloc((size_t) *n * *q,sizeof(double));
  bt=0;ct=1;mgcv_mmult(KU1t,K,U1,&bt,&ct,n,q,&rank);

  P=V; /* note: really modifying V here, V can't be used after this point */
  p3=d+rank;
  for (p0=d;p0<p3;p0++) for (i=0;i< *q;i++,P++) *P /= *p0;
  P=V;
  
  /************************************************************************************/
  /* The coefficient derivative iteration starts here */
  /************************************************************************************/
  /* set up some storage first */
  n_2dCols = *M * (1 + *M)/2;
  n_b2 = *q * n_2dCols;
  b2 = (double *)calloc((size_t)n_b2,sizeof(double)); /* 2nd derivs of beta */
  B2zBase = (double *)calloc((size_t)n_b2,sizeof(double)); /* part of 2nd derivs of beta */
  B2z = (double *)calloc((size_t)n_b2,sizeof(double)); /* part of 2nd derivs of beta */
  n_b1 = *q * *M;
  b1 = (double *)calloc((size_t)n_b1,sizeof(double)); /* 1st derivs of beta */
  B1zBase = (double *)calloc((size_t)n_b1,sizeof(double)); /* part of 1st derivs of beta */
  B1z = (double *)calloc((size_t)n_b1,sizeof(double)); /* part of 1st  derivs of beta */
  n_eta1 = *n * *M;
  eta1 = (double *)calloc((size_t)n_eta1,sizeof(double));
  Tk = (double *)calloc((size_t)n_eta1,sizeof(double));
  mu1 = (double *)calloc((size_t)n_eta1,sizeof(double));
  z1 = (double *)calloc((size_t)n_eta1,sizeof(double));
  zz1 = (double *)calloc((size_t)n_eta1,sizeof(double));
  w1 = (double *)calloc((size_t)n_eta1,sizeof(double));

  n_eta2 = *n * n_2dCols;
  eta2 = (double *)calloc((size_t)n_eta2,sizeof(double));
  Tkm = (double *)calloc((size_t)n_eta2,sizeof(double));
  z2 = (double *)calloc((size_t)n_eta2,sizeof(double));
  zz2 = (double *)calloc((size_t)n_eta2,sizeof(double));
  w2 = (double *)calloc((size_t)n_eta2,sizeof(double));

  B1z1 = (double *)calloc((size_t)(*M * *M * *q),sizeof(double));
  KKtz = (double *)calloc((size_t) *n,sizeof(double)); /* KK'z */
  PKtz = (double *)calloc((size_t) *q,sizeof(double)); /* PK'z */
  KPtSPKtz = (double *)calloc((size_t)(*n * *M),sizeof(double)); /* KP'S_kPK'z */
  
 
  v1 = work;v2=work + *n * *M; /* a couple of working vectors */ 
  /* Now get the iteration independent parts of the derivatives, which are also
     the intial values for the derivatives */
  B1B2zBaseSetup(B2zBase,B1zBase,zz,P,K,KKtz,PKtz,KPtSPKtz,rS,
                 rSncol,n,q,&rank,M,sp,work);
  /* need to copy B2zBase and B1zBase into b2 and b1 */

  p1=b2+n_b2;for (p0=b2,p2=B2zBase;p0<p1;p0++,p2++)  *p0 = *p2;  
  p1=b1+n_b1;for (p0=b1,p2=B1zBase;p0<p1;p0++,p2++)  *p0 = *p2;  

  /* Set up constants involved in z (not z'!) updates (little work => leave readable!)*/
  c0=(double *)calloc((size_t)*n,sizeof(double));
  c1=(double *)calloc((size_t)*n,sizeof(double));  
  c2=(double *)calloc((size_t)*n,sizeof(double));
  for (i=0;i< *n;i++) c0[i]=y[i]-mu[i];
  for (i=0;i<*n;i++) c2[i]=g2[i]/g1[i];
  /* c1 = (y-mu)*g2/g1 */
  for (i=0;i<*n;i++) c1[i]=c2[i]*c0[i];
  /* c2 = (y-mu)*(g3/g1-g2/g1) - g2/g1 */
  for (i=0;i<*n;i++) c2[i]=c0[i]*(g3[i]-g2[i]*g2[i]/g1[i])/g1[i]-c2[i];

  /* set up constants involved in w updates */
  a0=(double *)calloc((size_t)*n,sizeof(double));
  a1=(double *)calloc((size_t)*n,sizeof(double));  
  a2=(double *)calloc((size_t)*n,sizeof(double));
  for (i=0;i< *n;i++) a0[i] = - w[i]*w[i]*w[i]*(V1[i]*g1[i]+2*V0[i]*g2[i])/(2*p_weights[i]) ;
  for (i=0;i< *n;i++) a1[i] = 3/w[i];
  for (i=0;i< *n;i++) 
    a2[i] = -w[i]*w[i]*w[i]*(V2[i]*g1[i]+3*V1[i]*g2[i]+2*g3[i]*V0[i])/(g1[i]*2*p_weights[i]);

  /* some useful arrays for Tk and Tkm */
  wi=(double *)calloc((size_t)*n,sizeof(double));
  wis=(double *)calloc((size_t)*n,sizeof(double));
  for (i=0;i< *n;i++) { wi[i]=1/w[i];wis[i]=wi[i]*wi[i];}

  /* get gradient vector and Hessian of deviance wrt coefficients */
  for (i=0;i< *n ;i++) v1[i] = -2*p_weights[i]*(y[i]-mu[i])/(V0[i]*g1[i]);
  dev_grad=(double *)calloc((size_t)*q,sizeof(double));
  bt=1;ct=0;mgcv_mmult(dev_grad,X,v1,&bt,&ct,q,&one,n);
  
  for (i=0;i< *n ;i++) 
  v1[i] = 2*p_weights[i]*
         (1/V0[i] + (y[i]-mu[i])/(V0[i]*V0[i]*g1[i])*(V1[i]*g1[i]+V0[i]*g2[i]))/(g1[i]*g1[i]);
  dev_hess=(double *)calloc((size_t)(*q * *q),sizeof(double));
  getXtWX(dev_hess,X,v1,n,q,v2);
  
  /* create storage for gradient and Hessian of deviance wrt sp's from previous iteration,
     for convergence testing */
  D1_old =(double *)calloc((size_t)(*M),sizeof(double));
  D2_old =(double *)calloc((size_t)(*M * *M),sizeof(double));

  /* create initial gradient and Hessian of deviance */

  bt=1;ct=0;mgcv_mmult(D1,b1,dev_grad,&bt,&ct,M,&one,q); /* gradient of deviance is complete */
      
  getXtMX(D2,b1,dev_hess,q,M,v1);
          
  for (pb2=b2,m=0;m < *M;m++) for (k=m;k < *M;k++) { /* double sp loop */
     p1 = dev_grad + *q;  
     for (xx=0.0,p0=dev_grad;p0<p1;p0++,pb2++) xx += *p0 * *pb2;
     D2[k * *M + m] += xx;
     D2[m * *M + k] = D2[k * *M + m];
  } /* Hessian of Deviance is complete !! */ 

  /* store D1 and D2 for convergence testing */
  for (p0=D1,p2=D1_old,p1=D1 + *M;p0<p1;p0++,p2++) *p2 = *p0;
  for (p0=D2,p2=D2_old,p1=D2 + *M * *M;p0<p1;p0++,p2++) *p2 = *p0;
  
  /* NOTE: when DEBUG complete, better to store initial D1 and D2 directly in D1_old and D2_old */
    
  for (iter=0;iter<100;iter++) { /* main derivative iteration */ 
      /* get derivatives of eta and mu */
      bt=0;ct=0;mgcv_mmult(eta1,X,b1,&bt,&ct,n,M,q);
      bt=0;ct=0;mgcv_mmult(eta2,X,b2,&bt,&ct,n,&n_2dCols,q);
     
      p2 = g1 + *n;
      for (p3=mu1,p0=eta1,i=0;i < *M;i++) 
	  for (p1=g1;p1<p2;p1++,p0++,p3++) *p3 = *p0 / *p1;
  
     /* update the derivatives of z */
      rc_prod(z1,c1,eta1,M,n); /* z1 = dz/d\rho_k done */
   
      rc_prod(z2,c1,eta2,&n_2dCols,n);
      for (pz2=z2,m=0;m < *M;m++) for (k=m;k < *M;k++) {
	  rc_prod(v1,mu1 + *n * m,eta1 + *n * k,&one,n);
          rc_prod(v2,c2,v1,&one,n);
          p1=v2 + *n;
          for (p0=v2;p0<p1;p0++,pz2++) *pz2 += *p0;        
      } /* z2 update completed */
     
     /* update derivatives of w */  
      rc_prod(w1,a0,eta1,M,n); /* w1 = dw/d\rho_k done */

      rc_prod(w2,a0,eta2,&n_2dCols,n); 
      for (pw2=w2,m=0;m < *M;m++) for (k=m;k < *M;k++) {
	  rc_prod(v1,eta1 + *n * m,eta1 + *n * k,&one,n);
          rc_prod(v2,a2,v1,&one,n);
          p1=v2 + *n;
          for (p0=v2;p0<p1;p0++,pw2++) *pw2 += *p0;        
          pw2 -= *n;
          rc_prod(v1,w1 + *n * m,w1 + *n * k,&one,n);
          rc_prod(v2,a1,v1,&one,n);
          p1=v2 + *n;
          for (p0=v2;p0<p1;p0++,pw2++) *pw2 += *p0;     
      } /* w2 update completed */
      
      /* update Tk and Tkm */
      
      rc_prod(Tk,wi,w1,M,n); /* Tk done */

      rc_prod(Tkm,wi,w2,&n_2dCols,n);
      for (p0=Tkm,m=0;m < *M;m++) for (k=m;k < *M;k++) {
	  rc_prod(v1,w1+k * *n,w1+m * *n,&one,n);
          rc_prod(v2,wis,v1,&one,n);
          p2 = v2 + *n;
          for (p1=v2;p1<p2;p1++,p0++) *p0 -= *p1; 
      } /* Tkm finished */
     
      /* update the derivatives of z' (zz) */
      rc_prod(zz1,z,w1,M,n); /* dw_i/d\rho_k z_i */
      rc_prod(v1,w,z1,M,n);  /* dz_i/d\rho_k w_i */
      p2 = v1 + *M * *n;
      for (p0=v1,p1=zz1;p0<p2;p0++,p1++) *p1 += *p0; /*zz1=dz'/d\rho_k finished */
     
      rc_prod(zz2,z,w2,&n_2dCols,n);
      rc_prod(w2,w,z2,&n_2dCols,n); /* NOTE: w2 over-written here! */
      p2 = zz2 + n_2dCols * *n;
      for (p0=zz2,p1=w2;p0<p2;p0++,p1++) *p0 += *p1; 
     
      for (pz2=zz2,m=0;m < *M;m++) for (k=m;k < *M;k++) {
          rc_prod(v1,w1+ m * *n ,z1 + k * *n,&one,n);
          rc_prod(v2,w1+ k * *n ,z1 + m * *n,&one,n);
          p1 = v1 + *n;
          for (p0=v1,p2=v2;p0<p1;p0++,p2++,pz2++) *pz2 += *p0 + *p2; 
      } /* zz2 complete */
             
      /* update derivatives of \beta */
      
      /* Start with the horrid term B2z, and get B1z at the same time */
     
      B1B2z(B2z,B1z,B2zBase,B1zBase,zz,Tk,Tkm,P,K,KKtz,PKtz,KPtSPKtz,rS,
	rSncol,n,q,&rank,M,sp,work);
     
      /* now evaluate Bzz1 and Bzz2 and add them to B1z and B2z,
         using w1 and w2 as work-space. */

      bt=1;ct=0;mgcv_mmult(w1,K,zz1,&bt,&ct,&rank,M,n);
      bt=0;ct=0;mgcv_mmult(b1,P,w1,&bt,&ct,q,M,&rank); /* b1 = B zz1, currently */
      
      bt=1;ct=0;mgcv_mmult(w2,K,zz2,&bt,&ct,&rank,&n_2dCols,n);
      bt=0;ct=0;mgcv_mmult(b2,P,w2,&bt,&ct,q,&n_2dCols,&rank); /* b2 = B zz2, currently */
      
      p2 = b1 + *M * *q;
      for (p0=b1,p1=B1z;p0<p2;p0++,p1++) *p0 += *p1; /* b1 complete */

      p2 = b2 + n_2dCols * *q;
      for (p0=b2,p1=B2z;p0<p2;p0++,p1++) *p0 += *p1; /* b2 = B2 zz + B zz2, currently */

      /* now get the B1 zz1 cross terms by calling getB1z1 */

      getB1z1(B1z1,zz1,K,P,Tk,sp,rS,rSncol,n,&rank,q,M,work); 
      
      /* (dB/d\rho_k dz'/d\rho_m)[i] is in B1Z1[q*m+M*k*q+i] */
      
      pb2 = b2;   
      for (m=0;m < *M;m++) for (k=m;k < *M;k++) { /* double sp loop */
	  p0=B1z1 + *q * m + *M * *q * k;p2 = p0 + *q;
          p1=B1z1 + *q * k + *M * *q * m;
          for (;p0<p2;p0++,p1++,pb2++) *pb2 += *p1 + *p0; 
      } /* b2 complete */

      /* evaluate gradient and Hessian of deviance (since these are what convergence 
         should be judged on) */
      bt=1;ct=0;mgcv_mmult(D1,b1,dev_grad,&bt,&ct,M,&one,q); /* gradient of deviance is complete */
      
             
      getXtMX(D2,b1,dev_hess,q,M,v1);
          
      for (pb2=b2,m=0;m < *M;m++) for (k=m;k < *M;k++) { /* double sp loop */
        p1 = dev_grad + *q;  
        for (xx=0.0,p0=dev_grad;p0<p1;p0++,pb2++) xx += *p0 * *pb2;
        D2[k * *M + m] += xx;
        D2[m * *M + k] = D2[k * *M + m];
      } /* Hessian of Deviance is complete !! */


      /* now test for convergence */
      ok=1;
      /* test first derivative convergence */ 
      for (diff=mag=0,p0=D1,p2=D1_old,p1=D1 + *M;p0<p1;p0++,p2++) {
         xx = fabs(*p0 - *p2); /* change in derivative */
         if (xx>diff) diff=xx;
         xx = (fabs(*p0) + fabs(*p2))/2; /* size of derivative */
         if (xx>mag) mag=xx; 
      } 
      if (diff > mag * *conv_tol) ok=0;
      /* and do same for second derivatives */
      for (diff=mag=0,p0=D2,p2=D2_old,p1=D2 + *M * *M;p0<p1;p0++,p2++) {
         xx = fabs(*p0 - *p2); /* change in derivative */
         if (xx>diff) diff=xx;
         xx = (fabs(*p0) + fabs(*p2))/2; /* size of derivative */
         if (xx>mag) mag=xx;
      } 
      if (diff > mag * *conv_tol) ok=0;
      if (ok) break; /* converged */
        
      /* store D1 and D2 for convergence testing */
      for (p0=D1,p2=D1_old,p1=D1 + *M;p0<p1;p0++,p2++) *p2 = *p0;
      for (p0=D2,p2=D2_old,p1=D2 + *M * *M;p0<p1;p0++,p2++) *p2 = *p0;
      
   } /* end of main derivative iteration */

  /************************************************************************************/
  /* End of the coefficient derivative iteration  */
  /************************************************************************************/

  /* unpivot P into rV and PKtz into beta */

  for (i=0;i< *q;i++) beta[pivot[i]] = PKtz[i];

  for (p1=P,i=0;i < rank; i++) for (j=0;j<*q;j++,p1++) rV[pivot[j] + i * *q] = *p1;
  p0 = rV + *q * rank;p1 = rV + *q * *q;
  for (p2=p0;p2<p1;p2++) *p2 = 0.0; /* padding any trailing columns of rV with zeroes */

  /* dump debug information */
  
  for (i=0;i<*q;i++) for (j=0;j<*M;j++) debug1[pivot[i] + j * *q] = b1[i + j * *q];
  
  for (i=0;i<*q;i++) for (j=0;j<n_2dCols;j++) debug2[pivot[i] + j * *q] = b2[i + j * *q];

  /* clean up memory, except what's needed to get tr(A) and derivatives 
     Note: Vt and R already freed. P is really V - don't free yet.
  */ 
  free(KKtz);
  free(zz);free(WX);free(tau);free(pivot);free(work);free(d);free(b2);free(B2zBase);free(B2z);
  free(b1);
  free(B1zBase);
  free(B1z);
  free(eta1);
  free(mu1);
  free(eta2);
  free(B1z1);
  
  free(KPtSPKtz);free(c0);free(c1);free(c2);free(a0);
  free(a1);free(a2);free(wi);free(wis);free(dev_grad);free(dev_hess);free(D1_old);
  free(D2_old);free(z1);free(z2);free(zz1);free(zz2);
  free(w1);free(w2);free(PKtz);



  get_trA(trA,trA1,trA2,U1,KU1t,P,K,sp,rS,rSncol,Tk,Tkm,n,q,&rank,M);
  /* clear up the remainder */
  free(U1);
  free(V);
  free(K);
  free(KU1t);
  free(Tk);
  free(Tkm);
}
