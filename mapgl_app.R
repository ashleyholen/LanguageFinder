library(shiny)
library(mapgl)
library(here)
library(sf)

county_data <- st_read(here("data/county_data.gpkg"))
tract_data <- st_read(here("data/tract_data.gpkg"))


# App
# Get unique languages for dropdown
available_languages <- unique(tract_data$language)

# Define UI
ui <- fluidPage(
  titlePanel("Language Distribution Map"),
  
  sidebarLayout(
    sidebarPanel(
      selectInput(
        "language_choice", 
        "Choose a Language:", 
        choices = available_languages, 
        selected = "Spanish"
      )
    ),
    
    mainPanel(
      maplibreOutput("language_map", height = "600px")
    )
  )
)

# Define Server Logic
server <- function(input, output, session) {
  
  # Reactive dataset based on selected language
  selected_data <- reactive({
    tract_filtered <- tract_data %>%
      filter(language == input$language_choice)
    
    county_filtered <- county_data %>%
      filter(language == input$language_choice)
    
    list(tract = tract_filtered, county = county_filtered)
  })
  
  # Render the Map
  output$language_map <- renderMaplibre({
    data <- selected_data()
    
    maplibre(
      style = carto_style("positron"),
      center = c(-98.5795, 39.8283),
      zoom = 3
    ) |>
      set_projection("globe") |>
      add_fill_layer(
        id = "fill-layer",
        source = data$tract,
        fill_color = interpolate(
          column = "percent_speakers",  # Use precomputed percent
          type = "linear",
          values = c(0, 10, 50),  # Adjust based on distribution
          stops = c("#edf8b1", "#7fcdbb", "#2c7fb8"),
          na_color = "lightgrey"
        ),
        fill_opacity = 0.7,
        min_zoom = 8,
        tooltip = "percent_speakers"
      ) |>
      add_fill_layer(
        id = "county-fill-layer",
        source = data$county,
        fill_color = interpolate(
          column = "percent_speakers",  # Use precomputed percent
          type = "linear",
          values = c(0, 5, 25),  # Adjust based on distribution
          stops = c("#edf8b1", "#7fcdbb", "#2c7fb8"),
          na_color = "lightgrey"
        ),
        fill_opacity = 0.7,
        max_zoom = 7.99,
        tooltip = "percent_speakers"
      ) |>
      add_continuous_legend(
        "Percent of Population Speaking Language",
        values = c("0%", "10%", "50%"),
        colors = c("#edf8b1", "#7fcdbb", "#2c7fb8")
      )
  })
}

# Run the Shiny App
shinyApp(ui, server)
