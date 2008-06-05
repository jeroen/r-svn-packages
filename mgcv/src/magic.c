/* Copyright (C) 2003-2008 Simon N. Wood  simon.wood@r-project.org

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
(www.gnu.org/copyleft/gpl.html)

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
USA. */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "general.h"
#include "mgcv.h"
#include "matrix.h"
/*#include <dmalloc.h>*/


double ***array3d(int ni,int nj,int nk)
/* allocate 3d array */
{ double ***a,***p,**p1,*p2;
  int j;
  a=(double ***)calloc((size_t)(ni),sizeof(double **));
  *a=(double **)calloc((size_t)(ni*nj),sizeof(double *));
  **a=(double *)calloc((size_t)(ni*nj*nk),sizeof(double));
  p2 = **a; p1= *a;p=a;
  for (p=a;p<a+ni;p++) 
  { *p = p1; /* a[i]=a[0]+i*nj   */
    for (j=0;j<nj;j++,p2+=nk,p1++) *p1 = p2; /* a[i][j]= a[0][0]+i*nj*nk+j*nk  */
  } 
  return(a);
}

void free3d(double ***a)
{ free(**a);free(*a);free(a);
}

double **array2d(int ni,int nj)

{ double **a,*p,**dum;
  a=(double **)calloc((size_t)ni,sizeof(double *));
  *a=(double *)calloc((size_t)(ni*nj),sizeof(double));
  for (p= *a,dum=a;dum<a+ni;dum++,p+=nj) *dum = p; 
  return(a);
}

void free2d(double **a) {free(*a);free(a);}



void mgcv_AtA(double *AA,double *A,int *q,int *n)
/* form A'A efficiently where A is an R matrix supplied using 
   as.double(A) so that it is stored column wise. A has n rows
   and q columns.
   Typical R call something like
   matrix(.C("mgcv_AtA",as.double(rep(0,q*q)),as.double(A),as.integer(q),
              as.integer(n),PACKAGE="mgcv")[[1]],q,q)
*/
{ double xx,*p,*p1,*p2,*p3,*p4;
  int nq,i,j;
  nq= *n * *q;
  for (i=0,p=A;i < *q;p+= *n,i++) for (j=i,p1=p;j< *q;p1+= *n,j++)
  { for (xx=0.0,p2=p,p3=p1,p4=p+ *n;p2<p4;p2++,p3++) xx += *p2 * *p3;
    AA[i * *q + j] = AA[ j * *q + i]=xx;
  }
}


void mgcv_mmult(double *A,double *B,double *C,int *bt,int *ct,int *r,int *c,int *n)
/* Forms r by c product of B and C, transposing each according to bt and ct.
   n is the common dimension of the two matrices, which are stored in R 
   default column order form. Algorithm is inner loop optimized in each case 
   (i.e. inner loops only update pointers by 1, rather than jumping).
   
  
   r<-1000;c<-1000;n<-1000
   A<-matrix(0,r,c);B<-matrix(rnorm(r*n),n,r);C<-matrix(rnorm(n*c),c,n)
   system.time(
   A<-matrix(.C("mgcv_mmult",as.double(A),as.double(B),as.double(C),as.integer(1),as.integer(1),
          as.integer(r),as.integer(c),as.integer(n))[[1]],r,c))
   range(as.numeric(t(B)%*%t(C)-A))
   A<-matrix(0,r,c);B<-matrix(rnorm(r*n),n,r);C<-matrix(rnorm(n*c),n,c)
   system.time(
   A<-matrix(.C("mgcv_mmult",as.double(A),as.double(B),as.double(C),as.integer(1),as.integer(0),
          as.integer(r),as.integer(c),as.integer(n))[[1]],r,c))
   range(as.numeric(t(B)%*%C-A))
   A<-matrix(0,r,c);B<-matrix(rnorm(r*n),r,n);C<-matrix(rnorm(n*c),c,n)
   system.time(
   A<-matrix(.C("mgcv_mmult",as.double(A),as.double(B),as.double(C),as.integer(0),as.integer(1),
          as.integer(r),as.integer(c),as.integer(n))[[1]],r,c))
   range(as.numeric(B%*%t(C)-A))
   A<-matrix(0,r,c);B<-matrix(rnorm(r*n),r,n);C<-matrix(rnorm(n*c),n,c)
   system.time(
   A<-matrix(.C("mgcv_mmult",as.double(A),as.double(B),as.double(C),as.integer(0),as.integer(0),
          as.integer(r),as.integer(c),as.integer(n))[[1]],r,c))
   range(as.numeric(B%*%C-A))  
*/

{ double xx,*bp,*cp,*cp1,*cp2,*cp3,*ap,*ap1;
  int br,cr,i,j;
  if (*bt)
  { if (*ct) /* A=B'C' */
    { /* this one is really awkward: have to use first row of C' as working storage
         for current A row; move most slowly through B */
      for (i=0;i<*r;i++) /* update A *row-wise*, one full sweep of C per i */    
      { cp1 = C + *c;
        /* back up row 1 of C' (in A), and initialize current row of A (stored in row 1 of C') */
        xx = *B;
        for (ap=A,cp=C;cp<cp1;cp++,ap+= *r) { *ap = *cp; *cp *= xx;}  
        B++;cp2=cp1;
        for (j=1;j< *n;j++,B++) 
	    for (xx= *B,cp=C;cp<cp1;cp++,cp2++) *cp += xx * *cp2;      
        /* row i of A is now in row 1 of C', need to swap back */
        for (ap=A,cp=C;cp<cp1;cp++,ap+= *r) { xx = *ap; *ap = *cp; *cp = xx;}
        A++;
      } 
    } else /* A=B'C - easiest case: move most slowly through A*/
    { br= *n;cr= *n;cp2 = C + *c * cr;
      for (ap=A,cp1=C;cp1< cp2;cp1+=cr) for (bp=B,i=0;i< *r;i++,ap++)  
      { for (xx=0.0,cp=cp1,cp3=cp1+ *n;cp< cp3;cp++,bp++) xx += *cp * *bp; /* B[k+br*i]*C[k+cr*j];*/
        *ap=xx;
      }
    }
  } else
  { if (*ct) /* A=BC' - update A column-wise, move most slowly through C (but in big steps)*/
    { cp = C;
      for (j=0;j< *c;j++) /* go through columns of A, one full B sweep per j */
      { ap1 = A + *r;C=cp;xx = *C;bp=B;
        for (ap=A;ap<ap1;ap++,bp++) *ap = xx * *bp ;
        C += *c;
        for (i=1;i< *n;i++,C+= *c) 
	for (xx=*C,ap=A;ap<ap1;ap++,bp++) *ap += xx * *bp;
        A=ap1;cp++;
      }
    } else /* A=BC - update A column-wise, moving most slowly through C */
    { for (j=0;j< *c;j++) /* go through columns of A, one full B sweep per j */
      { ap1 = A + *r;xx = *C;bp=B;
        for (ap=A;ap<ap1;ap++,bp++) *ap = xx * *bp ;
        C++;
        for (i=1;i< *n;i++,C++) 
	for (xx=*C,ap=A;ap<ap1;ap++,bp++) *ap += xx * *bp;
        A=ap1;
      }
    }
  }
} 


void update_beta(double *X,double *Sr,double *rS,double *theta,double *w,double *w1,
                 double *z,double *z1,int *Srncol,int *rSncol,int *m, int *n,int *q,
                 int *get_trA,int *deriv,double *rank_tol,double *beta, double *trA,
                 double *beta1,double *trA1,double *rV,int *rank_est)
