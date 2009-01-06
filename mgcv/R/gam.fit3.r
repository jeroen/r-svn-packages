## R routines for gam fitting with calculation of derivatives w.r.t. sp.s
## (c) Simon Wood 2004-2008

## This routine is for type 3 gam fitting. The basic idea is that a P-IRLS
## is run to convergence, and only then is a scheme for evaluating the 
## derivatives iterated to convergence. The advantage is that many key
## quantities are fixed at this stage, including the key decompositions
## In addition the R side work is simplified considerably.The routine
## evaluates first and second derivatives of the deviance and tr(A).


gam.fit2 <- function (x, y, sp, S=list(),rS=list(),off, H=NULL, 
            weights = rep(1, nobs), start = NULL, etastart = NULL, 
            mustart = NULL, offset = rep(0, nobs), family = gaussian(), 
            control = gam.control(), intercept = TRUE,deriv=2,use.svd=TRUE,
            gamma=1,scale=1,printWarn=TRUE,scoreType="REML",...) 
## deriv, sp, S, rS, H added to arg list. 
## need to modify family before call.
## This is essentially a backup of the version of gam.fit3 implementing a Wood (2008) based
## on derivative iteration, but with Newton extensions. This version will fail if 
## newton weights become negative, but could easily be modified to revert to fisher only.
{   if (family$link==family$canonical) fisher <- TRUE else fisher=FALSE ## Newton = Fisher, but Fisher cheaper!
    if (scale>0) scale.known <- TRUE else scale.known <- FALSE
    scale <- abs(scale)
    if (!deriv%in%c(0,1,2)) stop("unsupported order of differentiation requested of gam.fit3")
    x <- as.matrix(x)
    iter <- 0;coef <- rep(0,ncol(x))
    xnames <- dimnames(x)[[2]]
    ynames <- if (is.matrix(y)) 
        rownames(y)
    else names(y)
    conv <- FALSE
    n <- nobs <- NROW(y) ## n is just to keep codetools happy
    nvars <- ncol(x)
    EMPTY <- nvars == 0
    if (is.null(weights)) 
        weights <- rep.int(1, nobs)
    if (is.null(offset)) 
        offset <- rep.int(0, nobs)
    variance <- family$variance
    dev.resids <- family$dev.resids
    aic <- family$aic
    linkinv <- family$linkinv
    mu.eta <- family$mu.eta
    if (!is.function(variance) || !is.function(linkinv)) 
        stop("illegal `family' argument")
    valideta <- family$valideta
    if (is.null(valideta)) 
        valideta <- function(eta) TRUE
    validmu <- family$validmu
    if (is.null(validmu)) 
        validmu <- function(mu) TRUE
    if (is.null(mustart)) {
        eval(family$initialize)
    }
    else {
        mukeep <- mustart
        eval(family$initialize)
        mustart <- mukeep
    }

    ## Added code
    if (family$family=="gaussian"&&family$link=="identity") strictly.additive <- TRUE else
      strictly.additive <- FALSE
    nSp <- length(S)
    if (nSp==0) deriv <- FALSE 
    St <- totalPenalty(S,H,off,sp,ncol(x))
    Sr <- mroot(St)

    ## end of added code

    D1 <- D2 <- P <- P1 <- P2 <- trA <- trA1 <- trA2 <- 
        GCV<- GCV1<- GCV2<- GACV<- GACV1<- GACV2<- UBRE <-
        UBRE1<- UBRE2<- REML<- REML1<- REML2 <-NULL

    if (EMPTY) {
        eta <- rep.int(0, nobs) + offset
        if (!valideta(eta)) 
            stop("Invalid linear predictor values in empty model")
        mu <- linkinv(eta)
        if (!validmu(mu)) 
            stop("Invalid fitted means in empty model")
        dev <- sum(dev.resids(y, mu, weights))
        w <- ((weights * mu.eta(eta)^2)/variance(mu))^0.5
        residuals <- (y - mu)/mu.eta(eta)
        good <- rep(TRUE, length(residuals))
        boundary <- conv <- TRUE
        coef <- numeric(0)
        iter <- 0
        V <- variance(mu)
        alpha <- dev
        trA2 <- trA1 <- trA <- 0
        if (deriv) GCV2 <- GCV1<- UBRE2 <- UBRE1<-trA1 <- rep(0,nSp)
        GCV <- nobs*alpha/(nobs-gamma*trA)^2
        UBRE <- alpha/nobs - scale + 2*gamma/n*trA
        scale.est <- alpha / (nobs - trA)
    } ### end if (EMPTY)
    else {
        coefold <- NULL
        eta <- if (!is.null(etastart)) 
            etastart
        else if (!is.null(start)) 
            if (length(start) != nvars) 
                stop("Length of start should equal ", nvars, 
                  " and correspond to initial coefs for ", deparse(xnames))
            else {
                coefold <- start
                offset + as.vector(if (NCOL(x) == 1) 
                  x * start
                else x %*% start)
            }
        else family$linkfun(mustart)
        etaold <- eta
        muold <- mu <- linkinv(eta)
        if (!(validmu(mu) && valideta(eta))) 
            stop("Can't find valid starting values: please specify some")
    
        boundary <- conv <- FALSE
        rV=matrix(0,ncol(x),ncol(x))   
        old.pdev <- 0     
        for (iter in 1:control$maxit) {
            good <- weights > 0
            varmu <- variance(mu)[good]
            if (any(is.na(varmu))) 
                stop("NAs in V(mu)")
            if (any(varmu == 0)) 
                stop("0s in V(mu)")
            mu.eta.val <- mu.eta(eta)
            if (any(is.na(mu.eta.val[good]))) 
                stop("NAs in d(mu)/d(eta)")
            good <- (weights > 0) & (mu.eta.val != 0)
            if (all(!good)) {
                conv <- FALSE
                warning("No observations informative at iteration ", 
                  iter)
                break
            }
            mevg<-mu.eta.val[good];mug<-mu[good];yg<-y[good]
            weg<-weights[good];var.mug<-variance(mug)
            if (fisher) { ## Conventional Fisher scoring
              z <- (eta - offset)[good] + (yg - mug)/mevg
              w <- sqrt((weg * mevg^2)/var.mug)
            } else { ## full Newton
              c <- yg - mug
              e <- mevg*(1 + c*(family$dvar(mug)/mevg+var.mug*family$d2link(mug))*mevg/var.mug)
              z <- (eta - offset)[good] + c/e ## offset subtracted as eta = X%*%beta + offset
              w <- sqrt(weg*e*mevg/var.mug)
              ## correct `good', `w' and `z' to remove any zero weights
              if (sum(w==0)) {
                wf <- weights*0
                wf[good] <- w
                good <- (wf!=0)&good
                ind <- w!=0
                w <- w[ind];z <- z[ind]
              }
            }

            ## Here a Fortran call has been replaced by update.beta call
           
            if (sum(good)<ncol(x)) stop("Not enough informative observations.")
     
            oo<-.C(C_pls_fit,y=as.double(z),as.double(x[good,]),as.double(w),as.double(Sr),as.integer(sum(good)),
            as.integer(ncol(x)),as.integer(ncol(Sr)),eta=as.double(z),penalty=as.double(1),
            as.double(.Machine$double.eps*100))
       
            start <- oo$y[1:ncol(x)];
            penalty <- oo$penalty
            eta <- drop(x%*%start)

            if (any(!is.finite(start))) {
                conv <- FALSE
                warning("Non-finite coefficients at iteration ", 
                  iter)
                break
            }        
     
           mu <- linkinv(eta <- eta + offset)
           dev <- sum(dev.resids(y, mu, weights))
          
           if (control$trace) 
                cat("Deviance =", dev, "Iterations -", iter, 
                  "\n")
            boundary <- FALSE
            
            if (!is.finite(dev)) {
                if (is.null(coefold)) 
                  stop("no valid set of coefficients has been found:please supply starting values", 
                    call. = FALSE)
                warning("Step size truncated due to divergence", 
                  call. = FALSE)
                ii <- 1
                while (!is.finite(dev)) {
                  if (ii > control$maxit) 
                    stop("inner loop 1; can't correct step size")
                  ii <- ii + 1
                  start <- (start + coefold)/2
                  eta <- (eta + etaold)/2               
                  mu <- linkinv(eta)
                  dev <- sum(dev.resids(y, mu, weights))
                }
                boundary <- TRUE
                if (control$trace) 
                  cat("Step halved: new deviance =", dev, "\n")
            }
            if (!(valideta(eta) && validmu(mu))) {
                warning("Step size truncated: out of bounds", 
                  call. = FALSE)
                ii <- 1
                while (!(valideta(eta) && validmu(mu))) {
                  if (ii > control$maxit) 
                    stop("inner loop 2; can't correct step size")
                  ii <- ii + 1
                  start <- (start + coefold)/2
                  eta <- (eta + etaold)/2 
                  mu <- linkinv(eta)
                }
                boundary <- TRUE
                dev <- sum(dev.resids(y, mu, weights))
                if (control$trace) 
                  cat("Step halved: new deviance =", dev, "\n")
            }

            pdev <- dev + penalty  ## the penalized deviance 

            if (control$trace) 
                  cat("penalized deviance =", pdev, "\n")

            div.thresh <- 10*(.1+abs(old.pdev))*.Machine$double.eps^.5 
            ## ... threshold for judging divergence --- too tight and near
            ## perfect convergence can cause a failure here

            if (iter>1&&(pdev-old.pdev>div.thresh)) { ## solution diverging
             ii <- 1 ## step halving counter
             while (pdev -old.pdev > div.thresh)  
             { ## step halve until pdev <= old.pdev
                if (ii > 200) 
                   stop("inner loop 3; can't correct step size")
                ii <- ii + 1
                start <- (start + coefold)/2 
                eta <- (eta + etaold)/2               
                mu <- linkinv(eta)
                  dev <- sum(dev.resids(y, mu, weights))
                  pdev <- dev + t(start)%*%St%*%start ## the penalized deviance
                if (control$trace) 
                  cat("Step halved: new penalized deviance =", pdev, "\n")
              }
            } 
            
            if (strictly.additive) { conv <- TRUE;coef <- start;break;}

            if (abs(pdev - old.pdev)/(0.1 + abs(pdev)) < control$epsilon) {
               ## if (max(abs(start-coefold))>control$epsilon*max(abs(start+coefold))/2) {
                if (max(abs(mu-muold))>control$epsilon*max(abs(mu+muold))/2) {
                  old.pdev <- pdev
                  coef <- coefold <- start
                  etaold <- eta 
                  muold <- mu
                } else {
                  conv <- TRUE
                  coef <- start
                  break 
                }
            }
            else {  old.pdev <- pdev
                coef <- coefold <- start
                etaold <- eta 
            }
        } ### end main loop 
       
        dev <- sum(dev.resids(y, mu, weights)) 
       
        ## Now call the derivative calculation scheme. This requires the
        ## following inputs:
        ## z and w - the pseudodata and weights
        ## X the model matrix and E where EE'=S
        ## rS the single penalty square roots
        ## sp the log smoothing parameters
        ## y and mu the data and model expected values
        ## g1,g2,g3 - the first 3 derivatives of g(mu) wrt mu
        ## V,V1,V2 - V(mu) and its first two derivatives wrt mu
        ## on output it returns the gradient and hessian for
        ## the deviance and trA 

         good <- weights > 0
         varmu <- variance(mu)[good]
         if (any(is.na(varmu))) stop("NAs in V(mu)")
         if (any(varmu == 0)) stop("0s in V(mu)")
         mu.eta.val <- mu.eta(eta)
         if (any(is.na(mu.eta.val[good]))) 
                stop("NAs in d(mu)/d(eta)")
         good <- (weights > 0) & (mu.eta.val != 0)
   
         mevg <- mu.eta.val[good];mug <- mu[good];yg <- y[good]
         weg <- weights[good];etag <- eta[good]
         var.mug<-variance(mug)

         if (fisher) { ## Conventional Fisher scoring
              
              z <- (eta - offset)[good] + (yg - mug)/mevg
            
              w <- sqrt((weg * mevg^2)/var.mug)
         } else { ## full Newton
          
              c <- yg - mug
              e <- mevg*(1 + c*(family$dvar(mug)/mevg+var.mug*family$d2link(mug))*mevg/var.mug)
              z <- (eta - offset)[good] + c/e ## offset subtracted as eta = X%*%beta + offset
              w <- sqrt(weg*e*mevg/var.mug)

              ## correct `good', `w' and `z' to remove any zero weights
              if (sum(w==0)) {
                wf <- weights*0
                wf[good] <- w
                good <- (wf!=0)&good
                ind <- w!=0
                w <- w[ind];z <- z[ind]
                mevg <- mu.eta.val[good];mug <- mu[good];yg <- y[good]
                weg <- weights[good];etag <- eta[good]
                var.mug<-variance(mug)
              }
         
         }
        
         g1 <- 1/mevg
         g2 <- family$d2link(mug)
         g3 <- family$d3link(mug)

         V <- family$variance(mug)
         V1 <- family$dvar(mug)
         V2 <- family$d2var(mug)      
        
         if (fisher) {
           g4 <- V3 <- 0
         } else {
           g4 <- family$d4link(mug)
           V3 <- family$d3var(mug)
         }

         if (TRUE) { ### TEST CODE for derivative ratio based versions of code... 
           g2 <- g2/g1;g3 <- g3/g1;g4 <- g4/g1
           V1 <- V1/V;V2 <- V2/V;V3 <- V3/V
         }

         P1 <- D1 <- array(0,nSp);P2 <- D2 <- matrix(0,nSp,nSp) # for derivs of deviance/ Pearson
         trA1 <- array(0,nSp);trA2 <- matrix(0,nSp,nSp) # for derivs of tr(A)
         rV=matrix(0,ncol(x),ncol(x));
         dum <- 1
         if (control$trace) cat("calling gdi...")

       oo <- .C(C_gdi,X=as.double(x[good,]),E=as.double(Sr),rS = as.double(unlist(rS)),
           sp=as.double(exp(sp)),z=as.double(z),w=as.double(w),mu=as.double(mug),eta=as.double(etag),y=as.double(yg),
           p.weights=as.double(weg),g1=as.double(g1),g2=as.double(g2),g3=as.double(g3),g4=as.double(g4),V0=as.double(V),
           V1=as.double(V1),V2=as.double(V2),V3=as.double(V3),beta=as.double(coef),D1=as.double(D1),D2=as.double(D2),
           P=as.double(dum),P1=as.double(P1),P2=as.double(P2),trA=as.double(dum),
           trA1=as.double(trA1),trA2=as.double(trA2),rV=as.double(rV),rank.tol=as.double(.Machine$double.eps*100),
           conv.tol=as.double(control$epsilon),rank.est=as.integer(1),n=as.integer(length(z)),
           p=as.integer(ncol(x)),M=as.integer(nSp),Encol = as.integer(ncol(Sr)),
           rSncol=as.integer(unlist(lapply(rS,ncol))),deriv=as.integer(deriv),use.svd=as.integer(use.svd),
           REML = as.integer(scoreType=="REML"),fisher=as.integer(fisher),fixed.penalty = as.integer(!is.null(H)))      
       
         if (control$trace) cat("done! (iteration took ",oo$deriv," steps)\n")
 
         rV <- matrix(oo$rV,ncol(x),ncol(x))
         coef <- oo$beta;
         trA <- oo$trA;
         scale.est <- dev/(nobs-trA)

        if (scoreType=="REML") {
          if (scale.known) { ## use Fisher-Laplace REML
             ls <- family$ls(y,weights,n,scale) ## saturated likelihood and derivatives
             REML <- (dev + oo$conv.tol)/(2*scale) - ls[1] + oo$rank.tol/2
             if (deriv) {
               REML1 <- oo$D1/(2*scale) + oo$trA1/2
               if (deriv==2) REML2 <- (matrix(oo$D2,nSp,nSp)/scale + matrix(oo$trA2,nSp,nSp))/2
               if (sum(!is.finite(REML2))) {
                 stop("Smoothing parameter derivate iteration diverging. Decrease fit tolerance! See `epsilon' in `gam.contol'")
               }
             }
           } else { ## scale unknown use Pearson-Fisher-Laplace REML
             phi <- oo$P ## REMLish scale estimate
             ls <- family$ls(y,weights,n,phi) ## saturated likelihood and derivatives
             phi1 <- oo$P1;phi2 <- matrix(oo$P2,nSp,nSp)
             Dp <- dev + oo$conv.tol
             Dp1 <- oo$D1
             Dp2 <- matrix(oo$D2,nSp,nSp)
             K <- oo$rank.tol/2
             K1 <- oo$trA1/2;K2 <- matrix(oo$trA2,nSp,nSp)/2             

             REML <- Dp/(2*phi) - ls[1] + K
             if (deriv) {
               REML1 <- Dp1/(2*phi) - phi1*(Dp/(2*phi^2) + ls[2]) + K1
               if (deriv==2) REML2 <- 
                      Dp2/(2*phi) - (outer(Dp1,phi1)+outer(phi1,Dp1))/(2*phi^2) +
                      (Dp/phi^3 - ls[3])*outer(phi1,phi1) -
                      (Dp/(2*phi^2)+ls[2])*phi2 + K2
             }
           } 
         } else { ## Not REML ....

           P <- oo$P
           
           delta <- nobs - gamma * trA
           delta.2 <- delta*delta           
  
           GCV <- nobs*dev/delta.2
           GACV <- dev/nobs + P * 2*gamma*trA/(delta * nobs) 

           UBRE <- dev/nobs - 2*delta*scale/nobs + scale
        
           if (deriv) {
             trA1 <- oo$trA1
           
             D1 <- oo$D1
             P1 <- oo$P1
          
             if (sum(!is.finite(D1))||sum(!is.finite(P1))||sum(!is.finite(trA1))) { 
                 stop("Smoothing parameter derivate iteration diverging. Decrease fit tolerance! See `epsilon' in `gam.contol'")}
         
             delta.3 <- delta*delta.2
  
             GCV1 <- nobs*D1/delta.2 + 2*nobs*dev*trA1*gamma/delta.3
             GACV1 <- D1/nobs + 2*P/delta.2 * trA1 + 2*gamma*trA*P1/(delta*nobs)

             UBRE1 <- D1/nobs + gamma * trA1 *2*scale/nobs
             if (deriv==2) {
               trA2 <- matrix(oo$trA2,nSp,nSp) 
               D2 <- matrix(oo$D2,nSp,nSp)
               P2 <- matrix(oo$P2,nSp,nSp)
              
               if (sum(!is.finite(D2))||sum(!is.finite(P2))||sum(!is.finite(trA2))) { 
                 stop("Smoothing parameter derivate iteration diverging. Decrease fit tolerance! See `epsilon' in `gam.contol'")}
             
               GCV2 <- outer(trA1,D1)
               GCV2 <- (GCV2 + t(GCV2))*gamma*2*nobs/delta.3 +
                      6*nobs*dev*outer(trA1,trA1)*gamma*gamma/(delta.2*delta.2) + 
                      nobs*D2/delta.2 + 2*nobs*dev*gamma*trA2/delta.3  
               GACV2 <- D2/nobs + outer(trA1,trA1)*4*P/(delta.3) +
                      2 * P * trA2 / delta.2 + 2 * outer(trA1,P1)/delta.2 +
                      2 * outer(P1,trA1) *(1/(delta * nobs) + trA/(nobs*delta.2)) +
                      2 * trA * P2 /(delta * nobs) 
               GACV2 <- (GACV2 + t(GACV2))*.5
               UBRE2 <- D2/nobs +2*gamma * trA2 * scale / nobs
             } ## end if (deriv==2)
           } ## end if (deriv)
        } ## end !REML
        # end of inserted code
        if (!conv&&printWarn) 
            warning("Algorithm did not converge")
        if (printWarn&&boundary) 
            warning("Algorithm stopped at boundary value")
        eps <- 10 * .Machine$double.eps
        if (printWarn&&family$family[1] == "binomial") {
            if (any(mu > 1 - eps) || any(mu < eps)) 
                warning("fitted probabilities numerically 0 or 1 occurred")
        }
        if (printWarn&&family$family[1] == "poisson") {
            if (any(mu < eps)) 
                warning("fitted rates numerically 0 occurred")
        }
 
        residuals <- rep.int(NA, nobs)
        residuals[good] <- z - (eta - offset)[good]
          
        names(coef) <- xnames 
    } ### end if (!EMPTY)
    names(residuals) <- ynames
    names(mu) <- ynames
    names(eta) <- ynames
    wt <- rep.int(0, nobs)
    wt[good] <- w^2
    names(wt) <- ynames
    names(weights) <- ynames
    names(y) <- ynames
   
    wtdmu <- if (intercept) 
        sum(weights * y)/sum(weights)
    else linkinv(offset)
    nulldev <- sum(dev.resids(y, wtdmu, weights))
    n.ok <- nobs - sum(weights == 0)
    nulldf <- n.ok - as.integer(intercept)
   
    aic.model <- aic(y, n, mu, weights, dev) # note: incomplete 2*edf needs to be added

    list(coefficients = coef, residuals = residuals, fitted.values = mu, 
         family = family, linear.predictors = eta, deviance = dev, 
        null.deviance = nulldev, iter = iter, weights = wt, prior.weights = weights, 
        df.null = nulldf, y = y, converged = conv,
        boundary = boundary,D1=D1,D2=D2,P=P,P1=P1,P2=P2,trA=trA,trA1=trA1,trA2=trA2,
        GCV=GCV,GCV1=GCV1,GCV2=GCV2,GACV=GACV,GACV1=GACV1,GACV2=GACV2,UBRE=UBRE,
        UBRE1=UBRE1,UBRE2=UBRE2,REML=REML,REML1=REML1,REML2=REML2,rV=rV,
        scale.est=scale.est,aic=aic.model,rank=oo$rank.est)
} ## end of gam.fit2


