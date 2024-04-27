# Overview of the project

- It should be globally accessible
- It should check if the Docker is installed
- It should check if the Lando is installed

- Setting project initially:
    - Files are stored in a directory:
        - To be able to automatically detect if the user run the script from the WordPress project directory,
          we need to check if the directory contains (one of) the following folders:
            - `wp-content`
            - `wp-includes`
            - `wp-admin`
        - We will get the project name from the directory name, but the user will be asked to confirm it
    - Files are stored in a GitHub repository (defaults to our theme repository):
        - If the script is not run from the project directory, the user will be asked to provide the GitHub repository URL
        - We will get the project name from the repository name, but the user will be asked to confirm it
        - We will clone the repository in the current directory, enter the directory, and work from there
    - The user will be prompted to specify PHP version (default: 8.3, min: 7.4, max: 8.3)
    - The user will be prompted to specify the database version (default: 8.0, min: 5.6, max: 8.0)
    - The user will be prompted to specify the Node.js version (default: 20, min: 8, max: 20)
    - The user will be prompted to specify database username (default: `root`)
    - The user will be prompted to specify database password (default: `root`)
    - The user will be prompted to specify database name (default: `wordpress`)
    - The user will be prompted to specify the table prefix (default: `wp_`)
    - We will check if the wp-config.php file exists
        - If it does not exist, we will create it
        - If it exists, we will ask the user if they want to overwrite it
            - If the user wants to overwrite it, we will create a new one
        - We will use `lando wp config create` to create `wp-config.php`
    - The user will be prompted to specify the path of the sql file to import (default: none)
        - In this case, we have to check if the file exists and is readable
        - If the file does not exist or is not readable, the user will be prompted to provide a valid path
        - If the file is not a .sql file, the user will be prompted to provide a valid path
        - If the file is a .sql file, we will copy it to the project directory
        - We will use `lando db-import` to import the sql file
        - We will delete the sql file after the import
        - After the import, the user will be prompted to specify search-replace strings
        - We will use `lando wp search-replace` to replace the strings