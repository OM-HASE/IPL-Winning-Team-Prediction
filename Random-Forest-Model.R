library(shiny)
library(randomForest)
library(caret)
library(dplyr)
library(ggplot2)
library(stringr)

# Load datasets (update file paths accordingly)
matches <- read.csv("C:/Users/omhas/Documents/IPL Project/Dataset/matches.csv")
deliveries <- read.csv("C:/Users/omhas/Documents/IPL Project/Dataset/deliveries.csv")

# Data processing and feature engineering
inning_score<- deliveries %>% group_by(match_id, inning) %>% summarise(total_runs = sum(total_runs),.groups = 'drop') %>% filter(inning == 1)
inning_score <- inning_score %>% mutate(target = total_runs + 1)

# Rename columns for joining
colnames(matches)[colnames(matches) == "ID"] <- "id"
colnames(inning_score)[colnames(inning_score) == "match_id"] <- "id"
matches <- matches %>%
  left_join(inning_score %>% select(id, target), by = "id")

# Update old team names to new ones
matches$team1 <- gsub('Delhi Daredevils', 'Delhi Capitals', matches$team1)
matches$team2 <- gsub('Delhi Daredevils', 'Delhi Capitals', matches$team2)
matches$winner <- gsub('Delhi Daredevils', 'Delhi Capitals', matches$winner)
matches$team1 <- gsub('Kings XI Punjab', 'Punjab Kings', matches$team1)
matches$team2 <- gsub('Kings XI Punjab', 'Punjab Kings', matches$team2)
matches$winner <- gsub('Kings XI Punjab', 'Punjab Kings', matches$winner)
matches$team1 <- gsub('Deccan Chargers', 'Sunrisers Hyderabad', matches$team1)
matches$team2 <- gsub('Deccan Chargers', 'Sunrisers Hyderabad', matches$team2)
matches$winner <- gsub('Deccan Chargers', 'Sunrisers Hyderabad', matches$winner)

# Filter for relevant teams (2024 IPL teams)
teams2024 <- c(
  'Rajasthan Royals', 'Royal Challengers Bangalore', 'Sunrisers Hyderabad', 
  'Delhi Capitals', 'Chennai Super Kings', 'Gujarat Titans', 
  'Lucknow Super Giants', 'Kolkata Knight Riders', 'Punjab Kings', 'Mumbai Indians'
)

matches <- matches %>%
  filter(team1 %in% teams2024) %>%
  filter(team2 %in% teams2024) %>%
  filter(winner %in% teams2024)

matches <- matches %>%
  select(id, city, team1, team2, winner, target) %>%
  na.omit()

# Filter deliveries dataset for the same teams
deliveries <- deliveries %>%
  filter(batting_team %in% teams2024)

# Merge datasets for second innings prediction
final <- matches %>%
  inner_join(deliveries, by = "id") %>%
  filter(inning == 2)

final$current_score <- ave(final$total_runs, final$id, FUN = cumsum)
final$runs_left <- ifelse(final$target - final$current_score >= 0, final$target - final$current_score, 0)
final$balls_left <- ifelse(120 - final$over * 6 - final$ball >= 0, 120 - final$over * 6 - final$ball, 0)
final <- final %>%
  group_by(id) %>%
  mutate(wickets_left = 10 - cumsum(is_wicket)) %>%
  ungroup()

final$current_run_rate <- (final$current_score * 6) / (120 - final$balls_left)
final$required_run_rate <- ifelse(final$balls_left > 0, final$runs_left * 6 / final$balls_left, 0)

# Add result column for match outcome
final$result <- ifelse(final$batting_team == final$winner, 1, 0)

# Prepare training data
winningPred <- final %>%
  select(BattingTeam = batting_team, BowlingTeam = bowling_team, city, runs_left, balls_left, 
         wickets_left, current_run_rate, required_run_rate, target, result)

# Convert categorical variables into dummy variables
trf <- dummyVars(result ~ BattingTeam + BowlingTeam + city, data = winningPred, fullRank = TRUE)
X <- predict(trf, newdata = winningPred)
y <- winningPred$result

# Split data into training and testing sets
train_indices <- createDataPartition(y, p = 0.8, list = FALSE)
X_train <- X[train_indices, ]
X_test <- X[-train_indices, ]
y_train <- y[train_indices]
y_test <- y[-train_indices]

# Train the Random Forest model
rf_model <- randomForest(x = X_train, y = as.factor(y_train), ntree = 200, mtry = sqrt(ncol(X_train)))

# Define UI for the Shiny App
ui <- fluidPage(
  titlePanel("IPL Match Winning Prediction"),
  sidebarLayout(
    sidebarPanel(
      selectInput("batting_team", "Batting Team:", choices = teams2024),
      selectInput("bowling_team", "Bowling Team:", choices = teams2024),
      textInput("city", "City:"),
      numericInput("runs_left", "Runs Left:", value = 0, min = 0),
      numericInput("balls_left", "Balls Left:", value = 0, min = 0),
      numericInput("wickets_left", "Wickets Left:", value = 0, min = 0),
      numericInput("current_run_rate", "Current Run Rate:", value = 0, min = 0),
      numericInput("required_run_rate", "Required Run Rate:", value = 0, min = 0),
      numericInput("target", "Target:", value = 0, min = 0),
      actionButton("predict", "Predict")
    ),
    mainPanel(
      h3("Winning Probability"),
      textOutput("result")
    )
  )
)

# Define server logic
server <- function(input, output) {
  observeEvent(input$predict, {
    new_data <- data.frame(
      BattingTeam = input$batting_team,
      BowlingTeam = input$bowling_team,
      city = input$city,
      runs_left = input$runs_left,
      balls_left = input$balls_left,
      wickets_left = input$wickets_left,
      current_run_rate = input$current_run_rate,
      required_run_rate = input$required_run_rate,
      target = input$target
    )
    
    # Convert the new data into the same format as training data
    new_data_transformed <- predict(trf, newdata = new_data)
    
    # Predict the outcome
    prediction <- predict(rf_model, newdata = as.data.frame(new_data_transformed))
    
    output$result <- renderText({
      if (prediction == 1) {
        paste("Prediction: Batting Team", input$batting_team, "is more likely to win.")
      } else {
        paste("Prediction: Bowling Team", input$bowling_team, "is more likely to win.")
      }
    })
  })
}

# Run the application 
shinyApp(ui = ui, server = server)


