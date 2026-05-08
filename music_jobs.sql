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

INSERT INTO music_jobs (payload)
VALUES
(
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
),
(
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
),
(
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
-----------------+------------------------------
 Hiruga          | 2026-05-08 15:00:54.20712-06
 Miami           | 2026-05-08 15:00:54.20712-06
 Buruboun Garada | 2026-05-08 15:00:54.20712-06
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
SELECT id, payload->>'filename' AS job_filename, payload->>'mime_type' AS mime_type
FROM music_jobs
WHERE payload->>'mime_type' = 'audio/mpeg';

                  id                  |    job_filename     | mime_type  
--------------------------------------+---------------------+------------
 019e0964-b044-7439-a140-9dfe8f09e9d2 | miami.mp3           | audio/mpeg
 019e0964-b044-748b-9c43-accc7de06c89 | buruboun-garada.mp3 | audio/mpeg
(2 rows)
*/

/* 4. Find the jobs that has the extra field.
SELECT id, payload->>'filename' AS job_filename
FROM music_jobs
WHERE payload ? 'publisher';

                  id                  |    job_filename     
--------------------------------------+---------------------
 019e0964-b044-748b-9c43-accc7de06c89 | buruboun-garada.mp3
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
 019e0964-b043-71e1-a637-fa9fb4723d5b | 48182626-ea3f-48e7-9235-eec18916d77d
 019e0964-b044-7439-a140-9dfe8f09e9d2 | 0eed9e62-98f5-47aa-8ec9-6ca691969be2
 019e0964-b044-748b-9c43-accc7de06c89 | 4f40c13e-2ad1-4fb6-995e-4c1db3232d9a
(3 rows)

From the results, you can notice how in the id field, which is using uuidv7, the first
part is the exact same, with the second and third parts quite similar. This probably 
corresponds to the timestamp that is embedded. There is no common or similar pattern seen 
in the public_id field.
*/

/* 2. Run uuid_extract_timestamp() on both columns - what does this prove?
SELECT uuid_extract_timestamp(id) AS id_timestamp, uuid_extract_timestamp(public_id) AS public_id_timestamp FROM music_jobs;

        id_timestamp        | public_id_timestamp 
----------------------------+---------------------
 2026-05-08 15:00:54.211-06 | [null]
 2026-05-08 15:00:54.212-06 | [null]
 2026-05-08 15:00:54.212-06 | [null]
(3 rows)

This proves that uuidv7 has a timestamp component and that uuidv4 does not.
*/

/* 3. Show what the Go server would return to the client after insert.
HTTP/2 202 
date: Fri, 08 May 2026 23:35:31 GMT
content-type: application/json
content-length: 56
{
    "job_id": "48182626-ea3f-48e7-9235-eec18916d77d"
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
