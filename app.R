# Libraries ----
library(shiny)
library(tidyverse)
library(here)
library(tigris)
library(tidycensus)
library(mapview)
library(sf)
library(rmapshaper)
library(leaflet)
library(plotly)


# Load and preprocess data ----
lang_data <- read_csv(here("LangAppData.csv")) %>%
  mutate(ST_label = sub("/.*", "", ST_label))

# Group and calculate percentages ----
lang_data_summary <- lang_data %>%
  group_by(ST_label, LANP_label, AgeGroup, ENG_label) %>%
  summarise(total_speakers = sum(n, na.rm = TRUE), .groups = "drop") %>%
  group_by(ST_label, LANP_label) %>%
  mutate(percentage = total_speakers / sum(total_speakers) * 100)

# Load and simplify state geometries ----
states_sf <- states(cb = TRUE) %>%
  ms_simplify(keep = 0.05)

# Process Data for the Map ----
lang_data_all_state <- lang_data %>%
  group_by(LANP_label, ST_label) %>%
  summarise(total_speakers = sum(n), .groups = "drop") %>%
  group_by(LANP_label) %>%
  mutate(percent_speakers = round((total_speakers / sum(total_speakers)) * 100, 0)) %>%
  rename(NAME = ST_label)

# Join spatial and language data ----
joined_data <- states_sf %>%
  left_join(lang_data_all_state, by = "NAME")

# Get state populations with simplified geometry ----
# state_pops <- get_estimates(geography = "state", product = "population", vintage = 2022) %>%
#   filter(variable == "POPESTIMATE") %>%
#   ms_simplify(keep = 0.05)

# Get state populations


lang_data <- lang_data %>%
  rename(NAME = ST_label)

# Join with population data ----
lang_data_state_pops <- full_join(lang_data, state_pops, by = "NAME")

# Calculate speakers per state ----
lang_data_by_state <- lang_data_state_pops %>%
  group_by(LANP_label, NAME, estimate, geom) %>%
  summarise(total_speakers_per_100k = round((sum(n) / estimate) * 100000, 0)) %>%
  st_as_sf()

# Function to dynamically generate color palettes
generate_palette <- function(n, palette_name = "Blues") {
  colorRampPalette(RColorBrewer::brewer.pal(9, palette_name))(n)
}


# UI ----
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
      selectInput("language", "Select a Language:", 
                  choices = unique(lang_data$LANP_label), 
                  selected = "Spanish"),
      
      # Informational Text Below the Dropdown
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
          5-year estimates from 2017-2021. This is the most reliable and most recent data available on languages spoken at home in the US. 
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
      leafletOutput("combined_map", height = "400px"),  # **Unchanged slider map**
      plotlyOutput("agegroup_barplot", height = "700px")  # **Increased height**
    )
  )
)


# Server ----
server <- function(input, output, session) {
  
  # Reactive: Filtered map data based on selected language ----
  reactive_data <- reactive({
    selected_language <- input$language
    
    # Filter for selected language
    map1_data <- joined_data %>% filter(LANP_label == selected_language) 
    map1_data <- map1_data %>%
      mutate(percent_speakers_tooltip = paste0(percent_speakers, "%")) %>%
      mutate(percent_speakers_label = paste0(percent_speakers, "%"))  
    
    map2_data <- lang_data_by_state %>% filter(LANP_label == selected_language)
    map2_data <- map2_data %>%
      mutate(total_speakers_per_100k_label = paste0(total_speakers_per_100k, " per 100,000 👤"))
    
    # Render maps
    map1 <- mapview(
      map1_data,
      zcol = "percent_speakers",
      layer.name = "Percentage of Language Speakers<br>Living in State",
      col.regions = generate_palette(9, "Blues"),
      na.color = "grey",
      label = map1_data$percent_speakers_label,
      popup = paste0("Percentage of Speakers: ", map1_data$percent_speakers_label)
    ) 
    
    map2 <- mapview(
      map2_data,
      zcol = "total_speakers_per_100k",
      layer.name = "Speakers per 100,000 Population",
      col.regions = generate_palette(9, "Greens"),
      na.color = "grey",
      label = map2_data$total_speakers_per_100k_label,
      popup = paste0("Speakers: ", map2_data$total_speakers_per_100k_label)
    )
    
    map1 | map2
  })
  
  # Render Map ----
  output$combined_map <- renderLeaflet({
    reactive_data()@map
  })
  
  # Reactive: Filtered data for stacked bar chart ----
  filtered_chart_data <- reactive({
    lang_data_summary %>%
      filter(LANP_label == input$language) %>%
      mutate(AgeGroup = factor(AgeGroup, levels = c("Youth", "Adult", "Senior")))  # Set factor order
  })
  
  
  # Render Stacked Bar Chart ----
  output$agegroup_barplot <- renderPlotly({
    chart_data <- filtered_chart_data()
    
    if (nrow(chart_data) == 0) return(NULL)  # Prevent error when no data
    
    p <- ggplot(chart_data, aes(x = ST_label, y = percentage, fill = ENG_label)) +
      geom_bar(stat = "identity", position = "stack") +
      facet_wrap(~AgeGroup) +  # **Facet by AgeGroup**
      coord_flip() +  # **Flip coordinates**
      scale_fill_viridis_d(option = "plasma") +
      labs(
        title = paste("Age & English Proficiency Breakdown for", input$language),
        x = "", y = "Percentage",
        fill = "English Proficiency"
      ) +
      theme_minimal() +
      theme(
        axis.text.y = element_text(size = 7),  # Adjust size for readability
        strip.text.y = element_text(angle = 0)  # Keep facet labels horizontal
      )
    
    ggplotly(p)
  })
}

# Run the app
shinyApp(ui = ui, server = server)
