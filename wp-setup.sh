#!/bin/bash

# Define some colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "Docker ${RED}${BOLD}is not installed${NC}. Please install Docker and try again."
    exit 1
fi

# Check if Lando is installed
if ! command -v lando &> /dev/null; then
    echo -e "Lando ${RED}${BOLD}is not installed${NC}. Please install Lando and try again."
    exit 1
fi

# Function to check if any of the WordPress directories exist
check_any_wordpress_directory() {
    if [ -d "./wp-content" ] || [ -d "./wp-includes" ] || [ -d "./wp-admin" ]; then
        echo -e "${GREEN}${BOLD}You are currently in the WordPress project directory${NC}."
        return 0
    fi
    echo -e "${YELLOW}${BOLD}You aren't currently in the WordPress project directory${NC}."
    return 1
}

# Function to check if all WordPress directories exist
check_all_wordpress_directories() {
    if [ -d "./wp-content" ] && [ -d "./wp-includes" ] && [ -d "./wp-admin" ]; then
        return 0
    fi
    return 1
}

# Function to clone a repository
clone_repository() {
    read -e -p "Please provide the GitHub repository URL: " repo_url
    echo -e "Cloning the repository from ${BOLD}'$repo_url'${NC}..."
    if ! git clone "$repo_url"; then
        echo -e "${RED}${BOLD}Failed to clone the repository.${NC} Please check the URL and try again."
        exit 1
    fi
    echo -e "${GREEN}${BOLD}Repository cloned successfully.${NC}"
    cd "$(basename "$repo_url" .git)" || exit
}

# Function to set the project name
set_project_name() {
    echo -e "The current directory name is ${BOLD}$(basename "$(pwd)")${NC}."
    read -e -p "This will be used as the project name, please confirm (yes/no) [yes]: " confirm
    if [ "$confirm" = "no" ] || [ "$confirm" = "n" ]; then
        while true; do
            read -e -p "Please provide the project name: " project_name

            if [[ "$project_name" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{3,15}$ ]]; then
                break
            fi
            echo -e "${RED}${BOLD}Invalid project name${NC}. It should be 4 to 16 characters long, start with a letter or underscore, and can contain alphanumeric characters, underscores, and dashes."
        done
    else
        project_name=$(basename "$(pwd)")
    fi
    echo -e "The project name is ${BOLD}$project_name${NC}."
}

