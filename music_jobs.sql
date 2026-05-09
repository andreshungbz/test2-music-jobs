/* ====================================================================================
CMPS3162 Test 2: PostgreSQL Job Queue
Music Processing - Multi-Step Incremental Build
Andres Hung (2018118240@ub.edu.bz)
PostgreSQL 18.3 (Homebrew)
May 14, 2026
==================================================================================== */

/* ====================================================================================
STEP 0 - Reset

This initial extra step is used to clear the database so that this file can be ran
and iterated upon with the psql \i music_jobs.sql command.
==================================================================================== */

DROP TABLE IF EXISTS music_jobs;

/* ====================================================================================
STEP 1 - id, payload, created_at
==================================================================================== */

CREATE TABLE IF NOT EXISTS music_jobs (
    -- id is time-ordered for B-Tree performance as uuidv7 contains a timestamp and 
    -- PostgreSQL automatically creates a default B-Tree index for primary keys
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- QUESTIONS/ANSWERS --

/* 1. Why UUID over SERIAL for the primary key?
While SERIAL works great as a unique field for simpler databases, UUID is designed to be
unique even across other tables and databases. For example, if another jobs tabled needed
to be merged into the music_jobs table, then using UUID make it extremely less likely to
cause a conflict compared to the incrementing integers of SERIAL. It is also better from a 
security standpoint since with SERIAL, it may be possible to enumerate records. 
*/

/* 2. Why uuidv7() specifically over uuidv4()?
A uuidv7 contains a timestamp component in addition to random bits. This design improves database
performance when used alongside a B-Tree index. The result is improved performance at scale, which
uuidv4 is worse at because it does not contain a timestamp component. 
*/

/* 3. Why JSONB over JSON?
The key-value pair structure of JSON works well for storing metadata information of music files. 
The JSONB type is optimized for searching, indexing, and filtering since PostgreSQL parses the 
input on insert. This is preferable to the JSON type, which PostgreSQL stores as is (whitespace, 
duplicates, etc.), since this allows us to search/filter music jobs by artist, for example, 
which in turn is a useful statistic. The music jobs use case works better for JSONB.
*/

/* 4. Why TIMESTAMPTZ over TIMESTAMP?
The TIMESTAMPTZ type stores a timestamp which is converted to UTC, whereas the TIMESTAMP type
does not contain timezone information. TIMESTAMPTZ is preferred since for the use case of a
created_at field, timezone-related bugs are avoided. If the database server would be moved to 
another region or distributed, the TIMESTAMPTZ type ensures that the exact instant that occurred
globally is recorded.
*/

-- SAMPLE DATA --
-- Note that pg_sleep is used to make sure the created_at aren't all the same.

INSERT INTO music_jobs (payload)
VALUES (
    '{
        "filename": "hiruga.wav",
        "mime_type": "audio/wav",
        "title": "Hiruga",
        "album": "Garifuna Nuguya",
        "artist": "Clayton Williams",
        "genre": "Worldwide",
        "year": 2015,
        "duration_s": 234,
        "sample_rate": 48000,
        "channels": 2,
        "bit_depth": 24
    }'::JSONB
);

SELECT pg_sleep(1);

INSERT INTO music_jobs (payload)
VALUES (
    '{
        "filename": "miami.mp3",
        "mime_type": "audio/mpeg",
        "title": "Miami",
        "album": "Wátina",
        "artist": "The Garifuna Collective, Andy Palacio",
        "genre": "African",
        "year": 2007,
        "duration_s": 224,
        "bitrate_kbps": 256
    }'::JSONB
);

SELECT pg_sleep(1);

INSERT INTO music_jobs (payload)
VALUES (
    '{
        "filename": "buruboun-garada.mp3",
        "mime_type": "audio/mpeg",
        "title": "Buruboun Garada",
        "artist": "Lloyd Augustine",
        "genre": "Caribbean",
        "year": 2023,
        "publisher": "Stonetree Records",
        "duration_s": 211,
        "bitrate_kbps": 320
    }'::JSONB
);

-- VERIFICATION QUERIES --

/* 1. Show all jobs ordered by creation time.
SELECT payload->>'title' AS music_job_title, created_at
FROM music_jobs
ORDER BY created_at;

 music_job_title |          created_at           
-----------------+-------------------------------
 Hiruga          | 2026-05-08 18:28:47.747185-06
 Miami           | 2026-05-08 18:28:48.76592-06
 Buruboun Garada | 2026-05-08 18:28:49.768337-06
(3 rows)
*/