/* Routine to update model coefficients and derivatives w.r.t. log s.p.s in type 2
   GAM iteration. 
   X - n by q model matrix; Sr - q by Srncol square root of full penalty, so 
   Sr Sr' gives full penalty; rS - series of square roots of individual penalties, 
   each q by rSncol[i], so rS_i rS_i' gives component penalty;
   theta - the log smoothing parameters (dim m); w - the n weights; w1 - the n by m 
   derivatives of weights w.r.t. theta; z - the n pseudodata; z1 - the n by m pseudodata.

   `Outputs' are: beta - q vector of parameters; trA - the trace of the influence matrix
                  beta1 - q by m matrix of derivatives of beta w.r.t. sps;
                  trA1  - m vector of derivatives of trA w.r.t sps;
                  derivatives only returned if deriv!=0; trA info. only
                  returned if get_trA!=0; rank_tol used to judge rank of
                  problem.
                  rV is the square root of the posterior covariance matrix of the parameters
                  rV%*%t(rV) gives cov matrix... only returned if trA requested.

   Code assumes *q <= *n.
 
*/
{ double *WX,*p,*p0,*p1,*p2,*p3,*p4,*p5,*p6,*p7,*R,*Vt,*d,xx,*V,*U1,*dum,*U1tQtz,*tau,*work,
         *T,*TQU1U1tQtz,*Tz,*dum0,*dum2,*dum3,*VDU1tQtz,*U0,*QU1U1t,*VDU1t,*rSiVDU1t,
         trTiA,trATiA,trBSiBt;
  int i,j,k,*pi,r,rank,left,tp,ScS,*pivot,np0,np2,bt,ct,c;
  /* transform things into w - transformed space */
  if (deriv)
  for (j=0;j<*m;j++) for (i=0;i<*n;i++) /* form derivs of Wz */
  { k = i + *n * j;
    z1[k]=w1[k]*z[i]+w[i]*z1[k];
  } 
  for (i=0;i< *n;i++) z[i] = z[i]*w[i]; /* form Wz itself*/
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
  mgcv_qr(WX,n,q,pivot,tau);
  /* Apply pivoting to the parameter space - this simply means reordering the rows of Sr and the 
     rS_i, and then unscrambling the parameter vector at the end (along with any covariance matrix)
     pivot[i] gives the unpivoted position of the ith pivoted parameter.
  */
  ScS=0;for (pi=rSncol;pi<rSncol + *m;pi++) ScS+= *pi;  /* total columns of input rS */
  work=(double *)calloc((size_t) *q,sizeof(double)); 
  p0 = work + *q;
  for (p=rS,i=0;i<ScS;i++,p += *q) /* work across columns */
  { for (pi=pivot,p2=work;p2<p0;pi++,p2++) *p2 = p[*pi];  /* apply pivot into work */
    p3 = p + *q;
    for (p1=p,p2=work;p1<p3;p1++,p2++) *p1 = *p2;  /* copy back into rS */
  } /* rS pivoting complete, do Sr .... */
  p0 = work + *q;
  for (p=Sr,i=0;i< *Srncol;i++,p += *q) /* work across columns */
  { for (pi=pivot,p2=work;p2<p0;pi++,p2++) *p2 = p[*pi];  /* apply pivot into work */
    p3 = p + *q;
    for (p1=p,p2=work;p1<p3;p1++,p2++) *p1 = *p2;  /* copy back into Sr */
  }
  /* Now form the augmented R matrix [R',St']' */
  r = *Srncol + *q;
  R=(double *)calloc((size_t)(r * *q),sizeof(double));  
  for (j=0;j< *q;j++) for (i=0;i<=j;i++) R[i+r*j] = WX[i + *n * j];
  for (j=0;j< *q;j++) for (i= *q;i<r;i++) R[i+r*j]=Sr[j+ (i - *q) * *q ];
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
  /* get U1'Q'z ... */
  dum = (double *)calloc((size_t) *n,sizeof(double));
  p0 = z+ *n;
  for (p=dum,p1=z;p1<p0;p++,p1++) *p = *p1;
  left=1;tp=1;i=1;mgcv_qrqy(dum,WX,tau,n,&i,q,&left,&tp); /* first q elements are what's of interest */
 
  U1tQtz=(double *)calloc((size_t) rank,sizeof(double));
  for (i=0;i< rank;i++) { for (xx=0.0,j=0;j< *q;j++) xx += U1[j + i* *q]*dum[j];U1tQtz[i] = xx;}
  /* Now get the coefficient estimates beta = V D^{-1} U1' Q' z ... */
  for (i=0;i<rank;i++) dum[i]=U1tQtz[i]/d[i];

  for (i=0;i< *q;i++) 
  { for (xx=0.0,j=0;j< rank;j++) xx += V[i + j * *q]*dum[j];beta[pivot[i]] = xx;}

  if (get_trA) /* tr(A) = tr(U1'U1) and rV = VD^{-1}*/
  { *trA=0.0;
    p1 = U1 + rank * *q;
    for (p0=U1;p0<p1;p0++) *trA += *p0 * *p0;
    p1=V;p2=d+rank; /* Form rV = V D^{-1} and unpivot it!! */
    for (i=0,p3=d;p3<p2;p3++,i++) 
    for (j=0;j<*q;j++,p1++) rV[pivot[j] + i * *q] = *p1 / *p3;
    p0 = rV + *q * rank;p1 = rV + *q * *q;
    for (p2=p0;p2<p1;p2++) *p2 = 0.0; /* padding any trailing columns of rV with zeroes */
  
  }
  /* If required, calculate tr(A) = tr(U1 U1') ... */
  
  if (*deriv) /* perform calculations associated with derivatives */
  { T = (double *) calloc((size_t)*m * *n,sizeof(double));
    for (j=0;j<*m;j++) for (i=0;i<*n;i++) /* form derivs of T_ij = dw_i/dsp_j /w_i */
    { k = i + *n * j;
      T[k]=w1[k]/w[i];
    } 
    /* Form U1 U1' Q' z (in first q elements of dum)*/

    p0=dum;np0=*q;p1=U1;p2=U1tQtz;np2=rank;
    /* standard p0 = p1 p2 loop where p0 is vector length np0, 
    p2 is vector, length np2 and p1 is a matrix (column ordered as R) */
    p6=p0+np0;p7=p2+np2; 
    for (p3=p0;p3<p6;p3++,p1++)
    { for (xx=0.0,p4=p1,p5=p2;p5<p7;p5++,p4+=np0) xx += *p4 * *p5;
      *p3 = xx;
    }
    /* Then form Q U1 U1' Q' z */ 
    for (i=*q;i<*n;i++) dum[i]=0.0;
    left=1;tp=0;i=1;mgcv_qrqy(dum,WX,tau,n,&i,q,&left,&tp);
    
    TQU1U1tQtz = (double *)calloc((size_t) *m * *n,sizeof(double));
    Tz  = (double *)calloc((size_t) *m * *n,sizeof(double));
    for (j=0;j<*m;j++) for (i=0;i<*n;i++) /* T_ij (QU1U1tQtz)_i */
    { k = i + *n * j;
      TQU1U1tQtz[k] = T[k]*dum[i];
      Tz[k] = T[k]*z[i];
    } 
    /* bind columns together for single Q' multiplication */
    dum2 = (double *)calloc((size_t)*m * *n * 3,sizeof(double));
    p1=dum2;
    p2=TQU1U1tQtz + *m * *n;
    for (p=TQU1U1tQtz;p<p2;p++,p1++) *p1 = *p;
    p2=Tz + *m * *n;
    for (p=Tz;p<p2;p++,p1++) *p1 = *p;
    p2=z1 + *m * *n;
    for (p=z1;p<p2;p++,p1++) *p1 = *p;
    left=1;tp=1;i = 3 * *m;
    mgcv_qrqy(dum2,WX,tau,n,&i,q,&left,&tp); /* only first *q rows of dum2 are interesting */
    /* repack dum2 as q by 3m matrix... */
    p1=p=dum2;
    for (j=0;j< 3 * *m;j++,p1+= *n) 
    { p3=p1+ *q;
      for (p2=p1;p2<p3;p2++,p++) *p=*p2;     
    }
    bt=1;ct=0;c=3 * *m;
    dum3=(double *)calloc((size_t)(c * *q),sizeof(double)); /* larger than need be to allow re-use */
    mgcv_mmult(dum3,U1,dum2,&bt,&ct,&rank,&c,q);     
    /* so first m columns of dum3 give: U1tQtTQU1'U'tQ'z; next 3 give:
       U1tQtTz; final 3 give: U1tQtz1 */
    /* pre-multiply by D = diag(d) ... */ 
    p = dum3;for (j=0;j < *m * 3;j++) for (i=0;i<rank;i++,p++) *p = *p/d[i]; 
    /* pre-multiply by V */  
    bt=0;ct=0;c=3 * *m;
    mgcv_mmult(dum2,V,dum3,&bt,&ct,q,&c,&rank);
    /* columns of dum2 give components of the beta derivatives */

    /* get V D^{-1} U1'Q'z ... */
    VDU1tQtz = (double *)calloc((size_t)*q,sizeof(double));
    for (i=0;i<rank;i++) U1tQtz[i]/=d[i];
    p0=VDU1tQtz;np0=*q;p1=V;p2=U1tQtz;np2=rank;
    /* standard p0 = p1 p2 loop where p0 is vector length np0, 
    p2 is vector, length np2 and p1 is a matrix (column ordered as R) */
    p6=p0+np0;p7=p2+np2; 
    for (p3=p0;p3<p6;p3++,p1++)
    { for (xx=0.0,p4=p1,p5=p2;p5<p7;p5++,p4+=np0) xx += *p4 * *p5;
      *p3 = xx;
    }
    /* loop  to create V D^{-2} V' rSi rSi' V D^{-1} U1' Q' z */
    dum0=(double *)calloc((size_t)*n,sizeof(double));
    p=rS;
    for (i=0;i< *m;i++)
    { /* rSi' V D^{-1} U1' Q' z */
      p0=dum0;np0=rSncol[i];p1=p;p2=VDU1tQtz;np2=*q;
      /* standard p0 = p1' p2 loop where p0 is vector length np0, 
         p2 is vector, length np2 and p1 is a matrix (column ordered as R) */
      p6=p0+np0;p7=p2+np2; 
      for (p3=p0;p3<p6;p3++)
      { for (xx=0.0,p5=p2;p5<p7;p5++,p1++) xx += *p1 * *p5;
	*p3 = xx;
      }
      /* rSi rSi' V D^{-1} U1' Q' z */
      p0=dum;np0=*q;p1=p;p2=dum0;np2=rSncol[i];
      /* standard p0 = p1 p2 loop */
      p6=p0+np0;p7=p2+np2; 
      for (p3=p0;p3<p6;p3++,p1++)
      { for (xx=0.0,p4=p1,p5=p2;p5<p7;p5++,p4+=np0) xx += *p4 * *p5;
        *p3 = xx;
      }
      p += rSncol[i] * *q; /* move pointer on to next square root */
      /* V' rSi rSi' V D^{-1} U1' Q' z */
      p0=dum0;np0=rank;p1=V;p2=dum;np2=*q;
      /* standard p0 = p1' p2 loop */
      p6=p0+np0;p7=p2+np2; 
      for (p3=p0;p3<p6;p3++)
      { for (xx=0.0,p5=p2;p5<p7;p5++,p1++) xx += *p1 * *p5;
	*p3 = xx;
      }
      /* D^{-2} V' rSi rSi' V D^{-1} U1' Q' z */
      for (k=0;k<rank;k++) dum0[k]/=(d[k]*d[k]);
      /* V D^{-2} V' rSi rSi' V D^{-1} U1' Q' z */
      p0=dum;np0=*q;p1=V;p2=dum0;np2=rank;
      /* standard p0 = p1 p2 loop */
      p6=p0+np0;p7=p2+np2; 
      for (p3=p0;p3<p6;p3++,p1++)
      { for (xx=0.0,p4=p1,p5=p2;p5<p7;p5++,p4+=np0) xx += *p4 * *p5;
        *p3 = xx;
      }
      for (p1=dum3+i * *q,p2=p1 + *q,p3=dum;p1<p2;p1++,p3++) *p1 = * p3;
    }
   
    for (j=0;j<*m;j++) 
    { xx = exp(theta[j]);
      for (i=0;i<*q;i++)
      { beta1[pivot[i] + *q * j] = -xx * dum3[i + *q * j] -2 * dum2[i + *q * j] + 
	                   dum2[i + *q * (j + *m)] + dum2[i + *q * (j + *m * 2)];
      }
    }
    if (*get_trA) /* perform relatively expensive derivative of trA calculations */ 
    { U0 = (double *)calloc((size_t) *n * rank,sizeof(double));
      p0=U1;p1=U0; /* first q rows of U0 should be U1 */
      for (j=0;j<rank;j++,p1+= *n) { p3=p1 + *q;for (p2=p1;p2<p3;p2++,p0++) *p2 = *p0;} 
      left=1;tp=0;mgcv_qrqy(U0,WX,tau,n,&rank,q,&left,&tp); /* U0 = QU1, now */
      QU1U1t = (double *) calloc((size_t) (*n * *q),sizeof(double));
      bt=0;ct=1;mgcv_mmult(QU1U1t,U0,U1,&bt,&ct,n,q,&rank);      
      for (p0=U1,i=0;i<rank;i++) 
      { xx=d[i];for (j=0;j<*q;j++,p0++) *p0/=xx;
      } /* U1 now contains t(D^{-1}t(U1)) */
      VDU1t = (double *)calloc((size_t)(*q * *q),sizeof(double));
      bt=0;ct=1;mgcv_mmult(VDU1t,V,U1,&bt,&ct,q,q,&rank); /* V D^{-1} U1' */
      p=rS;
      rSiVDU1t = (double *)calloc((size_t)(*q * *q),sizeof(double)); 
      for (i=0;i<*m;i++) 
      { trTiA=0.0;p0=U0; /* QU1 */
        p1=T + i * *n;p2=p1 + *n;
        for (j=0;j<rank;j++) for (p3=p1;p3<p2;p3++,p0++) trTiA += *p3 * *p0 * *p0;
        /* ....  tr(Ti A) = tr(Ti Q U1 U1' Q') */
        trATiA = 0.0;p0=QU1U1t;
        for (j=0;j<*q;j++) for (p3=p1;p3<p2;p3++,p0++) trATiA += *p3 * *p0 * *p0;
        /* ... tr(A Ti A) = tr(U1 U1' Q' Ti Q U1 U1') */
        bt=1;ct=0;mgcv_mmult(rSiVDU1t,p,VDU1t,&bt,&ct,rSncol+i,q,q); /* rS[[i]]'VD^{-1} U1'*/
        p += *q * rSncol[i]; 
        trBSiBt=0.0;p0=rSiVDU1t;p1=p0+ *q * rSncol[i];
        for (p2=p0;p2<p1;p2++) trBSiBt += *p2 * *p2;
        trA1[i] = 2*trTiA - 2*trATiA - exp(theta[i])*trBSiBt;
      }
      free(U0);free(QU1U1t);free(VDU1t);free(rSiVDU1t);
    } 
    free(T);free(TQU1U1tQtz);free(Tz);free(dum0);free(dum2);free(dum3);free(VDU1tQtz);
  } /* end of derivative section */
  free(d);free(dum);free(U1tQtz);free(work);free(pivot);free(tau);free(V);free(U1);free(WX);
}