gam.fit3 <- function (x, y, sp, S=list(),rS=list(),UrS=list(),off, H=NULL, 
            weights = rep(1, nobs), start = NULL, etastart = NULL, 
            mustart = NULL, offset = rep(0, nobs),U1=0,Mp=-1, family = gaussian(), 
            control = gam.control(), intercept = TRUE,deriv=2,use.svd=TRUE,
            gamma=1,scale=1,printWarn=TRUE,scoreType="REML",...) 
## This version is designed to allow iterative weights to be negative. This means that 
## it deals with weights, rather than sqrt weights.
## deriv, sp, S, rS, H added to arg list. 
## need to modify family before call.
{   if (family$link==family$canonical) fisher <- TRUE else fisher=FALSE ##if cononical Newton = Fisher, but Fisher cheaper!
    if (scale>0) scale.known <- TRUE else scale.known <- FALSE
    if (!scale.known&&scoreType%in%c("REML","ML")) { ## the final element of sp is actually log(scale)
      nsp <- length(sp)
      scale <- exp(sp[nsp])
      sp <- sp[-nsp]
    }

   # scale <- abs(scale) ## NOTE: this line should not be needed
    if (!deriv%in%c(0,1,2)) stop("unsupported order of differentiation requested of gam.fit3")
    x <- as.matrix(x)
    iter <- 0;coef <- rep(0,ncol(x))
    xnames <- dimnames(x)[[2]]
    ynames <- if (is.matrix(y)) 
        rownames(y)
    else names(y)
    conv <- FALSE
    n <- nobs <- NROW(y) ## n is just to keep codetools happy
    nvars <- ncol(x)
    EMPTY <- nvars == 0
    if (is.null(weights)) 
        weights <- rep.int(1, nobs)
    if (is.null(offset)) 
        offset <- rep.int(0, nobs)
    variance <- family$variance
    dev.resids <- family$dev.resids
    aic <- family$aic
    linkinv <- family$linkinv
    mu.eta <- family$mu.eta
    if (!is.function(variance) || !is.function(linkinv)) 
        stop("illegal `family' argument")
    valideta <- family$valideta
    if (is.null(valideta)) 
        valideta <- function(eta) TRUE
    validmu <- family$validmu
    if (is.null(validmu)) 
        validmu <- function(mu) TRUE
    if (is.null(mustart)) {
        eval(family$initialize)
    }
    else {
        mukeep <- mustart
        eval(family$initialize)
        mustart <- mukeep
    }

    ## Added code
    if (family$family=="gaussian"&&family$link=="identity") strictly.additive <- TRUE else
      strictly.additive <- FALSE
    nSp <- length(S)
    if (nSp==0) deriv <- FALSE 
    St <- totalPenalty(S,H,off,sp,ncol(x))
    Sr <- mroot(St)

    ## end of added code

    D1 <- D2 <- P <- P1 <- P2 <- trA <- trA1 <- trA2 <- 
        GCV<- GCV1<- GCV2<- GACV<- GACV1<- GACV2<- UBRE <-
        UBRE1<- UBRE2<- REML<- REML1<- REML2 <-NULL

    if (EMPTY) {
        eta <- rep.int(0, nobs) + offset
        if (!valideta(eta)) 
            stop("Invalid linear predictor values in empty model")
        mu <- linkinv(eta)
        if (!validmu(mu)) 
            stop("Invalid fitted means in empty model")
        dev <- sum(dev.resids(y, mu, weights))
        w <- (weights * mu.eta(eta)^2)/variance(mu)   ### BUG: incorrect for Newton
        residuals <- (y - mu)/mu.eta(eta)
        good <- rep(TRUE, length(residuals))
        boundary <- conv <- TRUE
        coef <- numeric(0)
        iter <- 0
        V <- variance(mu)
        alpha <- dev
        trA2 <- trA1 <- trA <- 0
        if (deriv) GCV2 <- GCV1<- UBRE2 <- UBRE1<-trA1 <- rep(0,nSp)
        GCV <- nobs*alpha/(nobs-gamma*trA)^2
        UBRE <- alpha/nobs - scale + 2*gamma/n*trA
        scale.est <- alpha / (nobs - trA)
    } ### end if (EMPTY)
    else {
        coefold <- NULL
        eta <- if (!is.null(etastart)) 
            etastart
        else if (!is.null(start)) 
            if (length(start) != nvars) 
                stop("Length of start should equal ", nvars, 
                  " and correspond to initial coefs for ", deparse(xnames))
            else {
                coefold <- start
                offset + as.vector(if (NCOL(x) == 1) 
                  x * start
                else x %*% start)
            }
        else family$linkfun(mustart)
        etaold <- eta
        muold <- mu <- linkinv(eta)
        if (!(validmu(mu) && valideta(eta))) 
            stop("Can't find valid starting values: please specify some")
    
        boundary <- conv <- FALSE
        rV=matrix(0,ncol(x),ncol(x))   
       
        ## need an initial `null deviance' to test for initial divergence... 
        null.coef <- qr.coef(qr(x),family$linkfun(mean(y)+0*y))
        null.coef[is.na(null.coef)] <- 0 
        null.eta <- x%*%null.coef + offset
        old.pdev <- sum(dev.resids(y, linkinv(null.eta), weights)) + t(null.coef)%*%St%*%null.coef 
        ## ... if the deviance exceeds this then there is an immediate problem
            
        for (iter in 1:control$maxit) { ## start of main fitting iteration
            good <- weights > 0
            varmu <- variance(mu)[good]
            if (any(is.na(varmu))) 
                stop("NAs in V(mu)")
            if (any(varmu == 0)) 
                stop("0s in V(mu)")
            mu.eta.val <- mu.eta(eta)
            if (any(is.na(mu.eta.val[good]))) 
                stop("NAs in d(mu)/d(eta)")
            good <- (weights > 0) & (mu.eta.val != 0)
            if (all(!good)) {
                conv <- FALSE
                warning("No observations informative at iteration ", 
                  iter)
                break
            }
            mevg<-mu.eta.val[good];mug<-mu[good];yg<-y[good]
            weg<-weights[good];var.mug<-variance(mug)
            if (fisher) { ## Conventional Fisher scoring
              z <- (eta - offset)[good] + (yg - mug)/mevg
              w <- (weg * mevg^2)/var.mug
            } else { ## full Newton
              c <- yg - mug
              alpha <- mevg*(1 + c*(family$dvar(mug)/mevg+var.mug*family$d2link(mug))*mevg/var.mug)
              z <- (eta - offset)[good] + c/alpha ## offset subtracted as eta = X%*%beta + offset
              w <- weg*alpha*mevg/var.mug
            }

            ## Here a Fortran call has been replaced by update.beta call
           
            if (sum(good)<ncol(x)) stop("Not enough informative observations.")
     
            oo<-.C(C_pls_fit,y=as.double(z),as.double(x[good,]),as.double(w),as.double(Sr),n=as.integer(sum(good)),
            as.integer(ncol(x)),as.integer(ncol(Sr)),eta=as.double(z),penalty=as.double(1),
            as.double(.Machine$double.eps*100))
       
            if (!fisher&&oo$n<0) { ## likelihood indefinite - switch to Fisher for this step
              z <- (eta - offset)[good] + (yg - mug)/mevg
              w <- (weg * mevg^2)/var.mug
              oo<-.C(C_pls_fit,y=as.double(z),as.double(x[good,]),as.double(w),as.double(Sr),n=as.integer(sum(good)),
                     as.integer(ncol(x)),as.integer(ncol(Sr)),eta=as.double(z),penalty=as.double(1),
                     as.double(.Machine$double.eps*100))
            }

            start <- oo$y[1:ncol(x)];
            penalty <- oo$penalty
            eta <- drop(x%*%start)

            if (any(!is.finite(start))) {
                conv <- FALSE
                warning("Non-finite coefficients at iteration ", 
                  iter)
                break
            }        
     
           mu <- linkinv(eta <- eta + offset)
           dev <- sum(dev.resids(y, mu, weights))
          
           if (control$trace) 
                cat("Deviance =", dev, "Iterations -", iter, 
                  "\n")
            boundary <- FALSE
            
            if (!is.finite(dev)) {
                if (is.null(coefold)) 
                  stop("no valid set of coefficients has been found:please supply starting values", 
                    call. = FALSE)
                warning("Step size truncated due to divergence", 
                  call. = FALSE)
                ii <- 1
                while (!is.finite(dev)) {
                  if (ii > control$maxit) 
                    stop("inner loop 1; can't correct step size")
                  ii <- ii + 1
                  start <- (start + coefold)/2
                  eta <- (eta + etaold)/2               
                  mu <- linkinv(eta)
                  dev <- sum(dev.resids(y, mu, weights))
                }
                boundary <- TRUE
                if (control$trace) 
                  cat("Step halved: new deviance =", dev, "\n")
            }
            if (!(valideta(eta) && validmu(mu))) {
                warning("Step size truncated: out of bounds", 
                  call. = FALSE)
                ii <- 1
                while (!(valideta(eta) && validmu(mu))) {
                  if (ii > control$maxit) 
                    stop("inner loop 2; can't correct step size")
                  ii <- ii + 1
                  start <- (start + coefold)/2
                  eta <- (eta + etaold)/2 
                  mu <- linkinv(eta)
                }
                boundary <- TRUE
                dev <- sum(dev.resids(y, mu, weights))
                if (control$trace) 
                  cat("Step halved: new deviance =", dev, "\n")
            }

            pdev <- dev + penalty  ## the penalized deviance 

            if (control$trace) 
                  cat("penalized deviance =", pdev, "\n")

            div.thresh <- 10*(.1+abs(old.pdev))*.Machine$double.eps^.5 
            ## ... threshold for judging divergence --- too tight and near
            ## perfect convergence can cause a failure here

            if (pdev-old.pdev>div.thresh) { ## solution diverging
             ii <- 1 ## step halving counter
             if (iter==1) { ## immediate divergence, need to shrink towards zero 
               etaold <- null.eta; coefold <- null.coef
             }
             while (pdev -old.pdev > div.thresh)  
             { ## step halve until pdev <= old.pdev
                if (ii > 200) 
                   stop("inner loop 3; can't correct step size")
                ii <- ii + 1
                start <- (start + coefold)/2 
                eta <- (eta + etaold)/2               
                mu <- linkinv(eta)
                  dev <- sum(dev.resids(y, mu, weights))
                  pdev <- dev + t(start)%*%St%*%start ## the penalized deviance
                if (control$trace) 
                  cat("Step halved: new penalized deviance =", pdev, "\n")
              }
            } 
            
            if (strictly.additive) { conv <- TRUE;coef <- start;break;}

            if (abs(pdev - old.pdev)/(0.1 + abs(pdev)) < control$epsilon) {
               ## if (max(abs(start-coefold))>control$epsilon*max(abs(start+coefold))/2) {
                if (max(abs(mu-muold))>control$epsilon*max(abs(mu+muold))/2) {
                  old.pdev <- pdev
                  coef <- coefold <- start
                  etaold <- eta 
                  muold <- mu
                } else {
                  conv <- TRUE
                  coef <- start
                  break 
                }
            }
            else {  old.pdev <- pdev
                coef <- coefold <- start
                etaold <- eta 
            }
        } ### end main loop 
       
        dev <- sum(dev.resids(y, mu, weights)) 
       
        ## Now call the derivative calculation scheme. This requires the
        ## following inputs:
        ## z and w - the pseudodata and weights
        ## X the model matrix and E where EE'=S
        ## rS the single penalty square roots
        ## sp the log smoothing parameters
        ## y and mu the data and model expected values
        ## g1,g2,g3 - the first 3 derivatives of g(mu) wrt mu
        ## V,V1,V2 - V(mu) and its first two derivatives wrt mu
        ## on output it returns the gradient and hessian for
        ## the deviance and trA 

         good <- weights > 0
         varmu <- variance(mu)[good]
         if (any(is.na(varmu))) stop("NAs in V(mu)")
         if (any(varmu == 0)) stop("0s in V(mu)")
         mu.eta.val <- mu.eta(eta)
         if (any(is.na(mu.eta.val[good]))) 
                stop("NAs in d(mu)/d(eta)")
         good <- (weights > 0) & (mu.eta.val != 0)
   
         mevg <- mu.eta.val[good];mug <- mu[good];yg <- y[good]
         weg <- weights[good];etag <- eta[good]
         var.mug<-variance(mug)

         if (fisher) { ## Conventional Fisher scoring
              z <- (eta - offset)[good] + (yg - mug)/mevg
              w <- (weg * mevg^2)/var.mug
         } else { ## full Newton
              c <- yg - mug
              alpha <- mevg*(1 + c*(family$dvar(mug)/mevg+var.mug*family$d2link(mug))*mevg/var.mug)
              z <- (eta - offset)[good] + c/alpha ## offset subtracted as eta = X%*%beta + offset
              w <- weg*alpha*mevg/var.mug
         }
        
         g1 <- 1/mevg
         g2 <- family$d2link(mug)
         g3 <- family$d3link(mug)

         V <- family$variance(mug)
         V1 <- family$dvar(mug)
         V2 <- family$d2var(mug)      
        
         if (fisher) {
           g4 <- V3 <- 0
         } else {
           g4 <- family$d4link(mug)
           V3 <- family$d3var(mug)
         }

         if (TRUE) { ### TEST CODE for derivative ratio based versions of code... 
           g2 <- g2/g1;g3 <- g3/g1;g4 <- g4/g1
           V1 <- V1/V;V2 <- V2/V;V3 <- V3/V
         }

         P1 <- D1 <- array(0,nSp);P2 <- D2 <- matrix(0,nSp,nSp) # for derivs of deviance/ Pearson
         trA1 <- array(0,nSp);trA2 <- matrix(0,nSp,nSp) # for derivs of tr(A)
         rV=matrix(0,ncol(x),ncol(x));
         dum <- 1
         if (control$trace) cat("calling gdi...")

       REML <- 0 ## signals GCV/AIC used
       if (scoreType%in%c("REML","P-REML")) REML <- 1 else 
       if (scoreType%in%c("ML","P-ML")) REML <- -1 

       if (REML==0) rSncol <- unlist(lapply(rS,ncol)) else rSncol <- unlist(lapply(UrS,ncol))

       oo <- .C(C_gdi,X=as.double(x[good,]),E=as.double(Sr),rS = as.double(unlist(rS)),UrS = as.double(unlist(UrS)),U1=as.double(U1),
           sp=as.double(exp(sp)),z=as.double(z),w=as.double(w),mu=as.double(mug),eta=as.double(etag),y=as.double(yg),
           p.weights=as.double(weg),g1=as.double(g1),g2=as.double(g2),g3=as.double(g3),g4=as.double(g4),V0=as.double(V),
           V1=as.double(V1),V2=as.double(V2),V3=as.double(V3),beta=as.double(coef),D1=as.double(D1),D2=as.double(D2),
           P=as.double(dum),P1=as.double(P1),P2=as.double(P2),trA=as.double(dum),
           trA1=as.double(trA1),trA2=as.double(trA2),rV=as.double(rV),rank.tol=as.double(.Machine$double.eps*100),
           conv.tol=as.double(control$epsilon),rank.est=as.integer(1),n=as.integer(length(z)),
           p=as.integer(ncol(x)),M=as.integer(nSp),Mp=as.integer(Mp),Encol = as.integer(ncol(Sr)),
           rSncol=rSncol,deriv=as.integer(deriv),use.svd=as.integer(use.svd),
           REML = as.integer(REML),fisher=as.integer(fisher),fixed.penalty = as.integer(!is.null(H)))      
       
         if (control$trace) cat("done!\n")
 
         rV <- matrix(oo$rV,ncol(x),ncol(x))
         coef <- oo$beta;
         trA <- oo$trA;
         scale.est <- dev/(nobs-trA)
         reml.scale <- NA  

        if (scoreType%in%c("REML","ML")) { ## use Laplace (RE)ML
          
          ls <- family$ls(y,weights,n,scale) ## saturated likelihood and derivatives
          Dp <- dev + oo$conv.tol
          REML <- Dp/(2*scale) - ls[1] + oo$rank.tol/2
          if (deriv) {
            REML1 <- oo$D1/(2*scale) + oo$trA1/2
            if (deriv==2) REML2 <- (matrix(oo$D2,nSp,nSp)/scale + matrix(oo$trA2,nSp,nSp))/2
            if (sum(!is.finite(REML2))) {
               stop("Non finite derivatives. Try decreasing fit tolerance! See `epsilon' in `gam.contol'")
            }
          }
          if (!scale.known&&deriv) { ## need derivatives wrt log scale, too 
            ls <- family$ls(y,weights,n,scale) ## saturated likelihood and derivatives
            dlr.dlphi <- -Dp/(2 *scale) - ls[2]*scale
            d2lr.d2lphi <- Dp/(2*scale) - ls[3]*scale^2 - ls[2]*scale
            d2lr.dspphi <- -oo$D1/(2*scale)
            REML1 <- c(REML1,dlr.dlphi)
            if (deriv==2) {
              REML2 <- rbind(REML2,as.numeric(d2lr.dspphi))
              REML2 <- cbind(REML2,c(as.numeric(d2lr.dspphi),d2lr.d2lphi))
            }
          }
          reml.scale <- scale
        } else if (scoreType%in%c("P-REML","P-ML")) { ## scale unknown use Pearson-Laplace REML
          reml.scale <- phi <- oo$P ## REMLish scale estimate
          ls <- family$ls(y,weights,n,phi) ## saturated likelihood and derivatives
        
          Dp <- dev + oo$conv.tol
         
          K <- oo$rank.tol/2
                 
          REML <- Dp/(2*phi) - ls[1] + K
          if (deriv) {
            phi1 <- oo$P1; Dp1 <- oo$D1; K1 <- oo$trA1/2;
            REML1 <- Dp1/(2*phi) - phi1*(Dp/(2*phi^2) + ls[2]) + K1
            if (deriv==2) {
                   phi2 <- matrix(oo$P2,nSp,nSp);Dp2 <- matrix(oo$D2,nSp,nSp)
                   K2 <- matrix(oo$trA2,nSp,nSp)/2    
                   REML2 <- 
                   Dp2/(2*phi) - (outer(Dp1,phi1)+outer(phi1,Dp1))/(2*phi^2) +
                   (Dp/phi^3 - ls[3])*outer(phi1,phi1) -
                   (Dp/(2*phi^2)+ls[2])*phi2 + K2
            }
          }
 
        } else { ## Not REML ....

           P <- oo$P
           
           delta <- nobs - gamma * trA
           delta.2 <- delta*delta           
  
           GCV <- nobs*dev/delta.2
           GACV <- dev/nobs + P * 2*gamma*trA/(delta * nobs) 

           UBRE <- dev/nobs - 2*delta*scale/nobs + scale
        
           if (deriv) {
             trA1 <- oo$trA1
           
             D1 <- oo$D1
             P1 <- oo$P1
          
             if (sum(!is.finite(D1))||sum(!is.finite(P1))||sum(!is.finite(trA1))) { 
                 stop("Non-finite derivatives. Try decreasing fit tolerance! See `epsilon' in `gam.contol'")}
         
             delta.3 <- delta*delta.2
  
             GCV1 <- nobs*D1/delta.2 + 2*nobs*dev*trA1*gamma/delta.3
             GACV1 <- D1/nobs + 2*P/delta.2 * trA1 + 2*gamma*trA*P1/(delta*nobs)

             UBRE1 <- D1/nobs + gamma * trA1 *2*scale/nobs
             if (deriv==2) {
               trA2 <- matrix(oo$trA2,nSp,nSp) 
               D2 <- matrix(oo$D2,nSp,nSp)
               P2 <- matrix(oo$P2,nSp,nSp)
              
               if (sum(!is.finite(D2))||sum(!is.finite(P2))||sum(!is.finite(trA2))) { 
                 stop("Non-finite derivatives. Try decreasing fit tolerance! See `epsilon' in `gam.contol'")}
             
               GCV2 <- outer(trA1,D1)
               GCV2 <- (GCV2 + t(GCV2))*gamma*2*nobs/delta.3 +
                      6*nobs*dev*outer(trA1,trA1)*gamma*gamma/(delta.2*delta.2) + 
                      nobs*D2/delta.2 + 2*nobs*dev*gamma*trA2/delta.3  
               GACV2 <- D2/nobs + outer(trA1,trA1)*4*P/(delta.3) +
                      2 * P * trA2 / delta.2 + 2 * outer(trA1,P1)/delta.2 +
                      2 * outer(P1,trA1) *(1/(delta * nobs) + trA/(nobs*delta.2)) +
                      2 * trA * P2 /(delta * nobs) 
               GACV2 <- (GACV2 + t(GACV2))*.5
               UBRE2 <- D2/nobs +2*gamma * trA2 * scale / nobs
             } ## end if (deriv==2)
           } ## end if (deriv)
        } ## end !REML
        # end of inserted code
        if (!conv&&printWarn) 
            warning("Algorithm did not converge")
        if (printWarn&&boundary) 
            warning("Algorithm stopped at boundary value")
        eps <- 10 * .Machine$double.eps
        if (printWarn&&family$family[1] == "binomial") {
            if (any(mu > 1 - eps) || any(mu < eps)) 
                warning("fitted probabilities numerically 0 or 1 occurred")
        }
        if (printWarn&&family$family[1] == "poisson") {
            if (any(mu < eps)) 
                warning("fitted rates numerically 0 occurred")
        }
 
        residuals <- rep.int(NA, nobs)
        residuals[good] <- z - (eta - offset)[good]
          
        names(coef) <- xnames 
    } ### end if (!EMPTY)
    names(residuals) <- ynames
    names(mu) <- ynames
    names(eta) <- ynames
    wt <- rep.int(0, nobs)
    wt[good] <- w
    names(wt) <- ynames
    names(weights) <- ynames
    names(y) <- ynames
   
    wtdmu <- if (intercept) 
        sum(weights * y)/sum(weights)
    else linkinv(offset)
    nulldev <- sum(dev.resids(y, wtdmu, weights))
    n.ok <- nobs - sum(weights == 0)
    nulldf <- n.ok - as.integer(intercept)
   
    aic.model <- aic(y, n, mu, weights, dev) # note: incomplete 2*edf needs to be added

    list(coefficients = coef, residuals = residuals, fitted.values = mu, 
         family = family, linear.predictors = eta, deviance = dev, 
        null.deviance = nulldev, iter = iter, weights = wt, prior.weights = weights, 
        df.null = nulldf, y = y, converged = conv,
        boundary = boundary,D1=D1,D2=D2,P=P,P1=P1,P2=P2,trA=trA,trA1=trA1,trA2=trA2,
        GCV=GCV,GCV1=GCV1,GCV2=GCV2,GACV=GACV,GACV1=GACV1,GACV2=GACV2,UBRE=UBRE,
        UBRE1=UBRE1,UBRE2=UBRE2,REML=REML,REML1=REML1,REML2=REML2,rV=rV,
        scale.est=scale.est,reml.scale= reml.scale,aic=aic.model,rank=oo$rank.est)
}


