library(tidyverse)
library(here)
library(arrow)
library(janitor)
library(tigris)
library(tidycensus)
library(mapgl)
library(shiny)
library(sf)

# Read in Data 

tract_level_19_23_data <- read_feather(here("data/tract_level_19_23_data.feather"))

tract_level_19_23_data <- tract_level_19_23_data %>% 
  clean_names()

tract_level_19_23_data$cest <- as.numeric(tract_level_19_23_data$cest)


tract_level_19_23_data <- tract_level_19_23_data %>% 
  filter(age == "Total", ability_to_speak_english == "Total", language != "Total")


tract_level_sums_per_language <- tract_level_19_23_data %>% 
  group_by(geoname, language) %>% 
  summarize(speakers = sum(cest, na.rm = TRUE))

county_level_sums_per_language <- tract_level_sums_per_language %>% 
  mutate(geoname = stringr::str_extract(geoname, "(?<=, ).*")) %>%
  group_by(geoname, language) %>%
  #filter(language != "Total") %>% ???
  summarise(speakers = sum(speakers, na.rm = TRUE))
  

# Add shapefiles with populations for tracts

tract_pops <- get_acs(
  geography = "tract",
  variables = "B01003_001",  # Total Population
  state = c(state.abb, "DC", "PR"),
  year = 2023,
  geometry = TRUE,
  resolution = "5m"
)

tract_pops <- tract_pops %>% 
  rename(geoname = "NAME")

tract_level_sums_per_language <- tract_level_sums_per_language %>% 
  mutate(geoname = stringr::str_replace_all(geoname, ",", ";"))

tract_data <- full_join(tract_level_sums_per_language, tract_pops, 
                        by = "geoname")


# Add shapefiles with populations for counties

county_pops <- get_acs(
  geography = "county",
  variables = "B01003_001",  # Total Population
  state = c(state.abb, "DC", "PR"),
  year = 2023,
  geometry = TRUE,
  resolution = "5m"
)

county_pops <- county_pops %>% 
  rename(geoname = "NAME")


county_data <- full_join(county_level_sums_per_language, county_pops,
                         by = c("geoname"))

# Set as sf objects
tract_data <- st_as_sf(tract_data)
county_data <- st_as_sf(county_data)


# define speakers as percentage of speakers per tract or per county

tract_data <- tract_data %>% 
  mutate(percent_speakers = round((speakers / estimate) * 100, 2))

county_data <- county_data %>% 
  mutate(percent_speakers = round((speakers / estimate) * 100, 2))



# Write as sf objects

st_write(county_data, here("data/county_data.gpkg"), delete_layer = TRUE)
st_write(tract_data, here("data/tract_data.gpkg"), delete_layer = TRUE)


