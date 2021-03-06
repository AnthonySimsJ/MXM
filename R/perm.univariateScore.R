perm.univariateScore = function(target, dataset, test, wei = NULL, targetID, threshold, R, ncores) {
  #how many tests
  nTests = dim(dataset)[2];
  univariateModels = NULL;
  univariateModels$pvalue = numeric(nTests) 
  univariateModels$stat = numeric(nTests)
  #for way to initialize the univariateModel
  for ( i in 1:nTests ) {
    #arguments order for any CI test are fixed
    if ( i != targetID ) {
      test_results = test(target, dataset, xIndex=i, csIndex = 0, wei = wei, threshold = threshold, R = R)
      univariateModels$pvalue[[i]] = test_results$pvalue;
      univariateModels$stat[[i]] = test_results$stat;
    } else {
      univariateModels$pvalue[[i]] = log(1);
      univariateModels$stat[[i]] = 0;
    }
  }
  
  univariateModels
}