# Function to import SQL file
import_sql_file() {
    # Check if the Lando containers for the project are running
    if [ "$(lando list --format json | jq --arg project_name "${project_name//[-_]/}" 'any(.[]; .app == $project_name)')" != "true" ]; then
        echo -e "The Lando containers for the project are not running. ${YELLOW}${BOLD}Starting the Lando containers${NC}..."
        lando start
        echo -e "${GREEN}${BOLD}Lando containers started successfully${NC}."
    fi

    echo -e "Checking for an SQL file to import..."

    # Check if there is a .sql file in the project directory
    sql_file=$(find . -maxdepth 1 -name "*.sql" -print -quit)

    if [ -n "$sql_file" ]; then
        echo -e "A .sql file was found in the project directory: ${BOLD}$sql_file${NC}"
        read -e -p "Do you want to use this file? (yes/no) [no]: " use_sql_file
        if [ "$use_sql_file" = "yes" ] || [ "$use_sql_file" = "y" ]; then
            sql_file_path=$sql_file
        fi
    fi

    # Initialize a flag to check if the SQL file was copied from a different directory
    copied_sql_file=false

    # If the user did not want to use the .sql file in the project directory, or if no .sql file was found, prompt the user to specify the path of the SQL file to import
    if [ -z "$sql_file_path" ]; then
        if command -v zenity &> /dev/null; then
            sql_file_path=$(zenity --file-selection --title="Select the SQL file to import" --file-filter="SQL files (sql) | *.sql")
        else
            read -e -p "Please specify the path of the SQL file to import (default: none): " sql_file_path
        fi
    fi

    # Check if the SQL file path is not empty
    if [ -n "$sql_file_path" ]; then
        # Check if the SQL file exists and is readable
        if [ -f "$sql_file_path" ] && [ -r "$sql_file_path" ]; then
            # Check if the file is a .sql file
            if [[ "$sql_file_path" == *.sql ]]; then
                # Check if the SQL file is not in the project directory
                if [[ "$sql_file_path" != ./*.sql ]]; then
                    echo "Copying the SQL file to the project directory..."
                    cp "$sql_file_path" .
                    copied_sql_file=true
                fi

                # Use `lando db-import` to import the SQL file
                lando wp db drop --yes
                lando wp db create
                lando db-import "$(basename "$sql_file_path")" --no-wipe

                # Delete the SQL file after the import if it was copied from a different directory
                if $copied_sql_file; then
                    echo "Deleting the SQL file..."
                    rm "$(basename "$sql_file_path")"
                fi

                # Get the table prefix from the .lando.yml file
                echo "Getting the table prefix from the .lando.yml file..."
                table_prefix=$(grep 'TABLE_PREFIX:' .lando.yml | sed 's/TABLE_PREFIX: //' | tr -d '[:space:]')
                echo -e "The table prefix is '${BOLD}$table_prefix${NC}'."

                # Get the old domain from the options table
                old_domain=$(lando wp db query "SELECT option_value FROM ${table_prefix}options WHERE option_name = 'siteurl'" --skip-column-names --silent | tr -d '[:space:]')
                new_domain="http://$project_name.lndo.site"

                echo -e "Planning to replace '${BOLD}$old_domain${NC}' with '${BOLD}$new_domain${NC}' in the database..."
                read -e -p "Do you want to proceed with this replacement? (yes/no) [yes]: " confirm_replace
                if [ "$confirm_replace" = "no" ] || [ "$confirm_replace" = "n" ]; then
                    read -e -p "Please provide the search string: " search_string
                    read -e -p "Please provide the replace string: " replace_string

                    echo -e "Replacing the search string '${BOLD}$search_string${NC}' with the replace string '${BOLD}$replace_string${NC}' in the database..."
                    lando wp search-replace "$search_string" "$replace_string" --all-tables
                    echo -e "${GREEN}${BOLD}Search and replace completed successfully.${NC}"
                else
                    echo -e "Replacing the old domain '${BOLD}$old_domain${NC}' with the new domain '${BOLD}$new_domain${NC}' in the database..."
                    lando wp search-replace "$old_domain" "$new_domain" --all-tables
                    echo -e "${GREEN}${BOLD}Search and replace completed successfully.${NC}"
                fi
            else
                echo -e "${RED}${BOLD}The file is not a .sql file. Please provide a valid path.${NC}"
            fi
        else
            echo -e "${RED}${BOLD}The SQL file does not exist or is not readable. Please provide a valid path.${NC}"
        fi
    else
           echo -e "${YELLOW}${BOLD}No SQL file was provided.${NC}"
    fi
}

check_lando_file_exists() {
    if [ ! -f ".lando.yml" ]; then
        return 1
    fi

    read -e -p "A .lando.yml file already exists in the project directory. Do you want to overwrite it? (yes/no) [no]: " overwrite_lando_file
    if [ "$overwrite_lando_file" = "yes" ] || [ "$overwrite_lando_file" = "y" ]; then
        rm .lando.yml
        return 1
    fi

    return 0
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
  mail:
    type: mailhog
    portforward: true
    hogfrom:
      - appserver
tooling:
  node:
    service: appserver
  npm:
    service: appserver
  npx:
    service: appserver
proxy:
  pma:
    - pma.$project_name.lndo.site
  mail:
    - mail.$project_name.lndo.site
EOF
    echo -e "${GREEN}${BOLD}.lando.yml file created successfully.${NC}"
}

# Check if the script is run from a WordPress project directory
if check_any_wordpress_directory; then
    set_project_name
else
    clone_repository

    if check_any_wordpress_directory; then
        set_project_name
    else
        echo -e "${RED}${BOLD}The cloned repository is not a WordPress project.${NC} Please check the repository URL and try again."
        cd ..
        rm -rf "$(basename "$repo_url" .git)"
        exit 1
    fi
fi

if check_lando_file_exists; then
    import_sql_file
    exit 0
fi

# Prompt the user to specify PHP version
while true; do
    read -e -p "Please specify the PHP version (default: 8.3): " php_version
    php_version=${php_version:-8.3}

    if [[ "$php_version" =~ ^(7\.3|7\.4|8\.[0-3])$ ]]; then
        break
    fi
    echo -e "${RED}${BOLD}Invalid PHP version${NC}. Please specify a version from the list: 7.3, 7.4, 8.0, 8.1, 8.2, 8.3."
done


# Prompt the user to specify the database version
while true; do
    read -e -p "Please specify the database version (default: 8.0): " db_version
    db_version=${db_version:-8.0}

    if [[ "$db_version" =~ ^(5\.5|5\.6|5\.7|8\.0)$ ]]; then
        break
    fi
    echo -e "${RED}${BOLD}Invalid database version. Please specify a version from the list: 5.5, 5.6, 5.7, 8.0.${NC}"
done

# Prompt the user to specify the Node.js version
read -e -p "Please specify the Node.js version (default: 20): " node_version
node_version=${node_version:-20}

# Prompt the user to specify the database username
while true; do
    read -e -rp "Please specify the database username (default: user): " db_user
    db_user=${db_user:-user}

    if [[ "$db_user" != "root" && "$db_user" =~ ^[a-zA-Z_$][a-zA-Z0-9_$-]{0,15}$ ]]; then
        break
    fi
    echo -e "${RED}${BOLD}Invalid username. It should start with a letter, underscore or dollar sign, can contain alphanumeric characters, dollar signs, underscores, or hyphens, and must not exceed 16 characters. The username 'root' is not allowed.${NC}"
done

# Prompt the user to specify the database password
while true; do
    read -e -p "Please specify the database password (default: user): " db_password
    db_password=${db_password:-user}

    if [[ ${#db_password} -ge 4 ]]; then
        break
    fi
    echo -e "${RED}${BOLD}Invalid password. It should be at least 4 characters long.${NC}"
done

# Prompt the user to specify the database name
while true; do
    read -e -p "Please specify the database name (default: wordpress): " db_name
    db_name=${db_name:-wordpress}

    if [[ "$db_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,63}$ ]]; then
        break
    fi
    echo -e "${RED}${BOLD}Invalid database name. It should start with a letter or underscore, can contain alphanumeric characters and underscores, and must not exceed 64 characters.${NC}"
done

# Prompt the user to specify the table prefix
while true; do
    read -e -p "Please specify the table prefix (default: wp_): " table_prefix
    table_prefix=${table_prefix:-wp_}

    if [[ "$table_prefix" =~ ^[a-zA-Z_][a-zA-Z0-9_]*_$ ]]; then
        break
    fi
    echo -e "${RED}${BOLD}Invalid table prefix. It should start with a letter or underscore, can contain alphanumeric characters and underscores, and must end with an underscore.${NC}"
done

# Create .lando.yml file
create_lando_file

# Start up Lando
if ! lando start; then
    echo -e "${RED}${BOLD}Lando failed to start. Exiting the script.${NC}"
    exit 1
fi

# Import SQL file
import_sql_file
