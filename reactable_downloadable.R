# Load necessary libraries
library(shiny)
library(reactable)
library(htmltools)

# Define UI
ui <- fluidPage(
  titlePanel("Language Data Table"),
  sidebarLayout(
    sidebarPanel(
      # Add the download button using htmltools
      htmltools::browsable(
        tagList(
          tags$button("Download Filtered Data as CSV", 
                      onclick = "Reactable.downloadDataCSV('languageTable')"),
          # Note: The ID 'languageTable' must match the elementId of reactable
          tags$script(HTML(
            "Shiny.addCustomMessageHandler('downloadData', function(message) {
               Reactable.downloadDataCSV(message.id);
             });"
          ))
        )
      )
    ),
    mainPanel(
      reactableOutput("languageTable")
    )
  )
)

# Define server logic
server <- function(input, output, session) {
  
  data <- reactive({
    # Path to the CSV file in your home directory
    read.csv("LangAppData.csv")
  })
  
  output$languageTable <- renderReactable({
    req(data())
    reactable(
      data(),
      groupBy = c("LANP_label", "ST_label", "AgeGroup"),
      searchable = TRUE,
      showPageSizeOptions = TRUE,
      striped = TRUE,
      highlight = TRUE,
      fullWidth = FALSE,
      columns = list(
        LANP_label = colDef(name = "Language", filterable = TRUE),
        ENG_label = colDef(name = "Ability to Speak English", filterable = TRUE),
        AgeGroup = colDef(name = "Age Group", filterable = TRUE),
        ST_label = colDef(name = "State", filterable = TRUE),
        n = colDef(name = "Number of Speakers", aggregate = "sum")
      ),
      elementId = "languageTable"  # Important for JavaScript interaction
    )
  })
  
  observeEvent(input$downloadData, {
    session$sendCustomMessage('downloadData', list(id = "languageTable"))
  })
}

# Run the app
shinyApp(ui = ui, server = server)
