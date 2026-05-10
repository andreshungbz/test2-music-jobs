/* ====================================================================================
CMPS3162 Test 2: PostgreSQL Job Queue
Music Processing - Multi-Step Incremental Build
Andres Hung (2018118240@ub.edu.bz)
PostgreSQL 18.3 (Homebrew)
May 14, 2026
==================================================================================== */

/* ====================================================================================
STEP 0 - Reset
This initial extra step is used to clear the database so that this file can be run
and iterated upon with the \i music_jobs.sql command in psql.
==================================================================================== */

DROP INDEX IF EXISTS idx_music_jobs_result;
DROP INDEX IF EXISTS idx_music_jobs_payload;
DROP INDEX IF EXISTS idx_music_jobs_status_created;
DROP TRIGGER IF EXISTS music_jobs_updated_at ON music_jobs;
DROP FUNCTION IF EXISTS set_updated_at();
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
unique even across other tables and databases. For example, if another jobs table needed
to be merged into the music_jobs table, then using UUID makes it extremely less likely to
cause a conflict compared to the incrementing integers of SERIAL. It is also better from a 
security standpoint since with SERIAL, it may be possible to enumerate records. 
*/

/* 2. Why uuidv7() specifically over uuidv4()?
A UUIDv7 contains a timestamp component in addition to random bits. This design improves database
performance when used alongside a B-Tree index. The result is improved performance at scale, which
UUIDv4 is worse at because it does not contain a timestamp component. 
*/

/* 3. Why JSONB over JSON?
The key-value pair structure of JSON works well for storing metadata information of music files. 
The JSONB type is optimized for searching, indexing, and filtering since PostgreSQL parses the 
input on insert. This is preferable to the JSON type, which PostgreSQL stores as is (whitespace, 
duplicates, etc.), since this allows us to search/filter music jobs by artist, for example, 
which in turn is a useful statistic. The music jobs use case works better with JSONB.
*/

/* 4. Why TIMESTAMPTZ over TIMESTAMP?
The TIMESTAMPTZ type stores a timestamp which is converted to UTC, whereas the TIMESTAMP type
does not contain timezone information. TIMESTAMPTZ is preferred since, for the use case of a
created_at field, timezone-related bugs are avoided. If the database server were moved to 
another region or distributed, the TIMESTAMPTZ type ensures that the exact instant that occurred
globally is recorded.
*/

-- SAMPLE DATA --
-- Note that pg_sleep is used to make sure the created_at aren't all the same.