void fit_magic(double *X,double *sp,double **S,double *H,double *gamma,double *scale,
               int *control,double rank_tol,double yy,double *y0,double *y1,double *U1,
               double *V,double *d,double *b,double *score,double *norm,double *delta,int *rank,
               double *norm_const,int *n_score)

/* Routine to actually do the model fitting, rank determination and score calculation, returning 
   information needed for derivative calculation.
   All matrices are stored in R style column order, i.e. r by c matrix A has element i,j at A[i+r*j].

   X is an n by q matrix the top right corner of which provides R from the QR
     decomposition of the model matrix.
   sp[i] is assumed to contain the log of th ith smoothing parameter.
   S[i] is assumed to contain the ith full (q by q) penalty matrix.  
   H is the fixed penalty matrix, not referenced unless control[3]!=0.
   gamma is the degrees of freedom inflation term.
   norm_const is a constant to add to the residual sum of squares term in the 
              GCV/UBRE score and scale parameter estimation.
   scale is the scale parameter, if gcv is used it contains the estimated scale on exit.
   control[0] is 1 for GCV/0 for UBRE; control[1] is n, number of data; control[2] is q, number 
     of parameters; control[3] is 1 if H is to be used, 0 otherwise; control[4] is m, number of
     penalties.
   rank_tol is used in numerical rank determination
   yy is y'y, where y is the data
   y0 is Q_1'y a q-vector
   y1 contains U_1'Q_1'y on exit.
   U1 contains U_1 on exit (a q by rank matrix)
   V contains q by rank matrix V on exit
   d contains the rank singular values on exit.
   b contains the estimated parameters on exit.
   score contains the GCV or UBRE score on exit.
   norm contains ||y-Ay||^2 on exit (excluding norm_const)
   delta contains n-gamma*tr(A) on exit   
   rank contains the estimated rank of the problem on exit.

   The quantities modified by the routine are scale (if gcv), y1,U1,V,d,b,score,norm,delta,rank.

   There are two possibilities at this stage: it would be possible and considerably cheaper
   to simply QR decompose [R',S^{1/2}']' at this point, attempt to estimate the rank of the problem 
   truncate the parameter space and proceed. However, QR is not a fool proof method for rank 
   estimation, so this routine actually uses a singular value decomposition, which is 
   probably even proof against Comrade Napoleon.  
*/

