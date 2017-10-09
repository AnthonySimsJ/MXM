#Cross Validation for SES
#INPUT
#target as in SES
#dataset as in SES
#kfolds: number of folds (integer)
#folds: already defined folds of the data to use (a list). If NULL the folds created internally with the same function
#alphas: vector of SES alphas hyper parameters used in CV. Default is c(0.1, 0.05, 0.01)
#maxk_s: vector of SES max_ks parameters used in CV. Default is c(3, 2)
#task: character, it can be "C" for classification (logistic regression classifier), "R" for regression (linear regression classifier), "S" for cox survival analysis (cox regression classifier)
#metric: a metric function provided by the user or auto defined due to the task. It may be NULL or a function in the form of other metric functions (e.g., mse.mxm). For example the default for the classification task is auc.mxm but the user can also define acc.mxm (based on the accuracy metric) that is supported on the package. Or the user can make his own metric function that follows the signature and the inputs, outputs of ours.
#modeler: a modeling function provided by the user or auto defined due to the task if it is NULL (e.g., lm.mxm)
#ses_test: A function object that defines the test used in the SES function (see SES help page for more). If it is NULL, its is auto defined due to the task.
#OUTPUT
#a list called best_model with the below slots
#cv_results_all: a list with the predictions, performances and the signatures for each fold of each configuration (i.e cv_results_all[[3]]$performances[1] indicates the performance of the 1st fold with the 3d configuration of SES)
#best_performance: numeric, the best average performance
#best_configuration: the best configuration of SES (a list with the slots id, a, max_k)
cv.permses <- function(target, dataset, wei = NULL, kfolds = 10, folds = NULL, alphas = c(0.1, 0.05, 0.01), max_ks = c(3, 2), task = NULL, metric = NULL, modeler = NULL, ses_test = NULL, R = 999, ncores = 1)
{
  
  if ( ncores > 1 ) {  ## multi-threaded task
    result = cvpermses.par(target, dataset, wei = wei, kfolds = kfolds, folds = folds, alphas = alphas, max_ks = max_ks, task = task, metric = metric, modeler = modeler, ses_test = ses_test, R = R, ncores = ncores)
    
  } else { ## one core task     
    
    if ( is.null(alphas) )  alphas <- c(0.1, 0.05, 0.01)
    if ( is.null(max_ks) )  max_ks <- c(3, 2)  
    
    alphas = sort(alphas, decreasing = TRUE)
    max_ks = sort(max_ks, decreasing = TRUE)
    nAlpha <- length(alphas);
    nMax_ks <- length(max_ks);
    #defining the SES configurations
    nSESConfs <- nAlpha*nMax_ks;
    SES_configurations <- vector("list" , nSESConfs);
    i <- 0;
    for (a in alphas) {
      for (k in max_ks) {
        configuration <- NULL;
        i <- i + 1;
        configuration$id <- i;
        configuration$a <- a;
        configuration$max_k <- k;
        SES_configurations[[i]] <- configuration;
      }
    }
    
    if ( is.null(folds) ) {
      if (task == "R" ) {
        folds <- generatefolds(target, nfolds = kfolds, stratified = FALSE, seed = FALSE)
      } else if (task == "S") {
        folds <- generatefolds(target[, 1], nfolds = kfolds, stratified = FALSE, seed = FALSE)
      } else   folds <- generatefolds(target, nfolds = kfolds, stratified = TRUE, seed = FALSE)
    } else  kfolds <- length( folds );
    
    if ( is.null(task) ) {
      stop("Please provide a valid task argument 'C'-classification, 'R'-regression, 'S'-survival.")
      #to do: select automatically the appropriate task due to the data, target
    } else if (task == 'C'){
      #Classification task (logistic regression)
      if ( is.null(metric) ) {
        metricFunction <- auc.mxm;
      } else   metricFunction <- metric;
      
      if ( is.null(modeler) ) {
        modelerFunction <- glm.mxm;
      } else   modelerFunction <- modeler;
      
      if ( is.null(ses_test) ) {
        test <- 'permLogistic';
      } else  test <- ses_test;
      
    } else if(task == 'R'){
      
      #Regression task 
      if ( is.null(metric) ) {
        metricFunction <- mse.mxm;
      } else  metricFunction <- metric;
      
      if ( is.null(modeler) ) {
        modelerFunction <- lm.mxm;
      } else  modelerFunction <- modeler;
      
      if ( is.null(ses_test) ) {
        test = 'permFisher';
      } else  test <- ses_test;
      
    } else if (task == 'S') {
      
      #cox survival analysis (cox regression)
      if ( is.null(metric) ) {
        metricFunction <- ci.mxm;
      } else  metricFunction <- metric;
      
      if ( is.null(modeler) ) {
        modelerFunction <- coxph.mxm;
      } else  modelerFunction <- modeler;
      
      if ( is.null(ses_test) ) {
        test = "permCR";
      } else  test <- ses_test;
      
    } else  stop("Please provide a valid task argument 'C'-classification, 'R'-regression, 'S'-survival.")
    
    nSESConfs = length(SES_configurations)
    #merging SES configuration lists and create the general cv results list
    conf_ses <- vector("list", nSESConfs)
    
    for(i in 1:nSESConfs){
      conf_ses[[i]]$configuration <- SES_configurations[[i]]
      conf_ses[[i]]$preds <- vector('list', kfolds)
      conf_ses[[i]]$performances <- vector('numeric', kfolds)
      conf_ses[[i]]$signatures <- vector('list', kfolds)
    }
    ####################
    ## Start the CV procedure
    ####################
    
    tic <- proc.time()
    
    for (k in 1:kfolds) {
      #print(paste('CV: Fold', k, 'of', kfolds));
      train_samples <- c();
      for ( i in which(c(1:kfolds) != k) )   train_samples = c( train_samples, folds[[ i ]] )
      #leave one fold out each time as a test set and the rest as train set
      train_set <- dataset[train_samples, ] #Set the training set
      train_target <- target[train_samples]
      wtrain <- wei[train_samples]
      test_set <- dataset[folds[[k]], ] #Set the validation set
      test_target <- target[ folds[[k]] ]
      #SES hashmap
      SESHashMap = NULL;
      sesini = NULL
      #for each conf of SES
      for(ses_conf_id in 1:nSESConfs){
        #SES options
        threshold <- SES_configurations[[ses_conf_id]]$a;
        max_k <- SES_configurations[[ses_conf_id]]$max_k;
        #running SES
        results <- perm.ses(train_target, train_set, max_k, threshold, test = test, ini = sesini, wei = wtrain, hash = TRUE, hashObject = SESHashMap, R = R)
        sesini <- results@univ
        SESHashMap <- results@hashObject;
        signatures <- results@signatures;
        #recording the selected signatures
        conf_ses[[ses_conf_id]]$signatures[[k]] <- signatures;
        #get the data of the reference signature (i.e the selected variables)
        curr_sign <- as.matrix(signatures[1, ])
        #curr_sign <- as.matrix(results@selectedVars) #in case that the signature slot is not returned due to lack of memory. See InternalSES final part.
        sign_data <- train_set[, curr_sign, drop = FALSE]
        sign_test <- test_set[, curr_sign, drop = FALSE]
        
        if ( dim(signatures)[1] >= 1 & length(results@selectedVars ) > 0 ) {
          #generate a model due to the task and find the performance
          #logistic model for a classification task, linear model for the regression task and a cox model for the survival task
          moda <- modelerFunction(train_target, sign_data, sign_test, wei = wtrain)
          preds <- moda$preds
          theta <- moda$theta
        } else  {
          moda <- modelerFunction(train_target, rep(1, nrow(sign_data)), rep(1, nrow(sign_test)), wei = wtrain)
          preds <- moda$preds
          theta <- moda$theta
        }  
        
        if ( is.null(preds) ) {
          conf_ses[[ses_conf_id]]$preds[[k]] <- NULL
          conf_ses[[ses_conf_id]]$performances[k] <- NA
        } else {
          performance = metricFunction(preds, test_target, theta)
          conf_ses[[ses_conf_id]]$preds[[k]] <- preds
          conf_ses[[ses_conf_id]]$performances[k] <- performance
        }
      }
      #clear the hashmap and garbages
      if ( !is.null(SESHashMap$pvalue_hash) )   hash::clear(SESHashMap$pvalue_hash)
      if ( !is.null(SESHashMap$stat_hash) )    hash::clear(SESHashMap$stat_hash)
      rm(SESHashMap);
      gc();
    }
    #finding the best performance for the metric  
    index = 1;
    best_perf = mean(conf_ses[[1]]$performances, na.rm = TRUE);
    
    for ( i in 2:length(conf_ses) ) {
      averagePerf <- mean( conf_ses[[i]]$performances, na.rm = TRUE );
      if ( !is.na(averagePerf)   &  !is.na(best_perf) ) {
        if ( averagePerf < best_perf ) {
          best_perf <- averagePerf;
          index <- i;
        }
      }
    }
    #recording the best results
    best_model <- NULL
    best_model$cv_results_all <- conf_ses;
    best_model$best_performance <- best_perf
    #TT
    mat <- matrix(nrow = length(best_model[[ 1 ]]), ncol = kfolds)
    for ( i in 1:dim(mat)[1] )  mat[i, ] <- as.vector( best_model[[ 1 ]][[ i ]]$performances )  
    
    opti <- Rfast::rowmeans(mat)
    bestpar <- which.max(opti)
    estb <- abs( sum( mat[bestpar, ] - Rfast::colMaxs(mat, value = TRUE) ) / kfolds )    ##   apply(mat, 2, max) ) ) / kfolds 
    
    best_model$best_configuration <- conf_ses[[bestpar]]$configuration
    best_model$best_performance <- max( opti )
    best_model$BC_best_perf <- best_model$best_performance - estb
    best_model$runtime <- proc.time() - tic 
    
    result <- best_model
  }
  
  result
}






















