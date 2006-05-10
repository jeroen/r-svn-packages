c-- Routines common to
c-- fastLTS ( ./rfltsreg.f )  and
c-- fastMCD ( ./rffastmcd.f )

ccccc
ccccc
	subroutine rfrangen(n,nsel,index,seed)
cc
cc    Randomly draws nsel cases out of n cases.
cc    Here, index is the index set.
cc
	integer seed
	integer index(nsel)
	real uniran
cc
	do 100 i=1,nsel
 10	  num=int(uniran(seed)*n)+1
	  if(i.gt.1) then
	    do 50 j=1,i-1
	      if(index(j).eq.num) goto 10
 50	    continue
	  endif
	  index(i)=num
 100	continue
	return
	end
ccccc
ccccc
	function uniran(seed)
cc
cc  Draws a random number from the uniform distribution on [0,1].
cc
	real uniran
	integer seed
	integer quot
cc
	seed=seed*5761+999
	quot=seed/65536
	seed=seed-quot*65536
	uniran=float(seed)/65536.D0
	return
	end
ccccc
ccccc
	subroutine rfgenpn(n,nsel,index)
cc
cc    Constructs all subsets of nsel cases out of n cases.
cc
	integer index(nsel)
cc
	k=nsel
	index(k)=index(k)+1
 10	if(k.eq.1.or.index(k).le.(n-(nsel-k))) goto 100
	k=k-1
	index(k)=index(k)+1
	do 50 i=k+1,nsel
	  index(i)=index(i-1)+1
 50	continue
	goto 10
 100	return
	end
ccccc
ccccc
	subroutine rfshsort(a,n)
cc
cc  Sorts the array a of length n.
cc
	double precision a(n)
	double precision t
	integer gap
cc
	gap=n
 100	gap=gap/2
	if(gap.eq.0) goto 200
	do 180 i=1,n-gap
	  j=i
 120	  if(j.lt.1) goto 180
	  nextj=j+gap
	  if(a(j).gt.a(nextj)) then
	    t=a(j)
	    a(j)=a(nextj)
	    a(nextj)=t
	  else
	    j=0
	  endif
	  j=j-gap
	  goto 120
 180	continue
	goto 100
 200	return
	end
ccccc
ccccc
	subroutine rfishsort(a,kk)
cc
cc  Sorts the integer array a of length kk.
cc
	integer a(kk)
	integer t
	integer gap
cc
	gap=kk
 100	gap=gap/2
	if(gap.eq.0) goto 200
	do 180 i=1,kk-gap
	  j=i
 120	  if(j.lt.1) goto 180
	  nextj=j+gap
	  if(a(j).gt.a(nextj)) then
	    t=a(j)
	    a(j)=a(nextj)
	    a(nextj)=t
	  else
	    j=0
	  endif
	  j=j-gap
	  goto 120
 180	continue
	goto 100
 200	return
	end
ccccc
ccccc
      function replow(k)
cc
cc    Find out which combinations of n and p are
cc    small enough in order to perform exaustive search
cc    Returns the maximal n for a given p, for which
cc    exhaustive search is to be done
cc
cc    k is the number of variables (p)
cc
      integer replow, k
      integer irep(6)
      data irep/500,50,22,17,15,14/

      iret=0
      if(k.le.6) iret = irep(k)

      replow = iret
      return
      end
ccccc
ccccc
      function rfncomb(k,n)
cc
cc  Computes the number of combinations of k out of n.
cc  (To avoid integer overflow during the computation,
cc  ratios of reals are multiplied sequentially.)
cc  For comb > 1E+009 the resulting 'comb' may be too large
cc  to be put in the integer 'rfncomb', but the main program
cc  only calls this function for small enough n and k.
cc
      integer rfncomb,k,n
      double precision comb,fact
cc
      comb=dble(1.0)
      do 10 j=1,k
      fact=(dble(n-j+1.0))/(dble(k-j+1.0))
      comb=comb*fact
 10   continue
      rfncomb=int(comb+0.5D0)
      return
      end
ccccc
ccccc
	subroutine rfcovcopy(a,b,n1,n2)
cc
cc  Copies matrix a to matrix b.
cc
	double precision a(n1,n2)
	double precision b(n1,n2)
cc
	do 100 i=1,n1
	  do 90 j=1,n2
	    b(i,j)=a(i,j)
 90	  continue
 100	continue
	return
	end
ccccc
ccccc
	function rffindq(aw,ncas,k,index)
cc
cc  Finds the k-th order statistic of the array aw of length ncas.
cc
	double precision rffindq
	double precision aw(ncas)
	double precision ax,wa
	integer index(ncas)
