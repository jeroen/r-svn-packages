##  R routines for the package mgcv (c) Simon Wood 2000-2009

##  This file is primarily concerned with defining classes of smoother,
##  via constructor methods and prediction matrix methods. There are
##  also wrappers for the constructors to automate constraint absorption,
##  `by' variable handling and the summation convention used for general
##  linear functional terms. 


##############################
## First some useful utilities
##############################

nat.param <- function(X,S,rank=NULL,type=0,tol=.Machine$double.eps^.8,unit.fnorm=TRUE) {
## X is an n by p model matrix. S is a p by p
## +ve semi definite penalty matrix, with the 
## given rank. type 0 reparameterization leaves
## the penalty matrix as a diagonal, type 1 
## reduces it to the identity. 
## type 2 is not really natural. It simply converts the 
## penalty to rank deficient identity, with some attempt to
## control the condition number sensibly. type 2 is most 
## efficient, but has highest condition.  
## unit.fnorm == TRUE implies that the model matrix should be
## rescaled so that its penalized and unpenalized model matrices 
## both have unit Frobenious norm. 
## For natural param as in the book, type=0 and unit.fnorm=FALSE.
  null.exists <- rank < ncol(X) ## is there a null space, or is smooth full rank
  if (type==2) { ## no need for QR step
    er <- eigen(S,symmetric=TRUE)
    if (is.null(rank)||rank<1||rank>ncol(S)) { 
      rank <- sum(er$value>max(er$value)*tol)
    }

    E <- rep(1,ncol(X));E[1:rank] <- sqrt(er$value[1:rank])
    X <- X%*%er$vectors
    col.norm <- colSums(X^2)
    col.norm <- col.norm/E^2 
    ## col.norm[i] is now what norm of ith col will be, unless E modified...
    av.norm <- mean(col.norm[1:rank])
   
    if (null.exists) for (i in (rank+1):ncol(X)) {
       E[i] <- sqrt(col.norm[i]/av.norm)
    }
    P <- t(t(er$vectors)/E) 
    X <- t(t(X)/E)
    if (unit.fnorm) { ## rescale so ||X||_f = 1
      ind <- 1:rank
      scale <- 1/sqrt(mean(X[,ind]^2))
      X[,ind] <- X[,ind]*scale;P[ind,] <- P[ind,]*scale
      if (null.exists) {
        ind <- (rank+1):ncol(X)
        scalef <- 1/sqrt(mean(X[,ind]^2))
        X[,ind] <- X[,ind]*scalef;P[ind,] <- P[ind,]*scalef
      }
    } else scale <- 1
    ## see end for return list defs
    return(list(X=X,D=rep(scale^2,rank),P=P,rank=rank,type=type)) ## type of reparameterization
  }

  qrx <- qr(X)
  R <- qr.R(qrx,complete=FALSE)
  RSR <- forwardsolve(t(R),t(forwardsolve(t(R),t(S))))
  er <- eigen(RSR,symmetric=TRUE)
  if (is.null(rank)||rank<1||rank>ncol(S)) { 
    rank <- sum(er$value>max(er$value)*tol)
  }
  ## D contains +ve elements of diagonal penalty 
  ## (zeroes at the end)...
  D <- er$values[1:rank] 
  ## X is the model matrix...
  X <- qr.Q(qrx,complete=FALSE)%*%er$vectors
  ## P transforms parameters in this parameterization back to 
  ## original parameters...
  P <- backsolve(R,er$vectors)

  if (type==1) { ## penalty should be identity...
    E <- c(sqrt(D),rep(1,ncol(X)-length(D)))
    P <- t(t(P)/E)
    X <- t(t(X)/E) ## X%*%diag(1/E)
    D <- D*0+1
  }

  if (unit.fnorm) { ## rescale so ||X||_f = 1 
    ind <- 1:rank
    scale <- 1/sqrt(mean(X[,ind]^2))
    X[,ind] <- X[,ind]*scale;P[,ind] <- P[,ind]*scale
    D <- D * scale^2
    if (null.exists) {
      ind <- (rank+1):ncol(X)
      scalef <- 1/sqrt(mean(X[,ind]^2))
      X[,ind] <- X[,ind]*scalef;P[,ind] <- P[,ind]*scalef
    }
  } 
  ## unpenalized always at the end...
  list(X=X, ## transformed model matrix
       D=D, ## +ve elements on leading diagonal of penalty
       P=P, ## transforms parameter estimates back to original parameterization
            ## postmultiplying original X by P gives reparam version
       rank=rank, ## penalty rank (number of penalized parameters)
       type=type) ## type of reparameterization
} ## end nat.param


mono.con<-function(x,up=TRUE,lower=NA,upper=NA)
# Takes the knot sequence x for a cubic regression spline and returns a list with 
# 2 elements matrix A and array b, such that if p is the vector of coeffs of the
# spline, then Ap>b ensures monotonicity of the spline.
# up=TRUE gives monotonic increase, up=FALSE gives decrease.
# lower and upper are the optional lower and upper bounds on the spline.
{
  if (is.na(lower)) {lo<-0;lower<-0;} else lo<-1
  if (is.na(upper)) {hi<-0;upper<-0;} else hi<-1
  if (up) inc<-1 else inc<-0
  control<-4*inc+2*lo+hi
  n<-length(x)
  if (n<4) stop("At least three knots required in call to mono.con.")
  A<-matrix(0,4*(n-1)+lo+hi,n)
  b<-array(0,4*(n-1)+lo+hi)
  if (lo*hi==1&&lower>=upper) stop("lower bound >= upper bound in call to mono.con()")
  oo<-.C(C_RMonoCon,as.double(A),as.double(b),as.double(x),as.integer(control),as.double(lower),
         as.double(upper),as.integer(n))
  A<-matrix(oo[[1]],dim(A)[1],dim(A)[2])
  b<-array(oo[[2]],dim(A)[1])
  list(A=A,b=b)
} ## end mono.con


uniquecombs<-function(x) {
## takes matrix x and counts up unique rows
## `unique' now does this in R
if (is.null(x)) stop("x is null")
if (is.null(nrow(x))) stop("x has no row attribute")
if (is.null(ncol(x))) stop("x has no col attribute")
ind <- rep(0,nrow(x))
res<-.C(C_RuniqueCombs,x=as.double(x),ind=as.integer(ind),
        r=as.integer(nrow(x)),c=as.integer(ncol(x)))
n <- res$r*res$c
x <- matrix(res$x[1:n],res$r,res$c)
attr(x,"index") <- res$ind+1 ## C to R index gotcha
x
}

cSplineDes <- function (x, knots, ord = 4)
{ ## cyclic version of spline design...
  require(splines)
  nk <- length(knots)
  if (ord<2) stop("order too low")
  if (nk<ord) stop("too few knots")
  knots <- sort(knots)
  k1 <- knots[1]
  if (min(x)<k1||max(x)>knots[nk]) stop("x out of range")
  xc <- knots[nk-ord+1] ## wrapping involved above this point
  ## copy end intervals to start, for wrapping purposes...
  knots <- c(k1-(knots[nk]-knots[(nk-ord+1):(nk-1)]),knots)
  ind <- x>xc ## index for x values where wrapping is needed
  X1 <- splineDesign(knots,x,ord,outer.ok=TRUE)
  x[ind] <- x[ind] - max(knots) + k1
  if (sum(ind)) {
    X2 <- splineDesign(knots,x[ind],ord,outer.ok=TRUE) ## wrapping part
    X1[ind,] <- X1[ind,] + X2
  }
  X1 ## final model matrix
}




get.var <- function(txt,data,vecMat = TRUE)
# txt contains text that may be a variable name and may be an expression 
# for creating a variable. get.var first tries data[[txt]] and if that 
# fails tries evaluating txt within data (only). Routine returns NULL
# on failure, or if result is not numeric or a factor.
# matrices are coerced to vectors, which facilitates matrix arguments 
# to smooths.
{ x <- data[[txt]]
  if (is.null(x)) 
  { x <- try(eval(parse(text=txt),data,enclos=NULL),silent=TRUE)
    if (inherits(x,"try-error")) x <- NULL
  }
  if (!is.numeric(x)&&!is.factor(x)) x <- NULL
  if (is.matrix(x)) ismat <- TRUE else ismat <- FALSE
  if (vecMat&&is.matrix(x)) x <- as.numeric(x)
  if (ismat) attr(x,"matrix") <- TRUE
  x
}

################################################
## functions for use in `gam(m)' formulae ......
################################################

te <- function(..., k=NA,bs="cr",m=NA,d=NA,by=NA,fx=FALSE,mp=TRUE,np=TRUE,xt=NULL,id=NULL,sp=NULL)
# function for use in gam formulae to specify a tensor product smooth term.
# e.g. te(x0,x1,x2,k=c(5,4,4),bs=c("tp","cr","cr"),m=c(1,1,2),by=x3) specifies a rank 80 tensor  
# product spline. The first basis is rank 5, t.p.r.s. basis penalty order 1, and the next 2 bases
# are rank 4 cubic regression splines with m ignored.  
# k, bs,m,d and fx can be supplied as single numbers or arrays with an element for each basis.
# Returns a list consisting of:
# * margin - a list of smooth.spec objects specifying the marginal bases
# * term   - array of covariate names
# * by     - the by variable name
# * fx     - array indicating which margins should be treated as fixed (i.e unpenalized).
# * label  - label for this term
# * mp - TRUE to use a penalty per dimension, FALSE to use a single penalty
{ vars<-as.list(substitute(list(...)))[-1] # gets terms to be smoothed without evaluation
  dim<-length(vars) # dimension of smoother
  by.var<-deparse(substitute(by),backtick=TRUE) #getting the name of the by variable
  term<-deparse(vars[[1]],backtick=TRUE) # first covariate
  if (dim>1) # then deal with further covariates
  for (i in 2:dim)
  { term[i]<-deparse(vars[[i]],backtick=TRUE)
  }
  for (i in 1:dim) term[i] <- attr(terms(reformulate(term[i])),"term.labels")
  # term now contains the names of the covariates for this model term
  
  # check d - the number of covariates per basis
  if (sum(is.na(d))||is.null(d)) { n.bases<-dim;d<-rep(1,dim)} # one basis for each dimension
  else  # array d supplied, the dimension of each term in the tensor product 
  { d<-round(d)
    ok<-TRUE
    if (sum(d<=0)) ok<-FALSE 
    if (sum(d)!=dim) ok<-FALSE
    if (ok)
    n.bases<-length(d)
    else 
    { warning("something wrong with argument d.")
      n.bases<-dim;d<-rep(1,dim)
    }     
  }
  
  # now evaluate k 
  if (sum(is.na(k))||is.null(k)) k<-5^d 
  else 
  { k<-round(k);ok<-TRUE
    if (sum(k<3)) { ok<-FALSE;warning("one or more supplied k too small - reset to default")}
    if (length(k)==1&&ok) k<-rep(k,n.bases)
    else if (length(k)!=n.bases) ok<-FALSE
    if (!ok) k<-5^d 
  }
  # evaluate fx
  if (sum(is.na(fx))||is.null(fx)) fx<-rep(FALSE,n.bases)
  else if (length(fx)==1) fx<-rep(fx,n.bases)
  else if (length(fx)!=n.bases)
  { warning("dimension of fx is wrong") 
    fx<-rep(FALSE,n.bases)
  }

  # deal with `xt' extras list
  xtra <- list()
  if (is.null(xt)||length(xt)==1) for (i in 1:n.bases) xtra[[i]] <- xt else
  if (length(xt)==n.bases) xtra <- xt else
  stop("xt argument is faulty.")

  # now check the basis types
  if (length(bs)==1) bs<-rep(bs,n.bases)
  if (length(bs)!=n.bases) {warning("bs wrong length and ignored.");bs<-rep("cr",n.bases)}
  bs[d>1&(bs=="cr"|bs=="cs"|bs=="ps"|bs=="cp")]<-"tp"
  # finally the penalty orders
  if (length(m)==1) m<-rep(m,n.bases)
  if (length(m)!=n.bases) 
  { warning("m wrong length and ignored.");m<-rep(0,n.bases)}
  m[m<0]<-0
  # check for repeated variables in function argument list
  if (length(unique(term))!=dim) stop("Repeated variables as arguments of a smooth are not permitted")
  # Now construct smooth.spec objects for the margins
  j<-1 # counter for terms
  margin<-list()
  for (i in 1:n.bases)
  { j1<-j+d[i]-1
    if (is.null(xt)) xt1 <- NULL else xt1 <- xtra[[i]]
    stxt<-"s("
    for (l in j:j1) stxt<-paste(stxt,term[l],",",sep="")
    stxt<-paste(stxt,"k=",deparse(k[i],backtick=TRUE),",bs=",deparse(bs[i],backtick=TRUE),
                ",m=",deparse(m[i],backtick=TRUE),",xt=xt1", ")")
    margin[[i]]<- eval(parse(text=stxt))  # NOTE: fx and by not dealt with here!
    j<-j1+1
  }
  # assemble term.label 
  if (mp) mp <- TRUE else mp <- FALSE
  if (np) np <- TRUE else np <- FALSE
  full.call<-paste("te(",term[1],sep="")
  if (dim>1) for (i in 2:dim) full.call<-paste(full.call,",",term[i],sep="")
  label<-paste(full.call,")",sep="")   # label for parameters of this term
  if (!is.null(id)) { 
    if (length(id)>1) { 
      id <- id[1]
      warning("only first element of `id' used")
    } 
    id <- as.character(id)
  }
  ret<-list(margin=margin,term=term,by=by.var,fx=fx,label=label,dim=dim,mp=mp,np=np,
            id=id,sp=sp)
  class(ret) <- "tensor.smooth.spec"
  ret
} ## end of te