score.transect <- function(ii, x, y, sp, S=list(),rS=list(),UrS=list(),off, H=NULL, 
            weights = rep(1, length(y)), start = NULL, etastart = NULL, 
            mustart = NULL, offset = rep(0, length(y)),U1,Mp,family = gaussian(), 
            control = gam.control(), intercept = TRUE,deriv=2,use.svd=TRUE,
            gamma=1,scale=1,printWarn=TRUE,scoreType="REML",eps=1e-7,...) {
## plot a transect through the score for sp[ii]
  np <- 200
  if (scoreType%in%c("REML","P-REML","ML","P-ML")) reml <- TRUE else reml <- FALSE
  score <- spi <- seq(-30,30,length=np)
  for (i in 1:np) {

     sp[ii] <- spi[i]
     b<-gam.fit3(x=x, y=y, sp=sp, S=S,rS=rS,UrS=UrS,off=off, H=H,
      offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=0,
      control=control,gamma=gamma,scale=scale,
      printWarn=FALSE,use.svd=use.svd,mustart=mustart,scoreType=scoreType,...)

      if (reml) {
        score[i] <- b$REML
      } else if (scoreType=="GACV") {
        score[i] <- b$GACV
      } else if (scoreType=="UBRE"){
        score[i] <- b$UBRE 
      } else { ## default to deviance based GCV
        score[i] <- b$GCV
      }
  }
  par(mfrow=c(2,2),mar=c(4,4,1,1))
  plot(spi,score,xlab="log(sp)",ylab=scoreType,type="l")
  plot(spi[1:(np-1)],score[2:np]-score[1:(np-1)],type="l",ylab="differences")
  plot(spi,score,ylim=c(score[1]-.1,score[1]+.1),type="l")
  plot(spi,score,ylim=c(score[np]-.1,score[np]+.1),type="l")
}

