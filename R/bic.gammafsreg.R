bic.gammafsreg <- function( target, dataset, wei = NULL, tol = 0, heavy = FALSE, robust = FALSE, ncores = 1) {
  
  p <- dim(dataset)[2]  ## number of variables
  bico <- numeric( p )
  moda <- list()
  k <- 1   ## counter
  n <- length(target)  ## sample size
  tool <- NULL
  info <- matrix( 0, ncol = 2 )
  #check for NA values in the dataset and replace them with the variable median or the mode
  if ( any( is.na(dataset) ) ) {
    warning("The dataset contains missing values (NA) and they were replaced automatically by the variable (column) median (for numeric) or by the most frequent level (mode) if the variable is factor")
    if ( is.matrix(dataset) )  {
      dataset <- apply( dataset, 2, function(x){ x[which(is.na(x))] = median(x, na.rm = TRUE) ; return(x) } ) 
    } else {
      poia <- unique( which( is.na(dataset), arr.ind = TRUE )[, 2] )
      for( i in poia )  {
        xi <- dataset[, i]
        if ( is.numeric(xi) ) {                    
          xi[ which( is.na(xi) ) ] <- median(xi, na.rm = TRUE) 
        } else if ( is.factor( xi ) )     xi[ which( is.na(xi) ) ] <- levels(xi)[ which.max( as.vector( table(xi) ) )]
        dataset[, i] <- xi
      }
    }
  }
  
  if ( heavy )   con <- log(n)

    durat <- proc.time()
    if ( !heavy ) {
      ini = BIC( glm( target ~ 1, weights = wei, family = Gamma(link = log), y = FALSE, model = FALSE ) )   ## initial BIC
    } else {
      inimod <- speedglm::speedglm( target ~ 1, data = data.frame(dataset), family = Gamma(link = log), weights = wei )
      ini <-  - 2 * inimod$logLik + con   ## initial BIC
      ci_test <- "testIndGamma"
    }	

    if (ncores <= 1) {
      
      if ( !heavy ) {
        for (i in 1:p) {
          mi <- glm( target ~ dataset[, i], family = Gamma(link = log), weights = wei, y = FALSE, model = FALSE )
          bico[i] <- BIC( mi )
        }
      } else {
        for (i in 1:p) { 
          mi <- speedglm::speedglm( target ~ dataset[, i], data = data.frame( dataset[, i] ), family = Gamma(link = log), weights = wei )
          bico[i] <-  - 2 * mi$logLik + length( mi$coefficients ) * con   ## initial BIC
        }	
      }  
      
      mat <- cbind(1:p, bico)
      if( any( is.na(mat) ) )   mat[ which( is.na(mat) ) ] = ini
      
    } else {
      if ( !heavy ) {
        cl <- makePSOCKcluster(ncores)
        registerDoParallel(cl)
        mod <- foreach( i = 1:p, .combine = rbind) %dopar% {
          ww <- glm( target ~ dataset[, i], family =  Gamma(link = log), weights = wei )
          return( BIC( ww ) )
        }
        stopCluster(cl)
      }  else {
        cl <- makePSOCKcluster(ncores)
        registerDoParallel(cl)
        mod <- foreach( i = 1:p, .combine = rbind, .export = "speedglm", .packages = "speedglm") %dopar% {
          ww <- speedglm::speedglm( target ~ dataset[, i], data = data.frame(dataset[, i]), family =  Gamma(link = log), weights = wei )
          return( -2 * ww$logLik + (length( coef(ww) ) + 1) * con )   ## initial BIC
        }
        stopCluster(cl) 
      } 
      mat <- cbind(1:p, mod)
      if ( any( is.na(mat) ) )    mat[ which( is.na(mat) ) ] = ini
    }
    
    colnames(mat) <- c("variable", "BIC")
    rownames(mat) <- 1:p
    sel <- which.min( mat[, 2] )
    sela <- sel
    
    if ( ini - mat[sel, 2] > tol ) {
      
      info[1, ] <- mat[sel, ]
      mat <- mat[-sel, , drop = FALSE]
      if ( !heavy ) {
        mi <- glm( target ~ dataset[, sel], family = Gamma(link = log), weights = wei, y = FALSE, model = FALSE )
        tool[1] <- BIC( mi )
      } else {
        mi <- speedglm::speedglm( target ~ dataset[, sel], data = data.frame(dataset[, sel]), family = Gamma(link = log), weights = wei )
        tool[1] <-  - 2 * mi$logLik + (length( mi$coefficients ) + 1) * con   ## initial BIC
      }  

      moda[[ 1 ]] <- mi
    }  else  {
      info <- info  
      sela <- NULL
    }
    ######
    ###     k equals 2
    ######
    if ( length(moda) > 0  &  nrow(mat) > 0 ) {
      
      k <- 2
      pn <- p - k  + 1
      mod <- list()
      
      if ( ncores <= 1 ) {
        bico <- numeric( pn )
        if ( !heavy ) {
          for ( i in 1:pn ) {
            ma <- glm( target ~., data = data.frame( dataset[, c(sel, mat[i, 1]) ] ), family = Gamma(link = log), y = FALSE, model = FALSE )
            bico[i] <- BIC( ma )
          }
        } else {
          for ( i in 1:pn ) {
            ma <- speedglm::speedglm( target ~., data = data.frame( dataset[, c(sel, mat[i, 1]) ] ), family = Gamma(link = log), weights = wei )
            bico[i] <-  - 2 * ma$logLik + ( length( ma$coefficients ) + 1) * con
          }		  
        }
        mat[, 2] <- bico
        
      } else {
        
        if ( !heavy ) {
          cl <- makePSOCKcluster(ncores)
          registerDoParallel(cl)
          mod <- foreach( i = 1:pn, .combine = rbind) %dopar% {
            ww <- glm( target ~ dataset[, sel ] + dataset[, mat[i, 1] ], family = Gamma(link = log), weights = wei )
            return( BIC( ww ) )
          }
          stopCluster(cl)
        } else {
          cl <- makePSOCKcluster(ncores)
          registerDoParallel(cl)
          mod <- foreach( i = 1:pn, .combine = rbind, export = "speedglm", .packages = "speedglm") %dopar% {
            ww <- speedglm::speedglm( target ~ dataset[, sel ] + dataset[, mat[i, 1] ], data = data.frame(dataset), family = Gamma(link = log), weights = wei )
            return( - 2 * ww$logLik + (length( ww$coefficients ) + 1) * con )
          }
          stopCluster(cl)		  
        }	

        mat[, 2] <- mod
      }
      
      ina <- which.min( mat[, 2] )
      sel <- mat[ina, 1]
      if ( tool[1] - mat[ina, 2] <= tol ) {
        info <- info
      } else {
        tool[2] <- mat[ina, 2]
        info <- rbind(info, mat[ina, ] )
        sela <- info[, 1]
        mat <- mat[-ina, , drop = FALSE]
      }
      
    }
    #########
    ####      k is greater than 2
    #########
    if ( nrow(info) > 1  &  nrow(mat) > 0 ) {
      while (  k < n - 15  &  tool[ k - 1 ] - tool[ k ] > tol  & nrow(mat) > 0 ) {
        
        k <- k + 1
        pn <- p - k + 1
        
        if (ncores <= 1) {
          if ( !heavy ) {
            for ( i in 1:pn ) {
              ma <- glm( target ~., data = as.data.frame( dataset[, c(sela, mat[i, 1]) ] ), family = Gamma(link = log), weights = wei, y = FALSE, model = FALSE )
              mat[i, 2] <- BIC( ma )
            }
          } else {
            for ( i in 1:pn ) {
              ma <- speedglm::speedglm( target ~., data = data.frame( dataset[, c(sela, mat[i, 1]) ] ), family = Gamma(link = log), weights = wei )
              mat[i, 2] <-  - 2 * ma$logLik + ( length( ma$coefficients ) + 1 ) * con
            }		  
          }   

          
        } else {
          if ( !heavy ) {
            cl <- makePSOCKcluster(ncores)
            registerDoParallel(cl)
            bico <- numeric(pn)
            mod <- foreach( i = 1:pn, .combine = rbind) %dopar% {
              ww <- glm( target ~., data = as.data.frame( dataset[, c(sela, mat[i, 1]) ] ), family = Gamma(link = log), weights = wei )
              bico[i] <- BIC( ww )
            }
            stopCluster(cl)
          } else {
            cl <- makePSOCKcluster(ncores)
            registerDoParallel(cl)
            mod <- foreach( i = 1:pn, .combine = rbind, .export = "speedglm", .packages = "speedglm") %dopar% {
              ww <- speedglm::speedglm( target ~., data = data.frame( dataset[, c(sela, mat[i, 1]) ] ), family = Gamma(link = log), weights = wei )
              return( - 2 * ww$logLik + ( length( ww$coefficients ) + 1 ) * con )
            }
            stopCluster(cl)		  
          }

          mat[, 2] <- mod
          
        }
        
        ina <- which.min( mat[, 2] )
        sel <- mat[ina, 1]
        if ( tool[k - 1] - mat[ina, 2]  <= tol ) {
          info <- rbind( info,  c( -10, 1e300 ) )
          tool[k] <- Inf
          
        } else {
          tool[k] <- mat[ina, 2]
          info <- rbind(info, mat[ina, ] )
          sela <- info[, 1]
          mat <- mat[-ina, , drop = FALSE]
        }
        
      }
      
    }
    
    duration <- proc.time() - durat

  d <- length(sela)
  final <- NULL
  
  if ( d >= 1 ) {
    if ( !heavy ) {
      final <- glm( target ~., data = as.data.frame( dataset[, sela] ), weights = wei, family = Gamma(link = log), model = FALSE )
    } else  final <- speedglm::speedlm( target ~., data = as.data.frame( dataset[, sela] ), weights = wei, family = Gamma(link = log) )	 
  }
  info <- info[1:d, , drop = FALSE]
  colnames(info) <- c( "variables", "BIC" )
  rownames(info) <- info[, 1]
  
  list( runtime = duration, mat = t(mat), info = info,ci_test = ci_test,  final = final)
}