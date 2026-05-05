library(shiny)
library(bslib)
library(mapgl)
library(sf)
library(tidyverse)
library(here)
library(viridis)
library(reactable)
library(plotly)
library(querychat)
library(arrow) 

# Load spatial data
tract_data <- st_read(here("data/tract_data.gpkg"))
county_data <- st_read(here("data/county_data.gpkg"))

# Load querychat data
language_qc_data <- read_feather(here("data/querychat_count_tract.feather"))

# Create QueryChat object
qc <- QueryChat$new(
  language_qc_data,
  client = "openai/gpt-4.1",
  data_description = "data_description.md",
  greeting = "Hello! I'm here to help you explore U.S. Census language data. Ask me about speakers of different languages across census tracts and counties."
)

# Extract county + state from geoname
tract_data <- tract_data %>%
  mutate(
    county_name = str_extract(geoname, ";\\s[^;]+ (County|Parish|Borough)") %>%
      str_remove(";\\s") %>%
      str_trim(),
    state_name = str_extract(geoname, ";\\s[^;]+$") %>%
      str_remove(";\\s") %>%
      str_trim(),
    county_label = paste(county_name, state_name, sep = ", ")
  )

state_choices <- sort(unique(tract_data$state_name))
state_choices_ui <- c("Select a state..." = "", state_choices)
available_languages <- sort(unique(tract_data$language))