deriv.check <- function(x, y, sp, S=list(),rS=list(),UrS=list(),off, H=NULL, 
            weights = rep(1, length(y)), start = NULL, etastart = NULL, 
            mustart = NULL, offset = rep(0, length(y)),U1,Mp,family = gaussian(), 
            control = gam.control(), intercept = TRUE,deriv=2,use.svd=TRUE,
            gamma=1,scale=1,printWarn=TRUE,scoreType="REML",eps=1e-7,...)
## FD checking of derivatives: basically a debugging routine
{  if (!deriv%in%c(1,2)) stop("deriv should be 1 or 2")
   if (control$epsilon>1e-9) control$epsilon <- 1e-9 
   b<-gam.fit3(x=x, y=y, sp=sp, S=S,rS=rS,UrS=UrS,off=off, H=H,
      offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
      control=control,gamma=gamma,scale=scale,
      printWarn=FALSE,use.svd=use.svd,mustart=mustart,scoreType=scoreType,...)

   P0 <- b$P;fd.P1 <- P10 <- b$P1;  if (deriv==2) fd.P2 <- P2 <- b$P2 
   trA0 <- b$trA;fd.gtrA <- gtrA0 <- b$trA1 ; if (deriv==2) fd.htrA <- htrA <- b$trA2 
   dev0 <- b$deviance;fd.D1 <- D10 <- b$D1 ; if (deriv==2) fd.D2 <- D2 <- b$D2 

   if (scoreType%in%c("REML","P-REML","ML","P-ML")) reml <- TRUE else reml <- FALSE

   if (reml) {
     score0 <- b$REML;grad0 <- b$REML1; if (deriv==2) hess <- b$REML2 
   } else if (scoreType=="GACV") {
     score0 <- b$GACV;grad0 <- b$GACV1;if (deriv==2) hess <- b$GACV2 
   } else if (scoreType=="UBRE"){
     score0 <- b$UBRE;grad0 <- b$UBRE1;if (deriv==2) hess <- b$UBRE2 
   } else { ## default to deviance based GCV
     score0 <- b$GCV;grad0 <- b$GCV1;if (deriv==2) hess <- b$GCV2
   }
  
   fd.grad <- grad0
   if (deriv==2) fd.hess <- hess
   for (i in 1:length(sp)) {
     sp1 <- sp;sp1[i] <- sp[i]+eps/2
     bf<-gam.fit3(x=x, y=y, sp=sp1, S=S,rS=rS,UrS=UrS,off=off, H=H,
      offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
      control=control,gamma=gamma,scale=scale,
      printWarn=FALSE,use.svd=use.svd,mustart=mustart,scoreType=scoreType,...)
      
     sp1 <- sp;sp1[i] <- sp[i]-eps/2
     bb<-gam.fit3(x=x, y=y, sp=sp1, S=S,rS=rS,UrS=UrS,off=off, H=H,
      offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
      control=control,gamma=gamma,scale=scale,
      printWarn=FALSE,use.svd=use.svd,mustart=mustart,scoreType=scoreType,...)
      
   
      if (!reml) {
        Pb <- bb$P;Pf <- bf$P 
        P1b <- bb$P1;P1f <- bf$P1
        trAb <- bb$trA;trAf <- bf$trA
        gtrAb <- bb$trA1;gtrAf <- bf$trA1
        devb <- bb$deviance;devf <- bf$deviance
        D1b <- bb$D1;D1f <- bf$D1
      }
     

      if (reml) {
        scoreb <- bb$REML;scoref <- bf$REML;
        if (deriv==2) { gradb <- bb$REML1;gradf <- bf$REML1}
      } else if (scoreType=="GACV") {
        scoreb <- bb$GACV;scoref <- bf$GACV;
        if (deriv==2) { gradb <- bb$GACV1;gradf <- bf$GACV1}
      } else if (scoreType=="UBRE"){
        scoreb <- bb$UBRE; scoref <- bf$UBRE;
        if (deriv==2) { gradb <- bb$UBRE1;gradf <- bf$UBRE1} 
      } else { ## default to deviance based GCV
        scoreb <- bb$GCV;scoref <- bf$GCV;
        if (deriv==2) { gradb <- bb$GCV1;gradf <- bf$GCV1}
      }

      if (!reml) {
        fd.P1[i] <- (Pf-Pb)/eps
        fd.gtrA[i] <- (trAf-trAb)/eps
        fd.D1[i] <- (devf - devb)/eps
      }
      
     
      fd.grad[i] <- (scoref-scoreb)/eps
      if (deriv==2) { 
        fd.hess[,i] <- (gradf-gradb)/eps
        if (!reml) {
          fd.htrA[,i] <- (gtrAf-gtrAb)/eps
          fd.P2[,i] <- (P1f-P1b)/eps
          fd.D2[,i] <- (D1f-D1b)/eps
        } 
       
      }
   }
   
   if (!reml) {
     cat("\n Pearson Statistic... \n")
     cat("grad    ");print(P10)
     cat("fd.grad ");print(fd.P1)
     if (deriv==2) {
       fd.P2 <- .5*(fd.P2 + t(fd.P2))
       cat("hess\n");print(P2)
       cat("fd.hess\n");print(fd.P2)
     }

     cat("\n\n tr(A)... \n")
     cat("grad    ");print(gtrA0)
     cat("fd.grad ");print(fd.gtrA)
     if (deriv==2) {
       fd.htrA <- .5*(fd.htrA + t(fd.htrA))
       cat("hess\n");print(htrA)
       cat("fd.hess\n");print(fd.htrA)
     }
   

     cat("\n Deviance... \n")
     cat("grad    ");print(D10)
     cat("fd.grad ");print(fd.D1)
     if (deriv==2) {
       fd.D2 <- .5*(fd.D2 + t(fd.D2))
       cat("hess\n");print(D2)
       cat("fd.hess\n");print(fd.D2)
     }
   }
 
   cat("\n\n The objective...\n")

   cat("grad    ");print(grad0)
   cat("fd.grad ");print(fd.grad)
   if (deriv==2) {
     fd.hess <- .5*(fd.hess + t(fd.hess))
     cat("hess\n");print(hess)
     cat("fd.hess\n");print(fd.hess)
   }
   NULL
}