/* 2. Extract just the filename and mime_type from each job.
SELECT payload->>'filename' AS job_filename, payload->>'mime_type' AS mime_type
FROM music_jobs;

    job_filename     | mime_type  
---------------------+------------
 hiruga.wav          | audio/wav
 miami.mp3           | audio/mpeg
 buruboun-garada.mp3 | audio/mpeg
(3 rows)
*/

/* 3. Find only MP3 uploads.
SELECT payload->>'filename' AS job_filename, payload->>'mime_type' AS mime_type
FROM music_jobs
WHERE payload->>'mime_type' = 'audio/mpeg';

    job_filename     | mime_type  
---------------------+------------
 miami.mp3           | audio/mpeg
 buruboun-garada.mp3 | audio/mpeg
(2 rows)
*/

/* 4. Find the jobs that has the extra field.
SELECT id, payload->>'filename' AS job_filename
FROM music_jobs
WHERE payload ? 'publisher';

                  id                  |    job_filename     
--------------------------------------+---------------------
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | buruboun-garada.mp3
(1 row)
*/

/* ====================================================================================
STEP 2 - public_id
==================================================================================== */

-- Note that PostgreSQL automatically creates an index for a field with the UNIQUE constraint.
ALTER TABLE music_jobs ADD COLUMN public_id UUID UNIQUE NOT NULL DEFAULT uuidv4();

-- QUESTIONS/ANSWERS --

/* 1. Why does this column use uuidv4() and not uuidv7()?
As uuidv7 has the timestamp embedded, it can potentially be a security concern if it was
used for the public_id field. In this case, when a job was created could be used by an 
attacker to analyze traffic. Determining the average number of jobs being created could be
useful to a competitor, or even maliciously used in configuring a DDOS attack. Using uuidv4()
is better for the public_id field since it does not embed a timestamp.
*/

/* 2. What does uuid_extract_timestamp() reveal about uuidv7?
The PostgreSQL uuid_extract)timestamp function reveals when the UUID was generated. This is 
a security concern as discussed in Question 1.
*/

/* 3. WHy does the UNIQUE constraint make CREATE INDEX unnecessary?
When a field has the UNIQUE constraint, PostgreSQL automatically creates a unique B-Tree
index for it. The same occurs for primary keys and EXCLUSION constraints.
*/

/* 4. What is the two-ID pattern and why does it matter?
The two-ID pattern involves using two different identifiers for one record. Usually, one
is internal and the other is public. It matters because it allows us to take advantage of
both the better indexing performance offered by an id that can be ordered like uuidv7 and 
the obfuscation of metadata offered by another id that is truly random like uuidv4. 
*/

-- VERIFICATION QUERIES --

/* 1. Show id vs public_id side by side - what do you notice?
SELECT id, public_id FROM music_jobs;

                  id                  |              public_id               
--------------------------------------+--------------------------------------
 019e0a23-050b-7cd0-9091-c81ce85f694c | d43440f1-da73-412f-960b-017b25c79928
 019e0a23-08fe-733c-b146-c2b411010a5c | f28b59a3-66d1-45af-977e-385bc95d881c
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | 28157939-27c8-4f6e-a60b-3136bf04496b
(3 rows)

From the results, you can notice how in the id field, which is using uuidv7, the first
part is the exact same. This corresponds to the timestamp that is embedded. There is no 
common or similar pattern seen in the public_id field.
*/

/* 2. Run uuid_extract_timestamp() on both columns - what does this prove?
SELECT uuid_extract_timestamp(id) AS id_timestamp, uuid_extract_timestamp(public_id) AS public_id_timestamp FROM music_jobs;

        id_timestamp        | public_id_timestamp 
----------------------------+---------------------
 2026-05-08 18:28:47.755-06 | [null]
 2026-05-08 18:28:48.766-06 | [null]
 2026-05-08 18:28:49.768-06 | [null]
(3 rows)

This proves that uuidv7 has a timestamp component and that uuidv4 does not.
*/

/* 3. Show what the Go server would return to the client after insert.
HTTP/2 202 
date: Fri, 08 May 2026 23:35:31 GMT
content-type: application/json
content-length: 56
{
    "job_id": "d43440f1-da73-412f-960b-017b25c79928"
}

After insert, the server would return a JSON response with the job_id, which is the 
public_id field internally. The client would use this id to poll the status of the job. 
Most notable is the 202 HTTP status code, which means the request was received and 
accepted for processing, but the processing has not yet been completed.
*/

/* 4. Show what the Go server would do when the client polls.
HTTP/2 200 
date: Fri, 08 May 2026 23:36:30 GMT
content-type: application/json
content-length: 50
{
    "status": "processing",
    "progress": 25
}

When the client polls for the particular job using the job_id or public_id, the server would 
return a JSON response with the status and progress of the job. The HTTP status code is 200 
for OK, and the client would use the response to check the overall job. Note that these
fields are added in STEP 3.
*/

