library(querychat)
library(sf)
library(here)
library(tidyverse)
library(arrow)

county_df <- st_read(here("data/county_data.gpkg")) %>% 
  st_drop_geometry() %>% 
  mutate(level = "county")

tract_df <- st_read(here("data/tract_data.gpkg")) %>% 
  st_drop_geometry() %>% 
  mutate(level = "tract")

combined_data <- bind_rows(county_df, tract_df)

querychat_app(combined_data, client = "openai/gpt-4.1")

write_feather(combined_data, here("data/querychat_count_tract.feather"))

feather_test <- read_feather(here("data/querychat_count_tract.feather"))