rt <- function(x,r1) {
## transform of x, asymptoting to values in r1
## returns rerivatives wrt to x as well as transform values
## r1[i] == NA for no transform 
  x <- as.numeric(x)
  ind <- x>0 
  rho2 <- rho1 <- rho <- 0*x
  if (length(r1)==1) r1 <- x*0+r1
  h <- exp(x[ind])/(1+exp(x[ind]))
  h1 <- h*(1-h);h2 <- h1*(1-2*h)
  rho[ind] <- r1[ind]*(h-0.5)*2
  rho1[ind] <- r1[ind]*h1*2
  rho2[ind] <- r1[ind]*h2*2
  rho[!ind] <- r1[!ind]*x[!ind]/2
  rho1[!ind] <- r1[!ind]/2
  ind <- is.na(r1)
  rho[ind] <- x[ind]
  rho1[ind] <- 1
  rho2[ind] <- 0
  list(rho=rho,rho1=rho1,rho2=rho2)
}

rti <- function(r,r1) {
## inverse of rti.
  r <- as.numeric(r)
  ind <- r>0
  x <- r
  if (length(r1)==1) r1 <- x*0+r1
  r2 <- r[ind]*.5/r1[ind] + .5
  x[ind] <- log(r2/(1-r2))
  x[!ind] <- 2*r[!ind]/r1[!ind]
  ind <- is.na(r1)
  x[ind] <- r[ind]
  x
}



newton <- function(lsp,X,y,S,rS,UrS,off,L,lsp0,H,offset,U1,Mp,family,weights,
                   control,gamma,scale,conv.tol=1e-6,maxNstep=5,maxSstep=2,
                   maxHalf=30,printWarn=FALSE,scoreType="deviance",
                   use.svd=TRUE,mustart = NULL,...)
## Newton optimizer for GAM gcv/aic optimization that can cope with an 
## indefinite Hessian! Main enhancements are: i) always peturbs the Hessian
## to +ve definite ii) step halves on step 
## failure, without obtaining derivatives until success; (iii) carries start
## values forward from one evaluation to next to speed convergence.    
## L is the matrix such that L%*%lsp + lsp0 gives the logs of the smoothing 
## parameters actually multiplying the S[[i]]'s
{  
  reml <- scoreType%in%c("REML","P-REML","ML","P-ML") ## REML/ML indicator

  ## sanity check L
  if (is.null(L)) L <- diag(length(lsp)) else {
    if (!inherits(L,"matrix")) stop("L must be a matrix.")
    if (nrow(L)<ncol(L)) stop("L must have at least as many rows as columns.")
    if (nrow(L)!=length(S)+as.numeric(scoreType=="REML"&&scale==0)||ncol(L)!=length(lsp)) stop("L has inconsistent dimensions.")
  }
  if (is.null(lsp0)) lsp0 <- rep(0,ncol(L))

  if (reml) { 
    frob.X <- sqrt(sum(X*X))
    lsp.max <- rep(NA,length(lsp0))
    for (i in 1:length(S)) { 
      lsp.max[i] <- 16 + log(frob.X/sqrt(sum(rS[[i]]^2))) - lsp0[i]
      if (lsp.max[i]<2) lsp.max[i] <- 2
    } 
  } else lsp.max <- NULL

  if (!is.null(lsp.max)) { ## then there are upper limits on lsp's
    lsp1.max <- coef(lm(lsp.max-lsp0~L-1)) ## get upper limits on lsp1 scale
    ind <- lsp>lsp1.max
    lsp[ind] <- lsp1.max[ind]-1 ## reset lsp's already over limit
    delta <- rti(lsp,lsp1.max) ## initial optimization parameters
  } else { ## optimization parameters are just lsp
    delta <- lsp
  }

  ## code designed to be turned on during debugging...
  check.derivs <- FALSE;sp.trace <- FALSE
  if (check.derivs) {
     deriv <- 2
     eps <- 1e-4
     deriv.check(x=X, y=y, sp=L%*%lsp+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
         offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
         control=control,gamma=gamma,scale=scale,
         printWarn=FALSE,use.svd=use.svd,mustart=mustart,
         scoreType=scoreType,eps=eps,...)
  }

  ii <- 0
  if (ii>0) {
    score.transect(ii,x=X, y=y, sp=L%*%lsp+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
         offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
         control=control,gamma=gamma,scale=scale,
         printWarn=FALSE,use.svd=use.svd,mustart=mustart,
         scoreType=scoreType,eps=eps,...)
  }
  ## ... end of debugging code 


  ## initial fit
  b<-gam.fit3(x=X, y=y, sp=L%*%lsp+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
     offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=2,
     control=control,gamma=gamma,scale=scale,
     printWarn=FALSE,use.svd=use.svd,mustart=mustart,scoreType=scoreType,...)

  mustart<-b$fitted.values

  if (reml) {
     old.score <- score <- b$REML;grad <- b$REML1;hess <- b$REML2 
  } else if (scoreType=="GACV") {
    old.score <- score <- b$GACV;grad <- b$GACV1;hess <- b$GACV2 
  } else if (scoreType=="UBRE"){
    old.score <- score <- b$UBRE;grad <- b$UBRE1;hess <- b$UBRE2 
  } else { ## default to deviance based GCV
    old.score <- score <- b$GCV;grad <- b$GCV1;hess <- b$GCV2
  }
  
  grad <- t(L)%*%grad
  hess <- t(L)%*%hess%*%L

  if (!is.null(lsp.max)) { ## need to transform to delta space
    rho <- rt(delta,lsp1.max)
    nr <- length(rho$rho1)
    hess <- diag(rho$rho1,nr,nr)%*%hess%*%diag(rho$rho1,nr,nr) + diag(rho$rho2*grad)
    grad <- rho$rho1*grad
  }

  score.scale <- b$scale.est + score;    
  uconv.ind <- abs(grad) > score.scale*conv.tol
  ## check for all converged too soon, and undo !
  if (!sum(uconv.ind)) uconv.ind <- uconv.ind | TRUE
  for (i in 1:200) {
   ## debugging code....
   if (check.derivs) {
     deriv <- 2
     eps <- 1e-4
     deriv.check(x=X, y=y, sp=L%*%lsp+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
         offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
         control=control,gamma=gamma,scale=scale,
         printWarn=FALSE,use.svd=use.svd,mustart=mustart,
         scoreType=scoreType,eps=eps,...)
    }
    ii <- 0
    if (ii>0) {
    score.transect(ii,x=X, y=y, sp=L%*%lsp+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
         offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
         control=control,gamma=gamma,scale=scale,
         printWarn=FALSE,use.svd=use.svd,mustart=mustart,
         scoreType=scoreType,eps=eps,...)
    }

    ## exclude apparently converged gradients from computation
    hess1 <- hess[uconv.ind,uconv.ind] 
    grad1 <- grad[uconv.ind]
    ## get the trial step ...
    eh <- eigen(hess1,symmetric=TRUE)
    d <- eh$values;U <- eh$vectors
    ind <- d < 0
    d[ind] <- -d[ind] ## see Gill Murray and Wright p107/8
    d <- 1/d
    
    Nstep <- 0 * grad
    Nstep[uconv.ind] <- -drop(U%*%(d*(t(U)%*%grad1))) # (modified) Newton direction
   
    Sstep <- -grad/max(abs(grad)) # steepest descent direction 
    
    ms <- max(abs(Nstep))
    if (ms>maxNstep) Nstep <- maxNstep * Nstep/ms

    ## try the step ...
    if (sp.trace) cat(lsp,"\n")

    if (!is.null(lsp.max)) { ## need to take step in delta space
      delta1 <- delta + Nstep
      lsp1 <- rt(delta1,lsp1.max)$rho ## transform to log sp space
    } else lsp1 <- lsp + Nstep

    b<-gam.fit3(x=X, y=y, sp=L%*%lsp1+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
       offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=2,
       control=control,gamma=gamma,scale=scale,
       printWarn=FALSE,mustart=mustart,use.svd=use.svd,scoreType=scoreType,...)
    
    if (reml) {
      score1 <- b$REML
    } else if (scoreType=="GACV") {
      score1 <- b$GACV
    } else if (scoreType=="UBRE") {
      score1 <- b$UBRE
    } else score1 <- b$GCV
    ## accept if improvement, else step halve
    ii <- 0 ## step halving counter
    if (score1<score) { ## accept
      old.score <- score 
      mustart <- b$fitted.values
      lsp <- lsp1
      if (reml) {
          score <- b$REML;grad <- b$REML1;hess <- b$REML2 
      } else if (scoreType=="GACV") {
          score <- b$GACV;grad <- b$GACV1;hess <- b$GACV2
      } else if (scoreType=="UBRE") {
          score <- b$UBRE;grad <- b$UBRE1;hess <- b$UBRE2 
      } else { score <- b$GCV;grad <- b$GCV1;hess <- b$GCV2} 
      grad <- t(L)%*%grad
      hess <- t(L)%*%hess%*%L
      
      if (!is.null(lsp.max)) { ## need to transform to delta space
        delta <- delta1
        rho <- rt(delta,lsp1.max)
        nr <- length(rho$rho1)
        hess <- diag(rho$rho1,nr,nr)%*%hess%*%diag(rho$rho1,nr,nr) + diag(rho$rho2*grad)
        grad <- rho$rho1*grad
      }

    } else { ## step halving ...
      step <- Nstep ## start with the (pseudo) Newton direction
      while (score1>score && ii < maxHalf) {
        if (ii==3) { ## Newton really not working - switch to SD, but keeping step length 
          s.length <- min(sum(step^2)^.5,maxSstep)
          step <- Sstep*s.length/sum(Sstep^2)^.5 ## use steepest descent direction
        } else step <- step/2
        ##if (ii>3) Slength <- Slength/2 ## keep track of SD step length
        if (!is.null(lsp.max)) { ## need to take step in delta space
          delta1 <- delta + step
          lsp1 <- rt(delta1,lsp1.max)$rho ## transform to log sp space
        } else lsp1 <- lsp + step
        b1<-gam.fit3(x=X, y=y, sp=L%*%lsp1+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
           offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=0,
           control=control,gamma=gamma,scale=scale,
           printWarn=FALSE,mustart=mustart,use.svd=use.svd,
           scoreType=scoreType,...)
         
        if (reml) {       
          score1 <- b1$REML
        } else if (scoreType=="GACV") {
          score1 <- b1$GACV
        } else if (scoreType=="UBRE") {
          score1 <- b1$UBRE
        } else score1 <- b1$GCV

        if (score1 <= score) { ## accept
          b<-gam.fit3(x=X, y=y, sp=L%*%lsp1+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
             offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=2,
             control=control,gamma=gamma,scale=scale,
             printWarn=FALSE,mustart=mustart,use.svd=use.svd,scoreType=scoreType,...)
          mustart <- b$fitted.values
          old.score <- score;lsp <- lsp1
         
          if (reml) {
            score <- b$REML;grad <- b$REML1;hess <- b$REML2 
          } else if (scoreType=="GACV") {
            score <- b$GACV;grad <- b$GACV1;hess <- b$GACV2
          } else if (scoreType=="UBRE") {
            score <- b$UBRE;grad <- b$UBRE1;hess <- b$UBRE2 
          } else { score <- b$GCV;grad <- b$GCV1;hess <- b$GCV2}
          grad <- t(L)%*%grad
          hess <- t(L)%*%hess%*%L
          if (!is.null(lsp.max)) { ## need to transform to delta space
             delta <- delta1
             rho <- rt(delta,lsp1.max)
             nr <- length(rho$rho1)
             hess <- diag(rho$rho1,nr,nr)%*%hess%*%diag(rho$rho1,nr,nr) + diag(rho$rho2*grad)
             grad <- rho$rho1*grad
          }
          
        }  # end of if (score1<= score )
        ii <- ii + 1
      } # end of step halving
    }
    ## test for convergence
    converged <- TRUE
    score.scale <- b$scale.est + abs(score);    
    uconv.ind <- abs(grad) > score.scale*conv.tol*.1
    if (sum(abs(grad)>score.scale*conv.tol)) converged <- FALSE
    if (abs(old.score-score)>score.scale*conv.tol) { 
      if (converged) uconv.ind <- uconv.ind | TRUE ## otherwise can't progress
      converged <- FALSE      
    }
    if (ii==maxHalf) converged <- TRUE ## step failure
    if (converged) break
  } ## end of iteration loop
  if (ii==maxHalf) ct <- "step failed"
  else if (i==200) ct <- "iteration limit reached" 
  else ct <- "full convergence"
  list(score=score,lsp=lsp,lsp.full=L%*%lsp+lsp0,grad=grad,hess=hess,iter=i,conv =ct,object=b)
}