# ── Help Drawer ───────────────────────────────────────────────────────────────
help_drawer <- tagList(
  
  tags$style(HTML("
    #help-drawer {
      position: fixed;
      top: 51px; right: 0;
      width: 400px;
      height: calc(100% - 51px);
      background: #ffffff;
      box-shadow: -4px 0 20px rgba(0,0,0,0.13);
      z-index: 9999;
      transform: translateX(0);
      transition: transform 0.35s cubic-bezier(0.4,0,0.2,1);
      overflow-y: auto;
      padding: 0 0 40px 0;
      box-sizing: border-box;
      font-size: 15px;
    }
    #help-drawer.closed {
      transform: translateX(400px);
    }

    #help-toggle {
      position: fixed;
      top: 50%;
      right: 400px;
      transform: translateY(-50%);
      background: #2c7fb8;
      color: white;
      border: none;
      border-radius: 8px 0 0 8px;
      padding: 16px 10px;
      cursor: pointer;
      z-index: 10000;
      font-size: 0.9rem;
      writing-mode: vertical-rl;
      text-orientation: mixed;
      letter-spacing: 0.06em;
      font-weight: 700;
      font-family: sans-serif;
      transition: right 0.35s cubic-bezier(0.4,0,0.2,1), background 0.2s;
      box-shadow: -2px 2px 8px rgba(0,0,0,0.18);
      line-height: 1.2;
      white-space: nowrap;
    }
    #help-toggle:hover { background: #1a5f8a; }
    #help-toggle.closed { right: 0; }

    .drawer-tab-nav {
      display: flex;
      border-bottom: 2px solid #e8f0f7;
      background: #f7fafd;
      position: sticky;
      top: 0;
      z-index: 10;
    }
    .drawer-tab-btn {
      flex: 1;
      background: none;
      border: none;
      border-bottom: 3px solid transparent;
      padding: 13px 6px 11px;
      font-size: 0.97rem;
      font-weight: 600;
      color: #6a8aaa;
      cursor: pointer;
      transition: color 0.2s, border-color 0.2s;
      font-family: sans-serif;
      letter-spacing: 0.01em;
    }
    .drawer-tab-btn:hover { color: #2c7fb8; }
    .drawer-tab-btn.active {
      color: #2c7fb8;
      border-bottom: 3px solid #2c7fb8;
      background: #fff;
    }

    .drawer-tab-content {
      display: none;
      padding: 20px 24px 10px 24px;
    }
    .drawer-tab-content.active { display: block; }

    .drawer-intro {
      background: #eaf4fb;
      border-left: 4px solid #2c7fb8;
      border-radius: 0 8px 8px 0;
      padding: 11px 15px;
      font-size: 1.2rem;
      color: #2c4a6e;
      margin-bottom: 18px;
      line-height: 1.6;
    }
    .help-steps ol { margin: 0; padding-left: 20px; }
    .help-steps li {
      font-size: 1.2rem;
      color: #3a4a5c;
      margin-bottom: 12px;
      line-height: 1.65;
    }
    .help-steps li:last-child { margin-bottom: 0; }

    .help-tips {
      background: #fff8e6;
      border: 1px solid #f5d77a;
      border-radius: 10px;
      padding: 13px 15px;
      margin-top: 20px;
    }
    .help-tips p { margin: 0 0 9px; font-weight: 700; font-size: 1.2rem; color: #7a5500; }
    .help-tips ul { margin: 0; padding-left: 18px; }
    .help-tips li { font-size: 1.15rem; color: #5a4400; margin-bottom: 9px; line-height: 1.6; }

    .tract-tip {
      border-bottom: 2px dotted #2c7fb8;
      cursor: help;
      color: inherit;
      text-decoration: none;
    }

    .faq-group { margin-bottom: 22px; }
    .faq-group-title {
      font-size: 0.8rem; font-weight: 800; text-transform: uppercase;
      letter-spacing: 0.09em; color: #2c7fb8; margin: 0 0 10px 0;
      padding-bottom: 5px; border-bottom: 2px solid #e8f0f7;
    }
    .faq-item { border: 1px solid #e4edf5; border-radius: 8px; margin-bottom: 8px; overflow: hidden; }
    .faq-question {
      width: 100%; background: #f7fafd; border: none; text-align: left;
      padding: 12px 14px; font-size: 1.05rem; font-weight: 600; color: #2c3e50;
      cursor: pointer; display: flex; justify-content: space-between; align-items: center;
      font-family: sans-serif; line-height: 1.4; transition: background 0.15s;
    }
    .faq-question:hover { background: #eaf4fb; }
    .faq-question.open { background: #eaf4fb; color: #1a5f8a; }
    .faq-chevron { font-size: 0.8rem; transition: transform 0.2s; flex-shrink: 0; margin-left: 8px; color: #2c7fb8; }
    .faq-question.open .faq-chevron { transform: rotate(180deg); }
    .faq-answer {
      display: none; padding: 11px 15px 13px; font-size: 1rem;
      color: #3a4a5c; line-height: 1.65; background: #fff; border-top: 1px solid #e4edf5;
    }
    .faq-answer.open { display: block; }

    .drawer-footer { margin-top: 18px; padding: 0 24px; font-size: 0.88rem; color: #aab; text-align: center; }
  ")),
  
  tags$button(id = "help-toggle", class = "closed", "\U0001f5fa\ufe0f How to Use"),
  
  div(id = "help-drawer", class = "closed",
      
      div(class = "drawer-tab-nav",
          tags$button(class = "drawer-tab-btn active", id = "dtab-howto", onclick = "switchDrawerTab('howto')", "\U0001f5fa\ufe0f How to Use"),
          tags$button(class = "drawer-tab-btn", id = "dtab-faq", onclick = "switchDrawerTab('faq')", "\u2753 FAQ")
      ),
      
      div(id = "drawer-howto", class = "drawer-tab-content active",
          div(id = "drawer-intro", class = "drawer-intro",
              "Select a state and county, then click Search to explore language data by area."),
          div(id = "drawer-steps", class = "help-steps",
              tags$ol(
                tags$li("Select a ", tags$strong("State"), " from the dropdown."),
                tags$li("Then pick a ", tags$strong("County"), " within that state."),
                tags$li("Click the ", tags$strong("Search"), " button to zoom the map into your county."),
                tags$li("Each colored area is shaded by its ", tags$strong("most spoken non-English language"), "."),
                tags$li(
                  tags$strong("Click any colored area"), " to see a pie chart of languages in that ",
                  tags$abbr(class = "tract-tip",
                            title = "A census tract is a small, neighborhood-sized area defined by the Census Bureau \u2014 typically home to 1,200\u20138,000 people.",
                            "census tract"),
                  ", then scroll down to view it."
                )
              )
          ),
          div(class = "help-tips",
              p("\U0001f4a1 Tips"),
              tags$ul(
                tags$li("Use the ", tags$strong("+ and \u2212 buttons"), " on the bottom-left of the map to zoom in and out."),
                tags$li("Counties = large areas like a whole city or region. Tracts = small neighborhoods within a county."),
                tags$li("Language names follow Census labels (e.g. 'Tagalog', not 'Filipino').")
              )
          )
      ),
      
      div(id = "drawer-faq", class = "drawer-tab-content",
          div(class = "faq-group",
              p(class = "faq-group-title", "\U0001f4ca About the Data"),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("Why is English not shown?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "This tool focuses on languages other than English. Since English is spoken nearly everywhere in the US, showing it would drown out the linguistic diversity we're trying to highlight.")
              ),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("How old is this data?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "The data comes from the US Census Bureau's American Community Survey (ACS) and was updated March 2025. The ACS collects responses on a rolling basis, so figures reflect averages over a recent multi-year period rather than a single point in time.")
              ),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("Does \u2018speakers\u2019 mean fluent speakers only?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "Not exactly. The Census asks whether someone speaks a language other than English at home. It captures regular home use \u2014 not fluency level, country of origin, or whether the person also speaks English.")
              )
          ),
          div(class = "faq-group",
              p(class = "faq-group-title", "\U0001f5fa\ufe0f Reading the Map"),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("What\u2019s the difference between a county and a tract?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "A county is a large area \u2014 like Honolulu County or Los Angeles County. A census tract is a much smaller, neighborhood-sized area within a county, typically home to 1,200\u20138,000 people. Tracts give you a finer-grained view of where languages are spoken.")
              ),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("Why are some areas grey?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "Grey means the Census did not record any speakers of the selected language in that area, or the count was too small to be reliably reported.")
              ),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("What does \u2018most spoken language\u2019 mean?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "Each colored area is shaded by whichever non-English language has the highest number of speakers there. It doesn\u2019t mean everyone speaks that language \u2014 just that it\u2019s the most common one in that area. Click any area to see the full breakdown of all languages spoken.")
              )
          ),
          div(class = "faq-group",
              p(class = "faq-group-title", "\U0001f4bb Using the App"),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("Why does scrolling the left panel control the map?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "The map is built as a \u2018scrollytelling\u2019 feature \u2014 scrolling the left panel steps you through the story and zooms the map automatically to your selected county. Scrolling the page itself would just move you away from the map.")
              ),
              div(class = "faq-item",
                  tags$button(class = "faq-question", onclick = "toggleFaq(this)",
                              span("What is the Chat tab \u2014 am I talking to a real person?"), span(class = "faq-chevron", "\u25bc")),
                  div(class = "faq-answer", "No \u2014 it\u2019s an AI assistant connected directly to this dataset. You can ask questions in plain English (e.g. \u2018Which counties in Texas have the most Vietnamese speakers?\u2019) and it will search the data and return a results table. It only reports what\u2019s in the data \u2014 it won\u2019t guess or make things up.")
              )
          )
      ),
      
      div(class = "drawer-footer", "Data: US Census Bureau \u00b7 Updated March 2025")
  ),
  
  tags$script(HTML("
    function toggleDrawer() {
      var drawer = document.getElementById('help-drawer');
      var toggle = document.getElementById('help-toggle');
      drawer.classList.toggle('closed');
      toggle.classList.toggle('closed');
    }
    document.getElementById('help-toggle').addEventListener('click', toggleDrawer);

    function switchDrawerTab(tab) {
      ['howto', 'faq'].forEach(function(t) {
        document.getElementById('drawer-' + t).classList.toggle('active', t === tab);
        document.getElementById('dtab-' + t).classList.toggle('active', t === tab);
      });
    }

    function toggleFaq(btn) {
      var answer = btn.nextElementSibling;
      var isOpen = answer.classList.contains('open');
      btn.closest('.faq-group').querySelectorAll('.faq-answer').forEach(function(a) { a.classList.remove('open'); });
      btn.closest('.faq-group').querySelectorAll('.faq-question').forEach(function(b) { b.classList.remove('open'); });
      if (!isOpen) { answer.classList.add('open'); btn.classList.add('open'); }
    }

    var tabHelp = {
      'Search by Geography': {
        intro: 'Select a state and county, then click Search to explore language data by area.',
        steps: [
          'Select a <strong>State</strong> from the dropdown.',
          'Then pick a <strong>County</strong> within that state.',
          'Click the <strong>Search</strong> button to zoom the map into your county.',
          'Each colored area is shaded by its <strong>most spoken non-English language</strong>.',
          '<strong>Click any colored area</strong> to see a pie chart of languages in that <abbr class=\"tract-tip\" title=\"A census tract is a small, neighborhood-sized area defined by the Census Bureau \u2014 typically home to 1,200\u20138,000 people.\">census tract</abbr>, then scroll down to view it.'
        ],
        toggle: '\U0001f5fa\ufe0f How to Use'
      },
      'Search by Language': {
        intro: 'Pick a language and see everywhere in the US it is spoken, from dense cities to rural areas.',
        steps: [
          'Pick a <strong>language</strong> from the dropdown.',
          'The map shows <strong>every US area</strong> where it is spoken.',
          '<strong>Darker color = higher %</strong> of the population speaks it.',
          'Hover over an area for the percentage; click for the location name.',
          'Scroll down for the <strong>Top 20 Areas</strong> table.'
        ],
        toggle: '\U0001f310 How to Use'
      },
      'Chat with Data': {
        intro: 'Ask any question in plain English and the AI will search the database and return a results table.',
        steps: [
          'Type a question like: <em>&ldquo;Which TX counties have the most Vietnamese speakers?&rdquo;</em>',
          'Or try: <em>&ldquo;Top Spanish-speaking areas in Florida?&rdquo;</em>',
          'The AI writes the query automatically \u2014 no coding needed.',
          'Use <strong>percent speakers</strong> for concentration questions.',
          'Use <strong>total speakers</strong> for raw count questions.'
        ],
        toggle: '\U0001f4ac How to Use'
      }
    };

    function updateDrawer(tabName) {
      var help = tabHelp[tabName] || tabHelp['Search by Geography'];
      document.getElementById('drawer-intro').innerHTML = help.intro;
      document.getElementById('help-toggle').innerHTML = help.toggle;
      var ol = document.createElement('ol');
      help.steps.forEach(function(step) {
        var li = document.createElement('li');
        li.innerHTML = step;
        ol.appendChild(li);
      });
      var stepsDiv = document.getElementById('drawer-steps');
      stepsDiv.innerHTML = '';
      stepsDiv.appendChild(ol);
    }

    document.addEventListener('click', function(e) {
      var link = e.target.closest('.navbar-nav > li > a');
      if (link) updateDrawer(link.textContent.trim());
    });

    document.addEventListener('DOMContentLoaded', function() {
      updateDrawer('Search by Geography');
    });
  "))
)

ui <- tagList(
  help_drawer,
  page_navbar(
    title = div(
      img(src = "SpiceLogo1.png", height = "40px", style = "vertical-align: middle; margin-right: 10px;"),
      span("LanguageFinder", style = "vertical-align: middle; font-weight: bold;")
    ),
    header = tags$head(
      tags$style(HTML("
        .maplibregl-canvas-container,
        .maplibregl-map { z-index: 0 !important; }
        .navbar { z-index: 1100 !important; position: relative; }
        .download-bar { display: flex; justify-content: flex-end; padding: 8px 16px 0 16px; }
      "))
    ),
    
    nav_panel(
      "Search by Geography",
      fluidPage(
        div(class = "download-bar", uiOutput("geo_download_ui")),
        layout_sidebar(
          sidebar = sidebar(
            selectInput("state", "Choose a State:", choices = state_choices_ui, selected = ""),
            uiOutput("county_ui"),
            actionButton("show_county", "Search", class = "btn-primary", width = "100%"),
            div(HTML(
              "<p style='margin-top: 12px;'><strong>Explore languages by place.</strong></p>
               <p>Choose a state, then a county, then click <strong>Search</strong> to zoom in and load tract data. Click a tract for a pie chart of languages in that tract.</p>"
            ))
          ),
          uiOutput("county_heading"),
          maplibreOutput("map", height = "600px"),
          br(),
          fluidRow(
            column(6, h4("Top languages in selected county"), plotOutput("language_plot", height = "400px")),
            column(6, h4("Languages in clicked tract"), plotOutput("pie_chart", height = "400px"))
          )
        )
      )
    ),
    
    nav_panel(
      "Search by Language",
      fluidPage(
        div(class = "download-bar",
            downloadButton("download_language", "Download All Tract Data as CSV",
                           class = "btn-outline-secondary btn-sm", icon = icon("download"))
        ),
        layout_sidebar(
          sidebar = sidebar(
            selectInput("language_choice", "Choose a Language:", choices = available_languages, selected = "Hawaiian"),
            div(HTML(
              "<p><strong>Find out which languages other than English are spoken in particular places.</strong></p>
               <ul><li>Disaster response, healthcare, and environmental justice</li>
               <li>Engagement in local government</li>
               <li>Workplace safety and more</li></ul>
               <p>Explore how speakers of a language are distributed across the U.S.</p>
               <p>Updated March 2025</p>"
            ))
          ),
          uiOutput("language_map_title"),
          maplibreOutput("language_map", height = "600px"),
          br(),
          h3("Top 20 Census Tracts with the Highest Percentage of Speakers"),
          reactableOutput("top_tracts_table")
        )
      )
    ),
    
    nav_panel(
      "AI Assistant",
      layout_sidebar(
        sidebar = qc$sidebar(),
        card(
          card_header(
            div(
              style = "display: flex; justify-content: space-between; align-items: center;",
              span("Query Results"),
              downloadButton("download_qc", "Download as CSV", class = "btn-outline-secondary btn-sm")
            )
          ),
          reactableOutput("qc_table")
        )
      )
    ),
    
    # ── About Panel ──────────────────────────────────────────────────────────
    nav_panel("About",
              fluidPage(
                div(style = "max-width: 860px; margin: 30px auto; padding: 0 20px;",
                    
                    h2("About LanguageFinder",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    p("LanguageFinder is an interactive tool for exploring the linguistic diversity of the United States. Drawing on recent U.S. Census data (American Community Survey, 2024), the app allows users to investigate where different language communities live, down to the county and census-tracts levels. It brings together geographic visualization and an AI-powered assistant to make language data accessible and meaningful for a wide range of users, including researchers, educators, policymakers, and service providers who need rapid access to language data for community outreach and emergency response."),
                    
                    p("LanguageFinder was founded by Dr. Catherine Brockway, who developed the original concept and built the foundation of the app. The project has since grown through successive cohorts of student researchers and faculty collaborators, and is currently being developed as a capstone project for the GIS Certification program in the Data Science, Analytics, and Visualization (DSAV) program at Chaminade University of Honolulu."),
                    
                    p(strong("With LanguageFinder, you can:")),
                    tags$ul(
                      tags$li("Search by location to see the languages spoken in a specific county or census tract"),
                      tags$li("Search by language to find where speakers are concentrated across the U.S."),
                      tags$li("Explore patterns through interactive maps and charts"),
                      tags$li("Query the data conversationally using an AI assistant"),
                      tags$li("Identify communities by language need to support outreach, planning, and emergency response")
                    ),
                    
                    br(),
                    
                    h2("The Team",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    div(style = "display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 10px;",
                        
                        div(style = "background: #f7fafd; border: 1px solid #e4edf5; border-radius: 10px; padding: 16px;",
                            p(strong("Dr. Amber Camp"), style = "margin-bottom: 6px; color: #1a5f8a;"),
                            p(style = "margin: 0; font-size: 0.95rem; color: #3a4a5c;",
                              "Amber is an assistant professor of Data Science, Analytics, and Visualization at Chaminade University of Honolulu, whose research background in linguistics informs the project's attention to how language communities are represented and understood through data. She contributed to the early development of LanguageFinder alongside its founder and has since led the project through its current phase, overseeing student researchers, guiding design and development, and ensuring the integrity of the data and code.")
                        ),
                        
                        div(style = "background: #f7fafd; border: 1px solid #e4edf5; border-radius: 10px; padding: 16px;",
                            p(strong("Connor Flynn"), style = "margin-bottom: 6px; color: #1a5f8a;"),
                            p(style = "margin: 0; font-size: 0.95rem; color: #3a4a5c;",
                              "Connor is a Data Scientist and Adjunct Professor in Data Science at Chaminade University of Honolulu, and co-leads the LanguageFinder project. He primarily focuses on app design, AI implementation, and reproducibility with Github.")
                        ),
                        
                        div(style = "background: #f7fafd; border: 1px solid #e4edf5; border-radius: 10px; padding: 16px;",
                            p(strong("Alex Greb"), style = "margin-bottom: 6px; color: #1a5f8a;"),
                            p(style = "margin: 0; font-size: 0.95rem; color: #3a4a5c;",
                              "Alex is a senior in the Data Science, Analytics, and Visualization program at Chaminade University of Honolulu, where he is also completing the GIS Certification. He plays baseball for the Chaminade Silverswords. Alex has focused on consolidating and unifying code contributions from multiple team members into a cohesive codebase, as well as implementing improvements to several app features at the UI level.")
                        ),
                        
                        div(style = "background: #f7fafd; border: 1px solid #e4edf5; border-radius: 10px; padding: 16px;",
                            p(strong("Jaydon Laboy"), style = "margin-bottom: 6px; color: #1a5f8a;"),
                            p(style = "margin: 0; font-size: 0.95rem; color: #3a4a5c;",
                              "Jaydon contributed to the development of LanguageFinder by improving the app's layout and overall user experience. His work included refining formatting, optimizing the globe view, and ensuring the map loads in an effective position when the app starts.")
                        ),
                        
                        div(style = "background: #f7fafd; border: 1px solid #e4edf5; border-radius: 10px; padding: 16px;",
                            p(strong("Berylin Lau"), style = "margin-bottom: 6px; color: #1a5f8a;"),
                            p(style = "margin: 0; font-size: 0.95rem; color: #3a4a5c;",
                              "Berylin designed and built the Help system for LanguageFinder, including the sliding Help drawer, the \u201cHow to Use\u201d and \u201cFAQ\u201d tab interface, and all written content within them, step-by-step instructions, accordion FAQ sections, and context-aware text that updates depending on which tab you're viewing. Also contributed to the AI Assistant tab, helping set up the Querychat connection.")
                        ),
                        
                        div(style = "background: #f7fafd; border: 1px solid #e4edf5; border-radius: 10px; padding: 16px;",
                            p(strong("Ashley Holen"), style = "margin-bottom: 6px; color: #1a5f8a;"),
                            p(style = "margin: 0; font-size: 0.95rem; color: #3a4a5c;",
                              "Ashley implemented Querychat AI Assistant, conducted data validation and processing, designed user interface, built the data download capabilities for users, and assisted with the overall vision and direction of the application.")
                        )
                    ),
                    
                    br(),
                    
                    h2("Previous Collaborators",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    p("LanguageFinder has benefited from the contributions of students and collaborators across multiple project cycles:"),
                    tags$ul(
                      tags$li(strong("Dr. Catherine Brockway"), " - App Founder"),
                      tags$li("Lydia Hefel"),
                      tags$li("Logan Lasell")
                    ),
                    
                    br(),
                    
                    h2("Presentations",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    tags$ul(
                      tags$li("Holen, A., Greb, A., Laboy, J. & Lau, B. LanguageFinder 3.0. N\u0101 Liko Na\u02bbauao Student Research Symposium. Honolulu, HI. April 22, 2026. (talk)"),
                      tags$li("Hefel, L. & Lasell, L. LanguageFinder. N\u0101 Liko Na\u02bbauao Student Research Symposium. Honolulu, HI. April 16, 2025. (talk)"),
                      tags$li("Brockway, C., Camp, A. B. & Flynn, C. LanguageFinder for Languages in Diaspora: Mapping Communities and Estimated Speaker Numbers Across the United States. 9th International Conference on Language Documentation and Conservation. Honolulu, HI. March 8, 2025. (talk)")
                    ),
                    
                    br(),
                    
                    h2("Funding",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    p("LanguageFinder is supported by Chaminade University of Honolulu through the Data Science, Analytics, and Visualization program and its GIS Certification initiative. The project was previously funded by the NSF INCLUDES Alliance: Alliance Supporting Pacific Impact through Computational Excellence (ALL-SPICE), Award No. 2217242."),
                    
                    br(),
                    
                    h2("Data & Software",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    p("U.S. Census Bureau. (2024). American Community Survey custom tabulation: Language spoken at home [Custom data file]. U.S. Department of Commerce. https://data.census.gov"),
                    
                    p(strong("Software citations:")),
                    tags$ul(
                      tags$li("R Core Team (2025). ", em("R: A Language and Environment for Statistical Computing."), " R Foundation for Statistical Computing, Vienna, Austria. https://www.R-project.org/"),
                      tags$li("Chang W, Cheng J, Allaire J, Sievert C, Schloerke B, Xie Y, Allen J, McPherson J, Dipert A, Borges B (2025). ", em("shiny: Web Application Framework for R."), " R package version 1.11.1. https://CRAN.R-project.org/package=shiny. doi:10.32614/CRAN.package.shiny"),
                      tags$li("Walker K (2025). ", em("mapgl: Interactive Maps with \u2018Mapbox GL JS\u2019 and \u2018MapLibre GL JS\u2019."), " R package version 0.4.0. https://CRAN.R-project.org/package=mapgl. doi:10.32614/CRAN.package.mapgl"),
                      tags$li("Aden-Buie G, Cheng J, Sievert C (2026). ", em("querychat: Filter and Query Data Frames in \u2018shiny\u2019 Using an LLM Chat Interface."), " R package version 0.2.0. https://CRAN.R-project.org/package=querychat. doi:10.32614/CRAN.package.querychat"),
                      tags$li("Wickham H, Averick M, Bryan J, et al. (2019). \u201cWelcome to the tidyverse.\u201d ", em("Journal of Open Source Software,"), " 4(43), 1686. doi:10.21105/joss.01686")
                    ),
                    
                    br(),
                    
                    h2("Citation",
                       style = "color: #2c7fb8; border-bottom: 2px solid #e8f0f7; padding-bottom: 8px;"),
                    
                    p("This citation reflects contributors to the current version. Previous versions and their contributors are documented in the project's version history."),
                    p("Holen, A., Greb, A., Laboy, J., Lau, B., Flynn, C. & Camp, A. (2026). LanguageFinder (Version 3.0). Chaminade University of Honolulu. [tbd url]")
                )
              )
    )
  )
)

server <- function(input, output, session) {
  # QueryChat server
  qc_vals <- qc$server()
  
  output$qc_table <- renderReactable({
    reactable(qc_vals$df(), defaultPageSize = 20, highlight = TRUE, bordered = TRUE, striped = TRUE)
  })
  
  # Dynamic language map title
  output$language_map_title <- renderUI({
    h3(paste("Map of Locations where", input$language_choice, "is Spoken"))
  })
  
  # ---- Geography tab ----
  active_county <- reactiveVal(NULL)
  clicked_tract <- reactiveVal(NULL)
  
  observeEvent(input$state, { active_county(NULL); clicked_tract(NULL) }, ignoreNULL = TRUE)
  observeEvent(input$county, { active_county(NULL); clicked_tract(NULL) }, ignoreNULL = TRUE)
  
  output$county_ui <- renderUI({
    if (is.null(input$state) || !nzchar(input$state)) {
      return(selectInput("county", "Choose a County:", choices = c("Select a state first" = ""), selected = ""))
    }
    counties_in_state <- tract_data %>%
      filter(state_name == input$state) %>%
      distinct(county_label) %>%
      arrange(county_label)
    selectInput("county", "Choose a County:", choices = c("Select a county..." = "", counties_in_state$county_label), selected = "")
  })
  
  geo_selection_complete <- reactive({
    !is.null(input$state) && nzchar(input$state) &&
      !is.null(input$county) && nzchar(input$county)
  })
  
  observeEvent(input$show_county, {
    if (!geo_selection_complete()) {
      showNotification("Select a state and county, then click Search.", type = "warning")
      return()
    }
    active_county(input$county)
    clicked_tract(NULL)
  })
  
  output$geo_download_ui <- renderUI({
    req(active_county())
    downloadButton("download_geo", "Download County Data as CSV",
                   class = "btn-outline-secondary btn-sm", icon = icon("download"))
  })
  
  sel_tracts <- reactive({
    req(active_county())
    tract_data %>%
      filter(county_label == active_county(), language != "Total", !is.na(language)) %>%
      group_by(GEOID) %>%
      slice_max(speakers, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      st_set_geometry("geom")
  })
  
  #ADDED TO TRY AND FIX LOUISIANA
  all_county_languages <- reactive({
    req(active_county())
    tract_data %>%
      filter(
        county_label == active_county(),
        language != "Total",
        !is.na(language)
      ) %>%
      st_drop_geometry()
  })
  
  observeEvent(input$map_click, {
    req(input$map_click$lng, input$map_click$lat, active_county())
    sel <- sel_tracts()
    sel <- sel[!st_is_empty(sel), ]
    req(nrow(sel) > 0)
    click_pt <- st_sfc(st_point(c(input$map_click$lng, input$map_click$lat)), crs = st_crs(tract_data))
    clicked_tract(sel$GEOID[st_nearest_feature(click_pt, sel)])
  })
  
  clicked_languages <- reactive({
    req(clicked_tract())
    tract_data %>%
      filter(GEOID == clicked_tract(), language != "Total", !is.na(language)) %>%
      mutate(percentage = round(speakers / sum(speakers) * 100, 1))
  })
  
  output$map <- renderMaplibre({
    base <- maplibre(carto_style("positron"), center = c(-98.5795, 39.8283), zoom = 3, scrollZoom = FALSE)
    if (is.null(active_county())) return(base)
    
    selected <- sel_tracts() %>% filter(!is.na(language))
    if (nrow(selected) == 0) return(base |> fit_bounds(county_data, animate = FALSE))
    
    selected <- selected %>%
      mutate(language = as.factor(language), lang_id = as.numeric(language))
    
    lang_vals <- levels(selected$language)
    if (!is.character(lang_vals) || length(lang_vals) == 0)
      return(base |> fit_bounds(county_data, animate = FALSE))
    
    lang_colors <- viridisLite::turbo(length(lang_vals))
    
    maplibre(carto_style("positron"), scrollZoom = FALSE) |>
      add_navigation_control(position = "bottom-left", show_compass = FALSE) |>
      add_fill_layer(
        id = "tracts", source = selected,
        fill_color = interpolate(column = "lang_id", values = seq_along(lang_vals),
                                 stops = lang_colors, na_color = "lightgrey"),
        fill_opacity = 0.8
      ) |>
      add_line_layer(id = "tract_borders", source = selected, line_color = "#ffffff", line_width = 1) |>
      add_categorical_legend(legend_title = "Most Spoken Language",
                             values = lang_vals, colors = lang_colors, position = "bottom-right") |>
      fit_bounds(selected, animate = FALSE)
  })
  
  output$county_heading <- renderUI({
    if (is.null(active_county())) return(h3("Select a state and county, then click Search"))
    h3(active_county())
  })
  
  output$language_plot <- renderPlot({
    validate(need(!is.null(active_county()), "Select a state and county, then click Search to see top languages in that county."))
    all_county_languages() %>%
      group_by(language) %>%
      summarise(speakers = sum(speakers, na.rm = TRUE), .groups = "drop") %>%
      arrange(desc(speakers)) %>%
      slice_head(n = 15) %>%
      ggplot(aes(x = reorder(language, speakers), y = speakers)) +
      geom_col(fill = "#3182bd") +
      coord_flip() +
      labs(x = NULL, y = "Speakers", title = paste("Top Languages in", active_county())) +
      theme_minimal(base_size = 14)
  })
  
  output$pie_chart <- renderPlot({
    validate(
      need(!is.null(active_county()), "Select a state and county, then click Search to enable tract details."),
      need(clicked_tract(), "Click a tract on the map above to see the language mix for that tract.")
    )
    tract_name <- tract_data %>% filter(GEOID == clicked_tract()) %>% pull(geoname) %>% unique()
    ggplot(clicked_languages(), aes(x = "", y = percentage, fill = language)) +
      geom_col(width = 1, color = "white") +
      coord_polar(theta = "y") +
      geom_text(aes(label = paste0(language, "\n", percentage, "%")),
                position = position_stack(vjust = 0.5), size = 2.5) +
      theme_void() +
      scale_fill_viridis_d() +
      labs(title = tract_name, fill = "Language")
  })
  
  # ---- Language Search tab ----
  selected_data <- reactive({
    tract_filtered <- tract_data %>%
      filter(language == input$language_choice) %>%
      mutate(tooltip_label = paste0(round(percent_speakers, 2), "% speak this language"))
    county_filtered <- county_data %>%
      filter(language == input$language_choice) %>%
      mutate(tooltip_label = paste0(round(percent_speakers, 2), "% speak this language"))
    list(tract = tract_filtered, county = county_filtered)
  })
  
  output$language_map <- renderMaplibre({
    data <- selected_data()
    maplibre(style = carto_style("positron"), center = c(-98.5795, 39.8283), zoom = 3, scrollZoom = FALSE) |>
      set_projection("globe") |>
      add_navigation_control(position = "bottom-left", show_compass = FALSE) |>
      # County layer first (bottom) — shows when zoomed out
      add_fill_layer(
        id = "county-fill-layer", source = data$county,
        fill_color = interpolate(column = "percent_speakers", type = "linear",
                                 values = c(0, 0.5, 1, 2, 5, 10, 20, 30, 50),
                                 stops = rev(mako(9)), na_color = "lightgrey"),
        fill_opacity = 0.7, max_zoom = 7.99,
        tooltip = "tooltip_label", popup = "geoname"
      ) |>
      # Tract layer second (top) — shows when zoomed in
      add_fill_layer(
        id = "fill-layer", source = data$tract,
        fill_color = interpolate(column = "percent_speakers", type = "linear",
                                 values = c(0, 0.5, 1, 2, 5, 10, 20, 30, 50),
                                 stops = rev(mako(9)), na_color = "lightgrey"),
        fill_opacity = 0.7, min_zoom = 8,
        tooltip = "tooltip_label", popup = "geoname"
      ) |>
      add_continuous_legend("Percent of Population Speaking Language",
                            values = c(0, 0.5, 1, 2, 5, 10, 20, 30, 50),
                            colors = rev(mako(9)), width = "250px")
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
        highlight = TRUE, bordered = TRUE, striped = TRUE
      )
  })
  
  output$download_geo <- downloadHandler(
    filename = function() paste0("languages_", gsub("[^A-Za-z0-9]", "_", active_county()), ".csv"),
    content = function(file) {
      req(active_county())
      tract_data %>%
        filter(county_label == active_county(), language != "Total", !is.na(language)) %>%
        st_drop_geometry() %>%
        select(GEOID, geoname, language, speakers, percent_speakers, county_label, state_name) %>%
        write.csv(file, row.names = FALSE)
    }
  )
  
  output$download_language <- downloadHandler(
    filename = function() paste0("all_tracts_", gsub("[^A-Za-z0-9]", "_", input$language_choice), ".csv"),
    content = function(file) {
      selected_data()$tract %>%
        st_drop_geometry() %>%
        select(geoname, speakers, percent_speakers) %>%
        arrange(desc(percent_speakers)) %>%
        write.csv(file, row.names = FALSE)
    }
  )
  
  output$download_qc <- downloadHandler(
    filename = function() paste0("query_results_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv"),
    content = function(file) write.csv(qc_vals$df(), file, row.names = FALSE)
  )
}

shinyApp(ui, server)