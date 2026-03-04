-- migrate:up
RENAME TABLE users TO members;

-- migrate:down
RENAME TABLE members TO users;