bfgs <- function(lsp,X,y,S,rS,UrS,off,L,lsp0,H,offset,U1,Mp,family,weights,
                   control,gamma,scale,conv.tol=1e-6,maxNstep=5,maxSstep=2,
                   maxHalf=30,printWarn=FALSE,scoreType="GCV",use.svd=TRUE,
                   mustart = NULL,...)
## This optimizer is experimental... The main feature is to alternate infrequent 
## Newton steps with BFGS Quasi-Newton steps. In theory this should be faster 
## than Newton, because of the cost of full Hessian calculation, but
## in practice the extra steps required by QN tends to mean that the advantage
## is not realized...
## Newton optimizer for GAM gcv/aic optimization that can cope with an 
## indefinite Hessian, and alternates BFGS and Newton steps for speed reasons
## Main enhancements are: i) always peturbs the Hessian
## to +ve definite ii) step halves on step 
## failure, without obtaining derivatives until success; (iii) carries start
## values forward from one evaluation to next to speed convergence.    
## L is the matrix such that L%*%lsp + lsp0 gives the logs of the smoothing 
## parameters actually multiplying the S[[i]]'s
{ 
  reml <- scoreType%in%c("REML","P-REML","ML","P-ML") ## REML/ML indicator

  ## sanity check L
  if (is.null(L)) L <- diag(length(lsp)) else {
    if (!inherits(L,"matrix")) stop("L must be a matrix.")
    if (nrow(L)<ncol(L)) stop("L must have at least as many rows as columns.")
    if (nrow(L)!=length(S)+as.numeric(scoreType=="REML"&&scale==0)||ncol(L)!=length(lsp)) stop("L has inconsistent dimensions.")
  }
  if (is.null(lsp0)) lsp0 <- rep(0,ncol(L))
  ## initial fit
#  ptm <- proc.time()
  b<-gam.fit3(x=X, y=y, sp=L%*%lsp+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
     offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=2,
     control=control,gamma=gamma,scale=scale,
     printWarn=FALSE,use.svd=use.svd,mustart=mustart,scoreType=scoreType,...)
#  ptm <- proc.time()-ptm
#  cat("deriv=2 ",ptm,"\n")

  mustart<-b$fitted.values

  QNsteps <- floor(length(S)/2) ## how often to Newton should depend on cost...

  if (reml) {
     score <- b$REML;grad <- b$REML1;hess <- b$REML2 
  } else if (scoreType=="GACV") {
    old.score <- score <- b$GACV;grad <- b$GACV1;hess <- b$GACV2 
  } else if (scoreType=="UBRE"){
    old.score <- score <- b$UBRE;grad <- b$UBRE1;hess <- b$UBRE2 
  } else { ## default to deviance based GCV
    old.score <- score <- b$GCV;grad <- b$GCV1;hess <- b$GCV2
  }
  
  grad <- t(L)%*%grad
  hess <- t(L)%*%hess%*%L

  score.scale <- b$scale.est + score;    
  uconv.ind <- abs(grad) > score.scale*conv.tol
  ## check for all converged too soon, and undo !
  if (!sum(uconv.ind)) uconv.ind <- uconv.ind | TRUE
  kk <- 0 ## counter for QN steps between Newton steps
  for (i in 1:200) {
   
    if (kk==0) { ## time to reset B
      eh <- eigen(hess,symmetric=TRUE)
      d <- eh$values;U <- eh$vectors
      ind <- d < 0
      d[ind] <- -d[ind] ## see Gill Murray and Wright p107/8
      d <- 1/d
      d[d==0] <- min(d)*.Machine$double.eps^.5
      B <- U%*%(d*t(U)) ## Newton based inverse Hessian
    }
     
    kk <- kk + 1
    if (kk > QNsteps) kk <- 0 
 
    ## get the trial step ...
    
    Nstep <- 0 * grad
    Nstep[uconv.ind] <- -drop(B[uconv.ind,uconv.ind]%*%grad[uconv.ind]) # (modified) Newton direction
    
    ms <- max(abs(Nstep))
    if (ms>maxNstep) Nstep <- maxNstep * Nstep/ms

    ## try the step ...
    sc.extra <- 1e-4*sum(grad*Nstep) ## -ve sufficient decrease 
    ii <- 0 ## step halving counter
    step <- Nstep*2
    score1 <- abs(score)*2
    while (score1>score+sc.extra && ii < maxHalf) { ## reject and step halve
      ii <- ii + 1
      step <- step/2
      lsp1 <- lsp + step
  
#      ptm <- proc.time()
      if (kk!=0||ii==1) deriv <- 1 else deriv <- 0
      b1<-gam.fit3(x=X, y=y, sp=L%*%lsp1+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
          offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=deriv,
          control=control,gamma=gamma,scale=scale,
          printWarn=FALSE,mustart=mustart,use.svd=use.svd,scoreType=scoreType,...)
#       ptm <- proc.time()-ptm
#       cat("deriv= ",deriv,"  ",ptm,"\n")
      
      if (reml) {
          score1 <- b1$REML1
      } else if (scoreType=="GACV") {
          score1 <- b1$GACV
      } else if (scoreType=="UBRE") {
          score1 <- b1$UBRE
      } else score1 <- b1$GCV
    } ## accepted step or step failed to lead to decrease

    if (ii < maxHalf) { ## step succeeded 
      mustart <- b1$fitted.values
      if (kk==0) { ## time for a full Newton step ...
#        ptm <- proc.time()
        b<-gam.fit3(x=X, y=y, sp=L%*%lsp1+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
               offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=2,
               control=control,gamma=gamma,scale=scale,
               printWarn=FALSE,mustart=mustart,use.svd=use.svd,scoreType=scoreType,...)
#         ptm <- proc.time()-ptm
#         cat("deriv=2 ",ptm,"\n")

        mustart <- b$fitted.values
        old.score <- score;lsp <- lsp1
        if (reml) {
           score <- b$REML;grad <- b$REML1;hess <- b$REML2 
        } else if (scoreType=="GACV") {
          score <- b$GACV;grad <- b$GACV1;hess <- b$GACV2
        } else if (scoreType=="UBRE") {
          score <- b$UBRE;grad <- b$UBRE1;hess <- b$UBRE2 
        } else { score <- b$GCV;grad <- b$GCV1;hess <- b$GCV2}
        grad <- t(L)%*%grad
        hess <- t(L)%*%hess%*%L
      } else { ## just a BFGS update
        ## first derivatives only.... 
#        ptm <- proc.time()
         if (ii==1) b <- b1 else  
         b<-gam.fit3(x=X, y=y, sp=L%*%lsp1+lsp0, S=S,rS=rS,UrS=UrS,off=off, H=H,
               offset = offset,U1=U1,Mp=Mp,family = family,weights=weights,deriv=1,
               control=control,gamma=gamma,scale=scale,
               printWarn=FALSE,mustart=mustart,use.svd=use.svd,scoreType=scoreType,...)
#         ptm <- proc.time()-ptm
#         cat("deriv=1 ",ptm,"\n")

        mustart <- b$fitted.values
        old.score <- score;lsp <- lsp1
        old.grad <- grad
        if (reml) {
          score <- b$REML;grad <- b$REML1 
        } else if (scoreType=="GACV") {
          score <- b$GACV;grad <- b$GACV1
        } else if (scoreType=="UBRE") {
          score <- b$UBRE;grad <- b$UBRE1
        } else { score <- b$GCV;grad <- b$GCV1}
        grad <- t(L)%*%grad
        ## BFGS update of the inverse Hessian...
        yg <- grad-old.grad
        rho <- 1/sum(yg*step)
        B <- B - rho*step%*%(t(yg)%*%B)
        B <- B - rho*(B%*%yg)%*%t(step) + rho*step%*%t(step)
      } ## end of BFGS
    } ## end of successful step updating
    ## test for convergence
    converged <- TRUE
    score.scale <- b$scale.est + abs(score);    
    uconv.ind <- abs(grad) > score.scale*conv.tol
    if (sum(uconv.ind)) converged <- FALSE
    if (abs(old.score-score)>score.scale*conv.tol) { 
      if (converged) uconv.ind <- uconv.ind | TRUE ## otherwise can't progress
      converged <- FALSE      
    }
    if (ii==maxHalf) converged <- TRUE ## step failure
    if (converged) break
  } ## end of iteration loop
  if (ii==maxHalf) ct <- "step failed"
  else if (i==200) ct <- "iteration limit reached" 
  else ct <- "full convergence"
  list(score=score,lsp=lsp,lsp.full=L%*%lsp,grad=grad,hess=hess,iter=i,conv =ct,object=b)
}



