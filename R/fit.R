#' Fit CREMID model
#'
#' This function generates a sample from the posterior of CREMID. 
#'
#' @param Y Matrix of the data. Each row represents an observation.
#' @param C Vector of the group label of each observation. Labels are integers starting from 1. 
#' @param prior A list giving the prior information. If unspecified, a default prior is used. 
#' The list includes the following hyparameters: 
#' \code{K} Number of mixture components.
#' \code{epsilon_range} Vector with minimum and maximum values for \code{epsilon}.
#' \code{merge_step} Introduce step to merge mixture components with small KL divergence. Default is \code{merge_step = TRUE}.
#' \code{merge_par} Parameter controlling merging radius. Default is \code{merge_par = 0.1}.
#' @param mcmc A list giving the MCMC parameters. If unspecified, default parameters are used.  
#' The list includes the following parameters: \code{nburn} indicates the number of burn-in scans,
#' \code{nsave} indicates the number of scans to be saved,
#' \code{nskip} indicates the thinning interval,
#' \code{ndisplay} indicates the number of scans to be displayed on screen. 
#' The total number of scans is equal to  \code{nburn + nsave*nskip}.
#' @param state Initial state of the chain. At the moment only the latent variables Z can be initialized.
#' @return A \code{MPG} object. 
#' @details
#' \deqn{y_{i,j} = \sum_{k=1}^{K_0+K_1}\pi_{j,k}N(y_{i,j} | \mu_{j,k}, \Sigma_k )  }
#' where \eqn{i = 1, \ldots, n_j} and \eqn{j = 1, \ldots, J}.
#' The weights are defined as follows:
#' \deqn{ \pi_{j,k} = \rho w_{0,k}   \;\;\;  k = 1, \ldots, K_0,}
#' \deqn{ \pi_{j,k} = (1 - \rho) w_{j,k + K_0}   \;\;\;  k = 1, \ldots, K_1, }
#' where 
#' \deqn{(w_{0,1}, \ldots, w_{0,K_0}) \sim Dirichlet(\alpha_0/K_0) }
#' \deqn{(w_{j,1}, \ldots, w_{j,K_1}) \sim Dirichlet(\alpha_j/K_1) }
#' @export
#' @examples
#' n = c(250, 250)
#' p = 4
#' 
#' Y1 = rbind( matrix( rnorm( n[1]*p), ncol = p), matrix( rnorm(n[2]*p) + 3, ncol = p))
#' Y2 = rbind( matrix( rnorm( n[1]*p), ncol = p), matrix( rnorm(n[2]*p) + 4, ncol = p))
#' Y = rbind(Y1, Y2)
#' C = c( rep(1,sum(n)), rep(2,sum(n)))
#' 
#' ans = Fit(Y, C)
Fit <- function(Y, C, prior = NULL, mcmc = NULL, state = NULL)
{
  Y = as.matrix(Y)  
  p = ncol(Y)
  
  if(is.null(prior))
  {
    prior = list( K = 10,
                  epsilon_range =  c(10^-10, 1),
                  m_0 = colMeans(Y),
                  nu_2 = p+2, 
                  nu_1 = p+2,
                  Psi_2 = cov(Y),
                  V_0 = 100*cov(Y),
                  tau_k0 = c(4,4),
                  tau_alpha = c(1,1),
                  tau_rho = c(0.5,0.5),
                  point_masses_rho = c(0.0, 0.0),
                  tau_varphi = c(0.5,0.5),
                  point_masses_varphi = c(0.0, 0.0),
                  merge_step = TRUE,
                  merge_par = 0.1,
                  shared_alpha = TRUE
    )
  }
  else
  {
    if(is.null(prior$K))
      prior$K = 10
    if(is.null(prior$epsilon_range))
      prior$epsilon_range =  c(10^-10, 1)
    if(is.null(prior$m_0))
      prior$m_0 = colMeans(Y)
    if(is.null(prior$nu_2))
      prior$nu_2 = p+2
    if(is.null(prior$nu_1))
      prior$nu_1 = p+2
    if(is.null(prior$Psi_2))
      prior$Psi_2 = cov(Y)
    if(is.null(prior$V_0))
      prior$V_0 = 100*cov(Y)
    if(is.null(prior$tau_k0))
      prior$tau_k0 = c(4,4)
    if(is.null(prior$tau_alpha))
      prior$tau_alpha = c(1,1)
    if(is.null(prior$tau_rho))
      prior$tau_rho = c(0.5, 0.5)
    if(is.null(prior$point_masses_rho))
      prior$point_masses_rho = c(0,0)
    if(is.null(prior$tau_varphi))
      prior$tau_varphi = c(0.5,0.5)
    if(is.null(prior$point_masses_varphi))
      prior$point_masses_varphi = c(0.0, 0.0)
    if(is.null(prior$merge_step))
      prior$merge_step = TRUE
    if(is.null(prior$merge_par))
      prior$merge_par = 0.1
    if (is.null(prior$shared_alpha))
      prior$shared_alpha = TRUE
  }
  
  if(is.null(mcmc))
  {
    mcmc = list(nburn = 5000, nsave = 1000, nskip = 1, ndisplay = 1000)
  }
  else
  {
    if(is.null(mcmc$nburn))
      mcmc$nburn = 5000
    if(is.null(mcmc$nsave))
      mcmc$nsave = 1000
    if(is.null(mcmc$nskip))
      mcmc$nskip = 1
    if(is.null(mcmc$ndisplay))
      mcmc$ndisplay = 100
  }
  
  # TODO: remove "adaptive" version.
  if(is.null(prior$truncation_type))
    prior$truncation_type = "fixed"
  
  if(is.null(prior$tau_eta))
    prior$tau_eta = c(1,1)
  
  state = list()
  if(is.null(state$R))
    state$R = sample(0:1, prior$K, prob = prior$tau_eta / sum(prior$tau_eta), replace = TRUE )
  
  J = length(unique(C))
  if( sum( sort(unique(C)) == 1:J )  != J )
  {
    print("ERROR: unique(C) should look like 1, 2, ...")
    return(0);
  }
  C = C - 1
  
  if(is.null(state$Z))
  {
    state$Z = kmeans(Y, prior$K, iter.max = 100  )$cluster - 1
  }
  ans = fit(Y, C, prior, mcmc, state)
  colnames(ans$data$Y) = colnames(Y)
  ans$data$C = ans$data$C + 1
  ans$chain$Z = ans$chain$Z + 1 
  class(ans) = "cremid"
  return(ans)
  
}