INSERT INTO music_jobs (payload)
VALUES (
    '{
        "original_filename": "hiruga.wav",
        "stored_path": "uploads/hiruga.wav",
        "mime_type": "audio/wav",
        "file_size": 18000000,
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
        "original_filename": "miami.mp3",
        "stored_path": "uploads/miami.mp3",
        "mime_type": "audio/mpeg",
        "file_size": 1200000,
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

-- extra field: publisher
INSERT INTO music_jobs (payload)
VALUES (
    '{
        "original_filename": "buruboun-garada.mp3",
        "stored_path": "uploads/buruboun-garada.mp3",
        "mime_type": "audio/mpeg",
        "file_size": 3800000,
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
SELECT payload->>'title' AS music_job_title, created_at FROM music_jobs ORDER BY created_at;

 music_job_title |          created_at           
-----------------+-------------------------------
 Hiruga          | 2026-05-08 18:28:47.747185-06
 Miami           | 2026-05-08 18:28:48.76592-06
 Buruboun Garada | 2026-05-08 18:28:49.768337-06
(3 rows)
*/

/* 2. Extract just the original_filename and mime_type from each job.
SELECT payload->>'original_filename' AS job_filename, payload->>'mime_type' AS mime_type FROM music_jobs;

    job_filename     | mime_type  
---------------------+------------
 hiruga.wav          | audio/wav
 miami.mp3           | audio/mpeg
 buruboun-garada.mp3 | audio/mpeg
(3 rows)
*/

/* 3. Find only MP3 uploads.
SELECT payload->>'original_filename' AS job_filename, payload->>'mime_type' AS mime_type
FROM music_jobs WHERE payload->>'mime_type' = 'audio/mpeg';

    job_filename     | mime_type  
---------------------+------------
 miami.mp3           | audio/mpeg
 buruboun-garada.mp3 | audio/mpeg
(2 rows)
*/

/* 4. Find the jobs that have the extra field.
SELECT id, payload->>'original_filename' AS job_filename FROM music_jobs WHERE payload ? 'publisher';

                  id                  |    job_filename     
--------------------------------------+---------------------
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | buruboun-garada.mp3
(1 row)

Note the use of the key existence operator (?).
*/

/* ====================================================================================
STEP 2 - public_id
==================================================================================== */

-- Note that PostgreSQL automatically creates an index for a field with the UNIQUE constraint.
ALTER TABLE music_jobs
    ADD COLUMN public_id UUID UNIQUE NOT NULL DEFAULT uuidv4();

-- QUESTIONS/ANSWERS --

/* 1. Why does this column use uuidv4() and not uuidv7()?
As UUIDv7 has an embedded timestamp, it can potentially be a security concern if it were
used for the public_id field. In this case, when a job was created could be used by an 
attacker to analyze traffic. Determining the average number of jobs being created could be
useful to a competitor, or even maliciously used in configuring a DDOS attack. Using uuidv4()
is better for the public_id field since it does not embed a timestamp.
*/

/* 2. What does uuid_extract_timestamp() reveal about uuidv7?
The PostgreSQL uuid_extract_timestamp() function returns the timestamp when the UUID 
was generated. This is a security concern as discussed in Question 1.
*/

/* 3. Why does the UNIQUE constraint make CREATE INDEX unnecessary?
When a field has the UNIQUE constraint, PostgreSQL automatically creates a unique B-Tree
index for it. The same occurs for primary keys and EXCLUSION constraints.
*/

/* 4. What is the two-ID pattern and why does it matter?
The two-ID pattern involves using two distinct identifiers for a single record. Usually, one
is internal, and the other is public. It matters because it allows us to take advantage of
both the better indexing performance offered by an ID that can be ordered like UUIDv7, and 
the obfuscation of metadata offered by another ID that is truly random like UUIDv4. 
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

From the results, one can notice how in the id field, which is using uuidv7, the first
part is the exact same. This corresponds to the embedded timestamp. There is no 
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

This proves that UUIDv7 has a timestamp component, whereas UUIDv4 does not.
*/

/* 3. Show what the Go server would return to the client after insert.
HTTP/2 202 
date: Fri, 08 May 2026 23:35:31 GMT
content-type: application/json
content-length: 56
{
    "job_id": "d43440f1-da73-412f-960b-017b25c79928"
}

After the insert, the server would return a JSON response with the job_id, which is the 
public_id field internally. The client would use this ID to check the job's status. 
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
fields are added in STEP 3 and further expanded in a later STEP.
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
These fields also concern the job record itself, rather than as part of the metadata
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
+------------+                                 v
|    DONE    | ---------------------------->  END
+------------+

Note that START and END are used in place of the typical UML symbols in a 
state (machine) diagram.
*/

-- SAMPLE DATA --
-- Using the oldest job.

UPDATE music_jobs
SET status = 'processing', progress = 25 -- the first UPDATE from pending should change status to processing
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1); -- the oldest job

UPDATE music_jobs
SET progress = 50 -- the second UPDATE doesn't need to set status, as it is still processing
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

UPDATE music_jobs
SET status = 'done', progress = 100 -- the third UPDATE changes status since the job is done
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

-- VERIFICATION QUERIES --

-- Update the second oldest job to be processing so that we have a processing job for Query 1 (OFFSET 1).
UPDATE music_jobs
SET status = 'processing', progress = 25
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* 1. What does the client see when polling a processing job?
SELECT status, progress FROM music_jobs WHERE public_id = 'f28b59a3-66d1-45af-977e-385bc95d881c';

   status   | progress 
------------+----------
 processing |       25
(1 row)

Note that this is the query from which the JSON response would be created. Such 
a response would look like this so far:

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
SELECT id FROM music_jobs WHERE status = 'pending' ORDER BY created_at LIMIT 1;

                  id                  
--------------------------------------
 019e0a23-0ce8-79e0-a6dd-04d71902f005
(1 row)

Note that this is the third-oldest job, which is still pending. See Query 3.
*/

/* 3. Show all jobs with their current states
SELECT id, payload->>'title' AS title, status, progress, created_at FROM music_jobs ORDER BY created_at;

                  id                  |      title      |   status   | progress |          created_at           
--------------------------------------+-----------------+------------+----------+-------------------------------
 019e0a23-050b-7cd0-9091-c81ce85f694c | Hiruga          | done       |      100 | 2026-05-08 18:28:47.747185-06
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami           | processing |       25 | 2026-05-08 18:28:48.76592-06
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | Buruboun Garada | pending    |        0 | 2026-05-08 18:28:49.768337-06
(3 rows)

Note that additional fields are shown, and the result was ordered to more clearly show 
the results of the UPDATE queries from before.
*/

/* ====================================================================================
STEP 4 - result, error_msg
==================================================================================== */

ALTER TABLE music_jobs
    ADD COLUMN result JSONB NOT NULL DEFAULT '{}',
    ADD COLUMN error_msg TEXT;

-- QUESTIONS/ANSWERS

/* 1. Why does the result default to '{}' and not NULL?
Using an empty object '{}' is preferable to NULL since it keeps a consistent JSON structure 
where JSON operations can be safely performed without NULL checks. It can be logically 
interpreted as having no result data yet, rather than unknown, as NULL could imply.
*/

/* 2. Why is error_msg TEXT and not inside the result JSONB?
Likewise with the status and progress fields, the error_msg field is part of the job 
lifecycle and does not particularly relate to the metadata of a music file or its result. 
Using the TEXT type provides a simple and consistent structure for error messages.
*/

/* 3. What does the || operator do to a JSONB object?
It is the merge operator, taking the operand on the right-hand side, and merging it 
with the operand on the left-hand side. For a JSONB object, if a key does not exist 
on the left-hand JSONB object, a new one is created. If a key already exists, the 
value is overwritten.
*/

/* 4. Why does each stage read from the original file, not the previous stage's output?
Of the four stages: normalize, trim silence, convert, and waveform, the original file 
is read instead of using the previous stage's output, so that the result of one stage 
is not reflected in another stage. Having the stages be independent has the advantage 
of being able to be processed in parallel. Additionally, errors or artifacts aren't carried 
over across stages. For example, adjusting the volume in the normalize stage would 
most certainly affect the generated waveform for the waveform stage. 
*/

-- SAMPLE DATA --
-- Simulating stages for the oldest job.

UPDATE music_jobs
SET status = 'processing', progress = 25, -- change status to processing
result = result || jsonb_build_object(
    'normalized_path', 'uploads/processed/normalized_' || md5(payload->>'title') || '.wav'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

/*
SELECT  payload->>'title' AS title, status, progress, result
FROM music_jobs WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

 title  |   status   | progress |                                          result                                          
--------+------------+----------+------------------------------------------------------------------------------------------
 Hiruga | processing |       25 | {"normalized_path": "uploads/processed/normalized_12a1b35871580a987e3ed5c049ef784b.wav"}
(1 row)
*/

UPDATE music_jobs
SET progress = 50,
result = result || jsonb_build_object(
    'trimmed_path', 'uploads/processed/trimmed_' || md5(payload->>'title') || '.wav'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

/*
SELECT  payload->>'title' AS title, status, progress, result
FROM music_jobs WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

 title  |   status   | progress |                                                                                   result                                                                                   
--------+------------+----------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Hiruga | processing |       50 | {"trimmed_path": "uploads/processed/trimmed_12a1b35871580a987e3ed5c049ef784b.wav", "normalized_path": "uploads/processed/normalized_12a1b35871580a987e3ed5c049ef784b.wav"}
(1 row)
*/

UPDATE music_jobs
SET progress = 75,
result = result || jsonb_build_object(
    'converted_path', 'uploads/processed/converted_' || md5(payload->>'title') || '.mp3'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

/*
SELECT  payload->>'title' AS title, status, progress, result
FROM music_jobs WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

 title  |   status   | progress |                                                                                                                              result                                                                                                                              
--------+------------+----------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Hiruga | processing |       75 | {"trimmed_path": "uploads/processed/trimmed_12a1b35871580a987e3ed5c049ef784b.wav", "converted_path": "uploads/processed/converted_12a1b35871580a987e3ed5c049ef784b.mp3", "normalized_path": "uploads/processed/normalized_12a1b35871580a987e3ed5c049ef784b.wav"}
(1 row)
*/

UPDATE music_jobs
SET status = 'done', progress = 100, -- change status to done
result = result || jsonb_build_object(
    'waveform_path', 'uploads/processed/waveform_' || md5(payload->>'title') || '.json'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

/*
SELECT  payload->>'title' AS title, status, progress, result
FROM music_jobs WHERE id = (SELECT id FROM music_jobs ORDER BY created_at LIMIT 1);

 title  | status | progress |                                                                                                                                                                        result                                                                                                                                                                         
--------+--------+----------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Hiruga | done   |      100 | {"trimmed_path": "uploads/processed/trimmed_12a1b35871580a987e3ed5c049ef784b.wav", "waveform_path": "uploads/processed/waveform_12a1b35871580a987e3ed5c049ef784b.json", "converted_path": "uploads/processed/converted_12a1b35871580a987e3ed5c049ef784b.mp3", "normalized_path": "uploads/processed/normalized_12a1b35871580a987e3ed5c049ef784b.wav"}
(1 row)
*/

-- Simulating failure for the third oldest job (OFFSET 2)
UPDATE music_jobs
SET status = 'failed', progress = 0
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 2 LIMIT 1);

/*
SELECT  payload->>'title' AS title, status, progress, result
FROM music_jobs WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 2 LIMIT 1);

      title      | status | progress | result 
-----------------+--------+----------+--------
 Buruboun Garada | failed |        0 | {}
(1 row)
*/

-- VERIFICATION QUERIES --

/* 1. What does the client see when polling a completed job?
HTTP/2 200 
date: Sat, 09 May 2026 17:22:58 GMT
content-type: application/json
content-length: 439
{
    "status": "done",
    "progress": 100,
    "result": {
        "trimmed_path": "uploads/processed/trimmed_12a1b35871580a987e3ed5c049ef784b.wav",
        "waveform_path": "uploads/processed/waveform_12a1b35871580a987e3ed5c049ef784b.json",
        "converted_path": "uploads/processed/converted_12a1b35871580a987e3ed5c049ef784b.mp3",
        "normalized_path": "uploads/processed/normalized_12a1b35871580a987e3ed5c049ef784b.wav"
    }
}

Note that, in this case, the result property includes other properties with paths.
*/

-- Update second oldest job for Query 2 (OFFSET 1)
UPDATE music_jobs
SET status = 'processing', progress = 25,
result = result || jsonb_build_object(
    'normalized_path', 'uploads/processed/normalized_' || md5(payload->>'title') || '.mp3'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* 2. What does the client see mid-processing (partial result)?
HTTP/2 200 
date: Sat, 09 May 2026 17:25:58 GMT
content-type: application/json
content-length: 439
{
    "status": "processing",
    "progress": 25,
    "result": {
        "normalized_path": "uploads/processed/normalized_0f5de708d2f6808ffb0c3893b2b8964a.mp3"
    }
}

Note that in this case, it is assumed that each stage is an independent component 
of the result that the client can already access, despite the overall status 
being processing.
*/

/* 3. How do you find all failed jobs?
SELECT id, payload->>'title' AS title, status, progress FROM music_jobs WHERE status = 'failed';

                  id                  |      title      | status | progress 
--------------------------------------+-----------------+--------+----------
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | Buruboun Garada | failed |        0
(1 row)
*/

/* 4. Show the full result object for a completed job
SELECT id, payload->>'title' AS title, status, progress, result FROM music_jobs
WHERE status = 'done' LIMIT 1;

                  id                  | title  | status | progress |                                                                                                                                                                        result                                                                                                                                                                         
--------------------------------------+--------+--------+----------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 019e0a23-050b-7cd0-9091-c81ce85f694c | Hiruga | done   |      100 | {"trimmed_path": "uploads/processed/trimmed_12a1b35871580a987e3ed5c049ef784b.wav", "waveform_path": "uploads/processed/waveform_12a1b35871580a987e3ed5c049ef784b.json", "converted_path": "uploads/processed/converted_12a1b35871580a987e3ed5c049ef784b.mp3", "normalized_path": "uploads/processed/normalized_12a1b35871580a987e3ed5c049ef784b.wav"}
(1 row)
*/

/* ====================================================================================
STEP 5 - updated_at
==================================================================================== */

ALTER TABLE music_jobs
    ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- QUESTIONS/ANSWERS --

/* 1. Why is created_at not enough?
If one wanted to calculate how long a job took from when it began processing until it 
was done, a field in addition to created_at is needed. This is the reason for adding an 
updated_at field. It is also useful for knowing whether a worker might have crashed. The 
created_at field only tells when the job was submitted.
*/

/* 2. What goes wrong if application code maintains updated_at?
If the application code maintains the updated_at field, then there is a possibility that 
it may forget to set it when making an UPDATE to a record. The record is then left in an 
inconsistent state, which may lead to bugs.
*/

/* 3. Write a query that would power an SSE health check endpoint.
SELECT status, progress, updated_at FROM music_jobs WHERE public_id = $1 AND updated_at > $2

Given the public_id of a job and a time value of the last updated_at value as parameters, 
this query run by the server can detect when a job has been updated and then notify the 
client of the event (SSE). 
*/

-- SAMPLE DATA --
-- Using the second oldest job (OFFSET 1).

/* Before UPDATE
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1;

                  id                  | title |   status   | progress |          updated_at           
--------------------------------------+-------+------------+----------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | processing |       25 | 2026-05-09 12:32:40.777033-06
(1 row)
*/

UPDATE music_jobs
SET progress = 50,
result = result || jsonb_build_object(
    'trimmed_path', 'uploads/processed/trimmed_' || md5(payload->>'title') || '.mp3'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* After UPDATE with stale data
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1;

                  id                  | title |   status   | progress |          updated_at           
--------------------------------------+-------+------------+----------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | processing |       50 | 2026-05-09 12:32:40.777033-06
(1 row)

Note that the updated_at field matches the previous UPDATE.
*/

UPDATE music_jobs
SET progress = 75, updated_at = now(), -- updated_at being changed to now()
result = result || jsonb_build_object(
    'converted_path', 'uploads/processed/converted_' || md5(payload->>'title') || '.mp3'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* After UPDATE with correct updated_at
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1;

                  id                  | title |   status   | progress |          updated_at           
--------------------------------------+-------+------------+----------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | processing |       75 | 2026-05-09 12:41:23.118813-06
(1 row)

Note how the updated_at field has now been changed to reflect when progress was last updated.
*/

/*
Updating the updated_at field in this manner is fragile because we, as programmers, may forget 
to maintain the field in the application code with our constructed queries.
*/

-- VERIFICATION QUERIES --

/* 1. Find jobs that changed in the last 60 seconds.
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs WHERE updated_at > now() - INTERVAL '60 seconds' ORDER BY updated_at DESC;

                  id                  |      title      |   status   | progress |          updated_at           
--------------------------------------+-----------------+------------+----------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami           | processing |       75 | 2026-05-09 12:46:56.117368-06
 019e0a23-0ce8-79e0-a6dd-04d71902f005 | Buruboun Garada | failed     |        0 | 2026-05-09 12:46:45.70571-06
(2 rows)

Note that some previous queries were rerun with updated_at set to a different value.
*/

/* 2. Find jobs stuck in processing for more than 5 minutes.
SELECT id, payload->>'title' AS title, status, progress, created_at, updated_at
FROM music_jobs WHERE status = 'processing' AND updated_at < now() - INTERVAL '5 minutes';

                  id                  | title |   status   | progress |          created_at          |          updated_at           
--------------------------------------+-------+------------+----------+------------------------------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | processing |       75 | 2026-05-08 18:28:48.76592-06 | 2026-05-09 12:46:56.117368-06
(1 row)

Note that at least 5 minutes had passed when recording the results of this query.
*/

/* 3. How long did each completed job take?
SELECT id, payload->>'title' AS title, status, progress, updated_at - created_at AS processing_time
FROM music_jobs WHERE status = 'done';

                  id                  | title  | status | progress | processing_time 
--------------------------------------+--------+--------+----------+-----------------
 019e0a23-050b-7cd0-9091-c81ce85f694c | Hiruga | done   |      100 | 18:03:53.029848
(1 row)

Note that the long processing time is due to the record being created a day before, 
while the table was being incrementally worked on. Typical values should be in the 
range of seconds or minutes.
*/

/* ====================================================================================
STEP 6 - Trigger on updated_at
==================================================================================== */

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER music_jobs_updated_at
    BEFORE UPDATE ON music_jobs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- QUESTIONS/ANSWERS --

/* 1. Why BEFORE UPDATE and not AFTER UPDATE?
Because the music_jobs_updated_at trigger needs to modify the updated_at record before 
the record is saved to the database, BEFORE UPDATE is more appropriate. Using AFTER 
UPDATE would not correctly update the record, and we would then require another UPDATE.
*/

/* 2. What is NEW and what is OLD in a trigger function?
NEW and OLD are special row variables that are available in triggers.
NEW represents the new version of the row in INSERT and UPDATE triggers. 
OLD represents the previous row version in UPDATE and DELETE triggers.
*/

/* 3. Why does returning NEW matter?
It matters because PostgreSQL expects a row to be returned in INSERT and UPDATE triggers 
so that it can save it to the database in those operations. NEW is typically the 
correct row to return, as opposed to OLD or NULL.
*/

/* 4. Why is the function reusable across tables?
The set_updated_at() function is independent of the created trigger, the latter being 
associated with a particular table. If there was another table, as long as it had an 
updated_at field, the function could be reused for that table in another trigger.
*/

-- SAMPLE DATA --
-- Using the second oldest job (OFFSET 1).

/* Before UPDATE
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1;

                  id                  | title |   status   | progress |          updated_at           
--------------------------------------+-------+------------+----------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | processing |       75 | 2026-05-09 12:46:56.117368-06
(1 row)
*/

UPDATE music_jobs
SET status = 'done', progress = 100, -- updated_at not being changed here
result = result || jsonb_build_object(
    'waveform_path', 'uploads/processed/waveform_' || md5(payload->>'title') || '.json'
)
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* After UPDATE
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1;

                  id                  | title | status | progress |          updated_at           
--------------------------------------+-------+--------+----------+-------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | done   |      100 | 2026-05-09 13:36:47.674315-06
(1 row)

Note how updated_at was changed without being specified in the UPDATE statement. This is due 
to the trigger.
*/

UPDATE music_jobs
SET updated_at = '2000-01-01' -- attempt to sabotage
WHERE id = (SELECT id FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1);

/* After UPDATE sabotage attempt
SELECT id, payload->>'title' AS title, status, progress, updated_at
FROM music_jobs ORDER BY created_at OFFSET 1 LIMIT 1;

                  id                  | title | status | progress |          updated_at          
--------------------------------------+-------+--------+----------+------------------------------
 019e0a23-08fe-733c-b146-c2b411010a5c | Miami | done   |      100 | 2026-05-09 13:39:16.46505-06
(1 row)

Note that updated_at did not become 2000-01-01. It is still set to now() per the trigger. 
No other fields for this record were changed, as this was just for demonstrating the trigger.
*/

/* Trigger existence verification
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers WHERE event_object_table = 'music_jobs';

     trigger_name      | event_manipulation | action_timing |         action_statement          
-----------------------+--------------------+---------------+-----------------------------------
 music_jobs_updated_at | UPDATE             | BEFORE        | EXECUTE FUNCTION set_updated_at()
(1 row)
*/

-- VERIFICATION QUERIES --

/* 1. Show trigger details from information_schema.triggers.
SELECT trigger_name, event_object_table, event_manipulation, action_timing, action_statement
FROM information_schema.triggers WHERE event_object_table = 'music_jobs';

     trigger_name      | event_object_table | event_manipulation | action_timing |         action_statement          
-----------------------+--------------------+--------------------+---------------+-----------------------------------
 music_jobs_updated_at | music_jobs         | UPDATE             | BEFORE        | EXECUTE FUNCTION set_updated_at()
(1 row)

Note that this is practically the same query as for verifying trigger existence.
*/

/* 2. Show function details from information_schema.routines
SELECT routine_name, routine_type, data_type
FROM information_schema.routines WHERE routine_name = 'set_updated_at';

  routine_name  | routine_type | data_type 
----------------+--------------+-----------
 set_updated_at | FUNCTION     | trigger
(1 row)
*/

/* ====================================================================================
STEP 7 - Indexes + EXPLAIN ANALYZE
==================================================================================== */

-- PART A: Generated Rows (adapted from Quiz 6) --

INSERT INTO music_jobs (status, progress, payload, result, error_msg)
SELECT
    -- job status
    s.status,

    -- set progress value based on status
    CASE s.status
        WHEN 'pending'    THEN 0
        WHEN 'processing' THEN (random() * 99)::INTEGER
        WHEN 'done'       THEN 100
        WHEN 'failed'     THEN (random() * 99)::INTEGER
    END AS progress,

    -- simulated input payload
    jsonb_build_object(
        'original_filename', 'music_file_' || i || CASE WHEN s.is_mp3 THEN '.mp3' ELSE '.wav' END,
        'stored_path', 'uploads/' || md5(i::text) || CASE WHEN s.is_mp3 THEN '.mp3' ELSE '.wav' END,
        'mime_type', CASE WHEN s.is_mp3 THEN 'audio/mpeg' ELSE 'audio/wav' END,
        'duration_s', (30 + random() * 600)::INTEGER, -- 30s to 10min
        'file_size',
        CASE
            WHEN s.is_mp3 THEN (random() * 8000000 + 500000)::INTEGER -- 0.5 – 8.5 MB for MP3
            ELSE (random() * 60000000 + 5000000)::INTEGER -- 5 – 65 MB for WAV
        END
    ) AS payload,

    -- simulated result only for completed jobs
    CASE s.status
        WHEN 'done' THEN jsonb_build_object(
            'normalized_path', 'uploads/processed/normalized_' || md5(i::text) || CASE WHEN s.is_mp3 THEN '.mp3' ELSE '.wav' END,
            'trimmed_path', 'uploads/processed/trimmed_' || md5(i::text) || CASE WHEN s.is_mp3 THEN '.mp3' ELSE '.wav' END,
            'converted_path', 'uploads/processed/converted_' || md5(i::text) || '.mp3', -- always MP3
            'waveform_path', 'uploads/processed/waveform_' || md5(i::text) || '.json'
        )
        ELSE '{}'::JSONB
    END AS result,

    -- error message only for failed jobs
    CASE s.status
        WHEN 'failed' THEN
            'MusicProcessingError: stage ' || (random() * 4)::INTEGER
        ELSE NULL
    END AS error_msg

-- number of records to generate
FROM generate_series(1, 50000) AS i

-- subquery which uses i to compute status for each row
CROSS JOIN LATERAL (
    SELECT 
        -- using modulo to force 25% per status
        (ARRAY['pending', 'processing', 'done', 'failed'])[((i - 1) % 4) + 1] AS status,
        -- using modulo so that 80% will be MP3, and 20% will be WAV (every 5 rows, 4 are true, and 1 is false)
        (i % 5) < 4 AS is_mp3
) AS s;

-- PART B: EXPLAIN ANALYZE Before Indexes --

/* QUERY 1: Worker Poll
EXPLAIN ANALYZE
SELECT id, payload FROM music_jobs WHERE status = 'pending' ORDER BY created_at LIMIT 1;

                                                           QUERY PLAN                                                            
---------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=3188.14..3188.14 rows=1 width=219) (actual time=26.883..26.885 rows=1.00 loops=1)
   Buffers: shared hit=2501
   ->  Sort  (cost=3188.14..3219.19 rows=12421 width=219) (actual time=26.881..26.882 rows=1.00 loops=1)
         Sort Key: created_at
         Sort Method: top-N heapsort  Memory: 25kB
         Buffers: shared hit=2501
         ->  Seq Scan on music_jobs  (cost=0.00..3126.04 rows=12421 width=219) (actual time=0.027..22.928 rows=12500.00 loops=1)
               Filter: (status = 'pending'::text)
               Rows Removed by Filter: 37503
               Buffers: shared hit=2501
 Planning Time: 0.206 ms
 Execution Time: 26.923 ms
(12 rows)
*/

/* QUERY 2: Client Poll
EXPLAIN ANALYZE
SELECT id, status, progress, result, error_msg FROM music_jobs
WHERE public_id = (SELECT public_id FROM music_jobs LIMIT 1);

                                                                QUERY PLAN                                                                
------------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using music_jobs_public_id_key on music_jobs  (cost=0.35..8.37 rows=1 width=147) (actual time=0.105..0.107 rows=1.00 loops=1)
   Index Cond: (public_id = (InitPlan 1).col1)
   Index Searches: 1
   Buffers: shared hit=5
   InitPlan 1
     ->  Limit  (cost=0.00..0.06 rows=1 width=16) (actual time=0.027..0.028 rows=1.00 loops=1)
           Buffers: shared hit=2
           ->  Seq Scan on music_jobs music_jobs_1  (cost=0.00..3001.03 rows=50003 width=16) (actual time=0.026..0.026 rows=1.00 loops=1)
                 Buffers: shared hit=2
 Planning Time: 0.231 ms
 Execution Time: 0.145 ms
(11 rows)
*/

/* QUERY 3: JSONB Containment
EXPLAIN ANALYZE
SELECT id, payload->>'original_filename' FROM music_jobs WHERE payload @> '{"mime_type": "audio/mpeg"}'::JSONB;

                                                     QUERY PLAN                                                     
--------------------------------------------------------------------------------------------------------------------
 Seq Scan on music_jobs  (cost=0.00..3228.32 rows=40912 width=48) (actual time=0.031..32.217 rows=40002.00 loops=1)
   Filter: (payload @> '{"mime_type": "audio/mpeg"}'::jsonb)
   Rows Removed by Filter: 10001
   Buffers: shared hit=2501
 Planning Time: 0.208 ms
 Execution Time: 35.349 ms
(6 rows)
*/

-- PART C: Add Indexes --

CREATE INDEX idx_music_jobs_status_created ON music_jobs (status, created_at); -- PostgreSQL default index is B-Tree
CREATE INDEX idx_music_jobs_payload ON music_jobs USING GIN (payload);
CREATE INDEX idx_music_jobs_result ON music_jobs USING GIN (result);

-- PART D: EXPLAIN ANALYZE After Indexes --

/* QUERY 1: Worker Poll
EXPLAIN ANALYZE
SELECT id, payload FROM music_jobs WHERE status = 'pending' ORDER BY created_at LIMIT 1;

                                                                         QUERY PLAN                                                                         
------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=0.29..1.09 rows=1 width=219) (actual time=0.074..0.075 rows=1.00 loops=1)
   Buffers: shared hit=3
   ->  Index Scan using idx_music_jobs_status_created on music_jobs  (cost=0.29..9949.62 rows=12421 width=219) (actual time=0.071..0.072 rows=1.00 loops=1)
         Index Cond: (status = 'pending'::text)
         Index Searches: 1
         Buffers: shared hit=3
 Planning Time: 0.296 ms
 Execution Time: 0.116 ms
(8 rows)
*/

/* QUERY 2: Client Poll
EXPLAIN ANALYZE
SELECT id, status, progress, result, error_msg
FROM music_jobs WHERE public_id = (SELECT public_id FROM music_jobs LIMIT 1);

                                                                QUERY PLAN                                                                
------------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using music_jobs_public_id_key on music_jobs  (cost=0.35..8.37 rows=1 width=147) (actual time=0.058..0.061 rows=1.00 loops=1)
   Index Cond: (public_id = (InitPlan 1).col1)
   Index Searches: 1
   Buffers: shared hit=5
   InitPlan 1
     ->  Limit  (cost=0.00..0.06 rows=1 width=16) (actual time=0.024..0.025 rows=1.00 loops=1)
           Buffers: shared hit=2
           ->  Seq Scan on music_jobs music_jobs_1  (cost=0.00..3001.03 rows=50003 width=16) (actual time=0.023..0.023 rows=1.00 loops=1)
                 Buffers: shared hit=2
 Planning Time: 0.213 ms
 Execution Time: 0.092 ms
(11 rows)
*/

/* QUERY 3: JSONB Containment
EXPLAIN ANALYZE
SELECT id, payload->>'original_filename' FROM music_jobs WHERE payload @> '{"mime_type": "audio/mpeg"}'::JSONB;

                                                     QUERY PLAN                                                     
--------------------------------------------------------------------------------------------------------------------
 Seq Scan on music_jobs  (cost=0.00..3228.32 rows=40912 width=48) (actual time=0.023..27.608 rows=40002.00 loops=1)
   Filter: (payload @> '{"mime_type": "audio/mpeg"}'::jsonb)
   Rows Removed by Filter: 10001
   Buffers: shared hit=2501
 Planning:
   Buffers: shared hit=1
 Planning Time: 0.212 ms
 Execution Time: 30.940 ms
(8 rows)
*/

-- PART E: Results Explanation --

/*
Before indexes:
Query 1 (Worker Poll) performed a sequential scan without indexes for an execution time of 26.923 ms. 
Query 2 (Client Poll) performed an index scan for an execution time of 0.145 ms.
Query 3 (JSONB Containment) performed a sequential scan without indexes for an execution time of 35.349 ms.

From these results, we can see how Query 2 was significantly faster than the other two queries. This 
was thanks to the B-Tree index that PostgreSQL automatically created on the public_id field from 
its UNIQUE constraint. 

After indexes:
Query 1 (Worker Poll) performed an index scan for an execution time of 0.116 ms.
Query 2 (Client Poll) performed an index scan, as before, with an execution time of 0.092 ms.
Query 3 (JSONB Containment) performed a sequential scan, as before, with an execution time of 30.940 ms.

From these results, we can see how Query 1's execution time improved thanks to the composite 
index that was created on the status and created_at fields. Despite the GIN index being created 
on the payload field, PostgreSQL decided to use a sequential scan for Query 3. In these cases, 
it turns out to be more performant to use a sequential scan since {"mime_type": "audio/mpeg"} 
constitutes 80% of the records in the table. It goes to show how PostgreSQL makes decisions 
on optimizing queries, and that created indexes may not always be used if another option is 
more performant. Query 2 remained the same, using the same existing index on public_id.

Below is the result if Query 3 were to search for {"mime_type": "audio/wav"} instead, 
which constitutes 20% of the records in the table. In this case, a bitmap heap scan is done, 
and the GIN index is used, which improves the execution time.

EXPLAIN ANALYZE
SELECT id, payload->>'original_filename' FROM music_jobs WHERE payload @> '{"mime_type": "audio/wav"}'::JSONB;

                                                                QUERY PLAN                                                                
------------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on music_jobs  (cost=90.17..2727.53 rows=9091 width=48) (actual time=3.937..21.168 rows=10001.00 loops=1)
   Recheck Cond: (payload @> '{"mime_type": "audio/wav"}'::jsonb)
   Heap Blocks: exact=2501
   Buffers: shared hit=2524
   ->  Bitmap Index Scan on idx_music_jobs_payload  (cost=0.00..87.89 rows=9091 width=0) (actual time=3.089..3.090 rows=10001.00 loops=1)
         Index Cond: (payload @> '{"mime_type": "audio/wav"}'::jsonb)
         Index Searches: 1
         Buffers: shared hit=23
 Planning:
   Buffers: shared hit=1
 Planning Time: 0.218 ms
 Execution Time: 21.981 ms
(12 rows)
*/

-- QUESTIONS/ANSWERS --

/* 1. What is a sequential scan and why is it slow at scale?
A sequential scan in PostgreSQL is one in which a table is read row by row from  
start to finish until the matching record is found. It is slow at scale since 
it is O(n), with the time taken to search a record growing linearly with table 
size. A lot of unnecessary data may be read before the matching one is found. 
*/

/* 2. Why does the worker poll query need COMPOSITE index and not just an index on status alone?
A composite index of status alongside created_at is needed since a worker querying 
or polling for a job will almost always filter by both those conditions. For example, 
when a worker wants to take the next oldest pending job, as it should logically do, 
it queries for both the status being 'pending' as well as ordering by created_at in 
ascending order before limiting it to 1 record. Without the composite index counting 
created_at, all pending jobs would then have to be scanned one by one for the oldest 
one, and it may be the case that there are a significant number of pending jobs, which 
would slow down the query.
*/

/* 3. Why GIN and not B-Tree for JSONB columns?
A GIN index is better suited for JSONB columns since JSONB is a type that contains 
many keys and nested values, which are searched for more in a "contains" context. 
These indexes are also better for the array type and full-text search vectors. 
The B-Tree index is better for values that are scalar or orderable, which JSONB 
typically is not.
*/

/* 4. Which operators USE the GIN index? Which do NOT?
Operators that use the GIN index include the containment operation (@>) and 
the key existence operation (?). Operators that do not use the GIN index 
include comparison operators like (>), (<), (BETWEEN), and the text pattern matching 
operation (LIKE).
*/

/* 5. What speedup did you measure? Show the before/after execution time.
Query 1 (Worker Poll): 26.923 ms (BEFORE), 0.116 ms (AFTER - Speedup of approx. 26 ms). 
Query 2 (Client Poll): 0.145 ms (BEFORE), 0.092 ms (AFTER - Average not changed).
Query 3 (JSONB Containment): 35.349 ms (BEFORE), 30.940 ms (AFTER - Average not changed).
*/

-- FINAL VERIFICATION --

/*
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'music_jobs' ORDER BY indexname;
\d music_jobs

           indexname           |                                             indexdef                                             
-------------------------------+--------------------------------------------------------------------------------------------------
 idx_music_jobs_payload        | CREATE INDEX idx_music_jobs_payload ON public.music_jobs USING gin (payload)
 idx_music_jobs_result         | CREATE INDEX idx_music_jobs_result ON public.music_jobs USING gin (result)
 idx_music_jobs_status_created | CREATE INDEX idx_music_jobs_status_created ON public.music_jobs USING btree (status, created_at)
 music_jobs_pkey               | CREATE UNIQUE INDEX music_jobs_pkey ON public.music_jobs USING btree (id)
 music_jobs_public_id_key      | CREATE UNIQUE INDEX music_jobs_public_id_key ON public.music_jobs USING btree (public_id)
(5 rows)

                           Table "public.music_jobs"
   Column   |           Type           | Collation | Nullable |     Default     
------------+--------------------------+-----------+----------+-----------------
 id         | uuid                     |           | not null | uuidv7()
 payload    | jsonb                    |           | not null | 
 created_at | timestamp with time zone |           | not null | now()
 public_id  | uuid                     |           | not null | uuidv4()
 status     | text                     |           | not null | 'pending'::text
 progress   | integer                  |           | not null | 0
 result     | jsonb                    |           | not null | '{}'::jsonb
 error_msg  | text                     |           |          | 
 updated_at | timestamp with time zone |           | not null | now()
Indexes:
    "music_jobs_pkey" PRIMARY KEY, btree (id)
    "idx_music_jobs_payload" gin (payload)
    "idx_music_jobs_result" gin (result)
    "idx_music_jobs_status_created" btree (status, created_at)
    "music_jobs_public_id_key" UNIQUE CONSTRAINT, btree (public_id)
Check constraints:
    "music_jobs_progress_check" CHECK (progress >= 0 AND progress <= 100)
    "music_jobs_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'processing'::text, 'done'::text, 'failed'::text]))
Triggers:
    music_jobs_updated_at BEFORE UPDATE ON music_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at()
*/
