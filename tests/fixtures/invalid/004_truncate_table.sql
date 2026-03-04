-- migrate:up
TRUNCATE TABLE users;

-- migrate:down
-- no rollback possible for truncate