t2 <- function(..., k=NA,bs="cr",m=NA,d=NA,by=NA,xt=NULL,id=NULL,sp=NULL,full=FALSE)
# function for use in gam formulae to specify a type 2 tensor product smooth term.
# e.g. te(x0,x1,x2,k=c(5,4,4),bs=c("tp","cr","cr"),m=c(1,1,2),by=x3) specifies a rank 80 tensor  
# product spline. The first basis is rank 5, t.p.r.s. basis penalty order 1, and the next 2 bases
# are rank 4 cubic regression splines with m ignored.  
# k, bs,m,d and fx can be supplied as single numbers or arrays with an element for each basis.
# Returns a list consisting of:
# * margin - a list of smooth.spec objects specifying the marginal bases
# * term   - array of covariate names
# * by     - the by variable name
# * label  - label for this term
{ vars<-as.list(substitute(list(...)))[-1] # gets terms to be smoothed without evaluation
  dim<-length(vars) # dimension of smoother
  by.var<-deparse(substitute(by),backtick=TRUE) #getting the name of the by variable
  term<-deparse(vars[[1]],backtick=TRUE) # first covariate
  if (dim>1) # then deal with further covariates
  for (i in 2:dim)
  { term[i]<-deparse(vars[[i]],backtick=TRUE)
  }
  for (i in 1:dim) term[i] <- attr(terms(reformulate(term[i])),"term.labels")
  # term now contains the names of the covariates for this model term
  
  # check d - the number of covariates per basis
  if (sum(is.na(d))||is.null(d)) { n.bases<-dim;d<-rep(1,dim)} # one basis for each dimension
  else  # array d supplied, the dimension of each term in the tensor product 
  { d<-round(d)
    ok<-TRUE
    if (sum(d<=0)) ok<-FALSE 
    if (sum(d)!=dim) ok<-FALSE
    if (ok)
    n.bases<-length(d)
    else 
    { warning("something wrong with argument d.")
      n.bases<-dim;d<-rep(1,dim)
    }     
  }
  
  # now evaluate k 
  if (sum(is.na(k))||is.null(k)) k<-5^d 
  else 
  { k<-round(k);ok<-TRUE
    if (sum(k<3)) { ok<-FALSE;warning("one or more supplied k too small - reset to default")}
    if (length(k)==1&&ok) k<-rep(k,n.bases)
    else if (length(k)!=n.bases) ok<-FALSE
    if (!ok) k<-5^d 
  }

  fx <- FALSE

  # deal with `xt' extras list
  xtra <- list()
  if (is.null(xt)||length(xt)==1) for (i in 1:n.bases) xtra[[i]] <- xt else
  if (length(xt)==n.bases) xtra <- xt else
  stop("xt argument is faulty.")

  # now check the basis types
  if (length(bs)==1) bs<-rep(bs,n.bases)
  if (length(bs)!=n.bases) {warning("bs wrong length and ignored.");bs<-rep("cr",n.bases)}
  bs[d>1&(bs=="cr"|bs=="cs"|bs=="ps"|bs=="cp")]<-"tp"
  # finally the penalty orders
  if (length(m)==1) m<-rep(m,n.bases)
  if (length(m)!=n.bases) 
  { warning("m wrong length and ignored.");m<-rep(0,n.bases)}
  m[m<0]<-0
  # check for repeated variables in function argument list
  if (length(unique(term))!=dim) stop("Repeated variables as arguments of a smooth are not permitted")
  # Now construct smooth.spec objects for the margins
  j<-1 # counter for terms
  margin<-list()
  for (i in 1:n.bases)
  { j1<-j+d[i]-1
    if (is.null(xt)) xt1 <- NULL else xt1 <- xtra[[i]]
    stxt<-"s("
    for (l in j:j1) stxt<-paste(stxt,term[l],",",sep="")
    stxt<-paste(stxt,"k=",deparse(k[i],backtick=TRUE),",bs=",deparse(bs[i],backtick=TRUE),
                ",m=",deparse(m[i],backtick=TRUE),",xt=xt1", ")")
    margin[[i]]<- eval(parse(text=stxt))  # NOTE: fx and by not dealt with here!
    j<-j1+1
  }
  # assemble term.label 
 
  full.call<-paste("t2(",term[1],sep="")
  if (dim>1) for (i in 2:dim) full.call<-paste(full.call,",",term[i],sep="")
  label<-paste(full.call,")",sep="")   # label for parameters of this term
  if (!is.null(id)) { 
    if (length(id)>1) { 
      id <- id[1]
      warning("only first element of `id' used")
    } 
    id <- as.character(id)
  }
  full <- as.logical(full)
  if (is.na(full)) full <- FALSE
  ret<-list(margin=margin,term=term,by=by.var,fx=fx,label=label,dim=dim,
            id=id,sp=sp,full=full)
  class(ret) <- "t2.smooth.spec" 
  ret
} ## end of t2



s <- function (..., k=-1,fx=FALSE,bs="tp",m=NA,by=NA,xt=NULL,id=NULL,sp=NULL)
# function for use in gam formulae to specify smooth term, e.g. s(x0,x1,x2,k=40,m=3,by=x3) specifies 
# a rank 40 thin plate regression spline of x0,x1 and x2 with a third order penalty, to be multiplied by
# covariate x3, when it enters the model.
# Returns a list consisting of the names of the covariates, and the name of any by variable,
# a model formula term representing the smooth, the basis dimension, the type of basis
# , whether it is fixed or penalized and the order of the penalty (0 for auto).
# xt contains information to be passed straight on to the basis constructor
{ vars<-as.list(substitute(list(...)))[-1] # gets terms to be smoothed without evaluation

  d<-length(vars) # dimension of smoother
  term<-deparse(vars[[d]],backtick=TRUE,width.cutoff=500) # last term in the ... arguments
  by.var<-deparse(substitute(by),backtick=TRUE,width.cutoff=500) #getting the name of the by variable
  if (by.var==".") stop("by=. not allowed")
  term<-deparse(vars[[1]],backtick=TRUE,width.cutoff=500) # first covariate
  if (term[1]==".") stop("s(.) not yet supported.")
  if (d>1) # then deal with further covariates
  for (i in 2:d)
  { term[i]<-deparse(vars[[i]],backtick=TRUE,width.cutoff=500)
    if (term[i]==".") stop("s(.) not yet supported.")
  }
  for (i in 1:d) term[i] <- attr(terms(reformulate(term[i])),"term.labels")
  # term now contains the names of the covariates for this model term
  # now evaluate all the other 
  k.new <- round(k) # in case user has supplied non-integer basis dimension
  if (!all.equal(k.new,k)) {warning("argument k of s() should be integer and has been rounded")}
  k <- k.new
  # check for repeated variables in function argument list
  if (length(unique(term))!=d) stop("Repeated variables as arguments of a smooth are not permitted")
  # assemble label for term
  full.call<-paste("s(",term[1],sep="")
  if (d>1) for (i in 2:d) full.call<-paste(full.call,",",term[i],sep="")
  label<-paste(full.call,")",sep="") # used for labelling parameters
  if (!is.null(id))  {
    if (length(id)>1) { 
      id <- id[1]
      warning("only first element of `id' used")
    } 
   id <- as.character(id)
  }

  ret<-list(term=term,bs.dim=k,fixed=fx,dim=d,p.order=m,by=by.var,label=label,xt=xt,
            id=id,sp=sp)
  class(ret)<-paste(bs,".smooth.spec",sep="")
  ret
}

#############################################################
## Type 1 tensor product methods start here (i.e. Wood, 2006)
#############################################################

tensor.prod.model.matrix<-function(X)
# X is a list of model matrices, from which a tensor product model matrix is to be produced.
# e.g. ith row is basically X[[1]][i,]%x%X[[2]][i,]%x%X[[3]][i,], but this routine works 
# column-wise, for efficiency
{ m<-length(X)
  X1<-X[[m]]
  n<-nrow(X1)
  if (m>1) for (i in (m-1):1)
  { X0<-X1;X1<-matrix(0,n,0)
    for (j in 1:ncol(X[[i]]))
    X1<-cbind(X1,X[[i]][,j]*X0)
  }
  X1
} ## end tensor.prod.model.matrix

tensor.prod.penalties <- function(S)
# Given a list S of penalty matrices for the marginal bases of a tensor product smoother
# this routine produces the resulting penalties for the tensor product basis. 
# e.g. if S_1, S_2 and S_3 are marginal penalties and I_1, I_2, I_3 are identity matrices 
# of the same dimensions then the tensor product penalties are:
#   S_1 %x% I_2 %x% I_3, I_1 %x% S_2 %x% I_3 and I_1 %*% I_2 %*% S_3
# Note that the penalty list must be in the same order as the model matrix list supplied
# to tensor.prod.model() when using these together.
{ m<-length(S)
  I<-list(); for (i in 1:m) { 
    n<-ncol(S[[i]])
    I[[i]]<-diag(n)
  #  I[[i]][1,1] <- I[[i]][n,n]<-.5 
  }
  TS<-list()
  if (m==1) TS[[1]]<-S[[1]] else
  for (i in 1:m)
  { if (i==1) M0<-S[[1]] else M0<-I[[1]]
    for (j in 2:m)
    { if (i==j) M1<-S[[i]] else M1<-I[[j]] 
      M0<-M0%x%M1
    }
    TS[[i]]<- (M0+t(M0))/2 # ensure exactly symmetric 
  }
  TS
}## end tensor.prod.penalties



