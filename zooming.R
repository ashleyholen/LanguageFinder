library(shiny)
library(mapgl)
library(sf)
library(tidyverse)
library(here)

# Load spatial data
tract_data <- st_read(here("data/tract_data.gpkg"))
county_data <- st_read(here("data/county_data.gpkg"))

# Extract county + state from geoname
tract_data <- tract_data %>%
  mutate(
    county_name = str_extract(geoname, ";\\s[^;]+ County|Parish|Borough") %>%
      str_remove(";\\s") %>% str_trim(),
    state_name = str_extract(geoname, ";\\s[^;]+$") %>%
      str_remove(";\\s") %>% str_trim(),
    county_label = paste(county_name, state_name, sep = ", ")
  )

# Get sorted list of states
state_choices <- sort(unique(tract_data$state_name))

# UI
ui <- fluidPage(
  story_maplibre(
    map_id = "map",
    sections = list(
      "intro" = story_section(
        title = "Languages Spoken by County",
        content = list(
          selectInput("state", "Choose a State:", choices = state_choices),
          uiOutput("county_ui"),
          p("Scroll down to zoom to the selected county and view language data by tract.")
        )
      ),
      "county" = story_section(
        title = NULL,
        content = list(
          uiOutput("county_title"),
          plotOutput("language_plot")
        )
      )
    )
  )
)

# Server
server <- function(input, output, session) {
  
  # Filtered county options based on selected state
  output$county_ui <- renderUI({
    req(input$state)
    counties_in_state <- tract_data %>%
      filter(state_name == input$state) %>%
      distinct(county_label) %>%
      arrange(county_label)
    
    selectInput("county", "Choose a County:",
                choices = counties_in_state$county_label)
  })
  
  # Get top language per tract for selected county
  sel_tracts <- reactive({
    req(input$county)
    tract_data %>%
      filter(county_label == input$county) %>%
      filter(language != "Total", !is.na(language)) %>%
      group_by(GEOID) %>%
      slice_max(speakers, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      st_set_geometry("geom")  # ensure geometry is correctly assigned
  })
  
  # Base map
  output$map <- renderMaplibre({
    maplibre(
      carto_style("positron"),
      scrollZoom = FALSE
    )
  })
  
  # Zoom out on intro
  on_section("map", "intro", {
    maplibre_proxy("map") |>
      fit_bounds(county_data, animate = TRUE)
  })
  
  on_section("map", "county", {
    selected <- sel_tracts() %>%
      filter(!is.na(language)) %>%
      st_set_geometry("geom") %>%
      mutate(language = as.factor(language)) %>%
      mutate(lang_id = as.numeric(language)) %>%
      mutate(
        popup_text = paste0(
          "<b>", geoname, "</b><br>",
          "Top Language: ", language, "<br>",
          "Speakers: ", format(speakers, big.mark = ","), "<br>",
          "Percent: ", percent_speakers, "%"
        )
      )
    
    lang_vals <- levels(selected$language)
    lang_colors <- viridisLite::turbo(length(lang_vals))
    color_map <- set_names(lang_colors, lang_vals)
    
    maplibre_proxy("map") |>
      clear_layer("tracts") |>
      clear_layer("tract_borders") |>
      clear_legend() |>
      
      add_fill_layer(
        id = "tracts",
        source = selected,
        fill_color = interpolate(
          column = "lang_id",
          values = seq_along(lang_vals),
          stops = lang_colors,
          na_color = "lightgrey"
        ),
        fill_opacity = 0.8,
        popup = "popup_text"
      ) |>
      add_line_layer(
        id = "tract_borders",
        source = selected,
        line_color = "#ffffff",
        line_width = 1
      ) |>
      add_categorical_legend(
        legend_title = "Most Spoken Language",
        values = lang_vals,
        colors = lang_colors,
        position = "bottom-right"
      ) |>
      fit_bounds(selected, animate = TRUE)
  })
  
  # Title and plot
  output$county_title <- renderUI({
    req(input$county)
    h2(input$county)
  })
  
  output$language_plot <- renderPlot({
    sel_tracts() %>%
      group_by(language) %>%
      summarise(speakers = sum(speakers, na.rm = TRUE)) %>%
      arrange(desc(speakers)) %>%
      slice_head(n = 15) %>%
      ggplot(aes(x = reorder(language, speakers), y = speakers)) +
      geom_col(fill = "#3182bd") +
      coord_flip() +
      labs(x = NULL, y = "Speakers", title = "Top Languages in Selected County") +
      theme_minimal(base_size = 14)
  })
}

shinyApp(ui, server)
