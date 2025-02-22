# frozen_string_literal: true

namespace :schedule do
  desc 'sitemaps'
  task sitemap: :environment do
    next unless Date.today.sunday?
    Rake::Task['sitemap:refresh'].invoke
  end

  desc 'Sends triage emails'
  task triage_emails: :environment do
    User.find_each(batch_size: 100) do |user|
      SendDailyTriageEmailJob.perform_later(user)
    end
  end

  desc 'Populates github issues'
  task populate_issues: :environment do
    Repo.find_each(batch_size: 100) { |repo| PopulateIssuesJob.perform_later(repo) }
  end

  desc 'Marks issues as closed'
  task mark_closed: :environment do
    Issue.queue_mark_old_as_closed!
    Repo.find_each(batch_size: 100) do |repo|
      repo.force_issues_count_sync!
    end
  end

  desc 'Sends an email to invite users to engage once a week'
  task poke_inactive: :environment do
    next unless Date.today.tuesday?

    repos_by_need_ids = Repo.order_by_need.first(10).map(&:id)
    User.inactive.find_each(batch_size: 100) do |user|
      BackgroundInactiveEmailJob.perform_later(user, repos_by_need_ids: repos_by_need_ids)
    end
  end

  task clean_inactive_repos: :environment do
    # Repo.inactive.destroy_all
  end

  task check_user_auth: :environment do
    # API may be down
    response          = Excon.get("https://status.github.com/api/status.json").body
    github_api_status = JSON.parse(response)["status"]
    next unless github_api_status == "good"

    User.where.not(token: nil).find_each(batch_size: 100) do |user|
      # Check multiple times if token is not valid
      # if token is valid once, go to next user
      next if user.auth_is_valid?
      next if user.auth_is_valid?
      next if user.auth_is_valid?

      # Archive bad token
      user.update(token: nil, old_token: user.token)
    end
  end

  task warn_invalid_token: :environment do
    next unless Date.today.thursday?
    User.where(token: nil).find_each(batch_size: 100) do |user|
      UserMailer.invalid_token(user: user).deliver_later
    end
  end

  desc "pulls in files from repos and adds them to the database"
  task process_repos: :environment do
    Repo.find_each(batch_size: 100) do |repo|
      PopulateDocsJob.perform_later(repo)
    end
  end
end