smooth.construct.tensor.smooth.spec<-function(object,data,knots)
## the constructor for a tensor product basis object
{ m<-length(object$margin)  # number of marginal bases
  Xm<-list();Sm<-list();nr<-r<-d<-array(0,m)
  C <- NULL
  for (i in 1:m)
  { knt <- dat <- list()
    term <- object$margin[[i]]$term
    for (j in 1:length(term)) { 
      dat[[term[j]]] <- data[[term[j]]]
      knt[[term[j]]] <- knots[[term[j]]] 
    }
    object$margin[[i]]<-smooth.construct(object$margin[[i]],dat,knt)
    Xm[[i]]<-object$margin[[i]]$X
    if (!is.null(object$margin[[i]]$te.ok) && !object$margin[[i]]$te.ok) stop("attempt to use unsuitable marginal smooth class")
    if (length(object$margin[[i]]$S)>1) 
    stop("Sorry, tensor products of smooths with multiple penalties are not supported.")
    Sm[[i]]<-object$margin[[i]]$S[[1]]
    d[i]<-nrow(Sm[[i]])
    r[i]<-object$margin[[i]]$rank
    nr[i]<-object$margin[[i]]$null.space.dim
    if (!is.null(object$margin[[i]]$C)&&nrow(object$margin[[i]]$C)==0) C <- matrix(0,0,0) ## no centering constraint needed
  }
  XP <- list()
  if (object$np) # reparameterize 
  for (i in 1:m)
  { if (object$margin[[i]]$dim==1) {
      if (!inherits(object$margin[[i]],c("cs.smooth","cr.smooth","cyclic.smooth"))) { # these classes already optimal
        x <- get.var(object$margin[[i]]$term,data)
        np <- ncol(object$margin[[i]]$X) ## number of params
        ## note: to avoid extrapolating wiggliness measure
        ## must include extremes as eval points
#        knt <- quantile(unique(x),(0:(np-1))/(np-1)) 
        knt <- seq(min(x),max(x),length=np) ## evaluation points
        pd <- data.frame(knt)
        names(pd) <- object$margin[[i]]$term
        sv <- svd(Predict.matrix(object$margin[[i]],pd))
        if (sv$d[np]/sv$d[1]<.Machine$double.eps^.66) { ## condition number rather high
          XP[[i]] <- NULL
          warning("reparameterization unstable for margin: not done")
        } else {
          XP[[i]] <- sv$v%*%(t(sv$u)/sv$d)
        ##XP[[i]] <- solve(Predict.matrix(object$margin[[i]],pd),tol=0) -- old code - could fail
          Xm[[i]] <- Xm[[i]]%*%XP[[i]]
          Sm[[i]] <- t(XP[[i]])%*%Sm[[i]]%*%XP[[i]]
        }
      } else XP[[i]]<-NULL
    } else XP[[i]]<-NULL
  }
  # scale `nicely' - mostly to avoid problems with lme ...
  for (i in 1:m)  Sm[[i]] <- Sm[[i]]/eigen(Sm[[i]],symmetric=TRUE,only.values=TRUE)$values[1] 
  max.rank<-prod(d)
  r<-max.rank*r/d # penalty ranks
  X<-tensor.prod.model.matrix(Xm)
  if (object$mp) # multiple penalties
  { S<-tensor.prod.penalties(Sm)
    for (i in m:1) if (object$fx[i]) S[[i]]<-NULL # remove penalties for un-penalized margins
  } else # single penalty
  { S<-Sm[[1]];r<-object$margin[[i]]$rank
    if (m>1) for (i in 2:m) 
    { S<-S%x%Sm[[i]]
      r<-r*object$margin[[i]]$rank
    } 
    if (sum(object$fx)==m) 
    { S <- list();object$fixed=TRUE } else
    { S<-list(S);object$fixed=FALSE }
    nr <- max.rank-r
    object$bs.dim<-max.rank
  }

  object$X<-X;object$S<-S;
  object$C <- C ## really just in case a marginal has implies that no cons are needed
  object$df <- ncol(X)
  object$null.space.dim <- prod(nr) # penalty null space rank 
  object$rank<-r
  object$XP <- XP
  class(object)<-"tensor.smooth"
  object
}## end smooth.construct.tensor.smooth.spec

Predict.matrix.tensor.smooth<-function(object,data)
## the prediction method for a tensor product smooth
{ m<-length(object$margin)
  X<-list()
  for (i in 1:m) { 
    term <- object$margin[[i]]$term
    dat <- list()
    for (j in 1:length(term)) dat[[term[j]]] <- data[[term[j]]]
    X[[i]]<-Predict.matrix(object$margin[[i]],dat)
  }
  mxp <- length(object$XP)
  if (mxp>0) 
  for (i in 1:mxp) if (!is.null(object$XP[[i]])) X[[i]] <- X[[i]]%*%object$XP[[i]]
  T <- tensor.prod.model.matrix(X)

  T
}## end Predict.matrix.tensor.smooth

#########################################################################
## Type 2 tensor product methods start here - separate identity penalties
#########################################################################

t2.model.matrix <- function(Xm,rank,full=TRUE) {
## Xm is a list of marginal model matrices.
## The first rank[i] columns of Xm[[i]] are penalized, 
## by a ridge penalty, the remainder are unpenalized. 
## this routine constructs a tensor product model matrix,
## subject to a sequence of non-overlapping ridge penalties.
## If full is TRUE then the result is completely invariant, 
## as each column of each null space is treated separately in
## the construction. Otherwise there is an element of arbitrariness
## in the invariance, as it depends on scaling of the null space 
## columns. 
  Zi <- Xm[[1]][,1:rank[1],drop=FALSE] ## range space basis for first margin
  X2 <- list(Zi)
  lab2 <- "r" ## list of term labels "r" denotes range space
  null.exists <- rank[1] < ncol(Xm[[1]]) ## does null exist for margin 1
  no.null <- FALSE
  if (full) pen2 <- TRUE
  if (null.exists) {
    Xi <- Xm[[1]][,(rank[1]+1):ncol(Xm[[1]]),drop=FALSE] ## null space basis margin 1
    if (full) { 
      pen2[2] <- FALSE
      colnames(Xi) <- as.character(1:ncol(Xi)) 
    }
    X2[[2]] <- Xi ## working model matrix component list
    lab2[2]<- "n" ## "n" is null space
   
  } else no.null <- TRUE ## tensor product will have *no* null space...  

  n.m <- length(Xm) ## number of margins
  X1 <- list()
  n <- nrow(Zi)
  if (n.m>1) for (i in 2:n.m) { ## work through margins...
    Zi <- Xm[[i]][,1:rank[i],drop=FALSE]   ## margin i range space
    null.exists <- rank[i] < ncol(Xm[[i]]) ## does null exist for margin i
    if (null.exists) { 
      Xi <- Xm[[i]][,(rank[i]+1):ncol(Xm[[i]]),drop=FALSE] ## margin i null space
      if (full) colnames(Xi)  <- as.character(1:ncol(Xi))
    } else no.null <- TRUE ## tensor product will have *no* null space...
    X1 <- X2 
    if (full) pen1 <- pen2
    lab1 <- lab2 ## labels
    k <- 1
    for (ii in 1:length(X1)) { ## form products with Zi
      if (!full || pen1[ii]) { ## X1[[ii]] is penalized and treated as a whole
        A <- matrix(0,n,0)
        for (j in 1:ncol(X1[[ii]])) A <- cbind(A,X1[[ii]][,j]*Zi)
        X2[[k]] <- A
        if (full) pen2[k] <- TRUE
        lab2[k] <- paste(lab1[ii],"r",sep="")
        k <- k + 1
      } else { ## X1[[ii]] is un-penalized, columns to be treated separately 
        cnx1 <- colnames(X1[[ii]])
        for (j in 1:ncol(X1[[ii]])) {
          X2[[k]] <- X1[[ii]][,j]*Zi
          lab2[k] <- paste(cnx1[j],"r",sep="")
          pen2[k] <- TRUE
          k <- k + 1
        }
      }
    } ## finished dealing with range space for this margin

    if (null.exists) {
      for (ii in 1:length(X1)) { ## form products with Xi
        if (!full || !pen1[ii]) { ## treat product as whole
          if (full) { ## need column labels to make correct term labels
            cn <- colnames(X1[[ii]]);cnxi <- colnames(Xi)
            cnx2 <- rep("",0)
          }
          A <- matrix(0,n,0)
          for (j in 1:ncol(X1[[ii]])) { 
            if (full) cnx2 <- c(cnx2,paste(cn[j],cnxi,sep="")) ## column labels
            A <- cbind(A,X1[[ii]][,j]*Xi)
          }
          if (full) colnames(A) <- cnx2
          lab2[k] <- paste(lab1[ii],"n",sep="")
          X2[[k]] <- A;
          if (full) pen2[k] <- FALSE ## if full, you only get to here when pen1[i] FALSE
          k <- k + 1
        } else { ## treat cols of Xi separately (full is TRUE)
           cnxi <- colnames(Xi) 
           for (j in 1:ncol(Xi)) {
             X2[[k]] <- X1[[ii]]*Xi[,j]
             lab2[k] <- paste(lab1[ii],cnxi[j],sep="")
             pen2[k] <- TRUE
             k <- k + 1
          }
        }
      }
    } ## finished dealing with null space for this margin
  } ## finished working through margins

  rm(X1)
  ## X2 now contains a sequence of model matrices, all but the last
  ## should have an associated ridge penalty. 
  xc <- unlist(lapply(X2,ncol)) ## number of columns of sub-matrix
  X <- matrix(unlist(X2),n,sum(xc))
  if (!no.null) { 
    xc <- xc[-length(xc)] ## last block unpenalized
    lab2 <- lab2[-length(lab2)] ## don't need label for unpenalized block
  } 
  attr(X,"sub.cols") <- xc ## number of columns in each seperately penalized sub matrix 
  attr(X,"p.lab") <- lab2 ## labels for each penalty, identifying how space is constructed
  ## note that sub.cols/xc only contains dimension of last block if it is penalized
  X
} ## end t2.model.matrix


smooth.construct.t2.smooth.spec <- function(object,data,knots)
## the constructor for an ss-anova style tensor product basis object.
## needs to check `by' variable, to see if a centering constraint
## is required. If it is, then it must be applied here.
{ m <- length(object$margin)  # number of marginal bases
  Xm <- list();Sm <- list();nr <- r <- d <- array(0,m)
  Pm <- list() ## list for matrices by which to postmultiply raw model matris to get repara version
  C <- NULL ## potential constraint matrix
  for (i in 1:m) { ## create marginal model matrices and penalties...
    ## pick up the required variables....
    knt <- dat <- list()
    term <- object$margin[[i]]$term
    for (j in 1:length(term)) { 
      dat[[term[j]]] <- data[[term[j]]]
      knt[[term[j]]] <- knots[[term[j]]] 
    }
    ## construct marginal smooth...
    object$margin[[i]]<-smooth.construct(object$margin[[i]],dat,knt)
    Xm[[i]]<-object$margin[[i]]$X
    if (!is.null(object$margin[[i]]$te.ok) && !object$margin[[i]]$te.ok) 
      stop("attempt to use unsuitable marginal smooth class")
    if (length(object$margin[[i]]$S)>1) 
    stop("Sorry, tensor products of smooths with multiple penalties are not supported.")
    Sm[[i]]<-object$margin[[i]]$S[[1]]
    d[i]<-nrow(Sm[[i]])
    r[i]<-object$margin[[i]]$rank ## rank of penalty for this margin
    nr[i]<-object$margin[[i]]$null.space.dim
   
    ## reparameterize so that penalty is identity (and scaling is nice)...
   
    np <- nat.param(Xm[[i]],Sm[[i]],rank=r[i],type=2,unit.fnorm=TRUE)
   
    Xm[[i]] <- np$X;
    dS <- rep(0,ncol(Xm[[i]]));dS[1:r[i]] <- 1;
    Sm[[i]] <- diag(dS) ## penalty now diagonal
    Pm[[i]] <- np$P ## maps original model matrix to reparameterized
    if (!is.null(object$margin[[i]]$C)&&
        nrow(object$margin[[i]]$C)==0) C <- matrix(0,0,0) ## no centering constraint needed
  } ## margin creation finished

  ## Create the model matrix...

  X <- t2.model.matrix(Xm,r,full=object$full)

  sub.cols <- attr(X,"sub.cols") ## size (cols) of penalized sub blocks

  ## Create penalties, which are simple non-overlapping
  ## partial identity matrices...

  nsc <- length(sub.cols) ## number of penalized sub-blocks of X
  S <- list()
  cxn <- c(0,cumsum(sub.cols))
  if (nsc>0) for (j in 1:nsc) {
    dd <- rep(0,ncol(X));dd[(cxn[j]+1):cxn[j+1]] <- 1
    S[[j]] <- diag(dd)
  }
 
  names(S) <- attr(X,"p.lab")

  if (length(object$fx)==1) object$fx <- rep(object$fx,nsc) else
  if (length(object$fx)!=nsc) {
    warning("fx length wrong from t2 term: ignored")
    object$fx <- rep(FALSE,nsc)
  }

  if (!is.null(object$sp)&&length(object$sp)!=nsc) {
    object$sp <- NULL
    warning("length of sp incorrect in t2: ignored")
  } 

  object$null.space.dim <- ncol(X) - sum(sub.cols) ## penalty null space rank 
  
  ## Create identifiability constraint. Key feature is that it 
  ## only affects the unpenalized parameters...
  nup <- sum(sub.cols[1:nsc]) ## range space rank
  if (is.null(C)) { ## if not null then already determined that constraint not needed
    if (object$null.space.dim==0) C <- matrix(0,0,0) else ## no null space => no constraint
    if (object$null.space.dim==1) C <- ncol(X) else ## might as well use set to zero
    C <- matrix(c(rep(0,nup),colSums(X[,(nup+1):ncol(X),drop=FALSE])),1,ncol(X)) ## constraint on null space
  }

  object$X <- X
  object$S <- S
  object$C <- C 
  if (is.matrix(C)&&nrow(C)==0) object$Cp <- NULL else
  object$Cp <- matrix(colSums(X),1,ncol(X)) ## alternative constraint for prediction
  object$df <- ncol(X)
  
  object$rank <- sub.cols[1:nsc] ## ranks of individual penalties
  object$P <- Pm ## map original marginal model matrices to reparameterized versions
  object$fixed <- as.logical(sum(object$fx)) ## needed by gamm/4
  class(object)<-"t2.smooth"
  object
} ## end of smooth.construct.t2.smooth.spec

