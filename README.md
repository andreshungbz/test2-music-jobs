# CMPS3162 Test #2

## YouTube Demo

{pending}

## PostgreSQL Job Queue - Music Jobs

| Key               | Value                                          |
| ----------------- | ---------------------------------------------- |
| **Student Name**  | [Andres Hung](https://github.com/andreshungbz) |
| **Student Email** | 2018118240@ub.edu.bz                           |
| **Course**        | CMPS3162 - Advanced Databases                  |
| **Due Date**      | May 14, 2026                                   |

## Database Setup

```
CREATE role music_user WITH LOGIN PASSWORD 'music_password';
CREATE DATABASE music_processing;
ALTER DATABASE music_processing OWNER TO music_user;
```

### Running the SQL file

In the project directory and having `psql` logged into the database, run:

```
\i music_jobs.sql
```
