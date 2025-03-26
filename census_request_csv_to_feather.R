library(tidyverse)
library(here)
library(arrow)


tract_level_19_23_data <- read_csv_arrow(here("data/ST361_2019thru2023_140_combined.csv"))

write_feather(tract_level_19_23_data, here("data/tract_level_19_23_data.feather"))


