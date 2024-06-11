#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#


# https://stackoverflow.com/questions/49415691/how-can-i-adjust-tidycensus-api-calls-with-shiny-app-input-and-visualize-the-res

library(shiny)

# Define UI for application that draws a histogram
ui <- fluidPage(
  titlePanel("Languages by Public Use Microdata Area (PUMA)"),
  
  # Create a new Row in the UI for selectInputs
  fluidRow(
    column(4,
           selectInput("PUMA20",
                       "PUMA:",
                       c("All",
                         unique(as.character(nonEng$PUMA20))))
    ),
    column(4,
           selectInput("LANP_label",
                       "Language:",
                       c("All",
                         unique(as.character(nonEng$LANP_label))))
    ),
    column(4,
           selectInput("AgeGroup",
                       "Age Group:",
                       c("All",
                         unique(as.character(nonEng$AgeGroup))))
    ),
    column(4,
           selectInput("ENG_label",
                       "English Proficiency:",
                       c("All",
                         unique(as.character(nonEng$ENG_label))))
    )
  ),
  # Create a new row for the table.
  DT::dataTableOutput("table")
)


# Define server logic required to draw a histogram
server <- function(input, output) {
    
    # Filter data based on selections
    output$table <- DT::renderDataTable(DT::datatable({
      data <- lang_totals
      if (input$PUMA20 != "All") {
        data <- data[data$PUMA20 == input$PUMA20,]
      }
      if (input$LANP_label != "All") {
        data <- data[data$LANP_label == input$LANP_label,]
      }
      if (input$AgeGroup != "All") {
        data <- data[data$AgeGroup == input$AgeGroup,]
      }
      if (input$ENG_label != "All") {
        data <- data[data$ENG_label == input$ENG_label,]
      }
      data
    }))
    
  }

# Run the application 
shinyApp(ui = ui, server = server)
