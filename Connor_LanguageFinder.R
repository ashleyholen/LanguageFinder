library(shiny)
library(mapgl)
library(sf)
library(tidyverse)
library(here)
library(viridis)
library(reactable)

# Load full spatial data
tract_all <- st_read(here("data/tract_all.fgb"))
county_all <- st_read(here("data/county_all.fgb"))

# Extract county + state from geoname
tract_all <- tract_all %>%
  mutate(
    county_name = str_extract(geoname, ";\\s[^;]+ County|Parish|Borough") %>%
      str_remove(";\\s") %>% str_trim(),
    state_name = str_extract(geoname, ";\\s[^;]+$") %>%
      str_remove(";\\s") %>% str_trim(),
    county_label = paste(county_name, state_name, sep = ", ")
  )

state_choices <- sort(unique(tract_all$state_name))
english_choices <- sort(unique(tract_all$ability_to_speak_english))
age_choices <- sort(unique(tract_all$age))
available_languages <- sort(unique(tract_all$language))

# UI
ui <- navbarPage(
  title = div(
    img(src = "SpiceLogo1.png", height = "40px", style = "vertical-align: middle; margin-right: 10px;"),
    span("LanguageFinder", style = "vertical-align: middle; font-weight: bold;")
  ),
  
  tabPanel("Search by Geography",
           fluidPage(
             story_maplibre(
               map_id = "map",
               sections = list(
                 "intro" = story_section(
                   title = "Languages Spoken by County & Tract",
                   content = list(
                     selectInput("state", "Choose a State:", choices = state_choices, selected = "Hawaii"),
                     uiOutput("county_ui"),
                     selectInput("eng_filter", "Ability to Speak English:", choices = english_choices, selected = "Total"),
                     selectInput("age_filter", "Age Group:", choices = age_choices, selected = "Total"),
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
  ),
  
  tabPanel("Search by Language",
           fluidPage(
             sidebarLayout(
               sidebarPanel(
                 selectInput("language_choice", "Choose a Language:", choices = available_languages, selected = "Hawaiian"),
                 div(HTML("
            <p><strong>Find out which languages other than English are spoken in particular places.</strong></p>
            <ul>
              <li>Disaster response, healthcare, and environmental justice</li>
              <li>Engagement in local government</li>
              <li>Workplace safety and more</li>
            </ul>
            <p>Explore how speakers of a language are distributed across the U.S.</p>
            <p>Updated March 2025</p>
          "))
               ),
               mainPanel(
                 h3("Map of Locations where Selected Language is Spoken"),
                 maplibreOutput("language_map", height = "600px"),
                 br(),
                 h3("Top 20 Census Tracts with the Highest Percentage of Speakers"),
                 reactableOutput("top_tracts_table")
               )
             )
           )
  )
)

# Server
server <- function(input, output, session) {
  ### --- Geography Tab --- ###
  output$county_ui <- renderUI({
    req(input$state)
    
    county_choices <- tract_all %>%
      filter(state_name == input$state) %>%
      pull(county_label) %>%
      unique() %>%
      sort()
    
    default_county <- if ("Honolulu County, Hawaii" %in% county_choices) {
      "Honolulu County, Hawaii"
    } else {
      county_choices[1]
    }
    
    selectInput("county", "Choose a County:",
                choices = county_choices,
                selected = default_county)
  })
  
  
  sel_tracts <- reactive({
    req(input$county, input$eng_filter, input$age_filter)
    
    tract_all %>%
      filter(
        county_label == input$county,
        ability_to_speak_english == input$eng_filter,
        age == input$age_filter,
        language != "Total",
        !is.na(language)
      ) %>%
      group_by(GEOID) %>%
      slice_max(speakers, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      st_set_geometry("geom")
  })
  
  output$map <- renderMaplibre({
    maplibre(carto_style("positron"), scrollZoom = FALSE)
  })
  
  on_section("map", "intro", {
    maplibre_proxy("map") |> fit_bounds(county_all, animate = TRUE)
  })
  
  on_section("map", "county", {
    selected <- sel_tracts() %>%
      filter(!is.na(language))
    
    if (nrow(selected) == 0) {
      maplibre_proxy("map") |>
        clear_layer("tracts") |>
        clear_layer("tract_borders") |>
        clear_legend()
      return()
    }
    
    selected <- selected %>%
      mutate(language = as.factor(language)) %>%
      mutate(lang_id = as.numeric(language)) %>%
      mutate(popup_text = paste0(
        "<b>", geoname, "</b><br>",
        "Top Language: ", language, "<br>",
        "Speakers: ", format(speakers, big.mark = ","), "<br>",
        "Percent: ", percent_speakers, "%"
      ))
    
    lang_vals <- levels(selected$language)
    
    if (is.character(lang_vals) && length(lang_vals) > 0) {
      lang_colors <- viridisLite::turbo(length(lang_vals))
      
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
    } else {
      maplibre_proxy("map") |>
        clear_layer("tracts") |>
        clear_layer("tract_borders") |>
        clear_legend()
    }
  })
  
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
  
  ### --- Language Tab --- ###
  selected_data <- reactive({
    tract_filtered <- tract_all %>% filter(language == input$language_choice)
    county_filtered <- county_all %>% filter(language == input$language_choice)
    list(tract = tract_filtered, county = county_filtered)
  })
  
  output$language_map <- renderMaplibre({
    data <- selected_data()
    
    maplibre(style = carto_style("positron"), center = c(-98.5795, 39.8283), zoom = 3) |>
      set_projection("globe") |>
      add_fill_layer(
        id = "fill-layer",
        source = data$tract,
        fill_color = interpolate(
          column = "percent_speakers",
          type = "linear",
          values = c(0, 0.5, 1, 2, 5, 10, 20, 30, 50),
          stops = rev(mako(9)),
          na_color = "lightgrey"
        ),
        fill_opacity = 0.7,
        min_zoom = 8,
        tooltip = "percent_speakers",
        popup = "geoname"
      ) |>
      add_fill_layer(
        id = "county-fill-layer",
        source = data$county,
        fill_color = interpolate(
          column = "percent_speakers",
          type = "linear",
          values = c(0, 0.5, 1, 2, 5, 10, 20, 30, 50),
          stops = rev(mako(9)),
          na_color = "lightgrey"
        ),
        fill_opacity = 0.7,
        max_zoom = 7.99,
        tooltip = "percent_speakers",
        popup = "geoname"
      ) |>
      add_continuous_legend(
        "Percent of Population Speaking Language",
        values = c(0, 0.5, 1, 2, 5, 10, 20, 30, 50),
        colors = rev(mako(9)),
        width = "250px"
      )
  })
  
  output$top_tracts_table <- renderReactable({
    selected_data()$tract %>%
      st_drop_geometry() %>%
      select(geoname, speakers, percent_speakers) %>%
      arrange(desc(percent_speakers)) %>%
      head(20) %>%
      reactable(
        columns = list(
          geoname = colDef(name = "Census Tract"),
          speakers = colDef(name = "Speakers", format = colFormat(separators = TRUE)),
          percent_speakers = colDef(name = "Percent Speakers", format = colFormat(suffix = "%", digits = 2))
        ),
        highlight = TRUE,
        bordered = TRUE,
        striped = TRUE
      )
  })
}

shinyApp(ui, server)