gam2derivative <- function(lsp,args,...)
## Performs IRLS GAM fitting for smoothing parameters given in lsp 
## and returns the derivatives of the GCV or UBRE score w.r.t the 
## smoothing parameters for the model.
## args is a list containing the arguments for gam.fit3
## For use as optim() objective gradient
{ reml <- args$scoreType%in%c("REML","P-REML","ML","P-ML") ## REML/ML indicator
  if (!is.null(args$L)) {
    lsp <- args$L%*%lsp + args$lsp0
  }
  b<-gam.fit3(x=args$X, y=args$y, sp=lsp, S=args$S,rS=args$rS,UrS=args$UrS,off=args$off, H=args$H,
     offset = args$offset,U1=args$U1,Mp=args$Mp,family = args$family,weights=args$w,deriv=1,
     control=args$control,gamma=args$gamma,scale=args$scale,scoreType=args$scoreType,
     use.svd=FALSE,...)
  if (reml) {
          ret <- b$REML1 
  } else if (args$scoreType=="GACV") {
          ret <- b$GACV1
  } else if (args$scoreType=="UBRE") {
          ret <- b$UBRE1
  } else { ret <- b$GCV1}
  if (!is.null(args$L)) ret <- t(args$L)%*%ret
  ret
}


gam2objective <- function(lsp,args,...)
## Performs IRLS GAM fitting for smoothing parameters given in lsp 
## and returns the GCV or UBRE score for the model.
## args is a list containing the arguments for gam.fit3
## For use as optim() objective
{ reml <- args$scoreType%in%c("REML","P-REML","ML","P-ML") ## REML/ML indicator
  if (!is.null(args$L)) {
    lsp <- args$L%*%lsp + args$lsp0
  }
  b<-gam.fit3(x=args$X, y=args$y, sp=lsp, S=args$S,rS=args$rS,UrS=args$UrS,off=args$off, H=args$H,
     offset = args$offset,U1=args$U1,Mp=args$Mp,family = args$family,weights=args$w,deriv=0,
     control=args$control,gamma=args$gamma,scale=args$scale,scoreType=args$scoreType,
     use.svd=FALSE,...)
  if (reml) {
          ret <- b$REML 
  } else if (args$scoreType=="GACV") {
          ret <- b$GACV
  } else if (args$scoreType=="UBRE") {
          ret <- b$UBRE
  } else { ret <- b$GCV}
  attr(ret,"full.fit") <- b
  ret
}



gam4objective <- function(lsp,args,...)
## Performs IRLS GAM fitting for smoothing parameters given in lsp 
## and returns the GCV or UBRE score for the model.
## args is a list containing the arguments for gam.fit3
## For use as nlm() objective
{ reml <- args$scoreType%in%c("REML","P-REML","ML","P-ML") ## REML/ML indicator
  if (!is.null(args$L)) {
    lsp <- args$L%*%lsp + args$lsp0
  }
  b<-gam.fit3(x=args$X, y=args$y, sp=lsp, S=args$S,rS=args$rS,UrS=args$UrS,off=args$off, H=args$H,
     offset = args$offset,U1=args$U1,Mp=args$Mp,family = args$family,weights=args$w,deriv=1,
     control=args$control,gamma=args$gamma,scale=args$scale,scoreType=args$scoreType,
     use.svd=FALSE,...)
  
  if (reml) {
          ret <- b$REML;at <- b$REML1
  } else if (args$scoreType=="GACV") {
          ret <- b$GACV;at <- b$GACV1
  } else if (args$scoreType=="UBRE") {
          ret <- b$UBRE;at <- b$UBRE1
  } else { ret <- b$GCV;at <- b$GCV1}  

  attr(ret,"full.fit") <- b

  if (!is.null(args$L)) at <- t(args$L)%*%at

  attr(ret,"gradient") <- at
  ret
}

##
## The following fix up family objects for use with gam.fit3
##


fix.family.link<-function(fam)
# adds d2link the second derivative of the link function w.r.t. mu
# to the family supplied, as well as a 3rd derivative function 
# d3link...
# All d2link and d3link functions have been checked numerically. 
{ if (!inherits(fam,"family")) stop("fam not a family object")
  if (is.null(fam$canonical)) { ## note the canonical link - saves effort in full Newton
    if (fam$family=="gaussian") fam$canonical <- "identity" else
    if (fam$family=="poisson"||fam$family=="quasipoisson") fam$canonical <- "log" else
    if (fam$family=="binomial"||fam$family=="quasibinomial") fam$canonical <- "logit" else
    if (fam$family=="Gamma") fam$canonical <- "inverse" else
    if (fam$family=="inverse.gaussian") fam$canonical <- "1/mu^2" else
    fam$canonical <- "none"
  }
  if (!is.null(fam$d2link)&&!is.null(fam$d3link)&&!is.null(fam$d4link)) return(fam) 
  link <- fam$link
  if (length(link)>1) if (fam$family=="quasi") # then it's a power link
  { lambda <- log(fam$linkfun(exp(1))) ## the power, if > 0
    if (lambda<=0) { fam$d2link <- function(mu) -1/mu^2
      fam$d3link <- function(mu) 2/mu^3
      fam$d4link <- function(mu) -6/mu^4
    }
    else { fam$d2link <- function(mu) lambda*(lambda-1)*mu^(lambda-2)
      fam$d3link <- function(mu) (lambda-2)*(lambda-1)*lambda*mu^(lambda-3)
      fam$d4link <- function(mu) (lambda-3)*(lambda-2)*(lambda-1)*lambda*mu^(lambda-4)
    }
    return(fam)
  } else stop("unrecognized (vector?) link")

  if (link=="identity") {
    fam$d4link <- fam$d3link <- fam$d2link <- 
    function(mu) rep.int(0,length(mu))
    return(fam)
  } 
  if (link == "log") {
    fam$d2link <- function(mu) -1/mu^2
    fam$d3link <- function(mu) 2/mu^3
    fam$d4link <- function(mu) -6/mu^4
    return(fam)
  }
  if (link == "inverse") {
    fam$d2link <- function(mu) 2/mu^3
    fam$d3link <- function(mu) { mu <- mu*mu;-6/(mu*mu)}
    fam$d4link <- function(mu) { mu2 <- mu*mu;24/(mu2*mu2*mu)}
    return(fam)
  }
  if (link == "logit") {
    fam$d2link <- function(mu) 1/(1 - mu)^2 - 1/mu^2
    fam$d3link <- function(mu) 2/(1 - mu)^3 + 2/mu^3
    fam$d4link <- function(mu) 6/(1-mu)^4 - 6/mu^4
    return(fam)
  }
  if (link == "probit") {
    fam$d2link <- function(mu) { 
      eta <- fam$linkfun(mu)
      eta/fam$mu.eta(eta)^2
    }
    fam$d3link <- function(mu) {
      eta <-  fam$linkfun(mu)
      (1 + 2*eta^2)/fam$mu.eta(eta)^3
    }
    fam$d4link <- function(mu) {
       eta <-  fam$linkfun(mu)
       (7*eta + 6*eta^3)/fam$mu.eta(eta)^4
    }
    return(fam)
  }
  if (link == "cloglog") {
    fam$d2link <- function(mu) { l1m <- log(1-mu)
      -1/((1 - mu)^2*l1m) *(1+ 1/l1m)
    }
    fam$d3link <- function(mu) { l1m <- log(1-mu)
       mu3 <- (1-mu)^3
      (-2 - 3*l1m - 2*l1m^2)/mu3/l1m^3
    }
    fam$d4link <- function(mu){
      l1m <- log(1-mu)
      mu4 <- (1-mu)^4
      ( - 12 - 11 * l1m - 6 * l1m^2 - 6/l1m )/mu4  /l1m^3
    }
    return(fam)
  }
  if (link == "sqrt") {
    fam$d2link <- function(mu) -.25 * mu^-1.5
    fam$d3link <- function(mu) .375 * mu^-2.5
    fam$d4link <- function(mu) -0.9375 * mu^-3.5
    return(fam)
  }
  if (link == "cauchit") {
    fam$d2link <- function(mu) { 
     eta <- fam$linkfun(mu)
     2*pi*pi*eta*(1+eta*eta)
    }
    fam$d3link <- function(mu) { 
     eta <- fam$linkfun(mu)
     eta2 <- eta*eta
     2*pi*pi*pi*(1+3*eta2)*(1+eta2)
    }
    fam$d4link <- function(mu) { 
     eta <- fam$linkfun(mu)
     eta2 <- eta*eta
     2*pi^4*(8*eta+12*eta2*eta)*(1+eta2)
    }
    return(fam)
  }
  if (link == "1/mu^2") {
    fam$d2link <- function(mu) 6 * mu^-4
    fam$d3link <- function(mu) -24 * mu^-5
    fam$d4link <- function(mu) 120 * mu^-6
    return(fam)
  }
  if (substr(link,1,3)=="mu^") { ## it's a power link
    ## note that lambda <=0 gives log link so don't end up here
    lambda <- get("lambda",environment(fam$linkfun))
    fam$d2link <- function(mu) (lambda*(lambda-1)) * mu^{lambda-2}
    fam$d3link <- function(mu) (lambda*(lambda-1)*(lambda-2)) * mu^{lambda-3}
    fam$d4link <- function(mu) (lambda*(lambda-1)*(lambda-2)*(lambda-3)) * mu^{lambda-4}
    return(fam)
  }
  stop("link not recognised")
}


fix.family.var<-function(fam)
# adds dvar the derivative of the variance function w.r.t. mu
# to the family supplied, as well as d2var the 2nd derivative of 
# the variance function w.r.t. the mean. (All checked numerically). 
{ if (!inherits(fam,"family")) stop("fam not a family object")
  if (!is.null(fam$dvar)&&!is.null(fam$d2var)&&!is.null(fam$d3var)) return(fam) 
  family <- fam$family
  if (family=="gaussian") {
    fam$d3var <- fam$d2var <- fam$dvar <- function(mu) rep.int(0,length(mu))
    return(fam)
  } 
  if (family=="poisson"||family=="quasipoisson") {
    fam$dvar <- function(mu) rep.int(1,length(mu))
    fam$d3var <- fam$d2var <- function(mu) rep.int(0,length(mu))
    return(fam)
  } 
  if (family=="binomial"||family=="quasibinomial") {
    fam$dvar <- function(mu) 1-2*mu
    fam$d2var <- function(mu) rep.int(-2,length(mu))
    fam$d3var <- function(mu) rep.int(0,length(mu))
    return(fam)
  }
  if (family=="Gamma") {
    fam$dvar <- function(mu) 2*mu
    fam$d2var <- function(mu) rep.int(2,length(mu))
    fam$d3var <- function(mu) rep.int(0,length(mu))
    return(fam)
  }
  if (family=="quasi") {
    fam$dvar <- switch(fam$varfun,
       constant = function(mu) rep.int(0,length(mu)),
       "mu(1-mu)" = function(mu) 1-2*mu,
       mu = function(mu) rep.int(1,length(mu)),
       "mu^2" = function(mu) 2*mu,
       "mu^3" = function(mu) 3*mu^2           
    )
    if (is.null(fam$dvar)) stop("variance function not recognized for quasi")
    fam$d2var <- switch(fam$varfun,
       constant = function(mu) rep.int(0,length(mu)),
       "mu(1-mu)" = function(mu) rep.int(-2,length(mu)),
       mu = function(mu) rep.int(0,length(mu)),
       "mu^2" = function(mu) rep.int(2,length(mu)),
       "mu^3" = function(mu) 6*mu           
    )
    fam$d3var <- switch(fam$varfun,
       constant = function(mu) rep.int(0,length(mu)),
       "mu(1-mu)" = function(mu) rep.int(0,length(mu)),
       mu = function(mu) rep.int(0,length(mu)),
       "mu^2" = function(mu) rep.int(0,length(mu)),
       "mu^3" = function(mu) rep.int(6,length(mu))           
    )
    return(fam)
  }
  if (family=="inverse.gaussian") {
    fam$dvar <- function(mu) 3*mu^2
    fam$d2var <- function(mu) 6*mu
    fam$d3var <- function(mu) rep.int(6,length(mu)) 
    return(fam)
  }
  stop("family not recognised")
}


