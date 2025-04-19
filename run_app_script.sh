#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function to check if config.txt exists and prompt for creation
check_and_create_config() {
  if [[ ! -f config.txt ]]; then
    echo -e "❌ Config file not found: config.txt"
    read -p "Do you want to create the config.txt file? (y/n): " create_config
    if [[ "$create_config" == "y" ]]; then
      # Create and open the config.txt file in vim editor
      echo "Opening vim to create and edit config.txt..."
      sudo touch config.txt
      sudo vim config.txt
      echo "✅ File created and saved. Proceeding with the rest of the steps."
    else
      echo "❌ Config file not created. Exiting."
      exit 1
    fi
  else
    echo "✅ Config file found at config.txt."
  fi
}

# Prompt to load JAVA_OPTS from config.txt
echo -e "\n🚀 Step 1: Load JAVA_OPTS from config.txt?"
read -p "Do you want to load JAVA_OPTS? (y/n): " load_java_opts

if [[ "$load_java_opts" == "y" ]]; then
  check_and_create_config  # Check if config.txt exists and prompt to create if not
  
  export JAVA_OPTS=$(tr '\n' ' ' < config.txt)
  echo "✅ JAVA_OPTS loaded: $JAVA_OPTS"
else
  echo "❌ Required step skipped: JAVA_OPTS not loaded. Exiting."
  exit 1
fi

# Step 2: Run Maven build
echo -e "\n🛠️ Step 2: Run 'mvn clean install'?"
read -p "Do you want to build the project? (y/n): " build_project

if [[ "$build_project" == "y" ]]; then
  echo "📦 Running Maven build..."
  mvn clean install
  echo -e "✅ Maven build successful."
else
  echo "❌ Required step skipped: Maven build not run. Exiting."
  exit 1
fi

# Step 3: Find the latest JAR in target/
echo -e "\n🔍 Step 3: Searching for the latest JAR in target/..."
JAR_FILE=$(find target -type f -name "*.jar" -print0 | xargs -0 ls -t | head -n 1)

if [[ -z "$JAR_FILE" ]]; then
  echo -e "❌ No JAR file found in target/. Exiting."
  exit 1
fi
echo "✅ Found JAR: $JAR_FILE"

# Step 4: Run the application
echo -e "\n🏃‍♂️ Step 4: Run the application?"
read -p "Do you want to run the application? (y/n): " run_app

if [[ "$run_app" == "y" ]]; then
  echo "🚀 Running the application..."
  java $JAVA_OPTS -jar "$JAR_FILE"
else
  echo "❌ Required step skipped: Application not run. Exiting."
  exit 1
fi
