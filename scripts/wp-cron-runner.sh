#!/usr/bin/env bash
set -e
set -u
set -o pipefail

# -------------------------------------------------------------------
# Config
# -------------------------------------------------------------------

BASE="/webb/municipio/htdocs"
WP_PATH="$BASE/wp"

LOG_DIR="/webb/municipio/logs/crons"
LOCK_DIR="/webb/municipio/tmp/crons"

WP_BIN="/bin/wp"

# Site URL used for WP-CLI
WP_URL="pitealabb.pitea.se"

mkdir -p "$LOG_DIR" "$LOCK_DIR"

# -------------------------------------------------------------------
# Lock whole runner
# -------------------------------------------------------------------

exec 200>"$LOCK_DIR/cron-runner.lock"

if ! flock -n 200; then
  echo "$(date '+%F %T') Runner already active, exiting" >> "$LOG_DIR/runner.log"
  exit 0
fi

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

timestamp() {
  date '+%F %T'
}

wp_cmd() {
  "$WP_BIN" \
    --path="$WP_PATH" \
    --url="$WP_URL" \
    "$@"
}

log_runner() {
  echo "$(timestamp) $*" >> "$LOG_DIR/runner.log"
}

should_run_every_minutes() {
  local minutes="$1"
  local name="$2"
  local marker="$LOCK_DIR/last-run-$name"
  local now
  local last

  now=$(date +%s)

  if [[ ! -f "$marker" ]]; then
    echo "$now" > "$marker"
    return 0
  fi

  last=$(cat "$marker")

  if (( now - last >= minutes * 60 )); then
    echo "$now" > "$marker"
    return 0
  fi

  return 1
}

run_locked() {
  local name="$1"
  shift

  local safe_name
  safe_name=$(printf '%s' "$name" | tr -c 'a-zA-Z0-9_.-' '_')

  local lock_file="$LOCK_DIR/$safe_name.lock"
  local log_file="$LOG_DIR/$safe_name.log"

  (
    if ! flock -n 201; then
      echo "$(timestamp) SKIP: already running: $name" >> "$log_file"
      exit 0
    fi

    echo "" >> "$log_file"
    echo "----------------------------------------" >> "$log_file"
    echo "$(timestamp) START: $name" >> "$log_file"
    echo "$(timestamp) CMD: $*" >> "$log_file"

    "$@" >> "$log_file" 2>&1
    local status=$?

    echo "$(timestamp) END: $name exit=$status" >> "$log_file"

    exit "$status"
  ) 201>"$lock_file"
}

run_cron_hook() {
  local hook="$1"

  run_locked "wp-cron-$hook" \
    wp_cmd cron event run "$hook"
}

# -------------------------------------------------------------------
# Start
# -------------------------------------------------------------------

log_runner "Runner started"

# -------------------------------------------------------------------
# Every 5 minutes
# -------------------------------------------------------------------

run_cron_hook "modularity_service_info_import"
run_cron_hook "modularity_service_info_unpublish_expired"

run_locked "wp-service-info-import" \
  wp_cmd service-info import

run_locked "wp-service-info-unpublish" \
  wp_cmd service-info unpublish

# -------------------------------------------------------------------
# Every 10 minutes
# -------------------------------------------------------------------

if should_run_every_minutes 10 "every-10-minutes"; then
  run_cron_hook "litespeed_task_crawler"
fi

# -------------------------------------------------------------------
# Every 15 minutes
# -------------------------------------------------------------------

if should_run_every_minutes 15 "every-15-minutes"; then
  run_cron_hook "litespeed_task_lqip"
  run_cron_hook "wpseo_indexable_index_batch"
fi

# -------------------------------------------------------------------
# Every hour
# -------------------------------------------------------------------

if should_run_every_minutes 60 "hourly"; then
  run_cron_hook "wp_privacy_delete_old_export_files"
  run_cron_hook "wpseo_cleanup_cron"
  run_cron_hook "municipio_external_content_sync_lediga-jobb"

  run_locked "wp-typesense-sync-external" \
    wp_cmd typesense sync-external --yes

  run_locked "wp-simpleview-events-sync" \
    wp_cmd simpleview-events sync

  run_locked "wp-noticeboard-archive" \
    wp_cmd noticeboard archive
fi

# -------------------------------------------------------------------
# Every 12 hours
# -------------------------------------------------------------------

if should_run_every_minutes 720 "every-12-hours"; then
  run_cron_hook "wp_update_user_counts"
  run_cron_hook "update_network_counts"
fi

# -------------------------------------------------------------------
# Daily
# -------------------------------------------------------------------

if should_run_every_minutes 1440 "daily"; then
  run_cron_hook "recovery_mode_clean_expired_keys"
  run_cron_hook "wp_scheduled_delete"
  run_cron_hook "delete_expired_transients"
  run_cron_hook "wp_scheduled_auto_draft_delete"
  run_cron_hook "municipio_store_theme_mod"
  run_cron_hook "mod_form_builder_remove_old_forms"
  run_cron_hook "wpseo-reindex"
  run_cron_hook "wpseo_permalink_structure_check"
  run_cron_hook "wpseo_detect_default_seo_data"
fi

# -------------------------------------------------------------------
# Weekly
# -------------------------------------------------------------------

if should_run_every_minutes 10080 "weekly"; then
  run_cron_hook "wp_delete_temp_updater_backups"
fi

# -------------------------------------------------------------------
# Nightly heavy rebuild
# Runs once per day during hour 02
# -------------------------------------------------------------------

CURRENT_HOUR="$(date '+%H')"

if [[ "$CURRENT_HOUR" == "02" ]]; then
  if should_run_every_minutes 1440 "typesense-rebuild-nightly"; then
    run_locked "wp-typesense-rebuild" \
      wp_cmd typesense rebuild --include-pdf --include-external --yes
  fi
fi

log_runner "Runner finished"