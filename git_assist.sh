#!/bin/bash

set -e

# ---------- Color Setup ----------
BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# ---------- Logging -------------
LOG_FILE="git-assist.log"
touch "$LOG_FILE"

log() { echo "$1" | tee -a "$LOG_FILE"; }
highlight() { echo "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"; }
success() { echo "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"; }
warn() { echo "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"; }
error() { echo "${RED}$1${RESET}" | tee -a "$LOG_FILE"; }

# ---------- Feature Menu ----------
highlight "🎛️  Git Assistant Menu"
echo "Choose steps to run (e.g. 1 2 4):"
echo "  1) 🔧 Run 'mvn clean install'"
echo "  2) 🔎 Run 'snyk test' and generate report"
echo "  3) 📝 Stage and commit git changes"
echo "  4) 🚀 Push to remote with branch protection"
read -p "${YELLOW}Enter your selection: ${RESET}" user_choice

run_mvn=false
run_snyk=false
do_git_commit=false
do_push=false

for option in $user_choice; do
  case $option in
    1) run_mvn=true ;;
    2) run_snyk=true ;;
    3) do_git_commit=true ;;
    4) do_push=true ;;
    *) warn "⚠️ Unknown option: $option" ;;
  esac
done

# ---------- Step 1: mvn clean install ----------
if $run_mvn; then
  highlight "🔧 Running mvn clean install..."
  if mvn clean install | tee -a "$LOG_FILE"; then
    success "✅ Maven build successful"
  else
    error "❌ Maven build failed. Exiting."
    exit 1
  fi
fi

# ---------- Step 2: snyk test ----------
if $run_snyk; then
  highlight "🔍 Running snyk test..."
  snyk_report_file="snyk-vuln-report.json"
  markdown_report_file="snyk-report.md"

  if snyk test --json > "$snyk_report_file"; then
    success "✅ Snyk test completed"
  else
    warn "⚠️ Snyk reported vulnerabilities. Parsing report..."
  fi

  if ! command -v jq &>/dev/null; then
    error "❌ 'jq' is required for parsing Snyk output. Install it and retry."
    exit 1
  fi

  critical_count=$(jq '[.vulnerabilities[] | select(.severity == "critical")] | length' "$snyk_report_file")
  high_count=$(jq '[.vulnerabilities[] | select(.severity == "high")] | length' "$snyk_report_file")

  highlight "🛡️ Vulnerability Summary:"
  echo "Critical: $critical_count"
  echo "High: $high_count"

  echo "# Snyk Vulnerability Report" > "$markdown_report_file"
  echo "| Severity | Package | Current Version | Affected Versions | Title |" >> "$markdown_report_file"
  echo "|----------|---------|------------------|--------------------|-------|" >> "$markdown_report_file"
  jq -r '.vulnerabilities[] | "| \(.severity | ascii_upcase) | \(.packageName) | \(.version) | \(.vulnerableVersions) | \(.title) |"' "$snyk_report_file" \
    | tee -a "$markdown_report_file"

  if [[ "$critical_count" -gt 0 ]]; then
    error "🚨 Critical vulnerabilities found. Aborting process."
    exit 1
  elif [[ "$high_count" -gt 0 ]]; then
    warn "⚠️ High severity vulnerabilities found."
    read -p "${YELLOW}Proceed anyway? (y/n): ${RESET}" allow_high
    [[ "$allow_high" != "y" ]] && error "⛔ Aborted due to high severity vulnerabilities." && exit 1
  fi

  success "✅ Snyk vulnerability report saved to $markdown_report_file"
fi

# ---------- Step 3: Git stage and commit ----------
if $do_git_commit; then
  highlight "📁 Checking for changes..."
  git status | tee -a "$LOG_FILE"
  changed_items=$(git status --porcelain | awk '{print $2}')
  files_to_add=()

  if [[ -z "$changed_items" ]]; then
    success "✅ No changes to commit"
    exit 0
  fi

  highlight "📦 Found changed files:"
  for item in $changed_items; do
    if [[ -d "$item" ]]; then
      subfiles=$(find "$item" -type f)
      for subfile in $subfiles; do
        read -p "${YELLOW}Add '$subfile'? (y/n): ${RESET}" confirm
        [[ "$confirm" == "y" ]] && files_to_add+=("$subfile")
      done
    else
      read -p "${YELLOW}Add '$item'? (y/n): ${RESET}" confirm
      [[ "$confirm" == "y" ]] && files_to_add+=("$item")
    fi
  done

  if [ ${#files_to_add[@]} -eq 0 ]; then
    error "🚫 No files selected. Aborting commit."
    exit 1
  fi

  git add "${files_to_add[@]}"
  success "✅ Files staged"

  current_branch=$(git rev-parse --abbrev-ref HEAD)
  jira_ticket=$(echo "$current_branch" | grep -Eo 'FINDATA-[0-9]+' || true)

  if [[ -z "$jira_ticket" ]]; then
    read -p "${YELLOW}Enter Jira ticket (FINDATA-###): ${RESET}" jira_ticket
    while [[ ! "$jira_ticket" =~ ^FINDATA-[0-9]+$ ]]; do
      error "❌ Invalid format. Must be like FINDATA-123"
      read -p "${YELLOW}Try again: ${RESET}" jira_ticket
    done
  fi

  tmpfile=$(mktemp /tmp/gitmsg.XXXXXX)
  ${EDITOR:-nano} "$tmpfile"
  commit_body=$(<"$tmpfile")
  rm "$tmpfile"

  [[ -z "$commit_body" ]] && error "❌ Empty commit message. Aborting." && exit 1

  full_commit="${jira_ticket}: ${commit_body}"
  echo "🧾 Commit message: $full_commit"
  read -p "${YELLOW}Commit changes? (y/n): ${RESET}" confirm_commit
  [[ "$confirm_commit" == "y" ]] && git commit -m "$full_commit" && success "✅ Commit done"
fi

# ---------- Step 4: Push ----------
if $do_push; then
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" =~ ^(main|develop|dev)$ ]]; then
    warn "⚠️ You are on a protected branch: $current_branch"
    read -p "${YELLOW}Do you really want to push to '$current_branch'? (y/n): ${RESET}" push_protected
    if [[ "$push_protected" != "y" ]]; then
      error "⛔ Push cancelled"
      git reset --soft HEAD~1
      read -p "${YELLOW}Create new feature branch? (y/n): ${RESET}" create_branch
      if [[ "$create_branch" == "y" ]]; then
        read -p "${YELLOW}New branch name: ${RESET}" new_branch
        git checkout -b "$new_branch"
        success "✅ Switched to new branch: $new_branch"
      fi
      exit 1
    fi
  fi

  highlight "🚀 Pushing to origin/$current_branch..."
  git push -u origin "$current_branch"
  success "✅ Push complete"
fi

highlight "🎉 Git Assistant finished at $(date)"