#metric functions
#input
#predictions
#test_target

#output
#the metric value (numeric)


#metric functions (use of ROCR package)
#auc
auc.mxm <- function(predictions, test_target, theta = NULL) {
  #predsObj <- prediction(predictions, test_target)
  #aucValue <- performance(predsObj, measure='auc')@y.values[[1]];
  test_target <- as.numeric( as.factor(test_target) )
  ri <- rank(predictions)
  up <- max(test_target)
  n <- length(predictions)
  n1 <- sum( test_target == up )
  n0 <- n - n1
  s1 <- sum( ri[test_target == up ] )
  ( s1 - 0.5 * ( n1 * (n1 + 1) ) ) / n0 / n1
}

#accuracy (binary)
acc.mxm <- function(predictions, test_target, theta = NULL) {
  sum( (predictions > 0.5) == test_target ) / length(test_target)
}

#accuracy
acc_multinom.mxm <- function(predictions, test_target, theta = NULL) {
  sum( predictions == test_target ) / length(test_target)
}

#mse lower values indicate better performance so we multiply with -1 in order to have higher values for better performances
mse.mxm <- function(predictions, test_target, theta = NULL) {
  - sum( (predictions - test_target)^2 ) / length(test_target)
}

#mean absolut error lower values indicate better performance so we multiply with -1 in order to have higher values for better performances
ord_mae.mxm <- function(predictions, test_target, theta = NULL) {
  - sum( abs(as.numeric(predictions) - as.numeric(test_target)) ) / length(test_target)
}

