library(shiny)
library(mapgl)
library(here)
library(sf)
library(reactable)  # Added for interactive table
library(viridis)
# Load Data
county_data <- st_read(here("data/county_data.gpkg"))
tract_data <- st_read(here("data/tract_data.gpkg"))

# Get unique languages for dropdown
available_languages <- unique(tract_data$language)

# Define UI
ui <- fluidPage(
  tags$head(tags$link(rel = "stylesheet", type = "text/css", href = "custom.css")),
  
  # Title Panel with Custom Font
  titlePanel(
    div(
      img(src = "SpiceLogo1.png", height = "50px", 
          style = "vertical-align: middle; margin-right: 10px;"),
      span("LanguageFinder", class = "language-title")
    )
  ),
  
  sidebarLayout(
    sidebarPanel(
      selectInput(
        "language_choice", 
        "Choose a Language:", 
        choices = available_languages, 
        selected = "Spanish"
      ),
      # Informational Text Below the Dropdown (No Changes Here)
      div(
        HTML("
          <p><strong>Find out which languages other than English are spoken in particular places.</strong></p>
          <p>Translations and interpretation services are key tools to increase accessibility to information. 
          Access to information is especially important in relation to:</p>
          <ul>
            <li>Disaster warnings and disaster response;</li>
            <li>Healthcare, especially treatment options and recovery instructions;</li>
            <li>Local government engagement;</li>
            <li>Environmental justice;</li>
            <li>Workplace safety.</li>
          </ul>
          <p>See how many people speak a particular language in different places.</p>
          <p>Understanding how speakers of a certain language are distributed across the U.S. can help organizations 
          find collaborative partners in creating translations and interpretive services for that language.</p>
          <p>Organizations that serve particular language communities can use this information to identify key service areas.</p>
          <p>This project seeks to make data about languages spoken in the U.S. accessible to decision-makers in social sector enterprises. 
          Key variables for decision-makers include the detailed language spoken, ability to speak English, and potentially age, for 
          organizations that serve specific age groups, e.g., voting-age population, K-12 children, seniors, etc.</p>
          
          <h3>About the Data</h3>
          <p>The data comes from the <a href='https://www.census.gov/' target='_blank'>US Census Bureau</a> 
          <a href='https://www.census.gov/programs-surveys/acs' target='_blank'>American Community Survey</a>, 
          5-year estimates from 2019-2023. This is the most reliable and most recent data available on languages spoken at home in the US. 
          This data is collected using the following questions:</p>
          
          <img src='language_600_q14.avif' width='50%' alt='Language Spoken at Home question on the American Community Survey'>
          
          <p>The US Census Bureau reports 130 language categories, including 105 individual languages (e.g., Spanish, Hawaiian) and 25 aggregated language categories (e.g., Other Malayo-Polynesian languages, Aleut languages).</p>
          <p>Where age information is given, ages were divided into three categories: Youth (age 5-17), Working Age (18-64), and Senior (65-99). 
          Data for individuals under age 5 and above age 99 are not provided by the US Census Bureau.</p>
          <p>Where Ability to Speak English is given, this data is self-reported in part C of the question shown above.</p>
        ")
      )
    ),
    
    mainPanel(
      maplibreOutput("language_map", height = "600px"),
      br(),
      h3("Top 20 Census Tracts with the Highest Percentage of Speakers"),
      reactableOutput("top_tracts_table")  # ✅ Added this table, nothing else changed
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
  
  # Render the Map (No Changes Here)
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
          column = "percent_speakers",
          type = "linear",
          values = c(0, 2, 5, 10, 15, 20, 25, 30, 45, 50),
          stops = magma(10),  # 🔥 Using Viridis!
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
          column = "percent_speakers",
          type = "linear",
          values = c(0, 2, 5, 10, 15, 20, 25, 30, 45, 50),
          stops = magma(10),  # 🔥 Using Viridis!
          na_color = "lightgrey"
        ),
        fill_opacity = 0.7,
        max_zoom = 7.99,
        tooltip = "percent_speakers"
      ) |>
      add_continuous_legend(
        "Percent of Population Speaking Language",
        values = c(0, 2, 5, 10, 15, 20, 25, 30, 45, 50),
        colors = magma(10),  # 🔥 Using Viridis!
        width = "250px"
      )  
  })
  
  # ✅ Render Top 20 Census Tracts Table (Only This Part Was Added)
  output$top_tracts_table <- renderReactable({
    data <- selected_data()$tract %>%
      st_drop_geometry() %>%  # ✅ Removes the sf geometry column
      select(geoname, speakers, percent_speakers) %>%  # ✅ Keep only relevant columns
      arrange(desc(percent_speakers)) %>%
      head(20)  # Get top 20 tracts
    
    reactable(data, 
              columns = list(
                geoname = colDef(name = "Census Tract"),
                speakers = colDef(name = "Speakers", format = colFormat(separators = TRUE)),  # Adds commas
                percent_speakers = colDef(name = "Percent Speakers", format = colFormat(suffix = "%", digits = 2))
              ),
              highlight = TRUE,
              bordered = TRUE,
              striped = TRUE
    )
  })
}

# Run the Shiny App
shinyApp(ui, server)