fix.family.ls<-function(fam)
# adds ls the log saturated likelihood and its derivatives
# w.r.t. the scale parameter to the family object.
{ if (!inherits(fam,"family")) stop("fam not a family object")
  if (!is.null(fam$ls)) return(fam) 
  family <- fam$family
  if (family=="gaussian") {
    fam$ls <- function(y,w,n,scale) c(-sum(w)*log(2*pi*scale)/2,-sum(w)/(2*scale),sum(w)/(2*scale*scale))
    return(fam)
  } 
  if (family=="poisson") {
    fam$ls <- function(y,w,n,scale) {
      res <- rep(0,3)
      res[1] <- sum(dpois(y,y,log=TRUE)*w)
      res
    }
    return(fam)
  } 
  if (family=="binomial") {
    fam$ls <- function(y,w,n,scale) { 
      c(-binomial()$aic(y,n,y,w,0)/2,0,0)
    }
    return(fam)
  }
  if (family=="Gamma") {
    fam$ls <- function(y,w,n,scale) {
      res <- rep(0,3)
      k <- -lgamma(1/scale) - log(scale)/scale - 1/scale
      res[1] <- sum(w*(k-log(y)))
      k <- (digamma(1/scale)+log(scale))/(scale*scale)
      res[2] <- sum(w*k)  
      k <- (-trigamma(1/scale)/(scale) + (1-2*log(scale)-2*digamma(1/scale)))/(scale^3)
      res[3] <- sum(w*k) 
      res
    }
    return(fam)
  }
  if (family=="quasi"||family=="quasipoisson"||family=="quasibinomial") {
    fam$ls <- function(y,w,n,scale) rep(0,3)
    return(fam)
  }
  if (family=="inverse.gaussian") {
    fam$ls <- function(y,w,n,scale) c(-sum(w*log(2*pi*scale*y^3))/2,
     -sum(w)/(2*scale),sum(w)/(2*scale*scale))
    return(fam)
  }
  stop("family not recognised")
}


negbin <- function (theta = stop("'theta' must be specified"), link = "log") { 
## modified from Venables and Ripley's MASS library to work with gam.fit3,
## and to allow a range of `theta' values to be specified
## single `theta' to specify fixed value; 2 theta values (first smaller that second)
## are limits within which to search for theta; otherwise supplied values make up 
## search set.
  linktemp <- substitute(link)
  if (!is.character(linktemp)) linktemp <- deparse(linktemp)
  if (linktemp %in% c("log", "identity", "sqrt")) stats <- make.link(linktemp)
  else if (is.character(link)) {
    stats <- make.link(link)
    linktemp <- link
  } else {
    if (inherits(link, "link-glm")) {
       stats <- link
            if (!is.null(stats$name))
                linktemp <- stats$name
        }
        else stop(linktemp, " link not available for negative binomial family; available links are \"identity\", \"log\" and \"sqrt\"")
    }
    env <- new.env(parent = .GlobalEnv)
    assign(".Theta", theta, envir = env)
    variance <- function(mu) mu + mu^2/get(".Theta")
    ## dvaraince/dmu needed as well
    dvar <- function(mu) 1 + 2*mu/get(".Theta")
    ## d2variance/dmu...
    d2var <- function(mu) rep(2/get(".Theta"),length(mu))
    d3var <- function(mu) rep(0,length(mu))
    getTheta <- function() get(".Theta")
    validmu <- function(mu) all(mu > 0)

    dev.resids <- function(y, mu, wt) { Theta <- get(".Theta")
      2 * wt * (y * log(pmax(1, y)/mu) - 
        (y + Theta) * log((y + Theta)/(mu + Theta))) 
    }
    aic <- function(y, n, mu, wt, dev) {
        Theta <- get(".Theta")
        term <- (y + Theta) * log(mu + Theta) - y * log(mu) +
            lgamma(y + 1) - Theta * log(Theta) + lgamma(Theta) -
            lgamma(Theta + y)
        2 * sum(term * wt)
    }
    ls <- function(y,w,n,scale) {
       Theta <- get(".Theta")
       ylogy <- y;ind <- y>0;ylogy[ind] <- y[ind]*log(y[ind])
       term <- (y + Theta) * log(y + Theta) - ylogy +
            lgamma(y + 1) - Theta * log(Theta) + lgamma(Theta) -
            lgamma(Theta + y)
       c(-sum(term*w),0,0)
    }
    initialize <- expression({
        if (any(y < 0)) stop("negative values not allowed for the negative binomial family")
        n <- rep(1, nobs)
        mustart <- y + (y == 0)/6
    })
    environment(dvar) <- environment(d2var) <- environment(variance) <- environment(validmu) <- 
    environment(ls) <- environment(dev.resids) <- environment(aic) <- environment(getTheta) <- env
    famname <- paste("Negative Binomial(", format(round(theta,3)), ")", sep = "")
    structure(list(family = famname, link = linktemp, linkfun = stats$linkfun,
        linkinv = stats$linkinv, variance = variance,dvar=dvar,d2var=d2var,d3var=d3var, dev.resids = dev.resids,
        aic = aic, mu.eta = stats$mu.eta, initialize = initialize,ls=ls,
        validmu = validmu, valideta = stats$valideta,getTheta = getTheta,canonical="log"), class = "family")
}



totalPenalty <- function(S,H,off,theta,p)
{ if (is.null(H)) St <- matrix(0,p,p)
  else { St <- H; 
    if (ncol(H)!=p||nrow(H)!=p) stop("H has wrong dimension")
  }
  theta <- exp(theta)
  m <- length(theta)
  if (m>0) for (i in 1:m) {
    k0 <- off[i]
    k1 <- k0 + nrow(S[[i]]) - 1
    St[k0:k1,k0:k1] <- St[k0:k1,k0:k1] + S[[i]] * theta[i]
  }
  St
}

totalPenaltySpace <- function(S,H,off,p)
{ ## function to obtain (orthogonal) basis for the null space and 
  ## range space of the penalty, and obtain actual null space dimension
  ## components are roughly rescaled to avoid any dominating

  if (is.null(H)) St <- matrix(0,p,p)
  else { St <- H/sqrt(sum(H*H)); 
    if (ncol(H)!=p||nrow(H)!=p) stop("H has wrong dimension")
  }
  m <- length(S)
  if (m>0) for (i in 1:m) {
    k0 <- off[i]
    k1 <- k0 + nrow(S[[i]]) - 1
    St[k0:k1,k0:k1] <- St[k0:k1,k0:k1] + S[[i]]/sqrt(sum(S[[i]]*S[[i]]))
  }
  es <- eigen(St,symmetric=TRUE)
  ind <- es$values>max(es$values)*.Machine$double.eps^.66
  Y <- es$vectors[,ind,drop=FALSE]  ## range space
  Z <- es$vectors[,!ind,drop=FALSE] ## null space - ncol(Z) is null space dimension
  list(Y=Y,Z=Z)
}



mini.roots <- function(S,off,np)
# function to obtain square roots, B[[i]], of S[[i]]'s having as few
# columns as possible. S[[i]]=B[[i]]%*%t(B[[i]]). np is the total number
# of parameters. S is in packed form. 
{ m<-length(S)
  if (m<=0) return(list())
  B<-S
  for (i in 1:m)
  { b<-mroot(S[[i]])
    B[[i]]<-matrix(0,np,ncol(b))
    B[[i]][off[i]:(off[i]+nrow(b)-1),]<-b
  }
  B
}


ldTweedie <- function(y,mu=y,p=1.5,phi=1) {
## evaluates log Tweedie density for 1<=p<=2, using series summation of
## Dunn & Smyth (2005) Statistics and Computing 15:267-280.
 
  if (length(p)>1||length(phi)>1) stop("only scalar `p' and `phi' allowed.")
  if (p<1||p>2) stop("p must be in [1,2]")
  ld <- cbind(y,y,y)
  if (p == 2) { ## It's Gamma
    if (sum(y<=0)) stop("y must be strictly positive for a Gamma density")
    ld[,1] <- dgamma(y, shape = 1/phi,rate = 1/(phi * mu),log=TRUE)
    ld[,2] <- (digamma(1/phi) + log(phi) - 1 + y/mu - log(y/mu))/(phi*phi)
    ld[,3] <- -2*ld[,2]/phi + (1-trigamma(1/phi)/phi)/(phi^3)
    return(ld)
  }  

  if (length(mu)==1) mu <- rep(mu,length(y))

  if (p == 1) { ## It's Poisson like
    ## ld[,1] <- dpois(x = y/phi, lambda = mu/phi,log=TRUE)
    if (sum(!is.integer(y/phi))) stop("y must be an integer multiple of phi for Tweedie(p=1)")
    ind <- (y!=0)|(mu!=0) ## take care to deal with y log(mu) when y=mu=0
    bkt <- y*0
    bkt[ind] <- (y[ind]*log(mu[ind]/phi) - mu[ind])
    dig <- digamma(y/phi+1)
    trig <- trigamma(y/phi+1)
    ld[,1] <- bkt/phi - lgamma(y/phi+1)
    ld[,2] <- (-bkt - y + dig*y)/(phi*phi)
    ld[,3] <- (2*bkt + 3*y - 2*dig*y - trig *y*y/phi)/(phi^3)
    return(ld) 
  }

  ## .. otherwise need the full series thing....
  ## first deal with the zeros  
  
  ind <- y==0
 
  ld[ind,1] <- -mu[ind]^(2-p)/(phi*(2-p))
  ld[ind,2] <- -ld[ind,1]/phi
  ld[ind,3] <- -2*ld[ind,2]/phi

  if (sum(!ind)==0) return(ld)

  ## now the non-zeros
  y <- y[!ind];mu <- mu[!ind]
  w <- w1 <- w2 <- y*0
  oo <- .C(C_tweedious,w=as.double(w),w1=as.double(w1),w2=as.double(w2),y=as.double(y),
           phi=as.double(phi),p=as.double(p),eps=as.double(.Machine$double.eps),n=as.integer(length(y)))
  
#  check.derivs <- TRUE
#  if (check.derivs) {
#    eps <- 1e-6
#    oo1 <- .C(C_tweedious,w=as.double(w),w1=as.double(w1),w2=as.double(w2),y=as.double(y),
#           phi=as.double(phi+eps),p=as.double(p),eps=as.double(.Machine$double.eps),n=as.integer(length(y)))
#    w2.fd <- (oo1$w1-oo$w1)/eps
#    print(oo$w2);print(w2.fd)
#  }  

  theta <- mu^(1-p)
  k.theta <- mu*theta/(2-p)
  theta <- theta/(1-p)
  l.base <-  (y*theta-k.theta)/phi
  ld[!ind,1] <- l.base - log(y) + oo$w
  ld[!ind,2] <- -l.base/phi + oo$w1   
  ld[!ind,3] <- 2*l.base/(phi*phi) + oo$w2
  
  ld
}

Tweedie <- function(p=1,link=power(0)) {
## a restricted Tweedie family
  if (p<=1||p>2) stop("Only 1<p<=2 supported")
  
  linktemp <- substitute(link)
  if (!is.character(linktemp)) linktemp <- deparse(linktemp)
  okLinks <- c("log", "identity", "sqrt","inverse")
  if (linktemp %in% okLinks)
    stats <- make.link(linktemp) else 
  if (is.character(link)) {
    stats <- make.link(link)
    linktemp <- link
  } else {
    if (inherits(link, "link-glm")) {
       stats <- link
       if (!is.null(stats$name))
          linktemp <- stats$name
        } else {
            stop(gettextf("link \"%s\" not available for poisson family.",
                linktemp, collapse = ""),domain = NA)
        }
    }
    
    variance <- function(mu) mu^p
    dvar <- function(mu) p*mu^(p-1)
    if (p==1) d2var <- function(mu) 0*mu else
      d2var <- function(mu) p*(p-1)*mu^(p-2)
    if (p==1||p==2)  d3var <- function(mu) 0*mu else
      d3var <- function(mu) p*(p-1)*(p-2)*mu^(p-3)
    validmu <- function(mu) all(mu >= 0)

    dev.resids <- function(y, mu, wt) {
        y1 <- y + (y == 0)
        if (p == 1)
            theta <- log(y1/mu)
        else theta <- (y1^(1 - p) - mu^(1 - p))/(1 - p)
        if (p == 2)
            kappa <- log(y1/mu)
        else kappa <- (y^(2 - p) - mu^(2 - p))/(2 - p)
        2 * wt * (y * theta - kappa)
    }
    initialize <- expression({
        n <- rep(1, nobs)
        mustart <- y + 0.1 * (y == 0)
    })
    ls <-  function(y,w,n,scale) {
      power <- p
      colSums(w*ldTweedie(y,y,p=power,phi=scale))
    }

    aic <- function(y, n, mu, wt, dev) {
      power <- p
      scale <- dev/sum(wt)
      -2*sum(ldTweedie(y,mu,p=power,phi=scale)[,1]*wt) + 2
    }
    structure(list(family = paste("Tweedie(",p,")",sep=""), variance = variance, 
              dev.resids = dev.resids,aic = aic, link = linktemp, linkfun = stats$linkfun, linkinv = stats$linkinv,
        mu.eta = stats$mu.eta, initialize = initialize, validmu = validmu,
        valideta = stats$valideta,dvar=dvar,d2var=d2var,d3var=d3var,ls=ls,canonical="none"), class = "family")


}