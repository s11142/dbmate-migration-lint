-- migrate:up
ALTER TABLE users ADD COLUMN firstName VARCHAR(255) NOT NULL DEFAULT '';

-- migrate:down
ALTER TABLE users DROP COLUMN firstName;
