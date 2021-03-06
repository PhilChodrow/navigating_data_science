#' -------------------------------------------------------------------------
#' CASE STUDY: Advanced Topics in Data Science
#' By Phil Chodrow
#' January 16th, 2020
#' -------------------------------------------------------------------------

#' This is the script for following along with our case-study analysis of trends 
#' in per-person rental prices. Following along with the case study is highly 
#' recommended. 

#' Prior to running any code, you probably want to go to 
#' Session > Set Working Directory > To Source File Location

#' We actually have a few more packages to install: 

#' install.packages(c('leaflet', 'flexdashboard'))


#' Load libraries ----------------------------------------------------------

library(tidyverse) #' includes dplyr, tidyr, ggplot2, purrr
library(broom)     #' for retrieving model predictions
library(lubridate) #' for manipulating dates and times
library(leaflet)   #' for geospatial visualization

#' Today we are going to continue with that AirBnB data set we used earlier
#' in our time together. We are going to use two distinct data sets. 

#' One more package installation for later

#' install.packages('flexdashboard')

#' Now let's readin our data. We have two data sets for today: 
#' 1. `prices` contains the prices per person accommodated for each listing, over
#' time. 
#' 2. `listings` contains information about each listing, like the numbers of 
#' bedrooms and bathrooms; ratings, that kind of thing. 

#' The data is contained in two directories, but each data set is broken up
#' into many separate pieces. Here's one way to handle that: 

names <- list.files('data/prices', full.names = T)

prices <- data_frame()
for(name in names){
  df <- read_csv(name)
  prices <- rbind(df, prices)
}
prices


#'---------------------------------------------------------------------------- 
#' 
#'----------------------------------------------------------------------------

#' Now that we've discussed the concept behind `map()`, let's use it to read 
#' in the data more efficiently. 

listings <- list.files('data/listings', full.names = TRUE) %>% 
  map(read_csv) %>% 
  reduce(rbind)

prices <- list.files('data/prices', full.names = TRUE) %>% 
  map(read_csv) %>% 
  reduce(rbind)

#' Take a moment to inspect the data by typing the name of each data frame 
#' (prices and listings)  in the terminal. Hopefully some of the column names 
#' look pretty familiar. The `price_per` column was computed for you by dividing
#' the price of the listing on the given date by the number of people that listing
#' accomodates. You can see the file `prep_data.R` for the full data preparation 
#' process. 

#' Preliminary Exploration -------------------------------------------------

#' EXERCISE: The first version of 
#' our analysis question is: 
#' 
#' > How do AirBnB prices vary over time? 

#' For a first pass at this question, let's plot the mean price per person over time. 
#' over time. Some pointers: 
#' 	- Use `group_by(date) %>% summarise()`` to create a data frame holding the mean
#' 	- We probably want `geom_line()`` again. 
#'  - We are going to come back to this plot, so name it `p`

p <- prices %>% 
	group_by(date) %>% 
	summarise(mean_pp = mean(price_per, na.rm = T)) %>% 
	ggplot() +
	aes(x = date, y = mean_pp) + 
	geom_line()
p

#' Three interesting things are happening here...what are they? 

#' Modeling ----------------------------------------------------------------
#' We want to peel out the seasonal variation present in the data. 
#' The seasonal variation should be a smooth curve that varies slowly. 
#' LOESS (**LO**cally **E**stimated **S**catterplot **S**moothing) is a simple 
#' method for fitting such models. LOESS is easy to use; in fact, it's the 
#' default option for `geom_smooth`:

p + geom_smooth()

#' Ok, so that's helpful, but we've seen that the seasonal variation is different
#' between listings. Eventually, we want to fit a *different* model to *each*
#' listing. For now, let's fit a single one. The span is a hyperparameter, a bit
#' like lambda in LASSO. 

model_data <- prices %>%       # extract a single listing's 
	filter(listing_id == 5506)   # worth of data

single_model <-  loess(price_per ~ as.numeric(date),  
					   data = model_data, span = .2)

single_model 
single_model %>% summary()

#' We can get the smoothing curve as the predicted value from the model. 
#' The most convenient way to do this is using the `augment()` function from the 
#' `broom` package. The output is a data frame containing all the original data, 
#' plus the fitted model values, standard errors, and residuals. 

model_preds <- augment(single_model, model_data) 
model_preds %>% head()

