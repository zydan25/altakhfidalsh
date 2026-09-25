-- Run with:
-- psql -v db_password='...' -U postgres -f init_takhfid1.sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'takhfid1') THEN
        EXECUTE format('CREATE ROLE takhfid1 LOGIN PASSWORD %L', :'db_password');
    ELSE
        EXECUTE format('ALTER ROLE takhfid1 WITH LOGIN PASSWORD %L', :'db_password');
    END IF;
END $$;

SELECT format('CREATE DATABASE takhfid1 OWNER takhfid1')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'takhfid1')\gexec