Predict.matrix.t2.smooth <- function(object,data)
## the prediction method for a t2 tensor product smooth
{ m <- length(object$margin)
  X <- list()
  rank <- rep(0,m)
  for (i in 1:m) { 
    term <- object$margin[[i]]$term
    dat <- list()
    for (j in 1:length(term)) dat[[term[j]]] <- data[[term[j]]]
    X[[i]]<-Predict.matrix(object$margin[[i]],dat)%*%object$P[[i]]
    rank[i] <-  object$margin[[i]]$rank
  }
  T <- t2.model.matrix(X,rank,full=object$full)
  T
} ## end of Predict.matrix.t2.smooth

split.t2.smooth <- function(object) {
## function to split up a t2 smooth into a list of separate smooths
  if (!inherits(object,"t2.smooth")) return(object) 
  ind <- 1:ncol(object$S[[1]])                   ## index of penalty columns 
  ind.para <- object$first.para:object$last.para ## index of coefficients 
  sm <- list() ## list to receive split up smooths
  sm[[1]] <- object ## stores everything in original object
  St <- object$S[[1]]*0
  for (i in 1:length(object$S)) { ## work through penalties
    indi <- ind[diag(object$S[[i]])!=0] ## index of penalized coefs.
    label <- paste(object$label,".frag",i,sep="")
    sm[[i]] <- list(S = list(object$S[[i]][indi,indi]), ## the penalty
                    first.para = min(ind.para[indi]),
                    last.para = max(ind.para[indi]),
                    fx=object$fx[i],fixed=object$fx[i],
                    sp=object$sp[i],
                    null.space.dim=0,
                    df = length(indi),
                    rank=object$rank[i],
                    label=label,
                    S.scale=object$S.scale[i] 
     ) 
     class(sm[[i]]) <- "t2.frag"
     St <- St + object$S[[i]]
   }
   ## now deal with the null space (alternative would be to append this to one of penalized terms)
   i <- length(object$S) + 1
   indi <- ind[diag(St)==0] ## index of unpenalized elements
   if (length(indi)) { ## then there are unplenalized elements
      label <- paste(object$label,".frag",i,sep="")
      sm[[i]] <- list(S = NULL, ## the penalty
                    first.para = min(ind.para[indi]),
                    last.para = max(ind.para[indi]),
                    fx=TRUE,fixed=TRUE,
                    null.space.dim=0,
                    label = label,
                    df = length(indi)
     ) 
     class(sm[[i]]) <- "t2.frag"
   }
   sm
}

expand.t2.smooths <- function(sm) {
## takes a list that may contain `t2.smooth' objects, and expands it into 
## a list of `smooths' with single penalties  
  m <- length(sm)
  not.needed <- TRUE
  for (i in 1:m) if (inherits(sm[[i]],"t2.smooth")&&length(sm[[i]]$S)>1) { not.needed <- FALSE;break}
  if (not.needed) return(NULL)
  smr <- list() ## return list
  k <- 0
  for (i in 1:m) {
    if (inherits(sm[[i]],"t2.smooth")) {
      smi <- split.t2.smooth(sm[[i]])
      comp.ind <- (k+1):(k+length(smi)) ## index of all fragments making up complete smooth
      for (j in 1:length(smi)) {
        k <- k + 1
        smr[[k]] <- smi[[j]]
        smr[[k]]$comp.ind <- comp.ind
      }
    } else { k <- k+1; smr[[k]] <- sm[[i]] } 
  }
  smr ## return expanded list
}

##########################################################
## Thin plate regression splines (tprs) methods start here
##########################################################

null.space.dimension<-function(d,m)
# vectorized function for calculating null space dimension for penalties of order m
# for dimension d data M=(m+d-1)!/(d!(m-1)!). Any m not satisfying 2m>d is reset so 
# that 2m>d+1 (assuring "visual" smoothness) 
{ if (sum(d<0)) stop("d can not be negative in call to null.space.dimension().")
  ind<-2*m<d+1
  if (sum(ind)) # then default m required for some elements
  { m[ind]<-1;ind<-2*m<d+2
    while (sum(ind)) { m[ind]<-m[ind]+1;ind<-2*m<d+2;}
  }
  M<-m*0+1;ind<-M==1;i<-0
  while(sum(ind))
  { M[ind]<-M[ind]*(d[ind]+m[ind]-1-i);i<-i+1;ind<-i<d
  }
  ind<-d>1;i<-2
  while(sum(ind))
  { M[ind]<-M[ind]/i;ind<-d>i;i<-i+1   
  }
  M
}



smooth.construct.tp.smooth.spec<-function(object,data,knots)
## The constructor for a t.p.r.s. basis object.
{ shrink <- attr(object,"shrink")
  ## deal with possible extra arguments of "tp" type smooth
  xtra <- list()

  if (is.null(object$xt$max.knots)) xtra$max.knots <- 3000 
  else xtra$max.knots <- object$xt$max.knots 
  if (is.null(object$xt$seed)) xtra$seed <- 1 
  else xtra$seed <- object$xt$seed 
  ## now collect predictors
  x<-array(0,0)
  shift<-array(0,object$dim)
  for (i in 1:object$dim) 
  { ## xx <- get.var(object$term[[i]],data)
    xx <- data[[object$term[i]]]
    shift[i]<-mean(xx)  # centre covariates
    xx <- xx - shift[i]
    if (i==1) n <- length(xx) else 
    if (n!=length(xx)) stop("arguments of smooth not same dimension")
    x<-c(x,xx)
  }
  if (is.null(knots)) {knt<-0;nk<-0}
  else 
  { knt<-array(0,0)
    for (i in 1:object$dim) 
    { dum <- knots[[object$term[i]]]-shift[i]
      if (is.null(dum)) {knt<-0;nk<-0;break} # no valid knots for this term
      knt <- c(knt,dum)
      nk0 <- length(dum)
      if (i > 1 && nk != nk0) 
      stop("components of knots relating to a single smooth must be of same length")
      nk <- nk0
    }
  }
  if (nk>n) { nk <- 0
  warning("more knots than data in a tp term: knots ignored.")}
  ## deal with possibility of large data set
  if (nk==0 && n>xtra$max.knots) { ## then there *may* be too many data  
    xu <- uniquecombs(matrix(x,n,object$dim)) ## find the unique `locations'
    nu <- nrow(xu)  ## number of unique locations
    if (nu>xtra$max.knots) { ## then there is really a problem 
      seed <- get(".Random.seed",envir=.GlobalEnv) ## store RNG seed
      kind <- RNGkind(NULL)
      RNGkind("default","default")
      set.seed(xtra$seed) ## ensure repeatability
      nk <- xtra$max.knots ## going to create nk knots
      ind <- sample(1:nu,nk,replace=FALSE)  ## by sampling these rows from xu
      knt <- as.numeric(xu[ind,])  ## ... like this
      RNGkind(kind[1],kind[2])
      assign(".Random.seed",seed,envir=.GlobalEnv) ## RNG behaves as if it had not been used
    }
  } ## end of large data set handling
  if (object$bs.dim[1]<0) object$bs.dim <- 10*3^(object$dim-1) # auto-initialize basis dimension
  object$p.order[is.na(object$p.order)] <- 0 ## auto-initialize
  k<-object$bs.dim 
  M<-null.space.dimension(object$dim,object$p.order) 
  if (k<M+1) # essential or construct_tprs will segfault, as tprs_setup does this
  { k<-M+1
    object$bs.dim<-k
    warning("basis dimension, k, increased to minimum possible\n")
  }
  

  X<-array(0,n*k)
  S<-array(0,k*k)
 
  UZ<-array(0,(n+M)*k)
  Xu<-x
  C<-array(0,k)
  nXu<-0  
  oo<-.C(C_construct_tprs,as.double(x),as.integer(object$dim),as.integer(n),as.double(knt),as.integer(nk),
               as.integer(object$p.order[1]),as.integer(object$bs.dim),X=as.double(X),S=as.double(S),
               UZ=as.double(UZ),Xu=as.double(Xu),n.Xu=as.integer(nXu),C=as.double(C))
  object$X<-matrix(oo$X,n,k)                   # model matrix

  object$S<-list()
  if (!object$fixed) 
  { object$S[[1]]<-matrix(oo$S,k,k)         # penalty matrix
    object$S[[1]]<-(object$S[[1]]+t(object$S[[1]]))/2 # ensure exact symmetry
    if (!is.null(shrink)) # then add shrinkage term to penalty 
    { ## pre- 1.5 code the identity term could dominate the small eigenvales
      ## and really mess up the penalty...
      ## norm <- mean(object$S[[1]]^2)^0.5
      ## object$S[[1]] <- object$S[[1]] + diag(k)*norm*abs(shrink)
      
      ## Modify the penalty by increasing the penalty on the 
      ## unpenalized space from zero... 
      es <- eigen(object$S[[1]],symmetric=TRUE)
      ## now add a penalty on the penalty null space
      es$values[(k-M+1):k] <- es$values[k-M]*shrink 
      ## ... so penalty on null space is still less than that on range space.
      object$S[[1]] <- es$vectors%*%(as.numeric(es$values)*t(es$vectors))
    }
  }
  UZ.len <- (oo$n.Xu+M)*k
  object$UZ<-matrix(oo$UZ[1:UZ.len],oo$n.Xu+M,k)         # truncated basis matrix
  Xu.len <- oo$n.Xu*object$dim
  object$Xu<-matrix(oo$Xu[1:Xu.len],oo$n.Xu,object$dim)  # unique covariate combinations

  object$df<-object$bs.dim                   # DoF unconstrained and unpenalized
  object$shift<-shift                          # covariate shifts
  if (is.null(shrink)) { 
    object$rank <- k-M 
  } else object$rank <- k                             # penalty rank
  object$null.space.dim<-M

  class(object)<-"tprs.smooth"
  object
}

smooth.construct.ts.smooth.spec<-function(object,data,knots)
# implements a class of tprs like smooths with an additional shrinkage
# term in the penalty... this allows for fully integrated GCV model selection
{ attr(object,"shrink") <- 1e-1
  object <- smooth.construct.tp.smooth.spec(object,data,knots)
  class(object) <- "ts.smooth"
  object
}

Predict.matrix.tprs.smooth<-function(object,data)
# prediction matrix method for a t.p.r.s. term 
{ x<-array(0,0)
  for (i in 1:object$dim) 
  { xx <- data[[object$term[i]]]
    xx <- xx - object$shift[i]
    if (i==1) n <- length(xx) else 
    if (length(xx)!=n) stop("arguments of smooth not same dimension")
    if (length(xx)<1) stop("no data to predict at")
    x<-c(x,xx)
  }

  by<-0;by.exists<-FALSE

  X<-matrix(0,n,object$bs.dim)
  oo<-.C(C_predict_tprs,as.double(x),as.integer(object$dim),as.integer(n),as.integer(object$p.order),
      as.integer(object$bs.dim),as.integer(object$null.space.dim),as.double(object$Xu),
      as.integer(nrow(object$Xu)),as.double(object$UZ),as.double(by),as.integer(by.exists),X=as.double(X))
  X<-matrix(oo$X,n,object$bs.dim)

  X
}

Predict.matrix.ts.smooth<-function(object,data)
# this is the prediction method for a t.p.r.s
# with shrinkage
{ Predict.matrix.tprs.smooth(object,data)
}


#############################################
## Cubic regression spline methods start here
#############################################


