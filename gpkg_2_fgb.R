# Load required libraries
library(sf)
library(here)

# Read the GeoPackage files
tract_all <- st_read(here("data/tract_all.gpkg"))
county_all <- st_read(here("data/county_all.gpkg"))

# Write the sf objects to FlatGeobuf files
st_write(tract_all, here("data/tract_all.fgb"))
st_write(county_all, here("data/county_all.fgb"))

# Read the FlatGeobuf files
tract_all <- st_read(here("data/tract_all.fgb"))
county_all <- st_read(here("data/county_all.fgb"))
