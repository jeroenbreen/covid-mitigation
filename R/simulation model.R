library(deSolve)
library(tidyverse)

### the ODE model
covidmodel <- function(t, vars, parms) {
  with(as.list(c(vars, parms)), {
    foi <- 
      (beta1 * I1 +
         beta2 * I2m + beta3 * I3m +
         beta2 * b_par * I2s + b_par * beta3 * I3s +
         beta2 * r_par * Y2 + beta3 * r_par * Y3) / (popsize)
    return(
      list(
        c(
          dS = -foi * S,
          dE = foi * S - sigma * E,
          dI1 = sigma * E - gamma1 * I1,
          dI2m = gamma1 * I1 * (1 - p_par) - gamma2 * I2m,
          dI3m = gamma2 * I2m - gamma3 * I3m,
          dI2s = gamma1 * I1 * p_par - (alpha + gamma2) * I2s,
          dI3s = gamma2 * I2s - gamma3 * I3s,
          dY2 = alpha * I2s - gamma2 * Y2,
          dY3 = gamma2 * Y2 - gamma3 * Y3,
          dInf = foi * S,
          dRep = alpha * I2s
        )
      )
    )
  })
}

### the function doing the simulations
# There are default parameter values for everything, 
# so simply calling the function produces a matrix with simulated variables.
# Alternative parameters can be chosen as argument to the function, 
# e.g. calling "covidsim(alpha = 0.3)"
covidsim <- function(
  popsize = 60e+06, seedsize = 10, burnintime = 30,
  timewindow = 365,
  parameters = c(
    beta1 = 0.25, beta2 = 0.16, beta3 = 0.016,
    sigma = 1, gamma1 = 0.2, gamma2 = 0.14, gamma3 = 0.14,
    alpha = 0.5, p_par = 0.5, b_par = 0.8, r_par = 0.01,
    start_dist = 60, end_dist = 108, effect_dist = 1
  ),
  ...
) {
  altparms <- list(...)
  for(i in names(altparms)) {
    parameters[i] <- altparms[[i]]
  }
  
  initialstate <- c(
    S = popsize, E = seedsize, I1 = 0,
    I2m = 0, I3m = 0,
    I2s = 0, I3s = 0,
    Y2 = 0, Y3 = 0,
    Infected = 0, Reported = 0
  )
  
  startparms <- c(popsize = popsize, parameters)
  startparms["r_par"] <- startparms["b_par"]
  simres <- ode(
    y = initialstate,
    times = seq(0, burnintime, 1),
    func = covidmodel,
    parms = startparms
  )
  
  nodistparms <- c(popsize = popsize, parameters)
  simres <- ode(
    y = tail(simres, 1)[, -1],
    times = seq(0, min(nodistparms["start_dist"], timewindow), 1),
    func = covidmodel,
    parms = nodistparms
  )
  
  if(timewindow <= nodistparms["start_dist"]) return(simres)
  distparms <- nodistparms
  distparms["beta1"] <- distparms["beta1"] * distparms["effect_dist"]
  distparms["beta2"] <- distparms["beta2"] * distparms["effect_dist"]
  distparms["beta3"] <- distparms["beta3"] * distparms["effect_dist"]
  simres <- rbind(
    head(simres, -1),
    ode(
      y = tail(simres, 1)[, -1],
      times = seq(distparms["start_dist"], min(distparms["end_dist"], timewindow), 1),
      func = covidmodel,
      parms = distparms
    )
  )
  
  if(timewindow <= nodistparms["end_dist"]) return(simres)
  simres <- rbind(
    head(simres, -1),
    ode(
      y = tail(simres, 1)[, -1],
      times = seq(nodistparms["end_dist"], timewindow, 1),
      func = covidmodel,
      parms = nodistparms
    )
  )
  
  return(simres)
}

### a function to plot 3 scenarios
# For each scenario you can set parameter values in a list.
# The first scenario is considered a baseline, so all parameter values for
# scenario1 are also used for scenario2 and scenario3, unless specified otherwise
# in the lists for those scenarios. For instance,
# "plotscenarios(list(alpha = 0.3, sigma = 0.3), list(alpha = 0.5), list(beta1 = 2))" 
# uses alpha=0.3 in the first and third simulation, and sigma=0.3 in all three
plotscenarios <- function(
  scenario1 = list(), scenario2 = list(), scenario3 = list()
) {
  baselineplot <- do.call(covidsim, scenario1)
  altplot1 <- do.call(covidsim, c(scenario2, scenario1))
  altplot2 <- do.call(covidsim, c(scenario3, scenario1))
  
  allplots <- as_tibble(baselineplot) %>%
    mutate(scenario = "baseline") %>%
    full_join(
      as_tibble(altplot1) %>%
        mutate(scenario = "scenario_1") 
    ) %>%
    full_join(
      as_tibble(altplot2) %>%
        mutate(scenario = "scenario_2")
    ) %>%
    group_by(scenario) %>%
    mutate(
      Infection = Infected - lag(Infected),
      Reporting = Reported - lag(Reported)
    ) %>%
    ungroup()
  allplots %>% ggplot(aes(x = time, y = Reporting, color = scenario)) +
    geom_line(aes(color = scenario), size = 2)
  
}

### This part is specific for our own figure
labeldata <- tibble(
  time = c(130, 140, 155, 0),
  Reporting = c(3.5e5, 2.1e5, 1.25e5, .6e5),
  scenario = c("baseline", "scenario_1", "scenario_2", "baseline"),
  lab = c(
    paste0("Timing and width of peak uncertain due to\n",
           "-  Stochasticity in early dynamics\n",
           "-  Heterogeneities in contact patterns\n",
           "-  Spatial variation\n",
           "-  Uncertainty in key epidemiological parameters"),
    paste0("Social distancing\n",
           "flattens curve"),
    paste0("Risk of resurgence\n",
           "  following lifting of\n",
           "      interventions"),
    paste0("Epidemic growth,\n",
           "doubling time\n",
           "~4-7 days")
  )
)
arrowdata <- tibble(
  time = 205,
  timeend = 200,
  Reporting = .67e5,
  Repend = .12e5,
  scenario = "scenario_2"
)
plotscenarios(
  scenario1 = list(),
  scenario2 = list(effect_dist = 0.75, start_dist = 70, end_dist = 365),
  scenario3 = list(effect_dist = 0.5, start_dist = 80, end_dist = 200)
)  +
  labs(x = "Months since transmission established", y = "Rate of cases being reported") +
  scale_color_discrete(labels = NULL) +
  scale_x_continuous(breaks = seq(0, 370, 30), labels = 0:12) +
  scale_y_continuous(labels = NULL) +
  geom_text(aes(label = lab), data = labeldata, hjust = 0, size = 4) +
  geom_segment(aes(yend = Repend, xend = timeend), data = arrowdata, 
               arrow = arrow(), size = 1) +
  theme_classic() +
  theme(text = element_text(size = 12)) +
  guides(color = FALSE)
ggsave("Results/fig_main.tiff", units = "cm", width = 16, height = 10)

### Doubling times for some parameter combinations
simres <- covidsim(r_par = 1, b_par = 1)
10/(log2(simres[20,3]) - log2(simres[10,3]))  ###5.3
simres <- covidsim(r_par = 0.8, b_par = 0.8)
10/(log2(simres[20,3]) - log2(simres[10,3])) ###5.6