smooth.construct.cr.smooth.spec<-function(object,data,knots)
# this routine is the constructor for cubic regression spline basis objects
# It takes a cubic regression spline specification object and returns the 
# corresponding basis object.
{ shrink <- attr(object,"shrink")
  if (length(object$term)!=1) stop("Basis only handles 1D smooths")
  x <- data[[object$term]]
  nx<-length(x)
  if (is.null(knots)) ok <- FALSE
  else 
  { k <- knots[[object$term]]
    if (is.null(k)) ok <- FALSE
    else ok<-TRUE
  }
    
  if (object$bs.dim < 0) object$bs.dim <- 10 ## default

  if (object$bs.dim <3) { object$bs.dim <- 3
    warning("basis dimension, k, increased to minimum possible\n")
  }

  nk <- object$bs.dim
  if (!ok) { k <- rep(0,nk);k[2]<- -1}
  
  if (length(k)!=nk) stop("number of supplied knots != k for a cr smooth")

  X <- rep(0,nx*nk);S<-rep(0,nk*nk);C<-rep(0,nk);control<-0
  
  if (length(unique(x))<nk) 
  { msg <- paste(object$term," has insufficient unique values to support ",
                 nk," knots: reduce k.",sep="")
    stop(msg)
  }

  oo <- .C(C_construct_cr,as.double(x),as.integer(nx),as.double(k),
           as.integer(nk),as.double(X),as.double(S),
           as.double(C),as.integer(control))

  object$X <- matrix(oo[[5]],nx,nk)

  object$S<-list()     # only return penalty if term not fixed
  if (!object$fixed) 
  { object$S[[1]] <- matrix(oo[[6]],nk,nk)
    object$S[[1]]<-(object$S[[1]]+t(object$S[[1]]))/2 # ensure exact symmetry
    if (!is.null(shrink)) # then add shrinkage term to penalty 
    { ## Following is pre-1.5 code. Approach was not general enough
      ## as identity term could dominate the small eigenvalues
      ## and really ness up the penalty
      ## norm <- mean(object$S[[1]]^2)^0.5
      ## object$S[[1]] <- object$S[[1]] + diag(nk)*norm*abs(shrink)
      
      ## Modify the penalty by increasing the penalty on the 
      ## unpenalized space from zero... 
      es <- eigen(object$S[[1]],symmetric=TRUE)
      ## now add a penalty on the penalty null space
      es$values[nk-1] <- es$values[nk-2]*shrink 
      es$values[nk] <- es$values[nk-1]*shrink
      ## ... so penalty on null space is still less than that on range space.
      object$S[[1]] <- es$vectors%*%(as.numeric(es$values)*t(es$vectors))
    }
  }
  if (is.null(shrink)) { 
    object$rank <- nk-2 
  } else object$rank <- nk   # penalty rank

  object$df<-object$bs.dim # degrees of freedom,  unconstrained and unpenalized
  object$null.space.dim <- 2
  object$xp <- oo[[3]]  # knot positions 
  class(object) <- "cr.smooth"
  object
}

smooth.construct.cs.smooth.spec<-function(object,data,knots)
# implements a class of cr like smooths with an additional shrinkage
# term in the penalty... this allows for fully integrated GCV model selection
{ attr(object,"shrink") <- .1
  object <- smooth.construct.cr.smooth.spec(object,data,knots)
  class(object) <- "cs.smooth"
  object
}


Predict.matrix.cr.smooth<-function(object,data)
# this is the prediction method for a cubic regression spline
{
  x <- data[[object$term]]
  if (length(x)<1) stop("no data to predict at")
  nx<-length(x)
  nk<-object$bs.dim
  X <- rep(0,nx*nk);S<-rep(0,nk*nk);C<-rep(0,nk);control<-0

  oo <- .C(C_construct_cr,as.double(x),as.integer(nx),as.double(object$xp),
            as.integer(object$bs.dim),as.double(X),as.double(S),
                   as.double(C),as.integer(control))
  X<-matrix(oo[[5]],nx,nk) # the prediction matrix

  X
}

Predict.matrix.cs.smooth<-function(object,data)
# this is the prediction method for a cubic regression spline 
# with shrinkage
{ Predict.matrix.cr.smooth(object,data)
}

#####################################################
## Cyclic cubic regression spline methods starts here
#####################################################


place.knots<-function(x,nk)
# knot placement code. x is a covariate array, nk is the number of knots,
# and this routine spaces nk knots evenly throughout the x values, with the 
# endpoints at the extremes of the data.
{ x<-sort(unique(x));n<-length(x)
  if (nk>n) stop("more knots than unique data values is not allowed")
  if (nk<2) stop("too few knots")
  if (nk==2) return(range(x))
  delta<-(n-1)/(nk-1) # how many data steps per knot
  lbi<-floor(delta*1:(nk-2))+1 # lower interval bound index
  frac<-delta*1:(nk-2)+1-lbi # left over proportion of interval  
  x.shift<-x[-1]
  knot<-array(0,nk)
  knot[nk]<-x[n];knot[1]<-x[1]
  knot[2:(nk-1)]<-x[lbi]*(1-frac)+x.shift[lbi]*frac
  knot
}

smooth.construct.cc.smooth.spec<-function(object,data,knots)
# constructor function for cyclic cubic splines
{ getBD<-function(x)
  # matrices B and D in expression Bm=Dp where m are s"(x_i) and 
  # p are s(x_i) and the x_i are knots of periodic spline s(x)
  # B and D slightly modified (for periodicity) from Lancaster 
  # and Salkauskas (1986) Curve and Surface Fitting section 4.7.
  { n<-length(x)
    h<-x[2:n]-x[1:(n-1)]
    n<-n-1
    D<-B<-matrix(0,n,n)
    B[1,1]<-(h[n]+h[1])/3;B[1,2]<-h[1]/6;B[1,n]<-h[n]/6
    D[1,1]<- -(1/h[1]+1/h[n]);D[1,2]<-1/h[1];D[1,n]<-1/h[n]
    for (i in 2:(n-1))
    { B[i,i-1]<-h[i-1]/6
      B[i,i]<-(h[i-1]+h[i])/3
      B[i,i+1]<-h[i]/6
      D[i,i-1]<-1/h[i-1]
      D[i,i]<- -(1/h[i-1]+1/h[i])
      D[i,i+1]<- 1/h[i]
    }
    B[n,n-1]<-h[n-1]/6;B[n,n]<-(h[n-1]+h[n])/3;B[n,1]<-h[n]/6
    D[n,n-1]<-1/h[n-1];D[n,n]<- -(1/h[n-1]+1/h[n]);D[n,1]<-1/h[n]
    list(B=B,D=D)
  } # end of getBD local function
  # evaluate covariate, x, and knots, k.
  if (length(object$term)!=1) stop("Basis only handles 1D smooths")
  x <- data[[object$term]]
  if (object$bs.dim < 0 ) object$bs.dim <- 10 ## default
  if (object$bs.dim <4) { object$bs.dim <- 4
    warning("basis dimension, k, increased to minimum possible\n")
  }

  nk <- object$bs.dim
  k <- knots[[object$term]]
  if (is.null(k)) k <- place.knots(x,nk)   
  if (length(k)==2) {
     k <- place.knots(c(k,x),nk)
  }  

  if (length(k)!=nk) stop("number of supplied knots != k for a cc smooth")

  um<-getBD(k)
  BD<-solve(um$B,um$D) # s"(k)=BD%*%s(k) where k are knots minus last knot
  if (!object$fixed)
  { object$S<-list(t(um$D)%*%BD)      # the penalty
    object$S[[1]]<-(object$S[[1]]+t(object$S[[1]]))/2 # ensure exact symmetry
  }
  object$BD<-BD # needed for prediction
  object$xp<-k  # needed for prediction   
  X<-Predict.matrix.cyclic.smooth(object,data) 

  object$X<-X

  object$rank<-ncol(X)-1  # rank of smoother matrix
  object$df<-object$bs.dim-1 # degrees of freedom, accounting for  cycling
  object$null.space.dim <- 1  
  class(object)<-"cyclic.smooth"
  object
}

Predict.matrix.cyclic.smooth<-function(object,data)
# this is the prediction method for a cyclic cubic regression spline
{ pred.mat<-function(x,knots,BD)
  # BD is B^{-1}D. Basis as given in Lancaster and Salkauskas (1986)
  # Curve and Surface fitting, but wrapped to give periodic smooth.
  { j<-x
    n<-length(knots)
    h<-knots[2:n]-knots[1:(n-1)]
    if (max(x)>max(knots)||min(x)<min(knots)) 
    stop("can't predict outside range of knots with periodic smoother")
    for (i in n:2) j[x<=knots[i]]<-i
    j1<-hj<-j-1
    j[j==n]<-1
    I<-diag(n-1)
    X<-BD[j1,]*as.numeric(knots[j1+1]-x)^3/as.numeric(6*h[hj])+
       BD[j,]*as.numeric(x-knots[j1])^3/as.numeric(6*h[hj])-
       BD[j1,]*as.numeric(h[hj]*(knots[j1+1]-x)/6)-
       BD[j,]*as.numeric(h[hj]*(x-knots[j1])/6) +
       I[j1,]*as.numeric((knots[j1+1]-x)/h[hj]) +
       I[j,]*as.numeric((x-knots[j1])/h[hj])
    X
  }
  x <- data[[object$term]]
  if (length(x)<1) stop("no data to predict at")
  X <- pred.mat(x,object$xp,object$BD)

  X
}

#####################################
## Cyclic P-spline methods start here
#####################################


smooth.construct.cp.smooth.spec<-function(object,data,knots)
## a cyclic p-spline constructor method function
## something like `s(x,bs="cp",m=c(2,1))' to invoke, (which 
## would couple a cubic B-spline basis with a 1st order difference 
## penalty. m==c(0,0) would be linear splines with a ridge penalty). 
{ if (length(object$p.order)==1) m <- rep(object$p.order,2) 
  else m <- object$p.order  ## m[1] - basis order, m[2] - penalty order
  m[is.na(m)] <- 2 ## default
  object$p.order <- m
  if (object$bs.dim<0) object$bs.dim <- max(10,m[1]) ## default
  nk <- object$bs.dim +1  ## number of interior knots
  if (nk<=m[1]) stop("basis dimension too small for b-spline order")
  if (length(object$term)!=1) stop("Basis only handles 1D smooths")
  x <- data[[object$term]]    # find the data
  k <- knots[[object$term]]
  
  if (is.null(k)) { x0 <- min(x);x1 <- max(x) } else
  if (length(k)==2) { 
    x0 <- min(k);x1 <- max(k);
    if (x0>min(x)||x1<max(x)) stop("knot range does not include data")
  } 
  if (is.null(k)||length(k)==2) {
     k <- seq(x0,x1,length=nk)  
  } else {
    if (length(k)!=nk) 
    stop(paste("there should be ",nk," supplied knots"))
  }

  if (length(k)!=nk) stop(paste("there should be",nk,"knots supplied"))

  object$X <- cSplineDes(x,k,ord=m[1]+2)  ## model matrix

  if (!is.null(k)) {
    if (sum(colSums(object$X)==0)>0) warning("knot range is so wide that there is *no* information about some basis coefficients")
  }  

  
  ## now construct penalty...
  p.ord <- m[2]
  np <- ncol(object$X)
  if (p.ord>np-1) stop("penalty order too high for basis dimension")
  De <- diag(np + p.ord)
  if (p.ord>0) { 
    for (i in 1:p.ord) De <- diff(De)
    D <- De[,-(1:p.ord)]
    D[,(np-p.ord+1):np] <-  D[,(np-p.ord+1):np] + De[,1:p.ord]
  } else D <- De
  object$S <- list(t(D)%*%D)  # get penalty

  ## other stuff...
  object$rank <- np-1  # penalty rank
  object$null.space.dim <- 1    # dimension of unpenalized space
  object$knots <- k; object$m <- m      # store p-spline specific info.
  class(object)<-"cpspline.smooth"  # Give object a class
  object
}

Predict.matrix.cpspline.smooth<-function(object,data)
## prediction method function for the cpspline smooth class
{ require(splines)
  X <- cSplineDes(data[[object$term]],object$knots,object$m[1]+2)
  X
}

##############################
## P-spline methods start here
##############################