#cindex
ci.mxm <- function(predictions, test_target, theta = NULL) {
  ## 1 - Hmisc::rcorr.cens(predictions, test_target)[1];
  survival::survConcordance(test_target ~ predictions)$concordance
}

#cindex for weibull and exponential regession
ciwr.mxm <- function(predictions, test_target, theta = NULL) {
  ## Hmisc::rcorr.cens(predictions, test_target)[1];
  1 - survival::survConcordance(test_target ~ predictions)$concordance
}  

#Poisson deviance. Lower values indicate better performance so we multiply with -1 in order to have higher values for better performances
poisdev.mxm <- function(predictions, test_target, theta = NULL) {
  - 2 * sum( test_target * log(test_target / predictions) ) 
}

#Negative binomial deviance. Lower values indicate better performance so we multiply with -1 in order to have higher values for better performances
nbdev.mxm <- function(predictions, test_target, theta) {
  - 2 * sum( test_target * log(test_target / predictions), na.rm = TRUE ) +
    2 * sum( ( test_target + theta ) * log( (test_target + theta) / (predictions + theta) ) )
}  


#Binomial deviance. Lower values indicate better performance so we multiply with -1 in order to have higher values for better performances
binomdev.mxm <- function(predictions, test_target, theta = NULL) {
  ya = test_target[, 1]     ;    N = test_target[, 2]
  yb = N - ya   
  esta = predictions     ;    estb = N - esta
  - 2 * sum( ya * log(ya / esta), na.rm = TRUE ) - 2 * sum( yb * log(yb / estb), na.rm = TRUE ) 
}

#Modeling Functions

#input
#train_target
#sign_data
#sign_test
#output
#preds


## binary logistic regression
glm.mxm <- function(train_target, sign_data, sign_test, wei) {
  #   if(dim(sign_data)[2] == 1)
  #   {
  #     return(NULL);
  #   }else{
  #using this variable x to overcome the structure naming problems when we have just one variable as a sign_data. For more on this contact athineo ;)
  x <- sign_data
  sign_model <- glm( train_target ~ ., data = data.frame(x), family = binomial(), weights = wei );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x), type = 'response' )
  #   preds[ preds>=0.5 ] = 1
  #   preds[ preds<0.5 ] = 0
  list(preds = preds, theta = NULL)
  #  }
}

