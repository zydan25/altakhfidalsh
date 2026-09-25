-- PostgreSQL initialization for takhfid1.
-- Run with:
-- psql -v db_password='...' -U postgres -f init_takhfid1.sql

SELECT format('CREATE ROLE takhfid1 LOGIN PASSWORD %L', :'db_password')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'takhfid1'
)\gexec

SELECT format('ALTER ROLE takhfid1 WITH LOGIN PASSWORD %L', :'db_password')
WHERE EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'takhfid1'
)\gexec

SELECT format('CREATE DATABASE takhfid1 OWNER takhfid1')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'takhfid1'
)\gexec
