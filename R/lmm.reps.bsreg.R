lmm.reps.bsreg <- function(target, dataset, id, reps, threshold = 0.05, wei = NULL) {
  
  threshold <- log(threshold)
  dm <- dim(dataset)
  if ( is.null(dm) ) {
    n <- length(target)
    p <- 1
  } else {
    n <- dm[1]  ## sample size 
    p <- dm[2]  ## number of variables
  }  
  if ( p > n ) {
    res <- paste("The number of variables is higher than the sample size. No backward procedure was attempted")
    
  } else {
    
    tic <- proc.time()
    ###################
    ini <- lme4::lmer( target ~ dataset + reps + (1 | id), REML = FALSE, weights = wei )
    likini <- logLik(ini) 
    stat <- numeric(p)
    if (p == 1) {
      mod <- lme4::lmer( target ~ 1 + reps + (1 | id), REML = FALSE, weights = wei )
      stat <- 2 * ( likini - logLik(mod) )	
    } else {
      for (j in 1:p) {
        mod <- lme4::lmer( target ~ dataset[, -j, drop = FALSE] + reps + (1 | id), REML = FALSE, weights = wei )
        stat[j] <- 2 * ( likini - logLik(mod) )
      }
    }  
    mat <- cbind(1:p, pchisq( stat, 1, lower.tail = FALSE, log.p = TRUE), stat )
    colnames(mat) <- c("variable", "log.p-values", "statistic" )
    rownames(mat) <- 1:p 
    sel <- which.max( mat[, 2] )
    info <- matrix( c(0, -10, -10), ncol = 3 )
    
    if ( mat[sel, 2] < threshold ) {
      runtime <- proc.time() - tic
      res <- list(runtime = runtime, info = matrix(0, 0, 3), mat = mat, final = ini ) 
      
    } else {
      info[1, ] <- mat[sel, ]
      mat <- mat[-sel, , drop = FALSE] 
      dat <- dataset[, -sel, drop = FALSE] 
      
      i <- 1  
      
      if ( info[1, 2] > threshold & dim(mat)[1] > 0) {
        
        while ( info[i, 2] > threshold  &  dim(dat)[2] > 0 )  {   
          
          ini <- lme4::lmer( target ~ dat + reps + (1 | id), REML = FALSE, weights = wei )
          likini <- logLik(ini) 
          i <- i + 1        
          k <- p - i + 1
          
          if ( k == 1 ) {
            mod <- lme4::lmer(target ~ 1 + reps + (1 | id), REML = FALSE, weights = wei)
            stat <- 2 * ( likini - logLik(mod) )
            pval <- pchisq( stat, 1, lower.tail = FALSE, log.p = TRUE)
            
            if (pval > threshold ) {
              final <- "No variables were selected"
              info <- rbind(info, c(mat[, 1], pval, stat) )
              dat <- dataset[, -info[, 1], drop = FALSE ]
              mat <- matrix(nrow = 0, ncol = 3)
            } else {
              info <- rbind(info, c(0, -10, -10)) 
              final <- ini
            }  
            
          } else { 
            stat <- numeric(k)
            
            for (j in 1:k) {
              mod <- lme4::lmer( target ~ dat[, -j, drop = FALSE] + reps + (1 | id), REML = FALSE, weights = wei )
              stat[j] <- 2 * ( likini - logLik(mod) )
            }
            mat[, 2:3] <- cbind( pchisq( stat, 1, lower.tail = FALSE, log.p = TRUE), stat )
            sel <- which.max( mat[, 2] )
            
            if ( mat[sel, 2] < threshold ) {
              final <- ini
              info <- rbind(info, c(0, -10, -10) )
              
            } else {
              info <- rbind(info, mat[sel, ] )
              mat <- mat[-sel, , drop = FALSE] 
              dat <- dataset[, -info[, 1], drop = FALSE ]
            }
            
          }
        }  ## end while ( info[i, 2] > threshold  &  dim(dat)[2] > 0 )
        runtime <- proc.time() - tic
        info <- info[ info[, 1] > 0, , drop = FALSE]
        colnames(mat) <- c("Variables", "log.p-values", "statistic")
        res <- list(runtime = runtime, info = info, mat = mat, final = final ) 
        
      } else {
        runtime <- proc.time() - tic
        res <- list(runtime = runtime, info = info, mat = NULL, final = mod ) 
      }  ##  end if ( info[1, 2] > threshold & dim(mat)[1] > 0)
      
    }  ## end if ( mat[sel, 2] < threshold ) 
  }  ## end if ( p > n )
  
  res
}  