{ double *St,*p,*p1,xx,*R,*Vt,*a,trA,yAy,yAAy;
  int i,j,k,m,n,q,rank_S=-1,r;
  m=control[4];n=control[1];q=control[2];
  /* first form S = H + \sum_i \theta_i S_i */
  St=(double *)calloc((size_t)(q*q),sizeof(double));
  if (control[3]) /* then there is a non null H */
  for (p=St;p<St+q*q;p++,H++) *p = *H; 
  for (k=0;k<m;k++) { xx=exp(sp[k]);for (p=St,p1=S[k];p<St+q*q;p++,p1++) *p += *p1 * xx;}
  
  if (m>0||control[3]) mroot(St,&rank_S,&q); /* St replaced by its square root */
  else rank_S=0;
 
  /* Now form the augmented R matrix [R',St']' */
  r=rank_S+q;
  R=(double *)calloc((size_t)(r*q),sizeof(double));  
  for (j=0;j<q;j++) for (i=0;i<=j;i++) R[i+r*j]=X[i+n*j];
  for (j=0;j<q;j++) for (i=q;i<r;i++) R[i+r*j]=St[(i-q)+rank_S*j];
  /* Get singular value decomposition, and hang the expense */
  a=(double *)calloc((size_t)q,sizeof(double));
  Vt=(double *)calloc((size_t)(q*q),sizeof(double));
  mgcv_svd_full(R,Vt,d,&r,&q);  
  /* now truncate the svd in order to deal with rank deficiency */
  *rank=q;xx=d[0]*rank_tol;
  while(d[*rank-1]<xx) (*rank)--;
  /*if (*rank < q) Rprintf("\n RANK DEFICIENCY!! rank = %d n",*rank);  */
  /* produce the truncated V (q by rank): columns dropped so V'V=I but VV'!=I   */
  for (i=0;i<q;i++) for (j=0;j< *rank;j++) V[i+q*j]=Vt[j+q*i];
  /* produce the truncated U1 (q by rank): rows and columns dropped - no-longer orthogonal */
  for (i=0;i<q;i++) for (j=0;j< *rank;j++) U1[i+q*j]=R[i+r*j];
  /* get parameters and score. First y_1 = U_1'Q_1'y */
  for (i=0;i< *rank;i++) { for (xx=0.0,j=0;j<q;j++) xx += U1[j + i*q]*y0[j];y1[i]=xx;}
  /* Now the components of the norm ||y-Ay||^2 ... */
  for (yAy=0.0,i=0;i< *rank;i++) yAy += y1[i]*y1[i];
  for (i=0;i<q;i++) { for (xx=0.0,j=0;j< *rank;j++) xx += U1[i + q*j]*y1[j];b[i]=xx;}
  for (yAAy=0.0,i=0;i<q;i++) yAAy += b[i]*b[i];
  *norm=yy-2*yAy+yAAy;
  if (*norm<0.0) *norm=0.0; /* avoid a rounding error -ve */
  /* tr(A).... */
  for (trA=0.0,i=0;i<q* *rank;i++) trA += U1[i]*U1[i];
  /* And the parameters .... */
  for (i=0;i<*rank;i++) a[i]=y1[i]/d[i];
  for (i=0;i<q;i++) { for (xx=0.0,j=0;j< *rank;j++) xx += V[i + q*j]*a[j];b[i]=xx;} 
  /* The score can now be calculated */
  n = *n_score; /* reset n from an actual dimension, to n in the GCV/UBRE score */
  xx = n - *gamma * trA;*delta=xx;
  if (control[0]) {*score = n* (*norm+*norm_const)/(xx*xx);*scale= (*norm + *norm_const)/(n-trA);} /* use GCV */
  else {*score = (*norm + *norm_const) / n - 2* *scale / n * xx + *scale; } /* UBRE/ approximate AIC */  
  free(a);free(Vt);free(R);free(St);
}

double *crude_grad(double *X,double *sp,double **Si,double *H,double *gamma,double *scale,
               int *control,double rank_tol,double yy,double *y0,double *y1,double *U1,
               double *V,double *d,double *b,double *score,double *norm,double *delta,int *rank,
               double *norm_const,int *n_score)
/* finite difference the GCV score to get approximate gradient  */
{ double ftol=1e-6,*grad,sc1,sc0,ds;
  int i;
  fit_magic(X,sp,Si,H,gamma,scale,control,rank_tol,yy,y0,y1,U1,V,d,b,&sc0,norm,delta,rank,norm_const,n_score);
  grad=(double *)calloc((size_t)control[4],sizeof(double));
  for (i=0;i<control[4];i++)
  { ds=fabs(sp[i])*ftol;
    sp[i] += ds;
    fit_magic(X,sp,Si,H,gamma,scale,control,rank_tol,yy,y0,y1,U1,V,d,b,&sc1,norm,delta,rank,norm_const,n_score);
    grad[i]=(sc1-sc0)/ds;sp[i] -= ds;
  }
  return(grad);
}