#' Note that the `augment()` function returns fitted values, residuals, and 
#' standard errors, in addition to the original columns. 

#' EXERCISE: Working with your partner, plot both the  `price_per` column and 
#' the `.fitted` column against the date. 

model_preds %>%
	ggplot(aes(x = date)) + 
	geom_line(aes(y = price_per)) + 
	geom_line(aes(y = .fitted), color = 'red')

#' Now, we need to do this many times for each listing. For this we'll use
#' the `map()` and `map2()` functions. These functions are convenient syntactic
#' tools that allow us to avoid messy `for` loops. 

prices_modeled <- prices %>% 
  nest(-listing_id) %>% 
  mutate(model = map(data, ~loess(price_per ~ as.numeric(date), data = ., span = .25)),
         preds = map2(model, data, augment)) %>% 
  unnest(preds)

#' The first three columns are exactly where we started, but the last three are 
#' new: they give the model predictions (and prediction uncertainty) that we've
#' generated. Let's rename the .fitted column "trend" instead:

prices_modeled <- prices_modeled %>% 
	rename(trend = .fitted) 

#' EXERCISE: Now, working with a partner, please visualize the model predictions
#' against the actual data for the first 2000 rows. Use geom_line() for both. 
#' You'll need to use geom_line() twice, with a different y aesthetic in each,
#' and you should consider using facet_wrap to show each listing and its model
#' in a separate plot. 

prices_modeled %>% 
	head(2000) %>% 
	ggplot(aes(x = date, group = listing_id)) +
	geom_line(aes(y = price_per)) +
	geom_line(aes(y = trend), color = 'red') +
	facet_wrap(~listing_id, ncol = 1, scales = 'free_y') + 
	theme(strip.text.x = element_blank())

#'---------------------------------------------------------------------------- 
#'
#'----------------------------------------------------------------------------

#' Isolating the Signal ----------------------------------------------------

#' Our next step is to begin isolating the April signal. We can think of the 
#' LOESS models we've fit as expressing the signal of long-term, seasonal 
#' variation. Next, we should capture the short-term, periodic signal. While
#' there are packages that can do this in a systematic way, we don't actually
#' need to use them, because we know the period of the signal -- the 7-day week. 
#' Our strategy is simple: we'll compute the average residual associated with 
#' each weekday. This is easy with a little help from the lubridate package. 
#' Note that .resid is "what's left" after we've accounted for the seasonal 
#' variation, so it's what we should be working with. 

prices_modeled <- prices_modeled %>% 
	mutate(weekday = wday(date, label = TRUE)) %>% #' compute the weekday
	group_by(listing_id, weekday) %>% 
	mutate(periodic = mean(.resid)) %>% 
	ungroup()

#' Now we can construct a new column for the part of the signal that's not 
#' captured by either the long-term trend or the periodic oscillation:  

prices_modeled <- prices_modeled %>% 
	mutate(remainder = price_per - trend - periodic)

#' Now, let's plot all four columns 
#' (price_per, trend, periodic, and remainder) as facets on the same visualization. 
#' To do this, we use `gather()` to "reshape" our data to be longer. 

prices_modeled %>% 
	head(1500) %>% 
	select(-.se.fit, -.resid, -weekday) %>% 
	gather(metric, value, -listing_id, -date) %>% 
	mutate(metric = factor(metric, c('price_per',
									 'trend',
									 'periodic',
									 'remainder'))) %>%
	ggplot() + 
	aes(x = date, 
		y = value, 
		group = listing_id, 
		color = as.character(listing_id)) + 
	geom_line() + 
	facet_grid(metric~., scales = 'free_y') +
	guides(color = FALSE)

#' EXERCISE: Now we can also take a look at the overall trend in what part of the
#' signal we've failed to capture. Working with your partner, construct a simple 
#' visualization of the mean of the remainder column over time. What do you see?

prices_modeled %>% 
	group_by(date) %>% 
	summarise(mean_remainder = mean(remainder, na.rm = T)) %>% 
	ggplot() + 
	aes(x = date, y = mean_remainder) + 
	geom_line()

#' We haven't done a perfect modeling job, but we have made considerable progress
#' toward isolating the signal in April. If we like, we can compare this picture to 
#' the original signal p from before: 
p

#' Now to K-Means ---------------------------------------------------------

