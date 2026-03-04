-- migrate:up
CREATE INDEX users_email_index ON users (email);

-- migrate:down
DROP INDEX users_email_index ON users;