/* ====================================================================================
STEP 3 - status, progress
==================================================================================== */

ALTER TABLE music_jobs
    ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'done', 'failed')),
    ADD COLUMN progress INTEGER NOT NULL DEFAULT 0
        CHECK (progress BETWEEN 0 AND 100);

-- QUESTIONS/ANSWERS --

/* 1. Why are status and progress real columns, not inside payload JSONB?
The status and progress fields are real columns because these fields will be queried 
more often, and it is faster when they are columns and not inside the payload JSONB. 
These fields also concern more the job record itself, rather than as part of the metadata
for a music file.
*/

/* 2. What happens if a buggy worker writes status = 'complet'?
The PostgreSQL database would not complete the write, instead returning an error. This 
is because of the CHECK constraint added in the definition of the column, which limits 
the valid values to the correctly spelled statuses.
*/

/* 3. Why does the CHECK constraint matter more than application validation?
It matters more because the constraint is enforced at the database level instead of the 
application level. As a result, the constraint cannot be bypassed due to bugs at the 
application level or bad data being accidentally entered.
*/

/* 4. Draw the state machine for a job lifecycle.
    START
      |
      v
+------------+
|  PENDING   |
+------------+
      |
      | worker starts processing
      v
+--------------+                         +----------+
| PROCESSING   | -- processing error --> |  FAILED  |
+--------------+                         +----------+
      |                                        |
      | processing completes                   |
      v                                        |
+-------------+                                v
| COMPLETED   | --------------------------->  END
+-------------+

Note that START and END are used in place of the typical UML symbols in a 
state (machine) diagram.
*/

-- SAMPLE DATA --

UPDATE music_jobs
SET status = 'processing', progress = 25 -- the first UPDATE from pending should change status to processing
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

UPDATE music_jobs
SET progress = 50
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

UPDATE music_jobs
SET status = 'done', progress = 100
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

UPDATE music_jobs
SET status = 'invalid'
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

/*
ERROR:  new row for relation "music_jobs" violates check constraint "music_jobs_status_check"
DETAIL:  Failing row contains (019e0a23-050b-7cd0-9091-c81ce85f694c, {"year": 2015, "album": "Garifuna Nuguya", "genre": "Worldwide",..., 2026-05-08 18:28:47.747185-06, d43440f1-da73-412f-960b-017b25c79928, invalid, 100).
*/

UPDATE music_jobs
SET progress = 150
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

/*
ERROR:  new row for relation "music_jobs" violates check constraint "music_jobs_progress_check"
DETAIL:  Failing row contains (019e0a23-050b-7cd0-9091-c81ce85f694c, {"year": 2015, "album": "Garifuna Nuguya", "genre": "Worldwide",..., 2026-05-08 18:28:47.747185-06, d43440f1-da73-412f-960b-017b25c79928, done, 150).
*/

-- VERIFICATION QUERIES

-- update the second record to be processing so that we have a processing job for Query 1.
UPDATE music_jobs
SET status = 'processing', progress = 25
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* 1. What does the client see when polling a processing job?
SELECT status, progress
FROM music_jobs
WHERE public_id = 'f28b59a3-66d1-45af-977e-385bc95d881c';

   status   | progress 
------------+----------
 processing |       25
(1 row)

Note that this is the query from which the JSON response would be created. Such 
a response would look like this:

HTTP/2 200 
date: Fri, 08 May 2026 23:37:30 GMT
content-type: application/json
content-length: 50
{
    "status": "processing",
    "progress": 25
}
*/

/* 2. What query does the worker run to find its next job?
SELECT id
FROM music_jobs
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1;

                  id                  
--------------------------------------
 019e0a23-0ce8-79e0-a6dd-04d71902f005
(1 row)

Note that this is the third job which is still pending. See Query 3.
*/

/* 3. Show all jobs with their current states
SELECT id, payload->>'title' AS title, status, progress, created_at
FROM music_jobs
ORDER BY created_at;

                  id                  |      title      |   status   | progress |          created_at           
--------------------------------------+-----------------+------------+----------+-------------------------------
 019e0a23-050b-7cd0-9091-c81ce85f694c | Hiruga          | done       |      100 | 2026-05-08 18:28:47.747185-06
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami           | processing |       25 | 2026-05-08 18:28:48.76592-06
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | Buruboun Garada | pending    |        0 | 2026-05-08 18:28:49.768337-06
(3 rows)

Note that additional fields are shown and the result was ordered to more clearly show 
the results of the UPDATE queries from before.
*/