#' Our motivating problem is: while the signal is apparent on average, not every 
#' individual raises their prices in April. How can we identify individual 
#' listings who did? There are plenty of ways to approach this, but we are going 
#' to practice our tidy modeling skills by using k-means. The idea is to separate
#' listings that raised their prices from listings that didn't into two "clusters." 

#' First, we need to prepare the data. K-means operates on a matrix, so the following
#' code prepares the data in matrix format. 

prices_to_cluster <- prices_modeled %>% 
  filter(month(date, label = T) == 'Apr') %>% 
  select(listing_id, date, remainder) %>% 
  group_by(listing_id) %>% 
  filter(n() == 30) %>% 
  ungroup() %>% 
  spread(key = date, value = remainder)

prices_matrix <- prices_to_cluster %>% 
  select(-listing_id) %>% 
  as.matrix()

#' From our hypothesis, we'd love it if there were two valid clusters in the data, 
#' but we don't know that for certain. We should first check. 
#' We'll fit 10 models for each of k = 1...10, for a total of 100 models.
#' As before, `map`` makes this easy. Note that an equivalent and more concise
#' approach would be 

set.seed(1234)
cluster_models <- data_frame(k = rep(1:10, 10)) %>%
	mutate(kclust = map(k, ~ kmeans(prices_matrix, .)))


#' Model Evaluation ------------------------------------------------------------

#' Now we can retrieve the model performance from each of the 100 models we fitted. 
#' The relevant performance metric in the context of K-means is called "tot.withinss." 
#' Better models have low values of this metric. 

cluster_performance <- cluster_models %>% 
	mutate(summary = map(kclust, glance)) %>% 
	unnest(summary)

#' EXERCISE: Compute the mean tot.withinss for each value of k and plot the
#' results, with k on the x-axis and the mean tot.withinss on the y-axis. What
#' value of k should we use? 

cluster_performance %>% 
	group_by(k) %>%
	summarise(withinss = mean(tot.withinss)) %>%
	ggplot() + 
	aes(x = k, y = withinss) +
	geom_point() 

#' We really only need one cluster, so let's extract the first one with our 
#' chosen value of k. 

chosen_model <- cluster_models$kclust[cluster_models$k == 2][[1]]

#' Now we can make a lookup table giving the cluster label for each listing. 

cluster_lookup <- prices_to_cluster %>% 
	mutate(cluster = chosen_model$cluster) %>% 
  select(listing_id, cluster)

#' Let's now `left_join` this lookup table to our original prices data. 

prices <- prices %>% 
  left_join(cluster_lookup, by = c('listing_id' = 'listing_id')) %>% 
  filter(!is.na(cluster)) 

#' EXERCISE: Plot the mean price for each day for the two clusters. 
#' Use a `color` aesthetic to distinguish between the two clusters. 
#' Call the result of your code `cluster_trends`

cluster_trends <- prices %>% 
  group_by(date, cluster) %>% 
  summarise(mean_pp = mean(price_per, na.rm = T)) %>% 
  ggplot() + 
  aes(x = date, y = mean_pp, group = cluster, color = as.character(cluster)) + 
  geom_line() + 
  theme_bw() + 
  scale_color_manual(values = c('navy', 'orange')) + 
  guides(color = FALSE)

cluster_trends

#' Geospatial Visualization ----------------------------------------------------

#' We've isolated the signal: users in one group have large spikes at the 
#' specific week in April; users in the other don't. Now we're ready to visualize
#' where these listings are located in geographic space. 
#' To do so, we need to combine our cluster labels with the geographic information
#' in the `listings` data frame. We'll use `left_join()` for this, but first
#' we need to remove all the duplicates in `prices_clustered`.  

locations_to_plot <- listings %>% 
	left_join(cluster_lookup, by = c('id' = 'listing_id')) %>% 
	filter(!is.na(cluster)) 

locations_to_plot

#' Now we'll plot using leaflet, an interative geospatial 
#' visualization library. 
library(leaflet)

pal <- colorFactor(c("navy", "orange"), domain = c("1", "2"))

m <- leaflet(data = locations_to_plot)%>% 
	addProviderTiles(providers$CartoDB.Positron) %>% 
	addCircles(~longitude, ~latitude, radius = 50, color = ~pal(cluster), label = ~paste(name, ':', review_scores_rating))
m	
#' Does this map support or testify against our hypothesis?