double **crude_hess(double *X,double *sp,double **Si,double *H,double *gamma,double *scale,
               int *control,double rank_tol,double yy,double *y0,double *y1,double *U1,
               double *V,double *d,double *b,double *score,double *norm,double *delta,int *rank,
               double *norm_const,int *n_score)
/* FD to check hessian */
{ int m,i,j;
  double *g0,*g1,**hess,ftol=1e-4,ds;
  m=control[4];
  hess=array2d(m,m);
  g0=crude_grad(X,sp,Si,H,gamma,scale,control,rank_tol,yy,y0,y1,U1,V,d,b,score,norm,delta,rank,norm_const,n_score);
  for (i=0;i<m;i++)
  { ds=fabs(sp[i])*ftol;
    sp[i] += ds;
    g1=crude_grad(X,sp,Si,H,gamma,scale,control,rank_tol,yy,y0,y1,U1,V,d,b,score,norm,delta,rank,norm_const,n_score);
    for (j=0;j<m;j++) hess[i][j] = (g1[j]-g0[j])/ds; 
    sp[i] -= ds;
  }  
  return(hess);
}

void magic_gH(double *U1U1,double **M,double **K,double *VS,double **My,double **Ky,double **yK,double **hess,
              double *grad,double *dnorm,double *ddelta,double *sp,double **d2norm,double **d2delta,double *S,
              double *U1,double *V,double *d,double *y1,int rank,int q,int m,int *cS,int gcv,double *gamma,double *scale,
              double norm,double delta,int n,double *norm_const)

/* service routine for magic that calculates gradient and hessian of score w.r.t. sp. 
   Note that n is assumed to be ued only in the score calculation, not as an actual physical 
   dimension!

*/

{ double *p,*p1,*p2,*p3,*p4,xx,xx1,x1,x2;
  int i,j,*ip,bt,ct,r,c; 
  mgcv_AtA(U1U1,U1,&rank,&q); /* U_1'U_1 U1 is q by rank*/
  for (p=S,ip=cS,i=0;ip<cS+m;p+= *ip *q,ip++,i++) /* work through all smooths */ 
  { bt=1;ct=0;r=rank;c= *ip;
    mgcv_mmult(VS,V,p,&bt,&ct,&r,&c,&q); /* V'S_i^0.5 result is rank by cS[i] */ 
    for (p2=VS,j=0;j<*ip;j++)
    for (p1=d;p1<d+rank;p1++,p2++) *p2 /= *p1;   /* D^{-1} V' S_i^0.5 */
    bt=1;ct=0;r= *ip;c= rank;
    mgcv_mmult(M[i],VS,U1U1,&bt,&ct,&r,&c,&rank); /* S_i^0.5 V D^{-1} U_1'U_1 */
    bt=ct=0;r=c=rank;
    mgcv_mmult(K[i],VS,M[i],&bt,&ct,&r,&c,ip); /* K_i = D^{-1}V'S_iVD^{-1}U_1'U_1 */
    bt=0;ct=1;r=c=rank;
    mgcv_mmult(M[i],VS,VS,&bt,&ct,&r,&c,ip); /* M_i= D^{-1}V'S_iVD^{-1} */
    for (p1=My[i],p2=M[i];p1<My[i]+rank;p1++) /* M_i y */
    { for (xx=0.0,p3=y1;p3<y1+rank;p3++,p2++) xx += *p3 * *p2;*p1 = xx;}
    for (p1=yK[i],p2=K[i];p1<yK[i]+rank;p1++) /* y' K_i */
    { for (xx=0.0,p3=y1;p3<y1+rank;p3++,p2++) xx += *p3 * *p2;*p1 = xx;}
    for (p1=Ky[i],p2=K[i];p1<Ky[i]+rank;p1++,p2++) /* K_i y */
    { for (xx=0.0,p4=p2,p3=y1;p3<y1+rank;p3++,p4+=rank) xx += *p3 * *p4;*p1 = xx;}
  }
  /* note at this stage that y1, M[i] and K[i] are all dimension rank */
  for (i=0;i<m;i++) 
  { for (xx=0.0,p=K[i];p<K[i]+rank*rank;p+=rank+1) xx += *p;ddelta[i]= *gamma * xx * exp(sp[i]);
    for (j=0;j<=i;j++)
    { for (xx=0.0,p=M[j],p1=K[i];p<M[j]+rank*rank;p++,p1++) xx += *p * *p1;
      d2delta[j][i]=d2delta[i][j]= - *gamma*2*exp(sp[i]+sp[j])*xx; 
    }    
    d2delta[i][i]+=ddelta[i];
    /* deal with the norm .... */
    for (xx=0.0,p=y1,p1=Ky[i],p2=My[i];p<y1+rank;p++,p1++,p2++) xx += *p *( *p2 - *p1);
    dnorm[i] =2*exp(sp[i])*xx;
    for (j=0;j<=i;j++)
    { for (xx=0.0,p1=My[i],p2=My[j],p3=Ky[i],p4=Ky[j],p=yK[i];p1<My[i]+rank;p++,p1++,p2++,p3++,p4++)
      xx += (*p1 * *p4 + *p2 * *p3 - 2 * *p1 * *p2 + *p * *p2);
      d2norm[i][j]=d2norm[j][i]=  xx*2*exp(sp[i]+sp[j]); 
    }
    d2norm[i][i]+=dnorm[i];
  }
  
  if (gcv)
  { norm += *norm_const; /* inflate the residual sum of squares by the supplied norm constant */
    xx = n/(delta*delta);xx1= xx*2*norm/delta;
    x1 = -2*xx/delta;x2=3*xx1/delta;
    for (i=0;i<m;i++) 
    { grad[i]=xx*dnorm[i]-xx1*ddelta[i];
      for (j=0;j<=i;j++) 
      hess[i][j]=hess[j][i]=x1*(ddelta[j]*dnorm[i]+ddelta[i]*dnorm[j])+
                 xx*d2norm[i][j]+x2*ddelta[i]*ddelta[j] -
                 xx1*d2delta[i][j];    
    } 
  } else
  { for (i=0;i<m;i++) 
    { grad[i]=( dnorm[i] - 2* *scale*ddelta[i])/ n;
      for (j=0;j<=i;j++) hess[i][j]=hess[j][i]=(d2norm[i][j]-2* *scale*d2delta[i][j])/ n;
    }
  }
}


void magic(double *y,double *X,double *sp0,double *def_sp,double *S,double *H,double *L,double *lsp0,
           double *gamma,double *scale,int *control,int *cS,double *rank_tol,double *tol,double *b,
           double *rV,double *norm_const,int *n_score) 

