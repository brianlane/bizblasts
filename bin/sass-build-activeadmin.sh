#!/usr/bin/env bash
set -e

# Get the ActiveAdmin gem's SCSS path
gem_scss_path=$(bundle show activeadmin)/app/assets/stylesheets

# Run Dart Sass with all required load paths
yarn sass ./app/assets/stylesheets/active_admin.scss:./app/assets/builds/active_admin.css --no-source-map --load-path=node_modules/@activeadmin/activeadmin/src/scss --load-path=node_modules --load-path=$gem_scss_path 