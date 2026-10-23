-- Runs once when the docker-compose Postgres starts for the first time.
-- The test suite loads the schema into this database itself.
CREATE DATABASE campushub_test OWNER campushub;