/* Maximally stable multiple gcv/ubre optimizer, based on pivoted QR decomposition and SVD, but without 
   a line search. At each point in the smoothing parameter space, the numerical rank of the problem 
   is estimated, and calculations proceed in a parameter space of that rank.

   Basic problem is to find optimal smoothing parameters, sp, for the problem:
   minimise ||y-Xb||^2 + b'Hb + \sum_i sp[i]*b'S_ib
   by GCV or UBRE. The approach is to use Newtons method backed up by steepest descent, working in the 
   space of the log of the smoothing parameters.

   y - an n dimensional response vector
   X - an n by q model matrix
   sp0 - an mp-array of (underlying) smoothing parameters (any -ve => autoinitialize)
   def_sp - an array of default values for sp0's (any -ve => set up internally)
   b - a q dimensional parameter vector
   S - an array of dimension q columns of square roots of the m S_i penalty matrices. There are cS[i]
       columns for the ith penalty, and they are packed starting from i=0.
   H - a q by q fixed penalty matrix
   L - m by mp matrix mapping log(sp0) to log coeffs multiplying S terms. 
       ignored if control[6] is negative.
   lsp0 - constant vector in linear transformation of log(sp0). So sp = Llog(sp0)+lsp0
          also ignored if control[6] is negative.
   gamma - a factor by which to inflate the model degrees of freedom in GCV/UBRE scores.
   norm_const - a constant to be added to the residual sum of squares (squared norm) term in 
                the GCV/UBRE and scale estimation calculations.
   scale - the scale parameter (fixed for UBRE, will be estimated for GCV).

   Elements of control are as follows:
   control[0] - 1 for GCV 0 for UBRE
   control[1] - n, the number of data
   control[2] - q, the number of parameters
   control[3] - 1 if H is to be used, 0 to ignore it 
   control[4] - m, the number of penalty matrices in S.
   control[5] - the maximum number of step halvings to try
   control[6] - mp, the number of actual smoothing parameters: -ve signals 
                that it's m and L is to be taken as the identity, but ignored.

   cS[i] gives the number of columns of S relating to S_i (column 0 is the first column of S_0).
   rank_tol is the tolerance to use in rank determination square root of the machine precision is quite good.
   tol is the convergence tolerance for the iterative score optimisation.
   b is the q dimensional parameter vector.
   rV is a square root of the parameter covariance matrix (to within the scale factor) cov(b)=rV rV' scale      

   The m square roots of smoothing penalty matrices are packed one after another in S.
   
   Currently first guess smoothing parameters are 1/tr(S_i), and second guess are
   \sigma^2 rank(S_i) / b'S_ib

   The routine modifies the following arguments on exit:

   b contains parameter estimates
   sp contains the smoothing parameter estimates   
   gamma contains the estimated GCV/UBRE score 
   scale - the estimated scale parameter if GCV used 
   tol - the root mean square gradient of the GCV/UBRE score at convergence
   rV - square root of the param. cov. matrix cov(b) = rV%*%rV'*scale, rV is q by rank.    

   control[0] - the final rank estimate
   control[1] - 1 if converged, 0 if step failure without meeting convergence criteria
   control[2] - 1 if the final Hessian was +ve definite
   control[3] - the number of iterations used
   control[4] - the number of score function evaluations
   control[5] - maximum number of step halvings to try 
   control[6] - The maximum number of iterations before giving up   

   Note that the effective degrees of freedom for each parameter are given by the 
   leading diagonal of cov(b)X'X/scale.

   Appropriate initialization of the smoothing parameters is important for this algorithm,
   particularly since there is no line search in this approach. Whether the initial estimates 
   are auto-generated or supplied, it is important to start with values such that the partial
   derivatives of the score w.r.t. the smoothing parameters are all "large", meeaning well
   above the level judged to have converged.

   To this end initial values are all checked for derivative magnitude. Any parameters for 
   which the derivative magnitude is too small are modified in an attempt to increase the 
   derivative magnitude. 

 */
{ int *pi,*pivot,q,n,autoinit,left,ScS,m,mp,i,j,tp,k,use_sd=0,rank,converged,iter=0,ok,
    gcv,try,fit_call=0,step_fail=0,max_half,*spok,def_supplied,use_dsyevd=1,L_exists;
  double *sp=NULL,*p,*p1,*p2,*tau,xx,*y1,*y0,yy,**Si=NULL,*work,score,*sd_step,*n_step,*U1,*V,*d,**M,**K,
         *VS,*U1U1,**My,**Ky,**yK,*dnorm,*ddelta,**d2norm,**d2delta,norm,delta,*grad,**hess,*nsp,
         min_score,*step,d_score=1e10,*ev=NULL,*u,msg=0.0,Xms,*rSms,*bag,*bsp,sign,*grad1,*u0;
  gcv=control[0];q=control[2];n=control[1];m=control[4];max_half=control[5];mp=control[6];
  
  /* first get the QR decomposition of X */
  tau=(double *)calloc((size_t)q,sizeof(double)); /* part of reflector storage */
  pivot=(int *)calloc((size_t)q,sizeof(int));
  /* Accuracy can be improved by pivoting on some occasions even though it's not going to be 
     `used' as such here - see Golub and Van Loan (1983) section 6.4. page 169 for reference. */
  mgcv_qr(X,&n,&q,pivot,tau);
  /* Apply pivoting to the parameter space - this simply means reordering the rows of the S_i
     stored in S doing the same for H, and then unscrambling the parameter vector at the end 
     (along with covariance matrix)
     pivot[i] gives the unpivoted position of the ith pivoted parameter.
  */
  
  ScS=0;for (pi=cS;pi<cS+m;pi++) ScS+= *pi;  /* total columns of input S */
  work=(double *)calloc((size_t)q,sizeof(double)); 
  for (p=S,i=0;i<ScS;i++,p+=q) /* work across columns */
  { for (pi=pivot,p2=work;p2<work+q;pi++,p2++) *p2 = p[*pi];  /* apply pivot into work */
    for (p1=p,p2=work;p1<p+q;p1++,p2++) *p1 = *p2;  /* copy back into S */
  } /* S pivoting complete, do H .... */
 
  if (control[3])
  { for (j=0;j<q;j++)
    { for (i=0;i<q;i++) work[i]=H[pivot[i]+q*j];
      for (i=0;i<q;i++) H[i+q*j]=work[i]; 
    }
    for (i=0;i<q;i++)
    { for (j=0;j<q;j++) work[j]=H[i+pivot[j]*q];
      for (j=0;j<q;j++) H[i+q*j]=work[j]; 
    }
  }

  /* form y_1 = Q_1'y */
 
  y0=(double *)calloc((size_t)n,sizeof(double));
  for (p=y,p1=y0;p<y+n;p++,p1++) *p1 = *p;
  left=1;tp=1;i=1;mgcv_qrqy(y0,X,tau,&n,&i,&q,&left,&tp); /* first q elements are y1 */
  /* form y'y */
 
  for (yy=0.0,p=y;p<y+n;p++) yy += *p * *p;
  /* explicitly form the S_i's since they are needed in S = H + \sum_i \theta_i S_i */
  
  if (m>0)
  { Si=array2d(m,q*q);
    i=0;j=1;
    for (p=S,k=0;k<m;p+=cS[k]*q,k++)  mgcv_mmult(Si[k],p,p,&i,&j,&q,&q,cS+k);   
  }
   
  /* now get the initial smoothing parameter estimates \propto 1/tr(S_i) */

  if (mp<0) { L_exists=0;mp=m;} else L_exists=1;

  if (m>0) sp = (double *)calloc((size_t)m,sizeof(double)); /* to hold actual log(sp[i]) terms multiplying penalties */

  autoinit=0;for (p=sp0;p<sp0+mp;p++) if (*p <=0.0) { autoinit=1;break;} /* autoinitialize s.p.s? */ 
  def_supplied=1; for (p=def_sp;p<def_sp+mp;p++) if (*p <=0.0) { def_supplied=0;break;} 

  if (L_exists&&!def_supplied) 
    error(_("magic requires smoothing parameter starting values if L supplied"));
  
 

  if (m>0&&!def_supplied) /* generate default sp's (only possible if there is no L)*/
  { rSms=(double *)calloc((size_t)m,sizeof(double));
    /* first get some sort of norm for X */
    Xms=0.0;for (j=0;j<q;j++) for (i=0;i<=j;i++) { xx=X[i+n*j];Xms+=xx*xx;}
    p=S;Xms/=n*q;
    for (i=0;i<m;i++)
    { for (xx=0.0,p=Si[i];p<Si[i]+q*q;p+=q+1) xx += *p;
      rSms[i]=xx/(q*cS[i]);
      def_sp[i]=Xms/rSms[i]; 
    }  
  } else { Xms=0.0;rSms=NULL;}

  if (autoinit) for (i=0;i<mp;i++) sp0[i]=log(def_sp[i]);
  else for (i=0;i<mp;i++) sp0[i]=log(sp0[i]);  

  if (L_exists) {
    i=0;j=1;if (mp) mgcv_mmult(sp,L,sp0,&i,&i,&m,&j,&mp); /* form sp = L sp0  */
    for (p=sp,p1=lsp0,p2=sp+m;p<p2;p++,p1++) *p += *p1; /* form sp= L sp0 + lsp0 */
  } else { /* sp0 and sp are identical */
    for (i=0;i<m;i++) sp[i]=sp0[i];
  }
/*  for (i=0;i<m;i++) Rprintf("%g  ",exp(sp[i]));Rprintf("\n");*/

  y1=(double *)calloc((size_t)q,sizeof(double)); /* Storage for U_1'Q_1'y */
  U1=(double *)calloc((size_t)(q*q),sizeof(double));
  V=(double *)calloc((size_t)(q*q),sizeof(double));
  d=(double *)calloc((size_t)q,sizeof(double));
  if (mp>0) /* allocate derivative related storage */
  { M=array2d(m,q*q);K=array2d(m,q*q);VS=(double *)calloc((size_t)(q*q),sizeof(double));
    My=array2d(m,q);Ky=array2d(m,q);yK=array2d(m,q);
    hess=array2d(m,m);
    grad=(double *)calloc((size_t)mp,sizeof(double));
    grad1=(double *)calloc((size_t)m,sizeof(double));
    dnorm=(double *)calloc((size_t)m,sizeof(double));
    ddelta=(double *)calloc((size_t)m,sizeof(double));
    nsp=(double *)calloc((size_t)mp,sizeof(double));
    d2norm=array2d(m,m);d2delta=array2d(m,m);
    ev=(double *)calloc((size_t)mp,sizeof(double));
    u=(double *)calloc((size_t)(m*m),sizeof(double));
    u0=(double *)calloc((size_t)(m*mp),sizeof(double));
    U1U1=(double *)calloc((size_t)(q*q),sizeof(double));
    spok=(int *)calloc((size_t)m,sizeof(int));
    /*dir_sp=(int *)calloc((size_t)m,sizeof(int));*/
    bsp=(double *)calloc((size_t)m,sizeof(double));
    bag=(double *)calloc((size_t)m,sizeof(double));
  } else 
  { M=K=My=Ky=yK=hess=d2norm=d2delta=NULL;
    u0=VS=grad1=grad=dnorm=ddelta=nsp=ev=u=U1U1=bsp=bag=NULL;
    spok=NULL;/*dir_sp=NULL;*/
  }

  fit_magic(X,sp,Si,H,gamma,scale,control,*rank_tol,yy,y0,y1,U1,V,d,b,&score,&norm,&delta,&rank,norm_const,n_score);
  fit_call++;  
  /* .... U1 and V are q by rank matrices, d is a dimension rank vector */
  /* Now check that all derivatives are large enough that SD or Newton can be expected to work... */

  if (mp>0&&!autoinit)
  { magic_gH(U1U1,M,K,VS,My,Ky,yK,hess,grad1,dnorm,ddelta,sp,d2norm,d2delta,S,
                 U1,V,d,y1,rank,q,m,cS,gcv,gamma,scale,norm,delta,*n_score,norm_const);
    xx=1e-4*(1+fabs(score));
    ok=1;
    /* reset to default any sp w.r.t. which score is flat */
    if (L_exists) { /* transform to grad w.r.t. sp0 */
      i=0;j=1;mgcv_mmult(grad,L,grad1,&j,&i,&mp,&j,&m);
    } else {
      p = grad;grad=grad1;grad1=p;
    }

    for (i=0;i<mp;i++) if (fabs(grad[i])<xx) 
    { sp0[i]=log(def_sp[i]);ok=0;
    /*  Rprintf("Resetting sp[%d]\n",i);*/
    } 
    
    if (L_exists) {
      i=0;j=1;mgcv_mmult(sp,L,sp0,&i,&i,&m,&j,&mp); /* form sp = L sp0 */
      for (p=sp,p1=lsp0,p2=sp+m;p<p2;p++,p1++) *p += *p1; /* form sp= L sp0 + lsp0 */
    } else { /* sp0 and sp are identical */
      for (i=0;i<m;i++) sp[i]=sp0[i];
    }

    if (!ok) 
    { fit_magic(X,sp,Si,H,gamma,scale,control,*rank_tol,yy,y0,y1,
                U1,V,d,b,&score,&norm,&delta,&rank,norm_const,n_score);
      fit_call++;
    }
  }
  

  min_score=score;
  sd_step=(double *)calloc((size_t)mp,sizeof(double));
  n_step=(double *)calloc((size_t)mp,sizeof(double));
 
  if (autoinit&&!def_supplied) /* can't get here if L exists */
  { /* second guesses are scale*rank(S_i) / b'S_ib */
    for (p=S,k=0;k<m;k++)
    { for (j=0;j<cS[k];j++)
      { for (xx=0.0,i=0;i<q;i++,p++) xx += *p * b[i]; 
        d[j]=xx;  
      }
      for (xx=0.0,j=0;j<cS[k];j++) xx+= d[j]*d[j];
      sd_step[k]=log(*scale * cS[k]/xx)-sp[k]; 
    }
    use_sd=1;
    /*  Rprintf("Using second guess\n");*/
  }
  
  /* Now do smoothing parameter estimation if there are any to estimate */
  if (mp>0)
  { converged=0;iter=0;
    while (!converged)
    { iter++;
      if (iter>400) error(_("magic, the gcv/ubre optimizer, failed to converge after 400 iterations."));
      if (iter>1||(autoinit&&!def_supplied)) ok=1; /* try out step */
      else ok=0; /* no step to try yet */
      try=0; 
      if (use_sd) step=sd_step; else step=n_step;
      while (ok) /* try out step, shrinking it if need be */
      { try++; if (try==4&&!use_sd) {use_sd=1;step=sd_step;}
        for (i=0;i<mp;i++) nsp[i]=sp0[i]+step[i];
        if (L_exists) {
          i=0;j=1;mgcv_mmult(sp,L,nsp,&i,&i,&m,&j,&mp); /* form sp = L nsp */
          for (p=sp,p1=lsp0,p2=sp+m;p<p2;p++,p1++) *p += *p1; /* form sp= L nsp + lsp0 */
        } else { /* nsp and sp are identical */
          for (i=0;i<m;i++) sp[i]=nsp[i];
        }
        fit_magic(X,sp,Si,H,gamma,scale,control,*rank_tol,yy,y0,y1,
                  U1,V,d,b,&score,&norm,&delta,&rank,norm_const,n_score);
        fit_call++;
        if (score<min_score) /* accept step */
        { ok=0;
          d_score=min_score-score;
          min_score=score;
          for (i=0;i<mp;i++) sp0[i]=nsp[i];
        } else
        for (i=0;i<mp;i++) step[i]/=2;
        if (try==(max_half-1)&&ok) 
        for (i=0;i<mp;i++) step[i]=0.0; /* reset sp's to best so far before giving up */
        if (try==max_half) {ok=0;} /* give up */
      }
      if (iter>3) /* test for convergence */
      { converged=1;
        if (d_score> *tol*(1+min_score)) converged=0;
        for (xx=0.0,i=0;i<mp;i++) xx+=grad[i]*grad[i];xx=sqrt(xx); 
        if (xx>pow(*tol,1/3.0)*(1+fabs(min_score))) converged=0;
        if (try==max_half) converged=1; /* can't improve score */
        if (converged) { msg=sqrt(xx*xx/mp);if (try==max_half) step_fail=1;}
      }
    
     
      /* now get derivatives */
      { if (L_exists) {
          i=0;j=1;mgcv_mmult(sp,L,sp0,&i,&i,&m,&j,&mp); /* form sp = L sp0 */
          for (p=sp,p1=lsp0,p2=sp+m;p<p2;p++,p1++) *p += *p1; /* form sp= L sp0 + lsp0 */
        } else { /* sp0 and sp are identical */
          for (i=0;i<m;i++) sp[i]=sp0[i];
        }
        magic_gH(U1U1,M,K,VS,My,Ky,yK,hess,grad1,dnorm,ddelta,sp,d2norm,d2delta,S,
                 U1,V,d,y1,rank,q,m,cS,gcv,gamma,scale,norm,delta,*n_score,norm_const);
        /* Now get the search directions */
        for (i=0;i<m;i++) for (j=0;j<m;j++) u[i+m*j]=hess[i][j]; 
	if (L_exists) { /* transform grad and hess */
          i=0;j=1;mgcv_mmult(grad,L,grad1,&j,&i,&mp,&j,&m);
          mgcv_mmult(u0,L,u,&j,&i,&mp,&m,&m); /* u0 contains L'H */
          mgcv_mmult(u,u0,L,&i,&i,&mp,&mp,&m); /* u contains L'HL - the transformed hessian */
        } else {
          p = grad;grad=grad1;grad1=p;
        }
               
        mgcv_symeig(u,ev,&mp,&use_dsyevd); /* columns of hess are now eigen-vectors */
        use_sd=0;for (p=ev;p<ev+mp;p++) if (*p<0.0) {use_sd=1;break;} /* check hessian +ve def */
        if (!use_sd) /* get the Newton direction Hess^{-1}grad */
        { for (i=0;i<mp;i++) { for (xx=0.0,j=0;j<mp;j++) xx+=u[j+mp*i]*grad[j];sd_step[i]=xx/ev[i];}
          for (i=0;i<mp;i++) { for (xx=0.0,j=0;j<mp;j++) xx+=u[i+mp*j]*sd_step[j];n_step[i]= -xx;}
          for (xx=fabs(n_step[0]),i=1;i<mp;i++) if (fabs(n_step[i])>xx) xx=fabs(n_step[i]);
          if (xx>5.0) /* scale step to max component length 5 */
          { xx=5.0/xx;for (i=0;i<mp;i++) n_step[i]*=xx;}
        } 
        for (xx=fabs(grad[0]),i=1;i<mp;i++) if (xx<fabs(grad[i])) xx=fabs(grad[i]);
        for (i=0;i<mp;i++) sd_step[i]= -grad[i]/xx;     
      }
    } /* end of estimation iterative loop */
  
    /* At this point Newton/SD has converged, but we need to check s.p. optima are not at +/- infinity */
    for (k=0;k<mp;k++)
    { ok=5;xx=2.0; 
      if (grad[k]<0.0) sign=1; else sign=-1;
      while (ok) /* change sp for as long as substantial reduction occurs */
      { sp0[k] += sign*xx;
        if (L_exists) {
          i=0;j=1;mgcv_mmult(sp,L,sp0,&i,&i,&m,&j,&mp); /* form sp = L sp0 */
          for (p=sp,p1=lsp0,p2=sp+m;p<p2;p++,p1++) *p += *p1; /* form sp= L sp0 + lsp0 */
        } else { /* nsp and sp are identical */
          for (i=0;i<m;i++) sp[i]=sp0[i];
        } 
        ok--; /* don't do more than 5 of these steps in any case! */
        fit_magic(X,sp,Si,H,gamma,scale,control,*rank_tol,yy,y0,y1,U1,V,d,b,&score,&norm,&delta,&rank,norm_const,n_score);
        if (score<min_score)
        { min_score=score; 
        } else /* last step was failure - undo it and leave this s.p.*/ 
        { ok=0;sp0[k] += -sign*xx;}
      } 
    }

    if (L_exists) {
      i=0;j=1; mgcv_mmult(sp,L,sp0,&i,&i,&m,&j,&mp); /* form sp = L nsp */
      for (p=sp,p1=lsp0,p2=sp+m;p<p2;p++,p1++) *p += *p1; /* form sp= L sp0 + lsp0 */
    } else { /* nsp and sp are identical */
      for (i=0;i<m;i++) sp[i]=sp0[i];
    }
    fit_magic(X,sp,Si,H,gamma,scale,control,*rank_tol,yy,y0,y1,U1,V,d,b,&score,&norm,&delta,&rank,norm_const,n_score);
   
    /* free search related memory */
    free2d(Si);free2d(M);free2d(K);free2d(My);free2d(Ky);free2d(yK);free2d(hess);
    free2d(d2norm);free2d(d2delta);free(U1U1);free(rSms);free(u);
    free(VS);free(grad);free(dnorm);free(ddelta);free(nsp);free(ev);
    free(bsp);free(bag);free(spok);free(sp);free(grad1);free(u0);
  } /* end of smoothness selection (if (mp>0) {... )*/

  /* prepare ``outputs''... */
  /* now get rV (in unpivoted space) */
  for (p2=V,p1=d;p1<d+rank;p1++) /* work through columns */ 
  for (j=0;j<q;j++,p2++) *p2 /= *p1; /* V now contains VD^{-1} */   
  /* unpivot V into rV... */
  for (p1=V,p2=rV;p2<rV+q*rank;p2+=q)
  for (pi=pivot;pi<pivot+q;pi++,p1++) p2[*pi] = *p1;
  /* now unpivot the parameters ...*/
  for (i=0;i<q;i++) d[i]=b[i];for (i=0;i<q;i++) b[pivot[i]]=d[i]; /* unpivot parameters */
  for (i=0;i<mp;i++) sp0[i]=exp(sp0[i]); /* exponentiate smoothing parameters */
  *gamma = score; /* return GCV/UBRE score */
  *tol = msg; /* the root mean square gradient at convergence */  
  control[0]=rank; /* problem rank at convergence */
  control[1]=1-step_fail; /* 1 for true convergence, 0  for step failure */
  control[2]=1-use_sd; /* 1 if Hessian +ve definite, 0 otherwise */
  control[3]=iter; /* iterations used */
  control[4]=fit_call; /* number of evaluations of GCV/UBRE score */
  
  free(tau);free(pivot);free(work);free(y0);free(y1);free(U1);free(V);free(d);free(sd_step);
  free(n_step);
    
 /* dmalloc_verify(NULL);dmalloc_log_stats();*/
}



/*main()

{ magic_test();

}*/