smooth.construct.ps.smooth.spec<-function(object,data,knots)
# a p-spline constructor method function
{ require(splines)
  if (length(object$p.order)==1) m <- rep(object$p.order,2) 
  else m <- object$p.order  # m[1] - basis order, m[2] - penalty order
  m[is.na(m)] <- 2 ## default
  object$p.order <- m
  if (object$bs.dim<0) object$bs.dim <- max(10,m[1]+1) ## default
  nk <- object$bs.dim - m[1]  # number of interior knots
  if (nk<=0) stop("basis dimension too small for b-spline order")
  if (length(object$term)!=1) stop("Basis only handles 1D smooths")
  x <- data[[object$term]]    # find the data
  k <- knots[[object$term]]
  if (is.null(k)) { xl <- min(x);xu <- max(x) } else
  if (length(k)==2) { 
    xl <- min(k);xu <- max(k);
    if (xl>min(x)||xu<max(x)) stop("knot range does not include data")
  } 
 
  if (is.null(k)||length(k)==2) {
    xr <- xu - xl # data limits and range
    xl <- xl-xr*0.001;xu <- xu+xr*0.001;dx <- (xu-xl)/(nk-1) 
    k <- seq(xl-dx*(m[1]+1),xu+dx*(m[1]+1),length=nk+2*m[1]+2)   
  } else {
    if (length(k)!=nk+2*m[1]+2) 
    stop(paste("there should be ",nk+2*m[1]+2," supplied knots"))
  }
  object$X <- spline.des(k,x,m[1]+2,x*0)$design # get model matrix
  if (!is.null(k)) {
    if (sum(colSums(object$X)==0)>0) warning("knot range is so wide that there is *no* information about some basis coefficients")
  }  

  ## now construct penalty        
  S<-diag(object$bs.dim);
  if (m[2]) for (i in 1:m[2]) S <- diff(S)
  object$S <- list(t(S)%*%S)  # get penalty
  object$S[[1]] <- (object$S[[1]]+t(object$S[[1]]))/2 # exact symmetry
 
  object$rank <- object$bs.dim-m[2]  # penalty rank 
  object$null.space.dim <- m[2]    # dimension of unpenalized space  
  object$knots <- k; object$m <- m      # store p-spline specific info.

  class(object)<-"pspline.smooth"  # Give object a class
  object
}



Predict.matrix.pspline.smooth<-function(object,data)
# prediction method function for the p.spline smooth class
{ require(splines)
  X <- spline.des(object$knots,data[[object$term]],object$m[1]+2)$design
  X
}

##########################################
## Adaptive smooth constructors start here
##########################################

mfil <- function(M,i,j,m) {
## sets M[i[k],j[k]] <- m[k] for all k in 1:length(m) without
## looping....
  nr <- nrow(M)
  a <- as.numeric(M)
  k <- (j-1)*nr+i
  a[k] <- m
  matrix(a,nrow(M),ncol(M))
}


D2 <- function(ni=5,nj=5) {

## Function to obtain second difference matrices for
## coefficients notionally on a regular ni by nj grid
## returns second order differences in each direction +
## mixed derivative, scaled so that
## t(Dcc)%*%Dcc + t(Dcr)%*%Dcr + t(Drr)%*%Drr
## is the discrete analogue of a thin plate spline penalty
## (the 2 on the mixed derivative has been absorbed)
  Ind <- matrix(1:(ni*nj),ni,nj) ## the indexing matrix
  rmt <- rep(1:ni,nj) ## the row index
  cmt <- rep(1:nj,rep(ni,nj)) ## the column index

  ci <- Ind[2:(ni-1),1:nj] ## column index
  n.ci <- length(ci)
  Drr <- matrix(0,n.ci,ni*nj)  ## difference matrices
  rr.ri <- rmt[ci]                              ## index to coef array row
  rr.ci <- cmt[ci]                              ## index to coef array column
 
  Drr <- mfil(Drr,1:n.ci,ci,-2) ## central coefficient
  ci <- Ind[1:(ni-2),1:nj] 
  Drr <- mfil(Drr,1:n.ci,ci,1) ## back coefficient
  ci <- Ind[3:ni,1:nj]
  Drr <- mfil(Drr,1:n.ci,ci,1) ## forward coefficient


  ci <- Ind[1:ni,2:(nj-1)] ## column index
  n.ci <- length(ci)
  Dcc <- matrix(0,n.ci,ni*nj)  ## difference matrices
  cc.ri <- rmt[ci]                              ## index to coef array row
  cc.ci <- cmt[ci]                              ## index to coef array column
 
  Dcc <- mfil(Dcc,1:n.ci,ci,-2) ## central coefficient
  ci <- Ind[1:ni,1:(nj-2)]
  Dcc <- mfil(Dcc,1:n.ci,ci,1) ## back coefficient
  ci <- Ind[1:ni,3:nj]
  Dcc <- mfil(Dcc,1:n.ci,ci,1) ## forward coefficient


  ci <- Ind[2:(ni-1),2:(nj-1)] ## column index
  n.ci <- length(ci)
  Dcr <- matrix(0,n.ci,ni*nj)  ## difference matrices
  cr.ri <- rmt[ci]                              ## index to coef array row
  cr.ci <- cmt[ci]                              ## index to coef array column
 
  ci <- Ind[1:(ni-2),1:(nj-2)] 
  Dcr <- mfil(Dcr,1:n.ci,ci,sqrt(0.125)) ## -- coefficient
  ci <- Ind[3:ni,3:nj] 
  Dcr <- mfil(Dcr,1:n.ci,ci,sqrt(0.125)) ## ++ coefficient
  ci <- Ind[1:(ni-2),3:nj] 
  Dcr <- mfil(Dcr,1:n.ci,ci,-sqrt(0.125)) ## -+ coefficient
  ci <- Ind[3:ni,1:(nj-2)] 
  Dcr <- mfil(Dcr,1:n.ci,ci,-sqrt(0.125)) ## +- coefficient

  list(Dcc=Dcc,Drr=Drr,Dcr=Dcr,rr.ri=rr.ri,rr.ci=rr.ci,cc.ri=cc.ri,
                cc.ci=cc.ci,cr.ri=cr.ri,cr.ci=cr.ci,rmt=rmt,cmt=cmt)
}

smooth.construct.ad.smooth.spec<-function(object,data,knots)
## an adaptive p-spline constructor method function
## This is the simplifies and more efficient version...

{ bs <- object$xt$bs
  if (length(bs)>1) bs <- bs[1]
  if (is.null(bs)) { ## use default bases  
    bs <- "ps"
  } else { # bases supplied, need to sanity check
    if (!bs%in%c("cc","cr","ps","cp")) bs[1] <- "ps"
  }
  if (bs == "cc"||bs=="cp") bsp <- "cp" else bsp <- "ps" ## if basis is cyclic, then so should penalty
  if (object$dim> 2 )  stop("the adaptive smooth class is limited to 1 or 2 covariates.")
  else if (object$dim==1) { ## following is 1D case...
    if (object$bs.dim < 0) object$bs.dim <- 40 ## default
    if (is.na(object$p.order[1])) object$p.order[1] <- 5
    pobject <- object
    pobject$p.order <- c(2,2)
    class(pobject) <- paste(bs[1],".smooth.spec",sep="")
    ## get basic spline object...
    if (is.null(knots)&&bs[1]%in%c("cr","cc")) { ## must create knots
      x <- data[[object$term]]
      knots <- list(seq(min(x),max(x),length=object$bs.dim))
      names(knots) <- object$term
    } ## end of knot creation
    pspl <- smooth.construct(pobject,data,knots)
    nk <- ncol(pspl$X)
    k <- object$p.order[1]   ## penalty basis size 
    if (k>=nk-2) stop("penalty basis too large for smoothing basis")
    if (k <= 0) { ## no penalty 
      pspl$fixed <- TRUE
      pspl$S <- NULL
    } else if (k>=2) { ## penalty basis needed ...
      x <- 1:(nk-2)/nk;m=2
      ## All elements of V must be >=0 for all S[[l]] to be +ve semi-definite 
      if (k==2) V <- cbind(rep(1,nk-2),x) else if (k==3) {
         m <- 1
         ps2 <- smooth.construct(s(x,k=k,bs=bsp,m=m,fx=TRUE),data=data.frame(x=x),knots=NULL)
         V <- ps2$X
      } else { ## general penalty basis construction...
        ps2 <- smooth.construct(s(x,k=k,bs=bsp,m=m,fx=TRUE),data=data.frame(x=x),knots=NULL)
        V <- ps2$X
      }
      Db<-diff(diff(diag(nk))) ## base difference matrix
      D <- list()
     # for (i in 1:k) D[[i]] <- as.numeric(V[,i])*Db
     # L <- matrix(0,k*(k+1)/2,k)
      S <- list();l<-0
      for (i in 1:k) {
        S[[i]] <- t(Db)%*%(as.numeric(V[,i])*Db)
        ind <- rowSums(abs(S[[i]]))>0
        ev <- eigen(S[[i]][ind,ind],symmetric=TRUE,only.values=TRUE)$values
        pspl$rank[i] <- sum(ev>max(ev)*.Machine$double.eps^.9)
      }
      pspl$S <- S
    }
  } else if (object$dim==2){ ## 2D case 
    ## first task is to obtain a tensor product basis
    object$bs.dim[object$bs.dim<0] <- 15 ## default
    k <- object$bs.dim;if (length(k)==1) k <- c(k[1],k[1])
    tec <- paste("te(",object$term[1],",",object$term[2],",bs=bs,k=k,m=2)",sep="")
    pobject <- eval(parse(text=tec)) ## tensor smooth specification object
    pobject$np <- FALSE ## do not re-parameterize
    if (is.null(knots)&&bs[1]%in%c("cr","cc")) { ## create suitable knots 
      for (i in 1:2) {
        x <- data[[object$term[i]]]
        knots <- list(seq(min(x),max(x),length=k[i]))
        names(knots)[i] <- object$term[i]
      } 
    } ## finished knots
    pspl <- smooth.construct(pobject,data,knots) ## create basis
    ## now need to create the adaptive penalties...
    ## First the penalty basis...
    kp <- object$p.order
   
    if (length(kp)!=2) kp <- c(kp[1],kp[1])
    kp[is.na(kp)] <- 3 ## default
   
    kp.tot <- prod(kp);k.tot <- (k[1]-2)*(k[2]-2) ## rows of Difference matrices   
    if (kp.tot > k.tot) stop("penalty basis too large for smoothing basis") 
    
    if (kp.tot <= 0) { ## no penalty 
      pspl$fixed <- TRUE
      pspl$S <- NULL
    } else { ## penalized, but how?
      Db <- D2(ni=k[1],nj=k[2]) ## get the difference-on-grid matrices
      pspl$S <- list() ## delete original S list
      if (kp.tot==1) { ## return a single fixed penalty
        pspl$S[[1]] <- t(Db[[1]])%*%Db[[1]] + t(Db[[2]])%*%Db[[2]] +
                       t(Db[[3]])%*%Db[[3]]
        pspl$rank <- ncol(pspl$S[[1]]) - 3
      } else { ## adaptive 
        if (kp.tot==3) { ## planar adaptiveness
          V <- cbind(rep(1,k.tot),Db[[4]],Db[[5]])
        } else { ## spline adaptive penalty...
          ## first check sanity of basis dimension request
          ok <- TRUE
          if (sum(kp<2)) ok <- FALSE
         
          if (!ok) stop("penalty basis too small")
          m <- min(min(kp)-2,1); m<-c(m,m);j<-1
          ps2 <- smooth.construct(te(i,j,bs=bsp,k=kp,fx=TRUE,m=m,np=FALSE),
                                data=data.frame(i=Db$rmt,j=Db$cmt),knots=NULL) 
          Vrr <- Predict.matrix(ps2,data.frame(i=Db$rr.ri,j=Db$rr.ci))
          Vcc <- Predict.matrix(ps2,data.frame(i=Db$cc.ri,j=Db$cc.ci))
          Vcr <- Predict.matrix(ps2,data.frame(i=Db$cr.ri,j=Db$cr.ci))
        } ## spline adaptive basis finished
        ## build penalty list
      
        S <- list()
        for (i in 1:kp.tot) {
          S[[i]] <- t(Db$Drr)%*%(as.numeric(Vrr[,i])*Db$Drr) + t(Db$Dcc)%*%(as.numeric(Vcc[,i])*Db$Dcc) +
                    t(Db$Dcr)%*%(as.numeric(Vcr[,i])*Db$Dcr)
          ev <- eigen(S[[i]],symmetric=TRUE,only.values=TRUE)$values
          pspl$rank[i] <- sum(ev>max(ev)*.Machine$double.eps*10)
        }

        pspl$S <- S
        pspl$pen.smooth <- ps2 ## the penalty smooth object
      } ## adaptive penalty finished
    } ## penalized case finished
  } 
  pspl$te.ok <- FALSE ## not suitable as a tensor product marginal
  pspl
}


#################################
# Random effects terms start here
#################################