cc
	do 10 j=1,ncas
	  index(j)=j
 10	continue
	l=1
	lr=ncas
 20	if(l.ge.lr) goto 90
	ax=aw(k)
	jnc=l
	j=lr
 30	if(jnc.gt.j) goto 80
 40	if(aw(jnc).ge.ax) goto 50
	jnc=jnc+1
	goto 40
 50	if(aw(j).le.ax) goto 60
	j=j-1
	goto 50
 60	if(jnc.gt.j) goto 70
	i=index(jnc)
	index(jnc)=index(j)
	index(j)=i
	wa=aw(jnc)
	aw(jnc)=aw(j)
	aw(j)=wa
	jnc=jnc+1
	j=j-1
 70	goto 30
 80	if(j.lt.k) l=jnc
	if(k.lt.jnc) lr=j
	goto 20
 90	rffindq=aw(k)
	return
	end
ccccc
ccccc
	subroutine rfrdraw(a,n,seed,ntot,mini,ngroup,kmini)
cc
cc  Draws ngroup nonoverlapping subdatasets out of a dataset of size n,
cc  such that the selected case numbers are uniformly distributed from 1 to n.
cc
	integer a(2,ntot)
	integer mini(kmini)
	integer seed
cc
	jndex=0
	do 10 k=1,ngroup
	  do 20 m=1,mini(k)
	    nrand=int(uniran(seed)*(n-jndex))+1
	    jndex=jndex+1
	    if(jndex.eq.1) then
	      a(1,jndex)=nrand
	      a(2,jndex)=k
	    else
		a(1,jndex)=nrand+jndex-1
		a(2,jndex)=k
		do 5,i=1,jndex-1
		  if(a(1,i).gt.nrand+i-1) then
		    do 6, j=jndex,i+1,-1
		      a(1,j)=a(1,j-1)
		      a(2,j)=a(2,j-1)
 6		    continue
		    a(1,i)=nrand+i-1
		    a(2,i)=k
		    goto 20
		  endif
 5		continue
	    endif
 20	  continue
 10	continue
	return
	end
ccccc
ccccc
	function rfodd(n)
cc
	logical rfodd
cc
	rfodd=.true.
	if(2*(n/2).eq.n) rfodd=.false.
	return
	end
ccccc
ccccc
	function rfnbreak(nhalf,n,nvar)
cc
cc  Computes the breakdown value of the MCD estimator
cc
	integer rfnbreak

	if (nhalf.le.(n+nvar+1)/2) then
	  rfnbreak=(nhalf-nvar)*100/n
	else
	  rfnbreak=(n-nhalf+1)*100/n
	endif
	return
	end
ccccc
ccccc

	subroutine rfmcduni(w,ncas,jqu,slutn,bstd,aw,aw2,factor,len)
cc
cc  rfmcduni : calculates the MCD in the univariate case.
cc	     w contains the ordered observations
cc
c This version returns the index (jint) in 'len'
c which is used in rfltreg.f

	implicit double precision (a-h,o-z), integer(i-n)
	double precision w(ncas),aw(ncas),aw2(ncas)
	double precision slutn(len)
cc
	sq=0.D0
	sqmin=0.D0
	ndup=1
	do 5 j=1,ncas-jqu+1
 5	  slutn(j)=0.D0
	do 20 jint=1,ncas-jqu+1
	  aw(jint)=0.D0
	  do 10 j=1,jqu
	    aw(jint)=aw(jint)+w(j+jint-1)
	    if (jint.eq.1) sq=sq+w(j)*w(j)
 10	  continue
	  aw2(jint)=aw(jint)*aw(jint)/jqu
	  if (jint.eq.1) then
	    sq=sq-aw2(jint)
	    sqmin=sq
	    slutn(ndup)=aw(jint)
	    len=jint
	  else
	    sq=sq - w(jint-1)*w(jint-1) + w(jint+jqu-1)*w(jint+jqu-1)
     *		- aw2(jint) + aw2(jint-1)
	    if(sq.lt.sqmin) then
	      ndup=1
	      sqmin=sq
	      slutn(ndup)=aw(jint)
	      len=jint
	    else
	      if(sq.eq.sqmin) then
		ndup=ndup+1
		slutn(ndup)=aw(jint)
	      endif
	    endif
	  endif
 20	continue
	slutn(1)=slutn(int((ndup+1)/2))/jqu
	bstd=factor*sqrt(sqmin/jqu)
	return
	end
ccccc
ccccc
