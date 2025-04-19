#!/bin/bash

set -e

# ------------- Colors ----------------
BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# ------------- Log -------------------
LOG_FILE="git-assist.log"
touch "$LOG_FILE"

log() {
  echo "$1" | tee -a "$LOG_FILE"
}

highlight() {
  echo "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"
}

success() {
  echo "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"
}

warn() {
  echo "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"
}

error() {
  echo "${RED}$1${RESET}" | tee -a "$LOG_FILE"
}

# ------------- Start -----------------

log ""
highlight "--------------------------------------------"
highlight "🕒 Git Assistant started at $(date)"
highlight "--------------------------------------------"

highlight "🧠 Git status:"
git status | tee -a "$LOG_FILE"
echo ""

changed_items=$(git status --porcelain | awk '{print $2}')

if [[ -z "$changed_items" ]]; then
  success "✅ No changes to commit. Working tree clean."
  exit 0
fi

highlight "🔍 Found changed files. Let's pick what to add:"
files_to_add=()

for item in $changed_items; do
  if [[ -d "$item" ]]; then
    warn "📁 '$item' is a directory. Checking inside..."
    subfiles=$(find "$item" -type f)
    for subfile in $subfiles; do
      read -p "${YELLOW}Add file '$subfile'? (y/n): ${RESET}" confirm
      if [[ "$confirm" == "y" ]]; then
        files_to_add+=("$subfile")
        success "✅ Selected: $subfile"
      else
        error "❌ Skipped: $subfile"
      fi
    done
  else
    read -p "${YELLOW}Add file '$item'? (y/n): ${RESET}" confirm
    if [[ "$confirm" == "y" ]]; then
      files_to_add+=("$item")
      success "✅ Selected: $item"
    else
      error "❌ Skipped: $item"
    fi
  fi
done

if [ ${#files_to_add[@]} -eq 0 ]; then
  error "🚫 No files selected. Exiting."
  exit 1
fi

highlight "➕ Staging files..."
git add "${files_to_add[@]}"
success "✅ Files staged."

# ------------ Jira ID from branch (FINDATA only) ---------------
current_branch=$(git rev-parse --abbrev-ref HEAD)
highlight "🌿 Current branch: $current_branch"

jira_ticket=$(echo "$current_branch" | grep -Eo 'FINDATA-[0-9]+' || true)

if [[ -n "$jira_ticket" ]]; then
  success "📌 Detected Jira ticket from branch: $jira_ticket"
else
  warn "⚠️ Jira pattern 'FINDATA-###' not found in branch name."
  read -p "${YELLOW}🎫 Enter Jira Ticket (must match FINDATA-###): ${RESET}" jira_ticket
  while [[ ! "$jira_ticket" =~ ^FINDATA-[0-9]+$ ]]; do
    error "❌ Invalid format. Must be like FINDATA-123"
    read -p "${YELLOW}Try again: ${RESET}" jira_ticket
  done
fi

# ------------ Multi-line Commit ----------
highlight "📝 Enter your commit message. Save and close the editor when done..."
tmpfile=$(mktemp /tmp/gitmsg.XXXXXX)
${EDITOR:-nano} "$tmpfile"
commit_body=$(<"$tmpfile")
rm "$tmpfile"

if [[ -z "$commit_body" ]]; then
  error "❌ Empty commit message. Aborting."
  exit 1
fi

full_commit_message="${jira_ticket}: ${commit_body}"
highlight "🧾 Final commit message:"
echo "$full_commit_message" | tee -a "$LOG_FILE"

read -p "${YELLOW}Proceed with commit? (y/n): ${RESET}" commit_confirm
if [[ "$commit_confirm" != "y" ]]; then
  error "❌ Commit aborted."
  exit 1
fi

git commit -m "$full_commit_message"
success "✅ Commit created."

# ------------ Protected Branch Guard ------------
if [[ "$current_branch" == "main" || "$current_branch" == "develop" || "$current_branch" == "dev" ]]; then
  warn "⚠️  You're on a protected branch: $current_branch"
  read -p "${YELLOW}Do you REALLY want to push to '$current_branch'? (y/n): ${RESET}" confirm_push
  if [[ "$confirm_push" != "y" ]]; then
    error "🚫 Push cancelled."
    warn "🕳️ Reverting the last commit..."
    git reset --soft HEAD~1
    success "✅ Commit reverted. Changes remain staged."

    read -p "${YELLOW}✨ Create and switch to a new feature branch? (y/n): ${RESET}" switch_branch
    if [[ "$switch_branch" == "y" ]]; then
      read -p "${YELLOW}Enter new branch name (e.g. feature/FINDATA-123): ${RESET}" new_branch
      git checkout -b "$new_branch"
      success "🌱 Switched to new branch: $new_branch"
    fi
    exit 1
  fi
fi

# ------------ Push -----------------------
highlight "🚀 Pushing to origin/$current_branch..."
git push -u origin "$current_branch"
success "✅ Pushed successfully."

highlight "✅ Git Assistant finished at $(date)"
highlight "--------------------------------------------"