smooth.construct.re.smooth.spec<-function(object,data,knots)
## a simple random effects constructor method function
## basic idea is that s(x,f,z,...,bs="re") generates model matrix
## corresponding to ~ x:f:z: ... - 1. Corresponding coefficients 
## have an identity penalty.
{ 
  ## id's with factor variables are problematic - should terms have
  ## same levels, or just same number of levels, for example? 
  ## => ruled out
  if (!is.null(object$id)) stop("random effects don't work with ids.")
  
  form <- as.formula(paste("~",paste(object$term,collapse=":"),"-1"))
  object$X <- model.matrix(form,data)
  object$bs.dim <- ncol(object$X)
 
  ## now construct penalty        
  object$S <- list(diag(object$bs.dim))  # get penalty
 
  object$rank <- object$bs.dim  # penalty rank 
  object$null.space.dim <- 0    # dimension of unpenalized space 

  object$C <- matrix(0,0,ncol(object$X)) # null constraint matrix

  ## need to store formula (levels taken care of by calling function)
  object$form <- form

  object$plot.me <- FALSE ## "re" terms should not be plotted by plot.gam
  object$te.ok <- FALSE ## these terms are not suitable as te marginals

  class(object)<-"random.effect"  # Give object a class

  object
}



Predict.matrix.random.effect<-function(object,data)
# prediction method function for the p.spline smooth class
{ require(splines)
  X <- model.matrix(object$form,data)
  X
}




############################
## The generics and wrappers
############################


smooth.construct <- function(object,data,knots) UseMethod("smooth.construct")

smooth.construct2 <- function(object,data,knots) {
## This routine does not require that `data' contains only
## the evaluated `object$term's and the `by' variable... it
## obtains such a data object from `data' and also deals with
## multiple evaluations at the same covariate points efficiently

  dk <- ExtractData(object,data,knots) 
  object <- smooth.construct(object,dk$data,dk$knots)
  ind <- attr(dk$data,"index") ## repeats index 
  if (!is.null(ind)) { ## unpack the model matrix
    offs <- attr(object$X,"offset")
    object$X <- object$X[ind,]
    if (!is.null(offs)) attr(object$X,"offset") <- offs[ind]
  } 
  object
}

smooth.construct3 <- function(object,data,knots) {
## This routine does not require that `data' contains only
## the evaluated `object$term's and the `by' variable... it
## obtains such a data object from `data' and also deals with
## multiple evaluations at the same covariate points efficiently
## In contrast to smooth.constuct2 it returns an object in which
## `X' contains the rows required to make the full model matrix,
## and ind[i] tells you which row of `X' is the ith row of the
## full model matrix. If `ind' is NULL then `X' is the full model matrix. 
  dk <- ExtractData(object,data,knots) 
  object <- smooth.construct(object,dk$data,dk$knots)
  ind <- attr(dk$data,"index") ## repeats index 
  object$ind <- ind
  object
}


Predict.matrix <- function(object,data) UseMethod("Predict.matrix")

Predict.matrix2 <- function(object,data) {
   dk <- ExtractData(object,data,NULL) 
   X <- Predict.matrix(object,dk$data)
   ind <- attr(dk$data,"index") ## repeats index
   if (!is.null(ind)) { ## unpack the model matrix
     offs <- attr(X,"offset")
     X <- X[ind,]
     if (!is.null(offs)) attr(X,"offset") <- offs[ind]
   } 
   X
}

Predict.matrix3 <- function(object,data) {
## version of Predict.matrix matching smooth.construct3
   dk <- ExtractData(object,data,NULL) 
   X <- Predict.matrix(object,dk$data)
   ind <- attr(dk$data,"index") ## repeats index
   list(X=X,ind=ind)
}



ExtractData <- function(object,data,knots) {
## `data' and `knots' contain the data needed to evaluate the `terms', `by'
## and `knots' elements of `object'. This routine does so, and returns
## a list with element `data' containing just the evaluated `terms', 
## with the by variable as the last column. If the `terms' evaluate matrices, 
## then a check is made of whether repeat evaluations are being made, 
## and if so only the unique evaluation points are returned in data, along 
## with the `index' attribute required to re-assemble the full dataset.
   knt <- dat <- list()
   for (i in 1:length(object$term)) { 
     dat[[object$term[i]]] <- get.var(object$term[i],data)
     knt[[object$term[i]]] <- get.var(object$term[i],knots)

   }
   names(dat) <- object$term;m <- length(object$term)
   if (!is.null(attr(dat[[1]],"matrix"))) { ## strip down to unique covariate combinations
     n <- length(dat[[1]])
     X <- matrix(unlist(dat),n,m)
     
     if (is.numeric(X)) {
       X <- uniquecombs(X)
       if (nrow(X)<n*.9) { ## worth the hassle
         for (i in 1:m) dat[[i]] <- X[,i]     ## return only unique rows
         attr(dat,"index") <- attr(X,"index") ## index[i] is row of dat[[i]] containing original row i
       }
     } ## end if(is.numeric(X))
   }    
   if (object$by!="NA") {
     by <- get.var(object$by,data) 
     if (!is.null(by))
     { dat[[m+1]] <- by 
       names(dat)[m+1] <- object$by
     }
   }
   return(list(data=dat,knots=knt))
}


#########################################################################
## What follows are the wrapper functions that gam.setup actually
## calls for basis construction, and other functions call for prediction
#########################################################################

smoothCon <- function(object,data,knots,absorb.cons=FALSE,scale.penalty=TRUE,n=nrow(data),
                      dataX = NULL,null.space.penalty = FALSE,sparse.cons=0)
