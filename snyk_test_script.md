Certainly! To add a **Snyk test** to your Git assistant script and prompt the user if there are any **high/critical vulnerabilities**, I've incorporated the following changes:

1. **Snyk Test**: We will run a `snyk test -d` command to test for vulnerabilities.
2. **Vulnerability Reporting**: Only report the **vulnerability name**, **package**, and whether it's **fixable**.
3. **Prompt for High/Critical Vulnerabilities**: If there are any **high/critical vulnerabilities**, the script will prompt the user for confirmation to proceed.

Here’s how your **Git Assistant** script would look with the **Snyk Test** integration:

### Updated Git Assistant Script:

```bash
#!/bin/bash

# Function to run Snyk test and report vulnerabilities
run_snyk_test() {
    echo -e "\n🔍 Step 0: Run Snyk Test for Vulnerabilities..."

    # Run Snyk test to get detailed results
    snyk_test_output=$(snyk test -d --json)

    # Check if Snyk is available
    if [[ $? -ne 0 ]]; then
        echo "❌ Snyk is not installed or there was an error during the test. Exiting."
        exit 1
    fi

    # Extract vulnerabilities using jq (ensure you have jq installed)
    vulnerabilities=$(echo "$snyk_test_output" | jq -r '.vulnerabilities[] | "\(.package.name) - \(.title) - \(.severity) - Fixable: \(.fixAvailable)"')

    # Report vulnerabilities
    echo -e "✅ Snyk Test Completed. Vulnerabilities found:\n"
    echo "$vulnerabilities"

    # Check if there are any high or critical vulnerabilities
    high_critical_vulnerabilities=$(echo "$snyk_test_output" | jq -r '.vulnerabilities[] | select(.severity == "high" or .severity == "critical")')

    if [[ -n "$high_critical_vulnerabilities" ]]; then
        echo -e "\n⚠️ High/Critical vulnerabilities detected!"
        echo "$high_critical_vulnerabilities"
        read -p "Do you want to proceed with the git operations? (y/n): " proceed_with_git
        if [[ "$proceed_with_git" != "y" ]]; then
            echo "❌ Aborting git operations due to high/critical vulnerabilities."
            exit 1
        fi
    else
        echo -e "✅ No high/critical vulnerabilities found. Proceeding with Git operations."
    fi
}

# Function to display prompt and exit if user cancels
confirm_action() {
  read -p "$1 (y/n): " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo "❌ Aborting operation."
    exit 1
  fi
}

# Function to check if config.txt exists and prompt for creation
check_and_create_config() {
  if [[ ! -f /etc/secrets/config.txt ]]; then
    echo -e "❌ Config file not found: /etc/secrets/config.txt"
    read -p "Do you want to create the config.txt file? (y/n): " create_config
    if [[ "$create_config" == "y" ]]; then
      # Create and open the config.txt file in vim editor
      echo "Opening vim to create and edit /etc/secrets/config.txt..."
      sudo touch /etc/secrets/config.txt
      sudo vim /etc/secrets/config.txt
      echo "✅ File created and saved. Proceeding with the rest of the steps."
    else
      echo "❌ Config file not created. Exiting."
      exit 1
    fi
  else
    echo "✅ Config file found at /etc/secrets/config.txt."
  fi
}

# Prompt to load JAVA_OPTS from config.txt
echo -e "\n🚀 Step 1: Load JAVA_OPTS from /etc/secrets/config.txt?"
read -p "Do you want to load JAVA_OPTS? (y/n): " load_java_opts

if [[ "$load_java_opts" == "y" ]]; then
  check_and_create_config  # Check if config.txt exists and prompt to create if not
  
  export JAVA_OPTS=$(tr '\n' ' ' < /etc/secrets/config.txt)
  echo "✅ JAVA_OPTS loaded: $JAVA_OPTS"
else
  echo "❌ Required step skipped: JAVA_OPTS not loaded. Exiting."
  exit 1
fi

# Run Snyk Test for vulnerabilities
run_snyk_test

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
```

### Key Additions:

1. **Snyk Test Integration**:
    - The function `run_snyk_test` runs `snyk test -d --json` to get detailed vulnerability data.
    - It then parses the output using `jq` to extract and display relevant details about each vulnerability: package name, vulnerability title, severity, and whether it’s fixable.

2. **High/Critical Vulnerabilities Prompt**:
    - If there are any vulnerabilities marked as **high** or **critical**, the script will display them and prompt you with the option to continue or cancel the process. If you choose "No", the script will exit.

3. **Snyk Test Reporting**:
    - The script reports vulnerabilities in a clear and concise format with only the package name, vulnerability title, and whether a fix is available. It lists these for your review.
    - If no high/critical vulnerabilities are found, it confirms that and continues with the Git operations.

---

### How It Works:

1. **Snyk Test**: When the script starts, it runs the `snyk test -d --json` command to perform a deep vulnerability test of your project.
2. **Vulnerability Report**: It filters and outputs only the important information, i.e., the package name, the vulnerability title, severity, and whether it is fixable.
3. **Prompt for High/Critical Vulnerabilities**: If any vulnerabilities are marked as high or critical, the script will ask for confirmation to proceed. If you choose not to proceed, the script will exit.
4. **Proceed with Git Operations**: If no critical issues are present (or if you choose to proceed despite them), the script will continue with the normal Git assistant workflow, such as loading the `JAVA_OPTS`, running the Maven build, and executing the application.

---

### How to Use:

1. **Ensure Snyk is Installed**:
   You need to have **Snyk** installed on your machine for this feature to work. If you haven't already installed it, you can do so by running:
   ```bash
   npm install -g snyk
   ```

2. **Save the Script**: Save the script as `git_assistant_with_snyk.sh`.

3. **Make it Executable**:
   ```bash
   chmod +x git_assistant_with_snyk.sh
   ```

4. **Run the Script**:
   ```bash
   ./git_assistant_with_snyk.sh
   ```

5. **Follow the Prompts**:
   - The script will first run the **Snyk Test** and report vulnerabilities.
   - If high/critical vulnerabilities are found, you'll be asked whether to proceed with the rest of the operations.
   - If you choose to continue, it will proceed with the Maven build, Git operations, and running the application as per the original assistant.

This added Snyk test makes your Git assistant more robust by ensuring you check for security vulnerabilities before proceeding with code changes and deployments.