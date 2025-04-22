#!/bin/bash

set -e

# ---------- Color Setup ----------
BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# ---------- Setup Folder ------------
REPORT_DIR="gitassist"
mkdir -p "$REPORT_DIR"

# ---------- Logging -------------
LOG_FILE="$REPORT_DIR/git-assist.log"
touch "$LOG_FILE"

log() { echo "$1" | tee -a "$LOG_FILE"; }
highlight() { echo "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"; }
success() { echo "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"; }
warn() { echo "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"; }
error() { echo "${RED}$1${RESET}" | tee -a "$LOG_FILE"; }

# ---------- Function Definitions ---------

run_mvn_clean_install() {
  highlight "🔧 Running mvn clean install..."
  if mvn clean install | tee -a "$LOG_FILE"; then
    success "✅ Maven build successful"
  else
    error "❌ Maven build failed."
    return 1
  fi
}

run_snyk_test() {
  highlight "⚠️⚠️⚠️⚠️⚠️The Snyk Report you are getting from here does not cover the shaded or unmanaged dependencies⚠️⚠️⚠️⚠️⚠️"
  highlight "🔍 Running snyk test..."
  snyk_report_file="$REPORT_DIR/snyk-vuln-report.json"
  markdown_report_file="$REPORT_DIR/snyk-report.md"

  if snyk test --json > "$snyk_report_file"; then
    success "✅ Snyk test completed"
  else
    warn "⚠️ Snyk reported vulnerabilities. Parsing report..."
  fi

  if ! command -v jq &>/dev/null; then
    error "❌ 'jq' is required for parsing Snyk output. Install it and retry."
    return 1
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
    error "🚨 Critical vulnerabilities found. Aborting this step."
    return 1
  elif [[ "$high_count" -gt 0 ]]; then
    warn "⚠️ High severity vulnerabilities found."
    read -p "${YELLOW}Proceed anyway? (y/n): ${RESET}" allow_high
    [[ "$allow_high" != "y" ]] && error "⛔ Step skipped due to high severity vulnerabilities." && return 1
  fi

  success "✅ Snyk vulnerability report saved to $markdown_report_file"
}

stage_and_commit() {
  highlight "📁 Checking for changes..."

  # 🧠 Check if remote branch is ahead
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  remote_branch="origin/$current_branch"

  git fetch origin "$current_branch" >/dev/null 2>&1

  if git rev-parse --verify "$remote_branch" >/dev/null 2>&1; then
    local_commit=$(git rev-parse "$current_branch")
    remote_commit=$(git rev-parse "$remote_branch")
    base_commit=$(git merge-base "$current_branch" "$remote_branch")

    if [[ "$local_commit" != "$remote_commit" && "$remote_commit" == "$base_commit" ]]; then
      warn "⚠️ Remote branch '$remote_branch' is ahead of your local '$current_branch'."
      read -p "${YELLOW}Do you still want to continue staging and committing? (y/n): ${RESET}" proceed_commit
      if [[ "$proceed_commit" != "y" ]]; then
        error "🚫 Commit cancelled because local branch is behind."
        return 1
      fi
    fi
  fi

  git status | tee -a "$LOG_FILE"
  changed_items=$(git status --porcelain | awk '{print $2}')
  files_to_add=()

  if [[ -z "$changed_items" ]]; then
    success "✅ No changes to commit"
    return 0
  fi

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
    error "🚫 No files selected. Skipping commit step."
    return 1
  fi

  git add "${files_to_add[@]}"
  success "✅ Files staged"

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

  [[ -z "$commit_body" ]] && error "❌ Empty commit message. Skipping commit." && return 1

  full_commit="${jira_ticket}: ${commit_body}"
  echo "🧾 Commit message: $full_commit"
  read -p "${YELLOW}Commit changes? (y/n): ${RESET}" confirm_commit
  [[ "$confirm_commit" == "y" ]] && git commit -m "$full_commit" && success "✅ Commit done"
}

push_to_remote() {
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" =~ ^(main|develop|dev|master)$ ]]; then
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
      return 1
    fi
  fi

  highlight "🚀 Pushing to origin/$current_branch..."
  git push -u origin "$current_branch"
  success "✅ Push complete"
}

clean_merged_branches() {
  highlight "🧹 Cleaning up remote merged branches..."

  git fetch --all --prune

  bases=("develop" "dev" "main" "master")
  base_branch=""
  for base in "${bases[@]}"; do
    if git show-ref --verify --quiet "refs/remotes/origin/$base"; then
      base_branch="$base"
      break
    fi
  done

  if [[ -z "$base_branch" ]]; then
    error "❌ None of the base branches (develop/dev/main/master) found on remote."
    return 1
  fi

  highlight "📥 Pulling latest for base branch: $base_branch"
  git checkout "$base_branch" && git pull origin "$base_branch"

  merged_branches=$(git branch -r --merged origin/"$base_branch" | grep -vE "origin/($base_branch|HEAD)" | sed 's/origin\///')

  if [[ -z "$merged_branches" ]]; then
    success "✅ No merged branches found to delete."
    return 0
  fi

  echo "🌿 Merged branches into '$base_branch':"
  echo "$merged_branches" | nl

  read -p "${YELLOW}Do you want to delete these merged branches from remote? (y/n): ${RESET}" confirm_delete
  if [[ "$confirm_delete" != "y" ]]; then
    warn "⚠️ Deletion aborted by user."
    return 0
  fi

  for branch in $merged_branches; do
    if [[ "$branch" =~ ^(main|master|develop|dev)$ ]]; then
      warn "⛔ Skipping protected branch: $branch"
      continue
    fi
    if git push origin --delete "$branch" 2>&1 | tee -a "$LOG_FILE"; then
      success "🗑️ Deleted: $branch"
      echo "Deleted remote branch: $branch" >> "$LOG_FILE"
    else
      warn "⚠️ Failed to delete: $branch"
    fi
  done
}

# ---------- Main Loop -----------
while true; do
  highlight "🎛️  Git Assistant Menu"
  echo "Choose steps to run (e.g. 1 3 4):"
  echo "  1) 🔧 Run 'mvn clean install'"
  echo "  2) 🔎 Run 'snyk test' and generate report"
  echo "  3) 📝 Stage and commit git changes"
  echo "  4) 🚀 Push to remote with branch protection"
  echo "  5) ⚙️ Execute All (1, 2, 3, 4)"
  echo "  6) 🧹 Clean merged remote branches"
  echo "  7) ❌ Exit"
  read -p "${YELLOW}Enter your selection: ${RESET}" user_choice

  for option in $user_choice; do
    case $option in
      1) run_mvn_clean_install ;;
      2) run_snyk_test ;;
      3) stage_and_commit ;;
      4) push_to_remote ;;
      5)
        run_mvn_clean_install
        run_snyk_test
        stage_and_commit
        push_to_remote
        ;;
      6) clean_merged_branches ;;
      7)
        success "👋 Exiting Git Assistant. Bye!"
        exit 0
        ;;
      *) warn "❓ Unknown option: $option" ;;
    esac
  done

  echo ""
  highlight "✅ Task(s) completed. Back to main menu..."
  echo ""
done