## wrapper function which calls smooth.construct methods, but can then modify
## the parameterization used. If absorb.cons==TRUE then a constraint free
## parameterization is used. 
## Handles `by' variables, and summation convention.
## Note that `data' must be a data.frame or model.frame, unless n is provided explicitly, 
## in which case a list will do.
## If present dataX specifies the data to be used to set up the model matrix, given the 
## basis set up using data (but n same for both).
{ sm <- smooth.construct3(object,data,knots)
  if (!is.null(attr(sm,"qrc"))) warning("smooth objects should not have a qrc attribute.")
 
  ## add plotting indicator if not present.
  ## plot.me tells `plot.gam' whether or not to plot the term
  if (is.null(sm$plot.me)) sm$plot.me <- TRUE

  ## automatically produce centering constraint...
  ## must be done here on original model matrix to ensure same
  ## basis for all `id' linked terms
  if (is.null(sm$C)) {
    if (sparse.cons==0) {
      sm$C <- matrix(colSums(sm$X),1,ncol(sm$X))
    } else { ## use sparse constraints for sparse terms
      if (sum(sm$X==0)>.1*sum(sm$X!=0)) { ## treat term as sparse
        if (sparse.cons==1) {
          xsd <- apply(sm$X,2,FUN=sd)
          if (sum(xsd==0)) ## are any columns constant?
            sm$C <- ((1:length(xsd))[xsd==0])[1] ## index of coef to set to zero
          else {
            ## xz <- colSums(sm$X==0) 
            ## find number of zeroes per column (without big memory footprint)...
            xz <- apply(sm$X,2,FUN=function(x) {sum(x==0)}) 
            sm$C <- ((1:length(xz))[xz==min(xz)])[1] ## index of coef to set to zero
          }
        } else if (sparse.cons==2) {
            sm$C = -1 ## params sum to zero
        } else  { stop("unimplemented sparse constraint type requested") }
      } else { ## it's not sparse anyway 
        sm$C <- matrix(colSums(sm$X),1,ncol(sm$X))
      }
    } ## end of sparse constraint handling
    conSupplied <- FALSE
  } else conSupplied <- TRUE

  ## set df fields (pre-constraint)...
  if (is.null(sm$df)) sm$df <- sm$bs.dim

  ## automatically discard penalties for fixed terms...
  if (!is.null(object$fixed)&&object$fixed) {
    sm$S <- NULL
  }

  ## The following is intended to make scaling `nice' for better gamm performance.
  ## Note that this takes place before any resetting of the model matrix, and 
  ## any `by' variable handling. From a `gamm' perspective this is not ideal, 
  ## but to do otherwise would mess up the meaning of smoothing parameters
  ## sufficiently that linking terms via `id's would not work properly (they 
  ## would have the same basis, but different penalties)

  sm$S.scale <- rep(1,length(sm$S))

  if (scale.penalty && length(sm$S)>0 && is.null(sm$no.rescale)) # then the penalty coefficient matrix is rescaled
  {  maXX <- mean(abs(t(sm$X)%*%sm$X)) # `size' of X'X
      for (i in 1:length(sm$S)) {
        maS <- mean(abs(sm$S[[i]])) / maXX
        sm$S[[i]] <- sm$S[[i]] / maS
        sm$S.scale[i] <- maS ## multiply S[[i]] by this to get original S[[i]]
      } 
  } 

  ## check whether different data to be used for basis setup
  ## and model matrix... 
  if (!is.null(dataX)) { er <- Predict.matrix3(sm,dataX) 
    sm$X <- er$X
    sm$ind <- er$ind
    rm(er)
  }

  ## check whether smooth called with matrix argument
  if ((is.null(sm$ind)&&nrow(sm$X)!=n)||(!is.null(sm$ind)&&length(sm$ind)!=n)) { 
    matrixArg <- TRUE 
    ## now get the number of columns in the matrix argument...
    if (is.null(sm$ind)) q <- nrow(sm$X)/n else q <- length(sm$ind)/n
    if (!is.null(sm$by.done)) warning("handling `by' variables in smooth constructors may not work with the summation convention ")
  } else {
    matrixArg <- FALSE
    if (!is.null(sm$ind)) {  ## unpack model matrix + any offset
      offs <- attr(sm$X,"offset")
      sm$X <- sm$X[sm$ind,]      
      if (!is.null(offs)) attr(sm$X,"offset") <- offs[sm$ind]
    }
  }
  offs <- NULL
  ## pick up "by variables" now, and handle summation convention ...
  if (matrixArg||(object$by!="NA"&&is.null(sm$by.done))) 
  { if (is.null(dataX)) by <- get.var(object$by,data) 
    else by <- get.var(object$by,dataX)
    if (matrixArg&&is.null(by)) { ## then by to be taken as sequence of 1s
      if (is.null(sm$ind)) by <- rep(1,nrow(sm$X)) else by <- rep(1,length(sm$ind))
    }
    if (is.null(by)) stop("Can't find by variable")
    offs <- attr(sm$X,"offset")
    if (is.factor(by)) { 
      if (matrixArg) stop("factor `by' variables can not be used with matrix arguments.")
      sml <- list()
      lev <- levels(by)
      for (j in 1:length(lev)) {
        sml[[j]] <- sm  ## replicate smooth for each factor level
        by.dum <- as.numeric(lev[j]==by)
        sml[[j]]$X <- by.dum*sm$X  ## multiply model matrix by dummy for level
        sml[[j]]$by.level <- lev[j] ## store level
        sml[[j]]$label <- paste(sm$label,":",object$by,lev[j],sep="") 
        if (!is.null(offs)) {
          attr(sml[[j]]$X,"offset") <- offs*by.dum
        }
      }
    } else { ## not a factor by variable
      sml <- list(sm)
      if ((is.null(sm$ind)&&length(by)!=nrow(sm$X))||
          (!is.null(sm$ind)&&length(by)!=length(sm$ind))) stop("`by' variable must be same dimension as smooth arguments")
     
      if (matrixArg) { ## arguments are matrices => summation convention used
        if (is.null(sm$ind)) { ## then the sm$X is in unpacked form
          sml[[1]]$X <- as.numeric(by)*sm$X ## normal `by' handling
          ## Now do the summation stuff....
          ind <- 1:n 
          X <- sml[[1]]$X[ind,]
          for (i in 2:q) {
            ind <- ind + n
            X <- X + sml[[1]]$X[ind,]
          }
          sml[[1]]$X <- X
          if (!is.null(offs)) { ## deal with any term specific offset (i.e. sum it too)
            offs <- attr(sm$X,"offset")*as.numeric(by) ## by variable multiplied version
            ind <- 1:n 
            offX <- offs[ind,]
            for (i in 2:q) {
              ind <- ind + n
              offX <- offX + offs[ind,]
            }
            attr(sml[[1]]$X,"offset") <- offX
          } ## end of term specific offset handling
        } else { ## model sm$X is in packed form to save memory
          ind <- 0:(q-1)*n
          offs <- attr(sm$X,"offset")
          if (!is.null(offs)) offX <- rep(0,n) else offX <- NULL 
          sml[[1]]$X <- matrix(0,n,ncol(sm$X))  
          for (i in 1:n) { ## in this case have to work down the rows
            ind <- ind + 1
            sml[[1]]$X[i,] <- colSums(by[ind]*sm$X[sm$ind[ind],]) 
            if (!is.null(offs)) {
              offX[i] <- sum(offs[sm$ind[ind]]*by[ind])
            }      
          } ## finished all rows
          attr(sml[[1]]$X,"offset") <- offX
        } 
      } else {  ## arguments not matrices => not in packed form + no summation needed 
        sml[[1]]$X <- as.numeric(by)*sm$X
        if (!is.null(offs)) attr(sml[[1]]$X,"offset") <- offs*as.numeric(by)
      }

      sml[[1]]$label <- paste(sm$label,":",object$by,sep="") 
     
      ## test for cases where no centring constraint on the smooth is needed. 
      if (!conSupplied) {
        if (matrixArg) {
          ##q <- nrow(sml[[1]]$X)/n
          L1 <- matrix(by,n,q)%*%rep(1,q)
          if (sd(L1)>mean(L1)*.Machine$double.eps*1000) sml[[1]]$C <- sm$C <- matrix(0,0,1) 
          else sml[[1]]$meanL1 <- mean(L1) ## store mean of L1 for use when adding intecept variability
        } else { ## numeric `by' -- constraint only needed if constant
          if (sd(by)>mean(by)*.Machine$double.eps*1000) sml[[1]]$C <- sm$C <- matrix(0,0,1)   
        }
      } ## end of constraint removal
    }
  } else {
    sml <- list(sm)
  }

  ###########################
  ## absorb constraints.....#
  ###########################

  if (absorb.cons)
  { k<-ncol(sm$X)

    ## If Cp is present it denotes a constraint to use in place of the fitting constraints
    ## when predicting. 

    if (!is.null(sm$Cp)&&is.matrix(sm$Cp)) { ## identifiability cons different for prediction
      pj <- nrow(sm$Cp)
      qrcp <- qr(t(sm$Cp)) 
      for (i in 1:length(sml)) { ## loop through smooth list
        sml[[i]]$Xp <- t(qr.qty(qrcp,t(sml[[i]]$X))[(pj+1):k,]) ## form XZ
        sml[[i]]$Cp <- NULL 
      }
    } else qrcp <- NULL ## rest of Cp processing is after C processing

    if (is.matrix(sm$C)) { ## the fit constraints
      j<-nrow(sm$C)
      if (j>0) # there are constraints
      { indi <- (1:ncol(sm$C))[colSums(sm$C)!=0] ## index of non-zero columns in C
        nx <- length(indi)
        if (nx<ncol(sm$C)) { ## then some parameters are completely constraint free
          nc <- j ## number of constraints
          nz <- nx-nc   ## reduced null space dimension
          qrc <- qr(t(sm$C[,indi,drop=FALSE])) ## gives constraint null space for constrained only
          for (i in 1:length(sml)) { ## loop through smooth list
            if (length(sm$S)>0)
            for (l in 1:length(sm$S)) # some smooths have > 1 penalty 
            { ZSZ <- sml[[i]]$S[[l]]
              ZSZ[indi[1:nz],]<-qr.qty(qrc,sml[[i]]$S[[l]][indi,,drop=FALSE])[(nc+1):nx,] 
              ZSZ <- ZSZ[-indi[(nz+1):nx],]   
              ZSZ[,indi[1:nz]]<-t(qr.qty(qrc,t(ZSZ[,indi,drop=FALSE]))[(nc+1):nx,])
              sml[[i]]$S[[l]] <- ZSZ[,-indi[(nz+1):nx],drop=FALSE]  ## Z'SZ

              ## ZSZ<-qr.qty(qrc,sm$S[[l]])[(j+1):k,]
              ## sml[[i]]$S[[l]]<-t(qr.qty(qrc,t(ZSZ))[(j+1):k,]) ## Z'SZ
            }
            sml[[i]]$X[,indi[1:nz]]<-t(qr.qty(qrc,t(sml[[i]]$X[,indi,drop=FALSE]))[(nc+1):nx,])
            sml[[i]]$X <- sml[[i]]$X[,-indi[(nz+1):nx]]
            ## sml[[i]]$X<-t(qr.qty(qrc,t(sml[[i]]$X))[(j+1):k,]) ## form XZ
            attr(sml[[i]],"qrc") <- qrc
            attr(sml[[i]],"nCons") <- j;
            attr(sml[[i]],"indi") <- indi ## index of constrained parameters
            sml[[i]]$C <- NULL
            sml[[i]]$rank <- pmin(sm$rank,k-j)
            sml[[i]]$df <- sml[[i]]$df - j
            ## ... so qr.qy(attr(sm,"qrc"),c(rep(0,nrow(sm$C)),b)) gives original para.'s
          } ## end smooth list loop
        } else { ## full null space created
          qrc<-qr(t(sm$C)) 
          for (i in 1:length(sml)) { ## loop through smooth list
            if (length(sm$S)>0)
            for (l in 1:length(sm$S)) # some smooths have > 1 penalty 
            { ZSZ<-qr.qty(qrc,sm$S[[l]])[(j+1):k,]
              sml[[i]]$S[[l]]<-t(qr.qty(qrc,t(ZSZ))[(j+1):k,]) ## Z'SZ
            }
            sml[[i]]$X <- t(qr.qty(qrc,t(sml[[i]]$X))[(j+1):k,]) ## form XZ
            attr(sml[[i]],"qrc") <- qrc
            attr(sml[[i]],"nCons") <- j;
            sml[[i]]$C <- NULL
            sml[[i]]$rank <- pmin(sm$rank,k-j)
            sml[[i]]$df <- sml[[i]]$df - j
            ## ... so qr.qy(attr(sm,"qrc"),c(rep(0,nrow(sm$C)),b)) gives original para.'s
            ## and qr.qy(attr(sm,"qrc"),rbind(rep(0,length(b)),diag(length(b)))) gives 
            ## null space basis Z, such that Zb are the original params, subject to con. 
          } ## end smooth list loop
        } # end full null space version of constraint
      } else { ## no constraints
        for (i in 1:length(sml)) {
         attr(sml[[i]],"qrc") <- "no constraints"
         attr(sml[[i]],"nCons") <- 0;
        }
      } ## end else no constraints
    } else if (sm$C>0) { ## set to zero constraints
       for (i in 1:length(sml)) { ## loop through smooth list
          if (length(sm$S)>0)
          for (l in 1:length(sm$S)) # some smooths have > 1 penalty 
          { sml[[i]]$S[[l]] <- sml[[i]]$S[[l]][-sm$C,-sm$C]
          }
          sml[[i]]$X <- sml[[i]]$X[,-sm$C]
          attr(sml[[i]],"qrc") <- sm$C
          attr(sml[[i]],"nCons") <- 1;
          sml[[i]]$C <- NULL
          sml[[i]]$rank <- pmin(sm$rank,k-1)
          sml[[i]]$df <- sml[[i]]$df - 1
          ## so insert an extra 0 at position sm$C in coef vector to get original
        } ## end smooth list loop
    } else if (sm$C <0) { ## params sum to zero 
       for (i in 1:length(sml)) { ## loop through smooth list
          if (length(sm$S)>0)
          for (l in 1:length(sm$S)) # some smooths have > 1 penalty 
          { sml[[i]]$S[[l]] <- diff(t(diff(sml[[i]]$S[[l]])))
          }
          sml[[i]]$X <- t(diff(t(sml[[i]]$X)))
          attr(sml[[i]],"qrc") <- sm$C
          attr(sml[[i]],"nCons") <- 1;
          sml[[i]]$C <- NULL
          sml[[i]]$rank <- pmin(sm$rank,k-1)
          sml[[i]]$df <- sml[[i]]$df - 1
          ## so insert an extra 0 at position sm$C in coef vector to get original
        } ## end smooth list loop       
    }
   
    ## finish of treatment of case where prediction constraints are different
    if (!is.null(qrcp)) {
      for (i in 1:length(sml)) { ## loop through smooth list
        attr(sml[[i]],"qrc") <- qrcp
        if (pj!=attr(sml[[i]],"nCons")) stop("Number of prediction and fit constraints must match")
        attr(sml[[i]],"indi") <- NULL ## no index of constrained parameters for Cp
      }
    }


  } else for (i in 1:length(sml)) attr(sml[[i]],"qrc") <-NULL ## no absorption

  ## The idea here is that term selection can be accomplished as part of fitting 
  ## by applying penalties to the null space of the penalty... 

  if (null.space.penalty) { ## then an extra penalty on the un-penalized space should be added 
    St <- sml[[1]]$S[[1]]
    if (length(sml[[1]]$S)>1) for (i in 1:length(sml[[1]]$S)) St <- St + sml[[1]]$S[[i]]
    es <- eigen(St,symmetric=TRUE)
    ind <- es$values<max(es$values)*.Machine$double.eps^.66
    if (sum(ind)) { ## then there is an unpenalized space remaining
      U <- es$vectors[,ind,drop=FALSE]
      Sf <- U%*%t(U) ## penalty for the unpenalized components
      M <- length(sm$S)
      for (i in 1:length(sml)) {
        sml[[i]]$S[[M+1]] <- Sf
        sml[[i]]$rank[M+1] <- sum(ind)
      }
    }
  }

  sml
} ## end of smoothCon




PredictMat <- function(object,data,n=nrow(data))
## wrapper function which calls Predict.matrix and imposes same constraints as 
## smoothCon on resulting Prediction Matrix
{ X <- Predict.matrix2(object,data)
  if (is.null(attr(X,"by.done"))) { ## handle `by variables' 
    if (object$by!="NA")  # deal with "by" variable 
    { by <- get.var(object$by,data)
      if (is.null(by)) stop("Can't find by variable")
      if (is.factor(by)) {
        by.dum <- as.numeric(object$by.level==by)
        X <- by.dum*X
      } else { 
        if (length(by)!=nrow(X)) stop("`by' variable must be same dimension as smooth arguments")
        X <- as.numeric(by)*X
      }
    }
  }
  attr(X,"by.done") <- NULL
  offset <- attr(X,"offset")

  ## now deal with any necessary model matrix summation
  if (n != nrow(X)) {
    q <- nrow(X)/n ## note: can't get here if `by' a factor
    ind <- 1:n 
    Xs <- X[ind,]
    for (i in 2:q) {
      ind <- ind + n
      Xs <- Xs + X[ind,]
    }
    X <- Xs
  }

  qrc <- attr(object,"qrc")
  if (!is.null(qrc)) { ## then smoothCon absorbed constraints
    j <- attr(object,"nCons")
    if (j>0) { ## there were constraints to absorb - need to untransform
      k<-ncol(X)
      if (inherits(qrc,"qr")) {
        indi <- attr(object,"indi") ## index of constrained parameters
        if (is.null(indi)) {
          if (sum(is.na(X))) {
            ind <- !is.na(rowSums(X))
            X1 <- t(qr.qty(qrc,t(X[ind,,drop=FALSE]))[(j+1):k,,drop=FALSE]) ## XZ
            X <- matrix(NA,nrow(X),ncol(X1))
            X[ind,] <- X1
          } else {
            X <- t(qr.qty(qrc,t(X))[(j+1):k,,drop=FALSE])
          }
        } else { ## only some parameters are subject to constraint
          nx <- length(indi)
          nc <- j;nz <- nx - nc
          if (sum(is.na(X))) {
            ind <- !is.na(rowSums(X))
            X[ind,indi[1:nz]]<-t(qr.qty(qrc,t(X[ind,indi,drop=FALSE]))[(nc+1):nx,])
            X <- X[,-indi[(nz+1):nx]]
            X[!ind,] <- NA 
          } else { 
            X[,indi[1:nz]]<-t(qr.qty(qrc,t(X[,indi,drop=FALSE]))[(nc+1):nx,,drop=FALSE])
            X <- X[,-indi[(nz+1):nx]]
          }
        }
      } else if (qrc>0) { ## simple set to zero constraint
        X <- X[,-qrc]
      } else if (qrc<0) { ## params sum to zero
        X <- t(diff(t(X)))
      }
    }
  }
  ## drop columns eliminated by side-conditions...
  del.index <- attr(object,"del.index") 
  if (!is.null(del.index)) X <- X[,-del.index]
  attr(X,"offset") <- offset
  X
} ## end of PredictMat