## poisson regression
pois.mxm <- function(train_target, sign_data, sign_test, wei) {
  #using this variable x to overcome the structure naming problems when we have just one variable as a sign_data. For more on this contact athineou ;)
  x <- sign_data
  sign_model <- glm( train_target ~ ., data = data.frame(x), family = poisson(), weights = wei );
  x <- sign_test
  preds <-predict( sign_model, newdata = data.frame(x), type = 'response' )
  list(preds = preds, theta = NULL)
}

## binomial regression
binom.mxm <-  function(train_target, sign_data, sign_test){
  #using this variable x to overcome the structure naming problems when we have just one variable as a sign_data. For more on this contact athineou ;)
  y1 = train_target[, 1]
  N1 = train_target[, 2]
  x <- sign_data
  sign_model <- glm( y1 / N1 ~ ., data = data.frame(x), weights = N1, family = binomial );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x), type = 'response' ) * N1 
  list(preds = preds, theta = NULL)
}

## negative binomial regression
nb.mxm <- function(train_target, sign_data, sign_test, wei) {
  #using this variable x to overcome the structure naming problems when we have just one variable as a sign_data. For more on this contact athineou ;)
  x <- sign_data
  sign_model <- MASS::glm.nb( train_target ~ ., data = data.frame(x), weights = wei );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x), type = 'response' )
  list(preds = preds, theta = sign_model$theta)
}

## multinomial regression
multinom.mxm <- function(train_target, sign_data, sign_test, wei) {
  #using this variable x to overcome the structure naming problems when we have just one variable as a sign_data. For more on this contact athineou ;)
  x <- sign_data
  sign_model <- nnet::multinom( train_target ~ ., data = data.frame(x), trace = FALSE, weights = wei );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x) )
  list(preds = preds, theta = NULL)
}

## oridnal regression
ordinal.mxm <- function(train_target, sign_data, sign_test, wei) {
  x <- sign_data
  sign_model <- ordinal::clm( train_target ~ ., data = data.frame(x), trace = FALSE, weights = wei );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x) )$fit
  preds <- max.col(preds)  
  list(preds = preds, theta = NULL)
}

## linear regression
lm.mxm <- function(train_target, sign_data, sign_test, wei) { ## used for univariate and multivariate target in classical regression
  x <- sign_data
  sign_model <- lm( train_target ~ ., data = data.frame(x), weights = wei );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x) )
  preds <- list(preds = preds, theta = NULL)
}

## quantile (median) regression
rq.mxm <- function(train_target, sign_data, sign_test, wei) { ## used for univariate and multivariate target in classical regression
  x <- sign_data
  sign_model <- quantreg::rq( train_target ~ ., data = data.frame(x), weights = wei);
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x) )
  list(preds = preds, theta = NULL)
}

## robust linear regression
lmrob.mxm <- function(train_target, sign_data, sign_test, wei) { ## used for univariate and multivariate target in classical regression
  x <- sign_data
  sign_model <- MASS::rlm( train_target ~ ., data = data.frame(x), maxit = 2000, weights = wei, methpd = "MM" );
  x <- sign_test
  preds <- predict( sign_model, newdata = data.frame(x) )
  list(preds = preds, theta = NULL)
}

## beta regression
beta.mxm <- function(train_target, sign_data, sign_test, wei) { ## used for univariate and multivariate target in classical regression
  preds <- beta.mod( train_target, sign_data, wei = wei, xnew = sign_test )$est
  preds <- log( preds / (1 - preds) )  ## logit transformation to make it comparable with the normal regression
  list(preds = preds, theta = NULL)
}

## cox regression
coxph.mxm <- function(train_target, sign_data, sign_test, wei) {
  x <- sign_data
  sign_model <- survival::coxph(train_target~., data = data.frame(x), weights = wei)
  x <- sign_test
  preds <- predict(sign_model, newdata = data.frame(x), type = "risk")
  list(preds = preds, theta = NULL)
}

## weibull regression
weibreg.mxm <- function(train_target, sign_data, sign_test, wei) {
  x <- sign_data
  sign_model <- survival::survreg(train_target~., data = data.frame(x), weights = wei)
  x <- sign_test
  preds <- predict(sign_model, newdata = data.frame(x) )
  list(preds = preds, theta = NULL)
}

exporeg.mxm <- function(train_target, sign_data, sign_test, wei) {
  x <- sign_data
  sign_model <- survreg(train_target~., data = data.frame(x), dist = "exponential", weights = wei)
  x <- sign_test
  preds <- predict(sign_model, newdata = data.frame(x) )
  list(preds = preds, theta = NULL)
}