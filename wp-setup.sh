#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Please install Docker and try again."
    exit 1
fi

# Check if Lando is installed
if ! command -v lando &> /dev/null
then
    echo "Lando is not installed. Please install Lando and try again."
    exit 1
fi

# Function to check if any of the WordPress directories exist
check_any_wordpress_directory() {
    if [ -d "./wp-content" ] || [ -d "./wp-includes" ] || [ -d "./wp-admin" ]; then
        echo "At least one WordPress directory exists."
        return 0
    else
        echo "None of the WordPress directories exist."
        return 1
    fi
}

# Function to check if all WordPress directories exist
check_all_wordpress_directories() {
    if [ -d "./wp-content" ] && [ -d "./wp-includes" ] && [ -d "./wp-admin" ]; then
        return 0
    else
        return 1
    fi
}

# Function to clone a repository
clone_repository() {
    echo "Please provide the GitHub repository URL:"
    read repo_url
    if ! git clone "$repo_url"; then
        echo "Failed to clone the repository. Please check the URL and try again."
        exit 1
    fi
    cd "$(basename "$repo_url" .git)" || exit
}

# Function to set the project name
set_project_name() {
    echo "The current directory name is $(basename "$(pwd)")."
    echo "This will be used as the project name, please confirm (yes/no):"
    read confirm
    if [ "$confirm" != "yes" ]; then
        echo "Please provide the project name:"
        read project_name
    else
        project_name=$(basename "$(pwd)")
    fi
    echo "The project name is $project_name."
}

# Function to import SQL file
import_sql_file() {
    # Check if the Lando containers for the project are running
    if [ "$(lando list --format json | jq --arg project_name "${project_name//[-_]/}" 'any(.[]; .app == $project_name)')" != "true" ]; then
        echo "The Lando containers for the project are not running. Starting the Lando containers..."
        lando start
    fi

    # Check if there is a .sql file in the project directory
    sql_file=$(find . -maxdepth 1 -name "*.sql" -print -quit)

    if [ -n "$sql_file" ]; then
        echo "A .sql file was found in the project directory: $sql_file"
        echo "Do you want to use this file? (yes/no)"
        read use_sql_file
        if [ "$use_sql_file" = "yes" ]; then
            sql_file_path=$sql_file
        fi
    fi

    # If the user did not want to use the .sql file in the project directory, or if no .sql file was found, prompt the user to specify the path of the SQL file to import
    if [ -z "$sql_file_path" ]; then
        echo "Please specify the path of the SQL file to import (default: none):"
        read sql_file_path
    fi

    # Check if the SQL file path is not empty
    if [ -n "$sql_file_path" ]; then
        # Check if the SQL file exists and is readable
        if [ -f "$sql_file_path" ] && [ -r "$sql_file_path" ]; then
            # Check if the file is a .sql file
            if [[ "$sql_file_path" == *.sql ]]; then
                cp "$sql_file_path" .

                # Use `lando db-import` to import the SQL file
                lando wp db drop --yes
                lando wp db create
                lando db-import "$(basename "$sql_file_path")" --no-wipe

                # Delete the SQL file after the import
                rm "$(basename "$sql_file_path")"

                # Get the table prefix from the .lando.yml file
                table_prefix=$(grep 'TABLE_PREFIX:' .lando.yml | sed 's/TABLE_PREFIX: //')

                # Get the old domain from the options table
                old_domain="$(lando wp db query "SELECT option_value FROM ${table_prefix}options WHERE option_name = 'siteurl'" --skip-column-names --silent | tr -d '[:space:]')"
                new_domain="http://$project_name.lndo.site"
                echo "Replacing '$old_domain' with '$new_domain' in the database..."

                # Use `lando wp search-replace` to replace the old domain with the new domain
                lando wp search-replace "$old_domain" "$new_domain"
            else
                echo "The file is not a .sql file. Please provide a valid path."
            fi
        else
            echo "The SQL file does not exist or is not readable. Please provide a valid path."
        fi
    fi
}

check_lando_file_exists() {
    if [ -f ".lando.yml" ]; then
        echo "A .lando.yml file already exists in the project directory. Do you want to overwrite it? (yes/no)"
        read overwrite_lando_file
        if [ "$overwrite_lando_file" = "yes" ]; then
            rm .lando.yml
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}

# Function to create .lando.yml file
create_lando_file() {
    cat << EOF > .lando.yml
name: $project_name
recipe: wordpress
config:
  webroot: .
  php: $php_version
  database: mysql:$db_version
services:
  appserver:
    scanner: false
    overrides:
      environment:
        DB_USER: $db_user
        DB_PASSWORD: $db_password
        DB_NAME: $db_name
        DB_HOST: database
        TABLE_PREFIX: $table_prefix
    build_as_root:
      - curl -fsSL https://deb.nodesource.com/setup_$node_version.x | bash -
      - apt-get install -y nodejs
      - if [ -d "wp-content/themes/$project_name" ]; then cd "wp-content/themes/$project_name"; if [ -f "package.json" ]; then npm install; fi; if [ -f "composer.json" ]; then composer install; fi; cd ../../../; fi
    run:
      - if [ ! -d "wp-content" ] || [ ! -d "wp-includes" ] || [ ! -d "wp-admin" ]; then wp core download; fi
      - if [ ! -f "wp-config.php" ]; then wp config create --dbname="$db_name" --dbuser="$db_user" --dbpass="$db_password" --dbhost="database" --dbprefix="$table_prefix"; fi
  database:
    creds:
      user: $db_user
      password: $db_password
      database: $db_name
  pma:
    type: phpmyadmin
tooling:
  node:
    service: appserver
  npm:
    service: appserver
proxy:
  pma:
    - pma.$project_name.lndo.site
EOF
}

# Check if the script is run from a WordPress project directory
if check_any_wordpress_directory; then
    set_project_name
else
    clone_repository

    if check_any_wordpress_directory; then
        set_project_name
    else
        echo "The cloned repository is not a WordPress project. Please check the repository URL and try again."
        cd ..
        rm -rf "$(basename "$repo_url" .git)"
        exit 1
    fi
fi

if check_lando_file_exists; then
    import_sql_file
    exit 0
fi

# Prompt the user to specify PHP version, database version, Node.js version, database username, password, name, and table prefix
echo "Please specify the PHP version (default: 8.3):"
read php_version
php_version=${php_version:-8.3}

echo "Please specify the database version (default: 8.0):"
read db_version
db_version=${db_version:-8.0}

echo "Please specify the Node.js version (default: 20):"
read node_version
node_version=${node_version:-20}

while true; do
    echo "Please specify the database username (default: user):"
    read db_user
    db_user=${db_user:-user}

    if [ "$db_user" = "root" ]; then
        echo "The username 'root' is not allowed. Please provide a different username."
    else
        break
    fi
done

echo "Please specify the database password (default: user):"
read db_password
db_password=${db_password:-user}

echo "Please specify the database name (default: wordpress):"
read db_name
db_name=${db_name:-wordpress}

echo "Please specify the table prefix (default: wp_):"
read table_prefix
table_prefix=${table_prefix:-wp_}

# Create .lando.yml file
create_lando_file

# Start up Lando
if ! lando start; then
    echo "Lando failed to start. Exiting the script."
    exit 1
fi

# Import SQL file
import_sql_file
